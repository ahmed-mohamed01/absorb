import 'package:flutter/material.dart';

import '../books_sheet_shared.dart' show coverGridCount, coverGridSubtitleHeight;
import '../library_grid_tiles.dart';
import 'shelf_cover_frames.dart';

// Fork-owned: the grid of a Dashboard shelf's sheet (section_detail_sheet.dart),
// the Library grid's tiles and spacing with every cover one height. See
// FORK_NOTES.md.

/// A Dashboard shelf's books as the Library grid draws them: the same tile,
/// columns and spacing, with every cover the slot's height as on the shelf.
class ForkDashboardShelfGrid extends StatelessWidget {
  /// The shelf's books.
  final List<dynamic> entities;

  /// The shape the cover setting gives, width over height.
  final double coverAspectRatio;

  /// Whether tiles show a subtitle line, as the Library's do.
  final bool showSubtitles;

  /// The sheet's scroll controller.
  final ScrollController? scrollController;

  /// Creates the grid of [entities].
  const ForkDashboardShelfGrid({
    super.key,
    required this.entities,
    required this.coverAspectRatio,
    required this.showSubtitles,
    this.scrollController,
  });

  /// Whether [entities] can all take a Library tile. An episode has its own
  /// title to show, which the Library tile leaves out.
  static bool canShow(List<dynamic> entities) =>
      !entities.any((e) => e is Map && e['recentEpisode'] != null);

  @override
  Widget build(BuildContext context) {
    final covers = ForkDashboardCovers.of(context, entities, coverAspectRatio);
    final ratio = forkCellRatioForSlot(covers.slot);
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4)
          .copyWith(bottom: 40),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: coverGridCount(context),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: ratio,
        mainAxisExtent: showSubtitles
            ? covers.tileWidth / ratio + coverGridSubtitleHeight(context)
            : null,
      ),
      itemCount: entities.length,
      itemBuilder: (context, index) {
        final item = entities[index] as Map<String, dynamic>;
        return GridBookTile(
          item: item,
          coverAspectRatio: covers.frames.of(item),
          coverSlot: covers.slot,
          showSubtitle: showSubtitles,
        );
      },
    );
  }
}
