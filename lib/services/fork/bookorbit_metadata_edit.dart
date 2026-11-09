part of '../api_service.dart';

// Fork-owned: what the BookOrbit Edit metadata page asks of the server. The
// book's own detail (with its locks, provider ids and custom values), who
// may edit it, a save of the changed fields and the locks together the way
// BookOrbit's web editor saves, and Auto-fill's refresh preview. The hook is
// the `part` line in api_service.dart. See FORK_NOTES.md.

/// A save or lookup BookOrbit turned down; [message] is its reason.
class MetadataEditFailure implements Exception {
  final String message;
  const MetadataEditFailure(this.message);
  @override
  String toString() => message;
}

String _meReason(Object e) =>
    e is _BoHttpError ? (e.serverMessage ?? 'The server said ${e.status}') : '$e';

extension ForkMetadataEditApi on BookOrbitApiService {
  /// The book as BookOrbit sends it, read fresh.
  Future<Map<String, dynamic>> metadataEditDetail(String bookId) => _detail(bookId, fresh: true);

  /// Whether the book has audio, so narrators, duration and abridged apply.
  bool metadataEditHasAudio(Map<String, dynamic> detail) => BookOrbitApiService._detailHasAudio(detail);

  /// Whether this user can edit [detail]'s metadata: the edit permission
  /// and editor or owner access to its library, as the server checks.
  Future<bool> canEditBookMetadata(Map<String, dynamic> detail) async {
    if (!await _can('library_edit_metadata')) return false;
    if (_superuser) return true;
    try {
      final libs = (await _boGet('/libraries') as List<dynamic>).whereType<Map>();
      final lib = libs.where((l) => '${l['id']}' == '${detail['libraryId']}').firstOrNull;
      final level = lib?['accessLevel'];
      // Older servers leave the level out; let the save be the check there.
      return level == null || level == 'editor' || level == 'owner';
    } catch (e) {
      debugPrint('[BookOrbit] library access: $e');
      return true;
    }
  }

  /// The active custom fields: id, label and type, in display order.
  Future<List<CustomField>> metadataEditCustomFields() async {
    try {
      final list = (await _boGet('/custom-metadata/fields/active') as List<dynamic>)
          .whereType<Map>()
          .where((f) => f['archivedAt'] == null && f['id'] is num)
          .toList()
        ..sort((a, b) => ((a['displayOrder'] as num?) ?? 0).compareTo((b['displayOrder'] as num?) ?? 0));
      return [
        for (final f in list)
          CustomField(id: (f['id'] as num).toInt(), label: '${f['label'] ?? ''}', type: '${f['type'] ?? 'text'}'),
      ];
    } catch (e) {
      debugPrint('[BookOrbit] custom fields: $e');
      return const [];
    }
  }

  /// Saves [body] (`{metadata?, lockedFields}`) in one request, which can
  /// unlock, edit and lock again at once, then tells open views.
  Future<Map<String, dynamic>> saveMetadataAndLocks(String bookId, Map<String, dynamic> body) async {
    try {
      await _boPatch('/books/$bookId/metadata-and-locks', body);
    } catch (e) {
      throw MetadataEditFailure(_meReason(e));
    }
    await _afterEdit(bookId);
    return _detail(bookId);
  }

  /// What a metadata refresh would write, without writing it: the fields
  /// under BookOrbit's update names.
  Future<Map<String, dynamic>> metadataRefreshPreview(String bookId) async {
    try {
      final r = await _boPost('/books/$bookId/refresh-metadata?preview=true', null, const Duration(seconds: 120));
      final m = r is Map ? r['metadata'] : null;
      return m is Map ? m.cast<String, dynamic>() : const {};
    } catch (e) {
      throw MetadataEditFailure(_meReason(e));
    }
  }

  /// Sets [slot]'s cover from an image file or URL, or removes it. Each tells
  /// open views, and throws when the server turns it down.
  Future<void> clearCover(String bookId, String slot) async {
    if (!await removeItemCover(bookId, coverSlot: slot)) throw const MetadataEditFailure('The cover was not removed');
  }

  Future<void> setCoverFile(String bookId, String slot, String path) async {
    if (!await uploadItemCover(bookId, path, coverSlot: slot)) throw const MetadataEditFailure('The cover was not uploaded');
  }

  Future<void> setCoverUrl(String bookId, String slot, String url) async {
    if (!await updateItemCoverUrl(bookId, url, coverSlot: slot)) throw const MetadataEditFailure('The cover was not set');
  }
}
