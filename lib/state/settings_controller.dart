import 'package:flutter/material.dart';

import '../data/settings_repository.dart';

/// Light or dark, or whatever the phone uses (PLAN.md D28).
enum AppThemeMode {
  system('System default'),
  light('Light'),
  dark('Dark');

  const AppThemeMode(this.label);
  final String label;

  ThemeMode get themeMode => switch (this) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  static AppThemeMode fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => system);
}

/// The app's appearance settings (Settings page, PLAN.md D28): dark mode
/// and high contrast. Saved in SQLite, and loaded before the first frame
/// (main.dart), so the app never flashes the wrong theme.
class SettingsController extends ChangeNotifier {
  /// [repository] null: the settings work but aren't saved (most tests).
  SettingsController([this._repository]);

  final SettingsRepository? _repository;

  static const themeModeKey = 'theme_mode';
  static const highContrastKey = 'high_contrast';

  AppThemeMode _themeMode = AppThemeMode.system;
  bool _highContrast = false;

  AppThemeMode get themeMode => _themeMode;
  bool get highContrast => _highContrast;

  Future<void> load() async {
    final repo = _repository;
    if (repo == null) return;
    try {
      final saved = await repo.loadAll();
      _themeMode = AppThemeMode.fromName(saved[themeModeKey]);
      _highContrast = saved[highContrastKey] == 'true';
      notifyListeners();
    } catch (e) {
      // The defaults are fine; the app must start regardless.
      debugPrint('Settings could not be loaded: $e');
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _save(themeModeKey, mode.name);
  }

  Future<void> setHighContrast(bool on) async {
    if (on == _highContrast) return;
    _highContrast = on;
    notifyListeners();
    await _save(highContrastKey, '$on');
  }

  Future<void> _save(String key, String value) async {
    try {
      await _repository?.save(key, value);
    } catch (e) {
      // The change still applies for this session.
      debugPrint('Setting $key could not be saved: $e');
    }
  }
}
