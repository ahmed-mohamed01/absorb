// Fork-owned: picks a release by hand for one format of a BookOrbit
// Watchlist work, inside the app. Opened from the Search button of the
// watchlist book sheet. See FORK_NOTES.md.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/book_requests.dart';
import '../../widgets/absorb_page_header.dart';
import '../../widgets/overlay_toast.dart';

/// BookOrbit asks its indexers for the work without writing a request; the
/// release picked is grabbed under the work's request for that format. Pops
/// with true once something was grabbed.
class WatchlistReleaseScreen extends StatefulWidget {
  final BookOrbitApiService api;
  final String workId;
  final String format;
  final String title;
  final String authorName;
  final String? coverUrl;
  final Map<String, String> coverHeaders;

  const WatchlistReleaseScreen({
    super.key,
    required this.api,
    required this.workId,
    required this.format,
    required this.title,
    required this.authorName,
    this.coverUrl,
    this.coverHeaders = const {},
  });

  static Future<bool> open(
    BuildContext context, {
    required BookOrbitApiService api,
    required String workId,
    required String format,
    required String title,
    required String authorName,
    String? coverUrl,
    Map<String, String> coverHeaders = const {},
  }) async {
    final grabbed = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => WatchlistReleaseScreen(
          api: api,
          workId: workId,
          format: format,
          title: title,
          authorName: authorName,
          coverUrl: coverUrl,
          coverHeaders: coverHeaders,
        ),
      ),
    );
    return grabbed == true;
  }

  @override
  State<WatchlistReleaseScreen> createState() => _WatchlistReleaseScreenState();
}

class _WatchlistReleaseScreenState extends State<WatchlistReleaseScreen> {
  BookRequestReleases? _result;
  // How each indexer delivers, by indexer id: torrent, usenet or shelfmark.
  Map<int, String> _delivery = const {};
  bool _loading = true;
  String? _error;
  int _generation = 0;
  String? _grabbing;

  bool get _audio => widget.format == 'audiobook';

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await widget.api.watchlistSearchReleases(widget.workId, widget.format);
    if (!mounted || generation != _generation) return;
    final raw = res.result;
    setState(() {
      _loading = false;
      _error = raw == null ? (res.error ?? 'The search failed') : null;
      if (raw == null) return;
      _result = BookRequestReleases.fromJson(raw);
      _delivery = {
        for (final i in (raw['indexers'] as List? ?? const []).whereType<Map>())
          if (i['indexerId'] is num && i['delivery'] is String)
            (i['indexerId'] as num).toInt(): i['delivery'] as String,
      };
    });
  }

  Future<void> _grab(BookRequestRelease release) async {
    if (_grabbing != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Grab this release?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(release.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              [
                release.indexerName,
                if (release.sizeBytes != null) formatReleaseSize(release.sizeBytes),
                if (release.formats.isNotEmpty) release.formats.join(', ').toUpperCase(),
              ].join(' · '),
            ),
            if (release.vipOnly) ...[
              const SizedBox(height: 8),
              Text(
                'The tracker only lets VIP accounts download this one.',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Grab')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _grabbing = release.guid);
    final res = await widget.api.watchlistGrabRelease(widget.workId, widget.format, release.indexerId, release.guid);
    if (!mounted) return;
    setState(() => _grabbing = null);
    if (res.error != null) {
      showOverlayToast(context, 'Could not grab it: ${res.error}', icon: Icons.error_outline_rounded);
      return;
    }
    showOverlayToast(context, 'Sent to the download client', icon: Icons.download_rounded);
    Navigator.pop(context, true);
  }

  void _close() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final result = _result;
    // BookOrbit ranks the list by its release profile; the order is kept.
    final releases = result?.releases ?? const <BookRequestRelease>[];

    // Leaving mid-grab would drop the outcome the sheet follows the request by.
    return PopScope(
      canPop: _grabbing == null,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: AbsorbPageHeader(
                        title: _audio ? 'Find an audiobook release' : 'Find an ebook release',
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Search again',
                      icon: Icon(Icons.refresh_rounded, color: cs.onSurfaceVariant),
                      onPressed: _loading || _grabbing != null ? null : _search,
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                      onPressed: _grabbing != null ? null : _close,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    _header(context),
                    const SizedBox(height: 10),
                    if (_loading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
                            const SizedBox(height: 14),
                            Text(
                              'Asking every indexer. This can take a minute.',
                              textAlign: TextAlign.center,
                              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    else if (_error != null)
                      _retryBlock(context, _error!, cs.error)
                    else if (result != null) ...[
                      _sources(context, result),
                      const SizedBox(height: 8),
                      if (releases.isEmpty) _retryBlock(context, _emptyText(result), cs.onSurfaceVariant),
                      for (final r in releases) _releaseRow(context, r),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _retryBlock(BuildContext context, String text, Color color) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(color: color),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _search, child: const Text('Retry')),
        ],
      ),
    );
  }

  static String _emptyText(BookRequestReleases r) {
    if (r.configuredIndexers == 0) return 'No release found: BookOrbit has no indexers set up.';
    if (r.enabledIndexers == 0) return 'No release found: every indexer is switched off.';
    if (r.indexers.isEmpty && r.uncoveredIndexers > 0) return 'No release found: no indexer carries this format.';
    return 'No releases were found.';
  }

  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final box = Container(
      width: 44,
      height: 64,
      color: cs.surfaceContainerHighest,
      child: Icon(_audio ? Icons.headphones_rounded : Icons.menu_book_rounded, size: 18, color: cs.onSurfaceVariant),
    );
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: widget.coverUrl == null
              ? box
              : CachedNetworkImage(
                  imageUrl: widget.coverUrl!,
                  httpHeaders: widget.coverHeaders,
                  width: 44,
                  height: 64,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => box,
                  errorWidget: (_, __, ___) => box,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                [if (widget.authorName.isNotEmpty) widget.authorName, _audio ? 'Audiobook' : 'Ebook'].join(' · '),
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sources(BuildContext context, BookRequestReleases r) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    String failure(String? code) => switch (code) {
      'unauthorized' => 'not signed in',
      'throttled' => 'rate limited',
      'timeout' => 'timed out',
      'unreachable' => 'unreachable',
      'unsupportedMedium' => 'does not carry this format',
      _ => 'failed',
    };
    final count = r.releases.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count == 1 ? '1 release' : '$count releases',
          style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
        ),
        if (r.indexers.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final i in r.indexers)
                _chip(
                  i.ok ? '${i.name} · ${i.count}' : '${i.name} · ${failure(i.failure)}',
                  i.ok ? (i.count > 0 ? cs.primary : cs.onSurfaceVariant) : cs.error,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(6)),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
    ),
  );

  static String? _age(DateTime? at) {
    if (at == null) return null;
    final days = DateTime.now().difference(at).inDays;
    if (days < 1) return 'today';
    if (days < 60) return '${days}d old';
    if (days < 730) return '${days ~/ 30}mo old';
    return '${days ~/ 365}y old';
  }

  static String? _protocol(String? delivery) => switch (delivery) {
    null => null,
    'torrent' => 'Torrent',
    'usenet' => 'Usenet',
    'shelfmark' || 'file' => 'Direct',
    final d => d,
  };

  static String _mismatch(Map failure) => switch (failure['code']) {
    'formatUnknown' => 'format not stated',
    'format' => 'wrong format',
    'fileLayoutUnknown' => 'file layout not stated',
    'fileLayout' => 'wrong file layout',
    'bitrate' => 'bitrate too low',
    'channels' => 'wrong channels',
    'languageUnknown' => 'language not stated',
    'language' => 'wrong language',
    'source' => 'source not allowed',
    'seeders' => 'too few seeders',
    'sizeUnknown' => 'size not stated',
    'size' => 'too large',
    'freeleech' => 'not freeleech',
    'vipOnly' => 'VIP only',
    final c => '$c',
  };

  /// What the release profile has against it, or null when it matched a
  /// tier or no profile is set.
  static String? _warning(BookRequestRelease r) {
    final m = r.raw['profileMismatch'];
    if (m is! Map) return null;
    final failures = [for (final f in (m['failures'] as List? ?? const []).whereType<Map>()) _mismatch(f)];
    final tier = '${m['tierName'] ?? ''}'.trim();
    final head = tier.isEmpty ? 'Misses the release profile' : 'Misses $tier';
    return failures.isEmpty ? head : '$head: ${failures.join(', ')}';
  }

  Widget _releaseRow(BuildContext context, BookRequestRelease r) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final busy = _grabbing == r.guid;
    final grabs = (r.raw['grabs'] as num?)?.toInt();
    final facts = [
      r.indexerName,
      if (r.sizeBytes != null) formatReleaseSize(r.sizeBytes),
      if (r.seeders != null) '${r.seeders} seeders' else if (grabs != null) '$grabs grabs',
      ?_age(r.publishedAt),
      ?_protocol(_delivery[r.indexerId]),
    ];
    final warning = _warning(r);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: _grabbing != null && !busy ? 0.6 : 1,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.title, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(facts.join(' · '), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (r.tierName != null)
                    _chip(r.tierName!, Colors.green)
                  else
                    _chip('Score ${r.score.round()}', cs.primary),
                  for (final f in r.formats) _chip(f.toUpperCase(), cs.onSurfaceVariant),
                  if (r.language != null) _chip(r.language!.toUpperCase(), cs.onSurfaceVariant),
                  if (r.freeleech) _chip('Freeleech', Colors.green),
                  if (r.vipOnly) _chip('VIP only', cs.error),
                  if (r.alreadyGrabbed) _chip('Grabbed before', Colors.orange),
                ],
              ),
              if (warning != null) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(warning, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: busy
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 10),
                            Text('Grabbing', style: tt.bodySmall),
                          ],
                        ),
                      )
                    : FilledButton.tonal(
                        onPressed: _grabbing != null ? null : () => _grab(r),
                        child: const Text('Grab'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
