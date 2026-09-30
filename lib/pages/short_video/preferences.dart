import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/fixed_playback_speed.dart';

enum ShortVideoSwipeStyle with EnumWithLabel {
  smooth('柔和沉浸 · 渐缓停靠'),
  quick('利落跟手 · 轻甩快切'),
  simple('简洁滑动 · 标准翻页');

  const ShortVideoSwipeStyle(this.label);
  @override
  final String label;
}

/// One snapshot per settings change, not a storage read for every animation frame.
class ShortVideoPreferences {
  const ShortVideoPreferences({
    this.enabled = true,
    this.autoPlay = true,
    this.autoNext = false,
    this.preload = true,
    this.personalized = true,
    this.onlyVertical = false,
    this.cellularPreload = false,
    this.muted = false,
    this.fill = true,
    this.haptics = true,
    this.swipeStyle = ShortVideoSwipeStyle.smooth,
    this.fixedSpeed = const FixedPlaybackSpeed(),
  });

  factory ShortVideoPreferences.read() => ShortVideoPreferences.fromMap(
    GStorage.setting.toMap(),
  );

  factory ShortVideoPreferences.fromMap(Map<dynamic, dynamic> values) {
    bool flag(String key, bool fallback) =>
        values[key] is bool ? values[key] as bool : fallback;
    final style = values[SettingBoxKey.shortVideoSwipeStyle];
    return ShortVideoPreferences(
      enabled: flag(SettingBoxKey.shortVideoEnabled, true),
      autoPlay: flag(SettingBoxKey.shortVideoAutoPlay, true),
      autoNext: flag(SettingBoxKey.shortVideoAutoNext, false),
      preload: flag(SettingBoxKey.shortVideoPreload, true),
      personalized: flag(SettingBoxKey.shortVideoPersonalized, true),
      onlyVertical: flag(SettingBoxKey.shortVideoOnlyVertical, false),
      cellularPreload: flag(SettingBoxKey.shortVideoCellularPreload, false),
      muted: flag(SettingBoxKey.shortVideoMuted, false),
      fill: flag(SettingBoxKey.shortVideoFill, true),
      haptics: flag(SettingBoxKey.shortVideoHaptics, true),
      fixedSpeed: FixedPlaybackSpeed.fromMap(values),
      swipeStyle: ShortVideoSwipeStyle.values.firstWhere(
        (value) => value.name == style,
        orElse: () => ShortVideoSwipeStyle.smooth,
      ),
    );
  }

  final bool enabled;
  final bool autoPlay;
  final bool autoNext;
  final bool preload;
  final bool personalized;
  final bool onlyVertical;
  final bool cellularPreload;
  final bool muted;
  final bool fill;
  final bool haptics;
  final ShortVideoSwipeStyle swipeStyle;
  final FixedPlaybackSpeed fixedSpeed;
  double get playbackRate => fixedSpeed.effectiveRate();
}
