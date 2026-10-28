import 'package:absorb/widgets/fork/library_icon.dart';
import 'package:absorb/widgets/fork/library_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the picker fits a narrow screen with large text and lists the tools last', (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? picked;
    bool? pickedSelected;
    final libraries = <Map<String, dynamic>>[
      {'id': 'book-dock', 'name': 'Book Dock', 'bookDock': true, 'mediaType': 'book'},
      {'id': '1', 'name': 'Audiobooks', 'icon': 'Headphones', 'mediaType': 'book', 'bookCount': 9},
      {'id': '2', 'name': 'Read-along', 'icon': 'BookOpen', 'mediaType': 'book', 'bookCount': 1},
      {
        'id': 'watchlist',
        'name': 'Watchlist',
        'watchlist': true,
        'mediaType': 'book',
        'watchlistAuthors': 4,
        'watchlistNeedsYou': 2,
      },
    ];
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(320, 1400), textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ForkLibraryPicker(
              libraries: libraries,
              title: 'Select Library',
              isSelected: (l) => l['id'] == '1',
              onPick: (l, selected) {
                picked = l;
                pickedSelected = selected;
              },
              dockSummary: () async => {'needsReview': 3, 'pending': 5, 'total': 5},
              watchlistUpcoming: () async => 4,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(find.text('Select Library'), findsOneWidget);
    expect(find.text('9 books'), findsOneWidget);
    expect(find.text('1 book'), findsOneWidget);
    expect(find.text('3 files need review'), findsOneWidget);
    expect(find.text('4 authors · 4 upcoming'), findsOneWidget);
    expect(find.text('2 needs you'), findsOneWidget);
    expect(find.byKey(const ValueKey('fork-picker-divider')), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.headphones_rounded), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
    expect(find.byIcon(Icons.move_to_inbox_rounded), findsOneWidget);
    expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);

    // Libraries first, then the divider, then the tools, whatever order they came in.
    final divider = tester.getTopLeft(find.byKey(const ValueKey('fork-picker-divider'))).dy;
    expect(tester.getTopLeft(find.text('Audiobooks')).dy, lessThan(divider));
    expect(tester.getTopLeft(find.text('Read-along')).dy, lessThan(divider));
    expect(tester.getTopLeft(find.text('Book Dock')).dy, greaterThan(divider));
    expect(tester.getTopLeft(find.text('Watchlist')).dy, greaterThan(divider));
    expect(tester.getTopLeft(find.text('Watchlist')).dy, greaterThan(tester.getTopLeft(find.text('Book Dock')).dy));

    await tester.tap(find.text('Read-along'));
    expect(picked?['id'], '2');
    expect(pickedSelected, isFalse);

    await tester.tap(find.text('Audiobooks'));
    expect(picked?['id'], '1');
    expect(pickedSelected, isTrue);
  });

  testWidgets('a Book Dock row without a summary has no line, and none is asked for without a dock', (tester) async {
    var asked = 0;
    var askedUpcoming = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ForkLibraryPicker(
          libraries: const [
            {'id': '1', 'name': 'Books', 'icon': 'books-1', 'mediaType': 'book'},
          ],
          title: 'Select Library',
          isSelected: (_) => false,
          onPick: (_, __) {},
          dockSummary: () async {
            asked++;
            return null;
          },
          watchlistUpcoming: () async {
            askedUpcoming++;
            return null;
          },
        ),
      ),
    ));
    await tester.pump();
    expect(asked, 0);
    expect(askedUpcoming, 0);
    expect(find.text('Books'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.byKey(const ValueKey('fork-picker-divider')), findsNothing);
  });

  testWidgets('a custom icon with no server to fetch from shows the media type icon', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ForkLibraryIcon(
          library: {'icon': 'custom:my-star', 'mediaType': 'podcast'},
          size: 24,
          color: Colors.red,
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.podcasts_rounded), findsOneWidget);
  });
}
