part of '../api_service.dart';

// Fork-owned: BookOrbit's Watchlist (code name `monitored`) as one more
// virtual library, the way the Book Dock is one. The hooks in
// bookorbit_api_service.dart are the library list, the `libraries/<id>`,
// `items/<id>` and `authors/<id>` dispatch, `getCoverUrl`,
// `getAuthorImageUrl` and `clearCaches`. See FORK_NOTES.md.

const _watchItemPrefix = 'watch-';
const _watchAuthorPrefix = 'watch-author-';
const _watchSeriesPrefix = 'watch-series-';
const _watchFormats = ['ebook', 'audiobook'];

/// Every watchlist item the list routes handed out, so a sheet opened from a
/// shelf or the grid reads it back without another server call. Insertion
/// order doubles as recency.
final Map<String, Map<String, dynamic>> _watchItems = {};
const _watchItemsMax = 2000;

/// Provider cover URL per item id. Kept apart from [_watchItems] and far
/// longer, because `getCoverUrl` only gets an id: a grid scrolled back past
/// the item cache must still find its covers.
final Map<String, String> _watchCovers = {};
const _watchCoversMax = 20000;

/// Followed authors from the last author list, as ABS author maps.
final Map<String, Map<String, dynamic>> _watchAuthors = {};
const _watchAuthorsMax = 2000;

/// Folder paths of every BookOrbit library, by `<server>|<library id>`, kept
/// from the raw library list because the mapped list drops them. Refilled
/// whenever that list is fetched.
final Map<String, List<String>> _watchLibraryRoots = {};

/// Whether each server has a watchlist, by base URL, from `GET /monitored`.
final Map<String, ({DateTime at, Map<String, dynamic>? summary})> _watchSummaries = {};
const _watchSummaryTtl = Duration(minutes: 5);
// A failed check is kept briefly so a server that hangs on `/monitored` does
// not hold up every library list for the full request timeout.
const _watchSummaryRetry = Duration(seconds: 30);
const _watchSummaryTimeout = Duration(seconds: 8);

void _watchRemember<T>(Map<String, T> cache, String key, T value, int max) {
  cache.remove(key);
  cache[key] = value;
  while (cache.length > max) {
    cache.remove(cache.keys.first);
  }
}

/// The Releases grid merged per work, by server, sort, order, status and
/// view. The server pages per format, so a page of works can only be cut
/// from the whole merged window; the window is bounded server-side (90 days
/// back, 365 ahead).
final Map<String, ({DateTime at, List<Map<String, dynamic>> items})> _watchMerged = {};
const _watchMergedTtl = Duration(seconds: 60);
const _watchMergedMax = 1000;
// Entries of [_watchMerged]: every sort, order, status set and view is one.
const _watchMergedEntries = 8;

/// The window fetch running for each [_watchMerged] base key, so both views
/// asked for together share one fetch.
final Map<String, Future<Map<WatchlistWhen, List<Map<String, dynamic>>>>> _watchMergedInFlight = {};

/// The last full release merge per server, by item id. A big author
/// catalogue can push release items out of [_watchItems] while the grid
/// still shows them, so the item route falls back to this.
final Map<String, Map<String, Map<String, dynamic>>> _watchLastMerge = {};

/// The last download percent read for each book request, by server, then
/// request id. Cards are rebuilt from server data, which carries no percent,
/// so [_ForkBookOrbitWatchlist._watchItem] stamps it from here.
final Map<String, Map<int, ({int percent, DateTime at})>> _watchProgress = {};
const _watchProgressTtl = Duration(minutes: 2);

/// Old item ids carried a `~<format>` suffix; a cached one still opens.
String _watchItemKey(String itemId) {
  final cut = itemId.indexOf('~');
  return cut < 0 ? itemId : itemId.substring(0, cut);
}

/// A followed author's works as items, from `GET /monitored/authors/:id`, by
/// `<server>|<monitor id>`. The author sheet fills it and the series sheets
/// of that author read from it.
final Map<String, ({DateTime at, Map<String, dynamic> author, List<Map<String, dynamic>> items})> _watchAuthorWorks = {};
const _watchAuthorWorksTtl = Duration(seconds: 60);
const _watchAuthorWorksMax = 20;

/// The author fetch running for each [_watchAuthorWorks] key, so the series
/// items and series record asked for together share one call.
final Map<String, Future<({Map<String, dynamic> author, List<Map<String, dynamic>> items})?>> _watchAuthorWorksInFlight = {};

/// Bumped by every write, so an author fetch that started before it does not
/// put pre-write works back into [_watchAuthorWorks].
int _watchGeneration = 0;

/// Series ids travel in URL paths and in a base64 filter, so the name is
/// carried base64url-encoded behind a `~` that neither part can contain.
String _watchSeriesId(String monitorAuthorId, String seriesName) =>
    '$_watchSeriesPrefix$monitorAuthorId~${base64Url.encode(utf8.encode(seriesName)).replaceAll('=', '')}';

({String monitorAuthorId, String name})? _watchParseSeriesId(String seriesId) {
  if (!seriesId.startsWith(_watchSeriesPrefix)) return null;
  final rest = seriesId.substring(_watchSeriesPrefix.length);
  final cut = rest.indexOf('~');
  if (cut <= 0) return null;
  try {
    return (
      monitorAuthorId: rest.substring(0, cut),
      name: utf8.decode(base64Url.decode(base64Url.normalize(rest.substring(cut + 1)))),
    );
  } catch (_) {
    return null;
  }
}

/// The two views of the Releases grid: formats still to come (or with no
/// date yet) and formats already out.
enum WatchlistWhen { upcoming, outNow }

/// Which release statuses the Releases grid asks for; empty is the server's
/// default set. The sort sheet writes it, the items route reads it.
class WatchlistReleaseFilter {
  /// The view the grid shows, kept for the app session. The Recent and
  /// Upcoming pills write it.
  static WatchlistWhen when = WatchlistWhen.upcoming;

  static const options = [
    ('missing', 'Missing'),
    ('upcoming', 'Upcoming'),
    ('in_progress', 'In progress'),
    ('needs_attention', 'Needs you'),
    ('in_library', 'Owned'),
  ];

  static Set<String> status = {};

  /// The `status` query value in the server's order, or null for its default.
  static String? get query {
    final picked = [for (final o in options) if (status.contains(o.$1)) o.$1];
    return picked.isEmpty ? null : picked.join(',');
  }
}

/// Bumped after every Watchlist write, and after a request status read that
/// saw a real change, so the library screen can reload what it shows.
class WatchlistChanges {
  static final ValueNotifier<int> tick = ValueNotifier(0);
}

void _watchlistClearCaches() {
  _watchMerged.clear();
  _watchMergedInFlight.clear();
  _watchLastMerge.clear();
  _watchProgress.clear();
  _watchAuthorWorks.clear();
  _watchAuthorWorksInFlight.clear();
  _watchGeneration++;
  _watchItems.clear();
  _watchCovers.clear();
  _watchAuthors.clear();
  _watchSummaries.clear();
}

int? _watchMs(Object? date) {
  if (date is! String) return null;
  final m = RegExp(r'^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?').firstMatch(date.trim());
  if (m == null) return null;
  return DateTime.utc(
    int.parse(m.group(1)!),
    int.tryParse(m.group(2) ?? '') ?? 1,
    int.tryParse(m.group(3) ?? '') ?? 1,
  ).millisecondsSinceEpoch;
}

/// Whether a release item's window has opened by [todayUtc] (`YYYY-MM-DD`),
/// on [WatchlistInfo.releaseStarted]'s rule.
bool _watchReleaseStarted(Map<String, dynamic> release, String todayUtc) {
  final text = '${release['releaseDate'] ?? ''}'.trim();
  return WatchlistInfo.releaseStarted(text, _watchReleasePrecision(release, text), today: todayUtc);
}

/// A release item carries no precision. Its date is the work's catalog date
/// for the format (or the release probe's), and the precision is stored
/// beside that; null when neither matches.
String? _watchReleasePrecision(Map<String, dynamic> release, String text) {
  final work = release['work'] as Map?;
  final audio = release['format'] == 'audiobook';
  final column = audio ? 'audio' : 'ebook';
  final own = work?['${column}DatePrecision'];
  if ('${work?['${column}ReleaseDate'] ?? ''}'.trim() == text && own is String) return own;
  final probe = (work?['formatReleases'] as Map?)?[audio ? 'audiobook' : 'ebook'];
  if (probe is Map && '${probe['releaseDate'] ?? ''}'.trim() == text && probe['precision'] is String) {
    return probe['precision'] as String;
  }
  return null;
}

extension _ForkBookOrbitWatchlist on BookOrbitApiService {
  static const _libraryName = 'Watchlist';

  Future<Map<String, dynamic>?> _watchSummary() async {
    final key = _cleanBaseUrl;
    final hit = _watchSummaries[key];
    if (hit != null && DateTime.now().difference(hit.at) < _watchSummaryTtl) return hit.summary;
    // Asked alongside the summary for the library picker's badge; it counts
    // formats, the way the server's release list does.
    final needsYou = _boGet('/monitored/releases', {'status': 'needs_attention', 'page': 0, 'size': 1}, _watchSummaryTimeout)
        .then<int?>((r) => ((r as Map)['total'] as num?)?.toInt(), onError: (Object e) {
      debugPrint('[Watchlist] needs-you count: $e');
      return null;
    });
    try {
      final s = await _boGet('/monitored', null, _watchSummaryTimeout) as Map<String, dynamic>;
      s['watchlistNeedsYou'] = await needsYou ?? 0;
      _watchSummaries[key] = (at: DateTime.now(), summary: s);
      return s;
    } on _BoHttpError catch (e) {
      // A server without the watchlist answers 404; other errors are not an
      // answer, so they are tried again soon.
      _watchSummaries[key] = (
        at: e.status == 404 ? DateTime.now() : DateTime.now().subtract(_watchSummaryTtl - _watchSummaryRetry),
        summary: null,
      );
      debugPrint('[Watchlist] summary: ${e.status}');
      return null;
    } catch (e) {
      _watchSummaries[key] = (at: DateTime.now().subtract(_watchSummaryTtl - _watchSummaryRetry), summary: null);
      debugPrint('[Watchlist] summary: $e');
      return null;
    }
  }

  /// Called with the raw `/libraries` answer before it is mapped.
  void _watchKeepLibraryRoots(List<dynamic> raw) {
    for (final lib in raw.whereType<Map>()) {
      _watchLibraryRoots['$_cleanBaseUrl|${lib['id']}'] = [
        for (final f in (lib['folders'] as List<dynamic>? ?? const []).whereType<Map>())
          if (f['path'] is String && (f['path'] as String).isNotEmpty) f['path'] as String,
      ];
    }
  }

  Future<Map<String, dynamic>?> _watchlistLibrary() async {
    final summary = await _watchSummary();
    if (summary == null) return null;
    return {
      'id': ApiService.watchlistLibraryId,
      'name': _libraryName,
      'displayOrder': 1 << 19,
      'icon': 'database',
      'mediaType': 'book',
      'provider': 'audible',
      'folders': const [],
      'settings': {'coverAspectRatio': 0},
      'watchlist': true,
      'watchlistNeedsYou': summary['watchlistNeedsYou'] ?? 0,
    };
  }

  static Map<String, dynamic> _emptyFilterData() => {
        'authors': const [], 'series': const [], 'genres': const [], 'tags': const [],
        'narrators': const [], 'languages': const [], 'publishers': const [], 'publishedDecades': const [],
      };

  /// One work as an ABS book item, with the release of each format it
  /// covers. It has no tracks and no ebook, so nothing tries to play, read or
  /// download it. Without [remember] it stays out of [_watchItems], which
  /// the book sheet reads.
  Map<String, dynamic> _watchItem({
    bool remember = true,
    required Map<String, dynamic> work,
    required List<String> formats,
    required String monitorAuthorId,
    required String authorName,
    Map<String, Map<String, dynamic>> releases = const {},
    Object? authorModes,
    Object? authorLastRefreshedAt,
    Object? isOwner,
  }) {
    final workId = '${work['id']}';
    final id = '$_watchItemPrefix$workId';
    // The card sorts by the date it shows: the first release it came with.
    final ms = [for (final f in formats) _watchMs(releases[f]?['releaseDate'])].whereType<int>().firstOrNull ?? 0;
    final title = '${work['title'] ?? ''}';
    final seriesName = work['seriesName'] as String?;
    final seriesIndex = work['seriesIndex']?.toString();
    final coverUrl = work['coverUrl'] as String?;
    final year = work['releaseYear'];
    final item = <String, dynamic>{
      'id': id,
      'ino': id,
      'libraryId': ApiService.watchlistLibraryId,
      'folderId': '',
      'path': '',
      'relPath': '',
      'isFile': true,
      'mediaType': 'book',
      'addedAt': ms,
      'updatedAt': ms,
      'isMissing': false,
      'isInvalid': false,
      'size': 0,
      'numFiles': 0,
      'media': {
        'id': id,
        'libraryItemId': id,
        // No `coverAspectRatio`: it switches shelves to per-book shapes, and
        // the Watchlist follows its library's cover setting like any other.
        'coverPath': coverUrl != null ? '/watchlist/cover' : null,
        'metadata': {
          'title': title,
          'titleIgnorePrefix': title,
          'subtitle': work['subtitle'],
          'authorName': authorName,
          'authorNameLF': authorName,
          'narratorName': '',
          'seriesName': seriesName == null ? '' : (seriesIndex == null ? seriesName : '$seriesName #$seriesIndex'),
          'description': work['description'],
          'publishedYear': year == null ? null : '$year',
          'series': seriesName == null
              ? const []
              : [
                  {'id': _watchSeriesId(monitorAuthorId, seriesName), 'name': seriesName, 'sequence': seriesIndex},
                ],
          'genres': const [],
          'narrators': const [],
          'authors': [
            {'id': '$_watchAuthorPrefix$monitorAuthorId', 'name': authorName},
          ],
          'explicit': false,
          'abridged': false,
        },
        'tags': const [],
        'audioFiles': const [],
        'chapters': const [],
        'duration': 0,
        'size': 0,
        'tracks': const [],
        'ebookFile': null,
        'numTracks': 0,
        'numAudioFiles': 0,
        'numChapters': 0,
      },
      'libraryFiles': const [],
      'watchlist': {
        'workId': workId,
        'formats': formats,
        'releases': releases,
        'monitorAuthorId': monitorAuthorId,
        'authorModes': authorModes,
        'authorLastRefreshedAt': authorLastRefreshedAt,
        'isOwner': isOwner,
        'work': work,
      },
    };
    _watchStampProgress(work, releases);
    if (remember) _watchRemember(_watchItems, id, item, _watchItemsMax);
    if (coverUrl != null) _watchRemember(_watchCovers, id, coverUrl, _watchCoversMax);
    return item;
  }

  /// Writes `requestProgress` onto [work] for each format whose request is
  /// downloading and has a recent percent in [_watchProgress].
  void _watchStampProgress(Map<String, dynamic> work, Map releases) {
    final known = _watchProgress[_cleanBaseUrl];
    final progress = <String, int>{};
    for (final f in _watchFormats) {
      if (known == null) break;
      final release = releases[f];
      final requestId = ((work['requestIds'] as Map?)?[f] as num?)?.toInt() ??
          (release is Map ? (release['requestId'] as num?)?.toInt() : null);
      final status = (work['requestStatuses'] as Map?)?[f] ?? (release is Map ? release['status'] : null);
      final hit = requestId == null ? null : known[requestId];
      if (status == 'downloading' && hit != null && DateTime.now().difference(hit.at) < _watchProgressTtl) {
        progress[f] = hit.percent;
      }
    }
    // A search hit's work can be a const empty map, which has nothing to clear.
    if (progress.isEmpty) {
      if (work.containsKey('requestProgress')) work.remove('requestProgress');
    } else {
      work['requestProgress'] = progress;
    }
  }

  void _watchRestamp(Map<String, dynamic> item) {
    final w = item['watchlist'];
    if (w is! Map) return;
    final work = w['work'];
    if (work is Map<String, dynamic>) _watchStampProgress(work, (w['releases'] as Map?) ?? const {});
  }

  /// A cached item by id: the item cache, else the last full release merge.
  Map<String, dynamic>? _watchItemFor(String itemId) {
    final key = _watchItemKey(itemId);
    final item = _watchItems[key] ?? _watchLastMerge[_cleanBaseUrl]?[key];
    if (item != null) _watchRestamp(item);
    return item;
  }

  static String _watchFormat(Object? f) => f == 'audiobook' ? 'audiobook' : 'ebook';

  /// Release items (one per format) folded into one item per work, in the
  /// order each work first appears.
  List<Map<String, dynamic>> _watchMergeReleases(Iterable<Map<String, dynamic>> raw, {bool remember = true}) {
    final byWork = <String, List<Map<String, dynamic>>>{};
    for (final r in raw) {
      byWork.putIfAbsent('${r['workId'] ?? (r['work'] as Map?)?['id']}', () => []).add(r);
    }
    return [
      for (final group in byWork.values) _watchReleaseItem(group, remember: remember),
    ];
  }

  Map<String, dynamic> _watchReleaseItem(List<Map<String, dynamic>> group, {bool remember = true}) {
    final first = group.first;
    // The newest copy of the work wins: every release carries the whole work.
    final work = (group.last['work'] as Map?)?.cast<String, dynamic>() ??
        {'id': first['workId'], 'title': first['title'], 'coverUrl': first['coverUrl']};
    final releases = <String, Map<String, dynamic>>{
      for (final r in group)
        _watchFormat(r['format']): {
          'status': r['status'],
          'releaseDate': r['releaseDate'],
          'requestId': r['requestId'],
        },
    };
    return _watchItem(
      remember: remember,
      work: work,
      formats: [for (final f in _watchFormats) if (releases.containsKey(f)) f],
      releases: releases,
      monitorAuthorId: '${first['monitorAuthorId'] ?? ''}',
      authorName: '${first['authorName'] ?? ''}',
      authorModes: first['authorModes'],
      authorLastRefreshedAt: first['authorLastRefreshedAt'],
      isOwner: first['isOwner'],
    );
  }

  /// A search hit has no release of its own: it stands for the formats the
  /// work is watched for, or both when neither is.
  Map<String, dynamic> _watchSearchItem(Map<String, dynamic> hit) {
    final work = (hit['work'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final modes = hit['authorModes'] as Map?;
    final monitor = work['monitorFormats'] as Map?;
    bool watched(String f) => modes?[f] != 'off' && monitor?[f] != false;
    final formats = _watchFormats.where(watched).toList();
    return _watchItem(
      work: work,
      formats: formats.isEmpty ? _watchFormats : formats,
      monitorAuthorId: '${hit['monitorAuthorId'] ?? ''}',
      authorName: '${hit['authorName'] ?? ''}',
      authorModes: modes,
      authorLastRefreshedAt: hit['authorLastRefreshedAt'],
      isOwner: hit['isOwner'],
    );
  }

  Future<({List<Map<String, dynamic>> raw, int total})> _watchReleasesRaw({
    required int page,
    required int size,
    String sort = 'date',
    String order = 'desc',
    String? filter,
    String? status,
  }) async {
    final res = await _boGet('/monitored/releases', {
      'page': page,
      'size': size.clamp(1, 100),
      'sort': sort,
      'order': order,
      if (filter != null) 'filter': filter,
      if (status != null) 'status': status,
    }) as Map<String, dynamic>;
    final raw = (res['items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    return (raw: raw, total: (res['total'] as num?)?.toInt() ?? raw.length);
  }

  /// The whole release window merged per work for [when], fetched 100 at a
  /// time up to [_watchMergedMax] release items and kept for a minute. One
  /// fetch fills both views: the format releases are split on their date,
  /// then each side is merged per work, so a work with one format out and
  /// one to come is a card in each, covering only that side's formats.
  Future<List<Map<String, dynamic>>> _watchMergedReleases(
      String sort, String order, String? status, WatchlistWhen when) async {
    final base = '$_cleanBaseUrl|$sort|$order|${status ?? ''}';
    final hit = _watchMerged['$base|${when.name}'];
    if (hit != null && DateTime.now().difference(hit.at) < _watchMergedTtl) return hit.items;
    var running = _watchMergedInFlight[base];
    if (running == null) {
      late final Future<Map<WatchlistWhen, List<Map<String, dynamic>>>> fetch;
      fetch = _watchFetchMerged(base, sort, order, status).whenComplete(() {
        // A write may have cleared the map and started another fetch meanwhile.
        if (identical(_watchMergedInFlight[base], fetch)) _watchMergedInFlight.remove(base);
      });
      _watchMergedInFlight[base] = running = fetch;
    }
    return (await running)[when]!;
  }

  Future<Map<WatchlistWhen, List<Map<String, dynamic>>>> _watchFetchMerged(
      String base, String sort, String order, String? status) async {
    final generation = _watchGeneration;
    final started = DateTime.now();
    final raw = <Map<String, dynamic>>[];
    var total = 0;
    for (var page = 0; raw.length < _watchMergedMax; page++) {
      final r = await _watchReleasesRaw(page: page, size: 100, sort: sort, order: order, status: status);
      raw.addAll(r.raw);
      total = r.total;
      if (r.raw.length < 100 || raw.length >= total) break;
    }
    // The sheet reads the whole work whichever view its card came from, so
    // the full merge is what gets remembered and the view cards are not. A
    // write since the fetch began makes it stale, so it is not kept.
    final current = generation == _watchGeneration;
    final works = _watchMergeReleases(raw, remember: current);
    final today = WatchlistInfo.todayUtc();
    final out = <Map<String, dynamic>>[];
    final upcoming = <Map<String, dynamic>>[];
    for (final r in raw) {
      (_watchReleaseStarted(r, today) ? out : upcoming).add(r);
    }
    final views = {
      WatchlistWhen.upcoming: _watchMergeReleases(upcoming, remember: false),
      WatchlistWhen.outNow: _watchMergeReleases(out, remember: false),
    };
    if (current) {
      final at = DateTime.now();
      _watchMerged.removeWhere((_, e) => at.difference(e.at) >= _watchMergedTtl);
      views.forEach((w, items) => _watchRemember(_watchMerged, '$base|${w.name}', (at: at, items: items), _watchMergedEntries));
      _watchLastMerge[_cleanBaseUrl] = {for (final w in works) w['id'] as String: w};
    }
    debugPrint('[Watchlist] releases: ${raw.length} items, ${works.length} works '
        '(${views[WatchlistWhen.upcoming]!.length} upcoming, ${views[WatchlistWhen.outNow]!.length} recent) in '
        '${DateTime.now().difference(started).inMilliseconds}ms');
    if (raw.length < total) {
      debugPrint('[Watchlist] releases: capped at ${raw.length} of $total items; later works are not shown');
    }
    return views;
  }

  Future<List<Map<String, dynamic>>> _watchShelves(Map<String, String> q) async {
    final wanted = (q['shelves'] ?? '').split(',').where((s) => s.isNotEmpty).toSet();
    final specs = [
      (id: 'watch-needs-you', label: 'Needs you', filter: null, status: 'needs_attention', order: 'desc'),
      (id: 'watch-available', label: 'Available now', filter: 'recent', status: 'missing,in_progress', order: 'desc'),
      (id: 'watch-soon', label: 'Coming soon', filter: 'soon', status: 'upcoming', order: 'asc'),
    ].where((s) => wanted.isEmpty || wanted.contains(s.id)).toList();
    final started = DateTime.now();
    final shelves = await Future.wait(specs.map((s) async {
      try {
        final page = await _watchReleasesRaw(page: 0, size: 20, order: s.order, filter: s.filter, status: s.status);
        if (page.raw.isEmpty) return null;
        final works = _watchMergeReleases(page.raw);
        return <String, dynamic>{
          'id': s.id,
          'label': s.label,
          'labelStringKey': s.label,
          'type': 'book',
          'entities': works,
          // The server counts formats; the folds seen here are taken off.
          'total': page.total - (page.raw.length - works.length),
        };
      } catch (e) {
        debugPrint('[Watchlist] shelf ${s.id} failed: $e');
        return null;
      }
    }));
    final out = shelves.whereType<Map<String, dynamic>>().toList();
    debugPrint('[Watchlist] shelves: ${out.length} of ${specs.length} in ${DateTime.now().difference(started).inMilliseconds}ms');
    return out;
  }

  Map<String, dynamic> _watchAuthor(Map<String, dynamic> a) {
    final id = '${a['id']}';
    final counts = (a['counts'] as Map?) ?? const {};
    final ebook = (counts['ebookOwned'] as num?)?.toInt() ?? 0;
    final audio = (counts['audioOwned'] as num?)?.toInt() ?? 0;
    final total = (counts['total'] as num?)?.toInt() ?? 0;
    final author = <String, dynamic>{
      'id': '$_watchAuthorPrefix$id',
      'name': '${a['authorName'] ?? ''}',
      'description': a['description'],
      'numBooks': total,
      'imagePath': a['portraitAuthorId'] != null ? '/monitored/portrait' : null,
      'libraryItems': const [],
      'series': const [],
      'watchlist': {
        'monitorAuthorId': id,
        // Works with any format owned is not in the list payload; the larger
        // per-format count is the closest it gets without a call per tile.
        'owned': math.max(ebook, audio),
        'ebookOwned': ebook,
        'audioOwned': audio,
        // The server's total already leaves hidden works out.
        'total': total,
        'nextReleaseAt': a['nextReleaseAt'],
        'fetchState': (a['fetch'] as Map?)?['state'],
        'formats': a['formats'],
        'paused': a['paused'] == true,
        'isOwner': a['isOwner'],
        'lastRefreshedAt': a['lastRefreshedAt'],
      },
    };
    _watchRemember(_watchAuthors, author['id'] as String, author, _watchAuthorsMax);
    return author;
  }

  Future<Map<String, dynamic>> _watchAuthorsPage(Map<String, String> q) async {
    final paged = q.containsKey('page');
    final page = int.tryParse(q['page'] ?? '') ?? 0;
    final limit = (int.tryParse(q['limit'] ?? '') ?? 100).clamp(1, 200);
    final sort = switch (q['sort']) {
      'numBooks' => 'books',
      'addedAt' => 'added',
      _ => 'name',
    };
    final order = q['desc'] == '1' ? 'desc' : 'asc';
    Future<({List<Map<String, dynamic>> authors, int total})> fetch(int p, int size) async {
      final res = await _boGet('/monitored/authors', {'page': p, 'size': size, 'sort': sort, 'order': order})
          as Map<String, dynamic>;
      final items = (res['items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>();
      return (authors: items.map(_watchAuthor).toList(), total: (res['total'] as num?)?.toInt() ?? 0);
    }

    if (paged) {
      final r = await fetch(page, limit);
      return {'results': r.authors, 'total': r.total, 'limit': limit, 'page': page};
    }
    // The unpaged shape is for pickers and the Authors tab; ten pages is more
    // authors than anyone follows.
    final all = <Map<String, dynamic>>[];
    for (var p = 0; p < 10; p++) {
      final r = await fetch(p, 200);
      all.addAll(r.authors);
      if (r.authors.length < 200 || all.length >= r.total) break;
    }
    return {'authors': all};
  }

  /// The formats an author-view card stands for: the ones watched or owned,
  /// else both.
  List<String> _watchWorkFormats(Map<String, dynamic> work, Map? modes) {
    final monitor = work['monitorFormats'] as Map?;
    final owned = (work['ownedFormats'] as List?) ?? const [];
    final formats = [
      for (final f in _watchFormats)
        if ((modes?[f] != 'off' && monitor?[f] != false) || owned.contains(f)) f,
    ];
    return formats.isEmpty ? _watchFormats : formats;
  }

  static double _watchSeriesNumber(Object? index) =>
      double.tryParse(RegExp(r'^[\d.]+').firstMatch('${index ?? ''}'.trim())?.group(0) ?? '') ?? double.maxFinite;

  static int _watchByIndexThenTitle(Map<String, dynamic> a, Map<String, dynamic> b) {
    final wa = (a['watchlist'] as Map)['work'] as Map;
    final wb = (b['watchlist'] as Map)['work'] as Map;
    final byIndex = _watchSeriesNumber(wa['seriesIndex']).compareTo(_watchSeriesNumber(wb['seriesIndex']));
    if (byIndex != 0) return byIndex;
    return '${wa['title'] ?? ''}'.toLowerCase().compareTo('${wb['title'] ?? ''}'.toLowerCase());
  }

  /// One followed author with every work on its default list, fetched once
  /// per minute at most: the author sheet and the series sheets opened from
  /// it share the answer. Null when the author is gone or not readable.
  /// [fresh] skips the kept answer but still joins a fetch already running.
  Future<({Map<String, dynamic> author, List<Map<String, dynamic>> items})?> _watchAuthorWithWorks(String monitorId,
      {bool fresh = false}) async {
    final key = '$_cleanBaseUrl|$monitorId';
    final hit = _watchAuthorWorks[key];
    if (!fresh && hit != null && DateTime.now().difference(hit.at) < _watchAuthorWorksTtl) {
      return (author: hit.author, items: hit.items);
    }
    final running = _watchAuthorWorksInFlight[key];
    if (running != null) return running;
    late final Future<({Map<String, dynamic> author, List<Map<String, dynamic>> items})?> fetch;
    fetch = _watchFetchAuthorWorks(monitorId, key).whenComplete(() {
      // A write may have cleared the map and started another fetch meanwhile.
      if (identical(_watchAuthorWorksInFlight[key], fetch)) _watchAuthorWorksInFlight.remove(key);
    });
    _watchAuthorWorksInFlight[key] = fetch;
    return fetch;
  }

  Future<({Map<String, dynamic> author, List<Map<String, dynamic>> items})?> _watchFetchAuthorWorks(
      String monitorId, String key) async {
    final generation = _watchGeneration;
    final started = DateTime.now();
    try {
      // The server's defaults: listed works only (hidden and in-review ones
      // stay out), every status.
      final res = await _boGet('/monitored/authors/${Uri.encodeComponent(monitorId)}') as Map<String, dynamic>;
      final a = res['author'];
      if (a is! Map<String, dynamic>) return null;
      final author = _watchAuthor(a);
      final formats = a['formats'] as Map?;
      final modes = {for (final f in _watchFormats) f: (formats?[f] as Map?)?['mode']};
      // A write since the fetch began makes these works stale.
      final current = generation == _watchGeneration;
      final items = [
        for (final w in (res['works'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
          _watchItem(
            remember: current,
            work: w,
            formats: _watchWorkFormats(w, modes),
            monitorAuthorId: monitorId,
            authorName: '${a['authorName'] ?? ''}',
            authorModes: modes,
            authorLastRefreshedAt: a['lastRefreshedAt'],
            isOwner: a['isOwner'],
          ),
      ];
      // Series first by name, each in reading order, then the rest by title.
      items.sort((x, y) {
        final sx = ((x['watchlist'] as Map)['work'] as Map)['seriesName'] as String?;
        final sy = ((y['watchlist'] as Map)['work'] as Map)['seriesName'] as String?;
        if (sx != sy) {
          if (sx == null) return 1;
          if (sy == null) return -1;
          return sx.toLowerCase().compareTo(sy.toLowerCase());
        }
        return _watchByIndexThenTitle(x, y);
      });
      if (current) {
        _watchRemember(_watchAuthorWorks, key, (at: DateTime.now(), author: author, items: items), _watchAuthorWorksMax);
      }
      debugPrint('[Watchlist] author $monitorId: ${items.length} works in ${DateTime.now().difference(started).inMilliseconds}ms');
      return (author: author, items: items);
    } on _BoHttpError catch (e) {
      if (e.status == 404 || e.status == 403) return null;
      rethrow;
    }
  }

  /// The ABS author shape the author sheet reads: its works as
  /// `libraryItems` and one `series` group per series, in reading order.
  Future<Map<String, dynamic>?> _watchAuthorDetail(String authorId) async {
    final monitorId = authorId.substring(_watchAuthorPrefix.length);
    final detail = await _watchAuthorWithWorks(monitorId, fresh: true);
    if (detail == null) return null;
    final groups = <String, Map<String, dynamic>>{};
    for (final item in detail.items) {
      final name = ((item['watchlist'] as Map)['work'] as Map)['seriesName'] as String?;
      if (name == null || name.trim().isEmpty) continue;
      final group = groups.putIfAbsent(name, () => {
            'id': _watchSeriesId(monitorId, name),
            'name': name,
            'items': <Map<String, dynamic>>[],
          });
      (group['items'] as List<Map<String, dynamic>>).add(item);
    }
    return {
      ...detail.author,
      'numBooks': detail.items.length,
      'libraryItems': detail.items,
      'series': groups.values.toList(),
    };
  }

  /// The works of one Watchlist series, in reading order, from its author's
  /// works.
  Future<List<Map<String, dynamic>>?> _watchSeriesWorks(String seriesId) async {
    final parsed = _watchParseSeriesId(seriesId);
    if (parsed == null) return null;
    final detail = await _watchAuthorWithWorks(parsed.monitorAuthorId);
    if (detail == null) return null;
    return [
      for (final item in detail.items)
        if (((item['watchlist'] as Map)['work'] as Map)['seriesName'] == parsed.name) item,
    ]..sort(_watchByIndexThenTitle);
  }

  /// `series.<base64 id>` from an items query, when it names a Watchlist series.
  static String? _watchSeriesFilter(String? filter) {
    if (filter == null || !filter.startsWith('series.')) return null;
    try {
      // A `+` in the unencoded query value arrives as a space.
      final raw = Uri.decodeComponent(filter.substring(7)).replaceAll(' ', '+');
      final id = utf8.decode(base64.decode(base64.normalize(raw)));
      return id.startsWith(_watchSeriesPrefix) ? id : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _watchSeriesItemsPage(String seriesId, int page, int limit) async {
    final works = await _watchSeriesWorks(seriesId) ?? const [];
    final from = math.min(page * limit, works.length);
    return {
      'results': works.sublist(from, math.min(from + limit, works.length)),
      'total': works.length,
      'limit': limit,
      'page': page,
    };
  }

  Future<Map<String, dynamic>?> _watchSeriesMeta(String seriesId) async {
    final parsed = _watchParseSeriesId(seriesId);
    if (parsed == null) return null;
    final works = await _watchSeriesWorks(seriesId);
    if (works == null) return null;
    final author = _watchAuthors['$_watchAuthorPrefix${parsed.monitorAuthorId}'];
    return {
      'id': seriesId,
      'name': parsed.name,
      'nameIgnorePrefix': parsed.name,
      'numBooks': works.length,
      'libraryId': ApiService.watchlistLibraryId,
      'authors': [
        if (author != null) {'id': author['id'], 'name': author['name']},
      ],
    };
  }

  Future<Map<String, dynamic>> _watchSearch(Map<String, String> q) async {
    final text = (q['q'] ?? '').trim();
    var found = const <Map<String, dynamic>>[];
    var authors = const <Map<String, dynamic>>[];
    if (text.length >= 3) {
      final started = DateTime.now();
      try {
        // The library search shows only title matches as books, so works found
        // by their author's name need the author as a row of its own. Losing
        // those rows is no reason to lose the works.
        final peopleCall = _boGet('/monitored/authors', {'q': text, 'size': 10}).then<Object?>((r) => r,
            onError: (Object e) {
          debugPrint('[Watchlist] search authors failed after '
              '${DateTime.now().difference(started).inMilliseconds}ms: $e');
          return null;
        });
        final works = await _boGet('/monitored/works', {
          'q': text,
          'size': (int.tryParse(q['limit'] ?? '') ?? 25).clamp(1, 100),
        });
        final people = await peopleCall;
        found = [
          for (final hit in ((works as Map)['items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
            _watchSearchItem(hit),
        ];
        authors = [
          for (final a in ((people as Map?)?['items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
            _watchAuthor(a),
        ];
        debugPrint('[Watchlist] search: ${found.length} works, ${authors.length} authors in '
            '${DateTime.now().difference(started).inMilliseconds}ms');
      } catch (e) {
        debugPrint('[Watchlist] search failed after ${DateTime.now().difference(started).inMilliseconds}ms: $e');
        rethrow;
      }
    }
    return {
      'book': [
        for (final item in found)
          {
            'libraryItem': item,
            'matchKey': 'title',
            'matchText': ((item['media'] as Map)['metadata'] as Map)['title'],
          },
      ],
      'podcast': const [],
      'series': const [],
      'authors': authors,
      'narrators': const [],
      'tags': const [],
      'genres': const [],
    };
  }

  Future<http.Response?> _routeWatchlistLibrary(int n, String sub, Map<String, String> q, [String at4 = '']) async {
    final lib = await _watchlistLibrary();
    if (lib == null) return BookOrbitApiService._status(404, 'Watchlist is not available');
    if (n == 3) {
      return BookOrbitApiService._json({
        ...lib,
        if ((q['include'] ?? '').contains('filterdata')) 'filterdata': _emptyFilterData(),
      });
    }
    final page = int.tryParse(q['page'] ?? '') ?? 0;
    final limit = (int.tryParse(q['limit'] ?? '') ?? 20).clamp(1, 100);
    switch (sub) {
      case 'personalized':
        return BookOrbitApiService._json(await _cached(
            'personalized:${ApiService.watchlistLibraryId}:${q['shelves'] ?? ''}:${q['limit'] ?? ''}',
            const Duration(seconds: 20),
            () => _watchShelves(q)));
      case 'items':
        final seriesId = _watchSeriesFilter(q['filter']);
        if (seriesId != null) return BookOrbitApiService._json(await _watchSeriesItemsPage(seriesId, page, limit));
        final sort = switch (q['sort']) {
          'media.metadata.title' || 'media.metadata.titleIgnorePrefix' => 'title',
          'media.metadata.authorName' || 'media.metadata.authorNameLF' => 'author',
          _ => 'date',
        };
        final order = q['sort'] == null || q['desc'] == '1' ? 'desc' : 'asc';
        final works =
            await _watchMergedReleases(sort, order, WatchlistReleaseFilter.query, WatchlistReleaseFilter.when);
        final from = math.min(page * limit, works.length);
        final slice = works.sublist(from, math.min(from + limit, works.length));
        slice.forEach(_watchRestamp);
        return BookOrbitApiService._json({
          'results': slice,
          'total': works.length,
          'limit': limit,
          'page': page,
          'sortBy': q['sort'],
          'sortDesc': order == 'desc',
          'filterBy': q['filter'],
          'mediaType': 'book',
          'minified': q['minified'] != '0',
          'collapseseries': false,
          'include': '',
        });
      case 'authors':
        return BookOrbitApiService._json(await _watchAuthorsPage(q));
      case 'search':
        return BookOrbitApiService._json(await _watchSearch(q));
      case 'filterdata':
        return BookOrbitApiService._json(_emptyFilterData());
      case 'series':
        if (n == 5) {
          final meta = await _watchSeriesMeta(at4);
          return meta == null ? BookOrbitApiService._status(404, 'Series not found') : BookOrbitApiService._json(meta);
        }
        return BookOrbitApiService._json({'results': const [], 'total': 0, 'limit': limit, 'page': page});
      case 'collections':
      case 'playlists':
        return BookOrbitApiService._json({'results': const [], 'total': 0, 'limit': limit, 'page': page});
      case 'narrators':
        return BookOrbitApiService._json({'narrators': const []});
      case 'stats':
        final summary = await _watchSummary();
        return BookOrbitApiService._json({
          'totalItems': summary?['releases'] ?? 0,
          'totalSize': 0,
          'totalDuration': 0,
          'numAudioFiles': 0,
          'numAudioTracks': 0,
          'totalAuthors': summary?['authors'] ?? 0,
          'totalGenres': 0,
        });
    }
    return null;
  }

  /// A watchlist item reads back from what the lists handed out; it has
  /// nothing to play, edit or download.
  Future<http.Response?> _routeWatchlistItem(String method, String itemId, int n) async {
    if (n == 3 && method == 'GET') {
      final item = _watchItemFor(itemId);
      return item == null ? BookOrbitApiService._status(404, 'Watchlist item not found') : BookOrbitApiService._json(item);
    }
    return BookOrbitApiService._status(409, 'This book is only on the watchlist');
  }

  String _watchCoverUrl(String itemId) {
    final cover = _watchCovers[_watchItemKey(itemId)] ?? '';
    return BookOrbitMediaProxy.instance.urlFor('/api/v1/monitored/cover?url=${Uri.encodeQueryComponent(cover)}');
  }

  String _watchPortraitUrl(String authorId) => BookOrbitMediaProxy.instance
      .urlFor('/api/v1/monitored/authors/${Uri.encodeComponent(authorId.substring(_watchAuthorPrefix.length))}/portrait');

  /// Puts a work the server just answered with into its cached item, so a
  /// reopened sheet shows the new state.
  void _watchPatchWork(Map<String, dynamic> work) {
    final id = '$_watchItemPrefix${work['id']}';
    final w = _watchItems[id]?['watchlist'];
    if (w is! Map) return;
    w['work'] = work;
    final cover = work['coverUrl'];
    if (cover is String) _watchCovers[id] = cover;
    final releases = w['releases'];
    if (releases is! Map) return;
    for (final format in _watchFormats) {
      final release = releases[format];
      final requestId = (work['requestIds'] as Map?)?[format];
      if (release is Map && requestId != null) release['requestId'] = requestId;
    }
  }

  /// A request's status moved: write it onto the cached work of every item
  /// that holds the request. The percent lives in [_watchProgress].
  bool _watchPatchRequestStatus(int requestId, String status) {
    var changed = false;
    for (final item in _watchItems.values) {
      final w = item['watchlist'];
      if (w is! Map) continue;
      final work = w['work'];
      if (work is! Map) continue;
      for (final format in _watchFormats) {
        final release = (w['releases'] as Map?)?[format];
        final ids = work['requestIds'] as Map?;
        final held = ids?[format] == requestId || (release is Map && release['requestId'] == requestId);
        if (!held) continue;
        final statuses = (work['requestStatuses'] as Map?) ?? {};
        if (statuses[format] == status) continue;
        work['requestStatuses'] = {...statuses, format: status};
        work['requestIds'] = {...?ids, format: requestId};
        changed = true;
      }
    }
    return changed;
  }

  /// Re-reads the work a library book matched, so a format that just landed
  /// reads as owned. False when BookOrbit has not matched it yet.
  Future<bool> _watchRefreshByBook(int bookId) async {
    try {
      final res = await _boGet('/monitored/works/by-book/$bookId') as Map<String, dynamic>;
      final work = res['work'];
      if (work is! Map<String, dynamic>) return false;
      _watchPatchWork(work);
      return true;
    } catch (e) {
      debugPrint('[Watchlist] work for book $bookId: $e');
      return false;
    }
  }

  void _watchAfterChange() {
    _watchMerged.clear();
    _watchMergedInFlight.clear();
    _watchAuthorWorks.clear();
    _watchAuthorWorksInFlight.clear();
    _watchGeneration++;
    BookOrbitApiService._recent.removeWhere((key, _) => key.startsWith('personalized:${ApiService.watchlistLibraryId}:'));
    WatchlistChanges.tick.value++;
  }

  /// Keeps [percent] for [requestId] while it downloads, and drops it, and
  /// any expired one, otherwise.
  void _watchKeepProgress(int requestId, String status, int? percent) {
    final known = _watchProgress.putIfAbsent(_cleanBaseUrl, () => {});
    final now = DateTime.now();
    known.removeWhere((_, p) => now.difference(p.at) >= _watchProgressTtl);
    if (status == 'downloading' && percent != null) {
      known[requestId] = (percent: percent, at: now);
    } else {
      known.remove(requestId);
    }
  }

  static String _watchError(Object e) {
    if (e is _BoHttpError) {
      if (e.status == 403) return 'You cannot request books on this server';
      return e.serverMessage ?? 'BookOrbit said no (${e.status})';
    }
    return 'Could not reach BookOrbit';
  }

  String _watchWorkPath(String workId) => '/monitored/works/${Uri.encodeComponent(workId)}';
}

/// What the book sheet and Settings call for watchlist items.
extension BookOrbitWatchlistActions on BookOrbitApiService {
  Future<bool> watchlistAvailable() async => await _watchSummary() != null;

  /// Null on success, else a short reason to show.
  Future<String?> watchlistRequest(String workId, String format) async {
    final started = DateTime.now();
    try {
      final work = await _boPost('${_watchWorkPath(workId)}/request', {'format': format}) as Map<String, dynamic>?;
      if (work != null) _watchPatchWork(work);
      _watchAfterChange();
      debugPrint('[Watchlist] request $workId $format ok in ${DateTime.now().difference(started).inMilliseconds}ms');
      return null;
    } catch (e) {
      debugPrint('[Watchlist] request $workId $format failed: $e');
      return _ForkBookOrbitWatchlist._watchError(e);
    }
  }

  /// Asks every indexer for [format] of the work, without writing a request:
  /// BookOrbit's `ReleaseSearchResult` as received, already ranked. Every
  /// tracker is asked in turn, which can take most of a minute.
  Future<({Map<String, dynamic>? result, String? error})> watchlistSearchReleases(String workId, String format) async {
    final started = DateTime.now();
    try {
      final res = await _boPost('${_watchWorkPath(workId)}/releases/search', {'format': format},
          const Duration(seconds: 120));
      if (res is! Map<String, dynamic>) return (result: null, error: 'BookOrbit sent nothing back');
      debugPrint('[Watchlist] release search $workId $format: ${(res['releases'] as List?)?.length ?? 0} '
          'in ${DateTime.now().difference(started).inMilliseconds}ms');
      return (result: res, error: null);
    } catch (e) {
      debugPrint('[Watchlist] release search $workId $format failed after '
          '${DateTime.now().difference(started).inMilliseconds}ms: $e');
      return (result: null, error: _ForkBookOrbitWatchlist._watchError(e));
    }
  }

  /// Sends one release from [watchlistSearchReleases] to the download client.
  /// BookOrbit makes or reuses the work's request for [format] and answers
  /// with it; its id and status land on the cached work.
  Future<({int? requestId, String? error})> watchlistGrabRelease(
      String workId, String format, int indexerId, String releaseGuid) async {
    final started = DateTime.now();
    try {
      final res = await _boPost('${_watchWorkPath(workId)}/releases/grab', {
        'format': format,
        'indexerId': indexerId,
        'releaseGuid': releaseGuid,
      }, const Duration(minutes: 2));
      final requestId = res is Map ? (res['id'] as num?)?.toInt() : null;
      final item = _watchItems['$_watchItemPrefix$workId']?['watchlist'];
      final work = item is Map ? item['work'] : null;
      if (requestId != null && work is Map) {
        work['requestIds'] = {...?(work['requestIds'] as Map?), format: requestId};
        work['requestStatuses'] = {...?(work['requestStatuses'] as Map?), format: '${(res as Map)['status'] ?? 'grabbed'}'};
        final release = (item['releases'] as Map?)?[format];
        if (release is Map) release['requestId'] = requestId;
      }
      _watchAfterChange();
      debugPrint('[Watchlist] grab $workId $format request=$requestId in ${DateTime.now().difference(started).inMilliseconds}ms');
      return (requestId: requestId, error: null);
    } catch (e) {
      debugPrint('[Watchlist] grab $workId $format failed: $e');
      return (requestId: null, error: _ForkBookOrbitWatchlist._watchError(e));
    }
  }

  /// One book request as the sheet follows it: `{status, message,
  /// progressPercent, refreshed}`. `message` is the server's reason for a
  /// failure; `refreshed` says the work was re-read after the request landed.
  /// A changed status is written onto the cached work and the shelves are
  /// dropped; the percent is kept for the cards. A request that just became
  /// available re-reads its work so the library match shows. Null when the
  /// request could not be read.
  Future<Map<String, dynamic>?> watchlistRequestStatus(int requestId) async {
    try {
      final res = await _boGet('/book-requests/$requestId') as Map<String, dynamic>;
      final status = '${res['status'] ?? ''}';
      final download = res['download'] as Map?;
      final reason = res['statusReason'] ?? download?['errorMessage'] ?? res['failureCode'];
      final percent = (download?['progressPercent'] as num?)?.round();
      _watchKeepProgress(requestId, status, percent);
      // A percent alone is not a change: the grid is not reloaded for it.
      final changed = _watchPatchRequestStatus(requestId, status);
      final bookId = (res['matchedBookId'] as num?)?.toInt();
      final refreshed = status == 'available' && bookId != null && await _watchRefreshByBook(bookId);
      if (changed || refreshed) _watchAfterChange();
      return {
        'status': status,
        'message': reason == null || '$reason'.trim().isEmpty ? null : '$reason'.trim(),
        'progressPercent': percent,
        'refreshed': refreshed,
      };
    } catch (e) {
      debugPrint('[Watchlist] request status $requestId: $e');
      return null;
    }
  }

  /// [format] is ebook, audiobook or both; the server takes 100 works a call.
  Future<String?> watchlistBulkRequest(List<String> workIds, String format) async {
    if (workIds.isEmpty) return null;
    var failed = 0;
    String? firstMessage;
    try {
      for (var i = 0; i < workIds.length; i += 100) {
        final chunk = workIds.sublist(i, math.min(i + 100, workIds.length));
        final res = await _boPost('/monitored/works/bulk-request', {'workIds': chunk, 'format': format})
            as Map<String, dynamic>?;
        for (final w in (res?['works'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>()) {
          _watchPatchWork(w);
        }
        for (final r in (res?['results'] as List<dynamic>? ?? const []).whereType<Map>()) {
          if (r['outcome'] == 'failed') {
            failed++;
            firstMessage ??= r['message'] as String?;
          }
        }
      }
      _watchAfterChange();
      debugPrint('[Watchlist] bulk request ${workIds.length} works $format: $failed failed');
      if (failed == 0) return null;
      return '$failed could not be requested${firstMessage == null ? '' : ': $firstMessage'}';
    } catch (e) {
      debugPrint('[Watchlist] bulk request $format failed: $e');
      _watchAfterChange();
      return _ForkBookOrbitWatchlist._watchError(e);
    }
  }

  Future<String?> _watchPatch(String workId, Map<String, dynamic> patch) async {
    try {
      final work = await _boPatch(_watchWorkPath(workId), patch) as Map<String, dynamic>?;
      if (work != null) _watchPatchWork(work);
      _watchAfterChange();
      return null;
    } catch (e) {
      debugPrint('[Watchlist] update $workId ${patch.keys.join(',')} failed: $e');
      return _ForkBookOrbitWatchlist._watchError(e);
    }
  }

  Future<String?> watchlistSetWatching(String workId, String format, bool watching) =>
      _watchPatch(workId, {format == 'audiobook' ? 'monitorAudiobook' : 'monitorEbook': watching});

  /// Null follows the author's mode again.
  Future<String?> watchlistSetAutoDownload(String workId, String format, bool? value) =>
      _watchPatch(workId, {format == 'audiobook' ? 'autoDownloadAudiobook' : 'autoDownloadEbook': value});

  /// Watching for many works at once, in calls of 100. [formats] are the
  /// formats switched; null on success, else a short reason.
  Future<String?> watchlistBulkSetWatching(List<String> workIds, List<String> formats, bool watching) async {
    if (workIds.isEmpty || formats.isEmpty) return null;
    final patch = {
      if (formats.contains('ebook')) 'monitorEbook': watching,
      if (formats.contains('audiobook')) 'monitorAudiobook': watching,
    };
    var failed = 0;
    try {
      for (var i = 0; i < workIds.length; i += 100) {
        final chunk = workIds.sublist(i, math.min(i + 100, workIds.length));
        final res = await _boPatch('/monitored/works/bulk', {'workIds': chunk, 'patch': patch}) as Map<String, dynamic>?;
        for (final w in (res?['works'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>()) {
          _watchPatchWork(w);
        }
        failed += (res?['failed'] as List<dynamic>? ?? const []).length;
      }
      _watchAfterChange();
      debugPrint('[Watchlist] bulk watching=${watching ? 1 : 0} ${workIds.length} works ${formats.join(',')}: $failed failed');
      return failed == 0 ? null : '$failed could not be changed';
    } catch (e) {
      debugPrint('[Watchlist] bulk watching failed: $e');
      _watchAfterChange();
      return _ForkBookOrbitWatchlist._watchError(e);
    }
  }

  /// Auto-download for many works. The bulk patch does not take it, so each
  /// work is patched on its own, a few at a time; callers pass a series'
  /// worth, not a library's.
  Future<String?> watchlistSetAutoDownloadMany(List<String> workIds, List<String> formats, bool? value) async {
    if (workIds.isEmpty || formats.isEmpty) return null;
    final patch = {
      if (formats.contains('ebook')) 'autoDownloadEbook': value,
      if (formats.contains('audiobook')) 'autoDownloadAudiobook': value,
    };
    final started = DateTime.now();
    final errors = await BookOrbitApiService._pool<String?>([
      for (final id in workIds)
        () async {
          try {
            final work = await _boPatch(_watchWorkPath(id), patch) as Map<String, dynamic>?;
            if (work != null) _watchPatchWork(work);
            return null;
          } catch (e) {
            return _ForkBookOrbitWatchlist._watchError(e);
          }
        },
    ], width: 4);
    _watchAfterChange();
    final failed = errors.whereType<String>().toList();
    debugPrint('[Watchlist] auto-download=$value ${workIds.length} works ${formats.join(',')}: ${failed.length} failed '
        'in ${DateTime.now().difference(started).inMilliseconds}ms');
    if (failed.isEmpty) return null;
    return failed.length == workIds.length ? failed.first : '${failed.length} could not be changed: ${failed.first}';
  }

  /// Authors BookOrbit can follow for [query], from its library and
  /// Hardcover: `{name, providerIds, localAuthorId, bookCount, imageUrl,
  /// alreadyMonitoredId}` each.
  Future<({List<Map<String, dynamic>> results, String? error})> watchlistSearchAuthors(String query) async {
    try {
      final res = await _boGet('/monitored/search', {'q': query.trim()}, const Duration(seconds: 30));
      return (
        results: (res as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList(),
        error: null,
      );
    } catch (e) {
      debugPrint('[Watchlist] author search failed: $e');
      return (results: const <Map<String, dynamic>>[], error: _ForkBookOrbitWatchlist._watchError(e));
    }
  }

  /// A provider image (an author search result's) through the server's
  /// cover cache, like every other Watchlist image.
  String watchlistImageUrl(String url) =>
      BookOrbitMediaProxy.instance.urlFor('/api/v1/monitored/cover?url=${Uri.encodeQueryComponent(url)}');

  /// The server's book libraries, for the follow form's pickers.
  Future<List<({int id, String name})>> watchlistBookLibraries() async {
    try {
      return [
        for (final l in await _libraries())
          if (int.tryParse('${l['id']}') != null) (id: int.parse('${l['id']}'), name: '${l['name'] ?? ''}'),
      ];
    } catch (e) {
      debugPrint('[Watchlist] libraries: $e');
      return const [];
    }
  }

  /// Where requests of each format land when nobody picks: the instance's
  /// default destinations, as library and folder ids (null when there is none).
  Future<Map<String, ({int? libraryId, int? folderId})>> watchlistDefaultLibraries() async {
    try {
      final res = await _boGet('/book-requests/default-destinations') as Map<String, dynamic>;
      return {
        for (final f in _watchFormats)
          f: (
            libraryId: ((res[f] as Map?)?['libraryId'] as num?)?.toInt(),
            folderId: ((res[f] as Map?)?['folderId'] as num?)?.toInt(),
          ),
      };
    } catch (e) {
      debugPrint('[Watchlist] default destinations: $e');
      return const {};
    }
  }

  /// [folderIds] carries a folder per format; the server sets a missing
  /// one to null, so a folder picked on the web must be sent back as it was.
  static Map<String, dynamic> _watchFormatsBody(Map<String, ({String mode, int? libraryId})> formats,
          [Map<String, int?> folderIds = const {}]) =>
      {
        for (final e in formats.entries)
          e.key: {
            'mode': e.value.mode,
            'libraryId': e.value.libraryId,
            'folderId': e.value.libraryId == null ? null : folderIds[e.key],
          },
      };

  void _watchAuthorsChanged() {
    // The picker's needs-you count follows the author's modes and pause.
    _watchSummaries.remove(_cleanBaseUrl);
    _watchAfterChange();
  }

  /// Writes an author's new modes onto every cached item of that author, so
  /// a sheet opened from a grid that was not reloaded reads them. Formats
  /// not in [modes] keep theirs.
  void _watchPatchAuthorModes(String monitorId, Map<String, Object?> modes) {
    for (final item in _watchItems.values) {
      final w = item['watchlist'];
      if (w is! Map || w['monitorAuthorId'] != monitorId) continue;
      w['authorModes'] = {...?(w['authorModes'] as Map?), ...modes};
    }
  }

  /// Follows [result] (an entry of [watchlistSearchAuthors]). Null on
  /// success, else a short reason.
  Future<String?> watchlistFollowAuthor(Map<String, dynamic> result, Map<String, ({String mode, int? libraryId})> formats,
      {Map<String, int?> folderIds = const {}}) async {
    final started = DateTime.now();
    try {
      final localId = (result['localAuthorId'] as num?)?.toInt();
      final res = await _boPost('/monitored/authors', {
        'authorName': '${result['name'] ?? ''}',
        if (localId != null) 'localAuthorId': localId,
        'providerIds': result['providerIds'] is Map ? result['providerIds'] : const {},
        'formats': _watchFormatsBody(formats, folderIds),
      });
      if (res is Map<String, dynamic>) _watchAuthor(res);
      _watchAuthorsChanged();
      debugPrint('[Watchlist] follow ok in ${DateTime.now().difference(started).inMilliseconds}ms');
      return null;
    } catch (e) {
      debugPrint('[Watchlist] follow failed: $e');
      return _ForkBookOrbitWatchlist._watchError(e);
    }
  }

  /// The Watchlist part of a followed author (`watch-author-<id>`): formats,
  /// paused, counts. From the last author list, else read from the server.
  Future<Map<String, dynamic>?> watchlistAuthorSettings(String authorId) async {
    final cached = (_watchAuthors[authorId]?['watchlist'] as Map?)?.cast<String, dynamic>();
    if (cached != null) return cached;
    try {
      final detail = await _watchAuthorWithWorks(authorId.substring(_watchAuthorPrefix.length));
      return (detail?.author['watchlist'] as Map?)?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('[Watchlist] author settings $authorId: $e');
      return null;
    }
  }

  String _watchAuthorPath(String authorId) =>
      '/monitored/authors/${Uri.encodeComponent(authorId.substring(_watchAuthorPrefix.length))}';

  /// Changes an author's formats and/or pause. Null on success.
  Future<String?> watchlistUpdateAuthor(String authorId,
      {Map<String, ({String mode, int? libraryId})>? formats, Map<String, int?> folderIds = const {}, bool? paused}) async {
    try {
      final res = await _boPatch(_watchAuthorPath(authorId), {
        if (formats != null) 'formats': _watchFormatsBody(formats, folderIds),
        if (paused != null) 'paused': paused,
      });
      if (res is Map<String, dynamic>) _watchAuthor(res);
      if (formats != null) {
        final saved = res is Map ? res['formats'] as Map? : null;
        String? savedMode(String f) => switch ((saved?[f] as Map?)?['mode']) { final String m => m, _ => null };
        // The server's answer wins over what was sent, for each format it carries.
        _watchPatchAuthorModes(authorId.substring(_watchAuthorPrefix.length), {
          for (final e in formats.entries) e.key: e.value.mode,
          for (final f in _watchFormats)
            if (savedMode(f) != null) f: savedMode(f),
        });
      }
      _watchAuthorsChanged();
      return null;
    } catch (e) {
      debugPrint('[Watchlist] update author $authorId failed: $e');
      return _ForkBookOrbitWatchlist._watchError(e);
    }
  }

  /// Asks BookOrbit to fetch the author's catalog again. Null when queued,
  /// else the server's reason (it refuses a refresh soon after the last).
  Future<String?> watchlistRefreshAuthor(String authorId) async {
    try {
      final res = await _boPost('${_watchAuthorPath(authorId)}/refresh');
      if (res is Map<String, dynamic>) _watchAuthor(res);
      _watchAuthorsChanged();
      return null;
    } catch (e) {
      debugPrint('[Watchlist] refresh author $authorId failed: $e');
      return _ForkBookOrbitWatchlist._watchError(e);
    }
  }

  /// Stops following the author. Null on success.
  Future<String?> watchlistUnfollowAuthor(String authorId) async {
    try {
      await _boDelete(_watchAuthorPath(authorId));
      _watchAuthors.remove(authorId);
      // Its catalogue cache goes with the rest in _watchAfterChange.
      final monitorId = authorId.substring(_watchAuthorPrefix.length);
      bool ofAuthor(String _, Map<String, dynamic> item) => (item['watchlist'] as Map?)?['monitorAuthorId'] == monitorId;
      _watchItems.removeWhere(ofAuthor);
      _watchLastMerge[_cleanBaseUrl]?.removeWhere(ofAuthor);
      _watchAuthorsChanged();
      debugPrint('[Watchlist] unfollowed $authorId');
      return null;
    } catch (e) {
      debugPrint('[Watchlist] unfollow $authorId failed: $e');
      return _ForkBookOrbitWatchlist._watchError(e);
    }
  }

  /// The matched book's main content file: `{folder, relativeFolder,
  /// libraryName, fileName, sizeBytes, format, fileCount}`. An audiobook in
  /// many files counts them all. `relativeFolder` is the book's folder below
  /// its library folder, as path segments.
  Future<Map<String, dynamic>?> watchlistMatchedFile(int bookId) async {
    try {
      final detail = await _detail('$bookId');
      final files = (detail['files'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((f) => f['role'] == 'primary' || f['role'] == 'content')
          .toList();
      if (files.isEmpty) return null;
      final primary = files.firstWhere((f) => f['role'] == 'primary', orElse: () => files.first);
      final path = '${primary['absolutePath'] ?? ''}';
      final slash = path.lastIndexOf(RegExp(r'[\\/]'));
      final size = files.fold<num>(0, (sum, f) => sum + ((f['sizeBytes'] as num?) ?? 0));
      final libraryId = detail['libraryId'];
      var libraryName = detail['libraryName'] as String?;
      try {
        // Cached for minutes and fetched by every library screen, so this is
        // rarely a call of its own; it also fills the library folders.
        final libs = await _libraries();
        libraryName ??= libs.firstWhere((l) => l['id'] == '$libraryId', orElse: () => const {})['name'] as String?;
      } catch (e) {
        debugPrint('[Watchlist] libraries for book $bookId: $e');
      }
      return {
        'folder': slash > 0 ? path.substring(0, slash) : '',
        'relativeFolder': _watchRelativeFolder(
          path,
          [for (final f in files) '${f['absolutePath'] ?? ''}'],
          _watchLibraryRoots['$_cleanBaseUrl|$libraryId'] ?? const [],
        ),
        'libraryName': libraryName,
        'fileName': primary['filename'] ?? (slash >= 0 ? path.substring(slash + 1) : path),
        'sizeBytes': size.toInt(),
        'format': primary['format'],
        'fileCount': files.length,
      };
    } catch (e) {
      debugPrint('[Watchlist] matched file for book $bookId: $e');
      return null;
    }
  }

  static List<String> _watchSegments(String path) => path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();

  /// The folder of [primaryPath] below the longest library folder it sits
  /// in, the way BookOrbit's web drawer cuts it. With no library folder to
  /// go by, it is cut below the folders all the book's files share, and when
  /// that leaves nothing the whole folder is shown.
  static List<String> _watchRelativeFolder(String primaryPath, List<String> filePaths, List<String> roots) {
    final folder = _watchSegments(primaryPath);
    if (folder.isNotEmpty) folder.removeLast();
    bool startsWith(List<String> a, List<String> prefix) {
      if (prefix.length > a.length) return false;
      for (var i = 0; i < prefix.length; i++) {
        if (a[i] != prefix[i]) return false;
      }
      return true;
    }

    var base = 0;
    for (final root in roots) {
      final r = _watchSegments(root);
      if (r.length > base && startsWith(folder, r)) base = r.length;
    }
    if (base > 0) return folder.sublist(base);
    var common = folder.length;
    for (final p in filePaths) {
      final f = _watchSegments(p);
      if (f.isNotEmpty) f.removeLast();
      var i = 0;
      while (i < common && i < f.length && f[i] == folder[i]) {
        i++;
      }
      common = i;
    }
    return common > 0 && common < folder.length ? folder.sublist(common) : folder;
  }
}
