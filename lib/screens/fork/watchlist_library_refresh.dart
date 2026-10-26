// Fork-owned: keeps the Watchlist's Library tabs fresh. A Watchlist write
// refreshes the releases grid in place and re-reads the authors list, and
// while BookOrbit is
// still fetching a followed author's books the authors list is re-read on a
// bounded timer. library_screen.dart owns one and feeds it. See
// FORK_NOTES.md.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../providers/library_provider.dart';
import '../../services/api_service.dart';
import '../../services/fork/watchlist_info.dart';
import '../../widgets/fork/watchlist_sort_sheet.dart';

/// The first [count] cards of the releases view on screen, read again through
/// the items route the grid pages through, with its total; null when a page
/// could not be read. After a write this is one window fetch, then memory.
Future<({List<Map<String, dynamic>> items, int total})?> watchlistReleasesHead(
    ApiService api, LibraryProvider lib, String libraryId, int count) async {
  final sort = switch (WatchlistSortChoice.sort) {
    WatchlistSort.date => 'addedAt',
    WatchlistSort.title => 'media.metadata.title',
    WatchlistSort.author => 'media.metadata.authorNameLF',
  };
  // The route serves at most 100 a page.
  const size = 100;
  final items = <Map<String, dynamic>>[];
  var total = 0;
  for (var page = 0; items.length < count; page++) {
    final res = await api.getLibraryItems(libraryId,
        page: page, limit: size, sort: sort, desc: WatchlistSortChoice.desc ? 1 : 0, filter: '');
    if (res == null) return null;
    final results = (res['results'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    total = (res['total'] as num?)?.toInt() ?? 0;
    items.addAll(results);
    if (results.length < size) break;
  }
  final head = items.length > count ? items.sublist(0, count) : items;
  for (final r in head) {
    final id = r['id'] as String?;
    if (id != null) lib.registerHasCover(id, (r['media'] as Map?)?['coverPath'] != null);
  }
  return (items: head, total: total);
}

class WatchlistLibraryRefresh {
  final String? Function() libraryId;
  final VoidCallback reloadReleases;
  final VoidCallback reloadAuthors;

  WatchlistLibraryRefresh({required this.libraryId, required this.reloadReleases, required this.reloadAuthors}) {
    WatchlistChanges.tick.addListener(_onChanged);
  }

  static const _releasesDelay = Duration(seconds: 2);
  static const _pollEvery = Duration(seconds: 10);
  static const _pollFor = Duration(minutes: 3);

  Timer? _releases;
  Timer? _poll;
  DateTime? _pollSince;
  Set<String> _fetching = const {};

  bool get _onWatchlist => WatchlistInfo.isLibrary(libraryId());

  // Writes come in bursts (a bulk action, a request then its first status
  // read), so the grid is reloaded once they settle.
  void _onChanged() {
    if (!_onWatchlist) return;
    reloadAuthors();
    _releases?.cancel();
    _releases = Timer(_releasesDelay, () {
      if (_onWatchlist) reloadReleases();
    });
  }

  /// Called with the authors on screen after each load. Polls while any of
  /// them is being fetched, for a few minutes at most; an author that starts
  /// fetching later opens a new window.
  void authorsShown(List<Map<String, dynamic>> authors) {
    final fetching = !_onWatchlist
        ? const <String>{}
        : {
            for (final a in authors)
              if (a['watchlist'] case final Map w when w['fetchState'] == 'queued' || w['fetchState'] == 'fetching')
                '${a['id']}',
          };
    if (fetching.isEmpty) {
      _stopPoll();
      return;
    }
    if (!fetching.every(_fetching.contains)) _pollSince = DateTime.now();
    _fetching = fetching;
    if (DateTime.now().difference(_pollSince!) >= _pollFor) {
      _poll?.cancel();
      return;
    }
    if (_poll?.isActive ?? false) return;
    _poll = Timer(_pollEvery, () {
      if (_onWatchlist) reloadAuthors();
    });
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
    _pollSince = null;
    _fetching = const {};
  }

  /// The library changed: nothing pending belongs to it.
  void reset() {
    _releases?.cancel();
    _stopPoll();
  }

  void dispose() {
    WatchlistChanges.tick.removeListener(_onChanged);
    reset();
  }
}
