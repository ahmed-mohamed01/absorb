import 'package:absorb/services/fork/dashboard_widgets_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to all four widgets when the list is missing', () {
    expect(forkEnabledWidgetTypes(null), forkSupportedWidgetTypes);
    expect(forkEnabledWidgetTypes({}), [
      'currently-reading',
      'reading-streak',
      'reading-rhythm',
      'reading-goal',
    ]);
    expect(forkEnabledWidgetTypes({'widgets': []}), isEmpty);
  });

  test('orders enabled supported types and removes duplicates', () {
    expect(
      forkEnabledWidgetTypes({
        'widgets': [
          {'type': 'reading-goal', 'order': 4},
          {'type': 'reading-streak', 'order': 2, 'enabled': true},
          {'type': 'reading-goal', 'order': 1},
          {'type': 'currently-reading', 'enabled': false, 'order': 0},
          {'type': 'unknown', 'order': 0},
          null,
        ],
      }),
      ['reading-goal', 'reading-streak'],
    );
  });

  test('parses all four payloads in requested order', () {
    final parsed = forkParseWidgetBatch(forkSupportedWidgetTypes, {
      'items': [
        {
          'type': 'reading-goal',
          'data': {'goalBooks': 24, 'completedBooks': 8, 'year': 2026},
        },
        {
          'type': 'reading-rhythm',
          'data': {
            'days': [
              {'date': '2026-10-27', 'readingSeconds': 1200},
              {'date': 'bad'},
            ],
            'consistencyPercent': 50,
            'avgSecondsPerDay': 600,
            'activeDays': 1,
            'totalDays': 2,
          },
        },
        {
          'type': 'reading-streak',
          'data': {
            'currentStreak': 3,
            'longestStreak': 10,
            'lastSevenDays': [true, false, true, false, true, true, true],
          },
        },
        {
          'type': 'currently-reading',
          'data': {
            'books': [
              {
                'bookId': 17,
                'title': 'Book',
                'authors': ['Author'],
                'progress': 65,
                'hasCover': true,
              },
              {'bookId': '18', 'progress': 0.25},
              {'bookId': '19', 'progress': 1},
              {'bookId': '20', 'progress': 100},
              {'bookId': '21', 'progress': 150},
            ],
          },
        },
      ],
    });
    expect(parsed.widgets.map((w) => w.type), forkSupportedWidgetTypes);
    final books = (parsed.widgets[0].data as ForkCurrentlyReading).books;
    expect(books.first.bookId, '17');
    expect(books.first.title, 'Book');
    expect(books.first.authors, ['Author']);
    expect(books.first.hasCover, isTrue);
    expect(books.map((b) => b.progress), [0.65, 0.0025, 0.01, 1.0, 1.0]);
    final streak = parsed.widgets[1].data as ForkReadingStreak;
    expect(streak.currentStreak, 3);
    expect(streak.longestStreak, 10);
    expect(streak.lastSevenDays.length, 7);
    final rhythm = parsed.widgets[2].data as ForkReadingRhythm;
    expect(rhythm.days.single.date, DateTime(2026, 10, 27));
    expect(rhythm.days.single.readingSeconds, 1200);
    expect(rhythm.consistencyPercent, 50);
    expect(rhythm.avgSecondsPerDay, 600);
    expect(rhythm.activeDays, 1);
    expect(rhythm.totalDays, 2);
    final goal = parsed.widgets[3].data as ForkReadingGoal;
    expect(goal.goalBooks, 24);
    expect(goal.completedBooks, 8);
    expect(goal.year, 2026);
  });

  test('failed, missing and malformed widgets have null data', () {
    final parsed = forkParseWidgetBatch(forkSupportedWidgetTypes, {
      'items': [
        {
          'type': 'currently-reading',
          'failed': true,
          'data': {'books': []},
        },
        {'type': 'reading-streak', 'data': 'wrong'},
        {'type': 'reading-goal', 'data': {}},
      ],
    });
    expect(parsed.widgets.take(3).map((w) => w.data), [null, null, null]);
    final goal = parsed.widgets.last.data as ForkReadingGoal;
    expect(goal.goalBooks, isNull);
    expect(goal.completedBooks, 0);
    expect(
      forkParseWidgetBatch(
        ['reading-streak'],
        {
          'items': [
            {'type': 'reading-streak', 'data': {}},
          ],
        },
      ).widgets.single.data,
      isA<ForkReadingStreak>(),
    );
  });

  test('reads the configured reading goal', () {
    expect(forkReadingGoalOf(null), isNull);
    expect(forkReadingGoalOf({}), isNull);
    expect(forkReadingGoalOf({'readingGoal': 'wrong'}), isNull);
    expect(forkReadingGoalOf({'readingGoal': 30}), 30);
    expect(forkReadingGoalOf({'readingGoal': 0}), 0);
  });

  group('forkLiveFraction', () {
    test('a loading player at zero keeps the server progress', () {
      expect(forkLiveFraction(seconds: 0, total: 80508), isNull);
      expect(forkLiveFraction(seconds: 100, total: 0), isNull);
    });

    test('a real position becomes a capped fraction', () {
      expect(forkLiveFraction(seconds: 40254, total: 80508), closeTo(0.5, 1e-9));
      expect(forkLiveFraction(seconds: 90000, total: 80508), 1.0);
    });
  });
}
