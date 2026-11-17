import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/ui/map/missing_location_badge.dart';

void main() {
  Future<void> pumpBadge(WidgetTester tester, int count) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: MissingLocationBadge(count: count),
        ),
      ),
    ));
  }

  Finder badge() => find.byKey(const Key('missingLocationBadge'));

  test('label uses singular and plural correctly', () {
    expect(MissingLocationBadge.label(1), '1 task without a location');
    expect(MissingLocationBadge.label(3), '3 tasks without locations');
  });

  testWidgets('hidden when every task has a location', (tester) async {
    await pumpBadge(tester, 0);
    expect(badge(), findsNothing);
  });

  testWidgets('starts collapsed as a small "!" circle', (tester) async {
    await pumpBadge(tester, 3);
    expect(find.text('!'), findsOneWidget);
    expect(find.text('3 tasks without locations'), findsNothing);
    final size = tester.getSize(badge());
    expect(size.width, size.height, reason: 'collapsed badge is a circle');
  });

  testWidgets('tap expands to show the count, tap again collapses',
      (tester) async {
    await pumpBadge(tester, 3);
    final collapsedWidth = tester.getSize(badge()).width;

    await tester.tap(badge());
    await tester.pumpAndSettle();
    expect(find.text('3 tasks without locations'), findsOneWidget);
    expect(tester.getSize(badge()).width, greaterThan(collapsedWidth));

    await tester.tap(badge());
    await tester.pumpAndSettle();
    expect(find.text('3 tasks without locations'), findsNothing);
    expect(tester.getSize(badge()).width, collapsedWidth);
  });

  testWidgets('screen readers hear the count and the expanded state',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpBadge(tester, 1);
    expect(find.bySemanticsLabel('1 task without a location'), findsOneWidget);
    handle.dispose();
  });
}
