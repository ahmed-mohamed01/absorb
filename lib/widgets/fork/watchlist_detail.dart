part of '../book_detail_sheet.dart';

// Fork-owned: the book sheet for a BookOrbit Watchlist item, one work with an
// edition card per format. book_detail_sheet.dart only picks it when the
// item carries `watchlist`. See FORK_NOTES.md.

const _watchEbookEdge = Color(0xFF6EA8FE);
const _watchAudioEdge = Color(0xFFA07AE0);
const _watchGreen = Color(0xFF4F9D6C);

extension _ForkWatchlistDetail on _BookDetailSheetContentState {
  Widget _buildWatchlistContent(BuildContext context, ColorScheme cs, TextTheme tt,
      AppLocalizations l, WatchlistInfo info) {
    final accent = (PlayerSettings.einkMode ? null : _coverScheme?.primary) ?? cs.primary;
    final metadata = ((_item?['media'] as Map?)?['metadata'] as Map?) ?? const {};
    return _WatchlistDetailBody(
      info: info,
      authorName: '${metadata['authorName'] ?? ''}',
      coverUrl: _coverUrl,
      accent: accent,
      scrollController: widget.scrollController,
      onChanged: _loadItem,
    );
  }
}

class _WatchlistDetailBody extends StatefulWidget {
  final WatchlistInfo info;
  final String authorName;
  final String? coverUrl;
  final Color accent;
  final ScrollController? scrollController;
  final Future<void> Function() onChanged;

  const _WatchlistDetailBody({
    required this.info,
    required this.authorName,
    required this.coverUrl,
    required this.accent,
    required this.scrollController,
    required this.onChanged,
  });

  @override
  State<_WatchlistDetailBody> createState() => _WatchlistDetailBodyState();
}

class _WatchlistDetailBodyState extends State<_WatchlistDetailBody> {
  bool _canRequest = false;
  bool _descExpanded = false;
  // Keys are '<format>:<action>' while that action runs.
  final Set<String> _busy = {};
  final Map<String, Map<String, dynamic>?> _files = {};
  final Set<String> _filesLoading = {};
  // The matched book each format's file was read for, or is being read for.
  final Map<String, int> _filesBookId = {};
  // The last read of each format's book request, with its `requestId`, while
  // the sheet is open; newer than the cached work it came with.
  final Map<String, Map<String, dynamic>> _live = {};
  Timer? _poll;
  bool _polling = false;
  int _missedPolls = 0;

  static const _pollEvery = Duration(seconds: 5);
  static const _maxMissedPolls = 3;
  static const _moving = {'pending', 'approved', 'searching', 'grabbed', 'downloading', 'importing'};

  WatchlistInfo get _info => widget.info;

  BookOrbitApiService? get _api {
    final api = context.read<AuthProvider>().apiService;
    return api is BookOrbitApiService ? api : null;
  }

  @override
  void initState() {
    super.initState();
    final api = _api;
    if (api == null) return;
    api.bookRequestAccess().then((a) {
      if (mounted && a.canRequest != _canRequest) setState(() => _canRequest = a.canRequest);
    });
    _followRequests(all: true);
    _loadFiles();
  }

  @override
  void didUpdateWidget(_WatchlistDetailBody old) {
    super.didUpdateWidget(old);
    _loadFiles();
  }

  /// Reads the file of each format matched to a book it was not read for, so
  /// an edition imported while the sheet is open shows its file too.
  void _loadFiles() {
    final api = _api;
    if (api == null) return;
    for (final format in WatchlistInfo.allFormats) {
      final bookId = _info.matchedBookId(format);
      if (bookId == null) {
        _filesBookId.remove(format);
        _files.remove(format);
        _filesLoading.remove(format);
        continue;
      }
      if (_filesBookId[format] == bookId) continue;
      _filesBookId[format] = bookId;
      _filesLoading.add(format);
      api.watchlistMatchedFile(bookId).then((f) {
        if (!mounted || _filesBookId[format] != bookId) return;
        setState(() {
          _files[format] = f;
          _filesLoading.remove(format);
        });
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Map<String, dynamic>? _liveFor(String format) {
    final live = _live[format];
    return live != null && live['requestId'] == _info.requestIdFor(format) ? live : null;
  }

  /// The request status for [format], from the last read if it is newer.
  String? _statusOf(String format) => _liveFor(format)?['status'] as String? ?? _info.requestStatus(format);

  bool _isMoving(String format) => !_info.isOwned(format) && _moving.contains(_statusOf(format));

  /// Reads the book request of each format ([all]) or of the ones still
  /// moving, then again every few seconds while any is. A change reloads the
  /// item, which the data layer has already patched.
  Future<void> _followRequests({bool all = false}) async {
    _poll?.cancel();
    final api = _api;
    if (api == null || _polling) return;
    final ids = <String, int>{
      for (final f in WatchlistInfo.allFormats)
        if (!_info.isOwned(f) && _info.requestIdFor(f) != null && (all || _isMoving(f))) f: _info.requestIdFor(f)!,
    };
    if (ids.isEmpty) return;
    _polling = true;
    var changed = false;
    var read = false;
    for (final e in ids.entries) {
      final res = await api.watchlistRequestStatus(e.value);
      if (res == null) continue;
      read = true;
      final before = _statusOf(e.key);
      final beforePercent = _liveFor(e.key)?['progressPercent'] ?? _info.requestProgress(e.key);
      _live[e.key] = {...res, 'requestId': e.value};
      if (before != res['status'] || beforePercent != res['progressPercent'] || res['refreshed'] == true) changed = true;
    }
    _polling = false;
    // Offline, signed out of requests or the request is gone: stop asking
    // every few seconds after a few misses in a row.
    _missedPolls = read ? 0 : _missedPolls + 1;
    if (!mounted) return;
    setState(() {});
    if (changed) await widget.onChanged();
    if (!mounted) return;
    if (_missedPolls < _maxMissedPolls && WatchlistInfo.allFormats.any(_isMoving)) {
      _poll = Timer(_pollEvery, _followRequests);
    }
  }

  Future<void> _run(String key, Future<String?> Function(BookOrbitApiService api) action,
      {String? success, IconData successIcon = Icons.check_rounded}) async {
    final api = _api;
    if (api == null || _busy.contains(key)) return;
    setState(() => _busy.add(key));
    final error = await action(api);
    if (!mounted) return;
    if (error != null) {
      showOverlayToast(context, error, icon: Icons.error_outline_rounded);
    } else if (success != null) {
      showOverlayToast(context, success, icon: successIcon);
    }
    await widget.onChanged();
    if (!mounted) return;
    setState(() => _busy.remove(key));
    if (error == null) unawaited(_followRequests(all: true));
  }

  void _request(String format) => _run('$format:request', (api) => api.watchlistRequest(_info.workId, format),
      success: format == 'audiobook' ? 'Audiobook requested' : 'Ebook requested', successIcon: Icons.playlist_add_check_rounded);

  void _setWatching(String format, bool on) =>
      _run('$format:watch', (api) => api.watchlistSetWatching(_info.workId, format, on));

  void _setAutoDownload(String format, bool on) =>
      _run('$format:auto', (api) => api.watchlistSetAutoDownload(_info.workId, format, on));

  Future<void> _searchReleases(String format) async {
    final api = _api;
    if (api == null) return;
    final grabbed = await WatchlistReleaseScreen.open(
      context,
      api: api,
      workId: _info.workId,
      format: format,
      title: _info.title,
      authorName: widget.authorName,
      coverUrl: widget.coverUrl,
      coverHeaders: context.read<LibraryProvider>().mediaHeaders,
    );
    if (!grabbed || !mounted) return;
    await widget.onChanged();
    if (mounted) unawaited(_followRequests(all: true));
  }

  void _openBook(int bookId) => showBookDetailSheet(context, '$bookId');

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).round()} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(20, 8, 20, 32 + MediaQuery.of(context).viewPadding.bottom),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2)),
          ),
        ),
        _header(context, cs, tt),
        if ((_info.description ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          _synopsis(cs, tt, _info.description!.trim()),
        ],
        const SizedBox(height: 20),
        Text('EDITIONS',
            style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        for (final format in WatchlistInfo.allFormats) ...[
          _edition(context, cs, tt, format),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _header(BuildContext context, ColorScheme cs, TextTheme tt) {
    final lib = context.read<LibraryProvider>();
    final year = _info.releaseYear;
    final byline = [widget.authorName, if (year != null) '$year'].where((s) => s.isNotEmpty).join(' · ');
    final series = _info.seriesName;
    final index = _info.seriesIndex;
    final ratings = _info.ratings;
    final placeholder = Container(
      color: cs.surfaceContainerHigh,
      child: Icon(Icons.visibility_rounded, size: 32, color: cs.onSurfaceVariant),
    );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 112,
        height: 168,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.coverUrl == null
            ? placeholder
            : CachedNetworkImage(
                imageUrl: widget.coverUrl!,
                fit: BoxFit.cover,
                httpHeaders: lib.mediaHeaders,
                placeholder: (_, __) => Container(color: cs.surfaceContainerHigh),
                errorWidget: (_, __, ___) => placeholder,
              ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_info.title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)),
          if ((_info.subtitle ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_info.subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
          if (byline.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(byline, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
          if (series != null && series.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.auto_stories_rounded, size: 14, color: widget.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(index == null || index.isEmpty ? series : '$series #$index',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: widget.accent)),
              ),
            ]),
          ],
          if (ratings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in ratings)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
                  ),
                  child: Text('★ ${r.average.toStringAsFixed(1)} ${r.sourceLabel}',
                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                ),
            ]),
          ],
        ]),
      ),
    ]);
  }

  void _toggleDescription() => setState(() => _descExpanded = !_descExpanded);

  Widget _synopsis(ColorScheme cs, TextTheme tt, String description) {
    final style = tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.75), height: 1.45);
    final isHtml = RegExp(r'<[a-zA-Z/][^>]*>').hasMatch(description);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: isHtml
          ? HtmlDescription(html: description, style: style, linkColor: widget.accent)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(description,
                  maxLines: _descExpanded ? null : 4,
                  overflow: _descExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: style),
              if (description.length > 220)
                GestureDetector(
                  onTap: _toggleDescription,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_descExpanded ? 'Show less' : 'Show more',
                        style: tt.labelMedium?.copyWith(color: widget.accent, fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
    );
  }

  Widget _edition(BuildContext context, ColorScheme cs, TextTheme tt, String format) {
    final audio = format == 'audiobook';
    final edge = audio ? _watchAudioEdge : _watchEbookEdge;
    final owned = _info.isOwned(format);
    final good = Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent : _watchGreen;
    final pillColor = owned ? good : watchlistMissing;
    return Container(
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: edge),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: edge.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
                    child: Icon(audio ? Icons.headphones_rounded : Icons.menu_book_rounded, size: 18, color: edge),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(audio ? 'Audiobook' : 'Ebook',
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: pillColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: pillColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(owned ? 'In library' : 'Not in library',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: pillColor)),
                  ),
                ]),
                const SizedBox(height: 10),
                ...(owned ? _ownedBody(cs, tt, format) : _missingBody(cs, tt, format)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _dateLine(TextTheme tt, ColorScheme cs, String format) {
    final text = _info.releaseDateTextFor(format);
    final precision = _info.precisionFor(format);
    final long = WatchlistInfo.longDate(text, precision: precision);
    final label = long == null
        ? 'No release date yet'
        : (WatchlistInfo.releaseStarted(text, precision) ? 'Released $long' : 'Coming $long');
    return Row(children: [
      Icon(Icons.event_rounded, size: 14, color: cs.onSurfaceVariant),
      const SizedBox(width: 6),
      Flexible(child: Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
    ]);
  }

  List<Widget> _ownedBody(ColorScheme cs, TextTheme tt, String format) {
    final bookId = _info.matchedBookId(format);
    final file = _files[format];
    final loading = _filesLoading.contains(format);
    return [
      if (bookId != null)
        CustomPaint(
          painter: WatchlistDashedBorder(color: cs.onSurfaceVariant.withValues(alpha: 0.4), radius: 10, strokeWidth: 1),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: loading
                ? Row(children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurfaceVariant)),
                    const SizedBox(width: 8),
                    Flexible(child: Text('Finding the file', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
                  ])
                : file == null
                    ? Text('No file details', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))
                    : _matchedFile(cs, tt, format, file),
          ),
        ),
      const SizedBox(height: 8),
      _dateLine(tt, cs, format),
      if (bookId != null) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton.icon(
            onPressed: () => _openBook(bookId),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open book', maxLines: 1, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.accent,
              side: BorderSide(color: widget.accent.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    ];
  }

  /// Laid out like BookOrbit's web drawer: what and where on top, then the
  /// folder inside its library, then the file. Paths wrap rather than cut in
  /// the middle, because the end of a path is the part that tells books apart.
  Widget _matchedFile(ColorScheme cs, TextTheme tt, String format, Map<String, dynamic> file) {
    final edge = format == 'audiobook' ? _watchAudioEdge : _watchEbookEdge;
    final count = (file['fileCount'] as int?) ?? 1;
    final bytes = (file['sizeBytes'] as int?) ?? 0;
    final kind = '${file['format'] ?? ''}'.trim().toUpperCase();
    final library = '${file['libraryName'] ?? ''}'.trim();
    final segments = (file['relativeFolder'] as List?)?.map((s) => '$s').toList();
    final folder = segments == null || segments.isEmpty ? '' : segments.join(' / ');
    final name = '${file['fileName'] ?? ''}';
    final muted = tt.labelSmall?.copyWith(color: cs.onSurfaceVariant);
    Widget line(IconData icon, String text, TextStyle? style) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 14, color: cs.onSurfaceVariant)),
          const SizedBox(width: 6),
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: style)),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (kind.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: edge.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(6)),
            child: Text(kind, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: edge)),
          ),
        Text([count == 1 ? '1 file' : '$count files', if (bytes > 0) _size(bytes)].join(' · '), style: muted),
        if (library.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.local_library_outlined, size: 12, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(library, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: muted?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
      ]),
      if (folder.isNotEmpty) ...[
        const SizedBox(height: 8),
        line(Icons.folder_open_outlined, folder, muted),
      ],
      if (name.isNotEmpty) ...[
        const SizedBox(height: 4),
        // Under its folder like BookOrbit's file tree: indented, with an elbow
        // from the folder icon.
        if (folder.isNotEmpty)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 9,
              height: 10,
              margin: const EdgeInsets.only(left: 6, right: 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                  bottom: BorderSide(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                ),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(3)),
              ),
            ),
            Expanded(
              child: line(Icons.insert_drive_file_outlined, name,
                  tt.bodySmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600)),
            ),
          ])
        else
          line(Icons.insert_drive_file_outlined, name,
              tt.bodySmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600)),
      ],
    ]);
  }

  static String? _statusText(String? status) => switch (status) {
        'pending' || 'approved' => 'Requested, waiting to start',
        'searching' => 'Searching for a release',
        'grabbed' => 'Release found, waiting to download',
        'downloading' => 'Downloading',
        'importing' => 'Importing',
        'needs_review' => 'Needs you: pick a file',
        'failed' => 'Request failed',
        'available' => 'Downloaded, waiting for the library',
        'cancelled' => 'The last request was cancelled',
        'rejected' => 'The last request was turned down',
        _ => null,
      };

  Widget _statusLine(ColorScheme cs, TextTheme tt, String format, String status, String text) {
    final live = _liveFor(format);
    final moving = _moving.contains(status);
    final warn = status == 'needs_review' || status == 'failed';
    final color = warn ? watchlistMissing : cs.onSurface;
    final progress = live?['progressPercent'] as int?;
    final label = status == 'downloading' && progress != null && progress > 0 ? '$text $progress%' : text;
    final reason = status == 'failed' ? (live?['message'] as String?) : null;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: moving
            ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: widget.accent))
            : Icon(
                switch (status) {
                  'needs_review' => Icons.priority_high_rounded,
                  'failed' => Icons.error_outline_rounded,
                  'available' => Icons.hourglass_bottom_rounded,
                  _ => Icons.info_outline_rounded,
                },
                size: 16,
                color: warn ? watchlistMissing : widget.accent),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: tt.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
          if (reason != null)
            Text(reason, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    ]);
  }

  List<Widget> _missingBody(ColorScheme cs, TextTheme tt, String format) {
    final status = _statusOf(format);
    final statusText = _statusText(status);
    // A request with work left on the server, or one that landed, takes no new one.
    final busyOnServer = _moving.contains(status) || status == 'needs_review' || status == 'available';
    final authorOff = _info.authorMode(format) == 'off';
    final watching = _info.isWatching(format) && !authorOff;
    final requesting = _busy.contains('$format:request');
    final failed = status == 'failed';
    // BookOrbit refuses changes to another user's author, so they are not offered.
    final canAct = _canRequest && _info.isOwner;
    final showRequest = canAct && !busyOnServer;
    // A release is only picked while nothing is downloading or landed yet.
    final showSearch = canAct && !const {'grabbed', 'downloading', 'importing', 'available'}.contains(status);
    final searchButton = Expanded(
      child: SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          onPressed: () => _searchReleases(format),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: const Text('Search', maxLines: 1, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.accent,
            side: BorderSide(color: widget.accent.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
    return [
      _dateLine(tt, cs, format),
      if (canAct) ...[
        const SizedBox(height: 6),
        _switchRow(
          cs, tt,
          icon: watching ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
          label: 'Watching',
          hint: authorOff ? 'Off for this author' : null,
          value: watching,
          busy: _busy.contains('$format:watch'),
          onChanged: authorOff ? null : (v) => _setWatching(format, v),
        ),
        _switchRow(
          cs, tt,
          icon: Icons.download_for_offline_outlined,
          label: 'Auto-download',
          hint: _info.autoDownload(format) == null ? 'Following the author' : null,
          value: _info.effectiveAutoDownload(format),
          busy: _busy.contains('$format:auto'),
          onChanged: (v) => _setAutoDownload(format, v),
        ),
      ],
      const SizedBox(height: 6),
      if (status != null && statusText != null)
        _statusLine(cs, tt, format, status, statusText)
      else
        Text(
            canAct
                ? 'No file for this format yet. Request it, or search for a release.'
                : 'No file for this format yet.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      if (showSearch || showRequest) ...[
        const SizedBox(height: 10),
        Row(children: [
          if (showSearch) searchButton,
          if (showRequest) ...[
            if (showSearch) const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 40,
                child: FilledButton.icon(
                  onPressed: requesting ? null : () => _request(format),
                  icon: requesting
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                      : Icon(failed ? Icons.refresh_rounded : Icons.playlist_add_rounded, size: 18),
                  label: Text(failed ? 'Retry' : 'Request', maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ],
    ];
  }

  Widget _switchRow(
    ColorScheme cs,
    TextTheme tt, {
    required IconData icon,
    required String label,
    String? hint,
    required bool value,
    required bool busy,
    required ValueChanged<bool>? onChanged,
  }) {
    return Row(children: [
      Icon(icon, size: 18, color: value ? widget.accent : cs.onSurfaceVariant),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: tt.bodyMedium?.copyWith(color: cs.onSurface)),
          if (hint != null) Text(hint, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
      if (busy)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: widget.accent)),
        )
      else
        Switch(value: value, onChanged: onChanged, activeThumbColor: widget.accent),
    ]);
  }
}
