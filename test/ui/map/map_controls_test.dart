import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/ui/map/map_controls.dart';

void main() {
  Future<List<String>> pumpControls(
    WidgetTester tester, {
    bool showCompleted = false,
    bool zoomInEnabled = true,
    bool zoomOutEnabled = true,
  }) async {
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: MapControls(
            showCompleted: showCompleted,
            onToggleCompleted: () => calls.add('toggle'),
            onZoomIn: zoomInEnabled ? () => calls.add('in') : null,
            onZoomOut: zoomOutEnabled ? () => calls.add('out') : null,
          ),
        ),
      ),
    ));
    return calls;
  }

  testWidgets('each button calls its callback', (tester) async {
    final calls = await pumpControls(tester);
    await tester.tap(find.byKey(const Key('zoomInButton')));
    await tester.tap(find.byKey(const Key('zoomOutButton')));
    await tester.tap(find.byKey(const Key('toggleCompletedButton')));
    expect(calls, ['in', 'out', 'toggle']);
  });

  testWidgets('a null callback disables that button', (tester) async {
    final calls = await pumpControls(tester, zoomInEnabled: false);
    await tester.tap(find.byKey(const Key('zoomInButton')));
    expect(calls, isEmpty);
  });

  testWidgets('toggle tooltip and icon reflect the current state',
      (tester) async {
    await pumpControls(tester);
    expect(find.byTooltip('Show completed'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    await pumpControls(tester, showCompleted: true);
    expect(find.byTooltip('Hide completed'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('buttons are small (40 x 40) and have tooltips',
      (tester) async {
    await pumpControls(tester);
    for (final key in ['zoomInButton', 'zoomOutButton', 'toggleCompletedButton']) {
      expect(tester.getSize(find.byKey(Key(key))),
          const Size.square(MapControls.buttonSize));
    }
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.byTooltip('Zoom out'), findsOneWidget);
  });
}
