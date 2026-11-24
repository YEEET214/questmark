import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/ui/theme.dart';

/// WCAG contrast ratio between two colours (1 to 21).
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    group('${brightness.name} theme', () {
      final normal = buildQuestTheme(brightness).colorScheme;
      final high = buildQuestTheme(brightness, highContrast: true).colorScheme;

      test('has the right brightness', () {
        expect(normal.brightness, brightness);
        expect(high.brightness, brightness);
      });

      test('high contrast: pure black/white background and text', () {
        final dark = brightness == Brightness.dark;
        expect(high.surface, dark ? Colors.black : Colors.white);
        expect(high.onSurface, dark ? Colors.white : Colors.black);
        expect(contrast(high.onSurface, high.surface), closeTo(21, 0.01));
      });

      test('high contrast: secondary text and outlines as strong as text',
          () {
        expect(high.onSurfaceVariant, high.onSurface);
        expect(high.outline, high.onSurface);
        expect(contrast(high.onSurfaceVariant, high.surface),
            greaterThan(contrast(normal.onSurfaceVariant, normal.surface)));
      });

      test('high contrast: buttons meet WCAG AAA (7:1)', () {
        expect(contrast(high.onPrimary, high.primary), greaterThanOrEqualTo(7));
        expect(contrast(high.primary, high.surface), greaterThanOrEqualTo(7));
      });

      test('normal theme still meets WCAG AA (4.5:1) for text', () {
        expect(contrast(normal.onSurface, normal.surface),
            greaterThanOrEqualTo(4.5));
        expect(contrast(normal.onPrimary, normal.primary),
            greaterThanOrEqualTo(4.5));
      });
    });
  }
}
