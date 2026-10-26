// Fork-owned: the Watchlist entry in Settings > Advanced, shown for BookOrbit
// servers only. See FORK_NOTES.md.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/player_settings.dart';

const _formats = [
  ('both', 'Both', 'Ebook and audiobook'),
  ('ebook', 'Ebook only', 'Leave audiobooks alone'),
  ('audiobook', 'Audiobook only', 'Leave ebooks alone'),
];

String _formatLabel(String value) =>
    _formats.firstWhere((f) => f.$1 == value, orElse: () => _formats.first).$2;

class WatchlistSettingsTile extends StatefulWidget {
  const WatchlistSettingsTile({super.key});

  @override
  State<WatchlistSettingsTile> createState() => _WatchlistSettingsTileState();
}

class _WatchlistSettingsTileState extends State<WatchlistSettingsTile> {
  String _format = 'both';

  @override
  void initState() {
    super.initState();
    PlayerSettings.getWatchlistRequestFormat().then((v) {
      if (mounted && v != _format) setState(() => _format = v);
    });
  }

  Future<void> _openSheet() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Request formats', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('What "Request missing" asks BookOrbit for.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
            for (final f in _formats)
              ListTile(
                leading: Icon(
                  f.$1 == _format ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: f.$1 == _format ? cs.primary : cs.onSurfaceVariant,
                ),
                title: Text(f.$2),
                subtitle: Text(f.$3, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                onTap: () => Navigator.of(context).pop(f.$1),
              ),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
    if (picked == null || picked == _format || !mounted) return;
    setState(() => _format = picked);
    await PlayerSettings.setWatchlistRequestFormat(picked);
  }

  @override
  Widget build(BuildContext context) {
    if (context.watch<AuthProvider>().apiService?.isBookOrbit != true) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Divider(height: 1, indent: 16, endIndent: 16),
      ListTile(
        leading: Icon(Icons.visibility_rounded, color: cs.primary),
        title: const Text('Watchlist'),
        subtitle: Text('Request formats: ${_formatLabel(_format)}',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
        onTap: _openSheet,
      ),
    ]);
  }
}
