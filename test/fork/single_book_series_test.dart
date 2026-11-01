import 'package:absorb/services/fork/fork_settings.dart';
import 'package:absorb/services/fork/single_book_series.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _series(String id, int numBooks) => {
      'id': id,
      'media': {'metadata': {'title': 'Book $id'}},
      'collapsedSeries': {'id': 'ser-$id', 'name': 'Series $id', 'numBooks': numBooks},
    };

void main() {
  tearDown(() => ForkSettings.singleBookSeriesAsBooks = true);

  test('a one-book series becomes its book, others stay', () {
    final book = {'id': 'b', 'media': {}};
    final items = [_series('a', 1), book, _series('c', 3)];
    final out = forkUncollapseSingles(items, enabled: true);
    expect(out, hasLength(3));
    expect(out[0]['id'], 'a');
    expect(out[0].containsKey('collapsedSeries'), isFalse);
    expect(out[0]['media'], same(items[0]['media']));
    expect(out[1], same(book));
    expect(out[2], same(items[2]));
    // The page's own list and item are untouched.
    expect(items[0].containsKey('collapsedSeries'), isTrue);
  });

  test('the same item gives the same book map on every rebuild', () {
    final items = [_series('a', 1)];
    expect(forkUncollapseSingles(items, enabled: true)[0],
        same(forkUncollapseSingles(items, enabled: true)[0]));
  });

  test('returns the list itself when off or nothing changes', () {
    final items = [_series('a', 1)];
    expect(forkUncollapseSingles(items, enabled: false), same(items));
    final many = [_series('a', 2), {'id': 'b'}];
    expect(forkUncollapseSingles(many, enabled: true), same(many));
  });

  test('a numBooks of 0 or missing stays a series; a double count works', () {
    final zero = [_series('a', 0)];
    expect(forkUncollapseSingles(zero, enabled: true), same(zero));
    final missing = [
      {'id': 'a', 'collapsedSeries': {'name': 'x'}}
    ];
    expect(forkUncollapseSingles(missing, enabled: true), same(missing));
    final asDouble = [
      {'id': 'a', 'collapsedSeries': {'numBooks': 1.0}}
    ];
    expect(forkUncollapseSingles(asDouble, enabled: true)[0].containsKey('collapsedSeries'), isFalse);
  });

  test('follows the setting by default', () {
    final items = [_series('a', 1)];
    ForkSettings.singleBookSeriesAsBooks = false;
    expect(forkUncollapseSingles(items), same(items));
    expect(forkSeriesShowsAsBook(1), isFalse);
    ForkSettings.singleBookSeriesAsBooks = true;
    expect(forkUncollapseSingles(items)[0].containsKey('collapsedSeries'), isFalse);
    expect(forkSeriesShowsAsBook(1), isTrue);
    expect(forkSeriesShowsAsBook(2), isFalse);
  });

  test('author sheet books: one per id, with their series label', () {
    final a = {'id': 'a'};
    final b = {'id': 'b'};
    final items = <dynamic>['series tile'];
    forkAddSectionBooks(items, [a], 'Saga');
    forkAddSectionBooks(items, [a], 'Other saga');
    forkAddSectionBooks(items, [b], null);
    expect(items, ['series tile', a, b]);
    expect(forkSeriesBookLabel(a), 'Saga');
    expect(forkSeriesBookLabel(b), isNull);
  });

  test('author sheet books without ids are all kept', () {
    final items = <dynamic>[];
    forkAddSectionBooks(items, [{'t': 1}, {'t': 2}], null);
    expect(items, hasLength(2));
  });
}
