import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/navigation_controller.dart';
import 'map/base_map_layer.dart';
import 'map/map_page.dart';
import 'tasks/task_list_page.dart';

/// The app's top-level scaffold: the current page plus a bottom navigation
/// bar for switching between the task list and the map.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, this.mapBaseLayer = const OpenFreeMapLayer()});

  /// Passed through to [MapPage]. Tests replace it so they never load real
  /// map tiles.
  final Widget mapBaseLayer;

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationController>();

    return Scaffold(
      // IndexedStack keeps both pages alive while switching tabs. This
      // matters for the map: rebuilding it would lose the camera position
      // and reload tiles, which wastes network and battery.
      body: IndexedStack(
        index: nav.current.index,
        children: [
          _tab(nav, AppTab.tasks, const TaskListPage()),
          _tab(nav, AppTab.map, MapPage(baseLayer: mapBaseLayer)),
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

  /// Hidden tabs keep their state, but their animations are paused
  /// (TickerMode off). That way the bobbing quest markers use no CPU or
  /// battery while you're looking at the list.
  Widget _tab(NavigationController nav, AppTab tab, Widget page) =>
      TickerMode(enabled: nav.current == tab, child: page);
}
