// Fork-owned: the data behind the Dashboard Home's widget strip (Currently
// Reading, Reading Streak, Reading Rhythm, Reading Goal), parsed from
// BookOrbit's dashboard config and its widget batch endpoint. Pure Dart so the
// parsing is testable without Flutter; see FORK_NOTES.md.

/// The server type for the Currently Reading widget.
const forkWidgetCurrentlyReading = 'currently-reading';

/// The server type for the reading streak widget.
const forkWidgetReadingStreak = 'reading-streak';

/// The server type for the reading rhythm widget.
const forkWidgetReadingRhythm = 'reading-rhythm';

/// The server type for the yearly goal widget.
const forkWidgetReadingGoal = 'reading-goal';

/// Supported widget types in their default display order.
const forkSupportedWidgetTypes = [
  forkWidgetCurrentlyReading,
  forkWidgetReadingStreak,
  forkWidgetReadingRhythm,
  forkWidgetReadingGoal,
];

/// One book on the Currently Reading card.
class ForkWidgetBook {
  /// The server identifier of the book.
  final String bookId;

  /// The title shown for the book.
  final String title;

  /// The author names shown for the book.
  final List<String> authors;

  /// A fraction from 0 to 1.
  final double progress;

  /// Whether the server has a cover for this book.
  final bool hasCover;

  /// Creates this value from the supplied fields.
  const ForkWidgetBook({
    required this.bookId,
    required this.title,
    this.authors = const [],
    this.progress = 0,
    this.hasCover = false,
  });
}

/// The books currently in progress.
class ForkCurrentlyReading {
  /// The books returned for this widget.
  final List<ForkWidgetBook> books;

  /// Creates this value from the supplied fields.
  const ForkCurrentlyReading(this.books);
}

/// Current and longest streaks with the last seven active days.
class ForkReadingStreak {
  /// The current number of consecutive reading days.
  final int currentStreak;

  /// The longest recorded run of reading days.
  final int longestStreak;

  /// Whether reading was recorded on each of the last seven days.
  final List<bool> lastSevenDays;

  /// Creates this value from the supplied fields.
  const ForkReadingStreak({
    required this.currentStreak,
    required this.longestStreak,
    required this.lastSevenDays,
  });
}

/// Reading time for one calendar day.
class ForkRhythmDay {
  /// The calendar date of this reading time.
  final DateTime date;

  /// The reading time recorded in seconds.
  final int readingSeconds;

  /// Creates this value from the supplied fields.
  const ForkRhythmDay(this.date, this.readingSeconds);
}

/// Daily reading time and consistency over the reported period.
class ForkReadingRhythm {
  /// The daily reading records in the reported period.
  final List<ForkRhythmDay> days;

  /// The percentage of days with reading activity.
  final int consistencyPercent;

  /// The average daily reading time in seconds.
  final int avgSecondsPerDay;

  /// The number of days with reading activity.
  final int activeDays;

  /// The number of days in the reported period.
  final int totalDays;

  /// Creates this value from the supplied fields.
  const ForkReadingRhythm({
    required this.days,
    required this.consistencyPercent,
    required this.avgSecondsPerDay,
    required this.activeDays,
    required this.totalDays,
  });
}

/// The yearly book target and completed count.
class ForkReadingGoal {
  /// The yearly book target, when set.
  final int? goalBooks;

  /// The books completed in the reported year.
  final int completedBooks;

  /// The year this goal describes.
  final int year;

  /// Creates this value from the supplied fields.
  const ForkReadingGoal({
    required this.goalBooks,
    required this.completedBooks,
    required this.year,
  });
}

/// One widget on the strip. [data] is a [ForkCurrentlyReading],
/// [ForkReadingStreak], [ForkReadingRhythm] or [ForkReadingGoal], or null when
/// the server failed that widget.
class ForkDashboardWidget {
  /// The server type used for this entry.
  final String type;

  /// The parsed widget payload, or null when unavailable.
  final Object? data;

  /// Creates this value from the supplied fields.
  const ForkDashboardWidget(this.type, this.data);
}

/// The configured widgets in display order.
class ForkDashboardWidgets {
  /// The widgets in configured display order.
  final List<ForkDashboardWidget> widgets;

  /// Creates this value from the supplied fields.
  const ForkDashboardWidgets(this.widgets);
}

/// The enabled, supported widget types in the user's order. Without a widget
/// list in [dashboardConfig], all four in their default order.
List<String> forkEnabledWidgetTypes(Map<String, dynamic>? dashboardConfig) {
  final raw = dashboardConfig?['widgets'];
  if (raw is! List) return List.of(forkSupportedWidgetTypes);
  final rows = <({String type, num order, int index})>[];
  var index = 0;
  for (final w in raw) {
    index++;
    if (w is! Map) continue;
    final type = w['type'];
    if (type is! String || !forkSupportedWidgetTypes.contains(type)) continue;
    if (w['enabled'] == false) continue;
    final order = w['order'];
    rows.add((type: type, order: order is num ? order : 1 << 30, index: index));
  }
  rows.sort((a, b) {
    final c = a.order.compareTo(b.order);
    return c != 0 ? c : a.index.compareTo(b.index);
  });
  final out = <String>[];
  for (final r in rows) {
    if (!out.contains(r.type)) out.add(r.type);
  }
  return out;
}

/// The user's yearly book goal from [dashboardConfig], if set.
int? forkReadingGoalOf(Map<String, dynamic>? dashboardConfig) {
  final g = dashboardConfig?['readingGoal'];
  return g is num ? g.toInt() : null;
}

/// One widget per [wanted] type, in order, from the batch [response]. A
/// missing, failed or malformed widget gets null data.
ForkDashboardWidgets forkParseWidgetBatch(
  List<String> wanted,
  Map<String, dynamic> response,
) {
  final byType = <String, Map>{};
  final items = response['items'];
  if (items is List) {
    for (final item in items) {
      if (item is Map && item['type'] is String) {
        byType.putIfAbsent(item['type'] as String, () => item);
      }
    }
  }
  return ForkDashboardWidgets([
    for (final type in wanted)
      ForkDashboardWidget(type, _parseItem(type, byType[type])),
  ]);
}

Object? _parseItem(String type, Map? item) {
  if (item == null || item['failed'] == true) return null;
  final data = item['data'];
  if (data is! Map) return null;
  try {
    switch (type) {
      case forkWidgetCurrentlyReading:
        return _parseCurrentlyReading(data);
      case forkWidgetReadingStreak:
        return _parseStreak(data);
      case forkWidgetReadingRhythm:
        return _parseRhythm(data);
      case forkWidgetReadingGoal:
        return _parseGoal(data);
    }
  } catch (_) {
    return null;
  }
  return null;
}

int _int(Object? v) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);

ForkCurrentlyReading? _parseCurrentlyReading(Map data) {
  final books = data['books'];
  if (books is! List) return null;
  final out = <ForkWidgetBook>[];
  for (final b in books) {
    if (b is! Map) continue;
    final id = b['bookId'];
    if (id == null) continue;
    final authors = b['authors'];
    final progress = b['progress'] is num
        ? (b['progress'] as num).toDouble() / 100
        : 0.0;
    out.add(
      ForkWidgetBook(
        bookId: id.toString(),
        title: (b['title'] ?? '').toString(),
        authors: authors is List
            ? [
                for (final a in authors)
                  if (a != null) a.toString(),
              ]
            : const [],
        progress: progress.clamp(0.0, 1.0),
        hasCover: b['hasCover'] == true,
      ),
    );
  }
  return ForkCurrentlyReading(out);
}

ForkReadingStreak _parseStreak(Map data) {
  final days = data['lastSevenDays'];
  return ForkReadingStreak(
    currentStreak: _int(data['currentStreak']),
    longestStreak: _int(data['longestStreak']),
    lastSevenDays: days is List ? [for (final d in days) d == true] : const [],
  );
}

ForkReadingRhythm? _parseRhythm(Map data) {
  final days = data['days'];
  if (days is! List) return null;
  final out = <ForkRhythmDay>[];
  for (final d in days) {
    if (d is! Map) continue;
    final date = d['date'] is String
        ? DateTime.tryParse(d['date'] as String)
        : null;
    if (date == null) continue;
    out.add(ForkRhythmDay(date, _int(d['readingSeconds'])));
  }
  return ForkReadingRhythm(
    days: out,
    consistencyPercent: _int(data['consistencyPercent']),
    avgSecondsPerDay: _int(data['avgSecondsPerDay']),
    activeDays: _int(data['activeDays']),
    totalDays: _int(data['totalDays']),
  );
}

ForkReadingGoal _parseGoal(Map data) {
  final g = data['goalBooks'];
  return ForkReadingGoal(
    goalBooks: g is num ? g.toInt() : null,
    completedBooks: _int(data['completedBooks']),
    year: data['year'] is num
        ? (data['year'] as num).toInt()
        : DateTime.now().year,
  );
}

/// The playing book's live fraction of [total] seconds, or null while the
/// player has no duration yet or still sits at zero before its seek lands,
/// so the card keeps the server's progress until then.
double? forkLiveFraction({required double seconds, required double total}) =>
    total > 0 && seconds > 0 ? (seconds / total).clamp(0.0, 1.0).toDouble() : null;
