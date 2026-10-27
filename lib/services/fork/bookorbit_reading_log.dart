part of '../api_service.dart';

// Fork-owned: what the reading log card needs from BookOrbit's session list.
// The hooks in bookorbit_api_service.dart are in `_itemListeningSessions`
// (`_forkReadingLogPrepare`, `_forkHasPosition`, `_forkOwnDevice`,
// `_forkReadingLogFields`, and the dropped audio-only filter), the
// `_forkFirstSend` check in `logReadingTime`, `_forkBookSeconds` in
// `_localSession` and `_forkReadingStats.clear()` in `clearCaches`. See
// FORK_NOTES.md.

/// BookOrbit's own totals from the last session list fetched for a book:
/// they cover every session, not just the page this client holds.
final Map<String, Map<String, dynamic>?> _forkReadingStats = {};

/// Ebook reading sessions already recorded as this phone's, so the record is
/// written once per session, not on every minute's send.
final Set<String> _forkRememberedReads = {};

/// The remembered own sessions, indexed by start second, for the map last
/// read from preferences.
Map<String, dynamic>? _forkMineFrom;
Map<int, String> _forkMineByStart = const {};

/// Whether a BookOrbit session moves through the book's audio, so its
/// percentage can be turned into a time: audio files, and listening to a
/// narrated EPUB. Reading an ebook and text to speech do not.
bool readingLogHasPosition(Map<String, dynamic> s) {
  final format = s['format'] as String?;
  return format == null || BookOrbitMapper.isAudioFormat(format) || s['sessionType'] == 'listen';
}

/// The device this phone recorded a session on, from the remembered map of
/// `bookId@startedAtIso` to device name, matched on the start second alone:
/// a session merged in from a linked edition carries that edition's book.
String? readingLogOwnDevice(Map<String, dynamic> mine, Object? startedAt) {
  if (!identical(mine, _forkMineFrom)) {
    _forkMineFrom = mine;
    _forkMineByStart = {
      for (final e in mine.entries)
        if (DateTime.tryParse(e.key.substring(e.key.indexOf('@') + 1)) case final at?)
          at.millisecondsSinceEpoch ~/ 1000: '${e.value}',
    };
  }
  final at = DateTime.tryParse(startedAt as String? ?? '');
  return at == null ? null : _forkMineByStart[at.millisecondsSinceEpoch ~/ 1000];
}

/// What the reading log shows beyond Audiobookshelf's session shape.
Map<String, dynamic> readingLogFields(Map<String, dynamic> s, bool ownDevice) => {
      if (s['sessionType'] != null) 'sessionType': s['sessionType'],
      if (s['medium'] != null) 'medium': s['medium'],
      if (s['source'] != null) 'source': s['source'],
      'ownDevice': ownDevice,
      if (s['format'] != null) 'format': (s['format'] as String).toUpperCase(),
      if (s['endProgress'] != null) 'endProgress': s['endProgress'],
      if (s['progressDelta'] != null) 'progressDelta': s['progressDelta'],
    };

extension BookOrbitReadingLog on ApiService {
  /// BookOrbit's totals for [itemId] (sessions, seconds, average, latest
  /// reached), or null on any other server or before its sessions loaded.
  Map<String, dynamic>? readingLogStats(String itemId) {
    final self = this;
    return self is BookOrbitApiService ? _forkReadingStats[self._key(itemId)] : null;
  }
}

extension _ForkBookOrbitReadingLog on BookOrbitApiService {
  /// Keeps the list's totals, and gives a narrated EPUB, which has no audio
  /// files, its narration's length so its sessions get positions. Only a
  /// narration already loaded: fetching one takes seconds on a long book,
  /// which the log should not wait for.
  Future<double> _forkReadingLogPrepare(String bookId, Map<String, dynamic> res, double bookSeconds) async {
    _forkReadingStats[_key(bookId)] = res['stats'] as Map<String, dynamic>?;
    return bookSeconds > 0 ? bookSeconds : (_narrations[_key(bookId)]?.overlay.duration ?? 0);
  }

  /// True the first time an ebook reading session is sent.
  bool _forkFirstSend(String sessionId) => _forkRememberedReads.add(sessionId);

  /// How long the book plays: its audio files, or for a narrated EPUB, which
  /// has none, its narration. Zero when neither is known.
  Future<double> _forkBookSeconds(String bookId, Map<String, dynamic>? manifest) async {
    final audio = manifest == null ? 0.0 : BookOrbitMapper.totalSeconds(manifest);
    if (audio > 0) return audio;
    try {
      return (await _narration(bookId))?.overlay.duration ?? 0;
    } catch (_) {
      return 0;
    }
  }

  bool _forkHasPosition(Map<String, dynamic> s) => readingLogHasPosition(s);

  String? _forkOwnDevice(Map<String, dynamic> mine, Object? startedAt) => readingLogOwnDevice(mine, startedAt);

  Map<String, dynamic> _forkReadingLogFields(Map<String, dynamic> s, bool ownDevice) => readingLogFields(s, ownDevice);
}
