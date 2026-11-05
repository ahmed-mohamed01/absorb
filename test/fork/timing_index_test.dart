import 'dart:convert';

import 'package:absorb/services/bookorbit_mapper.dart';
import 'package:absorb/services/fork/timing_index.dart';
import 'package:absorb/services/media_overlay.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// A chapter as the index holds it, and the plain EPUB's copy of it.
const _c1 = '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title><style>p { x: y }</style></head><body>\n'
    '<h2 id="h"><span id="c1-s0">Chapter &amp; One</span></h2>\n'
    '<p><span id="c1-s1">He said <i>no</i>.</span> <span id="c1-s2">\u201cWhy?\u201d</span></p><script>var a = 1;</script>\n'
    '</body></html>';
const _c1Plain = '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title></head><body>\n'
    '<h2 id="h">Chapter &amp; One</h2>\n'
    '<p>He said <i>no</i>. \u201cWhy?\u201d</p>\n'
    '</body></html>';

String _smil(String doc, List<(String id, String piece, double begin, double end)> pars) => '<smil><body><seq>'
    '${pars.map((p) => '<par id="${p.$1}"><text src="../Text/$doc#${p.$1}"/>'
        '<audio src="../Audio/${p.$2}" clipBegin="${p.$3}s" clipEnd="${p.$4}s"/></par>').join()}'
    '</seq></body></smil>';

/// A small index: two audiobook files (ids 11 and 12), cut into three pieces,
/// two chapters, and the title page timed in the end credits the way
/// Storyteller can.
List<int> _index({String c1 = _c1}) {
  final a = Archive()
    ..add(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..add(ArchiveFile.string('META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>'))
    ..add(ArchiveFile.string('OEBPS/content.opf', '''<package><manifest>
<item id="t" href="Text/title.html" media-type="application/xhtml+xml" media-overlay="t_o"/>
<item id="c1" href="Text/c1.html" media-type="application/xhtml+xml" media-overlay="c1_o"/>
<item id="c2" href="Text/c2.html" media-type="application/xhtml+xml" media-overlay="c2_o"/>
<item id="t_o" href="MediaOverlays/title.smil" media-type="application/smil+xml"/>
<item id="c1_o" href="MediaOverlays/c1.smil" media-type="application/smil+xml"/>
<item id="c2_o" href="MediaOverlays/c2.smil" media-type="application/smil+xml"/>
</manifest><spine><itemref idref="t"/><itemref idref="c1"/><itemref idref="c2"/></spine></package>'''))
    ..add(ArchiveFile.string('OEBPS/Text/title.html', '<html><body><p><span id="t-s0">Title</span></p></body></html>'))
    ..add(ArchiveFile.string('OEBPS/Text/c1.html', c1))
    ..add(ArchiveFile.string('OEBPS/Text/c2.html', '<html><body><p><span id="c2-s0">Three.</span></p></body></html>'))
    ..add(ArchiveFile.string('OEBPS/MediaOverlays/title.smil', _smil('title.html', [('t-s0', '00002-00002.mp4', 0, 3)])))
    ..add(ArchiveFile.string('OEBPS/MediaOverlays/c1.smil',
        _smil('c1.html', [('c1-s0', '00001-00001.mp4', 0, 4), ('c1-s1', '00001-00001.mp4', 4, 9)])))
    ..add(ArchiveFile.string('OEBPS/MediaOverlays/c2.smil', _smil('c2.html', [('c2-s0', '00002-00001.mp4', 0.5, 6)])))
    ..add(ArchiveFile.string('bookorbit-timings/provenance.json', jsonEncode({
      'version': 1,
      'epub': {'bookFileId': 5},
      'audio': [
        {'bookFileId': 12, 'order': 1},
        {'bookFileId': 11, 'order': 0},
      ],
      'sources': [
        {'name': '00001-00001.mp4', 'source': '0001.m4b', 'start': 0, 'end': 10},
        {'name': '00002-00001.mp4', 'source': '0002.m4b', 'start': 0, 'end': 20},
        {'name': '00002-00002.mp4', 'source': '0002.m4b', 'start': 20, 'end': 23},
      ],
      'audioEntries': [
        {'href': 'OEBPS/Audio/00001-00001.mp4', 'chunk': '00001-00001.mp4'},
        {'href': 'OEBPS/Audio/00002-00001.mp4', 'chunk': '00002-00001.mp4'},
        {'href': 'OEBPS/Audio/00002-00002.mp4', 'chunk': '00002-00002.mp4'},
      ],
    })));
  return ZipEncoder().encodeBytes(a);
}

void main() {
  group('timings', () {
    Future<MediaOverlay> overlay(Map<int, double> starts) async =>
        (await TimingIndex.read(_index())!.narration(starts))!.overlay;

    test('every sentence lands on the audiobook where its piece was cut from', () async {
      final index = TimingIndex.read(_index())!;
      expect(index.audioFileIds, [11, 12]);
      expect(index.epubFileId, 5);
      // The book plays file 11 from 0s and file 12 from 100s.
      final o = await overlay({11: 0, 12: 100});
      final starts = {for (final c in o.clips) c.fragment: o.startOf(c)};
      expect(starts, {'c1-s0': 0, 'c1-s1': 4, 'c2-s0': 100.5});
      expect(o.clipAt(5)?.fragment, 'c1-s1');
      expect(o.clipAt(101)?.fragment, 'c2-s0');
      expect(o.duration, 123);
    });

    test('a title page timed in the end credits is left out, and its section with it', () async {
      final o = await overlay({11: 0, 12: 100});
      expect(o.clips.map((c) => c.fragment), isNot(contains('t-s0')));
      expect(o.sections.map((s) => s.href), ['OEBPS/Text/c1.html', 'OEBPS/Text/c2.html']);
      expect(o.sections.map((s) => s.start), [0, 100.5]);
    });

    test('the credits piece left with no sentences lights nothing new', () async {
      // 120s to 123s is the piece the title page was timed in: the reader
      // leaves the last sentence as it is while nothing is found there.
      final o = await overlay({11: 0, 12: 100});
      expect(o.clipAt(119)?.fragment, 'c2-s0');
      expect(o.clipAt(121), isNull);
    });

    test('a sentence its chapter has no place for is left out', () async {
      // c1-s1 is timed, but the chapter was rewritten without it.
      final n = (await TimingIndex.read(_index(c1: _c1.replaceAll('id="c1-s1"', 'id="other"')))!.narration({11: 0, 12: 100}))!;
      expect(n.overlay.clips.map((c) => c.fragment), ['c1-s0', 'c2-s0']);
      expect((jsonDecode(n.positions) as Map)['OEBPS/Text/c1.html']['i'], ['c1-s0']);
    });

    test('kept on the phone and read back, it is the same narration', () async {
      final o = await overlay({11: 0, 12: 100});
      final back = MediaOverlay.fromJson(jsonDecode(jsonEncode(o.toJson())) as Map<String, dynamic>)!;
      expect({for (final c in back.clips) c.fragment: back.startOf(c)}, {for (final c in o.clips) c.fragment: o.startOf(c)});
      expect(back.clipAt(101)?.fragment, 'c2-s0');
      expect(back.duration, o.duration);
    });

    test('an audiobook missing one of the index\'s files gives no timings', () async {
      expect(await TimingIndex.read(_index())!.narration({11: 0}), isNull);
    });

    test('anything but a version 1 index is not read', () {
      expect(TimingIndex.read(utf8.encode('nope')), isNull);
      expect(TimingIndex.read(ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.string('a', 'b')))), isNull);
    });
  });

  group('sentence positions', () {
    const ids = {'c1-s0', 'c1-s1', 'c1-s2'};

    test('count the characters before each sentence that are not whitespace', () {
      final p = sentencePositions(_c1, ids)!;
      expect(p.ids, ['c1-s0', 'c1-s1', 'c1-s2']);
      // "Chapter&One" is 11, "Hesaidno." 9, the quoted "Why?" 6; the script is not text.
      expect(p.starts, [0, 11, 20]);
      expect(p.ends, [11, 20, 26]);
      expect(p.length, 26);
    });

    test('cut the same sentences out of the plain chapter', () {
      final p = sentencePositions(_c1, ids)!;
      // Counted by hand here, not by the code under test.
      final plain = _bodyText(_c1Plain).replaceAll(RegExp(r'\s+'), '');
      expect(plain.length, p.length);
      expect([for (var i = 0; i < p.ids.length; i++) plain.substring(p.starts[i], p.ends[i])],
          ['Chapter&One', 'Hesaidno.', '“Why?”']);
    });

    test('hash the counted characters the way the page script does', () {
      // Worked out with the page script's own arithmetic in node:
      //   h = 0; for (c of 'Chapter&OneHesaidno.\u201cWhy?\u201d') h = (Math.imul(h, 31) + c.charCodeAt(0)) | 0
      expect(sentencePositions(_c1, ids)!.hash, 231040548);
      expect(sentencePositions(_c1Plain, const {})!.hash, 231040548);
    });

    test('the same characters in another order hash differently', () {
      const a = '<html><body><p>AB</p><p>C</p></body></html>';
      const b = '<html><body><p>BA</p><p>C</p></body></html>';
      expect(sentencePositions(a, const {})!.length, sentencePositions(b, const {})!.length);
      expect(sentencePositions(a, const {})!.hash, isNot(sentencePositions(b, const {})!.hash));
    });

    test('a chapter that is not well-formed XML is still read', () {
      final p = sentencePositions('<html><body><p><span id="a">One<br>two</span> <span id="b">x</span></body></html>', {'a', 'b'})!;
      expect(p.starts, [0, 6]);
      expect(p.length, 7);
    });

    test('go with the narration as JSON by chapter', () async {
      final n = (await TimingIndex.read(_index())!.narration({11: 0, 12: 100}))!;
      final j = jsonDecode(n.positions) as Map<String, dynamic>;
      expect(j.keys, containsAll(['OEBPS/Text/c1.html', 'OEBPS/Text/c2.html']));
      final c1 = j['OEBPS/Text/c1.html'] as Map<String, dynamic>;
      expect(c1['n'], 26);
      expect(c1['h'], sentencePositions(_c1, const {})!.hash);
      expect(c1['i'], ['c1-s0', 'c1-s1']);
      expect(c1['s'], [0, 11]);
      expect(c1['e'], [11, 20]);
    });
  });

  group('which books follow a timing index', () {
    Map<String, dynamic> media(List<Map<String, dynamic>> files, {Map<String, dynamic>? sync}) =>
        BookOrbitMapper.item(detail: {'id': 1, 'files': files, if (sync != null) 'readAloudSync': sync})['media']
            as Map<String, dynamic>;
    const epub = {'id': 5, 'role': 'primary', 'format': 'epub', 'filename': 'b.epub'};
    const audio = {'id': 11, 'role': 'content', 'format': 'm4b', 'durationSeconds': 100};
    const index = {'id': 9, 'role': 'supplement', 'format': 'bookorbit-timings', 'fileHash': 'abc'};

    test('an audiobook, a plain EPUB and a timing index', () {
      final m = media([epub, audio, index]);
      expect(m['timingIndex'], {'fileId': '9', 'version': 'abc'});
      expect((m['ebookFile'] as Map)['ino'], '5');
    });

    test('not an ebook with no audiobook, nor an audiobook with no EPUB', () {
      expect(media([epub, index])['timingIndex'], isNull);
      expect(media([audio, index])['timingIndex'], isNull);
      expect(media([{...epub, 'format': 'pdf', 'filename': 'b.pdf'}, audio, index])['timingIndex'], isNull);
    });

    test('not a book whose read-along EPUB is in step with its audiobook', () {
      final m = media([
        {...epub, 'mediaOverlay': {'available': true, 'durationSeconds': 100}},
        audio,
        index,
      ], sync: {'state': 'enabled', 'overlayFileId': 5, 'overlayDurationSeconds': 100, 'audioDurationSeconds': 100});
      expect(m['readAlongEpub'], isNotNull);
      expect(m['timingIndex'], isNull);
    });
  });
}

/// A chapter's body text the plain way, to check the counts against.
String _bodyText(String chapter) {
  final body = RegExp(r'<body[^>]*>(.*)</body>', dotAll: true).firstMatch(chapter)!.group(1)!;
  return body
      .replaceAll(RegExp(r'<script.*?</script>', dotAll: true), '')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&');
}
