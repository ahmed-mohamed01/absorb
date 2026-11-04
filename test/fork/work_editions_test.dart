import 'package:absorb/services/fork/position_sync_chain.dart';
import 'package:absorb/services/fork/work_editions.dart';
import 'package:absorb/widgets/fork/editions_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ebook = SyncChainEdition(title: 'Columbus Day', formatName: 'EPUB e-book', sizeBytes: 2400000, progress: 68);
const _audio = SyncChainEdition(title: 'Columbus Day', formatName: 'M4B audiobook', sizeBytes: 512000000, progress: 70);
const _readAlong = SyncChainEdition(title: 'Columbus Day', formatName: 'Read-aloud EPUB', sizeBytes: 9000000, progress: 69,
);

SyncChainSnapshot _book({
  SyncChainEdition? ebook = _ebook,
  SyncChainEdition? audiobook = _audio,
  SyncChainEdition? readAlong,
  SyncChainReadAloudSlot slot = const SyncChainReadAloudSlot(entry: ReadAloudEntryAvailable()),
}) =>
    SyncChainSnapshot(bookId: 1, ebook: ebook, audiobook: audiobook, readAlong: readAlong, readAloudSlot: slot);

void main() {
  group('workEditions', () {
    test('lists audiobook, read-aloud, ebook in that order', () {
      final rows = workEditions(_book(readAlong: _readAlong));
      expect(rows.map((r) => r.kind), [SyncEdition.audiobook, SyncEdition.readAlong, SyncEdition.ebook]);
      expect(rows.map((r) => r.edition?.progress), [70, 69, 68]);
      expect(rows.every((r) => r.gap == null), isTrue);
    });

    test('a missing read-aloud is a create gap, or building while a job runs', () {
      expect(workEditions(_book())[1].gap, WorkEditionGap.generate);
      final running = _book(
          slot: const SyncChainReadAloudSlot(
              entry: ReadAloudEntryUnavailable(ReadAloudReason.jobActive, ''),
              job: SyncChainReadAloudJob(status: ReadAloudJobStatus.processing),
        ),
      );
      expect(workEditions(running)[1].gap, WorkEditionGap.building);
    });

    test('no gap where none can be made', () {
      final hidden = workEditions(_book(slot: const SyncChainReadAloudSlot()));
      expect(hidden.map((r) => r.kind), [SyncEdition.audiobook, SyncEdition.ebook]);
      final review = workEditions(_book(
          slot: const SyncChainReadAloudSlot(job: SyncChainReadAloudJob(status: ReadAloudJobStatus.awaitingReview)),
        ),
      );
      expect(review.map((r) => r.kind), [SyncEdition.audiobook, SyncEdition.ebook]);
    });

    test('a read-aloud beside the audio alone is two editions', () {
      final rows = workEditions(_book(ebook: null, readAlong: _readAlong));
      expect(rows.map((r) => r.kind), [SyncEdition.audiobook, SyncEdition.readAlong]);
    });

    test('one edition lists the other as a request', () {
      final audioOnly = workEditions(_book(ebook: null));
      expect(audioOnly.map((r) => r.kind), [SyncEdition.audiobook, SyncEdition.ebook]);
      expect(audioOnly.last.gap, WorkEditionGap.request);
      final ebookOnly = workEditions(_book(audiobook: null));
      expect(ebookOnly.map((r) => r.kind), [SyncEdition.audiobook, SyncEdition.ebook]);
      expect(ebookOnly.first.gap, WorkEditionGap.request);
    });

    test('a read-aloud counts as something to read', () {
      final rows = workEditions(_book(ebook: null, audiobook: null, readAlong: _readAlong));
      expect(rows.map((r) => (r.kind, r.gap)),
          [(SyncEdition.audiobook, WorkEditionGap.request), (SyncEdition.readAlong, null),
      ]);
    });

    test('nothing when the book holds no edition', () {
      expect(workEditions(_book(ebook: null, audiobook: null)), isEmpty);
    });
  });

  group('missingEditionRequestPayload', () {
    test('names this book and carries its metadata', () {
      final body = missingEditionRequestPayload({
        'title': ' Klara and the Sun ',
        'authors': [{'id': '1', 'name': 'Kazuo Ishiguro'},
          ],
        'series': [{'id': '2', 'name': 'Standalone', 'sequence': null},
          ],
        'isbn': '978-0-571-36487-9',
        'publishedYear': '2021',
        'language': 'en',
      }, 'ebook', 42,
      );
      expect(body, {
        'title': 'Klara and the Sun',
        'mediaKind': 'ebook',
        'authors': ['Kazuo Ishiguro'],
        'isbn13': '9780571364879',
        'seriesName': 'Standalone',
        'publishedYear': 2021,
        'language': 'en',
        'targetBookId': 42,
      });
    });

    test('leaves out what the book does not have', () {
      expect(missingEditionRequestPayload({'title': 'X', 'authors': [],
        'series': {'id': '2', 'name': 'Bob', 'sequence': '2'}}, 'audiobook', 7)['seriesName'], 'Bob');
      expect(missingEditionRequestPayload({'title': 'X', 'authors': []}, 'audiobook', 7),
          {'title': 'X', 'mediaKind': 'audiobook', 'targetBookId': 7,
      });
    });
  });

  group('ForkEditionsList', () {
    Future<void> pump(WidgetTester tester, double width, double scale,
        {VoidCallback? onOpen,
        bool expanded = true,
        VoidCallback? onToggle,
        SyncChainSnapshot? book,
        EditionRequestRow Function(WorkEdition r)? request,
      SyncChainIndex? index,
      EditionSyncCard? sync,
      ValueChanged<bool>? onIndexSync,
      ValueChanged<ChainActionId>? onIndexAction,
      Brightness brightness = Brightness.dark,
    }) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ForkEditionsList(
                rows: workEditions(book ?? _book()),
                audioProgress: 0.7,
                accent: Colors.amber,
                onOpen: onOpen ?? () {},
                expanded: expanded,
                onToggle: onToggle ?? () {},
                request: request,
                  sync: sync ?? (index == null ? null : EditionSyncCard.index(index)),
                  onSyncSwitch: onIndexSync,
                  onSyncAction: onIndexAction,
                ),
            ),
          ),
        ),
      ),
      );
    }

    testWidgets('collapsed it is one line that opens on tap', (tester) async {
      var toggled = false;
      await pump(tester, 320, 2, expanded: false, onToggle: () => toggled = true);
      expect(tester.takeException(), isNull);
      expect(find.text('Read-aloud'), findsNothing);
      await tester.tap(find.text('EDITIONS'));
      expect(toggled, isTrue);
    });

    testWidgets('edition sync in the footer fits at 320 px with 2x text and acts', (tester) async {
      bool? switched;
      ChainActionId? acted;
      await pump(
        tester,
        320,
        2,
        index: const SyncChainIndex(
          status: EditionSyncIndexStatus.failed,
          on: true,
          error: 'Worker stopped',
          canRetry: true,
        ),
        onIndexSync: (on) => switched = on,
        onIndexAction: (id) => acted = id,
      );
      expect(tester.takeException(), isNull);
      expect(find.text(PositionSyncCopy.indexCantIndex), findsOneWidget);
      expect(
        find.textContaining(PositionSyncCopy.syncEditions.toUpperCase(), findRichText: true),
        findsOneWidget,
        reason: 'the heading stays when narrow',
      );
      expect(
        tester.getTopLeft(find.byType(Switch)).dy,
        greaterThan(tester.getTopLeft(find.text('Read-aloud')).dy),
        reason: 'the switch sits under the editions',
      );
      await tester.tap(find.byType(Switch));
      // The failure waits behind an icon by the heading, with Retry in it.
      expect(find.text('Worker stopped'), findsNothing);
      await tester.tap(find.byIcon(Icons.error_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Worker stopped'), findsOneWidget);
      await tester.tap(find.text(PositionSyncCopy.indexRetry));
      await tester.pumpAndSettle();
      expect((acted, switched), (ChainActionId.retryIndex, false));
    });

    testWidgets('the why opens from the heading and status, a full tap target, in light theme too', (tester) async {
      ChainActionId? acted;
      await pump(
        tester,
        400,
        1,
        brightness: Brightness.light,
        index: const SyncChainIndex(status: EditionSyncIndexStatus.failed, on: true, canRetry: true),
        onIndexSync: (_) {},
        onIndexAction: (id) => acted = id,
      );
      expect(tester.takeException(), isNull);
      final target = tester.getSize(find.byType(PopupMenuButton<ChainActionId>));
      expect(target.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(target.width, greaterThanOrEqualTo(kMinInteractiveDimension));
      await tester.tap(find.text(PositionSyncCopy.indexCantIndex));
      await tester.pumpAndSettle();
      await tester.tap(find.text(PositionSyncCopy.indexRetry));
      await tester.pumpAndSettle();
      expect(acted, ChainActionId.retryIndex);
    });

    testWidgets('the switch keeps its black thumb while a flip goes through', (tester) async {
      await pump(
        tester,
        400,
        1,
        sync: EditionSyncCard.index(
          const SyncChainIndex(status: EditionSyncIndexStatus.ready, on: true, acting: true),
        ),
        onIndexSync: (_) {},
      );
      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.onChanged, isNull);
      expect(sw.thumbColor?.resolve({WidgetState.selected, WidgetState.disabled}), Colors.black87);
    });

    testWidgets(
      'a synced book says what sync does, an off one says Off; synced or without edition sync the total is back',
      (tester) async {
        await pump(tester, 400, 1, index: const SyncChainIndex(status: EditionSyncIndexStatus.ready, on: true));
        expect(find.text(PositionSyncCopy.indexSynced), findsNothing, reason: 'no text beside the switch');
        expect(find.textContaining(PositionSyncCopy.syncEditions.toUpperCase(), findRichText: true), findsOneWidget);
        expect(find.text(PositionSyncCopy.allEditionsKeepProgress), findsOneWidget);
        expect(find.byType(PopupMenuButton<ChainActionId>), findsNothing, reason: 'nothing to explain when synced');
        expect(find.text('2 · 490.6 MB'), findsOneWidget, reason: 'synced leaves the total in the header');
        await pump(
          tester,
          400,
          1,
          index: const SyncChainIndex(
            status: EditionSyncIndexStatus.ready,
            on: false,
            offReason: EditionSyncOffReason.notSelected,
          ),
        );
        expect(find.text(PositionSyncCopy.indexOff), findsOneWidget);
        expect(find.byTooltip(PositionSyncCopy.offNotSelected), findsOneWidget, reason: 'an icon says why it is off');
        expect(find.byType(TextButton), findsNothing);
        expect(find.text(PositionSyncCopy.allEditionsKeepProgress), findsNothing);
        await pump(tester, 400, 1);
        expect(find.byType(Switch), findsNothing);
        expect(find.text('2 · 490.6 MB'), findsOneWidget);
      },
    );

    testWidgets('opening grows each header mark into its row badge, and closing shrinks it back', (tester) async {
      await pump(tester, 400, 1, expanded: false);
      final head = tester.getRect(find.byTooltip('Audiobook'));
      await pump(tester, 400, 1);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 144));
      expect(tester.takeException(), isNull);
      // Halfway, the moving badge sits between the header mark and its row.
      final moving = tester.getRect(find.ancestor(of: find.text('Audiobook'), matching: find.byType(Positioned)));
      await tester.pumpAndSettle();
      final badge = tester.getRect(find.text('Audiobook'));
      expect(moving.top, inExclusiveRange(head.top, badge.bottom));
      expect(moving.width, greaterThan(head.width));
      expect(find.byType(Positioned), findsNothing, reason: 'the moving marks go once open');
      await pump(tester, 400, 1, expanded: false);
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.byType(Positioned), findsWidgets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Read-aloud'), findsNothing);
    });

    testWidgets('narrow with 2x text a synced book still says what sync does, and the switch says how it stands', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        320,
        2,
        index: const SyncChainIndex(status: EditionSyncIndexStatus.ready, on: true),
        onIndexSync: (_) {},
      );
      expect(tester.takeException(), isNull);
      expect(find.text(PositionSyncCopy.allEditionsKeepProgress), findsOneWidget);
      expect(tester.getSize(find.byType(Switch)).height, greaterThanOrEqualTo(48), reason: 'a full tap target');
      expect(
        tester.getSemantics(find.byType(Switch)),
        matchesSemantics(
          label: PositionSyncCopy.syncEditions,
          value: PositionSyncCopy.allEditionsKeepProgress,
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('a book with a read-aloud shows its read-aloud sync and its switch', (tester) async {
      bool? switched;
      await pump(
        tester,
        400,
        1,
        sync: const EditionSyncCard(
          on: true,
          readAlong: true,
          status: EditionSyncStatus(ConnectorState.readAloudSynced, ChainTone.success, PositionSyncCopy.indexSynced),
        ),
        onIndexSync: (on) => switched = on,
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining(PositionSyncCopy.syncEditions.toUpperCase(), findRichText: true), findsOneWidget);
      expect(find.text(PositionSyncCopy.allEditionsKeepProgress), findsOneWidget);
      await tester.tap(find.byType(Switch));
      expect(switched, isFalse);
    });

    testWidgets('collapsed, the header shows the total when synced', (tester) async {
      await pump(
        tester,
        400,
        1,
        expanded: false,
        index: const SyncChainIndex(status: EditionSyncIndexStatus.ready, on: true),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(PositionSyncCopy.indexSynced), findsNothing);
      expect(find.text('2 · 490.6 MB'), findsOneWidget);
    });

    testWidgets('collapsed, the header shows a sync status that is not synced, without the switch', (tester) async {
      await pump(
        tester,
        400,
        1,
        expanded: false,
        index: const SyncChainIndex(status: EditionSyncIndexStatus.none, on: true),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(PositionSyncCopy.indexNotIndexed), findsOneWidget);
      expect(find.text('2 · 490.6 MB'), findsNothing, reason: 'the status takes the total size\'s place');
      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining(PositionSyncCopy.syncEditions.toUpperCase(), findRichText: true), findsNothing);
    });

    testWidgets('fits at 320 px with 2x text', (tester) async {
      await pump(tester, 320, 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Read-aloud'), findsOneWidget);
      // No room for the sizes, in the rows or the header.
      expect(find.text('488.3 MB'), findsNothing);
    });

    testWidgets('shows sizes and opens the sync sheet on a phone at normal text', (tester) async {
      var opened = 0;
      await pump(tester, 400, 1, onOpen: () => opened++);
      expect(tester.takeException(), isNull);
      expect(find.text('488.3 MB'), findsOneWidget);
      expect(find.text('2 · 490.6 MB'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget, reason: "the audiobook row shows the page's progress");
      await tester.tap(find.text('Ebook'));
      await tester.tap(find.text('Create'));
      expect(opened, 2);
    });

    testWidgets('a missing ebook offers a Request pill that sends, not opens', (tester) async {
      var opened = 0, requested = 0;
      await pump(tester, 400, 1,
          book: _book(ebook: null),
          onOpen: () => opened++,
          request: (r) => EditionRequestRow(note: 'No ebook yet', action: 'Request', onTap: () => requested++),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('No ebook yet'), findsOneWidget);
      await tester.tap(find.text('Request'));
      await tester.tap(find.text('No ebook yet'));
      expect((requested, opened), (1, 0));
    });

    testWidgets('a request already made shows its state with no button', (tester) async {
      await pump(tester, 320, 2,
          book: _book(audiobook: null), request: (r) => const EditionRequestRow(note: 'Requested'),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Requested'), findsOneWidget);
      expect(find.text('Request'), findsNothing);
    });
  });
}
