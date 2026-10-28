import 'package:absorb/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

ForkScrollerConfig _config(String id, String type, {int limit = 20}) =>
    ForkScrollerConfig(id: id, type: type, label: 'Label $id', limit: limit);

Map<String, dynamic> _card(String id, {bool narrated = false}) => {
  'id': id,
  'libraryId': 7,
  'media': <String, dynamic>{
    'duration': 0,
    'metadata': <String, dynamic>{},
    if (narrated) 'narration': <String, dynamic>{},
  },
};

void main() {
  test('duplicate ids retain sorted config without inventing a library', () {
    final items = ForkScrollerConfig.batchItems([
      _config('same', 'random'),
      const ForkScrollerConfig(
        id: 'same',
        type: 'want-to-read',
        label: 'Chosen',
        order: -1,
      ),
    ]);
    final sections = ForkScrollerConfig.sections(
      items: items,
      response: {
        'items': [
          {
            'id': 'same',
            'books': [
              <String, dynamic>{'id': 'b'},
            ],
          },
        ],
      },
      wanted: {},
      toItem: (card) {
        expect(card['libraryId'], isNull);
        return card;
      },
    );
    expect(sections.single['id'], 'want-to-read');
    expect(sections.single['label'], 'Chosen');
  });

  test(
    'six shelves preserve order, split progress, labels, failures and empty slots',
    () {
      final items = ForkScrollerConfig.batchItems([
        _config('listen', 'continue-listening'),
        _config('read', 'continue-reading'),
        _config('series', 'up-next-in-series'),
        _config('want', 'want-to-read'),
        _config('failed', 'recently-added'),
        _config('random', 'random'),
      ]);
      final response = <String, dynamic>{
        'items': [
          {
            'id': 'listen',
            'books': [_card('both'), _card('listen-only')],
          },
          {
            'id': 'read',
            'books': [_card('narrated', narrated: true), _card('both')],
          },
          {
            'id': 'series',
            'books': [
              {
                ..._card('next'),
                'seriesId': 9,
                'seriesName': 'Saga',
                'seriesIndex': 2,
              },
            ],
          },
          {
            'id': 'want',
            'books': [_card('wish')],
          },
          {
            'id': 'failed',
            'failed': true,
            'books': [_card('bad')],
          },
          {'id': 'random', 'books': []},
        ],
      };
      Map<String, dynamic> toItem(Map<String, dynamic> card) {
        expect(card['libraryId'], '7');
        return {
          ...card,
          'media': <String, dynamic>{...card['media'] as Map, 'metadata': <String, dynamic>{}},
        };
      }

      List<Map<String, dynamic>> build({Set<String> wanted = const {}}) =>
          ForkScrollerConfig.sections(
            items: items,
            response: response,
            wanted: wanted,
            toItem: toItem,
          );
      final sections = build();
      expect(sections.map((s) => s['id']), [
        'continue-listening',
        'continue-reading',
        'continue-series',
        'want-to-read',
      ]);
      List<Object?> ids(Map<String, dynamic> section) =>
          (section['entities'] as List).map((e) => e['id']).toList();
      expect(ids(sections[0]), ['both', 'listen-only', 'narrated']);
      expect(ids(sections[1]), ['both']);
      expect(sections.last['label'], 'Label want');
      final next = (sections[2]['entities'] as List).single;
      expect(next['media']['metadata']['series'], {
        'id': '9',
        'name': 'Saga',
        'sequence': 2,
      });
      expect(build(wanted: {'continue-listening'}).map((s) => s['id']), [
        'continue-listening',
      ]);
      for (final entry in items) {
        entry.item['limit'] = 1;
      }
      expect(build().map((s) => (s['entities'] as List).length), [1, 1, 1, 1]);
      (response['items'] as List)[2] = {'id': 'series', 'books': []};
      final empty = build()[2];
      expect(empty['id'], 'continue-series');
      expect(empty['entities'], isEmpty);
      expect(empty['total'], 0);
    },
  );

  test(
    'a single continue shelf is not split and empty progress shelves remain',
    () {
      final items = ForkScrollerConfig.batchItems([
        _config('read', 'continue-reading'),
      ]);
      final sections = ForkScrollerConfig.sections(
        items: items,
        response: {
          'items': [
            {
              'id': 'read',
              'books': [_card('n', narrated: true)],
            },
          ],
        },
        wanted: {},
        toItem: (card) => card,
      );
      expect((sections.single['entities'] as List).single['id'], 'n');
      // An empty progress shelf keeps its slot beside a populated shelf.
      for (final type in ['continue-reading', 'continue-listening']) {
        final kept = ForkScrollerConfig.sections(
          items: ForkScrollerConfig.batchItems([
            _config('empty', type),
            _config('new', 'recently-added'),
          ]),
          response: {
            'items': [
              {'id': 'empty', 'books': []},
              {
                'id': 'new',
                'books': [_card('x')],
              },
            ],
          },
          wanted: {},
          toItem: (card) => card,
        );
        expect(kept.map((s) => s['id']), [type, 'recently-added']);
        expect(kept.first['total'], 0);
      }
    },
  );

  test('only empty progress shelves give no sections, so Home keeps its empty state', () {
    final items = ForkScrollerConfig.batchItems(const [
      ForkScrollerConfig(id: 'a', type: 'continue-listening', label: 'Listening'),
      ForkScrollerConfig(id: 'b', type: 'continue-reading', label: 'Reading'),
    ]);
    final response = {
      'items': [
        {'id': 'a', 'books': <Object>[], 'failed': false},
        {'id': 'b', 'books': <Object>[], 'failed': false},
      ],
    };
    final sections = ForkScrollerConfig.sections(
      items: items,
      response: response,
      wanted: const {},
      toItem: (card) => card,
    );
    expect(sections, isEmpty);
  });
}
