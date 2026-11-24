import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
