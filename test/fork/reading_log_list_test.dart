import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:absorb/widgets/fork/reading_log_list.dart';

void main() {
  testWidgets(
    'narrow large-text log groups, formats and opens original session',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final session = <String, dynamic>{
        'startedAt': DateTime(
          now.year,
          now.month,
          now.day,
          10,
          38,
        ).millisecondsSinceEpoch,
        'timeListening': 15,
        'sessionType': 'listen',
        'format': 'EPUB',
        'ownDevice': true,
        'progressDelta': 25.1,
        'endProgress': 65,
      };
      Map<String, dynamic>? tapped;
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              alwaysUse24HourFormat: true,
            ),
            child: Scaffold(
              body: ReadingLogList(
                sessions: [
                  session,
                  {...session, 'startedAt': null, 'endProgress': null},
                ],
                scrollController: controller,
                onSessionTap: (s) => tapped = s,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Read-along · Absorb'), findsWidgets);
      expect(find.text('+25.1% \uFFFC 65%', findRichText: true), findsOneWidget);
      expect(
        find.text('Big jump for 15s · likely a position sync'),
        findsWidgets,
      );
      await tester.tap(find.text('10:38'));
      expect(identical(tapped, session), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
