// Fork-owned: the narration read along follows for a BookOrbit book with a
// timing index, kept on the phone so it is there offline and the index is
// read once. `NarrationService.overlayFor`, `sentenceTimings` and `play` ask
// here after the book's own narration and read-along EPUB; the reader takes
// the sentence positions for its page script; a download fetches it ahead.
// Everything is kept per account, since two servers can number a book the
// same. See timing_index.dart and FORK_NOTES.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api_service.dart';
import '../media_overlay.dart';
import '../user_account_service.dart';
import 'timing_index.dart';
import 'timing_index_script.dart';

typedef _Kept = ({String version, TimingIndexNarration narration});

final Map<String, _Kept> _known = {};
final Map<String, Future<MediaOverlay?>> _loading = {};

/// What goes with each narration handed out: a reader keeps its narration
/// for as long as it is open, whatever is looked up again meanwhile.
final Expando<_Kept> _keptOf = Expando();

MediaOverlay _hand(String scope, _Kept kept) {
  _known[scope] = kept;
  _keptOf[kept.narration.overlay] = kept;
  return kept.narration.overlay;
}

String _scope(String itemId) => '${UserAccountService().activeScopeKey}|$itemId';

/// The narration of [itemId] from its timing index, laid on its audiobook.
/// Null for a book without one that is current.
Future<MediaOverlay?> forkTimingIndexOverlay(ApiService? api, String itemId) {
  if (api is! BookOrbitApiService) return Future.value(null);
  final scope = _scope(itemId);
  final running = _loading[scope];
  if (running != null) return running;
  final load = _load(api, itemId, scope);
  _loading[scope] = load;
  // A block, so the removed future isn't handed back to wait on itself.
  load.whenComplete(() {
    if (identical(_loading[scope], load)) _loading.remove(scope);
  }).ignore();
  return load;
}

/// Whether BookOrbit itself keeps the page and the audio of [itemId] together
/// through its timing index, so nothing has to be transcribed to do it.
Future<bool> forkTimingIndexKeepsSpots(ApiService? api, String itemId) async {
  if (api is! BookOrbitApiService) return false;
  try {
    return (await api.timingIndexSource(itemId))?.serverSyncs ?? false;
  } catch (_) {
    return false;
  }
}

/// Puts the narration script [bootstrap] in the reader's page, with the
/// sentence positions that go with [overlay] when it is a timing index's
/// narration and the page doesn't hold them yet. [eval] runs script in the
/// page.
Future<void> forkNarrationInstall(
    Future<dynamic> Function(String source) eval, String bootstrap, MediaOverlay? overlay) async {
  final kept = overlay == null ? null : _keptOf[overlay];
  if (kept == null) {
    await eval(bootstrap);
    return;
  }
  final key = sha1.convert(utf8.encode(kept.version)).toString();
  if (await eval(narrationHasPositionsSource(key)) == 'y') {
    await eval(bootstrap);
  } else {
    await eval(narrationPositionsSource(bootstrap, key, kept.narration.positions));
  }
}

/// Whether the server couldn't be asked, as opposed to answering.
bool _unreachable(Object e) =>
    e is TimingIndexUnreachable ||
    e is SocketException ||
    e is HandshakeException ||
    e is TimeoutException ||
    e is http.ClientException;

Future<MediaOverlay?> _load(BookOrbitApiService api, String itemId, String scope) async {
  final TimingIndexSource? source;
  try {
    source = await api.timingIndexSource(itemId);
  } catch (e) {
    if (!_unreachable(e)) {
      debugPrint('[TimingIndex] $itemId: the server\'s answer was not understood (${e.runtimeType})');
      return null;
    }
    // The server can't be asked (offline): the copy kept here still fits the
    // audiobook it was made for.
    final kept = _known[scope] ?? await _read(scope, null);
    debugPrint('[TimingIndex] $itemId: server not reached (${e.runtimeType}) - '
        '${kept == null ? 'no' : 'using the'} copy kept here');
    return kept == null ? null : _hand(scope, kept);
  }
  if (source == null) {
    // The server says there is none to follow: the kept copy goes too, or
    // it would come back the next time the phone is offline.
    _known.remove(scope);
    await _forget(scope);
    return null;
  }
  final known = _known[scope];
  if (known != null && known.version == source.version) return known.narration.overlay;
  final kept = await _read(scope, source.version);
  if (kept != null) return _hand(scope, kept);
  try {
    final started = DateTime.now();
    final bytes = await api.timingIndexBytes(source.fileId);
    final narration = await compute(buildTimingIndexNarration, (bytes, source));
    if (narration == null) {
      debugPrint('[TimingIndex] $itemId: index ${source.fileId} does not fit this book\'s EPUB and audio');
      _known.remove(scope);
      await _forget(scope);
      return null;
    }
    debugPrint('[TimingIndex] $itemId: ${narration.overlay.clips.length} sentences from index ${source.fileId} '
        '(${bytes.length} bytes) in ${DateTime.now().difference(started).inMilliseconds}ms');
    await _write(scope, source.version, narration);
    return _hand(scope, (version: source.version, narration: narration));
  } catch (e) {
    debugPrint('[TimingIndex] $itemId: index ${source.fileId} not read (${e.runtimeType})');
    return null;
  }
}

/// The index in [a].$1 laid on the audiobook of [a].$2. Null when it isn't
/// an index, or was made from another EPUB or other audio files.
Future<TimingIndexNarration?> buildTimingIndexNarration((Uint8List, TimingIndexSource) a) async {
  final index = TimingIndex.read(a.$1);
  final source = a.$2;
  if (index == null) return null;
  if (index.epubFileId != null && '${index.epubFileId}' != source.ebookFileId) return null;
  final starts = <int, double>{};
  var at = 0.0;
  for (final f in source.files) {
    starts[f.id] = at;
    at += f.duration;
  }
  return index.narration(starts);
}

Future<File> _file(String scope) async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/timing_index');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return File('${dir.path}/${sha1.convert(utf8.encode(scope))}.json');
}

/// The copy kept under [scope], when it is [version] (any, when null).
Future<_Kept?> _read(String scope, String? version) async {
  try {
    final f = await _file(scope);
    if (!f.existsSync()) return null;
    return await compute(_decode, (await f.readAsString(), scope, version));
  } catch (e) {
    debugPrint('[TimingIndex] kept copy not read: $e');
    return null;
  }
}

_Kept? _decode((String, String, String?) a) {
  final j = jsonDecode(a.$1) as Map<String, dynamic>;
  final v = j['version'] as String;
  if (j['scope'] != a.$2 || (a.$3 != null && v != a.$3)) return null;
  final overlay = MediaOverlay.fromJson(j['overlay'] as Map<String, dynamic>);
  if (overlay == null) return null;
  return (version: v, narration: TimingIndexNarration(overlay, j['positions'] as String));
}

String _encode((String, _Kept) a) => jsonEncode({
      'scope': a.$1,
      'version': a.$2.version,
      'overlay': a.$2.narration.overlay.toJson(),
      'positions': a.$2.narration.positions,
    });

Future<void> _write(String scope, String version, TimingIndexNarration n) async {
  try {
    final f = await _file(scope);
    // Written beside it and moved into place, so a half-written copy is
    // never read.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(await compute(_encode, (scope, (version: version, narration: n))), flush: true);
    await tmp.rename(f.path);
  } catch (e) {
    debugPrint('[TimingIndex] copy not kept: $e');
  }
}

Future<void> _forget(String scope) async {
  try {
    final f = await _file(scope);
    if (f.existsSync()) await f.delete();
  } catch (_) {}
}
