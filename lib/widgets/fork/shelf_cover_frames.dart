import 'package:flutter/widgets.dart';

import '../../services/fork/cover_frame.dart';

// Fork-owned: the cover shapes in a shelf's sheet (section_detail_sheet.dart)
// on the Dashboard, where each BookOrbit book comes in its own frame. See
// FORK_NOTES.md.

/// The cover shapes of one shelf's books. On the Dashboard each book takes
/// the frame BookOrbit gave it; elsewhere, or for a book with none, the
/// shape the cover setting gives ([fallback]).
class ForkShelfFrames {
  /// The shape the cover setting gives, width over height.
  final double fallback;

  /// Whether the shelf is on the Dashboard, where books carry their frames.
  final bool dashboard;

  /// Whether any book on the shelf is portrait, so the grid needs room for
  /// portrait covers.
  final bool hasPortrait;

  /// Whether the books come in more than one shape. Covers then sit at the
  /// bottom of a portrait slot so they line up.
  final bool mixed;

  ForkShelfFrames._(this.fallback, this.dashboard, this.hasPortrait, this.mixed);

  /// The shapes of [entities] on a shelf whose cover setting is [fallback].
  factory ForkShelfFrames(List<dynamic> entities, double fallback, {required bool dashboard}) {
    final shapes = {
      for (final e in entities) dashboard ? (forkBookFrame(e) ?? fallback) : fallback,
    };
    return ForkShelfFrames._(
      fallback,
      dashboard,
      shapes.isEmpty ? fallback < 1.0 : shapes.any((f) => f < 1.0),
      shapes.length > 1,
    );
  }

  /// The shape [item]'s cover is drawn in.
  double of(Object? item) => dashboard ? (forkBookFrame(item) ?? fallback) : fallback;

  /// The shape of the space [item]'s cover sits in: a portrait slot on a
  /// mixed shelf, otherwise the cover's own shape.
  double slotOf(Object? item) => mixed ? forkPortraitFrame : of(item);
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
