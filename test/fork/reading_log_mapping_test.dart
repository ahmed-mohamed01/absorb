import 'package:absorb/services/api_service.dart';
import 'package:absorb/widgets/fork/reading_log_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readingLogHasPosition', () {
    test('audio files and listening to a narrated EPUB have a position', () {
      expect(readingLogHasPosition({'format': 'm4b', 'sessionType': 'read'}), isTrue);
      expect(readingLogHasPosition({'format': 'epub', 'sessionType': 'listen'}), isTrue);
      expect(readingLogHasPosition({'sessionType': 'listen'}), isTrue);
    });

    test('reading an ebook and text to speech have none', () {
      expect(readingLogHasPosition({'format': 'epub', 'sessionType': 'read'}), isFalse);
      expect(readingLogHasPosition({'format': 'epub', 'sessionType': 'tts'}), isFalse);
      expect(readingLogHasPosition({'format': 'pdf'}), isFalse);
    });
  });

  group('readingLogOwnDevice', () {
    test('matches on the start second whatever the book, offset or precision', () {
      final mine = <String, dynamic>{
        '12@2026-10-26T10:38:00.123Z': 'Pixel 9',
        '40@2026-10-25T08:00:00.000Z': 'Pixel 9',
      };
      expect(readingLogOwnDevice(mine, '2026-10-26T10:38:00.000Z'), 'Pixel 9');
      expect(readingLogOwnDevice(mine, '2026-10-26T11:38:00.500+01:00'), 'Pixel 9');
      expect(readingLogOwnDevice(mine, '2026-10-25T08:00:00Z'), 'Pixel 9');
    });

    test('anything else is not this phone', () {
      final mine = <String, dynamic>{'12@2026-10-26T10:38:00.000Z': 'Pixel 9', 'no-date': 'x'};
      expect(readingLogOwnDevice(mine, '2026-10-26T10:38:01.000Z'), isNull);
      expect(readingLogOwnDevice(mine, null), isNull);
      expect(readingLogOwnDevice(mine, 'not a date'), isNull);
      expect(readingLogOwnDevice(const {}, '2026-10-26T10:38:00.000Z'), isNull);
    });

    test('a newly read map replaces the old index', () {
      expect(readingLogOwnDevice({'1@2026-01-01T00:00:00Z': 'A'}, '2026-01-01T00:00:00Z'), 'A');
      expect(readingLogOwnDevice({'1@2026-01-02T00:00:00Z': 'B'}, '2026-01-01T00:00:00Z'), isNull);
    });
  });

  test('readingLogFields keeps what the log needs and drops nulls', () {
    final fields = readingLogFields({
      'sessionType': 'listen',
      'medium': 'listened',
      'source': 'android',
      'format': 'epub',
      'endProgress': 62.0,
      'progressDelta': 1.1,
      'id': 9,
    }, true);
    expect(fields, {
      'sessionType': 'listen',
      'medium': 'listened',
      'source': 'android',
      'ownDevice': true,
      'format': 'EPUB',
      'endProgress': 62.0,
      'progressDelta': 1.1,
    });
    expect(readingLogFields({'source': 'web'}, false), {'source': 'web', 'ownDevice': false});
  });

  group('ReadingLogEntry.fromSession', () {
    ReadingMode mode(Map<String, dynamic> s) => ReadingLogEntry.fromSession(s).mode;

    test('mode from type, format and medium', () {
      expect(mode({'sessionType': 'listen', 'format': 'M4B'}), ReadingMode.listen);
      expect(mode({'sessionType': 'listen', 'format': 'EPUB'}), ReadingMode.readAlong);
      expect(mode({'sessionType': 'tts', 'format': 'EPUB'}), ReadingMode.listen);
      expect(mode({'sessionType': 'read', 'format': 'EPUB'}), ReadingMode.read);
      // Audiobookshelf's sessions arrive with BookOrbit's default type.
      expect(mode({'sessionType': 'read', 'format': 'M4B'}), ReadingMode.listen);
      expect(mode({'sessionType': 'read', 'format': 'EPUB', 'medium': 'listened'}), ReadingMode.readAlong);
    });

    test('source is Absorb for this phone, else BookOrbit bucket', () {
      String source(Map<String, dynamic> s) => ReadingLogEntry.fromSession(s).source;
      expect(source({'source': 'android', 'ownDevice': true}), 'absorb');
      expect(source({'source': 'android'}), 'android');
      expect(source({'source': 'kobo'}), 'kobo');
      expect(source({'source': 'audiobookshelf'}), 'audiobookshelf');
      expect(source({'source': 'web'}), 'bookorbit');
      expect(source({'source': 'manual'}), 'bookorbit');
      expect(source({}), 'bookorbit');
    });

    test('change reads as one, signed', () {
      String change(Map<String, dynamic> s) => ReadingLogCard.change(ReadingLogEntry.fromSession(s));
      expect(change({'progressDelta': 4.1, 'endProgress': 65}), '+4.1% → 65%');
      expect(change({'progressDelta': -87.1, 'endProgress': 4}), '−87.1% → 4%');
      expect(change({'endProgress': 19}), '19%');
      expect(change({}), '–');
    });
  });
}
