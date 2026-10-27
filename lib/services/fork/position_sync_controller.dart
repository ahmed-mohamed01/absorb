import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api_service.dart';
import 'perf_caches.dart';
import 'position_sync_chain.dart';

// Fork-owned: loads, polls and acts on one BookOrbit book's position sync,
// a port of BookOrbit's useSyncChainPanel and the composables it uses
// (useEditionLink, useReadingAlignment, useReadAlong, the Audiobookshelf
// sync link). The sync button and the sheet share one controller per book.
// It has no widgets: what an action ends with goes to [onNotice], which the
// open sheet turns into a toast. See FORK_NOTES.md.

enum PositionSyncNoticeKind { success, error, info }

class PositionSyncNotice {
  final PositionSyncNoticeKind kind;
  final String message;
  const PositionSyncNotice(this.kind, this.message);
}

/// What a read-along build request ended with. Only [started] leaves a job
/// running; the sheet goes back to the chain for all but [failed], which
/// keeps the options open for a retry.
enum ReadAlongBuildOutcome { started, ready, blocked, failed }

class _Entry {
  final PositionSyncController controller;
  int refs = 0;
  Timer? disposeTimer;
  _Entry(this.controller);
}

const _alignmentPoll = Duration(seconds: 3);
// Storyteller runs for minutes to hours, so its status is read far less often.
const _readAlongPoll = Duration(seconds: 5);
// A build starts asynchronously, so the next reads can still show the row
// from before it. This many are held as the optimistic status.
const _maxAwaitBuildRowPolls = 5;
// A build runs for hours; one failed read from a restarting proxy must not
// end the build view.
const _maxReadAlongFailures = 5;
const _searchDebounce = Duration(milliseconds: 250);

bool _alignmentRunning(AlignmentStatus s) => s == AlignmentStatus.pending || s == AlignmentStatus.building;

bool _readAlongInFlight(ReadAlongStatus s) => s == ReadAlongStatus.queued || s == ReadAlongStatus.building;

class PositionSyncController extends ChangeNotifier {
  PositionSyncController._(this.api, this.bookId);

  static final Map<int, _Entry> _registry = {};

  /// The shared controller for [bookId]; every acquire needs a [release].
  /// [api] replaces the one held, since the auth provider hands out a fresh
  /// service on every read.
  static bool _listensForClears = false;

  static PositionSyncController acquire(BookOrbitApiService api, int bookId) {
    if (!_listensForClears) {
      _listensForClears = true;
      ForkCacheClears.listen(disposeIdle);
    }
    final entry = _registry.putIfAbsent(bookId, () => _Entry(PositionSyncController._(api, bookId)));
    final c = entry.controller;
    c.api = api;
    entry.refs++;
    entry.disposeTimer?.cancel();
    entry.disposeTimer = null;
    // A sheet reopened within the grace period shows the state it had, reads
    // the link again behind it and picks its build polling back up.
    if (entry.refs == 1 && c._parked) {
      c._parked = false;
      if (c.loaded) {
        unawaited(c.load());
        if (c.link != null) unawaited(c._fetchBuildStatuses());
      }
    }
    return c;
  }

  /// How long a released controller is kept for the next open of its book.
  /// Settable so tests can run it in milliseconds.
  static Duration releaseGrace = const Duration(seconds: 90);

  /// Parks the controller while no sheet shows it: its polling stops, and it
  /// is disposed after [releaseGrace] unless acquired again.
  static void release(PositionSyncController c) {
    final entry = _registry[c.bookId];
    if (entry == null || !identical(entry.controller, c)) return;
    entry.refs--;
    if (entry.refs > 0) return;
    c._parked = true;
    c._alTimer?.cancel();
    c._alTimer = null;
    c._raTimer?.cancel();
    c._raTimer = null;
    c._searchTimer?.cancel();
    c._searchTimer = null;
    entry.disposeTimer?.cancel();
    entry.disposeTimer = Timer(releaseGrace, () {
      if (!identical(_registry[c.bookId], entry) || entry.refs > 0) return;
      _registry.remove(c.bookId);
      c.dispose();
    });
  }

  /// Drops every parked controller now (sign-out, account switch): the next
  /// open starts from nothing instead of another server's book with this id.
  static void disposeIdle() {
    for (final id in _registry.keys.toList()) {
      final entry = _registry[id]!;
      if (entry.refs > 0) continue;
      entry.disposeTimer?.cancel();
      _registry.remove(id);
      entry.controller.dispose();
    }
  }

  @visibleForTesting
  static bool retainedForTest(int bookId) => _registry.containsKey(bookId);

  @visibleForTesting
  bool get parkedForTest => _parked;

  @visibleForTesting
  bool get pollingForTest => _alTimer != null || _raTimer != null;

  @visibleForTesting
  bool get disposedForTest => _disposed;

  /// Set while no sheet holds the controller: no polling is scheduled.
  bool _parked = false;

  BookOrbitApiService api;
  final int bookId;

  /// Set by the open sheet; notices raised while it is closed are dropped.
  ValueChanged<PositionSyncNotice>? onNotice;

  bool _disposed = false;
  bool _initialStarted = false;
  bool _opened = false;
  String? _title;
  String? _author;

  bool loaded = false;
  bool loading = false;
  String? loadError;
  PositionSyncBookInfo? info;
  PositionSyncPermissions perms = const PositionSyncPermissions();
  EditionLinkForBookWire? forBook;
  EditionLinkCandidateWire? picked;
  bool proposalDismissed = false;
  int _loadReq = 0;
  int? _requestedCounterpartId;
  bool _linkMutating = false;
  bool cancelling = false;

  // Alignment.
  AlignmentStatusWire alignment = const AlignmentStatusWire();
  AlignmentBlock? alignmentBlocked;
  bool alignmentMutating = false;

  /// From a link request until its first build is under way, so the
  /// connector reads Linking for the whole window.
  bool pendingStart = false;
  Timer? _alTimer;
  int _alReq = 0;
  bool _alAwaiting = false;
  int _alAwaitPolls = 0;
  AlignmentStatus _alBaseStatus = AlignmentStatus.none;
  String? _alBaseBuiltAt;
  Future<bool>? _pendingAlBuild;

  // Read-along.
  ReadAlongStatusWire readAlong = const ReadAlongStatusWire();

  /// A read of [readAlong] has come back (or failed) since the pair was
  /// last reset, so a `none` there means none.
  bool readAlongChecked = false;
  bool readAlongMutating = false;
  List<StorytellerExistingMatchWire> existing = const [];
  List<ReadAlongLibraryWire> targetLibraries = const [];
  int? chosenTargetLibraryId;
  bool keepRemoteCopy = false;
  bool keepRemoteCopyTouched = false;
  bool _keepRemoteCopyDefault = false;
  ({int bookId, int counterpartId})? _raCounterpart;
  int? _raLastBookId;
  int? _reloadedForOutputId;
  bool _reloadingMember = false;
  Timer? _raTimer;
  int _raReq = 0;
  int _existingReq = 0;
  bool _raAwaiting = false;
  int _raAwaitPolls = 0;
  int _raFailures = 0;
  ReadAlongStatus _raBaseStatus = ReadAlongStatus.none;
  String? _raBaseBuiltAt;
  Future<ReadAlongBuildOutcome>? _pendingRaBuild;

  // Audiobookshelf.
  bool absConfigured = false;
  AbsSyncLinkWire? absLink;
  AbsSyncLiveWire? absLive;
  bool absChecking = false;

  /// The reconcile direction or action in flight.
  String? absBusy;
  String? absActionError;
  int? _absLoadedFor;
  int _absReq = 0;

  // Change search.
  List<EditionLinkCandidateWire> candidates = const [];
  List<AbsBookStateWire> absCandidates = const [];
  bool searching = false;
  bool hasSearched = false;
  String? searchError;
  Timer? _searchTimer;
  int _searchReq = 0;

  SyncChain? _chain;

  @override
  void dispose() {
    _disposed = true;
    _alTimer?.cancel();
    _raTimer?.cancel();
    _searchTimer?.cancel();
    onNotice = null;
    super.dispose();
  }

  void _notice(PositionSyncNoticeKind kind, String message) => onNotice?.call(PositionSyncNotice(kind, message));

  void _changed() {
    if (_disposed) return;
    _chain = null;
    _healMissingMember();
    if (_opened && absAudioBookId != _absLoadedFor) unawaited(_absLoad(absAudioBookId));
    notifyListeners();
  }

  /// This book's title and author, which the for-book answer does not carry.
  /// Called while building, so it does not notify; the next change shows it.
  void describeThisBook(String? title, String? author) {
    if (title == _title && author == _author) return;
    _title = title;
    _author = author;
    _chain = null;
  }

  // ─── Derived ──────────────────────────────────────────────

  EditionLinkWire? get link => forBook?.link;
  EditionLinkMembersWire? get members => forBook?.members;
  EditionLinkRole? get role => forBook?.role;
  bool get _isReadAlongPage => role == EditionLinkRole.readAlong;

  bool get busy => _linkMutating || alignmentMutating || readAlongMutating || absBusy != null;

  /// A read-along whose pair this reader cannot relink gets no button, nor a
  /// book with both or no editions. Until both answers are in the button
  /// shows its loading look rather than jumping away.
  bool get eligible {
    final i = info;
    if (i == null || !loaded) return true;
    if (forBook?.readAlongOutput == true) return false;
    return i.modality == PositionSyncModality.text || i.modality == PositionSyncModality.audio || _isReadAlongPage;
  }

  SyncEdition get thisBook {
    switch (role) {
      case EditionLinkRole.readAlong:
        return SyncEdition.readAlong;
      case EditionLinkRole.text:
        return SyncEdition.ebook;
      case EditionLinkRole.audio:
        return SyncEdition.audiobook;
      case null:
        return info?.modality == PositionSyncModality.audio ? SyncEdition.audiobook : SyncEdition.ebook;
    }
  }

  /// The server keys alignment and read-along builds to the pair, so a
  /// read-along page acts through the pair's ebook.
  int get pairBookId {
    final m = members;
    return _isReadAlongPage && m != null ? (m.text?.id ?? m.audio.id) : bookId;
  }

  /// A read-along detached from its pair stays matched to the pair it was
  /// built from, so its page offers to link that pair again.
  bool get _detachedReadAlong => _isReadAlongPage && link == null && members != null;

  EditionLinkCandidateWire? get selected => picked ?? (proposalDismissed ? null : forBook?.proposed);

  EditionMatch? get _matchChip {
    if (picked != null) return const EditionMatch(MatchSource.manual);
    final s = selected;
    if (s == null) return null;
    return s.fromBuild ? const EditionMatch(MatchSource.build) : EditionMatch(MatchSource.auto, s.score);
  }

  /// [progressKnown] is false for a member built from a summary that carries
  /// no progress, so its missing progress stays unknown.
  SyncChainSide _memberSide(EditionLinkMemberWire member, bool linked, {bool progressKnown = true}) => SyncChainSide(
        book: SyncChainBook(
          id: member.id,
          title: member.title,
          authorName: member.authorName,
          coverVersion: member.coverVersion,
          // A linked member with no progress record has not been started.
          progress: linked && progressKnown ? (member.progressPercentage ?? 0) : member.progressPercentage,
        ),
        isMember: linked,
        isThisBook: member.id == bookId,
        match: linked ? null : const EditionMatch(MatchSource.pair),
      );

  SyncChainBook get _currentBook =>
      SyncChainBook(id: bookId, title: _title, authorName: _author, progress: forBook?.thisBookProgress);

  // The answer's own member knows the position first-hand; a pick is
  // described by the server's pickedProgress.
  int? _candidateProgress(EditionLinkCandidateWire c) {
    final m = members;
    final member = m == null ? null : [m.text, m.audio].firstWhere((e) => e?.id == c.bookId, orElse: () => null);
    if (member != null) return member.progressPercentage;
    if (c.progress != null) return c.progress;
    return picked?.bookId == c.bookId ? forBook?.pickedProgress : null;
  }

  /// [serverOnly] takes the server's proposal over a pick or dismissal made
  /// in the sheet.
  SyncChainSide _candidateSide([bool serverOnly = false]) {
    final c = serverOnly ? forBook?.proposed : selected;
    if (c == null) return SyncChainSide.empty;
    return SyncChainSide(
      book: SyncChainBook(
        id: c.bookId,
        title: c.title,
        authorName: c.authorName,
        coverVersion: c.coverVersion,
        progress: _candidateProgress(c),
      ),
      match: serverOnly
          ? (c.fromBuild ? const EditionMatch(MatchSource.build) : EditionMatch(MatchSource.auto, c.score))
          : _matchChip,
    );
  }

  SyncChainSide _counterpartSide([bool serverOnly = false]) {
    final summary = link != null ? forBook?.counterpart : null;
    if (summary != null) {
      return _memberSide(
          EditionLinkMemberWire(
              id: summary.id, title: summary.title, authorName: summary.authorName, coverVersion: summary.coverVersion),
          true,
          progressKnown: false);
    }
    return _candidateSide(serverOnly);
  }

  /// Ebook first, audiobook second, whichever page the sheet is opened from.
  ({SyncChainSide ebook, SyncChainSide audiobook}) get sides => _sidesFor();

  ({SyncChainSide ebook, SyncChainSide audiobook}) _sidesFor([bool serverOnly = false]) {
    final m = members;
    if (m != null && (link != null || _detachedReadAlong)) {
      final linked = link != null;
      // A link with no ebook yet still proposes one.
      return (
        ebook: m.text != null ? _memberSide(m.text!, linked) : _candidateSide(serverOnly),
        audiobook: _memberSide(m.audio, linked)
      );
    }
    final current = SyncChainSide(book: _currentBook, isMember: link != null, isThisBook: true);
    final counterpart = _counterpartSide(serverOnly);
    return thisBook == SyncEdition.audiobook
        ? (ebook: counterpart, audiobook: current)
        : (ebook: current, audiobook: counterpart);
  }

  SyncChainSide side(SyncEdition e) => e == SyncEdition.audiobook ? sides.audiobook : sides.ebook;

  int? get absAudioBookId => sides.audiobook.book?.id;

  /// Also set on an unlinked ebook page whose candidate audiobook already
  /// carries the read-along, while that audiobook is the one on screen.
  EditionLinkMemberWire? get readAlongMember {
    final m = members;
    if (m == null) return null;
    if (link != null) return m.readAlong;
    return m.audio.id == sides.audiobook.book?.id ? m.readAlong : null;
  }

  int? get _missingReadAlongMemberId {
    final output = readAlong.outputBook;
    if (link == null || readAlong.status != ReadAlongStatus.ready || output == null || members?.readAlong != null) {
      return null;
    }
    return output.id;
  }

  // The server re-attaches a read-along to a relinked pair, so its member is
  // normally there; this is a safety net for a ready output that still lacks
  // one. Reloaded once per output book, so a deliberate detach cannot loop.
  void _healMissingMember() {
    final outputId = _missingReadAlongMemberId;
    if (outputId == null || outputId == _reloadedForOutputId) return;
    _reloadedForOutputId = outputId;
    _reloadingMember = true;
    unawaited(load().whenComplete(() {
      _reloadingMember = false;
      _changed();
    }));
  }

  bool get _alignmentRunningNow => _alignmentRunning(alignment.status) || alignmentMutating;

  SyncChainAlignment get _alignmentSnapshot {
    // Before a pair exists there is nothing to align.
    if (link == null) return SyncChainAlignment(running: pendingStart);
    return SyncChainAlignment(
      status: alignment.status,
      stale: alignment.stale,
      builtAt: alignment.builtAt,
      samplesDone: alignment.samplesDone,
      samplesTotal: alignment.samplesTotal,
      buildBlocked: alignmentBlocked,
      buildError: alignment.error,
      running: pendingStart || _alignmentRunningNow,
    );
  }

  static SyncChainBook? _book(EditionLinkMemberWire? m) => m == null
      ? null
      : SyncChainBook(
          id: m.id, title: m.title, authorName: m.authorName, coverVersion: m.coverVersion, progress: m.progressPercentage);

  SyncChainSnapshot get snapshot => _snapshotFor(sides);

  /// The snapshot as the server has it, for listing the work's editions:
  /// the proposed match stays whatever the sheet has picked or set aside.
  SyncChainSnapshot get availableSnapshot => _snapshotFor(_sidesFor(true));

  SyncChainSnapshot _snapshotFor(({SyncChainSide ebook, SyncChainSide audiobook}) s) {
    final ra = readAlong;
    final issue = info?.readAloudIssue;
    final output = ra.outputBook;
    return SyncChainSnapshot(
      thisBook: thisBook,
      linked: link != null,
      ebook: s.ebook,
      audiobook: s.audiobook,
      alignment: _alignmentSnapshot,
      readAlong: SyncChainReadAlong(
        member: _book(readAlongMember),
        status: ra.status,
        blocked: ra.blocked,
        phase: ra.phase,
        remoteTask: ra.remoteTask,
        remoteProgress: ra.remoteProgress,
        queuePosition: ra.queuePosition,
        outputBook: output == null ? null : SyncChainBook(id: output.id, title: output.title),
        thisBook: _isReadAlongPage ? _currentBook : null,
        error: ra.error,
        mutating: readAlongMutating,
        memberPending: _reloadingMember && _missingReadAlongMemberId != null,
      ),
      // Only known on the audiobook and read-along pages.
      readAloudIssue: thisBook != SyncEdition.ebook && issue != null
          ? ReadAloudIssueView(readAloudIssueMessage(issue.reason,
              narrationFile: issue.narrationFile,
              narrationSeconds: issue.narrationSeconds,
              chapter: issue.chapter,
              chapterSeconds: issue.chapterSeconds))
          : null,
      abs: perms.abs ? SyncChainAbs(configured: absConfigured, link: _absMirror, live: _absLiveMirror, checking: absChecking) : null,
      can: SyncChainPermissions(editLink: perms.editLink, generate: perms.generate, rebuild: perms.rebuild && link != null),
    );
  }

  AbsLink? get _absMirror {
    final l = absLink;
    return l == null
        ? null
        : AbsLink(
            audioBookId: l.audioBookId,
            absLibraryItemId: l.absLibraryItemId,
            title: l.title,
            authorName: l.authorName,
            libraryName: l.libraryName,
            direction: l.direction,
            syncing: l.syncing,
            pausedReason: l.pausedReason,
          );
  }

  AbsLive? get _absLiveMirror {
    final l = absLive;
    return l == null
        ? null
        : AbsLive(
            status: l.status,
            progressPercentage: l.progressPercentage,
            progressFinished: l.progressFinished,
            localPercentage: l.localPercentage,
            divergedReason: l.divergedReason,
          );
  }

  SyncChain get chain => _chain ??= buildSyncChain(snapshot);

  SyncButtonState get buttonState {
    // A failed first load reads as not linked, with no dot.
    if (loaded && forBook == null) return SyncButtonState.notLinked;
    return syncButtonState(loaded: loaded, tone: chain.header.tone);
  }

  String get buttonTooltip => syncButtonTooltip(
        linked: link != null,
        audioModality: info?.modality == PositionSyncModality.audio,
        readAlongStatus: readAlong.status,
        readAlongMutating: readAlongMutating,
        alignmentRunning: _alignmentRunningNow,
        alignmentStatus: alignment.status,
        alignmentStale: alignment.stale,
        membersWithoutText: members != null && members!.text == null,
      );

  /// The building ring's fill: alignment samples, or Storyteller's own
  /// progress while it reports one; null spins.
  double? get buttonProgress {
    if (_alignmentRunningNow || pendingStart) {
      final done = alignment.samplesDone;
      final total = alignment.samplesTotal;
      return done != null && total != null && total > 0 ? (done / total).clamp(0.0, 1.0) : null;
    }
    final stage = readAlong.status == ReadAlongStatus.queued ? 0 : stageIndex(readAlong.phase, readAlong.remoteTask);
    final p = readAlongPercent(stage, readAlong.remoteProgress);
    return p == null ? null : p / 100;
  }

  StorytellerExistingMatchWire? get existingMatch {
    for (final m in existing) {
      if (m.aligned) return m;
    }
    return null;
  }

  String? get targetLibraryName {
    final chosen = chosenTargetLibraryId;
    if (chosen == null) return readAlong.targetLibraryName;
    for (final l in targetLibraries) {
      if (l.id == chosen) return l.name;
    }
    return null;
  }

  /// Leaving from the audiobook dissolves the whole link; leaving from the
  /// ebook keeps the read-along on the audiobook.
  String get unlinkDescription {
    if (readAlongMember == null) return PositionSyncCopy.unlinkDescription;
    return thisBook == SyncEdition.audiobook
        ? PositionSyncCopy.unlinkDescriptionReadAlong
        : PositionSyncCopy.unlinkDescriptionReadAlongStays;
  }

  // ─── Loading ──────────────────────────────────────────────

  /// Read up front so the button reflects the real state before the sheet
  /// is opened. Runs once per controller.
  Future<void> loadInitial() async {
    if (_initialStarted) return;
    _initialStarted = true;
    try {
      final (p, i) = await (api.positionSyncPermissions(), api.positionSyncBookInfo(bookId)).wait;
      perms = p;
      info = i;
    } on ParallelWaitError catch (e) {
      // Keep whichever read worked.
      final (p, i) = e.values as (PositionSyncPermissions?, PositionSyncBookInfo?);
      perms = p ?? perms;
      info = i;
      debugPrint('[PositionSync] book info for $bookId: ${e.errors}');
    } catch (e) {
      debugPrint('[PositionSync] book info for $bookId: $e');
    }
    if (_disposed) return;
    await load();
    if (link != null) unawaited(_fetchBuildStatuses());
  }

  // Without a link the server checks the audiobook it is told about, so a
  // read-along that audiobook holds belongs to the pair on screen.
  int? get _forBookCounterpartId => link == null && thisBook == SyncEdition.ebook ? selected?.bookId : null;

  Future<void> load() async {
    final req = ++_loadReq;
    final counterpartId = _forBookCounterpartId;
    _requestedCounterpartId = counterpartId;
    loading = true;
    _changed();
    try {
      final r = await api.editionLinkForBook(bookId, counterpartId: counterpartId);
      if (_disposed || req != _loadReq) return;
      forBook = r;
      loadError = null;
    } catch (e) {
      if (_disposed || req != _loadReq) return;
      debugPrint('[PositionSync] for-book $bookId: $e');
      loadError = PositionSyncCopy.loadFailed;
    } finally {
      if (!_disposed && req == _loadReq) {
        loaded = true;
        loading = false;
        _changed();
      }
    }
  }

  Future<void> _fetchBuildStatuses() async {
    if (link == null) return;
    await Future.wait([_alFetch(pairBookId), _raFetch(pairBookId, forget: true)]);
  }

  // A build of an unlinked pair is only reachable through its pick, so a
  // reopen during it, after it failed, or after it finished unattached keeps
  // that pair rather than the proposal.
  bool get _keepsPick =>
      _readAlongInFlight(readAlong.status) ||
      readAlong.status == ReadAlongStatus.failed ||
      (readAlong.status == ReadAlongStatus.ready && readAlong.outputBook != null && readAlongMember == null);

  /// The sheet opened: start over on the choices made in it and read
  /// everything it shows.
  Future<void> open() async {
    if (!_keepsPick) {
      picked = null;
      proposalDismissed = false;
    }
    chosenTargetLibraryId = null;
    keepRemoteCopyTouched = false;
    keepRemoteCopy = _keepRemoteCopyDefault;
    absActionError = null;
    resetSearch();
    if (!_initialStarted) await loadInitial();
    // Read again on every open: one failed /auth/me would otherwise leave the
    // sheet read-only until the detail sheet closes. The service keeps the
    // answer once it has one.
    try {
      perms = await api.positionSyncPermissions();
      info ??= await api.positionSyncBookInfo(bookId);
    } catch (e) {
      debugPrint('[PositionSync] book info for $bookId: $e');
    }
    if (_disposed) return;
    _opened = true;
    final configured = _absLoadConfigured();
    await load();
    if (_disposed) return;
    if (link != null) {
      unawaited(_fetchBuildStatuses());
      if (perms.generate && readAlongMember == null) {
        unawaited(fetchExisting());
        unawaited(loadTargetLibraries());
      }
    } else if (perms.generate || selected != null) {
      // Read on an unlinked book too: the chain has to know whether
      // Storyteller is usable, and whether the matched pair already has a
      // read-along that the link would bring back.
      final cp = selected?.bookId;
      unawaited(_raFetch(pairBookId, counterpartId: cp, forget: cp == null));
      if (perms.generate) unawaited(loadTargetLibraries());
    }
    await _absLoad(absAudioBookId);
    await configured;
  }

  // ─── Alignment ────────────────────────────────────────────

  void _alSchedule(int bookId) {
    _alTimer?.cancel();
    _alTimer = null;
    if (_parked || !_alignmentRunning(alignment.status)) return;
    _alTimer = Timer(_alignmentPoll, () {
      _alTimer = null;
      unawaited(_alFetch(bookId));
    });
  }

  bool _alKeepAwaiting() {
    if (!_alAwaiting) return false;
    _alAwaitPolls++;
    if (_alAwaitPolls < _maxAwaitBuildRowPolls) return true;
    _alAwaiting = false;
    _alAwaitPolls = 0;
    alignment = const AlignmentStatusWire();
    return false;
  }

  // While awaiting a build: none means the row isn't created yet; a terminal
  // read is stale only if it matches the snapshot the build began from.
  bool _alStaleRead(AlignmentStatus next, String? builtAt) {
    if (!_alAwaiting || next == AlignmentStatus.building) return false;
    if (next == AlignmentStatus.none) return true;
    return next == _alBaseStatus && builtAt == _alBaseBuiltAt;
  }

  Future<void> _alFetch(int bookId) async {
    final req = ++_alReq;
    try {
      final r = await api.alignmentStatus(bookId);
      if (_disposed || req != _alReq) return;
      if (_alStaleRead(r.status, r.builtAt) && _alKeepAwaiting()) return;
      _alAwaiting = false;
      _alAwaitPolls = 0;
      alignment = r;
    } catch (e) {
      if (_disposed || req != _alReq) return;
      if (!_alKeepAwaiting()) alignment = const AlignmentStatusWire();
    } finally {
      // Only the latest read drives polling, and never after disposal.
      if (!_disposed && req == _alReq) {
        _alSchedule(bookId);
        _changed();
      }
    }
  }

  /// False when the request itself failed; a refusal sets
  /// [alignmentBlocked] instead.
  Future<bool> _alBuild(int bookId, {bool force = false}) {
    final f = _alRequestBuild(bookId, force);
    _pendingAlBuild = f;
    f.whenComplete(() {
      if (identical(_pendingAlBuild, f)) _pendingAlBuild = null;
    });
    return f;
  }

  Future<bool> _alRequestBuild(int bookId, bool force) async {
    alignmentMutating = true;
    alignmentBlocked = null;
    final baseStatus = alignment.status;
    final baseBuiltAt = alignment.builtAt;
    _changed();
    try {
      final r = await api.buildAlignment(bookId, force: force);
      if (_disposed) return true;
      if (r.blocked != null) {
        alignmentBlocked = r.blocked;
        return true;
      }
      // The row is created asynchronously, so the next read can still say none.
      alignment = AlignmentStatusWire(
        status: AlignmentStatus.building,
        samplesDone: alignment.samplesDone,
        samplesTotal: alignment.samplesTotal,
        builtAt: alignment.builtAt,
      );
      _alAwaiting = true;
      _alAwaitPolls = 0;
      _alBaseStatus = baseStatus;
      _alBaseBuiltAt = baseBuiltAt;
      await _alFetch(bookId);
      return true;
    } catch (e) {
      debugPrint('[PositionSync] alignment build for $bookId: $e');
      if (!_disposed) await _alFetch(bookId);
      return false;
    } finally {
      alignmentMutating = false;
      _changed();
    }
  }

  Future<bool> _alCancel(int bookId) async {
    alignmentMutating = true;
    _changed();
    try {
      // A cancel sent before the build lands finds nothing to stop.
      final pending = _pendingAlBuild;
      if (pending != null) {
        await pending;
        alignmentMutating = true;
      }
      await api.cancelAlignment(bookId);
      // A cancelled build never gets its row.
      _alAwaiting = false;
      _alAwaitPolls = 0;
      await _alFetch(bookId);
      return true;
    } catch (e) {
      debugPrint('[PositionSync] alignment cancel for $bookId: $e');
      return false;
    } finally {
      alignmentMutating = false;
      _changed();
    }
  }

  Future<void> buildAlignmentAction({bool force = false}) async {
    if (!await _alBuild(pairBookId, force: force)) {
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastAlignBuildFailed);
    }
  }

  Future<void> cancelAlignmentAction() async {
    cancelling = true;
    _changed();
    try {
      if (!await _alCancel(pairBookId)) {
        _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastSyncCancelKeptRunning);
      }
    } finally {
      cancelling = false;
      _changed();
    }
  }

  // ─── Read-along ───────────────────────────────────────────

  void _raSchedule(int bookId) {
    _raTimer?.cancel();
    _raTimer = null;
    if (_disposed || _parked || !_readAlongInFlight(readAlong.status)) return;
    _raTimer = Timer(_readAlongPoll, () {
      _raTimer = null;
      unawaited(_raFetch(bookId));
    });
  }

  // A running build is only found through the counterpart it started with,
  // so a read naming another one would lose it.
  void _rememberCounterpart(int bookId, int? counterpartId) {
    final cp = _raCounterpart;
    final running = cp?.bookId == bookId && _readAlongInFlight(readAlong.status);
    if (running && counterpartId != null && counterpartId != cp?.counterpartId) return;
    _raCounterpart = counterpartId == null ? null : (bookId: bookId, counterpartId: counterpartId);
  }

  int? _counterpartOf(int bookId) => _raCounterpart?.bookId == bookId ? _raCounterpart?.counterpartId : null;

  int? get readAlongCounterpart => _counterpartOf(pairBookId);

  ReadAlongStatusWire _raWith(ReadAlongStatus status, {ReadAlongBlock? blocked}) {
    final r = readAlong;
    return ReadAlongStatusWire(
      status: status,
      blocked: blocked,
      phase: r.phase,
      remoteTask: r.remoteTask,
      remoteProgress: r.remoteProgress,
      outputBook: r.outputBook,
      targetLibraryId: r.targetLibraryId,
      targetLibraryName: r.targetLibraryName,
      epubBytes: r.epubBytes,
      audioBytes: r.audioBytes,
      readAlongBytes: r.readAlongBytes,
      keepRemoteCopyByDefault: r.keepRemoteCopyByDefault,
      remoteCopyReclaimable: r.remoteCopyReclaimable,
      startedAt: r.startedAt,
      builtAt: r.builtAt,
    );
  }

  /// Nothing known about a build any more; the destination and copy facts
  /// stay.
  void _raUnknown() {
    final r = readAlong;
    readAlong = ReadAlongStatusWire(
      targetLibraryId: r.targetLibraryId,
      targetLibraryName: r.targetLibraryName,
      epubBytes: r.epubBytes,
      audioBytes: r.audioBytes,
      readAlongBytes: r.readAlongBytes,
      keepRemoteCopyByDefault: r.keepRemoteCopyByDefault,
      remoteCopyReclaimable: r.remoteCopyReclaimable,
    );
  }

  void _raGiveUp() {
    _raAwaiting = false;
    _raAwaitPolls = 0;
    _raFailures = 0;
    _raUnknown();
  }

  bool _raKeepAwaiting() {
    if (!_raAwaiting) return false;
    _raAwaitPolls++;
    if (_raAwaitPolls < _maxAwaitBuildRowPolls) return true;
    _raGiveUp();
    return false;
  }

  bool _raStaleRead(ReadAlongStatus next, String? builtAt) {
    if (!_raAwaiting || _readAlongInFlight(next)) return false;
    if (next == ReadAlongStatus.none) return true;
    return next == _raBaseStatus && builtAt == _raBaseBuiltAt;
  }

  void _raApply(ReadAlongStatusWire r) {
    final previous = readAlong.status;
    readAlong = r;
    _keepRemoteCopyDefault = r.keepRemoteCopyByDefault;
    if (!keepRemoteCopyTouched) keepRemoteCopy = r.keepRemoteCopyByDefault;
    // A finished build adds the read-along member, which only the for-book
    // answer knows about.
    if (r.status == ReadAlongStatus.ready && _readAlongInFlight(previous)) unawaited(load());
  }

  /// [counterpartId] names the edition an unlinked book is matched with and
  /// is remembered; [forget] drops it (the pair is linked); neither reuses
  /// the remembered one.
  Future<void> _raFetch(int bookId, {int? counterpartId, bool forget = false}) async {
    if (_raLastBookId != bookId) {
      _raLastBookId = bookId;
      keepRemoteCopyTouched = false;
    }
    if (forget || counterpartId != null) _rememberCounterpart(bookId, forget ? null : counterpartId);
    final req = ++_raReq;
    try {
      final r = await api.readAlongStatus(bookId, counterpartId: _counterpartOf(bookId));
      if (_disposed || req != _raReq) return;
      _raFailures = 0;
      if (_raStaleRead(r.status, r.builtAt) && _raKeepAwaiting()) return;
      _raAwaiting = false;
      _raAwaitPolls = 0;
      _raApply(r);
    } catch (e) {
      if (_disposed || req != _raReq) return;
      // A visible build survives a few failed reads in a row.
      _raFailures++;
      if (readAlong.status == ReadAlongStatus.none || _raFailures >= _maxReadAlongFailures) _raGiveUp();
    } finally {
      if (!_disposed && req == _raReq) {
        readAlongChecked = true;
        _raSchedule(bookId);
        _changed();
      }
    }
  }

  /// Forgets everything read for a pair that no longer exists, including
  /// reads still in flight.
  void _raReset() {
    _raTimer?.cancel();
    _raTimer = null;
    _raReq++;
    _existingReq++;
    _raAwaiting = false;
    _raAwaitPolls = 0;
    _raFailures = 0;
    _raCounterpart = null;
    readAlong = const ReadAlongStatusWire();
    readAlongChecked = false;
    existing = const [];
  }

  void setKeepRemoteCopy(bool value) {
    keepRemoteCopyTouched = true;
    keepRemoteCopy = value;
    _changed();
  }

  void setTargetLibrary(int? id) {
    chosenTargetLibraryId = id;
    _changed();
  }

  Future<void> fetchExisting([int? pairId]) async {
    final id = pairId ?? pairBookId;
    final req = ++_existingReq;
    final matches = await api.readAlongExisting(id, counterpartId: _counterpartOf(id));
    if (_disposed || req != _existingReq) return;
    existing = matches;
    _changed();
  }

  Future<void> loadTargetLibraries() async {
    try {
      final libs = await api.readAlongTargetLibraries();
      if (_disposed) return;
      targetLibraries = libs;
      _changed();
    } catch (e) {
      debugPrint('[PositionSync] read-along libraries: $e');
    }
  }

  /// Starts (or imports, with [useExistingUuid]) a read-along for the pair
  /// on screen. A failed build resumes from its last phase, so only a
  /// deliberate rebuild passes [force].
  Future<ReadAlongBuildOutcome> generate({String? useExistingUuid, bool force = false}) async {
    final pairId = pairBookId;
    final counterpartId = link == null ? selected?.bookId : null;
    _rememberCounterpart(pairId, counterpartId);
    final f = _raRequestBuild(pairId,
        force: force,
        counterpartId: counterpartId,
        targetLibraryId: chosenTargetLibraryId,
        useExistingUuid: useExistingUuid,
        // Sent only once the user chose, so an untouched build follows the
        // server's setting.
        cleanUpRemote: keepRemoteCopyTouched ? !keepRemoteCopy : null);
    _pendingRaBuild = f;
    f.whenComplete(() {
      if (identical(_pendingRaBuild, f)) _pendingRaBuild = null;
    });
    final outcome = await f;
    if (outcome == ReadAlongBuildOutcome.failed) {
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastReadAlongBuildFailed);
    } else if (outcome == ReadAlongBuildOutcome.ready) {
      _notice(PositionSyncNoticeKind.info, PositionSyncCopy.toastReadAlongAlreadyReady);
    }
    return outcome;
  }

  Future<ReadAlongBuildOutcome> _raRequestBuild(int bookId,
      {required bool force, int? counterpartId, int? targetLibraryId, String? useExistingUuid, bool? cleanUpRemote}) async {
    readAlongMutating = true;
    readAlong = _raWith(readAlong.status);
    final baseStatus = readAlong.status;
    final baseBuiltAt = readAlong.builtAt;
    _changed();
    try {
      final r = await api.buildReadAlong(bookId,
          force: force,
          counterpartId: counterpartId,
          targetLibraryId: targetLibraryId,
          useExistingUuid: useExistingUuid,
          cleanUpRemote: cleanUpRemote);
      if (_disposed) return ReadAlongBuildOutcome.failed;
      if (r.blocked != null) {
        readAlong = _raWith(r.status, blocked: r.blocked);
        // A refusal can still hand back a build someone else started.
        _raSchedule(bookId);
        return ReadAlongBuildOutcome.blocked;
      }
      // An unforced build of a pair that already has a read-along answers
      // ready without building.
      if (!_readAlongInFlight(r.status)) {
        readAlong = _raWith(r.status);
        await _raFetch(bookId);
        return readAlong.status == ReadAlongStatus.ready ? ReadAlongBuildOutcome.ready : ReadAlongBuildOutcome.blocked;
      }
      readAlong = _raWith(r.status);
      _raAwaiting = true;
      _raAwaitPolls = 0;
      _raBaseStatus = baseStatus;
      _raBaseBuiltAt = baseBuiltAt;
      await _raFetch(bookId);
      return ReadAlongBuildOutcome.started;
    } catch (e) {
      debugPrint('[PositionSync] read-along build for $bookId: $e');
      if (!_disposed) await _raFetch(bookId);
      return ReadAlongBuildOutcome.failed;
    } finally {
      readAlongMutating = false;
      _changed();
    }
  }

  Future<ReadAlongCancelOutcome> _raCancel(int bookId) async {
    readAlongMutating = true;
    _changed();
    try {
      final pending = _pendingRaBuild;
      if (pending != null) {
        await pending;
        readAlongMutating = true;
      }
      final outcome = await api.cancelReadAlong(bookId, counterpartId: _counterpartOf(bookId));
      if (outcome != ReadAlongCancelOutcome.cancelled) return outcome;
      _raAwaiting = false;
      _raAwaitPolls = 0;
      await _raFetch(bookId);
      return ReadAlongCancelOutcome.cancelled;
    } finally {
      readAlongMutating = false;
      _changed();
    }
  }

  Future<void> retryReadAlong() => generate();

  Future<void> rebuildReadAlong() => generate(force: true);

  Future<void> cancelReadAlongAction() async {
    final outcome = await _raCancel(pairBookId);
    if (outcome == ReadAlongCancelOutcome.tooLate) {
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastReadAlongCancelTooLate);
    } else if (outcome == ReadAlongCancelOutcome.failed) {
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastReadAlongCancelUnavailable);
    }
  }

  // ─── Edition links ────────────────────────────────────────

  /// Runs one edition-link change and reloads this book's answer after it.
  /// Returns the failure, or null when it went through.
  Future<PositionSyncRequestFailure?> _mutate(Future<void> Function() call) async {
    _linkMutating = true;
    _changed();
    try {
      await call();
      candidates = const [];
      _linkMutating = false;
      await load();
      return null;
    } on PositionSyncRequestFailure catch (e) {
      return e;
    } catch (e) {
      debugPrint('[PositionSync] edition link change for $bookId: $e');
      return const PositionSyncRequestFailure(0, '');
    } finally {
      _linkMutating = false;
      _changed();
    }
  }

  // A fresh pair gets its alignment straight away. The read-along is never
  // started here: it is hours of work and always asked for on its own.
  Future<void> _alignNewPair(int pairId) async {
    _notice(PositionSyncNoticeKind.success, PositionSyncCopy.toastLinked);
    await _alBuild(pairId);
    pendingStart = false;
    _changed();
    // The pre-link read answered for a book without a pair.
    unawaited(_raFetch(pairId, forget: true));
    if (perms.generate) unawaited(fetchExisting(pairId));
  }

  Future<void> linkPair() async {
    // Taken before the link reloads this book's state.
    final pairId = pairBookId;
    final m = members;
    final s = selected;
    final detached = _detachedReadAlong;
    // A page whose pair the server already knows links through the pair's
    // own books.
    final ({int source, int counterpart})? request = detached && m?.text != null
        ? (source: m!.text!.id, counterpart: m.audio.id)
        : m != null && m.text == null && (detached || link != null) && s != null
            ? (source: m.audio.id, counterpart: s.bookId)
            : !detached && link == null && s != null
                ? (source: bookId, counterpart: s.bookId)
                : null;
    if (request == null) return;
    pendingStart = true;
    final failure = await _mutate(() => api.linkEditions(request.source, request.counterpart));
    if (failure != null) {
      pendingStart = false;
      _changed();
      final reason = (failure.status == 400 || failure.status == 409) && failure.message.isNotEmpty
          ? failure.message
          : PositionSyncCopy.toastLinkFailed;
      _notice(PositionSyncNoticeKind.error, reason);
      return;
    }
    await _alignNewPair(pairId);
  }

  /// Stops whatever this pair has running. A refused cancel is reported and
  /// the unlink still happens, except for a read-along already being
  /// imported onto this link.
  Future<bool> _stopPairBuilds(int pairId) async {
    if (_readAlongInFlight(readAlong.status) || readAlongMutating) {
      final outcome = await _raCancel(pairId);
      if (outcome == ReadAlongCancelOutcome.tooLate) {
        _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastReadAlongCancelTooLate);
        return false;
      }
      if (outcome == ReadAlongCancelOutcome.failed) {
        _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastReadAlongCancelKeptRunning);
      }
    }
    if (_alignmentRunningNow) {
      if (!await _alCancel(pairId)) _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastSyncCancelKeptRunning);
    }
    return true;
  }

  EditionLinkCandidateWire? _linkedCounterpartCandidate() {
    final m = members;
    // The ebook is the side that leaves on the read-along page too, so only
    // the ebook page restores the audiobook.
    final counterpart = m == null ? null : (role == EditionLinkRole.text ? m.audio : m.text);
    if (counterpart != null) {
      return EditionLinkCandidateWire(
        bookId: counterpart.id,
        title: counterpart.title,
        authorName: counterpart.authorName,
        coverVersion: counterpart.coverVersion,
        progress: counterpart.progressPercentage,
      );
    }
    final summary = forBook?.counterpart;
    return summary == null
        ? null
        : EditionLinkCandidateWire(
            bookId: summary.id, title: summary.title, authorName: summary.authorName, coverVersion: summary.coverVersion);
  }

  void _restoreSelection(EditionLinkCandidateWire? candidate) {
    if (candidate != null && forBook?.proposed?.bookId != candidate.bookId) {
      picked = candidate;
      proposalDismissed = true;
      return;
    }
    picked = null;
    proposalDismissed = false;
  }

  // Nothing read for the old pair may narrate the next one. The status is
  // asked for the restored counterpart, or the pair's surviving read-along
  // would be offered as a new build.
  void _forgetPair(EditionLinkCandidateWire? candidate) {
    _restoreSelection(candidate);
    _raReset();
    _changed();
    unawaited(load());
    unawaited(_alFetch(pairBookId));
    final cp = selected?.bookId;
    unawaited(_raFetch(pairBookId, counterpartId: cp, forget: cp == null));
  }

  /// The switch went off while the pair was still linking. Unlinked through
  /// the ebook where there is one, so a read-along stays on the audiobook.
  Future<void> cancelLinking() async {
    final pairId = pairBookId;
    final leavingId = members?.text?.id ?? pairId;
    final candidate = _linkedCounterpartCandidate();
    cancelling = true;
    _changed();
    try {
      if (!await _stopPairBuilds(pairId)) return;
      if (await _mutate(() => api.unlinkEdition(leavingId)) != null) {
        _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastCancelFailed);
        return;
      }
      _forgetPair(candidate);
    } finally {
      cancelling = false;
      _changed();
    }
  }

  Future<void> unlinkPair() async {
    final pairId = pairBookId;
    if (!await _stopPairBuilds(pairId)) return;
    if (await _mutate(() => api.unlinkEdition(pairId)) != null) {
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastUnlinkFailed);
      return;
    }
    _notice(PositionSyncNoticeKind.success, PositionSyncCopy.toastUnlinked);
    _forgetPair(null);
  }

  /// A member side swapped for [candidate]: unlink, then link the kept side
  /// with it.
  Future<void> applyChange(SyncEdition edition, EditionLinkCandidateWire candidate) async {
    final m = members;
    final keptId = m != null ? (edition == SyncEdition.audiobook ? (m.text?.id ?? bookId) : m.audio.id) : bookId;
    final pairId = pairBookId;
    if (_alignmentRunningNow && !await _alCancel(pairId)) {
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastSyncCancelKeptRunning);
    }
    if (await _mutate(() => api.unlinkEdition(pairId)) != null) {
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastUnlinkFailed);
      return;
    }
    resetSearch();
    pendingStart = true;
    if (await _mutate(() => api.linkEditions(keptId, candidate.bookId)) != null) {
      pendingStart = false;
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastChangeFailed(candidate.title ?? PositionSyncCopy.untitled));
      // Offered again as the candidate, so a second try is one tap.
      _forgetPair(candidate);
      return;
    }
    await _alignNewPair(keptId);
  }

  // With no link yet the read-along attaches to the audiobook alone, which
  // starts a link without an ebook.
  Future<void> attachReadAlongAction() async {
    final readAlongId = readAlong.outputBook?.id ?? (_isReadAlongPage ? bookId : null);
    final target = link != null ? pairBookId : sides.audiobook.book?.id;
    if (readAlongId == null || target == null) return;
    final failure = await _mutate(() => api.attachReadAlong(target, readAlongId));
    _notice(failure == null ? PositionSyncNoticeKind.success : PositionSyncNoticeKind.error,
        failure == null ? PositionSyncCopy.toastAttached : PositionSyncCopy.toastAttachFailed);
  }

  Future<void> detachReadAlongAction() async {
    final member = readAlongMember;
    if (member == null) return;
    // The detached output is still ready on a linked pair, which is what the
    // heal reloads for; a failed detach owes that heal again.
    final healedBefore = _reloadedForOutputId;
    _reloadedForOutputId = readAlong.outputBook?.id ?? member.id;
    if (await _mutate(() => api.unlinkEdition(member.id)) != null) {
      _reloadedForOutputId = healedBefore;
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastDetachFailed);
      return;
    }
    _notice(PositionSyncNoticeKind.success, PositionSyncCopy.toastDetached);
    final cp = link != null ? null : selected?.bookId;
    unawaited(_raFetch(pairBookId, counterpartId: cp, forget: cp == null));
  }

  // ─── Change search ────────────────────────────────────────

  void resetSearch() {
    _searchTimer?.cancel();
    _searchTimer = null;
    _searchReq++;
    candidates = const [];
    absCandidates = const [];
    searching = false;
    hasSearched = false;
    searchError = null;
  }

  /// Candidates for [edition]'s slot, debounced. They are those of the pair
  /// member the pick joins, which on a read-along page is not this book.
  void searchCandidates(SyncEdition edition, String q) {
    final s = sides;
    final sourceId = edition == SyncEdition.ebook ? (s.audiobook.book?.id ?? bookId) : (s.ebook.book?.id ?? bookId);
    _debounceSearch(() async {
      candidates = await api.editionLinkCandidates(sourceId, q: q);
    });
  }

  void searchAbs(String q) => _debounceSearch(() async {
        absCandidates = await api.absUnmatched(q: q);
      });

  void _debounceSearch(Future<void> Function() run) {
    _searchTimer?.cancel();
    final req = ++_searchReq;
    searching = true;
    hasSearched = true;
    searchError = null;
    _changed();
    _searchTimer = Timer(_searchDebounce, () async {
      try {
        await run();
        if (_disposed || req != _searchReq) return;
        searchError = null;
      } catch (e) {
        if (_disposed || req != _searchReq) return;
        candidates = const [];
        absCandidates = const [];
        searchError = PositionSyncCopy.searchFailed;
      } finally {
        if (!_disposed && req == _searchReq) {
          searching = false;
          _changed();
        }
      }
    });
  }

  bool isMemberSide(SyncEdition edition) => side(edition).isMember;

  /// A pick for a side that is not a member yet: it becomes the candidate
  /// the pair switch links.
  void pick(EditionLinkCandidateWire candidate) {
    final previous = selected?.bookId;
    picked = candidate;
    proposalDismissed = true;
    resetSearch();
    _changed();
    _selectionChanged(previous);
  }

  // Picking another counterpart before linking changes the pair, and so
  // whether a read-along exists for it.
  void _selectionChanged(int? previous) {
    final next = selected?.bookId;
    if (link != null || _linkMutating || next == previous) return;
    final followed = _forBookCounterpartId;
    final answeredFor = _requestedCounterpartId ?? forBook?.proposed?.bookId;
    if (followed != null && followed != answeredFor) unawaited(load());
    if (!perms.generate || _readAlongInFlight(readAlong.status)) return;
    unawaited(_raFetch(pairBookId, counterpartId: next, forget: next == null));
  }

  // ─── Audiobookshelf ───────────────────────────────────────

  Future<void> _absLoadConfigured() async {
    if (!perms.abs) return;
    try {
      final configured = await api.absConfigured();
      if (_disposed) return;
      absConfigured = configured;
      _changed();
    } catch (e) {
      // Keep the previous answer.
      debugPrint('[PositionSync] Audiobookshelf settings: $e');
    }
  }

  Future<void> _absLoad(int? audioBookId) async {
    _absLoadedFor = audioBookId;
    final req = ++_absReq;
    if (!perms.abs || audioBookId == null) {
      absLink = null;
      absLive = null;
      absChecking = false;
      return;
    }
    try {
      final link = await api.absLinkForBook(audioBookId);
      if (_disposed || req != _absReq) return;
      if (link?.absLibraryItemId != absLink?.absLibraryItemId) absLive = null;
      absLink = link;
      _changed();
      if (link != null && link.syncing) {
        await _absRefreshLive(req);
      } else {
        // A paused or missing match has no live position to show.
        absLive = null;
        absChecking = false;
        _changed();
      }
    } catch (e) {
      if (_disposed || req != _absReq) return;
      debugPrint('[PositionSync] Audiobookshelf link for $audioBookId: $e');
      absLink = null;
      absLive = null;
      _changed();
    }
  }

  Future<void> _absRefreshLive([int? req]) async {
    final id = absLink?.absLibraryItemId;
    if (id == null || absLink?.syncing != true) return;
    absChecking = absLive == null;
    _changed();
    AbsSyncLiveWire live;
    try {
      live = await api.absLive(id);
    } catch (e) {
      live = const AbsSyncLiveWire(status: AbsLiveStatus.unreachable);
    }
    if (_disposed || (req != null && req != _absReq)) return;
    absLive = live;
    absChecking = false;
    _changed();
  }

  /// [direction] is 'push' or 'pull'. Both sides' positions move, so the
  /// cards are read again after it.
  Future<void> absReconcileAction(String direction) async {
    final id = absLink?.absLibraryItemId;
    if (id == null) return;
    absBusy = direction;
    absActionError = null;
    _changed();
    try {
      absLive = await api.absReconcile(id, direction);
      absBusy = null;
      _changed();
      await load();
    } on PositionSyncRequestFailure catch (e) {
      absActionError = e.status == 409
          ? PositionSyncCopy.absReconcileBusy
          : e.status == 502
              ? PositionSyncCopy.absReconcileUnreachable
              : PositionSyncCopy.absReconcileFailed;
    } catch (e) {
      absActionError = PositionSyncCopy.absReconcileFailed;
    } finally {
      absBusy = null;
      _changed();
    }
  }

  Future<void> absRetry() async {
    absBusy = 'retry';
    absActionError = null;
    try {
      await _absRefreshLive();
    } finally {
      absBusy = null;
      _changed();
    }
  }

  Future<void> _absSetExcluded(bool excluded) async {
    final id = absLink?.absLibraryItemId;
    if (id == null) return;
    absBusy = excluded ? 'pause' : 'resume';
    _changed();
    try {
      await api.absSetExcluded(id, excluded);
      await _absLoad(absAudioBookId);
      _notice(PositionSyncNoticeKind.success, excluded ? PositionSyncCopy.toastAbsPaused : PositionSyncCopy.toastAbsResumed);
    } catch (e) {
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastAbsFailed);
    } finally {
      absBusy = null;
      _changed();
    }
  }

  Future<void> absPause() => _absSetExcluded(true);

  Future<void> absResume() => _absSetExcluded(false);

  Future<void> absConfirmAction() async {
    final id = absLink?.absLibraryItemId;
    if (id == null) return;
    absBusy = 'confirm';
    _changed();
    try {
      await api.absConfirm(id);
      await _absLoad(absAudioBookId);
      if (absLink?.syncing == true) _notice(PositionSyncNoticeKind.success, PositionSyncCopy.toastAbsResumed);
    } catch (e) {
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastAbsFailed);
    } finally {
      absBusy = null;
      _changed();
    }
  }

  /// Matches the audiobook with [item] instead of its current
  /// Audiobookshelf item. True when it went through.
  Future<bool> absChange(AbsBookStateWire item) async {
    final audioBookId = absAudioBookId;
    if (audioBookId == null) return false;
    final previous = absLink?.absLibraryItemId;
    final replaces = previous != null && previous != item.absLibraryItemId;
    absBusy = 'change';
    _changed();
    try {
      if (replaces) await api.absUnlinkBook(previous);
      try {
        await api.absLinkBook(item.absLibraryItemId, audioBookId);
      } catch (_) {
        // Best effort: put the previous match back.
        if (replaces) {
          try {
            await api.absLinkBook(previous, audioBookId);
          } catch (_) {}
        }
        rethrow;
      }
      _notice(PositionSyncNoticeKind.success, PositionSyncCopy.toastAbsChanged);
      return true;
    } catch (e) {
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastAbsFailed);
      return false;
    } finally {
      await _absLoad(audioBookId);
      absBusy = null;
      _changed();
    }
  }
}
