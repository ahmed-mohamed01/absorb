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
  // Every card and detail item passes through here: keep the last one per
  // book for the detail sheet to paint from (bookorbit_perf.dart).
  _forkRememberItem(item);
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
  Future<http.Response?> _routeDashboardLibrary(
    int n,
    String sub,
    Map<String, String> q,
  ) async {
    if (n == 3) return BookOrbitApiService._json(_dashboardLibrary());
    final page = int.tryParse(q['page'] ?? '') ?? 0;
    final limit = int.tryParse(q['limit'] ?? '') ?? 20;
    switch (sub) {
      case 'personalized':
        return BookOrbitApiService._json(
          await _cached(
            'personalized:$BookOrbitApiService.dashboardLibraryId:${q['shelves'] ?? ''}:${q['limit'] ?? ''}',
            const Duration(seconds: 20),
            () => _personalized(BookOrbitApiService.dashboardLibraryId, q),
          ),
        );
      case 'items':
      case 'series':
      case 'collections':
      case 'playlists':
        return BookOrbitApiService._json({
          'results': const [],
          'total': 0,
          'limit': limit,
          'page': page,
        });
      case 'authors':
        return BookOrbitApiService._json(
          q.containsKey('page')
              ? {'results': const [], 'total': 0, 'limit': limit, 'page': page}
              : {'authors': const []},
        );
      case 'narrators':
        return BookOrbitApiService._json({'narrators': const []});
      case 'filterdata':
        return BookOrbitApiService._json({
          'authors': const [],
          'series': const [],
          'genres': const [],
          'tags': const [],
          'narrators': const [],
          'languages': const [],
          'publishers': const [],
          'publishedDecades': const [],
        });
    }
    return null;
  }
}

/// One configured Dashboard shelf and the pure mapping of its batch response.
class ForkScrollerConfig {
  /// The server identifier for this shelf.
  final String id;

  /// The server type used for this entry.
  final String type;

  /// The configured display label.
  final String label;

  /// Whether this shelf is enabled.
  final bool enabled;

  /// The configured display order.
  final int order;

  /// The number of books requested per row.
  final int limit;

  /// The number of rows requested.
  final int rows;

  /// The saved smart scope, when this shelf uses one.
  final int? smartScopeId;

  /// Creates this value from the supplied fields.
  const ForkScrollerConfig({
    required this.id,
    required this.type,
    required this.label,
    this.enabled = true,
    this.order = 0,
    this.limit = 20,
    this.rows = 1,
    this.smartScopeId,
  });

  /// Reads synced shelves from the user's settings.
  static List<ForkScrollerConfig>? fromSettings(Map<String, dynamic> settings) {
    final config = settings['dashboardShelfConfig'];
    if (config is! Map || config['syncAcrossSessions'] != true) return null;
    final raw = config['scrollers'];
    if (raw is! List || raw.isEmpty) return null;
    int number(Object? v, int fallback) =>
        v is num && v.isFinite ? v.toInt() : fallback;
    return [
      for (final c in raw)
        if (c is Map)
          ForkScrollerConfig(
            id: c['id'] is String ? c['id'] as String : '',
            type: c['type'] is String ? c['type'] as String : '',
            label: c['label'] is String ? c['label'] as String : '',
            enabled: c['enabled'] is bool ? c['enabled'] as bool : true,
            order: number(c['order'], 0),
            limit: number(c['limit'], 20),
            rows: number(c['rows'], 1),
            smartScopeId:
                c['smartScopeId'] is num && (c['smartScopeId'] as num).isFinite
                ? (c['smartScopeId'] as num).toInt()
                : null,
          ),
    ];
  }

  /// Builds valid batch requests in configured order, retaining each shelf.
  static List<({ForkScrollerConfig config, Map<String, dynamic> item})>
  batchItems(List<ForkScrollerConfig> all) {
    final sorted = all.indexed.where((e) => e.$2.enabled).toList()
      ..sort((a, b) {
        final order = a.$2.order.compareTo(b.$2.order);
        return order == 0 ? a.$1.compareTo(b.$1) : order;
      });
    final seen = <String>{};
    const supported = {
      'recently-added',
      'continue-reading',
      'continue-listening',
      'want-to-read',
      'up-next-in-series',
      'random',
      'smart-scope',
    };
    return [
      for (final entry in sorted)
        if (supported.contains(entry.$2.type) &&
            entry.$2.id.isNotEmpty &&
            entry.$2.id.length <= 64 &&
            (entry.$2.smartScopeId == null || entry.$2.smartScopeId! >= 1) &&
            (entry.$2.type != 'smart-scope' || entry.$2.smartScopeId != null) &&
            seen.add(entry.$2.id))
          (
            config: entry.$2,
            item: <String, dynamic>{
              'id': entry.$2.id,
              'type': entry.$2.type,
              'limit': (entry.$2.limit * entry.$2.rows).clamp(1, 50),
              if (entry.$2.smartScopeId != null)
                'smartScopeId': entry.$2.smartScopeId,
            },
          ),
    ].take(8).toList();
  }

  /// Maps a server scroller to the section used by Home.
  static String sectionId(ForkScrollerConfig c) => switch (c.type) {
    'up-next-in-series' => 'continue-series',
    'random' => 'discover',
    'smart-scope' => 'smart-scope:${c.smartScopeId}',
    _ => c.type,
  };

  /// Maps batch cards to Home sections without making requests.
  static List<Map<String, dynamic>> sections({
    required List<({ForkScrollerConfig config, Map<String, dynamic> item})>
    items,
    required Map<String, dynamic> response,
    required Set<String> wanted,
    required Map<String, dynamic> Function(Map<String, dynamic> card) toItem,
    bool Function(String sectionId, Map<String, dynamic> card)? hidden,
  }) {
    final byId = <String, List<Map<String, dynamic>>>{};
    final raw = response['items'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map || item['failed'] == true || item['books'] is! List)
          continue;
        byId['${item['id']}'] = [
          for (final card in item['books'] as List)
            if (card is Map) Map<String, dynamic>.from(card),
        ];
      }
    }
    final listening = <Map<String, dynamic>>[];
    final reading = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item.item['type'] == 'continue-listening')
        listening.addAll(byId[item.item['id']] ?? []);
      if (item.item['type'] == 'continue-reading')
        reading.addAll(byId[item.item['id']] ?? []);
    }
    final split =
        items.any((i) => i.item['type'] == 'continue-listening') &&
        items.any((i) => i.item['type'] == 'continue-reading');
    final listenIds = {for (final c in listening) '${c['id']}'};
    final readIds = {for (final c in reading) '${c['id']}'};
    final seen = <String>{};
    final merged = [
      ...listening,
      ...reading,
    ].where((c) => seen.add('${c['id']}')).toList();
    bool belongs(Map<String, dynamic> card, bool listen) {
      final media =
          toItem({...card, 'libraryId': card['libraryId']?.toString()})['media']
              as Map;
      final id = '${card['id']}';
      final narration = media['narration'] != null;
      final audio = narration || ((media['duration'] as num?) ?? 0) > 0;
      if (listen)
        return listenIds.contains(id) ||
            narration ||
            (!readIds.contains(id) && audio);
      return !narration &&
          (readIds.contains(id) || (!listenIds.contains(id) && !audio));
    }

    final sections = <Map<String, dynamic>>[];
    for (final batch in items) {
      final c = batch.config;
      final id = sectionId(c);
      if (wanted.isNotEmpty && !wanted.contains(id)) continue;
      if (!byId.containsKey(c.id)) continue;
      Iterable<Map<String, dynamic>> cards = byId[c.id]!;
      if (split &&
          (c.type == 'continue-listening' || c.type == 'continue-reading')) {
        cards = merged.where(
          (card) => belongs(card, c.type == 'continue-listening'),
        );
      }
      if (hidden != null) cards = cards.where((card) => !hidden(id, card));
      final entities = cards.take(batch.item['limit'] as int).map((card) {
        final item = toItem({
          ...card,
          'libraryId': card['libraryId']?.toString(),
        });
        if (c.type == 'up-next-in-series' && card['seriesName'] != null) {
          ((item['media'] as Map<String, dynamic>)['metadata']
              as Map<String, dynamic>)['series'] = {
            'id': '${card['seriesId'] ?? 'name:${card['seriesName']}'}',
            'name': card['seriesName'],
            'sequence': card['seriesIndex'],
          };
        }
        return item;
      }).toList();
      if (entities.isEmpty &&
          !{
            'continue-listening',
            'continue-reading',
            'continue-series',
          }.contains(id))
        continue;
      sections.add({
        'id': id,
        'label': c.label,
        'labelStringKey': c.label,
        'type': 'book',
        'entities': entities,
        'total': entities.length,
      });
    }
    // Only empty slots means nothing to show: Home keeps its empty state.
    if (sections.every((s) => (s['entities'] as List).isEmpty)) return [];
    return sections;
  }
}

/// Cache key of the user's Dashboard settings (one minute).
const _forkDashboardConfigKey = 'fork-dashboard-config';

// Keyed by server, not instance: the app builds BookOrbitApiService objects
// freely (their caches are static), so a flag on one would not reach another.
final _forkDashboardConfigured = <String, bool>{};

/// The last settings each server gave, for a read that fails later.
final _forkLastSettings = <String, Map<String, dynamic>>{};

/// Forgets both maps, run with the other caches when the account changes.
void _forkDashboardClearCaches() {
  _forkDashboardConfigured.clear();
  _forkLastSettings.clear();
}

/// Loads the server's shared Dashboard settings and configured shelves.
extension ForkDashboardConfigurationApi on BookOrbitApiService {
  /// Whether this server has synced shelves, unknown until a successful read.
  bool? get forkDashboardConfigured => _forkDashboardConfigured[_cleanBaseUrl];

  Future<Map<String, dynamic>> _forkDashboardSettings() =>
      _cached(_forkDashboardConfigKey, const Duration(seconds: 60), () async {
        final me = await _boGet('/auth/me') as Map<String, dynamic>;
        final settings = me['settings'];
        return settings is Map
            ? Map<String, dynamic>.from(settings)
            : <String, dynamic>{};
      });

  Future<List<ForkScrollerConfig>?> _forkDashboardShelfConfig() async {
    Map<String, dynamic> settings;
    try {
      settings = await _forkDashboardSettings();
      _forkLastSettings[_cleanBaseUrl] = settings;
    } catch (e) {
      // A failed read keeps the last settings this server gave, so Home keeps
      // its configured shelves; with none yet the fixed shelves show and the
      // configured flag stays unknown. Throwing here would blank Home: the
      // route turns an error into no shelves at all.
      debugPrint('[BookOrbit] Dashboard settings read failed: $e');
      final last = _forkLastSettings[_cleanBaseUrl];
      if (last == null) return null;
      settings = last;
    }
    final config = ForkScrollerConfig.fromSettings(settings);
    _forkDashboardConfigured[_cleanBaseUrl] = config != null;
    return config;
  }

  Future<List<Map<String, dynamic>>?> _forkConfiguredShelves(
    List<ForkScrollerConfig> config,
    Map<String, String> q,
  ) async {
    final wanted = (q['shelves'] ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toSet();
    // Fetch both continue shelves when either is requested so the split is stable.
    bool asked(({ForkScrollerConfig config, Map<String, dynamic> item}) entry) {
      if (wanted.isEmpty) return true;
      final c = entry.config;
      if (wanted.contains(ForkScrollerConfig.sectionId(c))) return true;
      final progress =
          c.type == 'continue-listening' || c.type == 'continue-reading';
      return progress &&
          (wanted.contains('continue-listening') ||
              wanted.contains('continue-reading'));
    }

    final items = ForkScrollerConfig.batchItems(config).where(asked).toList();
    if (items.isEmpty) return [];
    Map<String, dynamic> response;
    try {
      response =
          await _boPost('/dashboard/scrollers/batch', {
                'items': [for (final entry in items) entry.item],
              })
              as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[BookOrbit] Dashboard batch failed: $e');
      return null;
    }
    // Continue shelves honour what was removed from them, as upstream's do.
    final hiddenBooks = (await ScopedPrefs.getStringList(BookOrbitApiService._hiddenBooksKey)).toSet();
    final hiddenSeries = (await ScopedPrefs.getStringList(BookOrbitApiService._hiddenSeriesKey)).toSet();
    return ForkScrollerConfig.sections(
      hidden: (shelfId, c) => switch (shelfId) {
        'continue-listening' || 'continue-reading' => hiddenBooks.contains('${c['id']}'),
        'continue-series' => hiddenSeries.contains('${c['seriesId'] ?? 'name:${c['seriesName']}'}'),
        _ => false,
      },
      items: items,
      response: response,
      wanted: wanted,
      toItem: (card) =>
          _cardItem(card, libraryId: card['libraryId'] as String?),
    );
  }
}
