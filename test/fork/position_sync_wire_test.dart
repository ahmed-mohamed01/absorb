import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/fork/position_sync_chain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditionSyncBookStateWire', () {
    test('reads the switch and the index', () {
      final w = EditionSyncBookStateWire.fromJson({
        'bookId': 50,
        'eligible': true,
        'hasReadAlong': false,
        'syncEnabled': true,
        'pinned': false,
        'runActive': true,
        'index': {'status': 'running',
          'stage': 'aligning',
          'progress': 42.5,
          'queuePosition': null,
          'nextRunAt': '2026-11-03T02:00:00.000Z',
        'error': null,
          'whisperFallback': false,
        },
        'canRunNow': false,
        'canRetry': true,
      });
      expect(w.eligible, isTrue);
      expect(w.syncEnabled, isTrue);
      expect(w.runActive, isTrue);
      expect(w.status, EditionSyncIndexStatus.running);
      expect(w.stage, 'aligning');
      expect(w.progress, 42.5);
      expect(w.nextRunAt, '2026-11-03T02:00:00.000Z');
      expect(w.canRetry, isTrue);
      expect(w.moving, isTrue);
    });

    test('an unknown status or a bare payload reads as none, and off never polls', () {
      expect(EditionSyncBookStateWire.fromJson({'index': {'status': 'weird'}}).status, EditionSyncIndexStatus.none);
      final bare = EditionSyncBookStateWire.fromJson(const {});
      expect(bare.status, EditionSyncIndexStatus.none);
      expect(bare.eligible, isFalse);
      expect(
          EditionSyncBookStateWire.fromJson({'syncEnabled': false, 'index': {'status': 'queued'}}).moving, isFalse);
    });

    test('effectiveReason says why sync is off, and is dropped while on', () {
      expect(EditionSyncBookStateWire.fromJson({'syncEnabled': false, 'effectiveReason': 'not_selected'}).offReason,
          EditionSyncOffReason.notSelected);
      expect(EditionSyncBookStateWire.fromJson({'syncEnabled': false, 'effectiveReason': 'user_disabled'}).offReason,
          EditionSyncOffReason.userDisabled);
      expect(EditionSyncBookStateWire.fromJson({'syncEnabled': true, 'effectiveReason': 'excluded'}).offReason, isNull);
      expect(EditionSyncBookStateWire.fromJson({'syncEnabled': false, 'effectiveReason': 'new_one'}).offReason, isNull);
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

  group('PositionSyncBookInfo', () {
    test('groups the plain EPUB, the read-aloud EPUB and the audio tracks', () {
      final info = PositionSyncBookInfo.fromDetail({
        'coverVersion': 'v3',
        'language': 'English',
        'files': [
          {'id': 1, 'role': 'primary', 'format': 'EPUB', 'sizeBytes': 2000000, 'filename': 'Anathem.epub'},
          {
            'id': 2,
            'role': 'content',
            'format': 'epub',
            'sizeBytes': 9000000,
            'filename': 'Anathem (read-aloud).epub',
            'mediaOverlay': {'available': true},
          },
          {'id': 3, 'role': 'content', 'format': 'm4b', 'sizeBytes': 400, 'filename': 'Anathem - Part 1.m4b'},
          {'id': 4, 'role': 'content', 'format': 'M4B', 'sizeBytes': 600, 'filename': 'Anathem - Part 2.m4b'},
          {'id': 5, 'role': 'content', 'format': 'kepub', 'sizeBytes': 1},
          {'id': 6, 'role': 'supplementary', 'format': 'mp3', 'sizeBytes': 1},
        ],
        'readAloudSync': {
          'mode': 'disabled',
          'state': 'disabled',
          'unavailableReason': null,
          'audioDurationSeconds': 3600,
          'overlayDurationSeconds': 3500.5,
        },
      });
      expect(info.coverVersion, 'v3');
      expect(info.language, 'English');
      expect(info.ebook!.fileIds, [1]);
      expect(info.ebook!.formatName, 'EPUB e-book');
      expect(info.ebook!.title, 'Anathem');
      expect(info.readAlong!.fileIds, [2]);
      expect(info.readAlong!.formatName, 'Read-aloud EPUB');
      expect(info.audiobook!.fileIds, [3, 4]);
      expect(info.audiobook!.sizeBytes, 1000);
      expect(info.audiobook!.formatName, 'M4B audiobook');
      expect(info.audiobook!.title, 'Anathem - Part', reason: 'what the track names share');
      expect(info.readAloudSync.mode, ReadAloudSyncMode.disabled);
      expect(info.readAloudSync.state, ReadAloudSyncState.disabled);
      expect(info.readAloudSync.overlayDurationSeconds, 3500.5);
    });

    test('a book with neither, and a server without read-aloud sync', () {
      final info = PositionSyncBookInfo.fromDetail({'files': []});
      expect(info.ebook, isNull);
      expect(info.readAlong, isNull);
      expect(info.audiobook, isNull);
      expect(info.readAloudSync.state, ReadAloudSyncState.unavailable);
      expect(info.readAloudSync.unavailableReason, ReadAloudSyncReason.noMediaOverlayEpub);
    });

    test('snake_case sync reasons', () {
      final sync = readAloudSyncFromJson({'mode': 'auto', 'state': 'unavailable', 'unavailableReason': 'duration_mismatch'});
      expect(sync.mode, ReadAloudSyncMode.auto);
      expect(sync.unavailableReason, ReadAloudSyncReason.durationMismatch);
      expect(readAloudSyncFromJson({'unavailableReason': 'no_audio_files'}).unavailableReason, ReadAloudSyncReason.noAudioFiles);
    });
  });

  group('read-aloud', () {
    Map<String, dynamic> job([Map<String, dynamic> extra = const {}]) => {
          'id': 'j1',
          'bookId': 9,
          'status': 'processing',
          'stage': 'generating_emissions',
          'progress': 42.5,
          'queuePosition': null,
          'errorCode': null,
          'cancelRequested': false,
          'cancellable': true,
          'canManage': true,
          'updatedAt': '2026-10-31T10:00:00.000Z',
          'dismissedAt': null,
          'retryableUntil': null,
          ...extra,
        };

    test('a job', () {
      final j = ReadAloudJobWire.fromJson(job())!;
      expect(j.id, 'j1');
      expect(j.bookId, 9);
      expect(j.status, ReadAloudJobStatus.processing);
      expect(j.stage, 'generating_emissions');
      expect(j.progress, 42.5);
      expect(j.running, isTrue);
      expect(j.active, isTrue);
      expect(ReadAloudJobWire.fromJson(job({'status': 'awaiting_review'}))!.status, ReadAloudJobStatus.awaitingReview);
      expect(ReadAloudJobWire.fromJson(job({'status': 'completed_with_warnings'}))!.completed, isTrue);
      expect(ReadAloudJobWire.fromJson(job({'status': 'something_new'})), isNull);
      expect(ReadAloudJobWire.fromJson(null), isNull);
    });

    test('a capability', () {
      final c = ReadAloudCapabilityWire.fromJson({
        'model': 'quartznet15x5',
        'supportedLanguages': ['en', 'de'],
        'workerConfigured': true,
        'workerAvailable': true,
        'eligible': false,
        'reason': 'too_many_audio_files',
        'epubFiles': [
          {'id': 1, 'filename': 'Anathem.epub', 'format': 'epub', 'sizeBytes': 1, 'durationSeconds': null},
        ],
        'audioFiles': [
          {'id': 3},
          {'id': 4},
        ],
        'existingReadAlongs': [
          {'fileId': 2},
        ],
        'latestJob': job(),
      });
      expect(c.workerConfigured, isTrue);
      expect(c.eligible, isFalse);
      expect(c.reason, ReadAloudReason.tooManyAudioFiles);
      expect(c.supportedLanguages, ['en', 'de']);
      expect(c.epubFiles.single.filename, 'Anathem.epub');
      expect(c.audioFileIds, [3, 4]);
      expect(c.existingReadAlongs, 1);
      expect(c.latestJob!.id, 'j1');
      expect(ReadAloudCapabilityWire.fromJson({}).latestJob, isNull);
    });

    test('a request', () {
      expect(
        const ReadAloudRequest(epubFileId: 1, audioFileIds: [3, 4], language: 'en').toJson(),
        {'epubFileId': 1, 'audioFileIds': [3, 4], 'language': 'en', 'granularity': 'sentence'},
      );
    });
  });
}
