import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/ui/map/player_marker.dart';

import '../../helpers/fake_location_service.dart';

void main() {
  List<CircleMarker> circles(Widget layer) => (layer as CircleLayer).circles;

  test('the accuracy circle is drawn in metres, at the fix', () {
    final c = circles(PlayerMarker.accuracyLayer(fixAt(60, 24, accuracy: 25)));
    expect(c, hasLength(1));
    expect(c.single.radius, 25);
    expect(c.single.useRadiusInMeter, isTrue);
    expect(c.single.point.latitude, 60);
  });

  test('no circle for a zero or a huge (useless) accuracy', () {
    expect(circles(PlayerMarker.accuracyLayer(fixAt(60, 24, accuracy: 0))),
        isEmpty);
    expect(
        circles(PlayerMarker.accuracyLayer(fixAt(60, 24,
            accuracy: PlayerMarker.maxAccuracyCircleMeters + 1))),
        isEmpty);
  });

  test('the dot sits at the fix', () {
    final m = (PlayerMarker.dotLayer(fixAt(60, 24)) as MarkerLayer).markers;
    expect(m.single.point.latitude, 60);
    expect(m.single.point.longitude, 24);
    expect(m.single.width, PlayerMarker.dotSize);
  });

  testWidgets('the dot is a blue circle with a label for screen readers',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: SizedBox.square(dimension: 22, child: PlayerDot()))));
    final semantics = tester.getSemantics(find.byType(PlayerDot));
    expect(semantics.label, 'Your location');
  });
}
