import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'reading_log_card.dart';

const readingLogTabTitle = 'Reading log';
const _changeColor = Color(0xFFE59B73);

/// Most sessions the chart draws; past this each bar would be under a pixel.
const _chartMax = 60;

/// The full BookOrbit log. Fetching and session details belong to the host sheet.
class ReadingLogList extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  final ScrollController scrollController;
  final ValueChanged<Map<String, dynamic>> onSessionTap;

  const ReadingLogList({
    super.key,
    required this.sessions,
    required this.scrollController,
    required this.onSessionTap,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = sessions.toList()
      ..sort(
        (a, b) => ((b['startedAt'] as num?) ?? 0).compareTo(
          (a['startedAt'] as num?) ?? 0,
        ),
      );
    final groups = <DateTime?, List<Map<String, dynamic>>>{};
    for (final session in sorted) {
      final at = ReadingLogEntry.fromSession(session).startedAt;
      groups
          .putIfAbsent(at == null ? null : DateUtils.dateOnly(at), () => [])
          .add(session);
    }
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _progress(
          context,
          sorted.map(ReadingLogEntry.fromSession).toList().reversed.toList(),
        ),
        for (final group in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _day(context, group.key),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${ReadingLogCard.length(group.value.fold<double>(0, (sum, s) => sum + ReadingLogEntry.fromSession(s).seconds))} · ${group.value.length} ${group.value.length == 1 ? 'session' : 'sessions'}',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: _box(context),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < group.value.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 12, endIndent: 12),
                  _row(context, group.value[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  BoxDecoration _box(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.onSurface.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
    );
  }

  String _day(BuildContext context, DateTime? day) {
    if (day == null) return 'Unknown date';
    final today = DateUtils.dateOnly(DateTime.now());
    final prefix = day == today
        ? 'Today · '
        : day == DateUtils.addDaysToDate(today, -1)
        ? 'Yesterday · '
        : '';
    final locale = Localizations.localeOf(context).toString();
    return '$prefix${DateFormat(day.year == today.year ? 'EEE, MMM d' : 'EEE, MMM d, y', locale).format(day)}';
  }

  Widget _progress(BuildContext context, List<ReadingLogEntry> all) {
    // The latest sessions only: hundreds would leave no bar visible. The
    // range, dates and legend describe the same sessions the bars do.
    final entries = all.length > _chartMax ? all.sublist(all.length - _chartMax) : all;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final reached = entries.where((e) => e.reached != null).toList();
    String percent(ReadingLogEntry e) => '${e.reached!.round()}%';
    String label(ReadingLogEntry e) => e.startedAt == null
        ? ''
        : '${ReadingLogCard.day(context, e.startedAt!)} ${ReadingLogCard.time(context, e.startedAt!)}';
    final sources = readingLogSourceColors.keys.where(
      (s) => entries.any((e) => e.source == s),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _box(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SESSIONS & PROGRESS',
                  style: tt.labelSmall?.copyWith(letterSpacing: 1),
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text.rich(
                  reached.isEmpty
                      ? const TextSpan(text: 'no position')
                      : ReadingLogCard.arrowSpan(percent(reached.first), percent(reached.last), tt.labelMedium),
                  textAlign: TextAlign.right,
                  style: tt.labelMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ReadingLogChart(
                  entries: entries,
                  line: cs.onSurface.withValues(alpha: 0.15),
                  height: 96,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('100%', style: tt.labelSmall),
                    const Spacer(),
                    Text('50%', style: tt.labelSmall),
                    const Spacer(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (entries.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    label(entries.first),
                    style: tt.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label(entries.last),
                    style: tt.labelSmall,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final source in sources)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dot(source),
                    const SizedBox(width: 4),
                    Text(readingLogSourceNames[source]!, style: tt.labelSmall),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(String source) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      color: readingLogSourceColors[source],
      shape: BoxShape.circle,
    ),
  );

  Widget _row(BuildContext context, Map<String, dynamic> session) {
    final e = ReadingLogEntry.fromSession(session);
    final tt = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final mode = switch (e.mode) {
      ReadingMode.listen => 'Listen',
      ReadingMode.read => 'Read',
      ReadingMode.readAlong => 'Read-along',
    };
    final jump = (e.delta ?? 0) > 20 && e.seconds < 60;
    return InkWell(
      onTap: () => onSessionTap(session),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ReadingModeIcon(e.mode, color: muted, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.startedAt == null
                        ? 'Unknown time'
                        : ReadingLogCard.time(context, e.startedAt!),
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      _dot(e.source),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '$mode · ${readingLogSourceNames[e.source]}',
                          style: tt.bodySmall?.copyWith(color: muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (jump)
                    Text(
                      'Big jump for ${ReadingLogCard.length(e.seconds)} · likely a position sync',
                      style: tt.labelSmall?.copyWith(
                        color: Colors.amber.shade700,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    ReadingLogCard.length(e.seconds),
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text.rich(
                    e.reached == null
                        ? const TextSpan(text: 'no position')
                        : ReadingLogCard.changeSpan(e, tt.bodySmall?.copyWith(color: _changeColor)),
                    style: tt.bodySmall?.copyWith(
                      color: e.reached == null ? muted : _changeColor,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
