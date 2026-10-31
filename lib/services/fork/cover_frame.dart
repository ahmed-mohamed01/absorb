// Fork-owned: reading the per-book cover frame that `_forkWithFrame`
// (bookorbit_dashboard.dart) stamps on BookOrbit items. Pure Dart; see
// FORK_NOTES.md.

/// The shape of a portrait (ebook) cover, width over height.
const double forkPortraitFrame = 2 / 3;

/// The cover frame BookOrbit gave [item] (`media.coverAspectRatio`): 1.0 for
/// a square audiobook cover, [forkPortraitFrame] for an ebook. Null when the
/// item has none, as off BookOrbit.
double? forkBookFrame(Object? item) {
  final media = item is Map ? item['media'] : null;
  final frame = media is Map ? media['coverAspectRatio'] : null;
  return frame is num ? frame.toDouble() : null;
}

/// Whether BookOrbit holds both an audiobook and an ebook cover for [item],
/// read off its `coverVersion` (`face:faceStamp:otherStamp`, a missing slot
/// stamped `-`). A legacy or absent version says nothing, so it's false.
bool forkHasBothCovers(Object? item) {
  final bookOrbit = item is Map ? item['bookOrbit'] : null;
  final version = bookOrbit is Map ? bookOrbit['coverVersion'] : null;
  if (version is! String) return false;
  if (!version.startsWith('audio:') && !version.startsWith('ebook:')) return false;
  return !version.endsWith(':-') && version.substring(6).split(':').first != '-';
}
