import 'dart:convert';

import 'package:absorb/services/fork/open_routes_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('forkProgressWrite', () {
    test('groups an ebook save, without inventing narration fields', () {
      final write = forkProgressWrite(7, {'percentage': 42.0, 'cfi': 'epubcfi(/6/4)'});
      expect(write, {
        'fileId': 7,
        'percentage': 42.0,
        'text': {'cfi': 'epubcfi(/6/4)'},
      });
    });

    test('keeps a narration save and its explicit nulls', () {
      final write = forkProgressWrite(7, {
        'percentage': 10,
        'positionSeconds': 90.5,
        'mediaOverlayFragment': null,
        'mediaOverlaySectionIndex': 2,
        'source': 'narration',
      });
      expect(write['kind'], 'narration');
      expect(write['narration'], {'seconds': 90.5, 'fragment': null, 'sectionIndex': 2});
      expect(write.containsKey('text'), isFalse);
    });

    test('says when a late save was made, in UTC, and only then', () {
      final at = DateTime.utc(2026, 11, 8, 10);
      expect(forkProgressWrite(1, {'percentage': 5}, editedAt: at)['editedAt'], '2026-11-08T10:00:00.000Z');
      expect(forkProgressWrite(1, {'percentage': 5}).containsKey('editedAt'), isFalse);
    });

    test('sends a page number as text', () {
      expect(forkProgressWrite(1, {'percentage': 5, 'pageNumber': 12})['text'], {'page': 12});
    });
  });

  group('forkIsListeningFormat', () {
    test('audio formats and sessions with no file are listening', () {
      for (final f in ['M4B', 'mp3', 'flac', 'UNKNOWN', '', null]) {
        expect(forkIsListeningFormat(f), isTrue, reason: '$f');
      }
    });

    test('book formats are reading', () {
      for (final f in ['epub', 'PDF', 'cbz']) {
        expect(forkIsListeningFormat(f), isFalse, reason: f);
      }
    });
  });

  group('forkIsoWeek', () {
    test('matches known ISO weeks, across year ends', () {
      expect(forkIsoWeek(DateTime.utc(2026, 11, 8)), (year: 2026, week: 45));
      expect(forkIsoWeek(DateTime.utc(2021, 1, 3)), (year: 2020, week: 53));
      expect(forkIsoWeek(DateTime.utc(2024, 12, 30)), (year: 2025, week: 1));
    });
  });

  const tokyo = Duration(hours: 9);
  const hawaii = Duration(hours: -10);

  test('forkMergedInto reads where a merged book went, and nothing else', () {
    expect(
        forkMergedInto('{"errorCode":"BOOK_MERGED","errorMeta":{"targetBookId":2}}'), '2');
    expect(forkMergedInto('{"message":"Book 1 not found"}'), isNull);
    expect(forkMergedInto('{"errorCode":"OTHER","errorMeta":{"targetBookId":2}}'), isNull);
    expect(forkMergedInto('not json'), isNull);
  });

  test('forkFolderName is the last part of the path, or the fallback at a root', () {
    expect(forkFolderName('/data/books/audio/', 'Lib'), 'audio');
    expect(forkFolderName('/', 'Lib'), 'Lib');
    expect(forkFolderName(null, 'Lib'), 'Lib');
  });

  test('forkWidgetStatsUsable needs both reads', () {
    expect(forkWidgetStatsUsable({'today': 0}, const []), isTrue);
    expect(forkWidgetStatsUsable(null, const []), isFalse);
    expect(forkWidgetStatsUsable({'today': 0}, null), isFalse);
  });

  test('forkAccountTime reads the clock of the offset, whatever the phone says', () {
    final t = forkAccountTime(DateTime.utc(2026, 11, 8, 20), tokyo);
    expect(forkDayKey(t), '2026-11-09');
    expect(t.hour, 5);
  });

  group('weeks', () {
    test('a day ahead of UTC can start in the UTC week before', () {
      // Monday 2026-11-09 in Tokyo starts on Sunday in UTC, the week before.
      expect(forkWeeksOfDay('2026-11-09', tokyo), {(year: 2026, week: 45), (year: 2026, week: 46)});
      expect(forkWeeksOfDay('2026-11-09', Duration.zero), {(year: 2026, week: 46)});
    });

    test('a day behind UTC can end in the UTC week after', () {
      // Sunday 2026-11-08 in Hawaii ends on Monday in UTC.
      expect(forkWeeksOfDay('2026-11-08', hawaii), {(year: 2026, week: 45), (year: 2026, week: 46)});
    });

    test('forkActiveWeeks lists each week once, newest first, with no cap', () {
      final weeks = forkActiveWeeks(['2026-11-01', '2026-11-08', '2026-11-07', 'junk', '2026-10-01'], Duration.zero);
      expect(weeks, [(year: 2026, week: 45), (year: 2026, week: 44), (year: 2026, week: 40)]);
    });

    test('forkWeeksToLoad takes recent weeks and outdated ones, newest first, up to the cap', () {
      final now = DateTime.utc(2026, 11, 8);
      final active = [for (var w = 45; w > 25; w--) (year: 2026, week: w)];
      final all = forkWeeksToLoad(active, (_) => true, now);
      expect(all, hasLength(forkSplitWeeks));
      expect(all.first, (year: 2026, week: 45));
      expect(forkWeeksToLoad(active, (_) => false, now), [(year: 2026, week: 45), (year: 2026, week: 44)]);
      final next = forkWeeksToLoad(active, (w) => w.week == 30, now);
      expect(next.last, (year: 2026, week: 30));
    });
  });

  group('forkSecondsByDay', () {
    test('a session inside one account day stays whole', () {
      final start = DateTime.utc(2026, 11, 8, 10);
      expect(forkSecondsByDay(start, start.add(const Duration(hours: 1)), 3000, Duration.zero), {'2026-11-08': 3000});
    });

    test('a session past midnight is shared by time and adds up', () {
      final parts = forkSecondsByDay(DateTime.utc(2026, 11, 8, 23), DateTime.utc(2026, 11, 9, 1), 3600, Duration.zero);
      expect(parts, {'2026-11-08': 1800, '2026-11-09': 1800});
    });

    test('midnight is the account zone’s, not UTC’s', () {
      final start = DateTime.utc(2026, 11, 8, 14);
      final end = DateTime.utc(2026, 11, 8, 16);
      expect(forkSecondsByDay(start, end, 3600, tokyo), {'2026-11-08': 1800, '2026-11-09': 1800});
      expect(forkSecondsByDay(start, end, 3600, Duration.zero), {'2026-11-08': 3600});
    });
  });

  Map<String, dynamic> session(int id, String? format, {int hour = 10, num seconds = 600, String? kind}) => {
        'sessionId': id,
        'bookId': id * 10,
        'bookTitle': 'Book $id',
        'bookFormat': format,
        'bookSource': 'android',
        'startedAt': DateTime.utc(2026, 11, 8, hour).toIso8601String(),
        'endedAt': DateTime.utc(2026, 11, 8, hour, 20).toIso8601String(),
        'durationSeconds': seconds,
        'sessionType': ?kind,
      };

  const week45 = (year: 2026, week: 45);
  const week46 = (year: 2026, week: 46);

  group('ForkWeekSplit', () {
    test('a session crossing into the next week counts once, in the week it started', () {
      // Sunday 23:30 to Monday 00:30 UTC: the server returns it for both weeks.
      final crossing = {
        ...session(1, 'm4b', seconds: 3600),
        'startedAt': DateTime.utc(2026, 11, 8, 23, 30).toIso8601String(),
        'endedAt': DateTime.utc(2026, 11, 9, 0, 30).toIso8601String(),
      };
      final merged = forkMergeWeeks([
        ForkWeekSplit.fromSessions([crossing], Duration.zero, week45),
        ForkWeekSplit.fromSessions([crossing], Duration.zero, week46),
      ]);
      expect(merged.listen, {'2026-11-08': 1800, '2026-11-09': 1800});
      expect((merged.items['10'] as Map)['timeListening'], 3600);
    });

    test('splits by format and counts a repeated session once', () {
      final split = ForkWeekSplit.fromSessions(
          [session(1, 'm4b'), session(1, 'm4b'), session(2, 'epub', seconds: 300)], Duration.zero, week45);
      expect(split.listen, {'2026-11-08': 600});
      expect(split.read, {'2026-11-08': 300});
      expect(split.books['10'], {'t': 'Book 1', 's': 600});
    });

    test('read along on an EPUB is listening once its kind is known', () {
      final split = ForkWeekSplit.fromSessions(
          [session(1, 'epub', kind: 'listen'), session(2, 'epub', kind: 'read', seconds: 300)], Duration.zero, week45);
      expect(split.listen, {'2026-11-08': 600});
      expect(split.read, {'2026-11-08': 300});
    });

    test('survives being stored', () {
      final split = ForkWeekSplit.fromSessions([session(1, 'm4b')], Duration.zero, week45);
      final back = ForkWeekSplit.fromJson(jsonDecode(jsonEncode(split.toJson())) as Map<String, dynamic>);
      expect(back.listen, split.listen);
      expect(back.books, split.books);
    });
  });

  test('forkMergeWeeks adds weeks up, in the Stats screen item shape', () {
    final merged = forkMergeWeeks([
      ForkWeekSplit.fromSessions([session(1, 'm4b')], Duration.zero, week45),
      ForkWeekSplit.fromSessions([session(1, 'm4b', hour: 11, seconds: 400)..['sessionId'] = 9], Duration.zero, week45),
    ]);
    expect(merged.listen, {'2026-11-08': 1000});
    expect((merged.items['10'] as Map)['timeListening'], 1000);
    expect(((merged.items['10'] as Map)['mediaMetadata'] as Map)['title'], 'Book 1');
  });

  test('forkTopBookIds takes the books most time went to', () {
    final items = {
      for (var i = 1; i <= 7; i++) '$i': {'timeListening': i},
    };
    expect(forkTopBookIds(items), ['7', '6', '5', '4', '3']);
  });

  group('book lookups', () {
    test('forkBooksToLookUp skips audio and takes the longest books', () {
      final sessions = [
        session(1, 'm4b', seconds: 9000),
        for (var i = 2; i < 8; i++) session(i, 'epub', seconds: i * 100),
      ];
      final ids = forkBooksToLookUp(sessions);
      expect(ids, ['70', '60', '50', '40']);
      expect(ids, hasLength(forkBookLookupsPerWeek));
    });

    test('forkWithSessionDetail adds the kind and file by session id', () {
      final out = forkWithSessionDetail([session(1, 'epub'), session(2, 'epub')], [
        {'id': 1, 'sessionType': 'tts', 'bookFileId': 39},
      ]);
      expect(out.first['sessionType'], 'tts');
      expect(out.first['bookFileId'], 39);
      expect(out.last.containsKey('sessionType'), isFalse);
    });
  });

  test('forkDaySessions keeps that account day only, in the activity day shape', () {
    final day = forkDaySessions([session(1, 'epub'), session(1, 'epub')], '2026-11-08', Duration.zero);
    expect(day, hasLength(1));
    expect(day.single['id'], 1);
    expect(day.single['mediaBucket'], 'reading');
    expect(day.single['sourceBucket'], 'android');
    expect(day.single['durationOnDaySeconds'], 600);
    expect(forkDaySessions([session(1, 'epub')], '2026-11-09', Duration.zero), isEmpty);
    // 22:00 UTC is already tomorrow in Tokyo.
    final late = session(2, 'm4b', hour: 22);
    expect(forkDaySessions([late], '2026-11-09', tokyo), hasLength(1));
    expect(forkDaySessions([late], '2026-11-08', tokyo), isEmpty);
    expect(forkDaySessions([session(3, 'epub', kind: 'listen')], '2026-11-08', Duration.zero).single['mediaBucket'],
        'listening');
  });

  test('forkHourRows and forkHoursTotal split peak hours by format', () {
    final hours = [
      {
        'hour': 8,
        'byFormat': {'M4B': 100, 'EPUB': 50, 'UNKNOWN': 10},
      },
      {
        'hour': 9,
        'byFormat': {'PDF': 40},
      },
    ];
    expect(forkHourRows(hours).first, {'hour': 8, 'listening': 110, 'reading': 50});
    final total = forkHoursTotal(hours);
    expect(total.listening, 110);
    expect(total.reading, 90);
  });

  test('forkPaceMedians takes each median, and null when there is nothing', () {
    final m = forkPaceMedians([
      {'durationSeconds': 100, 'progressDelta': 1, 'format': 'M4B'},
      {'durationSeconds': 300, 'progressDelta': 3, 'format': 'EPUB'},
      {'durationSeconds': 500, 'progressDelta': 5, 'format': 'EPUB'},
    ]);
    expect(m.session, 300);
    expect(m.listen, 100);
    expect(m.read, 400);
    expect(m.progress, 3);
    expect(forkPaceMedians(null).session, isNull);
  });

  test('forkYearStats counts that year only', () {
    final stats = forkYearStats(
      year: 2026,
      rows: [
        {'day': '2025-12-31', 'readingSeconds': 999, 'eventsCount': 9},
        {'day': '2026-01-02', 'readingSeconds': 100, 'eventsCount': 1},
        {'day': '2026-03-02', 'readingSeconds': 300, 'eventsCount': 2},
        {'day': '2026-03-03', 'readingSeconds': 0, 'eventsCount': 0},
      ],
      split: (listening: 250, reading: 150),
      finished: 4,
    );
    expect(stats['totalListeningTime'], 250);
    expect(stats['bookOrbitReadingTime'], 150);
    expect(stats['bookOrbitActiveDays'], 2);
    expect(stats['totalListeningSessions'], 3);
    expect(stats['numBooksFinished'], 4);
    expect(stats['mostListenedMonth'], {'month': 2});
  });
}
