import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/providers/auth_provider.dart';
import 'package:absorb/services/book_stats_service.dart';
import 'package:absorb/widgets/fork/reading_log_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('compact card fits a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final stats = BookStatsService.instance.stats('reading-log-card-test');
    stats.loading = false;
    stats.mySessions = 2;
    stats.mySeconds = 9060;
    stats.sessions = [
      {
        'sessionType': 'listen',
        'format': 'EPUB',
        'source': 'android',
        'ownDevice': true,
        'startedAt': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        'timeListening': 8520,
        'progressDelta': 41.8,
        'endProgress': 100,
      },
      {
        'sessionType': 'read',
        'format': 'EPUB',
        'source': 'koreader',
        'startedAt': now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
        'timeListening': 15,
        'progressDelta': -87.1,
        'endProgress': 4,
      },
    ];
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 1200), textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ReadingLogCard(itemId: 'reading-log-card-test', accent: Colors.amber),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('+41.8% \uFFFC 100%', findRichText: true), findsOneWidget);
    expect(find.text('−87.1% \uFFFC 4%', findRichText: true), findsOneWidget);
    expect(find.text('2h 22m'), findsOneWidget);
  });
}
