import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/api_service.dart';
import '../../services/fork/position_sync_chain.dart';
import '../../services/fork/position_sync_controller.dart';
import '../adaptive_modal.dart';
import '../overlay_toast.dart';
import 'tinted_sheet.dart';

// Fork-owned: the BookOrbit Position sync button in the detail page's top
// bar and its sheet: the chain of the book's own files (ebook, read-aloud,
// audiobook and its Audiobookshelf match), upstream's read-aloud generator
// and its options, and the Audiobookshelf match search. The hooks are the
// import in book_detail_sheet.dart and the button in the redesigned page's
// top bar. See FORK_NOTES.md.

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
/// book with nothing to sync.
class ForkSyncButton extends StatefulWidget {
  final String itemId;
  final Color accent;
  final BookOrbitApiService api;

  /// The cover's container colour, which tints the sheet like the page it
  /// opens over. Null keeps the plain sheet colour.
  final Color? tint;

  const ForkSyncButton({
    super.key,
    required this.itemId,
    required this.accent,
    required this.api,
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
    _c = acquirePositionSync(widget.api, widget.itemId);
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

  /// The chain's state on a bare icon, drawn the way the bookmark beside it
  /// is: the sheet's swap icon, outlined until the files sync, filled in the
  /// cover's accent when they're in sync, outlined in the accent when one
  /// wants checking, filled red when something needs attention, and in the
  /// blue build ring while an alignment or a read-aloud is made.
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
PositionSyncController acquirePositionSync(BookOrbitApiService api, String itemId) {
  final c = PositionSyncController.acquire(api, int.parse(itemId));
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(c.loadInitial()));
  return c;
}

/// Starts a book's sync state loading as its detail sheet opens, beside the
/// book itself, so the button's status arrives with the rest of the sheet.
/// Call the returned release when the sheet closes.
VoidCallback? prefetchPositionSync(AuthProvider auth, LibraryProvider lib, String itemId) {
  if (!ForkSyncButton.shouldShow(auth, lib, itemId)) return null;
  final c = acquirePositionSync(auth.apiService as BookOrbitApiService, itemId);
  return () => PositionSyncController.release(c);
}

// ─── Sheet ──────────────────────────────────────────────────

Future<void> showPositionSyncSheet(BuildContext context, PositionSyncController controller, Color accent,
    {Map<String, String> coverHeaders = const {}, Color? tint}) {
  // As tall as its content, up to the safe area, so a short chain doesn't
  // open as a full screen of empty sheet.
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PositionSyncSheet(
      controller: controller,
      accent: accent,
      coverHeaders: coverHeaders,
      tint: tint,
    ),
  );
}

enum _Page { chain, modify, absSearch }

class _PositionSyncSheet extends StatefulWidget {
  final PositionSyncController controller;
  final Color accent;
  final Map<String, String> coverHeaders;
  final Color? tint;

  const _PositionSyncSheet({
    required this.controller,
    required this.accent,
    required this.coverHeaders,
    this.tint,
  });

  @override
  State<_PositionSyncSheet> createState() => _PositionSyncSheetState();
}

class _PositionSyncSheetState extends State<_PositionSyncSheet> {
  late final PositionSyncController _c;
  _Page _page = _Page.chain;
  final _query = TextEditingController();
  final Set<ConnectorKey> _explained = {};

  // The options page's choices, seeded from the dialog's own defaults.
  String? _language;
  int? _epubFileId;
  String _granularity = 'sentence';
  String? _modifyError;

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
        if (page != _Page.absSearch) _query.clear();
      });

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    // Lifted over the keyboard while the search field has it; the bottom
    // inset only counts when the keyboard isn't already covering it.
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        // The book page's own cover gradient, so the sheet reads as part of it.
        decoration: forkTintedSheetDecoration(context, widget.tint),
        child: ListenableBuilder(
          listenable: _c,
          // The handle sits outside the list so dragging it always closes the
          // sheet. The list shrinks to its page; while the page fits, it takes
          // no drags, so a drag anywhere moves the sheet. Once it scrolls, a
          // pull down past its top closes the sheet.
          builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.only(top: 8), child: forkSheetHandle(context)),
            Flexible(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _closeOnPullDown,
                  child: ListView(
                    shrinkWrap: true,
                    // Not primary, so it only takes drags when it can scroll.
                    primary: false,
                    padding: EdgeInsets.fromLTRB(
                        16, 0, 16, 32 + (keyboard > 0 ? 0 : MediaQuery.viewPaddingOf(context).bottom)),
                    children: [
                      ...switch (_page) {
                        _Page.chain => _chainPage(context),
                        _Page.modify => _modifyPage(context),
                        _Page.absSearch => _absSearchPage(context),
                      },
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  bool _closing = false;

  /// Closes the sheet when the user pulls the scrolled-to-top list down:
  /// an overscroll past the top (Android) or a bounce well past it (iOS).
  bool _closeOnPullDown(ScrollNotification n) {
    if (_closing || n.metrics.axis != Axis.vertical) return false;
    final pulled = switch (n) {
      OverscrollNotification(:final overscroll, :final dragDetails) =>
        dragDetails != null && overscroll < 0 && n.metrics.extentBefore == 0,
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null && n.metrics.pixels < -48,
      _ => false,
    };
    if (pulled) {
      _closing = true;
      Navigator.of(context).maybePop();
    }
    return false;
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
        ChainReadAloudSlotRow _ => ChainFrame.spine,
      };

  Widget _row(BuildContext context, ChainRow row, {required bool inGroup}) => switch (row) {
        ChainCardRow r => _cardRow(context, r, inGroup: inGroup),
        ChainGhostRow r => _ghostRow(context, r),
        ChainConnectorRow r => _connectorRow(context, r),
        ChainReadAloudSlotRow r => _slotRow(context, r),
      };

  // The edition picks the cover slot: a book with both files has an audio
  // and an ebook cover, and the list default may be either.
  Widget _cover(BuildContext context, ChainCover cover, SyncEdition edition, double w, double h) {
    final cs = Theme.of(context).colorScheme;
    final tile = Container(
      color: cs.onSurface.withValues(alpha: 0.08),
      child: Center(child: Icon(syncEditionIcon(edition), size: w * 0.45, color: cs.onSurfaceVariant)),
    );
    final url = switch (cover) {
      BookCover c => _c.api.getCoverUrl('${c.bookId}',
          width: 200, coverRatio: edition == SyncEdition.audiobook ? 1.0 : 0.66),
      AbsCover c => _c.api.positionSyncAbsCoverUrl(c.absLibraryItemId),
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: w,
        height: h,
        child: CachedNetworkImage(
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

  String? _progressLine(ChainCardRow r) {
    final p = r.progress;
    if (r.edition == SyncEdition.abs) {
      if (p == null && r.progressPending) return PositionSyncCopy.absChecking;
      return p == null ? null : PositionSyncCopy.progressListened(p);
    }
    if (p == null) return null;
    return r.edition == SyncEdition.audiobook ? PositionSyncCopy.progressListened(p) : PositionSyncCopy.progressRead(p);
  }

  Widget _cardRow(BuildContext context, ChainCardRow r, {required bool inGroup}) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final progress = _progressLine(r);
    final subtitle = [r.subtitle, progress].nonNulls.join(' · ');
    final busy = _c.busy;
    Widget? trailing;
    if (r.confirm != null) {
      trailing = FilledButton(
        onPressed: busy || r.confirm!.disabled ? null : () => _runAction(r.confirm!),
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Text(r.confirm!.label),
      );
    } else if (r.change) {
      trailing = TextButton(
        onPressed: busy ? null : _openAbsSearch,
        style: TextButton.styleFrom(foregroundColor: _accent),
        child: Text(PositionSyncCopy.actionChange),
      );
    }
    return Material(
      color: cs.onSurface.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(inGroup ? 13 : 16),
        side: BorderSide(color: cs.onSurface.withValues(alpha: r.linked ? 0.1 : 0.18), width: r.linked ? 1 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          _cover(context, r.cover, r.edition, 42, 62),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kindLine(context, r.edition, [
                if (r.external) _tag(PositionSyncCopy.tagExternal, muted),
                if (!r.linked && r.chip != null) _tag(r.chip!, muted),
              ]),
              const SizedBox(height: 2),
              Text(r.title ?? PositionSyncCopy.untitled,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: muted)),
              ],
            ]),
          ),
          if (trailing != null) trailing,
        ]),
      ),
    );
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
            onPressed: _c.busy || action.disabled ? null : () => _runAction(action),
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
              // switch for a moment, doesn't grey them all; only a switch
              // that can't be turned on is dimmed.
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
            for (var i = 0; i < r.actions.length; i++) _pillButton(context, r.actions[i], r.tone, filled: i == 0),
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
              onPressed: _c.cancelling || r.cancel!.disabled ? null : () => _runAction(r.cancel!),
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

  Widget _bar(BuildContext context, double? value) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        minHeight: 3,
        value: value,
        color: _tone(context, ChainTone.info),
        backgroundColor: cs.onSurface.withValues(alpha: 0.12),
      ),
    );
  }

  Widget _ticks(BuildContext context, ({int? done, int? total}) t) {
    final total = t.total;
    final done = t.done ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Expanded(child: _bar(context, total == null || total <= 0 ? null : (done / total).clamp(0.0, 1.0))),
        if (total != null) ...[
          const SizedBox(width: 8),
          Text('$done / $total', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ]),
    );
  }

  Widget _pillButton(BuildContext context, ChainAction a, ChainTone tone, {required bool filled, bool pending = false}) {
    final color = tone == ChainTone.muted ? _accent : _tone(context, tone);
    final isCancel = a.id == ChainActionId.cancelAlignment || a.id == ChainActionId.cancelReadAloud;
    final enabled = !a.disabled && (isCancel ? !_c.cancelling : !_c.busy);
    final onPressed = enabled ? () => _runAction(a) : null;
    const shape = StadiumBorder();
    const size = Size(0, 36);
    final label = Row(mainAxisSize: MainAxisSize.min, children: [
      if (pending) ...[
        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: filled ? null : color)),
        const SizedBox(width: 8),
      ],
      Text(a.label, style: const TextStyle(fontWeight: FontWeight.w600)),
    ]);
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
        child: label,
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
      child: label,
    );
  }

  Widget _slotRow(BuildContext context, ChainReadAloudSlotRow r) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final status = switch (r.variant) {
      ReadAloudSlotVariant.processing => _tag(PositionSyncCopy.tagCreating, _tone(context, ChainTone.info)),
      ReadAloudSlotVariant.queued => _tag(PositionSyncCopy.tagQueued, muted),
      ReadAloudSlotVariant.review => _tag(PositionSyncCopy.tagReview, _tone(context, ChainTone.warning)),
      ReadAloudSlotVariant.failed => _tag(PositionSyncCopy.tagFailed, _tone(context, ChainTone.destructive)),
      _ => null,
    };
    final action = r.action;
    final secondary = r.secondary;
    final progress = r.progress;
    final running = r.variant == ReadAloudSlotVariant.processing || r.variant == ReadAloudSlotVariant.queued;
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
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: r.cancel!.label,
              icon: r.pending == ChainActionId.cancelReadAloud
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.close_rounded, size: 20, color: cs.error),
              onPressed: r.cancel!.disabled ? null : () => _runAction(r.cancel!),
            )
          else
            const SizedBox(height: 40),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text.rich(
            TextSpan(text: r.note, children: [
              if (progress?.percent != null)
                TextSpan(
                    text: ' ${progress!.percent}%',
                    style: TextStyle(fontWeight: FontWeight.w700, color: _tone(context, ChainTone.info))),
            ]),
            style: TextStyle(fontSize: 14, height: 1.4, color: cs.onSurface.withValues(alpha: 0.85)),
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _bar(context, progress.percent == null ? null : progress.percent! / 100),
          ),
        ],
        if (running) ...[
          const SizedBox(height: 10),
          Text(PositionSyncCopy.safeToClose, style: TextStyle(fontSize: 12, color: muted)),
        ],
        if (action != null || secondary != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (action != null)
                _pillButton(context, action, ChainTone.muted, filled: true, pending: r.pending == action.id),
              if (secondary != null) _pillButton(context, secondary, ChainTone.muted, filled: false),
            ]),
          ),
        ],
      ]),
    );
  }

  // ─── Actions ──────────────────────────────────────────────

  // Switches are derived from the data, so a cancelled confirm leaves them
  // where they were by itself.
  void _onSwitch(ChainConnectorRow row, bool next) {
    final toggle = row.toggle;
    if (toggle == null || toggle.disabled) return;
    final id = next ? toggle.onAction : toggle.offAction;
    if (id != null) _runAction(ChainAction(id, ''));
  }

  void _runAction(ChainAction a) {
    switch (a.id) {
      case ChainActionId.cancelAlignment:
        unawaited(_c.cancelAlignmentAction());
      case ChainActionId.retryAlignment:
      case ChainActionId.alignNow:
        unawaited(_c.buildAlignmentAction());
      case ChainActionId.rebuildAlignment:
        unawaited(_c.buildAlignmentAction(force: true));
      case ChainActionId.enableReadAloudSync:
        unawaited(_c.setReadAloudSync(true));
      case ChainActionId.disableReadAloudSync:
        unawaited(_c.setReadAloudSync(false));
      case ChainActionId.createReadAloud:
        unawaited(_create());
      case ChainActionId.modifyReadAloud:
        unawaited(_openModify());
      case ChainActionId.cancelReadAloud:
        unawaited(_c.cancelReadAloud());
      case ChainActionId.retryReadAloud:
        unawaited(_c.retryReadAloud());
      case ChainActionId.reviewReadAloud:
        unawaited(_review());
      case ChainActionId.change:
        _openAbsSearch();
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
      case ChainActionId.pauseAbs:
        unawaited(_confirm(PositionSyncCopy.pauseAbsTitle, PositionSyncCopy.pauseAbsDescription,
                PositionSyncCopy.stopSyncing)
            .then((ok) => ok ? _c.absPause() : null));
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

  /// One tap with the dialog's defaults; the options open instead when the
  /// book's language gives none the speech model knows.
  Future<void> _create() async {
    if (!await _c.createReadAloud() && mounted) await _openModify();
  }

  /// Review lists the chapters the narration matched and adds the result to
  /// the book; that lives in BookOrbit's web app.
  Future<void> _review() async {
    _toast(const PositionSyncNotice(PositionSyncNoticeKind.info, PositionSyncCopy.toastReviewInBrowser));
    await launchUrl(Uri.parse(_c.reviewUrl), mode: LaunchMode.externalApplication);
  }

  // ─── Read-aloud options ───────────────────────────────────

  Future<void> _openModify() async {
    final saved = await _c.api.readAloudDefaultLanguage();
    if (!mounted) return;
    final c = _c.capability;
    final defaults = _c.defaultRequest(saved);
    setState(() {
      _language = defaults?.language;
      _epubFileId = defaults?.epubFileId ?? (c == null || c.epubFiles.isEmpty ? null : c.epubFiles.first.id);
      _granularity = 'sentence';
      _modifyError = null;
    });
    _go(_Page.modify);
  }

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

  Future<T?> _pick<T>(List<(T, String)> choices, T? current) {
    final cs = Theme.of(context).colorScheme;
    return showAdaptiveActionMenu<T>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (value, label) in choices)
              ListTile(
                title: Text(label),
                trailing: value == current ? Icon(Icons.check_rounded, color: _accent) : null,
                iconColor: cs.onSurfaceVariant,
                onTap: () => Navigator.pop(ctx, value),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _startFromOptions() async {
    final c = _c.capability;
    final language = _language;
    final epub = _epubFileId;
    if (c == null || language == null || epub == null) return;
    setState(() => _modifyError = null);
    final error = await _c.createReadAloudWith(ReadAloudRequest(
      epubFileId: epub,
      audioFileIds: c.audioFileIds,
      language: language,
      granularity: _granularity,
    ));
    if (!mounted) return;
    if (error == null) {
      _go(_Page.chain);
    } else {
      setState(() => _modifyError = error);
    }
  }

  List<Widget> _modifyPage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _c.capability;
    final busy = _c.busy;
    final epubs = c?.epubFiles ?? const <ReadAloudCandidateFileWire>[];
    final epub = epubs.where((f) => f.id == _epubFileId).firstOrNull;
    final languages = c?.supportedLanguages ?? const <String>[];
    final change = TextButton.styleFrom(foregroundColor: _accent);
    return [
      _pageHeader(context, PositionSyncCopy.modifyTitle, PositionSyncCopy.modifySubtitle),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accent.withValues(alpha: 0.45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _option(
            context,
            Icons.translate_rounded,
            _language == null ? PositionSyncCopy.modifyLanguage : readAloudLanguageName(_language!),
            _language == null ? PositionSyncCopy.modifyLanguageNone : PositionSyncCopy.modifyLanguage,
            TextButton(
              style: change,
              onPressed: busy || languages.isEmpty
                  ? null
                  : () async {
                      final picked = await _pick([for (final l in languages) (l, readAloudLanguageName(l))], _language);
                      if (picked != null && mounted) setState(() => _language = picked);
                    },
              child: Text(PositionSyncCopy.actionChange),
            ),
            first: true,
          ),
          _option(
            context,
            Icons.menu_book_rounded,
            epub?.filename ?? PositionSyncCopy.untitled,
            PositionSyncCopy.modifyEpub,
            epubs.length > 1
                ? TextButton(
                    style: change,
                    onPressed: busy
                        ? null
                        : () async {
                            final picked = await _pick([for (final f in epubs) (f.id, f.filename)], _epubFileId);
                            if (picked != null && mounted) setState(() => _epubFileId = picked);
                          },
                    child: Text(PositionSyncCopy.actionChange),
                  )
                : null,
          ),
          _option(context, Icons.headphones_rounded, PositionSyncCopy.modifyAudioFiles(c?.audioFileIds.length ?? 0),
              PositionSyncCopy.modifyAudio, null),
          _option(
            context,
            Icons.short_text_rounded,
            _granularity == 'word' ? PositionSyncCopy.granularityWord : PositionSyncCopy.granularitySentence,
            PositionSyncCopy.modifyGranularity,
            TextButton(
              style: change,
              onPressed: busy
                  ? null
                  : () async {
                      final picked = await _pick([
                        ('sentence', PositionSyncCopy.granularitySentence),
                        ('word', PositionSyncCopy.granularityWord),
                      ], _granularity);
                      if (picked != null && mounted) setState(() => _granularity = picked);
                    },
              child: Text(PositionSyncCopy.actionChange),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text(PositionSyncCopy.modifyHint, style: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant)),
          ),
          if (_modifyError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_modifyError!, style: TextStyle(fontSize: 13, color: cs.error)),
            ),
          _wideButton(
            context,
            icon: Icons.auto_awesome_rounded,
            label: PositionSyncCopy.createReadAloud,
            height: 48,
            pending: _c.jobAction == ReadAloudPending.create,
            onPressed: busy || _language == null || epub == null ? null : _startFromOptions,
          ),
        ]),
      ),
    ];
  }

  Widget _wideButton(BuildContext context,
      {IconData? icon, required String label, required double height, bool pending = false, VoidCallback? onPressed}) {
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
          if (pending)
            ...[const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 8)]
          else if (icon != null)
            ...[Icon(icon, size: 18), const SizedBox(width: 8)],
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

  // ─── Audiobookshelf match search ──────────────────────────

  void _openAbsSearch() {
    _go(_Page.absSearch);
    // An empty query lists the unmatched items first.
    _c.searchAbs('');
  }

  Widget _resultRow(BuildContext context, AbsBookStateWire item) {
    final cs = Theme.of(context).colorScheme;
    final sub = [item.absAuthorName, item.absLibraryName].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.onSurface.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _c.busy
              ? null
              : () async {
                  if (await _c.absChange(item) && mounted) _go(_Page.chain);
                },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              _cover(context, AbsCover(item.absLibraryItemId), SyncEdition.abs, 36, 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.absTitle.isEmpty ? PositionSyncCopy.untitled : item.absTitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _absSearchPage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final results = [for (final item in _c.absCandidates) _resultRow(context, item)];
    final status = _c.searching
        ? PositionSyncCopy.searching
        : _c.searchError ?? (_c.hasSearched && results.isEmpty ? PositionSyncCopy.noMatches : null);
    return [
      _pageHeader(context, PositionSyncCopy.selectAbs, null),
      TextField(
        controller: _query,
        autofocus: true,
        onChanged: _c.searchAbs,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: PositionSyncCopy.searchAbs,
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
