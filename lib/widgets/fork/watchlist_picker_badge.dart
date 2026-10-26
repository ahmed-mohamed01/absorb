// Fork-owned: the "N needs you" pill on the Watchlist row of the library
// picker. The count rides on the library map (`watchlistNeedsYou`), fetched
// with the Watchlist summary. Hooked from library_picker_sheet.dart. See
// FORK_NOTES.md.
import 'package:flutter/material.dart';

import 'watchlist_cover_badges.dart';

/// The row title with the pill, or null when there is nothing to flag.
Widget? watchlistPickerTitle(Map<String, dynamic> library, String name) {
  final count = (library['watchlistNeedsYou'] as num?)?.toInt() ?? 0;
  if (library['watchlist'] != true || count <= 0) return null;
  return Row(children: [
    Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
    const SizedBox(width: 8),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: watchlistMissing.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: watchlistMissing.withValues(alpha: 0.5)),
      ),
      child: Text('$count needs you',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: watchlistMissing)),
    ),
  ]);
}
