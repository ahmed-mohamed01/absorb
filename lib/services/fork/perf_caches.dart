// Fork-owned: small pure-Dart caches behind the BookOrbit request hooks in
// bookorbit_perf.dart. No Flutter, no I/O, so they are unit-tested on their
// own. See FORK_NOTES.md.

import 'dart:async';
import 'dart:collection';

export 'shared_http_client.dart';

/// Joins identical concurrent requests: the second caller of [run] for a key
/// that is still in flight gets the first caller's future instead of a second
/// request. Nothing is kept once the future completes.
class InFlightJoin<K> {
  final Map<K, Future<Object?>> _inFlight = {};

  int get pending => _inFlight.length;

  Future<T> run<T>(K key, Future<T> Function() load) {
    final hit = _inFlight[key];
    if (hit != null) return hit.then((v) => v as T);
    final future = load();
    _inFlight[key] = future;
    // The joiners get the error through their own copies of the future.
    future.whenComplete(() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }).ignore();
    return future;
  }
}

/// A map that forgets its oldest entries past [capacity]; a read moves the
/// entry to the back so what is in use stays.
class BoundedMap<K, V> {
  BoundedMap(this.capacity);
  final int capacity;
  final LinkedHashMap<K, V> _map = LinkedHashMap();

  int get length => _map.length;

  V? operator [](K key) {
    final v = _map.remove(key);
    if (v == null) return null;
    _map[key] = v;
    return v;
  }

  void operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }

  void remove(K key) => _map.remove(key);
  void clear() => _map.clear();
}

/// Remembers that something was missing for a while, so the same miss is not
/// asked for again right away.
class MissMemo<K> {
  MissMemo(this.ttl, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final Duration ttl;
  final DateTime Function() _now;
  final Map<K, DateTime> _at = {};

  void add(K key) => _at[key] = _now();

  bool contains(K key) {
    final at = _at[key];
    if (at == null) return false;
    if (_now().difference(at) >= ttl) {
      _at.remove(key);
      return false;
    }
    return true;
  }

  void remove(K key) => _at.remove(key);
  void clear() => _at.clear();
}

/// Responses started ahead of the reads that will want them. Each is handed
/// to the first [take] of its key and then forgotten (one-shot), and ignored
/// once older than [ttl], so a read made after a write can never be served
/// from before it. The keys started for one owner are dropped together.
class WarmResponses<K> {
  WarmResponses(this.ttl, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final Duration ttl;
  final DateTime Function() _now;
  final Map<K, ({DateTime at, Future<Object?> value})> _byKey = {};
  final Map<String, List<K>> _byOwner = {};

  int get length => _byKey.length;

  /// The warm future for [key] if one is young enough, else [start]'s.
  Future<Object?> put(String owner, K key, Future<Object?> Function() start) {
    final existing = _byKey[key];
    if (existing != null && _now().difference(existing.at) < ttl) return existing.value;
    final value = start();
    _byKey[key] = (at: _now(), value: value);
    (_byOwner[owner] ??= []).add(key);
    value.then<void>((_) {}, onError: (Object _) {});
    return value;
  }

  /// Takes the warm response for [key], once, or null when there is none
  /// young enough.
  Future<Object?>? take(K key) {
    final hit = _byKey.remove(key);
    if (hit == null || _now().difference(hit.at) >= ttl) return null;
    return hit.value;
  }

  void drop(String owner) {
    for (final k in _byOwner.remove(owner) ?? const []) {
      _byKey.remove(k);
    }
  }

  void clear() {
    _byKey.clear();
    _byOwner.clear();
  }
}

/// Who wants to know when the BookOrbit caches are cleared (sign-out, account
/// switch), without the service library importing them.
class ForkCacheClears {
  static final List<void Function()> _listeners = [];

  static void listen(void Function() onClear) {
    if (!_listeners.contains(onClear)) _listeners.add(onClear);
  }

  static void run() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}
