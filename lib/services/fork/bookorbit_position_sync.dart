part of '../api_service.dart';

// Fork-owned: BookOrbit position sync over the server's own API for one
// book's files (reading alignment, upstream's read-aloud sync and generator,
// Audiobookshelf sync) and its wire models. The server does the matching and
// building; this only asks. The hook is the `part` line in api_service.dart.
// See FORK_NOTES.md.

int? _psInt(Object? v) => v is num ? v.round() : (v is String ? int.tryParse(v) : null);

double? _psDouble(Object? v) => v is num ? v.toDouble() : null;

String? _psString(Object? v) => v is String ? v : null;

Map<String, dynamic>? _psMap(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

Iterable<Map<String, dynamic>> _psMaps(Object? v) => (v is List ? v : const []).whereType<Map>().map((m) => m.cast());

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

class AlignmentStatusWire {
  final AlignmentStatus status;
  final int? samplesDone;
  final int? samplesTotal;
  final String? builtAt;
  final String? error;
  final bool stale;
  const AlignmentStatusWire({
    this.status = AlignmentStatus.none,
    this.samplesDone,
    this.samplesTotal,
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

/// A book's `readAloudSync`. A server before the read-aloud sync has none,
/// which reads as unavailable for want of a read-aloud EPUB.
ReadAloudSync readAloudSyncFromJson(Map<String, dynamic>? j) => j == null
    ? const ReadAloudSync(unavailableReason: ReadAloudSyncReason.noMediaOverlayEpub)
    : ReadAloudSync(
        mode: _psEnum(ReadAloudSyncMode.values, j['mode']) ?? ReadAloudSyncMode.auto,
        state: _psEnum(ReadAloudSyncState.values, j['state']) ?? ReadAloudSyncState.unavailable,
        unavailableReason: _psEnum(ReadAloudSyncReason.values, j['unavailableReason']),
        audioDurationSeconds: _psDouble(j['audioDurationSeconds']),
        overlayDurationSeconds: _psDouble(j['overlayDurationSeconds']),
      );

/// One kind of the book's files, as BookOrbit's `bookFormatEntries` groups
/// them: the plain EPUB, the read-aloud EPUB, or the audio tracks together.
class PositionSyncEditionFiles {
  final String? title;
  final String formatName;
  final List<int> fileIds;
  final int sizeBytes;
  const PositionSyncEditionFiles({this.title, required this.formatName, this.fileIds = const [], this.sizeBytes = 0});
}

/// The book's own files, read from its detail.
class PositionSyncBookInfo {
  final String? coverVersion;
  final String? language;
  final PositionSyncEditionFiles? ebook;
  final PositionSyncEditionFiles? readAlong;
  final PositionSyncEditionFiles? audiobook;
  final ReadAloudSync readAloudSync;
  const PositionSyncBookInfo({
    this.coverVersion,
    this.language,
    this.ebook,
    this.readAlong,
    this.audiobook,
    this.readAloudSync = const ReadAloudSync(),
  });

  static const _formatNames = {
    'djvu': 'DjVu document',
    'epub': 'EPUB e-book',
    'kepub': 'KEPUB e-book',
    'pdf': 'PDF document',
    'cbz': 'CBZ comic',
    'cbr': 'CBR comic',
    'cb7': 'CB7 comic',
    'mobi': 'MOBI e-book',
    'azw3': 'AZW3 e-book',
    'azw': 'AZW e-book',
    'fb2': 'FictionBook',
    'm4b': 'M4B audiobook',
    'mp3': 'MP3 audio',
    'm4a': 'M4A audio',
    'opus': 'Opus audio',
    'ogg': 'OGG audio',
    'flac': 'FLAC audio',
  };
  static const _readAlongName = 'Read-aloud EPUB';

  static String _base(Map<String, dynamic> f) {
    final name = _psString(f['filename']) ?? (_psString(f['absolutePath']) ?? '').split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    // Read-aloud EPUBs are often named "<title>.readaloud.epub".
    return base.replaceFirst(RegExp(r'\.readaloud$', caseSensitive: false), '');
  }

  /// What several files' names share, as the web panel titles an edition;
  /// a share too short to read falls back to the first name.
  static String? _title(List<Map<String, dynamic>> files) {
    final bases = [for (final f in files) _base(f)].where((b) => b.isNotEmpty).toList();
    if (bases.isEmpty) return null;
    if (bases.length == 1) return bases.first;
    var stem = bases.first;
    for (final b in bases.skip(1)) {
      var i = 0;
      while (i < stem.length && i < b.length && stem[i] == b[i]) {
        i++;
      }
      stem = stem.substring(0, i);
    }
    stem = stem.replaceAll(RegExp(r'[\s\-_.(\[]+$'), '');
    return stem.length >= 3 ? stem : bases.first;
  }

  static PositionSyncEditionFiles? _edition(List<Map<String, dynamic>> files, String formatName) => files.isEmpty
      ? null
      : PositionSyncEditionFiles(
          title: _title(files),
          formatName: formatName,
          fileIds: [for (final f in files) if (_psInt(f['id']) != null) _psInt(f['id'])!],
          sizeBytes: files.fold(0, (sum, f) => sum + (_psInt(f['sizeBytes']) ?? 0)),
        );

  factory PositionSyncBookInfo.fromDetail(Map<String, dynamic> detail) {
    final plain = <Map<String, dynamic>>[];
    final narrated = <Map<String, dynamic>>[];
    final audio = <Map<String, dynamic>>[];
    for (final f in _psMaps(detail['files'])) {
      if (f['role'] != 'primary' && f['role'] != 'content') continue;
      final format = (f['format'] as String?)?.toLowerCase();
      if (format == null) continue;
      if (BookOrbitMapper.isAudioFormat(format)) {
        audio.add(f);
      } else if (format == 'epub') {
        (_psMap(f['mediaOverlay'])?['available'] == true ? narrated : plain).add(f);
      }
    }
    final audioFormat = audio.isEmpty ? null : (audio.first['format'] as String).toLowerCase();
    return PositionSyncBookInfo(
      coverVersion: _psString(detail['coverVersion']),
      language: _psString(detail['language']),
      ebook: _edition(plain, _formatNames['epub']!),
      readAlong: _edition(narrated, _readAlongName),
      audiobook: audioFormat == null ? null : _edition(audio, _formatNames[audioFormat] ?? audioFormat.toUpperCase()),
      readAloudSync: readAloudSyncFromJson(_psMap(detail['readAloudSync'])),
    );
  }
}

/// How far each of the book's files is, 0..100, and the audiobook's
/// playback position.
class PositionSyncProgressWire {
  final Map<int, double> files;
  final double? audio;
  const PositionSyncProgressWire({this.files = const {}, this.audio});
}

class ReadAloudCandidateFileWire {
  final int id;
  final String filename;
  const ReadAloudCandidateFileWire({required this.id, required this.filename});
}

class ReadAloudJobWire {
  final String id;
  final int bookId;
  final ReadAloudJobStatus status;
  final String stage;
  final double progress;
  final int? queuePosition;
  final String? errorCode;
  final bool cancelRequested;
  final bool cancellable;
  final bool canManage;
  final String? updatedAt;
  final String? dismissedAt;
  final String? retryableUntil;
  const ReadAloudJobWire({
    required this.id,
    required this.bookId,
    required this.status,
    this.stage = 'queued',
    this.progress = 0,
    this.queuePosition,
    this.errorCode,
    this.cancelRequested = false,
    this.cancellable = false,
    this.canManage = false,
    this.updatedAt,
    this.dismissedAt,
    this.retryableUntil,
  });

  /// Null for a payload without an id or a status this build knows.
  static ReadAloudJobWire? fromJson(Map<String, dynamic>? j) {
    final id = _psString(j?['id']);
    final status = _psEnum(ReadAloudJobStatus.values, j?['status']);
    if (j == null || id == null || status == null) return null;
    return ReadAloudJobWire(
      id: id,
      bookId: _psInt(j['bookId']) ?? 0,
      status: status,
      stage: _psString(j['stage']) ?? 'queued',
      progress: _psDouble(j['progress']) ?? 0,
      queuePosition: _psInt(j['queuePosition']),
      errorCode: _psString(j['errorCode']),
      cancelRequested: j['cancelRequested'] == true,
      cancellable: j['cancellable'] == true,
      canManage: j['canManage'] == true,
      updatedAt: _psString(j['updatedAt']),
      dismissedAt: _psString(j['dismissedAt']),
      retryableUntil: _psString(j['retryableUntil']),
    );
  }

  bool get active =>
      status == ReadAloudJobStatus.queued ||
      status == ReadAloudJobStatus.processing ||
      status == ReadAloudJobStatus.awaitingReview;

  bool get running => status == ReadAloudJobStatus.queued || status == ReadAloudJobStatus.processing;

  bool get completed => status == ReadAloudJobStatus.completed || status == ReadAloudJobStatus.completedWithWarnings;
}

/// `GET /books/:id/read-aloud`: whether upstream's generator can run on the
/// book, and its latest job.
class ReadAloudCapabilityWire {
  final bool workerConfigured;
  final bool eligible;
  final ReadAloudReason? reason;
  final List<String> supportedLanguages;
  final List<ReadAloudCandidateFileWire> epubFiles;
  final List<int> audioFileIds;
  final int existingReadAlongs;
  final ReadAloudJobWire? latestJob;
  const ReadAloudCapabilityWire({
    this.workerConfigured = false,
    this.eligible = false,
    this.reason,
    this.supportedLanguages = const [],
    this.epubFiles = const [],
    this.audioFileIds = const [],
    this.existingReadAlongs = 0,
    this.latestJob,
  });

  factory ReadAloudCapabilityWire.fromJson(Map<String, dynamic> j) => ReadAloudCapabilityWire(
        workerConfigured: j['workerConfigured'] == true,
        eligible: j['eligible'] == true,
        reason: _psEnum(ReadAloudReason.values, j['reason']),
        supportedLanguages: [for (final l in (j['supportedLanguages'] as List? ?? const [])) if (l is String) l],
        epubFiles: [
          for (final f in _psMaps(j['epubFiles']))
            if (_psInt(f['id']) != null) ReadAloudCandidateFileWire(id: _psInt(f['id'])!, filename: _psString(f['filename']) ?? ''),
        ],
        audioFileIds: [for (final f in _psMaps(j['audioFiles'])) if (_psInt(f['id']) != null) _psInt(f['id'])!],
        existingReadAlongs: (j['existingReadAlongs'] as List?)?.length ?? 0,
        latestJob: ReadAloudJobWire.fromJson(_psMap(j['latestJob'])),
      );
}

/// What a new read-aloud job is made from, as upstream's dialog sends it.
class ReadAloudRequest {
  final int epubFileId;
  final List<int> audioFileIds;
  final String language;

  /// 'sentence' or 'word'.
  final String granularity;
  const ReadAloudRequest(
      {required this.epubFileId, required this.audioFileIds, required this.language, this.granularity = 'sentence'});

  Map<String, dynamic> toJson() =>
      {'epubFileId': epubFileId, 'audioFileIds': audioFileIds, 'language': language, 'granularity': granularity};
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

class PositionSyncPermissions {
  final bool align;
  final bool generate;
  final bool abs;
  const PositionSyncPermissions({this.align = false, this.generate = false, this.abs = false});
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

  /// [fresh] reads the detail past its cache, for after a job added a file.
  Future<PositionSyncBookInfo> positionSyncBookInfo(int bookId, {bool fresh = false}) =>
      _ps(() async => PositionSyncBookInfo.fromDetail(await _detail('$bookId', fresh: fresh)));

  Future<PositionSyncPermissions> positionSyncPermissions() async => PositionSyncPermissions(
        // One /auth/me per ten minutes, not one per sheet (bookorbit_perf.dart).
        align: await _forkLoadPermissions().then((_) => _can('library_edit_metadata')),
        generate: await _can('library_generate_read_aloud'),
        abs: await _can('audiobookshelf_sync'),
      );

  /// Each file's progress and, for a book with audio, the playback position.
  Future<PositionSyncProgressWire> positionSyncProgress(int bookId) => _ps(() async {
        final detail = await _detail('$bookId');
        final rows = await _boGet('/books/$bookId/progress') as List<dynamic>? ?? const [];
        final files = <int, double>{};
        for (final r in rows.whereType<Map<String, dynamic>>()) {
          final id = _psInt(r['fileId']);
          final pct = _psDouble(r['percentage']);
          if (id != null && pct != null) files[id] = pct;
        }
        double? audio;
        if (BookOrbitApiService._detailHasAudio(detail)) {
          final p = await _itemProgress('$bookId', detail: detail);
          final fraction = (p?['progress'] as num?)?.toDouble();
          if (fraction != null) audio = p?['isFinished'] == true ? 100 : fraction * 100;
        }
        return PositionSyncProgressWire(files: files, audio: audio);
      });

  String positionSyncAbsCoverUrl(String absLibraryItemId) =>
      BookOrbitMediaProxy.instance.urlFor('/api/v1${_absPath(absLibraryItemId)}/cover');

  /// The book's page in BookOrbit's web app with its read-aloud job open,
  /// where a job is reviewed.
  String readAloudReviewUrl(int bookId) => '$_cleanBaseUrl/book/$bookId?tab=files&readAloud=details';

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

  // Upstream's read-aloud sync and generator.

  /// Turns the book's read-aloud sync on ('auto') or off; the server answers
  /// with the book, which replaces the cached detail.
  Future<ReadAloudSync> setReadAloudSyncMode(int bookId, ReadAloudSyncMode mode) => _ps(() async {
        final d = _psMap(await _boPatch('/books/$bookId/read-aloud-sync', {'mode': mode.name}));
        if (d == null) throw const PositionSyncRequestFailure(0, 'empty answer');
        final k = _key('$bookId');
        BookOrbitApiService._details[k] = d;
        BookOrbitApiService._detailAt[k] = DateTime.now();
        return readAloudSyncFromJson(_psMap(d['readAloudSync']));
      });

  Future<ReadAloudCapabilityWire> readAloudCapability(int bookId) => _ps(() async =>
      ReadAloudCapabilityWire.fromJson(await _boGet('/books/$bookId/read-aloud') as Map<String, dynamic>));

  Future<ReadAloudJobWire?> readAloudJob(String jobId) =>
      _ps(() async => ReadAloudJobWire.fromJson(_psMap(await _boGet('/read-aloud-jobs/${Uri.encodeComponent(jobId)}'))));

  Future<ReadAloudJobWire?> createReadAloudJob(int bookId, ReadAloudRequest request) => _ps(() async =>
      ReadAloudJobWire.fromJson(_psMap(await _boPost('/books/$bookId/read-aloud-jobs', request.toJson()))));

  Future<ReadAloudJobWire?> cancelReadAloudJob(String jobId) =>
      _ps(() async => ReadAloudJobWire.fromJson(_psMap(await _boDelete('/read-aloud-jobs/${Uri.encodeComponent(jobId)}'))));

  Future<ReadAloudJobWire?> retryReadAloudJob(String jobId) => _ps(() async =>
      ReadAloudJobWire.fromJson(_psMap(await _boPost('/read-aloud-jobs/${Uri.encodeComponent(jobId)}/retry'))));

  /// The reader's saved narration language, or null; never throws, since it
  /// only fills a default.
  Future<String?> readAloudDefaultLanguage() async {
    try {
      final r = _psMap(await _boGet('/user-preferences/read-aloud'));
      return _psString(_psMap(r?['settings'])?['defaultLanguage']);
    } catch (e) {
      debugPrint('[BookOrbit] read-aloud preferences: $e');
      return null;
    }
  }

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
        return [for (final i in _psMaps(r?['items'])) AbsBookStateWire.fromJson(i)];
      });
}
