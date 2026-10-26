// Fork-owned: the BookOrbit Position sync state model, a port of BookOrbit's
// client/src/features/book/lib/sync-chain.ts trimmed to what the sheet shows.
// Pure Dart with no imports, so every state can be pinned by a unit test.
// See FORK_NOTES.md.

// ─── Server enums ───────────────────────────────────────────
// Shared with the wire models in bookorbit_position_sync.dart, which parse
// them from the server's strings.

enum AlignmentStatus { none, pending, building, ready, failed, unalignable }

enum AlignmentBlock { disabled, unavailable, busy }

enum ReadAlongStatus { none, queued, building, ready, failed }

enum ReadAlongPhase { prepare, register, process, wait, collect, link }

enum ReadAlongBlock {
  notConfigured,
  unreachable,
  busy,
  noPair,
  noEpub,
  sourceEpubUnreadable,
  noAudio,
  noTargetLibrary,
  targetNotAllowed,
  formatNotAllowed,
  previousOutputNotDeletable,
}

enum AbsDirection { twoWay, fromAbs, toAbs }

enum AbsPausedReason { excluded, needsReview, positionSyncOff }

enum AbsLiveStatus { synced, sending, receiving, unreachable, diverged }

enum AbsDivergedReason { pushOff, pullRefused, stale }

// ─── Copy ───────────────────────────────────────────────────
// BookOrbit's own English strings (en.json), plain constants until upstream
// takes translations. The few marked local have no BookOrbit counterpart.

abstract final class PositionSyncCopy {
  static const title = 'Position sync';
  static const tooltipNeedsAudio = 'Link an audiobook to enable position sync.';
  static const tooltipNeedsText = 'Link an ebook to enable position sync.';
  static const tooltipLinked = 'Manage the linked edition.';
  static const tooltipAligning = 'Linked - building position sync...';
  static const tooltipAligned = 'Linked - position sync ready.';
  static const tooltipAlignStale = 'Linked - position sync out of date. Rebuild it from this panel.';
  static const tooltipAlignFailed = 'Linked - position sync failed. Rebuild it from this panel.';
  static const tooltipReadAlongBuilding = 'Linked - building the read-along...';
  static const tooltipReadAlongQueued = 'Linked - read-along queued.';
  static const tooltipReadAlongFailed = 'Linked - read-along build failed.';

  static const headerNeedsAttention = 'Needs attention';
  static const headerCheckSync = 'Check sync';
  static const headerLinking = 'Linking';
  static String headerInSync(int n, int m) => '$n of $m in sync';
  static const headerNotLinked = 'Not linked';
  static const introLinked = 'Every linked edition keeps the same position.';
  static const introUnlinked = 'Link editions to keep them at the same position.';

  static const shortEbook = 'Ebook';
  static const shortReadAlong = 'Read-along';
  static const shortAudiobook = 'Audiobook';
  static const shortAbs = 'ABS';
  static const kindAbs = 'Audiobookshelf';
  static const tagThisBook = 'This book';
  static const tagExternal = 'External';
  static String progressRead(int p) => '$p% read';
  static String progressListened(int p) => '$p% listened';

  static const pillAvailable = 'Not linked';
  static const pillLinked = 'Linked';
  static const pillLinkedViaWhisper = 'Linked · via Whisper';
  static const pillLinking = 'Linking';
  static const pillRebuilding = 'Rebuilding';
  static const pillAlignmentFailed = 'Alignment failed';
  static const pillOutOfDate = 'Out of date';
  static const pillNotAligned = 'Not aligned';
  static const pillCantAlign = "Can't align";
  static const pillCantReach = "Can't reach server";
  static const pillOneWay = 'Linked · one way';
  static const pillDiverged = 'Out of sync';
  static const pillNotSyncing = 'Not syncing';

  static const qualifierViaWhisper = 'via Whisper';
  static const qualifierDirect = 'direct';
  static const qualifierOneWay = 'one way';
  static const qualifierTwoWay = 'two way';
  static const offNotLinked = 'not linked';
  static const offSyncPaused = 'sync paused';
  static const offNeedsReview = 'needs review';
  static const offNotMatched = 'not matched';
  static const offPickAudiobookFirst = 'pick an audiobook first';
  static const offSyncOffInSettings = 'sync off in Settings';
  static const offNotGenerated = 'not generated';

  static String chipMatch(int score) => '$score% match';
  static const chipSelected = 'Selected';
  static String chipGeneratedFrom(String title) => 'Generated from $title';
  static const chipGenerated = 'Generated';
  static const chipPaused = 'Paused';
  static const chipNeedsReview = 'Needs review';

  static const ghostNoMatchEbook = 'No matching ebook found yet';
  static const ghostNoMatchAudiobook = 'No matching audiobook found yet';
  static const ghostNoMatchAbs = 'No match in your libraries';
  static const ghostAbsPositionSyncOff = 'Position sync is off in Settings';
  static const ghostAbsNeedsAudio = 'Pick an audiobook first';
  static const ghostOutOfReach = "Added to a library you can't open.";

  static const disabledNothingToLink = 'There is nothing to link yet.';
  static const disabledNoPermission = "You don't have permission to change links.";

  static const changeBlocked = 'Rebuild or detach the read-along first';
  static const changeBuilding = 'Wait for the read-along build, or cancel it';
  static const changeFailed = 'Retry the read-along build first';

  static const explainWhisper =
      "Two-way. Whisper maps the audiobook's audio onto the ebook's text, so your position carries in both directions.";
  static const explainReadAlongAudio =
      "Two-way. The read-along narrates the audiobook's own audio, so positions map directly between them.";
  static const explainAbsTwoWay =
      'Two-way. Listening progress is exchanged with your Audiobookshelf server through its API.';
  static const explainAbsFromAbs =
      'One-way. Listening progress comes from your Audiobookshelf server through its API and nothing is sent back.';
  static const explainAbsToAbs =
      'One-way. Listening progress is sent to your Audiobookshelf server through its API and nothing is read back.';
  static const noteLinking = 'Both editions keep their own progress until it finishes.';
  static const noteAlignmentFailed = "Whisper stopped while aligning, so these two aren't syncing.";
  static const noteStale =
      "The audiobook file changed after this map was built. Syncing is paused until it's rebuilt.";
  static const noteAbsUnreachable = 'Progress catches up when Audiobookshelf is back.';
  static const noteAbsSending = 'Your newer position is on its way.';
  static const alignUnalignable = "Position sync isn't available for this book pair.";
  static const alignIdle = 'Maps audio to text so your position carries between editions.';

  static const actionRetry = 'Retry';
  static const actionRebuildAlignment = 'Rebuild alignment';
  static const actionAlignNow = 'Align now';
  static const actionSearch = 'Search';
  static const actionMatch = 'Match';
  static const actionConfirm = 'Confirm';
  static const actionCancel = 'Cancel';
  static const actionRebuild = 'Rebuild';
  static const actionRebuildReadAlong = 'Rebuild read-along';
  static const actionUnlink = 'Unlink';
  static const actionChange = 'Change';
  static const actionCancelLinking = 'Cancel linking';
  static const actionCancelAlignment = 'Cancel alignment rebuild';
  static const actionCancelReadAlong = 'Cancel read-along build';
  static const actionDismiss = 'Dismiss';
  static const actionAbsPush = 'Send to ABS';
  static const actionAbsPull = 'Use ABS';
  static const actionAbsUseNow = 'Use it now';
  static const actionImport = 'Import'; // local

  static const unlinkTitle = 'Unlink ebook and audiobook?';
  static const unlinkDescription =
      'Their positions stop syncing with each other. The alignment map is kept, so linking again is instant.';
  static const unlinkDescriptionReadAlong =
      'Their positions stop syncing with each other. The alignment map is kept, so linking again is instant. The read-along stops syncing too and stays in its library.';
  static const unlinkDescriptionReadAlongStays =
      'Their positions stop syncing with each other. The alignment map is kept, so linking again is instant. The read-along keeps syncing with the audiobook.';
  static const detachTitle = 'Stop syncing the read-along?';
  static const detachDescription =
      'Its position stops syncing with the other editions. The read-along book stays in its library.';
  static const stopSyncing = 'Stop syncing';
  static const pauseAbsTitle = 'Stop syncing with Audiobookshelf?';
  static const pauseAbsDescription =
      'Listening progress stops syncing with your Audiobookshelf server. Nothing is removed there.';
  static String changeTitle(String title) => 'Link $title instead?';
  static String changeDescription(String kind) =>
      'The current $kind is unlinked and the alignment is rebuilt for the new pair.';
  static const changeConfirm = 'Link instead';
  static const rebuildTitle = 'Replace this read-along?';
  static String rebuildDescription(String title) =>
      'Rebuilding aligns the pair again and replaces "$title". The existing read-along book and its file are deleted from your library once the new one has been imported and linked. Your ebook and audiobook are not touched.';
  static const rebuildConfirm = 'Rebuild and replace';
  static const readyPending = 'Read-along ready';
  static const untitled = 'Untitled';

  static const loadFailed = 'Failed to load edition link';
  static const toastLinked = 'Books linked.';
  static const toastLinkFailed = 'Failed to link book.';
  static const toastUnlinked = 'Books unlinked.';
  static const toastUnlinkFailed = 'Failed to unlink book.';
  static const toastCancelFailed = "Couldn't cancel linking.";
  static const toastSyncCancelKeptRunning = "The position sync build couldn't be cancelled and keeps running.";
  static const searchFailed = "Couldn't search for a match. Try again.";
  static const toastAttached = 'Read-along syncing again.';
  static const toastDetached = 'Read-along no longer syncing.';
  static const toastAbsResumed = 'Syncing with Audiobookshelf.';
  static const toastAbsPaused = 'Stopped syncing with Audiobookshelf.';
  static const toastAbsChanged = 'Audiobookshelf item changed.';
  static const toastAbsFailed = "Couldn't update Audiobookshelf sync.";
  static const toastAttachFailed = "Couldn't sync the read-along.";
  static const toastDetachFailed = "Couldn't stop syncing the read-along.";
  static String toastChangeFailed(String title) => "Couldn't link $title. The previous edition was unlinked.";
  static const toastAlignBuildFailed = 'Failed to start alignment build.';
  static const toastReadAlongBuildFailed = 'Failed to start the read-along build.';
  static const toastReadAlongAlreadyReady = 'This pair already has a read-along, so nothing was rebuilt.';
  static const toastReadAlongCancelUnavailable = "The read-along build couldn't be cancelled.";
  static const toastReadAlongCancelTooLate = "The read-along is being imported and can't be cancelled now.";
  static const toastReadAlongCancelKeptRunning =
      "The read-along build couldn't be cancelled and keeps running on Storyteller.";

  static const searching = 'Searching...';
  static const noMatches = 'No matches found.';
  static const selectEbook = 'Select a matching ebook';
  static const selectAudiobook = 'Select a matching audiobook';
  static const selectEbookHint =
      'Pick the ebook edition of this book to link progress between them or generate a read-along.';
  static const selectAudiobookHint =
      'Pick the audiobook edition of this book to link progress between them or generate a read-along.';
  static const searchEbooks = 'Search ebooks in your libraries...';
  static const searchAudiobooks = 'Search audiobooks in your libraries...';
  static const selectAbs = 'Pick the Audiobookshelf item';
  static const searchAbs = 'Search Audiobookshelf items…';
  static const bestMatches = 'BEST MATCHES'; // local

  static const absReconcileFailed = 'Could not update the position. Try again.';
  static const absReconcileBusy = 'Sync is busy, try again in a moment.';
  static const absReconcileUnreachable = 'Could not reach Audiobookshelf.';
  static const absChecking = 'Checking Audiobookshelf';
  static String absDivergedHint(int abs, int local) => 'Audiobookshelf $abs%, BookOrbit $local%.';
  static const absDivergedPushOff = 'Sending is off.';
  static const absDivergedPullRefused = 'The last pull did not apply.';
  static const absDivergedStale = 'Neither side has moved since the last sync.';
  static const absReceivingHint = 'Picked up on the next sync.';
  static String absLibrary(String name) => '$name library';

  static const slotNotGenerated = 'Not generated. Storyteller builds it from the ebook and audiobook above.';
  static const slotNeedsEbook = 'Not generated. Pick an ebook in the slot above first.';
  static const slotNeedsAudio = 'Not generated. Pick an audiobook first.';
  static const slotGenerating = 'Generating with Storyteller…';
  static String slotFailed(String step) => 'Storyteller stopped at the $step step. Nothing was added to your library.';
  static const generateHint = 'Storyteller can take an hour or more. Your editions keep syncing meanwhile.';
  static String queued(int position) => 'Waiting for another read-along to finish ($position in line)';
  static const queuedUnknown = 'Waiting for another read-along to finish';
  static const safeToClose = 'Safe to close. Absorb shows progress on the sync button.'; // local
  static const stages = ['Sending', 'Transcribing', 'Aligning', 'Importing'];
  static const tagGenerating = 'Generating'; // local
  static const tagQueued = 'Queued'; // local
  static const tagFailed = 'Failed'; // local

  static const generate = 'Generate read-along';
  static const generateSubtitle = 'Storyteller aligns these two into one book.'; // local
  static String importExisting(String title) => 'Import "$title" from Storyteller';
  static const importExistingHint = 'Already aligned there. Skips the hour-long build.'; // local
  static const targetLibrary = 'Read-along library';
  static String targetLibraryWill(String library) => 'Will be added to $library';
  static const targetLibraryDefault = 'Will be added to the read-along library';
  static const targetLibraryUseConfigured = 'Use the configured library';
  static const targetLibraryConfigured = 'The configured read-along library'; // local
  static const keepRemoteCopy = 'Keep Storyteller copy when done';
  static const keepRemoteCopyOn = 'Storyteller keeps its copy after BookOrbit imports the read-along.';
  static const keepRemoteCopyOff = 'Removed from Storyteller after import. BookOrbit keeps the only copy.';

  static const readAlongBlocks = <ReadAlongBlock, String>{
    ReadAlongBlock.notConfigured: "Storyteller isn't configured on this server yet.",
    ReadAlongBlock.unreachable: "The Storyteller server can't be reached.",
    ReadAlongBlock.busy: 'Storyteller is busy with another read-along. Try again shortly.',
    ReadAlongBlock.noPair: 'Link an ebook and an audiobook first.',
    ReadAlongBlock.noEpub: 'This pair has no EPUB to align.',
    ReadAlongBlock.noAudio: 'This pair has no audio to align.',
    ReadAlongBlock.noTargetLibrary: 'Pick a read-along library in the Storyteller settings.',
    ReadAlongBlock.targetNotAllowed: "You don't have access to the read-along library.",
    ReadAlongBlock.formatNotAllowed: "The read-along library doesn't allow EPUB files.",
    ReadAlongBlock.previousOutputNotDeletable:
        'A read-along already exists for this pair. Replacing it needs permission to delete books.',
    ReadAlongBlock.sourceEpubUnreadable:
        'This book’s EPUB file cannot be read, so Storyteller cannot align it. Replacing the file with a valid EPUB will fix it.',
  };

  static const alignmentBlocks = <AlignmentBlock, String>{
    AlignmentBlock.disabled: 'Reading alignment is turned off for this server.',
    AlignmentBlock.unavailable: "Reading alignment isn't configured on this server yet.",
    AlignmentBlock.busy: 'The server is busy aligning other books. Try again shortly.',
  };

  static String narrationMismatch(int file, String narration, int chapter, String chapterLength) =>
      "Narration does not follow this audiobook's chapters: file $file is $narration, chapter $chapter is $chapterLength.";
  static const narrationMismatchPlain = "Narration does not follow this audiobook's chapters.";
  static const audioChanged = 'The audiobook files changed after this read-along was built.';
}

// ─── Helpers ────────────────────────────────────────────────

/// Index into the four build stages (Sending, Transcribing, Aligning,
/// Importing). Any Storyteller task other than syncing counts as
/// transcription.
int stageIndex(ReadAlongPhase? phase, String? remoteTask) {
  switch (phase) {
    case ReadAlongPhase.wait:
      return remoteTask?.toUpperCase() == 'SYNC_CHAPTERS' ? 2 : 1;
    case ReadAlongPhase.collect:
    case ReadAlongPhase.link:
      return 3;
    default:
      return 0;
  }
}

/// Storyteller's own progress as a whole percentage, or null outside the
/// two stages that report one.
int? readAlongPercent(int stage, double? remoteProgress) {
  if ((stage != 1 && stage != 2) || remoteProgress == null || remoteProgress.isNaN) return null;
  return (remoteProgress * 100).round().clamp(0, 100);
}

/// Busy clears on its own, so actions stay clickable for a retry; every
/// other reason needs a change elsewhere first.
bool isActionBlocked(ReadAlongBlock? blocked) => blocked != null && blocked != ReadAlongBlock.busy;

/// Disabled and unavailable only change with a server config update.
bool isTerminalBlock(AlignmentBlock? reason) =>
    reason == AlignmentBlock.disabled || reason == AlignmentBlock.unavailable;

/// 0..100 for display; rounding alone would read 100% for an unfinished
/// item at 99.5%.
int? displayPercentage(double? value, bool finished) {
  if (value == null) return null;
  if (value <= 0) return 0;
  if (finished) return 100;
  return value.round().clamp(1, 99);
}

/// h:mm:ss, or m:ss under an hour. Seconds matter: a narration file and its
/// chapter differ by seconds.
String playbackClock(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// The read-along's fit with its audiobook, for the connector's note.
String readAloudIssueMessage(String reason,
    {int? narrationFile, double? narrationSeconds, int? chapter, double? chapterSeconds}) {
  if (reason == 'audio_changed') return PositionSyncCopy.audioChanged;
  if (narrationFile != null && narrationSeconds != null && chapter != null && chapterSeconds != null) {
    return PositionSyncCopy.narrationMismatch(
        narrationFile, playbackClock(narrationSeconds), chapter, playbackClock(chapterSeconds));
  }
  return PositionSyncCopy.narrationMismatchPlain;
}

String editionShortName(SyncEdition e) => switch (e) {
      SyncEdition.ebook => PositionSyncCopy.shortEbook,
      SyncEdition.readAlong => PositionSyncCopy.shortReadAlong,
      SyncEdition.audiobook => PositionSyncCopy.shortAudiobook,
      SyncEdition.abs => PositionSyncCopy.shortAbs,
    };

// ─── Snapshot ───────────────────────────────────────────────

enum SyncEdition { ebook, readAlong, audiobook, abs }

enum ChainTone { success, info, warning, destructive, muted }

/// Group rows are drawn inside the audio box: the audiobook, its
/// Audiobookshelf connector and the Audiobookshelf row.
enum ChainFrame { spine, group }

/// The position flow between a connector's names: both ways, towards `from`
/// or towards `to`.
enum ChainArrow { both, left, right }

class SyncChainBook {
  final int id;
  final String? title;
  final String? authorName;
  final String? coverVersion;

  /// 0..100, null when nothing is recorded.
  final int? progress;
  const SyncChainBook({required this.id, this.title, this.authorName, this.coverVersion, this.progress});
}

enum MatchSource { auto, manual, pair, build }

class EditionMatch {
  final MatchSource source;

  /// Meaningful for [MatchSource.auto] only.
  final int score;
  const EditionMatch(this.source, [this.score = 0]);
}

/// One side of the ebook/audiobook pair: the book in that slot, if any, and
/// how it got there.
class SyncChainSide {
  final SyncChainBook? book;
  final bool isMember;
  final bool isThisBook;
  final EditionMatch? match;
  const SyncChainSide({this.book, this.isMember = false, this.isThisBook = false, this.match});
  static const empty = SyncChainSide();
}

class SyncChainAlignment {
  final AlignmentStatus status;
  final bool stale;
  final String? builtAt;
  final int? samplesDone;
  final int? samplesTotal;
  final AlignmentBlock? buildBlocked;
  final String? buildError;

  /// A build is queued or running, including the window between a link and
  /// the first optimistic building status.
  final bool running;
  const SyncChainAlignment({
    this.status = AlignmentStatus.none,
    this.stale = false,
    this.builtAt,
    this.samplesDone,
    this.samplesTotal,
    this.buildBlocked,
    this.buildError,
    this.running = false,
  });
}

class SyncChainReadAlong {
  /// Strictly the link's own read-along member; a detached output never
  /// counts.
  final SyncChainBook? member;
  final ReadAlongStatus status;
  final ReadAlongBlock? blocked;
  final ReadAlongPhase? phase;
  final String? remoteTask;
  final double? remoteProgress;
  final int? queuePosition;
  final SyncChainBook? outputBook;

  /// The current book, set only on the read-along's own page.
  final SyncChainBook? thisBook;
  final String? error;
  final bool mutating;

  /// The output is ready and the link is being reloaded to pick up its
  /// member, so no row is shown yet.
  final bool memberPending;
  const SyncChainReadAlong({
    this.member,
    this.status = ReadAlongStatus.none,
    this.blocked,
    this.phase,
    this.remoteTask,
    this.remoteProgress,
    this.queuePosition,
    this.outputBook,
    this.thisBook,
    this.error,
    this.mutating = false,
    this.memberPending = false,
  });
}

class AbsLink {
  final int audioBookId;
  final String absLibraryItemId;
  final String? title;
  final String? authorName;
  final String? libraryName;
  final AbsDirection direction;
  final bool syncing;
  final AbsPausedReason? pausedReason;
  const AbsLink({
    required this.audioBookId,
    required this.absLibraryItemId,
    this.title,
    this.authorName,
    this.libraryName,
    this.direction = AbsDirection.twoWay,
    this.syncing = false,
    this.pausedReason,
  });
}

class AbsLive {
  final AbsLiveStatus status;
  final double? progressPercentage;
  final bool progressFinished;
  final double? localPercentage;
  final AbsDivergedReason? divergedReason;
  const AbsLive({
    required this.status,
    this.progressPercentage,
    this.progressFinished = false,
    this.localPercentage,
    this.divergedReason,
  });
}

class SyncChainAbs {
  /// The integration is effectively on for this reader; without it the chain
  /// has no Audiobookshelf rows.
  final bool configured;
  final AbsLink? link;
  final AbsLive? live;
  final bool checking;
  const SyncChainAbs({this.configured = true, this.link, this.live, this.checking = false});
}

class ReadAloudIssueView {
  final String message;
  const ReadAloudIssueView(this.message);
}

class SyncChainPermissions {
  final bool editLink;
  final bool generate;
  final bool rebuild;
  const SyncChainPermissions({this.editLink = false, this.generate = false, this.rebuild = false});
}

class SyncChainSnapshot {
  /// Ebook, audiobook or read-along; never abs.
  final SyncEdition thisBook;
  final bool linked;
  final SyncChainSide ebook;
  final SyncChainSide audiobook;
  final SyncChainAlignment alignment;
  final SyncChainReadAlong readAlong;
  final ReadAloudIssueView? readAloudIssue;

  /// Null without the Audiobookshelf sync permission.
  final SyncChainAbs? abs;
  final SyncChainPermissions can;
  const SyncChainSnapshot({
    required this.thisBook,
    this.linked = false,
    this.ebook = SyncChainSide.empty,
    this.audiobook = SyncChainSide.empty,
    this.alignment = const SyncChainAlignment(),
    this.readAlong = const SyncChainReadAlong(),
    this.readAloudIssue,
    this.abs,
    this.can = const SyncChainPermissions(),
  });

  SyncChainSnapshot _withoutAbs() => SyncChainSnapshot(
        thisBook: thisBook,
        linked: linked,
        ebook: ebook,
        audiobook: audiobook,
        alignment: alignment,
        readAlong: readAlong,
        readAloudIssue: readAloudIssue,
        can: can,
      );

  SyncChainSide side(SyncEdition e) => e == SyncEdition.audiobook ? audiobook : ebook;
}

// ─── Rows ───────────────────────────────────────────────────

enum ChainActionId {
  linkPair,
  cancelLinking,
  cancelAlignment,
  retryAlignment,
  alignNow,
  rebuildAlignment,
  unlinkPair,
  attachReadAlong,
  openGenerate,
  cancelReadAlong,
  retryReadAlong,
  rebuildReadAlong,
  change,
  retryAbs,
  absPush,
  absPull,
  confirmAbs,
  resumeAbs,
}

class ChainAction {
  final ChainActionId id;
  final String label;
  final bool disabled;
  const ChainAction(this.id, this.label, {this.disabled = false});
}

class ReadAlongJob {
  /// Index into the four build stages.
  final int stage;
  final double? remoteProgress;

  /// The build failed at [stage], so the stepper shows that step as failed.
  final bool failed;
  final ChainAction? cancel;
  final ChainAction? retry;
  final String? error;
  const ReadAlongJob({required this.stage, this.remoteProgress, this.failed = false, this.cancel, this.retry, this.error});
}

enum ChangeState { available, blocked, none }

sealed class ChainCover {
  const ChainCover();
}

class BookCover extends ChainCover {
  final int bookId;
  final String? coverVersion;
  const BookCover(this.bookId, this.coverVersion);
}

class AbsCover extends ChainCover {
  final String absLibraryItemId;
  const AbsCover(this.absLibraryItemId);
}

class TileCover extends ChainCover {
  const TileCover();
}

sealed class ChainRow {
  const ChainRow();
}

class ChainCardRow extends ChainRow {
  final SyncEdition edition;
  final ChainFrame frame;
  final ChainCover cover;
  final String? title;

  /// Author for a book, library for the Audiobookshelf item.
  final String? subtitle;
  final bool isThisBook;
  final bool external;
  final int? progress;

  /// The live check is still running.
  final bool progressPending;

  /// A member or this book; any other edition that exists waits for the
  /// switch next to it.
  final bool linked;

  /// How the edition was picked, or why it is not syncing.
  final String? chip;
  final ChangeState change;
  final String? changeHint;
  final ChainAction? confirm;
  final ChainAction? rebuild;
  final ReadAlongJob? job;
  const ChainCardRow({
    required this.edition,
    required this.frame,
    required this.cover,
    this.title,
    this.subtitle,
    this.isThisBook = false,
    this.external = false,
    this.progress,
    this.progressPending = false,
    this.linked = false,
    this.chip,
    this.change = ChangeState.none,
    this.changeHint,
    this.confirm,
    this.rebuild,
    this.job,
  });
}

class ChainGhostRow extends ChainRow {
  final SyncEdition edition;
  final ChainFrame frame;
  final String label;
  final String note;

  /// At most one: Search or Match, which both open the Change page.
  final ChainAction? action;
  const ChainGhostRow({required this.edition, required this.frame, required this.label, required this.note, this.action});
}

enum ReadAlongSlotVariant { notGenerated, needsEbook, needsAudio, blocked, queued, building, failed }

class ChainReadAlongSlotRow extends ChainRow {
  final ReadAlongSlotVariant variant;
  final String note;

  /// Generate while idle, Retry after a failure.
  final ChainAction? action;

  /// The red X for a job in flight, Dismiss for a failed one.
  final ChainAction? cancel;
  final ReadAlongJob? job;
  final String? error;
  const ChainReadAlongSlotRow({required this.variant, required this.note, this.action, this.cancel, this.job, this.error});
}

enum ConnectorKey { readAlongAudiobook, ebookAudiobook, audiobookAbs }

enum ConnectorState {
  linking,
  rebuilding,
  alignmentFailed,
  outOfDate,
  cantAlign,
  alignmentBlocked,
  notAligned,
  linkedViaWhisper,
  linked,
  available,
  readAloudIssue,
  absUnreachable,
  absDiverged,
  absReceiving,
  absSending,
  absOneWay,
  absLinked,
}

/// What a connector's switch turns off: always the link that connector
/// draws.
enum OffTarget { pair, readAlong, abs }

class ChainSwitch {
  final bool on;
  final bool disabled;

  /// Turning it on runs this action; turning it off opens the confirm for
  /// [offTarget] (or cancels while linking).
  final ChainActionId? onAction;
  final OffTarget? offTarget;
  const ChainSwitch({required this.on, required this.disabled, this.onAction, this.offTarget});
}

class ChainConnectorRow extends ChainRow {
  final ConnectorKey key;
  final ChainFrame frame;
  final SyncEdition from;
  final SyncEdition to;
  final ConnectorState state;
  final ChainTone tone;
  final ChainArrow arrow;
  final String pill;
  final String? qualifier;
  final String? explainer;

  /// Null when the switch is hidden (failed alignment, a bare rail node).
  final ChainSwitch? toggle;

  /// Why a disabled switch cannot be turned on.
  final String? disabledReason;
  final String? note;

  /// Literal text under the note, such as the alignment build error.
  final String? detail;
  final List<ChainAction> actions;

  /// The X beside the ticks while aligning.
  final ChainAction? cancel;
  final ({int? done, int? total})? ticks;

  /// Audiobookshelf states add the live hint line for receiving and
  /// diverged.
  final bool absDetails;
  const ChainConnectorRow({
    required this.key,
    required this.frame,
    required this.from,
    required this.to,
    required this.state,
    required this.tone,
    required this.arrow,
    required this.pill,
    this.qualifier,
    this.explainer,
    this.toggle,
    this.disabledReason,
    this.note,
    this.detail,
    this.actions = const [],
    this.cancel,
    this.ticks,
    this.absDetails = false,
  });
}

class SyncChainHeader {
  final ChainTone tone;
  final String label;
  const SyncChainHeader(this.tone, this.label);
}

class SyncChain {
  final List<ChainRow> rows;
  final SyncChainHeader header;
  final String intro;

  /// A failure or a check-sync state is showing.
  final bool needsAttention;
  const SyncChain({required this.rows, required this.header, required this.intro, required this.needsAttention});
}

// ─── Derivation (same names as sync-chain.ts) ───────────────

bool _sideIsCard(SyncChainSide side) => side.book != null && (side.isMember || side.isThisBook);

// Audiobookshelf matches the audiobook itself, so its rows need an audiobook
// on screen, linked to this page or not.
bool _absIsCard(SyncChainSnapshot s) => s.abs?.link?.syncing == true && s.audiobook.book != null;

/// The read-along is a book of its own (linked, detached or this page), so it
/// gets a place on the spine.
bool _readAlongBookExists(SyncChainSnapshot s) {
  final ra = s.readAlong;
  if (s.thisBook == SyncEdition.readAlong || ra.member != null) return true;
  return !ra.memberPending && ra.status == ReadAlongStatus.ready && ra.outputBook != null;
}

bool _readAlongOutOfReach(SyncChainSnapshot s) {
  final ra = s.readAlong;
  return !ra.memberPending &&
      s.thisBook != SyncEdition.readAlong &&
      ra.member == null &&
      ra.status == ReadAlongStatus.ready &&
      ra.outputBook == null;
}

bool _readAlongBuildRunning(SyncChainSnapshot s) =>
    s.readAlong.status == ReadAlongStatus.queued || s.readAlong.status == ReadAlongStatus.building;

/// The bottom slot shows a build for the pair on screen: running, or failed
/// and retryable by this reader.
bool _slotShowsBuild(SyncChainSnapshot s) {
  if (s.readAlong.memberPending || _readAlongBookExists(s)) return false;
  return _readAlongBuildRunning(s) || (s.readAlong.status == ReadAlongStatus.failed && s.can.generate);
}

enum _AlignmentState { linking, rebuilding, alignmentFailed, outOfDate, cantAlign, alignmentBlocked, notAligned, ready }

_AlignmentState _alignmentState(SyncChainAlignment a) {
  if (a.running || a.status == AlignmentStatus.pending || a.status == AlignmentStatus.building) {
    return a.builtAt == null ? _AlignmentState.linking : _AlignmentState.rebuilding;
  }
  if (a.status == AlignmentStatus.failed) return _AlignmentState.alignmentFailed;
  if (a.status == AlignmentStatus.ready) return a.stale ? _AlignmentState.outOfDate : _AlignmentState.ready;
  if (a.status == AlignmentStatus.unalignable) return _AlignmentState.cantAlign;
  return isTerminalBlock(a.buildBlocked) ? _AlignmentState.alignmentBlocked : _AlignmentState.notAligned;
}

ConnectorState _absState(AbsLink link, AbsLive? live) {
  switch (live?.status) {
    case AbsLiveStatus.unreachable:
      return ConnectorState.absUnreachable;
    case AbsLiveStatus.diverged:
      return ConnectorState.absDiverged;
    case AbsLiveStatus.receiving:
      return ConnectorState.absReceiving;
    case AbsLiveStatus.sending:
      return ConnectorState.absSending;
    default:
      return link.direction == AbsDirection.twoWay ? ConnectorState.absLinked : ConnectorState.absOneWay;
  }
}

bool _hasReadAloudIssue(SyncChainSnapshot s) => s.readAlong.member != null && s.readAloudIssue != null;

bool _canCancelReadAlong(SyncChainSnapshot s) {
  if (!s.can.generate) return false;
  final ra = s.readAlong;
  if (ra.status == ReadAlongStatus.queued) return true;
  return ra.status == ReadAlongStatus.building && ra.phase != ReadAlongPhase.collect && ra.phase != ReadAlongPhase.link;
}

ReadAlongJob? _readAlongJob(SyncChainSnapshot s, bool withRetry) {
  final ra = s.readAlong;
  final failed = ra.status == ReadAlongStatus.failed;
  if (ra.status != ReadAlongStatus.queued && ra.status != ReadAlongStatus.building && !failed) return null;
  return ReadAlongJob(
    stage: ra.status == ReadAlongStatus.queued ? 0 : stageIndex(ra.phase, ra.remoteTask),
    remoteProgress: ra.remoteProgress,
    failed: failed,
    cancel: _canCancelReadAlong(s)
        ? ChainAction(ChainActionId.cancelReadAlong, PositionSyncCopy.actionCancelReadAlong, disabled: ra.mutating)
        : null,
    retry: withRetry && failed && s.can.generate
        ? ChainAction(ChainActionId.retryReadAlong, PositionSyncCopy.actionRetry,
            disabled: ra.mutating || isActionBlocked(ra.blocked))
        : null,
    error: failed ? ra.error : null,
  );
}

/// Re-pointing a side would orphan what the read-along holds: its member, or
/// a build queued for this pair. An unlinked candidate also keeps a failed
/// build's pair, so Retry still targets the same audiobook.
(ChangeState, String?) _pairChange(SyncChainSnapshot s, SyncChainSide side, bool linked) {
  if (side.isThisBook || !s.can.editLink) return (ChangeState.none, null);
  if (!linked) {
    if (side.match?.source == MatchSource.pair) return (ChangeState.none, null);
    if (_readAlongBuildRunning(s)) return (ChangeState.blocked, PositionSyncCopy.changeBuilding);
    if (!_slotShowsBuild(s)) return (ChangeState.available, null);
    return (ChangeState.blocked, PositionSyncCopy.changeFailed);
  }
  if (s.readAlong.member != null) return (ChangeState.blocked, PositionSyncCopy.changeBlocked);
  if (_readAlongBuildRunning(s)) return (ChangeState.blocked, PositionSyncCopy.changeBuilding);
  return (ChangeState.available, null);
}

String? _candidateChip(EditionMatch? match, String title) {
  switch (match?.source) {
    case MatchSource.auto:
      return PositionSyncCopy.chipMatch(match!.score);
    case MatchSource.manual:
    case MatchSource.build:
      return PositionSyncCopy.chipSelected;
    case MatchSource.pair:
      return PositionSyncCopy.chipGeneratedFrom(title);
    case null:
      return null;
  }
}

ChainGhostRow _ghostRow(SyncEdition edition, ChainFrame frame, String note, {ChainAction? action}) => ChainGhostRow(
      edition: edition,
      frame: frame,
      label: edition == SyncEdition.abs ? PositionSyncCopy.kindAbs : editionShortName(edition),
      note: note,
      action: action,
    );

ChainFrame _sideFrame(SyncEdition edition) => edition == SyncEdition.audiobook ? ChainFrame.group : ChainFrame.spine;

ChainRow _sideSlot(SyncChainSnapshot s, SyncEdition edition) {
  final side = s.side(edition);
  final book = side.book;
  if (book == null) {
    return _ghostRow(
      edition,
      _sideFrame(edition),
      edition == SyncEdition.ebook ? PositionSyncCopy.ghostNoMatchEbook : PositionSyncCopy.ghostNoMatchAudiobook,
      action: s.can.editLink ? const ChainAction(ChainActionId.change, PositionSyncCopy.actionSearch) : null,
    );
  }
  final linked = _sideIsCard(side);
  final (change, changeHint) = _pairChange(s, side, linked);
  return ChainCardRow(
    edition: edition,
    frame: _sideFrame(edition),
    cover: BookCover(book.id, book.coverVersion),
    title: book.title,
    subtitle: book.authorName,
    isThisBook: side.isThisBook,
    progress: book.progress,
    linked: linked,
    chip: linked ? null : _candidateChip(side.match, book.title ?? ''),
    change: change,
    changeHint: changeHint,
  );
}

/// A rebuild replaces a ready read-along member, so it needs a real link for
/// the new output to attach to.
bool _canRebuildReadAlong(SyncChainSnapshot s, SyncChainReadAlong ra) =>
    s.linked && ra.member != null && ra.status == ReadAlongStatus.ready && s.can.generate && s.can.rebuild;

ChainCardRow _readAlongCard(SyncChainSnapshot s) {
  final ra = s.readAlong;
  final isThisBook = s.thisBook == SyncEdition.readAlong;
  final linked = ra.member != null || isThisBook;
  final book = ra.member ?? ra.outputBook ?? ra.thisBook;
  return ChainCardRow(
    edition: SyncEdition.readAlong,
    frame: ChainFrame.spine,
    cover: book != null
        ? BookCover(book.id, ra.member?.coverVersion ?? ra.thisBook?.coverVersion)
        : const TileCover(),
    title: book?.title,
    subtitle: ra.member?.authorName ?? ra.thisBook?.authorName,
    isThisBook: isThisBook,
    progress: ra.member?.progress,
    linked: linked,
    chip: linked ? null : PositionSyncCopy.chipGenerated,
    rebuild: _canRebuildReadAlong(s, ra)
        ? ChainAction(ChainActionId.rebuildReadAlong, PositionSyncCopy.actionRebuild,
            disabled: ra.mutating || isActionBlocked(ra.blocked))
        : null,
    job: _readAlongJob(s, true),
  );
}

ChainCardRow _absCard(SyncChainAbs abs, AbsLink link) {
  final live = abs.live;
  final linked = link.syncing;
  final needsReview = !linked && link.pausedReason == AbsPausedReason.needsReview;
  return ChainCardRow(
    edition: SyncEdition.abs,
    frame: ChainFrame.group,
    cover: AbsCover(link.absLibraryItemId),
    title: link.title,
    subtitle: link.libraryName,
    external: true,
    progress: live == null ? null : displayPercentage(live.progressPercentage, live.progressFinished),
    progressPending: abs.checking,
    linked: linked,
    chip: linked ? null : (needsReview ? PositionSyncCopy.chipNeedsReview : PositionSyncCopy.chipPaused),
    change: ChangeState.available,
    confirm: needsReview ? const ChainAction(ChainActionId.confirmAbs, PositionSyncCopy.actionConfirm) : null,
  );
}

ChainRow _absSlot(SyncChainSnapshot s, SyncChainAbs abs) {
  final link = abs.link;
  final audioExists = s.audiobook.book != null;
  if (link == null) {
    if (!audioExists) return _ghostRow(SyncEdition.abs, ChainFrame.group, PositionSyncCopy.ghostAbsNeedsAudio);
    return _ghostRow(SyncEdition.abs, ChainFrame.group, PositionSyncCopy.ghostNoMatchAbs,
        action: const ChainAction(ChainActionId.change, PositionSyncCopy.actionMatch));
  }
  if (link.pausedReason == AbsPausedReason.positionSyncOff) {
    return _ghostRow(SyncEdition.abs, ChainFrame.group, PositionSyncCopy.ghostAbsPositionSyncOff);
  }
  if (!audioExists) return _ghostRow(SyncEdition.abs, ChainFrame.group, PositionSyncCopy.ghostAbsNeedsAudio);
  return _absCard(abs, link);
}

ConnectorKey _connectorKey(SyncEdition from, SyncEdition to) => switch ((from, to)) {
      (SyncEdition.readAlong, _) => ConnectorKey.readAlongAudiobook,
      (_, SyncEdition.abs) => ConnectorKey.audiobookAbs,
      _ => ConnectorKey.ebookAudiobook,
    };

ChainConnectorRow _connectorRow(
  SyncEdition from,
  SyncEdition to, {
  required ConnectorState state,
  required ChainTone tone,
  required String pill,
  ChainFrame frame = ChainFrame.spine,
  ChainArrow arrow = ChainArrow.both,
  String? qualifier,
  String? explainer,
  ChainSwitch? toggle,
  String? disabledReason,
  String? note,
  String? detail,
  List<ChainAction> actions = const [],
  ChainAction? cancel,
  ({int? done, int? total})? ticks,
  bool absDetails = false,
}) =>
    ChainConnectorRow(
      key: _connectorKey(from, to),
      frame: frame,
      from: from,
      to: to,
      state: state,
      tone: tone,
      arrow: arrow,
      pill: pill,
      qualifier: qualifier,
      explainer: explainer,
      toggle: toggle,
      disabledReason: disabledReason ?? (toggle?.disabled == true ? PositionSyncCopy.disabledNoPermission : null),
      note: note,
      detail: detail,
      actions: actions,
      cancel: cancel,
      ticks: ticks,
      absDetails: absDetails,
    );

const _offTargets = {
  ConnectorKey.readAlongAudiobook: OffTarget.readAlong,
  ConnectorKey.ebookAudiobook: OffTarget.pair,
  ConnectorKey.audiobookAbs: OffTarget.abs,
};

ChainSwitch _onSwitch(SyncChainSnapshot s, SyncEdition from, SyncEdition to, {bool? disabled}) => ChainSwitch(
      on: true,
      disabled: disabled ?? !s.can.editLink,
      offTarget: _offTargets[_connectorKey(from, to)],
    );

ChainAction? _editAction(SyncChainSnapshot s, ChainActionId id, String label) =>
    s.can.editLink ? ChainAction(id, label) : null;

List<ChainAction> _present(List<ChainAction?> actions) => [for (final a in actions) if (a != null) a];

/// Nothing is linked across this pair: a muted off switch the user can turn
/// on unless [disabledReason] says why not.
ChainConnectorRow _offConnector(
  SyncEdition from,
  SyncEdition to, {
  required ChainFrame frame,
  required String qualifier,
  required ChainActionId? onAction,
  required String? disabledReason,
  ChainArrow arrow = ChainArrow.both,
  String? explainer,
}) =>
    _connectorRow(
      from,
      to,
      state: ConnectorState.available,
      tone: ChainTone.muted,
      frame: frame,
      arrow: arrow,
      pill: PositionSyncCopy.pillAvailable,
      qualifier: qualifier,
      explainer: explainer,
      toggle: ChainSwitch(on: false, disabled: disabledReason != null, onAction: onAction),
      disabledReason: disabledReason,
    );

ChainConnectorRow _alignmentConnector(SyncChainSnapshot s, SyncEdition from, SyncEdition to) {
  final a = s.alignment;
  final ticks = (done: a.samplesDone, total: a.samplesTotal);
  switch (_alignmentState(a)) {
    case _AlignmentState.linking:
      return _connectorRow(from, to,
          state: ConnectorState.linking,
          tone: ChainTone.info,
          pill: PositionSyncCopy.pillLinking,
          toggle: _onSwitch(s, from, to),
          note: PositionSyncCopy.noteLinking,
          cancel: _editAction(s, ChainActionId.cancelLinking, PositionSyncCopy.actionCancelLinking),
          ticks: ticks);
    case _AlignmentState.rebuilding:
      return _connectorRow(from, to,
          state: ConnectorState.rebuilding,
          tone: ChainTone.info,
          pill: PositionSyncCopy.pillRebuilding,
          toggle: _onSwitch(s, from, to),
          cancel: _editAction(s, ChainActionId.cancelAlignment, PositionSyncCopy.actionCancelAlignment),
          ticks: ticks);
    case _AlignmentState.alignmentFailed:
      return _connectorRow(from, to,
          state: ConnectorState.alignmentFailed,
          tone: ChainTone.destructive,
          pill: PositionSyncCopy.pillAlignmentFailed,
          note: PositionSyncCopy.noteAlignmentFailed,
          detail: a.buildError,
          actions: _present([
            _editAction(s, ChainActionId.retryAlignment, PositionSyncCopy.actionRetry),
            _editAction(s, ChainActionId.unlinkPair, PositionSyncCopy.actionUnlink),
          ]));
    case _AlignmentState.outOfDate:
      return _connectorRow(from, to,
          state: ConnectorState.outOfDate,
          tone: ChainTone.warning,
          pill: PositionSyncCopy.pillOutOfDate,
          toggle: _onSwitch(s, from, to),
          note: PositionSyncCopy.noteStale,
          actions: _present([_editAction(s, ChainActionId.rebuildAlignment, PositionSyncCopy.actionRebuildAlignment)]));
    case _AlignmentState.cantAlign:
      return _connectorRow(from, to,
          state: ConnectorState.cantAlign,
          tone: ChainTone.muted,
          pill: PositionSyncCopy.pillCantAlign,
          toggle: _onSwitch(s, from, to),
          note: PositionSyncCopy.alignUnalignable);
    case _AlignmentState.alignmentBlocked:
      return _connectorRow(from, to,
          state: ConnectorState.alignmentBlocked,
          tone: ChainTone.muted,
          pill: PositionSyncCopy.pillNotAligned,
          toggle: _onSwitch(s, from, to),
          note: PositionSyncCopy.alignmentBlocks[a.buildBlocked]);
    case _AlignmentState.notAligned:
      return _connectorRow(from, to,
          state: ConnectorState.notAligned,
          tone: ChainTone.warning,
          pill: PositionSyncCopy.pillNotAligned,
          toggle: _onSwitch(s, from, to),
          note: a.buildBlocked == AlignmentBlock.busy
              ? PositionSyncCopy.alignmentBlocks[AlignmentBlock.busy]
              : PositionSyncCopy.alignIdle,
          actions: _present([_editAction(s, ChainActionId.alignNow, PositionSyncCopy.actionAlignNow)]));
    case _AlignmentState.ready:
      return _connectorRow(from, to,
          state: ConnectorState.linkedViaWhisper,
          tone: ChainTone.success,
          pill: PositionSyncCopy.pillLinkedViaWhisper,
          qualifier: PositionSyncCopy.qualifierViaWhisper,
          explainer: PositionSyncCopy.explainWhisper,
          toggle: _onSwitch(s, from, to));
  }
}

ChainConnectorRow _pairConnector(SyncChainSnapshot s) {
  if (s.linked && _sideIsCard(s.ebook) && _sideIsCard(s.audiobook)) {
    return _alignmentConnector(s, SyncEdition.ebook, SyncEdition.audiobook);
  }
  final nothingToLink = s.ebook.book == null || s.audiobook.book == null;
  return _offConnector(SyncEdition.ebook, SyncEdition.audiobook,
      frame: ChainFrame.spine,
      qualifier: PositionSyncCopy.offNotLinked,
      onAction: ChainActionId.linkPair,
      disabledReason: nothingToLink
          ? PositionSyncCopy.disabledNothingToLink
          : s.can.editLink
              ? null
              : PositionSyncCopy.disabledNoPermission,
      explainer: PositionSyncCopy.explainWhisper);
}

ChainConnectorRow _readAlongConnector(SyncChainSnapshot s) {
  final ra = s.readAlong;
  if (ra.member == null) {
    // A read-along attaches to its audiobook on its own, so its switch only
    // waits for an audiobook to exist.
    final noAudio = s.audiobook.book == null;
    return _offConnector(SyncEdition.readAlong, SyncEdition.audiobook,
        frame: ChainFrame.spine,
        onAction: ChainActionId.attachReadAlong,
        explainer: PositionSyncCopy.explainReadAlongAudio,
        qualifier: noAudio ? PositionSyncCopy.offPickAudiobookFirst : PositionSyncCopy.offNotLinked,
        disabledReason: noAudio
            ? PositionSyncCopy.offPickAudiobookFirst
            : s.can.editLink
                ? null
                : PositionSyncCopy.disabledNoPermission);
  }
  final issue = s.readAloudIssue;
  if (issue != null) {
    return _connectorRow(SyncEdition.readAlong, SyncEdition.audiobook,
        state: ConnectorState.readAloudIssue,
        tone: ChainTone.warning,
        pill: PositionSyncCopy.pillNotSyncing,
        toggle: _onSwitch(s, SyncEdition.readAlong, SyncEdition.audiobook),
        note: issue.message,
        actions: _canRebuildReadAlong(s, ra)
            ? [
                ChainAction(ChainActionId.rebuildReadAlong, PositionSyncCopy.actionRebuildReadAlong,
                    disabled: ra.mutating || isActionBlocked(ra.blocked)),
              ]
            : const []);
  }
  return _connectorRow(SyncEdition.readAlong, SyncEdition.audiobook,
      state: ConnectorState.linked,
      tone: ChainTone.success,
      pill: PositionSyncCopy.pillLinked,
      qualifier: PositionSyncCopy.qualifierDirect,
      explainer: PositionSyncCopy.explainReadAlongAudio,
      toggle: _onSwitch(s, SyncEdition.readAlong, SyncEdition.audiobook));
}

String _absExplain(AbsDirection d) => switch (d) {
      AbsDirection.twoWay => PositionSyncCopy.explainAbsTwoWay,
      AbsDirection.fromAbs => PositionSyncCopy.explainAbsFromAbs,
      AbsDirection.toAbs => PositionSyncCopy.explainAbsToAbs,
    };

ChainArrow _absArrow(AbsDirection d) => switch (d) {
      AbsDirection.fromAbs => ChainArrow.left,
      AbsDirection.toAbs => ChainArrow.right,
      AbsDirection.twoWay => ChainArrow.both,
    };

ChainConnectorRow _absLinkedConnector(SyncChainSnapshot s, SyncChainAbs abs, AbsLink link) {
  final state = _absState(link, abs.live);
  final warns = state == ConnectorState.absUnreachable || state == ConnectorState.absDiverged;
  return _connectorRow(SyncEdition.audiobook, SyncEdition.abs,
      state: state,
      frame: ChainFrame.group,
      tone: warns ? ChainTone.warning : ChainTone.success,
      arrow: _absArrow(link.direction),
      pill: switch (state) {
        ConnectorState.absUnreachable => PositionSyncCopy.pillCantReach,
        ConnectorState.absDiverged => PositionSyncCopy.pillDiverged,
        ConnectorState.absOneWay => PositionSyncCopy.pillOneWay,
        _ => PositionSyncCopy.pillLinked,
      },
      qualifier: warns
          ? null
          : link.direction == AbsDirection.twoWay
              ? PositionSyncCopy.qualifierTwoWay
              : PositionSyncCopy.qualifierOneWay,
      explainer: warns ? null : _absExplain(link.direction),
      // The whole Audiobookshelf section is already gated on its permission.
      toggle: _onSwitch(s, SyncEdition.audiobook, SyncEdition.abs, disabled: false),
      note: switch (state) {
        ConnectorState.absUnreachable => PositionSyncCopy.noteAbsUnreachable,
        ConnectorState.absSending => PositionSyncCopy.noteAbsSending,
        _ => null,
      },
      actions: switch (state) {
        ConnectorState.absUnreachable => const [ChainAction(ChainActionId.retryAbs, PositionSyncCopy.actionRetry)],
        ConnectorState.absDiverged => const [
            ChainAction(ChainActionId.absPush, PositionSyncCopy.actionAbsPush),
            ChainAction(ChainActionId.absPull, PositionSyncCopy.actionAbsPull),
          ],
        ConnectorState.absReceiving => const [ChainAction(ChainActionId.absPull, PositionSyncCopy.actionAbsUseNow)],
        _ => const [],
      },
      absDetails: true);
}

ChainConnectorRow _absOffConnector(SyncChainSnapshot s, AbsLink? link) {
  ChainConnectorRow off(String qualifier, ChainActionId? onAction, String? reason) =>
      _offConnector(SyncEdition.audiobook, SyncEdition.abs,
          frame: ChainFrame.group,
          qualifier: qualifier,
          onAction: onAction,
          disabledReason: reason,
          explainer: link != null ? _absExplain(link.direction) : null,
          arrow: link != null ? _absArrow(link.direction) : ChainArrow.both);
  if (link?.pausedReason == AbsPausedReason.positionSyncOff) {
    return off(PositionSyncCopy.offSyncOffInSettings, null, PositionSyncCopy.offSyncOffInSettings);
  }
  if (s.audiobook.book == null) {
    return off(PositionSyncCopy.offPickAudiobookFirst, null, PositionSyncCopy.offPickAudiobookFirst);
  }
  if (link == null) return off(PositionSyncCopy.offNotMatched, null, PositionSyncCopy.disabledNothingToLink);
  return link.pausedReason == AbsPausedReason.needsReview
      ? off(PositionSyncCopy.offNeedsReview, ChainActionId.confirmAbs, null)
      : off(PositionSyncCopy.offSyncPaused, ChainActionId.resumeAbs, null);
}

ChainConnectorRow _absConnector(SyncChainSnapshot s, SyncChainAbs abs) {
  final link = abs.link;
  return _absIsCard(s) && link != null ? _absLinkedConnector(s, abs, link) : _absOffConnector(s, link);
}

ChainReadAlongSlotRow? _idleSlot(SyncChainSnapshot s) {
  final ra = s.readAlong;
  if (!s.can.generate || ra.blocked == ReadAlongBlock.notConfigured) return null;
  ChainAction generate(bool disabled) =>
      ChainAction(ChainActionId.openGenerate, PositionSyncCopy.generate, disabled: disabled);
  if (s.audiobook.book == null) {
    return ChainReadAlongSlotRow(
        variant: ReadAlongSlotVariant.needsAudio, note: PositionSyncCopy.slotNeedsAudio, action: generate(true));
  }
  if (s.ebook.book == null) {
    return ChainReadAlongSlotRow(
        variant: ReadAlongSlotVariant.needsEbook, note: PositionSyncCopy.slotNeedsEbook, action: generate(true));
  }
  final blocked = ra.blocked == ReadAlongBlock.noPair && !s.linked ? null : ra.blocked;
  if (isActionBlocked(blocked)) {
    return ChainReadAlongSlotRow(
        variant: ReadAlongSlotVariant.blocked,
        note: PositionSyncCopy.readAlongBlocks[blocked]!,
        action: generate(true));
  }
  return ChainReadAlongSlotRow(
      variant: ReadAlongSlotVariant.notGenerated,
      note: PositionSyncCopy.slotNotGenerated,
      action: generate(ra.mutating));
}

ChainReadAlongSlotRow? _readAlongSlot(SyncChainSnapshot s) {
  final ra = s.readAlong;
  if (ra.memberPending || _readAlongBookExists(s) || _readAlongOutOfReach(s)) return null;
  switch (ra.status) {
    case ReadAlongStatus.queued:
    case ReadAlongStatus.building:
      final job = _readAlongJob(s, false);
      final building = ra.status == ReadAlongStatus.building;
      return ChainReadAlongSlotRow(
        variant: building ? ReadAlongSlotVariant.building : ReadAlongSlotVariant.queued,
        note: building
            ? PositionSyncCopy.slotGenerating
            : ra.queuePosition == null
                ? PositionSyncCopy.queuedUnknown
                : PositionSyncCopy.queued(ra.queuePosition!),
        cancel: job?.cancel,
        job: job,
      );
    case ReadAlongStatus.failed:
      return ChainReadAlongSlotRow(
        variant: ReadAlongSlotVariant.failed,
        note: PositionSyncCopy.slotFailed(PositionSyncCopy.stages[stageIndex(ra.phase, ra.remoteTask)]),
        action: s.can.generate
            ? ChainAction(ChainActionId.retryReadAlong, PositionSyncCopy.actionRetry,
                disabled: ra.mutating || isActionBlocked(ra.blocked))
            : null,
        cancel: s.can.generate
            ? ChainAction(ChainActionId.cancelReadAlong, PositionSyncCopy.actionDismiss, disabled: ra.mutating)
            : null,
        error: ra.error,
      );
    default:
      return _idleSlot(s);
  }
}

/// The muted connector above a read-along that has nothing to switch: a bare
/// node that keeps the spine joined.
ChainConnectorRow _mutedReadAlongConnector(String? qualifier) => _connectorRow(
      SyncEdition.readAlong,
      SyncEdition.audiobook,
      state: ConnectorState.available,
      tone: ChainTone.muted,
      pill: qualifier ?? PositionSyncCopy.pillAvailable,
      qualifier: qualifier,
    );

List<ChainRow> _readAlongRows(SyncChainSnapshot s) {
  if (_readAlongBookExists(s)) return [_readAlongConnector(s), _readAlongCard(s)];
  if (_readAlongOutOfReach(s)) {
    return [
      _mutedReadAlongConnector(null),
      _ghostRow(SyncEdition.readAlong, ChainFrame.spine, PositionSyncCopy.ghostOutOfReach),
    ];
  }
  final slot = _readAlongSlot(s);
  return slot != null ? [_mutedReadAlongConnector(PositionSyncCopy.offNotGenerated), slot] : const [];
}

List<ChainRow> _orderedRows(SyncChainSnapshot s) {
  final abs = s.abs;
  final group = <ChainRow>[
    _sideSlot(s, SyncEdition.audiobook),
    if (abs != null) ...[_absConnector(s, abs), _absSlot(s, abs)],
  ];
  final ebookSlot = _sideSlot(s, SyncEdition.ebook);
  final ebookConnector = _pairConnector(s);
  switch (s.thisBook) {
    case SyncEdition.audiobook:
      return [...group, ebookConnector, ebookSlot, ..._readAlongRows(s)];
    case SyncEdition.readAlong:
      return [_readAlongCard(s), _readAlongConnector(s), ...group, ebookConnector, ebookSlot];
    case SyncEdition.ebook:
    case SyncEdition.abs:
      return [ebookSlot, ebookConnector, ...group, ..._readAlongRows(s)];
  }
}

int? _headerPriority(SyncChainSnapshot s) {
  final pairLinked = s.linked && _sideIsCard(s.ebook) && _sideIsCard(s.audiobook);
  final align = pairLinked ? _alignmentState(s.alignment) : null;
  final ra = s.readAlong.status;
  final link = s.abs?.link;
  final abs = _absIsCard(s) && link != null ? _absState(link, s.abs!.live) : null;
  if (align == _AlignmentState.alignmentFailed || ra == ReadAlongStatus.failed) return 1;
  final alignWarns = align == _AlignmentState.outOfDate ||
      align == _AlignmentState.notAligned ||
      align == _AlignmentState.cantAlign ||
      align == _AlignmentState.alignmentBlocked;
  if (alignWarns ||
      _hasReadAloudIssue(s) ||
      abs == ConnectorState.absUnreachable ||
      abs == ConnectorState.absDiverged) {
    return 2;
  }
  if (align == _AlignmentState.linking ||
      align == _AlignmentState.rebuilding ||
      ra == ReadAlongStatus.queued ||
      ra == ReadAlongStatus.building) {
    return 3;
  }
  return null;
}

int countInSync(SyncChainSnapshot s) {
  final absSyncing = _absIsCard(s);
  final ebook = _sideIsCard(s.ebook) && s.ebook.isMember;
  final readAlong = s.readAlong.member != null;
  // The audiobook is in sync while anything hangs off it, even when this page
  // is not linked to it.
  final audiobook = s.audiobook.book != null && (s.audiobook.isMember || absSyncing || readAlong);
  return [ebook, audiobook, readAlong, absSyncing].where((v) => v).length;
}

SyncChain buildSyncChain(SyncChainSnapshot input) {
  final s = input.abs != null && !input.abs!.configured ? input._withoutAbs() : input;
  final rows = _orderedRows(s);
  final inSync = countInSync(s);
  final present = rows.whereType<ChainCardRow>().length;
  final priority = _headerPriority(s);
  final header = switch (priority) {
    1 => const SyncChainHeader(ChainTone.destructive, PositionSyncCopy.headerNeedsAttention),
    2 => const SyncChainHeader(ChainTone.warning, PositionSyncCopy.headerCheckSync),
    3 => const SyncChainHeader(ChainTone.info, PositionSyncCopy.headerLinking),
    _ => inSync >= 2
        ? SyncChainHeader(ChainTone.success, PositionSyncCopy.headerInSync(inSync, present))
        : const SyncChainHeader(ChainTone.muted, PositionSyncCopy.headerNotLinked),
  };
  return SyncChain(
    rows: rows,
    header: header,
    intro: inSync >= 2 ? PositionSyncCopy.introLinked : PositionSyncCopy.introUnlinked,
    needsAttention: priority == 1 || priority == 2 || rows.any((r) => r is ChainCardRow && r.confirm != null),
  );
}

// ─── Sync button ────────────────────────────────────────────

enum SyncButtonState { loading, notLinked, inSync, building, checkSync, needsAttention }

/// The detail icon row's button, from the chain's header tone.
SyncButtonState syncButtonState({required bool loaded, required ChainTone tone}) {
  if (!loaded) return SyncButtonState.loading;
  return switch (tone) {
    ChainTone.muted => SyncButtonState.notLinked,
    ChainTone.info => SyncButtonState.building,
    ChainTone.warning => SyncButtonState.checkSync,
    ChainTone.destructive => SyncButtonState.needsAttention,
    ChainTone.success => SyncButtonState.inSync,
  };
}

/// The button's tooltip, port of useSyncChainPanel's triggerTooltip.
String syncButtonTooltip({
  required bool linked,
  required bool audioModality,
  required ReadAlongStatus readAlongStatus,
  required bool readAlongMutating,
  required bool alignmentRunning,
  required AlignmentStatus alignmentStatus,
  required bool alignmentStale,
  required bool membersWithoutText,
}) {
  if (!linked) return audioModality ? PositionSyncCopy.tooltipNeedsText : PositionSyncCopy.tooltipNeedsAudio;
  if (readAlongStatus == ReadAlongStatus.queued) return PositionSyncCopy.tooltipReadAlongQueued;
  if (readAlongMutating || readAlongStatus == ReadAlongStatus.building) {
    return PositionSyncCopy.tooltipReadAlongBuilding;
  }
  if (alignmentRunning) return PositionSyncCopy.tooltipAligning;
  if (readAlongStatus == ReadAlongStatus.failed) return PositionSyncCopy.tooltipReadAlongFailed;
  if (alignmentStatus == AlignmentStatus.ready) {
    return alignmentStale ? PositionSyncCopy.tooltipAlignStale : PositionSyncCopy.tooltipAligned;
  }
  if (alignmentStatus == AlignmentStatus.failed) return PositionSyncCopy.tooltipAlignFailed;
  if (membersWithoutText) return PositionSyncCopy.tooltipNeedsText;
  return PositionSyncCopy.tooltipLinked;
}
