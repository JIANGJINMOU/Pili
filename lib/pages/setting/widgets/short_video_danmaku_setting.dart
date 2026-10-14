import 'package:PiliPlus/pages/short_video/preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:material_ui/material_ui.dart';
import 'package:PiliPlus/pages/setting/widgets/short_video_style_slider.dart';

class ShortVideoDanmakuSetting extends StatelessWidget {
  const ShortVideoDanmakuSetting({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: GStorage.setting.watch(),
    builder: (context, _) {
      final p = ShortVideoPreferences.read();
      return Column(
        children: [
          ShortVideoStyleSlider(
            label: '弹幕字号',
            storageKey: SettingBoxKey.shortVideoDanmakuFont,
            value: p.danmakuFont,
            min: 12,
            max: 30,
            divisions: 18,
            suffix: 'px',
          ),
          ShortVideoStyleSlider(
            label: '弹幕不透明度',
            storageKey: SettingBoxKey.shortVideoDanmakuOpacity,
            value: p.danmakuOpacity,
            min: .2,
            max: 1,
            divisions: 16,
            suffix: '%',
          ),
          ShortVideoStyleSlider(
            label: '弹幕显示区域',
            storageKey: SettingBoxKey.shortVideoDanmakuArea,
            value: p.danmakuArea,
            min: .2,
            max: 1,
            divisions: 16,
            suffix: '%',
          ),
        ],
      );
    },
  );
}
