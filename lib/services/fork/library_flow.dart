// Fork-owned: the untethered Library and Absorbing flow for BookOrbit.
// The hooks are listed in FORK_NOTES.md.

import '../api_service.dart';

class ForkLibraryFlow {
  /// True while the signed-in server is BookOrbit; the Absorbing page then
  /// shows every library and a library switch never stops playback, as if
  /// the "Unified Absorbing page" setting were on.
  static bool unifiedAbsorbing = false;

  static bool isVirtualLibrary(String? id) =>
      id == ApiService.bookDockLibraryId || id == ApiService.watchlistLibraryId;

  /// The Book Dock and the Watchlist are visited, not kept, so the Library
  /// tab reopens on the last real library.
  static String? restoreLibraryId({required String? saved, required String? lastBook}) =>
      isVirtualLibrary(saved) ? lastBook : saved;
}
