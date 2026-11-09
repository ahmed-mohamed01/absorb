// Fork-owned: the decisions behind the routes BookOrbit leaves open to any
// signed-in client, free of the network so they can be tested. Its activity
// routes only answer its official iOS app. See FORK_NOTES.md.

import 'dart:convert';

/// BookOrbit's `AUDIO_FORMAT_LIST`.
const _audioFormats = {'m4b', 'mp3', 'm4a', 'opus', 'ogg', 'flac'};

/// How many weeks of sessions one Stats load reads. Each costs a request, plus
/// up to [forkBookLookupsPerWeek] more, so a long history fills in over several
/// loads. BookOrbit doesn't rate limit these routes; this keeps one load modest
/// for the server and for any proxy in front of it.
const forkSplitWeeks = 8;

/// How many books in a week have their sessions' kinds looked up.
const forkBookLookupsPerWeek = 4;

typedef ForkIsoWeek = ({int year, int week});
typedef ForkMediaSplit = ({num listening, num reading});

/// One write for `PUT /reading-progress` from the older route's [body].
/// Narration fields stay out when [body] leaves them out, which keeps the
/// marker the server holds; only an explicit null clears it.
/// [editedAt] is when the move was made, for one saved late: a position saved
/// on the server since then stays.
Map<String, dynamic> forkProgressWrite(int fileId, Map<String, dynamic> body, {DateTime? editedAt}) => {
      'fileId': fileId,
      'percentage': body['percentage'],
      if (editedAt != null) 'editedAt': editedAt.toUtc().toIso8601String(),
      if (body['source'] != null) 'kind': body['source'],
      if (body.containsKey('cfi') || body.containsKey('pageNumber'))
        'text': {
          if (body.containsKey('cfi')) 'cfi': body['cfi'],
          if (body.containsKey('pageNumber')) 'page': body['pageNumber'],
        },
      if (body.containsKey('positionSeconds') ||
          body.containsKey('mediaOverlayFragment') ||
          body.containsKey('mediaOverlaySectionIndex'))
        'narration': {
          if (body.containsKey('positionSeconds')) 'seconds': body['positionSeconds'],
          if (body.containsKey('mediaOverlayFragment')) 'fragment': body['mediaOverlayFragment'],
          if (body.containsKey('mediaOverlaySectionIndex')) 'sectionIndex': body['mediaOverlaySectionIndex'],
        },
    };

/// The book a 404 [body] says this one was merged into, if it says so.
String? forkMergedInto(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['errorCode'] != 'BOOK_MERGED') return null;
    return (decoded['errorMeta'] as Map?)?['targetBookId']?.toString();
  } catch (_) {
    return null;
  }
}

/// The last part of a library folder's [path], or [fallback] for a root.
String forkFolderName(Object? path, String fallback) {
  for (final part in '${path ?? ''}'.split('/').reversed) {
    if (part.isNotEmpty) return part;
  }
  return fallback;
}

/// Whether the home screen widget's numbers can be worked out. A failed read
/// would otherwise come out as zeros over what it was showing.
bool forkWidgetStatsUsable(Map<String, dynamic>? stats, Object? progress) => stats != null && progress != null;

/// Whether a session on [format] counts as listening, when its kind isn't
/// known. A session with no file counts as listening: a reading session
/// always has one.
bool forkIsListeningFormat(String? format) {
  final f = format?.trim().toLowerCase() ?? '';
  return f.isEmpty || f == 'unknown' || _audioFormats.contains(f);
}

bool forkIsListeningKind(String kind) => kind == 'listen' || kind == 'tts';

/// Whether a timeline session is listening: its kind when looked up, which
/// tells read along on an EPUB from reading it, otherwise its file's format.
bool forkIsListeningSession(Map<String, dynamic> session) {
  final kind = session['sessionType'];
  return kind is String ? forkIsListeningKind(kind) : forkIsListeningFormat(session['bookFormat'] as String?);
}

/// [time] as a UTC value whose fields read as the clock [offset] from UTC.
DateTime forkAccountTime(DateTime time, Duration offset) => time.toUtc().add(offset);

String forkDayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The ISO year and week of [day], using its calendar date as given.
ForkIsoWeek forkIsoWeek(DateTime day) {
  final date = DateTime.utc(day.year, day.month, day.day);
  final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
  final week = thursday.difference(DateTime.utc(thursday.year)).inDays ~/ 7 + 1;
  return (year: thursday.year, week: week);
}

String forkWeekKey(ForkIsoWeek week) => '${week.year}-${week.week}';

/// The server's UTC weeks an account's [day] falls in, which can be two.
Set<ForkIsoWeek> forkWeeksOfDay(String day, Duration offset) {
  final parsed = DateTime.tryParse(day);
  if (parsed == null) return const {};
  final start = DateTime.utc(parsed.year, parsed.month, parsed.day).subtract(offset);
  return {forkIsoWeek(start), forkIsoWeek(start.add(const Duration(days: 1, seconds: -1)))};
}

/// Every week holding one of the account's active [days], newest first.
List<ForkIsoWeek> forkActiveWeeks(Iterable<String> days, Duration offset) {
  final weeks = {for (final day in days) ...forkWeeksOfDay(day, offset)}.toList();
  weeks.sort((a, b) => a.year != b.year ? b.year.compareTo(a.year) : b.week.compareTo(a.week));
  return weeks;
}

/// Whether [week] is this week or last, where sessions can still land.
bool forkWeekIsRecent(ForkIsoWeek week, DateTime now) {
  final utc = now.toUtc();
  return week == forkIsoWeek(utc) || week == forkIsoWeek(utc.subtract(const Duration(days: 7)));
}

/// The weeks one load reads, newest first: recent ones, then any [isOutdated]
/// (never read, or read before a session changed), up to [forkSplitWeeks].
List<ForkIsoWeek> forkWeeksToLoad(List<ForkIsoWeek> active, bool Function(ForkIsoWeek) isOutdated, DateTime now) =>
    active.where((w) => forkWeekIsRecent(w, now) || isOutdated(w)).take(forkSplitWeeks).toList();

/// The books in a week's [sessions] worth asking about: those on a book format,
/// which might be read along, longest first.
List<String> forkBooksToLookUp(Iterable<Map<String, dynamic>> sessions) {
  final seconds = <String, num>{};
  for (final s in sessions) {
    if (forkIsListeningFormat(s['bookFormat'] as String?)) continue;
    final id = '${s['bookId']}';
    seconds[id] = (seconds[id] ?? 0) + ((s['durationSeconds'] as num?) ?? 0);
  }
  final ids = seconds.keys.toList()..sort((a, b) => seconds[b]!.compareTo(seconds[a]!));
  return ids.take(forkBookLookupsPerWeek).toList();
}

/// [sessions] with the kind and file from [rows], `/books/:id/sessions` rows.
List<Map<String, dynamic>> forkWithSessionDetail(
    Iterable<Map<String, dynamic>> sessions, Iterable<Map<String, dynamic>> rows) {
  final byId = {for (final r in rows) r['id']: r};
  return [
    for (final s in sessions)
      if (byId[s['sessionId']] case final row?)
        {...s, 'sessionType': row['sessionType'], 'bookFileId': row['bookFileId']}
      else
        s,
  ];
}

/// A session's seconds on each of the account's days it touches, shared by
/// time so the parts add up to [seconds].
Map<String, num> forkSecondsByDay(DateTime start, DateTime end, num seconds, Duration offset) {
  final from = forkAccountTime(start, offset);
  final to = forkAccountTime(end, offset);
  final span = to.difference(from).inSeconds;
  if (span <= 0 || forkDayKey(from) == forkDayKey(to)) return {forkDayKey(from): seconds};
  final out = <String, num>{};
  var at = from;
  while (at.isBefore(to)) {
    final midnight = DateTime.utc(at.year, at.month, at.day + 1);
    final until = midnight.isBefore(to) ? midnight : to;
    out[forkDayKey(at)] = seconds * until.difference(at).inSeconds / span;
    at = until;
  }
  return out;
}

/// The readable [sessions], each once.
Iterable<({Map<String, dynamic> session, DateTime start, DateTime end, num seconds})> _uniqueSessions(
    Iterable<Map<String, dynamic>> sessions) sync* {
  final seen = <Object?>{};
  for (final s in sessions) {
    if (!seen.add(s['sessionId'])) continue;
    final start = DateTime.tryParse(s['startedAt'] as String? ?? '');
    final end = DateTime.tryParse(s['endedAt'] as String? ?? '');
    if (start == null || end == null) continue;
    yield (session: s, start: start, end: end, seconds: (s['durationSeconds'] as num?) ?? 0);
  }
}

/// One week's listening and reading by day, and its time by book. Kept so a
/// finished week need not be read again.
class ForkWeekSplit {
  final Map<String, num> listen;
  final Map<String, num> read;

  /// Book id to its title (`t`) and seconds (`s`).
  final Map<String, Map<String, dynamic>> books;

  const ForkWeekSplit(this.listen, this.read, this.books);

  /// The server answers [week] with every session overlapping it, so one
  /// crossing Monday 00:00 UTC comes back in two weeks. It counts in the week
  /// it started.
  factory ForkWeekSplit.fromSessions(Iterable<Map<String, dynamic>> sessions, Duration offset, ForkIsoWeek week) {
    final listen = <String, num>{}, read = <String, num>{};
    final books = <String, Map<String, dynamic>>{};
    for (final s in _uniqueSessions(sessions)) {
      if (s.seconds <= 0 || forkIsoWeek(s.start.toUtc()) != week) continue;
      final target = forkIsListeningSession(s.session) ? listen : read;
      forkSecondsByDay(s.start, s.end, s.seconds, offset).forEach((day, part) {
        target[day] = (target[day] ?? 0) + part;
      });
      final id = '${s.session['bookId']}';
      books[id] = {'t': s.session['bookTitle'], 's': ((books[id]?['s'] as num?) ?? 0) + s.seconds};
    }
    return ForkWeekSplit(listen, read, books);
  }

  factory ForkWeekSplit.fromJson(Map<String, dynamic> json) => ForkWeekSplit(
        (json['l'] as Map? ?? const {}).cast<String, num>(),
        (json['r'] as Map? ?? const {}).cast<String, num>(),
        (json['b'] as Map? ?? const {}).map((k, v) => MapEntry('$k', (v as Map).cast<String, dynamic>())),
      );

  Map<String, dynamic> toJson() => {'l': listen, 'r': read, 'b': books};
}

typedef ForkWeeksMerged = ({Map<String, num> listen, Map<String, num> read, Map<String, dynamic> items});

/// All [weeks] together: listening and reading by day, and each book's total in
/// the Stats screen's item shape.
ForkWeeksMerged forkMergeWeeks(Iterable<ForkWeekSplit> weeks) {
  final listen = <String, num>{}, read = <String, num>{};
  final items = <String, dynamic>{};
  void add(Map<String, num> into, Map<String, num> from) =>
      from.forEach((day, seconds) => into[day] = (into[day] ?? 0) + seconds);
  for (final week in weeks) {
    add(listen, week.listen);
    add(read, week.read);
    week.books.forEach((id, book) {
      final previous = (items[id] as Map?)?['timeListening'] as num? ?? 0;
      items[id] = {
        'id': id,
        'timeListening': previous + ((book['s'] as num?) ?? 0),
        'mediaMetadata': {'title': book['t'], 'authorName': null},
      };
    });
  }
  return (listen: listen, read: read, items: items);
}

/// The ids of the books most time went to, the ones the Stats screen lists.
List<String> forkTopBookIds(Map<String, dynamic> items, {int count = 5}) {
  num seconds(String id) => (items[id] as Map)['timeListening'] as num;
  return (items.keys.toList()..sort((a, b) => seconds(b).compareTo(seconds(a)))).take(count).toList();
}

/// One of the account's days' sessions in the shape of BookOrbit's activity day.
List<Map<String, dynamic>> forkDaySessions(Iterable<Map<String, dynamic>> sessions, String day, Duration offset) => [
      for (final s in _uniqueSessions(sessions))
        if (forkSecondsByDay(s.start, s.end, s.seconds, offset)[day] case final onDay?)
          {
            'id': s.session['sessionId'],
            'bookId': s.session['bookId'],
            'bookFileId': s.session['bookFileId'],
            'bookTitle': s.session['bookTitle'],
            'format': s.session['bookFormat'],
            'mediaBucket': forkIsListeningSession(s.session) ? 'listening' : 'reading',
            'sourceBucket': s.session['bookSource'],
            'startedAt': s.session['startedAt'],
            'endedAt': s.session['endedAt'],
            'durationOnDaySeconds': onDay,
          },
    ];

/// Seconds by listening and reading from a row's `byFormat`.
ForkMediaSplit forkFormatSplit(Map? byFormat) {
  num listening = 0, reading = 0;
  byFormat?.forEach((format, seconds) {
    if (seconds is! num) return;
    if (forkIsListeningFormat('$format')) {
      listening += seconds;
    } else {
      reading += seconds;
    }
  });
  return (listening: listening, reading: reading);
}

/// The hour rows the Stats screen charts, from `peak-hours`.
List<Map<String, dynamic>> forkHourRows(List<dynamic>? peakHours) => [
      for (final h in (peakHours ?? const []).whereType<Map>())
        () {
          final split = forkFormatSplit(h['byFormat'] as Map?);
          return <String, dynamic>{'hour': h['hour'], 'listening': split.listening, 'reading': split.reading};
        }(),
    ];

/// Seconds by listening and reading across all of `peak-hours`.
ForkMediaSplit forkHoursTotal(List<dynamic>? peakHours) {
  num listening = 0, reading = 0;
  for (final row in forkHourRows(peakHours)) {
    listening += row['listening'] as num;
    reading += row['reading'] as num;
  }
  return (listening: listening, reading: reading);
}

num? _median(List<num> values) {
  if (values.isEmpty) return null;
  final sorted = values.toList()..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// The typical session lengths and progress from `reading-pace`.
({num? session, num? listen, num? read, num? progress}) forkPaceMedians(List<dynamic>? points) {
  final all = <num>[], listen = <num>[], read = <num>[], progress = <num>[];
  for (final p in (points ?? const []).whereType<Map>()) {
    final seconds = p['durationSeconds'] as num?;
    if (seconds != null) {
      all.add(seconds);
      (forkIsListeningFormat(p['format'] as String?) ? listen : read).add(seconds);
    }
    final delta = p['progressDelta'] as num?;
    if (delta != null) progress.add(delta);
  }
  return (session: _median(all), listen: _median(listen), read: _median(read), progress: _median(progress));
}

/// The numbers Year in Review shows for [year], from `daily-reading` [rows].
Map<String, dynamic> forkYearStats({
  required int year,
  required List<dynamic> rows,
  required ForkMediaSplit split,
  required int finished,
}) {
  final prefix = '$year-';
  num sessions = 0;
  var activeDays = 0;
  final byMonth = List<num>.filled(12, 0);
  for (final d in rows.whereType<Map>()) {
    final day = d['day'] as String? ?? '';
    if (!day.startsWith(prefix)) continue;
    final seconds = (d['readingSeconds'] as num?) ?? 0;
    sessions += (d['eventsCount'] as num?) ?? 0;
    if (seconds > 0) activeDays++;
    final month = DateTime.tryParse(day)?.month;
    if (month != null) byMonth[month - 1] += seconds;
  }
  var topMonth = -1;
  for (var i = 0; i < 12; i++) {
    if (byMonth[i] > 0 && (topMonth < 0 || byMonth[i] > byMonth[topMonth])) topMonth = i;
  }
  return {
    'totalListeningTime': split.listening,
    'bookOrbitReadingTime': split.reading,
    'bookOrbitActiveDays': activeDays,
    'totalListeningSessions': sessions,
    'numBooksFinished': finished,
    if (topMonth >= 0) 'mostListenedMonth': {'month': topMonth},
  };
}
