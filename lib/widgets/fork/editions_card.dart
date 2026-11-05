import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/library_provider.dart';
import '../../services/api_service.dart';
import '../../services/book_requests.dart';
import '../../services/bookorbit_match.dart';
import '../../services/download_service.dart';
import '../../services/ebook_cache.dart';
import '../../services/narration_service.dart';
import '../../services/fork/plain_ebook_copy.dart';
import '../../services/fork/position_sync_chain.dart';
import '../../services/fork/timing_index_narration.dart';
import '../../services/fork/work_editions.dart';
import '../absorbing_shared.dart' show DownloadWideButton;
import '../overlay_toast.dart';
import 'position_sync_sheet.dart';
import 'watchlist_cover_badges.dart' show WatchlistDashedBorder;

// Fork-owned: the Editions card on a BookOrbit book page, listing the book's
// audiobook, read-aloud and ebook files from its position sync state. A row
// opens the Position sync sheet; a missing audiobook or ebook can be
// requested into this book. Its footer carries the book's edition sync
// switch and status, where BookOrbit's card lists the files on disk; the
// collapsed header shows the status. Hooked in from book_detail_redesign.dart.
// See FORK_NOTES.md.

// New text stays plain until upstream takes it (FORK_NOTES rule 4).
const _kEditions = 'Editions';
const _kNotCreated = 'Not created yet';
const _kCreate = 'Create';
const _kBuilding = 'Being created';
const _kSaveEbook = 'Download ebook';
const _kEbookSaved = 'Ebook downloaded';
const _kNoAudiobook = 'No audiobook yet';
const _kNoEbook = 'No ebook yet';
const _kRequest = 'Request';
const _kJoinRequest = 'Join request';
const _kRequested = 'Requested';
const _kRequestedBySomeone = 'Requested by someone else';
const _kOwnedElsewhere = 'In your library as a separate book';
const _kSubmittedAudiobook = 'Requested. The audiobook will join this book when it arrives';
const _kSubmittedEbook = 'Requested. The ebook will join this book when it arrives';
const _kJoinedRequest = 'Added you to the existing request';
const _kRequestFailed = 'Could not send the request';

/// Where a missing format's request stands, as BookOrbit's own row reads it.
enum _RequestState { checking, fresh, joinable, following, owned }

/// What a request gap's row says and offers.
class EditionRequestRow {
  final String note;

  /// Null when there is nothing to press.
  final String? action;
  final bool busy;
  final VoidCallback? onTap;
  const EditionRequestRow({required this.note, this.action, this.busy = false, this.onTap});
}

/// Width of the download button at a row's end.
const double _kActionSlot = 34;

class ForkEditionsCard extends StatefulWidget {
  final String itemId;
  final BookOrbitApiService api;
  final Color accent;

  /// For the audiobook's download record and the ebook's file.
  final String title;
  final String? author;
  final String? coverUrl;

  /// The mapped book, which the Ebook and Read-along rows' files come from.
  final Map<String, dynamic>? item;

  /// This book's progress as the page shows it (0..1), fresher than the
  /// sync state's copy of the audiobook's.
  final double progress;

  /// The cover's container colour for the Position sync sheet.
  final Color? tint;

  /// The book's mapped metadata, which a request for its missing format is
  /// made from.
  final Map<String, dynamic> metadata;

  const ForkEditionsCard({
    super.key,
    required this.itemId,
    required this.api,
    required this.accent,
    required this.progress,
    required this.title,
    required this.metadata,
    this.author,
    this.coverUrl,
    this.item,
    this.tint,
  });

  @override
  State<ForkEditionsCard> createState() => _ForkEditionsCardState();
}

class _ForkEditionsCardState extends State<ForkEditionsCard> {
  late final PositionSyncController _c;
  bool _expanded = false;

  /// Whether this reader may request a format into this book: allowed to
  /// request, on a server that files a request into a named book. Null until
  /// known.
  bool? _canRequest;

  /// The format the request gap is for, and where its request stands.
  String? _requestKind;
  _RequestState _request = _RequestState.checking;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // The page already holds this controller (prefetch and sync button), so
    // its state is there or on its way.
    _c = acquirePositionSync(widget.api, widget.itemId);
    widget.api.bookRequestAccess().then((a) {
      if (mounted) setState(() => _canRequest = a.canRequest && a.pairs);
    });
  }

  /// Asks the server whether the missing format is already asked for, owned
  /// as another book, or new, as the web row does before it offers anything.
  Future<void> _checkRequest(String kind) async {
    _requestKind = kind;
    _request = _RequestState.checking;
    // The book's ISBN may be an ISBN-10, which would match nothing as an ISBN-13.
    final isbn = '${widget.metadata['isbn'] ?? ''}'.replaceAll('-', '');
    final isbn13 = isbn.length == 13 ? isbn : '';
    final candidate = MatchCandidate({
      'title': widget.metadata['title'] ?? widget.title,
      'authors': [if ((widget.author ?? '').isNotEmpty) widget.author!.split(', ').first],
      'isbn13': isbn13,
    });
    final answers = await widget.api.bookRequestAvailability([candidate], kind);
    if (!mounted || _requestKind != kind) return;
    setState(() => _request = _stateOf(answers.firstOrNull));
  }

  static _RequestState _stateOf(BookRequestAvailability? a) {
    if (a?.ownedBookId != null) return _RequestState.owned;
    if (a?.existingRequestId != null) return a!.alreadySubscribed ? _RequestState.following : _RequestState.joinable;
    return _RequestState.fresh;
  }

  Future<void> _submitRequest(String kind) async {
    final bookId = int.tryParse(widget.itemId);
    if (bookId == null) return;
    setState(() => _submitting = true);
    final result = await widget.api.submitBookRequest(missingEditionRequestPayload(widget.metadata, kind, bookId));
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (result.ok) _request = _RequestState.following;
    });
    if (result.ok) {
      showOverlayToast(
        context,
        result.subscribed ? _kJoinedRequest : (kind == 'audiobook' ? _kSubmittedAudiobook : _kSubmittedEbook),
        icon: Icons.check_circle_outline_rounded,
      );
    } else {
      showOverlayToast(
        context,
        result.error == null ? _kRequestFailed : '$_kRequestFailed: ${result.error}',
        icon: Icons.error_outline_rounded,
      );
    }
  }

  EditionRequestRow _requestRow(WorkEdition r) {
    final kind = requestMediaKind(r.kind);
    final missing = kind == 'audiobook' ? _kNoAudiobook : _kNoEbook;
    if (_canRequest != true) return EditionRequestRow(note: missing);
    return switch (_request) {
      _RequestState.checking => EditionRequestRow(note: missing, busy: true),
      _RequestState.owned => const EditionRequestRow(note: _kOwnedElsewhere),
      _RequestState.following => const EditionRequestRow(note: _kRequested),
      _RequestState.joinable => EditionRequestRow(
        note: _kRequestedBySomeone,
        action: _kJoinRequest,
        busy: _submitting,
        onTap: () => _submitRequest(kind),
      ),
      _RequestState.fresh => EditionRequestRow(
        note: missing,
        action: _kRequest,
        busy: _submitting,
        onTap: () => _submitRequest(kind),
      ),
    };
  }

  @override
  void dispose() {
    PositionSyncController.release(_c);
    super.dispose();
  }

  void _openSync() => showPositionSyncSheet(
    context,
    _c,
    widget.accent,
    coverHeaders: context.read<LibraryProvider>().mediaHeaders,
    tint: widget.tint,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        if (!forkEditionsCardShows(_c)) return const SizedBox.shrink();
        final rows = workEditions(_c.snapshot);
        final gap = rows.where((r) => r.gap == WorkEditionGap.request).firstOrNull;
        final kind = gap == null ? null : requestMediaKind(gap.kind);
        if (_canRequest == true && kind != null && kind != _requestKind) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _requestKind != kind) _checkRequest(kind);
          });
        }
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ForkEditionsList(
            rows: rows,
            audioProgress: widget.progress,
            accent: widget.accent,
            buildProgress: _c.buttonProgress,
            onOpen: _openSync,
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
            download: _download,
            request: _requestRow,
            sync: _c.card,
            onSyncSwitch: (on) => _act(_c.setCardSync(on)),
            onSyncAction: (id) => _act(_c.runIndexAction(id)),
          ),
        );
      },
    );
  }

  /// The sheet toasts its own failures; with it closed the card does.
  Future<void> _act(Future<bool> action) async {
    final readAlong = _c.card?.readAlong == true;
    if (!await action && mounted && _c.onNotice == null) {
      showOverlayToast(
        context,
        readAlong ? PositionSyncCopy.toastReadAloudSyncFailed : PositionSyncCopy.toastEditionSyncFailed,
        icon: Icons.error_outline_rounded,
      );
    }
  }

  /// The audiobook downloads as the page's own button does. The Ebook row
  /// keeps the plain ebook and the Read-along row the read-along EPUB the
  /// reader opens beside the audiobook; each is its own copy on the phone.
  Widget? _download(WorkEdition r) {
    final plain = forkPlainEbookFile(widget.item);
    final readAlong = forkReadAlongFile(widget.item);
    Widget ebook(Map<String, dynamic> file, {bool readAlong = false}) => _compactIconButtons(
      context,
      _EbookDownloadButton(
        itemId: widget.itemId,
        api: widget.api,
        ebookFile: file,
        title: widget.title,
        accent: widget.accent,
        readAlong: readAlong,
      ),
    );
    return switch (r.kind) {
      SyncEdition.audiobook => _compactIconButtons(
        context,
        DownloadWideButton(
          itemId: widget.itemId,
          coverUrl: widget.coverUrl,
          title: widget.title,
          author: widget.author,
          accent: widget.accent,
          iconOnly: true,
        ),
      ),
      SyncEdition.ebook when plain != null => ebook(plain),
      SyncEdition.readAlong when r.edition != null && readAlong != null => ebook(readAlong, readAlong: true),
      _ => null,
    };
  }
}

/// Icon buttons sized to the row rather than the 48 px tap target.
Widget _compactIconButtons(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  return Theme(
    data: theme.copyWith(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(_kActionSlot),
          fixedSize: const Size.square(_kActionSlot),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    ),
    child: child,
  );
}

/// Keeps one of the book's ebook copies on the phone for offline reading, or
/// takes it off, showing which it is and the fetch while it runs: the plain
/// ebook (its own copy when the reader opens a read-along EPUB), or with
/// [readAlong] the read-along EPUB and its timings.
class _EbookDownloadButton extends StatefulWidget {
  final String itemId;
  final ApiService api;
  final Map<String, dynamic> ebookFile;
  final String title;
  final Color accent;
  final bool readAlong;

  const _EbookDownloadButton({
    required this.itemId,
    required this.api,
    required this.ebookFile,
    required this.title,
    required this.accent,
    this.readAlong = false,
  });

  @override
  State<_EbookDownloadButton> createState() => _EbookDownloadButtonState();
}

class _EbookDownloadButtonState extends State<_EbookDownloadButton> {
  final _dl = DownloadService();
  bool _saved = false;
  bool _busy = false;

  /// This book's download records when the cache was last looked at.
  /// Downloads notify on every progress tick, anywhere in the app, so the
  /// cache is looked at again only when these change.
  (bool, bool)? _records;

  @override
  void initState() {
    super.initState();
    _dl.addListener(_onDownloads);
    forkEbookCopiesChanged.addListener(_check);
    _check();
  }

  @override
  void didUpdateWidget(_EbookDownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ebookFile['ino'] != widget.ebookFile['ino'] ||
        oldWidget.ebookFile['version'] != widget.ebookFile['version']) {
      _check();
    }
  }

  @override
  void dispose() {
    _dl.removeListener(_onDownloads);
    forkEbookCopiesChanged.removeListener(_check);
    super.dispose();
  }

  void _onDownloads() {
    final records = (_dl.isDownloaded(widget.itemId), _dl.keptEbook(widget.itemId) != null);
    if (records != _records) _check();
  }

  /// Saved means this copy is on the phone, however it got there; the
  /// read-along only while it is the server's current one.
  Future<void> _check() async {
    _records = (_dl.isDownloaded(widget.itemId), _dl.keptEbook(widget.itemId) != null);
    final file = widget.ebookFile;
    final bool saved;
    if (widget.readAlong) {
      saved = await isEbookCached(widget.itemId, file) &&
          await cachedEbookIsCurrent(await ebookCacheFileFor(widget.itemId, file), file);
    } else if (forkIsPlainCopy(file)) {
      saved = await isEbookCached(widget.itemId, file);
    } else {
      saved = await cachedEbookFileFor(widget.itemId) != null;
    }
    if (mounted && saved != _saved) setState(() => _saved = saved);
  }

  Future<void> _download() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      if (forkIsPlainCopy(widget.ebookFile)) {
        await fetchEbookToCache(widget.api, widget.itemId, widget.ebookFile, widget.title);
      } else {
        await NarrationService.instance.readerFile(widget.api, widget.itemId, widget.ebookFile, widget.title);
      }
      // Read-along offline also needs its timings, which the reader keeps.
      // The plain ebook's come from the book's timing index, if it has one.
      if (widget.readAlong) {
        await NarrationService.instance.overlayFor(widget.api, widget.itemId);
      } else {
        unawaited(forkTimingIndexOverlay(widget.api, widget.itemId));
      }
      // As the reader does: an ebook-only book becomes a download, a book
      // with audio keeps the ebook beside it.
      final registered =
          !_dl.isDownloaded(widget.itemId) &&
          await _dl.registerEbookDownload(api: widget.api, itemId: widget.itemId, onlyIfNoAudio: true);
      if (!registered) await _dl.keepEbook(api: widget.api, itemId: widget.itemId);
      await _check();
      if (mounted) showOverlayToast(context, l.ebookSavedOffline, icon: Icons.download_done_rounded);
    } catch (_) {
      if (mounted) showOverlayToast(context, l.ebookOfflineFailed, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removeDownloadQuestion),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.remove, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // With two copies only this one goes; the kept record goes with the last.
    if (widget.readAlong || forkIsPlainCopy(widget.ebookFile)) {
      if (widget.readAlong) {
        await forkDeleteReaderCopy(widget.itemId, widget.ebookFile);
      } else {
        await forkDeletePlainCopyOnPhone(widget.itemId);
      }
      final left = await cachedEbookFileFor(widget.itemId) != null || await forkPlainCopyOnPhone(widget.itemId) != null;
      if (!left && _dl.keptEbook(widget.itemId) != null) await _dl.deleteEbookCopy(widget.itemId);
      await _check();
      if (mounted) showOverlayToast(context, l.ebookRemovedOffline, icon: Icons.delete_outline_rounded);
      return;
    }
    // An ebook-only book's download is the ebook itself; beside audio, only
    // the ebook copy goes.
    final onPhone = await _dl.onPhone(widget.itemId);
    if (_dl.isDownloaded(widget.itemId) && !onPhone.audio) {
      await _dl.deleteDownload(widget.itemId, byUser: true);
    } else {
      await _dl.deleteEbookCopy(widget.itemId);
    }
    await _check();
    if (mounted) showOverlayToast(context, l.ebookRemovedOffline, icon: Icons.delete_outline_rounded);
  }

  @override
  Widget build(BuildContext context) {
    if (context.watch<LibraryProvider>().isOffline && !_saved) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final green = dark ? Colors.greenAccent.withValues(alpha: 0.7) : Colors.green.shade700;
    return IconButton(
      tooltip: _saved ? _kEbookSaved : _kSaveEbook,
      onPressed: _busy ? null : (_saved ? _remove : _download),
      icon: _busy
          ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: widget.accent))
          : Icon(
              _saved ? Icons.download_done_rounded : Icons.download_outlined,
              size: 24,
              color: _saved ? green : null,
            ),
    );
  }
}

/// Whether the Editions card is showing rows for this book's sync state: it
/// draws nothing while loading or for a book holding no edition.
bool forkEditionsCardShows(PositionSyncController c) => c.loaded && workEditions(c.snapshot).isNotEmpty;

/// The card itself, apart from where its rows come from.
class ForkEditionsList extends StatelessWidget {
  final List<WorkEdition> rows;

  /// The page's progress (0..1), which the audiobook row shows.
  final double audioProgress;
  final Color accent;
  final double? buildProgress;

  /// Any row opens the Position sync sheet.
  final VoidCallback onOpen;

  /// Collapsed, the card is one line: an icon per edition and the total.
  final bool expanded;
  final VoidCallback onToggle;

  /// The download button at the end of an edition's row, or null for none.
  final Widget? Function(WorkEdition r)? download;

  /// What a request gap's row says and offers; without it the row only says
  /// the format is missing.
  final EditionRequestRow Function(WorkEdition r)? request;

  /// The book's sync (read-aloud sync or the timing index), in the open
  /// card's footer; null hides it.
  final EditionSyncCard? sync;
  final ValueChanged<bool>? onSyncSwitch;

  /// Run now or Retry indexing, from the status icon's menu.
  final ValueChanged<ChainActionId>? onSyncAction;

  const ForkEditionsList({
    super.key,
    required this.rows,
    required this.audioProgress,
    required this.accent,
    required this.onOpen,
    required this.onToggle,
    this.expanded = false,
    this.buildProgress,
    this.download,
    this.request,
    this.sync,
    this.onSyncSwitch,
    this.onSyncAction,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Each row's size needs about 300 px at normal text; below that it
      // stays in the header's total only.
      final roomy = box.maxWidth >= MediaQuery.textScalerOf(context).scale(300);
      return _EditionsReveal(expanded: expanded, builder: (context, m) => _card(context, roomy, m));
    },
  );

  Widget _card(BuildContext context, bool roomy, _Morph m) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final muted = cs.onSurfaceVariant;
    final books = rows.where((r) => r.edition != null).toList();
    final total = books.fold<int>(0, (sum, r) => sum + r.edition!.sizeBytes);
    final sync = this.sync;
    final headSync = sync != null && sync.status.tone != ChainTone.success ? sync : null;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(6, 8, 4, m.t > 0 ? 6 : 8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Stack(
        key: m.stackKey,
        clipBehavior: Clip.none,
        children: [
          Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, right: 4, top: 2, bottom: 2),
              child: Row(
                children: [
                  Flexible(
                    flex: roomy ? 0 : 1,
                    child: Text(
                      _kEditions.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall?.copyWith(color: muted, letterSpacing: 1, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 10),
                  for (final r in rows) Padding(padding: const EdgeInsets.only(right: 4), child: KeyedSubtree(
                            key: m.headKey(r.kind),
                            child: Opacity(opacity: m.showHead ? 1 : 0, child: _mark(context, r, label: false)),
                          ),
                        ),
                      const SizedBox(width: 4),
                      // Edition sync not in sync takes the total's place: its
                      // status while collapsed; open, the status and switch sit
                      // in the footer. In sync it says nothing here.
                      if (headSync != null && m.t == 0) ...[
                        Expanded(
                          child: Align(alignment: Alignment.centerRight, child: _syncStatus(context, headSync)),
                        ),
                        const SizedBox(width: 6),
                      ] else if (headSync != null)
                        const Spacer()
                      // Narrow or with large text the marks need the room.
                      else if (roomy)
                    Expanded(
                      child: Text(
                        total == 0 ? '${books.length}' : '${books.length} · ${formatSyncBytes(total)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: tt.labelSmall?.copyWith(color: muted),
                      ),
                    )
                  else
                    const Spacer(),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded, size: 20, color: muted),
                  ),
                ],
              ),
            ),
          ),
              // The rows unfold under the header as the marks grow into their
              // badges.
              if (m.t > 0)
                ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: m.c,
                    child: Opacity(
                      opacity: m.fade,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          for (final r in rows) r.edition != null ? _editionRow(context, r, roomy, m) : _gapRow(context, r, roomy, m),
                          if (sync != null) _syncFooter(context, sync),
        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (m.morphing)
            for (final r in rows)
              if (m.rect(r.kind) case final rect?)
                Positioned.fromRect(
                  rect: rect,
                  child: IgnorePointer(child: _morphMark(context, r, m.c)),
                ),
        ],
      ),
    );
  }

  /// Edition sync under the editions, where BookOrbit lists the files on
  /// disk: its name (with an icon for why, when there is one) over what it
  /// does (when on and in sync) or how it stands, which wraps rather than
  /// going when narrow, and the switch beside them.
  Widget _syncFooter(BuildContext context, EditionSyncCard i) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final status = i.status;
    const blurb = PositionSyncCopy.allEditionsKeepProgress;
    final synced = status.tone == ChainTone.success;
    final why = _syncWhyIcon(context, i);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 13, indent: 6, endIndent: 6, color: cs.onSurface.withValues(alpha: 0.08)),
        Padding(
          padding: const EdgeInsets.only(left: 6, right: 8),
          child: Row(
            children: [
              Expanded(
                child: _syncWhyMenu(
                  context,
                  i,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Set like the card's own EDITIONS heading.
                      Row(
                        children: [
                          Icon(Icons.sync_rounded, size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 5),
                          // The heading, then how it syncs: read-aloud
                          // or the timing index.
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: PositionSyncCopy.syncEditions.toUpperCase(),
                                    style: const TextStyle(letterSpacing: 1, fontWeight: FontWeight.w600),
                                  ),
                                  TextSpan(
                                    text: '  ${i.via}',
                                    style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                          if (why != null) why,
                        ],
                      ),
                      const SizedBox(height: 2),
                      // In sync it says what that means; otherwise how it
                      // stands (Off, queued, indexing, failed).
                      if (synced)
                        Text(
                          blurb,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        )
                      else
                        _syncStatus(context, i, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _syncSwitch(context, i, synced ? blurb : status.label),
            ],
          ),
        ),
      ],
    );
  }

  /// Edition sync's status in its tone, with a ring while the index is
  /// made.
  /// On and waiting reads in the switch's yellow; a failure stays red.
  ChainTone _cardTone(EditionSyncCard i) {
    final tone = i.status.tone;
    return i.on && tone != ChainTone.success && tone != ChainTone.destructive ? ChainTone.warning : tone;
  }

  Widget _syncStatus(BuildContext context, EditionSyncCard i, {TextStyle? style}) {
    final status = i.status;
    final tone = _syncTone(context, _cardTone(i));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status.state == ConnectorState.indexRunning) ...[
          SizedBox.square(
            dimension: 10,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: i.progress == null ? null : (i.progress! / 100).clamp(0.0, 1.0),
              color: tone,
            ),
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            status.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: (style ?? Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))?.copyWith(
              color: tone,
            ),
          ),
        ),
      ],
    );
  }

  /// The book's edition sync switch, full size with a full tap target; a
  /// screen reader hears how it stands with its name.
  /// Green when in sync; on but not yet in sync (timings still to make, out
  /// of date, failed, a pair that can't sync) yellow, with the line beside
  /// it saying why. Fixed colours, so a cover's accent can't make the two
  /// look alike.
  Widget _syncSwitch(BuildContext context, EditionSyncCard i, String state) {
    final track = syncToneColor(context, i.status.tone == ChainTone.success ? ChainTone.success : ChainTone.warning);
    return Semantics(
      label: PositionSyncCopy.syncEditions,
      value: state,
      child: Switch(
        value: i.on,
        activeTrackColor: track,
        // Black whether or not it can be flipped, so a flip going through
        // doesn't swap the thumb's colour.
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.black87 : null),
        onChanged: i.acting || onSyncSwitch == null ? null : onSyncSwitch,
      ),
    );
  }

  Color _syncTone(BuildContext context, ChainTone tone) =>
      tone == ChainTone.muted ? Theme.of(context).colorScheme.onSurfaceVariant : syncToneColor(context, tone);

  /// Why it is off, what it waits for or what went wrong, as an icon in its
  /// tone beside the heading; null when synced or there is nothing to say.
  Widget? _syncWhyIcon(BuildContext context, EditionSyncCard card) {
    final status = card.status;
    if (status.detail == null || status.tone == ChainTone.success) return null;
    final icon = switch (status.tone) {
      ChainTone.destructive => Icons.error_outline_rounded,
      ChainTone.warning => Icons.warning_amber_rounded,
      _ => Icons.info_outline_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Icon(icon, size: 16, color: _syncTone(context, _cardTone(card))),
    );
  }

  /// The heading and status, when there is a why, open the explanation with
  /// Run now or Retry indexing, as BookOrbit's header opens a dropdown; the
  /// whole block is the target, so it is large enough to tap.
  Widget _syncWhyMenu(BuildContext context, EditionSyncCard card, Widget child) {
    final status = card.status;
    final detail = status.detail;
    if (detail == null || status.tone == ChainTone.success) return child;
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<ChainActionId>(
      tooltip: detail,
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.padded),
      onSelected: (id) => onSyncAction?.call(id),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(detail, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface)),
        ),
        for (final a in status.actions)
          PopupMenuItem(
            value: a.id,
            enabled: !a.disabled && onSyncAction != null,
            child: Text(
              a.label,
              style: TextStyle(color: accent, fontWeight: FontWeight.w600),
            ),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Align(alignment: AlignmentDirectional.centerStart, child: child),
      ),
    );
  }

  /// One width for every badge, so the bars and gap notes line up.
  Widget _badgeSlot(BuildContext context, WorkEdition r, _Morph m) => SizedBox(
    width: MediaQuery.textScalerOf(context).scale(122).clamp(0, 140).toDouble(),
    child: Align(alignment: Alignment.centerLeft, child: KeyedSubtree(
        key: m.rowKey(r.kind),
        child: Opacity(opacity: m.showRow ? 1 : 0, child: _mark(context, r, label: true)),
      ),
    ),
  );

  /// How one edition is marked, as a round icon in the collapsed line or a
  /// labelled badge on its row: filled for one the book holds, dashed for a
  /// missing one.
  Widget _mark(BuildContext context, WorkEdition r, {required bool label}) {
    final fg = _markFg(context, r);
    final icon = Icon(syncEditionIcon(r.kind), size: label ? 14 : 13, color: fg);
    final content = label
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    editionShortName(r.kind),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
                  ),
                ),
              ],
            ),
          )
        : SizedBox.square(dimension: 22, child: Center(child: icon));
    final mark = _markShape(context, r, label ? 14.0 : 11.0, content);
    return label ? mark : Tooltip(message: editionShortName(r.kind), child: mark);
  }

  Color _markFg(BuildContext context, WorkEdition r) => r.gap != null
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : (Theme.of(context).brightness == Brightness.dark ? Colors.black87 : Colors.white);

  Widget _markShape(BuildContext context, WorkEdition r, double radius, Widget child) => r.gap != null
        ? CustomPaint(
            painter: WatchlistDashedBorder(color: Theme.of(context).colorScheme.outline, radius: radius, strokeWidth: 1),
            child: child,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: syncEditionColor(context, r.kind),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: child,
          );

  /// A header mark on its way to its row's badge, or back (`c` 0 to 1): the
  /// round icon stretches into the pill as the name fades in.
  Widget _morphMark(BuildContext context, WorkEdition r, double c) {
    final fg = _markFg(context, r);
    return _markShape(
      context,
      r,
      lerpDouble(11, 14, c)!,
      ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 0,
          maxWidth: double.infinity,
          child: Padding(
            padding: EdgeInsets.only(left: lerpDouble(4.5, 10, c)!),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(syncEditionIcon(r.kind), size: lerpDouble(13, 14, c), color: fg),
                SizedBox(width: 5 * c),
                Opacity(
                  opacity: const Interval(0.35, 1).transform(c),
                  child: Text(
                    editionShortName(r.kind),
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editionRow(BuildContext context, WorkEdition r, bool roomy, _Morph m) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final edition = r.edition!;
    final color = syncEditionColor(context, r.kind);
    final pct = r.kind == SyncEdition.audiobook ? (audioProgress * 100).round() : edition.progress;
    final size = roomy && edition.sizeBytes > 0 ? edition.sizeBytes : null;
    double scale(double w) => MediaQuery.textScalerOf(context).scale(w);
    final small = tt.labelMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          children: [
            _badgeSlot(context, r, m),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (pct ?? 0) / 100,
                  minHeight: 5,
                  color: color,
                  backgroundColor: cs.onSurface.withValues(alpha: 0.10),
                ),
              ),
            ),
            // Fixed slots for the figures, so every bar is one length and
            // the sizes start on one line.
            SizedBox(
              width: scale(40).clamp(0, 60).toDouble(),
              child: Text(pct == null ? '–' : '$pct%', textAlign: TextAlign.end, maxLines: 1, style: small),
            ),
            if (roomy) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: scale(64),
                child: Text(size == null ? '' : formatSyncBytes(size), maxLines: 1, style: small),
              ),
            ],
            // Every row keeps the slot, button or not, so the columns hold.
            const SizedBox(width: 4),
            SizedBox(
              width: _kActionSlot,
              child: Center(child: download?.call(r)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gapRow(BuildContext context, WorkEdition r, bool roomy, _Morph m) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    Widget spinner([double? value]) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(strokeWidth: 2, value: value, color: accent),
      ),
    );
    final String note;
    final Widget? trailing;
    switch (r.gap!) {
      case WorkEditionGap.generate:
        note = _kNotCreated;
        trailing = _pill(context, _kCreate, Icons.auto_awesome_rounded, onOpen);
      case WorkEditionGap.building:
        note = _kBuilding;
        trailing = spinner(buildProgress);
      case WorkEditionGap.request:
        final req =
            request?.call(r) ?? EditionRequestRow(note: r.kind == SyncEdition.audiobook ? _kNoAudiobook : _kNoEbook);
        note = req.note;
        trailing = req.action != null
            ? _pill(context, req.action!, Icons.auto_awesome_rounded, req.onTap, busy: req.busy)
            : (req.busy ? spinner() : null);
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      // A request row has only its button; the sync sheet has nothing on it.
      onTap: r.gap == WorkEditionGap.request ? null : onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          children: [
            _badgeSlot(context, r, m),
            const SizedBox(width: 10),
            // Narrow, the button alone says it.
            if (roomy || trailing == null)
              Expanded(
                child: Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              )
            else
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            if (roomy && trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  /// A row's action: a pill in the accent, like BookOrbit's Request button.
  Widget _pill(BuildContext context, String label, IconData icon, VoidCallback? onTap, {bool busy = false}) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null && !busy;
    return Material(
      color: accent.withValues(alpha: 0.12),
      shape: StadiumBorder(side: BorderSide(color: accent.withValues(alpha: 0.45))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                  : Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the editions' marks are while the card opens or closes: each round
/// header mark grows into its row's labelled badge, drawn over the card
/// between the two places they were last laid out.
class _Morph {
  /// How far open the card is, linear and eased.
  final double t, c;
  final Map<SyncEdition, Rect> from, to;
  final GlobalKey stackKey;
  final GlobalKey Function(SyncEdition kind) headKey, rowKey;

  const _Morph({
    required this.t,
    required this.c,
    required this.from,
    required this.to,
    required this.stackKey,
    required this.headKey,
    required this.rowKey,
  });

  /// Until both ends are measured (the first frame of opening) the marks
  /// just swap.
  bool get morphing => t > 0 && t < 1 && from.isNotEmpty && to.isNotEmpty;
  bool get showHead => !morphing && t < 0.5;
  bool get showRow => !morphing && t >= 0.5;

  /// The rows' own contents fade in behind the badges.
  double get fade => Curves.easeOut.transform(((t - 0.25) / 0.75).clamp(0.0, 1.0));

  Rect? rect(SyncEdition kind) {
    final a = from[kind], b = to[kind];
    return a == null || b == null ? null : Rect.lerp(a, b, c);
  }
}

/// Runs the card's open and close and measures where each mark sits at
/// either end, after every frame it is open at all.
class _EditionsReveal extends StatefulWidget {
  final bool expanded;
  final Widget Function(BuildContext context, _Morph m) builder;

  const _EditionsReveal({required this.expanded, required this.builder});

  @override
  State<_EditionsReveal> createState() => _EditionsRevealState();
}

class _EditionsRevealState extends State<_EditionsReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: widget.expanded ? 1 : 0,
  );
  final _stack = GlobalKey();
  final _head = <SyncEdition, GlobalKey>{};
  final _row = <SyncEdition, GlobalKey>{};
  final _from = <SyncEdition, Rect>{};
  final _to = <SyncEdition, Rect>{};

  @override
  void didUpdateWidget(_EditionsReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _anim.value = widget.expanded ? 1 : 0;
    } else {
      widget.expanded ? _anim.forward() : _anim.reverse();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final stack = _stack.currentContext?.findRenderObject();
    if (stack is! RenderBox || !stack.hasSize) return;
    void fill(Map<SyncEdition, GlobalKey> keys, Map<SyncEdition, Rect> out) {
      out.clear();
      for (final e in keys.entries) {
        final box = e.value.currentContext?.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) {
          out[e.key] = box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
        }
      }
    }

    fill(_head, _from);
    fill(_row, _to);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (context, _) {
      final t = _anim.value;
      if (t > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      } else {
        _to.clear();
      }
      return widget.builder(
        context,
        _Morph(
          t: t,
          c: Curves.easeInOutCubic.transform(t),
          from: Map.of(_from),
          to: Map.of(_to),
          stackKey: _stack,
          headKey: (k) => _head.putIfAbsent(k, GlobalKey.new),
          rowKey: (k) => _row.putIfAbsent(k, GlobalKey.new),
        ),
      );
    },
  );
}
