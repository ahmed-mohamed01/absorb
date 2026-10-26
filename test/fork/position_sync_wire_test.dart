import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/fork/position_sync_chain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditionLinkForBookWire', () {
    test('a linked pair with members', () {
      final w = EditionLinkForBookWire.fromJson({
        'link': {'id': 7, 'textBookId': 1, 'audioBookId': 2, 'readAlongBookId': null, 'createdBy': 1, 'createdAt': 'x'},
        'proposed': null,
        'counterpart': {'id': 2, 'title': 'Anathem', 'authorName': 'Neal Stephenson', 'coverVersion': 'v1'},
        'role': 'text',
        'members': {
          'text': {
            'id': 1,
            'title': 'Anathem',
            'authorName': 'Neal Stephenson',
            'coverVersion': null,
            'progress': {'percentage': 41.4, 'updatedAt': 'x'},
            'narrationPercentage': null,
          },
          'audio': {'id': 2, 'title': 'Anathem', 'authorName': null, 'coverVersion': null, 'progress': null},
          'readAlong': null,
        },
        'thisBookProgress': 41,
        'pickedProgress': 12,
        'readAlongOutput': true,
      });
      expect(w.link!.id, 7);
      expect(w.link!.textBookId, 1);
      expect(w.link!.audioBookId, 2);
      expect(w.link!.readAlongBookId, isNull);
      expect(w.role, EditionLinkRole.text);
      expect(w.counterpart!.title, 'Anathem');
      expect(w.members!.text!.progressPercentage, 41);
      expect(w.members!.audio.id, 2);
      expect(w.members!.audio.progressPercentage, isNull);
      expect(w.members!.readAlong, isNull);
      expect(w.thisBookProgress, 41);
      expect(w.pickedProgress, 12);
      expect(w.readAlongOutput, isTrue);
    });

    test('an unlinked book with a proposal and no optional fields', () {
      final w = EditionLinkForBookWire.fromJson({
        'link': null,
        'proposed': {'bookId': 9, 'title': 'Anathem', 'authorName': null, 'coverVersion': null, 'score': 87},
        'counterpart': null,
        'role': null,
        'members': null,
        'thisBookProgress': null,
      });
      expect(w.link, isNull);
      expect(w.members, isNull);
      expect(w.role, isNull);
      expect(w.proposed!.bookId, 9);
      expect(w.proposed!.score, 87);
      expect(w.proposed!.fromBuild, isFalse);
      expect(w.proposed!.progress, isNull);
      expect(w.pickedProgress, isNull);
      expect(w.readAlongOutput, isFalse);
      expect(EditionLinkForBookWire.fromJson({'role': 'readAlong'}).role, EditionLinkRole.readAlong);
    });
  });

  group('AlignmentStatusWire', () {
    test('a bare none payload', () {
      final w = AlignmentStatusWire.fromJson({'status': 'none'});
      expect(w.status, AlignmentStatus.none);
      expect(w.builtAt, isNull);
      expect(w.stale, isFalse);
      expect(AlignmentStatusWire.fromJson({'status': 'weird'}).status, AlignmentStatus.none);
    });

    test('a full ready and stale payload', () {
      final w = AlignmentStatusWire.fromJson({
        'status': 'ready',
        'samplesDone': 40,
        'samplesTotal': 40,
        'anchorCount': 312,
        'builtAt': '2026-10-01T10:00:00.000Z',
        'error': null,
        'stale': true,
      });
      expect(w.status, AlignmentStatus.ready);
      expect(w.samplesDone, 40);
      expect(w.samplesTotal, 40);
      expect(w.anchorCount, 312);
      expect(w.builtAt, '2026-10-01T10:00:00.000Z');
      expect(w.stale, isTrue);
    });

    test('a build answer tells a block from a start', () {
      final busy = AlignmentBuildWire.fromJson({'status': 'busy'});
      expect(busy.blocked, AlignmentBlock.busy);
      expect(busy.started, isNull);
      final building = AlignmentBuildWire.fromJson({'status': 'building'});
      expect(building.blocked, isNull);
      expect(building.started, AlignmentStatus.building);
      expect(AlignmentBuildWire.fromJson({'status': 'unavailable'}).blocked, AlignmentBlock.unavailable);
    });
  });

  group('ReadAlongStatusWire', () {
    test('normalises what the server sends', () {
      final unknown = ReadAlongStatusWire.fromJson({'status': 'exploded', 'queuePosition': 3, 'remoteProgress': 2.5});
      expect(unknown.status, ReadAlongStatus.none);
      expect(unknown.queuePosition, isNull);
      expect(unknown.remoteProgress, 1.0);
      expect(unknown.remoteCopyReclaimable, isTrue);
      expect(unknown.keepRemoteCopyByDefault, isFalse);

      final queued = ReadAlongStatusWire.fromJson({'status': 'queued', 'queuePosition': 2, 'remoteProgress': -1});
      expect(queued.status, ReadAlongStatus.queued);
      expect(queued.queuePosition, 2);
      expect(queued.remoteProgress, 0.0);
      expect(ReadAlongStatusWire.fromJson({'status': 'queued', 'queuePosition': 0}).queuePosition, isNull);

      final building = ReadAlongStatusWire.fromJson({
        'status': 'building',
        'blocked': 'previous_output_not_deletable',
        'phase': 'wait',
        'remoteTask': 'SYNC_CHAPTERS',
        'remoteProgress': 0.4,
        'outputBook': {'id': 11, 'title': 'Anathem'},
        'targetLibraryId': 3,
        'targetLibraryName': 'Read-alongs',
        'remoteCopyBytes': {'epub': 2100000, 'audio': 900000000, 'readAlong': null},
        'keepRemoteCopyByDefault': true,
        'remoteCopyReclaimable': false,
        'error': 'ignored unless failed',
        'queuePosition': 4,
      });
      expect(building.blocked, ReadAlongBlock.previousOutputNotDeletable);
      expect(building.phase, ReadAlongPhase.wait);
      expect(building.remoteProgress, 0.4);
      expect(building.outputBook!.id, 11);
      expect(building.targetLibraryName, 'Read-alongs');
      expect(building.epubBytes, 2100000);
      expect(building.audioBytes, 900000000);
      expect(building.readAlongBytes, isNull);
      expect(building.keepRemoteCopyByDefault, isTrue);
      expect(building.remoteCopyReclaimable, isFalse);
      expect(building.error, isNull);
      expect(building.queuePosition, isNull);

      final failed = ReadAlongStatusWire.fromJson({'status': 'failed', 'error': 'boom', 'phase': 'nope'});
      expect(failed.error, 'boom');
      expect(failed.phase, isNull);
    });

    test('snake_case block reasons', () {
      for (final entry in {
        'not_configured': ReadAlongBlock.notConfigured,
        'no_pair': ReadAlongBlock.noPair,
        'source_epub_unreadable': ReadAlongBlock.sourceEpubUnreadable,
        'no_target_library': ReadAlongBlock.noTargetLibrary,
        'format_not_allowed': ReadAlongBlock.formatNotAllowed,
        'busy': ReadAlongBlock.busy,
      }.entries) {
        expect(ReadAlongStatusWire.fromJson({'status': 'none', 'blocked': entry.key}).blocked, entry.value);
      }
      final build = ReadAlongBuildWire.fromJson({'status': 'queued', 'blocked': null});
      expect(build.status, ReadAlongStatus.queued);
      expect(build.blocked, isNull);
      expect(ReadAlongBuildWire.fromJson({'status': 'none', 'blocked': 'no_epub'}).blocked, ReadAlongBlock.noEpub);
    });
  });

  group('Audiobookshelf', () {
    test('link enums', () {
      final link = AbsSyncLinkWire.fromJson({
        'audioBookId': 2,
        'absLibraryItemId': 'li_1',
        'title': 'Anathem',
        'authorName': 'Neal Stephenson',
        'libraryName': 'Fiction',
        'direction': 'from_abs',
        'syncing': false,
        'pausedReason': 'needs_review',
        'webUrl': 'https://abs/item/li_1',
      });
      expect(link.direction, AbsDirection.fromAbs);
      expect(link.pausedReason, AbsPausedReason.needsReview);
      expect(link.syncing, isFalse);
      expect(link.libraryName, 'Fiction');
      expect(AbsSyncLinkWire.fromJson({'direction': 'to_abs'}).direction, AbsDirection.toAbs);
      expect(AbsSyncLinkWire.fromJson({'direction': '???'}).direction, AbsDirection.twoWay);
      expect(AbsSyncLinkWire.fromJson({'pausedReason': 'position_sync_off'}).pausedReason, AbsPausedReason.positionSyncOff);
    });

    test('live status', () {
      final live = AbsSyncLiveWire.fromJson({
        'status': 'diverged',
        'progress': {'percentage': 52.3, 'isFinished': false, 'lastUpdate': 1760000000000},
        'local': {'percentage': 34, 'capturedAt': 'x'},
        'divergedReason': 'pull_refused',
      });
      expect(live.status, AbsLiveStatus.diverged);
      expect(live.progressPercentage, 52.3);
      expect(live.progressFinished, isFalse);
      expect(live.progressLastUpdateMs, 1760000000000);
      expect(live.localPercentage, 34);
      expect(live.divergedReason, AbsDivergedReason.pullRefused);
      final bare = AbsSyncLiveWire.fromJson({'status': 'unreachable', 'progress': null, 'local': null});
      expect(bare.status, AbsLiveStatus.unreachable);
      expect(bare.progressPercentage, isNull);
      expect(bare.divergedReason, isNull);
      expect(AbsSyncLiveWire.fromJson({'divergedReason': 'push_off'}).divergedReason, AbsDivergedReason.pushOff);
    });
  });

  test('book info from a detail', () {
    final ebook = PositionSyncBookInfo.fromDetail({
      'files': [
        {'role': 'primary', 'format': 'EPUB'},
        {'role': 'supplementary', 'format': 'mp3'},
      ],
    });
    expect(ebook.modality, PositionSyncModality.text);
    expect(ebook.readAloudIssue, isNull);
    final both = PositionSyncBookInfo.fromDetail({
      'files': [
        {'role': 'primary', 'format': 'm4b'},
        {'role': 'content', 'format': 'kepub'},
      ],
      'readAloudSync': {
        'state': 'unavailable',
        'unavailableReason': 'narration_mismatch',
        'narrationMismatch': {'narrationFile': 21, 'narrationSeconds': 2335.5, 'chapter': 8, 'chapterSeconds': 9683},
      },
    });
    expect(both.modality, PositionSyncModality.both);
    expect(both.readAloudIssue!.reason, 'narration_mismatch');
    expect(both.readAloudIssue!.narrationFile, 21);
    expect(both.readAloudIssue!.chapterSeconds, 9683);
    expect(PositionSyncBookInfo.fromDetail({'files': []}).modality, PositionSyncModality.none);
    final otherReason = PositionSyncBookInfo.fromDetail({
      'files': [
        {'role': 'primary', 'format': 'mp3'},
      ],
      'readAloudSync': {'state': 'unavailable', 'unavailableReason': 'missing_duration'},
    });
    expect(otherReason.modality, PositionSyncModality.audio);
    expect(otherReason.readAloudIssue, isNull);
  });
}
