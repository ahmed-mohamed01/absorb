part of '../api_service.dart';

// Fork-owned: BookOrbit position sync over the server's own API (edition
// links, reading alignment, Storyteller read-alongs, Audiobookshelf sync)
// and its wire models. The server does the matching and building; this only
// asks. The hook is the `part` line in api_service.dart. See FORK_NOTES.md.

int? _psInt(Object? v) => v is num ? v.round() : (v is String ? int.tryParse(v) : null);

double? _psDouble(Object? v) => v is num ? v.toDouble() : null;

String? _psString(Object? v) => v is String ? v : null;

Map<String, dynamic>? _psMap(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

/// `not_configured` -> `notConfigured`, to look the server's snake_case up
/// in a Dart enum.
String _psCamel(String v) => v.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());

T? _psEnum<T extends Enum>(List<T> values, Object? v) =>
    v is String ? values.asNameMap()[_psCamel(v)] : null;

/// A non-2xx answer from a position sync call: [status] is the HTTP status,
/// [message] BookOrbit's reason when it gave one.
class PositionSyncRequestFailure implements Exception {
  final int status;
  final String message;
  const PositionSyncRequestFailure(this.status, this.message);
  @override
  String toString() => 'PositionSyncRequestFailure($status): $message';
}

class EditionLinkWire {
  final int id;
  final int? textBookId;
  final int audioBookId;
  final int? readAlongBookId;
  const EditionLinkWire({required this.id, this.textBookId, required this.audioBookId, this.readAlongBookId});

  factory EditionLinkWire.fromJson(Map<String, dynamic> j) => EditionLinkWire(
        id: _psInt(j['id']) ?? 0,
        textBookId: _psInt(j['textBookId']),
        audioBookId: _psInt(j['audioBookId']) ?? 0,
        readAlongBookId: _psInt(j['readAlongBookId']),
      );
}

class EditionLinkMemberWire {
  final int id;
  final String? title;
  final String? authorName;
  final String? coverVersion;
  final int? progressPercentage;
  final int? narrationPercentage;
  const EditionLinkMemberWire({
    required this.id,
    this.title,
    this.authorName,
    this.coverVersion,
    this.progressPercentage,
    this.narrationPercentage,
  });

  factory EditionLinkMemberWire.fromJson(Map<String, dynamic> j) => EditionLinkMemberWire(
        id: _psInt(j['id']) ?? 0,
        title: _psString(j['title']),
        authorName: _psString(j['authorName']),
        coverVersion: _psString(j['coverVersion']),
        progressPercentage: _psInt(_psMap(j['progress'])?['percentage']),
        narrationPercentage: _psInt(j['narrationPercentage']),
      );
}

class EditionLinkMembersWire {
  final EditionLinkMemberWire? text;
  final EditionLinkMemberWire audio;
  final EditionLinkMemberWire? readAlong;
  const EditionLinkMembersWire({this.text, required this.audio, this.readAlong});

  static EditionLinkMembersWire? fromJson(Map<String, dynamic>? j) {
    final audio = _psMap(j?['audio']);
    if (j == null || audio == null) return null;
    final text = _psMap(j['text']);
    final readAlong = _psMap(j['readAlong']);
    return EditionLinkMembersWire(
      text: text == null ? null : EditionLinkMemberWire.fromJson(text),
      audio: EditionLinkMemberWire.fromJson(audio),
      readAlong: readAlong == null ? null : EditionLinkMemberWire.fromJson(readAlong),
    );
  }
}

class EditionLinkCandidateWire {
  final int bookId;
  final String? title;
  final String? authorName;
  final String? coverVersion;

  /// 0..100.
  final int score;
  final int? progress;

  /// The proposal is the pair of a read-along build, so its score means
  /// nothing.
  final bool fromBuild;
  const EditionLinkCandidateWire({
    required this.bookId,
    this.title,
    this.authorName,
    this.coverVersion,
    this.score = 0,
    this.progress,
    this.fromBuild = false,
  });

  factory EditionLinkCandidateWire.fromJson(Map<String, dynamic> j) => EditionLinkCandidateWire(
        bookId: _psInt(j['bookId']) ?? 0,
        title: _psString(j['title']),
        authorName: _psString(j['authorName']),
        coverVersion: _psString(j['coverVersion']),
        score: _psInt(j['score']) ?? 0,
        progress: _psInt(j['progress']),
        fromBuild: j['fromBuild'] == true,
      );
}

class EditionLinkCounterpartWire {
  final int id;
  final String? title;
  final String? authorName;
  final String? coverVersion;
  const EditionLinkCounterpartWire({required this.id, this.title, this.authorName, this.coverVersion});

  factory EditionLinkCounterpartWire.fromJson(Map<String, dynamic> j) => EditionLinkCounterpartWire(
        id: _psInt(j['id']) ?? 0,
        title: _psString(j['title']),
        authorName: _psString(j['authorName']),
        coverVersion: _psString(j['coverVersion']),
      );
}

enum EditionLinkRole { text, audio, readAlong }

class EditionLinkForBookWire {
  final EditionLinkWire? link;
  final EditionLinkCandidateWire? proposed;
  final EditionLinkCounterpartWire? counterpart;
  final EditionLinkRole? role;
  final EditionLinkMembersWire? members;
  final int? thisBookProgress;
  final int? pickedProgress;

  /// A generated read-along whose pair this reader cannot see or relink, so
  /// nothing is offered for it.
  final bool readAlongOutput;
  const EditionLinkForBookWire({
    this.link,
    this.proposed,
    this.counterpart,
    this.role,
    this.members,
    this.thisBookProgress,
    this.pickedProgress,
    this.readAlongOutput = false,
  });

  factory EditionLinkForBookWire.fromJson(Map<String, dynamic> j) {
    final link = _psMap(j['link']);
    final proposed = _psMap(j['proposed']);
    final counterpart = _psMap(j['counterpart']);
    return EditionLinkForBookWire(
      link: link == null ? null : EditionLinkWire.fromJson(link),
      proposed: proposed == null ? null : EditionLinkCandidateWire.fromJson(proposed),
      counterpart: counterpart == null ? null : EditionLinkCounterpartWire.fromJson(counterpart),
      role: _psEnum(EditionLinkRole.values, j['role']),
      members: EditionLinkMembersWire.fromJson(_psMap(j['members'])),
      thisBookProgress: _psInt(j['thisBookProgress']),
      pickedProgress: _psInt(j['pickedProgress']),
      readAlongOutput: j['readAlongOutput'] == true,
    );
  }
}

class AlignmentStatusWire {
  final AlignmentStatus status;
  final int? samplesDone;
  final int? samplesTotal;
  final int? anchorCount;
  final String? builtAt;
  final String? error;
  final bool stale;
  const AlignmentStatusWire({
    this.status = AlignmentStatus.none,
    this.samplesDone,
    this.samplesTotal,
    this.anchorCount,
    this.builtAt,
    this.error,
    this.stale = false,
  });

  /// A 'none' payload carries only its status.
  factory AlignmentStatusWire.fromJson(Map<String, dynamic> j) {
    final status = _psEnum(AlignmentStatus.values, j['status']) ?? AlignmentStatus.none;
    if (status == AlignmentStatus.none) return const AlignmentStatusWire();
    return AlignmentStatusWire(
      status: status,
      samplesDone: _psInt(j['samplesDone']),
      samplesTotal: _psInt(j['samplesTotal']),
      anchorCount: _psInt(j['anchorCount']),
      builtAt: _psString(j['builtAt']),
      error: _psString(j['error']),
      stale: j['stale'] == true,
    );
  }
}

/// The answer to a build request: the status it started with, or why it
/// could not start.
class AlignmentBuildWire {
  final AlignmentStatus? started;
  final AlignmentBlock? blocked;
  const AlignmentBuildWire({this.started, this.blocked});

  factory AlignmentBuildWire.fromJson(Map<String, dynamic> j) {
    final blocked = _psEnum(AlignmentBlock.values, j['status']);
    if (blocked != null) return AlignmentBuildWire(blocked: blocked);
    return AlignmentBuildWire(started: _psEnum(AlignmentStatus.values, j['status']) ?? AlignmentStatus.none);
  }
}

class ReadAlongOutputBookWire {
  final int id;
  final String? title;
  const ReadAlongOutputBookWire({required this.id, this.title});
}

class ReadAlongStatusWire {
  final ReadAlongStatus status;
  final ReadAlongBlock? blocked;
  final ReadAlongPhase? phase;
  final String? remoteTask;

  /// 0..1, as Storyteller reports it for the current task.
  final double? remoteProgress;
  final ReadAlongOutputBookWire? outputBook;
  final int? targetLibraryId;
  final String? targetLibraryName;
  final int? epubBytes;
  final int? audioBytes;
  final int? readAlongBytes;
  final bool keepRemoteCopyByDefault;
  final bool remoteCopyReclaimable;
  final String? error;
  final String? startedAt;
  final String? builtAt;

  /// 1-based place among queued builds; only while queued.
  final int? queuePosition;
  const ReadAlongStatusWire({
    this.status = ReadAlongStatus.none,
    this.blocked,
    this.phase,
    this.remoteTask,
    this.remoteProgress,
    this.outputBook,
    this.targetLibraryId,
    this.targetLibraryName,
    this.epubBytes,
    this.audioBytes,
    this.readAlongBytes,
    this.keepRemoteCopyByDefault = false,
    this.remoteCopyReclaimable = true,
    this.error,
    this.startedAt,
    this.builtAt,
    this.queuePosition,
  });

  factory ReadAlongStatusWire.fromJson(Map<String, dynamic> j) {
    final status = _psEnum(ReadAlongStatus.values, j['status']) ?? ReadAlongStatus.none;
    final progress = _psDouble(j['remoteProgress']);
    final output = _psMap(j['outputBook']);
    final bytes = _psMap(j['remoteCopyBytes']);
    final queue = j['queuePosition'];
    return ReadAlongStatusWire(
      status: status,
      blocked: _psEnum(ReadAlongBlock.values, j['blocked']),
      phase: _psEnum(ReadAlongPhase.values, j['phase']),
      remoteTask: _psString(j['remoteTask']),
      remoteProgress: progress == null || progress.isNaN ? null : progress.clamp(0.0, 1.0),
      outputBook: output == null || _psInt(output['id']) == null
          ? null
          : ReadAlongOutputBookWire(id: _psInt(output['id'])!, title: _psString(output['title'])),
      targetLibraryId: _psInt(j['targetLibraryId']),
      targetLibraryName: _psString(j['targetLibraryName']),
      epubBytes: _psInt(bytes?['epub']),
      audioBytes: _psInt(bytes?['audio']),
      readAlongBytes: _psInt(bytes?['readAlong']),
      keepRemoteCopyByDefault: j['keepRemoteCopyByDefault'] == true,
      remoteCopyReclaimable: j['remoteCopyReclaimable'] != false,
      error: status == ReadAlongStatus.failed ? _psString(j['error']) : null,
      startedAt: _psString(j['startedAt']),
      builtAt: _psString(j['builtAt']),
      queuePosition: status == ReadAlongStatus.queued && queue is int && queue > 0 ? queue : null,
    );
  }
}

class ReadAlongBuildWire {
  final ReadAlongStatus status;
  final ReadAlongBlock? blocked;
  const ReadAlongBuildWire({required this.status, this.blocked});

  factory ReadAlongBuildWire.fromJson(Map<String, dynamic> j) => ReadAlongBuildWire(
        status: _psEnum(ReadAlongStatus.values, j['status']) ?? ReadAlongStatus.none,
        blocked: _psEnum(ReadAlongBlock.values, j['blocked']),
      );
}

enum ReadAlongCancelOutcome { cancelled, tooLate, failed }

class StorytellerExistingMatchWire {
  final String uuid;
  final String title;
  final List<String> authors;
  final bool aligned;
  final int score;
  const StorytellerExistingMatchWire({
    required this.uuid,
    required this.title,
    this.authors = const [],
    this.aligned = false,
    this.score = 0,
  });

  factory StorytellerExistingMatchWire.fromJson(Map<String, dynamic> j) => StorytellerExistingMatchWire(
        uuid: _psString(j['uuid']) ?? '',
        title: _psString(j['title']) ?? '',
        authors: [for (final a in (j['authors'] as List<dynamic>? ?? const [])) if (a is String) a],
        aligned: j['aligned'] == true,
        score: _psInt(j['score']) ?? 0,
      );
}

class AbsSyncLinkWire {
  final int audioBookId;
  final String absLibraryItemId;
  final String? title;
  final String? authorName;
  final String? libraryName;
  final AbsDirection direction;
  final bool syncing;
  final AbsPausedReason? pausedReason;
  final String? webUrl;
  const AbsSyncLinkWire({
    required this.audioBookId,
    required this.absLibraryItemId,
    this.title,
    this.authorName,
    this.libraryName,
    this.direction = AbsDirection.twoWay,
    this.syncing = false,
    this.pausedReason,
    this.webUrl,
  });

  factory AbsSyncLinkWire.fromJson(Map<String, dynamic> j) => AbsSyncLinkWire(
        audioBookId: _psInt(j['audioBookId']) ?? 0,
        absLibraryItemId: _psString(j['absLibraryItemId']) ?? '',
        title: _psString(j['title']),
        authorName: _psString(j['authorName']),
        libraryName: _psString(j['libraryName']),
        direction: _psEnum(AbsDirection.values, j['direction']) ?? AbsDirection.twoWay,
        syncing: j['syncing'] == true,
        pausedReason: _psEnum(AbsPausedReason.values, j['pausedReason']),
        webUrl: _psString(j['webUrl']),
      );
}

class AbsSyncLiveWire {
  final AbsLiveStatus status;
  final double? progressPercentage;
  final bool progressFinished;
  final int? progressLastUpdateMs;
  final double? localPercentage;
  final AbsDivergedReason? divergedReason;
  const AbsSyncLiveWire({
    required this.status,
    this.progressPercentage,
    this.progressFinished = false,
    this.progressLastUpdateMs,
    this.localPercentage,
    this.divergedReason,
  });

  factory AbsSyncLiveWire.fromJson(Map<String, dynamic> j) {
    final progress = _psMap(j['progress']);
    return AbsSyncLiveWire(
      status: _psEnum(AbsLiveStatus.values, j['status']) ?? AbsLiveStatus.synced,
      progressPercentage: _psDouble(progress?['percentage']),
      progressFinished: progress?['isFinished'] == true,
      progressLastUpdateMs: _psInt(progress?['lastUpdate']),
      localPercentage: _psDouble(_psMap(j['local'])?['percentage']),
      divergedReason: _psEnum(AbsDivergedReason.values, j['divergedReason']),
    );
  }
}

/// An Audiobookshelf item from the unmatched bucket, for the Change search.
class AbsBookStateWire {
  final String absLibraryItemId;
  final String absTitle;
  final String? absAuthorName;
  final String? absLibraryName;
  const AbsBookStateWire({required this.absLibraryItemId, required this.absTitle, this.absAuthorName, this.absLibraryName});

  factory AbsBookStateWire.fromJson(Map<String, dynamic> j) => AbsBookStateWire(
        absLibraryItemId: _psString(j['absLibraryItemId']) ?? '',
        absTitle: _psString(j['absTitle']) ?? '',
        absAuthorName: _psString(j['absAuthorName']),
        absLibraryName: _psString(j['absLibraryName']),
      );
}

class ReadAlongLibraryWire {
  final int id;
  final String name;
  const ReadAlongLibraryWire({required this.id, required this.name});
}

enum PositionSyncModality { text, audio, both, none }

/// The read-along's fit with its audiobook when a rebuild would fix it.
class ReadAloudIssue {
  /// 'narration_mismatch' or 'audio_changed'.
  final String reason;
  final int? narrationFile;
  final double? narrationSeconds;
  final int? chapter;
  final double? chapterSeconds;
  const ReadAloudIssue({required this.reason, this.narrationFile, this.narrationSeconds, this.chapter, this.chapterSeconds});

  static ReadAloudIssue? fromJson(Map<String, dynamic>? j) {
    if (j == null || j['state'] != 'unavailable') return null;
    final reason = j['unavailableReason'];
    if (reason != 'narration_mismatch' && reason != 'audio_changed') return null;
    final mismatch = reason == 'narration_mismatch' ? _psMap(j['narrationMismatch']) : null;
    return ReadAloudIssue(
      reason: reason as String,
      narrationFile: _psInt(mismatch?['narrationFile']),
      narrationSeconds: _psDouble(mismatch?['narrationSeconds']),
      chapter: _psInt(mismatch?['chapter']),
      chapterSeconds: _psDouble(mismatch?['chapterSeconds']),
    );
  }
}

class PositionSyncBookInfo {
  final PositionSyncModality modality;
  final ReadAloudIssue? readAloudIssue;
  const PositionSyncBookInfo({required this.modality, this.readAloudIssue});

  /// From a BookOrbit book detail: the content files decide whether it is an
  /// ebook, an audiobook, both or neither.
  factory PositionSyncBookInfo.fromDetail(Map<String, dynamic> detail) {
    var text = false;
    var audio = false;
    for (final f in (detail['files'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>()) {
      if (f['role'] != 'primary' && f['role'] != 'content') continue;
      final format = (f['format'] as String?)?.toLowerCase();
      if (format == null) continue;
      if (format == 'epub' || format == 'kepub') text = true;
      if (BookOrbitMapper.isAudioFormat(format)) audio = true;
    }
    return PositionSyncBookInfo(
      modality: text && audio
          ? PositionSyncModality.both
          : text
              ? PositionSyncModality.text
              : audio
                  ? PositionSyncModality.audio
                  : PositionSyncModality.none,
      readAloudIssue: ReadAloudIssue.fromJson(_psMap(detail['readAloudSync'])),
    );
  }
}

class PositionSyncPermissions {
  final bool editLink;
  final bool generate;
  final bool rebuild;
  final bool abs;
  const PositionSyncPermissions({this.editLink = false, this.generate = false, this.rebuild = false, this.abs = false});
}

extension ForkPositionSyncApi on BookOrbitApiService {
  /// Runs [call], turning a BookOrbit error answer into a
  /// [PositionSyncRequestFailure] that carries the server's reason.
  Future<T> _ps<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on _BoHttpError catch (e) {
      throw PositionSyncRequestFailure(e.status, e.serverMessage ?? e.message.trim());
    }
  }

  static String _absPath(String absLibraryItemId) =>
      '/audiobookshelf/books/${Uri.encodeComponent(absLibraryItemId)}';

  Future<PositionSyncBookInfo> positionSyncBookInfo(int bookId) =>
      _ps(() async => PositionSyncBookInfo.fromDetail(await _detail('$bookId')));

  Future<PositionSyncPermissions> positionSyncPermissions() async => PositionSyncPermissions(
        editLink: await _can('library_edit_metadata'),
        generate: await _can('library_upload'),
        rebuild: await _can('library_delete_books'),
        abs: await _can('audiobookshelf_sync'),
      );

  String positionSyncAbsCoverUrl(String absLibraryItemId) =>
      BookOrbitMediaProxy.instance.urlFor('/api/v1${_absPath(absLibraryItemId)}/cover');

  // Edition links.

  Future<EditionLinkForBookWire> editionLinkForBook(int bookId, {int? counterpartId}) => _ps(() async =>
      EditionLinkForBookWire.fromJson(
          await _boGet('/edition-links/for-book/$bookId', {'counterpartId': counterpartId}) as Map<String, dynamic>));

  Future<List<EditionLinkCandidateWire>> editionLinkCandidates(int sourceBookId, {String? q}) => _ps(() async {
        var query = q?.trim() ?? '';
        if (query.length > 200) query = query.substring(0, 200);
        final list = await _boGet('/edition-links/candidates/$sourceBookId', {'q': query.isEmpty ? null : query});
        return [
          for (final c in (list as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
            EditionLinkCandidateWire.fromJson(c),
        ];
      });

  Future<EditionLinkWire> linkEditions(int sourceBookId, int counterpartId) => _ps(() async => EditionLinkWire.fromJson(
      await _boPost('/edition-links/link/$sourceBookId', {'counterpartId': counterpartId}) as Map<String, dynamic>));

  /// What leaves depends on [bookId]'s role in its link: a read-along is
  /// detached, an ebook leaves, an audiobook dissolves the whole link.
  Future<EditionLinkWire?> unlinkEdition(int bookId) => _ps(() async {
        final r = _psMap(await _boDelete('/edition-links/link/$bookId'));
        return r == null ? null : EditionLinkWire.fromJson(r);
      });

  Future<EditionLinkWire> attachReadAlong(int pairBookId, int readAlongBookId) => _ps(() async =>
      EditionLinkWire.fromJson(await _boPost('/edition-links/read-along/$pairBookId', {'readAlongBookId': readAlongBookId})
          as Map<String, dynamic>));

  // Reading alignment.

  Future<AlignmentStatusWire> alignmentStatus(int bookId) => _ps(() async => AlignmentStatusWire.fromJson(
      await _boGet('/reading-alignment/books/$bookId/alignment') as Map<String, dynamic>));

  Future<AlignmentBuildWire> buildAlignment(int bookId, {bool force = false}) => _ps(() async =>
      AlignmentBuildWire.fromJson(_psMap(
              await _boPost('/reading-alignment/books/$bookId/build${force ? '?force=true' : ''}')) ??
          const {}));

  Future<void> cancelAlignment(int bookId) => _ps(() async {
        await _boDelete('/reading-alignment/books/$bookId/build');
      });

  // Storyteller read-along.

  Future<ReadAlongStatusWire> readAlongStatus(int bookId, {int? counterpartId}) => _ps(() async =>
      ReadAlongStatusWire.fromJson(await _boGet('/storyteller/read-along/books/$bookId/status',
          {'counterpartId': counterpartId}) as Map<String, dynamic>));

  Future<ReadAlongBuildWire> buildReadAlong(int bookId,
          {bool force = false, int? counterpartId, int? targetLibraryId, String? useExistingUuid, bool? cleanUpRemote}) =>
      _ps(() async => ReadAlongBuildWire.fromJson(_psMap(await _boPost('/storyteller/read-along/books/$bookId/build', {
            if (force) 'force': true,
            if (counterpartId != null) 'counterpartId': counterpartId,
            if (targetLibraryId != null) 'targetLibraryId': targetLibraryId,
            if (useExistingUuid != null) 'useExistingUuid': useExistingUuid,
            if (cleanUpRemote != null) 'cleanUpRemote': cleanUpRemote,
          })) ??
          const {}));

  /// Never throws: a refusal because the import already runs is
  /// [ReadAlongCancelOutcome.tooLate], anything else that fails is
  /// [ReadAlongCancelOutcome.failed].
  Future<ReadAlongCancelOutcome> cancelReadAlong(int bookId, {int? counterpartId}) async {
    try {
      final q = counterpartId == null ? '' : '?counterpartId=$counterpartId';
      await _boDelete('/storyteller/read-along/books/$bookId/build$q');
      return ReadAlongCancelOutcome.cancelled;
    } on _BoHttpError catch (e) {
      return e.status == 409 ? ReadAlongCancelOutcome.tooLate : ReadAlongCancelOutcome.failed;
    } catch (e) {
      debugPrint('[BookOrbit] read-along cancel for $bookId: $e');
      return ReadAlongCancelOutcome.failed;
    }
  }

  /// Aligned Storyteller books that already cover this pair; empty on any
  /// failure, since they only enrich the Import offer.
  Future<List<StorytellerExistingMatchWire>> readAlongExisting(int bookId, {int? counterpartId}) async {
    try {
      final r = _psMap(await _boGet('/storyteller/read-along/books/$bookId/existing', {'counterpartId': counterpartId}));
      return [
        for (final m in (r?['matches'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
          StorytellerExistingMatchWire.fromJson(m),
      ];
    } catch (e) {
      debugPrint('[BookOrbit] read-along existing for $bookId: $e');
      return const [];
    }
  }

  /// Book libraries whose allow-list takes an EPUB, the only ones the build
  /// endpoint accepts as a destination. The list only carries
  /// `allowedFormats` for a superuser; a missing one means every format.
  Future<List<ReadAlongLibraryWire>> readAlongTargetLibraries() => _ps(() async {
        final raw = await _boGet('/libraries') as List<dynamic>? ?? const [];
        bool takesEpub(Object? formats) => formats is! List || formats.isEmpty || formats.contains('epub');
        return [
          for (final l in raw.whereType<Map<String, dynamic>>())
            if (l['type'] == 'books' && takesEpub(l['allowedFormats']) && _psInt(l['id']) != null)
              ReadAlongLibraryWire(id: _psInt(l['id'])!, name: _psString(l['name']) ?? ''),
        ];
      });

  // Audiobookshelf.

  Future<bool> absConfigured() => _ps(() async =>
      (_psMap(await _boGet('/audiobookshelf/settings'))?['effectiveEnabled']) == true);

  /// Null when the audiobook has no Audiobookshelf match (an empty body).
  Future<AbsSyncLinkWire?> absLinkForBook(int audioBookId) => _ps(() async {
        final r = _psMap(await _boGet('/audiobookshelf/books/for-book/$audioBookId'));
        return r == null ? null : AbsSyncLinkWire.fromJson(r);
      });

  Future<AbsSyncLiveWire> absLive(String absLibraryItemId) => _ps(() async =>
      AbsSyncLiveWire.fromJson(await _boGet('${_absPath(absLibraryItemId)}/live') as Map<String, dynamic>));

  /// [direction] is 'push' or 'pull'.
  Future<AbsSyncLiveWire> absReconcile(String absLibraryItemId, String direction) => _ps(() async =>
      AbsSyncLiveWire.fromJson(
          await _boPost('${_absPath(absLibraryItemId)}/reconcile', {'direction': direction}) as Map<String, dynamic>));

  Future<void> absConfirm(String absLibraryItemId) => _ps(() async {
        await _boPost('${_absPath(absLibraryItemId)}/confirm');
      });

  Future<void> absSetExcluded(String absLibraryItemId, bool syncExcluded) => _ps(() async {
        await _boPatch('${_absPath(absLibraryItemId)}/exclusion', {'syncExcluded': syncExcluded});
      });

  Future<void> absLinkBook(String absLibraryItemId, int bookId) => _ps(() async {
        await _boPatch('${_absPath(absLibraryItemId)}/link', {'bookId': bookId});
      });

  Future<void> absUnlinkBook(String absLibraryItemId) => _ps(() async {
        await _boDelete('${_absPath(absLibraryItemId)}/link');
      });

  Future<List<AbsBookStateWire>> absUnmatched({String? q, int pageSize = 10}) => _ps(() async {
        final query = q?.trim() ?? '';
        final r = _psMap(await _boGet('/audiobookshelf/books', {
          'bucket': 'unmatched',
          'page': 0,
          'pageSize': pageSize,
          'q': query.isEmpty ? null : query,
        }));
        return [
          for (final i in (r?['items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
            AbsBookStateWire.fromJson(i),
        ];
      });
}
