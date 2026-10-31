// Fork-owned: settings only this fork has, changed on the Fork settings page
// (widgets/fork/fork_settings_screen.dart). Cached for grid builders and
// loaded beside PlayerSettings' cached values. See FORK_NOTES.md.
import '../player_settings.dart';
import '../scoped_prefs.dart';

class ForkSettings {
  ForkSettings._();

  static const _ownCoverShapesKey = 'forkOwnCoverShapes';

  /// Whether the Library grid and the author and narrator sheets draw each
  /// BookOrbit book in its own cover shape (portrait ebooks, square
  /// audiobooks) rather than all in the library's cover shape. The series
  /// and Dashboard shelf sheets always do.
  static bool ownCoverShapes = true;

  /// Reads the cached values for the signed-in server.
  static Future<void> load() async {
    ownCoverShapes = await ScopedPrefs.getBool(_ownCoverShapesKey) ?? true;
  }

  static Future<void> setOwnCoverShapes(bool value) async {
    ownCoverShapes = value;
    await ScopedPrefs.setBool(_ownCoverShapesKey, value);
    PlayerSettings.notifySettingsChanged();
  }
}
