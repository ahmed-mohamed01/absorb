import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/fork/perf_caches.dart';
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
}
