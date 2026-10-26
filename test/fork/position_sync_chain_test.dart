import 'package:absorb/services/fork/position_sync_chain.dart';
import 'package:flutter_test/flutter_test.dart';

const _ebook = SyncChainBook(id: 1, title: 'Anathem', authorName: 'Neal Stephenson', progress: 41);
const _audio = SyncChainBook(id: 2, title: 'Anathem', authorName: 'Neal Stephenson', progress: 34);
const _readAlongBook = SyncChainBook(id: 3, title: 'Anathem (read-along)', authorName: 'Neal Stephenson', progress: 20);
const _allowed = SyncChainPermissions(editLink: true, generate: true, rebuild: true);

SyncChainSnapshot snap({
  SyncEdition thisBook = SyncEdition.ebook,
  bool linked = false,
  SyncChainSide? ebook,
  SyncChainSide? audiobook,
  SyncChainAlignment alignment = const SyncChainAlignment(),
  SyncChainReadAlong readAlong = const SyncChainReadAlong(),
  ReadAloudIssueView? readAloudIssue,
  SyncChainAbs? abs,
  SyncChainPermissions can = _allowed,
}) =>
    SyncChainSnapshot(
      thisBook: thisBook,
      linked: linked,
      ebook: ebook ?? SyncChainSide.empty,
      audiobook: audiobook ?? SyncChainSide.empty,
      alignment: alignment,
      readAlong: readAlong,
      readAloudIssue: readAloudIssue,
      abs: abs,
      can: can,
    );

/// Unlinked ebook page with the server proposing an audiobook at 87%.
SyncChainSnapshot proposal({SyncChainPermissions can = _allowed, SyncChainReadAlong ra = const SyncChainReadAlong()}) =>
    snap(
      ebook: const SyncChainSide(book: _ebook, isThisBook: true),
      audiobook: const SyncChainSide(book: _audio, match: EditionMatch(MatchSource.auto, 87)),
      readAlong: ra,
      can: can,
    );

/// A linked pair seen from the ebook page.
SyncChainSnapshot linkedPair({
  SyncChainAlignment alignment = const SyncChainAlignment(status: AlignmentStatus.ready, builtAt: '2026-01-01'),
  SyncEdition thisBook = SyncEdition.ebook,
  SyncChainReadAlong readAlong = const SyncChainReadAlong(),
  ReadAloudIssueView? readAloudIssue,
  SyncChainAbs? abs,
  SyncChainPermissions can = _allowed,
}) =>
    snap(
      thisBook: thisBook,
      linked: true,
      ebook: SyncChainSide(book: _ebook, isMember: true, isThisBook: thisBook == SyncEdition.ebook),
      audiobook: SyncChainSide(book: _audio, isMember: true, isThisBook: thisBook == SyncEdition.audiobook),
      alignment: alignment,
      readAlong: readAlong,
      readAloudIssue: readAloudIssue,
      abs: abs,
      can: can,
    );

T rowAt<T extends ChainRow>(SyncChain chain, int i) => chain.rows[i] as T;

ChainConnectorRow connector(SyncChain chain, ConnectorKey key) =>
    chain.rows.whereType<ChainConnectorRow>().firstWhere((r) => r.key == key);

ChainCardRow card(SyncChain chain, SyncEdition edition) =>
    chain.rows.whereType<ChainCardRow>().firstWhere((r) => r.edition == edition);

void main() {
  group('unlinked', () {
    test('1. an ebook with a proposal offers the link and a read-along', () {
      final chain = buildSyncChain(proposal());
      expect(chain.rows, hasLength(5));
      final ebook = rowAt<ChainCardRow>(chain, 0);
      expect(ebook.edition, SyncEdition.ebook);
      expect(ebook.isThisBook, isTrue);
      expect(ebook.linked, isTrue);
      expect(ebook.change, ChangeState.none);
      final pair = rowAt<ChainConnectorRow>(chain, 1);
      expect(pair.key, ConnectorKey.ebookAudiobook);
      expect(pair.state, ConnectorState.available);
      expect(pair.toggle!.on, isFalse);
      expect(pair.toggle!.disabled, isFalse);
      expect(pair.toggle!.onAction, ChainActionId.linkPair);
      expect(pair.qualifier, 'not linked');
      expect(pair.disabledReason, isNull);
      final audio = rowAt<ChainCardRow>(chain, 2);
      expect(audio.edition, SyncEdition.audiobook);
      expect(audio.frame, ChainFrame.group);
      expect(audio.linked, isFalse);
      expect(audio.chip, '87% match');
      expect(audio.change, ChangeState.available);
      final muted = rowAt<ChainConnectorRow>(chain, 3);
      expect(muted.key, ConnectorKey.readAlongAudiobook);
      expect(muted.tone, ChainTone.muted);
      expect(muted.toggle, isNull);
      expect(muted.qualifier, 'not generated');
      final slot = rowAt<ChainReadAlongSlotRow>(chain, 4);
      expect(slot.variant, ReadAlongSlotVariant.notGenerated);
      expect(slot.action!.id, ChainActionId.openGenerate);
      expect(slot.action!.label, 'Generate read-along');
      expect(chain.header.tone, ChainTone.muted);
      expect(chain.header.label, 'Not linked');
      expect(chain.intro, PositionSyncCopy.introUnlinked);
      expect(chain.needsAttention, isFalse);
    });

    test('2. without editLink the switch is read-only; without generate there is no slot', () {
      final chain = buildSyncChain(proposal(can: const SyncChainPermissions(generate: true)));
      final pair = connector(chain, ConnectorKey.ebookAudiobook);
      expect(pair.toggle!.disabled, isTrue);
      expect(pair.disabledReason, "You don't have permission to change links.");
      expect(card(chain, SyncEdition.audiobook).change, ChangeState.none);

      final ghosts = buildSyncChain(snap(
        ebook: const SyncChainSide(book: _ebook, isThisBook: true),
        can: const SyncChainPermissions(generate: true),
      ));
      final ghost = ghosts.rows.whereType<ChainGhostRow>().single;
      expect(ghost.action, isNull);

      final noGenerate = buildSyncChain(proposal(can: const SyncChainPermissions(editLink: true)));
      expect(noGenerate.rows.whereType<ChainReadAlongSlotRow>(), isEmpty);
      expect(noGenerate.rows, hasLength(3));
    });

    test('3. nothing to link disables the switch and shows a ghost audiobook', () {
      final chain = buildSyncChain(snap(ebook: const SyncChainSide(book: _ebook, isThisBook: true)));
      final pair = connector(chain, ConnectorKey.ebookAudiobook);
      expect(pair.toggle!.disabled, isTrue);
      expect(pair.disabledReason, 'There is nothing to link yet.');
      final ghost = chain.rows.whereType<ChainGhostRow>().single;
      expect(ghost.edition, SyncEdition.audiobook);
      expect(ghost.frame, ChainFrame.group);
      expect(ghost.note, 'No matching audiobook found yet');
      expect(ghost.action!.label, 'Search');
      expect(ghost.action!.id, ChainActionId.change);
    });
  });

  group('alignment', () {
    test('4. a ready alignment is linked via Whisper and in sync', () {
      final chain = buildSyncChain(linkedPair());
      final pair = connector(chain, ConnectorKey.ebookAudiobook);
      expect(pair.state, ConnectorState.linkedViaWhisper);
      expect(pair.tone, ChainTone.success);
      expect(pair.pill, 'Linked · via Whisper');
      expect(pair.explainer, PositionSyncCopy.explainWhisper);
      expect(pair.toggle!.on, isTrue);
      expect(pair.toggle!.offTarget, OffTarget.pair);
      expect(chain.header.tone, ChainTone.success);
      expect(chain.header.label, '2 of 2 in sync');
      expect(chain.intro, PositionSyncCopy.introLinked);
      expect(chain.needsAttention, isFalse);
    });

    test('5. a running build is Linking before it ever built, Rebuilding after', () {
      final linking = buildSyncChain(linkedPair(
          alignment: const SyncChainAlignment(status: AlignmentStatus.pending, samplesDone: 12, samplesTotal: 40)));
      final pair = connector(linking, ConnectorKey.ebookAudiobook);
      expect(pair.state, ConnectorState.linking);
      expect(pair.tone, ChainTone.info);
      expect(pair.cancel!.id, ChainActionId.cancelLinking);
      expect(pair.ticks!.done, 12);
      expect(pair.ticks!.total, 40);
      expect(pair.note, PositionSyncCopy.noteLinking);
      expect(linking.header.label, 'Linking');
      expect(linking.header.tone, ChainTone.info);

      final rebuilding = buildSyncChain(linkedPair(
          alignment: const SyncChainAlignment(status: AlignmentStatus.building, builtAt: '2026-01-01')));
      final again = connector(rebuilding, ConnectorKey.ebookAudiobook);
      expect(again.state, ConnectorState.rebuilding);
      expect(again.cancel!.id, ChainActionId.cancelAlignment);
      expect(rebuilding.header.label, 'Linking');
    });

    test('6. a failed alignment has no switch and offers Retry and Unlink', () {
      final chain = buildSyncChain(
          linkedPair(alignment: const SyncChainAlignment(status: AlignmentStatus.failed, buildError: 'boom')));
      final pair = connector(chain, ConnectorKey.ebookAudiobook);
      expect(pair.state, ConnectorState.alignmentFailed);
      expect(pair.toggle, isNull);
      expect(pair.detail, 'boom');
      expect(pair.actions.map((a) => a.label), ['Retry', 'Unlink']);
      expect(pair.actions.map((a) => a.id), [ChainActionId.retryAlignment, ChainActionId.unlinkPair]);
      expect(chain.header.tone, ChainTone.destructive);
      expect(chain.header.label, 'Needs attention');
      expect(chain.needsAttention, isTrue);
    });

    test('7. a stale alignment is out of date', () {
      final chain = buildSyncChain(linkedPair(
          alignment: const SyncChainAlignment(status: AlignmentStatus.ready, stale: true, builtAt: '2026-01-01')));
      final pair = connector(chain, ConnectorKey.ebookAudiobook);
      expect(pair.state, ConnectorState.outOfDate);
      expect(pair.tone, ChainTone.warning);
      expect(pair.actions.single.label, 'Rebuild alignment');
      expect(chain.header.label, 'Check sync');
      expect(chain.needsAttention, isTrue);
    });

    test('8. build blocks: terminal is muted, busy still offers Align now', () {
      final disabled = connector(
          buildSyncChain(linkedPair(alignment: const SyncChainAlignment(buildBlocked: AlignmentBlock.disabled))),
          ConnectorKey.ebookAudiobook);
      expect(disabled.state, ConnectorState.alignmentBlocked);
      expect(disabled.tone, ChainTone.muted);
      expect(disabled.note, 'Reading alignment is turned off for this server.');
      expect(disabled.actions, isEmpty);

      final busy = connector(
          buildSyncChain(linkedPair(alignment: const SyncChainAlignment(buildBlocked: AlignmentBlock.busy))),
          ConnectorKey.ebookAudiobook);
      expect(busy.state, ConnectorState.notAligned);
      expect(busy.tone, ChainTone.warning);
      expect(busy.note, 'The server is busy aligning other books. Try again shortly.');
      expect(busy.actions.single.label, 'Align now');

      final idle = connector(buildSyncChain(linkedPair(alignment: const SyncChainAlignment())), ConnectorKey.ebookAudiobook);
      expect(idle.note, PositionSyncCopy.alignIdle);
    });
  });

  group('read-along', () {
    const member = SyncChainReadAlong(member: _readAlongBook, status: ReadAlongStatus.ready);

    test('9. a member on the audiobook page orders the chain and counts three in sync', () {
      final chain = buildSyncChain(linkedPair(thisBook: SyncEdition.audiobook, readAlong: member));
      expect(chain.rows.map((r) => r.runtimeType), [
        ChainCardRow,
        ChainConnectorRow,
        ChainCardRow,
        ChainConnectorRow,
        ChainCardRow,
      ]);
      expect(rowAt<ChainCardRow>(chain, 0).edition, SyncEdition.audiobook);
      expect(rowAt<ChainConnectorRow>(chain, 1).key, ConnectorKey.ebookAudiobook);
      expect(rowAt<ChainCardRow>(chain, 2).edition, SyncEdition.ebook);
      final ra = rowAt<ChainConnectorRow>(chain, 3);
      expect(ra.key, ConnectorKey.readAlongAudiobook);
      expect(ra.state, ConnectorState.linked);
      expect(ra.qualifier, 'direct');
      expect(rowAt<ChainCardRow>(chain, 4).edition, SyncEdition.readAlong);
      expect(countInSync(linkedPair(thisBook: SyncEdition.audiobook, readAlong: member)), 3);
      expect(chain.header.label, '3 of 3 in sync');

      const issue = ReadAloudIssueView('Narration does not follow this audiobook\'s chapters.');
      final withIssue = buildSyncChain(linkedPair(thisBook: SyncEdition.audiobook, readAlong: member, readAloudIssue: issue));
      final notSyncing = connector(withIssue, ConnectorKey.readAlongAudiobook);
      expect(notSyncing.state, ConnectorState.readAloudIssue);
      expect(notSyncing.tone, ChainTone.warning);
      expect(notSyncing.pill, 'Not syncing');
      expect(notSyncing.note, issue.message);
      expect(notSyncing.actions.single.label, 'Rebuild read-along');
      expect(withIssue.header.label, 'Check sync');

      final noRebuild = buildSyncChain(linkedPair(
          thisBook: SyncEdition.audiobook,
          readAlong: member,
          readAloudIssue: issue,
          can: const SyncChainPermissions(editLink: true, generate: true)));
      expect(connector(noRebuild, ConnectorKey.readAlongAudiobook).actions, isEmpty);
      final building = buildSyncChain(linkedPair(
          thisBook: SyncEdition.audiobook,
          readAlong: const SyncChainReadAlong(member: _readAlongBook, status: ReadAlongStatus.building),
          readAloudIssue: issue));
      expect(connector(building, ConnectorKey.readAlongAudiobook).actions, isEmpty);
    });

    test('10. Change is blocked while the read-along holds the pair', () {
      final withMember = buildSyncChain(linkedPair(readAlong: member));
      final audio = card(withMember, SyncEdition.audiobook);
      expect(audio.change, ChangeState.blocked);
      expect(audio.changeHint, 'Rebuild or detach the read-along first');

      final running = buildSyncChain(proposal(ra: const SyncChainReadAlong(status: ReadAlongStatus.building)));
      expect(card(running, SyncEdition.audiobook).change, ChangeState.blocked);
      expect(card(running, SyncEdition.audiobook).changeHint, 'Wait for the read-along build, or cancel it');

      final failed = buildSyncChain(proposal(ra: const SyncChainReadAlong(status: ReadAlongStatus.failed)));
      expect(card(failed, SyncEdition.audiobook).change, ChangeState.blocked);
      expect(card(failed, SyncEdition.audiobook).changeHint, 'Retry the read-along build first');

      final pair = buildSyncChain(snap(
        ebook: const SyncChainSide(book: _ebook, isThisBook: true),
        audiobook: const SyncChainSide(book: _audio, match: EditionMatch(MatchSource.pair)),
      ));
      expect(card(pair, SyncEdition.audiobook).change, ChangeState.none);
      expect(card(pair, SyncEdition.audiobook).chip, 'Generated from Anathem');
    });

    test('11. the slot follows the build', () {
      final queued = buildSyncChain(proposal(ra: const SyncChainReadAlong(status: ReadAlongStatus.queued, queuePosition: 2)));
      final q = queued.rows.whereType<ChainReadAlongSlotRow>().single;
      expect(q.variant, ReadAlongSlotVariant.queued);
      expect(q.note, 'Waiting for another read-along to finish (2 in line)');
      expect(q.job!.stage, 0);
      expect(q.cancel!.id, ChainActionId.cancelReadAlong);
      expect(queued.header.label, 'Linking');

      final building = buildSyncChain(proposal(
          ra: const SyncChainReadAlong(
              status: ReadAlongStatus.building,
              phase: ReadAlongPhase.wait,
              remoteTask: 'sync_chapters',
              remoteProgress: 0.62)));
      final b = building.rows.whereType<ChainReadAlongSlotRow>().single;
      expect(b.variant, ReadAlongSlotVariant.building);
      expect(b.note, 'Generating with Storyteller…');
      expect(b.job!.stage, 2);
      expect(readAlongPercent(b.job!.stage, b.job!.remoteProgress), 62);

      final failed = buildSyncChain(proposal(
          ra: const SyncChainReadAlong(
              status: ReadAlongStatus.failed,
              phase: ReadAlongPhase.wait,
              blocked: ReadAlongBlock.noEpub,
              error: 'stack trace')));
      final f = failed.rows.whereType<ChainReadAlongSlotRow>().single;
      expect(f.variant, ReadAlongSlotVariant.failed);
      expect(f.note, 'Storyteller stopped at the Transcribing step. Nothing was added to your library.');
      expect(f.action!.label, 'Retry');
      expect(f.action!.disabled, isTrue);
      expect(f.cancel!.label, 'Dismiss');
      expect(f.error, 'stack trace');
      expect(failed.header.tone, ChainTone.destructive);
      final busyRetry = buildSyncChain(proposal(
          ra: const SyncChainReadAlong(status: ReadAlongStatus.failed, blocked: ReadAlongBlock.busy)));
      expect(busyRetry.rows.whereType<ChainReadAlongSlotRow>().single.action!.disabled, isFalse);

      final notConfigured =
          buildSyncChain(proposal(ra: const SyncChainReadAlong(blocked: ReadAlongBlock.notConfigured)));
      expect(notConfigured.rows.whereType<ChainReadAlongSlotRow>(), isEmpty);

      final needsEbook = buildSyncChain(snap(
        thisBook: SyncEdition.audiobook,
        audiobook: const SyncChainSide(book: _audio, isThisBook: true),
      ));
      final ne = needsEbook.rows.whereType<ChainReadAlongSlotRow>().single;
      expect(ne.variant, ReadAlongSlotVariant.needsEbook);
      expect(ne.action!.disabled, isTrue);
      final needsAudio = buildSyncChain(snap(ebook: const SyncChainSide(book: _ebook, isThisBook: true)));
      expect(needsAudio.rows.whereType<ChainReadAlongSlotRow>().single.variant, ReadAlongSlotVariant.needsAudio);

      final noPair = buildSyncChain(proposal(ra: const SyncChainReadAlong(blocked: ReadAlongBlock.noPair)));
      expect(noPair.rows.whereType<ChainReadAlongSlotRow>().single.variant, ReadAlongSlotVariant.notGenerated);
      final blocked = buildSyncChain(proposal(ra: const SyncChainReadAlong(blocked: ReadAlongBlock.noTargetLibrary)));
      final bl = blocked.rows.whereType<ChainReadAlongSlotRow>().single;
      expect(bl.variant, ReadAlongSlotVariant.blocked);
      expect(bl.note, 'Pick a read-along library in the Storyteller settings.');
    });

    test('14. on the read-along page it leads the chain', () {
      const thisReadAlong = SyncChainBook(id: 3, title: 'Anathem (read-along)');
      final chain = buildSyncChain(snap(
        thisBook: SyncEdition.readAlong,
        linked: true,
        ebook: const SyncChainSide(book: _ebook, isMember: true),
        audiobook: const SyncChainSide(book: _audio, isMember: true),
        alignment: const SyncChainAlignment(status: AlignmentStatus.ready),
        readAlong: const SyncChainReadAlong(member: _readAlongBook, thisBook: thisReadAlong, status: ReadAlongStatus.ready),
        abs: const SyncChainAbs(),
      ));
      expect(rowAt<ChainCardRow>(chain, 0).edition, SyncEdition.readAlong);
      expect(rowAt<ChainCardRow>(chain, 0).isThisBook, isTrue);
      expect(rowAt<ChainConnectorRow>(chain, 1).key, ConnectorKey.readAlongAudiobook);
      expect(rowAt<ChainCardRow>(chain, 2).edition, SyncEdition.audiobook);
      expect(rowAt<ChainConnectorRow>(chain, 3).key, ConnectorKey.audiobookAbs);
      expect(rowAt<ChainGhostRow>(chain, 4).edition, SyncEdition.abs);
      expect(rowAt<ChainConnectorRow>(chain, 5).key, ConnectorKey.ebookAudiobook);
      expect(rowAt<ChainCardRow>(chain, 6).edition, SyncEdition.ebook);
      expect(chain.rows, hasLength(7));
    });
  });

  group('Audiobookshelf', () {
    const syncing = AbsLink(audioBookId: 2, absLibraryItemId: 'li_1', title: 'Anathem', libraryName: 'Fiction', syncing: true);

    test('12. rows follow the link and its live state', () {
      final off = buildSyncChain(linkedPair(abs: const SyncChainAbs(configured: false, link: syncing)));
      expect(off.rows.where((r) => r is ChainConnectorRow && r.key == ConnectorKey.audiobookAbs), isEmpty);
      expect(off.rows.where((r) => r is ChainCardRow && r.edition == SyncEdition.abs), isEmpty);

      final diverged = buildSyncChain(linkedPair(
          abs: const SyncChainAbs(link: syncing, live: AbsLive(status: AbsLiveStatus.diverged))));
      final d = connector(diverged, ConnectorKey.audiobookAbs);
      expect(d.state, ConnectorState.absDiverged);
      expect(d.tone, ChainTone.warning);
      expect(d.actions.map((a) => a.label), ['Send to ABS', 'Use ABS']);
      expect(d.absDetails, isTrue);
      expect(diverged.header.label, 'Check sync');

      final unreachable = connector(
          buildSyncChain(linkedPair(abs: const SyncChainAbs(link: syncing, live: AbsLive(status: AbsLiveStatus.unreachable)))),
          ConnectorKey.audiobookAbs);
      expect(unreachable.pill, "Can't reach server");
      expect(unreachable.actions.single.label, 'Retry');

      const oneWayLink = AbsLink(audioBookId: 2, absLibraryItemId: 'li_1', direction: AbsDirection.fromAbs, syncing: true);
      final oneWay = buildSyncChain(
          linkedPair(abs: const SyncChainAbs(link: oneWayLink, live: AbsLive(status: AbsLiveStatus.synced, progressPercentage: 52))));
      final o = connector(oneWay, ConnectorKey.audiobookAbs);
      expect(o.state, ConnectorState.absOneWay);
      expect(o.arrow, ChainArrow.left);
      expect(o.pill, 'Linked · one way');
      expect(card(oneWay, SyncEdition.abs).progress, 52);
      expect(oneWay.header.label, '3 of 3 in sync');

      const review = AbsLink(audioBookId: 2, absLibraryItemId: 'li_1', pausedReason: AbsPausedReason.needsReview);
      final needsReview = buildSyncChain(linkedPair(abs: const SyncChainAbs(link: review)));
      final reviewCard = card(needsReview, SyncEdition.abs);
      expect(reviewCard.chip, 'Needs review');
      expect(reviewCard.confirm!.id, ChainActionId.confirmAbs);
      expect(connector(needsReview, ConnectorKey.audiobookAbs).toggle!.onAction, ChainActionId.confirmAbs);
      expect(needsReview.needsAttention, isTrue);

      const settingsOff = AbsLink(audioBookId: 2, absLibraryItemId: 'li_1', pausedReason: AbsPausedReason.positionSyncOff);
      final positionSyncOff = buildSyncChain(linkedPair(abs: const SyncChainAbs(link: settingsOff)));
      expect(positionSyncOff.rows.whereType<ChainGhostRow>().single.note, 'Position sync is off in Settings');
      final offSwitch = connector(positionSyncOff, ConnectorKey.audiobookAbs);
      expect(offSwitch.toggle!.disabled, isTrue);
      expect(offSwitch.disabledReason, 'sync off in Settings');

      final unmatched = buildSyncChain(linkedPair(abs: const SyncChainAbs()));
      final ghost = unmatched.rows.whereType<ChainGhostRow>().single;
      expect(ghost.note, 'No match in your libraries');
      expect(ghost.action!.label, 'Match');

      const paused = AbsLink(audioBookId: 2, absLibraryItemId: 'li_1', pausedReason: AbsPausedReason.excluded);
      final p = buildSyncChain(linkedPair(abs: const SyncChainAbs(link: paused)));
      expect(card(p, SyncEdition.abs).chip, 'Paused');
      expect(connector(p, ConnectorKey.audiobookAbs).toggle!.onAction, ChainActionId.resumeAbs);
    });
  });

  group('helpers', () {
    test('13. stage, percent, display percentage and blocks', () {
      expect(stageIndex(null, null), 0);
      expect(stageIndex(ReadAlongPhase.prepare, null), 0);
      expect(stageIndex(ReadAlongPhase.wait, 'TRANSCRIBE'), 1);
      expect(stageIndex(ReadAlongPhase.wait, 'SYNC_CHAPTERS'), 2);
      expect(stageIndex(ReadAlongPhase.collect, null), 3);
      expect(stageIndex(ReadAlongPhase.link, null), 3);

      expect(readAlongPercent(0, 0.5), isNull);
      expect(readAlongPercent(3, 0.5), isNull);
      expect(readAlongPercent(1, null), isNull);
      expect(readAlongPercent(1, 0.555), 56);
      expect(readAlongPercent(2, 1.4), 100);
      expect(readAlongPercent(2, -0.2), 0);

      expect(displayPercentage(null, false), isNull);
      expect(displayPercentage(0, true), 0);
      expect(displayPercentage(-3, false), 0);
      expect(displayPercentage(40, true), 100);
      expect(displayPercentage(99.6, false), 99);
      expect(displayPercentage(0.2, false), 1);
      expect(displayPercentage(42.4, false), 42);

      expect(isTerminalBlock(AlignmentBlock.disabled), isTrue);
      expect(isTerminalBlock(AlignmentBlock.unavailable), isTrue);
      expect(isTerminalBlock(AlignmentBlock.busy), isFalse);
      expect(isTerminalBlock(null), isFalse);
      expect(isActionBlocked(null), isFalse);
      expect(isActionBlocked(ReadAlongBlock.busy), isFalse);
      expect(isActionBlocked(ReadAlongBlock.noEpub), isTrue);
    });

    test('read-aloud issue text keeps the seconds', () {
      expect(
        readAloudIssueMessage('narration_mismatch',
            narrationFile: 21, narrationSeconds: 2335.9, chapter: 8, chapterSeconds: 9683),
        "Narration does not follow this audiobook's chapters: file 21 is 38:55, chapter 8 is 2:41:23.",
      );
      expect(readAloudIssueMessage('narration_mismatch'), "Narration does not follow this audiobook's chapters.");
      expect(readAloudIssueMessage('audio_changed'), 'The audiobook files changed after this read-along was built.');
    });

    test('button state and tooltip', () {
      expect(syncButtonState(loaded: false, tone: ChainTone.success), SyncButtonState.loading);
      expect(syncButtonState(loaded: true, tone: ChainTone.muted), SyncButtonState.notLinked);
      expect(syncButtonState(loaded: true, tone: ChainTone.info), SyncButtonState.building);
      expect(syncButtonState(loaded: true, tone: ChainTone.warning), SyncButtonState.checkSync);
      expect(syncButtonState(loaded: true, tone: ChainTone.destructive), SyncButtonState.needsAttention);
      expect(syncButtonState(loaded: true, tone: ChainTone.success), SyncButtonState.inSync);

      String tip({bool linked = true, bool audio = false, ReadAlongStatus ra = ReadAlongStatus.none,
              AlignmentStatus al = AlignmentStatus.none, bool stale = false, bool running = false}) =>
          syncButtonTooltip(
            linked: linked,
            audioModality: audio,
            readAlongStatus: ra,
            readAlongMutating: false,
            alignmentRunning: running,
            alignmentStatus: al,
            alignmentStale: stale,
            membersWithoutText: false,
          );
      expect(tip(linked: false), 'Link an audiobook to enable position sync.');
      expect(tip(linked: false, audio: true), 'Link an ebook to enable position sync.');
      expect(tip(ra: ReadAlongStatus.queued), 'Linked - read-along queued.');
      expect(tip(running: true), 'Linked - building position sync...');
      expect(tip(al: AlignmentStatus.ready, stale: true), PositionSyncCopy.tooltipAlignStale);
      expect(tip(al: AlignmentStatus.ready), 'Linked - position sync ready.');
      expect(tip(), 'Manage the linked edition.');
    });
  });
}
