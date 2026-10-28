import 'package:absorb/services/fork/dashboard_widgets_model.dart';
import 'package:absorb/widgets/fork/dashboard_widgets.dart';
import 'package:absorb/widgets/wavy_progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ForkDashboardWidgets _fakeData() {
  final start = DateTime(2026, 10, 12); // a Monday
  const seconds = [0, 1200, 3600, 5400, 300, 0, 7200, 2400, 600, 0, 4500, 1800, 9000, 60];
  return ForkDashboardWidgets([
    const ForkDashboardWidget(
      forkWidgetCurrentlyReading,
      ForkCurrentlyReading([
        ForkWidgetBook(
            bookId: 'b1',
            title: 'A Very Long Title That Will Certainly Not Fit On One Line',
            authors: ['First Author', 'Second Author'],
            progress: 0.42),
        ForkWidgetBook(bookId: 'b2', title: 'Second Book', authors: ['Someone'], progress: 0.9),
        ForkWidgetBook(bookId: 'b3', title: 'Third Book', progress: 0),
      ]),
    ),
    const ForkDashboardWidget(
      forkWidgetReadingStreak,
      ForkReadingStreak(
        currentStreak: 244,
        longestStreak: 244,
        lastSevenDays: [true, true, true, false, true, true, true],
      ),
    ),
    ForkDashboardWidget(
      forkWidgetReadingRhythm,
      ForkReadingRhythm(
        days: [
          for (var i = 0; i < 14; i++) ForkRhythmDay(start.add(Duration(days: i)), seconds[i]),
        ],
        consistencyPercent: 79,
        avgSecondsPerDay: 4980,
        activeDays: 11,
        totalDays: 14,
      ),
    ),
    const ForkDashboardWidget('unknown-type', null),
    const ForkDashboardWidget(
      forkWidgetReadingGoal,
      ForkReadingGoal(goalBooks: 120, completedBooks: 558, year: 2026),
    ),
  ]);
}

final _horizontal = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.right);

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required double textScale,
  void Function(String)? onOpenBook,
  VoidCallback? onOpenPlayer,
  Future<bool> Function(int)? onSetGoal,
  String? activeBookId,
  ForkWidgetBook? activeBook,
  bool playing = false,
  double? Function(String)? liveProgress,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: ListView(children: [
          ForkDashboardWidgetRow(
            data: _fakeData(),
            onOpenBook: onOpenBook ?? (_) {},
            onOpenPlayer: onOpenPlayer ?? () {},
            onOpenStats: () {},
            onSetGoal: onSetGoal ?? (_) async => true,
            coverUrl: (_) => null,
            activeBookId: activeBookId,
            activeBook: activeBook,
            playing: playing,
            liveProgress: liveProgress,
          ),
        ]),
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _checkAllCards(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  for (final title in ['Currently Reading', 'Reading Streak', 'Reading Rhythm', 'Reading Goal 2026']) {
    await tester.scrollUntilVisible(find.text(title), 150, scrollable: _horizontal);
    await tester.pumpAndSettle();
    expect(find.text(title), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'overflow on $title');
  }
}

void main() {
  testWidgets('every card fits 320 px with 2x text', (tester) async {
    await _pump(tester, width: 320, textScale: 2);
    await _checkAllCards(tester);
    expect(find.text('of 120'), findsOneWidget);
    expect(find.text('558'), findsOneWidget);
  });

  testWidgets('every card fits 400 px with normal text', (tester) async {
    await _pump(tester, width: 400, textScale: 1);
    await _checkAllCards(tester);
    expect(find.text('avg 1h 23m/day'), findsOneWidget);
    expect(find.text('100% complete'), findsOneWidget);
  });

  testWidgets('streak card shows the days and seven dots', (tester) async {
    await _pump(tester, width: 400, textScale: 1);
    await tester.scrollUntilVisible(find.text('Reading Streak'), 150, scrollable: _horizontal);
    await tester.pumpAndSettle();
    expect(find.text('244'), findsOneWidget);
    expect(find.text('days streak'), findsOneWidget);
    expect(find.text('Best: 244 days'), findsOneWidget);
    expect(find.text('Last 7 days'), findsOneWidget);
  });

  testWidgets('tapping a book row opens that book', (tester) async {
    final opened = <String>[];
    await _pump(tester, width: 400, textScale: 1, onOpenBook: opened.add);
    await tester.tap(find.text('Second Book'));
    await tester.pump();
    expect(opened, ['b2']);
  });

  testWidgets("the playing book's row opens the player, any other its book", (tester) async {
    final opened = <String>[];
    var playerOpens = 0;
    await _pump(tester,
        width: 400,
        textScale: 1,
        activeBookId: 'b2',
        playing: true,
        onOpenBook: opened.add,
        onOpenPlayer: () => playerOpens++);
    await tester.tap(find.text('Second Book'));
    await tester.pump();
    expect(playerOpens, 1);
    expect(opened, isEmpty);

    await tester.tap(find.text('Third Book'));
    await tester.pump();
    expect(opened, ['b3']);
    expect(playerOpens, 1);

    // Paused, the same row opens the book again.
    await _pump(tester,
        width: 400,
        textScale: 1,
        activeBookId: 'b2',
        playing: false,
        onOpenBook: opened.add,
        onOpenPlayer: () => playerOpens++);
    await tester.tap(find.text('Second Book'));
    await tester.pump();
    expect(opened, ['b3', 'b2']);
    expect(playerOpens, 1);
  });

  testWidgets('the playing book comes first with a live wavy bar', (tester) async {
    await _pump(tester,
        width: 400,
        textScale: 1,
        activeBookId: 'b2',
        playing: true,
        liveProgress: (id) => id == 'b2' ? 0.95 : null);
    final firstRowTop = tester.getTopLeft(find.text('Second Book')).dy;
    expect(firstRowTop, lessThan(tester.getTopLeft(find.textContaining('A Very Long Title')).dy));
    expect(find.byType(WavyProgressIndicator), findsOneWidget);
    expect(find.text('95%'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pump(tester, width: 400, textScale: 1, activeBookId: 'b2', playing: false);
    expect(find.byType(WavyProgressIndicator), findsNothing);
    expect(tester.getTopLeft(find.text('Second Book')).dy,
        lessThan(tester.getTopLeft(find.textContaining('A Very Long Title')).dy));
    expect(find.text('90%'), findsOneWidget);
  });

  testWidgets('a playing book the server does not list yet comes first', (tester) async {
    await _pump(tester,
        width: 400,
        textScale: 1,
        activeBookId: 'new',
        activeBook: const ForkWidgetBook(bookId: 'new', title: 'Just Started', authors: ['New Author']),
        playing: true,
        liveProgress: (id) => id == 'new' ? 0.03 : null);
    expect(find.text('Just Started'), findsOneWidget);
    expect(find.text('New Author'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Just Started')).dy,
        lessThan(tester.getTopLeft(find.textContaining('A Very Long Title')).dy));
    expect(find.byType(WavyProgressIndicator), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('fork-widget-book-new')),
            matching: find.byType(WavyProgressIndicator)),
        findsOneWidget);
    expect(find.text('3%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short streak history still draws seven dots', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Scaffold(
        body: ListView(children: [
          ForkDashboardWidgetRow(
            data: const ForkDashboardWidgets([
              ForkDashboardWidget(
                forkWidgetReadingStreak,
                ForkReadingStreak(currentStreak: 2, longestStreak: 9, lastSevenDays: [true, true]),
              ),
            ]),
            onOpenBook: (_) {},
            onOpenPlayer: () {},
            onOpenStats: () {},
            onSetGoal: (_) async => true,
            coverUrl: (_) => null,
          ),
        ]),
      ),
    ));
    await tester.pump();
    final dots = find.byWidgetPredicate((w) =>
        w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle);
    expect(dots, findsNWidgets(7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pencil edits the goal', (tester) async {
    final saved = <int>[];
    await _pump(tester, width: 320, textScale: 2, onSetGoal: (n) async {
      saved.add(n);
      return true;
    });
    await tester.scrollUntilVisible(find.byIcon(Icons.edit_outlined), 150, scrollable: _horizontal);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Reading goal'), findsOneWidget);
    expect(find.widgetWithText(TextField, '120'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('fork-reading-goal-field')), '150');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, [150]);
    expect(find.text('Reading goal'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed save says so', (tester) async {
    await _pump(tester, width: 400, textScale: 1, onSetGoal: (_) async => false);
    await tester.scrollUntilVisible(find.byIcon(Icons.edit_outlined), 150, scrollable: _horizontal);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save the goal'), findsOneWidget);
  });
}
