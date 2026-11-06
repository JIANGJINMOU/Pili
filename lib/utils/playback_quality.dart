import 'package:PiliPlus/utils/connectivity_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// Shared full-screen quality preference for ordinary and portrait playback.
abstract final class PlaybackQuality {
  static int forNetwork(bool isWiFi) =>
      isWiFi ? Pref.defaultVideoQa : Pref.defaultVideoQaCellular;

  static Future<int> get preferred async => PlatformUtils.isMobile
      ? forNetwork(await ConnectivityUtils.isWiFi)
      : Pref.defaultVideoQa;

  static Future<void> save(int quality) async {
    final key = !PlatformUtils.isMobile || await ConnectivityUtils.isWiFi
        ? SettingBoxKey.defaultVideoQa
        : SettingBoxKey.defaultVideoQaCellular;
    await GStorage.setting.put(key, quality);
  }
}
