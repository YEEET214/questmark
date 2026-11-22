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
  group('InitialMapView.choose (start-up order, PLAN.md D19)', () {
    const london = LatLng(51.5, -0.12);
    const paris = LatLng(48.86, 2.35);
    const quests = [helsinki, tampere];

    test('1. a pending "Show on map" request wins over everything', () {
      final r = InitialMapView.choose(
          focus: tampere, gps: london, lastKnown: paris, quests: quests);
      expect(r.source, StartViewSource.focusRequest);
      final v = r.view as CenterView;
      expect(v.center, tampere);
      expect(v.zoom, MapConfig.questZoom);
    });

    test('2. then the live GPS position, at street level', () {
      final r = InitialMapView.choose(
          gps: london, lastKnown: paris, quests: quests);
      expect(r.source, StartViewSource.gps);
      final v = r.view as CenterView;
      expect(v.center, london);
      expect(v.zoom, MapConfig.playerZoom);
    });

    test('3. then the last known position', () {
      final r = InitialMapView.choose(lastKnown: paris, quests: quests);
      expect(r.source, StartViewSource.lastKnown);
      expect((r.view as CenterView).center, paris);
    });

    test('4. otherwise the quests, as before (or the world without any)', () {
      final r = InitialMapView.choose(quests: quests);
      expect(r.source, StartViewSource.quests);
      expect(r.view, isA<FitView>());
      expect(InitialMapView.choose(quests: const []).view, isA<WorldView>());
    });
  });
}
