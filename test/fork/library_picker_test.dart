import 'dart:async';

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
    var requestsTapped = false;
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
              requestsAccount: 'can-request',
              canRequest: () async => true,
              requestCount: () async => 80,
              onRequests: () => requestsTapped = true,
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
    // Book requests sit between the Book Dock and the Watchlist.
    final requests = tester.getTopLeft(find.text('Book requests')).dy;
    expect(requests, greaterThan(tester.getTopLeft(find.text('Book Dock')).dy));
    expect(requests, lessThan(tester.getTopLeft(find.text('Watchlist')).dy));
    expect(find.text('80 requests'), findsOneWidget);
    await tester.tap(find.text('Book requests'));
    expect(requestsTapped, isTrue);

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

  testWidgets('no Book requests row when the user may not request', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ForkLibraryPicker(
          libraries: const [
            {'id': '1', 'name': 'Audiobooks', 'mediaType': 'book', 'bookCount': 9},
            {'id': 'watchlist', 'name': 'Watchlist', 'watchlist': true, 'mediaType': 'book'},
          ],
          title: 'Select Library',
          isSelected: (_) => false,
          onPick: (_, _) {},
          requestsAccount: 'cannot-request',
          canRequest: () async => false,
          requestCount: () async => 3,
          onRequests: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Book requests'), findsNothing);
    expect(find.text('Watchlist'), findsOneWidget);
  });

  testWidgets('the Book requests row is remembered per account', (tester) async {
    Widget picker(String account, Future<bool> Function() canRequest) => MaterialApp(
          home: Scaffold(
            body: ForkLibraryPicker(
              key: UniqueKey(),
              libraries: const [
                {'id': 'watchlist', 'name': 'Watchlist', 'watchlist': true, 'mediaType': 'book'},
              ],
              title: 'Select Library',
              isSelected: (_) => false,
              onPick: (_, _) {},
              requestsAccount: account,
              canRequest: canRequest,
              onRequests: () {},
            ),
          ),
        );
    final never = Completer<bool>();

    await tester.pumpWidget(picker('remembered', () async => true));
    await tester.pump();
    expect(find.text('Book requests'), findsOneWidget);

    // Opened again for the same account: there before the check answers.
    await tester.pumpWidget(picker('remembered', () => never.future));
    expect(find.text('Book requests'), findsOneWidget);

    // Another account starts without it.
    await tester.pumpWidget(picker('someone-else', () => never.future));
    expect(find.text('Book requests'), findsNothing);
  });

  testWidgets('offline keeps the last Book requests answer', (tester) async {
    Widget picker(Future<bool?> Function() canRequest) => MaterialApp(
          home: Scaffold(
            body: ForkLibraryPicker(
              key: UniqueKey(),
              libraries: const [
                {'id': 'watchlist', 'name': 'Watchlist', 'watchlist': true, 'mediaType': 'book'},
              ],
              title: 'Select Library',
              isSelected: (_) => false,
              onPick: (_, _) {},
              requestsAccount: 'goes-offline',
              canRequest: canRequest,
              onRequests: () {},
            ),
          ),
        );

    await tester.pumpWidget(picker(() async => true));
    await tester.pump();
    expect(find.text('Book requests'), findsOneWidget);

    // Offline: the check cannot tell, so the row stays and is still remembered.
    await tester.pumpWidget(picker(() async => null));
    await tester.pump();
    expect(find.text('Book requests'), findsOneWidget);
    await tester.pumpWidget(picker(() => Completer<bool?>().future));
    expect(find.text('Book requests'), findsOneWidget);
  });
}
