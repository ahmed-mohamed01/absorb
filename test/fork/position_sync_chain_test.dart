import 'package:absorb/services/fork/position_sync_chain.dart';
import 'package:flutter_test/flutter_test.dart';

const _ebook = SyncChainEdition(title: 'Anathem', formatName: 'EPUB e-book', sizeBytes: 2 << 20, progress: 41);
const _audio = SyncChainEdition(title: 'Anathem', formatName: 'M4B audiobook', fileCount: 3, sizeBytes: 500 << 20, progress: 34,
);
const _readAlong = SyncChainEdition(title: 'Anathem', formatName: 'Read-aloud EPUB', sizeBytes: 9 << 20, progress: 20);
const _ready = SyncChainIndex(status: EditionSyncIndexStatus.ready, on: true);
const _synced = ReadAloudSync(mode: ReadAloudSyncMode.auto, state: ReadAloudSyncState.enabled);

SyncChainSnapshot snap({
  SyncChainEdition? ebook,
  SyncChainEdition? audiobook,
  SyncChainEdition? readAlong,
  SyncChainReadAloudSlot slot = const SyncChainReadAloudSlot(),
  SyncChainIndex? index,
  ReadAloudSync readAloud = const ReadAloudSync(),
  SyncChainAbs? abs,
}) =>
    SyncChainSnapshot(
      bookId: 7,
      ebook: ebook,
      audiobook: audiobook,
      readAlong: readAlong,
      readAloudSlot: slot,
  index: index,
      readAloud: readAloud,
      abs: abs,
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
        },
    )
    .join(' ');

void main() {
  group('timing index between the plain EPUB and the audio', () {
    ChainConnectorRow link(SyncChainIndex index) =>
        connector(buildSyncChain(snap(ebook: _ebook, audiobook: _audio, index: index)), ConnectorKey.ebookAudiobook);

    test('a ready index is in sync, with a switch', () {
      final chain = buildSyncChain(snap(ebook: _ebook, audiobook: _audio, index: _ready));
      expect(kinds(chain), 'card:ebook link:ebook-audiobook card:audiobook');
      final l = connector(chain, ConnectorKey.ebookAudiobook);
      expect(l.state, ConnectorState.indexSynced);
      expect(l.tone, ChainTone.success);
      expect(l.qualifier, PositionSyncCopy.qualifierViaTimings);
      expect(l.toggle?.on, isTrue);
      expect(l.toggle?.offAction, ChainActionId.disableIndexSync);
      expect(chain.header.label, '2 of 2 in sync');
      expect(chain.header.tone, ChainTone.success);
      expect(chain.intro, PositionSyncCopy.introSynced);
    });

    test('every file card is this book, with its file summary', () {
      final chain = buildSyncChain(snap(ebook: _ebook, audiobook: _audio, index: _ready));
      final cards = chain.rows.whereType<ChainCardRow>().toList();
      expect(cards.map((c) => (c.cover as BookCover).bookId), [7, 7]);
      expect(cards[0].subtitle, 'EPUB e-book · 2.0 MB');
      expect(cards[1].subtitle, 'M4B audiobook · 3 files · 500.0 MB');
      expect(cards[1].frame, ChainFrame.group);
      expect(cards.every((c) => c.linked), isTrue);
    });

    test('without edition sync the pair has no connector and is not syncing', () {
      final chain = buildSyncChain(snap(ebook: _ebook, audiobook: _audio));
      expect(kinds(chain), 'card:ebook card:audiobook');
      expect(chain.header.tone, ChainTone.muted);
      expect(chain.header.label, PositionSyncCopy.headerNotSyncing);
    });

    test('switched off reads Sync off and turns back on', () {
      final l = link(const SyncChainIndex(status: EditionSyncIndexStatus.ready));
      expect(l.state, ConnectorState.available);
      expect(l.pill, PositionSyncCopy.syncDisabled);
      expect(l.toggle?.on, isFalse);
      expect(l.toggle?.onAction, ChainActionId.enableIndexSync);
    });

    test('queued says when, and offers Run now unless a run is starting', () {
      final queued = link(
        const SyncChainIndex(
          status: EditionSyncIndexStatus.queued,
          on: true,
          queuePosition: 3,
          when: 'tonight 02:00',
          canRunNow: true,
        ),
      );
      expect(queued.state, ConnectorState.indexQueued);
      expect(queued.pill, 'Queued #3 · tonight 02:00');
      expect(queued.note, PositionSyncCopy.indexDetailQueued('tonight 02:00'));
      expect(queued.actions.map((a) => a.id), [ChainActionId.runIndexNow]);
      final soon = link(
        const SyncChainIndex(status: EditionSyncIndexStatus.queued, on: true, canRunNow: true, startingSoon: true),
      );
      expect(soon.pill, 'Queued · Starting soon');
      expect(soon.actions, isEmpty);
    });

    test('indexing shows the stage and percent, and heads the chain', () {
      final chain = buildSyncChain(snap(
          ebook: _ebook,
          audiobook: _audio,
          index: const SyncChainIndex(status: EditionSyncIndexStatus.running,
            on: true,
            stage: 'aligning',
            progress: 42.4,
          ),
        ),
      );
      final l = connector(chain, ConnectorKey.ebookAudiobook);
      expect(l.state, ConnectorState.indexRunning);
      expect(l.pill, 'Matching the text to the narration · 42%');
      expect(chain.header.tone, ChainTone.info);
      expect(chain.header.label, PositionSyncCopy.headerIndexing);
    });

    test('a failure needs attention, a stale index or Whisper wants checking', () {
      final failed = buildSyncChain(snap(
          ebook: _ebook, audiobook: _audio,
          index: const SyncChainIndex(status: EditionSyncIndexStatus.failed, on: true, error: 'boom', canRetry: true),
        ),
      );
      final l = connector(failed, ConnectorKey.ebookAudiobook);
      expect(l.state, ConnectorState.indexFailed);
      expect(l.note, 'boom');
      expect(l.actions.map((a) => a.id), [ChainActionId.retryIndex]);
      expect(failed.header.tone, ChainTone.destructive);
      expect(failed.needsAttention, isTrue);
      final stale = buildSyncChain(snap(
          ebook: _ebook,
          audiobook: _audio,
          index: const SyncChainIndex(status: EditionSyncIndexStatus.stale, on: true, canRunNow: true),
        ),
      );
      expect(connector(stale, ConnectorKey.ebookAudiobook).actions.map((a) => a.id), [ChainActionId.runIndexNow]);
      expect(stale.header.tone, ChainTone.warning);
      expect(stale.header.label, PositionSyncCopy.headerCheckSync);
      final whisper = link(
        const SyncChainIndex(status: EditionSyncIndexStatus.failed, on: true, whisperFallback: true),
      );
      expect(whisper.state, ConnectorState.indexViaWhisper);
      expect(whisper.pill, PositionSyncCopy.indexViaWhisper);
    });

    test('a request in flight locks the switch and the actions', () {
      final l = link(
        const SyncChainIndex(status: EditionSyncIndexStatus.stale, on: true, canRunNow: true, acting: true),
      );
      expect(l.toggle?.disabled, isTrue);
      expect(l.actions.single.disabled, isTrue);
    });

    test('one file alone has nothing to sync', () {
      final chain = buildSyncChain(snap(ebook: _ebook));
      expect(kinds(chain), 'card:ebook');
      expect(chain.header.tone, ChainTone.muted);
    });
  });

  test('off says why under the status when the server gave a reason', () {
    final why = editionSyncStatus(const SyncChainIndex(offReason: EditionSyncOffReason.excluded));
    expect((why.label, why.detail), (PositionSyncCopy.indexOff, PositionSyncCopy.offExcluded));
    expect(editionSyncStatus(const SyncChainIndex()).detail, isNull);
    for (final r in EditionSyncOffReason.values) {
      expect(PositionSyncCopy.offReason(r), isNotEmpty);
    }
  });

  group("the Editions card's sync", () {
    test('a book with a read-aloud uses read-aloud sync, counting its editions', () {
      final s = snap(ebook: _ebook, audiobook: _audio, readAlong: _readAlong, readAloud: _synced, index: _ready);
      expect(readAlongSyncCount(s), 3);
      final card = editionSyncCard(s)!;
      expect(
        (card.readAlong, card.on, card.status.label, card.status.tone),
        (true, true, PositionSyncCopy.indexSynced, ChainTone.success),
      );
      expect(card.status.detail, isNull);
      expect(card.via, PositionSyncCopy.qualifierViaReadAloud);
      expect(EditionSyncCard.index(_ready).via, PositionSyncCopy.qualifierViaTimings);
      const whisper = SyncChainIndex(status: EditionSyncIndexStatus.failed, on: true, whisperFallback: true);
      expect(EditionSyncCard.index(whisper).via, PositionSyncCopy.qualifierViaWhisper);
    });

    test('an index never made and not scheduled says so rather than queued', () {
      const none = SyncChainIndex(status: EditionSyncIndexStatus.none, on: true);
      expect(editionSyncStatus(none).label, PositionSyncCopy.indexNotIndexed);
      expect(
        editionSyncStatus(const SyncChainIndex(status: EditionSyncIndexStatus.none, on: true, queuePosition: 2)).label,
        PositionSyncCopy.indexQueuedAt(2),
      );
    });

    test('read-aloud sync off says why; an unavailable pair gives its short reason and the long one behind it', () {
      final off = editionSyncCard(
        snap(
          audiobook: _audio,
          readAlong: _readAlong,
          readAloud: const ReadAloudSync(mode: ReadAloudSyncMode.disabled, state: ReadAloudSyncState.disabled),
        ),
      )!;
      expect(
        (off.on, off.status.label, off.status.detail),
        (false, PositionSyncCopy.indexOff, PositionSyncCopy.offReadAloudSync),
      );
      // Off without the reader turning it off is a plain Off, as upstream.
      final serverOff = editionSyncCard(
        snap(
          audiobook: _audio,
          readAlong: _readAlong,
          readAloud: const ReadAloudSync(mode: ReadAloudSyncMode.auto, state: ReadAloudSyncState.disabled),
        ),
      )!;
      expect((serverOff.status.label, serverOff.status.detail), (PositionSyncCopy.indexOff, null));
      final issue = editionSyncCard(
        snap(
          audiobook: _audio,
          readAlong: _readAlong,
          readAloud: const ReadAloudSync(
            state: ReadAloudSyncState.unavailable,
            unavailableReason: ReadAloudSyncReason.durationMismatch,
            audioDurationSeconds: 3600,
            overlayDurationSeconds: 1800,
          ),
        ),
      )!;
      expect(
        (issue.on, issue.status.label, issue.status.tone),
        (true, PositionSyncCopy.headerReasons[ReadAloudSyncReason.durationMismatch], ChainTone.warning),
      );
      expect(issue.status.detail, contains('Durations do not match'));
    });

    test('EPUB copies only: normal without audio, a warning with it', () {
      const unavailable = ReadAloudSync(
        state: ReadAloudSyncState.unavailable,
        unavailableReason: ReadAloudSyncReason.noAudioFiles,
      );
      final copies = editionSyncCard(snap(ebook: _ebook, readAlong: _readAlong, readAloud: unavailable))!;
      expect((copies.status.label, copies.status.tone), (PositionSyncCopy.epubCopiesOnly, ChainTone.success));
      final partial = editionSyncCard(
        snap(ebook: _ebook, audiobook: _audio, readAlong: _readAlong, readAloud: unavailable),
      )!;
      expect((partial.status.label, partial.status.tone), (PositionSyncCopy.headerEpubOnly, ChainTone.warning));
      expect(partial.status.detail, startsWith(PositionSyncCopy.epubCopiesDescription));
    });

    test('without a read-aloud it is the timing index, and nothing without one either', () {
      final card = editionSyncCard(snap(ebook: _ebook, audiobook: _audio, index: _ready))!;
      expect((card.readAlong, card.status.label), (false, PositionSyncCopy.indexSynced));
      expect(editionSyncCard(snap(ebook: _ebook, audiobook: _audio)), isNull);
      expect(editionSyncCard(snap(readAlong: _readAlong)), isNull, reason: 'a read-aloud alone has nothing to sync');
    });
  });

  group('describeNextRun', () {
    final now = DateTime(2026, 11, 2, 15);
    test('buckets the run as upstream does', () {
      expect(describeNextRun(DateTime(2026, 11, 2, 16, 5), now), 'today 16:05');
      expect(describeNextRun(DateTime(2026, 11, 2, 22), now), 'tonight 22:00');
      expect(describeNextRun(DateTime(2026, 11, 3, 2), now), 'tonight 02:00');
      expect(describeNextRun(DateTime(2026, 11, 3, 9), now), 'tomorrow 09:00');
      expect(describeNextRun(DateTime(2026, 11, 5, 2), now), 'Thu, Nov 5 02:00');
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

    test('the timing index stays out once there is a read-aloud', () {
      final chain = buildSyncChain(snap(
          ebook: _ebook,
          audiobook: _audio,
          readAlong: _readAlong,
          readAloud: _synced,
          index: const SyncChainIndex(status: EditionSyncIndexStatus.failed, on: true),
        ),
      );
      expect(chain.rows.whereType<ChainConnectorRow>().where((r) => r.key == ConnectorKey.ebookAudiobook), isEmpty);
      expect(chain.header.tone, ChainTone.success, reason: 'the failed index is not on screen');
    });

    test('turned off, both switches turn it back on', () {
      final chain = buildSyncChain(snap(
          ebook: _ebook,
          audiobook: _audio,
          readAlong: _readAlong,
          readAloud: const ReadAloudSync(mode: ReadAloudSyncMode.disabled, state: ReadAloudSyncState.disabled),
        ),
      );
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
          ),
        ),
      );
      final link = connector(chain, ConnectorKey.readAlongAudiobook);
      expect(link.state, ConnectorState.readAloudIssue);
      expect(link.note, PositionSyncCopy.durationMismatch('3h 2m', '3h 40m'));
      expect(chain.header.tone, ChainTone.warning);
    });

    test('EPUB copies still sync without the audio', () {
      final chain = buildSyncChain(snap(
          ebook: _ebook,
          readAlong: _readAlong,
          readAloud: const ReadAloudSync(state: ReadAloudSyncState.unavailable, unavailableReason: ReadAloudSyncReason.noAudioFiles,
          ),
        ),
      );
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
          readAloud: const ReadAloudSync(state: ReadAloudSyncState.unavailable, unavailableReason: ReadAloudSyncReason.missingDuration,
          ),
        ),
      );
      final link = connector(chain, ConnectorKey.readAlongAudiobook);
      expect(link.state, ConnectorState.readAloudPartial);
      expect(link.note, PositionSyncCopy.syncReasons[ReadAloudSyncReason.missingDuration]);
    });
  });

  group('read-aloud slot', () {
    SyncChain withSlot(SyncChainReadAloudSlot slot) =>
        buildSyncChain(snap(ebook: _ebook, audiobook: _audio, index: _ready, slot: slot));

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
          only<ChainReadAloudSlotRow>(withSlot(const SyncChainReadAloudSlot(entry: ReadAloudEntryAvailable(), pending: ReadAloudPending.create)),
      );
      expect(slot.action?.disabled, isTrue);
      expect(slot.secondary?.disabled, isTrue);
      expect(slot.pending, ChainActionId.createReadAloud);
    });

    test('a failed start shows in place of the note', () {
      final slot = only<ChainReadAloudSlotRow>(
          withSlot(const SyncChainReadAloudSlot(entry: ReadAloudEntryAvailable(), error: PositionSyncCopy.errorCreate)),
      );
      expect(slot.note, PositionSyncCopy.errorCreate);
    });

    test('a hidden entry leaves no slot; an unavailable one says why', () {
      expect(withSlot(const SyncChainReadAloudSlot()).rows.whereType<ChainReadAloudSlotRow>(), isEmpty);
      final slot = only<ChainReadAloudSlotRow>(withSlot(const SyncChainReadAloudSlot(
          entry: ReadAloudEntryUnavailable(ReadAloudReason.workerUnavailable, 'offline')),
        ),
      );
      expect(slot.variant, ReadAloudSlotVariant.unavailable);
      expect(slot.note, 'offline');
      expect(slot.action, isNull);
    });

    test('a running job shows its stage and percent and can be cancelled', () {
      final slot = only<ChainReadAloudSlotRow>(withSlot(const SyncChainReadAloudSlot(
          entry: ReadAloudEntryUnavailable(ReadAloudReason.jobActive, ''),
          job: SyncChainReadAloudJob(
              status: ReadAloudJobStatus.processing, stage: 'aligning', progress: 61.6, canCancel: true,
            ),
          ),
        ),
      );
      expect(slot.variant, ReadAloudSlotVariant.processing);
      expect(slot.note, 'Matching the text to the narration');
      expect(slot.progress, (stage: 'aligning', percent: 62));
      expect(slot.cancel?.id, ChainActionId.cancelReadAloud);
    });

    test('a queued job says its place; a stopping one has no cancel', () {
      final queued = only<ChainReadAloudSlotRow>(withSlot(const SyncChainReadAloudSlot(
          job: SyncChainReadAloudJob(status: ReadAloudJobStatus.queued, queuePosition: 2, canCancel: true),
          ),
        ),
      );
      expect(queued.note, '2 jobs ahead');
      expect(queued.progress?.percent, isNull);
      final stopping = only<ChainReadAloudSlotRow>(withSlot(const SyncChainReadAloudSlot(
          job: SyncChainReadAloudJob(status: ReadAloudJobStatus.processing, stopping: true, canCancel: true),
          ),
        ),
      );
      expect(stopping.note, PositionSyncCopy.stoppingTitle);
      expect(stopping.cancel, isNull);
    });

    test('a job waiting for review, and a failed one', () {
      final review = only<ChainReadAloudSlotRow>(
          withSlot(const SyncChainReadAloudSlot(job: SyncChainReadAloudJob(status: ReadAloudJobStatus.awaitingReview))),
      );
      expect(review.variant, ReadAloudSlotVariant.review);
      expect(review.action?.id, ChainActionId.reviewReadAloud);
      final retryable = only<ChainReadAloudSlotRow>(withSlot(const SyncChainReadAloudSlot(
          job: SyncChainReadAloudJob(status: ReadAloudJobStatus.failed, canRetry: true, error: 'boom'),
          ),
        ),
      );
      expect(retryable.note, 'boom');
      expect(retryable.action?.id, ChainActionId.retryReadAloud);
      expect(retryable.secondary?.id, ChainActionId.reviewReadAloud);
      final spent = only<ChainReadAloudSlotRow>(
          withSlot(const SyncChainReadAloudSlot(job: SyncChainReadAloudJob(status: ReadAloudJobStatus.failed))),
      );
      expect(spent.action?.id, ChainActionId.reviewReadAloud);
      expect(spent.secondary, isNull);
    });

    test('no slot once the book has a read-aloud, or without both files', () {
      const slot = SyncChainReadAloudSlot(entry: ReadAloudEntryAvailable());
      expect(buildSyncChain(snap(ebook: _ebook, audiobook: _audio, readAlong: _readAlong, slot: slot),
        ).rows.whereType<ChainReadAloudSlotRow>(),
          isEmpty,
      );
      expect(buildSyncChain(snap(audiobook: _audio, slot: slot)).rows.whereType<ChainReadAloudSlotRow>(), isEmpty);
    });
  });

  group('Audiobookshelf', () {
    const link = AbsLink(absLibraryItemId: 'li_1', title: 'Anathem', libraryName: 'Fiction', syncing: true);

    test('a syncing match joins the audio group', () {
      final chain = buildSyncChain(snap(
          ebook: _ebook,
          audiobook: _audio,
          index: _ready,
          abs: const SyncChainAbs(link: link, live: AbsLive(status: AbsLiveStatus.synced, progressPercentage: 34),
          ),
        ),
      );
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
          snap(audiobook: _audio, abs: const SyncChainAbs(link: link, live: AbsLive(status: AbsLiveStatus.diverged),
          ),
        ),
      );
      final c = connector(chain, ConnectorKey.audiobookAbs);
      expect(c.state, ConnectorState.absDiverged);
      expect(c.actions.map((a) => a.id), [ChainActionId.absPush, ChainActionId.absPull]);
      expect(chain.header.tone, ChainTone.warning);
    });

    test('paused resumes; needing review confirms and needs attention', () {
      final paused = buildSyncChain(snap(
          audiobook: _audio,
          abs: const SyncChainAbs(link: AbsLink(absLibraryItemId: 'li_1', pausedReason: AbsPausedReason.excluded),
          ),
        ),
      );
      expect(connector(paused, ConnectorKey.audiobookAbs).toggle?.onAction, ChainActionId.resumeAbs);
      expect(paused.rows.whereType<ChainCardRow>().last.chip, PositionSyncCopy.chipPaused);
      final review = buildSyncChain(snap(
          audiobook: _audio,
          abs: const SyncChainAbs(link: AbsLink(absLibraryItemId: 'li_1', pausedReason: AbsPausedReason.needsReview),
          ),
        ),
      );
      expect(review.rows.whereType<ChainCardRow>().last.confirm?.id, ChainActionId.confirmAbs);
      expect(review.needsAttention, isTrue);
    });

    test('no match offers Match; position sync off says so', () {
      final none = buildSyncChain(snap(audiobook: _audio, abs: const SyncChainAbs()));
      expect(only<ChainGhostRow>(none).action?.id, ChainActionId.change);
      expect(connector(none, ConnectorKey.audiobookAbs).toggle?.disabled, isTrue);
      final off = buildSyncChain(snap(
          audiobook: _audio,
          abs: const SyncChainAbs(link: AbsLink(absLibraryItemId: 'li_1', pausedReason: AbsPausedReason.positionSyncOff),
          ),
        ),
      );
      expect(only<ChainGhostRow>(off).note, PositionSyncCopy.ghostAbsPositionSyncOff);
    });

    test('not configured, or no audio, leaves it out', () {
      expect(kinds(buildSyncChain(snap(audiobook: _audio, abs: const SyncChainAbs(configured: false, link: link),
            ),
          ),
        ),
          'card:audiobook',
      );
      expect(kinds(buildSyncChain(snap(ebook: _ebook, abs: const SyncChainAbs(link: link),
            ),
          ),
        ), 'card:ebook',
      );
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
