part of '../api_service.dart';

// Fork-owned: the BookOrbit Dashboard (a virtual library built from BookOrbit's
// own cross-library shelves) and the per-book cover frame. The hooks in
// bookorbit_api_service.dart are `dashboardLibraryId`, the `global` branches in
// `_personalized`, and the `_forkWithFrame` calls. See FORK_NOTES.md.

/// The book's own cover frame, so screens can draw each book in the shape
/// of its primary file.
Map<String, dynamic> _forkWithFrame(Map<String, dynamic> item, Object? frame) {
  if (frame is String && item['media'] is Map) {
    (item['media'] as Map)['coverAspectRatio'] = frame == '1/1' ? 1.0 : 2 / 3;
  }
  return item;
}

extension _ForkBookOrbitDashboard on BookOrbitApiService {
  Map<String, dynamic> _dashboardLibrary() => {
        'id': BookOrbitApiService.dashboardLibraryId,
        'name': 'Dashboard',
        'displayOrder': -1,
        'icon': 'database',
        'mediaType': 'book',
        'provider': 'audible',
        'folders': const [],
        'settings': {'coverAspectRatio': 0},
      };

  /// The dashboard is every library at once: its shelves come from
  /// BookOrbit's own cross-library scrollers, and it has no books of its
  /// own to browse.
  Future<http.Response?> _routeDashboardLibrary(int n, String sub, Map<String, String> q) async {
    if (n == 3) return BookOrbitApiService._json(_dashboardLibrary());
    final page = int.tryParse(q['page'] ?? '') ?? 0;
    final limit = int.tryParse(q['limit'] ?? '') ?? 20;
    switch (sub) {
      case 'personalized':
        return BookOrbitApiService._json(await _cached('personalized:$BookOrbitApiService.dashboardLibraryId:${q['shelves'] ?? ''}:${q['limit'] ?? ''}',
            const Duration(seconds: 20), () => _personalized(BookOrbitApiService.dashboardLibraryId, q)));
      case 'items':
      case 'series':
      case 'collections':
      case 'playlists':
        return BookOrbitApiService._json({'results': const [], 'total': 0, 'limit': limit, 'page': page});
      case 'authors':
        return BookOrbitApiService._json(q.containsKey('page')
            ? {'results': const [], 'total': 0, 'limit': limit, 'page': page}
            : {'authors': const []});
      case 'narrators':
        return BookOrbitApiService._json({'narrators': const []});
      case 'filterdata':
        return BookOrbitApiService._json({
          'authors': const [], 'series': const [], 'genres': const [], 'tags': const [],
          'narrators': const [], 'languages': const [], 'publishers': const [], 'publishedDecades': const [],
        });
    }
    return null;
  }
}
