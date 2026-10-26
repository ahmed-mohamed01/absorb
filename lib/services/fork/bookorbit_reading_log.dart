part of '../api_service.dart';

// Fork-owned: what the reading log card needs from BookOrbit's session list.
// The hooks in bookorbit_api_service.dart are in `_itemListeningSessions`
// (`_forkReadingLogPrepare`, `_forkHasPosition`, `_forkOwnDevice`,
// `_forkReadingLogFields`, and the dropped audio-only filter) and the
// `_rememberSessionDevice` call in `logReadingTime`. See FORK_NOTES.md.

/// BookOrbit's own totals from the last session list fetched for a book:
/// they cover every session, not just the page this client holds.
final Map<String, Map<String, dynamic>?> _forkReadingStats = {};

/// The remembered own sessions, indexed by start second, for the map last
/// read from preferences.
Map<String, Map<String, String>>? _forkMineFrom;
Map<int, Map<String, String>> _forkMineByStart = const {};

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
  /// files, its narration's length so its sessions get positions.
  Future<double> _forkReadingLogPrepare(String bookId, Map<String, dynamic> res, double bookSeconds) async {
    _forkReadingStats[_key(bookId)] = res['stats'] as Map<String, dynamic>?;
    if (bookSeconds > 0) return bookSeconds;
    try {
      return (await _narration(bookId))?.overlay.duration ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Audio, and listening to a narrated EPUB, move through the book's audio;
  /// reading an ebook does not.
  bool _forkHasPosition(Map<String, dynamic> s) {
    final format = s['format'] as String?;
    return format == null ||
        BookOrbitMapper.isAudioFormat(format) ||
        s['sessionType'] == 'listen' ||
        s['sessionType'] == 'tts';
  }

  /// The device this phone recorded the session on, matched on the start
  /// time alone: a session merged in from a linked edition carries that
  /// edition's book, not the one asked for.
  Map<String, String>? _forkOwnDevice(Map<String, Map<String, String>> mine, Object? startedAt) {
    if (!identical(mine, _forkMineFrom)) {
      _forkMineFrom = mine;
      _forkMineByStart = {
        for (final e in mine.entries)
          if (DateTime.tryParse(e.key.substring(e.key.indexOf('@') + 1)) case final at?)
            at.millisecondsSinceEpoch ~/ 1000: e.value,
      };
    }
    final at = DateTime.tryParse(startedAt as String? ?? '');
    return at == null ? null : _forkMineByStart[at.millisecondsSinceEpoch ~/ 1000];
  }

  /// What the reading log card shows beyond Audiobookshelf's session shape.
  Map<String, dynamic> _forkReadingLogFields(Map<String, dynamic> s, bool ownDevice) => {
        if (s['sessionType'] != null) 'sessionType': s['sessionType'],
        if (s['medium'] != null) 'medium': s['medium'],
        if (s['source'] != null) 'source': s['source'],
        'ownDevice': ownDevice,
        if (s['format'] != null) 'format': (s['format'] as String).toUpperCase(),
        if (s['endProgress'] != null) 'endProgress': s['endProgress'],
        if (s['progressDelta'] != null) 'progressDelta': s['progressDelta'],
      };
}
