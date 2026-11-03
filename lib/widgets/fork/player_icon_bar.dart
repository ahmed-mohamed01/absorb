part of '../card_buttons.dart';

// The player's icon bar, as BookOrbit's app draws it: a speed pill and plain
// icons (chapters, bookmarks, sleep timer, details) under the controls, and
// a pill of read / download / more - top right of the full player, in the
// Now Playing header for the small card. Replaces the button grid on both.

/// The icon row's buttons, left to right.
const _forkIconRowIds = ['speed', 'chapters', 'bookmarks', 'sleep', 'details'];

/// Buttons the pill carries, so More leaves them out.
const _forkTopPillIds = ['download', 'ebook'];

/// The full player's top bar: collapse on the left, the [pill] on the right,
/// on the page's 20dp edges.
class ForkPlayerHeader extends StatelessWidget {
  final bool compact;
  final VoidCallback onClose;
  final Widget pill;
  const ForkPlayerHeader({super.key, required this.compact, required this.onClose, required this.pill});

  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, compact ? 4 : 12, 20, 0),
      child: Row(
        children: [
          Tooltip(
            message: MaterialLocalizations.of(context).closeButtonTooltip,
            child: Semantics(
              button: true,
              child: Pressable(
                onTap: onClose,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.onSurface.withValues(alpha: 0.1),
                  ),
                  child: Icon(Icons.keyboard_arrow_down_rounded, size: 28,
                      color: cs.onSurface.withValues(alpha: 0.85)),
                ),
              ),
            ),
          ),
          const Spacer(),
          pill,
        ],
      ),
    );
  }
}

extension ForkPlayerBar on CardActionDelegate {
  /// What More lists under the icon bar: every button the row and pill
  /// don't carry, Manage Queue first when the page offers it. Read along is
  /// left out when the pill's book button already opens it.
  List<String> _forkIconBarOverflow() {
    final ids = _shownOrder.where((id) => id != '_more' && !_forkIconRowIds.contains(id) && !_forkTopPillIds.contains(id)
        && !(id == 'lyrics' && _readAlongInstead && hasEbook)).toList();
    if (onManageQueue != null) ids.insert(0, '_queue');
    return ids;
  }

  Widget _forkManageQueueItem(Color accent, BuildContext ctx) => MoreMenuItem(
    icon: Icons.reorder_rounded, label: AppLocalizations.of(context)!.absorbingManageQueue, accent: accent,
    onTap: () { Navigator.pop(ctx); onManageQueue?.call(); },
  );

  /// Plain icons in one row: a speed pill, then chapters, bookmarks, sleep
  /// timer and details. No boxes - the controls above carry the weight.
  Widget buildIconRow(Color accent, TextTheme tt) {
    final cs = Theme.of(context).colorScheme;
    final fg = cs.onSurface.withValues(alpha: _inkAlpha(0.8, 1.0));
    final isEpisode = episodeId != null || isPodcastEpisode;
    final items = <Widget>[
      PlayerSpeedPill(player: player, accent: accent, isActive: isActive, itemId: itemId),
      _PlainIconButton(
        icon: Icons.format_list_numbered_rounded, color: fg,
        tooltip: AppLocalizations.of(context)!.chapters,
        onTap: chapters.isNotEmpty ? () => showChapters(context, accent, tt) : _showNoChapters,
      ),
      _PlainIconButton(
        icon: Icons.bookmark_outline_rounded, color: fg,
        tooltip: AppLocalizations.of(context)!.bookmarks,
        onTap: () => _showBookmarkSheet(accent),
        onLongPress: isPlaybackActive ? _quickAddBookmark : null,
      ),
      ListenableBuilder(
        listenable: SleepTimerService(),
        builder: (_, __) {
          final sleep = SleepTimerService();
          final on = isPlaybackActive && sleep.isActive;
          String? label;
          if (on && sleep.mode == SleepTimerMode.time) {
            final r = sleep.timeRemaining;
            label = '${r.inMinutes.toString().padLeft(2, '0')}:${(r.inSeconds % 60).toString().padLeft(2, '0')}';
          } else if (on) {
            label = '${sleep.chaptersRemaining}ch';
          }
          return _PlainIconButton(
            icon: on ? Icons.nightlight_round : Icons.nightlight_round_outlined,
            color: on ? _inkAccent(accent) : (isPlaybackActive ? fg : cs.onSurface.withValues(alpha: _inkAlpha(0.3, 0.85))),
            tooltip: AppLocalizations.of(context)!.timer,
            label: label,
            onTap: isPlaybackActive ? () => showSleepTimerSheet(context, accent) : () => showInactiveToast(context),
          );
        },
      ),
      _PlainIconButton(
        icon: isEpisode ? Icons.podcasts_rounded : Icons.info_outline_rounded, color: fg,
        tooltip: isEpisode ? AppLocalizations.of(context)!.episodeDetailsLabel : AppLocalizations.of(context)!.bookDetailsLabel,
        onTap: _openDetails,
      ),
    ];
    // Space the five by their centres, edges flush with the row, so the
    // wider speed pill doesn't pull the icons off an even rhythm. On a row
    // too narrow for that the gaps bottom out at zero.
    return LayoutBuilder(builder: (context, constraints) {
      final step = (constraints.maxWidth - PlayerSpeedPill.width / 2 - _PlainIconButton.size / 2) / 4;
      final firstGap = (step - PlayerSpeedPill.width / 2 - _PlainIconButton.size / 2).clamp(0.0, double.infinity);
      final gap = (step - _PlainIconButton.size).clamp(0.0, double.infinity);
      return Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i == 1) SizedBox(width: firstGap) else if (i > 1) SizedBox(width: gap),
          items[i],
        ],
      ]);
    });
  }

  /// The pill at the player's top right: read (read along when the book's
  /// epub can follow the audio, the plain reader otherwise), download, more.
  ///
  /// [dense] is the Now Playing page header's size, next to its refresh
  /// button: smaller icons and the header's hairline border.
  Widget buildTopPill(Color accent, TextTheme tt, {bool dense = false}) {
    final cs = Theme.of(context).colorScheme;
    final fg = dense ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: _inkAlpha(0.85, 1.0));
    final divider = Container(width: 1, height: dense ? 16 : 22, color: cs.onSurface.withValues(alpha: dense ? 0.12 : 0.18));
    final showBook = hasEbook && episodeId == null && !isPodcastEpisode;
    final iconSize = dense ? 18.0 : 24.0;
    // Every button keeps Material's 48dp tap target; the dense pill only
    // looks 32dp tall, its buttons reach past it top and bottom.
    const w = 48.0;
    const h = 48.0;
    final decoration = BoxDecoration(
      color: dense ? cs.onSurface.withValues(alpha: 0.06) : cs.onSurface.withValues(alpha: _inkAlpha(0.1, 0.06)),
      borderRadius: BorderRadius.circular(28),
      border: dense ? Border.all(color: cs.onSurface.withValues(alpha: 0.08)) : null,
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBook) ...[
          _PlainIconButton(
            icon: isEbookPdf ? Icons.picture_as_pdf_outlined : Icons.menu_book_outlined,
            color: fg, iconSize: iconSize, width: w, height: h,
            tooltip: _readAlongInstead ? AppLocalizations.of(context)!.readAlong : 'Read',
            onTap: () => _readAlongInstead ? onReadAlongTap?.call() : onEbookTap?.call(),
          ),
          divider,
        ],
        ListenableBuilder(
          listenable: DownloadService(),
          builder: (_, __) {
            final dl = DownloadService();
            final key = _forkDownloadKey;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            if (dl.isDownloading(key)) {
              return _PlainIconButton(
                icon: Icons.close_rounded, color: _inkAccent(accent), iconSize: dense ? 11 : 14, width: w, height: h,
                tooltip: AppLocalizations.of(context)!.cancel,
                progress: dl.downloadProgress(key),
                onTap: _forkToggleDownload,
              );
            }
            final done = dl.isDownloaded(key);
            return _PlainIconButton(
              icon: done ? Icons.download_done_rounded : Icons.arrow_circle_down_outlined,
              color: done
                  ? (isDark ? Colors.greenAccent.withValues(alpha: 0.8) : Colors.green.shade700)
                  : fg,
              iconSize: iconSize, width: w, height: h,
              tooltip: done ? AppLocalizations.of(context)!.saved : AppLocalizations.of(context)!.download,
              onTap: _forkToggleDownload,
            );
          },
        ),
        divider,
        ListenableBuilder(
          listenable: ChromecastService(),
          builder: (_, __) {
            final casting = ChromecastService().isCasting;
            return _PlainIconButton(
              icon: casting ? Icons.cast_connected_rounded : Icons.more_horiz_rounded,
              color: casting ? _inkAccent(accent) : fg,
              iconSize: iconSize, width: w, height: h,
              tooltip: AppLocalizations.of(context)!.more,
              onTap: () => showMoreMenu(accent, tt, iconBar: true),
            );
          },
        ),
      ],
    );
    if (!dense) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: decoration,
        child: buttons,
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(left: 0, right: 0, top: 8, bottom: 8,
            child: DecoratedBox(decoration: decoration)),
        buttons,
      ],
    );
  }

  void _showBookmarkSheet(Color accent) {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.05, snap: true, maxChildSize: 0.9, expand: false,
        builder: (_, sc) => SimpleBookmarkSheet(itemId: itemId, episodeId: _bookmarkEpisodeId, player: player, accent: accent, scrollController: sc, onChanged: () {}),
      ),
    );
  }

  /// Long-press on the bookmark icon: drop one at the current position.
  Future<void> _quickAddBookmark() async {
    final l = AppLocalizations.of(context)!;
    final cast = ChromecastService();
    final pos = isCastingThis
        ? cast.castPosition.inMilliseconds / 1000.0
        : player.position.inMilliseconds / 1000.0;
    String? chTitle;
    for (final ch in isCastingThis ? cast.castingChapters : player.chapters) {
      final m = ch as Map<String, dynamic>;
      final s = (m['start'] as num?)?.toDouble() ?? 0;
      final e = (m['end'] as num?)?.toDouble() ?? 0;
      if (pos >= s && pos < e) { chTitle = m['title'] as String?; break; }
    }
    await BookmarkService().addBookmark(
        itemId: episodeKeyFor(itemId, _bookmarkEpisodeId), positionSeconds: pos,
        title: chTitle ?? l.bookmark, api: AudioPlayerService().currentApi);
    if (context.mounted) {
      showOverlayToast(context, l.bookmarkAdded, icon: Icons.bookmark_added_rounded);
    }
  }

  String get _forkDownloadKey => episodeId != null ? '$itemId-$episodeId' : itemId;

  /// Download, cancel, or (after a confirm) remove this card's audio.
  void _forkToggleDownload() {
    final l = AppLocalizations.of(context)!;
    final dlKey = _forkDownloadKey;
    final dl = DownloadService();
    if (dl.isDownloaded(dlKey)) {
      showDialog(context: context, builder: (dCtx) => AlertDialog(
        title: Text(l.removeDownloadQuestion),
        content: Text(l.removeDownloadContent),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l.cancel)),
          TextButton(onPressed: () {
            dl.deleteDownload(dlKey, byUser: true);
            Navigator.pop(dCtx);
            showOverlayToast(context, l.downloadRemoved, icon: Icons.delete_outline_rounded);
          }, child: Text(l.remove, style: const TextStyle(color: Colors.redAccent))),
        ],
      ));
    } else if (dl.isDownloading(dlKey)) {
      dl.cancelDownload(dlKey);
    } else {
      final auth = context.read<AuthProvider>();
      final api = auth.apiService;
      if (api == null) return;
      dl.downloadItem(api: api, itemId: dlKey, episodeId: episodeId, title: title, author: author, coverUrl: coverUrl, libraryId: context.read<LibraryProvider>().selectedLibraryId).then((error) {
        if (error != null && context.mounted) {
          showOverlayToast(context, error, icon: Icons.error_outline_rounded);
        }
      });
    }
  }
}

/// A borderless icon button for the player's icon bar and top pill. A
/// [label] replaces the icon (a running sleep timer's countdown); a
/// [progress] rings it (a download in flight).
class _PlainIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final String? label;
  final double? progress;
  final double iconSize;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const _PlainIconButton({required this.icon, required this.color, required this.tooltip, this.label, this.progress, this.iconSize = 24, this.width = size, this.height = size, this.onTap, this.onLongPress});

  /// Material's minimum touch target.
  static const size = 48.0;

  @override Widget build(BuildContext context) {
    final Widget content;
    if (label != null) {
      content = Text(label!, maxLines: 1, style: TextStyle(
        color: color, fontSize: 13, fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()]));
    } else if (progress != null) {
      content = Stack(alignment: Alignment.center, children: [
        SizedBox.square(dimension: iconSize < 14 ? 17 : 22, child: CircularProgressIndicator(
          value: progress!.clamp(0.0, 1.0), strokeWidth: 2.2, color: color,
          backgroundColor: color.withValues(alpha: 0.2))),
        Icon(icon, size: iconSize, color: color),
      ]);
    } else {
      content = Icon(icon, size: iconSize, color: color);
    }
    final button = Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(width: width, height: height, child: Center(child: content)),
    );
    // Long-press names the button, as Android's icon buttons do - unless
    // long-press already does something (quick bookmark).
    if (onLongPress != null) {
      return Semantics(button: true, label: tooltip, child: button);
    }
    return Tooltip(message: tooltip, child: Semantics(button: true, child: button));
  }
}

/// The speed control on the player's icon bar: the current rate in a pill.
class PlayerSpeedPill extends StatefulWidget {
  final AudioPlayerService player;
  final Color accent;
  final bool isActive;
  final String itemId;
  const PlayerSpeedPill({super.key, required this.player, required this.accent, required this.isActive, required this.itemId});

  /// Fixed so the icon row can space around it; fits "1.75x".
  static const width = 72.0;

  @override State<PlayerSpeedPill> createState() => _PlayerSpeedPillState();
}

class _PlayerSpeedPillState extends State<PlayerSpeedPill> {
  double _savedSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _loadSavedSpeed();
    PlayerSettings.settingsChanged.addListener(_loadSavedSpeed);
  }

  @override
  void dispose() {
    PlayerSettings.settingsChanged.removeListener(_loadSavedSpeed);
    super.dispose();
  }

  Future<void> _loadSavedSpeed() async {
    final speed = await PlayerSettings.getBookSpeed(widget.itemId) ?? await PlayerSettings.getDefaultSpeed();
    if (mounted && speed != _savedSpeed) setState(() => _savedSpeed = speed);
  }

  /// 1.0 -> "1x", 1.75 -> "1.75x", 1.5 -> "1.5x".
  static String _fmt(double v) {
    var t = v.toStringAsFixed(2);
    t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '${t}x';
  }

  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cast = ChromecastService();
    return ListenableBuilder(
      listenable: Listenable.merge([cast, widget.player]),
      builder: (context, _) {
        final castNow = cast.isCasting && cast.castingItemId == widget.itemId;
        final speed = castNow ? cast.castSpeed : (widget.isActive ? widget.player.speed : _savedSpeed);
        final changed = (speed - 1.0).abs() >= 0.01;
        return Semantics(
          button: true,
          label: AppLocalizations.of(context)!.speed,
          child: Pressable(
            onTap: () => showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
              useSafeArea: true,
              builder: (_) => CardSpeedSheet(player: widget.player, accent: widget.accent, itemId: widget.itemId)),
            child: Container(
              width: PlayerSpeedPill.width,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: _inkAlpha(0.1, 0.06)),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(_fmt(speed), style: TextStyle(
                color: changed ? _inkAccent(widget.accent) : cs.onSurface.withValues(alpha: _inkAlpha(0.85, 1.0)),
                fontSize: 15, fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
        );
      },
    );
  }
}
