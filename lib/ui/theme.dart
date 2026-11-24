import 'package:flutter/material.dart';

/// Quest-marker gold. Used as the seed colour so the whole UI shares the
/// palette of the map markers.
const Color questGold = Color(0xFFE0A526);

/// Builds the app theme for the given [brightness] (PLAN.md D28).
///
/// Material 3, seeded from [questGold].
///
/// [highContrast] (the Settings switch, or on iOS the phone's own
/// "Increase Contrast" setting) uses Material's highest contrast level for
/// the generated colours. On top of that, secondary text and outlines get
/// the full text
/// colour, and the background is pure white (light) or pure black (dark),
/// so every label and edge stands out. The map tiles are not changed.
ThemeData buildQuestTheme(Brightness brightness, {bool highContrast = false}) {
  var scheme = ColorScheme.fromSeed(
    seedColor: questGold,
    brightness: brightness,
    contrastLevel: highContrast ? 1.0 : 0.0,
  );
  if (highContrast) {
    final dark = brightness == Brightness.dark;
    scheme = scheme.copyWith(
      surface: dark ? Colors.black : Colors.white,
      onSurface: dark ? Colors.white : Colors.black,
      onSurfaceVariant: dark ? Colors.white : Colors.black,
      outline: dark ? Colors.white : Colors.black,
      outlineVariant: dark ? Colors.white70 : Colors.black87,
    );
  }
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    dividerTheme: highContrast
        ? DividerThemeData(color: scheme.outline, thickness: 1.5)
        : null,
  );
}
