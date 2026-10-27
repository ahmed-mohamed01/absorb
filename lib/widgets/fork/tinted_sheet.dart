import 'package:flutter/material.dart';

// Fork-owned: the one background every sheet the book detail page opens
// shares, so they read as part of the page. See FORK_NOTES.md.

/// The sheet colour with the book page's cover gradient over its top: the
/// cover's container colour at half strength fading into the plain sheet
/// colour. A null [tint] (no cover colour yet, or e-ink) gives the plain
/// sheet colour.
BoxDecoration forkTintedSheetDecoration(BuildContext context, Color? tint) {
  final theme = Theme.of(context);
  final base = theme.bottomSheetTheme.backgroundColor ?? theme.colorScheme.surface;
  return BoxDecoration(
    color: base,
    gradient: tint == null
        ? null
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.4, 1.0],
            colors: [
              Color.alphaBlend(tint.withValues(alpha: 0.5), base),
              Color.alphaBlend(tint.withValues(alpha: 0.12), base),
              base,
            ],
          ),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
  );
}
