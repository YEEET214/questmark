import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/task_query.dart';
import 'package:questmark/state/task_list_view_controller.dart';

void main() {
  late TaskListViewController view;
  late int notifications;

  setUp(() {
    view = TaskListViewController();
    notifications = 0;
    view.addListener(() => notifications++);
  });

  test('starts with the default query and nothing kept visible', () {
    expect(view.query, const TaskQuery());
    expect(view.keepVisible, isEmpty);
  });

  test('setQuery notifies only on a real change', () {
    view.setQuery(const TaskQuery());
    expect(notifications, 0);
    view.setQuery(const TaskQuery(search: 'x'));
    expect(view.query.search, 'x');
    expect(notifications, 1);
  });

  test('keepTaskVisible remembers ids and notifies once per new id', () {
    view.keepTaskVisible(3);
    view.keepTaskVisible(3);
    expect(view.keepVisible, {3});
    expect(notifications, 1);
  });

  test('changing a filter releases kept tasks', () {
    view.keepTaskVisible(3);
    view.setQuery(const TaskQuery(status: StatusFilter.notCompleted));
    expect(view.keepVisible, isEmpty);
  });

  test('changing only the sort keeps them', () {
    view.keepTaskVisible(3);
    view.setQuery(const TaskQuery(sortField: SortField.title, ascending: false));
    expect(view.keepVisible, {3});
  });

  test('releaseKeptTasks clears them, and is quiet when already empty', () {
    view.keepTaskVisible(3);
    notifications = 0;
    view.releaseKeptTasks();
    expect(view.keepVisible, isEmpty);
    expect(notifications, 1);
    view.releaseKeptTasks();
    expect(notifications, 1);
  });

  test('keepVisible cannot be modified from outside', () {
    view.keepTaskVisible(1);
    expect(() => view.keepVisible.add(2), throwsUnsupportedError);
  });
}
