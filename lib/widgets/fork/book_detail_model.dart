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
/// A title that ends with its own subtitle loses that end.
/// An empty subtitle means none is shown.
({String title, String subtitle}) forkDisplayTitle({
  required String title,
  required String subtitle,
  required List<dynamic> series,
}) {
  final colon = title.indexOf(': ');
  var mainTitle = colon > 0 ? title.substring(0, colon).trim() : title;
  final shown = subtitle.isNotEmpty ? subtitle : colon > 0 ? title.substring(colon + 2).trim() : '';
  // Some titles end with their own subtitle; it reads once, on its own line.
  if (shown.isNotEmpty && mainTitle.length > shown.length && mainTitle.toLowerCase().endsWith(shown.toLowerCase())) {
    mainTitle = mainTitle.substring(0, mainTitle.length - shown.length).replaceFirst(RegExp(r'[\s,:;\-–—]+$'), '');
  }
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

/// A book's `series` as a list. The server sends a list; a series sheet
/// hands the item over with one map, the number it lists the book under.
List<dynamic> forkSeriesEntries(Object? raw) => raw is List ? raw : raw is Map ? [raw] : const [];

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

/// The other books in [series] (this book's entry in it), in reading order,
/// as tiles the page draws: `{id, title, hasCover, sequence}`. [raw] is the
/// series fetch (library items, or ABS's `{libraryItem, sequence}`
/// wrappers). Never this book or another edition of it: editions share a
/// number, so each number shows once, and a book with none once per title.
/// Titles compare whole, since "Name: Volume 2" is a different book from
/// "Name: Volume 1". Books with no number go last.
List<Map<String, dynamic>> forkSeriesBooksToShow(List<dynamic> raw,
    {required String itemId, required String title, required dynamic series}) {
  final seriesId = series is Map ? '${series['id'] ?? ''}' : '';
  final seriesName = _name(series);
  String key(String sequence, String t) => sequence.isNotEmpty ? '#$sequence' : t.trim().toLowerCase();
  final seen = {key(_sequence(series), title), key('', title)};
  final out = <Map<String, dynamic>>[];
  for (final r in raw) {
    if (r is! Map) continue;
    final item = r['libraryItem'] is Map ? r['libraryItem'] as Map : r;
    final id = item['id'];
    final media = item['media'] is Map ? item['media'] as Map : const {};
    final metadata = media['metadata'] is Map ? media['metadata'] as Map : const {};
    final bookTitle = '${metadata['title'] ?? item['title'] ?? ''}';
    final sequence = '${r['sequence'] ?? item['sequence'] ?? _seriesSequence(metadata, seriesId, seriesName)}'.trim();
    if (id is! String || id == itemId || !seen.add(key(sequence, bookTitle))) continue;
    out.add({
      'id': id,
      'title': bookTitle,
      'hasCover': item['hasCover'] == true || media['coverPath'] != null,
      'sequence': sequence,
    });
  }
  double order(Map<String, dynamic> b) =>
      double.tryParse(RegExp(r'^[\d.]+').stringMatch(b['sequence'] as String) ?? '') ?? double.maxFinite;
  // A stable sort, so books without a number keep the server's order.
  final indexed = out.asMap().entries.toList()
    ..sort((a, b) {
      final c = order(a.value).compareTo(order(b.value));
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

/// A book's number in one series: its entry in `series` (a list or a single
/// map) matched by id or name, else the joined `seriesName` ("Name #3, ...")
/// that minified items carry. Empty when it has none.
String _seriesSequence(Map metadata, String seriesId, String seriesName) {
  final list = forkSeriesEntries(metadata['series']);
  final wanted = seriesName.trim().toLowerCase();
  for (final s in list) {
    if (s is! Map) continue;
    if ((seriesId.isNotEmpty && s['id'] == seriesId) || (wanted.isNotEmpty && _name(s).toLowerCase() == wanted)) {
      return _sequence(s);
    }
  }
  for (final entry in '${metadata['seriesName'] ?? ''}'.split(',')) {
    final m = RegExp(r'^(.+?)\s*#\s*([\d.]+)$').firstMatch(entry.trim());
    if (m != null && m.group(1)!.trim().toLowerCase() == wanted) return m.group(2)!;
  }
  return '';
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

/// Which tab is open: the one asked for, unless it's Related (the `similar`
/// tab: the series and similar books) with nothing to show (none came back,
/// none was asked for, or offline), when the
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

/// The lines the title and subtitle beside the cover get from [height]: all
/// of them when they fit. Otherwise the title comes first, keeping one line
/// for the subtitle, and the subtitle has what's left. A title always gets two
/// lines however tight it is. [clipped] says some text was cut, so a tap has
/// something to show.
({int title, int subtitle, bool clipped}) forkFitTitleLines({
  required int titleLines,
  required int subtitleLines,
  required double titleLineHeight,
  required double subtitleLineHeight,
  required double gap,
  required double height,
}) {
  double subtitleBlock(int lines) => lines > 0 ? gap + lines * subtitleLineHeight : 0;
  if (titleLines * titleLineHeight + subtitleBlock(subtitleLines) <= height) {
    return (title: titleLines, subtitle: subtitleLines, clipped: false);
  }
  final titleRoom = height - subtitleBlock(subtitleLines > 0 ? 1 : 0);
  final title = (titleRoom / titleLineHeight).floor().clamp(titleLines < 2 ? titleLines : 2, titleLines);
  final subtitle = subtitleLines == 0
      ? 0
      : ((height - title * titleLineHeight - gap) / subtitleLineHeight).floor().clamp(1, subtitleLines);
  return (title: title, subtitle: subtitle, clipped: title < titleLines || subtitle < subtitleLines);
}

/// Which of the series chips (by [widths], in order) fit in [maxRows] rows of
/// [maxWidth]: as many as fit, the rest counted in [hidden] for a `+N` chip at
/// the end of the last row. A chip wider than a row keeps a row of its own and
/// is clipped by its caller.
({List<List<int>> rows, int hidden}) forkFitSeriesChips(
  List<double> widths, {
  required double maxWidth,
  required int maxRows,
  required double gap,
  required double Function(int hidden) moreWidth,
}) {
  final rows = <List<int>>[];
  var used = 0.0;
  var shown = 0;
  for (var i = 0; i < widths.length; i++) {
    final w = widths[i];
    if (rows.isNotEmpty && used + gap + w <= maxWidth) {
      rows.last.add(i);
      used += gap + w;
    } else {
      if (rows.length >= maxRows) break;
      rows.add([i]);
      used = w;
    }
    shown++;
  }
  if (shown == widths.length) return (rows: rows, hidden: 0);
  // Room for the +N chip, giving up the last row's chips (all but one) for it.
  final last = rows.last;
  double lastWidth() => last.fold<double>(0, (a, i) => a + widths[i]) + gap * (last.length - 1);
  while (last.length > 1 && lastWidth() + gap + moreWidth(widths.length - shown) > maxWidth) {
    last.removeLast();
    shown--;
  }
  return (rows: rows, hidden: widths.length - shown);
}
