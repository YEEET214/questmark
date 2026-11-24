import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/geocode_cache_repository.dart';
import 'data/last_location_repository.dart';
import 'data/offline_region_store.dart';
import 'data/settings_repository.dart';
import 'data/task_repository.dart';
import 'services/caching_geocoding_service.dart';
import 'services/geocoding_service.dart';
import 'services/location_service.dart';
import 'services/region_downloader.dart';
import 'services/tile_fetcher.dart';
import 'state/offline_maps_controller.dart';
import 'state/settings_controller.dart';
import 'ui/map/base_map_layer.dart';

Future<void> main() async {
  // Plugins (sqflite) can only be used after the binding is initialised.
  WidgetsFlutterBinding.ensureInitialized();

  // Open the database once, before the first frame. It stays open for the
  // app's lifetime; the OS closes it when the process ends.
  final db = await AppDatabase.open();

  // Dark mode and high contrast, before the first frame, so the app never
  // shows the wrong theme for a moment (PLAN.md D28).
  final settings = SettingsController(SqfliteSettingsRepository(db));
  await settings.load();

  // Nominatim behind the SQLite cache: the same question is never sent
  // twice, and every request is rate limited (PLAN.md D6).
  final geocoder =
      CachingGeocodingService(NominatimGeocoder(), SqfliteGeocodeCache(db));

  // Downloaded map regions, in their own file (PLAN.md D26). Downloads
  // only ever start from a button.
  final regions = await OfflineRegionStore.open();
  final offlineMaps = OfflineMapsController(
    regions,
    RegionDownloader(regions, OpenFreeMapTileFetcher()),
    geocoder: geocoder,
  )..load();

  runApp(
    QuestMarkApp(
      taskRepository: SqfliteTaskRepository(db),
      locationService: const GeolocatorLocationService(),
      lastLocationRepository: SqfliteLastLocationRepository(db),
      geocodingService: geocoder,
      settings: settings,
      offlineMaps: offlineMaps,
      regionTiles: regions,
      // The same cache the map draws from (opened once, app-wide), for
      // its size and "Clear" in Settings.
      tileCache: await openAppTileCache(),
    ),
  );
}
