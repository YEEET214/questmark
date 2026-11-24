import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/last_location_repository.dart';
import 'data/offline_region_store.dart';
import 'data/task_repository.dart';
import 'services/geocoding_service.dart';
import 'services/location_service.dart';
import 'state/location_controller.dart';
import 'state/map_focus_controller.dart';
import 'state/navigation_controller.dart';
import 'state/offline_maps_controller.dart';
import 'state/settings_controller.dart';
import 'state/task_list_controller.dart';
import 'state/task_list_view_controller.dart';
import 'ui/home_shell.dart';
import 'ui/map/base_map_layer.dart';
import 'ui/theme.dart';

/// Root widget. Provides the app-wide state objects and the theme.
///
/// Dependencies are created in `main.dart` (the composition root) and passed
/// in here. Widgets never construct services themselves, so tests can pump
/// [QuestMarkApp] with fakes, e.g. an in-memory [TaskRepository].
class QuestMarkApp extends StatelessWidget {
  const QuestMarkApp({
    super.key,
    required this.taskRepository,
    required this.locationService,
    required this.lastLocationRepository,
    required this.geocodingService,
    this.navigationController,
    this.settings,
    this.offlineMaps,
    this.regionTiles,
    this._mapBaseLayer,
  });

  final TaskRepository taskRepository;

  /// The phone's GPS. Tests pass a fake that emits made-up positions.
  final LocationService locationService;

  /// Where the last GPS fix is remembered between app starts (D19).
  final LastLocationRepository lastLocationRepository;

  /// Address search and lookup (Nominatim behind a cache, PLAN.md D6).
  /// Tests pass a fake, so they never touch the network.
  final GeocodingService geocodingService;

  /// Optional pre-built controller, mainly for tests.
  final NavigationController? navigationController;

  /// Dark mode and high contrast (PLAN.md D28), loaded in main.dart before
  /// the first frame. Tests may leave it out: the defaults, not saved.
  final SettingsController? settings;

  /// Downloaded map regions (PLAN.md D26): the Offline maps screen and
  /// the "download your area?" card. Left out (null) in most tests, which
  /// then have no offline-maps buttons.
  final OfflineMapsController? offlineMaps;

  /// The downloaded tiles, for the map to draw from.
  final RegionTileSource? regionTiles;

  /// The map's base layer. Tests pass an empty widget so no map tiles are
  /// loaded from the network.
  final Widget? _mapBaseLayer;

  @override
  Widget build(BuildContext context) {
    final mapBaseLayer =
        _mapBaseLayer ?? OpenFreeMapLayer(regionTiles: regionTiles);
    final offlineMaps = this.offlineMaps;
    return MultiProvider(
      providers: [
        // The base map for pages pushed on top of the shell (the location
        // picker), so they draw the same map and tests can replace it.
        Provider<MapBaseLayer>.value(value: MapBaseLayer(mapBaseLayer)),
        Provider<GeocodingService>.value(value: geocodingService),
        ChangeNotifierProvider<SettingsController>(
          create: (_) => settings ?? SettingsController(),
        ),
        ChangeNotifierProvider<NavigationController>(
          create: (_) => navigationController ?? NavigationController(),
        ),
        ChangeNotifierProvider<MapFocusController>(
          create: (_) => MapFocusController(),
        ),
        ChangeNotifierProvider<TaskListViewController>(
          create: (_) => TaskListViewController(),
        ),
        ChangeNotifierProvider<TaskListController>(
          create: (_) =>
              TaskListController(taskRepository, geocoder: geocodingService)
                ..load(),
        ),
        if (offlineMaps != null)
          ChangeNotifierProvider<OfflineMapsController>.value(
              value: offlineMaps),
        ChangeNotifierProvider<LocationController>(
          create: (_) =>
              LocationController(locationService, lastLocationRepository)
                ..start(),
        ),
      ],
      child: _ForegroundLocation(
        child: Consumer<SettingsController>(
          builder: (context, s, _) => MaterialApp(
            title: 'QuestMark',
            debugShowCheckedModeBanner: false,
            themeMode: s.themeMode.themeMode,
            theme: buildQuestTheme(Brightness.light,
                highContrast: s.highContrast),
            darkTheme: buildQuestTheme(Brightness.dark,
                highContrast: s.highContrast),
            // Used when the phone's own high-contrast setting is on (iOS
            // "Increase Contrast"; Android doesn't tell Flutter apps).
            highContrastTheme:
                buildQuestTheme(Brightness.light, highContrast: true),
            highContrastDarkTheme:
                buildQuestTheme(Brightness.dark, highContrast: true),
            home: HomeShell(mapBaseLayer: mapBaseLayer),
          ),
        ),
      ),
    );
  }
}

/// Foreground-only GPS (PLAN.md D8): stops the location updates when the
/// app goes to the background, and re-checks and resumes when it comes
/// back (the user may have changed the location settings meanwhile).
class _ForegroundLocation extends StatefulWidget {
  const _ForegroundLocation({required this.child});
  final Widget child;

  @override
  State<_ForegroundLocation> createState() => _ForegroundLocationState();
}

class _ForegroundLocationState extends State<_ForegroundLocation> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final location = context.read<LocationController>();
    _lifecycle = AppLifecycleListener(
      onPause: location.pause,
      onResume: location.resume,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
