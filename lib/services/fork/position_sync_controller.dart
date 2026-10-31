import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api_service.dart';
import 'perf_caches.dart';
import 'position_sync_chain.dart';

// Fork-owned: loads, polls and acts on one BookOrbit book's position sync,
// a port of BookOrbit's useSyncChainPanel and the composables it uses
// (useReadingAlignment, useSyncChainReadAloud with upstream's useReadAloud,
// the Audiobookshelf sync link). The sync button, the Editions card and the
// sheet share one controller per book. It has no widgets: what an action
// ends with goes to [onNotice], which the open sheet turns into a toast.
// See FORK_NOTES.md.

enum PositionSyncNoticeKind { success, error, info }

class PositionSyncNotice {
  final PositionSyncNoticeKind kind;
  final String message;
  const PositionSyncNotice(this.kind, this.message);
}

class _Entry {
  final PositionSyncController controller;
  int refs = 0;
  Timer? disposeTimer;
  _Entry(this.controller);
}

const _alignmentPoll = Duration(seconds: 3);
// A read-aloud runs for minutes to hours, so its job is read far less often;
// one waiting for review only changes when someone reviews it.
const _jobPoll = Duration(seconds: 5);
const _reviewPoll = Duration(seconds: 30);
// A build starts asynchronously, so the next reads can still show the row
// from before it. This many are held as the optimistic status.
const _maxAwaitBuildRowPolls = 5;
const _searchDebounce = Duration(milliseconds: 250);

bool _alignmentRunning(AlignmentStatus s) => s == AlignmentStatus.pending || s == AlignmentStatus.building;

const _slotStatuses = {
  ReadAloudJobStatus.queued,
  ReadAloudJobStatus.processing,
  ReadAloudJobStatus.awaitingReview,
  ReadAloudJobStatus.failed,
};

/// Reasons only an admin or a library change can clear: the slot stays out
/// of the chain rather than saying so on every visit.
const _hiddenReasons = {ReadAloudReason.workerNotConfigured, ReadAloudReason.singleFileLibrary, ReadAloudReason.noAudiobook};

/// Upstream's resolveReadAloudEntry.
ReadAloudEntry resolveReadAloudEntry({required bool enabled, ReadAloudCapabilityWire? capability, ReadAloudJobWire? job}) {
  if (!enabled || capability == null || !capability.workerConfigured) return const ReadAloudEntryHidden();
  final reason = capability.reason;
  if (reason != null && _hiddenReasons.contains(reason)) return const ReadAloudEntryHidden();
  if (job != null && job.active) {
    return ReadAloudEntryUnavailable(ReadAloudReason.jobActive, PositionSyncCopy.reasons[ReadAloudReason.jobActive]!);
  }
  if (reason == ReadAloudReason.noEpub && capability.existingReadAlongs > 0) {
    return const ReadAloudEntryUnavailable(ReadAloudReason.noEpub, PositionSyncCopy.reasonNoEpubExisting);
  }
  if (reason != null) return ReadAloudEntryUnavailable(reason, PositionSyncCopy.reasons[reason] ?? PositionSyncCopy.reasonUnknown);
  if (!capability.eligible) return const ReadAloudEntryUnavailable(null, PositionSyncCopy.reasonUnknown);
  return const ReadAloudEntryAvailable();
}

/// The job as the slot follows it, or null for one it does not show.
SyncChainReadAloudJob? slotJobFrom(ReadAloudJobWire? job, {DateTime? now}) {
  if (job == null || job.dismissedAt != null || !_slotStatuses.contains(job.status)) return null;
  final until = job.retryableUntil == null ? null : DateTime.tryParse(job.retryableUntil!);
  return SyncChainReadAloudJob(
    status: job.status,
    stage: job.stage,
    progress: job.progress,
    queuePosition: job.queuePosition,
    stopping: job.cancelRequested,
    canCancel: job.canManage && job.cancellable && job.stage != 'publishing',
    // As upstream's job card: Retry resumes from kept work files, which expire.
    canRetry: job.canManage && job.errorCode != 'review_expired' && until != null && until.isAfter(now ?? DateTime.now()),
    error: job.status == ReadAloudJobStatus.failed ? readAloudJobError(job.errorCode) : null,
  );
}

String _createError(Object e) => switch (e is PositionSyncRequestFailure ? e.status : null) {
      400 => PositionSyncCopy.errorCreateInvalid,
      403 => PositionSyncCopy.errorForbidden,
      409 => PositionSyncCopy.errorCreateConflict,
      503 => PositionSyncCopy.errorCreateUnavailable,
      _ => PositionSyncCopy.errorCreate,
    };

String _mutationError(Object e, String fallback) => switch (e is PositionSyncRequestFailure ? e.status : null) {
      403 => PositionSyncCopy.errorForbidden,
      404 => PositionSyncCopy.errorGone,
      409 => PositionSyncCopy.errorConflict,
      _ => fallback,
    };

class PositionSyncController extends ChangeNotifier {
  PositionSyncController._(this.api, this.bookId);

  static final Map<int, _Entry> _registry = {};

  static bool _listensForClears = false;

  /// The shared controller for [bookId]; every acquire needs a [release].
  /// [api] replaces the one held, since the auth provider hands out a fresh
  /// service on every read.
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
    // A sheet reopened within the grace period shows the state it had and
    // picks its polling back up.
    if (entry.refs == 1 && c._parked) {
      c._parked = false;
      if (c.loaded) {
        _resume(c);
      }
    }
    return c;
  }

  static void _resume(PositionSyncController c) {
    if (_alignmentRunning(c.alignment.status)) unawaited(c._alFetch());
    if (c._job?.active == true) unawaited(c._refreshJob());
  }

  /// How long a released controller is kept for the next open of its book.
  /// Settable so tests can run it in milliseconds.
  static Duration releaseGrace = const Duration(seconds: 90);

  /// Parks the controller while nothing shows it: its polling stops, and it
  /// is disposed after [releaseGrace] unless acquired again.
  static void release(PositionSyncController c) {
    final entry = _registry[c.bookId];
    if (entry == null || !identical(entry.controller, c)) return;
    entry.refs--;
    if (entry.refs > 0) return;
    c._parked = true;
    c._alTimer?.cancel();
    c._alTimer = null;
    c._jobTimer?.cancel();
    c._jobTimer = null;
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
  bool get pollingForTest => _alTimer != null || _jobTimer != null;

  @visibleForTesting
  bool get disposedForTest => _disposed;

  /// Set while nothing holds the controller: no polling is scheduled.
  bool _parked = false;

  BookOrbitApiService api;
  final int bookId;

  /// Set by the open sheet; notices raised while it is closed are dropped.
  ValueChanged<PositionSyncNotice>? onNotice;

  bool _disposed = false;
  bool _initialStarted = false;

  bool loaded = false;
  String? loadError;
  PositionSyncBookInfo? info;
  PositionSyncProgressWire progress = const PositionSyncProgressWire();
  PositionSyncPermissions perms = const PositionSyncPermissions();

  // Alignment.
  AlignmentStatusWire alignment = const AlignmentStatusWire();
  AlignmentBlock? alignmentBlocked;
  bool alignmentMutating = false;
  bool cancelling = false;
  Timer? _alTimer;
  int _alReq = 0;
  bool _alAwaiting = false;
  int _alAwaitPolls = 0;
  AlignmentStatus _alBaseStatus = AlignmentStatus.none;
  String? _alBaseBuiltAt;
  Future<bool>? _pendingAlBuild;

  // Upstream's read-aloud sync.
  bool readAloudSaving = false;

  // Upstream's read-aloud generator.
  ReadAloudCapabilityWire? capability;
  ReadAloudJobWire? _job;
  ReadAloudPending? jobAction;
  String? _slotError;
  Timer? _jobTimer;
  int _capReq = 0;
  final Set<String> _completedJobIds = {};

  /// The job whose status route answered 403 or 404; polling it again
  /// cannot succeed.
  String? _pollStoppedFor;

  // Audiobookshelf.
  bool absConfigured = false;
  AbsSyncLinkWire? absLink;
  AbsSyncLiveWire? absLive;
  bool absChecking = false;

  /// The reconcile direction or action in flight.
  String? absBusy;
  String? absActionError;
  int _absReq = 0;

  // Audiobookshelf match search.
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
    _jobTimer?.cancel();
    _searchTimer?.cancel();
    onNotice = null;
    super.dispose();
  }

  void _notice(PositionSyncNoticeKind kind, String message) => onNotice?.call(PositionSyncNotice(kind, message));

  void _changed() {
    if (_disposed) return;
    _chain = null;
    notifyListeners();
  }

  // ─── Derived ──────────────────────────────────────────────

  bool get _hasAudio => info?.audiobook != null;

  /// Whisper aligns the plain EPUB with the audio only while the book has no
  /// read-aloud, which upstream's own sync takes over.
  bool get _usesWhisper => info?.ebook != null && info?.audiobook != null && info?.readAlong == null;

  bool get busy =>
      alignmentMutating || readAloudSaving || jobAction != null || absBusy != null;

  /// Two of the book's own files to sync, or Audiobookshelf for its audio.
  /// Until the first answers are in the button shows its loading look rather
  /// than jumping away.
  bool get eligible {
    final i = info;
    if (i == null || !loaded) return true;
    final sides = [i.ebook, i.audiobook, i.readAlong].nonNulls.length;
    return sides >= 2 || (_hasAudio && perms.abs && absConfigured);
  }

  ReadAloudJobWire? get job => _job;

  bool get creating => _job?.running == true;

  SyncChainReadAloudSlot get _slot => SyncChainReadAloudSlot(
        entry: resolveReadAloudEntry(enabled: perms.generate && _usesWhisper, capability: capability, job: _job),
        job: slotJobFrom(_job),
        pending: jobAction,
        error: _slotError,
      );

  int? _filesProgress(PositionSyncEditionFiles? e) {
    if (e == null) return null;
    double? best;
    for (final id in e.fileIds) {
      final p = progress.files[id];
      if (p != null && (best == null || p > best)) best = p;
    }
    return best == null ? null : displayPercentage(best, best >= 100);
  }

  SyncChainEdition? _edition(PositionSyncEditionFiles? e, int? progress) => e == null
      ? null
      : SyncChainEdition(
          title: e.title,
          formatName: e.formatName,
          fileCount: e.fileIds.length,
          sizeBytes: e.sizeBytes,
          progress: progress,
        );

  SyncChainSnapshot get snapshot {
    final i = info;
    final audio = progress.audio;
    return SyncChainSnapshot(
      bookId: bookId,
      coverVersion: i?.coverVersion,
      ebook: _edition(i?.ebook, _filesProgress(i?.ebook)),
      readAlong: _edition(i?.readAlong, _filesProgress(i?.readAlong)),
      audiobook: _edition(i?.audiobook, audio == null ? null : displayPercentage(audio, audio >= 100)),
      readAloudSlot: _slot,
      alignment: SyncChainAlignment(
        status: alignment.status,
        stale: alignment.stale,
        builtAt: alignment.builtAt,
        samplesDone: alignment.samplesDone,
        samplesTotal: alignment.samplesTotal,
        buildBlocked: alignmentBlocked,
        buildError: alignment.error,
        running: _alignmentRunning(alignment.status) || alignmentMutating,
      ),
      readAloud: i?.readAloudSync ?? const ReadAloudSync(),
      abs: perms.abs ? SyncChainAbs(configured: absConfigured, link: _absMirror, live: _absLiveMirror, checking: absChecking) : null,
      canAlign: perms.align,
    );
  }

  AbsLink? get _absMirror {
    final l = absLink;
    return l == null
        ? null
        : AbsLink(
            absLibraryItemId: l.absLibraryItemId,
            title: l.title,
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
    // A failed first load reads as not syncing, with no dot.
    if (loaded && info == null) return SyncButtonState.notLinked;
    return syncButtonState(loaded: loaded, tone: chain.header.tone, creating: creating);
  }

  String get buttonTooltip => PositionSyncCopy.tooltip(
      creating && chain.header.tone != ChainTone.info ? readAloudStageLabel(_job?.stage) : chain.header.label);

  /// The building ring's fill: alignment samples, or the read-aloud job's
  /// own progress; null spins.
  double? get buttonProgress {
    if (_alignmentRunning(alignment.status) || alignmentMutating) {
      final done = alignment.samplesDone;
      final total = alignment.samplesTotal;
      return done != null && total != null && total > 0 ? (done / total).clamp(0.0, 1.0) : null;
    }
    final j = _job;
    if (j == null || j.status != ReadAloudJobStatus.processing) return null;
    return (j.progress / 100).clamp(0.0, 1.0);
  }

  // ─── Loading ──────────────────────────────────────────────

  /// Read up front so the button and the Editions card reflect the real
  /// state before the sheet is opened. Runs once per controller.
  Future<void> loadInitial() async {
    if (_initialStarted) return;
    _initialStarted = true;
    try {
      final (p, i) = await (api.positionSyncPermissions(), api.positionSyncBookInfo(bookId)).wait;
      perms = p;
      info = i;
      loadError = null;
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
    if (info == null) loadError = PositionSyncCopy.loadFailed;
    loaded = true;
    _changed();
    await Future.wait([_loadProgress(), _alFetchIfWhisper(), _absLoadConfigured(), _loadCapability()]);
  }

  /// The sheet opened: read everything it shows again.
  Future<void> open() async {
    absActionError = null;
    resetSearch();
    if (!_initialStarted) await loadInitial();
    // Read again on every open: one failed /auth/me would otherwise leave the
    // sheet read-only until the detail sheet closes. The service keeps the
    // answer once it has one.
    try {
      perms = await api.positionSyncPermissions();
      info = await api.positionSyncBookInfo(bookId);
      loadError = null;
    } catch (e) {
      debugPrint('[PositionSync] book info for $bookId: $e');
      if (info == null) loadError = PositionSyncCopy.loadFailed;
    }
    if (_disposed) return;
    _changed();
    await Future.wait([
      _loadProgress(),
      _alFetchIfWhisper(),
      _absLoadConfigured(),
      _absLoad(),
      _loadCapability(),
    ]);
  }

  Future<void> _loadProgress() async {
    try {
      final p = await api.positionSyncProgress(bookId);
      if (_disposed) return;
      progress = p;
      _changed();
    } catch (e) {
      debugPrint('[PositionSync] progress for $bookId: $e');
    }
  }

  /// A job that finished added a read-aloud file, which changes the whole
  /// chain: the detail is read past its cache.
  Future<void> _reloadBook() async {
    try {
      final i = await api.positionSyncBookInfo(bookId, fresh: true);
      if (_disposed) return;
      info = i;
      _changed();
      await _loadProgress();
    } catch (e) {
      debugPrint('[PositionSync] book reload for $bookId: $e');
    }
  }

  // ─── Alignment ────────────────────────────────────────────

  Future<void> _alFetchIfWhisper() => _usesWhisper ? _alFetch() : Future.value();

  void _alSchedule() {
    _alTimer?.cancel();
    _alTimer = null;
    if (_parked || !_alignmentRunning(alignment.status)) return;
    _alTimer = Timer(_alignmentPoll, () {
      _alTimer = null;
      unawaited(_alFetch());
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

  Future<void> _alFetch() async {
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
        _alSchedule();
        _changed();
      }
    }
  }

  /// False when the request itself failed; a refusal sets
  /// [alignmentBlocked] instead.
  Future<bool> _alBuild({bool force = false}) {
    final f = _alRequestBuild(force);
    _pendingAlBuild = f;
    f.whenComplete(() {
      if (identical(_pendingAlBuild, f)) _pendingAlBuild = null;
    });
    return f;
  }

  Future<bool> _alRequestBuild(bool force) async {
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
      await _alFetch();
      return true;
    } catch (e) {
      debugPrint('[PositionSync] alignment build for $bookId: $e');
      if (!_disposed) await _alFetch();
      return false;
    } finally {
      alignmentMutating = false;
      _changed();
    }
  }

  Future<void> buildAlignmentAction({bool force = false}) async {
    if (!await _alBuild(force: force)) _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastAlignBuildFailed);
  }

  /// Only a cancel in flight locks the cancel button: a build in flight is
  /// exactly what it stops.
  Future<void> cancelAlignmentAction() async {
    cancelling = true;
    _changed();
    try {
      // A cancel sent before the build lands finds nothing to stop.
      final pending = _pendingAlBuild;
      if (pending != null) await pending;
      await api.cancelAlignment(bookId);
      // A cancelled build never gets its row.
      _alAwaiting = false;
      _alAwaitPolls = 0;
      await _alFetch();
    } catch (e) {
      debugPrint('[PositionSync] alignment cancel for $bookId: $e');
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastSyncCancelKeptRunning);
    } finally {
      cancelling = false;
      _changed();
    }
  }

  // ─── Read-aloud sync ──────────────────────────────────────

  Future<void> setReadAloudSync(bool on) async {
    final mode = on ? ReadAloudSyncMode.auto : ReadAloudSyncMode.disabled;
    final current = info;
    if (readAloudSaving || current == null || current.readAloudSync.mode == mode) return;
    readAloudSaving = true;
    _changed();
    try {
      final sync = await api.setReadAloudSyncMode(bookId, mode);
      if (_disposed) return;
      info = PositionSyncBookInfo(
        coverVersion: current.coverVersion,
        language: current.language,
        ebook: current.ebook,
        readAlong: current.readAlong,
        audiobook: current.audiobook,
        readAloudSync: sync,
      );
    } catch (e) {
      debugPrint('[PositionSync] read-aloud sync for $bookId: $e');
      _notice(PositionSyncNoticeKind.error, PositionSyncCopy.toastReadAloudSyncFailed);
    } finally {
      readAloudSaving = false;
      _changed();
    }
  }

  // ─── Read-aloud generator ─────────────────────────────────

  bool get _generatorApplies => perms.generate && _usesWhisper;

  Future<void> _loadCapability() async {
    // A job already running is followed even when the book stopped
    // qualifying (say, it gained its read-aloud mid-way).
    if (!_generatorApplies && _job == null) return;
    final req = ++_capReq;
    try {
      final c = await api.readAloudCapability(bookId);
      if (_disposed || req != _capReq) return;
      capability = c;
      _applyJob(c.latestJob, fromUpdate: false);
    } catch (e) {
      // A failed recheck keeps the last good answer.
      debugPrint('[PositionSync] read-aloud capability for $bookId: $e');
    } finally {
      if (!_disposed && req == _capReq) _changed();
    }
  }

  void _applyJob(ReadAloudJobWire? next, {required bool fromUpdate}) {
    if (next != null && next.bookId != bookId) return;
    final previous = _job;
    // Polls and answers can cross; an older copy never overwrites a newer one.
    if (next != null && previous != null && next.id == previous.id) {
      final a = DateTime.tryParse(next.updatedAt ?? '');
      final b = DateTime.tryParse(previous.updatedAt ?? '');
      if (a != null && b != null && a.isBefore(b)) return;
    }
    if (next?.id != previous?.id) _slotError = null;
    _job = next;
    if (next != null && next.completed && _completedJobIds.add(next.id)) {
      final watched = previous?.id == next.id ? !previous!.completed : fromUpdate;
      if (watched) unawaited(_reloadBook());
    }
    // A job that just stopped frees the book's slot and may have added a
    // file, so what can be made moved.
    if (fromUpdate && previous?.active == true && next?.active != true) unawaited(_loadCapability());
    _jobSchedule();
    _changed();
  }

  void _jobSchedule() {
    _jobTimer?.cancel();
    _jobTimer = null;
    final j = _job;
    if (_parked || j == null || !j.active || _pollStoppedFor == j.id) return;
    _jobTimer = Timer(j.running ? _jobPoll : _reviewPoll, () {
      _jobTimer = null;
      unawaited(_refreshJob());
    });
  }

  Future<void> _refreshJob() async {
    final current = _job;
    if (current == null) return;
    try {
      final next = await api.readAloudJob(current.id);
      if (_disposed) return;
      _applyJob(next, fromUpdate: true);
    } on PositionSyncRequestFailure catch (e) {
      if (_disposed) return;
      if (e.status == 403 || e.status == 404) {
        _pollStoppedFor = current.id;
        _jobTimer?.cancel();
        _jobTimer = null;
        if (e.status == 404) unawaited(_loadCapability());
        return;
      }
      _jobSchedule();
    } catch (e) {
      // The next poll catches up; a transient failure is not worth a message.
      if (!_disposed) _jobSchedule();
    }
  }

  /// What upstream's dialog would start with no changes, or null when it
  /// would need the reader to pick something.
  ReadAloudRequest? defaultRequest(String? savedLanguage) {
    final c = capability;
    if (c == null || c.epubFiles.isEmpty || c.audioFileIds.isEmpty) return null;
    final language = readAloudLanguage(c.supportedLanguages, info?.language, savedLanguage);
    if (language == null) return null;
    return ReadAloudRequest(epubFileId: c.epubFiles.first.id, audioFileIds: c.audioFileIds, language: language);
  }

  /// One tap: the dialog's own defaults. False when it needs a choice, and
  /// the sheet opens the options instead.
  Future<bool> createReadAloud() async {
    if (jobAction != null || resolveReadAloudEntry(enabled: _generatorApplies, capability: capability, job: _job) is! ReadAloudEntryAvailable) {
      return true;
    }
    _slotError = null;
    final request = defaultRequest(await api.readAloudDefaultLanguage());
    if (request == null) return false;
    await createReadAloudWith(request);
    return true;
  }

  /// Null when the job started, else why not.
  Future<String?> createReadAloudWith(ReadAloudRequest request) async {
    if (jobAction != null) return PositionSyncCopy.errorCreate;
    jobAction = ReadAloudPending.create;
    _slotError = null;
    _changed();
    try {
      final created = await api.createReadAloudJob(bookId, request);
      if (_disposed) return null;
      _pollStoppedFor = null;
      _applyJob(created, fromUpdate: true);
      return null;
    } catch (e) {
      debugPrint('[PositionSync] read-aloud create for $bookId: $e');
      // A rejected selection, a job someone else started or an offline
      // worker all mean the capability is stale.
      if (!(e is PositionSyncRequestFailure && e.status == 403)) unawaited(_loadCapability());
      final error = _createError(e);
      _slotError = error;
      return error;
    } finally {
      jobAction = null;
      _changed();
    }
  }

  Future<void> _mutateJob(ReadAloudPending action, Future<ReadAloudJobWire?> Function(String id) call, String fallback) async {
    final current = _job;
    if (current == null || jobAction != null) return;
    jobAction = action;
    _slotError = null;
    _changed();
    try {
      final next = await call(current.id);
      if (_disposed) return;
      _applyJob(next, fromUpdate: true);
    } catch (e) {
      if (_disposed) return;
      _slotError = _mutationError(e, fallback);
      // The job may have moved on server-side; show where it is now.
      await _refreshJob();
    } finally {
      jobAction = null;
      _changed();
    }
  }

  Future<void> cancelReadAloud() =>
      _mutateJob(ReadAloudPending.cancel, api.cancelReadAloudJob, PositionSyncCopy.errorCancel);

  Future<void> retryReadAloud() =>
      _mutateJob(ReadAloudPending.retry, api.retryReadAloudJob, PositionSyncCopy.errorRetry);

  String get reviewUrl => api.readAloudReviewUrl(bookId);

  // ─── Audiobookshelf match search ──────────────────────────

  void resetSearch() {
    _searchTimer?.cancel();
    _searchTimer = null;
    _searchReq++;
    absCandidates = const [];
    searching = false;
    hasSearched = false;
    searchError = null;
  }

  void searchAbs(String q) {
    _searchTimer?.cancel();
    final req = ++_searchReq;
    searching = true;
    hasSearched = true;
    searchError = null;
    _changed();
    _searchTimer = Timer(_searchDebounce, () async {
      try {
        final found = await api.absUnmatched(q: q);
        if (_disposed || req != _searchReq) return;
        absCandidates = found;
      } catch (e) {
        if (_disposed || req != _searchReq) return;
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

  // ─── Audiobookshelf ───────────────────────────────────────

  /// Audiobookshelf only ever links the audiobook, so a book without one
  /// never needs its settings.
  Future<void> _absLoadConfigured() async {
    if (!perms.abs || !_hasAudio) return;
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

  Future<void> _absLoad() async {
    final req = ++_absReq;
    if (!perms.abs || !_hasAudio) {
      absLink = null;
      absLive = null;
      absChecking = false;
      return;
    }
    try {
      final link = await api.absLinkForBook(bookId);
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
      debugPrint('[PositionSync] Audiobookshelf link for $bookId: $e');
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
  /// progress is read again after it.
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
      await _loadProgress();
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
      await _absLoad();
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
      await _absLoad();
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
    if (!_hasAudio) return false;
    final previous = absLink?.absLibraryItemId;
    final replaces = previous != null && previous != item.absLibraryItemId;
    absBusy = 'change';
    _changed();
    try {
      if (replaces) await api.absUnlinkBook(previous);
      try {
        await api.absLinkBook(item.absLibraryItemId, bookId);
      } catch (_) {
        // Best effort: put the previous match back.
        if (replaces) {
          try {
            await api.absLinkBook(previous, bookId);
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
      await _absLoad();
      absBusy = null;
      _changed();
    }
  }
}
