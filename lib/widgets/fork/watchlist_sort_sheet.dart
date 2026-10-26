// Fork-owned: the sort sheet for the Watchlist's Releases grid, with the
// status filter. The server sorts releases only by date, title or author, so
// the library sort sheet's other choices would all fall back to date. The
// sort is the shown view's own; the status filter is shared by both views.
// library_screen.dart opens this instead for the Watchlist. See FORK_NOTES.md.

import 'package:flutter/material.dart';

import '../../screens/library_screen.dart';
import '../../services/api_service.dart';
import '../library_sort_filter_sheet.dart';

enum WatchlistSort { date, title, author }

/// The Releases grid sort for this app session, one per view
/// ([WatchlistReleaseFilter.when]): switching views brings that view's sort
/// back. The library sort is one setting for every library, so the Watchlist
/// keeps its own and does not write over it.
class WatchlistSortChoice {
  static final _byView = {
    WatchlistWhen.upcoming: (sort: WatchlistSort.date, desc: false),
    WatchlistWhen.outNow: (sort: WatchlistSort.date, desc: true),
  };

  static WatchlistSort get sort => _byView[WatchlistReleaseFilter.when]!.sort;
  static set sort(WatchlistSort value) => _byView[WatchlistReleaseFilter.when] = (sort: value, desc: desc);

  static bool get desc => _byView[WatchlistReleaseFilter.when]!.desc;
  static set desc(bool value) => _byView[WatchlistReleaseFilter.when] = (sort: sort, desc: value);

  /// Names A to Z; dates soonest first in Upcoming, newest first in Recent.
  static bool defaultDesc(WatchlistSort sort) =>
      sort == WatchlistSort.date && WatchlistReleaseFilter.when == WatchlistWhen.outNow;

  /// The library sort that sends the matching `sort` key to the items route.
  static LibrarySort get librarySort => switch (sort) {
        WatchlistSort.date => LibrarySort.recentlyAdded,
        WatchlistSort.title => LibrarySort.alphabetical,
        WatchlistSort.author => LibrarySort.authorName,
      };

  static bool get asc => !desc;
}

/// Opens the sheet; [onChanged] runs after every change, with
/// [WatchlistSortChoice] already updated.
Future<void> showWatchlistSortSheet(BuildContext context, {required VoidCallback onChanged}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WatchlistSortSheet(onChanged: onChanged),
  );
}

class _WatchlistSortSheet extends StatefulWidget {
  final VoidCallback onChanged;

  const _WatchlistSortSheet({required this.onChanged});

  @override
  State<_WatchlistSortSheet> createState() => _WatchlistSortSheetState();
}

class _WatchlistSortSheetState extends State<_WatchlistSortSheet> {
  static const _options = [
    (WatchlistSort.date, 'Date', Icons.event_rounded),
    (WatchlistSort.title, 'Title', Icons.sort_by_alpha_rounded),
    (WatchlistSort.author, 'Author', Icons.person_rounded),
  ];

  void _pick(WatchlistSort sort) {
    if (sort != WatchlistSortChoice.sort) {
      WatchlistSortChoice.sort = sort;
      WatchlistSortChoice.desc = WatchlistSortChoice.defaultDesc(sort);
      widget.onChanged();
    }
    Navigator.pop(context);
  }

  void _toggleStatus(String status) {
    setState(() {
      final next = {...WatchlistReleaseFilter.status};
      if (!next.remove(status)) next.add(status);
      WatchlistReleaseFilter.status = next;
    });
    widget.onChanged();
  }

  void _setDesc(bool desc) {
    if (desc == WatchlistSortChoice.desc) return;
    setState(() => WatchlistSortChoice.desc = desc);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewPadding.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(WatchlistReleaseFilter.when == WatchlistWhen.outNow ? 'Sort recent' : 'Sort upcoming',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.primary)),
            ),
            const SizedBox(height: 12),
            for (final (sort, label, icon) in _options)
              SheetOption(
                icon: icon,
                label: label,
                selected: sort == WatchlistSortChoice.sort,
                selectedColor: cs.primary,
                onTap: () => _pick(sort),
              ),
            const Divider(height: 24),
            for (final desc in const [false, true])
              SheetOption(
                icon: desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                label: desc ? 'Descending' : 'Ascending',
                selected: desc == WatchlistSortChoice.desc,
                selectedColor: cs.primary,
                onTap: () => _setDesc(desc),
              ),
            const Divider(height: 24),
            Center(
              child: Text('Show', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.primary)),
            ),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
              for (final (status, label) in WatchlistReleaseFilter.options)
                FilterChip(
                  label: Text(label),
                  selected: WatchlistReleaseFilter.status.contains(status),
                  onSelected: (_) => _toggleStatus(status),
                ),
            ]),
            const SizedBox(height: 8),
            Text(
              WatchlistReleaseFilter.status.isEmpty
                  ? 'Showing everything BookOrbit watches in this window, owned books included.'
                  : 'Showing only the picked kinds.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
