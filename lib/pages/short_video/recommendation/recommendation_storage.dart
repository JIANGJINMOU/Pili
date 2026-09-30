import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/pages/short_video/recommendation/user_profile.dart';

/// One write queue across page/controller instances, including settings-only
/// clears after leaving playback. Snapshot before enqueueing mutable profiles.
class RecommendationStorage {
  static const key = 'shortVideoRecommendationProfileV1';
  static Future<void> _pending = Future.value();

  ShortVideoProfile read() =>
      ShortVideoProfile.fromMap(GStorage.localCache.get(key));

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> save(ShortVideoProfile profile) {
    final snapshot = profile.toMap();
    return _enqueue(() => GStorage.localCache.put(key, snapshot));
  }

  Future<void> clear() => _enqueue(() => GStorage.localCache.delete(key));
}
