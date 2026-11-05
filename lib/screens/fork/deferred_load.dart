// Fork-owned: a load that waits a moment so the screen's first requests go
// first, unless something needs it sooner. library_screen.dart uses one for
// its filter data. See FORK_NOTES.md.
import 'dart:async';

/// Runs [load] [delay] after the last [schedule], or at once from [now]
/// while one is still waiting.
class ForkDeferredLoad {
  ForkDeferredLoad(this.delay, this.load);

  final Duration delay;
  final Future<void> Function() load;
  Timer? _timer;

  void schedule() {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(load()));
  }

  /// Runs a waiting load now; nothing when none is waiting.
  Future<void> now() async {
    final waiting = _timer;
    if (waiting == null || !waiting.isActive) return;
    waiting.cancel();
    await load();
  }

  void dispose() => _timer?.cancel();
}
