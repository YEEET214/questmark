import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/task_repository.dart';

Future<void> main() async {
  // Plugins (sqflite) can only be used after the binding is initialised.
  WidgetsFlutterBinding.ensureInitialized();

  // Open the database once, before the first frame. It stays open for the
  // app's lifetime; the OS closes it when the process ends.
  final db = await AppDatabase.open();

  runApp(QuestMarkApp(taskRepository: SqfliteTaskRepository(db)));
}
