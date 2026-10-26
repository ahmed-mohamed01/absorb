import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/book_stats_service.dart';
import '../../services/bookorbit_mapper.dart';
import '../../utils/duration_format.dart';
import '../card_buttons.dart';

// Fork-owned: the compact reading log on a BookOrbit book's detail sheet.
// Hooked in from book_detail_sheet.dart; see FORK_NOTES.md. Its text is plain
// English until upstream takes it.

/// How a session was spent.
enum ReadingMode { listen, read, readAlong }

/// One session in the reading log, from a BookOrbit session row.
class ReadingLogEntry {
  final ReadingMode mode;

  /// BookOrbit's source bucket, or 'absorb' for a session this phone sent.
  final String source;
  final DateTime? startedAt;
  final double seconds;
  final double? delta;
  final double? reached;

  const ReadingLogEntry(
    this.mode,
    this.source,
    this.startedAt,
    this.seconds,
    this.delta,
    this.reached,
  );

  static ReadingLogEntry fromSession(Map<String, dynamic> s) {
    final type = s['sessionType'] as String?;
    final format = s['format'] as String?;
    final audioFile =
        format == null || BookOrbitMapper.isAudioFormat(format.toLowerCase());
    // BookOrbit's medium counts audio files as listening even when the session
    // was saved with the default 'read' type (Audiobookshelf's are).
    final listened =
        type == 'listen' ||
        type == 'tts' ||
        s['medium'] == 'listened' ||
        (audioFile && format != null);
    // BookOrbit has no read-along type: listening on an EPUB is its narration.
    final mode = !listened
        ? ReadingMode.read
        : audioFile
        ? ReadingMode.listen
        : ReadingMode.readAlong;
    final ms = (s['startedAt'] as num?)?.toInt();
    return ReadingLogEntry(
      mode,
      s['ownDevice'] == true ? 'absorb' : bucket(s['source'] as String?),
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      (s['timeListening'] as num?)?.toDouble() ?? 0,
      (s['progressDelta'] as num?)?.toDouble(),
      (s['endProgress'] as num?)?.toDouble(),
    );
  }

  /// BookOrbit's display buckets: web, manual and unknown are all BookOrbit.
  static String bucket(String? source) => switch (source) {
    'ios' ||
    'watchos' ||
    'android' ||
    'koreader' ||
    'kobo' ||
    'audiobookshelf' => source!,
    _ => 'bookorbit',
  };
}

const Map<String, Color> readingLogSourceColors = {
  'absorb': Color(0xFFCAAC2F),
  'android': Color(0xFFCAAC2F),
  'ios': Color(0xFF65C67D),
  'watchos': Color(0xFFFF8B6D),
  'koreader': Color(0xFFAE8BFF),
  'kobo': Color(0xFF50BFBE),
  'audiobookshelf': Color(0xFFE48233),
  'bookorbit': Color(0xFF4DACF6),
};

const Map<String, String> readingLogSourceNames = {
  'absorb': 'Absorb',
  'android': 'Android',
  'ios': 'iOS',
  'watchos': 'Watch',
  'koreader': 'KOReader',
  'kobo': 'Kobo',
  'audiobookshelf': 'ABS',
  'bookorbit': 'BookOrbit',
};

const _changeColor = Color(0xFFE59B73);
const _tabular = [FontFeature.tabularFigures()];

const _title = 'Reading log';
const _none = 'Nothing logged yet';
const _sessions = 'sessions';
const _total = 'total';
const _avg = 'avg';
const _at = 'at';
const _listen = 'Listen';
const _read = 'Read';
const _readAlong = 'Read-along';
const _today = 'Today';
const _yesterday = 'Yesterday';

/// BookOrbit's reading log in brief: totals, a bar per session with the
/// progress line over it, and the latest three sessions.
class ReadingLogCard extends StatelessWidget {
  final String itemId;
  final Color accent;

  const ReadingLogCard({super.key, required this.itemId, required this.accent});

  @override
  Widget build(BuildContext context) {
    final stats = BookStatsService.instance.stats(itemId);
    return ListenableBuilder(
      listenable: stats,
      builder: (context, _) => _build(context, stats),
    );
  }

  Widget _build(BuildContext context, BookStats s) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final muted = cs.onSurfaceVariant;
    final line = cs.onSurface.withValues(alpha: 0.08);
    final box = BoxDecoration(
      color: cs.onSurface.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: line),
    );
    final heading = tt.labelSmall?.copyWith(
      color: muted,
      letterSpacing: 1,
      fontWeight: FontWeight.w600,
    );
    final entries = s.sessions.map(ReadingLogEntry.fromSession).toList();

    if (entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: box,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title.toUpperCase(), style: heading),
            const SizedBox(height: 8),
            if (s.loading && !s.failed)
              const LinearProgressIndicator(minHeight: 2)
            else
              Text(
                s.failed ? l.statsCouldNotLoad : _none,
                style: tt.bodySmall?.copyWith(color: muted),
              ),
          ],
        ),
      );
    }

    final totals = context.read<AuthProvider>().apiService?.readingLogStats(
      itemId,
    );
    final count = (totals?['totalSessions'] as num?)?.toInt() ?? s.mySessions;
    final seconds =
        (totals?['totalSeconds'] as num?)?.toDouble() ?? s.mySeconds;
    final avg =
        (totals?['avgDurationSeconds'] as num?)?.toDouble() ??
        (count == 0 ? 0.0 : seconds / count);
    final at =
        (totals?['latestEndProgress'] as num?)?.toDouble() ??
        entries
            .firstWhere((e) => e.reached != null, orElse: () => entries.first)
            .reached;
    final latest = entries.first.startedAt;

    final recent = entries.take(3).toList();
    final cols = _Columns.measure(
      context,
      recent,
      _changeStyle(tt),
      _lengthStyle(tt),
    );

    Widget stat(String value, String label) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          TextSpan(
            text: ' $label',
            style: tt.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      decoration: box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: _title.toUpperCase(), style: heading),
                      if (latest != null)
                        TextSpan(
                          text: ' · last read ${_when(context, latest)}',
                          style: tt.labelSmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => showPlaybackHistorySheet(
                  context,
                  itemId: itemId,
                  initialTab: PlaybackHistoryTab.sessions,
                  accent: accent,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'All $count',
                          style: tt.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: accent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 14,
                  children: [
                    stat('$count', _sessions),
                    stat(formatHm(seconds), _total),
                    stat(length(avg), _avg),
                  ],
                ),
              ),
              if (at != null) stat('${at.round()}%', _at),
            ],
          ),
          const SizedBox(height: 10),
          ReadingLogChart(
            entries: entries.take(28).toList().reversed.toList(),
            line: line,
          ),
          const SizedBox(height: 3),
          _chartLabels(context, entries, tt, muted),
          const SizedBox(height: 8),
          for (final e in recent) ...[
            Divider(height: 1, thickness: 1, color: line),
            _row(context, e, tt, cs, cols),
          ],
        ],
      ),
    );
  }

  Widget _chartLabels(
    BuildContext context,
    List<ReadingLogEntry> entries,
    TextTheme tt,
    Color muted,
  ) {
    final shown = entries.take(28).toList();
    final first = shown.last.startedAt;
    final last = shown.first.startedAt;
    final sameDay =
        first != null && last != null && DateUtils.isSameDay(first, last);
    String label(DateTime? d) =>
        d == null ? '' : (sameDay ? time(context, d) : day(context, d));
    final used = readingLogSourceColors.keys
        .where((k) => shown.any((e) => _dotSource(e) == k))
        .toList();
    final small = tt.labelSmall?.copyWith(color: muted, fontSize: 10);
    final legend = Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      children: [
        for (final k in used)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dot(readingLogSourceColors[k]!),
              const SizedBox(width: 4),
              Text(readingLogSourceNames[k]!, style: small, maxLines: 1),
            ],
          ),
      ],
    );
    final scaler = MediaQuery.textScalerOf(context);
    double w(String text) {
      final p = TextPainter(
        text: TextSpan(text: text, style: small),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = p.width;
      p.dispose();
      return width;
    }

    // Dates either side with the legend between, or the legend on its own
    // line when large text leaves it no room.
    final needed = w(label(first)) +
        w(label(last)) +
        used.fold<double>(0, (sum, k) => sum + 11 + w(readingLogSourceNames[k]!) + 10) +
        8;
    return LayoutBuilder(builder: (context, box) {
      if (needed <= box.maxWidth) {
        return Row(children: [
          Text(label(first), style: small),
          Expanded(child: legend),
          Text(label(last), style: small),
        ]);
      }
      return Column(children: [
        Row(children: [
          Flexible(child: Text(label(first), style: small, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const Spacer(),
          Flexible(child: Text(label(last), style: small, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 2),
        legend,
      ]);
    });
  }

  /// The chart's legend names BookOrbit's buckets; only rows say Absorb.
  static String _dotSource(ReadingLogEntry e) =>
      e.source == 'absorb' ? 'android' : e.source;

  static TextStyle? _changeStyle(TextTheme tt) => tt.bodySmall?.copyWith(
    color: _changeColor,
    fontFeatures: _tabular,
    height: 1.5,
  );

  static TextStyle? _lengthStyle(TextTheme tt) => tt.bodyMedium?.copyWith(
    fontWeight: FontWeight.w700,
    fontFeatures: _tabular,
    height: 1.4,
  );

  static String _delta(double d) =>
      '${d < 0 ? '\u2212' : '+'}${d.abs().toStringAsFixed(1)}%';

  static String _reached(ReadingLogEntry e) =>
      e.reached == null ? '\u2013' : '${e.reached!.round()}%';

  /// How far the session moved and where it ended, read as one: "+4.1% → 65%".
  static String change(ReadingLogEntry e) => e.delta == null
      ? _reached(e)
      : '${_delta(e.delta!)} \u2192 ${_reached(e)}';

  /// [change] as shown, with the arrow drawn as an icon centred on the digits:
  /// the font's own arrow sat low and thin beside them.
  static InlineSpan changeSpan(ReadingLogEntry e, TextStyle? style) => e.delta == null
      ? TextSpan(text: _reached(e), style: style)
      : arrowSpan(_delta(e.delta!), _reached(e), style);

  /// "[from] → [to]" with the arrow as a centred icon in [style]'s colour.
  static InlineSpan arrowSpan(String from, String to, TextStyle? style) => TextSpan(style: style, children: [
        TextSpan(text: '$from '),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(Icons.arrow_forward_rounded, size: (style?.fontSize ?? 12) * 1.05, color: style?.color),
        ),
        TextSpan(text: ' $to'),
      ]);

  Widget _row(
    BuildContext context,
    ReadingLogEntry e,
    TextTheme tt,
    ColorScheme cs,
    _Columns cols,
  ) {
    final how = switch (e.mode) {
      ReadingMode.listen => _listen,
      ReadingMode.read => _read,
      ReadingMode.readAlong => _readAlong,
    };
    final change = _changeStyle(tt);
    final icon = SizedBox(
      height: 18,
      child: Center(child: ReadingModeIcon(e.mode, color: cs.onSurfaceVariant)),
    );
    final label = Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          e.startedAt == null ? '' : _when(context, e.startedAt!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.4),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(readingLogSourceColors[e.source] ?? cs.outline),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$how · ${readingLogSourceNames[e.source] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
    final numbers = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: cols.change,
          child: Text.rich(ReadingLogCard.changeSpan(e, change),
              textAlign: TextAlign.left, maxLines: 1, softWrap: false, style: change),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: cols.length,
          child: Text(length(e.seconds),
              textAlign: TextAlign.right, maxLines: 1, softWrap: false, style: _lengthStyle(tt)),
        ),
      ],
    );
    // Icon, gaps and the least room the time and source get beside the numbers.
    const iconWidth = 22.0;
    const minLabel = 110.0;
    final numbersWidth = 6 + cols.change + 8 + cols.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth - iconWidth - numbersWidth >= minLabel) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            icon,
            const SizedBox(width: 4),
            Expanded(child: label),
            const SizedBox(width: 6),
            numbers,
          ]);
        }
        // Large text on a narrow screen: the numbers take their own line.
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            icon,
            const SizedBox(width: 4),
            Expanded(child: label),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: iconWidth, top: 2),
            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: numbers),
          ),
        ]);
      }),
    );
  }

  static Widget _dot(Color c) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  /// Seconds for the shortest sessions, which formatHm would show as 0m.
  static String length(double seconds) =>
      seconds < 60 ? '${seconds.round()}s' : formatHm(seconds);

  static String time(BuildContext context, DateTime d) {
    final locale = Localizations.localeOf(context).toString();
    return MediaQuery.alwaysUse24HourFormatOf(context)
        ? DateFormat.Hm(locale).format(d)
        : DateFormat('h:mm', locale).format(d);
  }

  /// Today, Yesterday, the weekday within a week, else the date.
  static String day(BuildContext context, DateTime d) {
    final locale = Localizations.localeOf(context).toString();
    final today = DateUtils.dateOnly(DateTime.now());
    final days = today.difference(DateUtils.dateOnly(d)).inDays;
    if (days == 0) return _today;
    if (days == 1) return _yesterday;
    if (days < 7) return DateFormat.E(locale).format(d);
    return d.year == today.year
        ? DateFormat.MMMd(locale).format(d)
        : DateFormat.yMMMd(locale).format(d);
  }

  static String _when(BuildContext context, DateTime d) =>
      '${day(context, d)} ${time(context, d)}';
}

/// Widths of the change and length columns, measured in the row's own font
/// and text size so each row's change starts at the same place and nothing
/// is clipped.
class _Columns {
  final double change, length;
  const _Columns(this.change, this.length);

  static _Columns measure(
    BuildContext context,
    List<ReadingLogEntry> rows,
    TextStyle? change,
    TextStyle? length,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    double w(String text, TextStyle? style) {
      final p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = p.width.ceilToDouble();
      p.dispose();
      return width;
    }

    double widest(Iterable<String> texts, TextStyle? style) =>
        texts.fold(0, (m, t) => math.max(m, w(t, style)));
    // The row draws the arrow as an icon (changeSpan), which can be wider
    // than the font's arrow measured here, so the column takes the gap.
    final arrowGap = math.max(0.0, scaler.scale((change?.fontSize ?? 12) * 1.05) - w('\u2192', change)).ceilToDouble();
    return _Columns(
      widest(rows.map(ReadingLogCard.change), change) + arrowGap,
      widest([
        '0m',
        ...rows.map((e) => ReadingLogCard.length(e.seconds)),
      ], length),
    );
  }
}

/// Listen, read or read-along, the last a book with headphones on it.
class ReadingModeIcon extends StatelessWidget {
  final ReadingMode mode;
  final Color color;
  final double size;
  const ReadingModeIcon(this.mode, {super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) => switch (mode) {
    ReadingMode.listen => Icon(Icons.headphones_rounded, size: size, color: color),
    ReadingMode.read => Icon(Icons.menu_book_rounded, size: size, color: color),
    ReadingMode.readAlong => SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.menu_book_rounded, size: size * 0.8, color: color),
          Positioned(
            right: -size / 16,
            bottom: -size / 16,
            child: Icon(Icons.headphones_rounded, size: size * 0.56, color: color),
          ),
        ],
      ),
    ),
  };
}

/// A bar per session (length, coloured by where it happened) with the
/// progress each one reached drawn over them.
class ReadingLogChart extends StatelessWidget {
  final List<ReadingLogEntry> entries;
  final Color line;
  final double height;
  const ReadingLogChart({
    super.key,
    required this.entries,
    required this.line,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    final maxSecs = entries.fold<double>(1, (m, e) => math.max(m, e.seconds));
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _ProgressPainter(entries, line, null),
        foregroundPainter: _ProgressPainter(
          entries,
          null,
          Theme.of(context).colorScheme.onSurface,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 0.5),
                  // Square root so a 15 second session still shows beside an hour.
                  height: math.max(
                    3,
                    height /
                        2 *
                        math.sqrt(math.max(0, entries[i].seconds) / maxSecs),
                  ),
                  decoration: BoxDecoration(
                    color: (readingLogSourceColors[entries[i].source] ?? line)
                        .withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Behind the bars it draws the 100% and 50% guides ([grid]); in front, the
/// progress line ([stroke]).
class _ProgressPainter extends CustomPainter {
  final List<ReadingLogEntry> entries;
  final Color? grid;
  final Color? stroke;
  _ProgressPainter(this.entries, this.grid, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = this.grid;
    if (grid != null) {
      final gridPaint = Paint()
        ..color = grid
        ..strokeWidth = 1;
      for (final y in [0.5, size.height / 2]) {
        for (var x = 0.0; x < size.width; x += 6) {
          canvas.drawLine(
            Offset(x, y),
            Offset(math.min(x + 3, size.width), y),
            gridPaint,
          );
        }
      }
    }
    final stroke = this.stroke;
    if (stroke == null) return;
    final path = Path();
    var started = false;
    final n = entries.length;
    for (var i = 0; i < n; i++) {
      final p = entries[i].reached;
      if (p == null) continue;
      final pt = Offset(
        (i + 0.5) / n * size.width,
        size.height * (1 - p.clamp(0, 100) / 100),
      );
      started ? path.lineTo(pt.dx, pt.dy) : path.moveTo(pt.dx, pt.dy);
      started = true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.entries != entries || old.stroke != stroke || old.grid != grid;
}
