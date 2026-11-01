// Fork-owned: the Fork settings page and its entry in Settings > Advanced.
// Every setting only this fork has goes here, so Settings itself keeps one
// hook line. See FORK_NOTES.md.
import 'package:flutter/material.dart';

import '../../services/fork/fork_settings.dart';

/// The Fork settings row in Settings.
class ForkSettingsTile extends StatelessWidget {
  const ForkSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Divider(height: 1, indent: 16, endIndent: 16),
      ListTile(
        leading: Icon(Icons.call_split_rounded, color: cs.primary),
        title: const Text('Fork settings'),
        subtitle: Text('Settings only this build has',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ForkSettingsScreen()),
        ),
      ),
    ]);
  }
}

class ForkSettingsScreen extends StatefulWidget {
  const ForkSettingsScreen({super.key});

  @override
  State<ForkSettingsScreen> createState() => _ForkSettingsScreenState();
}

class _ForkSettingsScreenState extends State<ForkSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Fork settings')),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Covers', style: tt.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
        ),
        SwitchListTile(
          title: const Text("Each book's own cover shape"),
          subtitle: Text(
            ForkSettings.ownCoverShapes
                ? 'Ebooks are portrait and audiobooks square in the Library grid and author and narrator pages'
                : 'Every cover follows the library\'s cover shape',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          value: ForkSettings.ownCoverShapes,
          onChanged: (v) async {
            await ForkSettings.setOwnCoverShapes(v);
            if (mounted) setState(() {});
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Series', style: tt.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
        ),
        SwitchListTile(
          title: const Text('Show single-book series as books'),
          subtitle: Text(
            ForkSettings.singleBookSeriesAsBooks
                ? 'With Collapse series on, a series of one book shows as that book in the Library and author pages'
                : 'With Collapse series on, a series of one book shows as a series',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          value: ForkSettings.singleBookSeriesAsBooks,
          onChanged: (v) async {
            await ForkSettings.setSingleBookSeriesAsBooks(v);
            if (mounted) setState(() {});
          },
        ),
      ]),
    );
  }
}
