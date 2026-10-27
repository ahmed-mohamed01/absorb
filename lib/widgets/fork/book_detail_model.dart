// Fork-owned: the decisions the redesigned book detail page makes from a
// book's data, kept free of Flutter so they can be unit-tested
// (test/fork/book_detail_model_test.dart). book_detail_redesign.dart draws
// what these return. See FORK_NOTES.md.
//
// Maps from the server and from the cached seed differ in their static types
// (a seed's series list is a List<Map<String, dynamic>>), so nothing here
// casts a list or calls firstWhere(orElse:) on one.

/// The flex the stat strip gives the status cell and each other cell; the
/// status and its date need the most room.
const forkStatusCellFlex = 3;
const forkOtherCellFlex = 2;

/// The title and subtitle the page shows.
///
/// A title carrying its subtitle ("… 13: A LitRPG Adventure") ran to three
/// lines, so the part after the colon comes off; it becomes the subtitle when
/// the book has none of its own. A subtitle that only restates the series
/// ("1 (Honor Harrington)", or "Book 13" beside a "#13" series) is dropped.
/// An empty subtitle means none is shown.
({String title, String subtitle}) forkDisplayTitle({
  required String title,
  required String subtitle,
  required List<dynamic> series,
}) {
  final colon = title.indexOf(': ');
  final mainTitle = colon > 0 ? title.substring(0, colon).trim() : title;
  final shown = subtitle.isNotEmpty ? subtitle : colon > 0 ? title.substring(colon + 2).trim() : '';
  if (shown.isEmpty) return (title: mainTitle, subtitle: '');
  final sequences = <String>{for (final s in series) _sequence(s)}..remove('');
  final bookNumber =
      RegExp(r'^(book|volume|vol\.?|part)\s*(\S+)$', caseSensitive: false).firstMatch(shown.trim());
  if (bookNumber != null && sequences.contains(bookNumber.group(2))) return (title: mainTitle, subtitle: '');
  final lower = shown.toLowerCase();
  for (final s in series) {
    final name = _name(s).toLowerCase();
    if (name.isNotEmpty && lower.contains(name)) return (title: mainTitle, subtitle: '');
  }
  return (title: mainTitle, subtitle: shown);
}

/// "Name #3", or just the name when the series has no number (and nothing
/// when it has no name). The number may arrive as a string or a number.
String forkSeriesLabel(dynamic s) {
  final name = _name(s);
  final seq = _sequence(s);
  return name.isEmpty || seq.isEmpty ? name : '$name #$seq';
}

/// The series the pill shows (the first with a number) and the rest, which a
/// "+N" offers. Null when the book is in no series.
({dynamic main, List<dynamic> others})? forkMainSeries(List<dynamic> series) {
  if (series.isEmpty) return null;
  dynamic main = series.first;
  for (final s in series) {
    if (_sequence(s).isNotEmpty) {
      main = s;
      break;
    }
  }
  return (main: main, others: [for (final s in series) if (!identical(s, main)) s]);
}

/// BookOrbit's similar books as the page shows them: never this book or
/// another edition of it, and each title once (titles compare without a
/// subtitle, since one edition may carry ": A LitRPG Adventure" and another
/// not).
List<Map<String, dynamic>> forkSimilarToShow(List<Map<String, dynamic>> similar,
    {required String itemId, required String title}) {
  String key(Object? t) => '${t ?? ''}'.split(':').first.trim().toLowerCase();
  final seen = {key(title)};
  return [
    for (final b in similar)
      if (b['id'] != itemId && seen.add(key(b['title']))) b,
  ];
}

/// The book's page count, or 0 when it has none.
int forkPageCount(Map<String, dynamic> metadata) =>
    num.tryParse('${metadata['pageCount'] ?? metadata['pages'] ?? ''}')?.toInt() ?? 0;

/// A date in milliseconds, or null for none: BookOrbit's mapper falls back to
/// the last playback, which is 0 for a book never played.
int? forkDate(Object? ms) {
  final v = ms is num ? ms.toInt() : null;
  return v != null && v > 0 ? v : null;
}

/// The reading status the strip shows. Audiobookshelf has no status of its
/// own, so it shows where you are; BookOrbit's is squared with the finish
/// state (Read and Skimmed mean finished, everything else not), which the
/// finish button changes without the status following.
String forkShownStatus({
  required bool isBookOrbit,
  required String? bookOrbitStatus,
  required bool isFinished,
  required double progress,
}) {
  if (!isBookOrbit) return isFinished ? 'read' : progress > 0 ? 'reading' : 'unread';
  final s = bookOrbitStatus ?? 'unread';
  final done = s == 'read' || s == 'skimmed';
  if (isFinished && !done) return 'read';
  if (!isFinished && done) return 'reading';
  return s;
}

/// What the status picker offers. BookOrbit gets every status it has;
/// Audiobookshelf only knows finished or not.
List<String> forkStatusOptions({required bool isBookOrbit, required bool isFinished, required String current}) =>
    isBookOrbit
        ? const ['unread', 'want_to_read', 'reading', 'on_hold', 'rereading', 'read', 'skimmed', 'abandoned']
        : [isFinished ? 'reading' : current, 'read'];

/// What picking [picked] has to do: move the finish state first (true =
/// finish, false = unfinish, null = leave it), then whether to save the
/// status on BookOrbit. BookOrbit calls a book it was just told is finished
/// Read, but one already finished (say Skimmed) still needs Read set.
({bool? finish, bool saveStatus}) forkStatusPlan({
  required String picked,
  required bool isFinished,
  required bool isBookOrbit,
}) {
  final done = picked == 'read' || picked == 'skimmed';
  final moved = done != isFinished;
  return (
    finish: moved ? done : null,
    saveStatus: isBookOrbit && !(picked == 'read' && moved),
  );
}

/// Which tab is open: the one asked for, unless it's More like this with
/// nothing to show (none came back, none was asked for, or offline), when the
/// page opens on the chapters until the reader picks a tab themselves. Falls
/// back to the first tab there is; '' when there are none.
String forkSelectedTab({
  required List<String> tabs,
  required String preferred,
  required bool userPicked,
  required bool similarReady,
  required bool similarRequested,
  required bool similarFetched,
  required bool offline,
  required bool hasChapters,
}) {
  var want = preferred;
  if (!userPicked && want == 'similar' && !similarReady &&
      (!similarRequested || similarFetched || offline) && hasChapters && tabs.contains('chapters')) {
    want = 'chapters';
  }
  return tabs.contains(want) ? want : (tabs.isEmpty ? '' : tabs.first);
}

/// Whether the similar books are still on their way: only while a request is
/// actually out (a book from the offline fallback never starts one).
bool forkSimilarLoading({
  required bool similarReady,
  required bool similarRequested,
  required bool similarFetched,
  required bool offline,
}) =>
    !similarReady && similarRequested && !similarFetched && !offline;

/// Whether the status cell has room for its chevron, worked out from the page
/// width and the cells the strip has, since the strip's IntrinsicHeight can't
/// hold a LayoutBuilder.
bool forkStatusCellRoomy({required double pageWidth, required int otherCells, required double textScale}) =>
    pageWidth * forkStatusCellFlex / (forkStatusCellFlex + forkOtherCellFlex * otherCells) - 8 >= 140 &&
    textScale <= 1.15;

String _sequence(dynamic s) => s is Map ? '${s['sequence'] ?? ''}'.trim() : '';
String _name(dynamic s) => s is Map ? '${s['name'] ?? ''}'.trim() : '';
