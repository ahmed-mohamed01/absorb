// Fork-owned: "Add an author" for the BookOrbit Watchlist. Searches the
// authors BookOrbit can follow and follows one with a mode and library per
// format. Opened from the first tile of the Watchlist Authors grid. See
// FORK_NOTES.md.
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/library_provider.dart';
import '../../services/api_service.dart';
import '../overlay_toast.dart';
import 'watchlist_formats_form.dart';

/// Opens the sheet. Resolves once it closes.
Future<void> showWatchlistAddAuthorSheet(BuildContext context, BookOrbitApiService api) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WatchlistAddAuthorSheet(api: api),
  );
}

class _WatchlistAddAuthorSheet extends StatefulWidget {
  final BookOrbitApiService api;

  const _WatchlistAddAuthorSheet({required this.api});

  @override
  State<_WatchlistAddAuthorSheet> createState() => _WatchlistAddAuthorSheetState();
}

class _WatchlistAddAuthorSheetState extends State<_WatchlistAddAuthorSheet> {
  static const _minQuery = 2;
  static const _debounce = Duration(milliseconds: 400);

  final _query = TextEditingController();
  Timer? _timer;
  int _generation = 0;
  bool _searching = false;
  String? _error;
  List<Map<String, dynamic>>? _results;

  // The follow form, once a result is picked.
  Map<String, dynamic>? _picked;
  bool _formLoading = false;
  bool _saving = false;
  List<({int id, String name})> _libraries = const [];
  Map<String, WatchlistFormatChoice> _formats = const {};
  // The default destinations, whose folder goes along while its library stays picked.
  Map<String, ({int? libraryId, int? folderId})> _defaults = const {};

  @override
  void dispose() {
    _timer?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _timer?.cancel();
    _timer = Timer(_debounce, _search);
  }

  void _onSubmitted(String _) {
    _timer?.cancel();
    _search();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    final generation = ++_generation;
    if (q.length < _minQuery) {
      setState(() {
        _results = null;
        _error = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final res = await widget.api.watchlistSearchAuthors(q);
    if (!mounted || generation != _generation) return;
    setState(() {
      _searching = false;
      _results = res.results;
      _error = res.error;
    });
  }

  /// The web's defaults: both formats on Notify, each filed where requests of
  /// that format already go when the account can reach that library, else in
  /// the first library.
  Future<void> _pick(Map<String, dynamic> result) async {
    setState(() {
      _picked = result;
      _formLoading = true;
    });
    final loaded = await Future.wait([widget.api.watchlistBookLibraries(), widget.api.watchlistDefaultLibraries()]);
    if (!mounted || _picked != result) return;
    final libraries = loaded[0] as List<({int id, String name})>;
    final defaults = loaded[1] as Map<String, ({int? libraryId, int? folderId})>;
    int? libraryFor(String format) {
      final preferred = defaults[format]?.libraryId;
      if (preferred != null && libraries.any((l) => l.id == preferred)) return preferred;
      return libraries.firstOrNull?.id;
    }

    setState(() {
      _libraries = libraries;
      _defaults = defaults;
      _formats = {
        for (final f in const ['ebook', 'audiobook']) f: (mode: 'notify', libraryId: libraryFor(f)),
      };
      _formLoading = false;
    });
  }

  void _back() => setState(() => _picked = null);

  void _setFormats(Map<String, WatchlistFormatChoice> formats) => setState(() => _formats = formats);

  Future<void> _follow() async {
    final picked = _picked;
    if (picked == null || _saving) return;
    setState(() => _saving = true);
    final error = await widget.api.watchlistFollowAuthor(picked, _formats, folderIds: {
      for (final e in _formats.entries)
        if (e.value.libraryId != null && e.value.libraryId == _defaults[e.key]?.libraryId) e.key: _defaults[e.key]?.folderId,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      showOverlayToast(context, error, icon: Icons.error_outline_rounded);
      return;
    }
    showOverlayToast(context, 'Following ${picked['name'] ?? ''}', icon: Icons.visibility_rounded);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final picked = _picked;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 12),
        Flexible(child: picked == null ? _searchView(context) : _followView(context, picked)),
      ]),
    );
  }

  Widget _searchView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final results = _results;
    Widget body;
    if (_searching && results == null) {
      body = const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    } else if (_error != null) {
      body = _message(cs, tt, _error!);
    } else if (results == null) {
      body = _message(cs, tt, 'Type at least $_minQuery letters of an author\'s name.');
    } else if (results.isEmpty) {
      body = _message(cs, tt, 'No authors found.');
    } else {
      body = ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 16),
        itemCount: results.length,
        itemBuilder: (_, i) => _resultRow(context, results[i]),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text('Add an author', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: SearchBar(
          controller: _query,
          autoFocus: true,
          hintText: 'Search authors',
          leading: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.search_rounded)),
          trailing: [
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
          onChanged: _onQueryChanged,
          onSubmitted: _onSubmitted,
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
        ),
      ),
      Flexible(child: body),
    ]);
  }

  Widget _message(ColorScheme cs, TextTheme tt, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Text(text, textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      );

  Widget _avatar(BuildContext context, Map<String, dynamic> result, double size) {
    final cs = Theme.of(context).colorScheme;
    final name = '${result['name'] ?? ''}'.trim();
    final initials = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    final placeholder = Container(
      color: cs.secondaryContainer,
      alignment: Alignment.center,
      child: Text(initials,
          style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: cs.onSecondaryContainer)),
    );
    final image = result['imageUrl'] as String?;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: image == null || image.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: widget.api.watchlistImageUrl(image),
                httpHeaders: context.read<LibraryProvider>().mediaHeaders,
                fit: BoxFit.cover,
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
              ),
      ),
    );
  }

  Widget _resultRow(BuildContext context, Map<String, dynamic> result) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final count = (result['bookCount'] as num?)?.toInt();
    final inLibrary = result['localAuthorId'] != null;
    final following = result['alreadyMonitoredId'] != null;
    final details = [
      count == null ? 'Book count unknown' : (count == 1 ? '1 book' : '$count books'),
      if (inLibrary) 'In your library',
    ].join(' · ');
    return ListTile(
      leading: _avatar(context, result, 44),
      title: Text('${result['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      trailing: following
          ? Text('Following', style: tt.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w600))
          : FilledButton.tonal(onPressed: () => _pick(result), child: const Text('Follow')),
    );
  }

  Widget _followView(BuildContext context, Map<String, dynamic> picked) {
    final tt = Theme.of(context).textTheme;
    final blocked = _formLoading || _formats.values.any(watchlistNeedsLibrary);
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewPadding.bottom + 16),
      children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Back', onPressed: _saving ? null : _back),
          const SizedBox(width: 4),
          _avatar(context, picked, 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Follow ${picked['name'] ?? ''}',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 12),
        if (_formLoading)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else
          WatchlistFormatsForm(values: _formats, libraries: _libraries, enabled: !_saving, onChanged: _setFormats),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: FilledButton.icon(
            onPressed: blocked || _saving ? null : _follow,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.visibility_rounded, size: 18),
            label: const Text('Start following'),
          ),
        ),
      ],
    );
  }
}
