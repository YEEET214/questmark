import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/ui/theme.dart';

/// Checks the platform files themselves, since these settings can't be
/// exercised by a widget test (PLAN.md D30).
void main() {
  test('Android: the activity is locked to portrait', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:screenOrientation="portrait"'));
  });

  test('iOS: iPhone and iPad allow portrait only', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, isNot(contains('UIInterfaceOrientationLandscape')));
    expect(plist, contains('UIInterfaceOrientationPortrait'));
    // Without this, iPad multitasking would require every orientation.
    expect(plist, contains('<key>UIRequiresFullScreen</key>'));
  });

  test('the app id is com.yeeet214.questmarkbeta on both platforms', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('applicationId = "com.yeeet214.questmarkbeta"'));
    final xcode =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(xcode, isNot(contains('com.example.questmark')));
    expect(xcode,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.yeeet214.questmarkbeta;'));
  });

  group('app icon (D31): the compass in the dark theme colours', () {
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final dark = buildQuestTheme(Brightness.dark).colorScheme;

    test('Android adaptive icon: the dark background behind the compass',
        () {
      final colors =
          File('android/app/src/main/res/values/colors.xml').readAsStringSync();
      expect(colors, contains('>${hex(dark.surface)}<'),
          reason: 're-run tool/app_icon if the dark theme changes');
      final adaptive = File(
              'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
          .readAsStringSync();
      expect(adaptive, contains('@drawable/ic_launcher_foreground'));
      expect(adaptive, contains('<monochrome>'),
          reason: 'Android 13 themed icons');
    });

    test('every launcher size exists, on Android and iOS', () {
      for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(File('android/app/src/main/res/mipmap-$d/ic_launcher.png')
            .existsSync(), isTrue, reason: d);
        expect(File('android/app/src/main/res/drawable-$d/'
                'ic_launcher_foreground.png')
            .existsSync(), isTrue, reason: d);
      }
      expect(
          File('ios/Runner/Assets.xcassets/AppIcon.appiconset/'
                  'Icon-App-1024x1024@1x.png')
              .existsSync(),
          isTrue);
    });

    test('the source colours match the dark theme', () {
      final source = File('assets/icon/colors.json').readAsStringSync();
      expect(source, contains(hex(dark.surface)));
      expect(source, contains(hex(dark.primary)));
    });
  });
}
