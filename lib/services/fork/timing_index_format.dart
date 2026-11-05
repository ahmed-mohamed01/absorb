// Fork-owned: what the BookOrbit mapper needs to know about timing indexes,
// kept apart from the code that reads them. See timing_index.dart.

/// `book_files.format` BookOrbit gives a timing index.
const timingIndexFormat = 'bookorbit-timings';

/// `media.timingIndex` for a book with these [files]: its timing index's file
/// id and a version that changes when the file does. Null without one, or
/// when the book isn't an audiobook beside a [plainEpub].
Map<String, String>? forkTimingIndexMedia(List<Map<String, dynamic>> files, {required bool plainEpub}) {
  if (!plainEpub) return null;
  for (final f in files) {
    if ('${f['format']}'.toLowerCase() != timingIndexFormat) continue;
    return {
      'fileId': '${f['id']}',
      'version': '${f['fileHash'] ?? f['contentVersion'] ?? f['sizeBytes'] ?? ''}',
    };
  }
  return null;
}
