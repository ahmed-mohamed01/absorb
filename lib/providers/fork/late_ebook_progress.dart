// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of '../library_provider.dart';

// Fork-owned: merges the BookOrbit ebook positions that land after the rest
// of the progress (`forkLateEbookProgress`, bookorbit_perf.dart) into the
// provider. The constructor's one-line listener is the hook. See
// FORK_NOTES.md.

extension _ForkLateEbookProgress on LibraryProvider {
  /// The ebook positions BookOrbit reads after the rest of the
  /// progress. Furthest wins, as in `_refreshProgress`, so a page read here
  /// and not yet sent isn't rewound. When the books read as ebooks changed,
  /// Continue Reading reloads once any Home load under way has finished
  /// (joining that load would return the shelves it fetched without them).
  Future<void> _forkMergeLateEbookProgress() async {
    final late = forkLateEbookProgress.value;
    if (late == null || isOffline || _api?.isBookOrbit != true) return;
    for (final e in late.ebook.entries) {
      final current = _progressMap[e.key];
      if (current == null) continue;
      final server = (e.value['ebookProgress'] as num?)?.toDouble() ?? -1;
      final have = (current['ebookProgress'] as num?)?.toDouble() ?? -1;
      if (server > have) _progressMap[e.key] = {...current, ...e.value};
    }
    notifyListeners();
    if (!late.cardsChanged) return;
    final home = _personalizedInFlight;
    if (home != null) await home;
    await refreshProgressShelves(force: true, reason: 'ebook-progress');
  }
}
