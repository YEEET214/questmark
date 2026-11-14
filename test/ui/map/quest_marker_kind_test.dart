import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/ui/map/quest_marker.dart';

void main() {
  final now = DateTime(2026, 11, 14, 10); // local time

  Task task({DateTime? due, bool done = false}) => Task(
        title: 'x',
        createdAt: DateTime.utc(2026, 1, 1),
        dueAt: due,
        isDone: done,
      );

  QuestMarkerKind kindOf(Task t) => QuestMarkerKind.of(t, now);

  group('QuestMarkerKind.of', () {
    test('open quest without a due date is active', () {
      expect(kindOf(task()), QuestMarkerKind.active);
    });

    test('completed quest is done, even if it was overdue', () {
      expect(kindOf(task(done: true)), QuestMarkerKind.done);
      expect(kindOf(task(done: true, due: DateTime(2026, 1, 1))),
          QuestMarkerKind.done);
    });

    test('due day already passed: overdue', () {
      expect(kindOf(task(due: DateTime(2026, 11, 13))), QuestMarkerKind.overdue);
    });

    test('due today or tomorrow: due soon', () {
      expect(kindOf(task(due: DateTime(2026, 11, 14))), QuestMarkerKind.dueSoon);
      expect(kindOf(task(due: DateTime(2026, 11, 15))), QuestMarkerKind.dueSoon);
    });

    test('due in two days or more: active', () {
      expect(kindOf(task(due: DateTime(2026, 11, 16))), QuestMarkerKind.active);
      expect(kindOf(task(due: DateTime(2027, 1, 1))), QuestMarkerKind.active);
    });

    test('day boundaries use local calendar days, not 24-hour spans', () {
      // 23:59 today: due tomorrow is still "due soon", and the day after
      // tomorrow is not.
      final lateNight = DateTime(2026, 11, 14, 23, 59);
      expect(QuestMarkerKind.of(task(due: DateTime(2026, 11, 15)), lateNight),
          QuestMarkerKind.dueSoon);
      expect(QuestMarkerKind.of(task(due: DateTime(2026, 11, 16)), lateNight),
          QuestMarkerKind.active);
    });
  });

  test('only open quests animate', () {
    expect(QuestMarkerKind.active.animates, isTrue);
    expect(QuestMarkerKind.dueSoon.animates, isTrue);
    expect(QuestMarkerKind.overdue.animates, isTrue);
    expect(QuestMarkerKind.done.animates, isFalse);
  });

  test('each state has a distinct colour', () {
    final fills = {
      for (final k in QuestMarkerKind.values) QuestMarkerColors.of(k).fill,
    };
    expect(fills, hasLength(QuestMarkerKind.values.length));
  });
}
