import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/library_provider.dart';
import '../../screens/chapter_editor_screen.dart';
import '../../services/api_service.dart';
import '../../services/bookorbit_match.dart';
import '../../services/fork/metadata_edit_form.dart';
import 'match_compare_view.dart';
import '../overlay_toast.dart';

// Fork-owned: the Edit metadata page for a BookOrbit book. One scrolling page:
// both covers side by side (tap one to edit it), Search online and Auto-fill,
// then Identity, Catalog, Description and Provider links as sections that fold,
// every field with its own lock. A bottom bar counts the changes and holds
// Reset and Save. Nothing is sent until Save, which saves the fields and the
// locks in one request and then any staged cover. Opened from the book page's
// more menu (`forkOpenEditMetadata`). See FORK_NOTES.md.

// New text stays plain until upstream takes it (FORK_NOTES rule 4).
const _kEditMetadata = 'Edit metadata';
const _kSave = 'Save';
const _kSaved = 'Saved';
const _kNothingToSave = 'Nothing changed';
const _kSearchOnline = 'Search online';
const _kAutoFill = 'Auto-fill';
const _kLockAll = 'Lock all';
const _kUnlockAll = 'Unlock all';
const _kReset = 'Reset';
const _kChapters = 'Chapters';
const _kIdentity = 'Identity';
const _kCatalog = 'Catalog';
const _kDescription = 'Description';
const _kCustomFields = 'Custom fields';
const _kBookCover = 'Book';
const _kAudioCover = 'Audiobook';
const _kBookCoverRow = 'Book cover';
const _kAudioCoverRow = 'Audiobook cover';
const _kFromUrl = 'URL';
const _kFromUrlTitle = 'Cover from a URL';
const _kFromFile = 'File';
const _kFindOnline = 'Find cover online';
const _kRemoveCover = 'Remove cover';
const _kUndoCover = 'Keep the current cover';
String _kCoverStatus(String name, {required bool locked, _StagedCover? staged}) => locked
    ? 'The $name cover is locked. Unlock it to change it.'
    : staged == null
        ? 'Editing the $name cover'
        : staged.remove
            ? 'The $name cover is removed when you save.'
            : 'New $name cover, sent when you save.';
const _kImageUrl = 'Image URL';
const _kUse = 'Use';
const _kCancel = 'Cancel';
const _kDiscardTitle = 'Discard your changes?';
const _kDiscardBody = 'You have edits that are not saved.';
const _kDiscard = 'Discard';
const _kKeepEditing = 'Keep editing';
const _kAddSeries = 'Add series';
const _kNumber = '#';
const _kOf = 'of';
const _kRemove = 'Remove';
const _kPressEnter = 'Press Enter to add';
const _kAddMore = 'Add';
const _kYes = 'Yes';
const _kNo = 'No';
const _kLengthError = 'Try 11h 27m';
const _kYourRating = 'Your rating';
const _kPickDate = 'Pick a date';
const _kClear = 'Clear';
const _kMoreIds = 'More providers';
const _kFewerIds = 'Fewer providers';
const _kProviderLinks = 'Provider links';
const _kMore = 'More';
const _kViewCover = 'View larger';
const _kNoChanges = 'No changes';
const _kEdited = 'edited';
const _kEmpty = 'Empty';
const _kCommunityRatings = 'Community ratings';
const _kNoCovers = 'No covers found';
const _kLoadFailed = 'Could not load this book';
const _kRetry = 'Retry';
const _kCannotEdit = 'You can see this book, but your access to its library does not let you edit it.';
const _kDescriptionHint = 'Bold, lists and links in the description are kept until you change its text.';
String _kFilled(int n, int locked) {
  final kept = locked == 0 ? '' : ' Kept $locked locked ${locked == 1 ? 'field' : 'fields'}.';
  return (n == 0 ? 'Nothing new to fill in.' : 'Filled $n ${n == 1 ? 'field' : 'fields'}. Check them, then Save.') + kept;
}

String _kCheck(List<String> fields) => 'Check ${fields.join(', ')}';
String _kCoverFailed(Object e) => "$e. Everything else saved, and the cover change is still waiting.";
String _kLockNotRestored(Object e) => "Saved, but a cover's lock couldn't be put back: $e";
String _kChanges(int n) => n == 1 ? '1 change' : '$n changes';
String _kLock(String label) => 'Lock $label';
String _kUnlock(String label) => 'Unlock $label';

/// Opens the Edit metadata page for a BookOrbit book.
void forkOpenEditMetadata(BuildContext context, String itemId, String bookTitle) {
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
    builder: (_) => ForkEditMetadataPage(itemId: itemId, bookTitle: bookTitle),
  ));
}

/// A cover change waiting for Save: an image file, an image URL, or none.
typedef _StagedCover = ({String? file, String? url, bool remove});

const _kCardRadius = 10.0;
const _kControlRadius = 8.0;
final _kButtonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_kControlRadius));

class ForkEditMetadataPage extends StatefulWidget {
  final String itemId;
  final String bookTitle;

  const ForkEditMetadataPage({super.key, required this.itemId, required this.bookTitle});

  @override
  State<ForkEditMetadataPage> createState() => _ForkEditMetadataPageState();
}

class _ForkEditMetadataPageState extends State<ForkEditMetadataPage> {
  BookOrbitApiService? _api;
  Map<String, dynamic>? _detail;
  Object? _loadError;
  bool _canEdit = true;
  bool _hasAudio = false;
  List<CustomField> _customFields = const [];
  List<String> _slots = const [];
  String _slot = 'ebook';
  final Map<String, _StagedCover> _staged = {};

  late MetadataEditForm _original;
  late MetadataEditForm _form;
  bool _saving = false;
  bool _filling = false;
  bool _allIds = false;
  final Set<String> _closed = {'description', 'providers'};
  Map<String, String> _originalText = const {};

  // One controller per plain text field, kept in step with [_form].
  final Map<String, TextEditingController> _ctrl = {};
  // The length field shows hours and minutes; the form keeps seconds.
  void _setLength(String v) {
    final t = v.trim();
    if (t.isEmpty) {
      _form.durationSeconds = '';
    } else if (t == formatLength(_original.durationSeconds)) {
      // Untouched minutes keep the book's exact seconds.
      _form.durationSeconds = _original.durationSeconds;
    } else {
      final seconds = parseLength(t);
      if (seconds != null) _form.durationSeconds = '$seconds';
    }
  }

  final List<({TextEditingController name, TextEditingController index, TextEditingController total})> _seriesCtrl = [];

  @override
  void initState() {
    super.initState();
    final api = context.read<AuthProvider>().apiService;
    _api = api is BookOrbitApiService ? api : null;
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    _disposeSeries();
    super.dispose();
  }

  void _disposeSeries() {
    for (final r in _seriesCtrl) {
      r.name.dispose();
      r.index.dispose();
      r.total.dispose();
    }
    _seriesCtrl.clear();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) return;
    setState(() => _loadError = null);
    try {
      final detail = await api.metadataEditDetail(widget.itemId);
      final results = await Future.wait([
        api.canEditBookMetadata(detail),
        api.metadataEditCustomFields(),
      ]);
      if (!mounted) return;
      final slots = [
        for (final m in (detail['coverMedia'] as List? ?? const []))
          if (m == 'audio' || m == 'ebook') '$m',
      ];
      setState(() {
        _detail = detail;
        _canEdit = results[0] as bool;
        _customFields = results[1] as List<CustomField>;
        _hasAudio = api.metadataEditHasAudio(detail);
        // Book first, as BookOrbit shows them.
        _slots = slots.isEmpty ? [_hasAudio ? 'audio' : 'ebook'] : (slots..sort((a, b) => b.compareTo(a)));
        if (!_slots.contains(_slot)) _slot = _slots.first;
        _staged.clear();
        _original = MetadataEditForm.fromDetail(detail);
        _form = _original.copy();
        _syncControllers();
        _originalText = {for (final e in _textFields.entries) e.key: e.value.$1()};
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  // ─── Form plumbing ─────────────────────────────────────────

  Map<String, (String Function(), void Function(String))> get _textFields => {
        'title': (() => _form.title, (v) => _form.title = v),
        'subtitle': (() => _form.subtitle, (v) => _form.subtitle = v),
        'publisher': (() => _form.publisher, (v) => _form.publisher = v),
        'language': (() => _form.language, (v) => _form.language = v),
        'publishedYear': (() => _form.publishedYear, (v) => _form.setYear(v)),
        'pageCount': (() => _form.pageCount, (v) => _form.pageCount = v),
        'isbn13': (() => _form.isbn13, (v) => _form.isbn13 = v),
        'isbn10': (() => _form.isbn10, (v) => _form.isbn10 = v),
        'durationSeconds': (() => formatLength(_form.durationSeconds), _setLength),
        'description': (() => _form.description, (v) => _form.description = v),
        for (final p in kProviderIdFields)
          p.field: (() => _form.providerIds[p.field] ?? '', (v) => _form.providerIds[p.field] = v),
        for (final f in _customFields)
          if (f.type != 'boolean')
            'custom:${f.id}': (() => _form.custom[f.id] == null ? '' : '${_form.custom[f.id]}', (v) {
              final t = v.trim();
              _form.custom[f.id] = t.isEmpty ? null : (f.type == 'number' ? (num.tryParse(t) ?? t) : t);
            }),
      };

  /// Puts [_form]'s values into the text boxes after a reset or a fill.
  void _syncControllers() {
    _textFields.forEach((key, f) {
      final c = _ctrl[key] ??= TextEditingController();
      if (c.text != f.$1()) c.text = f.$1();
    });
    _disposeSeries();
    for (final s in _form.series) {
      _seriesCtrl.add((
        name: TextEditingController(text: s.name),
        index: TextEditingController(text: s.index),
        total: TextEditingController(text: s.total),
      ));
    }
  }

  void _edit(void Function() change) {
    setState(change);
  }

  bool get _dirty =>
      _detail != null &&
      (_staged.isNotEmpty || _form.saveBody(_original, hasAudio: _hasAudio) != null || _invalid.isNotEmpty);

  bool get _lengthInvalid =>
      (_ctrl['durationSeconds']?.text.trim() ?? '').isNotEmpty && parseLength(_ctrl['durationSeconds']!.text) == null;

  /// Fields holding text that can't be saved, which keep Save off.
  List<String> get _invalid => [..._form.invalidFields(_original), if (_lengthInvalid) 'Length'];

  int get _changeCount => _form.changeCount(_original, hasAudio: _hasAudio) + _staged.length;

  bool _textEdited(String key) => (_ctrl[key]?.text ?? '').trim() != (_originalText[key] ?? '').trim();

  bool _locked(String lock) => _form.locks.contains(lock);

  void _toggleLock(String lock) {
    HapticFeedback.selectionClick();
    _edit(() => _locked(lock) ? _form.locks.remove(lock) : _form.locks.add(lock));
  }

  static String _coverLock(String slot) => slot == 'audio' ? 'audioCover' : 'cover';

  List<String> get _allLocks => MetadataEditForm.lockNames(
        hasAudio: _hasAudio,
        coverLocks: [for (final s in _slots) _coverLock(s)],
      );

  // ─── Actions ───────────────────────────────────────────────

  Future<void> _save() async {
    final api = _api;
    if (api == null || _saving || _invalid.isNotEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final body = _form.saveBody(_original, hasAudio: _hasAudio);
    if (body == null && _staged.isEmpty) {
      showOverlayToast(context, _kNothingToSave, icon: Icons.check_rounded);
      return;
    }
    setState(() => _saving = true);
    try {
      // A locked cover can't be replaced, so its lock is lifted for the
      // change and put back after, as the web editor does.
      final lifted = {for (final s in _staged.keys) if (_locked(_coverLock(s))) _coverLock(s)};
      if (body != null || lifted.isNotEmpty) {
        final locks = (_form.locks.difference(lifted).toList()..sort());
        await api.saveMetadataAndLocks(widget.itemId, {
          if (body?['metadata'] != null) 'metadata': body!['metadata'],
          'lockedFields': locks,
        });
      }
      // From here the fields are saved. A cover that fails stays staged for
      // another try, and a lifted lock always goes back on.
      final failed = <String, _StagedCover>{};
      Object? coverError;
      for (final e in _staged.entries) {
        final c = e.value;
        try {
          if (c.remove) {
            await api.clearCover(widget.itemId, e.key);
          } else if (c.file != null) {
            await api.setCoverFile(widget.itemId, e.key, c.file!);
          } else if (c.url != null) {
            await api.setCoverUrl(widget.itemId, e.key, c.url!);
          }
        } catch (error) {
          failed[e.key] = c;
          coverError = error;
        }
      }
      Object? lockError;
      if (lifted.isNotEmpty) {
        try {
          await api.saveMetadataAndLocks(widget.itemId, {'lockedFields': _form.locks.toList()..sort()});
        } catch (error) {
          lockError = error;
        }
      }
      if (!mounted) return;
      context.read<LibraryProvider>().refresh();
      if (lockError != null) {
        showOverlayToast(context, _kLockNotRestored(lockError), icon: Icons.error_outline_rounded);
      } else if (coverError != null) {
        showOverlayToast(context, _kCoverFailed(coverError), icon: Icons.error_outline_rounded);
      } else {
        HapticFeedback.mediumImpact();
        showOverlayToast(context, _kSaved, icon: Icons.check_circle_outline_rounded);
      }
      await _load();
      if (mounted && failed.isNotEmpty) setState(() => _staged.addAll(failed));
    } catch (e) {
      if (mounted) showOverlayToast(context, '$e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _autoFill() async {
    final api = _api;
    if (api == null || _filling) return;
    setState(() => _filling = true);
    try {
      final found = await api.metadataRefreshPreview(widget.itemId);
      if (!mounted) return;
      var n = 0, locked = 0;
      setState(() {
        final result = _form.fill(found, hasAudio: _hasAudio);
        n = result.filled;
        locked = result.locked;
        for (final (slot, key) in [('ebook', 'coverUrl'), ('audio', 'audioCoverUrl')]) {
          final url = found[key];
          if (url is String && url.isNotEmpty && _slots.contains(slot) && !_locked(_coverLock(slot))) {
            _staged[slot] = (file: null, url: url, remove: false);
            n++;
          }
        }
        _syncControllers();
      });
      showOverlayToast(context, _kFilled(n, locked), icon: Icons.auto_awesome_rounded);
    } catch (e) {
      if (mounted) showOverlayToast(context, '$e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _filling = false);
    }
  }

  MatchCurrent _matchCurrent() => MatchCurrent(
        title: _form.title,
        subtitle: _form.subtitle,
        authors: _form.authors,
        narrators: _form.narrators,
        genres: _form.genres,
        description: _form.description,
        publisher: _form.publisher,
        published: _form.publishedYear,
        language: _form.language,
        isbn: _form.isbn13.isNotEmpty ? _form.isbn13 : _form.isbn10,
        series: [
          for (final s in _form.series)
            if (!s.isEmpty) (name: s.name.trim(), index: s.index.trim().isEmpty ? null : s.index.trim()),
        ],
        providerIds: {
          for (final p in kProviderIdFields)
            if ((_form.providerIds[p.field] ?? '').isNotEmpty) p.key: _form.providerIds[p.field]!,
        },
      );

  void _searchOnline() {
    final api = _api;
    if (api == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (routeContext) => Scaffold(
        appBar: AppBar(title: const Text(_kSearchOnline)),
        body: ForkMatchView(
          api: api,
          itemId: widget.itemId,
          current: _matchCurrent(),
          coverSlots: [
            for (final slot in _slots)
              (
                slot: slot,
                title: _slots.length < 2 ? null : (slot == 'audio' ? _kAudioCoverRow : _kBookCoverRow),
                currentUrl: api.getCoverUrl(widget.itemId, width: null, coverSlot: slot),
                locked: _locked(_coverLock(slot)),
              ),
          ],
          coverHeaders: api.mediaHeaders,
          isAudiobook: _hasAudio,
          stagesChanges: true,
          onApply: (update) async {
            var n = 0, locked = 0;
            setState(() {
              final result = _form.fillFromMatch(update.metadata, hasAudio: _hasAudio);
              n = result.filled;
              locked = result.locked;
              update.covers.forEach((slot, url) {
                if (_locked(_coverLock(slot))) return;
                _staged[slot] = (file: null, url: url, remove: false);
                n++;
              });
              _syncControllers();
            });
            Navigator.of(routeContext).pop();
            showOverlayToast(context, _kFilled(n, locked), icon: Icons.auto_awesome_rounded);
            return true;
          },
        ),
      ),
    ));
  }

  void _reset() {
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _form = _original.copy();
      _staged.clear();
      _syncControllers();
    });
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(_kDiscardTitle),
        content: const Text(_kDiscardBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(_kKeepEditing)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(_kDiscard)),
        ],
      ),
    );
    return ok == true;
  }

  // ─── Covers ────────────────────────────────────────────────

  Future<void> _pickCoverFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    final path = result?.files.single.path;
    if (path != null && mounted) _edit(() => _staged[_slot] = (file: path, url: null, remove: false));
  }

  Future<void> _coverFromUrl() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(_kFromUrlTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: _kImageUrl, hintText: 'https://'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(_kCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text(_kUse)),
        ],
      ),
    );
    ctrl.dispose();
    final u = url?.trim() ?? '';
    if (u.isNotEmpty && mounted) _edit(() => _staged[_slot] = (file: null, url: u, remove: false));
  }

  Future<void> _findCover() async {
    final api = _api;
    if (api == null) return;
    final provider = await api.defaultCoverSearchProvider() ?? 'all';
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CoverSearchSheet(
        search: api.searchCovers(
          _form.title.isEmpty ? widget.bookTitle : _form.title,
          author: _form.authors.isEmpty ? null : _form.authors.first,
          provider: provider,
          coverSlot: _slot,
        ),
        headers: api.mediaHeaders,
        square: _slot == 'audio',
      ),
    );
    if (picked != null && mounted) _edit(() => _staged[_slot] = (file: null, url: picked, remove: false));
  }

  // ─── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ready = _detail != null;
    return PopScope(
      // Leaving wouldn't stop a save under way, so Back waits for it.
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) {
          _reset();
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text(_kEditMetadata, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(widget.bookTitle,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]),
          actions: [if (ready) _moreMenu()],
        ),
        bottomNavigationBar: ready && _canEdit ? _saveBar(cs, tt) : null,
        body: _loadError != null
            ? _failed(cs, tt)
            : !ready
                ? const Center(child: CircularProgressIndicator())
                : _body(cs, tt),
      ),
    );
  }

  Widget _failed(ColorScheme cs, TextTheme tt) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_kLoadFailed, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text(_kRetry)),
        ]),
      );

  Widget _moreMenu() {
    final allLocked = _allLocks.every(_locked);
    return PopupMenuButton<String>(
      tooltip: _kMore,
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (v) {
        if (v == 'locks') {
          _edit(() => allLocked ? _form.locks.removeAll(_allLocks) : _form.locks.addAll(_allLocks));
        } else if (v == 'chapters') {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChapterEditorScreen(itemId: widget.itemId, bookTitle: widget.bookTitle),
          ));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'locks',
          enabled: _canEdit && !_saving,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(allLocked ? Icons.lock_open_rounded : Icons.lock_rounded),
            title: Text(allLocked ? _kUnlockAll : _kLockAll),
          ),
        ),
        if (_hasAudio)
          const PopupMenuItem(
            value: 'chapters',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.format_list_numbered_rounded),
              title: Text(_kChapters),
            ),
          ),
      ],
    );
  }

  Widget _saveBar(ColorScheme cs, TextTheme tt) {
    final dirty = _dirty;
    final invalid = _invalid;
    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)))),
          child: Row(children: [
            Expanded(
              child: Text(invalid.isNotEmpty ? _kCheck(invalid) : (dirty ? _kChanges(_changeCount) : _kNoChanges),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: dirty ? FontWeight.w600 : null,
                    color: invalid.isNotEmpty ? cs.error : (dirty ? null : cs.onSurfaceVariant),
                  )),
            ),
            if (dirty) ...[
              TextButton(
                style: TextButton.styleFrom(shape: _kButtonShape),
                onPressed: _saving ? null : _reset,
                child: const Text(_kReset),
              ),
              const SizedBox(width: 6),
            ],
            FilledButton.icon(
              style: FilledButton.styleFrom(shape: _kButtonShape),
              onPressed: dirty && !_saving && invalid.isEmpty ? _save : null,
              icon: _saving
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                  : const Icon(Icons.check_rounded, size: 18),
              label: const Text(_kSave),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _body(ColorScheme cs, TextTheme tt) {
    final ratings = [
      for (final r in (_detail!['communityRatings'] as List? ?? const []).whereType<Map>())
        if (r['rating'] is num) r,
    ];
    final ids = [
      for (final p in kProviderIdFields)
        if (_allIds || (_form.providerIds[p.field] ?? '').isNotEmpty || (_original.providerIds[p.field] ?? '').isNotEmpty) p,
    ];
    final hiddenIds = kProviderIdFields.length - ids.length;
    final linked = kProviderIdFields.where((p) => (_form.providerIds[p.field] ?? '').isNotEmpty).length;
    final idsEdited = kProviderIdFields.any((p) => _textEdited(p.field));
    final paragraphs = _form.description.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).length;
    final hasHtml = RegExp(r'<(b|strong|i|em|u|a|ul|ol|li|h\d|blockquote)\b', caseSensitive: false)
        .hasMatch('${_detail!['description'] ?? ''}');
    Widget section(String id, String title, List<Widget> children, {String? summary, bool edited = false}) => _Section(
          title: title,
          summary: summary,
          edited: edited,
          open: !_closed.contains(id),
          onToggle: () => setState(() => _closed.contains(id) ? _closed.remove(id) : _closed.add(id)),
          children: children,
        );
    return AbsorbPointer(
      absorbing: _saving,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (!_canEdit) ...[
            _Notice(text: _kCannotEdit, cs: cs),
            const SizedBox(height: 10),
          ],
          _covers(cs, tt),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(shape: _kButtonShape),
                onPressed: _canEdit && !_saving ? _searchOnline : null,
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text(_kSearchOnline),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(shape: _kButtonShape),
                onPressed: _canEdit && !_saving && !_filling ? _autoFill : null,
                icon: _filling
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text(_kAutoFill),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          section('identity', _kIdentity, [
            _text('title', 'Title'),
            _text('subtitle', 'Subtitle'),
            _chips('authors', 'Authors', _form.authors, _original.authors, (v) => _form.authors = v, 'authors'),
            if (_hasAudio)
              _chips('narrators', 'Narrators', _form.narrators, _original.narrators, (v) => _form.narrators = v, 'narrators'),
            _series(cs),
            _chips('genres', 'Genres', _form.genres, _original.genres, (v) => _form.genres = v, 'genres'),
            _chips('tags', 'Tags', _form.tags, _original.tags, (v) => _form.tags = v, 'tags'),
          ]),
          if (_customFields.isNotEmpty) section('custom', _kCustomFields, [for (final f in _customFields) _custom(f)]),
          section('catalog', _kCatalog, [
            _text('publisher', 'Publisher', suggest: 'publishers'),
            _pair(_date(cs, tt), _text('publishedYear', 'Year', lock: 'publishedYear', number: true)),
            _pair(_text('language', 'Language', suggest: 'languages'), _text('pageCount', 'Pages', number: true)),
            _pair(_text('isbn13', 'ISBN-13', number: true), _text('isbn10', 'ISBN-10')),
            if (_hasAudio) ...[
              _pair(
                _text(
                  'durationSeconds',
                  'Length',
                  error: _lengthInvalid ? _kLengthError : null,
                ),
                _abridged(cs, tt),
              ),
            ],
            _rating(cs, tt),
            if (ratings.isNotEmpty) _communityRatings(cs, tt, ratings),
          ]),
          section(
            'description',
            _kDescription,
            summary: paragraphs == 0 ? _kEmpty : (paragraphs == 1 ? '1 paragraph' : '$paragraphs paragraphs'),
            edited: _textEdited('description'),
            [
              _text('description', _kDescription, lines: 8),
              if (hasHtml)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_kDescriptionHint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ),
            ],
          ),
          section(
            'providers',
            _kProviderLinks,
            summary: '$linked linked',
            edited: idsEdited,
            [
              for (final p in ids) _text(p.field, p.label),
              if (hiddenIds > 0 || _allIds)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(shape: _kButtonShape),
                    onPressed: () => setState(() => _allIds = !_allIds),
                    child: Text(_allIds ? _kFewerIds : '$_kMoreIds ($hiddenIds)'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _providerName(String key) => switch (key) {
        'google' => 'Google Books',
        'goodreads' => 'Goodreads',
        'amazon' => 'Amazon',
        'hardcover' => 'Hardcover',
        'audible' => 'Audible',
        'itunes' => 'iTunes',
        'openLibrary' => 'Open Library',
        'librofm' => 'Libro.fm',
        _ => key,
      };

  Widget _pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: a),
        const SizedBox(width: 8),
        Expanded(child: b),
      ]);

  Widget _lockButton(String lock, String label) {
    final on = _locked(lock);
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: on ? _kUnlock(label) : _kLock(label),
      onPressed: _canEdit ? () => _toggleLock(lock) : null,
      padding: EdgeInsets.zero,
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      icon: Icon(on ? Icons.lock_rounded : Icons.lock_open_rounded,
          size: 16, color: on ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.55)),
    );
  }

  Widget _text(String key, String label,
      {String? lock, String? suggest, String? error, bool number = false, int lines = 1}) {
    final lockName = lock ?? (key.startsWith('custom:') ? null : key);
    final locked = lockName != null && _locked(lockName);
    final edited = _textEdited(key);
    final f = _textFields[key]!;
    final ctrl = _ctrl[key] ??= TextEditingController(text: f.$1());
    final tt = Theme.of(context).textTheme;
    final valueStyle = tt.bodyMedium?.copyWith(fontSize: 14.5);
    final keyboard = number ? TextInputType.number : (lines > 1 ? TextInputType.multiline : TextInputType.text);
    if (lines > 1) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _Tile(
          label: label,
          locked: locked,
          edited: edited,
          trailing: lockName == null ? null : _lockButton(lockName, label),
          child: TextField(
            controller: ctrl,
            readOnly: locked || !_canEdit,
            minLines: 4,
            maxLines: lines,
            keyboardType: keyboard,
            style: valueStyle,
            onChanged: (v) => _edit(() => f.$2(v)),
            decoration: const InputDecoration.collapsed(hintText: ''),
          ),
        ),
      );
    }
    final field = TextField(
      controller: ctrl,
      readOnly: locked || !_canEdit,
      keyboardType: keyboard,
      style: valueStyle,
      onChanged: (v) => _edit(() => f.$2(v)),
      decoration: _tileDecoration(
        context,
        label: label,
        locked: locked,
        edited: edited,
        error: error,
        suffix: lockName == null ? null : _lockButton(lockName, label),
      ),
    );
    final input = suggest == null
        ? field
        : _Suggesting(
            api: _api!,
            source: suggest,
            controller: ctrl,
            enabled: !locked && _canEdit,
            onPick: (v) => _edit(() {
              ctrl.text = v;
              f.$2(v);
            }),
            child: field,
          );
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: input);
  }

  Widget _chips(
      String lock, String label, List<String> values, List<String> original, void Function(List<String>) set, String source) {
    final locked = _locked(lock);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Tile(
        label: label,
        locked: locked,
        edited: !listEquals(values, original),
        trailing: _lockButton(lock, label),
        child: _ChipsInput(
          key: ValueKey('chips:$lock'),
          api: _api!,
          source: source,
          values: values,
          enabled: !locked && _canEdit,
          onChanged: (v) => _edit(() => set(v)),
        ),
      ),
    );
  }

  Widget _series(ColorScheme cs) {
    final isLocked = _locked('seriesName');
    final locked = isLocked || !_canEdit;
    final edited = _form.changes(_original, hasAudio: _hasAudio).containsKey('seriesMemberships');
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14.5);
    void remove(int i) => _edit(() {
          _form.series.removeAt(i);
          final c = _seriesCtrl.removeAt(i);
          c.name.dispose();
          c.index.dispose();
          c.total.dispose();
        });
    Widget number(TextEditingController ctrl, String label, String? hint, TextInputType keyboard, ValueChanged<String> onChanged) =>
        SizedBox(
          width: 46,
          child: TextField(
            controller: ctrl,
            readOnly: locked,
            keyboardType: keyboard,
            style: style,
            onChanged: onChanged,
            decoration: _tileDecoration(
              context,
              label: label,
              locked: isLocked,
              edited: edited,
              hint: hint,
              padding: const EdgeInsets.fromLTRB(10, 12, 4, 12),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < _form.series.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: _Suggesting(
                api: _api!,
                source: 'series',
                controller: _seriesCtrl[i].name,
                enabled: !locked,
                onPick: (v) => _edit(() {
                  _seriesCtrl[i].name.text = v;
                  _form.series[i].name = v;
                }),
                child: TextField(
                  controller: _seriesCtrl[i].name,
                  readOnly: locked,
                  style: style,
                  onChanged: (v) => _edit(() => _form.series[i].name = v),
                  decoration: _tileDecoration(
                    context,
                    label: 'Series',
                    locked: isLocked,
                    edited: edited,
                    suffix: i == 0 ? _lockButton('seriesName', 'Series') : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            number(_seriesCtrl[i].index, _kNumber, null, const TextInputType.numberWithOptions(decimal: true),
                (v) => _edit(() => _form.series[i].index = v)),
            const SizedBox(width: 8),
            number(_seriesCtrl[i].total, _kOf, '?', TextInputType.number, (v) => _edit(() => _form.series[i].total = v)),
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: IconButton(
                tooltip: _kRemove,
                padding: EdgeInsets.zero,
                style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                constraints: const BoxConstraints.tightFor(width: 30, height: 36),
                onPressed: locked ? null : () => remove(i),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          TextButton.icon(
            style: TextButton.styleFrom(
              shape: _kButtonShape,
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: locked
                ? null
                : () => _edit(() {
                      _form.series.add(SeriesRow());
                      _seriesCtrl.add((
                        name: TextEditingController(),
                        index: TextEditingController(),
                        total: TextEditingController(),
                      ));
                    }),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(_kAddSeries),
          ),
          const Spacer(),
          // The first row carries the lock while there is one.
          if (_form.series.isEmpty) _lockButton('seriesName', 'Series'),
        ]),
      ),
    ]);
  }

  Widget _date(ColorScheme cs, TextTheme tt) {
    final locked = _locked('publishedYear') || !_canEdit;
    final parsed = DateTime.tryParse(_form.publishedDate);
    final shown = parsed == null ? _form.publishedDate : MaterialLocalizations.of(context).formatShortDate(parsed);
    final canClear = _form.publishedDate.isNotEmpty && !locked;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kControlRadius),
        onTap: locked
            ? null
            : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: parsed ?? DateTime.now(),
                  firstDate: DateTime(1000),
                  lastDate: DateTime(2200),
                  helpText: _kPickDate,
                );
                if (picked == null) return;
                final iso = '${picked.year.toString().padLeft(4, '0')}-'
                    '${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                _edit(() {
                  _form.publishedDate = iso;
                  _form.publishedYear = '${picked.year}';
                  _ctrl['publishedYear']?.text = '${picked.year}';
                });
              },
        child: InputDecorator(
          decoration: _tileDecoration(
            context,
            label: 'Published',
            locked: _locked('publishedYear'),
            edited: _form.publishedDate != _original.publishedDate,
            suffix: Row(mainAxisSize: MainAxisSize.min, children: [
              if (canClear)
                IconButton(
                  tooltip: _kClear,
                  padding: EdgeInsets.zero,
                  style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  constraints: const BoxConstraints.tightFor(width: 24, height: 36),
                  icon: Icon(Icons.close_rounded, size: 15, color: cs.onSurfaceVariant),
                  onPressed: () => _edit(() => _form.publishedDate = ''),
                ),
              _lockButton('publishedYear', 'Published date'),
            ]),
          ),
          child: Text(shown.isEmpty ? _kPickDate : shown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(fontSize: 14.5, color: shown.isEmpty ? cs.onSurfaceVariant : null)),
        ),
      ),
    );
  }

  Widget _abridged(ColorScheme cs, TextTheme tt) {
    final isLocked = _locked('abridged');
    final locked = isLocked || !_canEdit;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _RowTile(
        label: 'Abridged',
        locked: isLocked,
        edited: _form.abridged != _original.abridged,
        children: [
          Expanded(child: Text(_form.abridged ? _kYes : _kNo, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodyMedium?.copyWith(fontSize: 14.5))),
          Transform.scale(
            scale: 0.75,
            child: Switch(
              value: _form.abridged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: locked ? null : (v) => _edit(() => _form.abridged = v),
            ),
          ),
          _lockButton('abridged', 'Abridged'),
        ],
      ),
    );
  }

  Widget _rating(ColorScheme cs, TextTheme tt) {
    final isLocked = _locked('rating');
    final locked = isLocked || !_canEdit;
    final r = _form.rating ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _RowTile(
        label: _kYourRating,
        locked: isLocked,
        edited: _form.rating != _original.rating,
        children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              tooltip: '$i of 5',
              padding: EdgeInsets.zero,
              style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              onPressed: locked ? null : () => _edit(() => _form.rating = r == i ? null : i),
              icon: Icon(i <= r ? Icons.star_rounded : Icons.star_outline_rounded, size: 22, color: cs.primary),
            ),
          const Spacer(),
          _lockButton('rating', 'Rating'),
        ],
      ),
    );
  }

  /// What other sites rate the book: plain numbers, not controls.
  Widget _communityRatings(ColorScheme cs, TextTheme tt, List<Map<dynamic, dynamic>> ratings) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: LayoutBuilder(builder: (context, box) {
          const gap = 6.0;
          final width = (box.maxWidth - gap * 3) / 4;
          return Wrap(spacing: gap, runSpacing: gap, children: [
            SizedBox(
              width: box.maxWidth,
              child: Text(_kCommunityRatings, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
            for (final r in ratings)
              Semantics(
                label: '${_providerName('${r['provider']}')} rates it ${(r['rating'] as num).toStringAsFixed(1)} out of 5'
                    '${r['ratingCount'] is num ? ' from ${r['ratingCount']} ratings' : ''}',
                excludeSemantics: true,
                child: Container(
                  width: width,
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(_kControlRadius),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  child: Column(children: [
                    Text((r['rating'] as num).toStringAsFixed(1), style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text(_providerName('${r['provider']}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
          ]);
        }),
      );

  Widget _custom(CustomField f) {
    if (f.type == 'boolean') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _RowTile(
          label: f.label,
          children: [
            Expanded(child: Text(_form.custom[f.id] == true ? _kYes : _kNo)),
            Transform.scale(
              scale: 0.75,
              child: Switch(
                value: _form.custom[f.id] == true,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: _canEdit ? (v) => _edit(() => _form.custom[f.id] = v) : null,
              ),
            ),
          ],
        ),
      );
    }
    return _text('custom:${f.id}', f.label, number: f.type == 'number');
  }

  static String _slotName(String slot) => slot == 'audio' ? 'audiobook' : 'book';

  Widget _coverImage(ColorScheme cs, String slot, {BoxFit fit = BoxFit.cover}) {
    final s = _staged[slot];
    Widget missing() => ColoredBox(
          color: cs.surfaceContainerHighest,
          child: Center(
            child: Icon(slot == 'audio' ? Icons.headphones_rounded : Icons.menu_book_rounded, color: cs.onSurfaceVariant),
          ),
        );
    if (s?.remove == true) {
      return ColoredBox(
        color: cs.surfaceContainerHighest,
        child: Center(child: Icon(Icons.hide_image_outlined, color: cs.onSurfaceVariant)),
      );
    }
    if (s?.file != null) return Image.file(File(s!.file!), fit: fit);
    return CachedNetworkImage(
      imageUrl: s?.url ?? _api!.getCoverUrl(widget.itemId, width: 400, coverSlot: slot),
      httpHeaders: _api!.mediaHeaders,
      fit: fit,
      errorWidget: (_, __, ___) => missing(),
    );
  }

  void _viewCover(ColorScheme cs, String slot) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kControlRadius),
              child: _coverImage(cs, slot, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Widget _covers(ColorScheme cs, TextTheme tt) {
    final staged = _staged[_slot];
    final name = _slotName(_slot);
    final locked = _locked(_coverLock(_slot)) || !_canEdit;

    Widget overlay(IconData icon, String tooltip, Color color, VoidCallback? onTap) => Tooltip(
          message: tooltip,
          child: Material(
            color: cs.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(_kControlRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 18, color: color)),
            ),
          ),
        );

    Widget tile(String slot, double height) {
      final square = slot == 'audio';
      final selected = slot == _slot && _slots.length > 1;
      final isLocked = _locked(_coverLock(slot));
      final slotName = _slotName(slot);
      final label = square ? _kAudioCover : _kBookCover;
      return Semantics(
        button: true,
        selected: slot == _slot,
        label: '$label cover',
        child: GestureDetector(
          onTap: () => setState(() => _slot = slot),
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_kCardRadius),
                border: Border.all(color: selected ? cs.primary : Colors.transparent, width: 2),
              ),
              child: SizedBox(
                width: square ? height : height * 2 / 3,
                height: height,
                child: Stack(fit: StackFit.expand, children: [
                  ClipRRect(borderRadius: BorderRadius.circular(6), child: _coverImage(cs, slot)),
                  Positioned(
                    left: 5,
                    bottom: 5,
                    child: overlay(Icons.open_in_full_rounded, '$_kViewCover: $slotName cover', cs.onSurface,
                        () => _viewCover(cs, slot)),
                  ),
                  Positioned(
                    right: 5,
                    bottom: 5,
                    child: overlay(
                      isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      isLocked ? _kUnlock('$slotName cover') : _kLock('$slotName cover'),
                      isLocked ? cs.primary : cs.onSurface,
                      _canEdit ? () => _toggleLock(_coverLock(slot)) : null,
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: tt.labelMedium?.copyWith(
                    color: selected ? cs.primary : cs.onSurfaceVariant, fontWeight: selected ? FontWeight.w700 : null)),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(_kCardRadius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, box) {
          // Both covers at their own shape, the same height, as wide as fits.
          const chrome = 10.0;
          const gap = 12.0;
          final aspect = _slots.fold<double>(0, (sum, s) => sum + (s == 'audio' ? 1 : 2 / 3));
          final room = box.maxWidth - chrome * _slots.length - gap * (_slots.length - 1);
          final height = (room / aspect).clamp(80.0, 160.0);
          return Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < _slots.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              tile(_slots[i], height),
            ],
          ]);
        }),
        const SizedBox(height: 8),
        Text(_kCoverStatus(name, locked: locked && _canEdit, staged: staged),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(shape: _kButtonShape),
          onPressed: locked ? null : _findCover,
          icon: const Icon(Icons.image_search_rounded, size: 18),
          label: const Text(_kFindOnline),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(shape: _kButtonShape),
              onPressed: locked ? null : _pickCoverFile,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text(_kFromFile),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(shape: _kButtonShape),
              onPressed: locked ? null : _coverFromUrl,
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text(_kFromUrl),
            ),
          ),
        ]),
        Align(
          alignment: Alignment.centerRight,
          child: staged != null
              ? TextButton.icon(
                  style: TextButton.styleFrom(shape: _kButtonShape),
                  onPressed: () => _edit(() => _staged.remove(_slot)),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text(_kUndoCover),
                )
              : TextButton.icon(
                  style: TextButton.styleFrom(shape: _kButtonShape),
                  onPressed: locked ? null : () => _edit(() => _staged[_slot] = (file: null, url: null, remove: true)),
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: locked ? null : cs.error),
                  label: Text(_kRemoveCover, style: TextStyle(color: locked ? null : cs.error)),
                ),
        ),
      ]),
    );
  }
}

InputDecoration _tileDecoration(
  BuildContext context, {
  required String label,
  required bool locked,
  bool edited = false,
  String? error,
  String? hint,
  Widget? suffix,
  EdgeInsets padding = const EdgeInsets.fromLTRB(12, 12, 4, 12),
}) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(_kControlRadius),
        borderSide: BorderSide(color: color, width: width),
      );
  final rest = border(edited ? cs.primary : cs.outline.withValues(alpha: 0.65));
  final bad = border(cs.error);
  return InputDecoration(
    labelText: label,
    // A floating label is drawn at three quarters of this size.
    floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) => (tt.bodyLarge ?? const TextStyle()).copyWith(
          fontSize: 16,
          color: states.contains(WidgetState.error)
              ? cs.error
              : states.contains(WidgetState.focused)
                  ? cs.primary
                  : cs.onSurfaceVariant,
        )),
    floatingLabelBehavior: FloatingLabelBehavior.always,
    errorText: error,
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: locked ? Color.alphaBlend(cs.primary.withValues(alpha: 0.07), cs.surface) : cs.surface,
    contentPadding: padding,
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    border: rest,
    enabledBorder: rest,
    disabledBorder: rest,
    focusedBorder: border(cs.primary, 1.5),
    errorBorder: bad,
    focusedErrorBorder: bad,
  );
}

/// The same outlined box for things that aren't one line of text, with the
/// lock in the corner. The outline lights up while something inside has focus.
class _Tile extends StatelessWidget {
  final String label;
  final bool locked;
  final bool edited;
  final Widget? trailing;
  final Widget child;

  const _Tile({required this.label, this.locked = false, this.edited = false, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        child: Builder(
          builder: (context) => Stack(clipBehavior: Clip.none, children: [
            InputDecorator(
              isFocused: Focus.of(context).hasFocus,
              decoration: _tileDecoration(
                context,
                label: label,
                locked: locked,
                edited: edited,
                padding: EdgeInsets.fromLTRB(12, 10, trailing == null ? 12 : 34, 10),
              ),
              child: child,
            ),
            if (trailing != null) Positioned(top: 6, right: 2, child: trailing!),
          ]),
        ),
      );
}

/// The same box holding one row, for a switch or a rating.
class _RowTile extends StatelessWidget {
  final String label;
  final bool locked;
  final bool edited;
  final List<Widget> children;

  const _RowTile({required this.label, this.locked = false, this.edited = false, required this.children});

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: _tileDecoration(
          context,
          label: label,
          locked: locked,
          edited: edited,
          padding: const EdgeInsets.fromLTRB(12, 4, 2, 4),
        ),
        child: SizedBox(height: 36, child: Row(children: children)),
      );
}

/// A titled card of fields that folds, with a short summary while closed.
class _Section extends StatelessWidget {
  final String title;
  final String? summary;
  final bool edited;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;

  const _Section({
    required this.title,
    this.summary,
    this.edited = false,
    required this.open,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(_kCardRadius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          header: true,
          button: true,
          expanded: open,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 13, 10, 13),
              child: Row(children: [
                Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                if (!open && summary != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(edited ? '$summary · $_kEdited' : summary!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(color: edited ? cs.primary : cs.onSurfaceVariant)),
                  ),
                ] else
                  const Spacer(),
                AnimatedRotation(
                  turns: open ? 0 : -0.25,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
                ),
              ]),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
      ]),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final ColorScheme cs;

  const _Notice({required this.text, required this.cs});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(_kCardRadius)),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, color: cs.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: cs.onSecondaryContainer))),
        ]),
      );
}

/// Names the server already has that match what is typed, as chips under
/// the field, from `GET /metadata/<source>`.
class _Suggesting extends StatefulWidget {
  final BookOrbitApiService api;
  final String source;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onPick;
  final Widget child;

  /// Leaves out names already picked (a chip field's values).
  final List<String> exclude;

  const _Suggesting({
    required this.api,
    required this.source,
    required this.controller,
    required this.enabled,
    required this.onPick,
    required this.child,
    this.exclude = const [],
  });

  @override
  State<_Suggesting> createState() => _SuggestingState();
}

class _SuggestingState extends State<_Suggesting> {
  Timer? _debounce;
  List<String> _names = const [];
  String _asked = '';
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant _Suggesting old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final q = widget.controller.text.trim();
    if (q == _asked) return;
    _debounce?.cancel();
    if (q.isEmpty || !_focused) {
      if (_names.isNotEmpty) setState(() => _names = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      _asked = q;
      final names = await widget.api.metadataSuggestions(widget.source, q);
      if (!mounted || widget.controller.text.trim() != q) return;
      final taken = {for (final e in widget.exclude) e.toLowerCase()};
      setState(() => _names = [
            for (final n in names)
              if (n.toLowerCase() != q.toLowerCase() && !taken.contains(n.toLowerCase())) n,
          ].take(8).toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        _focused = f;
        if (!f) {
          _debounce?.cancel();
          if (_names.isNotEmpty) setState(() => _names = const []);
        }
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        widget.child,
        if (widget.enabled && _names.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final n in _names)
                ActionChip(
                  label: Text(n),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _asked = n;
                    setState(() => _names = const []);
                    widget.onPick(n);
                  },
                ),
            ]),
          ),
      ]),
    );
  }
}

/// A list of names as removable chips, with a box to add more: enter or a
/// comma adds what was typed, and the server's matching names show to tap.
class _ChipsInput extends StatefulWidget {
  final BookOrbitApiService api;
  final String source;
  final List<String> values;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;

  const _ChipsInput({
    super.key,
    required this.api,
    required this.source,
    required this.values,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_ChipsInput> createState() => _ChipsInputState();
}

class _ChipsInputState extends State<_ChipsInput> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final have = {for (final v in widget.values) v.toLowerCase()};
    final added = [
      for (final p in raw.split(','))
        if (p.trim().isNotEmpty && have.add(p.trim().toLowerCase())) p.trim(),
    ];
    _ctrl.clear();
    if (added.isNotEmpty) {
      widget.onChanged([...widget.values, ...added]);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final style = tt.bodyMedium?.copyWith(fontSize: 14.5);
    final chips = [
      for (final v in widget.values)
        InputChip(
          key: ValueKey(v),
          label: Text(v, style: tt.bodyMedium?.copyWith(fontSize: 13.5)),
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
          side: BorderSide.none,
          backgroundColor: cs.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          labelPadding: const EdgeInsets.only(left: 6, right: 2),
          deleteIcon: const Icon(Icons.close_rounded, size: 16),
          deleteIconColor: cs.onSurfaceVariant,
          deleteButtonTooltipMessage: '$_kRemove $v',
          onDeleted: widget.enabled ? () => widget.onChanged([...widget.values]..remove(v)) : null,
        ),
    ];
    if (!widget.enabled) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 20),
        child: Wrap(spacing: 6, runSpacing: 4, children: chips),
      );
    }
    final hint = widget.values.length < 2 ? _kPressEnter : _kAddMore;
    return LayoutBuilder(builder: (context, box) {
      // As wide as what it shows, so it sits beside the names when it fits
      // and only takes a line of its own when it doesn't.
      final measured = TextPainter(
        text: TextSpan(text: _ctrl.text.isEmpty ? hint : _ctrl.text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = (measured.width + 10).clamp(36.0, box.maxWidth);
      measured.dispose();
      return _Suggesting(
        api: widget.api,
        source: widget.source,
        controller: _ctrl,
        enabled: true,
        exclude: widget.values,
        onPick: (n) {
          _add(n);
          _focus.requestFocus();
        },
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ...chips,
          SizedBox(
            key: const ValueKey('chips-input'),
            width: width,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              style: style,
              textInputAction: TextInputAction.done,
              onChanged: (v) {
                if (v.endsWith(',')) {
                  _add(v);
                } else {
                  setState(() {});
                }
              },
              onSubmitted: (v) {
                _add(v);
                _focus.requestFocus();
              },
              onTapOutside: (_) {
                if (_ctrl.text.trim().isNotEmpty) _add(_ctrl.text);
              },
              decoration: InputDecoration.collapsed(
                hintText: hint,
                hintStyle: style?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// Cover search results for the selected slot; returns the picked URL.
class _CoverSearchSheet extends StatelessWidget {
  final Future<List<String>> search;
  final Map<String, String> headers;
  final bool square;

  const _CoverSearchSheet({required this.search, required this.headers, required this.square});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: FutureBuilder<List<String>>(
        future: search,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final urls = snap.data ?? const [];
          if (urls.isEmpty) return const Center(child: Text(_kNoCovers));
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: square ? 1 : 2 / 3,
            ),
            itemCount: urls.length,
            itemBuilder: (_, i) => Semantics(
              button: true,
              label: 'Cover ${i + 1}',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.pop(context, urls[i]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: urls[i],
                    httpHeaders: headers,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => ColoredBox(color: cs.surfaceContainerHigh),
                    errorWidget: (_, __, ___) => ColoredBox(
                      color: cs.surfaceContainerHigh,
                      child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
