import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/api_service.dart';
import '../../services/fork/position_sync_chain.dart';
import '../../services/fork/position_sync_controller.dart';
import '../adaptive_modal.dart';
import '../book_detail_sheet.dart' show showBookDetailSheet;
import '../overlay_toast.dart';
import '../stackable_sheet.dart';
import 'tinted_sheet.dart';

// Fork-owned: the BookOrbit Position sync button in the detail icon row and
// its sheet (the chain of linked editions, Generate read-along, Change
// edition; tapping another edition's card opens its page). The hooks are
// the import in book_detail_sheet.dart and the button in `_forkIconRow`.
// See FORK_NOTES.md.

const _green = Color(0xFF8FDCA8);
const _amber = Color(0xFFF2C46D);
const _red = Color(0xFFF28B82);
const _blue = Color(0xFF8AB4F8);

// The pastel tones are for dark sheets; a light sheet needs them deeper to
// stay readable.
Color _tone(BuildContext context, ChainTone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (tone) {
    case ChainTone.success:
      return dark ? _green : const Color(0xFF2E7D4F);
    case ChainTone.warning:
      return dark ? _amber : const Color(0xFF9A6700);
    case ChainTone.destructive:
      return dark ? _red : const Color(0xFFC5221F);
    case ChainTone.info:
      return dark ? _blue : const Color(0xFF1A5FB4);
    case ChainTone.muted:
      return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

Widget _tag(String text, Color color, {double fontSize = 11, EdgeInsets? padding}) => Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: color)),
    );

IconData syncEditionIcon(SyncEdition e) => switch (e) {
      SyncEdition.audiobook => Icons.headphones_rounded,
      SyncEdition.ebook => Icons.menu_book_rounded,
      SyncEdition.readAlong => Icons.record_voice_over_rounded,
      SyncEdition.abs => Icons.home_work_rounded,
    };

/// Each edition's own colour, as the Editions card draws it.
Color syncEditionColor(BuildContext context, SyncEdition e) => _tone(context, switch (e) {
      SyncEdition.audiobook => ChainTone.warning,
      SyncEdition.readAlong => ChainTone.success,
      SyncEdition.ebook => ChainTone.info,
      SyncEdition.abs => ChainTone.muted,
    });

String _editionKind(SyncEdition e) => e == SyncEdition.abs ? PositionSyncCopy.kindAbs : editionShortName(e);

String formatSyncBytes(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}

/// Where a connector row's switch sits: the row's 6 px top padding plus half
/// its 44 px switch box; the rail leaves the 32 px track and a few px clear.
const double _switchCenter = 6 + 44 / 2;
const double _railGapHalf = 18;

// ─── Button ─────────────────────────────────────────────────

/// The detail page's top-bar Position sync button. It shows nothing for a
/// book with nothing to link.
class ForkSyncButton extends StatefulWidget {
  final String itemId;
  final Color accent;
  final BookOrbitApiService api;
  final String title;
  final String authorName;
  /// The cover's container colour, which tints the sheet like the page it
  /// opens over. Null keeps the plain sheet colour.
  final Color? tint;

  const ForkSyncButton({
    super.key,
    required this.itemId,
    required this.accent,
    required this.api,
    required this.title,
    required this.authorName,
    this.tint,
  });

  /// Only BookOrbit books on a reachable server; dock items have no numeric
  /// id.
  static bool shouldShow(AuthProvider auth, LibraryProvider lib, String itemId) =>
      auth.isBookOrbit && !lib.isOffline && auth.apiService is BookOrbitApiService && int.tryParse(itemId) != null;

  @override
  State<ForkSyncButton> createState() => _ForkSyncButtonState();
}

class _ForkSyncButtonState extends State<ForkSyncButton> {
  late final PositionSyncController _c;

  @override
  void initState() {
    super.initState();
    _c = acquirePositionSync(widget.api, widget.itemId, widget.title, widget.authorName);
  }

  @override
  void didUpdateWidget(ForkSyncButton old) {
    super.didUpdateWidget(old);
    _c.describeThisBook(widget.title, widget.authorName);
  }

  @override
  void dispose() {
    PositionSyncController.release(_c);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        if (!_c.eligible) return const SizedBox.shrink();
        return _barButton(context);
      },
    );
  }

  /// The same states as [_button] on a bare icon for the detail page's top
  /// bar, drawn the way the bookmark beside it is: the sheet's swap icon,
  /// outlined until the editions are linked, filled in the cover's accent
  /// when they're in sync, outlined in the accent when one wants checking,
  /// filled red when something needs attention, and in the blue build ring
  /// while a read-along is made.
  Widget _barButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = _c.buttonState;
    final building = state == SyncButtonState.building;
    final (IconData icon, Color? color) = switch (state) {
      SyncButtonState.inSync => (Icons.swap_horizontal_circle, widget.accent),
      SyncButtonState.checkSync => (Icons.swap_horizontal_circle_outlined, widget.accent),
      SyncButtonState.needsAttention => (Icons.swap_horizontal_circle, cs.error),
      _ => (Icons.swap_horizontal_circle_outlined, null),
    };
    return IconButton(
      tooltip: _c.buttonTooltip,
      onPressed: () => showPositionSyncSheet(context, _c, widget.accent,
          coverHeaders: context.read<LibraryProvider>().mediaHeaders, tint: widget.tint),
      icon: SizedBox(width: 26, height: 26, child: Stack(alignment: Alignment.center, children: [
        if (building)
          CircularProgressIndicator(strokeWidth: 2.5, value: _c.buttonProgress, color: _blue,
              backgroundColor: cs.onSurface.withValues(alpha: 0.12)),
        Icon(icon, size: building ? 16 : 24, color: building ? null : color),
      ])),
    );
  }
}

/// Takes a book's shared controller for a widget on its page and starts it
/// loading after the frame (loading notifies, and the sheet may be
/// listening). Release it with [PositionSyncController.release].
PositionSyncController acquirePositionSync(BookOrbitApiService api, String itemId, String title, String authorName) {
  final c = PositionSyncController.acquire(api, int.parse(itemId))..describeThisBook(title, authorName);
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(c.loadInitial()));
  return c;
}

/// Starts a book's sync state loading as its detail sheet opens, beside the
/// book itself, so the button's status arrives with the rest of the sheet.
/// Call the returned release when the sheet closes.
VoidCallback? prefetchPositionSync(AuthProvider auth, LibraryProvider lib, String itemId) {
  if (!ForkSyncButton.shouldShow(auth, lib, itemId)) return null;
  final c = PositionSyncController.acquire(auth.apiService as BookOrbitApiService, int.parse(itemId));
  // After the frame, as the button does: loading notifies.
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(c.loadInitial()));
  return () => PositionSyncController.release(c);
}

// ─── Sheet ──────────────────────────────────────────────────

Future<void> showPositionSyncSheet(BuildContext context, PositionSyncController controller, Color accent,
    {Map<String, String> coverHeaders = const {}, Color? tint}) {
  return showStackableSheet(
    context: context,
    useSafeArea: true,
    initialChildSize: 0.85,
    maxChildSize: 0.95,
    builder: (ctx, sc) => _PositionSyncSheet(
      controller: controller,
      accent: accent,
      coverHeaders: coverHeaders,
      scrollController: sc,
      tint: tint,
    ),
  );
}

enum _Page { chain, generate, change }

class _PositionSyncSheet extends StatefulWidget {
  final PositionSyncController controller;
  final Color accent;
  final Map<String, String> coverHeaders;
  final ScrollController scrollController;
  final Color? tint;

  const _PositionSyncSheet({
    required this.controller,
    required this.accent,
    required this.coverHeaders,
    required this.scrollController,
    this.tint,
  });

  @override
  State<_PositionSyncSheet> createState() => _PositionSyncSheetState();
}

class _PositionSyncSheetState extends State<_PositionSyncSheet> {
  late final PositionSyncController _c;
  _Page _page = _Page.chain;
  SyncEdition? _changeEdition;
  EditionLinkCandidateWire? _changePick;
  final _query = TextEditingController();
  final Set<ConnectorKey> _explained = {};

  Color get _accent => widget.accent;

  @override
  void initState() {
    super.initState();
    // Its own reference, so polling lives while the sheet is open even if
    // the detail sheet underneath goes away.
    _c = PositionSyncController.acquire(widget.controller.api, widget.controller.bookId);
    _c.onNotice = _toast;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_c.open());
    });
  }

  @override
  void dispose() {
    if (_c.onNotice == _toast) _c.onNotice = null;
    _query.dispose();
    PositionSyncController.release(_c);
    super.dispose();
  }

  void _toast(PositionSyncNotice n) {
    if (!mounted) return;
    showOverlayToast(context, n.message,
        icon: switch (n.kind) {
          PositionSyncNoticeKind.success => Icons.check_circle_rounded,
          PositionSyncNoticeKind.error => Icons.error_outline_rounded,
          PositionSyncNoticeKind.info => Icons.info_outline_rounded,
        });
  }

  void _go(_Page page) => setState(() {
        _page = page;
        if (page != _Page.change) {
          _changeEdition = null;
          _changePick = null;
          _query.clear();
        }
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      // The book page's own cover gradient, so the sheet reads as part of it.
      decoration: forkTintedSheetDecoration(context, widget.tint),
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => ListView(
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.of(context).viewPadding.bottom),
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2)))),
            ...switch (_page) {
              _Page.chain => _chainPage(context),
              _Page.generate => _generatePage(context),
              _Page.change => _changePage(context),
            },
          ],
        ),
      ),
    );
  }

  // ─── Chain page ───────────────────────────────────────────

  List<Widget> _chainPage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final chain = _c.chain;
    final header = chain.header;
    final children = <Widget>[
      Row(children: [
        Icon(Icons.sync_alt_rounded, size: 22, color: cs.onSurface),
        const SizedBox(width: 10),
        Flexible(
          child: Text(PositionSyncCopy.title,
              overflow: TextOverflow.ellipsis, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 10),
        if (_c.loaded)
          _tag(header.label, _tone(context, header.tone),
              fontSize: 12, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3)),
      ]),
      const SizedBox(height: 2),
      Text(chain.intro, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      if (_c.loadError != null)
        Row(children: [
          Icon(Icons.error_outline_rounded, size: 16, color: cs.error),
          const SizedBox(width: 6),
          Expanded(child: Text(_c.loadError!, style: TextStyle(fontSize: 13, color: cs.error))),
          TextButton(onPressed: () => _c.open(), child: Text(PositionSyncCopy.actionRetry)),
        ]),
      const SizedBox(height: 14),
    ];
    if (!_c.loaded) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
      ));
      return children;
    }
    // Consecutive group rows (the audiobook with its Audiobookshelf rows)
    // share one box.
    final rows = chain.rows;
    var i = 0;
    while (i < rows.length) {
      if (_frame(rows[i]) == ChainFrame.group) {
        final group = <Widget>[];
        while (i < rows.length && _frame(rows[i]) == ChainFrame.group) {
          group.add(_row(context, rows[i], inGroup: true));
          i++;
        }
        children.add(Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: group),
        ));
      } else {
        children.add(_row(context, rows[i], inGroup: false));
        i++;
      }
    }
    return children;
  }

  static ChainFrame _frame(ChainRow row) => switch (row) {
        ChainCardRow r => r.frame,
        ChainGhostRow r => r.frame,
        ChainConnectorRow r => r.frame,
        ChainReadAlongSlotRow _ => ChainFrame.spine,
      };

  Widget _row(BuildContext context, ChainRow row, {required bool inGroup}) => switch (row) {
        ChainCardRow r => _cardRow(context, r, inGroup: inGroup),
        ChainGhostRow r => _ghostRow(context, r),
        ChainConnectorRow r => _connectorRow(context, r),
        ChainReadAlongSlotRow r => _slotRow(context, r),
      };

  // The edition picks the cover slot: a book with both files has an audio
  // and an ebook cover, and the list default may be either.
  Widget _cover(BuildContext context, ChainCover cover, SyncEdition edition, double w, double h) {
    final cs = Theme.of(context).colorScheme;
    final tile = Container(
      color: cs.onSurface.withValues(alpha: 0.08),
      child: Center(child: Icon(Icons.record_voice_over_rounded, size: w * 0.45, color: cs.onSurfaceVariant)),
    );
    final url = switch (cover) {
      BookCover c => _c.api.getCoverUrl('${c.bookId}',
          width: 200, coverRatio: edition == SyncEdition.audiobook ? 1.0 : 0.66),
      AbsCover c => _c.api.positionSyncAbsCoverUrl(c.absLibraryItemId),
      TileCover _ => null,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: w,
        height: h,
        child: url == null
            ? tile
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                httpHeaders: widget.coverHeaders,
                placeholder: (_, __) => tile,
                errorWidget: (_, __, ___) => tile,
              ),
      ),
    );
  }

  Widget _kindLine(BuildContext context, SyncEdition edition, List<Widget> tags) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(syncEditionIcon(edition), size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(_editionKind(edition),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
      ]),
      ...tags,
    ]);
  }

  String? _cardSubtitle(ChainCardRow r) {
    if (r.change == ChangeState.blocked && r.changeHint != null) return r.changeHint;
    final p = r.progress;
    if (r.edition == SyncEdition.abs) {
      if (p == null && r.progressPending) return PositionSyncCopy.absChecking;
      if (p != null && r.subtitle != null) return '${r.subtitle} · $p%';
      return p != null ? PositionSyncCopy.progressListened(p) : r.subtitle;
    }
    if (p != null) {
      return r.edition == SyncEdition.audiobook ? PositionSyncCopy.progressListened(p) : PositionSyncCopy.progressRead(p);
    }
    return r.subtitle;
  }

  /// The BookOrbit book a card opens: any edition but the one this page is
  /// already showing. The Audiobookshelf item has no page here.
  int? _openableBookId(ChainCardRow r) {
    final cover = r.cover;
    if (r.isThisBook || cover is! BookCover || cover.bookId == _c.bookId) return null;
    return cover.bookId;
  }

  // The sync sheet closes first, so the edition's page opens over the book
  // page it came from rather than over the sheet.
  void _closeAndOpenBook(int bookId) {
    final nav = Navigator.of(context);
    nav.pop();
    showBookDetailSheet(nav.context, '$bookId');
  }

  Widget _cardRow(BuildContext context, ChainCardRow r, {required bool inGroup}) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final subtitle = _cardSubtitle(r);
    final busy = _c.busy;
    Widget? trailing;
    if (r.confirm != null) {
      trailing = FilledButton(
        onPressed: busy || r.confirm!.disabled ? null : () => _runAction(r.confirm!, r),
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Text(r.confirm!.label),
      );
    } else if (r.rebuild != null) {
      trailing = TextButton(
        onPressed: busy || r.rebuild!.disabled ? null : () => _runAction(r.rebuild!, r),
        style: TextButton.styleFrom(foregroundColor: _accent),
        child: Text(r.rebuild!.label),
      );
    } else if (r.change != ChangeState.none) {
      final enabled = r.change == ChangeState.available && !busy;
      trailing = TextButton(
        onPressed: enabled ? () => _openChange(r.edition) : null,
        style: TextButton.styleFrom(foregroundColor: _accent),
        child: Text(PositionSyncCopy.actionChange),
      );
    }
    final openId = _openableBookId(r);
    final card = Material(
      color: cs.onSurface.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(inGroup ? 13 : 16),
        side: BorderSide(
          color: r.isThisBook ? _accent.withValues(alpha: 0.55) : cs.onSurface.withValues(alpha: r.linked ? 0.1 : 0.18),
          width: r.linked ? 1 : 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: openId == null ? null : () => _closeAndOpenBook(openId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            _cover(context, r.cover, r.edition, 42, 62),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _kindLine(context, r.edition, [
                  if (r.isThisBook) _tag(PositionSyncCopy.tagThisBook, _accent),
                  if (r.external) _tag(PositionSyncCopy.tagExternal, muted),
                  if (!r.linked && r.chip != null) _tag(r.chip!, muted),
                ]),
                const SizedBox(height: 2),
                Text(r.title ?? PositionSyncCopy.untitled,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: muted)),
                ],
              ]),
            ),
            if (trailing != null) trailing,
          ]),
        ),
      ),
    );
    final job = r.job;
    if (job == null) return card;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      card,
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _stepper(context, job),
          if (job.error != null) ...[
            const SizedBox(height: 8),
            Text(job.error!, style: TextStyle(fontSize: 12, color: muted)),
          ],
          if (job.cancel != null || job.retry != null) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (job.retry != null) _pillButton(context, job.retry!, r, ChainTone.info, filled: true),
              if (job.cancel != null) _pillButton(context, job.cancel!, r, ChainTone.destructive, filled: false),
            ]),
          ],
        ]),
      ),
    ]);
  }

  Widget _ghostRow(BuildContext context, ChainGhostRow r) {
    final cs = Theme.of(context).colorScheme;
    final action = r.action;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.18), width: 1.5),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kindLine(context, r.edition, const []),
            const SizedBox(height: 4),
            Text(r.note, style: const TextStyle(fontSize: 14)),
          ]),
        ),
        if (action != null)
          TextButton(
            onPressed: _c.busy || action.disabled ? null : () => _runAction(action, r),
            style: TextButton.styleFrom(foregroundColor: _accent),
            child: Text(action.label),
          ),
      ]),
    );
  }

  String _connectorLabel(ChainConnectorRow r) {
    final arrow = switch (r.arrow) {
      ChainArrow.both => '⇆',
      ChainArrow.left => '⇐',
      ChainArrow.right => '⇒',
    };
    return '${editionShortName(r.from)} $arrow ${editionShortName(r.to)}';
  }

  String? _absLiveHint(ChainConnectorRow r) {
    if (!r.absDetails) return null;
    final live = _c.absLive;
    if (r.state == ConnectorState.absReceiving) return PositionSyncCopy.absReceivingHint;
    if (r.state != ConnectorState.absDiverged || live == null) return null;
    final positions = PositionSyncCopy.absDivergedHint(
      displayPercentage(live.progressPercentage, live.progressFinished) ?? 0,
      displayPercentage(live.localPercentage, false) ?? 0,
    );
    final reason = switch (live.divergedReason) {
      AbsDivergedReason.pushOff => PositionSyncCopy.absDivergedPushOff,
      AbsDivergedReason.pullRefused => PositionSyncCopy.absDivergedPullRefused,
      AbsDivergedReason.stale => PositionSyncCopy.absDivergedStale,
      null => null,
    };
    return reason == null ? positions : '$positions $reason';
  }

  Widget _connectorRow(BuildContext context, ChainConnectorRow r) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final tone = _tone(context, r.tone);
    final toggle = r.toggle;
    final busy = _c.busy;
    final off = r.state == ConnectorState.available;
    final explained = _explained.contains(r.key);
    // Like BookOrbit's: the switch takes the row's tone (green only for a
    // working link, grey with a ban for one that can't sync) and its icon.
    final (switchTone, thumbIcon) = switch (r.tone) {
      ChainTone.success => (tone, Icons.link_rounded),
      ChainTone.info => (tone, Icons.sync_rounded),
      ChainTone.warning => (tone, Icons.priority_high_rounded),
      ChainTone.destructive => (tone, Icons.close_rounded),
      ChainTone.muted => (cs.outline, Icons.block_rounded),
    };
    final onTone = ThemeData.estimateBrightnessForColor(switchTone) == Brightness.dark ? Colors.white : Colors.black;
    bool selected(Set<WidgetState> s) => s.contains(WidgetState.selected);
    Widget switchArea = SizedBox(
      width: 60,
      height: 44,
      child: toggle == null
          ? null
          : Center(
              // Colours are pinned so a running action, which disables every
              // switch for a moment, doesn't grey them all; only a link this
              // reader can't change is dimmed.
              child: Opacity(
                opacity: toggle.disabled ? 0.5 : 1,
                child: Switch(
                  value: toggle.on,
                  onChanged: toggle.disabled || busy ? null : (v) => _onSwitch(r, v),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  trackColor: WidgetStateProperty.resolveWith(
                      (s) => selected(s) ? switchTone : cs.surfaceContainerHighest),
                  trackOutlineColor: WidgetStateProperty.resolveWith(
                      (s) => selected(s) ? Colors.transparent : cs.outline),
                  thumbColor: WidgetStateProperty.resolveWith(
                      (s) => selected(s) ? onTone.withValues(alpha: 0.85) : cs.outline),
                  thumbIcon: WidgetStateProperty.resolveWith((s) => selected(s)
                      ? Icon(thumbIcon, color: switchTone)
                      : Icon(Icons.link_off_rounded, color: cs.surfaceContainerHighest)),
                ),
              ),
            ),
    );
    if (r.disabledReason != null) switchArea = Tooltip(message: r.disabledReason!, child: switchArea);
    final hint = _absLiveHint(r);
    final details = <Widget>[
      if (r.note != null) _detailText(r.note!, cs.onSurface.withValues(alpha: 0.8)),
      if (r.detail != null) _detailText(r.detail!, muted, mono: true),
      if (hint != null) _detailText(hint, cs.onSurface.withValues(alpha: 0.8)),
      if (r.key == ConnectorKey.audiobookAbs && _c.absActionError != null) _detailText(_c.absActionError!, cs.error),
      if (r.ticks != null) _ticks(context, r.ticks!),
      if (r.actions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < r.actions.length; i++)
              _pillButton(context, r.actions[i], r, r.tone, filled: i == 0),
          ]),
        ),
    ];
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Top-aligned so the switch sits at a fixed height the rail can skip.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          switchArea,
          const SizedBox(width: 10),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(_connectorLabel(r),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: off ? muted : cs.onSurface)),
                  // An off switch says why it is off; a live one says how it is.
                  _tag(off ? (r.qualifier ?? r.pill) : r.pill, tone),
                ]),
              ),
            ),
          ),
          if (r.explainer != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: AnimatedRotation(
                turns: explained ? 0.5 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.expand_more_rounded, size: 20, color: muted),
              ),
              onPressed: () => setState(() => explained ? _explained.remove(r.key) : _explained.add(r.key)),
            ),
          if (r.cancel != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: r.cancel!.label,
              icon: Icon(Icons.close_rounded, size: 20, color: cs.error),
              onPressed: _c.cancelling || r.cancel!.disabled ? null : () => _runAction(r.cancel!, r),
            ),
        ]),
        if (explained && r.explainer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 2, 8, 0),
            child: Text(r.explainer!, style: TextStyle(fontSize: 12, height: 1.45, color: muted)),
          ),
        if (details.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(70, 2, 0, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: details),
          ),
      ]),
    );
    // The rail joins the cards above and below through the switch.
    final railColor = r.tone == ChainTone.muted ? cs.onSurface.withValues(alpha: 0.22) : tone.withValues(alpha: 0.7);
    return Stack(children: [
      Positioned(
        left: 29,
        top: 0,
        bottom: 0,
        child: CustomPaint(
          size: const Size(2, double.infinity),
          painter: _RailPainter(railColor,
              dashed: r.tone == ChainTone.muted || r.tone == ChainTone.destructive,
              gap: toggle == null ? null : (_switchCenter - _railGapHalf, _switchCenter + _railGapHalf)),
        ),
      ),
      content,
    ]);
  }

  Widget _detailText(String text, Color color, {bool mono = false}) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(text,
            style: TextStyle(fontSize: 12, height: 1.4, color: color, fontFamily: mono ? 'monospace' : null)),
      );

  Widget _ticks(BuildContext context, ({int? done, int? total}) t) {
    final cs = Theme.of(context).colorScheme;
    final total = t.total;
    final done = t.done ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              minHeight: 3,
              value: total == null || total <= 0 ? null : (done / total).clamp(0.0, 1.0),
              color: _tone(context, ChainTone.info),
              backgroundColor: cs.onSurface.withValues(alpha: 0.12),
            ),
          ),
        ),
        if (total != null) ...[
          const SizedBox(width: 8),
          Text('$done / $total', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ]),
    );
  }

  Widget _pillButton(BuildContext context, ChainAction a, ChainRow row, ChainTone tone, {required bool filled}) {
    final color = tone == ChainTone.muted ? _accent : _tone(context, tone);
    final isCancel = a.id == ChainActionId.cancelReadAlong ||
        a.id == ChainActionId.cancelLinking ||
        a.id == ChainActionId.cancelAlignment;
    final enabled = !a.disabled && (isCancel ? !_c.cancelling : !_c.busy);
    final onPressed = enabled ? () => _runAction(a, row) : null;
    const shape = StadiumBorder();
    const size = Size(0, 36);
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: (ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black)
              .withValues(alpha: 0.85),
          minimumSize: size,
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        minimumSize: size,
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _stepper(BuildContext context, ReadAlongJob job) {
    final cs = Theme.of(context).colorScheme;
    final blue = _tone(context, ChainTone.info);
    final red = _tone(context, ChainTone.destructive);
    final todo = cs.onSurface.withValues(alpha: 0.12);
    final reports = job.stage == 1 || job.stage == 2;
    return Row(children: [
      for (var i = 0; i < PositionSyncCopy.stages.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: i < job.stage
                    ? 1
                    : i > job.stage
                        ? 0
                        : job.failed || !reports || job.remoteProgress == null
                            ? 1
                            : job.remoteProgress!,
                color: i == job.stage && job.failed ? red : blue,
                backgroundColor: todo,
              ),
            ),
            const SizedBox(height: 4),
            Text(PositionSyncCopy.stages[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: i == job.stage ? FontWeight.w700 : FontWeight.w400,
                  color: i <= job.stage ? cs.onSurface : cs.onSurfaceVariant,
                )),
          ]),
        ),
      ],
    ]);
  }

  Widget _slotRow(BuildContext context, ChainReadAlongSlotRow r) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final job = r.job;
    final percent = job == null ? null : readAlongPercent(job.stage, job.remoteProgress);
    final status = switch (r.variant) {
      ReadAlongSlotVariant.building => _tag(PositionSyncCopy.tagGenerating, _tone(context, ChainTone.info)),
      ReadAlongSlotVariant.queued => _tag(PositionSyncCopy.tagQueued, muted),
      ReadAlongSlotVariant.failed => _tag(PositionSyncCopy.tagFailed, _tone(context, ChainTone.destructive)),
      _ => null,
    };
    final action = r.action;
    final running = r.variant == ReadAlongSlotVariant.building || r.variant == ReadAlongSlotVariant.queued;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.18), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _kindLine(context, SyncEdition.readAlong, [if (status != null) status])),
          if (r.cancel != null)
            r.variant == ReadAlongSlotVariant.failed
                ? TextButton(
                    onPressed: _c.busy || r.cancel!.disabled ? null : () => _runAction(r.cancel!, r),
                    style: TextButton.styleFrom(foregroundColor: muted),
                    child: Text(r.cancel!.label),
                  )
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: r.cancel!.label,
                    icon: Icon(Icons.close_rounded, size: 20, color: cs.error),
                    onPressed: _c.cancelling || r.cancel!.disabled ? null : () => _runAction(r.cancel!, r),
                  )
          else
            const SizedBox(height: 40),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text.rich(
            TextSpan(text: r.note, children: [
              if (r.variant == ReadAlongSlotVariant.building && percent != null)
                TextSpan(
                    text: ' $percent%',
                    style: TextStyle(fontWeight: FontWeight.w700, color: _tone(context, ChainTone.info))),
            ]),
            style: TextStyle(fontSize: 14, height: 1.4, color: cs.onSurface.withValues(alpha: 0.85)),
          ),
        ),
        if (job != null && r.variant == ReadAlongSlotVariant.building) ...[
          const SizedBox(height: 12),
          Padding(padding: const EdgeInsets.only(right: 6), child: _stepper(context, job)),
        ],
        if (r.error != null) ...[
          const SizedBox(height: 6),
          Text(r.error!, style: TextStyle(fontSize: 12, color: muted)),
        ],
        if (running) ...[
          const SizedBox(height: 10),
          Text(PositionSyncCopy.safeToClose, style: TextStyle(fontSize: 12, color: muted)),
        ],
        if (action != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _wideButton(
              context,
              icon: r.variant == ReadAlongSlotVariant.failed ? Icons.refresh_rounded : Icons.auto_awesome_rounded,
              label: action.label,
              height: 44,
              onPressed: action.disabled || _c.busy ? null : () => _runAction(action, r),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _wideButton(BuildContext context,
      {IconData? icon, required String label, required double height, VoidCallback? onPressed}) {
    final on = ThemeData.estimateBrightnessForColor(_accent) == Brightness.dark ? Colors.white : Colors.black;
    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: on.withValues(alpha: 0.85),
          disabledBackgroundColor: _accent.withValues(alpha: 0.4),
          disabledForegroundColor: on.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  // ─── Actions ──────────────────────────────────────────────

  // Switches are derived from the data, so a cancelled confirm leaves them
  // where they were by itself.
  void _onSwitch(ChainConnectorRow row, bool next) {
    final toggle = row.toggle;
    if (toggle == null || toggle.disabled) return;
    if (next) {
      final id = toggle.onAction;
      if (id != null) _runAction(ChainAction(id, ''), row);
      return;
    }
    final target = toggle.offTarget;
    if (target == null) return;
    if (row.state == ConnectorState.linking && target == OffTarget.pair) {
      unawaited(_c.cancelLinking());
      return;
    }
    switch (target) {
      case OffTarget.pair:
        unawaited(_confirmUnlink());
      case OffTarget.readAlong:
        unawaited(_confirm(PositionSyncCopy.detachTitle, PositionSyncCopy.detachDescription, PositionSyncCopy.stopSyncing)
            .then((ok) => ok ? _c.detachReadAlongAction() : null));
      case OffTarget.abs:
        unawaited(
            _confirm(PositionSyncCopy.pauseAbsTitle, PositionSyncCopy.pauseAbsDescription, PositionSyncCopy.stopSyncing)
                .then((ok) => ok ? _c.absPause() : null));
    }
  }

  void _runAction(ChainAction a, ChainRow row) {
    switch (a.id) {
      case ChainActionId.linkPair:
        unawaited(_c.linkPair());
      case ChainActionId.cancelLinking:
        unawaited(_c.cancelLinking());
      case ChainActionId.cancelAlignment:
        unawaited(_c.cancelAlignmentAction());
      case ChainActionId.retryAlignment:
      case ChainActionId.alignNow:
        unawaited(_c.buildAlignmentAction());
      case ChainActionId.rebuildAlignment:
        unawaited(_c.buildAlignmentAction(force: true));
      case ChainActionId.unlinkPair:
        unawaited(_confirmUnlink());
      case ChainActionId.attachReadAlong:
        unawaited(_c.attachReadAlongAction());
      case ChainActionId.openGenerate:
        _go(_Page.generate);
        // An aligned Storyteller book that already covers this pair can be
        // imported instead of rebuilt.
        unawaited(_c.fetchExisting());
        unawaited(_c.loadTargetLibraries());
      case ChainActionId.cancelReadAlong:
        unawaited(_c.cancelReadAlongAction());
      case ChainActionId.retryReadAlong:
        unawaited(_c.retryReadAlong());
      case ChainActionId.rebuildReadAlong:
        unawaited(_confirmRebuild());
      case ChainActionId.change:
        final edition = switch (row) {
          ChainCardRow r => r.edition,
          ChainGhostRow r => r.edition,
          _ => null,
        };
        if (edition != null) _openChange(edition);
      case ChainActionId.retryAbs:
        unawaited(_c.absRetry());
      case ChainActionId.absPush:
        unawaited(_c.absReconcileAction('push'));
      case ChainActionId.absPull:
        unawaited(_c.absReconcileAction('pull'));
      case ChainActionId.confirmAbs:
        unawaited(_c.absConfirmAction());
      case ChainActionId.resumeAbs:
        unawaited(_c.absResume());
    }
  }

  Future<bool> _confirm(String title, String body, String confirmLabel) async {
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
        ],
      ),
    );
    return ok == true && mounted;
  }

  Future<void> _confirmUnlink() async {
    if (await _confirm(PositionSyncCopy.unlinkTitle, _c.unlinkDescription, PositionSyncCopy.actionUnlink)) {
      await _c.unlinkPair();
    }
  }

  // The dialog names the ready read-along and promises to delete it, so it
  // goes away if a poll retires that read-along while it is open.
  Future<void> _confirmRebuild() async {
    final l = AppLocalizations.of(context)!;
    final title = _c.readAlongMember?.title ?? PositionSyncCopy.readyPending;
    var closed = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: _c,
        builder: (ctx, _) {
          if (_c.readAlong.status != ReadAlongStatus.ready && !closed) {
            closed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted) Navigator.pop(ctx, false);
            });
          }
          return AlertDialog(
            title: Text(PositionSyncCopy.rebuildTitle),
            content: Text(PositionSyncCopy.rebuildDescription(title)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(PositionSyncCopy.rebuildConfirm)),
            ],
          );
        },
      ),
    );
    if (ok == true && mounted) await _c.rebuildReadAlong();
  }

  // ─── Generate page ────────────────────────────────────────

  Widget _pageHeader(BuildContext context, String title, String? subtitle) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => _go(_Page.chain),
        ),
        const SizedBox(width: 4),
        Expanded(child: Text(title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
      ]),
      if (subtitle != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(44, 2, 0, 0),
          child: Text(subtitle, style: TextStyle(fontSize: 13, height: 1.4, color: cs.onSurfaceVariant)),
        ),
      const SizedBox(height: 14),
    ]);
  }

  Widget _miniRow(BuildContext context, IconData icon, String text, String? trailing) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
        if (trailing != null) Text(trailing, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  Widget _option(BuildContext context, IconData icon, String title, String? subtitle, Widget? trailing,
      {bool first = false}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.only(top: first ? 0 : 10, bottom: 10),
      decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)))),
      child: Row(children: [
        Icon(icon, size: 20, color: _accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, height: 1.35, color: cs.onSurfaceVariant)),
            ],
          ]),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }

  Future<void> _pickTargetLibrary() async {
    final cs = Theme.of(context).colorScheme;
    final picked = await showAdaptiveActionMenu<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.settings_suggest_rounded, color: cs.onSurfaceVariant),
            title: Text(PositionSyncCopy.targetLibraryUseConfigured),
            trailing: _c.chosenTargetLibraryId == null ? Icon(Icons.check_rounded, color: _accent) : null,
            onTap: () => Navigator.pop(ctx, -1),
          ),
          for (final lib in _c.targetLibraries)
            ListTile(
              leading: Icon(Icons.local_library_rounded, color: cs.onSurfaceVariant),
              title: Text(lib.name),
              trailing: _c.chosenTargetLibraryId == lib.id ? Icon(Icons.check_rounded, color: _accent) : null,
              onTap: () => Navigator.pop(ctx, lib.id),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    _c.setTargetLibrary(picked == -1 ? null : picked);
  }

  Future<void> _startGenerate({String? useExistingUuid}) async {
    final outcome = await _c.generate(useExistingUuid: useExistingUuid);
    if (!mounted) return;
    // Only a failed request keeps the options open for a retry.
    if (outcome != ReadAlongBuildOutcome.failed) _go(_Page.chain);
  }

  List<Widget> _generatePage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sides = _c.sides;
    final ra = _c.readAlong;
    final audio = sides.audiobook.book;
    final ebook = sides.ebook.book;
    final match = _c.existingMatch;
    final busy = _c.busy;
    final chosenName = _c.chosenTargetLibraryId == null ? null : _c.targetLibraryName;
    return [
      _pageHeader(context, PositionSyncCopy.generate, PositionSyncCopy.generateSubtitle),
      if (audio != null)
        _miniRow(context, Icons.headphones_rounded,
            '${audio.title ?? PositionSyncCopy.untitled} · ${PositionSyncCopy.shortAudiobook}',
            ra.audioBytes == null ? null : formatSyncBytes(ra.audioBytes!)),
      if (audio != null && ebook != null) const SizedBox(height: 6),
      if (ebook != null)
        _miniRow(context, Icons.menu_book_rounded, '${ebook.title ?? PositionSyncCopy.untitled} · EPUB',
            ra.epubBytes == null ? null : formatSyncBytes(ra.epubBytes!)),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accent.withValues(alpha: 0.45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (match != null)
            _option(
              context,
              Icons.download_rounded,
              PositionSyncCopy.importExisting(match.title),
              PositionSyncCopy.importExistingHint,
              TextButton(
                onPressed: busy ? null : () => _startGenerate(useExistingUuid: match.uuid),
                style: TextButton.styleFrom(foregroundColor: _accent),
                child: Text(PositionSyncCopy.actionImport),
              ),
              first: true,
            ),
          if (_c.targetLibraries.isNotEmpty)
            _option(
              context,
              Icons.local_library_rounded,
              chosenName != null
                  ? PositionSyncCopy.targetLibraryWill(chosenName)
                  : ra.targetLibraryName != null
                      ? PositionSyncCopy.targetLibraryWill(ra.targetLibraryName!)
                      : PositionSyncCopy.targetLibraryDefault,
              chosenName == null ? PositionSyncCopy.targetLibraryConfigured : PositionSyncCopy.targetLibrary,
              TextButton(
                onPressed: busy ? null : _pickTargetLibrary,
                style: TextButton.styleFrom(foregroundColor: _accent),
                child: Text(PositionSyncCopy.actionChange),
              ),
              first: match == null,
            ),
          if (ra.remoteCopyReclaimable)
            _option(
              context,
              Icons.cloud_queue_rounded,
              PositionSyncCopy.keepRemoteCopy,
              _c.keepRemoteCopy ? PositionSyncCopy.keepRemoteCopyOn : PositionSyncCopy.keepRemoteCopyOff,
              Switch(
                value: _c.keepRemoteCopy,
                onChanged: busy ? null : _c.setKeepRemoteCopy,
                activeThumbColor: _accent,
                activeTrackColor: _accent.withValues(alpha: 0.45),
              ),
              first: match == null && _c.targetLibraries.isEmpty,
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text(PositionSyncCopy.generateHint,
                style: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant)),
          ),
          _wideButton(
            context,
            icon: Icons.auto_awesome_rounded,
            label: PositionSyncCopy.generate,
            height: 48,
            onPressed: busy ? null : () => _startGenerate(),
          ),
        ]),
      ),
    ];
  }

  // ─── Change page ──────────────────────────────────────────

  void _openChange(SyncEdition edition) {
    _go(_Page.change);
    setState(() => _changeEdition = edition);
    // An empty query lists the server's own proposals first.
    if (edition == SyncEdition.abs) {
      _c.searchAbs('');
    } else {
      _c.searchCandidates(edition, '');
    }
  }

  void _onQuery(String q) {
    final edition = _changeEdition;
    if (edition == null) return;
    setState(() => _changePick = null);
    if (edition == SyncEdition.abs) {
      _c.searchAbs(q);
    } else {
      _c.searchCandidates(edition, q);
    }
  }

  Widget _resultRow(BuildContext context,
      {required ChainCover cover,
      required SyncEdition edition,
      required String title,
      required String subtitle,
      int? score,
      bool selected = false,
      required VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? _accent.withValues(alpha: 0.08) : cs.onSurface.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? _accent.withValues(alpha: 0.55) : cs.onSurface.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              _cover(context, cover, edition, 36, 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ]),
              ),
              if (score != null) ...[
                const SizedBox(width: 8),
                _tag('$score%', score >= 80 ? _tone(context, ChainTone.success) : cs.onSurfaceVariant, fontSize: 12),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _pickCandidate(SyncEdition edition, EditionLinkCandidateWire c) async {
    if (_c.isMemberSide(edition)) {
      setState(() => _changePick = c);
      return;
    }
    _c.pick(c);
    _go(_Page.chain);
  }

  List<Widget> _changePage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final edition = _changeEdition ?? SyncEdition.ebook;
    final isAbs = edition == SyncEdition.abs;
    final isEbook = edition == SyncEdition.ebook;
    final pick = _changePick;
    final results = <Widget>[];
    if (isAbs) {
      for (final item in _c.absCandidates) {
        final sub = [item.absAuthorName, item.absLibraryName].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
        results.add(_resultRow(
          context,
          cover: AbsCover(item.absLibraryItemId),
          edition: SyncEdition.abs,
          title: item.absTitle.isEmpty ? PositionSyncCopy.untitled : item.absTitle,
          subtitle: sub,
          onTap: _c.busy
              ? null
              : () async {
                  if (await _c.absChange(item) && mounted) _go(_Page.chain);
                },
        ));
      }
    } else {
      for (final cand in _c.candidates) {
        final kind = isEbook ? 'EPUB' : PositionSyncCopy.shortAudiobook;
        results.add(_resultRow(
          context,
          cover: BookCover(cand.bookId, cand.coverVersion),
          edition: edition,
          title: cand.title ?? PositionSyncCopy.untitled,
          subtitle: [if (cand.authorName != null && cand.authorName!.isNotEmpty) cand.authorName!, kind].join(' · '),
          score: cand.fromBuild ? null : cand.score,
          selected: pick?.bookId == cand.bookId,
          onTap: _c.busy ? null : () => _pickCandidate(edition, cand),
        ));
      }
    }
    final status = _c.searching
        ? PositionSyncCopy.searching
        : _c.searchError ?? (_c.hasSearched && results.isEmpty ? PositionSyncCopy.noMatches : null);
    return [
      _pageHeader(
        context,
        isAbs
            ? PositionSyncCopy.selectAbs
            : isEbook
                ? PositionSyncCopy.selectEbook
                : PositionSyncCopy.selectAudiobook,
        isAbs
            ? null
            : isEbook
                ? PositionSyncCopy.selectEbookHint
                : PositionSyncCopy.selectAudiobookHint,
      ),
      TextField(
        controller: _query,
        autofocus: true,
        onChanged: _onQuery,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: isAbs
              ? PositionSyncCopy.searchAbs
              : isEbook
                  ? PositionSyncCopy.searchEbooks
                  : PositionSyncCopy.searchAudiobooks,
          filled: true,
          fillColor: cs.onSurface.withValues(alpha: 0.04),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
        child: Text(PositionSyncCopy.bestMatches,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: cs.onSurfaceVariant)),
      ),
      if (status != null && (results.isEmpty || _c.searching))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Text(status,
              style: TextStyle(fontSize: 13, color: _c.searchError != null ? cs.error : cs.onSurfaceVariant)),
        ),
      ...results,
      if (pick != null) ...[
        Divider(height: 24, color: cs.onSurface.withValues(alpha: 0.08)),
        Text(PositionSyncCopy.changeTitle(pick.title ?? PositionSyncCopy.untitled),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(PositionSyncCopy.changeDescription(isEbook ? 'ebook' : 'audiobook'),
            style: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        _wideButton(
          context,
          label: PositionSyncCopy.changeConfirm,
          height: 48,
          onPressed: _c.busy
              ? null
              : () async {
                  _go(_Page.chain);
                  await _c.applyChange(edition, pick);
                },
        ),
      ],
    ];
  }
}

/// The spine between two rows, solid while the link holds and dashed while
/// it is off or broken.
class _RailPainter extends CustomPainter {
  final Color color;
  final bool dashed;

  /// The switch's band, left unpainted so the rail stops at its edges.
  final (double, double)? gap;
  const _RailPainter(this.color, {required this.dashed, this.gap});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    final x = size.width / 2;
    void segment(double from, double to) {
      if (to <= from) return;
      if (!dashed) {
        canvas.drawLine(Offset(x, from), Offset(x, to), paint);
        return;
      }
      for (var y = from; y < to; y += 8) {
        canvas.drawLine(Offset(x, y), Offset(x, (y + 4).clamp(from, to)), paint);
      }
    }
    final g = gap;
    if (g == null) {
      segment(0, size.height);
    } else {
      segment(0, g.$1);
      segment(g.$2, size.height);
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.color != color || old.dashed != dashed || old.gap != gap;
}
