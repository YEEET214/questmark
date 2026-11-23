import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/geocode_cache_repository.dart';
import 'data/last_location_repository.dart';
import 'data/task_repository.dart';
import 'services/caching_geocoding_service.dart';
import 'services/geocoding_service.dart';
import 'services/location_service.dart';

Future<void> main() async {
  // Plugins (sqflite) can only be used after the binding is initialised.
  WidgetsFlutterBinding.ensureInitialized();

  // Open the database once, before the first frame. It stays open for the
  // app's lifetime; the OS closes it when the process ends.
  final db = await AppDatabase.open();

  runApp(
    QuestMarkApp(
      taskRepository: SqfliteTaskRepository(db),
      locationService: const GeolocatorLocationService(),
      lastLocationRepository: SqfliteLastLocationRepository(db),
    // Nominatim behind the SQLite cache: the same question is never sent
    // twice, and every request is rate limited (PLAN.md D6).
    geocodingService:
        CachingGeocodingService(NominatimGeocoder(), SqfliteGeocodeCache(db)),
    ),
  );
}
