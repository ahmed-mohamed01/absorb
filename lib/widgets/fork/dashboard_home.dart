import 'package:flutter/material.dart';

import '../../services/api_service.dart';

export '../../services/fork/cover_frame.dart';

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

/// A Continue card's progress on the Dashboard: a bar along the bottom edge
/// of the cover in [color], as on BookOrbit's covers and the other shelves'
/// cards, in place of the bar under the title. Sits in the cover's `Stack`.
Widget forkCoverProgressBar(double value, Color color) => Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 4,
        backgroundColor: Colors.black38,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );

/// A Continue card's time left (or reading percent) on the Dashboard, a
/// small label in the cover's top-right corner, in place of the line under
/// the author. Sits in the cover's `Stack`.
Widget forkCoverProgressLabel(String text) => Positioned(
      top: 6,
      right: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            maxLines: 1,
            style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
      ),
    );
