import 'position_sync_chain.dart';

// Fork-owned: which editions a book page lists, read from the same position
// sync snapshot the sync sheet draws. On BookOrbit 3.6 an ebook, its
// read-aloud and its audiobook are files of one book. Pure Dart,
// unit-tested. See FORK_NOTES.md.

/// Why an edition row has no file behind it.
enum WorkEditionGap { generate, building }

/// One row of the book page's Editions card: the book's files of that
/// edition, or a [gap] saying what would make them.
class WorkEdition {
  final SyncEdition kind;
  final SyncChainEdition? edition;
  final WorkEditionGap? gap;
  const WorkEdition(this.kind, {this.edition, this.gap});
}

/// Audiobook, read-aloud, ebook, in that order. A missing read-aloud is a
/// gap only where the book could have one made: it holds a plain EPUB and
/// audio, and the generator is open to this reader or already running.
/// Empty when the book holds fewer than two editions.
List<WorkEdition> workEditions(SyncChainSnapshot s) {
  WorkEdition? present(SyncEdition kind) {
    final e = s.edition(kind);
    return e == null ? null : WorkEdition(kind, edition: e);
  }

  WorkEdition? readAlong() {
    final row = present(SyncEdition.readAlong);
    if (row != null || s.ebook == null || s.audiobook == null) return row;
    final slot = s.readAloudSlot;
    final status = slot.job?.status;
    if (status == ReadAloudJobStatus.queued || status == ReadAloudJobStatus.processing) {
      return const WorkEdition(SyncEdition.readAlong, gap: WorkEditionGap.building);
    }
    return slot.entry is ReadAloudEntryAvailable ? const WorkEdition(SyncEdition.readAlong, gap: WorkEditionGap.generate) : null;
  }

  final rows = [present(SyncEdition.audiobook), readAlong(), present(SyncEdition.ebook)].nonNulls.toList();
  return rows.where((r) => r.edition != null).length < 2 ? const [] : rows;
}
