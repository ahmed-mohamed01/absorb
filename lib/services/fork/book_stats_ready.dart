import 'dart:async';

import '../book_stats_service.dart';

// Fork-owned. See FORK_NOTES.md.

extension BookStatsReady on BookStats {
  /// The reader's own numbers are in, or known to have failed. The admin scan
  /// after them can take much longer and adds to the card without moving it.
  bool get ownReady => activity != null || !loading;

  /// Completes when [ownReady]; a caller that may give up waits with a timeout.
  Future<void> get whenOwnReady {
    if (ownReady) return Future.value();
    final done = Completer<void>();
    void check() {
      if (!ownReady) return;
      removeListener(check);
      done.complete();
    }
    addListener(check);
    return done.future;
  }
}
