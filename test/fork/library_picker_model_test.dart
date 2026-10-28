import 'package:absorb/widgets/fork/library_icon.dart';
import 'package:absorb/widgets/fork/library_picker_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('groups', () {
    test('tools go under the libraries, each keeping its order', () {
      final g = libraryPickerGroups([
        {'id': '0', 'name': 'Comics'},
        {'id': 'watchlist', 'watchlist': true},
        {'id': '1', 'name': 'Audiobooks'},
        {'id': 'book-dock', 'bookDock': true},
        {'id': '2', 'name': 'Ebooks'},
      ]);
      expect(g.libraries.map((l) => l['id']), ['0', '1', '2']);
      expect(g.tools.map((l) => l['id']), ['watchlist', 'book-dock']);
    });

    test('an Audiobookshelf server has no tools', () {
      final g = libraryPickerGroups([
        {'id': '1', 'name': 'Books', 'icon': 'books-1'},
        {'id': '2', 'name': 'Podcasts', 'mediaType': 'podcast'},
      ]);
      expect(g.libraries.length, 2);
      expect(g.tools, isEmpty);
    });
  });

  group('subtitle', () {
    test('a library says its book count, or nothing without one', () {
      expect(libraryPickerSubtitle({'bookCount': 9}), '9 books');
      expect(libraryPickerSubtitle({'bookCount': 1}), '1 book');
      expect(libraryPickerSubtitle({'bookCount': 0}), '0 books');
      expect(libraryPickerSubtitle({'name': 'Books'}), isNull);
      expect(libraryPickerSubtitle({'mediaType': 'podcast', 'bookCount': 3}), '3 podcasts');
      expect(libraryPickerSubtitle({'mediaType': 'podcast', 'bookCount': 1}), '1 podcast');
      expect(libraryPickerSubtitle({'mediaType': 'podcast'}), isNull);
    });

    test('the Book Dock says what needs the user first', () {
      expect(libraryPickerSubtitle({'bookDock': true}), isNull);
      expect(bookDockSubtitle({'needsReview': 3, 'error': 1, 'readyToFile': 2}), '3 files need review');
      expect(bookDockSubtitle({'needsReview': 1}), '1 file needs review');
      expect(bookDockSubtitle({'error': 2, 'readyToFile': 2}), '2 files failed');
      expect(bookDockSubtitle({'readyToFile': 4, 'working': 1}), '4 files ready to file');
      expect(bookDockSubtitle({'working': 1, 'pending': 1}), '1 file processing');
      expect(bookDockSubtitle({'pending': 2}), '2 files waiting');
      expect(bookDockSubtitle({'total': 0}), 'Nothing waiting');
      expect(libraryPickerSubtitle({'bookDock': true}, dockSummary: {'needsReview': 3}), '3 files need review');
    });

    test('the Watchlist counts its authors and upcoming releases', () {
      expect(watchlistSubtitle({'watchlistAuthors': 4}, upcoming: 4), '4 authors · 4 upcoming');
      expect(watchlistSubtitle({'watchlistAuthors': 1}, upcoming: 0), '1 author');
      expect(watchlistSubtitle({'watchlistAuthors': 4}), '4 authors');
      expect(watchlistSubtitle({'watchlistAuthors': 0}), 'No authors yet');
      expect(watchlistSubtitle({}, upcoming: 2), '2 upcoming');
      expect(watchlistSubtitle({'watchlist': true}), isNull);
      expect(libraryPickerSubtitle({'watchlist': true, 'watchlistAuthors': 2}), '2 authors');
      expect(libraryPickerSubtitle({'watchlist': true, 'watchlistAuthors': 2}, watchlistUpcoming: 1),
          '2 authors · 1 upcoming');
    });
  });

  group('icon', () {
    test('the virtual libraries keep their own icons', () {
      expect(forkLibraryIconData({'bookDock': true, 'icon': 'database'}), Icons.move_to_inbox_rounded);
      expect(forkLibraryIconData({'watchlist': true, 'icon': 'database'}), Icons.visibility_rounded);
    });

    test("BookOrbit's Lucide names map to Material icons", () {
      expect(forkLibraryIconData({'icon': 'Headphones'}), Icons.headphones_rounded);
      expect(forkLibraryIconData({'icon': 'BookOpen'}), Icons.menu_book_rounded);
      expect(forkLibraryIconData({'icon': 'Library'}), Icons.local_library_rounded);
    });

    test("Audiobookshelf's names map to Material icons", () {
      expect(forkLibraryIconData({'icon': 'books-1'}), Icons.menu_book_rounded);
      expect(forkLibraryIconData({'icon': 'headphones'}), Icons.headphones_rounded);
    });

    test("'database', the default nobody picked, shows the media type instead", () {
      expect(forkLibraryIconData({'icon': 'database'}), Icons.auto_stories_rounded);
      expect(forkLibraryIconData({'icon': 'database', 'mediaType': 'podcast'}), Icons.podcasts_rounded);
    });

    test('an unknown or missing name falls back to the media type', () {
      expect(forkLibraryIconData({'icon': 'NoSuchIcon'}), Icons.auto_stories_rounded);
      expect(forkLibraryIconData({'icon': 'NoSuchIcon', 'mediaType': 'podcast'}), Icons.podcasts_rounded);
      expect(forkLibraryIconData({'mediaType': 'book'}), Icons.auto_stories_rounded);
      expect(forkLibraryIconData(null), Icons.auto_stories_rounded);
    });

    test('a custom icon has a slug and a URL, and a fallback by media type', () {
      expect(forkCustomIconSlug({'icon': 'custom:my-star'}), 'my-star');
      expect(forkCustomIconSlug({'icon': 'custom:Bad Slug'}), isNull);
      expect(forkCustomIconSlug({'icon': 'Headphones'}), isNull);
      expect(forkCustomIconSlug(null), isNull);
      expect(forkLibraryIconData({'icon': 'custom:my-star', 'mediaType': 'podcast'}), Icons.podcasts_rounded);
      expect(forkCustomIconUrl('https://books.example/', 'my-star'),
          'https://books.example/api/v1/custom-icons/my-star.svg');
    });
  });
}
