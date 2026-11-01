import 'dart:io';

import 'package:absorb/services/fork/plain_ebook_copy.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _entry(String id, String format) => {
      'ino': id,
      'ebookFormat': format,
      'metadata': {'filename': 'book.$format', 'ext': '.$format'},
    };

void main() {
  group('which file each row downloads', () {
    test('a book reading its read-along keeps the plain ebook as its own copy', () {
      final item = {
        'media': {
          'ebookFile': _entry('7', 'epub'),
          'readAlongEpub': {'fileId': '7', 'plainEbookFile': _entry('5', 'epub')},
        },
      };
      final plain = forkPlainEbookFile(item)!;
      expect(plain['ino'], '5');
      expect(forkIsPlainCopy(plain), isTrue);
      expect(forkReadAlongFile(item)!['ino'], '7');
    });

    test('a read-along with no plain ebook beside it has no Ebook download', () {
      final item = {
        'media': {
          'ebookFile': _entry('7', 'epub'),
          'readAlongEpub': {'fileId': '7'},
        },
      };
      expect(forkPlainEbookFile(item), isNull);
      expect(forkReadAlongFile(item)!['ino'], '7');
    });

    test('a book without a read-along downloads its ebook as the reader keeps it', () {
      final item = {
        'media': {'ebookFile': _entry('5', 'mobi')},
      };
      final plain = forkPlainEbookFile(item)!;
      expect(plain['ino'], '5');
      expect(forkIsPlainCopy(plain), isFalse);
      expect(forkReadAlongFile(item), isNull);
    });

    test('a narrated book finds its plain ebook among its files', () {
      final item = {
        'media': {
          'ebookFile': _entry('7', 'epub'),
          'narration': {'fileId': '7'},
        },
        'bookOrbit': {
          'files': [
            {'id': '7', 'format': 'epub', 'readAlong': true},
            {'id': '9', 'format': 'pdf', 'readAlong': false, 'filename': 'b.pdf'},
            {'id': '8', 'format': 'epub', 'readAlong': false, 'filename': 'b.epub'},
          ],
        },
      };
      final plain = forkPlainEbookFile(item)!;
      expect(plain['ino'], '8');
      expect(forkIsPlainCopy(plain), isTrue);
    });
  });

  group('the plain copy on disk', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('plain_copy'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('lives under plain/, is found with its format, and is deleted with its side files', () async {
      final f = forkPlainCopyFile(dir, '42', '.epub')..writeAsStringSync('x');
      File('${f.path}.version').writeAsStringSync('v');
      File('${dir.path}/42.epub').writeAsStringSync('reader copy');
      expect(f.path, '${dir.path}/plain/42.epub');
      final found = forkCachedPlainCopy(dir, '42')!;
      expect(found['ebookFormat'], 'epub');
      expect(forkIsPlainCopy(found), isTrue);
      expect(forkCachedPlainCopy(dir, '4'), isNull);
      await forkDeletePlainCopies(dir, '42');
      expect(forkCachedPlainCopy(dir, '42'), isNull);
      expect(File('${f.path}.version').existsSync(), isFalse);
      expect(File('${dir.path}/42.epub').existsSync(), isTrue);
    });
  });
}
