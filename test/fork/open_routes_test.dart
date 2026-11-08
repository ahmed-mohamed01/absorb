import 'dart:convert';

import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/fork/open_routes_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The routes BookOrbit keeps for its official iOS app that Absorb used to
/// call, each answering as the real server does without an attestation.
final _guarded = RegExp(
  r'/books/files/\d+/progress$'
  r'|/smart-scopes/\d+/books$'
  r'|/user-statistics/activity-'
  r'|/uploads/capabilities$',
);

http.Response _ok(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// The day [utc] falls on at [offset] from UTC.
String _dayAt(DateTime utc, Duration offset) {
  final d = utc.toUtc().add(offset);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _Server {
  _Server({this.features = const ['reading-progress'], this.guarded = true, this.appInfoFails = false});

  final List<String> features;
  final bool guarded;
  final bool appInfoFails;
  final List<String> calls = [];
  final List<Uri> urls = [];
  final List<Object?> bodies = [];

  /// By call: a body, or a function of the request's query giving one.
  final Map<String, Object> answers = {};

  /// By call: answer with this status instead.
  final Map<String, int> statuses = {};

  http.Client get client => MockClient((req) async {
        final path = req.url.path.replaceFirst('/api/v1', '');
        final call = '${req.method} $path';
        calls.add(call);
        urls.add(req.url);
        if (req.body.isNotEmpty) bodies.add(jsonDecode(req.body));
        if (path == '/app-info') {
          return appInfoFails ? _ok({'message': 'down'}, 500) : _ok({'version': '3.7.0', 'features': features});
        }
        if (_guarded.hasMatch(path) && guarded) {
          return _ok({'errorCode': 'APP_ATTEST_REQUIRED'}, 403);
        }
        final status = statuses[call];
        if (status != null) return _ok({'message': 'refused'}, status);
        final answer = answers[call];
        if (answer is Object Function(Map<String, String>)) return _ok(answer(req.url.queryParameters));
        if (answer != null) return _ok(answer);
        if (req.method == 'DELETE') return http.Response('', 204);
        return _ok({'message': 'not found'}, 404);
      });

  bool get calledGuarded => calls.any((c) => _guarded.hasMatch(c));

  int count(String call) => calls.where((c) => c == call).length;
}

var _servers = 0;

int _weekNumber(DateTime t) {
  final w = forkIsoWeek(t);
  return w.year * 100 + w.week;
}

BookOrbitApiService _api(_Server s) => BookOrbitApiService(
      baseUrl: 'https://open-routes-${_servers++}.test',
      token: 't',
      httpClient: s.client,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BookOrbitApiService.clearCaches();
  });

  const epubBook = {
    'id': 1,
    'title': 'Anathem',
    'files': [
      {'id': 39, 'format': 'epub', 'fileName': 'a.epub', 'role': 'content'},
    ],
  };

  group('reading progress', () {
    test('an ebook save reaches the server through the open route', () async {
      final s = _Server()
        ..answers['GET /books/1'] = epubBook
        ..answers['PUT /reading-progress'] = {'results': []};
      final ok = await _api(s).updateEbookProgress('1', ebookLocation: 'epubcfi(/6/4)', ebookProgress: 0.5);
      expect(ok, isTrue, reason: s.calls.join('\n'));
      expect(s.calledGuarded, isFalse);
      final write = ((s.bodies.last as Map)['writes'] as List).single as Map;
      expect(write['fileId'], 39);
      expect(write['percentage'], 50);
      expect(write['text'], {'cfi': 'epubcfi(/6/4)'});
    });

    test('a server without the feature keeps the older route', () async {
      final s = _Server(features: const ['other'], guarded: false)
        ..answers['GET /books/1'] = epubBook
        ..answers['POST /books/files/39/progress'] = const {};
      final ok = await _api(s).updateEbookProgress('1', ebookLocation: 'epubcfi(/6/4)', ebookProgress: 0.5);
      expect(ok, isTrue, reason: s.calls.join('\n'));
      expect(s.calls, contains('POST /books/files/39/progress'));
      expect(s.calls, isNot(contains('PUT /reading-progress')));
    });

    test('a server whose features could not be read still gets the open route', () async {
      final s = _Server(appInfoFails: true)
        ..answers['GET /books/1'] = epubBook
        ..answers['PUT /reading-progress'] = {'results': []};
      final ok = await _api(s).updateEbookProgress('1', ebookLocation: 'epubcfi(/6/4)', ebookProgress: 0.5);
      expect(ok, isTrue, reason: s.calls.join('\n'));
      expect(s.calledGuarded, isFalse);
    });

    test('a reset clears every file and marks the book unread', () async {
      final s = _Server()
        ..answers['GET /books/1/progress'] = [
          {'fileId': 39},
          {'fileId': 40},
        ]
        ..answers['GET /books/1'] = {
          ...epubBook,
          'readStatus': {'status': 'reading'},
        }
        ..answers['PATCH /books/1/status'] = const {};
      expect(await _api(s).resetProgress('1', 0), isTrue, reason: s.calls.join('\n'));
      expect(s.calledGuarded, isFalse);
      expect(s.calls, containsAll(['DELETE /reading-progress/39', 'DELETE /reading-progress/40', 'PATCH /books/1/status']));
    });
  });

  group('Smart Scopes', () {
    test('a page of books comes from the query route', () async {
      final s = _Server()
        ..answers['POST /smart-scopes/5/books/query'] = {
          'items': [
            {'id': 1, 'title': 'Anathem', 'libraryId': 3},
          ],
          'total': 1,
        };
      final page = await _api(s).collectionBooksPage('scope-5', page: 2, size: 100);
      expect(page, hasLength(1));
      expect(s.calledGuarded, isFalse);
      expect(s.bodies.last, {
        'sort': <Object>[],
        'pagination': {'page': 2, 'size': 100},
      });
    });

    test('a whole scope is paged through the query route', () async {
      final s = _Server()
        ..answers['GET /smart-scopes/5'] = {'id': 5, 'name': 'Sci-fi'}
        ..answers['POST /smart-scopes/5/books/query'] = {
          'items': [
            for (var i = 0; i < 100; i++) {'id': i + 1, 'title': 'Book $i', 'libraryId': 3},
          ],
          'total': 150,
        };
      final scope = await _api(s).getCollection('scope-5');
      expect(s.calledGuarded, isFalse);
      expect(scope, isNotNull, reason: s.calls.join('\n'));
      expect(s.count('POST /smart-scopes/5/books/query'), greaterThan(1));
      expect((s.bodies.last as Map)['pagination'], containsPair('page', greaterThan(0)));
    });
  });

  group('Book Dock', () {
    test('destinations come from the libraries, by folder name', () async {
      final s = _Server()
        ..answers['GET /auth/me'] = {
          'permissions': ['library_upload'],
        }
        ..answers['GET /libraries'] = [
          {
            'id': 3,
            'name': 'Audio',
            'folders': [
              {'id': 8, 'path': '/data/books/audio/'},
            ],
          },
        ];
      final out = await _api(s).bookDockDestinations();
      expect(s.calledGuarded, isFalse);
      expect(out.single.libraryName, 'Audio');
      expect(out.single.folderId, '8');
      expect(out.single.folderName, 'audio');
    });

    test('a folder at a root takes the library name, not a blank', () async {
      final s = _Server()
        ..answers['GET /auth/me'] = {
          'permissions': ['library_upload'],
        }
        ..answers['GET /libraries'] = [
          {
            'id': 3,
            'name': 'Audio',
            'folders': [
              {'id': 8, 'path': '/'},
            ],
          },
        ];
      expect((await _api(s).bookDockDestinations()).single.folderName, 'Audio');
    });

    test('an account that cannot upload has none', () async {
      final s = _Server()..answers['GET /auth/me'] = {'permissions': <String>[]};
      expect(await _api(s).bookDockDestinations(), isEmpty);
      expect(s.calls, isNot(contains('GET /libraries')));
    });
  });

  group('Stats', () {
    _Server statsServer() {
      final now = DateTime.now();
      final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      return _Server()
        ..answers['GET /user-statistics/daily-reading'] = [
          {'day': day, 'readingSeconds': 900, 'eventsCount': 2},
        ]
        ..answers['GET /user-statistics/session-timeline'] = {
          'items': [
            {
              'sessionId': 1,
              'bookId': 10,
              'bookTitle': 'Anathem',
              'bookFormat': 'm4b',
              'bookSource': 'android',
              'startedAt': now.toUtc().toIso8601String(),
              'endedAt': now.toUtc().toIso8601String(),
              'durationSeconds': 600,
            },
          ],
        }
        ..answers['GET /user-statistics/peak-hours'] = [
          {
            'hour': 8,
            'byFormat': {'M4B': 600, 'EPUB': 300},
          },
        ]
        ..answers['GET /user-statistics/summary'] = {'startedBooks': 4}
        ..answers['GET /auth/me'] = {
          'settings': <String, Object>{},
        };
    }

    test('the screen loads without a guarded route, and a missing extra costs nothing', () async {
      final s = statsServer();
      final stats = await _api(s).getListeningStats();
      expect(s.calledGuarded, isFalse);
      expect(stats, isNotNull, reason: s.calls.join('\n'));
      expect(stats!['today'], 900);
      expect((stats['days'] as Map).values.single, 900);
      final bo = stats['bookOrbit'] as Map;
      expect((bo['listenDays'] as Map).values.single, 600);
      expect(bo['started'], 4);
      expect(bo['timezone'], 'UTC');
      expect((bo['hours'] as List).single, {'hour': 8, 'listening': 600, 'reading': 300});
    });

    test('stays within a small number of requests', () async {
      final s = statsServer();
      await _api(s).getListeningStats();
      expect(s.calls.length, lessThan(30), reason: s.calls.join('\n'));
    });

    test('with no day totals there are no stats, not zeros', () async {
      final s = _Server();
      expect(await _api(s).getListeningStats(), isNull);
    });

    test('Year in Review reads the year from open routes', () async {
      final s = statsServer();
      final data = await _api(s).getMyYearStats(DateTime.now().year);
      expect(s.calledGuarded, isFalse);
      expect(data, isNotNull, reason: s.calls.join('\n'));
      expect(data!['totalListeningTime'], 600);
      expect(data['bookOrbitReadingTime'], 300);
      expect(data['totalListeningSessions'], 2);
    });

    test('never asks the heatmap, which stops at UTC today', () async {
      final s = statsServer();
      await _api(s).getListeningStats();
      expect(s.calls, isNot(contains('GET /user-statistics/reading-heatmap')));
    });

    group('in an account zone far from the phone', () {
      const kiritimati = Duration(hours: 14);
      tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.absorb.time_zone'), null));

      _Server zoned() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.absorb.time_zone'),
          (call) async => {'id': 'UTC', 'offsetSeconds': 0, 'otherOffsetSeconds': kiritimati.inSeconds},
        );
        final now = DateTime.now().toUtc();
        return _Server()
          ..answers['GET /auth/me'] = {
            'settings': {'timezone': 'Pacific/Kiritimati'},
          }
          ..answers['GET /user-statistics/daily-reading'] = [
            {'day': _dayAt(now, kiritimati), 'readingSeconds': 900, 'eventsCount': 1},
          ]
          ..answers['GET /user-statistics/session-timeline'] = {
            'items': [
              {
                'sessionId': 1,
                'bookId': 10,
                'bookTitle': 'Anathem',
                'bookFormat': 'm4b',
                'bookSource': 'android',
                'startedAt': now.subtract(const Duration(minutes: 10)).toIso8601String(),
                'endedAt': now.toIso8601String(),
                'durationSeconds': 600,
              },
            ],
          };
      }

      test('today and the day\'s split are the account\'s', () async {
        final stats = await _api(zoned()).getListeningStats();
        expect(stats!['today'], 900);
        final key = _dayAt(DateTime.now(), kiritimati);
        expect(((stats['bookOrbit'] as Map)['listenDays'] as Map).keys, [key]);
        expect((stats['bookOrbit'] as Map)['timezone'], 'Pacific/Kiritimati');
      });

      test('recent sessions find the session on the account\'s day', () async {
        final s = zoned();
        final recent = await _api(s).getListeningSessions(page: 0, itemsPerPage: 10);
        expect(recent, isNotNull, reason: s.calls.join('\n'));
        expect(recent!['sessions'] as List, hasLength(1), reason: s.calls.join('\n'));
      });

      test('a phone that cannot name the zone still gets stats', () async {
        final s = zoned();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('com.absorb.time_zone'), (call) async => throw 'no zone');
        expect(await _api(s).getListeningStats(), isNotNull);
      });
    });

    group('a long history', () {
      /// [weeks] active weeks back from now, each with a book of its own.
      _Server history(int weeks, {String format = 'm4b', int booksPerWeek = 1}) {
        final now = DateTime.now().toUtc();
        final at = [for (var i = 0; i < weeks; i++) now.subtract(Duration(days: 7 * i))];
        return _Server()
          ..answers['GET /auth/me'] = {'settings': <String, Object>{}}
          ..answers['GET /user-statistics/daily-reading'] = [
            for (final t in at) {'day': _dayAt(t, Duration.zero), 'readingSeconds': 600, 'eventsCount': 1},
          ]
          ..answers['GET /user-statistics/session-timeline'] = (Map<String, String> q) {
            final week = int.parse(q['year']!) * 100 + int.parse(q['week']!);
            return {
              'items': [
                for (var b = 0; b < booksPerWeek; b++)
                  for (final t in at)
                    if (_weekNumber(t) == week)
                      {
                        'sessionId': week * 10 + b,
                        'bookId': week * 10 + b,
                        'bookTitle': 'Book',
                        'bookFormat': format,
                        'bookSource': 'android',
                        'startedAt': t.toIso8601String(),
                        'endedAt': t.add(const Duration(seconds: 1)).toIso8601String(),
                        'durationSeconds': 600,
                      },
              ],
            };
          };
      }

      int timelineCalls(_Server s) => s.count('GET /user-statistics/session-timeline');
      num listened(Map<String, dynamic> stats) =>
          ((stats['bookOrbit'] as Map)['listenDays'] as Map).values.cast<num>().fold(0, (a, b) => a + b);

      test('one load reads no more than the cap, and later loads fill in the rest', () async {
        final s = history(20);
        final api = _api(s);
        final first = await api.getListeningStats();
        expect(timelineCalls(s), 8);
        expect(listened(first!), 8 * 600);

        // A later launch: only what was kept survives, and only recent weeks and
        // unread ones are asked for.
        BookOrbitApiService.clearCaches();
        final second = await api.getListeningStats();
        expect(timelineCalls(s), 16);
        expect(listened(second!), 14 * 600);

        BookOrbitApiService.clearCaches();
        final third = await api.getListeningStats();
        expect(listened(third!), 20 * 600);

        BookOrbitApiService.clearCaches();
        final before = timelineCalls(s);
        final settled = await api.getListeningStats();
        expect(timelineCalls(s) - before, 2, reason: 'just this week and last');
        expect(listened(settled!), 20 * 600);
      });

      test('the heaviest load stays well inside the rate limit', () async {
        final s = history(30, format: 'epub', booksPerWeek: 6)..answers['GET /books/0/sessions'] = {'items': <Object>[]};
        await _api(s).getListeningStats();
        expect(s.calls.length, lessThan(90), reason: s.calls.join('\n'));
      });

      test('a refused week stops further reads, and the result is not held', () async {
        final s = history(20)..statuses['GET /user-statistics/session-timeline'] = 429;
        final api = _api(s);
        final stats = await api.getListeningStats();
        expect(stats, isNotNull);
        expect(timelineCalls(s), 1);
        s.statuses.clear();
        final again = await api.getListeningStats();
        expect(listened(again!), greaterThan(0), reason: 'read again, not five minutes of nothing');
      });

      test('a changed session sends kept weeks back to be read, counting until then', () async {
        final s = history(10)..answers['PATCH /users/me/settings'] = const {};
        final api = _api(s);
        await api.getListeningStats();
        BookOrbitApiService.clearCaches();
        await api.getListeningStats();
        expect(timelineCalls(s), 8 + 4);

        await api.setAccountTimeZone('UTC');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        BookOrbitApiService.clearCaches();
        final before = timelineCalls(s);
        final stats = await api.getListeningStats();
        expect(timelineCalls(s) - before, 8);
        expect(listened(stats!), 10 * 600);
      });
    });

    group('read along on an EPUB', () {
      _Server readAlong() {
        final now = DateTime.now().toUtc();
        return _Server()
          ..answers['GET /auth/me'] = {'settings': <String, Object>{}}
          ..answers['GET /user-statistics/daily-reading'] = [
            {'day': _dayAt(now, Duration.zero), 'readingSeconds': 600, 'eventsCount': 1},
          ]
          ..answers['GET /user-statistics/session-timeline'] = {
            'items': [
              {
                'sessionId': 1,
                'bookId': 10,
                'bookTitle': 'Anathem',
                'bookFormat': 'epub',
                'bookSource': 'android',
                'startedAt': now.toIso8601String(),
                'endedAt': now.add(const Duration(minutes: 10)).toIso8601String(),
                'durationSeconds': 600,
              },
            ],
          };
      }

      test('counts as listening once the session\'s kind is read', () async {
        final s = readAlong()
          ..answers['GET /books/10/sessions'] = {
            'items': [
              {'id': 1, 'bookFileId': 39, 'sessionType': 'listen', 'format': 'EPUB'},
            ],
          };
        final bo = (await _api(s).getListeningStats())!['bookOrbit'] as Map;
        expect((bo['listenDays'] as Map).values.single, 600);
        expect(bo['readDays'], isEmpty);
        final url = s.urls.firstWhere((u) => u.path.endsWith('/books/10/sessions'));
        expect(url.queryParameters.keys, containsAll(['dateFrom', 'dateTo']));
        expect(int.parse(url.queryParameters['pageSize']!), lessThanOrEqualTo(100));
      });

      test('a book the server no longer has counts by format and does not stop the load', () async {
        final s = readAlong();
        final bo = (await _api(s).getListeningStats())!['bookOrbit'] as Map;
        expect((bo['readDays'] as Map).values.single, 600);
      });

      test('an outage on the lookup is not kept for later loads', () async {
        final s = readAlong()..statuses['GET /books/10/sessions'] = 503;
        final api = _api(s);
        await api.getListeningStats();
        s.statuses.clear();
        s.answers['GET /books/10/sessions'] = {
          'items': [
            {'id': 1, 'bookFileId': 39, 'sessionType': 'listen'},
          ],
        };
        final bo = (await api.getListeningStats())!['bookOrbit'] as Map;
        expect((bo['listenDays'] as Map).values.single, 600);
      });
    });

    test('Most listened gets its authors, and a failed lookup costs nothing', () async {
      final s = statsServer()
        ..answers['GET /books/10'] = {
          'id': 10,
          'authors': [
            {'name': 'Neal Stephenson'},
          ],
        };
      final stats = await _api(s).getListeningStats();
      expect(((stats!['items'] as Map)['10']['mediaMetadata'] as Map)['authorName'], 'Neal Stephenson');
      BookOrbitApiService.clearCaches();
      final bare = await _api(statsServer()).getListeningStats();
      expect(((bare!['items'] as Map)['10']['mediaMetadata'] as Map)['authorName'], isNull);
    });

    test('changing a session\'s length logs it again against its own file and kind', () async {
      final start = DateTime.utc(2026, 11, 2, 10);
      final s = _Server()
        ..answers['GET /books/10/sessions'] = {
          'items': [
            {'id': 7, 'bookFileId': 39, 'sessionType': 'read', 'format': 'EPUB'},
          ],
        }
        ..answers['POST /books/files/39/sessions'] = const {};
      final ok = await _api(s).updateListeningSession({
        'id': 'bo-session-7',
        'libraryItemId': '10',
        'startedAt': start.millisecondsSinceEpoch,
        'boEndedAt': start.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        'boSeconds': 600,
        'updatedAt': start.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        'timeListening': 1200,
      });
      expect(ok, isTrue, reason: s.calls.join('\n'));
      expect(s.calledGuarded, isFalse);
      expect(s.calls, containsAll(['DELETE /books/10/sessions/7', 'POST /books/files/39/sessions']));
      expect((s.bodies.last as Map)['sessionType'], 'read');
    });

    test('sessions by day come from the week they fall in', () async {
      final s = statsServer();
      final sessions = await _api(s).getListeningSessionsForDay(DateTime.now());
      expect(s.calledGuarded, isFalse);
      expect(sessions, hasLength(1), reason: s.calls.join('\n'));
      expect(sessions!.single['boReading'], isFalse);
      expect(sessions.single['timeListening'], 600);
    });
  });
}
