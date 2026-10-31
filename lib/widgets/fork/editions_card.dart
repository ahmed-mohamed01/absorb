import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/library_provider.dart';
import '../../services/api_service.dart';
import '../../services/fork/position_sync_chain.dart';
import '../../services/fork/position_sync_controller.dart';
import '../../services/fork/work_editions.dart';
import 'position_sync_sheet.dart';
import 'watchlist_cover_badges.dart' show WatchlistDashedBorder;

// Fork-owned: the Editions card on a BookOrbit book page, listing the book's
// audiobook, read-aloud and ebook files from its position sync state. A row
// opens the Position sync sheet. Hooked in from book_detail_redesign.dart.
// See FORK_NOTES.md.

// New text stays plain until upstream takes it (FORK_NOTES rule 4).
const _kEditions = 'Editions';
const _kNotCreated = 'Not created yet';
const _kCreate = 'Create';
const _kBuilding = 'Being created';
const _kSync = 'Position sync';

class ForkEditionsCard extends StatefulWidget {
  final String itemId;
  final BookOrbitApiService api;
  final Color accent;

  /// This book's progress as the page shows it (0..1), fresher than the
  /// sync state's copy of the audiobook's.
  final double progress;

  /// The cover's container colour for the Position sync sheet.
  final Color? tint;

  const ForkEditionsCard({
    super.key,
    required this.itemId,
    required this.api,
    required this.accent,
    required this.progress,
    this.tint,
  });

  @override
  State<ForkEditionsCard> createState() => _ForkEditionsCardState();
}

class _ForkEditionsCardState extends State<ForkEditionsCard> {
  late final PositionSyncController _c;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // The page already holds this controller (prefetch and sync button), so
    // its state is there or on its way.
    _c = acquirePositionSync(widget.api, widget.itemId);
  }

  @override
  void dispose() {
    PositionSyncController.release(_c);
    super.dispose();
  }

  void _openSync() => showPositionSyncSheet(
    context,
    _c,
    widget.accent,
    coverHeaders: context.read<LibraryProvider>().mediaHeaders,
    tint: widget.tint,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        if (!_c.loaded) return const SizedBox.shrink();
        final rows = workEditions(_c.snapshot);
        if (rows.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ForkEditionsList(
            rows: rows,
            audioProgress: widget.progress,
            accent: widget.accent,
            buildProgress: _c.buttonProgress,
            onOpen: _openSync,
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
          ),
        );
      },
    );
  }
}

/// The card itself, apart from where its rows come from.
class ForkEditionsList extends StatelessWidget {
  final List<WorkEdition> rows;

  /// The page's progress (0..1), which the audiobook row shows.
  final double audioProgress;
  final Color accent;
  final double? buildProgress;

  /// Any row opens the Position sync sheet.
  final VoidCallback onOpen;

  /// Collapsed, the card is one line: an icon per edition and the total.
  final bool expanded;
  final VoidCallback onToggle;

  const ForkEditionsList({
    super.key,
    required this.rows,
    required this.audioProgress,
    required this.accent,
    required this.onOpen,
    required this.onToggle,
    this.expanded = false,
    this.buildProgress,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Each row's size needs about 300 px at normal text; below that it
      // stays in the header's total only.
      final roomy = box.maxWidth >= MediaQuery.textScalerOf(context).scale(300);
      return _card(context, roomy);
    },
  );

  Widget _card(BuildContext context, bool roomy) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final muted = cs.onSurfaceVariant;
    final books = rows.where((r) => r.edition != null).toList();
    final total = books.fold<int>(0, (sum, r) => sum + r.edition!.sizeBytes);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(6, 8, 4, expanded ? 6 : 8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, right: 4, top: 2, bottom: 2),
              child: Row(
                children: [
                  Flexible(
                    flex: roomy ? 0 : 1,
                    child: Text(
                      _kEditions.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall?.copyWith(color: muted, letterSpacing: 1, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 10),
                  for (final r in rows) Padding(padding: const EdgeInsets.only(right: 4), child: _mark(context, r, label: false)),
                  const SizedBox(width: 4),
                  // Narrow or with large text the marks need the room.
                  if (roomy)
                    Expanded(
                      child: Text(
                        total == 0 ? '${books.length}' : '${books.length} · ${formatSyncBytes(total)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: tt.labelSmall?.copyWith(color: muted),
                      ),
                    )
                  else
                    const Spacer(),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded, size: 20, color: muted),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) const SizedBox(height: 4),
          if (expanded)
            for (final r in rows) r.edition != null ? _editionRow(context, r, roomy) : _gapRow(context, r, roomy),
        ],
      ),
    );
  }

  /// One width for every badge, so the bars and gap notes line up.
  Widget _badgeSlot(BuildContext context, WorkEdition r) => SizedBox(
    width: MediaQuery.textScalerOf(context).scale(122).clamp(0, 140).toDouble(),
    child: Align(alignment: Alignment.centerLeft, child: _mark(context, r, label: true)),
  );

  /// How one edition is marked, as a round icon in the collapsed line or a
  /// labelled badge on its row: filled for one the book holds, dashed for a
  /// missing one.
  Widget _mark(BuildContext context, WorkEdition r, {required bool label}) {
    final color = syncEditionColor(context, r.kind);
    final fg = r.gap != null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : (Theme.of(context).brightness == Brightness.dark ? Colors.black87 : Colors.white);
    final icon = Icon(syncEditionIcon(r.kind), size: label ? 14 : 13, color: fg);
    final content = label
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    editionShortName(r.kind),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
                  ),
                ),
              ],
            ),
          )
        : SizedBox.square(dimension: 22, child: Center(child: icon));
    final radius = label ? 14.0 : 11.0;
    final mark = r.gap != null
        ? CustomPaint(
            painter: WatchlistDashedBorder(color: Theme.of(context).colorScheme.outline, radius: radius, strokeWidth: 1),
            child: content,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: content,
          );
    return label ? mark : Tooltip(message: editionShortName(r.kind), child: mark);
  }

  Widget _editionRow(BuildContext context, WorkEdition r, bool roomy) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final edition = r.edition!;
    final color = syncEditionColor(context, r.kind);
    final pct = r.kind == SyncEdition.audiobook ? (audioProgress * 100).round() : edition.progress;
    final size = roomy && edition.sizeBytes > 0 ? edition.sizeBytes : null;
    final small = tt.labelMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            _badgeSlot(context, r),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (pct ?? 0) / 100,
                  minHeight: 5,
                  color: color,
                  backgroundColor: cs.onSurface.withValues(alpha: 0.10),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(pct == null ? '–' : '$pct%', style: small),
            if (size != null) ...[const SizedBox(width: 10), Text(formatSyncBytes(size), style: small)],
            SizedBox(
              width: 24,
              child: Tooltip(
                message: _kSync,
                child: Icon(Icons.chevron_right_rounded, size: 20, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gapRow(BuildContext context, WorkEdition r, bool roomy) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (note, action) = switch (r.gap!) {
      WorkEditionGap.generate => (_kNotCreated, _kCreate),
      WorkEditionGap.building => (_kBuilding, ''),
    };
    final actionText = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        action,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: accent),
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            _badgeSlot(context, r),
            const SizedBox(width: 10),
            // Narrow, the action alone says it.
            if (roomy)
              Expanded(
                child: Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              )
            else if (r.gap == WorkEditionGap.building)
              const Spacer(),
            if (r.gap == WorkEditionGap.building)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, value: buildProgress, color: accent),
                ),
              )
            else if (roomy)
              actionText
            else
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: actionText),
              ),
          ],
        ),
      ),
    );
  }
}
