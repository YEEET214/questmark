import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:questmark/state/settings_controller.dart';
import 'package:questmark/ui/settings/settings_page.dart';

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

  testWidgets('the high contrast switch', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('highContrastSwitch')));
    await tester.pump();
    expect(settings.highContrast, isTrue);
    await tester.tap(find.byKey(const Key('highContrastSwitch')));
    await tester.pump();
    expect(settings.highContrast, isFalse);
  });
}
