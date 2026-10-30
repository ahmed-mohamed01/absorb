import 'package:flutter/widgets.dart';

import '../../services/fork/cover_frame.dart';

// Fork-owned: the cover shapes where each BookOrbit book comes in its own
// frame, in a Dashboard shelf's sheet (section_detail_sheet.dart) and in the
// series sheet (series_books_sheet.dart). See FORK_NOTES.md.

/// The cover shapes of one shelf's books. With [ownFrames] each book takes
/// the frame BookOrbit gave it; otherwise, or for a book with none, the
/// shape the cover setting gives ([fallback]).
class ForkShelfFrames {
  /// The shape the cover setting gives, width over height.
  final double fallback;

  /// Whether books take their own frames (a Dashboard shelf, the series
  /// sheet) rather than all taking [fallback].
  final bool ownFrames;

  /// Whether any book on the shelf is portrait, so the grid needs room for
  /// portrait covers.
  final bool hasPortrait;

  /// Whether the books come in more than one shape. Covers then sit at the
  /// bottom of a portrait slot so they line up.
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
class ForkShelfCover extends StatelessWidget {
  /// The shelf's cover shapes.
  final ForkShelfFrames frames;

  /// The book whose cover this is.
  final Object? item;

  /// The cover with its badges.
  final Widget child;

  /// Creates [item]'s cover from [frames].
  const ForkShelfCover({super.key, required this.frames, required this.item, required this.child});

  @override
  Widget build(BuildContext context) {
    final frame = frames.of(item);
    return AspectRatio(
      aspectRatio: frames.slotOf(item),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AspectRatio(aspectRatio: frame, child: child),
      ),
    );
  }
}

/// A sheet's grid tile whose cover is drawn in [item]'s own shape, pushed
/// down so the cover sits at the bottom of [item]'s slot from [frames] and
/// lines up with the portrait covers beside it. [child] is the whole tile,
/// cover and text, as `GridBookTile` draws it.
class ForkShelfGridTile extends StatelessWidget {
  /// The sheet's cover shapes.
  final ForkShelfFrames frames;

  /// The book the tile shows.
  final Object? item;

  /// The tile, with its cover in [item]'s own shape.
  final Widget child;

  /// Creates [item]'s tile from [frames].
  const ForkShelfGridTile({super.key, required this.frames, required this.item, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final drop = w / frames.slotOf(item) - w / frames.of(item);
      return Padding(padding: EdgeInsets.only(top: drop > 0 ? drop : 0), child: child);
    });
  }
}
