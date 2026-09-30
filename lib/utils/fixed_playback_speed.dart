import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';

/// Persisted fixed-speed preference for the portrait short-video player.
class FixedPlaybackSpeed {
  const FixedPlaybackSpeed({this.enabled = false, this.rate = 1.5});

  final bool enabled;
  final double rate;

  static const enabledKey = SettingBoxKey.shortVideoFixedSpeedEnabled;
  static const rateKey = SettingBoxKey.shortVideoFixedSpeed;

  factory FixedPlaybackSpeed.read() =>
      FixedPlaybackSpeed.fromMap(GStorage.setting.toMap());

  factory FixedPlaybackSpeed.fromMap(Map<dynamic, dynamic> values) {
    final stored = values[rateKey];
    return FixedPlaybackSpeed(
      enabled: values[enabledKey] == true,
      rate: stored is num && stored.isFinite && stored >= 0.25 && stored <= 5
          ? stored.toDouble()
          : 1.5,
    );
  }

  double effectiveRate([double fallback = 1]) => enabled ? rate : fallback;
  static String label(double value) =>
      '${value.toString().replaceFirst(RegExp(r'\.0$'), '')}×';
}
