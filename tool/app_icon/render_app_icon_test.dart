// Draws the app icon (PLAN.md D31): the compass from the empty quest list
// (Icons.explore_outlined), in the app's dark-mode colours: the dark
// theme's primary colour on its background.
//
// Run once on a PC, then let flutter_launcher_icons make every size:
//
//   flutter test tool/app_icon/render_app_icon_test.dart
//   dart run flutter_launcher_icons
//
// It's a "test" only because the Flutter test runner can draw images
// without a phone. It lives in tool/, so `flutter test` doesn't run it.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/ui/theme.dart';

const _size = 1024.0;

/// The icon font that ships with Flutter, so the glyph is exactly the one
/// the app shows.
File _materialIconsFont() {
  // flutter_tester runs from <flutter>/bin/cache/artifacts/engine/<os>/.
  final engineDir = File(Platform.resolvedExecutable).parent;
  final artifacts = engineDir.parent.parent;
  return File('${artifacts.path}/material_fonts/materialicons-regular.otf');
}

Future<void> _write(String path, ui.Image image) async {
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

/// [transparent]: no background (the Android adaptive-icon foreground).
Future<ui.Image> _draw({
  required Color background,
  required Color glyphColor,
  required double glyphFraction,
  bool transparent = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (!transparent) {
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, _size, _size), Paint()..color = background);
  }
  final glyph = String.fromCharCode(Icons.explore_outlined.codePoint);
  final fontSize = _size * glyphFraction;
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
    fontFamily: Icons.explore_outlined.fontFamily,
    fontSize: fontSize,
    height: 1,
  ))
    ..pushStyle(ui.TextStyle(
      color: glyphColor,
      fontFamily: Icons.explore_outlined.fontFamily,
      fontSize: fontSize,
      height: 1,
    ))
    ..addText(glyph);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: _size));
  canvas.drawParagraph(
    paragraph,
    Offset((_size - paragraph.maxIntrinsicWidth) / 2,
        (_size - paragraph.height) / 2),
  );
  return recorder.endRecording().toImage(_size.toInt(), _size.toInt());
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render the app icon', () async {
    final font = _materialIconsFont();
    expect(font.existsSync(), isTrue, reason: font.path);
    final loader = FontLoader(Icons.explore_outlined.fontFamily!)
      ..addFont(Future.value(
          ByteData.view(font.readAsBytesSync().buffer)));
    await loader.load();

    final scheme = buildQuestTheme(Brightness.dark).colorScheme;
    final background = scheme.surface;
    final glyph = scheme.primary;

    // iOS and older Android: the whole square.
    await _write('assets/icon/app_icon.png',
        await _draw(background: background, glyphColor: glyph, glyphFraction: 0.7));
    // Android 8+ adaptive icon: the glyph alone, on the colour below.
    // flutter_launcher_icons insets it by 16 % on each side, and the phone
    // shows the middle 66 % of the layer, so it's drawn bigger here to end
    // up the same size as on the square icon.
    await _write(
        'assets/icon/app_icon_foreground.png',
        await _draw(
            background: background,
            glyphColor: glyph,
            glyphFraction: 0.66,
            transparent: true));
    File('assets/icon/colors.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
      'background': _hex(background),
      'glyph': _hex(glyph),
    }));
    // ignore: avoid_print
    print('background ${_hex(background)}, glyph ${_hex(glyph)}');
  });
}
