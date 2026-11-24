import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/settings_repository.dart';
import 'package:questmark/state/settings_controller.dart';

class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository([Map<String, String>? saved]) : saved = saved ?? {};
  final Map<String, String> saved;
  bool broken = false;

  @override
  Future<Map<String, String>> loadAll() async {
    if (broken) throw StateError('disk error');
    return Map.of(saved);
  }

  @override
  Future<void> save(String key, String value) async {
    if (broken) throw StateError('disk error');
    saved[key] = value;
  }
}

void main() {
  test('defaults: follow the phone, no high contrast', () {
    final c = SettingsController();
    expect(c.themeMode, AppThemeMode.system);
    expect(c.themeMode.themeMode, ThemeMode.system);
    expect(c.highContrast, isFalse);
  });

  test('loads what was saved', () async {
    final c = SettingsController(FakeSettingsRepository(
        {'theme_mode': 'dark', 'high_contrast': 'true'}));
    await c.load();
    expect(c.themeMode, AppThemeMode.dark);
    expect(c.highContrast, isTrue);
  });

  test('changes apply at once, notify, and are saved', () async {
    final repo = FakeSettingsRepository();
    final c = SettingsController(repo);
    var notified = 0;
    c.addListener(() => notified++);
    await c.setThemeMode(AppThemeMode.light);
    await c.setHighContrast(true);
    expect(c.themeMode.themeMode, ThemeMode.light);
    expect(repo.saved, {'theme_mode': 'light', 'high_contrast': 'true'});
    expect(notified, 2);

    await c.setHighContrast(true); // no change: nothing happens
    expect(notified, 2);
  });

  test('an unknown saved value falls back to the default', () async {
    final c =
        SettingsController(FakeSettingsRepository({'theme_mode': 'purple'}));
    await c.load();
    expect(c.themeMode, AppThemeMode.system);
  });

  test('a broken database never stops the app', () async {
    final repo = FakeSettingsRepository()..broken = true;
    final c = SettingsController(repo);
    await c.load();
    expect(c.themeMode, AppThemeMode.system);
    await c.setThemeMode(AppThemeMode.dark);
    expect(c.themeMode, AppThemeMode.dark, reason: 'still applies now');
  });
}
