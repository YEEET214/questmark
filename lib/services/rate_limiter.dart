/// Runs tasks one at a time, starting each at least [minInterval] after
/// the previous one started (PLAN.md D6).
///
/// Nominatim allows at most one request per second and no parallel
/// requests. Every Nominatim call goes through one shared limiter, so the
/// app can't break that rule however fast the user taps.
///
/// Tasks queue in order. A task that fails doesn't block the ones after it.
class RateLimiter {
  RateLimiter(this.minInterval, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Duration minInterval;
  final DateTime Function() _clock;

  Future<void> _tail = Future.value();
  DateTime? _lastStart;

  /// Queues [task] and completes with its result (or error).
  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) async {
      final last = _lastStart;
      if (last != null) {
        final wait = last.add(minInterval).difference(_clock());
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      _lastStart = _clock();
      return task();
    });
    // The next task waits for this one to finish, whether it succeeded or
    // failed.
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}
