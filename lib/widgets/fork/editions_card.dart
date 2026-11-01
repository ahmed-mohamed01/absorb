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
import '../../services/fork/position_sync_chain.dart';
import '../../services/fork/position_sync_controller.dart';
import '../../services/fork/work_editions.dart';
import '../absorbing_shared.dart' show DownloadWideButton;
import '../overlay_toast.dart';
import 'position_sync_sheet.dart';
import 'watchlist_cover_badges.dart' show WatchlistDashedBorder;

// Fork-owned: the Editions card on a BookOrbit book page, listing the book's
// audiobook, read-aloud and ebook files from its position sync state. A row
// opens the Position sync sheet; a missing audiobook or ebook can be
// requested into this book. Hooked in from book_detail_redesign.dart.
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
  final Map<String, dynamic>? ebookFile;

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
    this.ebookFile,
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
        if (!_c.loaded) return const SizedBox.shrink();
        final rows = workEditions(_c.snapshot);
        if (rows.isEmpty) return const SizedBox.shrink();
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
          ),
        );
      },
    );
  }

  /// The audiobook downloads as the page's own button does; the ebook as the
  /// reader keeps it. The read-aloud EPUB has no download here yet: the
  /// ebook cache holds one EPUB per book.
  Widget? _download(WorkEdition r) => switch (r.kind) {
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
    SyncEdition.ebook when widget.ebookFile != null => _compactIconButtons(
      context,
      _EbookDownloadButton(
        itemId: widget.itemId,
        api: widget.api,
        ebookFile: widget.ebookFile!,
        title: widget.title,
        accent: widget.accent,
      ),
    ),
    _ => null,
  };
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

/// Keeps the book's ebook on the phone for offline reading, or takes it off,
/// showing which it is and the fetch while it runs.
class _EbookDownloadButton extends StatefulWidget {
  final String itemId;
  final ApiService api;
  final Map<String, dynamic> ebookFile;
  final String title;
  final Color accent;

  const _EbookDownloadButton({
    required this.itemId,
    required this.api,
    required this.ebookFile,
    required this.title,
    required this.accent,
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
    _check();
  }

  @override
  void dispose() {
    _dl.removeListener(_onDownloads);
    super.dispose();
  }

  void _onDownloads() {
    final records = (_dl.isDownloaded(widget.itemId), _dl.keptEbook(widget.itemId) != null);
    if (records != _records) _check();
  }

  /// Saved means the file is in the reader's cache, however it got there.
  Future<void> _check() async {
    _records = (_dl.isDownloaded(widget.itemId), _dl.keptEbook(widget.itemId) != null);
    final saved = await cachedEbookFileFor(widget.itemId) != null;
    if (mounted && saved != _saved) setState(() => _saved = saved);
  }

  Future<void> _download() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      await NarrationService.instance.readerFile(widget.api, widget.itemId, widget.ebookFile, widget.title);
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
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Each row's size needs about 300 px at normal text; below that it
      // stays in the header's total only.
      final roomy = box.maxWidth >= MediaQuery.textScalerOf(context).scale(300);
      return _card(context, roomy);
    },
  );

  Widget _card(BuildContext context, bool roomy) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final muted = cs.onSurfaceVariant;
    final books = rows.where((r) => r.edition != null).toList();
    final total = books.fold<int>(0, (sum, r) => sum + r.edition!.sizeBytes);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(6, 8, 4, expanded ? 6 : 8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
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
                  for (final r in rows) Padding(padding: const EdgeInsets.only(right: 4), child: _mark(context, r, label: false)),
                  const SizedBox(width: 4),
                  // Narrow or with large text the marks need the room.
                  if (roomy)
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
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded, size: 20, color: muted),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) const SizedBox(height: 4),
          if (expanded)
            for (final r in rows) r.edition != null ? _editionRow(context, r, roomy) : _gapRow(context, r, roomy),
        ],
      ),
    );
  }

  /// One width for every badge, so the bars and gap notes line up.
  Widget _badgeSlot(BuildContext context, WorkEdition r) => SizedBox(
    width: MediaQuery.textScalerOf(context).scale(122).clamp(0, 140).toDouble(),
    child: Align(alignment: Alignment.centerLeft, child: _mark(context, r, label: true)),
  );

  /// How one edition is marked, as a round icon in the collapsed line or a
  /// labelled badge on its row: filled for one the book holds, dashed for a
  /// missing one.
  Widget _mark(BuildContext context, WorkEdition r, {required bool label}) {
    final color = syncEditionColor(context, r.kind);
    final fg = r.gap != null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : (Theme.of(context).brightness == Brightness.dark ? Colors.black87 : Colors.white);
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
    final radius = label ? 14.0 : 11.0;
    final mark = r.gap != null
        ? CustomPaint(
            painter: WatchlistDashedBorder(color: Theme.of(context).colorScheme.outline, radius: radius, strokeWidth: 1),
            child: content,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: content,
          );
    return label ? mark : Tooltip(message: editionShortName(r.kind), child: mark);
  }

  Widget _editionRow(BuildContext context, WorkEdition r, bool roomy) {
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            _badgeSlot(context, r),
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

  Widget _gapRow(BuildContext context, WorkEdition r, bool roomy) {
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            _badgeSlot(context, r),
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
