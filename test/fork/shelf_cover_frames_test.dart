import 'package:absorb/services/fork/cover_frame.dart';
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

  testWidgets('grid tile: a square cover drops to the bottom of a portrait slot', (tester) async {
    final frames = ForkShelfFrames([_book(2 / 3), _book(1)], 1.0, ownFrames: true);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 100,
          height: 200,
          child: ForkShelfGridTile(
            frames: frames,
            item: _book(1),
            child: const Column(children: [
              AspectRatio(aspectRatio: 1, child: ColoredBox(key: ValueKey('cover'), color: Colors.grey)),
            ]),
          ),
        ),
      ),
    ));
    final cover = tester.getRect(find.byKey(const ValueKey('cover')));
    expect(cover.top, closeTo(50, 0.01));
    expect(cover.bottom, closeTo(150, 0.01));
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
}
