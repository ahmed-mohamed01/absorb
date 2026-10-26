// Fork-owned: the per-format mode and library pickers BookOrbit asks for when
// an author is followed or edited, shared by the add-author sheet and the
// author settings sheet. See FORK_NOTES.md.
import 'package:flutter/material.dart';

/// One format's choice: how the author is watched and where grabs land.
typedef WatchlistFormatChoice = ({String mode, int? libraryId});

/// BookOrbit's modes, labelled as its web app labels them.
const watchlistModes = [
  ('notify', 'Notify Upcoming', 'Alert on new releases. Nothing is downloaded.'),
  ('auto-upcoming', 'Autodownload Upcoming', 'Grab new releases automatically on release day.'),
  ('auto-all', 'Autodownload All', 'Backfill the full catalog and grab new releases.'),
  ('off', 'Not watching', 'Ignore this format for this author.'),
];

String watchlistModeLabel(String? mode) =>
    watchlistModes.firstWhere((m) => m.$1 == mode, orElse: () => watchlistModes.first).$2;

/// The server refuses an automatic mode with nowhere to file the grabs.
bool watchlistNeedsLibrary(WatchlistFormatChoice c) => c.mode.startsWith('auto-') && c.libraryId == null;

const _ebookEdge = Color(0xFF6EA8FE);
const _audioEdge = Color(0xFFA07AE0);

/// Mode and library for ebooks and audiobooks. Owns no state: [values]
/// comes in, [onChanged] hands out the whole map after every pick.
class WatchlistFormatsForm extends StatelessWidget {
  final Map<String, WatchlistFormatChoice> values;
  final List<({int id, String name})> libraries;
  final bool enabled;
  final ValueChanged<Map<String, WatchlistFormatChoice>> onChanged;

  const WatchlistFormatsForm({
    super.key,
    required this.values,
    required this.libraries,
    required this.onChanged,
    this.enabled = true,
  });

  void _set(String format, WatchlistFormatChoice choice) => onChanged({...values, format: choice});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final format in const ['ebook', 'audiobook']) ...[
        _formatCard(context, format),
        const SizedBox(height: 10),
      ],
    ]);
  }

  Widget _formatCard(BuildContext context, String format) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final audio = format == 'audiobook';
    final edge = audio ? _audioEdge : _ebookEdge;
    final value = values[format] ?? (mode: 'notify', libraryId: null);
    // A library the account lost access to still shows, so it is not
    // silently swapped for another.
    final known = value.libraryId == null || libraries.any((l) => l.id == value.libraryId);
    final help = watchlistModes.firstWhere((m) => m.$1 == value.mode, orElse: () => watchlistModes.first).$3;
    InputDecoration field(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: edge.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
            child: Icon(audio ? Icons.headphones_rounded : Icons.menu_book_rounded, size: 16, color: edge),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(audio ? 'Audiobooks' : 'Ebooks',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)),
          ),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: value.mode,
          isExpanded: true,
          decoration: field('Mode'),
          items: [
            for (final m in watchlistModes) DropdownMenuItem(value: m.$1, child: Text(m.$2, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: enabled ? (m) => _set(format, (mode: m ?? value.mode, libraryId: value.libraryId)) : null,
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          initialValue: value.libraryId ?? 0,
          isExpanded: true,
          decoration: field('Library'),
          items: [
            const DropdownMenuItem(value: 0, child: Text('No library')),
            for (final l in libraries) DropdownMenuItem(value: l.id, child: Text(l.name, overflow: TextOverflow.ellipsis)),
            if (!known) DropdownMenuItem(value: value.libraryId, child: const Text('A library you cannot see')),
          ],
          onChanged: enabled
              ? (id) => _set(format, (mode: value.mode, libraryId: id == null || id == 0 ? null : id))
              : null,
        ),
        const SizedBox(height: 6),
        Text(help, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        if (watchlistNeedsLibrary(value))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Pick a library for automatic downloads.',
                style: tt.labelSmall?.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}
