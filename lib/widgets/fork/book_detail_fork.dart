// ignore_for_file: invalid_use_of_protected_member
part of '../book_detail_sheet.dart';

// Fork-owned: the BookOrbit book detail pieces the redesigned page
// (book_detail_redesign.dart) and the sheet's own hooks call: the seed and
// skeleton, the sync prefetch, and the main and secondary buttons.
// See FORK_NOTES.md.

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
          box(_squareCovers ? 140 : 112, _squareCovers ? 140 : 168, r: 12),
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
    // An audiobook with its own ebook: the buttons say Listen and Read, and
    // [textPrimary] says which of them is the main one.
    bool dualCovers = false,
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
          // A narrated EPUB keeps its place as the book's own progress, often
          // with no separate ebook position, so the further of the two shows.
          // A book with its own audiobook keeps listening there, so its Read
          // button shows the reading alone.
          final saved = lib.getEbookProgress(widget.itemId);
          final ebookProgress = dualCovers || saved > progress ? saved : progress;
          // Under half a percent would read "0%", so it waits for 1%.
          final showFill = ebookProgress >= 0.005 && ebookProgress < 1 && !isFinished;
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
            final showFill = fetching || (!needsDownload && progress >= 0.005 && !isFinished);
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
                                  : Icon(dualCovers ? Icons.headphones_rounded : Icons.waves_rounded, size: 24, color: onAccent),
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
                                        : dualCovers
                                            ? _kListen
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
            ? ((media['narration'] != null || dualCovers) && !isEbookOnly
                ? _secondaryIconButton(accent, Icons.headphones_rounded,
                    lib.isOffline && !DownloadService().isDownloaded(widget.itemId) ? null : startListening,
                    progress: progress, tooltip: dualCovers ? _kListen : Wording.of(context).absorb)
                : null)
            : (ebookFile != null && canReadEbook(ebookFile)
                ? _secondaryIconButton(accent, Icons.menu_book_rounded, () => _openEbookReader(context, auth, ebookFile, title),
                    progress: ebookProgressNow, tooltip: l.readEbook)
                : null);
    return (primary: primaryButton, secondary: secondaryButton);
  }

  double? get _itemFrame => forkBookFrame(_item);

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

}
