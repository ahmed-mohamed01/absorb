// Fork-owned: whether the Stats home-screen widget is placed, so its refresh
// (a listening-stats read and a full progress read) is skipped when nobody
// sees it. home_widget_service.dart's `refreshStats` calls it. See
// FORK_NOTES.md.
import 'package:home_widget/home_widget.dart';

/// Whether a widget of [androidName] (the class's short name) or [iOSKind]
/// is on the home screen. True when it can't tell.
Future<bool> forkWidgetPlaced({required String androidName, required String iOSKind}) async {
  try {
    final placed = await HomeWidget.getInstalledWidgets();
    return placed.any((w) => (w.androidClassName ?? '').endsWith('.$androidName') || w.iOSKind == iOSKind);
  } catch (_) {
    return true;
  }
}
