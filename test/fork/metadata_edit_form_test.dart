import 'package:absorb/services/fork/metadata_edit_form.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _detail() => {
      'title': 'The Claw of the Conciliator',
      'subtitle': 'Science Fiction',
      'description': '<p>The saga <b>continues</b>.</p><p>Second &amp; last.</p>',
      'isbn10': '0671416162',
      'isbn13': '9780671416164',
      'publisher': 'Pocket',
      'publishedDate': '1981-02-01T00:00:00.000Z',
      'publishedYear': 1981,
      'language': 'en',
      'pageCount': 253,
      'seriesName': 'The Book of the New Sun',
      'seriesIndex': '2',
      'seriesMemberships': [
        {'seriesName': 'Solar Cycle', 'seriesIndex': '2', 'displayOrder': 1, 'expectedBookCount': null},
        {'seriesName': 'The Book of the New Sun', 'seriesIndex': '2', 'displayOrder': 0, 'expectedBookCount': 5},
      ],
      'rating': null,
      'hardcoverEditionId': '30570780',
      'providerIds': {'google': '5FUivgEACAAJ', 'goodreads': '463376', 'hardcover': 'the-claw'},
      'authors': [
        {'id': 1, 'name': 'Gene Wolfe', 'sortName': 'Wolfe, Gene'},
      ],
      'genres': ['Fantasy', 'Classics'],
      'tags': <String>[],
      'audioMetadata': {'narrators': ['Jonathan Davis'], 'durationSeconds': 41237.4, 'abridged': false},
      'customMetadata': [
        {'fieldId': 7, 'key': 'shelf', 'label': 'Shelf', 'type': 'text', 'displayOrder': 0, 'value': 'A3'},
      ],
      'lockedFields': ['cover', 'audioCover'],
    };

void main() {
  test('reads the detail, series in display order', () {
    final f = MetadataEditForm.fromDetail(_detail());
    expect(f.authors, ['Gene Wolfe']);
    expect(f.narrators, ['Jonathan Davis']);
    expect(f.series.map((s) => s.name), ['The Book of the New Sun', 'Solar Cycle']);
    expect(f.series.first.total, '5');
    expect(f.publishedDate, '1981-02-01');
    expect(f.durationSeconds, '41237');
    expect(f.description, 'The saga continues.\n\nSecond & last.');
    expect(f.providerIds['googleBooksId'], '5FUivgEACAAJ');
    expect(f.providerIds['hardcoverEditionId'], '30570780');
    expect(f.custom[7], 'A3');
    expect(f.locks, {'cover', 'audioCover'});
  });

  test('an untouched form saves nothing', () {
    final original = MetadataEditForm.fromDetail(_detail());
    expect(original.copy().saveBody(original, hasAudio: true), isNull);
  });

  test('sends only what changed, cleared fields as null, with every lock', () {
    final original = MetadataEditForm.fromDetail(_detail());
    final f = original.copy()
      ..title = 'The Claw'
      ..subtitle = ''
      ..pageCount = '300'
      ..genres = ['Fantasy']
      ..narrators = ['Jonathan Davis', 'Someone Else']
      ..providerIds['amazonId'] = 'B00X'
      ..custom[7] = null
      ..locks.add('title');
    final body = f.saveBody(original, hasAudio: true)!;
    final m = body['metadata'] as Map<String, dynamic>;
    expect(m.keys.toSet(), {'title', 'subtitle', 'pageCount', 'genres', 'amazonId', 'customMetadata', 'audioMetadata'});
    expect(m['subtitle'], isNull);
    expect(m['pageCount'], 300);
    expect(m['customMetadata'], [
      {'fieldId': 7, 'value': null},
    ]);
    expect(m['audioMetadata'], {
      'narrators': ['Jonathan Davis', 'Someone Else'],
    });
    expect(body['lockedFields'], ['audioCover', 'cover', 'title']);
  });

  test('a lock change alone is a save, and audio fields stay off an ebook', () {
    final original = MetadataEditForm.fromDetail(_detail());
    final f = original.copy()
      ..locks.remove('cover')
      ..narrators = ['X'];
    final body = f.saveBody(original, hasAudio: false)!;
    expect(body.containsKey('metadata'), isFalse);
    expect(body['lockedFields'], ['audioCover']);
  });

  test('series are sent whole when one changes, and empty rows are dropped', () {
    final original = MetadataEditForm.fromDetail(_detail());
    final f = original.copy();
    f.series.first.index = '2.5';
    f.series.add(SeriesRow());
    final m = f.changes(original, hasAudio: true);
    expect(m['seriesMemberships'], [
      {'seriesName': 'The Book of the New Sun', 'seriesIndex': '2.5', 'expectedBookCount': 5},
      {'seriesName': 'Solar Cycle', 'seriesIndex': '2'},
    ]);
  });

  test('counts changed fields, audio and custom ones each, and locks once', () {
    final original = MetadataEditForm.fromDetail(_detail());
    expect(original.copy().changeCount(original, hasAudio: true), 0);
    final f = original.copy()
      ..title = 'The Claw'
      ..narrators = ['Someone Else']
      ..custom[7] = null
      ..locks.addAll(['title', 'subtitle']);
    expect(f.changeCount(original, hasAudio: true), 4);
  });

  test('reads and writes a length as hours and minutes', () {
    expect(formatLength('41237'), '11h 27m');
    expect(formatLength('1500'), '25m');
    expect(formatLength(''), '');
    expect(parseLength('11h 27m'), 41220);
    expect(parseLength('11H'), 39600);
    expect(parseLength('11h 2'), 39720);
    expect(parseLength('27m'), 1620);
    expect(parseLength('27'), 1620);
    expect(parseLength('11:27'), 41220);
    expect(parseLength('11:27:17'), 41237);
    expect(parseLength('soon'), isNull);
    expect(parseLength('11h 27m extra'), isNull);
  });

  test('ranks covers of the slot shape first, keeping their order', () {
    final items = [('a', 'portrait'), ('b', null), ('c', 'square'), ('d', 'portrait'), ('e', 'square'), ('f', 'unknown')];
    List<String> sorted(String slot) => [for (final i in sortByCoverFit(items, slot, (i) => i.$2)) i.$1];
    expect(sorted('audio'), ['c', 'e', 'b', 'f', 'a', 'd']);
    expect(sorted('ebook'), ['a', 'd', 'b', 'f', 'c', 'e']);
  });

  test('a changed description is saved as paragraphs', () {
    final original = MetadataEditForm.fromDetail(_detail());
    final f = original.copy()..description = 'One <two>\nline\n\nThree';
    expect(f.changes(original, hasAudio: true)['description'], '<p>One &lt;two&gt;<br>line</p><p>Three</p>');
  });

  test('fill skips locked fields and empty values', () {
    final f = MetadataEditForm.fromDetail(_detail())..locks.add('title');
    final result = f.fill({
      'title': 'Other',
      'publisher': 'Tor',
      'subtitle': '',
      'genres': <String>[],
      'goodreadsId': '999',
      'audioMetadata': {'narrators': ['N']},
    });
    expect(result.filled, 3);
    expect(result.locked, 1);
    expect(f.title, 'The Claw of the Conciliator');
    expect(f.publisher, 'Tor');
    expect(f.providerIds['goodreadsId'], '999');
    expect(f.narrators, ['N']);
  });

  test('a match fills isbn, date, series and links its source', () {
    final f = MetadataEditForm.fromDetail(_detail());
    f.fillFromMatch({
      'isbn': '978-0-00-000000-2',
      'publishedYear': '1982-03-04',
      'series': [
        {'name': 'New Sun', 'sequence': '2'},
      ],
      'bookOrbitProviderIds': {'amazon': 'B01'},
    });
    expect(f.isbn13, '9780000000002');
    expect(f.publishedDate, '1982-03-04');
    expect(f.publishedYear, '1982');
    expect(f.series.single.name, 'New Sun');
    expect(f.providerIds['amazonId'], 'B01');
  });

  test('fill counts only real changes, and locks only where they hide one', () {
    final f = MetadataEditForm(title: 'Same', publisher: 'Old', locks: {'publisher', 'language'}, language: 'en');
    final result = f.fill({'title': 'Same', 'publisher': 'New', 'language': 'en'});
    expect(result.filled, 0);
    expect(result.locked, 1);
  });

  group('year and date', () {
    MetadataEditForm dated() => MetadataEditForm(publishedDate: '1981-02-01', publishedYear: '1981');

    test('a new year moves the date, and the save keeps it', () {
      final original = dated();
      final f = original.copy()..setYear('1982');
      expect(f.publishedDate, '1982-02-01');
      expect(f.changes(original, hasAudio: false)['publishedDate'], '1982-02-01');
    });

    test('a half-typed year leaves the date alone', () {
      final f = dated()..setYear('198');
      expect(f.publishedDate, '1981-02-01');
      f.setYear('1981');
      expect(f.publishedDate, '1981-02-01');
    });

    test('clearing the year clears the date too', () {
      final original = dated();
      final f = original.copy()..setYear('');
      final m = f.changes(original, hasAudio: false);
      expect(m.containsKey('publishedDate'), isTrue);
      expect(m['publishedDate'], isNull);
      expect(m['publishedYear'], isNull);
    });

    test('a day the new year lacks clears the date', () {
      final f = MetadataEditForm(publishedDate: '1980-02-29', publishedYear: '1980')..setYear('1981');
      expect(f.publishedDate, '');
      expect(f.publishedYear, '1981');
    });

    test('a year from a match drops a date from another year', () {
      final f = dated();
      f.fillFromMatch({'publishedYear': '1990'});
      expect(f.publishedYear, '1990');
      expect(f.publishedDate, '');
    });

    test('a partial date from a match gives its year and keeps a date of that year', () {
      final f = dated();
      f.fillFromMatch({'publishedYear': '1981-05'});
      expect(f.publishedYear, '1981');
      expect(f.publishedDate, '1981-02-01');
    });
  });

  test('text the server can not take is named, and untouched values pass', () {
    final original = MetadataEditForm(publishedYear: '12', pageCount: '100');
    expect(original.copy().invalidFields(original), isEmpty);
    final f = original.copy()
      ..publishedYear = '19x'
      ..pageCount = 'lots'
      ..series = [SeriesRow(name: 'A', total: 'five')];
    expect(f.invalidFields(original), ['Year', 'Pages', 'Series total']);
    f
      ..publishedYear = '999'
      ..pageCount = ''
      ..series = [SeriesRow(name: 'A', total: '5')];
    expect(f.invalidFields(original), ['Year']);
  });
}
