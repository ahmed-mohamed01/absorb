import 'package:absorb/main.dart' show flatNotifier, gradientIntensityNotifier;
import 'package:absorb/widgets/fork/shelf_sheet_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber, brightness: Brightness.dark),
    scaffoldBackgroundColor: const Color(0xFF101010),
  );

  Future<LinearGradient?> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: const Scaffold(body: ForkShelfSheetFrame(child: Text('content'))),
    ));
    expect(find.text('content'), findsOneWidget);
    final boxes = tester.widgetList<DecoratedBox>(find.descendant(
      of: find.byType(ForkShelfSheetFrame),
      matching: find.byType(DecoratedBox),
    ));
    return boxes
        .map((b) => (b.decoration as BoxDecoration).gradient)
        .whereType<LinearGradient>()
        .firstOrNull;
  }

  tearDown(() {
    flatNotifier.value = false;
    gradientIntensityNotifier.value = 0.06;
  });

  testWidgets('the sheet fades from the accent at Home\'s intensity to the background', (tester) async {
    gradientIntensityNotifier.value = 0.2;
    final gradient = await pump(tester);
    expect(gradient, isNotNull);
    expect(gradient!.colors.first, theme.colorScheme.primary.withValues(alpha: 0.2));
    expect(gradient.colors.last, theme.scaffoldBackgroundColor);
  });

  testWidgets('the flat background paints no gradient, as on Home', (tester) async {
    flatNotifier.value = true;
    expect(await pump(tester), isNull);
  });
}
