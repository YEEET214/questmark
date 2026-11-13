import 'package:flutter/material.dart';

/// Quest-marker gold. Used as the seed colour so the whole UI shares the
/// palette of the map markers.
const Color questGold = Color(0xFFE0A526);

/// Builds the app theme for the given [brightness].
///
/// This is Material 3 seeded from a single colour, which keeps the theme
/// small for now. The game-style visual design is planned for the polish
/// phase.
ThemeData buildQuestTheme(Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: questGold,
      brightness: brightness,
    ),
  );
}
