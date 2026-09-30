import 'package:PiliPlus/pages/short_video/preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class ShortVideoEntry extends StatelessWidget {
  const ShortVideoEntry({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: GStorage.setting.watch(key: SettingBoxKey.shortVideoEnabled),
    builder: (context, _) => ShortVideoPreferences.read().enabled
        ? Padding(
            padding: const EdgeInsets.only(left: 4),
            child: IconButton(
              tooltip: '竖屏视频',
              onPressed: () => Get.toNamed('/shortVideo'),
              icon: const Icon(Icons.smart_display_rounded),
            ),
          )
        : const SizedBox.shrink(),
  );
}
