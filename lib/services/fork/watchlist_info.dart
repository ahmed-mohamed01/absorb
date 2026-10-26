// Fork-owned: the Watchlist-only part of a watchlist item (`item['watchlist']`),
// the way BookDockInfo reads `item['bookDock']`. See FORK_NOTES.md.

import '../api_service.dart';

/// One community rating of a watchlist work.
class WatchlistRating {
  final String source;
  final double average;
  final int? count;

  const WatchlistRating({required this.source, required this.average, this.count});

  String get sourceLabel => switch (source) {
        'goodreads' => 'Goodreads',
        'audible' => 'Audible',
        'hardcover' => 'Hardcover',
        _ => source,
      };
}

/// One BookOrbit Watchlist work, as the data layer stamps it on a virtual
/// library item, with the release of each format it covers. Null for every
/// real book.
class WatchlistInfo {
  final Map<String, dynamic> raw;

  const WatchlistInfo._(this.raw);

  static const allFormats = ['ebook', 'audiobook'];

  static bool isLibrary(String? libraryId) => libraryId == ApiService.watchlistLibraryId;

  /// The Library tab pills the watchlist shows: its authors, then its
  /// releases grid twice, once per [WatchlistWhen]. Null for every other
  /// library.
  static List<({int tab, String label, WatchlistWhen? when})>? pills(String? libraryId) =>
      isLibrary(libraryId) ? _pills : null;
  static const List<({int tab, String label, WatchlistWhen? when})> _pills = [
    (tab: 2, label: 'Authors', when: null),
    (tab: 0, label: 'Recent', when: WatchlistWhen.outNow),
    (tab: 0, label: 'Upcoming', when: WatchlistWhen.upcoming),
  ];

  static WatchlistInfo? of(Map<String, dynamic>? item) {
    final w = item?['watchlist'];
    if (w is! Map) return null;
    return WatchlistInfo._(Map<String, dynamic>.from(w));
  }

  String get workId => '${raw['workId'] ?? ''}';
  String get monitorAuthorId => '${raw['monitorAuthorId'] ?? ''}';
  String? get authorLastRefreshedAt => raw['authorLastRefreshedAt'] as String?;

  /// The formats this card stands for, ebook first: the ones with a release
  /// in the list it came from, else the ones the work is watched for.
  List<String> get formats {
    final listed = raw['formats'];
    final own = listed is List ? listed.map((f) => '$f').toSet() : const <String>{};
    final out = [for (final f in allFormats) if (own.contains(f)) f];
    return out.isEmpty ? const ['ebook'] : out;
  }

  /// The card's leading format, for anything that only has room for one.
  String get format => formats.first;

  /// The release list's entry for [format]: `{status, releaseDate,
  /// requestId}`. Null when the card did not come from a release of it.
  Map<String, dynamic>? releaseFor(String format) {
    final r = (raw['releases'] as Map?)?[format];
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  /// The release list's status for [format]: upcoming, available, queued,
  /// downloading, moving, needs_review or grabbed (owned).
  String? releaseStatusFor(String format) => releaseFor(format)?['status'] as String?;

  /// The book request behind [format]. The work's id comes first: the
  /// server fills the release's from it, and a grab or retry that replaces a
  /// finished request patches the work.
  int? requestIdFor(String format) =>
      (_workMap('requestIds')?[format] as num?)?.toInt() ?? (releaseFor(format)?['requestId'] as num?)?.toInt();

  /// BookOrbit only lets the author's owner change or request a work; a
  /// missing flag is read as owned so older payloads keep their actions.
  bool get isOwner => raw['isOwner'] != false;

  /// The author's mode for [format]: notify, auto-upcoming, auto-all or off.
  String? authorMode(String format) => (raw['authorModes'] as Map?)?[format] as String?;

  Map<String, dynamic> get work {
    final w = raw['work'];
    return w is Map ? Map<String, dynamic>.from(w) : const {};
  }

  Map? _workMap(String key) => work[key] as Map?;

  String get title => '${work['title'] ?? ''}';
  String? get subtitle => work['subtitle'] as String?;
  String? get description => work['description'] as String?;
  String? get coverUrl => work['coverUrl'] as String?;
  int? get releaseYear => (work['releaseYear'] as num?)?.toInt();
  String? get seriesName => work['seriesName'] as String?;
  String? get seriesIndex => work['seriesIndex']?.toString();

  /// The date [format] is expected on: its release's date, else read through
  /// the release probe like BookOrbit does (a store saying the format is not
  /// listed beats the catalog).
  String? releaseDateTextFor(String format) {
    final listed = releaseFor(format)?['releaseDate'];
    if (listed is String && listed.isNotEmpty) return listed;
    final probe = _workMap('formatReleases')?[format];
    if (probe is Map) {
      if (probe['status'] == 'unlisted') return null;
      final d = probe['releaseDate'];
      if (d is String && d.isNotEmpty) return d;
    }
    return (format == 'ebook' ? work['ebookReleaseDate'] : work['audioReleaseDate']) as String?;
  }

  DateTime? releaseDateFor(String format) => parseDate(releaseDateTextFor(format));

  /// How much of [releaseDateTextFor] is known: BookOrbit stores the
  /// precision beside the date, so a year-only date is never shown as Jan 1.
  String? precisionFor(String format) => _precisionOf(releaseDateTextFor(format), format);

  String? _precisionOf(String? text, String format) {
    if (text == null) return null;
    final probe = _workMap('formatReleases')?[format];
    if (probe is Map && probe['releaseDate'] == text && probe['precision'] is String) {
      return probe['precision'] as String;
    }
    final column = format == 'ebook' ? 'ebook' : 'audio';
    final own = work['${column}DatePrecision'];
    if (work['${column}ReleaseDate'] == text && own is String) return own;
    // With nothing stored, a full January 1 is how a year-only date arrives.
    final inferred = precisionOf(text);
    final date = parseDate(text);
    return inferred == 'day' && date != null && date.month == 1 && date.day == 1 ? 'year' : inferred;
  }

  bool isOwned(String format) =>
      ((work['ownedFormats'] as List?) ?? const []).contains(format) ||
      matchedBookId(format) != null ||
      releaseStatusFor(format) == 'grabbed';

  int? matchedBookId(String format) => (_workMap('matchedBookIds')?[format] as num?)?.toInt();

  /// A missing entry means the work follows the author, which watches it.
  bool isWatching(String format) => _workMap('monitorFormats')?[format] != false;

  /// Null follows the author's mode.
  bool? autoDownload(String format) => _workMap('autoDownload')?[format] as bool?;

  /// The author's mode decides when the work has no override of its own.
  bool effectiveAutoDownload(String format) {
    final own = autoDownload(format);
    if (own != null) return own;
    final mode = authorMode(format);
    return mode == 'auto-all' || mode == 'auto-upcoming';
  }

  /// The book request status for [format]: pending, approved, searching,
  /// grabbed, downloading, importing, needs_review, available, failed, ...
  String? requestStatus(String format) => _workMap('requestStatuses')?[format] as String?;

  /// The download percent of [format]'s request from the last status read,
  /// while it reports one.
  int? requestProgress(String format) => (_workMap('requestProgress')?[format] as num?)?.toInt();

  /// Whether a request for [format] still has work left, so no new one is offered.
  bool requestActive(String format) => switch (requestStatus(format)) {
        'pending' || 'approved' || 'searching' || 'grabbed' || 'downloading' || 'importing' || 'needs_review' => true,
        _ => false,
      };

  /// BookOrbit's one-word state for [format], in its order of precedence:
  /// owned, downloading, importing, queued, needs_choice, failed,
  /// not_watching, missing, upcoming, unannounced.
  String formatStatus(String format) {
    if (isOwned(format)) return 'owned';
    // The release list states the acquisition when the work has no request
    // status of its own, in its own words.
    final status = requestStatus(format) ??
        switch (releaseStatusFor(format)) {
          'queued' => 'pending',
          'moving' => 'importing',
          final s => s,
        };
    switch (status) {
      case 'downloading':
        return 'downloading';
      case 'importing':
        return 'importing';
      case 'pending' || 'approved' || 'searching' || 'grabbed':
        return 'queued';
      case 'needs_review':
        return 'needs_choice';
      case 'failed':
        return 'failed';
    }
    if (!isWatching(format) || authorMode(format) == 'off') return 'not_watching';
    final text = releaseDateTextFor(format);
    if (parseDate(text) == null) return 'unannounced';
    return releaseStarted(text, precisionFor(format)) ? 'missing' : 'upcoming';
  }

  List<WatchlistRating> get ratings => [
        for (final r in ((work['ratings'] as List?) ?? const []).whereType<Map>())
          if (r['average'] is num)
            WatchlistRating(
              source: '${r['source'] ?? ''}',
              average: (r['average'] as num).toDouble(),
              count: (r['count'] as num?)?.toInt(),
            ),
      ];

  /// BookOrbit dates can be a year (`2027`), a month (`2027-11`) or a day.
  static DateTime? parseDate(String? text) {
    final t = text?.trim() ?? '';
    final m = RegExp(r'^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?').firstMatch(t);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.tryParse(m.group(2) ?? '') ?? 1,
      int.tryParse(m.group(3) ?? '') ?? 1,
    );
  }

  /// BookOrbit's "today": the UTC day, as `YYYY-MM-DD`.
  static String todayUtc() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

  static final _partialDate = RegExp(r'^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$');

  /// Whether a release's window has opened by [today] (default
  /// [todayUtc]), as BookOrbit's `monitoredReleaseStarted` reads it: a year
  /// starts on January 1, a month on its first day, and a missing or
  /// malformed date, or one shorter than its precision, has not started.
  static bool releaseStarted(String? text, String? precision, {String? today}) {
    final t = text?.trim() ?? '';
    final m = _partialDate.firstMatch(t);
    if (m == null) return false;
    final effective = precision ?? (m.group(3) != null ? 'day' : (m.group(2) != null ? 'month' : 'year'));
    if (effective == 'day' && t.length != 10) return false;
    if (effective == 'month' && t.length < 7) return false;
    final start = switch (effective) {
      'year' => '${t.substring(0, 4)}-01-01',
      'month' => '${t.substring(0, 7)}-01',
      _ => t,
    };
    return start.compareTo(today ?? todayUtc()) <= 0;
  }

  /// 'day', 'month' or 'year', from how much of the date [text] spells out.
  static String? precisionOf(String? text) {
    final t = text?.trim() ?? '';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(t)) return 'day';
    if (RegExp(r'^\d{4}-\d{2}').hasMatch(t)) return 'month';
    if (RegExp(r'^\d{4}').hasMatch(t)) return 'year';
    return null;
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Badge text for a release date: `today`, `yesterday` or `N days ago`
  /// for the last month, `tomorrow` or `in N days` for the next, else `Mar 4`
  /// this calendar year and `Mar 4, 2027` any other. A month or year
  /// precision never claims a day it does not know (`Nov`, `Nov 2027`, `2027`).
  /// With no precision, January 1 is read as a year-only date. Days are
  /// counted from the UTC day, the one BookOrbit splits Recent and Upcoming on.
  static String? releaseLabel(DateTime? date, {String? precision}) {
    if (date == null) return null;
    if (precision == 'year' || (precision == null && date.month == 1 && date.day == 1)) return '${date.year}';
    final now = DateTime.now().toUtc();
    final month = _months[date.month - 1];
    if (precision == 'month') {
      return date.year == now.year ? month : '$month ${date.year}';
    }
    final today = DateTime.utc(now.year, now.month, now.day);
    final day = DateTime.utc(date.year, date.month, date.day);
    final ago = today.difference(day).inDays;
    if (ago == 0) return 'today';
    if (ago == 1) return 'yesterday';
    if (ago > 1 && ago <= 30) return '$ago days ago';
    if (ago == -1) return 'tomorrow';
    if (ago < -1 && ago >= -30) return 'in ${-ago} days';
    return date.year == now.year ? '$month ${date.day}' : '$month ${date.day}, ${date.year}';
  }

  /// The format whose date the card shows: the nearest upcoming one if any
  /// format is still to come, else the most recently released.
  String? get _cardFormat {
    final today = todayUtc();
    String? next, last;
    DateTime? nextAt, lastAt;
    for (final f in formats) {
      final d = releaseDateFor(f);
      if (d == null) continue;
      if (!releaseStarted(releaseDateTextFor(f), precisionFor(f), today: today)) {
        if (nextAt == null || d.isBefore(nextAt)) (next, nextAt) = (f, d);
      } else if (lastAt == null || d.isAfter(lastAt)) {
        (last, lastAt) = (f, d);
      }
    }
    return next ?? last;
  }

  DateTime? get cardDate {
    final f = _cardFormat;
    return f == null ? null : releaseDateFor(f);
  }

  /// [releaseLabel] for [cardDate].
  String? get cardBadge {
    final f = _cardFormat;
    return f == null ? null : releaseLabel(releaseDateFor(f), precision: precisionFor(f));
  }

  /// `Nov 14, 2026`, `Nov 2026` or `2026`, for "Released ..." lines.
  static String? longDate(String? text, {String? precision}) {
    final date = parseDate(text);
    if (date == null) return null;
    return switch (precision ?? precisionOf(text)) {
      'year' => '${date.year}',
      'month' => '${_months[date.month - 1]} ${date.year}',
      _ => '${_months[date.month - 1]} ${date.day}, ${date.year}',
    };
  }
}
