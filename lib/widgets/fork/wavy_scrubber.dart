import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../card_progress_bar.dart';

/// The players' chapter scrubber as BookOrbit's app draws it: the chapter
/// name on a line of its own, then a wavy line up to the position, a thumb,
/// and a flat track to the end. Replaces the chapter pill; the caller keeps
/// the gestures and sizes it with [height].
///
/// The wave only moves while [isPlaying], so an idle player doesn't redraw
/// every frame.
class ForkWavyChapterBar extends StatefulWidget {
  final double progress;
  final Color accent;
  final bool isPlaying;
  final bool isDragging;
  final String? name;
  final bool compact;

  const ForkWavyChapterBar({
    super.key,
    required this.progress,
    required this.accent,
    required this.isPlaying,
    required this.isDragging,
    required this.name,
    this.compact = false,
  });

  static double _fontSize(bool compact) => compact ? 12 : 13;
  static double _gap(bool compact) => compact ? 6 : 8;
  static double _barHeight(bool compact) => compact ? 20 : 24;

  /// Total height: the name line, a gap, and the bar. The name line follows
  /// the text size (plus the marquee's 2dp above and below) so it never
  /// clips; the bar is 24dp (20 compact), so a drag that starts on the line
  /// itself has room.
  static double height(BuildContext context, bool compact) =>
      MediaQuery.textScalerOf(context).scale(_fontSize(compact)) * 1.3 + 4
      + _gap(compact) + _barHeight(compact);

  @override
  State<ForkWavyChapterBar> createState() => _ForkWavyChapterBarState();
}

class _ForkWavyChapterBarState extends State<ForkWavyChapterBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncPhase();
  }

  @override
  void didUpdateWidget(ForkWavyChapterBar old) {
    super.didUpdateWidget(old);
    if (old.isPlaying != widget.isPlaying) _syncPhase();
  }

  void _syncPhase() {
    if (widget.isPlaying && !_reduceMotion) {
      _phase.repeat();
    } else {
      _phase.stop();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final barH = ForkWavyChapterBar._barHeight(widget.compact);
    final name = widget.name;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: name != null
                  ? MarqueeText(
                      text: name,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                        fontSize: ForkWavyChapterBar._fontSize(widget.compact),
                        letterSpacing: 0.2,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        SizedBox(height: ForkWavyChapterBar._gap(widget.compact)),
        SizedBox(
          height: barH,
          width: double.infinity,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _WavyScrubberPainter(
                progress: widget.progress,
                accent: widget.accent,
                track: cs.onSurface.withValues(alpha: 0.18),
                isDragging: widget.isDragging,
                phase: _phase,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WavyScrubberPainter extends CustomPainter {
  final double progress;
  final Color accent;
  final Color track;
  final bool isDragging;
  final Animation<double> phase;

  _WavyScrubberPainter({
    required this.progress,
    required this.accent,
    required this.track,
    required this.isDragging,
    required this.phase,
  }) : super(repaint: phase);

  static const _stroke = 4.0;
  static const _amplitude = 3.0;
  static const _wavelength = 28.0;
  // Clear space either side of the thumb, as Material's wavy slider leaves.
  static const _thumbGap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final w = size.width;
    final p = progress.clamp(0.0, 1.0);
    final thumbW = isDragging ? 6.0 : 4.0;
    final thumbH = isDragging ? size.height : size.height * 0.75;
    // The thumb stays inside the bar at both ends.
    final x = w <= thumbW ? w / 2 : (p * w).clamp(thumbW / 2, w - thumbW / 2);
    final shift = phase.value * 2 * math.pi;

    final wave = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Played part: the wave, eased in over its first wavelength and out
    // toward the thumb so it meets the caps flat.
    final waveEnd = x - thumbW / 2 - _thumbGap;
    const start = _stroke / 2;
    if (waveEnd > start) {
      final path = Path()..moveTo(start, cy);
      for (double t = start; t <= waveEnd; t += 1.5) {
        final ease = math.min(
          ((t - start) / _wavelength).clamp(0.0, 1.0),
          ((waveEnd - t) / (_wavelength / 2)).clamp(0.0, 1.0),
        );
        path.lineTo(t, cy + _amplitude * ease * math.sin(2 * math.pi * t / _wavelength - shift));
      }
      canvas.drawPath(path, wave);
    }

    // Unplayed part: a flat track and a stop dot at the end.
    final trackStart = x + thumbW / 2 + _thumbGap;
    final trackEnd = w - _stroke / 2;
    if (trackStart < trackEnd) {
      canvas.drawLine(
        Offset(trackStart, cy),
        Offset(trackEnd, cy),
        Paint()
          ..color = track
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    if (p < 0.98) {
      canvas.drawCircle(Offset(w - _stroke / 2, cy), _stroke / 2, Paint()..color = accent);
    }

    // Thumb: an upright rounded bar.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, cy), width: thumbW, height: thumbH),
        Radius.circular(thumbW / 2),
      ),
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(_WavyScrubberPainter old) =>
      old.progress != progress ||
      old.accent != accent ||
      old.track != track ||
      old.isDragging != isDragging;
}
