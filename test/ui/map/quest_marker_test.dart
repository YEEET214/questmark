import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/ui/map/quest_marker.dart';

void main() {
  final task = Task(id: 1, title: 'Buy milk', createdAt: DateTime.utc(2026));

  Future<void> pumpMarker(WidgetTester tester, QuestMarkerKind kind,
      {VoidCallback? onTap}) {
    return tester.pumpWidget(MaterialApp(
      home: Center(child: QuestMarker(task: task, kind: kind, onTap: onTap)),
    ));
  }

  testWidgets('open quest shows "!" and bobs', (tester) async {
    await pumpMarker(tester, QuestMarkerKind.active);
    expect(find.text('!'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('completed quest shows a check and does not animate',
      (tester) async {
    await pumpMarker(tester, QuestMarkerKind.done);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('!'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('respects the "remove animations" accessibility setting',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await pumpMarker(tester, QuestMarkerKind.overdue);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('pauses when tickers are disabled (hidden tab)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TickerMode(
        enabled: false,
        child: Center(
            child: QuestMarker(task: task, kind: QuestMarkerKind.active)),
      ),
    ));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('tapping calls onTap', (tester) async {
    var taps = 0;
    await pumpMarker(tester, QuestMarkerKind.active, onTap: () => taps++);
    await tester.tap(find.byType(QuestMarker));
    expect(taps, 1);
  });

  testWidgets('has a screen-reader label describing the quest',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpMarker(tester, QuestMarkerKind.overdue);
    expect(find.bySemanticsLabel('Quest, overdue: Buy milk'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('changing to done stops the animation', (tester) async {
    await pumpMarker(tester, QuestMarkerKind.active);
    expect(tester.hasRunningAnimations, isTrue);
    await pumpMarker(tester, QuestMarkerKind.done);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('highlighted marker is drawn larger with a halo and says so',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: QuestMarker(
            task: task, kind: QuestMarkerKind.active, highlighted: true),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('questMarkerHalo')), findsOneWidget);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.4);
    expect(find.bySemanticsLabel('Quest: Buy milk, selected'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('not highlighted: normal size, no halo', (tester) async {
    await pumpMarker(tester, QuestMarkerKind.active);
    expect(find.byKey(const Key('questMarkerHalo')), findsNothing);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
}
