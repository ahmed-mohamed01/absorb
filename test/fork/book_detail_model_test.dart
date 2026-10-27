import 'package:absorb/widgets/fork/book_detail_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('forkDisplayTitle', () {
    test('moves a ": subtitle" off the title when the book has none', () {
      final t = forkDisplayTitle(title: 'Velocity Weapon: A Novel', subtitle: '', series: const []);
      expect(t.title, 'Velocity Weapon');
      expect(t.subtitle, 'A Novel');
    });

    test('keeps the book\'s own subtitle and still trims the title', () {
      final t = forkDisplayTitle(
          title: 'He Who Fights with Monsters 13: A LitRPG Adventure', subtitle: 'An Epic Tale', series: const []);
      expect(t.title, 'He Who Fights with Monsters 13');
      expect(t.subtitle, 'An Epic Tale');
    });

    test('hides "Book 13" beside a series numbered 13', () {
      final t = forkDisplayTitle(title: 'X', subtitle: 'Book 13', series: [
        {'name': 'He Who Fights with Monsters', 'sequence': '13'},
      ]);
      expect(t.subtitle, '');
    });

    test('keeps "Book 2" when the series number differs', () {
      final t = forkDisplayTitle(title: 'X', subtitle: 'Book 2', series: [
        {'name': 'Saga', 'sequence': '1'},
      ]);
      expect(t.subtitle, 'Book 2');
    });

    test('hides a subtitle that names the series', () {
      final t = forkDisplayTitle(title: 'On Basilisk Station', subtitle: '1 (Honor Harrington)', series: [
        {'name': 'Honor Harrington', 'sequence': '1'},
      ]);
      expect(t.subtitle, '');
    });

    test('takes a series number that arrives as a number', () {
      final t = forkDisplayTitle(title: 'X', subtitle: 'Volume 3', series: [
        {'name': 'Saga', 'sequence': 3},
      ]);
      expect(t.subtitle, '');
    });
  });

  group('series', () {
    test('the pill shows the first numbered series, the rest as others', () {
      final s = forkMainSeries([
        {'name': 'Honorverse'},
        {'name': 'Honor Harrington', 'sequence': '1'},
        {'name': 'Honor Harrington FRG', 'sequence': '1'},
      ])!;
      expect(forkSeriesLabel(s.main), 'Honor Harrington #1');
      expect(s.others.map(forkSeriesLabel), ['Honorverse', 'Honor Harrington FRG #1']);
    });

    test('works on a typed List<Map> from the cached seed', () {
      // The crash that blanked the page: firstWhere(orElse:) on a list whose
      // runtime type is narrower than List<dynamic>.
      final typed = <Map<String, dynamic>>[
        {'name': 'A'},
        {'name': 'B', 'sequence': '2'},
      ];
      expect(forkSeriesLabel(forkMainSeries(typed)!.main), 'B #2');
    });

    test('no series, no pill', () => expect(forkMainSeries(const []), isNull));

    test('a number without a name labels as nothing', () => expect(forkSeriesLabel({'sequence': 4}), ''));
  });

  group('forkSimilarToShow', () {
    test('drops this book, its other editions and repeated titles', () {
      final out = forkSimilarToShow([
        {'id': '1', 'title': 'On Basilisk Station'},
        {'id': '9', 'title': 'On Basilisk Station'},
        {'id': '2', 'title': 'Dauntless'},
        {'id': '3', 'title': 'Dauntless'},
        {'id': '4', 'title': 'He Who Fights with Monsters 13'},
        {'id': '5', 'title': 'A Soldier\'s Duty'},
      ], itemId: '1', title: 'On Basilisk Station');
      expect(out.map((b) => b['id']), ['2', '4', '5']);
    });

    test('compares titles without a subtitle', () {
      final out = forkSimilarToShow([
        {'id': '7', 'title': 'He Who Fights with Monsters 13'},
      ], itemId: '1', title: 'He Who Fights with Monsters 13: A LitRPG Adventure');
      expect(out, isEmpty);
    });
  });

  group('small values', () {
    test('page count from either key, as a string or number', () {
      expect(forkPageCount({'pageCount': 266}), 266);
      expect(forkPageCount({'pages': '383'}), 383);
      expect(forkPageCount({}), 0);
    });

    test('a zero date is no date', () {
      expect(forkDate(0), isNull);
      expect(forkDate(null), isNull);
      expect(forkDate(1793030000000), 1793030000000);
    });
  });

  group('reading status', () {
    test('Audiobookshelf shows where you are', () {
      expect(forkShownStatus(isBookOrbit: false, bookOrbitStatus: null, isFinished: false, progress: 0), 'unread');
      expect(forkShownStatus(isBookOrbit: false, bookOrbitStatus: null, isFinished: false, progress: .2), 'reading');
      expect(forkShownStatus(isBookOrbit: false, bookOrbitStatus: null, isFinished: true, progress: 1), 'read');
    });

    test('BookOrbit squares its status with the finish state', () {
      expect(forkShownStatus(isBookOrbit: true, bookOrbitStatus: 'on_hold', isFinished: true, progress: 1), 'read');
      expect(forkShownStatus(isBookOrbit: true, bookOrbitStatus: 'skimmed', isFinished: false, progress: .4), 'reading');
      expect(forkShownStatus(isBookOrbit: true, bookOrbitStatus: 'abandoned', isFinished: false, progress: .4), 'abandoned');
    });

    test('options: all eight on BookOrbit, two on Audiobookshelf', () {
      expect(forkStatusOptions(isBookOrbit: true, isFinished: false, current: 'reading'), hasLength(8));
      expect(forkStatusOptions(isBookOrbit: false, isFinished: false, current: 'unread'), ['unread', 'read']);
      expect(forkStatusOptions(isBookOrbit: false, isFinished: true, current: 'read'), ['reading', 'read']);
    });

    test('plan: Skimmed to Read on a finished book still saves Read', () {
      final p = forkStatusPlan(picked: 'read', isFinished: true, isBookOrbit: true);
      expect(p.finish, isNull);
      expect(p.saveStatus, isTrue);
    });

    test('plan: Read on an unfinished book finishes it and lets BookOrbit say Read', () {
      final p = forkStatusPlan(picked: 'read', isFinished: false, isBookOrbit: true);
      expect(p.finish, isTrue);
      expect(p.saveStatus, isFalse);
    });

    test('plan: Abandoned on a finished book unfinishes it, then saves', () {
      final p = forkStatusPlan(picked: 'abandoned', isFinished: true, isBookOrbit: true);
      expect(p.finish, isFalse);
      expect(p.saveStatus, isTrue);
    });

    test('plan: Audiobookshelf never saves a status', () {
      expect(forkStatusPlan(picked: 'read', isFinished: false, isBookOrbit: false).saveStatus, isFalse);
    });
  });

  group('tabs', () {
    String pick({
      List<String> tabs = const ['similar', 'chapters', 'bookmarks'],
      String preferred = 'similar',
      bool userPicked = false,
      bool similarReady = false,
      bool similarRequested = true,
      bool similarFetched = false,
      bool offline = false,
      bool hasChapters = true,
    }) =>
        forkSelectedTab(
          tabs: tabs,
          preferred: preferred,
          userPicked: userPicked,
          similarReady: similarReady,
          similarRequested: similarRequested,
          similarFetched: similarFetched,
          offline: offline,
          hasChapters: hasChapters,
        );

    test('stays on More like this while the books load', () => expect(pick(), 'similar'));
    test('opens on Chapters when none came back', () => expect(pick(similarFetched: true), 'chapters'));
    test('opens on Chapters when none was asked for', () => expect(pick(similarRequested: false), 'chapters'));
    test('opens on Chapters offline', () => expect(pick(offline: true), 'chapters'));
    test('respects a tab the reader picked', () => expect(pick(similarFetched: true, userPicked: true), 'similar'));
    test('keeps More like this when the book has no chapters',
        () => expect(pick(similarFetched: true, hasChapters: false), 'similar'));
    test('falls back to the first tab there is', () => expect(pick(tabs: const ['chapters', 'bookmarks']), 'chapters'));
    test('no tabs, none open', () => expect(pick(tabs: const []), ''));

    test('loading only while a request is out', () {
      expect(forkSimilarLoading(similarReady: false, similarRequested: true, similarFetched: false, offline: false), isTrue);
      expect(forkSimilarLoading(similarReady: false, similarRequested: false, similarFetched: false, offline: false), isFalse);
      expect(forkSimilarLoading(similarReady: false, similarRequested: true, similarFetched: true, offline: false), isFalse);
      expect(forkSimilarLoading(similarReady: false, similarRequested: true, similarFetched: false, offline: true), isFalse);
    });
  });

  test('status chevron needs room', () {
    // A 360dp phone (320 of page) with three cells is tight; a 412dp one isn't.
    expect(forkStatusCellRoomy(pageWidth: 320, otherCells: 2, textScale: 1), isFalse);
    expect(forkStatusCellRoomy(pageWidth: 380, otherCells: 2, textScale: 1), isTrue);
    expect(forkStatusCellRoomy(pageWidth: 320, otherCells: 1, textScale: 1), isTrue);
    expect(forkStatusCellRoomy(pageWidth: 600, otherCells: 2, textScale: 1.3), isFalse);
  });
}
