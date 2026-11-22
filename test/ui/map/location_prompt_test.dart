import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/ui/map/location_prompt.dart';

void main() {
  testWidgets('explains why, and its buttons call back', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LocationPrompt(
          onAllow: () => calls.add('allow'),
          onDismiss: () => calls.add('dismiss'),
        ),
      ),
    ));

    expect(find.text('See where you are among your quests'), findsOneWidget);
    expect(find.textContaining('never leaves your phone'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.tap(find.text('Allow'));
    expect(calls, ['dismiss', 'allow']);
  });
}
