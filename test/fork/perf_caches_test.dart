import 'dart:async';

import 'package:absorb/services/fork/perf_caches.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InFlightJoin', () {
    test('a second caller joins the first request and nothing stays after', () async {
      final join = InFlightJoin<String>();
      var loads = 0;
      final gate = Completer<int>();
      Future<int> load() {
        loads++;
        return gate.future;
      }

      final a = join.run('k', load);
      final b = join.run('k', load);
      expect(loads, 1);
      expect(join.pending, 1);
      gate.complete(7);
      expect(await a, 7);
      expect(await b, 7);
      await Future<void>.delayed(Duration.zero);
      expect(join.pending, 0);
      expect(await join.run('k', load), 7);
      expect(loads, 2);
    });

    test('different keys do not join, and a failure reaches every joiner', () async {
      final join = InFlightJoin<String>();
      var loads = 0;
      Future<int> fail() async {
        loads++;
        throw StateError('no');
      }

      final a = join.run('a', fail);
      final b = join.run('a', fail);
      final c = join.run('b', fail);
      await Future.wait([
        expectLater(a, throwsStateError),
        expectLater(b, throwsStateError),
        expectLater(c, throwsStateError),
      ]);
      expect(loads, 2);
    });
  });

  group('BoundedMap', () {
    test('drops the oldest past capacity and a read keeps an entry', () {
      final m = BoundedMap<String, int>(2);
      m['a'] = 1;
      m['b'] = 2;
      expect(m['a'], 1); // a is now the most recent
      m['c'] = 3;
      expect(m['b'], isNull);
      expect(m['a'], 1);
      expect(m['c'], 3);
      expect(m.length, 2);
      m['a'] = 10;
      expect(m['a'], 10);
      expect(m.length, 2);
    });
  });

  group('MissMemo', () {
    test('remembers a miss until the ttl passes', () {
      var now = DateTime(2026, 1, 1);
      final memo = MissMemo<String>(const Duration(seconds: 60), now: () => now);
      expect(memo.contains('x'), isFalse);
      memo.add('x');
      expect(memo.contains('x'), isTrue);
      now = now.add(const Duration(seconds: 59));
      expect(memo.contains('x'), isTrue);
      now = now.add(const Duration(seconds: 2));
      expect(memo.contains('x'), isFalse);
      memo.add('y');
      memo.remove('y');
      expect(memo.contains('y'), isFalse);
    });
  });

  group('WarmResponses', () {
    test('a warm response is taken once, then the next read is its own', () async {
      var now = DateTime(2026, 1, 1);
      final warm = WarmResponses<String>(const Duration(seconds: 5), now: () => now);
      var starts = 0;
      Future<Object?> start() async {
        starts++;
        return 'v$starts';
      }

      final first = warm.put('book', 'k', start);
      expect(identical(warm.put('book', 'k', start), first), isTrue, reason: 'a second warm-up joins the first');
      expect(starts, 1);
      expect(await warm.take('k'), 'v1');
      expect(warm.take('k'), isNull, reason: 'one-shot');
      expect(warm.length, 0);
    });

    test('a warm response older than the ttl is ignored', () async {
      var now = DateTime(2026, 1, 1);
      final warm = WarmResponses<String>(const Duration(seconds: 5), now: () => now);
      warm.put('book', 'k', () async => 'old');
      now = now.add(const Duration(seconds: 6));
      expect(warm.take('k'), isNull);
      expect(warm.length, 0);
      final again = warm.put('book', 'k', () async => 'new');
      expect(await again, 'new');
    });

    test('dropping an owner forgets its keys and nothing else', () {
      final warm = WarmResponses<String>(const Duration(seconds: 5));
      warm.put('a', 'a1', () async => 1);
      warm.put('a', 'a2', () async => 2);
      warm.put('b', 'b1', () async => 3);
      warm.drop('a');
      expect(warm.take('a1'), isNull);
      expect(warm.take('a2'), isNull);
      expect(warm.take('b1'), isNotNull);
      warm.put('b', 'b2', () async => 4);
      warm.clear();
      expect(warm.length, 0);
    });

    test('a failed warm request does not surface as an unhandled error', () async {
      final warm = WarmResponses<String>(const Duration(seconds: 5));
      warm.put('a', 'k', () async => throw StateError('down'));
      await Future<void>.delayed(Duration.zero);
      await expectLater(warm.take('k'), throwsStateError);
    });
  });

  group('ForkCacheClears', () {
    test('listeners run once per clear and are not added twice', () {
      var runs = 0;
      void l() => runs++;
      ForkCacheClears.listen(l);
      ForkCacheClears.listen(l);
      ForkCacheClears.run();
      expect(runs, 1);
    });
  });
}
