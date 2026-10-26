// Fork-owned: what the Watchlist's Authors grid adds to Absorb's author
// tiles (the owned/known count, the fetch spinner and the next-release pill)
// and the "Add an author" tile that opens the add-author sheet. Hooked from
// library_grid_tiles.dart and library_authors_tab.dart. See FORK_NOTES.md.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/api_service.dart';
import '../../services/fork/watchlist_info.dart';
import '../overlay_toast.dart';
import 'watchlist_add_author_sheet.dart';
import 'watchlist_cover_badges.dart';

Map? _watchOf(Map<String, dynamic> author) {
  final w = author['watchlist'];
  return w is Map ? w : null;
}

/// `owned/known` for a followed author's count badge; null for every
/// library author.
String? watchlistAuthorBadge(Map<String, dynamic> author) {
  final w = _watchOf(author);
  if (w == null) return null;
  return '${w['owned'] ?? 0}/${w['total'] ?? 0}';
}

/// The author list sends `nextReleaseAt` without its precision, and a
/// year-only date is stored as January 1, so a full date is left
/// unqualified for [WatchlistInfo.releaseLabel] to judge.
String? _listPrecision(String? text) {
  final p = WatchlistInfo.precisionOf(text);
  return p == 'day' ? null : p;
}

bool _fetching(Map w) => w['fetchState'] == 'queued' || w['fetchState'] == 'fetching';

/// Drawn in the portrait's Stack: a spinner while BookOrbit fetches the
/// author's books, and a pill at the foot of the portrait with the next
/// release. The author list carries no per-author attention or missing
/// counts, so those pills are left out rather than costing a call per tile.
class WatchlistAuthorOverlay extends StatelessWidget {
  final Map<String, dynamic> author;

  const WatchlistAuthorOverlay({super.key, required this.author});

  @override
  Widget build(BuildContext context) {
    final w = _watchOf(author);
    if (w == null) return const SizedBox.shrink();
    final busy = _fetching(w);
    final nextText = w['nextReleaseAt'] as String?;
    final next = busy
        ? null
        : WatchlistInfo.releaseLabel(WatchlistInfo.parseDate(nextText), precision: _listPrecision(nextText));
    final label = busy ? 'Finding books…' : next;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(clipBehavior: Clip.none, children: [
          if (busy)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.5)),
                child: const Center(
                  child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                ),
              ),
            ),
          if (label != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: -2,
              child: Center(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: busy ? Colors.black.withValues(alpha: 0.7) : watchlistUpcoming,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
                    ),
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// How many cells the "Add an author" tile takes at the head of the grid:
/// one on the Watchlist of a BookOrbit server, else none.
int watchlistAddAuthorSlots(BuildContext context) {
  if (!WatchlistInfo.isLibrary(context.read<LibraryProvider>().selectedLibraryId)) return 0;
  final api = context.read<AuthProvider>().apiService;
  return api is BookOrbitApiService ? 1 : 0;
}

/// The first tile of the Watchlist Authors grid, shaped like an author tile.
class WatchlistAddAuthorTile extends StatelessWidget {
  const WatchlistAddAuthorTile({super.key});

  // The tile is always there, because the grid can be drawn from a cached
  // author list before any permission check has run; access is asked on tap.
  Future<void> _open(BuildContext context) async {
    final api = context.read<AuthProvider>().apiService;
    if (api is! BookOrbitApiService) return;
    final access = await api.bookRequestAccess();
    if (!context.mounted) return;
    if (!access.canRequest) {
      showOverlayToast(context, 'You cannot add authors on this server', icon: Icons.block_rounded);
      return;
    }
    showWatchlistAddAuthorSheet(context, api);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: Column(children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.08),
              border: Border.all(color: cs.primary.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Icon(Icons.person_add_alt_1_rounded, size: 32, color: cs.primary),
          ),
        ),
        const SizedBox(height: 5),
        Text('Add an author',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: cs.primary)),
      ]),
    );
  }
}
