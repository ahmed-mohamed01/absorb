part of '../api_service.dart';

// Fork-owned: Dashboard widget loading and reading-goal updates.
// The service hooks are documented in FORK_NOTES.md.

/// Cache key of the widget payloads (one minute, under the `personalized:`
/// prefix so a write drops them with the shelves).
const _forkWidgetsKey = 'personalized:widgets';

/// Loads Dashboard widgets and updates their reading goal.
extension ForkDashboardWidgetsApi on BookOrbitApiService {
  /// Returns the configured widgets, or null when loading fails.
  Future<ForkDashboardWidgets?> forkDashboardWidgets({
    bool fresh = false,
  }) async {
    if (fresh) BookOrbitApiService._recent.remove(_key(_forkWidgetsKey));
    try {
      return await _cached(
        _forkWidgetsKey,
        const Duration(seconds: 60),
        () async {
          final settings = await _forkDashboardSettings();
          final config = _forkWidgetConfig(settings);
          final wanted = forkEnabledWidgetTypes(config);
          if (wanted.isEmpty) return const ForkDashboardWidgets([]);
          final response = await _boPost('/dashboard/widgets/batch', {
            'widgets': wanted,
          });
          final parsed = forkParseWidgetBatch(
            wanted,
            response as Map<String, dynamic>,
          );
          return ForkDashboardWidgets([
            for (final widget in parsed.widgets)
              if (widget.type == forkWidgetReadingGoal &&
                  widget.data is ForkReadingGoal)
                ForkDashboardWidget(
                  widget.type,
                  ForkReadingGoal(
                    goalBooks:
                        (widget.data as ForkReadingGoal).goalBooks ??
                        forkReadingGoalOf(config),
                    completedBooks:
                        (widget.data as ForkReadingGoal).completedBooks,
                    year: (widget.data as ForkReadingGoal).year,
                  ),
                )
              else
                widget,
          ]);
        },
      );
    } catch (_) {
      return null;
    }
  }

  /// Saves the goal while preserving freshly read Dashboard settings.
  Future<bool> forkSetReadingGoal(int goalBooks) async {
    try {
      final me = await _boGet('/auth/me') as Map<String, dynamic>;
      final settings = me['settings'];
      final current = _forkWidgetConfig(settings is Map ? Map<String, dynamic>.from(settings) : const {});
      await _boPatch('/users/me/settings', {
        'settings': {
          'dashboardConfig': {...?current, 'readingGoal': goalBooks},
        },
      });
      BookOrbitApiService._recent.remove(_key(_forkDashboardConfigKey));
      BookOrbitApiService._recent.remove(_key(_forkWidgetsKey));
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// The user's `dashboardConfig` from their settings, or null.
Map<String, dynamic>? _forkWidgetConfig(Map<String, dynamic> settings) {
  final config = settings['dashboardConfig'];
  return config is Map ? Map<String, dynamic>.from(config) : null;
}
