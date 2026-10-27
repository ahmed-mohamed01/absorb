// ignore_for_file: invalid_use_of_protected_member
part of '../book_detail_sheet.dart';

// Fork-owned: the book detail page as redesigned in October 2026. A top bar
// (back, download, position sync, Absorbing, more), the cover beside the
// title, one rating line, a stat strip with the reading status in the
// middle, the main and secondary buttons, About with the genres behind Read
// more, then More like this / Chapters / Bookmarks as tabs. Menus open as
// bottom sheets. book_detail_sheet.dart only calls `_forkBuildContent`.
// See FORK_NOTES.md.

// New text stays plain until upstream takes it (FORK_NOTES rule 4).
const _kBookInfo = 'Book info';
const _kReleased = 'Released';
const _kPages = 'Pages';
const _kLength = 'Length';
const _kMarkNotFinished = 'Mark as not finished';
const _kAllActions = 'All actions';
const _kNoSimilar = 'No similar books found';
const _kSimilarOffline = 'Similar books need a connection';
const _kPreviewPlaying = 'Playing a preview';
const _kPreviewLoading = 'Loading a preview…';
const _kPreviewLength = 'Up to 5 minutes of the narration';
const _kStop = 'Stop';
const _kDates = 'Dates';
const _kStarted = 'Started';
const _kFinished = 'Finished';
const _kAllActionsHint = 'Edit, reset progress, delete and more';
String _kPagesCount(int n) => n == 1 ? '1 page' : '$n pages';

/// Per-sheet state the layout needs and the upstream state class doesn't have.
class _ForkDetailUi {
  bool aboutExpanded = false;
  String tab = 'similar';
  // Once the reader picks a tab, the page stops choosing one for them.
  bool userPickedTab = false;
  bool similarFetched = false;
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

    final actions = _forkActionButtons(
      context: context, cs: cs, tt: tt, l: l, accent: accent, lib: lib, auth: auth,
      ebookFile: ebookFile, isEbookOnly: isEbookOnly, textPrimary: textPrimary,
      progress: progress, isFinished: isFinished, duration: duration, chapters: chapters,
      title: title, authorName: authorName, media: media,
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
    // An audiobook always gets every tab, an empty one saying so, so the
    // switcher keeps its shape from book to book. Chapters and bookmarks
    // belong to the audio, and only BookOrbit picks similar books.
    final tabs = <(String, IconData, String)>[
      if (auth.isBookOrbit) ('similar', Icons.auto_awesome_outlined, l.moreLikeThis),
      if (!isEbookOnly) ('chapters', Icons.list_rounded, l.chapters),
      if (!isEbookOnly) ('bookmarks', Icons.bookmarks_outlined, l.bookmarks),
    ];
    final selected = forkSelectedTab(
      tabs: [for (final t in tabs) t.$1],
      preferred: _ui.tab,
      userPicked: _ui.userPickedTab,
      similarReady: similarReady,
      similarRequested: _similarLoaded,
      similarFetched: _ui.similarFetched,
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
      'similar' => similarReady || similarLoading ? null : lib.isOffline ? _kSimilarOffline : _kNoSimilar,
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
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2)))),
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
      _forkHero(context, cs, tt, l, accent, lib, title: title, subtitle: subtitle, metadata: metadata, seriesEntries: seriesEntries),
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
      Row(children: [
        Expanded(child: actions.primary),
        if (actions.secondary != null) ...[const SizedBox(width: 10), actions.secondary!],
      ]),
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
          title: title, authorName: authorName, progress: progress,
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
      if (bookOrbitOnline) ...[
        const SizedBox(height: 16),
        ReadingLogCard(itemId: widget.itemId, accent: accent),
      ] else if (!lib.isOffline && !isEbookOnly) ...[
        const SizedBox(height: 16),
        _listeningStatsBlock(context, cs, tt, accent, title),
      ],
      if (tabs.length == 1 && (similarReady || similarLoading)) ...[
        const SizedBox(height: 20),
        Text(l.moreLikeThis, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
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
      if (selected == 'similar' && (similarReady || similarLoading)) Builder(builder: (context) {
        // Two lines of title at the reader's text size, so a large font
        // doesn't overflow the tile; grey tiles of the same size hold the
        // place while the books load, so nothing jumps when they land.
        final labelHeight = MediaQuery.textScalerOf(context).scale(tt.labelMedium?.fontSize ?? 12) * 1.2 * 2 + 8;
        final coverHeight = _squareCovers ? 112.0 : 168.0;
        return SizedBox(
          height: coverHeight + labelHeight,
          child: similarReady
              ? ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: similar.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _forkSimilarTile(cs, tt, lib, auth, similar[i], 112),
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
      }),
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
      // On BookOrbit, position sync: the linked editions and how they stand
      // (the sheet BookOrbit's own sync button opens). Audiobookshelf has no
      // links, so there it lines up the audiobook and its EPUB on the phone.
      if (ForkSyncButton.shouldShow(auth, lib, widget.itemId))
        ForkSyncButton(
          key: ValueKey('fork-sync-${widget.itemId}'),
          itemId: widget.itemId, accent: accent, api: auth.apiService as BookOrbitApiService,
          title: title, authorName: authorName,
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
  }) {
    final shown = forkDisplayTitle(title: title, subtitle: subtitle, series: seriesEntries);
    // Every cover gets the same height, two fifths of the page's width (a
    // square one then takes two fifths of the row); a 2:3 cover is narrower.
    final coverHeight = ((MediaQuery.sizeOf(context).width - 32) * 0.40).clamp(130.0, 190.0);
    final coverWidth = _squareCovers ? coverHeight : coverHeight / 1.5;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_coverUrl != null) ...[
        // Tapping the cover opens it full size; the ripple over it says so.
        Semantics(
          button: true,
          label: title,
          child: Container(
            width: coverWidth,
            height: coverHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
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
        Text(shown.title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)),
        // Tight, in reading order: title, subtitle, who wrote and read it,
        // then the series as a small pill and the rating.
        if (shown.subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(shown.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
        const SizedBox(height: 4),
        _buildAuthorLinks(context, metadata, cs, tt, accent),
        _buildNarratorLinks(context, metadata, cs, tt, accent),
        if (seriesEntries.isNotEmpty) ...[
          const SizedBox(height: 6),
          _forkSeriesPill(context, l, accent, seriesEntries),
        ],
        const SizedBox(height: 4),
        _forkRatingLine(cs, tt, l),
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
      // A small neutral pill: just the series and its number, with "+N" and
      // a down chevron only when there are more series to choose from.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(label(main), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface))),
          if (others.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text('+${others.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Icon(Icons.expand_more_rounded, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ]),
      ),
    );
  }

  /// The best-supported rating as one line: a star, the score, how many
  /// ratings and whose. BookOrbit knows several providers; the one with the
  /// most ratings stands for them all.
  Widget _forkRatingLine(ColorScheme cs, TextTheme tt, AppLocalizations l) {
    Map<String, dynamic>? best;
    if (context.read<AuthProvider>().isBookOrbit) {
      for (final b in _providerBadges()) {
        if (b['rating'] == null) continue;
        if (best == null || ((b['count'] as num?) ?? 0) > ((best['count'] as num?) ?? 0)) best = b;
      }
    }
    final double rating;
    final int count;
    final String source;
    final VoidCallback? onTap;
    if (best != null) {
      rating = (best['rating'] as num).toDouble();
      count = (best['count'] as num?)?.toInt() ?? 0;
      source = best['label'] as String;
      final url = best['url'] as String?;
      onTap = best['key'] == 'audible' && _asin != null
          ? () => _showAudibleReviews(context)
          : url == null ? null : () => _openProviderPage(url);
    } else if (_rating != null && (_rating!['rating'] as num).toDouble() > 0) {
      rating = (_rating!['rating'] as num).toDouble();
      count = (_rating!['count'] as num?)?.toInt() ?? 0;
      source = 'Audible';
      onTap = _asin != null ? () => _showAudibleReviews(context) : null;
    } else {
      return const SizedBox.shrink();
    }
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF5B83D)),
        const SizedBox(width: 4),
        Text(rating.toStringAsFixed(1), style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Flexible(child: Text(
          count > 0 ? '${_BookDetailSheetContentState._formatRatingCount(count, l.localeName)} · $source' : source,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
        if (onTap != null) Icon(Icons.chevron_right_rounded, size: 16, color: cs.onSurfaceVariant),
      ])),
    );
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

  Widget _forkSimilarTile(ColorScheme cs, TextTheme tt, LibraryProvider lib, AuthProvider auth, Map<String, dynamic> book, double width) {
    final id = book['id'] as String;
    final height = _squareCovers ? width : width * 1.5;
    final url = book['hasCover'] == true ? auth.apiService?.getCoverUrl(id) : null;
    final blank = Container(color: cs.surfaceContainerHighest, child: Icon(Icons.menu_book_rounded, color: cs.onSurfaceVariant));
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () => showBookDetailSheet(context, id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2)))),
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
