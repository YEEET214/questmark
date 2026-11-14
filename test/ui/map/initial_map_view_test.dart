import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:questmark/ui/map/initial_map_view.dart';
import 'package:questmark/ui/map/map_config.dart';

void main() {
  const helsinki = LatLng(60.17, 24.94);
  const tampere = LatLng(61.50, 23.76);

  group('InitialMapView.forPoints', () {
    test('no quests: whole world', () {
      expect(InitialMapView.forPoints([]), isA<WorldView>());
    });

    test('one quest: centred on it at quest zoom', () {
      final v = InitialMapView.forPoints([helsinki]) as CenterView;
      expect(v.center, helsinki);
      expect(v.zoom, MapConfig.questZoom);
    });

    test('several quests at the same spot: treated like one', () {
      expect(InitialMapView.forPoints([helsinki, helsinki]), isA<CenterView>());
    });

    test('quests in different places: fit them all', () {
      final v = InitialMapView.forPoints([helsinki, tampere]) as FitView;
      expect(v.points, [helsinki, tampere]);
    });
  });

  group('toMapOptions', () {
    test('world view uses the configured world centre and zoom', () {
      final o = const WorldView().toMapOptions();
      expect(o.initialCenter, MapConfig.worldCenter);
      expect(o.initialZoom, MapConfig.worldZoom);
      expect(o.initialCameraFit, isNull);
    });

    test('fit view sets a camera fit capped at quest zoom', () {
      final o = const FitView([helsinki, tampere]).toMapOptions();
      expect(o.initialCameraFit, isA<FitCoordinates>());
      expect((o.initialCameraFit! as FitCoordinates).maxZoom,
          MapConfig.questZoom);
    });

    test('every view applies the zoom limits and disables rotation', () {
      for (final v in [
        const WorldView(),
        const CenterView(helsinki, 15),
        const FitView([helsinki, tampere]),
      ]) {
        final o = v.toMapOptions();
        expect(o.minZoom, MapConfig.minZoom);
        expect(o.maxZoom, MapConfig.maxZoom);
        expect(
            InteractiveFlag.hasFlag(
                o.interactionOptions.flags, InteractiveFlag.rotate),
            isFalse);
        expect(
            InteractiveFlag.hasFlag(
                o.interactionOptions.flags, InteractiveFlag.pinchZoom),
            isTrue);
      }
    });
  });
}
