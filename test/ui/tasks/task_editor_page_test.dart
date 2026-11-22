import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/ui/tasks/task_editor_page.dart';

void main() {
  final today = DateTime(2026, 11, 14, 10);

  /// Pumps a launcher screen, opens the editor, and returns a getter for
  /// whatever the editor popped.
  Future<TaskEditorResult? Function()> openEditor(
    WidgetTester tester, {
    Task? initial,
  }) async {
    TaskEditorResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<TaskEditorResult>(
              MaterialPageRoute(
                builder: (_) =>
                    TaskEditorPage(initial: initial, clock: () => today),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('new quest: shows the "New quest" title and no delete button',
      (tester) async {
    await openEditor(tester);
    expect(find.text('New quest'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.text('No due date'), findsOneWidget);
  });

  testWidgets('an empty title is rejected and the editor stays open',
      (tester) async {
    final result = await openEditor(tester);
    await tester.enterText(find.byKey(const Key('titleField')), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Give your quest a title'), findsOneWidget);
    expect(find.byType(TaskEditorPage), findsOneWidget);
    expect(result(), isNull);
  });

  testWidgets('saving returns the entered fields', (tester) async {
    final result = await openEditor(tester);
    await tester.enterText(find.byKey(const Key('titleField')), 'Buy milk');
    await tester.enterText(
        find.byKey(const Key('descriptionField')), 'Oat, 2 litres');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = result() as TaskEditorSaved;
    expect(saved.title, 'Buy milk');
    expect(saved.description, 'Oat, 2 litres');
    expect(saved.dueAt, isNull);
  });

  testWidgets('picking a due date returns that day (local midnight)',
      (tester) async {
    final result = await openEditor(tester);
    await tester.enterText(find.byKey(const Key('titleField')), 'x');

    await tester.tap(find.text('Set due date'));
    await tester.pumpAndSettle();
    // The picker opens on "today" (November 2026, from the injected clock).
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Due 20-11-2026'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((result() as TaskEditorSaved).dueAt, DateTime(2026, 11, 20));
  });

  group('editing an existing quest', () {
    final existing = Task(
      id: 3,
      title: 'Return books',
      description: 'Library',
      createdAt: DateTime.utc(2026, 1, 1),
      dueAt: DateTime(2026, 11, 20),
      location: GeoPoint(60.17, 24.94),
    );

    testWidgets('fields are pre-filled', (tester) async {
      await openEditor(tester, initial: existing);
      expect(find.text('Edit quest'), findsOneWidget);
      expect(find.text('Return books'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Due 20-11-2026'), findsOneWidget);
    });

    testWidgets('the due date can be removed', (tester) async {
      final result = await openEditor(tester, initial: existing);
      await tester.tap(find.byTooltip('Remove due date'));
      await tester.pumpAndSettle();
      expect(find.text('No due date'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((result() as TaskEditorSaved).dueAt, isNull);
    });

    testWidgets('delete asks for confirmation; cancel keeps the editor open',
        (tester) async {
      final result = await openEditor(tester, initial: existing);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete quest?'), findsOneWidget);
      expect(find.textContaining('will be moved to the recycle bin'),
          findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditorPage), findsOneWidget);
      expect(result(), isNull);
    });

    testWidgets('confirmed delete returns TaskEditorDeleted', (tester) async {
      final result = await openEditor(tester, initial: existing);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(result(), isA<TaskEditorDeleted>());
    });

    testWidgets('back button returns null (no change)', (tester) async {
      final result = await openEditor(tester, initial: existing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(result(), isNull);
    });
  });
}
