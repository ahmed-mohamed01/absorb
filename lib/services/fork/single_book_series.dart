// Fork-owned: with Collapse series on, a series that holds one book shows as
// that book when ForkSettings.singleBookSeriesAsBooks is on. Pure Dart, so
// it is unit-tested in test/fork/single_book_series_test.dart. See
// FORK_NOTES.md.
import 'fork_settings.dart';

/// Whether a collapsed series of [bookCount] books shows as its one book.
bool forkSeriesShowsAsBook(int bookCount, {bool? enabled}) =>
    (enabled ?? ForkSettings.singleBookSeriesAsBooks) && bookCount == 1;

// The book made from each one-book series item, so a grid rebuild hands its
// tile the same map rather than a new copy.
final _asBook = Expando<Map<String, dynamic>>('forkSingleBookSeries');

/// [items] from a collapsed library page with every one-book series item
/// shown as its book: the representative item (the book itself on both
/// BookOrbit and Audiobookshelf) without its `collapsedSeries`. Returns
/// [items] itself when nothing changes.
List<Map<String, dynamic>> forkUncollapseSingles(List<Map<String, dynamic>> items, {bool? enabled}) {
  if (!(enabled ?? ForkSettings.singleBookSeriesAsBooks)) return items;
  List<Map<String, dynamic>>? out;
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final collapsed = item['collapsedSeries'];
    if (collapsed is! Map) continue;
    final count = collapsed['numBooks'];
    if (count is! num || !forkSeriesShowsAsBook(count.toInt(), enabled: true)) continue;
    out ??= List.of(items);
    out[i] = _asBook[item] ??= Map.of(item)..remove('collapsedSeries');
  }
  return out ?? items;
}

// The series each book the author sheet shows for a one-book series came
// from, so its row still finds its number.
final _seriesLabel = Expando<String>('forkSeriesBookLabel');

/// Adds [books] to the author sheet's collapsed [items] as books, skipping
/// one already listed (a book in two one-book series shows once), and
/// remembers [seriesLabel] for each for [forkSeriesBookLabel].
void forkAddSectionBooks(List<dynamic> items, List<Map<String, dynamic>> books, String? seriesLabel) {
  for (final book in books) {
    final id = book['id'];
    if (id != null && items.any((i) => i is Map && i['id'] == id)) continue;
    if (seriesLabel != null) _seriesLabel[book] = seriesLabel;
    items.add(book);
  }
}

/// The series [book] was added for by [forkAddSectionBooks], if any.
String? forkSeriesBookLabel(Map<String, dynamic> book) => _seriesLabel[book];
