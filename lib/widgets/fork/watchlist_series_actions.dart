// Fork-owned: a BookOrbit Watchlist series in Absorb's series views. The
// series sheet shows this action block in place of its own (stats, request
// missing, auto-download and watching for the whole series), and the series
// cards of a Watchlist author show owned/known. Hooked from
// series_books_sheet.dart, author_books_sheet.dart and
// library_grid_tiles.dart. See FORK_NOTES.md.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/fork/watchlist_info.dart';
import '../../services/player_settings.dart';
import '../overlay_toast.dart';

bool isWatchlistSeriesId(String? seriesId) => seriesId != null && seriesId.startsWith('watch-series-');

({int owned, int known}) _ownedOf(List<dynamic> books) {
  var owned = 0, known = 0;
  for (final b in books.whereType<Map<String, dynamic>>()) {
    final info = WatchlistInfo.of(b);
    if (info == null) continue;
    known++;
    if (WatchlistInfo.allFormats.any(info.isOwned)) owned++;
  }
  return (owned: owned, known: known);
}

/// `2 of 5 owned` under a Watchlist series' name; null for other series.
String? watchlistSeriesCount(String? seriesId, List<dynamic> books) {
  if (!isWatchlistSeriesId(seriesId)) return null;
  final c = _ownedOf(books);
  return '${c.owned} of ${c.known} owned';
}

/// [covers] (a series card's stacked covers) with an `owned/known` badge
/// drawn over its count badge, for a Watchlist series.
Widget watchlistSeriesCovers(String? seriesId, List<dynamic> books, Widget covers) {
  if (!isWatchlistSeriesId(seriesId)) return covers;
  final c = _ownedOf(books);
  // Where the stacked covers put their own count badge: inside the front
  // cover, which sits 5 px in per cover behind it (at most two).
  final inset = 6.0 + 5.0 * (books.length.clamp(1, 3) - 1);
  return Stack(children: [
    covers,
    Positioned(
      top: inset,
      right: inset,
      child: Builder(builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.auto_stories_rounded, size: 11, color: cs.onPrimaryContainer),
            const SizedBox(width: 3),
            Text('${c.owned}/${c.known}',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
          ]),
        );
      }),
    ),
  ]);
}

/// The series sheet's action block for a Watchlist series.
class WatchlistSeriesActions extends StatefulWidget {
  final List<Map<String, dynamic>> books;
  final Color accent;

  /// Re-reads the series after a change.
  final Future<void> Function() onChanged;

  const WatchlistSeriesActions({super.key, required this.books, required this.accent, required this.onChanged});

  @override
  State<WatchlistSeriesActions> createState() => _WatchlistSeriesActionsState();
}

class _WatchlistSeriesActionsState extends State<WatchlistSeriesActions> {
  bool _canRequest = false;
  String _requestFormat = 'both';
  // The action running: request, auto or watch.
  String? _busy;

  BookOrbitApiService? get _api {
    final api = context.read<AuthProvider>().apiService;
    return api is BookOrbitApiService ? api : null;
  }

  @override
  void initState() {
    super.initState();
    PlayerSettings.getWatchlistRequestFormat().then((v) {
      if (mounted && v != _requestFormat) setState(() => _requestFormat = v);
    });
    _api?.bookRequestAccess().then((a) {
      if (mounted && a.canRequest != _canRequest) setState(() => _canRequest = a.canRequest);
    });
  }

  /// The formats the request setting covers, ebook first.
  List<String> get _formats => switch (_requestFormat) {
        'ebook' => const ['ebook'],
        'audiobook' => const ['audiobook'],
        _ => WatchlistInfo.allFormats,
      };

  List<WatchlistInfo> get _infos => [for (final b in widget.books) WatchlistInfo.of(b)].whereType<WatchlistInfo>().toList();

  /// Per work, the covered formats that are out, watched and not owned or
  /// on their way.
  Map<String, List<String>> get _missing => {
        for (final info in _infos)
          if (_formats.any((f) => info.formatStatus(f) == 'missing'))
            info.workId: [for (final f in _formats) if (info.formatStatus(f) == 'missing') f],
      };

  /// Per work, the covered formats still to come. Only these are switched:
  /// an auto-download override on a format that is already out makes
  /// BookOrbit grab it on its next pass.
  Map<WatchlistInfo, List<String>> get _upcoming => {
        for (final info in _infos)
          if (_formats.any((f) => _isUpcoming(info, f)))
            info: [for (final f in _formats) if (_isUpcoming(info, f)) f],
      };

  static bool _isUpcoming(WatchlistInfo info, String format) =>
      const {'upcoming', 'unannounced'}.contains(info.formatStatus(format));

  bool get _autoOn {
    final upcoming = _upcoming;
    return upcoming.isNotEmpty && upcoming.entries.every((e) => e.value.every(e.key.effectiveAutoDownload));
  }

  bool get _watchingOn {
    final infos = _infos;
    return infos.isNotEmpty && infos.every((i) => _formats.every((f) => i.isWatching(f)));
  }

  String? get _nextLabel {
    final now = DateTime.now();
    DateTime? best;
    String? label;
    for (final info in _infos) {
      for (final f in _formats) {
        if (info.isOwned(f)) continue;
        final d = info.releaseDateFor(f);
        if (d == null || !d.isAfter(now) || (best != null && !d.isBefore(best))) continue;
        best = d;
        label = WatchlistInfo.releaseLabel(d, precision: info.precisionFor(f));
      }
    }
    return label;
  }

  /// `2 ebooks and 1 audiobook`: what a request of [missing] asks for.
  static String _formatWords(Map<String, List<String>> missing) {
    String count(int n, String word) => n == 1 ? '1 $word' : '$n ${word}s';
    final ebooks = missing.values.where((f) => f.contains('ebook')).length;
    final audiobooks = missing.values.where((f) => f.contains('audiobook')).length;
    return [
      if (ebooks > 0) count(ebooks, 'ebook'),
      if (audiobooks > 0) count(audiobooks, 'audiobook'),
    ].join(' and ');
  }

  Future<void> _run(String key, Future<String?> Function(BookOrbitApiService api) action, String success) async {
    final api = _api;
    if (api == null || _busy != null) return;
    setState(() => _busy = key);
    final error = await action(api);
    if (!mounted) return;
    showOverlayToast(context, error ?? success, icon: error == null ? Icons.check_rounded : Icons.error_outline_rounded);
    await widget.onChanged();
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _requestMissing() async {
    final missing = _missing;
    if (missing.isEmpty || _busy != null) return;
    final n = missing.length;
    // Held while the dialog is up, so a second tap cannot open another.
    setState(() => _busy = 'confirm');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n == 1 ? 'Request 1 book?' : 'Request $n books?'),
        content: Text('BookOrbit will request ${_formatWords(missing)}: the formats that are out, '
            'watched and not in your library yet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Request')),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _busy = null);
    if (confirmed != true) return;
    // One call per format set, so a work missing only its audiobook is not
    // asked for an ebook the owner switched off.
    final byFormat = <String, List<String>>{};
    for (final e in missing.entries) {
      byFormat.putIfAbsent(e.value.length == 2 ? 'both' : e.value.first, () => []).add(e.key);
    }
    await _run('request', (api) async {
      String? firstError;
      for (final e in byFormat.entries) {
        final error = await api.watchlistBulkRequest(e.value, e.key);
        firstError ??= error;
      }
      return firstError;
    }, n == 1 ? 'Requested 1 book' : 'Requested $n books');
  }

  void _toggleAuto() {
    final next = !_autoOn;
    final byFormats = <String, ({List<String> formats, List<String> ids})>{};
    for (final e in _upcoming.entries) {
      byFormats.putIfAbsent(e.value.join(','), () => (formats: e.value, ids: <String>[])).ids.add(e.key.workId);
    }
    _run('auto', (api) async {
      String? firstError;
      for (final group in byFormats.values) {
        final error = await api.watchlistSetAutoDownloadMany(group.ids, group.formats, next);
        firstError ??= error;
      }
      return firstError;
    }, next ? 'Upcoming books download on release' : 'Upcoming books will not download on their own');
  }

  void _toggleWatching() {
    final next = !_watchingOn;
    final ids = [for (final i in _infos) i.workId];
    _run('watch', (api) => api.watchlistBulkSetWatching(ids, _formats, next),
        next ? 'Watching this series' : 'Stopped watching this series');
  }

  Widget _stat(String value, String label, ColorScheme cs, TextTheme tt) => Expanded(
        child: Column(children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      );

  /// Shaped like the series sheet's own action pills.
  Widget _pill(ColorScheme cs, {required String key, required IconData icon, required String label, bool on = false, required VoidCallback onTap}) {
    final color = on ? widget.accent : cs.onSurfaceVariant;
    return Material(
      color: on ? widget.accent.withValues(alpha: 0.14) : cs.onSurface.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy == null ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_busy == key)
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
            else
              Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final counts = _ownedOf(widget.books);
    final missing = _missing.length;
    final infos = _infos;
    // BookOrbit refuses changes to another user's author.
    final canAct = _canRequest && infos.isNotEmpty && infos.every((i) => i.isOwner);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        _stat('${counts.owned} of ${counts.known}', 'Owned', cs, tt),
        _stat('$missing', 'Missing', cs, tt),
        _stat(_nextLabel ?? 'None', 'Next', cs, tt),
      ]),
      if (canAct) ...[
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          if (missing > 0)
            _pill(cs, key: 'request', icon: Icons.playlist_add_rounded, label: 'Request missing ($missing)', on: true, onTap: _requestMissing),
          if (_upcoming.isNotEmpty)
            _pill(cs,
                key: 'auto',
                icon: _autoOn ? Icons.downloading_rounded : Icons.download_outlined,
                label: 'Auto-download new books',
                on: _autoOn,
                onTap: _toggleAuto),
          _pill(cs,
              key: 'watch',
              icon: _watchingOn ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
              label: 'Watching',
              on: _watchingOn,
              onTap: _toggleWatching),
        ]),
      ],
    ]);
  }
}
