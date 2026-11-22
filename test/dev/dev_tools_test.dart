import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:questmark/dev/dev_tools.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/state/navigation_controller.dart';
import 'package:questmark/state/task_list_controller.dart';
import 'package:questmark/ui/map/quest_marker.dart';

import '../helpers/fake_task_repository.dart';

void main() {
  final now = DateTime(2026, 11, 17, 10);

  group('DemoQuests', () {
    late FakeTaskRepository repo;
    late TaskListController controller;

    setUp(() async {
      repo = FakeTaskRepository([
        Task(id: 1, title: 'My real quest', createdAt: DateTime.utc(2026)),
      ]);
      controller = TaskListController(repo, clock: () => now);
      await controller.load();
    });

    test('add creates every demo quest with the [Demo] prefix', () async {
      final n = await DemoQuests.add(controller, clock: () => now);
      expect(n, DemoQuests.all.length);
      final demo = controller.tasks
          .where((t) => t.title.startsWith(DemoQuests.titlePrefix))
          .toList();
      expect(demo, hasLength(DemoQuests.all.length));
    });

    test('demo quests cover every marker state and some list-only quests',
        () async {
      await DemoQuests.add(controller, clock: () => now);
      final kinds = controller.locatedTasks
          .where((t) => t.title.startsWith(DemoQuests.titlePrefix))
          .map((t) => QuestMarkerKind.of(t, now))
          .toSet();
      expect(kinds, QuestMarkerKind.values.toSet());
      expect(
          controller.unlocatedTasks
              .where((t) => t.title.startsWith(DemoQuests.titlePrefix)),
          isNotEmpty);
    });

    test('removeAll deletes only the demo quests', () async {
      await DemoQuests.add(controller, clock: () => now);
      final removed = await DemoQuests.removeAll(controller);
      expect(removed, DemoQuests.all.length);
      expect(controller.tasks.map((t) => t.title), ['My real quest']);
    });

    test('removeAll also permanently deletes demo quests in the bin',
        () async {
      await DemoQuests.add(controller, clock: () => now);
      final demo = controller.tasks
          .firstWhere((t) => t.title.startsWith(DemoQuests.titlePrefix));
      await controller.moveToBin(demo);

      await DemoQuests.removeAll(controller);
      expect(controller.binTasks, isEmpty);
      expect(await repo.getById(demo.id!), isNull);
      expect(controller.tasks.map((t) => t.title), ['My real quest']);
    });

    test('removeAll with no demo quests does nothing', () async {
      expect(await DemoQuests.removeAll(controller), 0);
      expect(controller.tasks, hasLength(1));
    });
  });

  testWidgets('the dev tools sheet adds demo quests and opens the map',
      (tester) async {
    final repo = FakeTaskRepository();
    final controller = TaskListController(repo)..load();
    final nav = NavigationController();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider.value(value: nav),
      ],
      child: MaterialApp(
        home: Scaffold(appBar: AppBar(actions: const [DevToolsButton()])),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Developer tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add demo quests and open the map'));
    await tester.pumpAndSettle();

    expect(controller.tasks, hasLength(DemoQuests.all.length));
    expect(nav.current, AppTab.map);
    expect(find.text('Added ${DemoQuests.all.length} demo quests'),
        findsOneWidget);
  });
}
