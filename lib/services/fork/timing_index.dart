// Fork-owned: read along from BookOrbit's edition sync timing index
// (`<book>.bookorbit-timings`), for a book with an audiobook and a plain EPUB.
//
// A read-along EPUB names each sentence by an element id and says which
// stretch of audio reads it, and read along lights that element. The timing
// index is such an EPUB without its audio, made from the plain EPUB the
// reader opens: same chapters, same text, plus a `<span id>` around every
// sentence. So the index gives the timings, and each sentence is found in the
// plain chapter by where its text sits, counted in characters that aren't
// whitespace. Nothing is transcribed, and the plain EPUB is left as it is.
//
// The index's SMIL times count from the start of the worker's audio pieces;
// `bookorbit-timings/provenance.json` says which audiobook file each piece was
// cut from and where, so every sentence lands at an exact second of the
// audiobook. The page side is timing_index_script.dart. See FORK_NOTES.md.

import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:html/dom.dart' as hdom;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import '../media_overlay.dart';

export 'timing_index_format.dart';

const _dir = 'bookorbit-timings/';

/// One worker audio piece: a stretch of one audiobook file.
class TimingIndexPiece {
  /// 0-based place of the audiobook file in the worker's input.
  final int order;
  final double start;
  final double end;
  const TimingIndexPiece(this.order, this.start, this.end);
}

/// Where a chapter's sentences sit in its text, in reading order: [starts]
/// and [ends] count the characters before them that aren't whitespace, out
/// of [length] in the whole chapter, whose characters hash to [hash].
class SentencePositions {
  final int length;
  final int hash;
  final List<String> ids;
  final List<int> starts;
  final List<int> ends;
  const SentencePositions(this.length, this.hash, this.ids, this.starts, this.ends);

  Map<String, dynamic> toJson() => {'n': length, 'h': hash, 'i': ids, 's': starts, 'e': ends};
}

/// A timing index read for read along: the narration on the audiobook's
/// timeline, and [positions] by chapter (the path its clips name), as the
/// JSON the page script takes. Every sentence of [overlay] has a position.
class TimingIndexNarration {
  final MediaOverlay overlay;
  final String positions;
  const TimingIndexNarration(this.overlay, this.positions);
}

class TimingIndex {
  final Archive archive;

  /// The EPUB the index was made from, as BookOrbit's file id.
  final int? epubFileId;

  /// Audiobook file ids in the worker's input order.
  final List<int> audioFileIds;

  /// EPUB audio entry (zip path) to the stretch of audiobook it holds.
  final Map<String, TimingIndexPiece> pieces;

  TimingIndex._(this.archive, this.epubFileId, this.audioFileIds, this.pieces);

  /// Null when [bytes] isn't a timing index this version understands.
  static TimingIndex? read(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }
    final f = archive.findFile('${_dir}provenance.json');
    if (f == null) return null;
    final Map<String, dynamic> p;
    try {
      p = jsonDecode(utf8.decode(f.content)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    if (p['version'] != 1) return null;
    final audio = [for (final a in (p['audio'] as List? ?? const []).whereType<Map>()) a]
      ..sort((a, b) => ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));
    final ids = [for (final a in audio) (a['bookFileId'] as num?)?.toInt() ?? -1];
    // The worker copies its inputs in as `0001.m4b`, `0002.mp3`, ... by order.
    final byChunk = <String, TimingIndexPiece>{};
    for (final s in (p['sources'] as List? ?? const []).whereType<Map>()) {
      final n = int.tryParse('${s['source']}'.split('.').first);
      final start = (s['start'] as num?)?.toDouble(), end = (s['end'] as num?)?.toDouble();
      if (n == null || n < 1 || n > ids.length || start == null || end == null || end < start) continue;
      byChunk['${s['name']}'] = TimingIndexPiece(n - 1, start, end);
    }
    final pieces = <String, TimingIndexPiece>{};
    for (final e in (p['audioEntries'] as List? ?? const []).whereType<Map>()) {
      final piece = byChunk['${e['chunk']}'];
      if (piece != null && e['href'] is String) pieces[e['href'] as String] = piece;
    }
    if (pieces.isEmpty) return null;
    return TimingIndex._(archive, ((p['epub'] as Map?)?['bookFileId'] as num?)?.toInt(), ids, pieces);
  }

  /// The narration laid on the audiobook's timeline, each of its files
  /// starting where [fileStarts] says, by file id, with where each of its
  /// sentences sits in its chapter's text. Sentences with no place in a
  /// chapter are left out. Null when the index has no narration, or a piece
  /// comes from a file [fileStarts] doesn't place (the audiobook changed
  /// since the index was made).
  Future<TimingIndexNarration?> narration(Map<int, double> fileStarts) async {
    final o = await MediaOverlay.fromEpub(archive);
    if (o == null || o.isEmpty) return null;
    final placement = <String, ({double start, double duration})>{};
    for (final e in pieces.entries) {
      final fileStart = fileStarts[audioFileIds[e.value.order]];
      if (fileStart == null) return null;
      placement[e.key] = (start: fileStart + e.value.start, duration: e.value.end - e.value.start);
    }
    final wanted = <String, Set<String>>{};
    for (final c in o.clips) {
      final id = c.fragment;
      if (id != null) (wanted[c.textHref] ??= {}).add(id);
    }
    final positions = <String, SentencePositions>{};
    for (final e in wanted.entries) {
      final f = archive.findFile(e.key);
      if (f == null) continue;
      final p = sentencePositions(utf8.decode(f.content, allowMalformed: true), e.value);
      if (p != null) positions[e.key] = p;
    }
    final placedIds = {for (final e in positions.entries) e.key: e.value.ids.toSet()};
    final placed = placeOnAudiobook(o, placement, keep: (c) => placedIds[c.textHref]?.contains(c.fragment) ?? false);
    if (placed == null) return null;
    return TimingIndexNarration(placed, jsonEncode(positions));
  }
}

/// [o] with each audio file put where [placement] says on another timeline:
/// a timing index places every piece on the audiobook it was cut from. Only
/// the sentences [keep] passes stay, and of those the longest run, in reading
/// order, whose times never go back: Storyteller can time the title page in
/// the closing credits, and following the audio must never jump back to it.
/// Null when a file has no place, or nothing is left.
MediaOverlay? placeOnAudiobook(
  MediaOverlay o,
  Map<String, ({double start, double duration})> placement, {
  bool Function(OverlayClip clip)? keep,
}) {
  if (o.tracks.any((t) => placement[t.href] == null)) return null;
  final order = List.generate(o.tracks.length, (i) => i)
    ..sort((a, b) => placement[o.tracks[a].href]!.start.compareTo(placement[o.tracks[b].href]!.start));
  final newIndex = {for (var i = 0; i < order.length; i++) order[i]: i};
  final clips = [
    for (final c in o.clips)
      if (keep == null || keep(c)) c,
  ];
  final times = [for (final c in clips) placement[o.tracks[c.track].href]!.start + c.begin];
  // Longest non-decreasing run, by patience sorting.
  final tails = <int>[];
  final prev = List<int>.filled(clips.length, -1);
  for (var i = 0; i < clips.length; i++) {
    var lo = 0, hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (times[tails[mid]] <= times[i]) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0) prev[i] = tails[lo - 1];
    if (lo == tails.length) {
      tails.add(i);
    } else {
      tails[lo] = i;
    }
  }
  final run = <int>[];
  for (var i = tails.isEmpty ? -1 : tails.last; i >= 0; i = prev[i]) {
    run.add(i);
  }
  final firstAt = <int, double>{};
  for (final i in run.reversed) {
    firstAt.putIfAbsent(clips[i].section, () => times[i]);
  }
  // MediaOverlay is built through its saved form, so nothing of the fork's
  // has to live in it.
  return MediaOverlay.fromJson({
    'tracks': [
      for (final i in order)
        {
          'href': o.tracks[i].href,
          'type': o.tracks[i].mediaType,
          'duration': placement[o.tracks[i].href]!.duration,
          'start': placement[o.tracks[i].href]!.start,
        },
    ],
    'clips': [
      for (final i in run.reversed)
        [clips[i].section, clips[i].textHref, clips[i].fragment, newIndex[clips[i].track], clips[i].begin, clips[i].end],
    ],
    'sections': [
      for (final s in o.sections)
        if (firstAt[s.index] case final at?) {'index': s.index, 'href': s.href, 'label': s.label, 'start': at},
    ]..sort((a, b) => (a['start'] as double).compareTo(b['start'] as double)),
  });
}

final _space = RegExp(r'\s+');

/// Where the elements named in [ids] sit in a chapter's body text. The page
/// script counts the plain chapter the same way: every text node under
/// `<body>` in order, `<script>` and `<style>` left out, whitespace not
/// counted, and the counted characters hashed so text in another order
/// doesn't pass for the same. Null when the chapter can't be read.
SentencePositions? sentencePositions(String chapter, Set<String> ids) {
  final found = <String, (int, int)>{};
  var at = 0, hash = 0;
  void text(String t) {
    for (final c in t.replaceAll(_space, '').codeUnits) {
      hash = (hash * 31 + c) & 0xFFFFFFFF;
      at++;
    }
  }

  void element(String? name, String? id, void Function() inside) {
    if (name == 'script' || name == 'style') return;
    if (id == null || !ids.contains(id) || found.containsKey(id)) return inside();
    final start = at;
    inside();
    found[id] = (start, at);
  }

  try {
    void walk(XmlNode node) {
      if (node is XmlText || node is XmlCDATA) {
        text(node.value ?? '');
      } else if (node is XmlElement) {
        element(node.name.local.toLowerCase(), node.getAttribute('id'), () => node.children.forEach(walk));
      }
    }

    final body = XmlDocument.parse(chapter).descendantElements.where((e) => e.name.local.toLowerCase() == 'body').firstOrNull;
    if (body == null) return null;
    body.children.forEach(walk);
  } catch (_) {
    // Not well-formed XML: read it the forgiving way a browser reads HTML.
    found.clear();
    at = 0;
    hash = 0;
    void walk(hdom.Node node) {
      if (node is hdom.Text) {
        text(node.data);
      } else if (node is hdom.Element) {
        element(node.localName?.toLowerCase(), node.attributes['id'], () => node.nodes.forEach(walk));
      }
    }

    final body = html.parse(chapter).body;
    if (body == null) return null;
    body.nodes.forEach(walk);
  }
  // Document order: sentences don't nest, so by start, then by end.
  final order = found.keys.toList()
    ..sort((a, b) {
      final byStart = found[a]!.$1.compareTo(found[b]!.$1);
      return byStart != 0 ? byStart : found[a]!.$2.compareTo(found[b]!.$2);
    });
  return SentencePositions(
      at, hash.toSigned(32), order, [for (final id in order) found[id]!.$1], [for (final id in order) found[id]!.$2]);
}
