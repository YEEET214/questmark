import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:questmark/ui/map/camera_animator.dart';
import 'package:questmark/ui/map/map_config.dart';

void main() {
  late MapController map;
  late CameraAnimator camera;

  Future<void> pump(WidgetTester tester) async {
    map = MapController();
    await tester.pumpWidget(MaterialApp(
      home: _Host(
        map: map,
        onReady: (vsync) => camera = CameraAnimator(vsync, map),
      ),
    ));
    await tester.pumpAndSettle();
    addTearDown(() => camera.dispose());
  }

  testWidgets('glides over 600 ms and ends exactly on the target',
      (tester) async {
    await pump(tester);
    camera.animateTo(const LatLng(60.17, 24.94), 12);

    await tester.pump(); // the animation's clock starts on this frame
    await tester.pump(const Duration(milliseconds: 300));
    final midway = map.camera.center;
    expect(midway.latitude, greaterThan(0));
    expect(midway.latitude, lessThan(60.17), reason: 'still moving');

    await tester.pumpAndSettle();
    expect(map.camera.center.latitude, closeTo(60.17, 1e-9));
    expect(map.camera.center.longitude, closeTo(24.94, 1e-9));
    expect(map.camera.zoom, 12);
  });

  testWidgets('instant jumps straight there', (tester) async {
    await pump(tester);
    camera.animateTo(const LatLng(-33.86, 151.2), 10, instant: true);
    await tester.pump();
    expect(map.camera.center.latitude, closeTo(-33.86, 1e-9));
  });

  testWidgets('the zoom is kept within the map limits', (tester) async {
    await pump(tester);
    camera.animateTo(const LatLng(0, 0), 99, instant: true);
    await tester.pump();
    expect(map.camera.zoom, MapConfig.maxZoom);
  });

  testWidgets('a new move replaces one in progress', (tester) async {
    await pump(tester);
    camera.animateTo(const LatLng(60, 25), 10);
    await tester.pump(const Duration(milliseconds: 200));
    camera.animateTo(const LatLng(-30, -60), 5);
    await tester.pumpAndSettle();
    expect(map.camera.center.latitude, closeTo(-30, 1e-9));
    expect(map.camera.center.longitude, closeTo(-60, 1e-9));
  });
}

class _Host extends StatefulWidget {
  const _Host({required this.map, required this.onReady});
  final MapController map;
  final void Function(TickerProvider vsync) onReady;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.onReady(this);
  }

  @override
  Widget build(BuildContext context) => FlutterMap(
        mapController: widget.map,
        options: const MapOptions(initialCenter: LatLng(0, 0), initialZoom: 3),
        children: const [],
      );
}
