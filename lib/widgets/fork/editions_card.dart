import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/library_provider.dart';
import '../../services/api_service.dart';
import '../../services/fork/position_sync_chain.dart';
import '../../services/fork/position_sync_controller.dart';
import '../../services/fork/work_editions.dart';
import '../book_detail_sheet.dart' show showBookDetailSheet;
import 'position_sync_sheet.dart';
import 'watchlist_cover_badges.dart' show WatchlistDashedBorder;

// Fork-owned: the Editions card on a BookOrbit book page, listing the work's
// audiobook, read-along and ebook from the book's position sync link. A row
// opens that edition's page; a missing one opens the Position sync sheet.
// Hooked in from book_detail_redesign.dart. See FORK_NOTES.md.

// New text stays plain until upstream takes it (FORK_NOTES rule 4).
const _kEditions = 'Editions';
const _kNotLinked = 'Not linked';
const _kLink = 'Link';
const _kNotGenerated = 'Not generated yet';
const _kGenerate = 'Generate';
const _kBuilding = 'Being generated';
const _kView = 'View';

class ForkEditionsCard extends StatefulWidget {
  final String itemId;
  final BookOrbitApiService api;
  final Color accent;
  final String title;
  final String authorName;

  /// This book's progress as the page shows it (0..1), fresher than the
  /// link's copy.
  final double progress;

  /// The cover's container colour for the Position sync sheet.
  final Color? tint;

  const ForkEditionsCard({
    super.key,
    required this.itemId,
    required this.api,
    required this.accent,
    required this.title,
    required this.authorName,
    required this.progress,
    this.tint,
  });

  @override
  State<ForkEditionsCard> createState() => _ForkEditionsCardState();
}

class _ForkEditionsCardState extends State<ForkEditionsCard> {
  late final PositionSyncController _c;
  // Null once asked when the size is unknown (failed, or no sizes on the files).
  final Map<int, int?> _sizes = {};
  final Set<int> _sizeAsked = {};
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // The page already holds this controller (prefetch and sync button), so
    // its state is there or on its way.
    _c = acquirePositionSync(widget.api, widget.itemId, widget.title, widget.authorName);
  }

  @override
  void dispose() {
    PositionSyncController.release(_c);
    super.dispose();
  }

  /// One book holding both formats, or neither, has no other editions; its
  /// snapshot would label it as one of them.
  bool get _holdsBothOrNone {
    final m = _c.info?.modality;
    return _c.role == null && (m == PositionSyncModality.both || m == PositionSyncModality.none);
  }

  void _askSize(int id) {
    if (!_sizeAsked.add(id)) return;
    widget.api.editionSizeBytes(id).then<int?>((b) => b > 0 ? b : null, onError: (_) => null).then((b) {
      if (mounted) setState(() => _sizes[id] = b);
    });
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
        if (!_c.loaded || _holdsBothOrNone) return const SizedBox.shrink();
        // What the server has, not what the sync sheet has picked or set
        // aside; a linked pair's read-along waits for its build status.
        final rows = workEditions(_c.availableSnapshot, readAlongKnown: _c.link == null || _c.readAlongChecked);
        if (rows.isEmpty) return const SizedBox.shrink();
        for (final r in rows) {
          if (r.book != null) _askSize(r.book!.id);
        }
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ForkEditionsList(
            rows: rows,
            sizes: _sizes,
            progress: widget.progress,
            accent: widget.accent,
            buildProgress: _c.buttonProgress,
            onOpen: (id) => showBookDetailSheet(context, '$id'),
            onGap: _openSync,
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
  /// Bytes per book id; null when it is known not to be known.
  final Map<int, int?> sizes;
  final double progress;
  final Color accent;
  final double? buildProgress;
  final ValueChanged<int> onOpen;
  final VoidCallback onGap;

  /// Collapsed, the card is one line: an icon per edition and the total.
  final bool expanded;
  final VoidCallback onToggle;

  const ForkEditionsList({
    super.key,
    required this.rows,
    required this.sizes,
    required this.progress,
    required this.accent,
    required this.onOpen,
    required this.onGap,
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
    final books = rows.where((r) => r.book != null).toList();
    // Once every size has answered, the ones that are known.
    final known = [for (final r in books) sizes[r.book!.id]].nonNulls;
    final total = books.every((r) => sizes.containsKey(r.book!.id)) && known.isNotEmpty
        ? known.fold<int>(0, (sum, b) => sum + b)
        : null;
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
                        total == null ? '${books.length}' : '${books.length} · ${formatSyncBytes(total)}',
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
            for (final r in rows) r.book != null ? _bookRow(context, r, roomy) : _gapRow(context, r, roomy),
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
  /// labelled badge on its row: filled for this book, tinted for another,
  /// dashed for a missing one.
  Widget _mark(BuildContext context, WorkEdition r, {required bool label}) {
    final color = syncEditionColor(context, r.kind);
    final fg = r.gap != null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : r.isThisBook
        ? (Theme.of(context).brightness == Brightness.dark ? Colors.black87 : Colors.white)
        : color;
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
              color: r.isThisBook ? color : color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: content,
          );
    return label ? mark : Tooltip(message: editionShortName(r.kind), child: mark);
  }

  Widget _bookRow(BuildContext context, WorkEdition r, bool roomy) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final book = r.book!;
    final color = syncEditionColor(context, r.kind);
    final pct = r.isThisBook ? (progress * 100).round() : book.progress;
    final size = roomy ? sizes[book.id] : null;
    final small = tt.labelMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // The book on screen is marked by a soft wash in its edition's colour.
    return Material(
      color: r.isThisBook ? color.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: r.isThisBook ? null : () => onOpen(book.id),
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
                child: r.isThisBook
                    ? null
                    : Tooltip(
                        message: _kView,
                        child: Icon(Icons.chevron_right_rounded, size: 20, color: cs.onSurfaceVariant),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gapRow(BuildContext context, WorkEdition r, bool roomy) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (note, action) = switch (r.gap!) {
      WorkEditionGap.link => (_kNotLinked, _kLink),
      WorkEditionGap.generate => (_kNotGenerated, _kGenerate),
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
      onTap: onGap,
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
