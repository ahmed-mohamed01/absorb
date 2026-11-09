import 'package:absorb/services/fork/cover_frame.dart';
import 'package:absorb/services/fork/fork_settings.dart';
import 'package:absorb/widgets/fork/shelf_cover_frames.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _book([double? frame]) => {
  'media': {if (frame != null) 'coverAspectRatio': frame},
};

void main() {
  test('reads the frame BookOrbit stamps, and nothing else', () {
    expect(forkBookFrame(_book(1)), 1.0);
    expect(forkBookFrame(_book(2 / 3)), forkPortraitFrame);
    expect(forkBookFrame(_book()), isNull);
    expect(forkBookFrame({'media': {'coverAspectRatio': '1/1'}}), isNull);
    expect(forkBookFrame(null), isNull);
  });

  test('both covers only when neither slot is stamped missing', () {
    Map<String, dynamic> v(Object? version) => {'bookOrbit': {'coverVersion': version}};
    expect(forkHasBothCovers(v('audio:2026-10-26T18:59:07.364Z:2026-10-25T16:00:00.557Z')), isTrue);
    expect(forkHasBothCovers(v('ebook:2026-10-25T16:00:00.557Z:2026-10-26T18:59:07.364Z')), isTrue);
    expect(forkHasBothCovers(v('audio:2026-10-26T18:59:07.364Z:-')), isFalse);
    expect(forkHasBothCovers(v('audio:-:2026-01-01T00:00:00.000Z')), isFalse);
    expect(forkHasBothCovers(v('legacy:x')), isFalse);
    expect(forkHasBothCovers(v(null)), isFalse);
    expect(forkHasBothCovers(null), isFalse);
  });

  test('a mixed Dashboard shelf gives each book its shape in a portrait slot', () {
    final frames = ForkShelfFrames([_book(1), _book(2 / 3), _book()], 1.0, ownFrames: true);
    expect(frames.mixed, isTrue);
    expect(frames.hasPortrait, isTrue);
    expect(frames.of(_book(1)), 1.0);
    expect(frames.of(_book()), 1.0);
    expect(frames.slotOf(_book(1)), forkPortraitFrame);
  });

  test('an all-square Dashboard shelf has no portrait room with the rectangle setting', () {
    final frames = ForkShelfFrames([_book(1), _book(1)], forkPortraitFrame, ownFrames: true);
    expect(frames.mixed, isFalse);
    expect(frames.hasPortrait, isFalse);
    expect(frames.slotOf(_book(1)), 1.0);
  });

  test('off the Dashboard every book takes the cover setting', () {
    final frames = ForkShelfFrames([_book(1), _book(2 / 3)], forkPortraitFrame, ownFrames: false);
    expect(frames.mixed, isFalse);
    expect(frames.hasPortrait, isTrue);
    expect(frames.of(_book(1)), forkPortraitFrame);
    final square = ForkShelfFrames(const [], 1.0, ownFrames: false);
    expect(square.hasPortrait, isFalse);
  });

  Future<void> pumpRow(WidgetTester tester, Widget Function(ForkShelfFrames, Map<String, dynamic>, int) cover) async {
    final books = [_book(2 / 3), _book(1)];
    final frames = ForkShelfFrames(books, 1.0, ownFrames: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          for (var i = 0; i < books.length; i++) cover(frames, books[i], i),
        ]),
      ),
    ));
  }

  testWidgets('grid: a square cover is as wide as a portrait one and ends on the same line', (tester) async {
    await pumpRow(tester, (frames, book, i) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 100,
        child: ForkShelfCover(frames: frames, item: book, child: ColoredBox(key: ValueKey('c$i'), color: Colors.grey)),
      ),
    ));
    final portrait = tester.getRect(find.byKey(const ValueKey('c0')));
    final square = tester.getRect(find.byKey(const ValueKey('c1')));
    expect(portrait.size, const Size(100, 150));
    expect(square.size, const Size(100, 100));
    final slot = tester.getRect(find.byType(ForkShelfCover).at(1));
    expect(slot.height, 150);
    expect(square.bottom, slot.bottom);
  });

  testWidgets('list: every thumbnail takes the same width so the titles line up', (tester) async {
    await pumpRow(tester, (frames, book, i) => SizedBox(
      height: 112,
      child: Row(children: [
        ForkShelfCover(frames: frames, item: book, child: ColoredBox(key: ValueKey('c$i'), color: Colors.grey)),
        Expanded(child: Text('Title', key: ValueKey('t$i'))),
      ]),
    ));
    expect(tester.getTopLeft(find.byKey(const ValueKey('t0'))).dx,
        tester.getTopLeft(find.byKey(const ValueKey('t1'))).dx);
    final square = tester.getRect(find.byKey(const ValueKey('c1')));
    expect(square.width, closeTo(112 * 2 / 3, 0.01));
    expect(square.height, closeTo(square.width, 0.01));
    expect(tester.takeException(), isNull);
  });

  // A copy of the series sheet's tile layout: the cover's slot, then the
  // title and a sub-series tile's author line in labelSmall.
  Widget titledTile(double extent, double width, double scale, TextScaler scaler) => MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: Builder(builder: (context) {
            final small = Theme.of(context).textTheme.labelSmall;
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: extent,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const AspectRatio(aspectRatio: 1, child: ColoredBox(color: Colors.grey)),
                  const SizedBox(height: 5),
                  Text('Title', maxLines: 1, style: small?.copyWith(fontSize: 11 * scale)),
                  Text('Author', maxLines: 1, style: small?.copyWith(fontSize: 10 * scale)),
                ]),
              ),
            );
          }),
        ),
      );

  testWidgets('a titled grid cell fits its title and second line at any font size', (tester) async {
    for (final scale in [1.0, 1.5]) {
      for (final font in [1.0, 1.5, 2.0, 3.0]) {
        final scaler = TextScaler.linear(font);
        final width = 100 * scale;
        final extent = forkTitledGridExtent(
            tileWidth: width, slot: 1.0, labelScale: scale, textScaler: scaler, secondLine: true);
        await tester.pumpWidget(titledTile(extent, width, scale, scaler));
        expect(tester.takeException(), isNull, reason: 'label scale $scale, font $font');
      }
    }
  });

  test('a titled grid cell is a portrait slot tall when the slot is portrait', () {
    const scaler = TextScaler.noScaling;
    final square = forkTitledGridExtent(tileWidth: 90, slot: 1.0, labelScale: 1, textScaler: scaler);
    final portrait = forkTitledGridExtent(tileWidth: 90, slot: forkPortraitFrame, labelScale: 1, textScaler: scaler);
    expect(portrait - square, closeTo(90 / forkPortraitFrame - 90, 0.0001));
  });

  test('grid cells keep upstream\'s square ratio and grow for portrait books', () {
    final square = ForkShelfFrames([_book(1), _book(1)], 1.0, ownFrames: true);
    expect(square.gridCellRatio, closeTo(0.65, 0.01));
    final mixed = ForkShelfFrames([_book(1), _book(2 / 3)], 1.0, ownFrames: true);
    expect(mixed.gridCellRatio, closeTo(1 / (1.5 + forkGridTitleShare), 0.0001));
  });

  test('the cover strip gives each cover its own width and overlaps them', () {
    final frames = ForkShelfFrames([_book(2 / 3), _book(1)], 1.0, ownFrames: true);
    final strip = forkCoverStrip([_book(2 / 3), _book(1), _book(2 / 3)], frames, height: 90);
    expect(strip.widths, [60, 90, 60]);
    expect(strip.lefts[0], 0);
    expect(strip.lefts[1], closeTo(60 * 0.68, 0.0001));
    expect(strip.lefts[2], closeTo(60 * 0.68 + 90 * 0.68, 0.0001));
    expect(strip.width, closeTo(strip.lefts[2] + 60, 0.0001));
    expect(forkCoverStrip([], frames).width, 0);
  });

  group('grids laid out as BookOrbit does', () {
    tearDown(() => ForkSettings.ownCoverShapes = true);

    test('a mixed grid gives every cover a square slot and square cells', () {
      final frames = forkGridFrames([_book(1), _book(2 / 3)], 1.0);
      expect(forkGridSlot(frames, _book(1)), 1.0);
      expect(forkGridSlot(frames, _book(2 / 3)), 1.0);
      expect(frames.of(_book(2 / 3)), forkPortraitFrame);
      expect(forkGridTall(frames), isFalse);
    });

    test('an all-portrait grid keeps portrait slots and tall cells', () {
      final frames = forkGridFrames([_book(2 / 3), _book(2 / 3)], 1.0);
      expect(forkGridSlot(frames, _book(2 / 3)), forkPortraitFrame);
      expect(forkGridTall(frames), isTrue);
    });

    test('an all-square grid stays square under the rectangle setting', () {
      final frames = forkGridFrames([_book(1), _book(1)], forkPortraitFrame);
      expect(forkGridSlot(frames, _book(1)), 1.0);
      expect(forkGridTall(frames), isFalse);
    });

    test('books without a frame follow the cover setting', () {
      final square = forkGridFrames([_book(), _book()], 1.0);
      expect(forkGridSlot(square, _book()), 1.0);
      expect(forkGridTall(square), isFalse);
      final rect = forkGridFrames([_book(), _book()], forkPortraitFrame);
      expect(forkGridSlot(rect, _book()), forkPortraitFrame);
      expect(forkGridTall(rect), isTrue);
    });

    test('with the switch off every cover takes the cover setting', () {
      ForkSettings.ownCoverShapes = false;
      final frames = forkGridFrames([_book(1), _book(2 / 3)], 1.0);
      expect(frames.of(_book(2 / 3)), 1.0);
      expect(forkGridSlot(frames, _book(2 / 3)), 1.0);
      expect(forkGridTall(frames), isFalse);
    });

    testWidgets('a portrait cover in a square slot is as tall, narrower and centred', (tester) async {
      const key = Key('cover');
      await tester.pumpWidget(Center(
        child: SizedBox(
          width: 90,
          child: forkCoverInSlot(1.0, const AspectRatio(aspectRatio: 2 / 3, child: SizedBox(key: key))),
        ),
      ));
      final slot = tester.getRect(find.byType(Center).last);
      final cover = tester.getRect(find.byKey(key));
      expect(slot.size, const Size(90, 90));
      expect(cover.height, 90);
      expect(cover.width, closeTo(60, 0.001));
      expect(cover.center.dx, closeTo(slot.center.dx, 0.001));
    });

    test('a cell is the Library grid\'s: tall only when every cover is portrait', () {
      expect(forkGridCellRatio(forkGridFrames([_book(1), _book(2 / 3)], 1.0)), 0.68);
      expect(forkGridCellRatio(forkGridFrames([_book(1), _book(1)], forkPortraitFrame)), 0.68);
      expect(forkGridCellRatio(forkGridFrames([_book(2 / 3), _book(2 / 3)], 1.0)), 0.48);
    });

    test('a Dashboard shelf of nothing but ebooks has the audiobook shelf\'s square slot', () {
      expect(forkDashboardSlot(forkGridFrames([_book(2 / 3), _book(2 / 3)], 1.0)), 1.0);
      expect(forkDashboardSlot(forkGridFrames([_book(1), _book(1)], 1.0)), 1.0);
      expect(forkDashboardSlot(forkGridFrames([_book(1), _book(2 / 3)], forkPortraitFrame)), 1.0);
    });

    test('with the switch off a Dashboard shelf takes the cover setting', () {
      ForkSettings.ownCoverShapes = false;
      expect(forkDashboardSlot(forkGridFrames([_book(1)], forkPortraitFrame)), forkPortraitFrame);
      expect(forkDashboardSlot(forkGridFrames([_book(2 / 3)], 1.0)), 1.0);
    });

    test('off the Dashboard a sheet takes the cover setting, and on it the switch decides', () {
      final book = _book(2 / 3);
      expect(forkSheetFrames([book], 1.0, dashboard: false).of(book), 1.0);
      expect(forkSheetFrames([book], 1.0, dashboard: true).of(book), forkPortraitFrame);
      ForkSettings.ownCoverShapes = false;
      expect(forkSheetFrames([book], 1.0, dashboard: true).of(book), 1.0);
    });

    testWidgets('Dashboard covers read a playlist entry\'s nested book and size from the tile', (tester) async {
      late ForkDashboardCovers covers;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Builder(builder: (context) {
          covers = ForkDashboardCovers.of(context, [{'libraryItem': _book(2 / 3)}, _book(1)], 1.0);
          return const SizedBox();
        }),
      ));
      expect(covers.frames.mixed, isTrue);
      expect(covers.slot, 1.0);
      expect(covers.coverHeight, covers.tileWidth);
      expect(covers.heroCardWidth, covers.tileWidth + 20);
      expect(covers.heroRowHeight, covers.tileWidth + 120);
    });

    testWidgets('with a slot a list cover is the row\'s full height, centred, and titles line up', (tester) async {
      final books = [_book(2 / 3), _book(1)];
      final frames = ForkShelfFrames(books, 1.0, ownFrames: true);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            for (var i = 0; i < books.length; i++)
              SizedBox(
                height: 112,
                child: Row(children: [
                  ForkShelfCover(frames: frames, item: books[i], slot: 1.0, child: ColoredBox(key: ValueKey('c$i'), color: Colors.grey)),
                  Expanded(child: Text('Title', key: ValueKey('t$i'))),
                ]),
              ),
          ]),
        ),
      ));
      final portrait = tester.getRect(find.byKey(const ValueKey('c0')));
      final square = tester.getRect(find.byKey(const ValueKey('c1')));
      expect(portrait.height, 112);
      expect(square.height, 112);
      expect(portrait.width, closeTo(112 * 2 / 3, 0.01));
      expect(portrait.center.dx, closeTo(square.center.dx, 0.01));
      expect(tester.getTopLeft(find.byKey(const ValueKey('t0'))).dx,
          tester.getTopLeft(find.byKey(const ValueKey('t1'))).dx);
    });

    test('no slot leaves the cover as it is', () {
      const cover = SizedBox(key: Key('cover'));
      expect(forkCoverInSlot(null, cover), same(cover));
    });
  });
}
