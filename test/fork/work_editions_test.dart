import 'package:absorb/services/fork/position_sync_chain.dart';
import 'package:absorb/services/fork/work_editions.dart';
import 'package:absorb/widgets/fork/editions_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ebook = SyncChainBook(id: 1, title: 'Columbus Day', progress: 68);
const _audio = SyncChainBook(id: 2, title: 'Columbus Day', progress: 70);
const _readAlong = SyncChainBook(id: 3, title: 'Columbus Day', progress: 69);
const _allowed = SyncChainPermissions(editLink: true, generate: true);

SyncChainSnapshot _linked({
  SyncEdition thisBook = SyncEdition.audiobook,
  SyncChainReadAlong ra = const SyncChainReadAlong(),
  SyncChainPermissions can = _allowed,
}) =>
    SyncChainSnapshot(
      thisBook: thisBook,
      linked: true,
      ebook: SyncChainSide(book: _ebook, isMember: true, isThisBook: thisBook == SyncEdition.ebook),
      audiobook: SyncChainSide(book: _audio, isMember: true, isThisBook: thisBook == SyncEdition.audiobook),
      readAlong: ra,
      can: can,
    );

void main() {
  group('workEditions', () {
    test('lists audiobook, read-along, ebook in that order', () {
      final rows = workEditions(_linked(ra: const SyncChainReadAlong(member: _readAlong)));
      expect(rows.map((r) => r.kind), [SyncEdition.audiobook, SyncEdition.readAlong, SyncEdition.ebook]);
      expect(rows.map((r) => r.book?.id), [2, 3, 1]);
      expect(rows.map((r) => r.isThisBook), [true, false, false]);
    });

    test('a missing read-along is a generate gap, or building while it runs', () {
      expect(workEditions(_linked())[1].gap, WorkEditionGap.generate);
      expect(workEditions(_linked(ra: const SyncChainReadAlong(status: ReadAlongStatus.building)))[1].gap,
          WorkEditionGap.building);
    });

    test('a finished read-along the link has not picked up is listed', () {
      final rows = workEditions(_linked(
          ra: const SyncChainReadAlong(status: ReadAlongStatus.ready, outputBook: _readAlong)));
      expect(rows[1].book?.id, 3);
    });

    test('no Generate before the read-along status is known', () {
      final rows = workEditions(_linked(), readAlongKnown: false);
      expect(rows.map((r) => r.kind), [SyncEdition.audiobook, SyncEdition.ebook]);
    });

    test('no gap the reader cannot fill', () {
      final rows = workEditions(_linked(can: const SyncChainPermissions()));
      expect(rows.map((r) => r.kind), [SyncEdition.audiobook, SyncEdition.ebook]);
    });

    test('on the read-along page the read-along is this book', () {
      final rows = workEditions(_linked(
          thisBook: SyncEdition.readAlong, ra: const SyncChainReadAlong(thisBook: _readAlong)));
      expect(rows.where((r) => r.isThisBook).single.kind, SyncEdition.readAlong);
    });

    test('a proposed match is listed', () {
      const proposal = SyncChainSnapshot(
        thisBook: SyncEdition.audiobook,
        audiobook: SyncChainSide(book: _audio, isThisBook: true),
        ebook: SyncChainSide(book: _ebook, match: EditionMatch(MatchSource.auto, 90)),
        can: _allowed,
      );
      final rows = workEditions(proposal);
      expect(rows.map((r) => r.book?.id), [2, null, 1]);
    });

    test('nothing when this book is the only edition', () {
      const alone = SyncChainSnapshot(
        thisBook: SyncEdition.audiobook,
        audiobook: SyncChainSide(book: _audio, isThisBook: true),
      );
      expect(workEditions(alone), isEmpty);
    });

    test('a detached read-along still lists beside this book, with the ebook to link', () {
      const s = SyncChainSnapshot(
        thisBook: SyncEdition.audiobook,
        audiobook: SyncChainSide(book: _audio, isThisBook: true),
        readAlong: SyncChainReadAlong(member: _readAlong),
        can: _allowed,
      );
      final rows = workEditions(s);
      expect(rows.map((r) => r.gap), [null, null, WorkEditionGap.link]);
    });
  });

  group('ForkEditionsList', () {

    Future<void> pump(WidgetTester tester, double width, double scale,
        {void Function(int)? onOpen, VoidCallback? onGap, bool expanded = true, VoidCallback? onToggle}) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ForkEditionsList(
                rows: workEditions(_linked()),
                sizes: const {1: 2400000, 2: 512000000},
                progress: 0.7,
                accent: Colors.amber,
                onOpen: onOpen ?? (_) {},
                onGap: onGap ?? () {},
                expanded: expanded,
                onToggle: onToggle ?? () {},
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('collapsed it is one line that opens on tap', (tester) async {
      var toggled = false;
      await pump(tester, 320, 2, expanded: false, onToggle: () => toggled = true);
      expect(tester.takeException(), isNull);
      expect(find.text('Read-along'), findsNothing);
      await tester.tap(find.text('EDITIONS'));
      expect(toggled, isTrue);
    });

    testWidgets('fits at 320 px with 2x text', (tester) async {
      await pump(tester, 320, 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Read-along'), findsOneWidget);
      // No room for the sizes, in the rows or the header.
      expect(find.text('488.3 MB'), findsNothing);
    });

    testWidgets('shows sizes and opens editions on a phone at normal text', (tester) async {
      int? opened;
      var gapTapped = false;
      await pump(tester, 400, 1, onOpen: (id) => opened = id, onGap: () => gapTapped = true);
      expect(tester.takeException(), isNull);
      expect(find.text('488.3 MB'), findsOneWidget);
      expect(find.text('2 · 490.6 MB'), findsOneWidget);
      await tester.tap(find.text('Ebook'));
      expect(opened, 1);
      await tester.tap(find.text('Audiobook'));
      expect(opened, 1, reason: 'this book does not open itself');
      await tester.tap(find.text('Generate'));
      expect(gapTapped, isTrue);
    });
  });
}
