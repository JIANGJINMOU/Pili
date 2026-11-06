import 'package:PiliPlus/services/logger.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// A departing player must not release another player's screen lock.
abstract final class PlaybackWakelock {
  static final _owners = <Object>{};

  static Future<void> set(Object owner, bool active) {
    final before = _owners.isNotEmpty;
    active ? _owners.add(owner) : _owners.remove(owner);
    final enabled = _owners.isNotEmpty;
    if (before == enabled) return Future.value();
    return WakelockPlus.toggle(enable: enabled)
        .catchError((Object error, StackTrace stack) {
          logger.w('playback screen lock', error: error, stackTrace: stack);
        });
  }
}
