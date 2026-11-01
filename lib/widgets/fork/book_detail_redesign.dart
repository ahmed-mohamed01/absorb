// ignore_for_file: invalid_use_of_protected_member
part of '../book_detail_sheet.dart';

// Fork-owned: the book detail page as redesigned in October 2026. A top bar
// (back, download, position sync, Absorbing, more), the cover beside the
// title, one rating line, a stat strip with the reading status in the
// middle, the main and secondary buttons, About with the genres behind Read
// more, then Related (the book's series and More like this) / Chapters /
// Bookmarks as tabs. Menus open as bottom sheets. book_detail_sheet.dart
// calls `_forkBuildContent`, and `_forkLoadSeriesBooks` from `_loadItem`.
// See FORK_NOTES.md.

// New text stays plain until upstream takes it (FORK_NOTES rule 4).
const _kBookInfo = 'Book info';
const _kReleased = 'Released';
const _kPages = 'Pages';
const _kLength = 'Length';
const _kMarkNotFinished = 'Mark as not finished';
const _kAllActions = 'All actions';
const _kNoSimilar = 'No similar books found';
const _kRelated = 'Related';
String _kMoreIn(String series) => 'More in $series';
const _kSimilarOffline = 'Similar books need a connection';
const _kPreviewPlaying = 'Playing a preview';
const _kPreviewLoading = 'Loading a preview…';
const _kPreviewLength = 'Up to 5 minutes of the narration';
const _kStop = 'Stop';
const _kDates = 'Dates';
const _kStarted = 'Started';
const _kFinished = 'Finished';
const _kAllActionsHint = 'Edit, reset progress, delete and more';
const _kListen = 'Listen';
const _kShowEbook = 'Show the ebook';
const _kShowAudiobook = 'Show the audiobook';
String _kPagesCount(int n) => n == 1 ? '1 page' : '$n pages';

/// Per-sheet state the layout needs and the upstream state class doesn't have.
class _ForkDetailUi {
  bool aboutExpanded = false;
  String tab = 'similar';
  // Once the reader picks a tab, the page stops choosing one for them.
  bool userPickedTab = false;
  bool similarFetched = false;
  // The rest of the book's series, shown above the similar books.
  List<Map<String, dynamic>> seriesBooks = const [];
  bool seriesRequested = false;
  bool seriesFetched = false;
  String seriesName = '';
  // Which cover a book with both an audiobook and an ebook shows in front;
  // null until the reader swaps, so the page picks from their progress.
  bool? ebookFront;
}

final _forkDetailUi = Expando<_ForkDetailUi>();

IconData _forkReadStatusIcon(String s) => switch (s) {
      'want_to_read' => Icons.bookmark_add_outlined,
      'reading' => Icons.menu_book_rounded,
      'on_hold' => Icons.pause_rounded,
      'rereading' => Icons.replay_rounded,
      'read' => Icons.library_add_check_outlined,
      'skimmed' => Icons.horizontal_rule_rounded,
      'abandoned' => Icons.disabled_by_default_outlined,
      _ => Icons.book_outlined,
    };

/// The colours BookOrbit's web app gives each status, so a status reads the
/// same on both. Unread has none and takes the surrounding text colour.
Color? _forkReadStatusColor(String s) => switch (s) {
      'want_to_read' => const Color(0xFFA78BFA),
      'reading' => const Color(0xFF60A5FA),
      'on_hold' => const Color(0xFFFBBF24),
      'rereading' => const Color(0xFFE879F9),
      'read' => const Color(0xFF34D399),
      'skimmed' => const Color(0xFF22D3EE),
      'abandoned' => const Color(0xFFF87171),
      _ => null,
    };

/// One row in a pick-from sheet: an icon (in [color] when it has one), a
/// label, an optional [subtitle] under it and [detail] on the right.
class _ForkSheetOption<T> {
  final T value;
  final IconData icon;
  final Color? color;
  final String label;
  final bool selected;
  final String? subtitle;
  final String? detail;
  const _ForkSheetOption({
    required this.value,
    required this.icon,
    required this.label,
    this.color,
    this.selected = false,
    this.subtitle,
    this.detail,
  });
}

extension _ForkBookDetailRedesign on _BookDetailSheetContentState {
  _ForkDetailUi get _ui => _forkDetailUi[this] ??= _ForkDetailUi();

  /// `_loadSimilar` has its answer, found or not, so an empty tab can say so
  /// instead of waiting.
  void _forkSimilarFetched() {
    if (!mounted) return;
    setState(() => _ui.similarFetched = true);
  }

  /// Fetches the other books in the book's main series for the More in
  /// <series> row, called from `_loadItem` once the item is in. A reload
  /// fetches again only if the last try found nothing, so a failed fetch
  /// gets another go.
  void _forkLoadSeriesBooks(ApiService api) {
    final metadata = (_item?['media'] as Map?)?['metadata'] as Map? ?? const {};
    final series = forkMainSeries(metadata['series'] as List<dynamic>? ?? const [])?.main;
    final seriesId = series is Map ? series['id'] as String? : null;
    final libraryId = _item?['libraryId'] as String?;
    final inFlight = _ui.seriesRequested && !_ui.seriesFetched;
    if (!api.isBookOrbit || inFlight || _ui.seriesBooks.isNotEmpty || seriesId == null || libraryId == null) return;
    setState(() {
      _ui.seriesRequested = true;
      _ui.seriesFetched = false;
      _ui.seriesName = series['name'] as String? ?? '';
    });
    final title = metadata['title'] as String? ?? '';
    unawaited(api.getAllBooksBySeries(libraryId, seriesId).then((raw) {
      if (!mounted) return;
      setState(() {
        _ui.seriesBooks = forkSeriesBooksToShow(raw, itemId: widget.itemId, title: title, series: series);
        _ui.seriesFetched = true;
      });
    }));
  }

  Widget _forkBuildContent(BuildContext context, ColorScheme cs, TextTheme tt, AppLocalizations l) {
    final accent = (PlayerSettings.einkMode ? null : _coverScheme?.primary) ?? cs.primary;
    // A reload brings the server's ebook-only shape back; the narration found
    // on this phone makes it an audiobook again.
    final narration = _localNarration;
    if (narration != null) _item = NarrationService.instance.withNarration(_item!, narration);
    final media = _item!['media'] as Map<String, dynamic>? ?? {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
    final chapters = media['chapters'] as List<dynamic>? ?? [];
    final title = metadata['title'] as String? ?? l.unknown;
    final subtitle = metadata['subtitle'] as String? ?? '';
    final authorName = metadata['authorName'] as String? ?? '';
    final descRaw = metadata['description'] as String? ?? '';
    final duration = (media['duration'] as num?)?.toDouble() ?? 0;
    final seriesEntries = metadata['series'] as List<dynamic>? ?? [];
    final genres = (metadata['genres'] as List<dynamic>?)?.cast<String>() ?? [];
    final tags = ((media['tags'] as List<dynamic>?) ?? (metadata['tags'] as List<dynamic>?) ?? const []).cast<String>();
    final publisher = metadata['publisher'] as String? ?? '';
    final year = metadata['publishedYear']?.toString() ?? '';
    final pages = forkPageCount(metadata);
    final lib = context.watch<LibraryProvider>();
    final auth = context.read<AuthProvider>();
    final progress = lib.getProgress(widget.itemId);
    final progressData = lib.getProgressData(widget.itemId);
    final isFinished = progressData?['isFinished'] == true;
    final currentTime = (progressData?['currentTime'] as num?)?.toDouble() ?? 0;
    final ebookFile = resolveEbookFile(_item) ?? _cachedEbookFallback;
    final bookOrbitOnline = auth.isBookOrbit && !lib.isOffline;
    final isEbookOnly = PlayerSettings.isEbookOnly(_item!);
    final narrated = media['narration'] != null || NarratedBooks.contains(widget.itemId);
    final textPrimary = isEbookOnly || media['narration'] != null;
    // Preview only makes sense before the book has been started, with a 60 s
    // grace so an accidental tap-and-close doesn't hide it.
    final showPreview = !isEbookOnly && !isFinished && currentTime < 60 &&
        progress * duration < 60 && duration > 0;
    // Logged once per change, with the inputs, as upstream's layout does, so
    // a missing Preview can be explained.
    if (showPreview != _loggedPreviewVisible) {
      _loggedPreviewVisible = showPreview;
      debugPrint('[Preview] book ${widget.itemId}: menu item ${showPreview ? "shown" : "hidden"} '
          '(ebookOnly=$isEbookOnly finished=$isFinished '
          'currentTime=${currentTime.toStringAsFixed(0)}s '
          'played=${(progress * duration).toStringAsFixed(0)}s '
          'duration=${duration.toStringAsFixed(0)}s)');
    }

    // An audiobook with its own ebook, and a cover for each, shows both; the
    // one in front decides whether the main button listens or reads. It
    // starts on the cover the page would show on its own, as BookOrbit's
    // web page does.
    final dualCovers = auth.isBookOrbit && !lib.isOffline && !isEbookOnly &&
        media['narration'] == null && ebookFile != null && canReadEbook(ebookFile) && forkHasBothCovers(_item) &&
        ((_item?['_localCoverUrl'] as String?)?.isEmpty ?? true);
    final ebookFront = dualCovers && (_ui.ebookFront ??
        (((_item?['bookOrbit'] as Map?)?['coverVersion'] as String?)?.startsWith('ebook:') ?? false));

    final actions = _forkActionButtons(
      context: context, cs: cs, tt: tt, l: l, accent: accent, lib: lib, auth: auth,
      ebookFile: ebookFile, isEbookOnly: isEbookOnly, textPrimary: textPrimary || ebookFront,
      progress: progress, isFinished: isFinished, duration: duration, chapters: chapters,
      title: title, authorName: authorName, media: media,
      dualCovers: dualCovers,
    );

    final shownStatus = forkShownStatus(
      isBookOrbit: auth.isBookOrbit,
      bookOrbitStatus: ((_item?['bookOrbit'] as Map?)?['readStatus'] as Map?)?['status'] as String?,
      isFinished: isFinished,
      progress: progress,
    );
    final statusColor = _forkReadStatusColor(shownStatus) ?? cs.onSurface;
    // Under the status, when it was started or finished if known, else what
    // the cell is.
    final startedAt = forkDate(progressData?['startedAt']);
    final finishedAt = forkDate(progressData?['finishedAt']);
    // Day first with no comma ("26 Oct 2026"), which fits the narrow cell.
    String day(int ms) => DateFormat('d MMM y', l.localeName).format(DateTime.fromMillisecondsSinceEpoch(ms));
    final statusLabel = (shownStatus == 'read' || shownStatus == 'skimmed') && finishedAt != null
        ? l.finishedDate(day(finishedAt))
        : (shownStatus == 'reading' || shownStatus == 'rereading') && startedAt != null
            ? l.startedDate(day(startedAt))
            : l.readStatusTitle;
    // The chevron gives way when the status cell is tight; the colour and
    // the tap ripple still say it opens something.
    final statusRoomy = forkStatusCellRoomy(
      pageWidth: MediaQuery.sizeOf(context).width - 32,
      otherCells: (year.isNotEmpty ? 1 : 0) + (duration > 0 || pages > 0 ? 1 : 0),
      textScale: MediaQuery.textScalerOf(context).scale(1),
    );
    // The status sits in the middle, where it's easy to reach and change;
    // pages ride along under the length when the book has both.
    final stats = <({Widget value, String label, bool status})>[
      if (year.isNotEmpty) (value: Text(year, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleSmall), label: _kReleased, status: false),
      (value: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_forkReadStatusIcon(shownStatus), size: 16, color: statusColor),
        const SizedBox(width: 4),
        Flexible(child: Text(_BookDetailSheetContentState._readStatusLabel(l, shownStatus), maxLines: 1,
          overflow: TextOverflow.ellipsis, style: tt.titleSmall?.copyWith(color: statusColor))),
        if (!lib.isOffline && statusRoomy) Icon(Icons.expand_more_rounded, size: 16, color: cs.onSurfaceVariant),
      ]), label: statusLabel, status: true),
      if (duration > 0)
        (value: Text(formatHm(duration), maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleSmall),
          label: pages > 0 ? _kPagesCount(pages) : _kLength, status: false)
      else if (pages > 0)
        (value: Text('$pages', maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleSmall), label: _kPages, status: false),
    ];

    final similar = forkSimilarToShow(_similar, itemId: widget.itemId, title: title);
    final hasAbout = descRaw.isNotEmpty || genres.isNotEmpty || tags.isNotEmpty;
    final personalNote = ((_item?['bookOrbit'] as Map?)?['personalNote'] as String?)?.trim() ?? '';
    final similarReady = similar.isNotEmpty && !lib.isOffline;
    final seriesReady = _ui.seriesBooks.isNotEmpty && !lib.isOffline;
    final seriesLoading = _ui.seriesRequested && !_ui.seriesFetched && !lib.isOffline;
    // The tab holds both rows, so it has something to show if either does.
    final relatedReady = similarReady || seriesReady;
    // An audiobook always gets every tab, an empty one saying so, so the
    // switcher keeps its shape from book to book. Chapters and bookmarks
    // belong to the audio, and only BookOrbit picks similar books.
    final tabs = <(String, IconData, String)>[
      if (auth.isBookOrbit) ('similar', Icons.auto_awesome_outlined, _kRelated),
      if (!isEbookOnly) ('chapters', Icons.list_rounded, l.chapters),
      if (!isEbookOnly) ('bookmarks', Icons.bookmarks_outlined, l.bookmarks),
    ];
    final selected = forkSelectedTab(
      tabs: [for (final t in tabs) t.$1],
      preferred: _ui.tab,
      userPicked: _ui.userPickedTab,
      similarReady: relatedReady,
      // Related is still loading only while a fetch that was started hasn't
      // answered; the similar books are never fetched for some books.
      similarRequested: _similarLoaded || _ui.seriesRequested,
      similarFetched: (!_similarLoaded || _ui.similarFetched) && (!_ui.seriesRequested || _ui.seriesFetched),
      offline: lib.isOffline,
      hasChapters: chapters.isNotEmpty,
    );
    final similarLoading = forkSimilarLoading(
      similarReady: similarReady,
      similarRequested: _similarLoaded,
      similarFetched: _ui.similarFetched,
      offline: lib.isOffline,
    );
    final emptyTab = switch (selected) {
      'similar' => relatedReady || similarLoading || seriesLoading ? null : lib.isOffline ? _kSimilarOffline : _kNoSimilar,
      'chapters' => chapters.isEmpty ? l.noChaptersBook : null,
      'bookmarks' => _bookmarks.isEmpty ? l.noBookmarksYet : null,
      _ => null,
    };

    Widget filterChip(String value, bool tag) => _chip(tag ? Icons.local_offer_outlined : Icons.tag_rounded, value, onTap: () {
          Navigator.of(context).pop();
          if (tag) {
            AppShell.openLibraryWithTagFilterGlobal(value);
          } else {
            AppShell.openLibraryWithGenreFilterGlobal(value);
          }
        });

    void showInfo() => showStackableSheet(
          context: context,
          useSafeArea: true,
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          // The stackable sheet draws nothing behind its content, so the
          // sheet paints its own tinted backing, like the pick-from sheets.
          builder: (ctx, sc) => DecoratedBox(
            decoration: forkTintedSheetDecoration(ctx, _forkSheetTint),
            child: ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
            forkSheetHandle(ctx),
            Text(_kBookInfo, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (year.isNotEmpty) _chip(Icons.calendar_today_rounded, year),
              if (duration > 0) _chip(Icons.schedule_rounded, formatHm(duration)),
              if (pages > 0) _chip(Icons.description_outlined, _kPagesCount(pages)),
              if (chapters.isNotEmpty) _chip(Icons.list_rounded, l.chaptersChip(chapters.length)),
              ..._audioInfoChips(media),
              if (publisher.isNotEmpty) _chip(Icons.business_rounded, publisher),
              // Read live from the library, not captured when the sheet
              // opened, so a date edited here shows its new value at once.
              ...() {
                final pd = ctx.watch<LibraryProvider>().getProgressData(widget.itemId);
                final started = forkDate(pd?['startedAt']);
                final finished = forkDate(pd?['finishedAt']);
                return [
                  if (started != null)
                    _chip(Icons.play_circle_outline_rounded, l.startedDate(_fmtDate(started)),
                        onTap: () => _editProgressDate(
                              auth: auth, lib: lib, editingFinishedDate: false,
                              startedAt: started, finishedAt: finished,
                            )),
                  if (finished != null)
                    _chip(Icons.check_circle_outline_rounded, l.finishedDate(_fmtDate(finished)),
                        onTap: () => _editProgressDate(
                              auth: auth, lib: lib, editingFinishedDate: true,
                              startedAt: started ?? finished, finishedAt: finished,
                            )),
                ];
              }(),
            ]),
          ])),
        );

    return ListView(controller: widget.scrollController, padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.of(context).viewPadding.bottom), children: [
      _forkTopBar(context, cs, l, accent, lib, auth,
          title: title, authorName: authorName, isEbookOnly: isEbookOnly, ebookFile: ebookFile,
          narrated: narrated, isFinished: isFinished, currentTime: currentTime, duration: duration,
          progress: progress, showInfo: showInfo,
          showPreview: showPreview, chapters: chapters),
      const SizedBox(height: 12),
      _forkHero(context, cs, tt, l, accent, lib, title: title, subtitle: subtitle, metadata: metadata, seriesEntries: seriesEntries,
          dualCovers: dualCovers, ebookFront: ebookFront, auth: auth),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: cs.onSurface.withValues(alpha: 0.10)))),
        child: IntrinsicHeight(child: Row(children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) VerticalDivider(width: 1, color: cs.onSurface.withValues(alpha: 0.10)),
            // The status and its date need the most room, the year the least.
            Expanded(flex: stats[i].status ? forkStatusCellFlex : forkOtherCellFlex, child: Builder(builder: (cellContext) {
              final cell = Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Column(children: [
                stats[i].value,
                Text(stats[i].label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ]));
              if (!stats[i].status || lib.isOffline || _savingStatus) return cell;
              return InkWell(borderRadius: BorderRadius.circular(10),
                  onTap: () => _forkPickReadStatus(auth, lib, shownStatus, isFinished, currentTime, duration),
                  child: cell);
            })),
          ],
        ])),
      ),
      const SizedBox(height: 20),
      // Swapping covers cross-fades the buttons to the other format.
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Row(key: ValueKey(ebookFront), children: [
          Expanded(child: actions.primary),
          if (actions.secondary != null) ...[const SizedBox(width: 10), actions.secondary!],
        ]),
      ),
      _forkSyncStatusLine(cs, tt, l, accent),
      // Preview starts from the … menu, which closes; this says it's playing
      // and stops it without going back to the menu.
      if (_preview != null && (_preview!.isPlaying || _preview!.isLoading)) ...[
        const SizedBox(height: 10),
        _forkPreviewLine(cs, tt, accent, chapters, duration),
      ],
      if (ForkSyncButton.shouldShow(auth, lib, widget.itemId))
        ForkEditionsCard(
          key: ValueKey('fork-editions-${widget.itemId}'),
          itemId: widget.itemId, api: auth.apiService as BookOrbitApiService, accent: accent,
          progress: progress,
          tint: _forkSheetTint,
        ),
      if (hasAbout) ...[
        const SizedBox(height: 20),
        Text(l.aboutSection, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _forkAbout(context, cs, tt, l, accent, descRaw, [
          ...genres.map((g) => filterChip(g, false)),
          ...tags.map((t) => filterChip(t, true)),
        ], trailing: bookOrbitOnline && personalNote.isEmpty
            ? TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: cs.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onPressed: () => _editPersonalNote(auth, personalNote),
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: Text(l.personalNoteAdd),
              )
            : null),
      ],
      // A written note shows in full under About; with no About section the
      // add-a-note button stands on its own as before.
      if (bookOrbitOnline && (personalNote.isNotEmpty || !hasAbout)) ...[
        const SizedBox(height: 8),
        _personalNoteBlock(cs, tt, auth),
      ],
      if (bookOrbitOnline || (!lib.isOffline && !isEbookOnly)) ...[
        const SizedBox(height: 16),
        _listeningStatsBlock(context, cs, tt, accent, title),
      ],
      if (tabs.length > 1) ...[
        const SizedBox(height: 20),
        _forkTabSwitcher(cs, tt, tabs, selected),
        const SizedBox(height: 12),
      ],
      if (selected == 'chapters' && chapters.isNotEmpty) _forkChapterList(context, cs, tt, accent, auth, chapters, currentTime, title, authorName, duration),
      if (selected == 'bookmarks')
        for (final bm in _bookmarks)
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 64, child: Text(bm.formattedAt(_displaySpeed), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bm.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodyMedium),
              if (bm.note != null && bm.note!.isNotEmpty)
                Text(bm.note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ])),
          ])),
      if (selected == 'similar') ...() {
        final showSeries = seriesReady || seriesLoading;
        final showSimilar = similarReady || similarLoading;
        Widget heading(String text) => Padding(padding: const EdgeInsets.only(bottom: 12),
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)));
        return [
          if (showSeries) ...[
            heading(_kMoreIn(_ui.seriesName)),
            _forkBookRow(cs, tt, lib, auth, _ui.seriesBooks, ready: seriesReady, numbered: true),
          ],
          if (showSimilar) ...[
            if (showSeries) const SizedBox(height: 8),
            heading(l.moreLikeThis),
            _forkBookRow(cs, tt, lib, auth, similar, ready: similarReady),
          ],
        ];
      }(),
      if (tabs.length > 1 && emptyTab != null)
        Padding(padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text(emptyTab, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)))),
      const SizedBox(height: 20),
    ]);
  }

  Widget _forkTopBar(BuildContext context, ColorScheme cs, AppLocalizations l, Color accent, LibraryProvider lib, AuthProvider auth, {
    required String title,
    required String authorName,
    required bool isEbookOnly,
    required dynamic ebookFile,
    required bool narrated,
    required bool isFinished,
    required double currentTime,
    required double duration,
    required double progress,
    required VoidCallback showInfo,
    required bool showPreview,
    required List<dynamic> chapters,
  }) {
    final onAbsorbing = lib.isOnAbsorbingList(widget.itemId);
    final syncPair = !isEbookOnly && ebookFile != null && ebookExtFromFile(ebookFile) == '.epub';
    return Row(children: [
      IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
      const Spacer(),
      if (!isEbookOnly)
        DownloadWideButton(itemId: widget.itemId, coverUrl: _coverUrl, title: title, author: authorName, accent: accent, iconOnly: true)
      else if (!_lookingForNarration && ebookFile != null && canReadEbook(ebookFile))
        ListenableBuilder(listenable: DownloadService(), builder: (_, __) {
          final saved = DownloadService().isDownloaded(widget.itemId);
          if (lib.isOffline && !saved && !_ebookOfflineDownloading) return const SizedBox.shrink();
          final dlGreen = Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent : Colors.green.shade700;
          return IconButton(
            tooltip: saved ? l.saved : l.ebookDownload,
            onPressed: _ebookOfflineDownloading
                ? null
                : () => saved ? _removeEbookOffline(context) : _downloadEbookOffline(context, auth, ebookFile, title),
            icon: _ebookOfflineDownloading
                ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                : Icon(saved ? Icons.download_done_rounded : Icons.download_rounded, color: saved ? dlGreen : null),
          );
        }),
      // On BookOrbit, position sync: how the book's own files stand (the sheet
      // BookOrbit's own sync button opens). Audiobookshelf has no such sync,
      // so there it lines up the audiobook and its EPUB on the phone.
      if (ForkSyncButton.shouldShow(auth, lib, widget.itemId))
        ForkSyncButton(
          key: ValueKey('fork-sync-${widget.itemId}'),
          itemId: widget.itemId, accent: accent, api: auth.apiService as BookOrbitApiService,
          tint: PlayerSettings.einkMode ? null : _coverScheme?.primaryContainer,
        )
      else if (!auth.isBookOrbit && syncPair && !lib.isOffline)
        ListenableBuilder(
          listenable: Listenable.merge([ReadListenSync.instance.syncing, ReadListenSync.instance.failed]),
          builder: (_, __) {
            final busy = ReadListenSync.instance.syncing.value.containsKey(widget.itemId);
            final bad = !busy && ReadListenSync.instance.failed.value.containsKey(widget.itemId);
            return IconButton(
              tooltip: bad ? l.syncFailed : l.syncPosition,
              onPressed: busy
                  ? null
                  : () => narrated
                      ? showOverlayToast(context, l.syncAlreadyTogether, icon: Icons.check_rounded)
                      : ReadListenSync.instance.syncNow(widget.itemId),
              icon: busy
                  ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                  : Icon(bad ? Icons.sync_problem_rounded : Icons.sync_rounded, color: bad ? cs.error : null),
            );
          }),
      IconButton(
        tooltip: onAbsorbing ? Wording.of(context).removeFromAbsorbing : Wording.of(context).addToAbsorbing,
        icon: Icon(onAbsorbing ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: onAbsorbing ? accent : null),
        onPressed: () async {
          if (onAbsorbing) {
            await lib.removeFromAbsorbing(widget.itemId);
            HapticFeedback.mediumImpact();
            if (context.mounted) showOverlayToast(context, Wording.of(context).removedFromAbsorbing, icon: Icons.remove_circle_outline_rounded);
          } else {
            await addToAbsorbingWithPicker(context, widget.itemId, item: _item, addedToast: Wording.of(context).addedToAbsorbing);
          }
        },
      ),
      IconButton(
        tooltip: l.moreActions,
        icon: const Icon(Icons.more_horiz_rounded),
        onPressed: () async {
          final value = await _forkPickFromSheet<String>(null, [
            _ForkSheetOption(value: 'finished', icon: isFinished ? Icons.remove_done_rounded : Icons.check_circle_outline_rounded, color: null,
              label: isFinished ? _kMarkNotFinished : Wording.of(context).fullyAbsorbAction, selected: false),
            if (!lib.isOffline && !auth.isBookOrbit)
              _ForkSheetOption(value: 'playlist', icon: Icons.playlist_add_rounded, color: null, label: l.addToPlaylist, selected: false),
            if (!lib.isOffline && !lib.isPodcastLibrary && (auth.isAdmin || auth.isBookOrbit))
              _ForkSheetOption(value: 'collection', icon: Icons.collections_bookmark_outlined, color: null, label: l.addToCollection, selected: false),
            // A sample of the narration, offered until you're a minute in.
            if (showPreview)
              _ForkSheetOption(value: 'preview', icon: (_preview?.isPlaying ?? false) ? Icons.stop_rounded : Icons.headphones_rounded, color: null,
                label: (_preview?.isPlaying ?? false) ? l.chapterStopPreview : l.preview, selected: false),
            _ForkSheetOption(value: 'info', icon: Icons.info_outline_rounded, color: null, label: _kBookInfo, selected: false),
            _ForkSheetOption(value: 'all', icon: Icons.grid_view_rounded, label: _kAllActions, subtitle: _kAllActionsHint),
          ]);
          if (!context.mounted) return;
          switch (value) {
            case 'finished':
              isFinished ? _markNotFinished(context, auth, currentTime, duration) : _markFinished(context, auth, duration);
            case 'playlist':
              PlaylistPickerSheet.show(context, widget.itemId);
            case 'collection':
              CollectionPickerSheet.show(context, widget.itemId);
            case 'preview':
              _togglePreview(context, chapters, duration);
            case 'info':
              showInfo();
            case 'all':
              _showMoreSheet(context, auth, lib, title, authorName, progress, isFinished, duration, ebookFile, isEbookOnly);
          }
        },
      ),
    ]);
  }

  Widget _forkHero(BuildContext context, ColorScheme cs, TextTheme tt, AppLocalizations l, Color accent, LibraryProvider lib, {
    required String title,
    required String subtitle,
    required Map<String, dynamic> metadata,
    required List<dynamic> seriesEntries,
    required bool dualCovers,
    required bool ebookFront,
    required AuthProvider auth,
  }) {
    final shown = forkDisplayTitle(title: title, subtitle: subtitle, series: seriesEntries);
    // The watchlist's cover size: 112 x 168 for a 2:3 cover, and a square
    // one at about the same area.
    final coverHeight = _squareCovers ? _ForkCoverStack.audioSide : _ForkCoverStack.ebookSize.height;
    final coverWidth = _squareCovers ? _ForkCoverStack.audioSide : _ForkCoverStack.ebookSize.width;
    String slotUrl(bool ebook, int width) =>
        auth.apiService!.getCoverUrl(widget.itemId, width: width, coverSlot: ebook ? 'ebook' : 'audio');
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (dualCovers) ...[
        _ForkCoverStack(
          ebookFront: ebookFront,
          cover: (ebook) => CachedNetworkImage(
            imageUrl: slotUrl(ebook, 800), fit: BoxFit.cover,
            httpHeaders: lib.mediaHeaders,
            placeholder: (_, __) => ColoredBox(color: cs.surfaceContainerHigh),
            errorWidget: (_, __, ___) => ColoredBox(
              color: cs.surfaceContainerHigh,
              child: Icon(ebook ? Icons.menu_book_rounded : Icons.headphones_rounded, color: cs.onSurfaceVariant),
            ),
          ),
          onOpenFront: () => _showFullCover(context, slotUrl(ebookFront, 4000), lib.mediaHeaders, title),
          onSwap: () {
            HapticFeedback.selectionClick();
            setState(() => _ui.ebookFront = !ebookFront);
          },
          title: title,
        ),
        const SizedBox(width: 16),
      ] else if (_coverUrl != null) ...[
        // Tapping the cover opens it full size; the ripple over it says so.
        Semantics(
          button: true,
          label: title,
          child: Container(
            width: coverWidth,
            height: coverHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 4))],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [
              _coverUrl!.startsWith('/')
                  ? Image.file(File(_coverUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())
                  : CachedNetworkImage(
                      imageUrl: _coverUrl!, fit: BoxFit.cover,
                      httpHeaders: lib.mediaHeaders,
                      placeholder: (_, __) => _forkCoverPlaceholder(lib),
                      errorWidget: (_, __, ___) => const SizedBox(),
                    ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => _showFullCover(context, _fullResCoverUrl ?? _coverUrl!, lib.mediaHeaders, title),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 16),
      ],
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Spaced like the watchlist's header: title, subtitle, who wrote and
        // read it, then the series pill and the rating a step further down.
        Text(shown.title, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)),
        if (shown.subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(shown.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
        ..._forkByline(context, metadata, cs, tt, accent),
        if (seriesEntries.isNotEmpty) ...[
          const SizedBox(height: 8),
          _forkSeriesPill(context, l, accent, seriesEntries),
        ],
      ])),
    ]);
  }

  /// One series pill however many series the book is in: the first with a
  /// number stands for them, a "+N" says there are more, and a tap then lists
  /// them all. A stack of pills pushed the author out of view.
  Widget _forkSeriesPill(BuildContext context, AppLocalizations l, Color accent, List<dynamic> seriesEntries) {
    final series = forkMainSeries(seriesEntries)!;
    final main = series.main;
    final others = series.others;
    const label = forkSeriesLabel;
    return GestureDetector(
      onTap: () async {
        if (others.isEmpty) {
          _openSeries(context, main['id'] as String?, main['name'] as String? ?? '');
          return;
        }
        final picked = await _forkPickFromSheet<dynamic>(l.seriesLabel, [
          for (final s in [main, ...others])
            _ForkSheetOption(value: s, icon: Icons.auto_stories_rounded, color: accent, label: label(s), selected: false),
        ]);
        if (picked != null && context.mounted) {
          _openSeries(context, picked['id'] as String?, picked['name'] as String? ?? '');
        }
      },
      // As on the watchlist: a book icon and the series with its number in
      // the accent, with "+N" and a down chevron only when there are more
      // series to choose from.
      behavior: HitTestBehavior.opaque,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_stories_rounded, size: 14, color: accent),
        const SizedBox(width: 6),
        Flexible(child: Text(label(main), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent))),
        if (others.isNotEmpty) ...[
          const SizedBox(width: 5),
          Text('+${others.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Icon(Icons.expand_more_rounded, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ],
      ]),
    );
  }

  /// Who wrote and read the book, laid out like the watchlist's byline, with
  /// each name in the accent so it reads as tappable: it opens that author
  /// or narrator.
  List<Widget> _forkByline(BuildContext context, Map<String, dynamic> metadata, ColorScheme cs, TextTheme tt, Color accent) {
    final authors = [
      for (final a in (metadata['authors'] as List<dynamic>? ?? const []))
        if (a is Map && ((a['name'] as String?) ?? '').isNotEmpty) a,
    ];
    final authorName = (metadata['authorName'] as String? ?? '').trim();
    final narrators = <String>[
      for (final n in (metadata['narrators'] as List<dynamic>? ?? const []))
        if (n is String) n.trim() else if (n is Map) ((n['name'] as String?) ?? '').trim(),
    ].where((s) => s.isNotEmpty).toList();
    if (narrators.isEmpty) {
      narrators.addAll((metadata['narratorName'] as String? ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
    }

    // Names separated by commas, the first three shown until "+N" is tapped.
    Widget names(List<String> all, TextStyle? style, bool expanded, VoidCallback expand, void Function(int) open, {String prefix = ''}) {
      final visible = expanded || all.length <= 3 ? all : all.sublist(0, 3);
      final link = style?.copyWith(color: accent, fontWeight: FontWeight.w500);
      return Wrap(children: [
        if (prefix.isNotEmpty) Text(prefix, style: style),
        for (var i = 0; i < visible.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => open(i),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: visible[i], style: link),
              if (i < visible.length - 1) TextSpan(text: ', ', style: style),
            ])),
          ),
        if (visible.length < all.length)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: expand,
            child: Text('  +${all.length - visible.length}', style: style?.copyWith(fontWeight: FontWeight.w600)),
          ),
      ]);
    }

    final byStyle = tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant);
    final narratedStyle = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final narratedParts = AppLocalizations.of(context)!.narratedBy('||X||').split('||X||');
    return [
      if (authors.isNotEmpty || authorName.isNotEmpty) ...[
        const SizedBox(height: 4),
        authors.isEmpty
            ? Text(authorName, style: byStyle)
            : names([for (final a in authors) a['name'] as String], byStyle, _authorsExpanded,
                () => setState(() => _authorsExpanded = true), (i) {
                final id = authors[i]['id'] as String? ?? '';
                if (id.isNotEmpty) showAuthorDetailSheet(context, authorId: id, authorName: authors[i]['name'] as String);
              }),
      ],
      if (narrators.isNotEmpty) ...[
        const SizedBox(height: 4),
        names(narrators, narratedStyle, _narratorsExpanded, () => setState(() => _narratorsExpanded = true),
            (i) => showNarratorBooksSheet(context, narratorName: narrators[i]),
            prefix: narratedParts.first),
      ],
    ];
  }

  Widget _forkPreviewLine(ColorScheme cs, TextTheme tt, Color accent, List<dynamic> chapters, double duration) {
    final loading = _preview?.isLoading ?? false;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        SizedBox(width: 22, height: 22, child: loading
            ? Padding(padding: const EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2, color: accent))
            : Icon(Icons.graphic_eq_rounded, size: 22, color: accent)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(loading ? _kPreviewLoading : _kPreviewPlaying, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          Text(_kPreviewLength, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ])),
        if (!loading)
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: cs.onSurface,
              backgroundColor: cs.onSurface.withValues(alpha: 0.10),
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const StadiumBorder(),
            ),
            onPressed: () => _togglePreview(context, chapters, duration),
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text(_kStop),
          ),
      ]),
    );
  }

  /// "Finding your place…" while a read/listen sync runs, and a retry when
  /// it couldn't.
  Widget _forkSyncStatusLine(ColorScheme cs, TextTheme tt, AppLocalizations l, Color accent) {
    return ListenableBuilder(
      listenable: Listenable.merge([ReadListenSync.instance.syncing, ReadListenSync.instance.failed]),
      builder: (context, _) {
        final to = ReadListenSync.instance.syncing.value[widget.itemId];
        final failed = to == null && ReadListenSync.instance.failed.value.containsKey(widget.itemId);
        if (to == null && !failed) return const SizedBox.shrink();
        if (failed) {
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => ReadListenSync.instance.syncNow(widget.itemId),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Icon(Icons.sync_problem_rounded, size: 16, color: cs.error),
                const SizedBox(width: 8),
                Expanded(child: Text(l.syncFailed, overflow: TextOverflow.ellipsis, style: tt.labelMedium?.copyWith(color: cs.error))),
                Text(l.retry, style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: accent)),
              ]),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
            const SizedBox(width: 10),
            Expanded(child: Text(to == SyncTarget.audio ? l.syncFindingAudio : l.syncFindingEbook,
                overflow: TextOverflow.ellipsis, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant))),
          ]),
        );
      },
    );
  }

  Widget _forkTabSwitcher(ColorScheme cs, TextTheme tt, List<(String, IconData, String)> tabs, String selected) {
    // The selected tab is a step up from the track in the theme's own
    // colours (so it holds in light mode), and only an outline on e-ink.
    final eink = PlayerSettings.einkMode;
    final selectedFill = eink ? Colors.transparent : Color.alphaBlend(cs.onSurface.withValues(alpha: 0.08), cs.surface);
    return LayoutBuilder(builder: (context, box) {
      // The icons are decoration; on a narrow phone or at a large text size
      // they give their room to the label.
      final perTab = (box.maxWidth - 8) / tabs.length;
      final showIcons = perTab >= 110 && MediaQuery.textScalerOf(context).scale(1) <= 1.15;
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          for (final tab in tabs)
            Expanded(child: Material(
              color: selected == tab.$1 ? selectedFill : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: selected == tab.$1 ? cs.onSurface.withValues(alpha: eink ? 1 : 0.14) : Colors.transparent,
                  width: eink ? 1.5 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() {
                  _ui.tab = tab.$1;
                  _ui.userPickedTab = true;
                }),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (showIcons) ...[
                        Icon(tab.$2, size: 16, color: selected == tab.$1 ? cs.onSurface : cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                      ],
                      Flexible(child: Text(tab.$3, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                          style: tt.labelMedium?.copyWith(color: selected == tab.$1 ? cs.onSurface : cs.onSurfaceVariant))),
                    ]),
                  ),
                ),
              ),
            )),
        ]),
      );
    });
  }

  /// The description clamped to four lines, with Read more only when there
  /// is more to see: text past those lines, or the genre and tag [chips]
  /// that wait behind it. With no description the chips show at once.
  Widget _forkAbout(BuildContext context, ColorScheme cs, TextTheme tt, AppLocalizations l, Color accent,
      String descRaw, List<Widget> chips, {Widget? trailing}) {
    final style = tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.7), height: 1.5);
    if (descRaw.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: chips),
        if (trailing != null) Align(alignment: Alignment.centerRight, child: trailing),
      ]);
    }
    return LayoutBuilder(builder: (context, box) {
      // Measured on the text HtmlDescription renders: the same block-to-
      // newline steps as its parser, then the inline tags dropped.
      final plain = descRaw
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .replaceAll(RegExp(r'<br\s*/?>'), '\n')
          .replaceAll(RegExp(r'</p>'), '\n\n')
          .replaceAll(RegExp(r'<p[^>]*>'), '')
          .replaceAll(RegExp(r'</div>'), '\n')
          .replaceAll(RegExp(r'<div[^>]*>'), '')
          .replaceAll(RegExp(r'</?ul[^>]*>'), '\n')
          .replaceAll(RegExp(r'</?ol[^>]*>'), '\n')
          .replaceAll(RegExp(r'<li[^>]*>'), '  \u2022 ')
          .replaceAll(RegExp(r'</li>'), '\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&');
      final painter = TextPainter(
        text: TextSpan(text: plain, style: style),
        maxLines: 4,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: box.maxWidth);
      final more = painter.didExceedMaxLines || chips.isNotEmpty;
      painter.dispose();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        HtmlDescription(html: descRaw, maxLines: 4, expanded: _ui.aboutExpanded || !more, style: style, linkColor: accent),
        if (_ui.aboutExpanded && chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
        // Read more on the left and the private note on the right share one
        // row, where they used to take a row each.
        if (more || trailing != null)
          Row(children: [
            if (more)
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
                onPressed: () => setState(() => _ui.aboutExpanded = !_ui.aboutExpanded),
                icon: Icon(_ui.aboutExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                label: Text(_ui.aboutExpanded ? l.showLess : l.readMore),
              ),
            const Spacer(),
            ?trailing,
          ]),
      ]);
    });
  }

  /// The chapter list, laid out like the card's: the chapter you're in is
  /// lit, the ones behind you fold into one row.
  Widget _forkChapterList(BuildContext context, ColorScheme cs, TextTheme tt, Color accent, AuthProvider auth,
      List<dynamic> chapters, double currentTime, String title, String authorName, double duration) {
    // The chapter rows are ListTiles with a highlight colour; they need a
    // Material right behind them, or the sheet's own coloured backing sits
    // in between and Flutter asserts that their colour and splashes may not
    // show (once per row, every frame).
    return Material(type: MaterialType.transparency, child: ListenableBuilder(
      listenable: AudioPlayerService(),
      builder: (context, _) {
        final player = AudioPlayerService();
        final isActive = player.hasBook && player.currentItemId == widget.itemId;
        final pos = isActive ? player.position.inMilliseconds / 1000.0 : currentTime;
        var done = 0;
        while (done < chapters.length &&
            pos >= (((chapters[done] as Map<String, dynamic>)['end'] as num?)?.toDouble() ?? 0)) {
          done++;
        }
        final anim = PlayerSettings.einkMode ? Duration.zero : const Duration(milliseconds: 250);
        return Column(children: [
          if (done > 0) ...[
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _finishedChaptersExpanded = !_finishedChaptersExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                child: Row(children: [
                  SizedBox(width: 28, child: AnimatedRotation(
                    turns: _finishedChaptersExpanded ? 0.5 : 0,
                    duration: anim,
                    child: Icon(Icons.expand_more_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.4)),
                  )),
                  Expanded(child: Text(AppLocalizations.of(context)!.detailChaptersFinished(done),
                      style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)))),
                ]),
              ),
            ),
            ClipRect(child: AnimatedSize(
              duration: anim,
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _finishedChaptersExpanded
                  ? Column(children: [
                      for (var i = 0; i < done; i++)
                        _chapterRow(context, cs, tt, accent, auth, chapters, i, pos, isActive, title, authorName, duration),
                    ])
                  : const SizedBox(width: double.infinity),
            )),
          ],
          for (var i = done; i < chapters.length; i++)
            _chapterRow(context, cs, tt, accent, auth, chapters, i, pos, isActive, title, authorName, duration),
        ]);
      },
    ));
  }

  /// A sideways row of book tiles. Two lines of title at the reader's text
  /// size, so a large font doesn't overflow the tile; grey tiles of the same
  /// size hold the place until [ready], so nothing jumps when they land.
  /// [numbered] puts each book's series number on its cover.
  Widget _forkBookRow(ColorScheme cs, TextTheme tt, LibraryProvider lib, AuthProvider auth, List<Map<String, dynamic>> books,
      {required bool ready, bool numbered = false}) {
    return Builder(builder: (context) {
      final labelHeight = MediaQuery.textScalerOf(context).scale(tt.labelMedium?.fontSize ?? 12) * 1.2 * 2 + 8;
      final coverHeight = _squareCovers ? 112.0 : 168.0;
      return SizedBox(
        height: coverHeight + labelHeight,
        child: ready
            ? ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: books.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _forkSimilarTile(cs, tt, lib, auth, books[i], 112, numbered: numbered),
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, __) => Align(alignment: Alignment.topCenter, child: Container(
                  width: 112, height: coverHeight,
                  decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
                )),
              ),
      );
    });
  }

  /// A small dark pill over a cover, legible on any artwork.
  Widget _forkCoverBadge(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
        child: child,
      );

  Widget _forkSimilarTile(ColorScheme cs, TextTheme tt, LibraryProvider lib, AuthProvider auth, Map<String, dynamic> book, double width,
      {bool numbered = false}) {
    final id = book['id'] as String;
    final height = _squareCovers ? width : width * 1.5;
    final url = book['hasCover'] == true ? auth.apiService?.getCoverUrl(id) : null;
    final blank = Container(color: cs.surfaceContainerHighest, child: Icon(Icons.menu_book_rounded, color: cs.onSurfaceVariant));
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () => showBookDetailSheet(context, id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: width,
                height: height,
                child: url == null
                    ? blank
                    : CachedNetworkImage(
                        imageUrl: url, httpHeaders: lib.mediaHeaders, fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: cs.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => blank,
                      ),
              ),
            ),
            if (numbered) ...[
              // The way BookOrbit's app marks a series row: a check on books
              // already read, the number in the corner.
              // 100% counts as finished, as it does in the series sheet.
              if (lib.getProgressData(id)?['isFinished'] == true || lib.getProgress(id) >= 1.0)
                Positioned(top: 6, left: 6, child: _forkCoverBadge(const Icon(Icons.check_rounded, size: 14, color: Colors.greenAccent))),
              if ((book['sequence'] as String? ?? '').isNotEmpty)
                Positioned(bottom: 6, right: 6, child: _forkCoverBadge(Text('#${book['sequence']}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)))),
            ],
          ]),
          const SizedBox(height: 6),
          Text(book['title'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: tt.labelMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.8), height: 1.2)),
        ]),
      ),
    );
  }

  /// The reading status picker from the stat strip. BookOrbit gets every
  /// status it has, Unread and Read included as the user asked (a hand-set
  /// Unread stays until changed). Audiobookshelf only knows finished or not,
  /// so it gets where the book stands and Read, which run the finish buttons.
  Future<void> _forkPickReadStatus(AuthProvider auth, LibraryProvider lib,
      String current, bool isFinished, double currentTime, double duration) async {
    final l = AppLocalizations.of(context)!;
    final options = forkStatusOptions(isBookOrbit: auth.isBookOrbit, isFinished: isFinished, current: current);
    // The dates sit under the statuses, so the date the strip shows can be
    // changed where it's seen instead of under … > Book info.
    final pd = lib.getProgressData(widget.itemId);
    final started = forkDate(pd?['startedAt']);
    final finished = forkDate(pd?['finishedAt']);
    String day(int ms) => DateFormat('d MMM y', l.localeName).format(DateTime.fromMillisecondsSinceEpoch(ms));
    const startedKey = '__started', finishedKey = '__finished';
    final picked = await _forkPickFromSheet<String>(l.readStatusTitle, [
      for (final s in options)
        _ForkSheetOption(value: s, icon: _forkReadStatusIcon(s), color: _forkReadStatusColor(s),
          label: _BookDetailSheetContentState._readStatusLabel(l, s), selected: s == current),
    ], footerTitle: _kDates, footer: [
      if (started != null)
        _ForkSheetOption(value: startedKey, icon: Icons.play_circle_outline_rounded, label: _kStarted, detail: day(started)),
      if (finished != null)
        _ForkSheetOption(value: finishedKey, icon: Icons.check_circle_outline_rounded, label: _kFinished, detail: day(finished)),
    ]);
    final api = auth.apiService;
    if (picked == null || picked == current || api == null || !mounted) return;
    if (picked == startedKey || picked == finishedKey) {
      await _editProgressDate(
        auth: auth, lib: lib, editingFinishedDate: picked == finishedKey,
        startedAt: started ?? finished!, finishedAt: finished,
      );
      return;
    }
    // Read and Skimmed count as finished and everything else as not, the way
    // _displayReadStatus squares the two, so the finish state moves first;
    // a cancelled confirmation leaves everything as it was.
    final plan = forkStatusPlan(picked: picked, isFinished: isFinished, isBookOrbit: auth.isBookOrbit);
    final finish = plan.finish;
    if (finish != null) {
      if (finish) {
        await _markFinished(context, auth, duration);
      } else {
        await _markNotFinished(context, auth, currentTime, duration);
      }
      if (!mounted || (lib.getProgressData(widget.itemId)?['isFinished'] == true) != finish) return;
    }
    if (!plan.saveStatus) return;
    setState(() => _savingStatus = true);
    final ok = await api.setReadStatus(widget.itemId, picked);
    if (!mounted) return;
    setState(() {
      _savingStatus = false;
      if (ok) {
        final bo = Map<String, dynamic>.from((_item?['bookOrbit'] as Map?) ?? const {});
        bo['readStatus'] = {...?(bo['readStatus'] as Map?)?.cast<String, dynamic>(), 'status': picked};
        _item = {..._item!, 'bookOrbit': bo};
      }
    });
    if (ok) {
      unawaited(lib.refresh());
    } else {
      showOverlayToast(context, l.failedToUpdateCheckConnection, icon: Icons.error_outline_rounded);
    }
  }

  /// The cover colour the page's sheets are tinted with; none on e-ink.
  Color? get _forkSheetTint => PlayerSettings.einkMode ? null : _coverScheme?.primaryContainer;

  /// A short list to pick from, as a bottom sheet like the app's other menus,
  /// tinted with the cover the way this sheet is. Null when dismissed.
  Future<T?> _forkPickFromSheet<T>(String? title, List<_ForkSheetOption<T>> options,
      {String? footerTitle, List<_ForkSheetOption<T>> footer = const []}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = (PlayerSettings.einkMode ? null : _coverScheme?.primary) ?? cs.primary;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      // The page's shared tinted background, drawn by the content itself.
      backgroundColor: Colors.transparent,
      builder: (ctx) => DecoratedBox(decoration: forkTintedSheetDecoration(ctx, _forkSheetTint), child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          forkSheetHandle(ctx),
          if (title != null)
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final o in [...options, ...footer]) ...[
              // A second group (the status sheet's dates) sits under a rule
              // and its own small heading.
              if (footer.isNotEmpty && identical(o, footer.first)) ...[
                Divider(height: 20, indent: 16, endIndent: 16, color: cs.onSurface.withValues(alpha: 0.10)),
                if (footerTitle != null)
                  Align(alignment: Alignment.centerLeft, child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(footerTitle.toUpperCase(), style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                  )),
              ],
              Material(
                color: o.selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(ctx, o.value),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(children: [
                        Icon(o.icon, size: 22, color: o.color ?? cs.onSurfaceVariant),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(o.label, style: tt.bodyLarge?.copyWith(fontWeight: o.selected ? FontWeight.w600 : null)),
                          if (o.subtitle != null)
                            Text(o.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ])),
                        if (o.detail != null) ...[
                          const SizedBox(width: 8),
                          Text(o.detail!, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                        if (o.selected) Icon(Icons.check_rounded, size: 20, color: accent),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ]))),
        ]),
      ))),
    );
  }
}

/// A book with both an audiobook and an ebook shows both covers, as
/// BookOrbit's web page does (`BookCoverStack.vue`): the one in front opens
/// full size, the other shows a tilted strip behind it, and tapping that
/// one (or swiping sideways) brings it forward. The stage is as tall as the
/// portrait cover and never changes size, so swapping doesn't move the page.
class _ForkCoverStack extends StatelessWidget {
  final bool ebookFront;
  final Widget Function(bool ebook) cover;
  final VoidCallback onSwap;
  final VoidCallback onOpenFront;
  final String title;

  const _ForkCoverStack({
    required this.ebookFront,
    required this.cover,
    required this.onSwap,
    required this.onOpenFront,
    required this.title,
  });

  static const ebookSize = Size(112, 168);
  static const audioSide = 140.0;
  // BookOrbit's stage is 1 : 1.29, here at the watchlist cover's height.
  static const height = 168.0;
  static const width = height / 1.29;
  // Its CSS, as shares of the stage: the portrait cover's width, the square
  // one's size and top, and where each starts when it's behind.
  static const _portrait = Size(width * 0.86, height);
  static const _square = Size(width * 0.95, height * 0.7364);
  static const _squareTop = height * 0.2636;
  static const _bleed = width * 0.06;
  static const _portraitBackStart = width * 0.1346 + _bleed;
  static const _squareBackStart = width * 0.0557 + _bleed;
  // 3 degrees, the ebook tipped one way and the audiobook the other.
  static const _tilt = 0.0524;
  static const _backScale = 0.94;
  static const _ease = Cubic(0.3, 0.9, 0.25, 1);

  static Rect _rect(bool ebook, bool front) => ebook
      ? Offset(front ? 0 : _portraitBackStart, 0) & _portrait
      : Offset(front ? 0 : _squareBackStart, _squareTop) & _square;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0).abs() > 200) onSwap();
      },
      child: SizedBox(
        width: width,
        height: height,
        // t runs 0 (audiobook in front) to 1 (ebook in front).
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: ebookFront ? 1 : 0),
          duration: const Duration(milliseconds: 500),
          curve: _ease,
          builder: (context, t, _) {
            final ebook = _card(context, ebook: true, frontness: t);
            final audio = _card(context, ebook: false, frontness: 1 - t);
            // The new front cover goes on top at once and slides into place.
            return Stack(clipBehavior: Clip.none, children: ebookFront ? [audio, ebook] : [ebook, audio]);
          },
        ),
      ),
    );
  }

  Widget _card(BuildContext context, {required bool ebook, required double frontness}) {
    final rect = Rect.lerp(_rect(ebook, false), _rect(ebook, true), frontness)!;
    final isFront = ebook == ebookFront;
    final back = 1 - frontness;
    Widget chipIcon(IconData icon) => Icon(icon, size: 10, color: Colors.white);
    return Positioned.fromRect(
      rect: rect,
      child: Transform.rotate(
        angle: (ebook ? _tilt : -_tilt) * back,
        child: Transform.scale(
          scale: 1 - (1 - _backScale) * back,
          child: Semantics(
            button: true,
            label: isFront ? title : (ebook ? _kShowEbook : _kShowAudiobook),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 10))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                cover(ebook),
                // The cover behind is a touch darker.
                IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: 0.08 * back))),
                // Each cover's format, and on the one behind, that it swaps.
                Positioned(
                  top: 6,
                  right: 6,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(3)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        chipIcon(ebook ? Icons.menu_book_rounded : Icons.headphones_rounded),
                        if (!isFront) ...[const SizedBox(width: 3), chipIcon(Icons.swap_horiz_rounded)],
                      ]),
                    ),
                  ),
                ),
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(onTap: isFront ? onOpenFront : onSwap),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
