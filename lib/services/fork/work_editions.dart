import 'position_sync_chain.dart';

// Fork-owned: which editions a book page lists, read from the same position
// sync snapshot the sync sheet draws. On BookOrbit 3.6 an ebook, its
// read-aloud and its audiobook are files of one book. Pure Dart,
// unit-tested. See FORK_NOTES.md.

/// Why an edition row has no file behind it: a read-aloud that could be
/// made or is being made, or an audiobook or ebook the book lacks, which can
/// be requested into it.
enum WorkEditionGap { generate, building, request }

/// One row of the book page's Editions card: the book's files of that
/// edition, or a [gap] saying what would make them.
class WorkEdition {
  final SyncEdition kind;
  final SyncChainEdition? edition;
  final WorkEditionGap? gap;
  const WorkEdition(this.kind, {this.edition, this.gap});
}

/// Audiobook, read-aloud, ebook, in that order. A missing read-aloud is a
/// gap only where the book could have one made: it holds a plain EPUB and
/// audio, and the generator is open to this reader or already running. A
/// book with only audio, or only something to read, lists the other as a
/// request gap, as BookOrbit's own Editions card does. Empty when the book
/// holds no edition.
List<WorkEdition> workEditions(SyncChainSnapshot s) {
  WorkEdition? present(SyncEdition kind) {
    final e = s.edition(kind);
    return e == null ? null : WorkEdition(kind, edition: e);
  }

  WorkEdition? readAlong() {
    final row = present(SyncEdition.readAlong);
    if (row != null || s.ebook == null || s.audiobook == null) return row;
    final slot = s.readAloudSlot;
    final status = slot.job?.status;
    if (status == ReadAloudJobStatus.queued || status == ReadAloudJobStatus.processing) {
      return const WorkEdition(SyncEdition.readAlong, gap: WorkEditionGap.building);
    }
    return slot.entry is ReadAloudEntryAvailable ? const WorkEdition(SyncEdition.readAlong, gap: WorkEditionGap.generate) : null;
  }

  final audio = present(SyncEdition.audiobook);
  final readAloud = readAlong();
  final ebook = present(SyncEdition.ebook);
  // A read-aloud EPUB is something to read, so beside one no ebook is missing.
  final readable = ebook != null || readAloud?.edition != null;
  final rows = [
    audio ?? (readable ? const WorkEdition(SyncEdition.audiobook, gap: WorkEditionGap.request) : null),
    readAloud,
    ebook ?? (audio != null && !readable ? const WorkEdition(SyncEdition.ebook, gap: WorkEditionGap.request) : null),
  ].nonNulls.toList();
  return rows.any((r) => r.edition != null) ? rows : const [];
}

/// The format a request gap asks for, as BookOrbit names it.
String requestMediaKind(SyncEdition kind) => kind == SyncEdition.audiobook ? 'audiobook' : 'ebook';

/// The body of `POST /book-requests` for the format [bookId] lacks, from the
/// book's own metadata as the app maps it. `targetBookId` lands the new files
/// in this book's folder and record rather than as a book of their own, as
/// BookOrbit's web Request button does.
Map<String, dynamic> missingEditionRequestPayload(Map<String, dynamic> metadata, String mediaKind, int bookId) {
  String? clip(Object? v, int max) {
    final s = v is String ? v.trim() : (v == null ? '' : '$v'.trim());
    if (s.isEmpty) return null;
    return s.length > max ? s.substring(0, max) : s;
  }

  final authors = [
    for (final a in (metadata['authors'] as List?) ?? const [])
      ?clip(a is Map ? a['name'] : a, 255),
  ];
  final rawSeries = metadata['series'];
  final series = rawSeries is Map ? rawSeries : (rawSeries is List ? rawSeries.whereType<Map>().firstOrNull : null);
  final isbn = clip(metadata['isbn'], 20)?.replaceAll('-', '');
  final year = int.tryParse('${metadata['publishedYear'] ?? ''}');
  return {
    'title': clip(metadata['title'], 500) ?? '?',
    'mediaKind': mediaKind,
    if (authors.isNotEmpty) 'authors': authors.take(50).toList(),
    if (isbn != null && isbn.length == 13) 'isbn13': isbn,
    if (isbn != null && isbn.length == 10) 'isbn10': isbn,
    'seriesName': ?clip(series?['name'], 500),
    if (year != null && year >= 0 && year <= 9999) 'publishedYear': year,
    // The other format of this book should be in the same language.
    'language': ?clip(metadata['language'], 20),
    'targetBookId': bookId,
  };
}
