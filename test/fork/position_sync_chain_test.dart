import 'package:absorb/services/fork/position_sync_chain.dart';
import 'package:flutter_test/flutter_test.dart';

const _ebook = SyncChainEdition(title: 'Anathem', formatName: 'EPUB e-book', sizeBytes: 2 << 20, progress: 41);
const _audio = SyncChainEdition(title: 'Anathem', formatName: 'M4B audiobook', fileCount: 3, sizeBytes: 500 << 20, progress: 34);
const _readAlong = SyncChainEdition(title: 'Anathem', formatName: 'Read-aloud EPUB', sizeBytes: 9 << 20, progress: 20);
const _ready = SyncChainAlignment(status: AlignmentStatus.ready, builtAt: '2026-01-01');
const _synced = ReadAloudSync(mode: ReadAloudSyncMode.auto, state: ReadAloudSyncState.enabled);

SyncChainSnapshot snap({
  SyncChainEdition? ebook,
  SyncChainEdition? audiobook,
  SyncChainEdition? readAlong,
  SyncChainReadAloudSlot slot = const SyncChainReadAloudSlot(),
  SyncChainAlignment alignment = const SyncChainAlignment(),
  ReadAloudSync readAloud = const ReadAloudSync(),
  SyncChainAbs? abs,
  bool canAlign = true,
}) =>
    SyncChainSnapshot(
      bookId: 7,
      ebook: ebook,
      audiobook: audiobook,
      readAlong: readAlong,
      readAloudSlot: slot,
      alignment: alignment,
      readAloud: readAloud,
      abs: abs,
      canAlign: canAlign,
    );

T only<T>(SyncChain chain) => chain.rows.whereType<T>().single;

ChainConnectorRow connector(SyncChain chain, ConnectorKey key) =>
    chain.rows.whereType<ChainConnectorRow>().firstWhere((r) => r.key == key);

String kinds(SyncChain chain) => chain.rows
    .map((r) => switch (r) {
          ChainCardRow c => 'card:${c.edition.name}',
          ChainGhostRow g => 'ghost:${g.edition.name}',
          ChainConnectorRow c => 'link:${c.from.name}-${c.to.name}',
          ChainReadAloudSlotRow _ => 'slot',
        })
    .join(' ');

void main() {
  group('Whisper between the plain EPUB and the audio', () {
    test('an aligned pair is in sync', () {
      final chain = buildSyncChain(snap(ebook: _ebook, audiobook: _audio, alignment: _ready));
      expect(kinds(chain), 'card:ebook link:ebook-audiobook card:audiobook');
      final link = connector(chain, ConnectorKey.ebookAudiobook);
      expect(link.state, ConnectorState.linkedViaWhisper);
      expect(link.tone, ChainTone.success);
      expect(link.toggle, isNull, reason: 'Whisper has no switch of its own');
      expect(chain.header.label, '2 of 2 in sync');
      expect(chain.header.tone, ChainTone.success);
      expect(chain.intro, PositionSyncCopy.introSynced);
    });

    test('every file card is this book, with its file summary', () {
      final chain = buildSyncChain(snap(ebook: _ebook, audiobook: _audio, alignment: _ready));
      final cards = chain.rows.whereType<ChainCardRow>().toList();
      expect(cards.map((c) => (c.cover as BookCover).bookId), [7, 7]);
      expect(cards[0].subtitle, 'EPUB e-book · 2.0 MB');
      expect(cards[1].subtitle, 'M4B audiobook · 3 files · 500.0 MB');
      expect(cards[1].frame, ChainFrame.group);
      expect(cards.every((c) => c.linked), isTrue);
    });

    test('not aligned offers Align now only to a reader who may', () {
      final chain = buildSyncChain(snap(ebook: _ebook, audiobook: _audio));
      final link = connector(chain, ConnectorKey.ebookAudiobook);
      expect(link.state, ConnectorState.notAligned);
      expect(link.actions.map((a) => a.id), [ChainActionId.alignNow]);
      expect(chain.header.tone, ChainTone.muted);
      expect(chain.header.label, PositionSyncCopy.headerNotSyncing);
      final readOnly = buildSyncChain(snap(ebook: _ebook, audiobook: _audio, canAlign: false));
      expect(connector(readOnly, ConnectorKey.ebookAudiobook).actions, isEmpty);
    });

    test('a busy server says so, a disabled one blocks', () {
      final busy = connector(
          buildSyncChain(snap(ebook: _ebook, audiobook: _audio, alignment: const SyncChainAlignment(buildBlocked: AlignmentBlock.busy))),
          ConnectorKey.ebookAudiobook);
      expect(busy.state, ConnectorState.notAligned);
      expect(busy.note, PositionSyncCopy.alignmentBlocks[AlignmentBlock.busy]);
      final off = connector(
          buildSyncChain(
              snap(ebook: _ebook, audiobook: _audio, alignment: const SyncChainAlignment(buildBlocked: AlignmentBlock.disabled))),
          ConnectorKey.ebookAudiobook);
      expect(off.state, ConnectorState.alignmentBlocked);
      expect(off.actions, isEmpty);
    });

    test('aligning shows ticks and a cancel, and heads the chain', () {
      final chain = buildSyncChain(snap(
          ebook: _ebook,
          audiobook: _audio,
          alignment: const SyncChainAlignment(status: AlignmentStatus.building, samplesDone: 3, samplesTotal: 10)));
      final link = connector(chain, ConnectorKey.ebookAudiobook);
      expect(link.state, ConnectorState.aligning);
      expect(link.ticks, (done: 3, total: 10));
      expect(link.cancel?.id, ChainActionId.cancelAlignment);
      expect(chain.header.tone, ChainTone.info);
      expect(chain.header.label, PositionSyncCopy.headerAligning);
    });

    test('a rebuild of a built map reads Rebuilding', () {
      final link = connector(
          buildSyncChain(snap(
              ebook: _ebook,
              audiobook: _audio,
              alignment: const SyncChainAlignment(status: AlignmentStatus.ready, builtAt: 'x', running: true))),
          ConnectorKey.ebookAudiobook);
      expect(link.state, ConnectorState.rebuilding);
    });

    test('a failure needs attention, a stale map wants checking', () {
      final failed = buildSyncChain(snap(
          ebook: _ebook, audiobook: _audio, alignment: const SyncChainAlignment(status: AlignmentStatus.failed, buildError: 'boom')));
      final link = connector(failed, ConnectorKey.ebookAudiobook);
      expect(link.state, ConnectorState.alignmentFailed);
      expect(link.detail, 'boom');
      expect(link.actions.map((a) => a.id), [ChainActionId.retryAlignment]);
      expect(failed.header.tone, ChainTone.destructive);
      expect(failed.needsAttention, isTrue);
      final stale = buildSyncChain(snap(
          ebook: _ebook,
          audiobook: _audio,
          alignment: const SyncChainAlignment(status: AlignmentStatus.ready, builtAt: 'x', stale: true)));
      expect(connector(stale, ConnectorKey.ebookAudiobook).actions.map((a) => a.id), [ChainActionId.rebuildAlignment]);
      expect(stale.header.tone, ChainTone.warning);
      expect(stale.header.label, PositionSyncCopy.headerCheckSync);
    });

    test('one file alone has nothing to sync', () {
      final chain = buildSyncChain(snap(ebook: _ebook));
      expect(kinds(chain), 'card:ebook');
      expect(chain.header.tone, ChainTone.muted);
    });
  });

  group("upstream's read-aloud sync", () {
    test('a book with all three files keeps them in step', () {
      final chain = buildSyncChain(snap(ebook: _ebook, audiobook: _audio, readAlong: _readAlong, readAloud: _synced));
      expect(kinds(chain),
          'card:ebook link:ebook-readAlong card:readAlong link:readAlong-audiobook card:audiobook');
      final copies = connector(chain, ConnectorKey.ebookReadAlong);
      expect(copies.state, ConnectorState.epubCopiesSynced);
      expect(copies.qualifier, PositionSyncCopy.qualifierDirect);
      expect(copies.toggle?.on, isTrue);
      expect(copies.toggle?.offAction, ChainActionId.disableReadAloudSync);
      final audio = connector(chain, ConnectorKey.readAlongAudiobook);
      expect(audio.state, ConnectorState.readAloudSynced);
      expect(chain.header.label, '3 of 3 in sync');
    });

    test('Whisper stays out once there is a read-aloud', () {
      final chain = buildSyncChain(snap(
          ebook: _ebook,
          audiobook: _audio,
          readAlong: _readAlong,
          readAloud: _synced,
          alignment: const SyncChainAlignment(status: AlignmentStatus.failed)));
      expect(chain.rows.whereType<ChainConnectorRow>().where((r) => r.key == ConnectorKey.ebookAudiobook), isEmpty);
      expect(chain.header.tone, ChainTone.success, reason: 'the failed map is not on screen');
    });

    test('turned off, both switches turn it back on', () {
      final chain = buildSyncChain(snap(
          ebook: _ebook,
          audiobook: _audio,
          readAlong: _readAlong,
          readAloud: const ReadAloudSync(mode: ReadAloudSyncMode.disabled, state: ReadAloudSyncState.disabled)));
      for (final key in [ConnectorKey.ebookReadAlong, ConnectorKey.readAlongAudiobook]) {
        final link = connector(chain, key);
        expect(link.state, ConnectorState.available);
        expect(link.toggle?.on, isFalse);
        expect(link.toggle?.onAction, ChainActionId.enableReadAloudSync);
      }
      expect(chain.header.tone, ChainTone.muted);
    });

    test('mismatched durations name both and want checking', () {
      final chain = buildSyncChain(snap(
          readAlong: _readAlong,
          audiobook: _audio,
          readAloud: const ReadAloudSync(
            state: ReadAloudSyncState.unavailable,
            unavailableReason: ReadAloudSyncReason.durationMismatch,
            audioDurationSeconds: 3 * 3600 + 120,
            overlayDurationSeconds: 3 * 3600 + 60 * 40,
          )));
      final link = connector(chain, ConnectorKey.readAlongAudiobook);
      expect(link.state, ConnectorState.readAloudIssue);
      expect(link.note, PositionSyncCopy.durationMismatch('3h 2m', '3h 40m'));
      expect(chain.header.tone, ChainTone.warning);
    });

    test('EPUB copies still sync without the audio', () {
      final chain = buildSyncChain(snap(
          ebook: _ebook,
          readAlong: _readAlong,
          readAloud: const ReadAloudSync(state: ReadAloudSyncState.unavailable, unavailableReason: ReadAloudSyncReason.noAudioFiles)));
      expect(kinds(chain), 'card:ebook link:ebook-readAlong card:readAlong');
      final copies = connector(chain, ConnectorKey.ebookReadAlong);
      expect(copies.state, ConnectorState.epubCopiesSynced);
      expect(copies.qualifier, PositionSyncCopy.epubCopiesOnly);
      expect(chain.header.label, '2 of 2 in sync');
    });

    test('a read-aloud with audio but no plain EPUB is partly synced when only its copies hold', () {
      final chain = buildSyncChain(snap(
          readAlong: const SyncChainEdition(formatName: 'Read-aloud EPUB', fileCount: 2),
          audiobook: _audio,
          readAloud: const ReadAloudSync(state: ReadAloudSyncState.unavailable, unavailableReason: ReadAloudSyncReason.missingDuration)));
      final link = connector(chain, ConnectorKey.readAlongAudiobook);
      expect(link.state, ConnectorState.readAloudPartial);
      expect(link.note, PositionSyncCopy.syncReasons[ReadAloudSyncReason.missingDuration]);
    });
  });

  group('read-aloud slot', () {
    SyncChain withSlot(SyncChainReadAloudSlot slot) =>
        buildSyncChain(snap(ebook: _ebook, audiobook: _audio, alignment: _ready, slot: slot));

    test('a book that can have one offers Create and Modify', () {
      final chain = withSlot(const SyncChainReadAloudSlot(entry: ReadAloudEntryAvailable()));
      expect(kinds(chain), 'card:ebook link:ebook-audiobook card:audiobook link:readAlong-audiobook slot');
      final slot = only<ChainReadAloudSlotRow>(chain);
      expect(slot.variant, ReadAloudSlotVariant.notCreated);
      expect(slot.action?.id, ChainActionId.createReadAloud);
      expect(slot.secondary?.id, ChainActionId.modifyReadAloud);
      final lead = chain.rows[chain.rows.length - 2] as ChainConnectorRow;
      expect(lead.toggle, isNull);
      expect(lead.qualifier, PositionSyncCopy.offNoReadAlong);
    });

    test('a request in flight locks the buttons and spins its own', () {
      final slot =
          only<ChainReadAloudSlotRow>(withSlot(const SyncChainReadAloudSlot(entry: ReadAloudEntryAvailable(), pending: ReadAloudPending.create)));
      expect(slot.action?.disabled, isTrue);
      expect(slot.secondary?.disabled, isTrue);
      expect(slot.pending, ChainActionId.createReadAloud);
    });

    test('a failed start shows in place of the note', () {
      final slot = only<ChainReadAloudSlotRow>(
          withSlot(const SyncChainReadAloudSlot(entry: ReadAloudEntryAvailable(), error: PositionSyncCopy.errorCreate)));
      expect(slot.note, PositionSyncCopy.errorCreate);
    });

    test('a hidden entry leaves no slot; an unavailable one says why', () {
      expect(withSlot(const SyncChainReadAloudSlot()).rows.whereType<ChainReadAloudSlotRow>(), isEmpty);
      final slot = only<ChainReadAloudSlotRow>(withSlot(const SyncChainReadAloudSlot(
          entry: ReadAloudEntryUnavailable(ReadAloudReason.workerUnavailable, 'offline'))));
      expect(slot.variant, ReadAloudSlotVariant.unavailable);
      expect(slot.note, 'offline');
      expect(slot.action, isNull);
    });

    test('a running job shows its stage and percent and can be cancelled', () {
      final slot = only<ChainReadAloudSlotRow>(withSlot(const SyncChainReadAloudSlot(
          entry: ReadAloudEntryUnavailable(ReadAloudReason.jobActive, ''),
          job: SyncChainReadAloudJob(
              status: ReadAloudJobStatus.processing, stage: 'aligning', progress: 61.6, canCancel: true))));
      expect(slot.variant, ReadAloudSlotVariant.processing);
      expect(slot.note, 'Matching the text to the narration');
      expect(slot.progress, (stage: 'aligning', percent: 62));
      expect(slot.cancel?.id, ChainActionId.cancelReadAloud);
    });

    test('a queued job says its place; a stopping one has no cancel', () {
      final queued = only<ChainReadAloudSlotRow>(withSlot(const SyncChainReadAloudSlot(
          job: SyncChainReadAloudJob(status: ReadAloudJobStatus.queued, queuePosition: 2, canCancel: true))));
      expect(queued.note, '2 jobs ahead');
      expect(queued.progress?.percent, isNull);
      final stopping = only<ChainReadAloudSlotRow>(withSlot(const SyncChainReadAloudSlot(
          job: SyncChainReadAloudJob(status: ReadAloudJobStatus.processing, stopping: true, canCancel: true))));
      expect(stopping.note, PositionSyncCopy.stoppingTitle);
      expect(stopping.cancel, isNull);
    });

    test('a job waiting for review, and a failed one', () {
      final review = only<ChainReadAloudSlotRow>(
          withSlot(const SyncChainReadAloudSlot(job: SyncChainReadAloudJob(status: ReadAloudJobStatus.awaitingReview))));
      expect(review.variant, ReadAloudSlotVariant.review);
      expect(review.action?.id, ChainActionId.reviewReadAloud);
      final retryable = only<ChainReadAloudSlotRow>(withSlot(const SyncChainReadAloudSlot(
          job: SyncChainReadAloudJob(status: ReadAloudJobStatus.failed, canRetry: true, error: 'boom'))));
      expect(retryable.note, 'boom');
      expect(retryable.action?.id, ChainActionId.retryReadAloud);
      expect(retryable.secondary?.id, ChainActionId.reviewReadAloud);
      final spent = only<ChainReadAloudSlotRow>(
          withSlot(const SyncChainReadAloudSlot(job: SyncChainReadAloudJob(status: ReadAloudJobStatus.failed))));
      expect(spent.action?.id, ChainActionId.reviewReadAloud);
      expect(spent.secondary, isNull);
    });

    test('no slot once the book has a read-aloud, or without both files', () {
      const slot = SyncChainReadAloudSlot(entry: ReadAloudEntryAvailable());
      expect(buildSyncChain(snap(ebook: _ebook, audiobook: _audio, readAlong: _readAlong, slot: slot)).rows.whereType<ChainReadAloudSlotRow>(),
          isEmpty);
      expect(buildSyncChain(snap(audiobook: _audio, slot: slot)).rows.whereType<ChainReadAloudSlotRow>(), isEmpty);
    });
  });

  group('Audiobookshelf', () {
    const link = AbsLink(absLibraryItemId: 'li_1', title: 'Anathem', libraryName: 'Fiction', syncing: true);

    test('a syncing match joins the audio group', () {
      final chain = buildSyncChain(snap(
          ebook: _ebook,
          audiobook: _audio,
          alignment: _ready,
          abs: const SyncChainAbs(link: link, live: AbsLive(status: AbsLiveStatus.synced, progressPercentage: 34))));
      expect(kinds(chain), 'card:ebook link:ebook-audiobook card:audiobook link:audiobook-abs card:abs');
      final abs = chain.rows.whereType<ChainCardRow>().last;
      expect(abs.subtitle, 'Fiction library');
      expect(abs.progress, 34);
      expect(abs.frame, ChainFrame.group);
      expect(connector(chain, ConnectorKey.audiobookAbs).toggle?.offAction, ChainActionId.pauseAbs);
      expect(chain.header.label, '3 of 3 in sync');
    });

    test('diverged offers both directions and wants checking', () {
      final chain = buildSyncChain(
          snap(audiobook: _audio, abs: const SyncChainAbs(link: link, live: AbsLive(status: AbsLiveStatus.diverged))));
      final c = connector(chain, ConnectorKey.audiobookAbs);
      expect(c.state, ConnectorState.absDiverged);
      expect(c.actions.map((a) => a.id), [ChainActionId.absPush, ChainActionId.absPull]);
      expect(chain.header.tone, ChainTone.warning);
    });

    test('paused resumes; needing review confirms and needs attention', () {
      final paused = buildSyncChain(snap(
          audiobook: _audio,
          abs: const SyncChainAbs(link: AbsLink(absLibraryItemId: 'li_1', pausedReason: AbsPausedReason.excluded))));
      expect(connector(paused, ConnectorKey.audiobookAbs).toggle?.onAction, ChainActionId.resumeAbs);
      expect(paused.rows.whereType<ChainCardRow>().last.chip, PositionSyncCopy.chipPaused);
      final review = buildSyncChain(snap(
          audiobook: _audio,
          abs: const SyncChainAbs(link: AbsLink(absLibraryItemId: 'li_1', pausedReason: AbsPausedReason.needsReview))));
      expect(review.rows.whereType<ChainCardRow>().last.confirm?.id, ChainActionId.confirmAbs);
      expect(review.needsAttention, isTrue);
    });

    test('no match offers Match; position sync off says so', () {
      final none = buildSyncChain(snap(audiobook: _audio, abs: const SyncChainAbs()));
      expect(only<ChainGhostRow>(none).action?.id, ChainActionId.change);
      expect(connector(none, ConnectorKey.audiobookAbs).toggle?.disabled, isTrue);
      final off = buildSyncChain(snap(
          audiobook: _audio,
          abs: const SyncChainAbs(link: AbsLink(absLibraryItemId: 'li_1', pausedReason: AbsPausedReason.positionSyncOff))));
      expect(only<ChainGhostRow>(off).note, PositionSyncCopy.ghostAbsPositionSyncOff);
    });

    test('not configured, or no audio, leaves it out', () {
      expect(kinds(buildSyncChain(snap(audiobook: _audio, abs: const SyncChainAbs(configured: false, link: link)))),
          'card:audiobook');
      expect(kinds(buildSyncChain(snap(ebook: _ebook, abs: const SyncChainAbs(link: link)))), 'card:ebook');
    });
  });

  group('helpers', () {
    test('the button shows a read-aloud being made as building', () {
      expect(syncButtonState(loaded: false, tone: ChainTone.success), SyncButtonState.loading);
      expect(syncButtonState(loaded: true, tone: ChainTone.success), SyncButtonState.inSync);
      expect(syncButtonState(loaded: true, tone: ChainTone.success, creating: true), SyncButtonState.building);
      expect(syncButtonState(loaded: true, tone: ChainTone.muted, creating: true), SyncButtonState.building);
      expect(syncButtonState(loaded: true, tone: ChainTone.warning, creating: true), SyncButtonState.checkSync);
      expect(syncButtonState(loaded: true, tone: ChainTone.destructive), SyncButtonState.needsAttention);
    });

    test('a book language picks the narration language the model knows', () {
      const supported = ['en', 'de', 'fr'];
      expect(readAloudLanguage(supported, 'en-GB', null), 'en');
      expect(readAloudLanguage(supported, 'English', null), 'en');
      expect(readAloudLanguage(supported, 'Deutsch', null), 'de');
      expect(readAloudLanguage(supported, 'fre', null), 'fr');
      expect(readAloudLanguage(supported, 'Klingon', 'de'), 'de');
      expect(readAloudLanguage(supported, 'nl', 'nl'), isNull);
      expect(readAloudLanguage(supported, null, null), isNull);
      expect(readAloudLanguageName('en'), 'English');
      expect(readAloudLanguageName('xx'), 'xx');
    });

    test('labels from a newer server fall back', () {
      expect(readAloudStageLabel('validating'), 'Checking the result');
      expect(readAloudStageLabel('teleporting'), PositionSyncCopy.stageWorking);
      expect(readAloudJobError('insufficient_storage'), "There isn't enough free disk space to finish.");
      expect(readAloudJobError('new_code'), PositionSyncCopy.jobErrorUnknown);
      expect(syncDuration(null), '-');
      expect(syncDuration(59 * 60), '59m');
    });
  });
}
