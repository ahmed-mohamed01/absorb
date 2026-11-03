import 'dart:convert';

import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/fork/perf_caches.dart';
import 'package:absorb/services/fork/position_sync_chain.dart';
import 'package:absorb/services/fork/position_sync_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  BookOrbitApiService api() => BookOrbitApiService(
        baseUrl: 'https://bookorbit.test',
        token: 't',
        httpClient: MockClient((_) async => http.Response('{"message":"no"}', 404)),
      );

  const grace = Duration(milliseconds: 60);
  Future<void> wait(Duration d) => Future<void>.delayed(d);

  setUp(() => PositionSyncController.releaseGrace = grace);
  tearDown(() => PositionSyncController.releaseGrace = const Duration(seconds: 90));

  test('a released controller is parked, kept for the grace period, then disposed', () async {
    final c = PositionSyncController.acquire(api(), 41);
    expect(c.parkedForTest, isFalse);
    PositionSyncController.release(c);
    expect(c.parkedForTest, isTrue);
    expect(c.pollingForTest, isFalse);
    expect(PositionSyncController.retainedForTest(41), isTrue);
    expect(c.disposedForTest, isFalse);

    await wait(grace ~/ 2);
    expect(PositionSyncController.retainedForTest(41), isTrue);
    await wait(grace);
    expect(PositionSyncController.retainedForTest(41), isFalse);
    expect(c.disposedForTest, isTrue);
  });

  test('reacquiring within the grace period keeps the same controller and unparks it', () async {
    final c = PositionSyncController.acquire(api(), 42);
    PositionSyncController.release(c);
    await wait(grace ~/ 2);
    final again = PositionSyncController.acquire(api(), 42);
    expect(identical(again, c), isTrue);
    expect(c.parkedForTest, isFalse);
    await wait(grace * 2);
    expect(c.disposedForTest, isFalse, reason: 'held again, so the old dispose timer must not fire');
    PositionSyncController.release(c);
    await wait(grace * 2);
    expect(c.disposedForTest, isTrue);
  });

  test('clearing the caches disposes parked controllers but not held ones', () async {
    final parked = PositionSyncController.acquire(api(), 43);
    final held = PositionSyncController.acquire(api(), 44);
    PositionSyncController.release(parked);
    ForkCacheClears.run();
    expect(parked.disposedForTest, isTrue);
    expect(PositionSyncController.retainedForTest(43), isFalse);
    expect(held.disposedForTest, isFalse);
    expect(PositionSyncController.retainedForTest(44), isTrue);
    PositionSyncController.release(held);
    await wait(grace * 2);
    expect(held.disposedForTest, isTrue);
  });

  group('read-aloud entry', () {
    const capable = ReadAloudCapabilityWire(workerConfigured: true, eligible: true);
    ReadAloudJobWire job(ReadAloudJobStatus status, {Map<String, dynamic> extra = const {}}) =>
        ReadAloudJobWire.fromJson({'id': 'j', 'bookId': 1, 'status': _snake(status.name), ...extra})!;

    test('follows upstream: hidden, available, unavailable', () {
      expect(resolveReadAloudEntry(enabled: false, capability: capable), isA<ReadAloudEntryHidden>());
      expect(resolveReadAloudEntry(enabled: true), isA<ReadAloudEntryHidden>());
      expect(resolveReadAloudEntry(enabled: true, capability: const ReadAloudCapabilityWire()), isA<ReadAloudEntryHidden>(),
          reason: 'no worker configured');
      expect(
          resolveReadAloudEntry(
              enabled: true,
              capability: const ReadAloudCapabilityWire(workerConfigured: true, reason: ReadAloudReason.singleFileLibrary)),
          isA<ReadAloudEntryHidden>());
      expect(resolveReadAloudEntry(enabled: true, capability: capable), isA<ReadAloudEntryAvailable>());
      final busy = resolveReadAloudEntry(enabled: true, capability: capable, job: job(ReadAloudJobStatus.processing));
      expect((busy as ReadAloudEntryUnavailable).reason, ReadAloudReason.jobActive);
      final existing = resolveReadAloudEntry(
          enabled: true,
          capability: const ReadAloudCapabilityWire(workerConfigured: true, reason: ReadAloudReason.noEpub, existingReadAlongs: 1));
      expect((existing as ReadAloudEntryUnavailable).message, PositionSyncCopy.reasonNoEpubExisting);
      final ineligible = resolveReadAloudEntry(enabled: true, capability: const ReadAloudCapabilityWire(workerConfigured: true));
      expect((ineligible as ReadAloudEntryUnavailable).message, PositionSyncCopy.reasonUnknown);
    });

    test('the slot follows running, review and failed jobs only', () {
      final now = DateTime.utc(2026, 10, 31);
      expect(slotJobFrom(job(ReadAloudJobStatus.completed)), isNull);
      expect(slotJobFrom(job(ReadAloudJobStatus.failed, extra: {'dismissedAt': 'x'})), isNull);
      final running = slotJobFrom(job(ReadAloudJobStatus.processing,
          extra: {'canManage': true, 'cancellable': true, 'stage': 'publishing'}))!;
      expect(running.canCancel, isFalse, reason: 'too late once it is being added to the book');
      final failed = slotJobFrom(
          job(ReadAloudJobStatus.failed,
              extra: {'canManage': true, 'errorCode': 'alignment_failed', 'retryableUntil': '2026-11-01T00:00:00Z'}),
          now: now)!;
      expect(failed.canRetry, isTrue);
      expect(failed.error, "The text couldn't be matched to the narration.");
      final expired = slotJobFrom(
          job(ReadAloudJobStatus.failed, extra: {'canManage': true, 'retryableUntil': '2026-10-30T00:00:00Z'}),
          now: now)!;
      expect(expired.canRetry, isFalse);
    });
  });

  test('a book with an EPUB and audio creates a read-aloud in one tap', () async {
    final requests = <String>[];
    Map<String, dynamic>? created;
    final job = {'id': 'j9', 'bookId': 50, 'status': 'queued', 'stage': 'queued', 'progress': 0, 'canManage': true, 'cancellable': true};
    final client = MockClient((req) async {
      final path = req.url.path.replaceFirst('/api/v1', '');
      requests.add('${req.method} $path');
      Object? body;
      switch ('${req.method} $path') {
        case 'GET /auth/me':
          body = {'permissions': ['library_generate_read_aloud', 'edition_sync']};
        case 'GET /edition-sync/settings':
          body = {'enabled': true, 'effectiveEnabled': true, 'disabledReason': null, 'bookSyncMode': 'all_eligible'};
        case 'GET /edition-sync/books/50/state':
          body = {
            'bookId': 50,
            'eligible': true,
            'hasReadAlong': false,
            'syncEnabled': true,
            'index': {'status': 'ready', 'whisperFallback': false},
          };
        case 'GET /books/50':
          body = {
            'id': 50,
            'language': 'en',
            'files': [
              {'id': 1, 'role': 'primary', 'format': 'epub', 'sizeBytes': 10, 'filename': 'Book.epub'},
              {'id': 2, 'role': 'content', 'format': 'm4b', 'sizeBytes': 20, 'filename': 'Book.m4b'},
            ],
            'readAloudSync': {'mode': 'auto', 'state': 'unavailable', 'unavailableReason': 'no_media_overlay_epub'},
          };
        case 'GET /books/50/progress':
          body = [
            {'fileId': 1, 'percentage': 40},
          ];
        case 'GET /books/50/read-aloud':
          body = {
            'workerConfigured': true,
            'eligible': true,
            'reason': null,
            'supportedLanguages': ['en'],
            'epubFiles': [
              {'id': 1, 'filename': 'Book.epub'},
            ],
            'audioFiles': [
              {'id': 2},
            ],
            'existingReadAlongs': [],
            'latestJob': null,
          };
        case 'GET /user-preferences/read-aloud':
          body = {'settings': {'defaultLanguage': null}};
        case 'POST /books/50/read-aloud-jobs':
          created = jsonDecode(req.body) as Map<String, dynamic>;
          body = job;
        default:
          return http.Response('{"message":"no"}', 404);
      }
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });
    final service = BookOrbitApiService(baseUrl: 'https://bookorbit.test', token: 't', httpClient: client);
    final c = PositionSyncController.acquire(service, 50);
    addTearDown(() => PositionSyncController.release(c));
    await c.loadInitial();
    expect(c.eligible, isTrue);
    final slot = c.chain.rows.whereType<ChainReadAloudSlotRow>().single;
    expect(slot.variant, ReadAloudSlotVariant.notCreated);
    expect(c.snapshot.ebook?.progress, 40);
    expect(c.chain.header.label, '2 of 2 in sync');

    expect(c.index?.status, EditionSyncIndexStatus.ready);

    expect(await c.createReadAloud(), isTrue);
    expect(created, {'epubFileId': 1, 'audioFileIds': [2], 'language': 'en', 'granularity': 'sentence'});
    expect(c.creating, isTrue);
    expect(c.buttonState, SyncButtonState.building);
    final queued = c.chain.rows.whereType<ChainReadAloudSlotRow>().single;
    expect(queued.variant, ReadAloudSlotVariant.queued);
    expect(queued.cancel?.id, ChainActionId.cancelReadAloud);
    expect(requests, contains('GET /books/50/read-aloud'));
  });
  /// A book with read-aloud sync off, on a server whose edition sync PATCH
  /// works or fails.
  Future<(PositionSyncController, List<String>)> editionSyncBook({
    int id = 60,
    bool enabled = false,
    bool patchFails = false,
    bool readAloudFails = false,
    bool serverOff = false,
  }) async {
    final requests = <String>[];
    var syncEnabled = enabled;
    final client = MockClient((req) async {
      final path = req.url.path.replaceFirst('/api/v1', '');
      requests.add('${req.method} $path${req.body.isEmpty ? '' : ' ${req.body}'}');
      Object? body;
      Map<String, dynamic> state() => {
            'eligible': true,
            'hasReadAlong': false,
            'syncEnabled': syncEnabled,
            'effectiveReason': syncEnabled ? null : 'excluded',
            'index': {'status': syncEnabled ? 'queued' : 'none'},
            'canRunNow': true,
          };
      Map<String, dynamic> book(String mode) => {
            'id': id,
            'files': [
              {'id': 1, 'role': 'primary', 'format': 'epub', 'sizeBytes': 10, 'filename': 'Book.epub'},
              {'id': 2, 'role': 'content', 'format': 'm4b', 'sizeBytes': 20, 'filename': 'Book.m4b'},
            ],
            'readAloudSync': {'mode': mode, 'state': 'disabled'},
          };
      switch ('${req.method} ${path.replaceFirst('/$id', '/ID')}') {
        case 'GET /auth/me':
          body = {'permissions': ['edition_sync']};
        case 'GET /edition-sync/settings':
          body = {'effectiveEnabled': true};
        case 'GET /edition-sync/books/ID/state':
          body = state();
        case 'PATCH /edition-sync/books/ID/state':
          if (patchFails) return http.Response('{"message":"down"}', 500);
          syncEnabled = !serverOff && (jsonDecode(req.body) as Map)['syncEnabled'] == true;
          body = state();
        case 'GET /books/ID':
          body = book('disabled');
        case 'PATCH /books/ID/read-aloud-sync':
          if (readAloudFails) return http.Response('{"message":"down"}', 500);
          body = book('auto');
        case 'GET /books/ID/progress':
          body = [];
        default:
          return http.Response('{"message":"no"}', 404);
      }
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });
    final service = BookOrbitApiService(baseUrl: 'https://bookorbit.test', token: 't', httpClient: client);
    final c = PositionSyncController.acquire(service, id);
    // Dropped at once, so the next test doesn't pick up this one parked.
    addTearDown(() {
      PositionSyncController.release(c);
      PositionSyncController.disposeIdle();
    });
    await c.loadInitial();
    return (c, requests);
  }

  test('turning edition sync on also turns read-aloud sync back on', () async {
    final (c, requests) = await editionSyncBook();
    expect(c.index?.on, isFalse);
    expect(c.index?.offReason, EditionSyncOffReason.excluded);
    expect(c.chain.rows.whereType<ChainConnectorRow>().single.toggle?.on, isFalse);

    expect(await c.setIndexSync(true), isTrue);
    expect(requests, contains('PATCH /edition-sync/books/60/state {"syncEnabled":true}'));
    expect(requests, contains('PATCH /books/60/read-aloud-sync {"mode":"auto"}'));
    expect(c.index?.on, isTrue);
    expect(c.index?.status, EditionSyncIndexStatus.queued);
    expect(c.pollingForTest, isTrue, reason: 'a queued index is polled');
  });

  test('a refused edition sync switch leaves read-aloud sync alone and says so', () async {
    final (c, requests) = await editionSyncBook(id: 61, enabled: true, patchFails: true);
    expect(c.index?.offReason, EditionSyncOffReason.readAloudSyncOff, reason: 'on, but read-aloud sync is off');
    final notices = <PositionSyncNotice>[];
    c.onNotice = notices.add;
    expect(await c.setIndexSync(true), isFalse);
    expect(requests.where((r) => r.startsWith('PATCH /books/61/read-aloud-sync')), isEmpty);
    expect(notices.single.message, PositionSyncCopy.toastEditionSyncFailed);
  });

  test('turning edition sync on fails when read-aloud sync then refuses', () async {
    final (c, requests) = await editionSyncBook(id: 62, readAloudFails: true);
    expect(await c.setIndexSync(true), isFalse, reason: 'the card toasts on false');
    expect(requests, contains('PATCH /books/62/read-aloud-sync {"mode":"auto"}'));
    expect(c.index?.on, isFalse);
  });

  test('a server that keeps edition sync off leaves read-aloud sync alone', () async {
    final (c, requests) = await editionSyncBook(id: 63, serverOff: true);
    expect(await c.setIndexSync(true), isTrue);
    expect(requests.where((r) => r.startsWith('PATCH /books/63/read-aloud-sync')), isEmpty);
  });

  test('an action that is not edition sync\'s sends nothing', () async {
    final (c, requests) = await editionSyncBook(id: 64);
    final before = requests.length;
    expect(await c.runIndexAction(ChainActionId.cancelReadAloud), isFalse);
    expect(requests.length, before);
  });

  test('a failed edition sync settings read keeps the last answer', () async {
    var down = false;
    final client = MockClient((req) async {
      final path = req.url.path.replaceFirst('/api/v1', '');
      if (path == '/auth/me') {
        return http.Response(jsonEncode({'permissions': ['edition_sync']}), 200, headers: {'content-type': 'application/json'});
      }
      if (path == '/edition-sync/settings') {
        if (down) return http.Response('{"message":"down"}', 503);
        return http.Response(jsonEncode({'effectiveEnabled': true}), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('{"message":"no"}', 404);
    });
    final service = BookOrbitApiService(baseUrl: 'https://settings.test', token: 't', httpClient: client);
    BookOrbitApiService.clearCaches();
    expect((await service.positionSyncPermissions()).editionSync, isTrue);
    BookOrbitApiService.clearCaches();
    down = true;
    expect((await service.positionSyncPermissions()).editionSync, isTrue);
  });
}

String _snake(String camel) => camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
