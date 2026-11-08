import 'package:flutter/services.dart';

// Fork-owned: how far an account's time zone is from UTC. See FORK_NOTES.md.

const _channel = MethodChannel('com.absorb.time_zone');

/// [zone]'s distance from UTC right now, from the phone's zone data. BookOrbit
/// splits days by the account's zone, which can differ from the phone's. Where
/// the phone can't say, UTC is exact and anything else takes the phone's own.
Future<Duration> forkAccountOffset(String zone) async {
  if (zone == 'UTC') return Duration.zero;
  try {
    final r = await _channel.invokeMapMethod<String, dynamic>('compare', {'other': zone});
    final seconds = r?['otherOffsetSeconds'] as int?;
    if (seconds != null) return Duration(seconds: seconds);
  } catch (_) {}
  return DateTime.now().timeZoneOffset;
}
