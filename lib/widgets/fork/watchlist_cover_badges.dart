// Fork-owned: what a BookOrbit Watchlist item shows over its cover. Added to
// the cover Stack in book_card.dart and library_grid_tiles.dart. See
// FORK_NOTES.md.
import 'package:flutter/material.dart';

import '../../services/fork/watchlist_info.dart';

const watchlistOwnedEbook = Color(0xFF4F9D6C);
const watchlistOwnedAudio = Color(0xFF8C6CD0);
const watchlistMissing = Color(0xFFE0A24A);
const watchlistUpcoming = Color(0xFF7DA2E0);

/// The card's date top-left, the series number top-right and one tile per
/// format the card covers bottom-left (ebook first), drawn over a cover in a
/// Stack.
class WatchlistCoverBadges extends StatelessWidget {
  final Map<String, dynamic> item;

  const WatchlistCoverBadges({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final info = WatchlistInfo.of(item);
    if (info == null) return const SizedBox.shrink();
    final label = info.cardBadge;
    final index = info.seriesIndex;
    final hasIndex = index != null && index.isNotEmpty;
    return Positioned.fill(
      child: IgnorePointer(
        // The pills sit side by side on a narrow cover, so a large system
        // font must not push them into each other.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Stack(children: [
            if (label != null)
              Positioned(
                top: 4,
                left: 4,
                right: hasIndex ? 36 : 4,
                child: Align(alignment: Alignment.centerLeft, child: _pill(label)),
              ),
            if (hasIndex) Positioned(top: 4, right: 4, child: _pill('#$index')),
            Positioned(
              left: 4,
              bottom: 4,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final format in info.formats) ...[
                  if (format != info.formats.first) const SizedBox(width: 3),
                  WatchlistFormatTile(info: info, format: format),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  static Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
      );
}

/// One 24x24 tile saying where a format stands: filled when owned, an amber
/// outline when missing, a dashed blue outline when still to come, and a
/// download arrow (or its percent, once known) while a request is fetching it.
class WatchlistFormatTile extends StatelessWidget {
  final WatchlistInfo info;
  final String format;
  final double size;

  const WatchlistFormatTile({super.key, required this.info, required this.format, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final audio = format == 'audiobook';
    final status = info.formatStatus(format);
    final icon = audio ? Icons.headphones_rounded : Icons.menu_book_rounded;
    final iconSize = size * 0.6;
    final radius = BorderRadius.circular(size / 4);
    switch (status) {
      case 'owned':
        return Container(
          width: size,
          height: size,
          // The shadow keeps a filled tile apart from a cover of the same hue.
          decoration: BoxDecoration(
            color: audio ? watchlistOwnedAudio : watchlistOwnedEbook,
            borderRadius: radius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 3)],
          ),
          child: Icon(icon, size: iconSize, color: Colors.white),
        );
      case 'downloading' || 'importing' || 'queued':
        final percent = status == 'downloading' ? info.requestProgress(format) : null;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: radius,
            border: Border.all(color: watchlistUpcoming, width: 1.5),
          ),
          child: percent != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('$percent%',
                          maxLines: 1,
                          style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w800, color: watchlistUpcoming)),
                    ),
                  ),
                )
              : Icon(status == 'queued' ? Icons.schedule_rounded : Icons.download_rounded,
                  size: iconSize, color: watchlistUpcoming),
        );
      case 'upcoming' || 'unannounced':
        return CustomPaint(
          painter: WatchlistDashedBorder(color: watchlistUpcoming, radius: size / 4, fill: Colors.black.withValues(alpha: 0.6)),
          child: SizedBox(width: size, height: size, child: Icon(icon, size: iconSize, color: watchlistUpcoming)),
        );
      case 'not_watching':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: radius,
            border: Border.all(color: Colors.white38, width: 1.5),
          ),
          child: Icon(icon, size: iconSize, color: Colors.white54),
        );
      default:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: radius,
            border: Border.all(color: watchlistMissing, width: 1.5),
          ),
          child: Icon(status == 'needs_choice' ? Icons.priority_high_rounded : icon,
              size: iconSize, color: watchlistMissing),
        );
    }
  }
}

/// A dashed rounded-rectangle outline, for things that are not there yet.
class WatchlistDashedBorder extends CustomPainter {
  final Color color;
  final double radius;
  final Color? fill;
  final double strokeWidth;

  const WatchlistDashedBorder({required this.color, this.radius = 8, this.fill, this.strokeWidth = 1.5});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(strokeWidth / 2);
    if (fill != null) canvas.drawRRect(rrect, Paint()..color = fill!);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    const dash = 4.0, gap = 3.0;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(WatchlistDashedBorder old) =>
      old.color != color || old.radius != radius || old.fill != fill || old.strokeWidth != strokeWidth;
}
