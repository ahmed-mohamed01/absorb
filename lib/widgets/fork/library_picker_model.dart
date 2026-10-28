// Fork-owned: what the library picker shows, free of Flutter so it is
// unit-tested in test/fork/library_picker_model_test.dart: the split into
// libraries and BookOrbit's tools (Book Dock, Watchlist), and the line under
// each name (book counts, the dock's files, the watchlist's authors and
// upcoming releases). library_picker.dart draws what these return. See
// FORK_NOTES.md.

/// BookOrbit's tools, which the picker lists under a divider after the
/// libraries: the Book Dock and the Watchlist.
bool libraryPickerIsTool(Map<String, dynamic> library) =>
    library['bookDock'] == true || library['watchlist'] == true;

/// The picker's two groups, each keeping the order of [all].
({List<Map<String, dynamic>> libraries, List<Map<String, dynamic>> tools}) libraryPickerGroups(
    Iterable<Map<String, dynamic>> all) {
  final libraries = <Map<String, dynamic>>[];
  final tools = <Map<String, dynamic>>[];
  for (final library in all) {
    (libraryPickerIsTool(library) ? tools : libraries).add(library);
  }
  return (libraries: libraries, tools: tools);
}

/// The line under [library]'s name, or null when there is nothing to say
/// (an Audiobookshelf library, whose list carries no counts). [dockSummary]
/// is BookOrbit's `/book-dock/summary` and [watchlistUpcoming] its count of
/// upcoming releases, both read when the picker opens; until they arrive the
/// Book Dock row has no line and the Watchlist row counts only its authors.
String? libraryPickerSubtitle(
  Map<String, dynamic> library, {
  Map<String, dynamic>? dockSummary,
  int? watchlistUpcoming,
}) {
  if (library['bookDock'] == true) return bookDockSubtitle(dockSummary);
  if (library['watchlist'] == true) return watchlistSubtitle(library, upcoming: watchlistUpcoming);
  final n = _count(library['bookCount']);
  if (n == null) return null;
  return library['mediaType'] == 'podcast' ? _plural(n, 'podcast', 'podcasts') : _plural(n, 'book', 'books');
}

/// The Book Dock's line: what needs the user first (files to review, then
/// failures, files ready to file, files still processing, files waiting),
/// else that nothing is waiting.
String? bookDockSubtitle(Map<String, dynamic>? summary) {
  if (summary == null) return null;
  final needsReview = _count(summary['needsReview']) ?? 0;
  if (needsReview > 0) return '$needsReview ${needsReview == 1 ? 'file needs' : 'files need'} review';
  final error = _count(summary['error']) ?? 0;
  if (error > 0) return '${_plural(error, 'file', 'files')} failed';
  final readyToFile = _count(summary['readyToFile']) ?? 0;
  if (readyToFile > 0) return '${_plural(readyToFile, 'file', 'files')} ready to file';
  final working = _count(summary['working']) ?? 0;
  if (working > 0) return '${_plural(working, 'file', 'files')} processing';
  final pending = _count(summary['pending']) ?? 0;
  if (pending > 0) return '${_plural(pending, 'file', 'files')} waiting';
  return 'Nothing waiting';
}

/// The Watchlist's line: the followed authors (`watchlistAuthors`, stamped
/// on its library entry from its summary) and, once read, the [upcoming]
/// releases when there are any. Both count the way the server does, so
/// upcoming counts formats, as the needs-you pill does.
String? watchlistSubtitle(Map<String, dynamic> library, {int? upcoming}) {
  final authors = _count(library['watchlistAuthors']);
  final parts = [
    if (authors != null) authors == 0 ? 'No authors yet' : _plural(authors, 'author', 'authors'),
    if (upcoming != null && upcoming > 0) '$upcoming upcoming',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

int? _count(Object? value) => value is num ? value.toInt() : null;

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
