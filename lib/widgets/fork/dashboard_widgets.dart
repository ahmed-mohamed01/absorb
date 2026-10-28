import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/api_service.dart';
import '../../services/audio_player_service.dart';
import '../../services/fork/dashboard_widgets_model.dart';
import '../wavy_progress_indicator.dart';

// Fork-owned: the widget strip at the top of the Dashboard Home (Currently
// Reading, Reading Streak, Reading Rhythm, Reading Goal) from BookOrbit's
// dashboard widgets. Hooked in from home_screen.dart; see FORK_NOTES.md. Its
// text is plain English until upstream takes it.

const _kGap = 10.0;
const _kSide = 20.0;
const _kBaseHeight = 270.0; // three Currently Reading panes at normal text

/// How long after the player changes book or stops before the strip asks the
/// server again, so its Currently Reading list has caught up.
const _kCatchUpDelay = Duration(seconds: 3);

/// What the Currently Reading card needs from the player: the book it holds
/// (as a row to show when the server does not list it yet) and whether it
/// is playing.
typedef ForkLiveState = ({String? activeBookId, ForkWidgetBook? activeBook, bool playing});

/// Loads the Dashboard widgets from BookOrbit and shows them as a sideways
/// row; takes no space while loading, off BookOrbit, or when there are none.
class ForkDashboardWidgetStrip extends StatefulWidget {
  /// Bumped by Home's pull to refresh; any change refetches fresh.
  final int refreshTick;

  /// Opens a book's detail sheet.
  final void Function(String bookId) onOpenBook;

  /// Opens the player, for the row of the book that is playing.
  final VoidCallback onOpenPlayer;

  /// Opens the Stats tab.
  final VoidCallback onOpenStats;

  /// The cover image address for a book, or null for a plain tile.
  final String? Function(String bookId) coverUrl;

  /// Creates the strip; it loads its own data and saves the goal itself.
  const ForkDashboardWidgetStrip({
    super.key,
    required this.refreshTick,
    required this.onOpenBook,
    required this.onOpenPlayer,
    required this.onOpenStats,
    required this.coverUrl,
  });

  @override
  State<ForkDashboardWidgetStrip> createState() => _ForkDashboardWidgetStripState();
}

class _ForkDashboardWidgetStripState extends State<ForkDashboardWidgetStrip> with WidgetsBindingObserver {
  ForkDashboardWidgets? _data;
  int _generation = 0;
  final _player = AudioPlayerService();

  /// Ticks once a second while playing, so the playing row's bar moves even
  /// when the player has nothing else to say. It only runs while this tab's
  /// tickers are on and the app is in front.
  final _secondTick = ValueNotifier<int>(0);
  Timer? _timer;
  late final Listenable _live = Listenable.merge([_player, _secondTick]);

  // Off while Home is a hidden tab (AppShell's TickerMode).
  ValueListenable<bool>? _tickerMode;
  AppLifecycleState? _lifecycle;

  // What the player held last time, to spot a new book or a stop.
  String? _lastItemId;
  bool _wasPlaying = false;
  Timer? _catchUp;

  // A catch-up fetch that came due while Home was hidden or the app was in
  // the background; it runs once the strip can be seen again.
  bool _refetchDue = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    _lastItemId = _player.currentItemId;
    _wasPlaying = _player.isPlaying;
    _player.addListener(_onPlayer);
    _load(fresh: widget.refreshTick > 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = TickerMode.getNotifier(context);
    if (!identical(notifier, _tickerMode)) {
      _tickerMode?.removeListener(_syncTimer);
      _tickerMode = notifier..addListener(_syncTimer);
    }
    _syncTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickerMode?.removeListener(_syncTimer);
    _player.removeListener(_onPlayer);
    _timer?.cancel();
    _catchUp?.cancel();
    _secondTick.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncTimer();
  }

  // True while the strip can be seen: this tab's tickers are on and the app
  // is resumed.
  bool get _visible =>
      (_tickerMode?.value ?? true) && (_lifecycle == null || _lifecycle == AppLifecycleState.resumed);

  // Runs the one-second tick only while playing and visible, and stops it
  // otherwise. Also runs a catch-up fetch that came due while hidden.
  void _syncTimer() {
    final visible = _visible;
    if (visible && _refetchDue && mounted) {
      _refetchDue = false;
      _load(fresh: true);
    }
    if (_player.isPlaying && visible && mounted) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _secondTick.value++);
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  // Starts or stops the tick, and asks the server again a little after the
  // player changes book or stops. While hidden the fetch waits until the
  // strip can be seen. The Currently Reading card listens itself.
  void _onPlayer() {
    _syncTimer();
    final itemId = _player.currentItemId;
    final playing = _player.isPlaying;
    final changed = itemId != _lastItemId || (_wasPlaying && !playing);
    _lastItemId = itemId;
    _wasPlaying = playing;
    if (!changed) return;
    _catchUp?.cancel();
    _catchUp = Timer(_kCatchUpDelay, () {
      if (!mounted) return;
      if (_visible) {
        _load(fresh: true);
      } else {
        _refetchDue = true;
      }
    });
  }

  ForkLiveState _liveState() {
    if (!_player.hasBook) return (activeBookId: null, activeBook: null, playing: _player.isPlaying);
    final id = _player.currentItemId!;
    final author = _player.currentAuthor;
    return (
      activeBookId: id,
      activeBook: ForkWidgetBook(
        bookId: id,
        title: _player.currentTitle ?? '',
        authors: author == null || author.isEmpty ? const [] : [author],
      ),
      playing: _player.isPlaying,
    );
  }

  double? _liveProgress(String bookId) {
    final live = _player.hasBook && _player.currentItemId == bookId
        ? forkLiveFraction(seconds: _player.position.inMilliseconds / 1000, total: _player.totalDuration)
        : null;
    if (live != null || !mounted) return live;
    final p = context.read<LibraryProvider>().getProgress(bookId);
    return p > 0 ? p : null;
  }

  @override
  void didUpdateWidget(ForkDashboardWidgetStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _load(fresh: true);
  }

  Future<void> _load({required bool fresh}) async {
    final generation = ++_generation;
    final api = context.read<AuthProvider>().apiService;
    final result = api is BookOrbitApiService ? await api.forkDashboardWidgets(fresh: fresh) : null;
    if (!mounted || generation != _generation) return;
    // A failed refresh keeps what was showing.
    if (result == null && fresh && api is BookOrbitApiService) return;
    setState(() => _data = result);
  }

  Future<bool> _setGoal(int goalBooks) async {
    final api = context.read<AuthProvider>().apiService;
    final ok = api is BookOrbitApiService && await api.forkSetReadingGoal(goalBooks);
    if (ok && mounted) await _load(fresh: true);
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null || data.widgets.isEmpty) return const SizedBox.shrink();
    return ForkDashboardWidgetRow(
      data: data,
      onOpenBook: widget.onOpenBook,
      onOpenPlayer: widget.onOpenPlayer,
      onOpenStats: widget.onOpenStats,
      onSetGoal: _setGoal,
      coverUrl: widget.coverUrl,
      httpHeaders: context.read<LibraryProvider>().mediaHeaders,
      liveProgress: _liveProgress,
      liveUpdates: _live,
      liveState: _liveState,
    );
  }
}

/// The sideways row of widget cards, free of providers so tests can pump it.
class ForkDashboardWidgetRow extends StatelessWidget {
  /// The widgets to show, in the server's order.
  final ForkDashboardWidgets data;

  /// Opens a book from a Currently Reading row.
  final void Function(String bookId) onOpenBook;

  /// Opens the player from the row of the book that is playing.
  final VoidCallback onOpenPlayer;

  /// Opens Stats when a card is tapped.
  final VoidCallback onOpenStats;

  /// Saves the yearly goal and says whether it worked.
  final Future<bool> Function(int goalBooks) onSetGoal;

  /// The cover image address for a book, or null for a plain tile.
  final String? Function(String bookId) coverUrl;

  /// Headers for the cover requests.
  final Map<String, String>? httpHeaders;

  /// The book the player holds; its Currently Reading row moves to the top.
  final String? activeBookId;

  /// The player's book as a row, shown first when [activeBookId] matches no
  /// row from the server yet (it must carry the same id).
  final ForkWidgetBook? activeBook;

  /// While true the active row's bar is wavy.
  final bool playing;

  /// This phone's progress for a book (0 to 1), or null to use the server's.
  final double? Function(String bookId)? liveProgress;

  /// When set, only the Currently Reading card rebuilds on its changes,
  /// reading [liveState] for the active book and playing state in place of
  /// [activeBookId], [activeBook] and [playing].
  final Listenable? liveUpdates;

  /// Reads the player's state each time [liveUpdates] fires.
  final ForkLiveState Function()? liveState;

  /// Creates the row; pass [liveUpdates] and [liveState] together.
  const ForkDashboardWidgetRow({
    super.key,
    required this.data,
    required this.onOpenBook,
    required this.onOpenPlayer,
    required this.onOpenStats,
    required this.onSetGoal,
    required this.coverUrl,
    this.httpHeaders,
    this.activeBookId,
    this.activeBook,
    this.playing = false,
    this.liveProgress,
    this.liveUpdates,
    this.liveState,
  });

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final w in data.widgets)
        if (forkSupportedWidgetTypes.contains(w.type) && w.data != null) w,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    final mq = MediaQuery.of(context);
    final scale = mq.textScaler.scale(1);
    final maxWidth = math.max(160.0, mq.size.width - 2 * _kSide);
    final height = _kBaseHeight + (scale - 1).clamp(0.0, 2.0) * 110;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: _kSide),
          physics: const BouncingScrollPhysics(),
          itemCount: shown.length,
          separatorBuilder: (_, __) => const SizedBox(width: _kGap),
          itemBuilder: (context, i) => SizedBox(
            width: math.min(_cardWidth(shown[i]), maxWidth),
            child: _card(context, shown[i]),
          ),
        ),
      ),
    );
  }

  Widget _readingBody(ForkCurrentlyReading d, String? active, ForkWidgetBook? book, bool isPlaying) =>
      _CurrentlyReadingBody(
        d,
        onOpenBook: onOpenBook,
        onOpenPlayer: onOpenPlayer,
        coverUrl: coverUrl,
        httpHeaders: httpHeaders,
        activeBookId: active,
        activeBook: book,
        playing: isPlaying,
        liveProgress: liveProgress,
      );

  /// Each card is as wide as its content needs: the lists and the fortnight
  /// of bars take the full width, the streak and the goal ring less.
  static double _cardWidth(ForkDashboardWidget w) => switch (w.type) {
        forkWidgetReadingStreak => 230.0,
        forkWidgetReadingGoal => 250.0,
        _ => 300.0,
      };

  Widget _card(BuildContext context, ForkDashboardWidget w) {
    final d = w.data;
    if (d is ForkCurrentlyReading) {
      return _ForkCard(
        icon: Icons.menu_book_rounded,
        title: 'Currently Reading',
        onTap: onOpenStats,
        child: liveUpdates == null || liveState == null
            ? _readingBody(d, activeBookId, activeBook, playing)
            : ListenableBuilder(
                listenable: liveUpdates!,
                builder: (_, __) {
                  final live = liveState!();
                  return _readingBody(d, live.activeBookId, live.activeBook, live.playing);
                },
              ),
      );
    }
    if (d is ForkReadingStreak) {
      return _ForkCard(
        icon: Icons.local_fire_department_rounded,
        title: 'Reading Streak',
        onTap: onOpenStats,
        child: _StreakBody(d),
      );
    }
    if (d is ForkReadingRhythm) {
      return _ForkCard(
        icon: Icons.monitor_heart_outlined,
        title: 'Reading Rhythm',
        onTap: onOpenStats,
        child: _RhythmBody(d),
      );
    }
    if (d is ForkReadingGoal) {
      return _ForkCard(
        icon: Icons.track_changes_rounded,
        title: 'Reading Goal ${d.year}',
        onTap: onOpenStats,
        child: _GoalBody(d, onSetGoal: onSetGoal),
      );
    }
    return const SizedBox.shrink();
  }
}

class _ForkCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Widget child;

  const _ForkCard({required this.icon, required this.title, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Translucent like BookOrbit's cards, so Home's tint shows through.
    final bg = cs.onSurface.withValues(alpha: 0.04);
    final radius = BorderRadius.circular(20);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: cs.primary.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentlyReadingBody extends StatelessWidget {
  final ForkCurrentlyReading data;
  final void Function(String bookId) onOpenBook;
  final VoidCallback onOpenPlayer;
  final String? Function(String bookId) coverUrl;
  final Map<String, String>? httpHeaders;
  final String? activeBookId;
  final ForkWidgetBook? activeBook;
  final bool playing;
  final double? Function(String bookId)? liveProgress;

  const _CurrentlyReadingBody(
    this.data, {
    required this.onOpenBook,
    required this.onOpenPlayer,
    required this.coverUrl,
    this.httpHeaders,
    this.activeBookId,
    this.activeBook,
    this.playing = false,
    this.liveProgress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // The playing book first; the rest keep the server's order. A book the
    // server does not list yet comes from the player.
    final books = [...data.books];
    final activeIndex = books.indexWhere((b) => b.bookId == activeBookId);
    final seed = activeBook;
    if (activeIndex > 0) {
      books.insert(0, books.removeAt(activeIndex));
    } else if (activeIndex < 0 && seed != null && activeBookId != null && seed.bookId == activeBookId) {
      books.insert(0, seed);
    }
    if (books.isEmpty) {
      return Center(
        child: Text('Nothing in progress',
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      physics: const BouncingScrollPhysics(),
      itemCount: books.length,
      itemBuilder: (context, i) {
        final b = books[i];
        final url = coverUrl(b.bookId);
        final placeholder = Container(color: cs.surfaceContainerHighest);
        final progress = (liveProgress?.call(b.bookId) ?? b.progress).clamp(0.0, 1.0).toDouble();
        final percent = (progress * 100).round();
        final track = cs.outlineVariant.withValues(alpha: 0.5);
        final wavy = playing && b.bookId == activeBookId;
        // Each row sits in its own lighter pane, as BookOrbit draws them.
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: cs.onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('fork-widget-book-${b.bookId}'),
              // The playing book's row goes to the player; any other opens the book.
              onTap: () => wavy ? onOpenPlayer() : onOpenBook(b.bookId),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: url == null
                            ? placeholder
                            : CachedNetworkImage(
                                imageUrl: url,
                                httpHeaders: httpHeaders,
                                fit: BoxFit.cover,
                                // No fade, so moving a row to the top does not replay it.
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (_, __) => placeholder,
                                errorWidget: (_, __, ___) => placeholder,
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(b.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          if (b.authors.isNotEmpty)
                            Text(b.authors.join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Row(children: [
                            // One 12 px slot for either bar, so the row keeps its height.
                            Expanded(
                              child: SizedBox(
                                height: 12,
                                child: wavy
                                    ? WavyProgressIndicator(
                                        value: progress,
                                        color: cs.primary,
                                        trackColor: track,
                                        height: 12,
                                        strokeWidth: 3,
                                        amplitude: 2,
                                      )
                                    : Center(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(2),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            minHeight: 4,
                                            color: cs.primary,
                                            backgroundColor: track,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('$percent%', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StreakBody extends StatelessWidget {
  final ForkReadingStreak data;
  const _StreakBody(this.data);

  String _days(int n) => n == 1 ? 'day' : 'days';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final dim = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    // Always seven slots, so the block keeps its width, and so its scale in
    // the card, however many days the server sent.
    final recent = data.lastSevenDays.length > 7
        ? data.lastSevenDays.sublist(data.lastSevenDays.length - 7)
        : data.lastSevenDays;
    final dots = [...List.filled(7 - recent.length, false), ...recent];
    // One centred block, as BookOrbit draws it, scaled as a whole to fill
    // the card: up on a wide card, down when large text would not fit.
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.local_fire_department_rounded, size: 34, color: cs.primary),
              const SizedBox(width: 6),
              Text('${data.currentStreak}',
                  style: tt.displayMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary, height: 1.05)),
            ]),
            Text('${_days(data.currentStreak)} streak', style: tt.bodyMedium),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.emoji_events_outlined, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('Best: ${data.longestStreak} ${_days(data.longestStreak)}', style: dim),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < dots.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dots[i] ? cs.primary : cs.outlineVariant,
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Text('Last 7 days', style: dim),
          ],
        ),
      ),
    );
  }
}

class _RhythmBody extends StatelessWidget {
  final ForkReadingRhythm data;
  const _RhythmBody(this.data);

  static const _initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  static String _avg(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? 'avg ${h}h ${m}m/day' : 'avg ${m}m/day';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final dim = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final maxSeconds = data.days.fold<int>(0, (m, d) => math.max(m, d.readingSeconds));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final day in data.days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(children: [
                      Expanded(
                        child: LayoutBuilder(builder: (context, c) {
                          final frac = maxSeconds == 0 ? 0.0 : day.readingSeconds / maxSeconds;
                          final h = day.readingSeconds == 0 ? 3.0 : math.max(3.0, c.maxHeight * frac);
                          return Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: h,
                              decoration: BoxDecoration(
                                color: day.readingSeconds == 0
                                    ? cs.primary.withValues(alpha: 0.35)
                                    : cs.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 14,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_initials[day.date.weekday - 1],
                              style: dim, textScaler: TextScaler.noScaling),
                        ),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final roomy = c.maxWidth >= 240 && scale <= 1.3;
          final left = Text(
            '${data.activeDays} active days · ${data.consistencyPercent}% consistency',
            maxLines: roomy ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: dim,
          );
          if (!roomy) return left;
          return Row(children: [
            Expanded(child: left),
            const SizedBox(width: 8),
            Text(_avg(data.avgSecondsPerDay), style: dim),
          ]);
        }),
      ],
    );
  }
}

class _GoalBody extends StatelessWidget {
  final ForkReadingGoal data;
  final Future<bool> Function(int goalBooks) onSetGoal;

  const _GoalBody(this.data, {required this.onSetGoal});

  Future<void> _edit(BuildContext context) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _GoalDialog(initial: data.goalBooks),
    );
    if (value == null || value <= 0) return;
    final ok = await onSetGoal(value);
    if (!ok && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not save the goal')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final dim = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final goal = data.goalBooks;
    final hasGoal = goal != null && goal > 0;
    final fraction = hasGoal ? (data.completedBooks / goal).clamp(0.0, 1.0) : 0.0;
    // The web caps a beaten goal at 100%.
    final percent = hasGoal ? (data.completedBooks * 100 / goal).round().clamp(0, 100) : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: CustomPaint(
                painter: _GoalRingPainter(fraction, cs.primary, cs.outlineVariant),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('${data.completedBooks}',
                            style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.bold, height: 1.05)),
                        Text(hasGoal ? 'of $goal' : 'No goal', style: dim),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(children: [
          Expanded(
            child: hasGoal
                ? Text('$percent% complete', maxLines: 1, overflow: TextOverflow.ellipsis, style: dim)
                : const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: 'Edit goal',
            onPressed: () => _edit(context),
            icon: Icon(Icons.edit_outlined, size: 18, color: cs.onSurfaceVariant),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          ),
        ]),
      ],
    );
  }
}

/// Asks for the yearly goal; owns its text controller so it is disposed when
/// the dialog goes, after its closing animation.
class _GoalDialog extends StatefulWidget {
  final int? initial;
  const _GoalDialog({this.initial});

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final _controller = TextEditingController(text: widget.initial?.toString() ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Reading goal'),
        content: TextField(
          key: const ValueKey('fork-reading-goal-field'),
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Books this year'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, int.tryParse(_controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      );
}

class _GoalRingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color track;

  _GoalRingPainter(this.fraction, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    if (rect.width <= 0 || rect.height <= 0) return;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base);
    if (fraction <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = fraction >= 1 ? StrokeCap.butt : StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(_GoalRingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}
