import 'package:PiliPlus/pages/short_video/preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class ShortVideoEntry extends StatelessWidget {
  const ShortVideoEntry({super.key, this.onOpen, this.playerStyle = false});
  final VoidCallback? onOpen;
  final bool playerStyle;

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: GStorage.setting.watch(key: SettingBoxKey.shortVideoEnabled),
    builder: (context, _) => ShortVideoPreferences.read().enabled
        ? Padding(
            padding: EdgeInsets.only(left: playerStyle ? 0 : 4),
            child: IconButton(
              tooltip: '竖屏视频',
              onPressed: onOpen ?? () => Get.toNamed('/shortVideo'),
              color: playerStyle ? Colors.white : null,
              iconSize: playerStyle ? 20 : null,
              padding: playerStyle ? EdgeInsets.zero : const EdgeInsets.all(8),
              icon: Icon(
                playerStyle
                    ? Icons.stay_current_portrait_rounded
                    : Icons.smart_display_rounded,
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
}
