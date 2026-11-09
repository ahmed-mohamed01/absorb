import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/bookorbit_match.dart';
import '../../services/fork/metadata_edit_form.dart';
import '../overlay_toast.dart';

/// The picks to save. [covers] holds the cover picked for each of
/// `coverSlots`, by slot; [coverUrl] is the cover without `coverSlots`.
typedef MatchUpdate = ({Map<String, dynamic> metadata, String? coverUrl, Map<String, String> covers});

/// One of a book's covers to compare: `ebook` or `audio`, with a title when
/// the book has both, and whether its lock keeps it as it is.
typedef MatchCoverSlot = ({String slot, String? title, String currentUrl, bool locked});

const _kCoverLocked = 'Locked';
String _kCoverSearching(String slot) => slot == 'audio' ? 'Looking for audiobook covers...' : 'Looking for book covers...';
String _kNoCovers(String slot) => slot == 'audio' ? 'No audiobook covers found.' : 'No book covers found.';

/// Edit metadata's Search online, after BookOrbit's web editor: every source
/// is searched at once and ranked against the book, then a result opens a
/// side by side comparison where each field is kept or taken from that
/// result or another one. Nothing changes until Apply.
class ForkMatchView extends StatefulWidget {
  final ApiService api;
  final String itemId;
  final MatchCurrent current;
  final String? currentCoverUrl;
  final Map<String, String> coverHeaders;
  final bool isAudiobook;

  /// Apply only stages the picks for a later save (the fork's Edit
  /// metadata page), rather than saving them.
  final bool stagesChanges;

  /// The covers to compare, each with its own row and pick. A book with
  /// both runs a second search for the medium it isn't searched as, as
  /// BookOrbit's web editor does. Without these there is one row, which
  /// fills [MatchUpdate.coverUrl].
  final List<MatchCoverSlot>? coverSlots;

  /// Saves the picked values; true when it worked.
  final Future<bool> Function(MatchUpdate update) onApply;

  const ForkMatchView({
    super.key,
    required this.api,
    required this.itemId,
    required this.current,
    required this.onApply,
    this.currentCoverUrl,
    this.coverHeaders = const {},
    this.isAudiobook = true,
    this.stagesChanges = false,
    this.coverSlots,
  });

  @override
  State<ForkMatchView> createState() => _ForkMatchViewState();
}

class _ForkMatchViewState extends State<ForkMatchView> with AutomaticKeepAliveClientMixin {
  late final _titleCtrl = TextEditingController(text: widget.current.title);
  late final _authorCtrl = TextEditingController(text: widget.current.authors.join(', '));
  late final _isbnCtrl = TextEditingController(text: widget.current.isbn);

  List<Map<String, String>> _providers = const [];
  final List<MatchCandidate> _results = [];
  final Map<String, String> _stopped = {};
  StreamSubscription<MatchSearchEvent>? _search;
  bool _streaming = false;
  bool _searched = false;
  String? _searchError;
  bool _showOther = false;
  bool _editSearch = false;
  _ResultFilter _resultFilter = _ResultFilter.all;

  MatchCandidate? _active;
  final Map<MatchField, MatchCandidate> _picks = {};
  final Map<String, MatchCandidate> _coverPicks = {};
  final List<MatchCandidate> _secondResults = [];
  StreamSubscription<MatchSearchEvent>? _secondSearch;
  bool _secondStreaming = false;
  bool _mergeGenres = true;
  _MatchFilter _filter = _MatchFilter.differences;
  bool _showMatching = false;
  final Set<MatchField> _expanded = {};
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    widget.api.bookMatchProviders().then((list) {
      if (mounted && list != null) setState(() => _providers = list);
    });
    _runSearch();
  }

  @override
  void dispose() {
    _search?.cancel();
    _secondSearch?.cancel();
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _isbnCtrl.dispose();
    super.dispose();
  }

  void _runSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    _search?.cancel();
    setState(() {
      _results.clear();
      _stopped.clear();
      _streaming = true;
      _searched = true;
      _searchError = null;
      _active = null;
      _editSearch = false;
    });
    _search = widget.api
        .searchMatches(
          widget.itemId,
          title: _titleCtrl.text,
          author: _authorCtrl.text,
          isbn: _isbnCtrl.text,
          isAudiobook: widget.isAudiobook,
        )
        .listen(
          (event) {
            if (!mounted) return;
            setState(() {
              final c = event.candidate;
              if (c != null) {
                if (!_results.any((r) => r.key == c.key)) _results.add(c);
              } else if (event.provider != null) {
                _stopped[event.provider!] = event.outcome ?? 'failed';
              }
            });
          },
          onError: (Object e) {
            debugPrint('[BookOrbit] match search failed: $e');
            if (mounted) setState(() {
              _streaming = false;
              _searchError = '$e';
            });
          },
          onDone: () {
            if (mounted) setState(() => _streaming = false);
          },
          cancelOnError: true,
        );
    _runSecondSearch();
  }

  /// The medium the book is searched as. The results it gets feed that cover.
  String get _mainSlot {
    final rows = widget.coverSlots;
    final searched = widget.isAudiobook ? 'audio' : 'ebook';
    if (rows == null) return '';
    return rows.any((r) => r.slot == searched) || rows.isEmpty ? searched : rows.first.slot;
  }

  /// Looks for the other medium's covers. The ISBN stays out: it names the
  /// main medium's edition, and some sources would answer with just that.
  void _runSecondSearch() {
    _secondSearch?.cancel();
    final second = widget.coverSlots?.where((r) => r.slot != _mainSlot && !r.locked).firstOrNull;
    setState(() {
      _secondResults.clear();
      _secondStreaming = second != null;
    });
    if (second == null) return;
    _secondSearch = widget.api
        .searchMatches(
          widget.itemId,
          title: _titleCtrl.text,
          author: _authorCtrl.text,
          mediaKind: second.slot == 'audio' ? 'audiobook' : 'ebook',
        )
        .listen(
          (event) {
            final c = event.candidate;
            if (!mounted || c == null) return;
            setState(() {
              if (!_secondResults.any((r) => r.key == c.key)) _secondResults.add(c);
            });
          },
          onError: (Object e) {
            debugPrint('[BookOrbit] second cover search failed: $e');
            if (mounted) setState(() => _secondStreaming = false);
          },
          onDone: () {
            if (mounted) setState(() => _secondStreaming = false);
          },
          cancelOnError: true,
        );
  }

  String _providerLabel(String key) {
    for (final p in _providers) {
      if (p['key'] == key) return p['label'] ?? key;
    }
    if (key == 'audnexus') return 'Audnexus';
    return key.isEmpty ? key : '${key[0].toUpperCase()}${key.substring(1)}';
  }

  List<String> get _providerOrder => [for (final p in _providers) p['key'] ?? ''];

  String _fieldLabel(AppLocalizations l, MatchField field) => switch (field) {
        MatchField.title => l.titleLabel,
        MatchField.subtitle => l.subtitleLabel,
        MatchField.authors => l.authorLabel,
        MatchField.narrators => l.narratorLabel,
        MatchField.series => l.seriesLabel,
        MatchField.description => l.descriptionLabel,
        MatchField.publisher => l.publisherLabel,
        MatchField.published => l.yearLabel,
        MatchField.language => l.languageLabel,
        MatchField.isbn => l.isbnLabel,
        MatchField.genres => l.genresLabel,
      };

  int get _pickCount => _picks.length + _coverPicks.length;

  Future<void> _apply() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _applying = true);
    // Only the main cover came from a result the book matched, so only it
    // links the book to its source.
    final update = buildMatchUpdate(
      widget.current,
      _picks,
      cover: _coverPicks[_mainSlot],
      mergeGenres: _mergeGenres,
    );
    final ok = await widget.onApply((
      metadata: update.metadata,
      coverUrl: update.coverUrl,
      covers: {
        if (widget.coverSlots != null)
          for (final e in _coverPicks.entries) e.key: e.value.coverUrl,
      },
    ));
    if (!mounted) return;
    setState(() {
      _applying = false;
      if (ok) {
        _picks.clear();
        _coverPicks.clear();
        _active = null;
      }
    });
    // Picks that were only staged aren't saved, and the page says so itself.
    if (ok && widget.stagesChanges) return;
    showOverlayToast(context, ok ? l.editMetadataUpdatedFromMatch : l.failedToUpdateMetadata,
        icon: ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded);
  }

  // Peeking at another tab keeps the results and picks.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final active = _active;
    return active == null ? _buildResults(context) : _buildCompare(context, active);
  }

  // Results

  Widget _buildResults(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ranked = rankMatches(_results, widget.current, providerOrder: _providerOrder);
    final strong = ranked.where((r) => r.assessment.tier == MatchTier.strong).toList();
    final possible = ranked.where((r) => r.assessment.tier == MatchTier.possible).toList();
    final other = ranked.where((r) => r.assessment.tier == MatchTier.weak).toList();
    final best = ranked.isNotEmpty && ranked.first.assessment.tier != MatchTier.weak ? ranked.first : null;
    final showEdition = _resultFilter != _ResultFilter.other;
    final showOther = _resultFilter != _ResultFilter.edition;
    final bestShown = best != null && (best.assessment.tier == MatchTier.strong ? showEdition : showOther);
    final counts = <String, int>{};
    for (final r in _results) {
      counts[r.provider] = (counts[r.provider] ?? 0) + 1;
    }
    final sources = [
      ..._providerOrder.where((k) => k.isNotEmpty),
      ...counts.keys.where((k) => !_providerOrder.contains(k)),
    ];
    final empty = [
      for (final k in sources)
        if ((counts[k] ?? 0) == 0 && !_stopped.containsKey(k)) _providerLabel(k),
    ];
    final stopped = [
      for (final e in _stopped.entries)
        '${_providerLabel(e.key)} ${switch (e.value) {
          'timeout' => l.bomatchSourceTimeout,
          'throttled' => l.bomatchSourceBusy,
          _ => l.bomatchSourceFailed,
        }}',
    ];
    final noResults = _searched && !_streaming && _results.isEmpty;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      if (_editSearch || noResults || !_searched) _searchForm(context, l) else _searchSummary(context, l),
      if (_streaming) ...[
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(2), child: const LinearProgressIndicator(minHeight: 2)),
      ],
      const SizedBox(height: 10),
      if (_results.isNotEmpty) ...[
        _segmented<_ResultFilter>(
          context,
          [
            (value: _ResultFilter.all, label: _kAllResults, count: _results.length, icon: null),
            (value: _ResultFilter.edition, label: _kEdition, count: strong.length, icon: Icons.menu_book_rounded),
            (value: _ResultFilter.other, label: _kOther, count: possible.length + other.length, icon: Icons.layers_outlined),
          ],
          _resultFilter,
          (v) => setState(() => _resultFilter = v),
        ),
        const SizedBox(height: 12),
      ],
      if (_searchError != null)
        Text(l.bomatchSearchFailed, style: tt.bodySmall?.copyWith(color: cs.error))
      else if (noResults)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text(l.bomatchNoResults, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
        ),
      if (bestShown) _bestMatch(context, best.candidate, best.assessment),
      if (showEdition)
        _resultGroup(context, bestShown ? _kAlsoEdition : _kThisEdition, [
          for (final r in strong)
            if (!bestShown || r.candidate.key != best.candidate.key) r,
        ]),
      if (showOther)
        _resultGroup(context, _kOtherVersions, [
          for (final r in possible)
            if (!bestShown || r.candidate.key != best.candidate.key) r,
        ]),
      if (showOther && other.isNotEmpty) ...[
        InkWell(
          borderRadius: BorderRadius.circular(_kControlRadius),
          onTap: () => setState(() => _showOther = !_showOther),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Text(l.bomatchOther(other.length),
                  style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(_showOther ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18, color: cs.onSurfaceVariant),
            ]),
          ),
        ),
        if (_showOther) _resultGroup(context, null, other),
      ],
      if (!_streaming && stopped.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(stopped.join(', '), textAlign: TextAlign.center, style: tt.bodySmall?.copyWith(color: cs.error)),
        ),
      if (!_streaming && _results.isNotEmpty && empty.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('$_kNoResultsFrom ${empty.join(', ')}',
              textAlign: TextAlign.center, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
    ]);
  }

  /// What was searched, on one line; Edit opens the form.
  Widget _searchSummary(BuildContext context, AppLocalizations l) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final line = [
      if (_authorCtrl.text.trim().isNotEmpty) _authorCtrl.text.trim(),
      if (_isbnCtrl.text.trim().isNotEmpty) 'ISBN ${_isbnCtrl.text.trim()}',
    ].join(' · ');
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(_kCardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _editSearch = true),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(Icons.search_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_titleCtrl.text.trim().isEmpty ? '-' : _titleCtrl.text.trim(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (line.isNotEmpty)
                  Text(line, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(_kEditSearch, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary)),
          ]),
        ),
      ),
    );
  }

  Widget _searchForm(BuildContext context, AppLocalizations l) {
    final cs = Theme.of(context).colorScheme;
    InputDecoration field(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(_kControlRadius)),
        );
    return Column(children: [
      const SizedBox(height: 8),
      TextField(controller: _titleCtrl, decoration: field(l.titleLabel), onSubmitted: (_) => _runSearch()),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(flex: 3, child: TextField(controller: _authorCtrl, decoration: field(l.authorLabel), onSubmitted: (_) => _runSearch())),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: TextField(controller: _isbnCtrl, decoration: field(l.isbnLabel), onSubmitted: (_) => _runSearch())),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_kControlRadius)),
          ),
          onPressed: _runSearch,
          icon: _streaming
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
              : const Icon(Icons.travel_explore_rounded, size: 18),
          label: Text(_streaming ? l.bomatchSearching : l.bomatchSearchAll),
        ),
      ),
    ]);
  }

  void _open(MatchCandidate c) => setState(() {
        _active = c;
        _expanded.clear();
        _showMatching = false;
      });

  List<MatchField> _differences(MatchCandidate c) => [
        for (final f in MatchField.values)
          if (isActionable(classifyField(widget.current, c, f))) f,
      ];

  Widget _cover(String url, {double width = 48, double? height, BoxFit fit = BoxFit.cover, Map<String, String>? headers}) {
    final cs = Theme.of(context).colorScheme;
    final tall = height ?? width * 1.4;
    final box = Container(
      width: width,
      height: tall,
      color: cs.surfaceContainerHigh,
      child: Icon(Icons.image_not_supported_outlined, size: width * 0.4, color: cs.onSurfaceVariant),
    );
    if (url.isEmpty) return ClipRRect(borderRadius: BorderRadius.circular(6), child: box);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: url,
        // Results point at the sources' own servers, which must not get the
        // account's token.
        httpHeaders: headers,
        width: width,
        height: tall,
        fit: fit,
        placeholder: (_, __) => box,
        errorWidget: (_, __, ___) => box,
      ),
    );
  }

  /// The top result, with what would change and a way straight in.
  Widget _bestMatch(BuildContext context, MatchCandidate c, MatchAssessment a) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final diffs = _differences(c);
    final names = [for (final f in diffs) _fieldLabel(l, f)];
    final line = [
      if (c.authors.isNotEmpty) c.authors.join(', '),
      _providerLabel(c.provider),
      if (c.year.isNotEmpty) c.year,
    ].join(' · ');
    final summary = switch (names.length) {
      0 => _kNothingDiffers,
      1 => '${names[0]} differs',
      2 => '${names[0]} and ${names[1].toLowerCase()} differ',
      _ => '${names[0]}, ${names[1].toLowerCase()} and ${names.length - 2} more differ',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _groupTitle(context, _kBestMatch),
        Material(
          color: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_kCardRadius),
            side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(c),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _cover(c.coverUrl, width: 62),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.title.isEmpty ? '-' : c.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(line, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 4, runSpacing: 4, children: [
                        if (a.isbnMatch) _tag(l.bomatchSameIsbn, Colors.green),
                        if (a.linked) _tag(l.bomatchLinked, Colors.green),
                        if (a.sparse) _tag(l.bomatchFewDetails, cs.onSurfaceVariant),
                      ]),
                    ]),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Text(summary, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _open(c),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_kControlRadius)),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(diffs.isEmpty ? _kReview : '$_kReview ${diffs.length}'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _groupTitle(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
      child: Text(text, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
    );
  }

  Widget _resultGroup(
    BuildContext context,
    String? title,
    List<({MatchCandidate candidate, MatchAssessment assessment})> rows,
  ) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) _groupTitle(context, title),
        Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(_kCardRadius),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 12, endIndent: 12, color: cs.outlineVariant.withValues(alpha: 0.5)),
              _resultRow(context, rows[i].candidate, rows[i].assessment),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _resultRow(BuildContext context, MatchCandidate c, MatchAssessment a) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final diffs = _differences(c).length;
    final head = [_providerLabel(c.provider), if (c.year.isNotEmpty) c.year].join(' · ');
    final line = [
      if (normalizeForMatch(c.title) != normalizeForMatch(widget.current.title) && c.title.isNotEmpty) c.title,
      if (a.isbnMatch) l.bomatchSameIsbn,
      if (a.linked) l.bomatchLinked,
      if (c.narrators.isNotEmpty) 'Read by ${c.narrators.first}',
      if (a.sparse) l.bomatchFewDetails,
    ].join(' · ');
    return InkWell(
      onTap: () => _open(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(children: [
          _cover(c.coverUrl, width: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(head, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (line.isNotEmpty)
                Text(line, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          if (diffs > 0) ...[const SizedBox(width: 8), _tag('$diffs', Colors.orange)],
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
      );

  // Compare
  //
  // Fork redesign: each field shows its values as tiles and the one tapped
  // is the one kept, short values side by side. Fields that already match
  // fold into one line. New text is plain constants (FORK_NOTES rule 4).

  /// Likely matches only: other books' values would be noise beside this one's.
  List<MatchCandidate> get _alternatives => [
        for (final r in rankMatches(_results, widget.current, providerOrder: _providerOrder))
          if (r.assessment.tier != MatchTier.weak) r.candidate,
      ];

  Widget _buildCompare(BuildContext context, MatchCandidate active) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final alternatives = _alternatives;
    final kinds = {for (final f in MatchField.values) f: classifyField(widget.current, active, f)};
    final actionable = [for (final f in MatchField.values) if (isActionable(kinds[f]!)) f];
    final empties = [for (final f in actionable) if (kinds[f] == DiffKind.fill) f];
    final allFields = [for (final f in MatchField.values) if (_showField(f, active, alternatives, _MatchFilter.all)) f];
    final fields = [for (final f in MatchField.values) if (_showField(f, active, alternatives, _filter)) f];
    final matching = _filter == _MatchFilter.all
        ? const <MatchField>[]
        : [for (final f in MatchField.values) if (kinds[f] == DiffKind.same && !fields.contains(f)) f];

    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          _compareHeader(context, active, actionable, empties),
          const SizedBox(height: 12),
          _segmented<_MatchFilter>(
            context,
            [
              (value: _MatchFilter.differences, label: 'Differences', count: actionable.length, icon: null),
              (value: _MatchFilter.all, label: 'All fields', count: allFields.length, icon: null),
              (value: _MatchFilter.empty, label: 'Empty only', count: empties.length, icon: null),
            ],
            _filter,
            (v) => setState(() => _filter = v),
          ),
          const SizedBox(height: 12),
          if (widget.coverSlots != null)
            for (final row in widget.coverSlots!) _coverRow(context, row, active, alternatives)
          else if (active.coverUrl.isNotEmpty || alternatives.any((c) => c.coverUrl.isNotEmpty))
            _coverRow(
              context,
              (slot: '', title: null, currentUrl: widget.currentCoverUrl ?? '', locked: false),
              active,
              alternatives,
            ),
          for (final f in fields) _fieldCard(context, active, f, alternatives),
          if (fields.isEmpty && _filter != _MatchFilter.all)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_filter == _MatchFilter.empty ? _kNoEmpty : _kNoDifferences,
                  textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          if (matching.isNotEmpty) ...[
            _matchingFold(context, matching),
            if (_showMatching) for (final f in matching) _fieldCard(context, active, f, alternatives),
          ],
        ]),
      ),
      _applyBar(context, l),
    ]);
  }

  Widget _compareHeader(
      BuildContext context, MatchCandidate active, List<MatchField> actionable, List<MatchField> empties) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final line = [
      _providerLabel(active.provider),
      if (active.year.isNotEmpty) active.year,
      if (active.narrators.isNotEmpty) 'read by ${active.narrators.first}',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(_kCardRadius)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cover(active.coverUrl, width: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(active.title.isEmpty ? '-' : active.title,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(line, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (actionable.isNotEmpty)
                _pill(context, Icons.done_all_rounded, 'Use all ${actionable.length}', strong: true, onTap: () {
                  setState(() {
                    for (final f in actionable) {
                      _picks[f] = active;
                    }
                    final locked = widget.coverSlots?.any((r) => r.slot == _mainSlot && r.locked) ?? false;
                    if (active.coverUrl.isNotEmpty && !locked) _coverPicks[_mainSlot] = active;
                  });
                }),
              if (empties.isNotEmpty && empties.length != actionable.length)
                _pill(context, Icons.add_rounded, 'Fill ${empties.length} empty', onTap: () {
                  setState(() {
                    // A value already picked from another result stays.
                    for (final f in empties) {
                      _picks.putIfAbsent(f, () => active);
                    }
                  });
                }),
              _pill(context, Icons.swap_horiz_rounded, _kOtherResults, onTap: () => setState(() => _active = null)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _pill(BuildContext context, IconData? icon, String text,
      {required VoidCallback onTap, bool strong = false, bool selected = false}) {
    final cs = Theme.of(context).colorScheme;
    final on = strong || selected;
    return Material(
      color: on ? cs.primary.withValues(alpha: 0.16) : cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kControlRadius),
        side: BorderSide(color: selected ? cs.primary : Colors.transparent),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: on ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? cs.primary : cs.onSurface)),
            ),
          ]),
        ),
      ),
    );
  }

  /// A grey track with a raised, neutral selected segment.
  Widget _segmented<T>(
    BuildContext context,
    List<({T value, String label, int? count, IconData? icon})> items,
    T selected,
    ValueChanged<T> onSelect,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(_kCardRadius)),
      child: Row(children: [
        for (final item in items)
          Expanded(
            child: Semantics(
              button: true,
              selected: item.value == selected,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(item.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: item.value == selected ? cs.surfaceContainerHighest : Colors.transparent,
                    borderRadius: BorderRadius.circular(_kControlRadius),
                    border: Border.all(color: item.value == selected ? cs.outlineVariant : Colors.transparent),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (item.icon != null) ...[
                      Icon(item.icon, size: 15, color: item.value == selected ? cs.onSurface : cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: item.label),
                          if (item.count != null)
                            TextSpan(text: '  ${item.count}', style: const TextStyle(fontWeight: FontWeight.w400)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: item.value == selected ? cs.onSurface : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _matchingFold(BuildContext context, List<MatchField> matching) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final names = matching.map((f) => _fieldLabel(l, f)).toList();
    final text = switch (names.length) {
      1 => '${names[0]} already matches',
      2 => '${names[0]} and ${names[1].toLowerCase()} already match',
      _ => '${names[0]}, ${names[1].toLowerCase()} and ${names.length - 2} more already match',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kCardRadius),
          side: BorderSide(color: cs.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _showMatching = !_showMatching),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              const Icon(Icons.check_circle_outline_rounded, size: 18, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
              Icon(_showMatching ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: cs.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _applyBar(BuildContext context, AppLocalizations l) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final n = _pickCount;
    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(n == 0 ? _kNothingPicked : '$n change${n == 1 ? '' : 's'} picked',
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(n == 0 ? _kTapToPick : (widget.stagesChanges ? _kStagedNote : _kSavedNote),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: n == 0 || _applying ? null : _apply,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_kControlRadius)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: _applying
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                  : Text(l.bomatchApply(n)),
            ),
          ]),
        ),
      ),
    );
  }

  bool _showField(MatchField f, MatchCandidate active, List<MatchCandidate> alternatives, _MatchFilter filter) {
    final kind = classifyField(widget.current, active, f);
    if (_picks.containsKey(f)) return true;
    return switch (filter) {
      _MatchFilter.differences => isActionable(kind),
      _MatchFilter.empty => kind == DiffKind.fill,
      _MatchFilter.all => kind != DiffKind.missing ||
          currentValue(widget.current, f).isNotEmpty ||
          otherValues(f, active, alternatives).isNotEmpty,
    };
  }

  /// One value to pick: the tapped tile is the one kept.
  Widget _tile(
    BuildContext context, {
    required String label,
    String? source,
    required String value,
    required bool chosen,
    required VoidCallback? onTap,
    int maxLines = 3,
  }) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final empty = value.isEmpty;
    return Material(
      color: chosen ? cs.primary.withValues(alpha: 0.10) : cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kControlRadius),
        side: BorderSide(color: chosen ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (source != null) ...[
                Container(
                  width: 15,
                  height: 15,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(4)),
                  child: Text(source.isEmpty ? '?' : source[0].toUpperCase(),
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: cs.primary)),
                ),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chosen ? cs.primary : Colors.transparent,
                  border: Border.all(color: chosen ? cs.primary : cs.outline, width: 1.5),
                ),
                child: chosen ? Icon(Icons.check_rounded, size: 13, color: cs.onPrimary) : null,
              ),
            ]),
            const SizedBox(height: 3),
            Text(empty ? l.bomatchEmpty : value,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium?.copyWith(
                  height: 1.35,
                  color: empty || !chosen ? cs.onSurfaceVariant : cs.onSurface,
                  fontStyle: empty ? FontStyle.italic : null,
                  fontWeight: chosen && !empty ? FontWeight.w600 : null,
                )),
          ]),
        ),
      ),
    );
  }

  /// A cover's choices, art of the slot's shape first. The main cover leads
  /// with the result being compared.
  List<MatchCandidate> _coverChoices(String slot, MatchCandidate active, List<MatchCandidate> alternatives) {
    final main = slot == _mainSlot;
    final seen = <String>{if (main) active.coverUrl};
    final pool = [
      for (final c in main ? alternatives : _secondResults)
        if (c.coverUrl.isNotEmpty && seen.add(c.coverUrl)) c,
    ];
    return [
      if (main && active.coverUrl.isNotEmpty) active,
      ...(slot.isEmpty ? pool : sortByCoverFit(pool, slot, (c) => c.raw['coverShape'] as String?)),
    ];
  }

  Widget _coverRow(BuildContext context, MatchCoverSlot row, MatchCandidate active, List<MatchCandidate> alternatives) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final slot = row.slot;
    final picked = _coverPicks[slot];
    final choices = row.locked ? const <MatchCandidate>[] : _coverChoices(slot, active, alternatives);
    final searching = slot == _mainSlot ? _streaming : _secondStreaming;
    // The whole image shows in a slot's own shape; art of the other shape
    // sits inside it rather than being cropped.
    Widget image(String url, {Map<String, String>? headers}) => switch (slot) {
          'audio' => _cover(url, width: 84, height: 84, fit: BoxFit.contain, headers: headers),
          'ebook' => _cover(url, width: 66, height: 92, fit: BoxFit.contain, headers: headers),
          _ => _cover(url, width: 66, headers: headers),
        };
    Widget option(Widget image, String label, bool chosen, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: chosen ? cs.primary : Colors.transparent, width: 2),
                ),
                child: image,
              ),
              if (chosen)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary),
                    child: Icon(Icons.check_rounded, size: 14, color: cs.onPrimary),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            Text(label,
                style: tt.labelSmall?.copyWith(
                    color: chosen ? cs.primary : cs.onSurfaceVariant, fontWeight: chosen ? FontWeight.w600 : null)),
          ]),
        );
    void pick(MatchCandidate? c) => setState(() {
          if (c == null) {
            _coverPicks.remove(slot);
          } else {
            _coverPicks[slot] = c;
          }
        });
    return _card(
      context,
      title: row.title ?? l.metadataLookupCover,
      kindColor: picked != null ? cs.primary : cs.onSurfaceVariant,
      trailing: row.locked
          ? _kCoverLocked
          : picked != null
              ? 'From ${_providerLabel(picked.provider)}'
              : null,
      highlighted: picked != null,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // Room for the tick, which sits over the cover's corner.
          padding: const EdgeInsets.only(top: 4, right: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (row.locked)
              image(row.currentUrl, headers: widget.coverHeaders)
            else
              option(image(row.currentUrl, headers: widget.coverHeaders), l.bomatchNow, picked == null, () => pick(null)),
            for (final c in choices) ...[
              const SizedBox(width: 10),
              option(image(c.coverUrl), _providerLabel(c.provider), picked?.key == c.key, () => pick(c)),
            ],
            if (!row.locked && choices.isEmpty && slot.isNotEmpty) ...[
              const SizedBox(width: 14),
              SizedBox(
                width: 190,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(searching ? _kCoverSearching(slot) : _kNoCovers(slot),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ),
              ),
            ],
          ]),
        ),
      ],
    );
  }

  Widget _card(
    BuildContext context, {
    required String title,
    required Color kindColor,
    String? trailing,
    bool highlighted = false,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: highlighted ? cs.primary.withValues(alpha: 0.35) : Colors.transparent),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: kindColor)),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
          if (trailing != null) Text(trailing, style: tt.labelSmall?.copyWith(color: kindColor)),
        ]),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }

  Widget _fieldCard(BuildContext context, MatchCandidate active, MatchField f, List<MatchCandidate> alternatives) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final kind = classifyField(widget.current, active, f);
    final picked = _picks[f];
    final source = picked ?? active;
    final fromOther = picked != null && picked.key != active.key;
    final now = currentValue(widget.current, f);
    final incoming = candidateValue(source, f);
    final others = otherValues(f, active, alternatives);
    final (kindLabel, kindColor) = switch (kind) {
      DiffKind.fill => (l.bomatchKindNew, Colors.green),
      DiffKind.change => (l.bomatchKindChange, Colors.orange),
      DiffKind.minor => (l.bomatchKindSmall, cs.onSurfaceVariant),
      DiffKind.same => (l.bomatchKindSame, Colors.green),
      DiffKind.missing => (l.bomatchKindNone, cs.onSurfaceVariant),
    };
    final long = f == MatchField.description;
    final expanded = _expanded.contains(f);
    final maxLines = long ? (expanded ? 1000 : 3) : 3;
    final canUse = kind != DiffKind.missing || fromOther;
    bool short(String v) => v.length <= 26 && !v.contains('\n');
    final sideBySide = !long && f != MatchField.genres && short(now) && short(incoming);

    final nowTile = _tile(context,
        label: l.bomatchNow,
        value: now,
        chosen: picked == null,
        maxLines: maxLines,
        onTap: () => setState(() => _picks.remove(f)));
    final sourceTile = _tile(context,
        label: _providerLabel(source.provider),
        source: _providerLabel(source.provider),
        value: incoming,
        chosen: picked != null,
        maxLines: maxLines,
        onTap: canUse ? () => setState(() => _picks[f] = source) : null);

    final chips = <Widget>[
      if (fromOther)
        _pill(context, null, _chipText(_providerLabel(active.provider), candidateValue(active, f), long),
            onTap: () => setState(() => _picks[f] = active)),
      for (final o in others)
        if (!o.from.any((c) => c.key == source.key))
          _pill(context, null, _chipText(o.from.map((c) => _providerLabel(c.provider)).toSet().join(', '), o.value, long),
              onTap: () => setState(() => _picks[f] = o.from.first)),
    ];

    return _card(
      context,
      title: _fieldLabel(l, f),
      kindColor: picked != null ? cs.primary : kindColor,
      trailing: picked != null ? (fromOther ? l.bomatchFrom(_providerLabel(picked.provider)) : _kPicked) : kindLabel,
      highlighted: picked != null,
      children: [
        if (sideBySide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: nowTile),
            const SizedBox(width: 8),
            Expanded(child: sourceTile),
          ])
        else ...[
          nowTile,
          const SizedBox(height: 8),
          sourceTile,
        ],
        if (f == MatchField.genres && picked != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            _pill(context, Icons.merge_rounded, l.bomatchMerge,
                selected: _mergeGenres, onTap: () => setState(() => _mergeGenres = true)),
            const SizedBox(width: 6),
            _pill(context, Icons.swap_horiz_rounded, l.bomatchReplace,
                selected: !_mergeGenres, onTap: () => setState(() => _mergeGenres = false)),
          ]),
        ],
        if (long && (now.length > 160 || incoming.length > 160)) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _expanded.contains(f) ? _expanded.remove(f) : _expanded.add(f)),
            child: Text(expanded ? _kShowLess : _kReadBoth,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.primary)),
          ),
        ],
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_kAlso, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
            ...chips,
          ]),
        ],
      ],
    );
  }

  /// A short value goes in its chip; a long one only names its sources.
  String _chipText(String sources, String value, bool long) =>
      long || value.length > 24 || value.contains('\n') ? sources : '$sources · ${value.isEmpty ? '-' : value}';
}

enum _MatchFilter { differences, all, empty }

enum _ResultFilter { all, edition, other }

const _kCardRadius = 10.0;
const _kControlRadius = 8.0;

const _kOtherResults = 'Other results';
const _kAllResults = 'All';
const _kEdition = 'Edition';
const _kOther = 'Other';
const _kBestMatch = 'Best match';
const _kThisEdition = 'This edition';
const _kAlsoEdition = 'Also this edition';
const _kOtherVersions = 'Other versions';
const _kNoResultsFrom = 'No results from';
const _kEditSearch = 'Edit';
const _kReview = 'Review';
const _kNothingDiffers = 'Nothing differs from your book';
const _kNoDifferences = 'This result has nothing new for the book.';
const _kNoEmpty = 'This result fills none of the empty fields.';
const _kNothingPicked = 'Nothing picked yet';
const _kTapToPick = 'Tap a value to use it';
const _kStagedNote = 'You review them before saving';
const _kSavedNote = 'Saved to the book on Apply';
const _kPicked = 'Picked';
const _kReadBoth = 'Read both in full';
const _kShowLess = 'Show less';
const _kAlso = 'Also';
