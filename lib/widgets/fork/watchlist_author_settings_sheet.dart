// Fork-owned: the watch settings of a followed BookOrbit author, behind the
// author sheet's edit pencil in place of Absorb's author editor: mode and
// library per format, refresh, pause and unfollow. Also the owned count the
// author sheet shows for a Watchlist author. See FORK_NOTES.md.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/book_requests.dart';
import '../../services/fork/watchlist_info.dart';
import '../overlay_toast.dart';
import 'watchlist_formats_form.dart';

bool isWatchlistAuthorId(String authorId) => authorId.startsWith('watch-author-');

/// `12 of 30 owned` for a Watchlist author's sheet, from the works it
/// lists; null for every library author.
String? watchlistAuthorSubtitle(String authorId, List<Map<String, dynamic>> books) {
  if (!isWatchlistAuthorId(authorId) || books.isEmpty) return null;
  var owned = 0;
  for (final b in books) {
    final info = WatchlistInfo.of(b);
    if (info != null && WatchlistInfo.allFormats.any(info.isOwned)) owned++;
  }
  return '$owned of ${books.length} owned';
}

/// Opens the settings. [onChanged] runs after a saved change, [onUnfollowed]
/// after the author was dropped (this sheet is closed by then).
Future<void> showWatchlistAuthorSettingsSheet(
  BuildContext context, {
  required String authorId,
  required String name,
  required VoidCallback onChanged,
  required VoidCallback onUnfollowed,
}) async {
  final api = context.read<AuthProvider>().apiService;
  if (api is! BookOrbitApiService) return;
  final unfollowed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WatchlistAuthorSettingsSheet(api: api, authorId: authorId, name: name, onChanged: onChanged),
  );
  if (unfollowed == true) onUnfollowed();
}

class _WatchlistAuthorSettingsSheet extends StatefulWidget {
  final BookOrbitApiService api;
  final String authorId;
  final String name;
  final VoidCallback onChanged;

  const _WatchlistAuthorSettingsSheet({
    required this.api,
    required this.authorId,
    required this.name,
    required this.onChanged,
  });

  @override
  State<_WatchlistAuthorSettingsSheet> createState() => _WatchlistAuthorSettingsSheetState();
}

class _WatchlistAuthorSettingsSheetState extends State<_WatchlistAuthorSettingsSheet> {
  bool _loading = true;
  bool _canRequest = false;
  bool _isOwner = true;
  bool _paused = false;
  // No settings came back, so the form holds defaults that must not be saved over the real ones.
  bool _unread = false;
  List<({int id, String name})> _libraries = const [];
  Map<String, WatchlistFormatChoice> _saved = const {};
  Map<String, WatchlistFormatChoice> _formats = const {};
  // The saved folder per format (picked on the web), kept while its library stays.
  Map<String, int?> _folders = const {};
  // The action running: save, refresh, pause or unfollow.
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.api;
    final results = await Future.wait([
      api.watchlistAuthorSettings(widget.authorId),
      api.watchlistBookLibraries(),
      api.bookRequestAccess(),
    ]);
    if (!mounted) return;
    final settings = results[0] as Map<String, dynamic>?;
    final formats = settings?['formats'] as Map?;
    final saved = {
      for (final f in WatchlistInfo.allFormats)
        f: (
          mode: '${(formats?[f] as Map?)?['mode'] ?? 'notify'}',
          libraryId: ((formats?[f] as Map?)?['libraryId'] as num?)?.toInt(),
        ),
    };
    setState(() {
      _folders = {
        for (final f in WatchlistInfo.allFormats) f: ((formats?[f] as Map?)?['folderId'] as num?)?.toInt(),
      };
      _libraries = results[1] as List<({int id, String name})>;
      _canRequest = (results[2] as BookRequestAccess).canRequest;
      _isOwner = settings?['isOwner'] != false;
      _paused = settings?['paused'] == true;
      _unread = settings == null;
      _saved = saved;
      _formats = saved;
      _loading = false;
    });
  }

  bool get _canChange => _canRequest && _isOwner && !_unread;

  bool get _dirty => WatchlistInfo.allFormats.any((f) => _formats[f] != _saved[f]);

  void _setFormats(Map<String, WatchlistFormatChoice> formats) => setState(() => _formats = formats);

  /// Runs [action] as [key]; true when it succeeded.
  Future<bool> _run(String key, Future<String?> Function() action, {String? success, IconData? icon}) async {
    if (_busy != null) return false;
    setState(() => _busy = key);
    final error = await action();
    if (!mounted) return false;
    setState(() => _busy = null);
    if (error != null) {
      showOverlayToast(context, error, icon: Icons.error_outline_rounded);
      return false;
    }
    if (success != null) showOverlayToast(context, success, icon: icon ?? Icons.check_rounded);
    return true;
  }

  Future<void> _save() async {
    final formats = _formats;
    final folders = {
      for (final f in WatchlistInfo.allFormats) f: formats[f]?.libraryId == _saved[f]?.libraryId ? _folders[f] : null,
    };
    final ok = await _run('save',
        () => widget.api.watchlistUpdateAuthor(widget.authorId, formats: formats, folderIds: folders),
        success: 'Watch settings saved');
    if (!ok || !mounted) return;
    setState(() {
      _saved = formats;
      _folders = folders;
    });
    widget.onChanged();
  }

  Future<void> _refresh() async {
    final ok = await _run('refresh', () => widget.api.watchlistRefreshAuthor(widget.authorId),
        success: 'Looking for new books', icon: Icons.refresh_rounded);
    if (ok) widget.onChanged();
  }

  Future<void> _togglePause() async {
    final next = !_paused;
    final ok = await _run('pause', () => widget.api.watchlistUpdateAuthor(widget.authorId, paused: next),
        success: next ? 'Paused' : 'Watching again', icon: next ? Icons.pause_rounded : Icons.play_arrow_rounded);
    if (!ok || !mounted) return;
    setState(() => _paused = next);
    widget.onChanged();
  }

  Future<void> _unfollow() async {
    if (_busy != null) return;
    // Held while the dialog is up, so a second tap cannot open another.
    setState(() => _busy = 'confirm');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop following ${widget.name}?'),
        content: const Text('Their books leave the Watchlist. Books already in your library stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unfollow')),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _busy = null);
    if (confirmed != true) return;
    final ok = await _run('unfollow', () => widget.api.watchlistUnfollowAuthor(widget.authorId),
        success: 'Stopped following ${widget.name}', icon: Icons.visibility_off_rounded);
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewPadding.bottom + 16),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Text(widget.name,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (_paused)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Paused', style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              ),
          ]),
          const SizedBox(height: 4),
          Text('Watch settings', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else ...[
            if (!_canChange)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                    _unread
                        ? 'Could not read this author\'s watch settings. Try again when BookOrbit can be reached.'
                        : _canRequest
                            ? 'Only the person who follows this author can change these.'
                            : 'This account cannot change the Watchlist on this server.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            WatchlistFormatsForm(
              values: _formats,
              libraries: _libraries,
              enabled: _canChange && _busy == null,
              onChanged: _setFormats,
            ),
            if (_canChange) ...[
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: _busy != null || !_dirty || _formats.values.any(watchlistNeedsLibrary) ? null : _save,
                  icon: _busy == 'save'
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save'),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: _actionButton(
                    cs,
                    key: 'refresh',
                    icon: Icons.refresh_rounded,
                    label: 'Refresh',
                    onPressed: _refresh,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionButton(
                    cs,
                    key: 'pause',
                    icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    label: _paused ? 'Resume' : 'Pause',
                    onPressed: _togglePause,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              _actionButton(
                cs,
                key: 'unfollow',
                icon: Icons.visibility_off_rounded,
                label: 'Unfollow',
                onPressed: _unfollow,
                color: cs.error,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _actionButton(ColorScheme cs,
      {required String key, required IconData icon, required String label, required VoidCallback onPressed, Color? color}) {
    final c = color ?? cs.primary;
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: _busy != null ? null : onPressed,
        icon: _busy == key
            ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c))
            : Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: c.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
