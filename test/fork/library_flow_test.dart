import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/fork/library_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isVirtualLibrary', () {
    test('recognises visited libraries only', () {
      expect(ForkLibraryFlow.isVirtualLibrary(ApiService.bookDockLibraryId), isTrue);
      expect(ForkLibraryFlow.isVirtualLibrary(ApiService.watchlistLibraryId), isTrue);
      expect(ForkLibraryFlow.isVirtualLibrary('real-library'), isFalse);
      expect(ForkLibraryFlow.isVirtualLibrary(null), isFalse);
    });
  });

  group('restoreLibraryId', () {
    test('keeps a saved real library', () {
      expect(ForkLibraryFlow.restoreLibraryId(saved: 'real-library', lastBook: 'other'), 'real-library');
    });

    test('reopens the last real library after visiting a virtual library', () {
      for (final id in [ApiService.bookDockLibraryId, ApiService.watchlistLibraryId]) {
        expect(ForkLibraryFlow.restoreLibraryId(saved: id, lastBook: 'real-library'), 'real-library');
      }
    });

    test('keeps an empty selection', () {
      expect(ForkLibraryFlow.restoreLibraryId(saved: null, lastBook: null), isNull);
    });
  });
}
