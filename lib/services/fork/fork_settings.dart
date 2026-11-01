// Fork-owned: settings only this fork has, changed on the Fork settings page
// (widgets/fork/fork_settings_screen.dart). Cached for grid builders and
// loaded beside PlayerSettings' cached values. See FORK_NOTES.md.
import '../player_settings.dart';
import '../scoped_prefs.dart';

class ForkSettings {
  ForkSettings._();

  static const _ownCoverShapesKey = 'forkOwnCoverShapes';
  static const _singleBookSeriesKey = 'forkSingleBookSeriesAsBooks';

  /// Whether the Library grid and the author and narrator sheets draw each
  /// BookOrbit book in its own cover shape (portrait ebooks, square
  /// audiobooks) rather than all in the library's cover shape. The series
  /// and Dashboard shelf sheets always do.
  static bool ownCoverShapes = true;

  /// Whether, with Collapse series on, a series holding one book shows as
  /// that book in the Library grid and the author sheet's series grouping
  /// (single_book_series.dart) rather than as a series tile.
  static bool singleBookSeriesAsBooks = true;

  /// Reads the cached values for the signed-in server.
  static Future<void> load() async {
    ownCoverShapes = await ScopedPrefs.getBool(_ownCoverShapesKey) ?? true;
    singleBookSeriesAsBooks = await ScopedPrefs.getBool(_singleBookSeriesKey) ?? true;
  }

  static Future<void> setOwnCoverShapes(bool value) async {
    ownCoverShapes = value;
    await ScopedPrefs.setBool(_ownCoverShapesKey, value);
    PlayerSettings.notifySettingsChanged();
  }

  static Future<void> setSingleBookSeriesAsBooks(bool value) async {
    singleBookSeriesAsBooks = value;
    await ScopedPrefs.setBool(_singleBookSeriesKey, value);
    PlayerSettings.notifySettingsChanged();
  }
}
