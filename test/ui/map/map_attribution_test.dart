import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/ui/map/map_attribution.dart';
import 'package:questmark/ui/map/map_config.dart';

void main() {
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(right: 12, bottom: 12, child: MapAttribution()),
              ],
            ),
          ),
        ),
      );

  testWidgets('starts as a small "i" button', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('attributionButton')), findsOneWidget);
    expect(find.byKey(const Key('attributionCard')), findsNothing);
    expect(find.byTooltip('Map credits'), findsOneWidget);
  });

  testWidgets('tapping it shows every required credit; ✕ closes it',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('attributionButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('attributionCard')), findsOneWidget);
    for (final a in MapConfig.attributions) {
      expect(find.text(a), findsOneWidget, reason: a);
    }

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attributionCard')), findsNothing);
    expect(find.byKey(const Key('attributionButton')), findsOneWidget);
  });
}
