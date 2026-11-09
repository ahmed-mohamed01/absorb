import 'package:flutter/widgets.dart';

import '../../services/fork/cover_frame.dart';
import '../../services/fork/fork_settings.dart';
import '../books_sheet_shared.dart' show coverGridTileWidth;

// Fork-owned: the cover shapes where each BookOrbit book comes in its own
// frame: in the series sheet (series_books_sheet.dart) and, while
// ForkSettings.ownCoverShapes is on, the Dashboard's shelves and their sheets
// (section_detail_sheet.dart), the Library grid and the author and narrator
// sheets. See FORK_NOTES.md.

/// The cover shapes of one shelf's books. With [ownFrames] each book takes
/// the frame BookOrbit gave it; otherwise, or for a book with none, the
/// shape the cover setting gives ([fallback]).
class ForkShelfFrames {
  /// The shape the cover setting gives, width over height.
  final double fallback;

  /// Whether books take their own frames rather than all taking [fallback].
  final bool ownFrames;

  /// Whether any book on the shelf is portrait, so the grid needs room for
  /// portrait covers.
  final bool hasPortrait;

  /// Whether the books come in more than one shape, so their covers need a
  /// shared slot to line up: [slotOf]'s or [forkGridSlot]'s.
  final bool mixed;

  ForkShelfFrames._(this.fallback, this.ownFrames, this.hasPortrait, this.mixed);

  /// The shapes of [entities] on a shelf whose cover setting is [fallback].
  factory ForkShelfFrames(List<dynamic> entities, double fallback, {required bool ownFrames}) {
    final shapes = {
      for (final e in entities) ownFrames ? (forkBookFrame(e) ?? fallback) : fallback,
    };
    return ForkShelfFrames._(
      fallback,
      ownFrames,
      shapes.isEmpty ? fallback < 1.0 : shapes.any((f) => f < 1.0),
      shapes.length > 1,
    );
  }

  /// The shape [item]'s cover is drawn in.
  double of(Object? item) => ownFrames ? (forkBookFrame(item) ?? fallback) : fallback;

  /// The shape of the space [item]'s cover sits in: a portrait slot on a
  /// mixed shelf, otherwise the cover's own shape.
  double slotOf(Object? item) => mixed ? forkPortraitFrame : of(item);

  /// Width over height of a grid cell for these books: a portrait cover's
  /// height when any book is portrait, plus [forkGridTitleShare] for the
  /// title. A grid of square books keeps upstream's 0.65.
  double get gridCellRatio => 1 / (1 / (hasPortrait ? forkPortraitFrame : 1.0) + forkGridTitleShare);
}

/// The room a grid tile's title and author take under its cover, as a share
/// of the tile's width: what upstream's square series grid (0.65) leaves.
const double forkGridTitleShare = 0.54;

/// Where each of [items]' covers sits in an overlapped strip [height] tall:
/// each as wide as its own shape from [frames], each starting [overlap] of
/// the way across the one before it. [width] is the whole strip's width.
({double height, List<double> widths, List<double> lefts, double width}) forkCoverStrip(
    List<Object?> items, ForkShelfFrames frames,
    {double height = 90, double overlap = 0.68}) {
  final widths = [for (final b in items) height * frames.of(b)];
  final lefts = <double>[];
  for (var i = 0; i < widths.length; i++) {
    lefts.add(i == 0 ? 0 : lefts[i - 1] + widths[i - 1] * overlap);
  }
  return (
    height: height,
    widths: widths,
    lefts: lefts,
    width: widths.isEmpty ? 0 : lefts.last + widths.last,
  );
}

/// A shelf sheet's cover: [child] drawn in [item]'s own shape, as wide as
/// the space it is given, at the bottom of [item]'s slot from [frames]. On a
/// shelf of one shape it is just that shape, as upstream's `AspectRatio` was.
/// With [slot] it is instead centred in a [slot]-shaped space at that space's
/// full height, as a Dashboard shelf's covers are.
class ForkShelfCover extends StatelessWidget {
  /// The shelf's cover shapes.
  final ForkShelfFrames frames;

  /// The book whose cover this is.
  final Object? item;

  /// The cover with its badges.
  final Widget child;

  /// The shape of a slot the cover is centred in, if it has one.
  final double? slot;

  /// Creates [item]'s cover from [frames].
  const ForkShelfCover({super.key, required this.frames, required this.item, required this.child, this.slot});

  @override
  Widget build(BuildContext context) {
    final frame = frames.of(item);
    if (slot != null) return forkCoverInSlot(slot, AspectRatio(aspectRatio: frame, child: child));
    return AspectRatio(
      aspectRatio: frames.slotOf(item),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AspectRatio(aspectRatio: frame, child: child),
      ),
    );
  }
}

/// Height of a grid cell whose tile is a cover in a [slot]-shaped space
/// [tileWidth] wide, then a title and, with [secondLine], one more line (a
/// sub-series tile's author), at the grid's [labelScale] and the phone's
/// font size [textScaler], with a little room under them.
double forkTitledGridExtent({
  required double tileWidth,
  required double slot,
  required double labelScale,
  required TextScaler textScaler,
  bool secondLine = false,
}) =>
    tileWidth / slot
    + 5 + textScaler.scale(11 * labelScale) * 1.6
    + (secondLine ? textScaler.scale(10 * labelScale) * 1.6 : 0)
    + 8;

/// The cover shapes of a grid of [items] outside the series sheet (the
/// Library grid, the author and narrator sheets, the Dashboard's shelves and
/// their sheets' grids): each book's own while [ForkSettings.ownCoverShapes]
/// is on, else all [fallback], the shape that grid had before.
///
/// These grids lay covers out as BookOrbit's app does: on a grid of mixed
/// shapes every cover sits in a square slot ([forkGridSlot]), a square
/// cover filling it and a portrait one as tall but narrower, centred
/// ([forkCoverInSlot]). Rows stay square, so there is no gap above square
/// covers and no blur around portrait ones.
ForkShelfFrames forkGridFrames(List<dynamic> items, double fallback) =>
    ForkShelfFrames(items, fallback, ownFrames: ForkSettings.ownCoverShapes);

/// The shape of [item]'s cover slot in a grid from [forkGridFrames]:
/// square on a grid of mixed shapes, otherwise the cover's own shape.
double forkGridSlot(ForkShelfFrames frames, Object? item) => frames.mixed ? 1.0 : frames.of(item);

/// Whether a grid from [forkGridFrames] needs portrait-height cells: only
/// when every cover is portrait.
bool forkGridTall(ForkShelfFrames frames) => frames.hasPortrait && !frames.mixed;

/// Width over height of a cell in a grid from [forkGridFrames], the Library
/// grid's own: taller when every cover is portrait.
double forkGridCellRatio(ForkShelfFrames frames) => forkCellRatioForSlot(forkGridTall(frames) ? forkPortraitFrame : 1.0);

/// The Library grid's cell, width over height, for covers in a [slot]-shaped space.
double forkCellRatioForSlot(double slot) => slot < 1.0 ? _forkPortraitCellRatio : _forkSquareCellRatio;

const double _forkPortraitCellRatio = 0.48;
const double _forkSquareCellRatio = 0.68;

/// The cover shapes of a shelf's sheet that isn't a [ForkDashboardCovers]
/// grid: on the Dashboard each book's own while
/// [ForkSettings.ownCoverShapes] is on, otherwise all [fallback].
ForkShelfFrames forkSheetFrames(List<dynamic> entities, double fallback, {required bool dashboard}) =>
    ForkShelfFrames(entities, fallback, ownFrames: dashboard && ForkSettings.ownCoverShapes);

/// The slot of every cover on a Dashboard shelf and in its sheet's grid. While
/// books take their own shapes it is always square, so an ebook is as tall as
/// an audiobook on every shelf, even one of nothing but ebooks; otherwise it
/// is the shape the cover setting gives.
double forkDashboardSlot(ForkShelfFrames frames) => frames.ownFrames ? 1.0 : frames.fallback;

/// How a Dashboard shelf's covers follow the Library grid: the shapes of its
/// books, one slot for all of them, and the Library tile's width.
class ForkDashboardCovers {
  /// The shelf's cover shapes.
  final ForkShelfFrames frames;

  /// The width of a Library tile at the current cover size.
  final double tileWidth;

  ForkDashboardCovers._(this.frames, this.tileWidth);

  /// The covers of [entities] on a shelf whose cover setting is [setting]. A
  /// playlist entry nests its book, so its shape is read from that.
  factory ForkDashboardCovers.of(BuildContext context, List<dynamic> entities, double setting) =>
      ForkDashboardCovers._(
        forkGridFrames([
          for (final e in entities) (e is Map<String, dynamic> ? e['libraryItem'] : null) ?? e,
        ], setting),
        coverGridTileWidth(context),
      );

  /// The slot every cover on the shelf sits in.
  double get slot => forkDashboardSlot(frames);

  /// The height of a cover's slot.
  double get coverHeight => tileWidth / slot;

  /// The width of a Continue card: the tile and the padding around its cover.
  double get heroCardWidth => tileWidth + 20;

  /// The height of a row of Continue cards: the slot, the padding above and
  /// below the cover, and the 106 px card text upstream's square row leaves.
  double get heroRowHeight => coverHeight + 14 + 106;
}

/// [cover] centred in a [slot]-shaped space as tall as it is, or [cover]
/// alone when there is no slot.
Widget forkCoverInSlot(double? slot, Widget cover) =>
    slot == null ? cover : AspectRatio(aspectRatio: slot, child: Center(child: cover));
