import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/task_repository.dart';
import 'state/map_focus_controller.dart';
import 'state/navigation_controller.dart';
import 'state/task_list_controller.dart';
import 'state/task_list_view_controller.dart';
import 'ui/home_shell.dart';
import 'ui/map/base_map_layer.dart';
import 'ui/theme.dart';

/// Root widget. Provides the app-wide state objects and the theme.
///
/// Dependencies are created in `main.dart` (the composition root) and passed
/// in here. Widgets never construct services themselves, so tests can pump
/// [QuestMarkApp] with fakes, e.g. an in-memory [TaskRepository].
class QuestMarkApp extends StatelessWidget {
  const QuestMarkApp({
    super.key,
    required this.taskRepository,
    this.navigationController,
    this.mapBaseLayer = const OpenFreeMapLayer(),
  });

  final TaskRepository taskRepository;

  /// Optional pre-built controller, mainly for tests.
  final NavigationController? navigationController;

  /// The map's base layer. Tests pass an empty widget so no map tiles are
  /// loaded from the network.
  final Widget mapBaseLayer;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NavigationController>(
          create: (_) => navigationController ?? NavigationController(),
        ),
        ChangeNotifierProvider<MapFocusController>(
          create: (_) => MapFocusController(),
        ),
        ChangeNotifierProvider<TaskListViewController>(
          create: (_) => TaskListViewController(),
        ),
        ChangeNotifierProvider<TaskListController>(
          create: (_) => TaskListController(taskRepository)..load(),
        ),
      ],
      child: MaterialApp(
        title: 'QuestMark',
        debugShowCheckedModeBanner: false,
        theme: buildQuestTheme(Brightness.light),
        darkTheme: buildQuestTheme(Brightness.dark),
        home: HomeShell(mapBaseLayer: mapBaseLayer),
      ),
    );
  }
}
