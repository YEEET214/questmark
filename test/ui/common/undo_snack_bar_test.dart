import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/ui/common/undo_snack_bar.dart';

void main() {
  test('lasts 4 seconds and does not persist despite having an action', () {
    final bar = undoSnackBar(message: 'Deleted', onUndo: () {});
    expect(bar.duration, const Duration(seconds: 4));
    expect(undoSnackBarDuration, const Duration(seconds: 4));
    expect(bar.persist, isFalse);
    expect(bar.action!.label, 'Undo');
  });

  testWidgets('disappears by itself after 4 seconds', (tester) async {
    var undone = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                undoSnackBar(message: 'Deleted "x"', onUndo: () => undone = true)),
            child: const Text('show'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.text('Deleted "x"'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Deleted "x"'), findsOneWidget, reason: 'still up at 3 s');

    await tester.pump(const Duration(seconds: 1, milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Deleted "x"'), findsNothing);
    expect(undone, isFalse);
  });

  testWidgets('Undo calls back', (tester) async {
    var undone = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                undoSnackBar(message: 'm', onUndo: () => undone = true)),
            child: const Text('show'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    expect(undone, isTrue);
  });
}
