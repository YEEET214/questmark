import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/navigation_controller.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';

/// Root widget. Provides the app-wide state objects and the theme.
///
/// Dependencies are created here (the composition root) and handed down
/// through `provider`. Widgets never construct services themselves, so
/// tests can pump [QuestMarkApp] with fakes injected through the
/// constructor.
class QuestMarkApp extends StatelessWidget {
  const QuestMarkApp({super.key, this.navigationController});

  /// Optional pre-built controller, mainly for tests.
  final NavigationController? navigationController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NavigationController>(
          create: (_) => navigationController ?? NavigationController(),
        ),
      ],
      child: MaterialApp(
        title: 'QuestMark',
        debugShowCheckedModeBanner: false,
        theme: buildQuestTheme(Brightness.light),
        darkTheme: buildQuestTheme(Brightness.dark),
        home: const HomeShell(),
      ),
    );
  }
}
