import 'position_sync_chain.dart';

// Fork-owned: which editions of one work a book page lists, read from the
// same position sync snapshot the sync sheet draws. Pure Dart, unit-tested.
// See FORK_NOTES.md.

/// Why an edition row has no book behind it.
enum WorkEditionGap { link, generate, building }

/// One row of the book page's Editions card: a book of that edition, or a
/// [gap] saying what would make one.
class WorkEdition {
  final SyncEdition kind;
  final SyncChainBook? book;
  final bool isThisBook;
  final WorkEditionGap? gap;
  const WorkEdition(this.kind, {this.book, this.isThisBook = false, this.gap});
}

/// Audiobook, read-along, ebook, in that order. An edition is listed whether
/// it is linked or only the server's proposed match. Empty when there is no
/// other edition. Until [readAlongKnown], a missing read-along is left out
/// rather than offered for generating.
List<WorkEdition> workEditions(SyncChainSnapshot s, {bool readAlongKnown = true}) {
  // A gap is only offered to a reader who can fill it from the sync sheet.
  WorkEdition? pairSide(SyncEdition kind) {
    final side = s.side(kind);
    final book = side.book;
    if (book != null) return WorkEdition(kind, book: book, isThisBook: side.isThisBook);
    return s.can.editLink ? WorkEdition(kind, gap: WorkEditionGap.link) : null;
  }

  WorkEdition? readAlong() {
    final ra = s.readAlong;
    // A finished build whose member the link hasn't picked up yet is there all the same.
    final book = ra.thisBook ?? ra.member ?? (ra.status == ReadAlongStatus.ready ? ra.outputBook : null);
    if (book != null) return WorkEdition(SyncEdition.readAlong, book: book, isThisBook: s.thisBook == SyncEdition.readAlong);
    if (ra.status == ReadAlongStatus.queued || ra.status == ReadAlongStatus.building) {
      return const WorkEdition(SyncEdition.readAlong, gap: WorkEditionGap.building);
    }
    return readAlongKnown && s.can.generate ? const WorkEdition(SyncEdition.readAlong, gap: WorkEditionGap.generate) : null;
  }

  final rows = [pairSide(SyncEdition.audiobook), readAlong(), pairSide(SyncEdition.ebook)].nonNulls.toList();
  return rows.where((r) => r.book != null).length < 2 ? const [] : rows;
}
