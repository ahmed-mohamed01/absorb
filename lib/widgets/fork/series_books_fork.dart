part of '../series_books_sheet.dart';

// Fork-owned: the series sheet's fork parts, hooked in from
// series_books_sheet.dart. Each book is drawn in the cover shape BookOrbit
// gave it, and the series actions sit behind an overflow beside Up next
// that opens a cover-tinted menu. See FORK_NOTES.md.

/// The sheet's cover shapes, kept per list of books so a rebuild (every
/// download tick) reads them instead of going over the series again.
final _forkFramesCache = Expando<(bool, ForkShelfFrames)>();

extension _ForkSeriesBooks on _SeriesBooksSheetState {
  /// Each book in the shape BookOrbit gave it, square for audiobooks and
  /// portrait for ebooks, as on the Dashboard. A book with none takes the
  /// library's cover setting.
  ForkShelfFrames get _forkFrames {
    final hit = _forkFramesCache[_books];
    if (hit != null && hit.$1 == _rectCovers) return hit.$2;
    final frames = ForkShelfFrames(_books, _rectCovers ? forkPortraitFrame : 1.0, ownFrames: true);
    _forkFramesCache[_books] = (_rectCovers, frames);
    return frames;
  }

  /// [book]'s grid tile with its cover in its own shape, lined up at the
  /// bottom of a portrait slot beside portrait covers.
  Widget _forkGridTile(Map<String, dynamic> book) {
    final frames = _forkFrames;
    return ForkShelfGridTile(
      frames: frames,
      item: book,
      child: GridBookTile(item: book, coverAspectRatio: frames.of(book), sequenceBadge: _getSequenceString(book),
          showAuthor: _forkShowAuthor),
    );
  }

  /// A sub-series tile in the shape of its first book, lined up like a
  /// book's tile.
  Widget _forkSeriesTile(Map<String, dynamic> series) {
    final frames = _forkFrames;
    final books = series['books'] as List<dynamic>? ?? const [];
    final first = books.isEmpty ? null : books.first;
    return ForkShelfGridTile(
      frames: frames,
      item: first,
      child: GridSeriesTileDirect(series: series, coverAspectRatio: frames.of(first), parentSeriesId: widget.seriesId),
    );
  }

  /// [upNext] with the series actions' overflow button on its right, or
  /// the button alone on the right when nothing is up next.
  Widget _forkWithActions(Color accent, Widget? upNext) => Row(children: [
        if (upNext != null) Expanded(child: upNext) else const Spacer(),
        const SizedBox(width: 8),
        _forkActionsButton(accent),
      ]);

  /// The overflow button that opens the series actions. While a mark-all or
  /// download-all runs it shows a spinner instead.
  Widget _forkActionsButton(Color accent) {
    final busy = _isMarkingAll || _isDownloadingAll;
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: busy
            ? Center(child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent)))
            : InkWell(
                onTap: () => _forkShowActionsMenu(accent),
                child: Tooltip(
                  message: MaterialLocalizations.of(context).moreButtonTooltip,
                  child: Icon(Icons.more_vert_rounded, size: 22, color: accent),
                ),
              ),
      ),
    );
  }

  /// The series actions as a menu from the bottom, tinted with the cover the
  /// way this sheet is, like the book page's menus. A switched-on action
  /// (its `tint` set) is highlighted and a disabled one dimmed; tapping one
  /// closes the menu and runs it.
  Future<void> _forkShowActionsMenu(Color accent) async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final items = _actionPills(context);
    final tint = PlayerSettings.einkMode ? null : _coverScheme?.primaryContainer;
    final picked = await showModalBottomSheet<ActionPillData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DecoratedBox(
        decoration: forkTintedSheetDecoration(ctx, tint),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              forkSheetHandle(ctx),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(widget.seriesName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final p in items)
                  () {
                    final on = p.tint != null;
                    final fg = p.enabled ? null : cs.onSurface.withValues(alpha: 0.38);
                    return Material(
                      color: on ? accent.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: p.enabled ? () => Navigator.pop(ctx, p) : null,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 52),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(children: [
                              Icon(p.icon, size: 22, color: fg ?? (on ? accent : cs.onSurfaceVariant)),
                              const SizedBox(width: 16),
                              Expanded(child: Text(p.label,
                                  style: tt.bodyLarge?.copyWith(color: fg, fontWeight: on ? FontWeight.w600 : null))),
                            ]),
                          ),
                        ),
                      ),
                    );
                  }(),
              ]))),
            ]),
          ),
        ),
      ),
    );
    if (picked != null && mounted) picked.onTap();
  }
}

/// Whether a book's list row or grid tile names the author. It doesn't: a
/// series is one author's, and BookOrbit's app leaves it out.
bool get _forkShowAuthor => false;

/// A list row's read status on its right, as BookOrbit's app shows it: a
/// green check when finished (amber when skimmed), the percentage when
/// started, nothing before that. A book at 100% counts as finished, as it
/// does for the sheet's finished count and Up next.
Widget _forkReadStatus(ColorScheme cs, TextTheme tt, AppLocalizations l,
    {required double progress, required bool isFinished, required bool isSkimmed}) {
  Widget child = const SizedBox.shrink();
  if (isFinished || progress >= 1.0) {
    final skimmed = isFinished && isSkimmed;
    final color = skimmed ? Colors.amberAccent.shade200 : Colors.greenAccent.shade400;
    child = Semantics(
      label: skimmed ? l.readStatusSkimmed : l.finished,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 20, color: Colors.black87),
      ),
    );
  } else if (progress > 0) {
    child = Text('${(progress * 100).clamp(1, 99).round()}%',
        style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600));
  }
  return Padding(
    padding: const EdgeInsets.only(right: 14),
    child: SizedBox(width: 40, child: Align(alignment: Alignment.centerRight, child: child)),
  );
}

/// A slim rounded bar under an unfinished, started book's details. None at
/// 100%, which [_forkReadStatus] shows as finished.
Widget _forkRowProgress(ColorScheme cs, double progress) => progress >= 1.0
    ? const SizedBox.shrink()
    : Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0), minHeight: 4,
          backgroundColor: cs.onSurface.withValues(alpha: 0.12),
          valueColor: AlwaysStoppedAnimation(cs.primary)),
      ),
    );
