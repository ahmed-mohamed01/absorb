part of '../api_service.dart';

// Fork-owned: what the library picker reads from BookOrbit when it opens: the
// Book Dock summary and the Watchlist's upcoming release count, for the lines
// under those two rows. See FORK_NOTES.md.

extension ForkLibraryPickerCounts on BookOrbitApiService {
  /// BookOrbit's `/book-dock/summary` (`pending`, `working`, `ready`,
  /// `error`, `needsReview`, `readyToFile`, `total`, `paused`), or null when
  /// it cannot be read (offline, no access). Read each time the picker opens,
  /// so the count is current while files are being processed.
  Future<Map<String, dynamic>?> forkDockSummary() async {
    try {
      final summary = await _boGet('/book-dock/summary', null, const Duration(seconds: 6));
      return summary is Map<String, dynamic> ? summary : null;
    } catch (e) {
      debugPrint('[LibraryPicker] dock summary: $e');
      return null;
    }
  }

  /// The server's count of upcoming Watchlist releases (formats, the way the
  /// needs-you pill counts), or null when it cannot be read. Read each time
  /// the picker opens, so the line is current.
  Future<int?> forkWatchlistUpcoming() => _watchReleaseTotal('upcoming', 'upcoming');
}
