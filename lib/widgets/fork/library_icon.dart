// Fork-owned: the icon of a library, from the icon its server keeps for it.
// BookOrbit stores a Lucide icon name ('Headphones') or a custom SVG
// ('custom:<slug>', served at /api/v1/custom-icons/<slug>.svg);
// Audiobookshelf stores one of its own icon names ('books-1'). A name is
// drawn with the closest Material icon, a custom SVG is fetched through the
// BookOrbit media proxy (a fresh token per request, as covers are) and
// tinted, and the virtual libraries (Dashboard, Book Dock, Watchlist) keep
// their own icons. Used by the library picker and the Home/Library header
// pills. See FORK_NOTES.md.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/bookorbit_media_proxy_stub.dart'
    if (dart.library.io) '../../services/bookorbit_media_proxy.dart';

/// Icon names a server can give a library, with the closest Material icon:
/// the Lucide names BookOrbit's library creator suggests, the ones its smart
/// scopes use and other likely picks (PascalCase), and Audiobookshelf's
/// library icons (lowercase), so one map serves both without a clash.
const forkLibraryIcons = <String, IconData>{
  // BookOrbit's suggested library icons.
  'Library': Icons.local_library_rounded,
  'LibraryBig': Icons.local_library_rounded,
  'BookOpen': Icons.menu_book_rounded,
  'BookOpenText': Icons.auto_stories_rounded,
  'BookCopy': Icons.library_books_rounded,
  'BookMarked': Icons.book_rounded,
  'FolderBookmark': Icons.folder_special_rounded,
  'Bookmark': Icons.bookmark_rounded,
  'BookHeadphones': Icons.headphones_rounded,
  'Headphones': Icons.headphones_rounded,
  'AudioLines': Icons.graphic_eq_rounded,
  'ScrollText': Icons.receipt_long_rounded,
  'Newspaper': Icons.newspaper_rounded,
  'GraduationCap': Icons.school_rounded,
  'Feather': Icons.history_edu_rounded,
  'Sparkles': Icons.auto_awesome_rounded,
  'Swords': Icons.castle_rounded,
  'Rocket': Icons.rocket_launch_rounded,
  'Ghost': Icons.nights_stay_rounded,
  'Heart': Icons.favorite_rounded,
  'Star': Icons.star_rounded,
  'Moon': Icons.nightlight_round,
  'Baby': Icons.child_care_rounded,
  'Layers': Icons.layers_rounded,
  'Podcast': Icons.podcasts_rounded,
  // The smart scope icons, which the picker's search also offers.
  'Funnel': Icons.filter_alt_rounded,
  'Clock': Icons.schedule_rounded,
  'Calendar': Icons.calendar_month_rounded,
  'Flame': Icons.local_fire_department_rounded,
  'Tag': Icons.sell_rounded,
  'CircleCheck': Icons.check_circle_rounded,
  'Sun': Icons.wb_sunny_rounded,
  'Trophy': Icons.emoji_events_rounded,
  'Brain': Icons.psychology_rounded,
  'Leaf': Icons.eco_rounded,
  // Other Lucide icons a library is likely to get (genres and media).
  'Book': Icons.class_rounded,
  'BookText': Icons.menu_book_rounded,
  'BookAudio': Icons.headphones_rounded,
  'BookImage': Icons.photo_album_rounded,
  'BookA': Icons.translate_rounded,
  'Languages': Icons.translate_rounded,
  'Music': Icons.music_note_rounded,
  'Mic': Icons.mic_rounded,
  'Radio': Icons.radio_rounded,
  'Rss': Icons.rss_feed_rounded,
  'Globe': Icons.public_rounded,
  'Map': Icons.map_rounded,
  'Compass': Icons.explore_rounded,
  'PawPrint': Icons.pets_rounded,
  'Film': Icons.movie_rounded,
  'Tv': Icons.tv_rounded,
  'Image': Icons.image_rounded,
  'Palette': Icons.palette_rounded,
  'Drama': Icons.theater_comedy_rounded,
  'Wand': Icons.auto_fix_high_rounded,
  'WandSparkles': Icons.auto_fix_high_rounded,
  'Castle': Icons.castle_rounded,
  'Gamepad2': Icons.sports_esports_rounded,
  'Code': Icons.code_rounded,
  'FlaskConical': Icons.science_rounded,
  'Microscope': Icons.biotech_rounded,
  'Landmark': Icons.account_balance_rounded,
  'Coffee': Icons.coffee_rounded,
  'Utensils': Icons.restaurant_rounded,
  'Dumbbell': Icons.fitness_center_rounded,
  'Briefcase': Icons.work_rounded,
  // Audiobookshelf's library icons ('database', its default, is left out:
  // see forkLibraryIconData).
  'audiobookshelf': Icons.library_books_rounded,
  'books-1': Icons.menu_book_rounded,
  'books-2': Icons.auto_stories_rounded,
  'book-1': Icons.book_rounded,
  'microphone-1': Icons.mic_rounded,
  'microphone-3': Icons.mic_external_on_rounded,
  'radio': Icons.radio_rounded,
  'podcast': Icons.podcasts_rounded,
  'rss': Icons.rss_feed_rounded,
  'headphones': Icons.headphones_rounded,
  'music': Icons.music_note_rounded,
  'file-picture': Icons.image_rounded,
  'rocket': Icons.rocket_launch_rounded,
  'power': Icons.power_rounded,
  'star': Icons.star_rounded,
  'heart': Icons.favorite_rounded,
};

const _customIconPrefix = 'custom:';
final _customIconSlug = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

/// The Material icon for [library]: the Dashboard's, Book Dock's and
/// Watchlist's own, else the server's icon by name, else the media type's
/// (also what a custom SVG falls back to while it loads or when it fails).
/// 'database' is what both servers give a library nobody picked an icon
/// for, so it counts as none and the media type's icon shows instead.
IconData forkLibraryIconData(Map<String, dynamic>? library) {
  if (library == null) return Icons.auto_stories_rounded;
  if (library['bookDock'] == true) return Icons.move_to_inbox_rounded;
  if (library['watchlist'] == true) return Icons.visibility_rounded;
  final icon = library['icon'];
  final named = icon is String ? forkLibraryIcons[icon] : null;
  if (named != null) return named;
  return library['mediaType'] == 'podcast' ? Icons.podcasts_rounded : Icons.auto_stories_rounded;
}

/// The slug of a BookOrbit custom icon (`custom:<slug>`), or null when the
/// library's icon is a name or the slug is not one the server would serve.
String? forkCustomIconSlug(Map<String, dynamic>? library) {
  final icon = library?['icon'];
  if (icon is! String || !icon.startsWith(_customIconPrefix)) return null;
  final slug = icon.substring(_customIconPrefix.length);
  return _customIconSlug.hasMatch(slug) ? slug : null;
}

/// The server path of a custom icon's SVG.
String forkCustomIconPath(String slug) => '/api/v1/custom-icons/$slug.svg';

/// Where [baseUrl] (the server root) serves a custom icon's SVG.
String forkCustomIconUrl(String baseUrl, String slug) =>
    '${baseUrl.replaceAll(RegExp(r'/+$'), '')}${forkCustomIconPath(slug)}';

/// A library's icon at [size] in [color]: the named icon, or its custom SVG
/// fetched from the signed-in BookOrbit server and tinted. Without one to
/// fetch from (no [AuthProvider] above, signed out, or not BookOrbit) the
/// named fallback shows.
class ForkLibraryIcon extends StatelessWidget {
  const ForkLibraryIcon({super.key, required this.library, required this.size, required this.color});

  final Map<String, dynamic>? library;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(forkLibraryIconData(library), size: size, color: color);
    final slug = forkCustomIconSlug(library);
    if (slug == null) return fallback;
    ApiService? api;
    try {
      api = context.read<AuthProvider>().apiService;
    } on ProviderNotFoundException {
      api = null;
    }
    if (api is! BookOrbitApiService) return fallback;
    // Through the media proxy, which puts a fresh token on every request
    // (BookOrbit's last fifteen minutes), the way covers load; straight from
    // the server with the account headers only while the proxy is not up.
    final proxy = BookOrbitMediaProxy.instance;
    return SvgPicture.network(
      proxy.isReady ? proxy.urlFor(forkCustomIconPath(slug)) : forkCustomIconUrl(api.baseUrl, slug),
      width: size,
      height: size,
      headers: proxy.isReady ? null : api.mediaHeaders,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
