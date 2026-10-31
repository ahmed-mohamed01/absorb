// Fork-owned: the BookOrbit Position sync state model, a port of BookOrbit's
// client/src/features/book/lib/sync-chain.ts trimmed to what the sheet shows.
// One book's own files make the chain: its plain EPUB, its read-aloud EPUB
// and its audio, with Audiobookshelf hanging off the audio. Upstream's
// read-aloud sync joins the read-aloud to the audio and to the plain EPUB;
// Whisper joins the plain EPUB to the audio only in a book with no
// read-aloud. Pure Dart with no imports, so every state can be pinned by a
// unit test. See FORK_NOTES.md.

// ─── Server enums ───────────────────────────────────────────
// Shared with the wire models in bookorbit_position_sync.dart, which parse
// them from the server's strings.

enum AlignmentStatus { none, pending, building, ready, failed, unalignable }

enum AlignmentBlock { disabled, unavailable, busy }

enum ReadAloudSyncMode { auto, disabled }

enum ReadAloudSyncState { enabled, disabled, unavailable }

enum ReadAloudSyncReason { noMediaOverlayEpub, noAudioFiles, missingDuration, durationMismatch }

enum ReadAloudJobStatus { queued, processing, awaitingReview, completed, completedWithWarnings, failed, cancelled }

/// Why upstream's read-aloud generator cannot start on a book.
enum ReadAloudReason {
  workerNotConfigured,
  workerUnavailable,
  workerIncompatible,
  bookMissing,
  noEpub,
  noAudiobook,
  tooManyAudioFiles,
  singleFileLibrary,
  epubNotAllowed,
  libraryNotMounted,
  jobActive,
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
  static String tooltip(String status) => 'Position sync: $status';

  static const headerNeedsAttention = 'Needs attention';
  static const headerCheckSync = 'Check sync';
  static const headerAligning = 'Aligning';
  static String headerInSync(int n, int m) => '$n of $m in sync';
  static const headerNotSyncing = 'Not syncing';
  static const introSynced = 'Synced files keep the same position as you switch between them.';
  static const introNotSynced = "Sync this book's files to keep them at the same position.";

  static const shortEbook = 'Ebook';
  static const shortReadAlong = 'Read-aloud';
  static const shortAudiobook = 'Audiobook';
  static const shortAbs = 'ABS';
  static const kindAbs = 'Audiobookshelf';
  static const tagExternal = 'External';
  static String progressRead(int p) => '$p% read';
  static String progressListened(int p) => '$p% listened';
  static String fileSummary(String format, int count, String size) =>
      count > 1 ? '$format · $count files · $size' : '$format · $size';

  static const pillAvailable = 'Not linked';
  static const pillLinked = 'Linked';
  static const pillLinkedViaWhisper = 'Linked · via Whisper';
  static const pillAligning = 'Aligning';
  static const pillRebuilding = 'Rebuilding';
  static const pillAlignmentFailed = 'Alignment failed';
  static const pillOutOfDate = 'Out of date';
  static const pillNotAligned = 'Not aligned';
  static const pillCantAlign = "Can't align";
  static const pillCantReach = "Can't reach server";
  static const pillOneWay = 'Linked · one way';
  static const pillDiverged = 'Out of sync';

  static const syncEnabled = 'Synced';
  static const syncPartial = 'Partly synced';
  static const syncDisabled = 'Sync off';
  static const syncUnavailable = 'Sync issue';
  static const epubCopiesOnly = 'EPUB copies only';
  static const epubCopiesDescription =
      'Web reader, Kobo, and KOReader positions stay in sync across the EPUB copies. Add matching audiobook files to sync the audiobook too.';

  static const qualifierViaWhisper = 'via Whisper';
  static const qualifierDirect = 'direct';
  static const qualifierOneWay = 'one way';
  static const qualifierTwoWay = 'two way';
  static const offSyncPaused = 'sync paused';
  static const offNeedsReview = 'needs review';
  static const offNotMatched = 'not matched';
  static const offSyncOffInSettings = 'sync off in Settings';
  static const offNoReadAlong = 'no read-aloud yet';

  static const chipPaused = 'Paused';
  static const chipNeedsReview = 'Needs review';

  static const ghostNoMatchAbs = 'No match in your libraries';
  static const ghostAbsPositionSyncOff = 'Position sync is off in Settings';

  static const disabledNothingToLink = 'There is nothing to link yet.';

  static const explainWhisper =
      "Two-way. Whisper maps the audiobook's audio onto the ebook's text, so your position carries in both directions.";
  static const explainReadAlongAudio =
      "Two-way. The read-aloud narrates the audiobook's own audio, so positions map directly between them.";
  static const explainAbsTwoWay =
      'Two-way. Listening progress is exchanged with your Audiobookshelf server through its API.';
  static const explainAbsFromAbs =
      'One-way. Listening progress comes from your Audiobookshelf server through its API and nothing is sent back.';
  static const explainAbsToAbs =
      'One-way. Listening progress is sent to your Audiobookshelf server through its API and nothing is read back.';
  static const noteAligning = 'The ebook and audiobook keep their own positions until it finishes.';
  static const noteAlignmentFailed = "Whisper stopped while aligning, so the ebook and audiobook aren't syncing.";
  static const noteStale =
      "The audiobook file changed after this map was built. Syncing is paused until it's rebuilt.";
  static const noteAbsUnreachable = 'Progress catches up when Audiobookshelf is back.';
  static const noteAbsSending = 'Your newer position is on its way.';
  static const alignUnalignable = "Position sync isn't available for this ebook and audiobook.";
  static const alignIdle = 'Maps the audio to the text so your position carries between the ebook and the audiobook.';

  static const actionRetry = 'Retry';
  static const actionRebuildAlignment = 'Rebuild alignment';
  static const actionAlignNow = 'Align now';
  static const actionMatch = 'Match';
  static const actionConfirm = 'Confirm';
  static const actionChange = 'Change';
  static const actionReview = 'Review';
  static const actionModify = 'Modify';
  static const actionCancelAlignment = 'Cancel alignment';
  static const actionAbsPush = 'Send to ABS';
  static const actionAbsPull = 'Use ABS';
  static const actionAbsUseNow = 'Use it now';

  static const pauseAbsTitle = 'Stop syncing with Audiobookshelf?';
  static const pauseAbsDescription =
      'Listening progress stops syncing with your Audiobookshelf server. Nothing is removed there.';
  static const stopSyncing = 'Stop syncing';
  static const untitled = 'Untitled';

  static const toastAbsResumed = 'Syncing with Audiobookshelf.';
  static const toastAbsPaused = 'Stopped syncing with Audiobookshelf.';
  static const toastAbsChanged = 'Audiobookshelf item changed.';
  static const toastAbsFailed = "Couldn't update Audiobookshelf sync.";
  static const toastSyncCancelKeptRunning = "The position sync build couldn't be cancelled and keeps running.";
  static const toastAlignBuildFailed = 'Failed to start alignment build.';
  static const toastReadAloudSyncFailed = 'Could not update read-aloud progress sync.';
  static const toastReviewInBrowser = 'Review opens in BookOrbit.'; // local
  static const searchFailed = "Couldn't search for a match. Try again."; // local
  static const loadFailed = "Couldn't load this book's files."; // local

  static const searching = 'Searching...';
  static const noMatches = 'No matches found.';
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
  static String absLibrary(String name) => name.toLowerCase().endsWith('library') ? name : '$name library';

  static const alignmentBlocks = <AlignmentBlock, String>{
    AlignmentBlock.disabled: 'Reading alignment is turned off for this server.',
    AlignmentBlock.unavailable: "Reading alignment isn't configured on this server yet.",
    AlignmentBlock.busy: 'The server is busy aligning other books. Try again shortly.',
  };

  static const syncReasons = <ReadAloudSyncReason, String>{
    ReadAloudSyncReason.noMediaOverlayEpub: 'A read-aloud EPUB with media overlays is required.',
    ReadAloudSyncReason.noAudioFiles: 'Matching standalone audiobook files are required.',
    ReadAloudSyncReason.missingDuration: 'Audio duration metadata is incomplete.',
  };
  static String durationMismatch(String audio, String overlay) =>
      'Durations do not match closely enough: audiobook $audio, read-aloud EPUB $overlay.';

  // Upstream's read-aloud generator (book.detail.files.readAloud).
  static const slotNotCreated = 'Not created yet';
  static const createReadAloud = 'Create read-aloud';
  static const cancelReadAloud = 'Cancel generation';
  static const queuedTitle = 'Waiting to start';
  static String queueAhead(int n) => n == 0 ? 'Next in line' : (n == 1 ? '1 job ahead' : '$n jobs ahead');
  static const stoppingTitle = 'Stopping…';
  static const reviewTitle = 'Ready for review';
  static const safeToClose = 'Safe to close. Absorb shows progress on the sync button.'; // local
  static const tagCreating = 'Creating'; // local
  static const tagQueued = 'Queued'; // local
  static const tagReview = 'Review'; // local
  static const tagFailed = 'Failed'; // local

  static const reasons = <ReadAloudReason, String>{
    ReadAloudReason.workerUnavailable: 'The read-aloud worker is offline right now.',
    ReadAloudReason.workerIncompatible: 'The read-aloud worker needs an update to work with this server.',
    ReadAloudReason.bookMissing: "Restore this book's missing files to create a read-aloud.",
    ReadAloudReason.noEpub: 'Add a plain EPUB to this book to create a read-aloud.',
    ReadAloudReason.tooManyAudioFiles: 'This audiobook is split into more files than a read-aloud can be made from.',
    ReadAloudReason.epubNotAllowed: "This library doesn't accept EPUB files, so a read-aloud can't be added.",
    ReadAloudReason.libraryNotMounted: "The read-aloud worker can't reach this library's folder.",
    ReadAloudReason.jobActive: 'A read-aloud is already being created for this book.',
  };
  static const reasonNoEpubExisting = 'This book already has a read-aloud and no plain EPUB to rebuild it from.';
  static const reasonUnknown = "A read-aloud can't be created for this book right now.";

  static const stages = <String, String>{
    'queued': 'Waiting to start',
    'preparing_audio': 'Preparing the audio',
    'downloading_model': 'Downloading the speech model',
    'generating_emissions': 'Listening to the narration',
    'marking_up_ebook': 'Marking up the ebook text',
    'aligning': 'Matching the text to the narration',
    'validating': 'Checking the result',
    'awaiting_review': 'Waiting for review',
    'publishing': 'Adding the read-aloud to this book',
    'completed': 'Done',
  };
  static const stageWorking = 'Working';

  static const jobErrors = <String, String>{
    'worker_unavailable': "The read-aloud worker couldn't be reached.",
    'worker_incompatible': 'The read-aloud worker needs an update to work with this server.',
    'worker_crashed': 'The read-aloud worker stopped unexpectedly.',
    'library_not_mounted': "The read-aloud worker can't reach this library's folder.",
    'source_missing': 'A selected file is no longer available.',
    'source_changed': 'A selected file changed after the job started.',
    'invalid_source': "The selected EPUB or audiobook couldn't be read.",
    'unsupported_language': "The speech model doesn't support the selected language.",
    'insufficient_storage': "There isn't enough free disk space to finish.",
    'audio_processing_failed': "The audiobook couldn't be prepared.",
    'model_download_failed': "The speech model couldn't be downloaded.",
    'inference_failed': 'Speech recognition failed while listening to the narration.',
    'markup_failed': "The ebook text couldn't be prepared for matching.",
    'alignment_failed': "The text couldn't be matched to the narration.",
    'invalid_output': 'The generated EPUB failed its checks.',
    'publication_failed': "The generated EPUB couldn't be added to this book.",
    'review_expired': "It wasn't reviewed within 14 days.",
    'discarded': 'The read-aloud was discarded at review.',
    'cancelled': 'The job was cancelled.',
  };
  static const jobErrorUnknown = 'Something went wrong while creating the read-aloud.';

  // What a failed request says (book.detail.files.readAloud.errors).
  static const errorCreate = "The read-aloud couldn't be started. Try again.";
  static const errorCreateInvalid =
      'Some selected files are no longer on this book. Check the selection and try again.';
  static const errorCreateConflict = 'Another read-aloud is already being created for this book.';
  static const errorCreateUnavailable = 'The read-aloud worker is offline. Try again later.';
  static const errorForbidden = "You don't have permission to do that.";
  static const errorGone = 'This job no longer exists.';
  static const errorConflict = 'This job had already moved on. It now shows where it is.';
  static const errorCancel = "The job couldn't be cancelled. Try again.";
  static const errorRetry = "The job couldn't be retried. Try again.";

  // The options page, Absorb's stand-in for upstream's dialog. Local.
  static const modifyTitle = 'Create read-aloud';
  static const modifySubtitle = "BookOrbit's read-aloud worker matches the EPUB's text to the audiobook's narration.";
  static const modifyLanguage = 'Narration language';
  static const modifyLanguageNone = 'Pick the language the audiobook is narrated in.';
  static const modifyEpub = 'EPUB';
  static const modifyAudio = 'Audio';
  static String modifyAudioFiles(int n) => n == 1 ? '1 file' : '$n files';
  static const modifyGranularity = 'Highlight';
  static const granularitySentence = 'Sentence by sentence';
  static const granularityWord = 'Word by word';
  static const modifyHint = 'It can take an hour or more. Your files keep syncing meanwhile.';
}

// ─── Helpers ────────────────────────────────────────────────

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

/// Upstream's short duration, as its read-aloud sync copy shows it.
String syncDuration(double? seconds) {
  if (seconds == null) return '-';
  final total = seconds.floor();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}

// Names a book's language field may carry for the speech model's languages,
// in English and in the language itself, and their three-letter codes.
const _languageNames = <String, List<String>>{
  'ar': ['arabic', 'العربية', 'ara'],
  'ca': ['catalan', 'català', 'cat'],
  'de': ['german', 'deutsch', 'deu', 'ger'],
  'en': ['english', 'eng'],
  'es': ['spanish', 'español', 'castellano', 'spa'],
  'fo': ['faroese', 'føroyskt', 'fao'],
  'fr': ['french', 'français', 'fra', 'fre'],
  'hy': ['armenian', 'հայերեն', 'hye', 'arm'],
  'is': ['icelandic', 'íslenska', 'isl', 'ice'],
  'it': ['italian', 'italiano', 'ita'],
  'ja': ['japanese', '日本語', 'jpn'],
  'kk': ['kazakh', 'қазақ тілі', 'kaz'],
  'mt': ['maltese', 'malti', 'mlt'],
  'pl': ['polish', 'polski', 'pol'],
  'pt': ['portuguese', 'português', 'por'],
  'ru': ['russian', 'русский', 'rus'],
  'zh': ['chinese', '中文', 'zho', 'chi'],
};

/// The language subtag a book's language field names, as upstream's
/// languageSubtagOf reads it: a code such as "en" or "en-GB", or a name.
String? languageSubtag(String? value) {
  final lowered = value?.trim().toLowerCase();
  if (lowered == null || lowered.isEmpty) return null;
  for (final e in _languageNames.entries) {
    if (e.value.contains(lowered)) return e.key;
  }
  final subtag = lowered.split(RegExp(r'[-_]')).first;
  return RegExp(r'^[a-z]{2,3}$').hasMatch(subtag) ? subtag : null;
}

/// A speech model language's English name, such as "English" for "en".
String readAloudLanguageName(String code) {
  final name = _languageNames[code]?.first;
  return name == null ? code : '${name[0].toUpperCase()}${name.substring(1)}';
}

/// The narration language upstream's dialog preselects: the book's own,
/// then the reader's saved default, whichever the speech model supports
/// first.
String? readAloudLanguage(List<String> supported, String? bookLanguage, String? savedDefault) {
  for (final code in [languageSubtag(bookLanguage), savedDefault]) {
    if (code != null && supported.contains(code)) return code;
  }
  return null;
}

/// Unknown stages from a newer server read as the generic working label.
String readAloudStageLabel(String? stage) => PositionSyncCopy.stages[stage] ?? PositionSyncCopy.stageWorking;

/// A code this build does not know reads as unknown, not as a raw code.
String readAloudJobError(String? code) => PositionSyncCopy.jobErrors[code] ?? PositionSyncCopy.jobErrorUnknown;

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

/// One kind of file the book holds: its plain EPUB, its read-aloud EPUB or
/// its audio tracks.
class SyncChainEdition {
  final String? title;

  /// Such as "EPUB e-book" or "M4B audiobook".
  final String formatName;
  final int fileCount;
  final int sizeBytes;

  /// 0..100, null when nothing is recorded.
  final int? progress;
  const SyncChainEdition(
      {this.title, required this.formatName, this.fileCount = 1, this.sizeBytes = 0, this.progress});
}

class SyncChainAlignment {
  final AlignmentStatus status;
  final bool stale;
  final String? builtAt;
  final int? samplesDone;
  final int? samplesTotal;
  final AlignmentBlock? buildBlocked;
  final String? buildError;

  /// A build is queued or running, including the window between a request
  /// and the first building read.
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

/// Upstream's per-book read-aloud sync between the read-aloud EPUB, the
/// audio and any other EPUB copy.
class ReadAloudSync {
  final ReadAloudSyncMode mode;
  final ReadAloudSyncState state;
  final ReadAloudSyncReason? unavailableReason;
  final double? audioDurationSeconds;
  final double? overlayDurationSeconds;
  const ReadAloudSync({
    this.mode = ReadAloudSyncMode.auto,
    this.state = ReadAloudSyncState.unavailable,
    this.unavailableReason,
    this.audioDurationSeconds,
    this.overlayDurationSeconds,
  });
}

/// How the generator's entry stands: hidden where it can never run,
/// available, or unavailable with a reason to show.
sealed class ReadAloudEntry {
  const ReadAloudEntry();
}

class ReadAloudEntryHidden extends ReadAloudEntry {
  const ReadAloudEntryHidden();
}

class ReadAloudEntryAvailable extends ReadAloudEntry {
  const ReadAloudEntryAvailable();
}

class ReadAloudEntryUnavailable extends ReadAloudEntry {
  final ReadAloudReason? reason;
  final String message;
  const ReadAloudEntryUnavailable(this.reason, this.message);
}

/// A read-aloud job the slot follows: running, waiting for review, or
/// failed and not dismissed.
class SyncChainReadAloudJob {
  final ReadAloudJobStatus status;
  final String stage;

  /// 0..100 for the current run.
  final double progress;
  final int? queuePosition;

  /// A cancel was asked for and the worker has not stopped yet.
  final bool stopping;
  final bool canCancel;
  final bool canRetry;

  /// Upstream's error text for a failed job.
  final String? error;
  const SyncChainReadAloudJob({
    required this.status,
    this.stage = 'queued',
    this.progress = 0,
    this.queuePosition,
    this.stopping = false,
    this.canCancel = false,
    this.canRetry = false,
    this.error,
  });
}

enum ReadAloudPending { create, cancel, retry, other }

/// Upstream's read-aloud generator as the slot sees it, for a book with a
/// plain EPUB and audio and no read-aloud.
class SyncChainReadAloudSlot {
  final ReadAloudEntry entry;
  final SyncChainReadAloudJob? job;

  /// The job action in flight, which locks the slot's buttons.
  final ReadAloudPending? pending;

  /// The last failed start or job action, shown in place of the note.
  final String? error;
  const SyncChainReadAloudSlot({this.entry = const ReadAloudEntryHidden(), this.job, this.pending, this.error});
}

class AbsLink {
  final String absLibraryItemId;
  final String? title;
  final String? libraryName;
  final AbsDirection direction;
  final bool syncing;
  final AbsPausedReason? pausedReason;
  const AbsLink({
    required this.absLibraryItemId,
    this.title,
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

class SyncChainSnapshot {
  final int bookId;
  final String? coverVersion;
  final SyncChainEdition? ebook;
  final SyncChainEdition? audiobook;
  final SyncChainEdition? readAlong;
  final SyncChainReadAloudSlot readAloudSlot;
  final SyncChainAlignment alignment;
  final ReadAloudSync readAloud;

  /// Null without the Audiobookshelf sync permission.
  final SyncChainAbs? abs;

  /// May build and cancel the Whisper alignment.
  final bool canAlign;
  const SyncChainSnapshot({
    required this.bookId,
    this.coverVersion,
    this.ebook,
    this.audiobook,
    this.readAlong,
    this.readAloudSlot = const SyncChainReadAloudSlot(),
    this.alignment = const SyncChainAlignment(),
    this.readAloud = const ReadAloudSync(),
    this.abs,
    this.canAlign = false,
  });

  SyncChainSnapshot _withoutAbs() => SyncChainSnapshot(
        bookId: bookId,
        coverVersion: coverVersion,
        ebook: ebook,
        audiobook: audiobook,
        readAlong: readAlong,
        readAloudSlot: readAloudSlot,
        alignment: alignment,
        readAloud: readAloud,
        canAlign: canAlign,
      );

  SyncChainEdition? edition(SyncEdition e) => switch (e) {
        SyncEdition.ebook => ebook,
        SyncEdition.readAlong => readAlong,
        SyncEdition.audiobook => audiobook,
        SyncEdition.abs => null,
      };
}

// ─── Rows ───────────────────────────────────────────────────

enum ChainActionId {
  cancelAlignment,
  retryAlignment,
  alignNow,
  rebuildAlignment,
  enableReadAloudSync,
  disableReadAloudSync,
  createReadAloud,
  modifyReadAloud,
  cancelReadAloud,
  retryReadAloud,
  reviewReadAloud,
  change,
  retryAbs,
  absPush,
  absPull,
  confirmAbs,
  resumeAbs,
  pauseAbs,
}

class ChainAction {
  final ChainActionId id;
  final String label;
  final bool disabled;
  const ChainAction(this.id, this.label, {this.disabled = false});

  ChainAction lockedIf(bool locked) => locked && !disabled ? ChainAction(id, label, disabled: true) : this;
}

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

sealed class ChainRow {
  const ChainRow();
}

class ChainCardRow extends ChainRow {
  final SyncEdition edition;
  final ChainFrame frame;
  final ChainCover cover;
  final String? title;

  /// The file summary for a file, the library for the Audiobookshelf item.
  final String? subtitle;
  final bool external;
  final int? progress;

  /// The live check is still running.
  final bool progressPending;

  /// A paused Audiobookshelf match is drawn dashed; every file of the book
  /// is a full card.
  final bool linked;

  /// Why the dashed card is not syncing.
  final String? chip;

  /// Change, for the Audiobookshelf match.
  final bool change;

  /// Confirm on an Audiobookshelf match that needs review.
  final ChainAction? confirm;
  const ChainCardRow({
    required this.edition,
    required this.frame,
    required this.cover,
    this.title,
    this.subtitle,
    this.external = false,
    this.progress,
    this.progressPending = false,
    this.linked = true,
    this.chip,
    this.change = false,
    this.confirm,
  });
}

class ChainGhostRow extends ChainRow {
  final SyncEdition edition;
  final ChainFrame frame;
  final String label;
  final String note;

  /// At most one: Match, which opens the Change page.
  final ChainAction? action;
  const ChainGhostRow({required this.edition, required this.frame, required this.label, required this.note, this.action});
}

enum ReadAloudSlotVariant { notCreated, unavailable, queued, processing, review, failed }

class ChainReadAloudSlotRow extends ChainRow {
  final ReadAloudSlotVariant variant;
  final String note;

  /// Create, Retry or Review.
  final ChainAction? action;

  /// Modify beside Create, Review beside Retry.
  final ChainAction? secondary;

  /// The red X for a job in flight.
  final ChainAction? cancel;

  /// The action whose request is in flight, which spins.
  final ChainActionId? pending;

  /// Queued or processing: the stage and its percent (null while queued).
  final ({String stage, int? percent})? progress;
  const ChainReadAloudSlotRow({
    required this.variant,
    required this.note,
    this.action,
    this.secondary,
    this.cancel,
    this.pending,
    this.progress,
  });
}

enum ConnectorKey { ebookReadAlong, readAlongAudiobook, ebookAudiobook, audiobookAbs }

enum ConnectorState {
  aligning,
  rebuilding,
  alignmentFailed,
  outOfDate,
  cantAlign,
  alignmentBlocked,
  notAligned,
  linkedViaWhisper,
  readAloudSynced,
  readAloudPartial,
  readAloudIssue,
  epubCopiesSynced,
  available,
  absUnreachable,
  absDiverged,
  absReceiving,
  absSending,
  absOneWay,
  absLinked,
}

class ChainSwitch {
  final bool on;
  final bool disabled;

  /// What turning it on runs, and what turning it off runs (or the confirm
  /// it opens).
  final ChainActionId? onAction;
  final ChainActionId? offAction;
  const ChainSwitch({required this.on, this.disabled = false, this.onAction, this.offAction});
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

  /// Muted text after the pair label: "via Whisper" when synced, "sync off"
  /// when off.
  final String? qualifier;
  final String? explainer;

  /// Null when the pair has no switch, and the rail runs through.
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

enum _AlignmentState { aligning, rebuilding, alignmentFailed, outOfDate, cantAlign, alignmentBlocked, notAligned, ready }

_AlignmentState _alignmentState(SyncChainAlignment a) {
  if (a.running || a.status == AlignmentStatus.pending || a.status == AlignmentStatus.building) {
    return a.builtAt == null ? _AlignmentState.aligning : _AlignmentState.rebuilding;
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

/// Upstream's read-aloud sync owns text and audio wherever the book has a
/// read-aloud, so Whisper fills in only without one.
bool usesWhisper(SyncChainSnapshot s) => s.ebook != null && s.audiobook != null && s.readAlong == null;

bool _hasReadAloudPair(SyncChainSnapshot s) => s.readAlong != null && s.audiobook != null;

/// Upstream counts any second EPUB beside the read-aloud as a copy it keeps
/// in step through the narration.
bool _hasEpubCopy(SyncChainSnapshot s) => s.readAlong != null && (s.ebook != null || s.readAlong!.fileCount > 1);

/// Upstream's "EPUB copies only": the audiobook half is unavailable, but the
/// EPUB copies still sync.
bool _syncsEpubCopiesOnly(SyncChainSnapshot s) {
  final sync = s.readAloud;
  return sync.state == ReadAloudSyncState.unavailable &&
      sync.unavailableReason != ReadAloudSyncReason.noMediaOverlayEpub &&
      _hasEpubCopy(s);
}

bool _absIsCard(SyncChainSnapshot s) => s.abs?.link?.syncing == true && s.audiobook != null;

// Cards and ghosts.

String _formatBytes(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}

ChainCardRow _fileCard(SyncChainSnapshot s, SyncEdition edition, SyncChainEdition file) => ChainCardRow(
      edition: edition,
      frame: edition == SyncEdition.audiobook ? ChainFrame.group : ChainFrame.spine,
      cover: BookCover(s.bookId, s.coverVersion),
      title: file.title,
      subtitle: PositionSyncCopy.fileSummary(file.formatName, file.fileCount, _formatBytes(file.sizeBytes)),
      progress: file.progress,
    );

ChainGhostRow _ghostRow(SyncEdition edition, ChainFrame frame, String note, {ChainAction? action}) => ChainGhostRow(
      edition: edition,
      frame: frame,
      label: edition == SyncEdition.abs ? PositionSyncCopy.kindAbs : editionShortName(edition),
      note: note,
      action: action,
    );

ChainCardRow _absCard(SyncChainAbs abs, AbsLink link) {
  final live = abs.live;
  final linked = link.syncing;
  final needsReview = !linked && link.pausedReason == AbsPausedReason.needsReview;
  return ChainCardRow(
    edition: SyncEdition.abs,
    frame: ChainFrame.group,
    cover: AbsCover(link.absLibraryItemId),
    title: link.title,
    subtitle: link.libraryName == null ? null : PositionSyncCopy.absLibrary(link.libraryName!),
    external: true,
    progress: live == null ? null : displayPercentage(live.progressPercentage, live.progressFinished),
    progressPending: abs.checking,
    linked: linked,
    chip: linked ? null : (needsReview ? PositionSyncCopy.chipNeedsReview : PositionSyncCopy.chipPaused),
    change: true,
    confirm: needsReview ? const ChainAction(ChainActionId.confirmAbs, PositionSyncCopy.actionConfirm) : null,
  );
}

ChainRow _absSlot(SyncChainAbs abs) {
  final link = abs.link;
  if (link == null) {
    return _ghostRow(SyncEdition.abs, ChainFrame.group, PositionSyncCopy.ghostNoMatchAbs,
        action: const ChainAction(ChainActionId.change, PositionSyncCopy.actionMatch));
  }
  if (link.pausedReason == AbsPausedReason.positionSyncOff) {
    return _ghostRow(SyncEdition.abs, ChainFrame.group, PositionSyncCopy.ghostAbsPositionSyncOff);
  }
  return _absCard(abs, link);
}

// Connectors.

ConnectorKey _connectorKey(SyncEdition from, SyncEdition to) => switch ((from, to)) {
      (SyncEdition.ebook, SyncEdition.readAlong) => ConnectorKey.ebookReadAlong,
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
      disabledReason: disabledReason,
      note: note,
      detail: detail,
      actions: actions,
      cancel: cancel,
      ticks: ticks,
      absDetails: absDetails,
    );

ChainAction? _alignAction(SyncChainSnapshot s, ChainActionId id, String label) =>
    s.canAlign ? ChainAction(id, label) : null;

List<ChainAction> _present(List<ChainAction?> actions) => [for (final a in actions) if (a != null) a];

ChainConnectorRow _alignmentConnector(SyncChainSnapshot s) {
  final a = s.alignment;
  final ticks = (done: a.samplesDone, total: a.samplesTotal);
  const from = SyncEdition.ebook;
  const to = SyncEdition.audiobook;
  switch (_alignmentState(a)) {
    case _AlignmentState.aligning:
      return _connectorRow(from, to,
          state: ConnectorState.aligning,
          tone: ChainTone.info,
          pill: PositionSyncCopy.pillAligning,
          note: PositionSyncCopy.noteAligning,
          cancel: _alignAction(s, ChainActionId.cancelAlignment, PositionSyncCopy.actionCancelAlignment),
          ticks: ticks,
          explainer: PositionSyncCopy.explainWhisper);
    case _AlignmentState.rebuilding:
      return _connectorRow(from, to,
          state: ConnectorState.rebuilding,
          tone: ChainTone.info,
          pill: PositionSyncCopy.pillRebuilding,
          cancel: _alignAction(s, ChainActionId.cancelAlignment, PositionSyncCopy.actionCancelAlignment),
          ticks: ticks,
          explainer: PositionSyncCopy.explainWhisper);
    case _AlignmentState.alignmentFailed:
      return _connectorRow(from, to,
          state: ConnectorState.alignmentFailed,
          tone: ChainTone.destructive,
          pill: PositionSyncCopy.pillAlignmentFailed,
          note: PositionSyncCopy.noteAlignmentFailed,
          detail: a.buildError,
          actions: _present([_alignAction(s, ChainActionId.retryAlignment, PositionSyncCopy.actionRetry)]));
    case _AlignmentState.outOfDate:
      return _connectorRow(from, to,
          state: ConnectorState.outOfDate,
          tone: ChainTone.warning,
          pill: PositionSyncCopy.pillOutOfDate,
          note: PositionSyncCopy.noteStale,
          actions: _present([_alignAction(s, ChainActionId.rebuildAlignment, PositionSyncCopy.actionRebuildAlignment)]),
          explainer: PositionSyncCopy.explainWhisper);
    case _AlignmentState.cantAlign:
      return _connectorRow(from, to,
          state: ConnectorState.cantAlign,
          tone: ChainTone.muted,
          pill: PositionSyncCopy.pillCantAlign,
          note: PositionSyncCopy.alignUnalignable);
    case _AlignmentState.alignmentBlocked:
      return _connectorRow(from, to,
          state: ConnectorState.alignmentBlocked,
          tone: ChainTone.muted,
          pill: PositionSyncCopy.pillNotAligned,
          note: PositionSyncCopy.alignmentBlocks[a.buildBlocked]);
    case _AlignmentState.notAligned:
      return _connectorRow(from, to,
          state: ConnectorState.notAligned,
          tone: ChainTone.muted,
          pill: PositionSyncCopy.pillNotAligned,
          note: a.buildBlocked == AlignmentBlock.busy
              ? PositionSyncCopy.alignmentBlocks[AlignmentBlock.busy]
              : PositionSyncCopy.alignIdle,
          actions: _present([_alignAction(s, ChainActionId.alignNow, PositionSyncCopy.actionAlignNow)]),
          explainer: PositionSyncCopy.explainWhisper);
    case _AlignmentState.ready:
      return _connectorRow(from, to,
          state: ConnectorState.linkedViaWhisper,
          tone: ChainTone.success,
          pill: PositionSyncCopy.pillLinkedViaWhisper,
          qualifier: PositionSyncCopy.qualifierViaWhisper,
          explainer: PositionSyncCopy.explainWhisper);
  }
}

String _readAloudReason(ReadAloudSync sync) {
  final reason = sync.unavailableReason ?? ReadAloudSyncReason.missingDuration;
  if (reason == ReadAloudSyncReason.durationMismatch) {
    return PositionSyncCopy.durationMismatch(
        syncDuration(sync.audioDurationSeconds), syncDuration(sync.overlayDurationSeconds));
  }
  return PositionSyncCopy.syncReasons[reason]!;
}

ChainSwitch _readAloudToggle(ReadAloudSync sync) => ChainSwitch(
      on: sync.mode != ReadAloudSyncMode.disabled,
      onAction: ChainActionId.enableReadAloudSync,
      offAction: ChainActionId.disableReadAloudSync,
    );

/// Upstream's per-book read-aloud sync: the switch flips its mode, whatever
/// state the pair is in.
ChainConnectorRow _readAloudConnector(SyncChainSnapshot s) {
  final sync = s.readAloud;
  final toggle = _readAloudToggle(sync);
  const from = SyncEdition.readAlong;
  const to = SyncEdition.audiobook;
  if (sync.state == ReadAloudSyncState.disabled) {
    return _connectorRow(from, to,
        state: ConnectorState.available,
        tone: ChainTone.muted,
        pill: PositionSyncCopy.syncDisabled,
        qualifier: PositionSyncCopy.syncDisabled,
        explainer: PositionSyncCopy.explainReadAlongAudio,
        toggle: toggle);
  }
  // With a plain EPUB on the spine its own connector shows the copies
  // syncing; this one is then only the audio half.
  if (_syncsEpubCopiesOnly(s) && s.ebook == null) {
    return _connectorRow(from, to,
        state: ConnectorState.readAloudPartial,
        tone: ChainTone.warning,
        pill: PositionSyncCopy.syncPartial,
        explainer: PositionSyncCopy.epubCopiesDescription,
        toggle: toggle,
        note: _readAloudReason(sync));
  }
  if (sync.state == ReadAloudSyncState.unavailable) {
    return _connectorRow(from, to,
        state: ConnectorState.readAloudIssue,
        tone: ChainTone.warning,
        pill: PositionSyncCopy.syncUnavailable,
        toggle: toggle,
        note: _readAloudReason(sync));
  }
  return _connectorRow(from, to,
      state: ConnectorState.readAloudSynced,
      tone: ChainTone.success,
      pill: PositionSyncCopy.syncEnabled,
      qualifier: PositionSyncCopy.qualifierDirect,
      explainer: PositionSyncCopy.explainReadAlongAudio,
      toggle: toggle);
}

/// Upstream's read-aloud sync keeps the plain EPUB in step with the
/// read-aloud through its narration, with or without audio.
ChainConnectorRow _epubCopiesConnector(SyncChainSnapshot s) {
  final sync = s.readAloud;
  final toggle = _readAloudToggle(sync);
  const from = SyncEdition.ebook;
  const to = SyncEdition.readAlong;
  if (sync.state == ReadAloudSyncState.disabled) {
    return _connectorRow(from, to,
        state: ConnectorState.available,
        tone: ChainTone.muted,
        pill: PositionSyncCopy.syncDisabled,
        qualifier: PositionSyncCopy.syncDisabled,
        explainer: PositionSyncCopy.epubCopiesDescription,
        toggle: toggle);
  }
  if (sync.state == ReadAloudSyncState.unavailable && !_syncsEpubCopiesOnly(s)) {
    return _connectorRow(from, to,
        state: ConnectorState.readAloudIssue,
        tone: ChainTone.warning,
        pill: PositionSyncCopy.syncUnavailable,
        toggle: toggle,
        note: _readAloudReason(sync));
  }
  return _connectorRow(from, to,
      state: ConnectorState.epubCopiesSynced,
      tone: ChainTone.success,
      pill: PositionSyncCopy.syncEnabled,
      // "EPUB copies only" is upstream's word for the copies syncing without
      // the audio half.
      qualifier: s.audiobook != null && !_syncsEpubCopiesOnly(s)
          ? PositionSyncCopy.qualifierDirect
          : PositionSyncCopy.epubCopiesOnly,
      explainer: PositionSyncCopy.epubCopiesDescription,
      toggle: toggle);
}

/// Leads into the read-aloud slot: nothing to sync yet, so a dashed rail
/// with no switch.
ChainConnectorRow _noReadAlongConnector() => _connectorRow(SyncEdition.readAlong, SyncEdition.audiobook,
    state: ConnectorState.available,
    tone: ChainTone.muted,
    pill: PositionSyncCopy.offNoReadAlong,
    qualifier: PositionSyncCopy.offNoReadAlong,
    explainer: PositionSyncCopy.explainReadAlongAudio);

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

ChainConnectorRow _absLinkedConnector(SyncChainAbs abs, AbsLink link) {
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
      toggle: const ChainSwitch(on: true, offAction: ChainActionId.pauseAbs),
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

ChainConnectorRow _absOffConnector(AbsLink? link) {
  ChainConnectorRow off(String qualifier, ChainActionId? onAction, String? reason) =>
      _connectorRow(SyncEdition.audiobook, SyncEdition.abs,
          state: ConnectorState.available,
          tone: ChainTone.muted,
          frame: ChainFrame.group,
          arrow: link != null ? _absArrow(link.direction) : ChainArrow.both,
          pill: PositionSyncCopy.pillAvailable,
          qualifier: qualifier,
          explainer: link != null ? _absExplain(link.direction) : null,
          toggle: ChainSwitch(on: false, disabled: reason != null, onAction: onAction),
          disabledReason: reason);
  if (link?.pausedReason == AbsPausedReason.positionSyncOff) {
    return off(PositionSyncCopy.offSyncOffInSettings, null, PositionSyncCopy.offSyncOffInSettings);
  }
  if (link == null) return off(PositionSyncCopy.offNotMatched, null, PositionSyncCopy.disabledNothingToLink);
  return link.pausedReason == AbsPausedReason.needsReview
      ? off(PositionSyncCopy.offNeedsReview, ChainActionId.confirmAbs, null)
      : off(PositionSyncCopy.offSyncPaused, ChainActionId.resumeAbs, null);
}

ChainConnectorRow _absConnector(SyncChainSnapshot s, SyncChainAbs abs) {
  final link = abs.link;
  return _absIsCard(s) && link != null ? _absLinkedConnector(abs, link) : _absOffConnector(link);
}

// Order: ebook, read-aloud, the audio group, so each upstream pair sits side
// by side. Without a read-aloud the ebook meets the audio through Whisper and
// the read-aloud slot trails the audio group. A connector only joins two
// files that are both there.

List<ChainRow> _audioGroup(SyncChainSnapshot s, SyncChainEdition audiobook) {
  final abs = s.abs;
  return [
    _fileCard(s, SyncEdition.audiobook, audiobook),
    if (abs != null) ...[_absConnector(s, abs), _absSlot(abs)],
  ];
}

// Read-aloud slot.

const _pendingAction = <ReadAloudPending, ChainActionId?>{
  ReadAloudPending.create: ChainActionId.createReadAloud,
  ReadAloudPending.cancel: ChainActionId.cancelReadAloud,
  ReadAloudPending.retry: ChainActionId.retryReadAloud,
  ReadAloudPending.other: null,
};

ChainReadAloudSlotRow _slotRow(
  SyncChainReadAloudSlot slot, {
  required ReadAloudSlotVariant variant,
  required String note,
  ChainAction? action,
  ChainAction? secondary,
  ChainAction? cancel,
  ({String stage, int? percent})? progress,
}) {
  final locked = slot.pending != null;
  return ChainReadAloudSlotRow(
    variant: variant,
    note: slot.error ?? note,
    action: action?.lockedIf(locked),
    secondary: secondary?.lockedIf(locked),
    cancel: cancel?.lockedIf(locked),
    pending: slot.pending == null ? null : _pendingAction[slot.pending],
    progress: progress,
  );
}

ChainReadAloudSlotRow _jobSlot(SyncChainReadAloudSlot slot, SyncChainReadAloudJob job) {
  final cancel = job.canCancel && !job.stopping
      ? const ChainAction(ChainActionId.cancelReadAloud, PositionSyncCopy.cancelReadAloud)
      : null;
  const review = ChainAction(ChainActionId.reviewReadAloud, PositionSyncCopy.actionReview);
  switch (job.status) {
    case ReadAloudJobStatus.queued:
      return _slotRow(slot,
          variant: ReadAloudSlotVariant.queued,
          note: job.stopping
              ? PositionSyncCopy.stoppingTitle
              : job.queuePosition == null
                  ? PositionSyncCopy.queuedTitle
                  : PositionSyncCopy.queueAhead(job.queuePosition!),
          cancel: cancel,
          progress: (stage: job.stage, percent: null));
    case ReadAloudJobStatus.processing:
      return _slotRow(slot,
          variant: ReadAloudSlotVariant.processing,
          note: job.stopping ? PositionSyncCopy.stoppingTitle : readAloudStageLabel(job.stage),
          cancel: cancel,
          progress: (stage: job.stage, percent: job.progress.clamp(0, 100).round()));
    case ReadAloudJobStatus.awaitingReview:
      return _slotRow(slot, variant: ReadAloudSlotVariant.review, note: PositionSyncCopy.reviewTitle, action: review);
    default:
      final retry = job.canRetry ? const ChainAction(ChainActionId.retryReadAloud, PositionSyncCopy.actionRetry) : null;
      return _slotRow(slot,
          variant: ReadAloudSlotVariant.failed,
          note: job.error ?? PositionSyncCopy.jobErrorUnknown,
          action: retry ?? review,
          secondary: retry != null ? review : null);
  }
}

/// Upstream hides its entry when the generator can never run here; a job it
/// already holds still shows.
ChainReadAloudSlotRow? _readAloudSlot(SyncChainSnapshot s) {
  final slot = s.readAloudSlot;
  final job = slot.job;
  if (job != null) return _jobSlot(slot, job);
  final entry = slot.entry;
  if (entry is ReadAloudEntryAvailable) {
    return _slotRow(slot,
        variant: ReadAloudSlotVariant.notCreated,
        note: PositionSyncCopy.slotNotCreated,
        action: const ChainAction(ChainActionId.createReadAloud, PositionSyncCopy.createReadAloud),
        secondary: const ChainAction(ChainActionId.modifyReadAloud, PositionSyncCopy.actionModify));
  }
  if (entry is ReadAloudEntryUnavailable && entry.reason != ReadAloudReason.jobActive) {
    return _slotRow(slot, variant: ReadAloudSlotVariant.unavailable, note: entry.message);
  }
  return null;
}

List<ChainRow> _readAloudSlotRows(SyncChainSnapshot s) {
  if (s.ebook == null || s.audiobook == null || s.readAlong != null) return const [];
  final slot = _readAloudSlot(s);
  return slot != null ? [_noReadAlongConnector(), slot] : const [];
}

List<ChainRow> _withReadAlong(SyncChainSnapshot s, SyncChainEdition readAlong) {
  final ebook = s.ebook;
  final audiobook = s.audiobook;
  return [
    if (ebook != null) ...[_fileCard(s, SyncEdition.ebook, ebook), _epubCopiesConnector(s)],
    _fileCard(s, SyncEdition.readAlong, readAlong),
    if (audiobook != null) ...[_readAloudConnector(s), ..._audioGroup(s, audiobook)],
  ];
}

List<ChainRow> _orderedRows(SyncChainSnapshot s) {
  final readAlong = s.readAlong;
  if (readAlong != null) return _withReadAlong(s, readAlong);
  final ebook = s.ebook;
  final audiobook = s.audiobook;
  return [
    if (ebook != null) _fileCard(s, SyncEdition.ebook, ebook),
    if (audiobook != null) ...[
      if (ebook != null) _alignmentConnector(s),
      ..._audioGroup(s, audiobook),
    ],
    ..._readAloudSlotRows(s),
  ];
}

// Header.

bool _copiesOnlyWithoutAudio(SyncChainSnapshot s) => s.audiobook == null && _syncsEpubCopiesOnly(s);

int? _headerPriority(SyncChainSnapshot s) {
  final align = usesWhisper(s) ? _alignmentState(s.alignment) : null;
  final link = s.abs?.link;
  final abs = _absIsCard(s) && link != null ? _absState(link, s.abs!.live) : null;
  final readAloudIssue = s.readAlong != null &&
      (s.audiobook != null || s.ebook != null) &&
      s.readAloud.state == ReadAloudSyncState.unavailable &&
      !_copiesOnlyWithoutAudio(s);
  if (align == _AlignmentState.alignmentFailed) return 1;
  if (align == _AlignmentState.outOfDate ||
      readAloudIssue ||
      abs == ConnectorState.absUnreachable ||
      abs == ConnectorState.absDiverged) {
    return 2;
  }
  if (align == _AlignmentState.aligning || align == _AlignmentState.rebuilding) return 3;
  return null;
}

int countInSync(SyncChainSnapshot s) {
  final pair = usesWhisper(s) && _alignmentState(s.alignment) == _AlignmentState.ready;
  final readAloudAudio = _hasReadAloudPair(s) && s.readAloud.state == ReadAloudSyncState.enabled;
  final copies = s.ebook != null &&
      s.readAlong != null &&
      (s.readAloud.state == ReadAloudSyncState.enabled || _syncsEpubCopiesOnly(s));
  final abs = _absIsCard(s);
  final ebook = pair || copies;
  final audiobook = pair || readAloudAudio || abs;
  final readAlong = readAloudAudio || copies;
  return [ebook, audiobook, readAlong, abs].where((v) => v).length;
}

SyncChain buildSyncChain(SyncChainSnapshot input) {
  final s = input.abs != null && (!input.abs!.configured || input.audiobook == null) ? input._withoutAbs() : input;
  final rows = _orderedRows(s);
  final inSync = countInSync(s);
  final present = rows.whereType<ChainCardRow>().length;
  final priority = _headerPriority(s);
  final header = switch (priority) {
    1 => const SyncChainHeader(ChainTone.destructive, PositionSyncCopy.headerNeedsAttention),
    2 => const SyncChainHeader(ChainTone.warning, PositionSyncCopy.headerCheckSync),
    3 => const SyncChainHeader(ChainTone.info, PositionSyncCopy.headerAligning),
    _ => inSync >= 2
        ? SyncChainHeader(ChainTone.success, PositionSyncCopy.headerInSync(inSync, present))
        : const SyncChainHeader(ChainTone.muted, PositionSyncCopy.headerNotSyncing),
  };
  return SyncChain(
    rows: rows,
    header: header,
    intro: inSync >= 2 ? PositionSyncCopy.introSynced : PositionSyncCopy.introNotSynced,
    needsAttention: priority == 1 || priority == 2 || rows.any((r) => r is ChainCardRow && r.confirm != null),
  );
}

// ─── Sync button ────────────────────────────────────────────

enum SyncButtonState { loading, notLinked, inSync, building, checkSync, needsAttention }

/// The detail page's button, from the chain's header tone. A read-aloud
/// being created shows the building ring too, though upstream's header
/// leaves it out.
SyncButtonState syncButtonState({required bool loaded, required ChainTone tone, bool creating = false}) {
  if (!loaded) return SyncButtonState.loading;
  return switch (tone) {
    ChainTone.destructive => SyncButtonState.needsAttention,
    ChainTone.warning => SyncButtonState.checkSync,
    ChainTone.info => SyncButtonState.building,
    _ when creating => SyncButtonState.building,
    ChainTone.muted => SyncButtonState.notLinked,
    ChainTone.success => SyncButtonState.inSync,
  };
}
