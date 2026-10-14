import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/short_video_style_slider.dart';
import 'package:PiliPlus/pages/short_video/preferences.dart';
import 'package:PiliPlus/pages/short_video/subtitle_preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class ShortVideoSubtitleSetting extends StatelessWidget {
  const ShortVideoSubtitleSetting({super.key});

  Widget _choice<T extends EnumWithLabel>(
    String title,
    IconData icon,
    String key,
    T value,
    List<T> items,
  ) => PopupModel<T>(
    title: title,
    leading: Icon(icon),
    value: () => value,
    items: items,
    onSelected: (v, refresh) async {
      try {
        await GStorage.setting.put(key, (v as Enum).name);
      } catch (_) {
        SmartDialog.showToast('字幕设置保存失败，请重试');
      }
    },
  ).widget;

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: GStorage.setting.watch(),
    builder: (context, _) {
      final p = ShortVideoPreferences.read().subtitles;
      return Column(
        children: [
          _choice(
            '优先字幕语言',
            Icons.language,
            SettingBoxKey.shortVideoSubtitleLanguage,
            p.language,
            ShortVideoSubtitleLanguage.values,
          ),
          _choice(
            '字幕位置',
            Icons.vertical_align_center,
            SettingBoxKey.shortVideoSubtitlePosition,
            p.position,
            ShortVideoSubtitlePosition.values,
          ),
          ExpansionTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('字幕样式'),
            subtitle: Text(
              '${p.fontSize.round()}px · ${p.color.label} · ${p.lines.label}',
            ),
            children: [
              Container(
                key: const ValueKey('subtitle-style-preview'),
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF30343D),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: p.backgroundOpacity),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '字幕效果预览\nSubtitle preview',
                      style: p.textStyle,
                      textAlign: p.align.align,
                      maxLines: p.lines.count,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              ShortVideoStyleSlider(
                label: '字幕字号',
                storageKey: SettingBoxKey.shortVideoSubtitleFont,
                value: p.fontSize,
                min: 12,
                max: 28,
                divisions: 16,
                suffix: 'px',
              ),
              ShortVideoStyleSlider(
                label: '字幕背景',
                storageKey: SettingBoxKey.shortVideoSubtitleBackground,
                value: p.backgroundOpacity,
                min: 0,
                max: .9,
                divisions: 18,
                suffix: '%',
              ),
              _choice(
                '字幕颜色',
                Icons.palette_outlined,
                SettingBoxKey.shortVideoSubtitleColor,
                p.color,
                ShortVideoSubtitleColor.values,
              ),
              _choice(
                '字幕对齐',
                Icons.format_align_center,
                SettingBoxKey.shortVideoSubtitleAlign,
                p.align,
                ShortVideoSubtitleAlign.values,
              ),
              _choice(
                '字幕最大行数',
                Icons.notes,
                SettingBoxKey.shortVideoSubtitleLines,
                p.lines,
                ShortVideoSubtitleLines.values,
              ),
              const SwitchModel(
                title: '字幕加粗',
                leading: Icon(Icons.format_bold),
                setKey: SettingBoxKey.shortVideoSubtitleBold,
              ).widget,
              const SwitchModel(
                title: '字幕阴影',
                subtitle: '增强亮色画面上的可读性',
                leading: Icon(Icons.tonality),
                setKey: SettingBoxKey.shortVideoSubtitleShadow,
                defaultVal: true,
              ).widget,
            ],
          ),
        ],
      );
    },
  );
}
