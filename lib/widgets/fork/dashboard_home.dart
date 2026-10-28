import 'package:flutter/material.dart';

import '../../services/api_service.dart';

// Fork-owned: the chrome of the Dashboard Home, which is the dimmed footer
// under the last shelf and the helpers that give Home's shelves their titles
// and icons. Hooked in from home_screen.dart; see FORK_NOTES.md. Its text is
// plain English until upstream takes it.

/// The icon for a Home shelf id the upstream map has no entry for, or null.
/// Want to Read and BookOrbit's smart-scope shelves get their own icons.
IconData? forkSectionIcon(String id) {
  if (id == 'want-to-read') return Icons.bookmark_add_outlined;
  if (id.startsWith('smart-scope:')) return Icons.filter_alt_outlined;
  return null;
}

/// A shelf's title on Home. When the shelves come from a synced BookOrbit
/// Dashboard config ([fromSyncedConfig] true) it is the [label] the user gave
/// the shelf there, if there is one. Otherwise it is [fallback], the title the
/// app would show anyway, so fixed shelves keep their localised names.
String forkSectionLabel(bool fromSyncedConfig, String? label, String fallback) =>
    fromSyncedConfig && label != null && label.isNotEmpty ? label : fallback;

/// Whether [api] is BookOrbit with the user's shelf config synced to the
/// server, for [ForkDashboardFooter.configured]. It is null off BookOrbit and
/// until a config read has succeeded, so the footer does not guess.
bool? forkDashboardConfigured(ApiService? api) =>
    api is BookOrbitApiService ? api.forkDashboardConfigured : null;

/// The dimmed line under the Dashboard Home's last shelf. It says where the
/// shelves and widgets are set, or asks the user to turn on syncing there
/// when the shelf config is not synced.
class ForkDashboardFooter extends StatelessWidget {
  /// True when the BookOrbit shelf config is synced to the server, false when
  /// it is not, and null when that is not known yet (nothing is shown).
  final bool? configured;

  /// Creates the footer for the given [configured] state.
  const ForkDashboardFooter({super.key, required this.configured});

  @override
  Widget build(BuildContext context) {
    final known = configured;
    if (known == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Text(
        known
            ? 'Shelves and widgets are set in BookOrbit › Dashboard'
            : 'Turn on Sync across sessions in BookOrbit › Dashboard to show your shelves here',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// How a shelf heading reads on the Dashboard: the bigger title and
/// full-colour icon of its design, over the small dim heading a library's
/// Home keeps. Null off the Dashboard, so the call sites keep upstream's
/// styles as their fallback.
({TextStyle? style, double iconSize, Color iconColor})? forkShelfHeading(BuildContext context, {required bool dashboard}) {
  if (!dashboard) return null;
  final theme = Theme.of(context);
  return (
    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
    iconSize: 22.0,
    iconColor: theme.colorScheme.primary,
  );
}
