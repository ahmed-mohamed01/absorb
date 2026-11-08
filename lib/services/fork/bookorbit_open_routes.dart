part of '../api_service.dart';

// Fork-owned: the routes open to any signed-in client, in place of the ones
// BookOrbit 3.7 keeps for its official iOS app (a 403 APP_ATTEST_REQUIRED for
// everyone else). The service hooks are documented in FORK_NOTES.md.

/// Weeks of sessions already read, per account: `zone`, `generation` (raised
/// when a session changes) and `weeks`, each with the generation it was read in.
const _forkStatsStoreKey = 'fork_stats_weeks';

extension ForkOpenRoutes on BookOrbitApiService {
  static const _statsWait = Duration(seconds: 45);

  /// A book or route that isn't there, or isn't this account's, will stay that
  /// way, unlike a rate limit or an outage.
  static bool _forkStaysRefused(Object e) => e is _BoHttpError && (e.status == 403 || e.status == 404);

  /// Only a server known to lack `reading-progress` takes the older route, which
  /// a 3.7 server refuses. Empty features mean `/app-info` couldn't be read.
  Future<bool> _forkHasReadingProgress() async {
    final features = await _features();
    return features.isEmpty || features.contains('reading-progress');
  }

  /// Saves one file's place. [body] is in the shape of the older route.
  Future<void> _forkSaveFileProgress(String fileId, Map<String, dynamic> body) async {
    if (!await _forkHasReadingProgress()) {
      await _boPost('/books/files/$fileId/progress', body);
      return;
    }
    await _boPut('/reading-progress', {
      'writes': [forkProgressWrite(int.parse(fileId), body)],
    });
  }

  Future<void> _forkClearFileProgress(String fileId) async {
    await _boDelete(await _forkHasReadingProgress() ? '/reading-progress/$fileId' : '/books/files/$fileId/progress');
  }

  /// One page of a Smart Scope's books. BookOrbit's GET route is a wrapper
  /// around this query.
  Future<Map<String, dynamic>> _forkScopePage(String scopeId, int page, int size) async =>
      await _boPost('/smart-scopes/$scopeId/books/query', {
        'sort': const <Object>[],
        'pagination': {'page': page, 'size': size},
      }) as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>?> _forkScopeItems(String scopeId, int page, int size) async {
    try {
      final res = await _forkScopePage(scopeId, page, size);
      return (res['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((card) => _cardItem(card))
          .toList();
    } catch (e) {
      debugPrint('[BookOrbit] Smart Scope $scopeId page $page failed: $e');
      return null;
    }
  }

  /// Where a Book Dock file can go, from the libraries this account can see.
  Future<List<BookDockDestination>> _forkDockDestinations() async {
    if (!await _can('library_upload')) return const [];
    final raw = await _boGet('/libraries') as List<dynamic>;
    return [
      for (final lib in raw.whereType<Map>())
        for (final folder in (lib['folders'] as List<dynamic>? ?? const []).whereType<Map>())
          BookDockDestination(
            libraryId: '${lib['id']}',
            libraryName: '${lib['name'] ?? ''}',
            folderId: '${folder['id']}',
            folderName: forkFolderName(folder['path'], '${lib['name'] ?? ''}'),
          ),
    ];
  }

  // The cache keys below start `activity-day-` so `_forgetListeningStats`
  // drops them with the rest after a session changes.

  /// BookOrbit's time per account day. Unlike `reading-heatmap`, which stops at
  /// UTC's today, this has today for an account ahead of UTC.
  Future<List<dynamic>> _forkDailyRows() => _cached(
        'activity-day-daily',
        const Duration(minutes: 1),
        () async => await _boGet('/user-statistics/daily-reading', {'days': 3650}, _statsWait) as List<dynamic>,
      );

  /// The account's zone name and distance from UTC. BookOrbit uses UTC until
  /// the account sets one. Null name when the account couldn't be read.
  Future<({String? name, Duration offset})> _forkAccountZone() async {
    try {
      final name = (await _mySettings())['timezone'] as String? ?? 'UTC';
      return (name: name, offset: await forkAccountOffset(name));
    } catch (e) {
      debugPrint('[BookOrbit] Stats: account zone failed: $e');
      return (name: null, offset: DateTime.now().timeZoneOffset);
    }
  }

  /// A book's sessions started between two times, as `/books/:id/sessions` has them.
  Future<List<Map<String, dynamic>>> _forkBookSessions(String bookId, DateTime from, DateTime to) async {
    final res = await _boGet('/books/$bookId/sessions', {
      'page': 1,
      'pageSize': 100,
      'sortBy': 'startedAt',
      'sortDir': 'asc',
      'dateFrom': BookOrbitApiService._iso(from.subtract(const Duration(minutes: 1))),
      'dateTo': BookOrbitApiService._iso(to.add(const Duration(minutes: 1))),
    }, _statsWait) as Map<String, dynamic>;
    return (res['items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
  }

  /// One UTC week's sessions, as the server splits them, with each session's
  /// real kind for the books that might be read along. `complete` is false when
  /// a kind couldn't be read, so the week isn't worth keeping.
  Future<({List<Map<String, dynamic>> sessions, bool complete})> _forkWeekSessions(ForkIsoWeek week) async {
    final recent = forkWeekIsRecent(week, DateTime.now());
    final key = 'activity-day-week-${forkWeekKey(week)}';
    final read = await _cached(
      key,
      recent ? const Duration(minutes: 1) : const Duration(hours: 6),
      () async {
        final res = await _boGet('/user-statistics/session-timeline', {'year': week.year, 'week': week.week}, _statsWait)
            as Map<String, dynamic>;
        var sessions = (res['items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
        var complete = true;
        for (final bookId in forkBooksToLookUp(sessions)) {
          final starts = sessions
              .where((s) => '${s['bookId']}' == bookId)
              .map((s) => DateTime.tryParse(s['startedAt'] as String? ?? ''))
              .whereType<DateTime>()
              .toList()
            ..sort();
          if (starts.isEmpty) continue;
          try {
            sessions = forkWithSessionDetail(sessions, await _forkBookSessions(bookId, starts.first, starts.last));
          } catch (e) {
            if (!_forkStaysRefused(e)) complete = false;
            debugPrint('[BookOrbit] Stats: sessions of book $bookId failed: $e');
          }
        }
        return (sessions: sessions, complete: complete);
      },
    );
    // Not held for hours: the missing kinds may be there on the next load.
    if (!read.complete) BookOrbitApiService._recent.remove(_key(key));
    return read;
  }

  /// One of the account's days' sessions: it can touch two of the server's weeks.
  Future<Map<String, dynamic>> _forkActivityDay(String day) async {
    final offset = (await _forkAccountZone()).offset;
    final weeks = await Future.wait(forkWeeksOfDay(day, offset).map(_forkWeekSessions));
    return {'sessions': forkDaySessions(weeks.expand((w) => w.sessions), day, offset)};
  }

  Future<Map<String, dynamic>> _forkReadStatsStore() async {
    final raw = await ScopedPrefs.getString(_forkStatsStoreKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// A session changed: every kept week may be out of date. They still count
  /// until they've been read again, so totals don't drop while that happens.
  Future<void> _forkStatsSessionsChanged() async {
    final store = await _forkReadStatsStore();
    if (store.isEmpty) return;
    store['generation'] = ((store['generation'] as num?)?.toInt() ?? 0) + 1;
    await ScopedPrefs.setString(_forkStatsStoreKey, jsonEncode(store));
  }

  /// Listening and reading by day and time by book, from weeks of sessions. A
  /// long history fills in over a few loads, newest first, within the rate
  /// limit. Returns whether a read failed, so the result isn't kept for long.
  Future<({ForkWeeksMerged merged, bool failed})> _forkSplitDays(Iterable<String> days, Duration offset, String? zone) async {
    final store = await _forkReadStatsStore();
    final sameZone = store['zone'] == '$zone@${offset.inMinutes}';
    final kept = sameZone ? (store['weeks'] as Map?)?.cast<String, dynamic>() ?? {} : <String, dynamic>{};
    final generation = (store['generation'] as num?)?.toInt() ?? 0;

    final active = forkActiveWeeks(days, offset);
    bool outdated(ForkIsoWeek week) => (kept[forkWeekKey(week)] as Map?)?['g'] != generation;
    final fresh = <String, ForkWeekSplit>{};
    var failed = false;
    for (final week in forkWeeksToLoad(active, outdated, DateTime.now())) {
      // One refusal is likely the rate limit: asking for more only adds to it.
      if (failed) break;
      try {
        final read = await _forkWeekSessions(week);
        final split = ForkWeekSplit.fromSessions(read.sessions, offset);
        fresh[forkWeekKey(week)] = split;
        if (read.complete) {
          kept[forkWeekKey(week)] = {...split.toJson(), 'g': generation};
        } else {
          failed = true;
        }
      } catch (e) {
        failed = true;
        debugPrint('[BookOrbit] Stats: week ${forkWeekKey(week)} failed: $e');
      }
    }

    // Raised while this ran: what was just read may already be out of date.
    final latest = ((await _forkReadStatsStore())['generation'] as num?)?.toInt() ?? generation;
    await ScopedPrefs.setString(
      _forkStatsStoreKey,
      jsonEncode({'zone': '$zone@${offset.inMinutes}', 'generation': latest, 'weeks': kept}),
    );
    final merged = forkMergeWeeks([
      for (final week in active)
        if (fresh[forkWeekKey(week)] case final split?)
          split
        else if (kept[forkWeekKey(week)] case final Map<String, dynamic> json)
          ForkWeekSplit.fromJson(json),
    ]);
    return (merged: merged, failed: failed);
  }

  /// The timeline has no authors, so the books the screen lists get theirs here.
  Future<void> _forkAddAuthors(Map<String, dynamic> items) async {
    await Future.wait(forkTopBookIds(items).map((id) async {
      try {
        final author = await _cached('stats-author-$id', const Duration(hours: 6), () async {
          final detail = await _boGet('/books/$id') as Map<String, dynamic>;
          return (detail['authors'] as List<dynamic>? ?? const [])
              .map((a) => a is Map ? '${a['name'] ?? ''}' : '$a')
              .where((a) => a.isNotEmpty)
              .join(', ');
        });
        ((items[id] as Map)['mediaMetadata'] as Map)['authorName'] = author;
      } catch (e) {
        debugPrint('[BookOrbit] Stats: author of book $id failed: $e');
      }
    }));
  }

  /// The Stats screen's numbers. Only the days are required. BookOrbit's open
  /// routes don't keep listening and reading apart by day, so that split comes
  /// from weeks of sessions.
  Future<Map<String, dynamic>> _forkListeningStats() async {
    final rows = await _forkDailyRows();
    final total = <String, num>{};
    for (final d in rows.whereType<Map>()) {
      final seconds = (d['readingSeconds'] as num?) ?? 0;
      if (d['day'] is String && seconds > 0) total[d['day'] as String] = seconds;
    }

    var failed = false;
    void noteFailure(String what, Object e) {
      debugPrint('[BookOrbit] Stats: $what failed: $e');
      if (!_forkStaysRefused(e)) failed = true;
    }

    Future<T?> optional<T>(String path, [Map<String, dynamic>? query]) async {
      try {
        return await _boGet(path, query, _statsWait) as T?;
      } catch (e) {
        noteFailure(path, e);
        return null;
      }
    }

    Future<int?> goal() async {
      try {
        final res = await _boPost('/dashboard/widgets/batch', {
          'widgets': ['reading-goal'],
        }) as Map<String, dynamic>;
        for (final item in (res['items'] as List<dynamic>? ?? const []).whereType<Map>()) {
          if (item['type'] == 'reading-goal') return ((item['data'] as Map?)?['goalBooks'] as num?)?.toInt();
        }
      } catch (e) {
        noteFailure('reading goal', e);
      }
      return null;
    }

    final (peakHours, sources, finished, genres, paceRows, latency, summary, goalBooks) = await (
      optional<List<dynamic>>('/user-statistics/peak-hours', {'days': 365}),
      optional<Map>('/user-statistics/reading-source-distribution', {'days': 365}),
      optional<List<dynamic>>('/user-statistics/completion-timeline', {'days': 1825}),
      optional<List<dynamic>>('/user-statistics/genre-reading-time', {'days': 365}),
      optional<List<dynamic>>('/user-statistics/reading-pace', {'days': 365}),
      optional<Map>('/user-statistics/completion-latency', {'days': 1825}),
      optional<Map>('/user-statistics/summary'),
      goal(),
    ).wait;
    final pace = forkPaceMedians(paceRows);

    final zone = await _forkAccountZone();
    final split = await _forkSplitDays(total.keys, zone.offset, zone.name);
    if (split.failed) failed = true;
    await _forkAddAuthors(split.merged.items);

    // Short of something that may answer next time: ask again on the next load.
    if (failed) BookOrbitApiService._recent.remove(_key('listening-stats'));

    return {
      'totalTime': total.values.fold<num>(0, (sum, v) => sum + v),
      'items': split.merged.items,
      'days': total,
      'today': total[forkDayKey(forkAccountTime(DateTime.now(), zone.offset))] ?? 0,
      'recentSessions': const [],
      'bookOrbit': {
        if (zone.name != null) 'timezone': zone.name,
        'listenDays': split.merged.listen,
        'readDays': split.merged.read,
        'hours': forkHourRows(peakHours),
        'sources': [
          for (final s in (sources?['slices'] as List<dynamic>? ?? const []).whereType<Map>())
            if (((s['readingSeconds'] as num?) ?? 0) > 0) {'bucket': s['bucket'], 'time': s['readingSeconds']},
        ],
        'finishedMonths': [
          for (final m in (finished ?? const []).whereType<Map>())
            {'year': m['year'], 'month': m['month'], 'count': m['count'] ?? 0},
        ],
        'genres': [
          for (final g in (genres ?? const []).whereType<Map>()) {'genre': g['genre'], 'time': g['readingSeconds'] ?? 0},
        ],
        'medianSession': pace.session,
        'medianListen': pace.listen,
        'medianRead': pace.read,
        'medianProgress': pace.progress,
        'medianDaysToFinish': latency?['medianDays'],
        'started': summary?['startedBooks'],
        'inProgress': summary?['inProgressBooks'],
        'completed': summary?['completedBooks'],
        'meanProgress': summary?['meanProgressPercent'],
        'goalBooks': goalBooks,
      },
    };
  }

  /// Year in Review. `peak-hours` only counts back from today, so a past
  /// year's split is the time since it began less the time since it ended.
  Future<Map<String, dynamic>> _forkYearStats(int year) async {
    final now = DateTime.now();
    if (year > now.year) return const {};
    int daysSince(int from) => (now.difference(DateTime(from)).inDays + 1).clamp(1, 3650);
    Future<ForkMediaSplit> since(int from) async => forkHoursTotal(
        await _boGet('/user-statistics/peak-hours', {'days': daysSince(from)}, _statsWait) as List<dynamic>);

    final fromStart = await since(year);
    final ForkMediaSplit fromEnd = year < now.year ? await since(year + 1) : (listening: 0, reading: 0);
    var finished = 0;
    try {
      final months =
          await _boGet('/user-statistics/completion-timeline', {'days': daysSince(year)}) as List<dynamic>;
      for (final m in months.whereType<Map>()) {
        if (m['year'] == year) finished += ((m['count'] as num?) ?? 0).toInt();
      }
    } catch (e) {
      debugPrint('[BookOrbit] Finished books for $year failed: $e');
    }
    return forkYearStats(
      year: year,
      rows: await _forkDailyRows(),
      split: (
        listening: math.max<num>(0, fromStart.listening - fromEnd.listening),
        reading: math.max<num>(0, fromStart.reading - fromEnd.reading),
      ),
      finished: finished,
    );
  }

  /// The file and kind of one session, which the timeline leaves out. Changing
  /// a session's length logs it again against them.
  Future<({String? fileId, bool reading})?> _forkSessionDetail(String bookId, int id, int startedAtMs) async {
    final at = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
    for (final row in await _forkBookSessions(bookId, at, at)) {
      if (row['id'] != id) continue;
      final kind = row['sessionType'] as String?;
      return (
        fileId: row['bookFileId'] == null ? null : '${row['bookFileId']}',
        reading: kind == null ? !forkIsListeningFormat(row['format'] as String?) : !forkIsListeningKind(kind),
      );
    }
    return null;
  }
}
