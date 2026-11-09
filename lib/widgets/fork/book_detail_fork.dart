// ignore_for_file: invalid_use_of_protected_member
part of '../book_detail_sheet.dart';

// Fork-owned: the BookOrbit book detail pieces the redesigned page
// (book_detail_redesign.dart) and the sheet's own hooks call: the seed and
// skeleton, the sync prefetch, and the main and secondary buttons.
// See FORK_NOTES.md.

/// Releases the sync state each open sheet started loading, run when it closes.
final _forkSyncPrefetch = Expando<VoidCallback>();

/// The sync state each open sheet holds, which the Editions card draws from.
final _forkSyncControllers = Expando<PositionSyncController>();

/// The book sheet's slide: longer than the default 250 ms, so more frames
/// carry it, and easing into place. Closing is quicker.
const _forkBookSheetMotion = AnimationStyle(
  curve: Cubic(0.05, 0.7, 0.1, 1),
  duration: Duration(milliseconds: 400),
  reverseDuration: Duration(milliseconds: 280),
);

/// How long a tap waits for a book before its sheet slides up anyway.
const _forkOpenWait = Duration(milliseconds: 300);

/// The book the latest tap is getting ready: a second tap on it doesn't open
/// it twice, and a tap on another book replaces it.
String? _forkBookOpening;

/// Each cover's accent by its url: palette work done once, and a sheet wears
/// the colour from its first frame.
final _forkCoverAccents = <String, Color>{};

/// Opens a book's sheet once it's ready, or at [_forkOpenWait]. A caller may
/// pop its own route straight after the tap, so the root navigator opens it
/// when [context] has gone.
void _forkOpenWhenReady(BuildContext context, String itemId, void Function(BuildContext) open) {
  if (_forkBookOpening == itemId) return;
  final ready = _forkPrepareBookSheet(context, itemId);
  if (ready == null) {
    _forkBookOpening = null;
    open(context);
    return;
  }
  _forkBookOpening = itemId;
  ready.whenComplete(() {
    if (_forkBookOpening != itemId) return;
    _forkBookOpening = null;
    final from = context.mounted ? context : rootNavigatorKey.currentContext;
    if (from != null) open(from);
  });
}

/// [work], given up on after [cap].
Future<void> _forkWaitAtMost(List<Future<void>> work, Duration cap) =>
    Future.wait(work).then<void>((_) {}).timeout(cap, onTimeout: () {});

/// Loads everything a BookOrbit book's sheet shows before it opens: the sync
/// data together, the cover decoded and its colour worked out. Null when
/// there is nothing to wait for; otherwise done within [_forkOpenWait].
Future<void>? _forkPrepareBookSheet(BuildContext context, String itemId) {
  final auth = context.read<AuthProvider>();
  final lib = context.read<LibraryProvider>();
  final sync = prefetchPositionSync(auth, lib, itemId);
  if (sync == null) return null;
  final api = auth.apiService as BookOrbitApiService;
  unawaited(sync.controller.loadInitial());
  final stats = BookStatsService.instance.stats(itemId);
  if (!ApiService.isWatchlistItem(itemId)) {
    unawaited(BookStatsService.instance.ensureLoaded(itemId, api, isAdmin: auth.isAdmin));
  }

  ImageProvider cover(String url) => CachedNetworkImageProvider(url, headers: lib.mediaHeaders);

  Future<void> warm(String url) async {
    if (!context.mounted) return;
    await precacheImage(cover(url), context, onError: (_, __) {});
  }

  // Only this cover colours the sheet.
  Future<void> warmWithAccent(String url) async {
    await warm(url);
    if (_forkCoverAccents.containsKey(url)) return;
    final accent = await coverAccentOffThread(cover(url));
    if (accent != null) _forkCoverAccents[url] = accent;
  }

  Future<void> covers() async {
    // A list screen's card knows the cover; without one, the detail does.
    var item = forkCachedBookOrbitItem(itemId);
    if (item == null) {
      await sync.controller.whenLoaded;
      item = forkCachedBookOrbitItem(itemId);
    }
    if (item == null) return;
    await Future.wait([
      if (lib.getCoverUrl(itemId, coverRatio: forkBookFrame(item)) case final url?) warmWithAccent(url),
      if (forkHasBothCovers(item)) ...[
        warm(api.getCoverUrl(itemId, width: 400, coverSlot: 'audio')),
        warm(api.getCoverUrl(itemId, width: 400, coverSlot: 'ebook')),
      ],
    ]);
  }

  final coverWork = covers().catchError((Object e) => debugPrint('[BookDetail] preparing $itemId: $e'));
  _forkCoversWarming[itemId] = coverWork;
  unawaited(coverWork.whenComplete(() {
    if (identical(_forkCoversWarming[itemId], coverWork)) _forkCoversWarming.remove(itemId);
  }));

  return _forkWaitAtMost([sync.controller.whenLoaded, stats.whenOwnReady, coverWork], _forkOpenWait)
      // The sheet holds the controller from its first frame.
      .whenComplete(() => Timer(const Duration(seconds: 2), sync.release));
}

/// Open sheets still waiting on their data, for at most [_forkHoldCap]: past
/// that a slow server gets the page with what has arrived.
final _forkHolding = Expando<bool>();
const _forkHoldCap = Duration(seconds: 3);

/// Books whose covers and colour are still being worked out for their sheet.
final _forkCoversWarming = <String, Future<void>>{};

/// The item each open sheet was seeded with, until `_loadItem` replaces it.
final _forkSeeds = Expando<Map<String, dynamic>>();

extension _ForkBookDetail on _BookDetailSheetContentState {
  /// Also keeps the page and the sync state in step: a read-aloud the
  /// controller saw finish reloads the item, and progress changed on the page
  /// (a reset, a status) reloads the files' positions.
  void _forkPrefetchSync() {
    final lib = context.read<LibraryProvider>();
    final sync = prefetchPositionSync(context.read<AuthProvider>(), lib, widget.itemId);
    if (sync == null) return;
    final c = sync.controller;
    void onFiles() => _filesChanged();
    // The sheet holds its content until everything it shows has arrived.
    final stats = BookStatsService.instance.stats(widget.itemId);
    final noStats = ApiService.isWatchlistItem(widget.itemId);
    final covers = _forkCoversWarming[widget.itemId];
    if (!c.loaded || (!noStats && !stats.ownReady) || covers != null) {
      _forkHolding[this] = true;
      _forkWaitAtMost([c.whenLoaded, if (!noStats) stats.whenOwnReady, ?covers], _forkHoldCap).whenComplete(() {
        _forkHolding[this] = false;
        if (!mounted) return;
        setState(() {
          // A seed `_forkSeedFailed` took down stays down.
          final seed = _forkSeeds[this];
          final detail = seed != null && identical(_item, seed) ? forkCachedBookOrbitItem(widget.itemId) : null;
          if (detail != null) {
            _item = detail;
            _forkSeeds[this] = detail;
          }
        });
      });
    }
    (bool, Object?) progressKey() {
      final p = lib.getProgressData(widget.itemId);
      return (p == null, p?['isFinished']);
    }
    var lastProgress = progressKey();
    void onLibrary() {
      final now = progressKey();
      if (now == lastProgress) return;
      lastProgress = now;
      unawaited(c.reloadProgress());
    }
    c.filesChanged.addListener(onFiles);
    lib.addListener(onLibrary);
    _forkSyncControllers[this] = c;
    _forkSyncPrefetch[this] = () {
      _forkSyncControllers[this] = null;
      c.filesChanged.removeListener(onFiles);
      lib.removeListener(onLibrary);
      sync.release();
    };
  }

  void _forkReleaseSync() => _forkSyncPrefetch[this]?.call();

  PositionSyncController? get _forkSyncController => _forkSyncControllers[this];

  /// The sync data, reading log or covers haven't arrived, so the skeleton
  /// stays up and the page lands whole. The quick sheet shows none of them.
  bool get _forkHoldingBack => !widget.quick && _forkHolding[this] == true;

  ColorScheme? _forkCachedCoverScheme() {
    if (_item == null) return null;
    final url = _forkPaletteUrl ?? _coverUrl;
    final accent = url == null ? null : _forkCoverAccents[url];
    return accent == null ? null : ColorScheme.fromSeed(seedColor: accent, brightness: Theme.of(context).brightness);
  }

  /// Wears the accent already worked out for [url], if there is one.
  bool _forkApplyKnownAccent(String url) {
    final accent = _forkCoverAccents[url];
    if (accent == null) return false;
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Theme.of(context).brightness);
    if (scheme != _rawCoverScheme) setState(() => _rawCoverScheme = scheme);
    return true;
  }

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

  /// Whether the sheet still shows the seed, not yet the fetched item.
  bool get _forkShowingSeed => _item != null && identical(_item, _forkSeeds[this]);

  /// The card's thumbnail URL on BookOrbit (already in the image cache from
  /// the shelf), which gives the same accent as the full cover.
  String? get _forkPaletteUrl {
    if (!context.read<AuthProvider>().isBookOrbit) return null;
    if ((_item?['_localCoverUrl'] as String?)?.isNotEmpty ?? false) return null;
    final coverPath = (_item?['media'] as Map?)?['coverPath'] as String?;
    if (coverPath == null || coverPath.isEmpty) return null;
    return context.read<LibraryProvider>().getCoverUrl(widget.itemId, coverRatio: _itemFrame);
  }

  /// A skeleton in the page's own shape and spacing (`_forkBuildContent`), so
  /// the content lands in place instead of replacing a spinner.
  Widget _forkLoadingBody(ColorScheme cs) {
    final tone = cs.onSurface.withValues(alpha: 0.06);
    Widget box(double w, double h, {double r = 8}) => Container(
          width: w, height: h,
          decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(r)),
        );
    final item = _item;
    final dual = item != null && forkHasBothCovers(item);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _forkLip(context),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          dual
              ? box(_ForkCoverStack.width, _ForkCoverStack.height, r: 12)
              : box(_squareCovers ? _ForkCoverStack.audioSide : _ForkCoverStack.ebookSize.width,
                  _squareCovers ? _ForkCoverStack.audioSide : _ForkCoverStack.ebookSize.height, r: 12),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            box(double.infinity, 26),
            const SizedBox(height: 10),
            box(120, 16),
            const SizedBox(height: 10),
            box(150, 14),
          ])),
        ]),
        const SizedBox(height: 20),
        box(double.infinity, 66),
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
