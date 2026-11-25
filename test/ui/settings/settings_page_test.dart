import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:questmark/data/tile_cache.dart';
import 'package:questmark/state/map_cache_controller.dart';
import 'package:questmark/state/settings_controller.dart';
import 'package:questmark/ui/settings/settings_page.dart';

import '../../helpers/fake_tile_cache.dart';

void main() {
  late SettingsController settings;

  Future<void> pump(WidgetTester tester) async {
    settings = SettingsController();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings,
      child: const MaterialApp(home: SettingsPage()),
    ));
  }

  testWidgets('shows the theme choices and the high contrast switch',
      (tester) async {
    await pump(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.text('High contrast mode'), findsOneWidget);
    expect(
        tester
            .widget<RadioGroup<AppThemeMode>>(
                find.byType(RadioGroup<AppThemeMode>))
            .groupValue,
        AppThemeMode.system);
  });

  testWidgets('choosing Dark mode and Light', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('themeMode-dark')));
    await tester.pump();
    expect(settings.themeMode, AppThemeMode.dark);
    await tester.tap(find.byKey(const Key('themeMode-light')));
    await tester.pump();
    expect(settings.themeMode, AppThemeMode.light);
  });

  testWidgets('Privacy: what is sent to Nominatim, word for word '
      '(moved from the address search, Phase 9b)', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('Privacy'), 100);
    expect(find.text('Address search'), findsOneWidget);
    expect(
        find.text('Searches and quest locations are sent to OpenStreetMap\'s '
            'Nominatim service to find addresses. Your own location is only '
            'sent, rounded to about 1 km, to name a map area you download.'),
        findsOneWidget);
  });

  testWidgets('the high contrast switch', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('highContrastSwitch')));
    await tester.pump();
    expect(settings.highContrast, isTrue);
    await tester.tap(find.byKey(const Key('highContrastSwitch')));
    await tester.pump();
    expect(settings.highContrast, isFalse);
  });
  group('Storage: the map cache (Phase 9b, D29)', () {
    late FakeTileCache cache;

    Future<void> pumpWithCache(WidgetTester tester) async {
      settings = SettingsController();
      cache = FakeTileCache()
        ..tiles['14/1/1'] = CachedTile(Uint8List(34000000), fresh: true);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(
              create: (_) =>
                  MapCacheController(cache, maxBytes: 100 * 1000 * 1000)),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ));
    }

    String size(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('mapCacheSize'))).data!;

    testWidgets('no Storage section without a cache', (tester) async {
      await pump(tester);
      expect(find.text('Storage'), findsNothing);
    });

    testWidgets('shows the size and the limit', (tester) async {
      await pumpWithCache(tester);
      expect(find.text('Storage'), findsOneWidget);
      expect(find.text('Map cache'), findsOneWidget);
      expect(size(tester), '34 MB of up to 100 MB');
    });

    testWidgets('Clear asks first: No keeps it', (tester) async {
      await pumpWithCache(tester);
      await tester.tap(find.byKey(const Key('clearCacheButton')));
      await tester.pumpAndSettle();
      expect(find.text('Clear the map cache?'), findsOneWidget);
      expect(find.textContaining('Downloaded areas and the world map are kept'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('clearCacheNo')));
      await tester.pumpAndSettle();
      expect(cache.clears, 0);
      expect(size(tester), '34 MB of up to 100 MB');
    });

    testWidgets('Yes: "Clearing…" with a bar, then empty, Clear disabled',
        (tester) async {
      await pumpWithCache(tester);
      cache.holdClear = Completer<void>();
      await tester.tap(find.byKey(const Key('clearCacheButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clearCacheYes')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(size(tester), 'Clearing…');
      expect(find.byKey(const Key('mapCacheClearing')), findsOneWidget);

      cache.holdClear!.complete();
      await tester.pumpAndSettle();
      expect(size(tester), '0.0 MB of up to 100 MB');
      expect(
          tester
              .widget<TextButton>(find.byKey(const Key('clearCacheButton')))
              .onPressed,
          isNull);
    });
  });
}
