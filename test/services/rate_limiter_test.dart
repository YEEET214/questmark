import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/services/rate_limiter.dart';

void main() {
  const gap = Duration(milliseconds: 1100);

  /// Runs [body] in fake time, with a limiter whose clock is that time.
  void withLimiter(void Function(FakeAsync async, RateLimiter limiter) body) {
    fakeAsync((async) {
      final start = DateTime(2026, 11, 23);
      final limiter = RateLimiter(gap, clock: () => start.add(async.elapsed));
      body(async, limiter);
    });
  }

  test('the first task starts at once', () {
    withLimiter((async, limiter) {
      var ran = false;
      limiter.run(() async => ran = true);
      async.flushMicrotasks();
      expect(ran, isTrue);
    });
  });

  test('tasks start at least 1.1 s apart, in order', () {
    withLimiter((async, limiter) {
      final starts = <Duration>[];
      for (var i = 0; i < 3; i++) {
        limiter.run(() async => starts.add(async.elapsed));
      }
      async.elapse(const Duration(seconds: 5));
      expect(starts, [Duration.zero, gap, gap * 2]);
    });
  });

  test('never two at once: a slow task delays the next one', () {
    withLimiter((async, limiter) {
      var running = 0;
      var maxRunning = 0;
      final starts = <Duration>[];
      Future<void> slow() async {
        running++;
        maxRunning = running > maxRunning ? running : maxRunning;
        starts.add(async.elapsed);
        await Future<void>.delayed(const Duration(seconds: 3));
        running--;
      }

      limiter.run(slow);
      limiter.run(slow);
      async.elapse(const Duration(seconds: 10));
      expect(maxRunning, 1);
      expect(starts[1], const Duration(seconds: 3),
          reason: 'waits for the first to finish (already > 1.1 s later)');
    });
  });

  test('after a quiet period the next task starts at once', () {
    withLimiter((async, limiter) {
      limiter.run(() async {});
      async.elapse(const Duration(seconds: 10));
      Duration? started;
      limiter.run(() async => started = async.elapsed);
      async.flushMicrotasks();
      expect(started, const Duration(seconds: 10));
    });
  });

  test('a failing task passes its error on and does not block the queue',
      () {
    withLimiter((async, limiter) {
      Object? error;
      limiter
          .run<void>(() async => throw StateError('boom'))
          .catchError((Object e) => error = e);
      int? value;
      limiter.run(() async => 42).then((v) => value = v);
      async.elapse(const Duration(seconds: 2));
      expect(error, isA<StateError>());
      expect(value, 42);
    });
  });
}
