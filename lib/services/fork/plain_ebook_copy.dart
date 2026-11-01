// Fork-owned: a second ebook copy per book. Upstream's ebook cache keeps one
// file per book, the copy Read opens, which on BookOrbit is the read-along
// EPUB whenever the book has one in step with its audiobook (or the narrated
// EPUB). The Editions card's Ebook row downloads the plain ebook beside it,
// into `ebook_cache/plain/`, so neither download replaces the other. The
// hooks are one line each in `ebook_cache.dart` (`ebookCacheFileFor`,
// `deleteCachedEbook`) and `ebook_router.dart` (the offline fallback).
// See FORK_NOTES.md.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';

import '../ebook_cache.dart';

/// Ticks whenever an ebook copy lands on or leaves the phone (the reader
/// fetching one counts), so download buttons show it at once. Bumped from
/// `rememberEbookVersion`.
final ValueNotifier<int> forkEbookCopiesChanged = ValueNotifier(0);

/// Marks an ebook file map as the plain copy kept beside the reader's.
const forkPlainCopyKey = 'forkPlainCopy';

Map<String, dynamic> forkAsPlainCopy(Map<String, dynamic> ebookFile) => {...ebookFile, forkPlainCopyKey: true};

bool forkIsPlainCopy(Map<String, dynamic> ebookFile) => ebookFile[forkPlainCopyKey] == true;

Directory _plainDir(Directory cacheDir) => Directory('${cacheDir.path}/plain');

/// `ebookCacheFileFor` for a plain copy: `plain/<item><ext>`.
File forkPlainCopyFile(Directory cacheDir, String itemId, String ext) {
  final dir = _plainDir(cacheDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return File('${dir.path}/$itemId$ext');
}

/// The plain copy of [itemId] on the phone, as an ebook file map the reader
/// takes, or null.
Map<String, dynamic>? forkCachedPlainCopy(Directory cacheDir, String itemId) {
  final dir = _plainDir(cacheDir);
  if (!dir.existsSync()) return null;
  for (final f in dir.listSync()) {
    if (f is! File) continue;
    final name = f.uri.pathSegments.last;
    if (!name.startsWith('$itemId.') || name.endsWith('.part')) continue;
    final ext = name.substring(itemId.length + 1).toLowerCase();
    // Its .version and .locations.json files sit beside it.
    if (ext.contains('.') || f.lengthSync() <= 0) continue;
    return {
      'ebookFormat': ext,
      'metadata': {'filename': name, 'ext': '.$ext'},
      forkPlainCopyKey: true,
    };
  }
  return null;
}

/// [forkCachedPlainCopy] in the app's ebook cache.
Future<Map<String, dynamic>?> forkPlainCopyOnPhone(String itemId) async {
  try {
    final base = await getApplicationSupportDirectory();
    return forkCachedPlainCopy(Directory('${base.path}/ebook_cache'), itemId);
  } catch (_) {
    return null;
  }
}

/// The reader's hook: offline, with the copy it chose not on the phone, it
/// opens the plain copy if that one was downloaded.
Future<Map<String, dynamic>> forkOfflineReaderCopy(String itemId, Map<String, dynamic> chosen, {required bool offline}) async {
  if (!offline || forkIsPlainCopy(chosen) || await isEbookCached(itemId, chosen)) return chosen;
  return await forkPlainCopyOnPhone(itemId) ?? chosen;
}

/// Removes the plain copy of [itemId] with its side files.
Future<void> forkDeletePlainCopies(Directory cacheDir, String itemId) async {
  final dir = _plainDir(cacheDir);
  if (!dir.existsSync()) return;
  for (final f in dir.listSync()) {
    if (f is File && f.uri.pathSegments.last.startsWith('$itemId.')) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}

/// The book's plain ebook (EPUB, MOBI, PDF...), marked as a plain copy when
/// the reader's copy is a read-along or narrated EPUB, or null.
Map<String, dynamic>? forkPlainEbookFile(Map<String, dynamic>? item) {
  final media = item?['media'] as Map?;
  final readAlong = media?['readAlongEpub'];
  if (readAlong is Map) {
    final plain = readAlong['plainEbookFile'];
    return plain is Map<String, dynamic> ? forkAsPlainCopy(plain) : null;
  }
  final reader = resolveEbookFile(item);
  if (reader == null || media?['narration'] == null) return reader;
  // A narrated EPUB is the reader's copy; the plain one is among the files.
  final files = [
    for (final f in ((item?['bookOrbit'] as Map?)?['files'] as List?) ?? const [])
      if (f is Map && f['readAlong'] != true && f['id'] != null && readableEbookFormats.contains(f['format'])) f,
  ];
  if (files.isEmpty) return null;
  final f = files.firstWhere((f) => f['format'] == 'epub', orElse: () => files.first);
  final format = f['format'] as String;
  return forkAsPlainCopy({
    'ino': '${f['id']}',
    'ebookFormat': format,
    'metadata': {'filename': f['filename'] ?? 'book.$format', 'ext': '.$format', 'size': f['size'] ?? 0},
  });
}

/// The read-along EPUB the reader opens beside the audiobook, or null when
/// the book has none in step with it.
Map<String, dynamic>? forkReadAlongFile(Map<String, dynamic>? item) {
  final media = item?['media'] as Map?;
  return media?['readAlongEpub'] is Map ? resolveEbookFile(item) : null;
}

/// Takes the reader's copy of [itemId] off the phone, leaving the plain one.
Future<void> forkDeleteReaderCopy(String itemId, Map<String, dynamic> ebookFile) async {
  final f = await ebookCacheFileFor(itemId, ebookFile);
  for (final path in [f.path, '${f.path}.version', '${f.path}.locations.json']) {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }
  forkEbookCopiesChanged.value++;
}

/// Takes the plain copy of [itemId] off the phone, leaving the reader's.
Future<void> forkDeletePlainCopyOnPhone(String itemId) async {
  try {
    final base = await getApplicationSupportDirectory();
    await forkDeletePlainCopies(Directory('${base.path}/ebook_cache'), itemId);
  } catch (_) {}
  forkEbookCopiesChanged.value++;
}
