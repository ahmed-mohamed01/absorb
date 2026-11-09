import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../utils/cover_accent.dart';

// Fork-owned. See FORK_NOTES.md.

/// [accentFromCoverPalette] for a cover, counting its colours on a background
/// isolate: PaletteGenerator's own loaders do that on the UI thread, where a
/// single cover can stop an opening sheet drawing.
Future<Color?> coverAccentOffThread(ImageProvider provider) async {
  final image = await _firstImage(ResizeImage(provider, width: 120));
  try {
    final rgba = await image.toByteData();
    if (rgba == null) return null;
    final accent = await compute(_accentFromRgba, (rgba, image.width, image.height));
    return accent == null ? null : Color(accent);
  } finally {
    image.dispose();
  }
}

Future<int?> _accentFromRgba((ByteData, int, int) cover) async {
  final (rgba, width, height) = cover;
  final palette = await PaletteGenerator.fromByteData(
    EncodedImage(rgba, width: width, height: height),
    maximumColorCount: 16,
  );
  return accentFromCoverPalette(palette)?.toARGB32();
}

/// The provider's image, which the caller disposes. A listener owns each
/// [ImageInfo] it is handed, so this keeps the first one's handle and drops
/// any other.
Future<ui.Image> _firstImage(ImageProvider provider) {
  final done = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener(
    (info, _) {
      if (done.isCompleted) {
        info.dispose();
      } else {
        done.complete(info.image);
      }
    },
    onError: (Object e, StackTrace? s) {
      if (!done.isCompleted) done.completeError(e, s);
    },
  );
  stream.addListener(listener);
  return done.future.timeout(const Duration(seconds: 15)).whenComplete(() => stream.removeListener(listener));
}
