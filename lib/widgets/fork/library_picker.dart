// Fork-owned: the library picker sheet's body as redesigned in October 2026:
// a left-aligned title, one rounded row per library with the server's own
// icon (library_icon.dart) and its book count under the name, the selected
// row filled in the accent with a check, and BookOrbit's tools (Book Dock,
// Watchlist) under a divider with their own lines (files to review; followed
// authors and upcoming releases, with the needs-you pill). The Book Dock's
// counts and the upcoming count are read when the sheet opens.
// library_picker_sheet.dart builds it through [forkLibraryPicker]. Plain
// English text. See FORK_NOTES.md.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/api_service.dart';
import 'library_icon.dart';
import 'library_picker_model.dart';
import 'watchlist_picker_badge.dart';

/// The sheet body for `showLibraryPickerSheet`: [libraries] are the rows in
/// order (the Dashboard entry first when Home shows it). Picking one closes
/// the sheet and switches to it the way the picker always has.
Widget forkLibraryPicker(
  BuildContext ctx,
  List<Map<String, dynamic>> libraries,
  LibraryProvider lib, {
  required bool forHome,
  required AppLocalizations l,
}) {
  final api = ctx.read<AuthProvider>().apiService;
  return ForkLibraryPicker(
    libraries: libraries,
    title: l.selectLibrary,
    fallbackName: l.libraryFallback,
    isSelected: (library) => library['dashboard'] == true
        ? lib.homeDashboard
        : library['id'] == lib.selectedLibraryId && !(forHome && lib.homeDashboard),
    onPick: (library, selected) {
      Navigator.pop(ctx);
      if (library['dashboard'] == true) {
        lib.setHomeDashboard(true);
      } else if (!selected) {
        if (forHome) lib.setHomeDashboard(false);
        final id = library['id'] as String;
        if (id != lib.selectedLibraryId) lib.selectLibrary(id);
      }
    },
    dockSummary: api is BookOrbitApiService ? api.forkDockSummary : null,
    watchlistUpcoming: api is BookOrbitApiService ? api.forkWatchlistUpcoming : null,
  );
}

/// The picker's rows, free of providers so a test can pump it on its own.
class ForkLibraryPicker extends StatefulWidget {
  const ForkLibraryPicker({
    super.key,
    required this.libraries,
    required this.title,
    required this.isSelected,
    required this.onPick,
    this.fallbackName = 'Library',
    this.dockSummary,
    this.watchlistUpcoming,
  });

  final List<Map<String, dynamic>> libraries;
  final String title;
  final String fallbackName;
  final bool Function(Map<String, dynamic> library) isSelected;

  /// Called with the tapped row and whether it was already the selected one.
  final void Function(Map<String, dynamic> library, bool selected) onPick;

  /// Reads BookOrbit's Book Dock summary for the line under its row; asked
  /// once when the sheet opens, and only when a Book Dock row is listed.
  final Future<Map<String, dynamic>?> Function()? dockSummary;

  /// Reads BookOrbit's count of upcoming Watchlist releases for the line
  /// under its row; asked once when the sheet opens, only with a Watchlist row.
  final Future<int?> Function()? watchlistUpcoming;

  @override
  State<ForkLibraryPicker> createState() => _ForkLibraryPickerState();
}

class _ForkLibraryPickerState extends State<ForkLibraryPicker> {
  Map<String, dynamic>? _dock;
  int? _upcoming;

  @override
  void initState() {
    super.initState();
    final dock = widget.dockSummary;
    if (dock != null && widget.libraries.any((l) => l['bookDock'] == true)) {
      dock().then((summary) {
        if (mounted && summary != null) setState(() => _dock = summary);
      });
    }
    final upcoming = widget.watchlistUpcoming;
    if (upcoming != null && widget.libraries.any((l) => l['watchlist'] == true)) {
      upcoming().then((n) {
        if (mounted && n != null) setState(() => _upcoming = n);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final groups = libraryPickerGroups(widget.libraries);
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(widget.title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad + 16),
              children: [
                for (final library in groups.libraries) _row(context, library),
                if (groups.tools.isNotEmpty) ...[
                  Padding(
                    key: const ValueKey('fork-picker-divider'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Divider(height: 1, thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  for (final library in groups.tools) _row(context, library),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> library) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = library['name'] as String? ?? widget.fallbackName;
    final selected = widget.isSelected(library);
    final subtitle = libraryPickerSubtitle(library, dockSummary: _dock, watchlistUpcoming: _upcoming);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onPick(library, selected),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(child: ForkLibraryIcon(library: library, size: 24, color: cs.primary)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle.merge(
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                        child: watchlistPickerTitle(library, name) ??
                            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.check_rounded, color: cs.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
