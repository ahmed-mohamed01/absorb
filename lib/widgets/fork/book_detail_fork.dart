// ignore_for_file: invalid_use_of_protected_member
part of '../book_detail_sheet.dart';

// Fork-owned: the BookOrbit book detail layout (header, main and secondary
// actions, icon row, tag chips). book_detail_sheet.dart only calls these.
// See FORK_NOTES.md.
const _forkTagChipLimit = 5;

/// flutter_svg caches a picture by its loader, and `mediaHeaders` is a new map
/// on every read, so a loader made per build fetched the provider icons again
/// on every open. One loader per icon URL (a handful of providers) keeps them
/// cached; the headers it was made with only matter for its first fetch.
final _forkProviderIconLoaders = <String, SvgNetworkLoader>{};

SvgNetworkLoader _forkProviderIconLoader(String url, Map<String, String> headers) =>
    _forkProviderIconLoaders.putIfAbsent(url, () => SvgNetworkLoader(url, headers: headers));

/// Releases the sync state each open sheet started loading, run when it closes.
final _forkSyncPrefetch = Expando<VoidCallback>();

/// The item each open sheet was seeded with, until `_loadItem` replaces it.
final _forkSeeds = Expando<Map<String, dynamic>>();

extension _ForkBookDetail on _BookDetailSheetContentState {
  void _forkPrefetchSync() {
    final release = prefetchPositionSync(context.read<AuthProvider>(), context.read<LibraryProvider>(), widget.itemId);
    if (release != null) _forkSyncPrefetch[this] = release;
  }

  void _forkReleaseSync() => _forkSyncPrefetch[this]?.call();

  /// Paints the sheet at once from what the app already holds for this book
  /// (its full detail if any Home card fetched it, else the last card built
  /// for it); `_loadItem` then refreshes it behind. BookOrbit only, and not
  /// offline, where `_loadItem` only has the downloads to answer from.
  void _forkSeedItem() {
    if (widget.initialItem != null || _item != null) return;
    final bookOrbit = context.read<AuthProvider>().isBookOrbit;
    final offline = context.read<LibraryProvider>().isOffline;
    if (!bookOrbit || offline) {
      if (forkTraceRequests) debugPrint('[BookDetail] no seed for ${widget.itemId}: bookOrbit=$bookOrbit offline=$offline');
      return;
    }
    final seed = forkCachedBookOrbitItem(widget.itemId);
    if (seed == null) return;
    _item = seed;
    _isLoading = false;
    _forkSeeds[this] = seed;
    debugPrint('[BookDetail] sheet seeded from cache item=${widget.itemId}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _deriveCoverScheme();
    });
  }

  /// `_loadItem` found nothing (server unreachable, book gone, no download):
  /// a seed it never replaced comes down, so the sheet shows the failure
  /// instead of a stale book with dead buttons.
  void _forkSeedFailed() {
    final seed = _forkSeeds[this];
    if (seed == null || !identical(_item, seed) || !mounted) return;
    _forkSeeds[this] = null;
    setState(() => _item = null);
  }

  /// The card's thumbnail URL on BookOrbit (already in the image cache from
  /// the shelf), which gives the same accent as the full cover and shows at
  /// once under the header cover while that one loads.
  String? get _forkPaletteUrl {
    if (!context.read<AuthProvider>().isBookOrbit) return null;
    if ((_item?['_localCoverUrl'] as String?)?.isNotEmpty ?? false) return null;
    final coverPath = (_item?['media'] as Map?)?['coverPath'] as String?;
    if (coverPath == null || coverPath.isEmpty) return null;
    return context.read<LibraryProvider>().getCoverUrl(widget.itemId, coverRatio: _itemFrame);
  }

  Widget _forkCoverPlaceholder(LibraryProvider lib) {
    final url = _forkPaletteUrl;
    if (url == null) return const SizedBox();
    return CachedNetworkImage(
      imageUrl: url, fit: BoxFit.contain,
      httpHeaders: lib.mediaHeaders,
      placeholder: (_, __) => const SizedBox(),
      errorWidget: (_, __, ___) => const SizedBox(),
    );
  }

  /// A skeleton in the layout's own shape for the opens nothing is cached
  /// for, so the content lands in place instead of replacing a spinner.
  Widget _forkLoadingBody(ColorScheme cs) {
    final tone = cs.onSurface.withValues(alpha: 0.06);
    Widget box(double w, double h, {double r = 8}) => Container(
          width: w, height: h,
          decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(r)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          box(_squareCovers ? 170 : 170 * 2 / 3, 170, r: 12),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 6),
            box(double.infinity, 22),
            const SizedBox(height: 10),
            box(140, 16),
            const SizedBox(height: 18),
            box(100, 14),
            const SizedBox(height: 8),
            box(120, 14),
          ])),
        ]),
        const SizedBox(height: 20),
        box(double.infinity, 52, r: 16),
        const SizedBox(height: 12),
        box(double.infinity, 44, r: 16),
        const SizedBox(height: 24),
        for (final w in [double.infinity, double.infinity, 220.0]) ...[box(w, 14), const SizedBox(height: 8)],
      ]),
    );
  }

  ({Widget primary, Widget? secondary}) _forkActionButtons({
    required BuildContext context,
    required ColorScheme cs,
    required TextTheme tt,
    required AppLocalizations l,
    required Color accent,
    required LibraryProvider lib,
    required AuthProvider auth,
    required dynamic ebookFile,
    required bool isEbookOnly,
    required bool textPrimary,
    required double progress,
    required bool isFinished,
    required double duration,
    required List<dynamic> chapters,
    required String title,
    required String authorName,
    required Map<String, dynamic> media,
  }) {
    final Widget primaryButton = _lookingForNarration
        ? _lookingButton(accent, _coverScheme?.onPrimary ?? cs.onPrimary)
        : (textPrimary && ebookFile != null && canReadEbook(ebookFile))
        ?
        // Reading progress fills the button the same way listening progress
        // fills Absorb.
        Builder(builder: (context) {
          final onAccent = _coverScheme?.onPrimary ?? cs.onPrimary;
          // A library refresh on BookOrbit carries an ebook-only book's
          // reading percent as its plain progress, with no ebook field.
          final saved = lib.getEbookProgress(widget.itemId);
          final ebookProgress = saved > 0 || !isEbookOnly ? saved : progress;
          final showFill = ebookProgress > 0 && ebookProgress < 1 && !isFinished;
          return SizedBox(
            height: 52,
            child: Material(
              color: accent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openEbookReader(context, auth, ebookFile, title),
                child: Stack(children: [
                  if (showFill)
                    FractionallySizedBox(
                      widthFactor: ebookProgress.clamp(0.0, 1.0),
                      child: Container(color: onAccent.withValues(alpha: 0.22)),
                    ),
                  Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.menu_book_rounded, size: 24, color: onAccent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(l.readEbook,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: onAccent)),
                      ),
                    ]),
                  ),
                  if (showFill)
                    Positioned(
                      right: 14,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Text(
                          '${(ebookProgress * 100).toStringAsFixed(0)}%',
                          style: tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: onAccent.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          );
        })
        : (isEbookOnly && ebookFile != null)
        ?
        // Ebook-only but not readable in-app (CBR) - can't open it, so the
        // primary action exports the file to the device instead.
        SizedBox(height: 52, child: FilledButton.icon(
          onPressed: () => _saveEbook(context, auth, ebookFile, title),
          icon: Icon(_ebookSaved ? Icons.download_done_rounded : Icons.save_alt_rounded, size: 24),
          label: Text(l.ebookSaveToDevice,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onPrimary)),
          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        ))
        : isEbookOnly
        ?
        SizedBox(height: 52, child: FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.menu_book_rounded, size: 24),
          label: Text(l.ebookOnlyNoAudio,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        ))
        :
      SizedBox(
        height: 52,
        child: ListenableBuilder(
          listenable: Listenable.merge([AudioPlayerService(), DownloadService()]),
          builder: (_, __) {
            final player = AudioPlayerService();
            final isCurrentPlaying =
                player.currentItemId == widget.itemId && player.isPlaying;
            final showAbsorbingState = _isAbsorbing || isCurrentPlaying;
            final onAccent = _coverScheme?.onPrimary ?? cs.onPrimary;
            final needsDownload = !showAbsorbingState && _needsNarrationDownload(auth);
            final fetching = needsDownload && DownloadService().isDownloading(widget.itemId);
            // How far into the book you are fills the button from the left,
            // the way the download button fills while it fetches. A narration
            // on its way down fills with the download instead.
            final fill = fetching ? DownloadService().downloadProgress(widget.itemId) : progress;
            final showFill = fetching || (!needsDownload && progress > 0 && !isFinished);
            // Offline with nothing to play: only the ebook may be on the
            // phone, and the Read button below still works.
            if (lib.isOffline &&
                !showAbsorbingState &&
                !DownloadService().isDownloaded(widget.itemId)) {
              return Material(
                color: accent.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.cloud_off_rounded, size: 22, color: onAccent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        ebookFile != null && canReadEbook(ebookFile)
                            ? l.absorbAudioNotDownloadedEbookOnly
                            : l.absorbAudioNotDownloaded,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600, color: onAccent),
                      ),
                    ),
                  ]),
                ),
              );
            }

            return Material(
              color: accent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: showAbsorbingState
                    ? () async {
                        if (isCurrentPlaying) {
                          final lib = context.read<LibraryProvider>();
                          await _activateQueueSource();
                          unawaited(lib.syncQueueAutoDownloads());
                        }
                        if (!context.mounted) return;
                        Navigator.of(context).popUntil((route) => route.isFirst);
                        AppShell.goToAbsorbingGlobal();
                      }
                    : () {
                        setState(() => _isAbsorbing = true);
                        _startAbsorb(
                          context,
                          auth: auth,
                          title: title,
                          author: authorName,
                          coverUrl: _coverUrl,
                          duration: duration,
                          chapters: chapters,
                        );
                      },
                child: Stack(children: [
                  if (showFill)
                    FractionallySizedBox(
                      widthFactor: fill.clamp(0.0, 1.0),
                      child: Container(color: onAccent.withValues(alpha: 0.22)),
                    ),
                  Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      showAbsorbingState
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: AbsorbingWave(color: onAccent),
                            )
                          : needsDownload
                              ? Icon(Icons.download_rounded, size: 24, color: onAccent)
                              : isFinished
                                  ? AbsorbReplayIcon(size: 24, color: onAccent)
                                  : Icon(Icons.waves_rounded, size: 24, color: onAccent),
                      const SizedBox(width: 8),
                      Flexible(child: Text(
                        showAbsorbingState
                            ? Wording.of(context).absorbing
                            : fetching
                                ? l.downloadsDownloading
                                : needsDownload
                                    ? Wording.of(context).downloadToAbsorb
                                    : isFinished
                                        ? Wording.of(context).absorbAgain
                                        : Wording.of(context).absorb,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600, color: onAccent),
                      )),
                    ]),
                  ),
                  if (showFill)
                    Positioned(
                      right: 14,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Text(
                          '${(fill * 100).toStringAsFixed(0)}%',
                          style: tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: onAccent.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            );
          },
        ),
      );

    void startListening() {
      setState(() => _isAbsorbing = true);
      _startAbsorb(context, auth: auth, title: title, author: authorName, coverUrl: _coverUrl, duration: duration, chapters: chapters);
    }
    final ebookProgressNow = lib.getEbookProgress(widget.itemId);
    final Widget? secondaryButton = _lookingForNarration
        ? null
        : textPrimary
            ? (media['narration'] != null && !isEbookOnly
                ? _secondaryIconButton(accent, Icons.headphones_rounded,
                    lib.isOffline && !DownloadService().isDownloaded(widget.itemId) ? null : startListening,
                    progress: progress, tooltip: Wording.of(context).absorb)
                : null)
            : (ebookFile != null && canReadEbook(ebookFile)
                ? _secondaryIconButton(accent, Icons.menu_book_rounded, () => _openEbookReader(context, auth, ebookFile, title),
                    progress: ebookProgressNow, tooltip: l.readEbook)
                : null);
    return (primary: primaryButton, secondary: secondaryButton);
  }

  Widget _forkDetailHeader({
    required BuildContext context,
    required ColorScheme cs,
    required TextTheme tt,
    required AppLocalizations l,
    required Color accent,
    required LibraryProvider lib,
    required AuthProvider auth,
    required String title,
    required String subtitle,
    required Map<String, dynamic> metadata,
    required List<dynamic> seriesEntries,
    required double headerProgress,
    required bool isFinished,
    required bool bookOrbitOnline,
    required String readStatus,
  }) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_coverUrl != null) ...[
        GestureDetector(
          onTap: () => _showFullCover(context, _fullResCoverUrl ?? _coverUrl!, lib.mediaHeaders, title),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 170),
            height: 170,
            width: _squareCovers ? 170 : 170 * 2 / 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 4))],
            ),
            clipBehavior: Clip.antiAlias,
            child: _squareCovers
                ? (_coverUrl!.startsWith('/')
                    ? BlurPaddedCover(
                        blurChild: Image.file(File(_coverUrl!), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                        child: Image.file(File(_coverUrl!), fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox()),
                      )
                    : BlurPaddedCover(
                        blurChild: CachedNetworkImage(
                          imageUrl: _coverUrl!, fit: BoxFit.cover,
                          httpHeaders: lib.mediaHeaders,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                        child: CachedNetworkImage(
                          imageUrl: _coverUrl!, fit: BoxFit.contain,
                          httpHeaders: lib.mediaHeaders,
                          placeholder: (_, __) => _forkCoverPlaceholder(lib),
                          errorWidget: (_, __, ___) => const SizedBox(),
                        ),
                      ))
                : CachedNetworkImage(
                    imageUrl: _coverUrl!, fit: BoxFit.contain,
                    httpHeaders: lib.mediaHeaders,
                    placeholder: (_, __) => _forkCoverPlaceholder(lib),
                    errorWidget: (_, __, ___) => const SizedBox(),
                  ),
          ),
        ),
        const SizedBox(width: 16),
      ],
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)),
      if (subtitle.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
      const SizedBox(height: 2),
      _buildAuthorLinks(context, metadata, cs, tt, accent),
      _buildNarratorLinks(context, metadata, cs, tt, accent),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 6, children: [
        if (headerProgress > 0 && !isFinished)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
            child: Text('${(headerProgress * 100).round()}%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent)),
          ),
        if (bookOrbitOnline)
          _chip(
            _BookDetailSheetContentState._readStatusIcon(readStatus),
            _BookDetailSheetContentState._readStatusLabel(l, readStatus),
            onTap: _savingStatus ? null : () => _pickReadStatus(auth, lib, readStatus),
          ),
      ]),
      // Series as a pill in the rating's style: a bounded target with its
      // own edges, so it can't be mistaken for the narrator line above it.
      if (seriesEntries.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.start,
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final s in seriesEntries)
              GestureDetector(
                onTap: () => _openSeries(context, s['id'] as String?, s['name'] as String? ?? ''),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withValues(alpha: 0.18)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_stories_rounded, size: 14, color: accent),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${s['name'] as String? ?? ''}'
                        '${(s['sequence'] as String? ?? '').isNotEmpty ? ' #${s['sequence']}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 16, color: accent.withValues(alpha: 0.6)),
                  ]),
                ),
              ),
          ],
        ),
      ],
      ])),
      ]);
  }

  Widget _forkIconRow({
    required BuildContext context,
    required ColorScheme cs,
    required AppLocalizations l,
    required Color accent,
    required LibraryProvider lib,
    required AuthProvider auth,
    required String title,
    required String authorName,
    required bool isEbookOnly,
    required dynamic ebookFile,
    required bool showPreview,
    required List<dynamic> chapters,
    required double duration,
    required double progress,
    required bool isFinished,
    required double currentTime,
  }) {
    return Row(children: [
        if (!isEbookOnly)
          Expanded(child: DownloadWideButton(itemId: widget.itemId, coverUrl: _coverUrl, title: title, author: authorName, accent: accent, compact: true))
        else if (!_lookingForNarration && ebookFile != null && canReadEbook(ebookFile))
          Expanded(child: ListenableBuilder(
            listenable: DownloadService(),
            builder: (_, __) {
              final saved = DownloadService().isDownloaded(widget.itemId);
              final dlGreen = Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent : Colors.green.shade700;
              return _iconAction(cs, saved ? Icons.download_done_rounded : Icons.download_rounded,
                  _ebookOfflineDownloading
                      ? null
                      : (saved ? () => _removeEbookOffline(context) : () => _downloadEbookOffline(context, auth, ebookFile, title)),
                  color: saved ? dlGreen : null, busy: _ebookOfflineDownloading,
                  tooltip: saved ? l.saved : l.ebookDownload);
            },
          )),
        if (showPreview) ...[
          const SizedBox(width: 8),
          Expanded(child: _iconAction(cs,
              (_preview?.isPlaying ?? false) ? Icons.stop_rounded : Icons.headphones_rounded,
              () => _togglePreview(context, chapters, duration),
              busy: _preview?.isLoading ?? false,
              tooltip: (_preview?.isPlaying ?? false) ? l.chapterStopPreview : l.preview)),
        ],
        const SizedBox(width: 8),
        Expanded(child: _iconAction(cs,
            isFinished ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
            () => isFinished ? _markNotFinished(context, auth, currentTime, duration) : _markFinished(context, auth, duration),
            color: isFinished ? Colors.green : null,
            tooltip: isFinished ? Wording.of(context).fullyAbsorbed : Wording.of(context).fullyAbsorbAction)),
        // Takes its own slot and gap, and gives them up for a book with
        // nothing to link.
        if (ForkSyncButton.shouldShow(auth, lib, widget.itemId))
          ForkSyncButton(
            key: ValueKey('fork-sync-${widget.itemId}'),
            itemId: widget.itemId, accent: accent, api: auth.apiService as BookOrbitApiService,
            title: title, authorName: authorName,
          ),
        const SizedBox(width: 8),
        Expanded(child: _iconAction(cs, Icons.more_horiz_rounded,
            () => _showMoreSheet(context, auth, lib, title, authorName, progress, isFinished, duration, ebookFile, isEbookOnly),
            tooltip: l.moreActions)),
      ]);
  }

  List<Widget> _forkTagChips(BuildContext context, AppLocalizations l, List<(String, bool)> labels) {
    return [
        for (final entry in labels.take(_tagsExpanded ? labels.length : _forkTagChipLimit))
          _chip(
            entry.$2 ? Icons.tag_rounded : Icons.local_offer_outlined,
            entry.$1,
            onTap: () {
              Navigator.of(context).pop();
              if (entry.$2) {
                AppShell.openLibraryWithGenreFilterGlobal(entry.$1);
              } else {
                AppShell.openLibraryWithTagFilterGlobal(entry.$1);
              }
            },
          ),
        if (labels.length > _forkTagChipLimit)
          _chip(
            _tagsExpanded ? Icons.expand_less_rounded : Icons.add_rounded,
            _tagsExpanded ? l.showLess : '${labels.length - _forkTagChipLimit}',
            onTap: () => setState(() => _tagsExpanded = !_tagsExpanded),
          ),
    ];
  }

  double? get _itemFrame {
    final f = (_item?['media'] as Map?)?['coverAspectRatio'];
    return f is num ? f.toDouble() : null;
  }

  Widget _secondaryIconButton(Color accent, IconData icon, VoidCallback? onTap, {double progress = 0, String? tooltip}) {
    final showFill = progress > 0 && progress < 1;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip ?? '',
      child: SizedBox(
      width: 56,
      height: 52,
      child: Material(
        color: accent.withValues(alpha: enabled ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(alignment: Alignment.center, children: [
            if (showFill)
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(height: 3, color: accent),
                ),
              ),
            Icon(icon, size: 24, color: enabled ? accent : accent.withValues(alpha: 0.4)),
          ]),
        ),
      ),
    ));
  }

  Widget _iconAction(ColorScheme cs, IconData icon, VoidCallback? onTap, {Color? color, bool busy = false, String? tooltip}) {
    final fg = color ?? cs.onSurfaceVariant;
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: (color ?? cs.onSurface).withValues(alpha: color == null ? 0.06 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: (color ?? cs.onSurface).withValues(alpha: color == null ? 0.08 : 0.2)),
        ),
        child: Center(
          child: busy
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              : Icon(icon, size: 20, color: fg),
        ),
      ),
    ));
  }
}
