import 'package:flutter/material.dart';

import '../../main.dart' show flatNotifier, gradientIntensityNotifier;

// Fork-owned: the background of a Home shelf's sheet (section_detail_sheet.dart),
// so the sheet carries Home's own accent gradient. See FORK_NOTES.md.

/// Home's background gradient, as `home_screen.dart` paints it: the theme's
/// primary colour at the user's gradient intensity at the top, fading through
/// the surface to the scaffold colour. Null when the flat (OLED) background
/// is on, as Home then paints no gradient.
LinearGradient? forkHomeGradient(BuildContext context) {
  if (flatNotifier.value) return null;
  final cs = Theme.of(context).colorScheme;
  final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
  final lowerFade = Color.lerp(cs.surface, scaffoldBg, 0.55) ?? scaffoldBg;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: const [0.0, 0.22, 0.72, 1.0],
    colors: [
      cs.primary.withValues(alpha: gradientIntensityNotifier.value),
      cs.surface,
      lowerFade,
      scaffoldBg,
    ],
  );
}

/// A shelf sheet's frame: rounded at the top, on Home's background with its
/// accent gradient, with the drag handle the shared sheet would otherwise
/// draw on its plain sheet colour. Open the sheet with `showHandle: false`.
class ForkShelfSheetFrame extends StatelessWidget {
  /// The sheet's content, under the handle.
  final Widget child;

  /// Creates the frame around [child].
  const ForkShelfSheetFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: forkHomeGradient(context)),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ]),
      ),
    );
  }
}
