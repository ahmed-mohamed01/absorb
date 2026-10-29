part of '../api_service.dart';

// Fork-owned: the request-level speedups for BookOrbit. The hooks in
// api_service.dart and bookorbit_api_service.dart are one line each:
// `_httpClient = httpClient ?? _forkSharedHttpClient`, `_boGet` -> `_forkGet`,
// `_shelfCards` -> `_forkShelfCards`, `_forkWarmItem` at the top of `_item`,
// and `_forkNarrationProgress` at the top of `_narrationProgress`.
// See FORK_NOTES.md and the perf report.

/// One connection pool for every ApiService the auth provider hands out, so
/// requests reuse TCP+TLS connections instead of opening one each. Null
/// keeps upstream's client per request.
final bool _forkShareHttpClient = true;
final http.Client? _forkSharedHttpClient = _forkShareHttpClient ? newSharedHttpClient() : null;

/// Logs every BookOrbit GET with its time (`[BookOrbit] GET /path -> status
/// Nms bytes`) and where the sheet seed came from; flip on to measure.
final bool _forkTraceRequests = false;
bool get forkTraceRequests => _forkTraceRequests;

/// Identical GETs in flight at the same moment share one request (the sheet's
/// detail and the sync button's detail, six shelves asking for one scroller).
final InFlightJoin<String> _forkInFlight = InFlightJoin<String>();

/// A book whose manifest answered 404 (narrated EPUBs, plain ebooks) is not
/// asked for it again for half a minute, which covers one open and one Home
/// load. A detail that shows audio files drops the memo, so audio added to a
/// book is seen by the next `fresh` manifest read.
final MissMemo<String> _forkNoManifest = MissMemo<String>(const Duration(seconds: 30));
final RegExp _forkManifestPath = RegExp(r'/audiobooks/(\d+)/manifest$');
final RegExp _forkDetailPath = RegExp(r'/books/(\d+)$');

/// Scroller cards are fetched once per type at the server's maximum and cut
/// to each shelf's limit, under upstream's `personalized:` cache prefix so
/// every write that drops the shelves drops them too. The flag is a plain
/// final so the upstream body after the hook is not flagged as dead.
final bool _forkShelfCache = true;
const _forkShelfTtl = Duration(seconds: 20);
const _forkShelfMax = 50;

/// The last item map built for each book (card or full detail), so a detail
/// sheet can paint from it before its own request returns.
final BoundedMap<String, Map<String, dynamic>> _forkItems = BoundedMap(2000);

/// Responses `_forkWarmItem` started for `_item`, each handed to the first
/// `_boGet` of the same URL and then forgotten (one-shot, 5 s), so a request
/// that finished before `_item` asked for it is not made twice and nothing
/// read after a write is served from before it.
final WarmResponses<String> _forkWarm = WarmResponses<String>(const Duration(seconds: 5));

void _forkRememberItem(Map<String, dynamic> item) {
  final id = '${item['id'] ?? ''}';
  if (id.isNotEmpty) _forkItems[id] = item;
}

/// Run from `clearCaches` (sign-out, account switch) through
/// `_watchlistClearCaches`.
void _forkPerfClearCaches() {
  _forkDashboardClearCaches();
  _forkNoManifest.clear();
  _forkItems.clear();
  _forkWarm.clear();
  ForkCacheClears.run();
}

extension _ForkBookOrbitPerf on BookOrbitApiService {
  /// `_boGet`: a response `_forkWarmItem` already fetched, else the joined
  /// request with the manifest-404 memo.
  Future<dynamic> _forkGet(String path, Map<String, dynamic>? query, Duration timeout) {
    final warm = _forkWarm.take(_boUri(path, query).toString());
    if (warm != null) return warm;
    return _forkGetRaw(path, query, timeout);
  }

  Future<dynamic> _forkGetRaw(String path, Map<String, dynamic>? query, Duration timeout) {
    final uri = _boUri(path, query);
    final key = uri.toString();
    final manifest = _forkManifestPath.hasMatch(uri.path);
    if (manifest && _forkNoManifest.contains(key)) {
      return Future.error(_BoHttpError(404, 'Book has no audiobook assets'));
    }
    return _forkInFlight.run(key, () async {
      final sw = _forkTraceRequests ? (Stopwatch()..start()) : null;
      try {
        // `_authGet` sends a native `/api/v1` URL straight to the base class.
        final r = await _authGet(uri, timeout: timeout);
        if (sw != null) debugPrint('[BookOrbit] GET $path -> ${r.statusCode} ${sw.elapsedMilliseconds}ms ${r.bodyBytes.length}B');
        final decoded = _decode(r);
        final detailOf = _forkDetailPath.firstMatch(uri.path)?.group(1);
        if (detailOf != null && decoded is Map<String, dynamic> && BookOrbitApiService._detailHasAudio(decoded)) {
          _forkNoManifest.remove(_boUri('/audiobooks/$detailOf/manifest').toString());
        }
        return decoded;
      } on _BoHttpError catch (e) {
        if (manifest && e.status == 404) _forkNoManifest.add(key);
        rethrow;
      }
    });
  }

  Future<List<Map<String, dynamic>>> _forkShelfCards(String type, int limit) async {
    final all = await _cached('personalized:scroller:$type', _forkShelfTtl, () async {
      final res = await _boGet('/dashboard/scrollers/$type', {'limit': _forkShelfMax}) as Map<String, dynamic>;
      return (res['books'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    });
    return all.take(limit.clamp(1, _forkShelfMax)).toList();
  }

  /// Starts every request `_item` is about to make, together, so its serial
  /// awaits take responses already on their way. What the cached detail says
  /// the book has decides which; an unknown book asks for its manifest first.
  void _forkWarmItem(String bookId, {required bool withProgress}) {
    _forkWarm.drop(bookId);
    final k = _key(bookId);
    final known = BookOrbitApiService._details[k];
    final progress = withProgress &&
        (known == null || (BookOrbitMapper.item(detail: known)['media'] as Map)['ebookFile'] != null);
    final manifestAt = BookOrbitApiService._manifestAt[k];
    final manifestFresh =
        manifestAt != null && DateTime.now().difference(manifestAt) < BookOrbitApiService._manifestTtl;
    _forkPrefetch(bookId, '/books/$bookId');
    if (progress) _forkPrefetch(bookId, '/books/$bookId/progress');
    if (known == null) {
      // A 404 (no audiobook) skips the playback state.
      _forkPrefetch(bookId, '/audiobooks/$bookId/manifest').then<void>((_) {
        _forkPrefetch(bookId, '/audiobooks/$bookId/playback-state');
      }, onError: (Object _) {});
    } else if (BookOrbitApiService._detailHasAudio(known)) {
      if (!manifestFresh) _forkPrefetch(bookId, '/audiobooks/$bookId/manifest');
      _forkPrefetch(bookId, '/audiobooks/$bookId/playback-state');
    }
  }

  Future<Object?> _forkPrefetch(String bookId, String path) => _forkWarm.put(
      bookId, _boUri(path).toString(), () => _forkGetRaw(path, null, BookOrbitApiService._timeout));

  /// A narrated EPUB's shelf position from its detail (duration) and its file
  /// progress (position), instead of downloading the megabytes of media
  /// overlay timings `_narration` reads. Null when the overlay is already in
  /// memory, the detail has no duration, or there is no position, and the
  /// caller goes on as before.
  Future<Map<String, dynamic>?> _forkNarrationProgress(String id, Map<String, dynamic>? card) async {
    if (BookOrbitApiService._narrations[_key(id)] != null) return null;
    try {
      final media = BookOrbitMapper.item(detail: await _detail(id))['media'] as Map<String, dynamic>;
      final narration = media['narration'] as Map?;
      final fileId = int.tryParse('${narration?['fileId']}');
      final duration = (narration?['duration'] as num?)?.toDouble() ?? 0;
      if (fileId == null || duration <= 0) return null;
      final spot = await _narrationPosition(id, fileId);
      if (spot == null) return null;
      final finished = card?['isFinished'] == true;
      return {
        ...?card,
        'id': card?['id'] ?? 'bo-$id',
        'libraryItemId': id,
        'mediaItemId': id,
        'mediaItemType': 'book',
        'episodeId': null,
        'currentTime': spot.seconds,
        'duration': duration,
        'progress': finished ? 1.0 : (spot.seconds / duration).clamp(0.0, 1.0),
        'isFinished': finished,
        'lastUpdate': spot.updatedAt ?? card?['lastUpdate'] ?? 0,
      }..remove('positionUnknown');
    } catch (e) {
      debugPrint('[BookOrbit] cheap narration progress for $id: $e');
      return null;
    }
  }

  /// The permissions the sync button needs, from one `/auth/me` per ten
  /// minutes instead of one per sheet (each sheet gets a fresh service).
  Future<void> _forkLoadPermissions() async {
    if (_permissions != null) return;
    try {
      _readPermissions(await _cached('fork-auth-me', const Duration(minutes: 10),
          () async => await _boGet('/auth/me') as Map<String, dynamic>));
    } catch (e) {
      // `_can` reads /auth/me itself and answers false when that fails too.
      debugPrint('[BookOrbit] Could not read permissions: $e');
    }
  }
}

/// What a BookOrbit detail sheet can paint before its own request returns:
/// the book's full detail if it was fetched before (any Home card), else the
/// last card built for it, with the card's progress. Null on other servers.
Map<String, dynamic>? forkCachedBookOrbitItem(String itemId) {
  final card = _forkItems[itemId];
  final detail = BookOrbitApiService._details[itemId];
  if (_forkTraceRequests) {
    debugPrint('[BookOrbit] seed for $itemId: card=${card != null} detail=${detail != null} (${_forkItems.length} cards kept)');
  }
  if (detail == null) return card;
  try {
    final item = _forkWithFrame(
      BookOrbitMapper.item(detail: detail, manifest: BookOrbitApiService._manifests[itemId]),
      detail['coverAspectRatio'],
    );
    final progress = card?['userMediaProgress'];
    if (progress != null) item['userMediaProgress'] = progress;
    return item;
  } catch (_) {
    return card;
  }
}

/// Test seams for the seed caches (the maps are private to this library).
@visibleForTesting
void forkPerfTestRemember(Map<String, dynamic> item) => _forkRememberItem(item);

@visibleForTesting
void forkPerfTestSeedDetail(String id, Map<String, dynamic>? detail) {
  if (detail == null) {
    BookOrbitApiService._details.remove(id);
  } else {
    BookOrbitApiService._details[id] = detail;
  }
}

@visibleForTesting
void forkPerfTestReset() {
  _forkPerfClearCaches();
  BookOrbitApiService.clearCaches();
}
