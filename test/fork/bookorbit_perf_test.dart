import 'dart:convert';

import 'package:absorb/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A BookOrbit server with one book on the continue-listening scroller that
/// counts every request it gets.
class _Server {
  final Map<String, int> hits = {};
  var listening = [
    {'id': 1, 'title': 'Anathem', 'libraryId': 3, 'authors': ['Neal Stephenson'], 'durationSeconds': 100, 'progress': 10},
  ];

  http.Client get client => MockClient((req) async {
        final path = '${req.method} ${req.url.path}';
        hits[path] = (hits[path] ?? 0) + 1;
        // The Dashboard reads the user's shelf config first; none synced here.
        if (req.url.path.endsWith('/auth/me')) {
          return http.Response(jsonEncode({'settings': {}}), 200, headers: {'content-type': 'application/json'});
        }
        if (req.url.path.endsWith('/dashboard/scrollers/continue-listening')) {
          return http.Response(jsonEncode({'books': listening}), 200, headers: {'content-type': 'application/json'});
        }
        if (req.url.path.endsWith('/dashboard/scrollers/continue-reading')) {
          return http.Response(jsonEncode({'books': []}), 200, headers: {'content-type': 'application/json'});
        }
        if (req.method == 'PATCH' && req.url.path.endsWith('/books/1/status')) {
          listening = [];
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"message":"not found"}', 404);
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(forkPerfTestReset);

  BookOrbitApiService api(_Server s) => BookOrbitApiService(baseUrl: 'https://bookorbit.test', token: 't', httpClient: s.client);

  group('shelf cards', () {
    test('six shelves at once cost one scroller request each, and a write drops them', () async {
      final s = _Server();
      final a = api(s);
      final shelves = await Future.wait([
        for (var i = 0; i < 6; i++)
          a.getPersonalizedView(BookOrbitApiService.dashboardLibraryId, shelves: ['continue-listening'], limit: 5 + i),
      ]);
      expect(shelves.every((v) => v != null && v.length == 1), isTrue);
      expect(s.hits['GET /api/v1/dashboard/scrollers/continue-listening'], 1);
      expect(s.hits['GET /api/v1/dashboard/scrollers/continue-reading'], 1);

      // Marking the book read must show on the next Home load, not 20 s later.
      expect(await a.setReadStatus('1', 'read'), isTrue);
      final after = await a.getPersonalizedView(BookOrbitApiService.dashboardLibraryId, shelves: ['continue-listening'], limit: 5);
      expect(after, isEmpty);
      expect(s.hits['GET /api/v1/dashboard/scrollers/continue-listening'], 2);
    });
  });

  group('forkCachedBookOrbitItem', () {
    test('nothing cached, nothing seeded', () {
      expect(forkCachedBookOrbitItem('9'), isNull);
    });

    test('the last card seeds the sheet when no detail was fetched', () {
      forkPerfTestRemember({'id': '9', 'media': {'metadata': {'title': 'Card'}}, 'userMediaProgress': {'progress': 0.4}});
      final seed = forkCachedBookOrbitItem('9')!;
      expect((seed['media'] as Map)['metadata']['title'], 'Card');
    });

    test('a fetched detail seeds the full item and keeps the card\'s progress', () {
      forkPerfTestRemember({'id': '9', 'media': {'metadata': {'title': 'Card'}}, 'userMediaProgress': {'progress': 0.4}});
      forkPerfTestSeedDetail('9', {
        'id': 9,
        'title': 'Detail',
        'libraryId': 3,
        'authors': [{'id': 1, 'name': 'A'}],
        'description': 'Full',
        'files': [],
      });
      final seed = forkCachedBookOrbitItem('9')!;
      expect((seed['media'] as Map)['metadata']['title'], 'Detail');
      expect((seed['media'] as Map)['metadata']['description'], 'Full');
      expect((seed['userMediaProgress'] as Map)['progress'], 0.4);
    });
  });
}
