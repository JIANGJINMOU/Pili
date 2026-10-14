import 'package:PiliPlus/pages/short_video/display_preferences.dart';
import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/pages/short_video/subtitle_preferences.dart';
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
    this.aspect = ShortVideoAspect.original,
    this.fit = ShortVideoFit.contain,
    this.showStatusBar = false,
    this.cleanScreen = false,
    this.subtitlesEnabled = false,
    this.danmakuEnabled = false,
    this.danmakuFont = 18,
    this.danmakuOpacity = .85,
    this.danmakuArea = .45,
    this.enabled = true,
    this.autoPlay = true,
    this.autoNext = false,
    this.preload = true,
    this.personalized = true,
    this.onlyVertical = false,
    this.cellularPreload = false,
    this.muted = false,
    this.subtitles = const ShortVideoSubtitlePreferences(),
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
    double number(String key, double fallback, double min, double max) {
      final value = values[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    final style = values[SettingBoxKey.shortVideoSwipeStyle];
    return ShortVideoPreferences(
      aspect:
          ShortVideoAspect.values
              .where((v) => v.name == values[SettingBoxKey.shortVideoAspect])
              .firstOrNull ??
          ShortVideoAspect.original,
      fit:
          ShortVideoFit.values
              .where((v) => v.name == values[SettingBoxKey.shortVideoFit])
              .firstOrNull ??
          ShortVideoFit.contain,
      showStatusBar: flag(SettingBoxKey.shortVideoShowStatusBar, false),
      cleanScreen: flag(SettingBoxKey.shortVideoCleanScreen, false),
      subtitlesEnabled: flag(SettingBoxKey.shortVideoSubtitles, false),
      danmakuEnabled: flag(SettingBoxKey.shortVideoDanmaku, false),
      danmakuFont: number(SettingBoxKey.shortVideoDanmakuFont, 18, 12, 30),
      danmakuOpacity: number(
        SettingBoxKey.shortVideoDanmakuOpacity,
        .85,
        .2,
        1,
      ),
      danmakuArea: number(SettingBoxKey.shortVideoDanmakuArea, .45, .2, 1),
      enabled: flag(SettingBoxKey.shortVideoEnabled, true),
      autoPlay: flag(SettingBoxKey.shortVideoAutoPlay, true),
      autoNext: flag(SettingBoxKey.shortVideoAutoNext, false),
      preload: flag(SettingBoxKey.shortVideoPreload, true),
      personalized: flag(SettingBoxKey.shortVideoPersonalized, true),
      onlyVertical: flag(SettingBoxKey.shortVideoOnlyVertical, false),
      cellularPreload: flag(SettingBoxKey.shortVideoCellularPreload, false),
      muted: flag(SettingBoxKey.shortVideoMuted, false),
      subtitles: ShortVideoSubtitlePreferences.fromMap(values),
      haptics: flag(SettingBoxKey.shortVideoHaptics, true),
      fixedSpeed: FixedPlaybackSpeed.fromMap(values),
      swipeStyle: ShortVideoSwipeStyle.values.firstWhere(
        (value) => value.name == style,
        orElse: () => ShortVideoSwipeStyle.smooth,
      ),
    );
  }

  final ShortVideoAspect aspect;
  final ShortVideoFit fit;
  final bool showStatusBar;
  final bool cleanScreen, subtitlesEnabled;
  final bool danmakuEnabled;
  final double danmakuFont, danmakuOpacity, danmakuArea;
  final bool enabled;
  final bool autoPlay;
  final bool autoNext;
  final bool preload;
  final bool personalized;
  final bool onlyVertical;
  final bool cellularPreload;
  final bool muted;
  final ShortVideoSubtitlePreferences subtitles;
  final bool haptics;
  final ShortVideoSwipeStyle swipeStyle;
  final FixedPlaybackSpeed fixedSpeed;
  double get playbackRate => fixedSpeed.effectiveRate();
}
