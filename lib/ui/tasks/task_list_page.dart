import 'package:flutter/material.dart';

/// Shows all tasks as a list.
///
/// Placeholder until phase 2 (task list UI).
class TaskListPage extends StatelessWidget {
  const TaskListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quests')),
      body: const Center(child: Text('No quests yet')),
    );
  }
}
