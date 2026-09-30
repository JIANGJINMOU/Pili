enum ShortVideoFeedback {
  like(5),
  coin(7),
  favorite(8),
  follow(10),
  dislike(-20);

  const ShortVideoFeedback(this.weight);
  final double weight;
}

/// Uses elapsed playback time, not position deltas (seeking is not watching).
/// Callbacks checkpoint deltas; background/pause never count as a quick skip.
class ShortVideoWatchSession {
  ShortVideoWatchSession({Duration Function()? now})
    : _now = now ?? (() => _clock.elapsed);
  static final _clock = Stopwatch()..start();
  final Duration Function() _now;
  Duration? _activeSince;
  double _rate = 1;
  double watchedMs = 0;
  double mediaMs = 0;
  double _credited = 0;
  int completions = 0;
  bool failed = false;
  bool closed = false;
  final _feedback = <ShortVideoFeedback>{};

  void playing(bool active, {double rate = 1}) {
    final now = _now();
    if (_activeSince != null) {
      final elapsed = (now - _activeSince!).inMicroseconds / 1000;
      watchedMs += elapsed;
      mediaMs += elapsed * _rate;
    }
    _activeSince = active && !closed && !failed ? now : null;
    _rate = rate;
  }

  double settle({
    required Duration duration,
    bool completed = false,
    bool leaving = false,
  }) {
    playing(_activeSince != null, rate: _rate);
    if (closed || failed) return 0;
    if (completed) completions = (completions + 1).clamp(0, 3);
    final fraction = duration.inMilliseconds > 0
        ? mediaMs / duration.inMilliseconds
        : 0;
    double weight = completions > 0
        ? completions * 4.0
        : (fraction >= 0.9 ? 3 : (fraction >= 0.5 ? 1 : 0));
    if (leaving && watchedMs > 0 && completions == 0) {
      if (watchedMs < 2000) {
        weight = -5;
      } else if (duration > Duration.zero && fraction < 0.2) {
        weight = -2;
      }
    }
    final delta = weight - _credited;
    _credited = weight;
    if (leaving) {
      closed = true;
      _activeSince = null;
    }
    return delta;
  }

  double feedback(ShortVideoFeedback kind, {bool enabled = true}) {
    if (enabled) return _feedback.add(kind) ? kind.weight : 0;
    return _feedback.remove(kind) ? -kind.weight : 0;
  }
}
