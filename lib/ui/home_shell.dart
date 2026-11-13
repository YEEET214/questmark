import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/navigation_controller.dart';
import 'map/map_page.dart';
import 'tasks/task_list_page.dart';

/// The app's top-level scaffold: the current page plus a bottom navigation
/// bar for switching between the task list and the map.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationController>();

    return Scaffold(
      // IndexedStack keeps both pages alive while switching tabs. This
      // matters for the map: rebuilding it would lose the camera position
      // and reload tiles, which wastes network and battery.
      body: IndexedStack(
        index: nav.current.index,
        children: const [
          TaskListPage(),
          MapPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: nav.current.index,
        onDestinationSelected: (i) => nav.select(AppTab.values[i]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Quests',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
        ],
      ),
    );
  }
}
