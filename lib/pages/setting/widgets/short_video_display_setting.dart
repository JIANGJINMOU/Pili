import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/short_video/display_preferences.dart';
import 'package:PiliPlus/pages/short_video/preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class ShortVideoDisplaySetting extends StatelessWidget {
  const ShortVideoDisplaySetting({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: GStorage.setting.watch(),
    builder: (context, _) {
      final p = ShortVideoPreferences.read();
      final ratio = PopupModel<ShortVideoAspect>(
        title: '画面比例',
        leading: const Icon(Icons.aspect_ratio),
        value: () => p.aspect,
        items: ShortVideoAspect.values,
        onSelected: (v, refresh) async {
          try {
            await GStorage.setting.put(SettingBoxKey.shortVideoAspect, v.name);
            refresh();
          } catch (_) {
            SmartDialog.showToast('画面比例保存失败，请重试');
          }
        },
      ).widget;
      final fit = PopupModel<ShortVideoFit>(
        title: '画面适配',
        leading: const Icon(Icons.fit_screen_outlined),
        value: () => p.fit,
        items: ShortVideoFit.values,
        onSelected: (v, refresh) async {
          try {
            await GStorage.setting.put(SettingBoxKey.shortVideoFit, v.name);
            refresh();
          } catch (_) {
            SmartDialog.showToast('画面适配保存失败，请重试');
          }
        },
      ).widget;
      return LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 560
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ratio),
                  Expanded(child: fit),
                ],
              )
            : Column(children: [ratio, fit]),
      );
    },
  );
}

class ShortVideoOrientationSetting extends StatelessWidget {
  const ShortVideoOrientationSetting({super.key});
  Future<void> _set(int orientation) async {
    try {
      await GStorage.setting.putAll({
        SettingBoxKey.shortVideoOnlyHorizontal: orientation == 1,
        SettingBoxKey.shortVideoOnlyVertical: orientation == 2,
      });
    } catch (_) {
      SmartDialog.showToast('视频方向保存失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: GStorage.setting.watch(),
    builder: (context, _) {
      final p = ShortVideoPreferences.read();
      final selected = p.onlyHorizontal
          ? 1
          : p.onlyVertical
          ? 2
          : 0;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('推荐视频方向', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (index, label, icon) in const [
                  (0, '全部', Icons.apps_rounded),
                  (1, '仅横屏', Icons.stay_current_landscape_outlined),
                  (2, '仅竖屏', Icons.stay_current_portrait_outlined),
                ])
                  ChoiceChip(
                    avatar: Icon(icon, size: 18),
                    label: Text(label),
                    selected: selected == index,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    visualDensity: VisualDensity.standard,
                    onSelected: (_) => _set(index),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '仅筛选推荐流；不影响搜索、UP投稿和主动选择的视频。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    },
  );
}
