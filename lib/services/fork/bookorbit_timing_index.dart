part of '../api_service.dart';

// Fork: what read along needs from BookOrbit to follow a book's edition sync
// timing index. See services/fork/timing_index.dart and FORK_NOTES.md.

/// A book's timing index and what it has to fit: the EPUB the reader opens
/// and the audiobook's files in play order with their lengths. [version]
/// changes when any of them does. [serverSyncs] when BookOrbit is keeping
/// the book's ebook and audio positions together through it.
typedef TimingIndexSource = ({
  String fileId,
  String version,
  String ebookFileId,
  List<({int id, double duration})> files,
  bool serverSyncs,
});

/// The server didn't give an answer about a book's timing index: it is
/// failing, or turned the request away for now.
class TimingIndexUnreachable implements Exception {
  final int status;
  const TimingIndexUnreachable(this.status);
}

/// Statuses that answer "there is none for you": forbidden, gone, not found.
bool _timingIndexRefused(int status) => status == 403 || status == 404 || status == 410;

extension ForkTimingIndexApi on BookOrbitApiService {
  /// The timing index read along can follow for [bookId], or null when the
  /// book has none BookOrbit says is current. Throws when the server can't
  /// be reached or is failing, so a copy kept on the phone can stand in.
  Future<TimingIndexSource?> timingIndexSource(String bookId) async {
    final id = int.tryParse(bookId);
    if (id == null) return null;
    try {
      // The detail alone says whether there is an index: most books have
      // none, and are asked nothing more.
      final detail = await _detail(bookId);
      if ((BookOrbitMapper.item(detail: detail)['media'] as Map)['timingIndex'] == null) return null;
      final state = await _cached('fork-timing-index-state|$bookId', const Duration(seconds: 20),
          () => editionSyncState(id).timeout(const Duration(seconds: 10)));
      if (state.status != EditionSyncIndexStatus.ready) {
        debugPrint('[TimingIndex] $bookId: index is ${state.status.name}, not used');
        return null;
      }
      // The files in the order the player plays them, from the manifest.
      final media = BookOrbitMapper.item(detail: detail, manifest: await _manifest(bookId))['media'] as Map;
      final ti = media['timingIndex'] as Map?;
      final fileId = ti?['fileId'] as String?;
      final ebookFileId = (media['ebookFile'] as Map?)?['ino'] as String?;
      if (fileId == null || ebookFileId == null) return null;
      if (state.indexFileId != null && '${state.indexFileId}' != fileId) {
        debugPrint('[TimingIndex] $bookId: file $fileId is not the index BookOrbit uses (${state.indexFileId})');
        return null;
      }
      final files = <({int id, double duration})>[];
      for (final f in (media['audioFiles'] as List? ?? const []).whereType<Map>()) {
        final fid = int.tryParse('${f['ino']}');
        final d = (f['duration'] as num?)?.toDouble() ?? 0;
        if (fid == null || d <= 0) return null;
        files.add((id: fid, duration: d));
      }
      if (files.isEmpty) return null;
      return (
        fileId: fileId,
        version: '$fileId:${ti?['version'] ?? ''}|$ebookFileId|${files.map((f) => '${f.id}:${f.duration}').join(',')}',
        ebookFileId: ebookFileId,
        files: files,
        // As the position sync sheet reads it: edition sync on for the
        // book, and upstream's read-aloud sync not switched off.
        serverSyncs: state.syncEnabled &&
            readAloudSyncFromJson(_psMap(detail['readAloudSync'])).mode != ReadAloudSyncMode.disabled,
      );
    } on _BoHttpError catch (e) {
      if (_timingIndexRefused(e.status)) return null;
      throw TimingIndexUnreachable(e.status);
    } on PositionSyncRequestFailure catch (e) {
      if (_timingIndexRefused(e.status)) return null;
      throw TimingIndexUnreachable(e.status);
    }
  }

  Future<Uint8List> timingIndexBytes(String fileId) async {
    final r = await _authGet(_boUri('/books/files/$fileId/download'), timeout: const Duration(minutes: 2));
    if (r.statusCode != 200) throw TimingIndexUnreachable(r.statusCode);
    return r.bodyBytes;
  }
}
