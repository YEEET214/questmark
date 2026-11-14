import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/task.dart';

void main() {
  final created = DateTime.utc(2026, 11, 14, 9, 30);

  Task fullTask() => Task(
        id: 7,
        title: 'Return library books',
        description: 'Three books, due Friday',
        isDone: true,
        createdAt: created,
        dueAt: DateTime.utc(2026, 11, 20, 16),
        address: 'Oodi, Helsinki',
        location: GeoPoint(60.1738, 24.9380),
      );

  group('Task validation and normalisation', () {
    test('trims the title and rejects empty titles', () {
      expect(Task(title: '  Buy milk ', createdAt: created).title, 'Buy milk');
      expect(() => Task(title: '', createdAt: created), throwsArgumentError);
      expect(() => Task(title: '   ', createdAt: created), throwsArgumentError);
    });

    test('turns blank description and address into null', () {
      final t = Task(
          title: 'x', description: '  ', address: '', createdAt: created);
      expect(t.description, isNull);
      expect(t.address, isNull);
    });

    test('defaults: not done, no location, no id', () {
      final t = Task(title: 'x', createdAt: created);
      expect(t.isDone, isFalse);
      expect(t.hasLocation, isFalse);
      expect(t.id, isNull);
    });

    test('stores times as UTC truncated to milliseconds', () {
      final local = DateTime(2026, 11, 14, 12, 0, 0, 123, 456);
      final t = Task(title: 'x', createdAt: local, dueAt: local);
      expect(t.createdAt.isUtc, isTrue);
      expect(t.createdAt.microsecond, 0);
      expect(t.createdAt.millisecondsSinceEpoch, local.millisecondsSinceEpoch);
      expect(t.dueAt!.isUtc, isTrue);
    });
  });

  group('Task <-> SQLite row', () {
    test('toMap uses SQLite-friendly types', () {
      final m = fullTask().toMap();
      expect(m[Task.colIsDone], 1);
      expect(m[Task.colCreatedAt], created.millisecondsSinceEpoch);
      expect(m[Task.colLatitude], 60.1738);
      expect(m[Task.colLongitude], 24.9380);
    });

    test('toMap omits a null id so SQLite assigns one', () {
      final m = Task(title: 'x', createdAt: created).toMap();
      expect(m.containsKey(Task.colId), isFalse);
      expect(m[Task.colLatitude], isNull);
      expect(m[Task.colLongitude], isNull);
    });

    test('round trip through toMap/fromMap preserves every field', () {
      final t = fullTask();
      expect(Task.fromMap(t.toMap()), t);
    });

    test('round trip works for a minimal task', () {
      final t = Task(id: 1, title: 'x', createdAt: created);
      expect(Task.fromMap(t.toMap()), t);
    });

    test('fromMap rejects a row with only one coordinate', () {
      final m = fullTask().toMap()..[Task.colLongitude] = null;
      expect(() => Task.fromMap(m), throwsFormatException);
    });

    test('fromMap accepts integer-valued coordinates', () {
      // SQLite may hand back a whole-number REAL as an int.
      final m = fullTask().toMap()
        ..[Task.colLatitude] = 60
        ..[Task.colLongitude] = 25;
      expect(Task.fromMap(m).location, GeoPoint(60, 25));
    });
  });

  group('Task.isOverdue', () {
    final now = DateTime(2026, 11, 14, 10); // local time

    Task due(DateTime? at, {bool done = false}) =>
        Task(title: 'x', createdAt: created, dueAt: at, isDone: done);

    test('false without a due date', () {
      expect(due(null).isOverdue(now), isFalse);
    });

    test('true when the due day is before today', () {
      expect(due(DateTime(2026, 11, 13, 23, 59)).isOverdue(now), isTrue);
    });

    test('false on the due day itself, even later that day', () {
      expect(due(DateTime(2026, 11, 14)).isOverdue(now), isFalse);
      expect(due(DateTime(2026, 11, 14)).isOverdue(DateTime(2026, 11, 14, 23)),
          isFalse);
    });

    test('false for future due dates', () {
      expect(due(DateTime(2026, 12, 1)).isOverdue(now), isFalse);
    });

    test('false once the task is done', () {
      expect(due(DateTime(2026, 1, 1), done: true).isOverdue(now), isFalse);
    });
  });

  group('Task.withoutId', () {
    test('clears only the id', () {
      final t = fullTask();
      final copy = t.withoutId();
      expect(copy.id, isNull);
      expect(copy.copyWith(id: t.id), t);
    });
  });

  group('Task.copyWith', () {
    test('changes only the given fields', () {
      final t = fullTask();
      final c = t.copyWith(title: 'New title', isDone: false);
      expect(c.title, 'New title');
      expect(c.isDone, isFalse);
      expect(c.copyWith(title: t.title, isDone: true), t);
    });

    test('nullable fields are kept when omitted and cleared with () => null',
        () {
      final t = fullTask();
      expect(t.copyWith().location, t.location);
      final cleared = t.copyWith(
        location: () => null,
        address: () => null,
        dueAt: () => null,
        description: () => null,
      );
      expect(cleared.location, isNull);
      expect(cleared.address, isNull);
      expect(cleared.dueAt, isNull);
      expect(cleared.description, isNull);
    });

    test('can set a location', () {
      final t = Task(title: 'x', createdAt: created);
      final moved = t.copyWith(location: () => GeoPoint(1, 2));
      expect(moved.location, GeoPoint(1, 2));
      expect(moved.hasLocation, isTrue);
    });
  });
}
