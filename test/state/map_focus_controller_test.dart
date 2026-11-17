import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/state/map_focus_controller.dart';

void main() {
  final located = Task(
    id: 7,
    title: 'Buy milk',
    createdAt: DateTime.utc(2026),
    location: GeoPoint(60.17, 24.94),
  );

  late MapFocusController focus;
  late int notifications;

  setUp(() {
    focus = MapFocusController();
    notifications = 0;
    focus.addListener(() => notifications++);
  });

  test('starts with no request and no highlight', () {
    expect(focus.pendingRequest, isNull);
    expect(focus.highlightedTaskId, isNull);
  });

  test('focusOn stores a request, highlights the task and notifies', () {
    focus.focusOn(located);
    expect(focus.pendingRequest!.taskId, 7);
    expect(focus.pendingRequest!.point, GeoPoint(60.17, 24.94));
    expect(focus.highlightedTaskId, 7);
    expect(notifications, 1);
  });

  test('takeRequest returns the request once, and keeps the highlight', () {
    focus.focusOn(located);
    expect(focus.takeRequest()!.taskId, 7);
    expect(focus.takeRequest(), isNull);
    expect(focus.highlightedTaskId, 7);
  });

  test('a newer request replaces an older one', () {
    focus.focusOn(located);
    final other = located.copyWith(id: 8, location: () => GeoPoint(1, 2));
    focus.focusOn(other);
    expect(focus.takeRequest()!.taskId, 8);
    expect(focus.highlightedTaskId, 8);
  });

  test('clearHighlight clears it and notifies only if something changed', () {
    focus.focusOn(located);
    notifications = 0;
    focus.clearHighlight();
    expect(focus.highlightedTaskId, isNull);
    expect(notifications, 1);

    focus.clearHighlight();
    expect(notifications, 1);
  });

  test('rejects tasks without a location or without an id', () {
    expect(() => focus.focusOn(located.copyWith(location: () => null)),
        throwsArgumentError);
    expect(() => focus.focusOn(located.withoutId()), throwsArgumentError);
    expect(notifications, 0);
  });
}
