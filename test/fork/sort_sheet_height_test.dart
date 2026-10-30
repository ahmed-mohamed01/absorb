import 'package:absorb/widgets/fork/sort_sheet_height.dart';
import 'package:absorb/widgets/library_sort_filter_sheet.dart' show LibraryTab;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<double> _height(WidgetTester tester,
    {LibraryTab tab = LibraryTab.library, bool podcast = false, int rows = 9, double screen = 900}) async {
  late double h;
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: Size(400, screen)),
    child: Builder(builder: (context) {
      h = forkLibrarySortHeight(context, 440, tab: tab, podcast: podcast, rows: rows);
      return const SizedBox();
    }),
  ));
  return h;
}

void main() {
  test('only a book library\'s Library tab has the Collapse series switch', () {
    expect(forkLibraryHasCollapseSwitch(LibraryTab.library, podcast: false), isTrue);
    expect(forkLibraryHasCollapseSwitch(LibraryTab.library, podcast: true), isFalse);
    expect(forkLibraryHasCollapseSwitch(LibraryTab.series, podcast: false), isFalse);
  });

  testWidgets('nine sorts and the switch get more than upstream\'s 440', (tester) async {
    expect(await _height(tester), greaterThan(490));
  });

  testWidgets('a short list and other tabs keep upstream\'s height', (tester) async {
    expect(await _height(tester, podcast: true, rows: 8), 440);
    expect(await _height(tester, tab: LibraryTab.series), 440);
  });

  testWidgets('a short screen caps it, but never below upstream', (tester) async {
    expect(await _height(tester, rows: 30, screen: 1000), 700);
    expect(await _height(tester, rows: 30, screen: 500), 440);
  });
}
