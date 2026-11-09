// Fork-owned: the BookOrbit Edit metadata page's form, free of Flutter so
// it is unit-tested. It is read straight from BookOrbit's book detail (not
// the Audiobookshelf-shaped item), and turns into the body of
// `PATCH /books/:id/metadata-and-locks`: only the fields that changed, plus
// the whole lock list. See FORK_NOTES.md.

/// One series the book belongs to. [total] is the series' expected number
/// of books, shared by every book in it.
class SeriesRow {
  String name;
  String index;
  String total;

  SeriesRow({this.name = '', this.index = '', this.total = ''});

  SeriesRow copy() => SeriesRow(name: name, index: index, total: total);

  bool get isEmpty => name.trim().isEmpty;
}

/// A custom metadata field the server has for this book's library.
class CustomField {
  final int id;
  final String label;

  /// text, url, number, date or boolean.
  final String type;

  const CustomField({required this.id, required this.label, required this.type});
}

/// A provider id the book can hold: the update field it is saved under
/// (also its lock name) and the label BookOrbit's web editor gives it.
typedef ProviderIdField = ({String field, String key, String label});

/// BookOrbit's provider ids in its web editor's order. [key] is the name in
/// the detail's `providerIds`; Hardcover's edition id sits on the detail.
const List<ProviderIdField> kProviderIdFields = [
  (field: 'googleBooksId', key: 'google', label: 'Google Books'),
  (field: 'goodreadsId', key: 'goodreads', label: 'Goodreads'),
  (field: 'amazonId', key: 'amazon', label: 'Amazon'),
  (field: 'hardcoverId', key: 'hardcover', label: 'Hardcover'),
  (field: 'hardcoverEditionId', key: 'hardcoverEdition', label: 'Hardcover edition'),
  (field: 'openLibraryId', key: 'openLibrary', label: 'Open Library'),
  (field: 'itunesId', key: 'itunes', label: 'iTunes'),
  (field: 'audibleId', key: 'audible', label: 'Audible'),
  (field: 'librofmId', key: 'librofm', label: 'Libro.fm'),
  (field: 'koboId', key: 'kobo', label: 'Kobo'),
  (field: 'comicvineId', key: 'comicvine', label: 'Comic Vine'),
  (field: 'ranobedbId', key: 'ranobedb', label: 'RanobeDB'),
  (field: 'lubimyczytacId', key: 'lubimyczytac', label: 'Lubimyczytać'),
  (field: 'aladinId', key: 'aladin', label: 'Aladin'),
];

String _str(Object? v) => v == null ? '' : '$v'.trim();

List<String> _strings(Object? v) => [
      for (final e in (v is List ? v : const []))
        if (_str(e is Map ? e['name'] : e).isNotEmpty) _str(e is Map ? e['name'] : e),
    ];

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Description HTML as the paragraphs a plain text box shows.
String descriptionToText(String html) {
  if (!html.contains('<')) return html.trim();
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|h[1-6]|blockquote)>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Plain text back to the HTML BookOrbit stores: one paragraph per blank
/// line, single line breaks kept.
String textToDescription(String text) {
  String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  return [
    for (final p in text.trim().split(RegExp(r'\n\s*\n')))
      if (p.trim().isNotEmpty) '<p>${esc(p.trim()).replaceAll('\n', '<br>')}</p>',
  ].join();
}

/// The editable copy of a book's metadata.
/// A length in whole seconds as hours and minutes, like `11h 27m`. Text that
/// is not a number comes back as it is.
String formatLength(String seconds) {
  final value = num.tryParse(seconds.trim());
  if (value == null) return seconds;
  final total = value.toInt();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// The seconds in a typed length: `11h 27m`, `11h`, `27m`, `11:27`, `11:27:05`,
/// or a bare number of minutes. Null when it can't be read.
int? parseLength(String text) {
  final t = text.trim().toLowerCase();
  final hm = RegExp(r'^(\d+)\s*h(?:ours?|rs?)?\s*(?:(\d+)\s*m?(?:ins?|inutes?)?)?$').firstMatch(t);
  if (hm != null) return int.parse(hm[1]!) * 3600 + int.parse(hm[2] ?? '0') * 60;
  final m = RegExp(r'^(\d+)\s*(?:m(?:ins?|inutes?)?)?$').firstMatch(t);
  if (m != null) return int.parse(m[1]!) * 60;
  final clock = RegExp(r'^(\d+):(\d{1,2})(?::(\d{1,2}))?$').firstMatch(t);
  if (clock != null) {
    return int.parse(clock[1]!) * 3600 + int.parse(clock[2]!) * 60 + int.parse(clock[3] ?? '0');
  }
  return null;
}

/// What a fill did: fields it changed, and fields it left because of a lock.
typedef FillResult = ({int filled, int locked});

/// A published year BookOrbit accepts.
bool _isYear(String text) {
  final year = int.tryParse(text);
  return year != null && year >= 1000 && year <= 2200;
}

class MetadataEditForm {
  String title;
  String subtitle;
  List<String> authors;
  List<String> narrators;
  List<SeriesRow> series;
  String publisher;
  List<String> genres;
  List<String> tags;
  String language;

  /// YYYY-MM-DD, or empty.
  String publishedDate;
  String publishedYear;
  String pageCount;
  String isbn13;
  String isbn10;
  String durationSeconds;
  bool abridged;
  int? rating;

  /// The description as plain text (see [descriptionToText]).
  String description;

  /// By update field name (`googleBooksId`, ...).
  Map<String, String> providerIds;

  /// By custom field id: a String, num or bool, or null when unset.
  Map<int, Object?> custom;

  /// BookOrbit lock names (`title`, `seriesName`, `cover`, ...).
  Set<String> locks;

  MetadataEditForm({
    this.title = '',
    this.subtitle = '',
    List<String>? authors,
    List<String>? narrators,
    List<SeriesRow>? series,
    this.publisher = '',
    List<String>? genres,
    List<String>? tags,
    this.language = '',
    this.publishedDate = '',
    this.publishedYear = '',
    this.pageCount = '',
    this.isbn13 = '',
    this.isbn10 = '',
    this.durationSeconds = '',
    this.abridged = false,
    this.rating,
    this.description = '',
    Map<String, String>? providerIds,
    Map<int, Object?>? custom,
    Set<String>? locks,
  })  : authors = authors ?? [],
        narrators = narrators ?? [],
        series = series ?? [],
        genres = genres ?? [],
        tags = tags ?? [],
        providerIds = providerIds ?? {},
        custom = custom ?? {},
        locks = locks ?? {};

  factory MetadataEditForm.fromDetail(Map<String, dynamic> d) {
    final audio = d['audioMetadata'] is Map ? (d['audioMetadata'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final ids = d['providerIds'] is Map ? (d['providerIds'] as Map) : const {};
    final memberships = (d['seriesMemberships'] is List ? d['seriesMemberships'] as List : const [])
        .whereType<Map>()
        .toList()
      ..sort((a, b) => ((a['displayOrder'] as num?) ?? 0).compareTo((b['displayOrder'] as num?) ?? 0));
    final series = [
      for (final m in memberships)
        if (_str(m['seriesName']).isNotEmpty)
          SeriesRow(name: _str(m['seriesName']), index: _str(m['seriesIndex']), total: _str(m['expectedBookCount'])),
    ];
    if (series.isEmpty && _str(d['seriesName']).isNotEmpty) {
      series.add(SeriesRow(name: _str(d['seriesName']), index: _str(d['seriesIndex'])));
    }
    final date = _str(d['publishedDate']);
    return MetadataEditForm(
      title: _str(d['title']),
      subtitle: _str(d['subtitle']),
      authors: _strings(d['authors']),
      narrators: _strings(audio['narrators']),
      series: series,
      publisher: _str(d['publisher']),
      genres: _strings(d['genres']),
      tags: _strings(d['tags']),
      language: _str(d['language']),
      publishedDate: date.length >= 10 ? date.substring(0, 10) : date,
      publishedYear: _str(d['publishedYear']),
      pageCount: _str(d['pageCount']),
      isbn13: _str(d['isbn13']),
      isbn10: _str(d['isbn10']),
      durationSeconds: audio['durationSeconds'] is num ? '${(audio['durationSeconds'] as num).round()}' : '',
      abridged: audio['abridged'] == true,
      rating: (d['rating'] as num?)?.round(),
      description: descriptionToText(_str(d['description'])),
      providerIds: {
        for (final p in kProviderIdFields)
          p.field: _str(p.key == 'hardcoverEdition' ? (d['hardcoverEditionId'] ?? ids[p.key]) : ids[p.key]),
      },
      custom: {
        for (final c in (d['customMetadata'] is List ? d['customMetadata'] as List : const []).whereType<Map>())
          if (c['fieldId'] is num) (c['fieldId'] as num).toInt(): c['value'],
      },
      locks: {for (final l in (d['lockedFields'] is List ? d['lockedFields'] as List : const [])) '$l'},
    );
  }

  MetadataEditForm copy() => MetadataEditForm(
        title: title,
        subtitle: subtitle,
        authors: List.of(authors),
        narrators: List.of(narrators),
        series: [for (final s in series) s.copy()],
        publisher: publisher,
        genres: List.of(genres),
        tags: List.of(tags),
        language: language,
        publishedDate: publishedDate,
        publishedYear: publishedYear,
        pageCount: pageCount,
        isbn13: isbn13,
        isbn10: isbn10,
        durationSeconds: durationSeconds,
        abridged: abridged,
        rating: rating,
        description: description,
        providerIds: Map.of(providerIds),
        custom: Map.of(custom),
        locks: Set.of(locks),
      );

  List<SeriesRow> get _filledSeries => [for (final s in series) if (!s.isEmpty) s];

  bool _seriesChanged(MetadataEditForm o) {
    final a = _filledSeries, b = o._filledSeries;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].name.trim() != b[i].name.trim() ||
          a[i].index.trim() != b[i].index.trim() ||
          a[i].total.trim() != b[i].total.trim()) {
        return true;
      }
    }
    return false;
  }

  /// The `metadata` part of the save: each field that differs from
  /// [original], a cleared one as null. Narrators, duration and abridged go
  /// under `audioMetadata`, and only for a book with audio.
  Map<String, dynamic> changes(MetadataEditForm original, {required bool hasAudio}) {
    final out = <String, dynamic>{};
    String? text(String v) => v.trim().isEmpty ? null : v.trim();
    int? number(String v) => int.tryParse(v.trim());
    void field(String key, String now, String was, [Object? Function(String)? convert]) {
      if (now.trim() == was.trim()) return;
      out[key] = (convert ?? text)(now);
    }

    field('title', title, original.title);
    field('subtitle', subtitle, original.subtitle);
    field('publisher', publisher, original.publisher);
    field('language', language, original.language);
    field('publishedDate', publishedDate, original.publishedDate);
    field('publishedYear', publishedYear, original.publishedYear, number);
    field('pageCount', pageCount, original.pageCount, number);
    field('isbn13', isbn13, original.isbn13);
    field('isbn10', isbn10, original.isbn10);
    if (description.trim() != original.description.trim()) {
      out['description'] = description.trim().isEmpty ? null : textToDescription(description);
    }
    if (!_sameList(authors, original.authors)) out['authors'] = authors;
    if (!_sameList(genres, original.genres)) out['genres'] = genres;
    if (!_sameList(tags, original.tags)) out['tags'] = tags;
    if (rating != original.rating) out['rating'] = rating;
    if (_seriesChanged(original)) {
      out['seriesMemberships'] = [
        for (final s in _filledSeries)
          {
            'seriesName': s.name.trim(),
            'seriesIndex': text(s.index),
            if (number(s.total) != null) 'expectedBookCount': number(s.total),
          },
      ];
    }
    for (final p in kProviderIdFields) {
      field(p.field, providerIds[p.field] ?? '', original.providerIds[p.field] ?? '');
    }
    final customChanges = [
      for (final e in custom.entries)
        if (e.value != original.custom[e.key]) {'fieldId': e.key, 'value': e.value},
    ];
    if (customChanges.isNotEmpty) out['customMetadata'] = customChanges;
    if (hasAudio) {
      final audio = <String, dynamic>{};
      if (!_sameList(narrators, original.narrators)) audio['narrators'] = narrators;
      if (durationSeconds.trim() != original.durationSeconds.trim()) audio['durationSeconds'] = number(durationSeconds);
      if (abridged != original.abridged) audio['abridged'] = abridged;
      if (audio.isNotEmpty) out['audioMetadata'] = audio;
    }
    return out;
  }

  /// How many fields differ from [original], for the Save bar. A lock change
  /// counts once however many locks moved.
  int changeCount(MetadataEditForm original, {required bool hasAudio}) {
    var n = locksChanged(original) ? 1 : 0;
    changes(original, hasAudio: hasAudio).forEach((key, value) {
      n += key == 'audioMetadata' && value is Map
          ? value.length
          : key == 'customMetadata' && value is List
              ? value.length
              : 1;
    });
    return n;
  }

  bool locksChanged(MetadataEditForm original) =>
      locks.length != original.locks.length || !locks.containsAll(original.locks);

  /// The body of `PATCH /books/:id/metadata-and-locks`, or null when
  /// nothing changed.
  Map<String, dynamic>? saveBody(MetadataEditForm original, {required bool hasAudio}) {
    final metadata = changes(original, hasAudio: hasAudio);
    if (metadata.isEmpty && !locksChanged(original)) return null;
    return {
      if (metadata.isNotEmpty) 'metadata': metadata,
      'lockedFields': locks.toList()..sort(),
    };
  }

  /// Every lock the page shows a toggle for, for Lock all.
  static List<String> lockNames({required bool hasAudio, required Iterable<String> coverLocks}) => [
        'title', 'subtitle', 'authors', if (hasAudio) 'narrators', 'seriesName', 'publisher',
        'genres', 'tags', 'language', 'publishedYear', 'pageCount', 'isbn13', 'isbn10',
        if (hasAudio) ...['durationSeconds', 'abridged'], 'rating', 'description',
        for (final p in kProviderIdFields) p.field,
        ...coverLocks,
      ];

  /// Sets the typed year. BookOrbit keeps a date and a year in step (a year
  /// sent alone clears the date), so a date moves to the new year, keeping its
  /// month and day. It goes when the year does, or when that day doesn't exist
  /// in the new year. A half-typed year leaves it alone.
  void setYear(String value) {
    publishedYear = value;
    final t = value.trim();
    if (t.isEmpty) {
      publishedDate = '';
      return;
    }
    if (!_isYear(t) || publishedDate.length < 10) return;
    final moved = '$t${publishedDate.substring(4)}';
    // A day past the month's end rolls over instead of failing to parse.
    publishedDate = DateTime.tryParse(moved)?.day == int.tryParse(moved.substring(8, 10)) ? moved : '';
  }

  /// The fields whose typed text BookOrbit can't take, by their labels. A
  /// save would otherwise turn them into a cleared field or lose them.
  List<String> invalidFields(MetadataEditForm original) => [
        if (publishedYear.trim() != original.publishedYear.trim() &&
            publishedYear.trim().isNotEmpty &&
            !_isYear(publishedYear.trim()))
          'Year',
        if (pageCount.trim() != original.pageCount.trim() &&
            pageCount.trim().isNotEmpty &&
            int.tryParse(pageCount.trim()) == null)
          'Pages',
        if (series.any((s) => s.total.trim().isNotEmpty && int.tryParse(s.total.trim()) == null)) 'Series total',
      ];

  /// Puts what a search or refresh found into the form, skipping locked
  /// fields. [found] uses BookOrbit's update field names (a refresh
  /// preview's `metadata`). Says how many fields changed, and how many more
  /// would have if they weren't locked.
  FillResult fill(Map<String, dynamic> found, {bool hasAudio = true}) {
    final before = copy();
    final unlocked = copy()..locks = {};
    unlocked._fill(found);
    _fill(found);
    unlocked.locks = locks;
    return (
      filled: changeCount(before, hasAudio: hasAudio),
      locked: unlocked.changeCount(this, hasAudio: hasAudio),
    );
  }

  void _fill(Map<String, dynamic> found) {
    void put(String lock, Object? value, void Function(Object? v) set) {
      if (value == null || locks.contains(lock)) return;
      if (value is String && value.trim().isEmpty) return;
      if (value is List && value.isEmpty) return;
      set(value);
    }

    put('title', found['title'], (v) => title = _str(v));
    put('subtitle', found['subtitle'], (v) => subtitle = _str(v));
    put('authors', found['authors'], (v) => authors = _strings(v));
    put('publisher', found['publisher'], (v) => publisher = _str(v));
    put('genres', found['genres'], (v) => genres = _strings(v));
    put('tags', found['tags'], (v) => tags = _strings(v));
    put('language', found['language'], (v) => language = _str(v));
    final date = RegExp(r'^\d{4}-\d{2}-\d{2}').stringMatch(_str(found['publishedDate']));
    if (date != null) {
      put('publishedYear', date, (_) {
        publishedDate = date;
        publishedYear = date.substring(0, 4);
      });
    } else {
      // Sources also give partial dates like 2021-05. A year alone says
      // nothing of the month, so a date from another year goes.
      put('publishedYear', found['publishedYear'] ?? found['publishedDate'], (v) {
        final year = RegExp(r'\b\d{4}\b').stringMatch(_str(v));
        if (year == null || !_isYear(year)) return;
        publishedYear = year;
        if (!publishedDate.startsWith(year)) publishedDate = '';
      });
    }
    put('pageCount', found['pageCount'], (v) => pageCount = _str(v));
    put('isbn13', found['isbn13'], (v) => isbn13 = _str(v));
    put('isbn10', found['isbn10'], (v) => isbn10 = _str(v));
    put('description', found['description'], (v) => description = descriptionToText(_str(v)));
    final memberships = found['seriesMemberships'];
    if (memberships is List && memberships.isNotEmpty) {
      put('seriesName', memberships, (v) => series = [
            for (final m in (v as List).whereType<Map>())
              if (_str(m['seriesName']).isNotEmpty)
                SeriesRow(name: _str(m['seriesName']), index: _str(m['seriesIndex']), total: _str(m['expectedBookCount'])),
          ]);
    } else if (_str(found['seriesName']).isNotEmpty) {
      put('seriesName', found['seriesName'],
          (v) => series = [SeriesRow(name: _str(v), index: _str(found['seriesIndex']))]);
    }
    for (final p in kProviderIdFields) {
      put(p.field, found[p.field], (v) => providerIds[p.field] = _str(v));
    }
    final audio = found['audioMetadata'];
    if (audio is Map) {
      put('narrators', audio['narrators'], (v) => narrators = _strings(v));
      put('durationSeconds', audio['durationSeconds'], (v) => durationSeconds = v is num ? '${v.round()}' : _str(v));
      put('abridged', audio['abridged'], (v) => abridged = v == true);
    }
  }

  /// Puts a match's picks into the form. [picked] is the Audiobookshelf
  /// media shape `buildMatchUpdate` makes; its `bookOrbitProviderIds` (by
  /// search provider key) link the book to the sources used.
  FillResult fillFromMatch(Map<String, dynamic> picked, {bool hasAudio = true}) {
    final found = <String, dynamic>{
      for (final k in ['title', 'subtitle', 'description', 'publisher', 'language', 'genres']) k: picked[k],
      'authors': picked['authors'],
      'publishedYear': picked['publishedYear'],
    };
    final isbn = _str(picked['isbn']).replaceAll('-', '');
    if (isbn.length == 13) found['isbn13'] = isbn;
    if (isbn.length == 10) found['isbn10'] = isbn;
    final year = _str(picked['publishedYear']);
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(year)) {
      found['publishedDate'] = year;
      found['publishedYear'] = year.substring(0, 4);
    }
    if (picked['series'] is List) {
      found['seriesMemberships'] = [
        for (final s in (picked['series'] as List).whereType<Map>())
          {'seriesName': s['name'], 'seriesIndex': s['sequence']},
      ];
    }
    if (picked['narrators'] != null) found['audioMetadata'] = {'narrators': picked['narrators']};
    final ids = picked['bookOrbitProviderIds'];
    if (ids is Map) {
      for (final p in kProviderIdFields) {
        if (ids[p.key] != null) found[p.field] = ids[p.key];
      }
    }
    return fill(found, hasAudio: hasAudio);
  }
}

/// [items] with art of [slot]'s shape first, then art of unknown shape, then
/// the other shape, each group in its order. An audiobook cover is square, a
/// book's portrait, as BookOrbit's web editor ranks them.
List<T> sortByCoverFit<T>(List<T> items, String slot, String? Function(T) shapeOf) {
  final want = slot == 'audio' ? 'square' : 'portrait';
  int rank(T item) {
    final shape = shapeOf(item);
    if (shape == want) return 0;
    return shape == 'square' || shape == 'portrait' ? 2 : 1;
  }

  final order = {for (var i = 0; i < items.length; i++) i: rank(items[i])};
  final indexes = order.keys.toList()..sort((a, b) => order[a]! != order[b]! ? order[a]! - order[b]! : a - b);
  return [for (final i in indexes) items[i]];
}
