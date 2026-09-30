import 'dart:async';

/// One cancellable delayed decision, shared by settings, panels and lifecycle.
class ShortVideoPreloadScheduler {
  ShortVideoPreloadScheduler(this.onReady, {required this.networkAllowed});
  final void Function(int index) onReady;
  final Future<bool> Function() networkAllowed;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void schedule(int index) {
    cancel();
    final generation = _generation;
    _timer = Timer(const Duration(milliseconds: 400), () async {
      _timer = null;
      try {
        final allowed = await networkAllowed();
        if (!_disposed && generation == _generation && allowed) onReady(index);
      } catch (_) {
        /* Unknown network: conservative, do not preload. */
      }
    });
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
