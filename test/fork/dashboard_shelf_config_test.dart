import 'package:absorb/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _me(Object? scrollers, {bool sync = true}) => {
  'dashboardShelfConfig': {'syncAcrossSessions': sync, 'scrollers': scrollers},
};

ForkScrollerConfig _config(
  String id,
  String type, {
  bool enabled = true,
  int order = 0,
  int limit = 20,
  int rows = 1,
  int? scope,
}) => ForkScrollerConfig(
  id: id,
  type: type,
  label: id,
  enabled: enabled,
  order: order,
  limit: limit,
  rows: rows,
  smartScopeId: scope,
);

void main() {
  group('Dashboard shelf config', () {
    test('requires sync and a nonempty scroller list', () {
      expect(
        ForkScrollerConfig.fromSettings(
          _me([
            {'id': 'a'},
          ], sync: false),
        ),
        isNull,
      );
      expect(ForkScrollerConfig.fromSettings(_me([])), isNull);
      expect(ForkScrollerConfig.fromSettings({}), isNull);
      expect(ForkScrollerConfig.fromSettings(_me('wrong')), isNull);
    });

    test('uses defaults for missing and wrongly typed fields', () {
      final c = ForkScrollerConfig.fromSettings(
        _me([
          {
            'id': 'a',
            'type': 'random',
            'label': 'Discover',
            'enabled': 'wrong',
            'order': [],
            'limit': null,
            'rows': false,
          },
        ]),
      )!.single;
      expect(c.id, 'a');
      expect(c.label, 'Discover');
      expect(c.enabled, isTrue);
      expect(c.order, 0);
      expect(c.limit, 20);
      expect(c.rows, 1);
      expect(c.smartScopeId, isNull);
    });

    test('batch respects order, exclusions, row limits and unique ids', () {
      final items = ForkScrollerConfig.batchItems([
        _config('late', 'random', order: 5, limit: 0),
        _config('disabled', 'random', enabled: false),
        _config('podcasts', 'continue-podcasts'),
        _config('missing', 'smart-scope'),
        _config('', 'random'),
        _config('x' * 65, 'random'),
        _config('zero', 'smart-scope', scope: 0),
        _config('negative', 'random', scope: -1),
        _config('scope', 'smart-scope', scope: 7, order: 1, limit: 30, rows: 2),
        _config('scope', 'random', order: 2),
        _config('first', 'recently-added', order: -1, limit: 4, rows: 3),
      ]);
      expect(items.map((i) => i.item['id']), ['first', 'scope', 'late']);
      expect(items.map((i) => i.item['limit']), [12, 50, 1]);
      expect(items[1].item['smartScopeId'], 7);
      expect(items[1].config.type, 'smart-scope');
      expect(items.first.item.containsKey('smartScopeId'), isFalse);
    });

    test('batch has at most eight items', () {
      final items = ForkScrollerConfig.batchItems([
        for (var i = 0; i < 12; i++) _config('$i', 'random', order: i),
      ]);
      expect(items.length, 8);
      expect(items.last.item['id'], '7');
    });

    test('maps section ids', () {
      const ids = {
        'continue-listening': 'continue-listening',
        'continue-reading': 'continue-reading',
        'up-next-in-series': 'continue-series',
        'recently-added': 'recently-added',
        'random': 'discover',
        'want-to-read': 'want-to-read',
        'smart-scope': 'smart-scope:9',
      };
      for (final entry in ids.entries) {
        expect(
          ForkScrollerConfig.sectionId(_config('a', entry.key, scope: 9)),
          entry.value,
        );
      }
    });
  });
}
