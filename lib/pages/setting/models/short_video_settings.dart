import 'package:PiliPlus/pages/short_video/display_preferences.dart';
import 'package:PiliPlus/pages/short_video/controller.dart';
import 'package:PiliPlus/pages/setting/widgets/short_video_subtitle_setting.dart';
import 'package:PiliPlus/pages/setting/widgets/short_video_danmaku_setting.dart';
import 'package:PiliPlus/pages/short_video/recommendation/recommendation_storage.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/fixed_speed_setting.dart';
import 'package:PiliPlus/pages/short_video/preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:material_ui/material_ui.dart';

List<SettingsModel> get shortVideoSettings => [
  const WidgetModel(child: ShortVideoSettingSection('基础播放')),
  const SwitchModel(
    title: '启用竖屏视频',
    subtitle: '立即生效；关闭后隐藏竖屏入口，停止竖屏播放，可在此重新开启',
    leading: Icon(Icons.smart_display_outlined),
    setKey: SettingBoxKey.shortVideoEnabled,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '竖屏自动播放',
    subtitle: '进入或切换视频后，画面停稳再播放；关闭后轻点画面播放',
    leading: Icon(Icons.play_circle_outline),
    setKey: SettingBoxKey.shortVideoAutoPlay,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '播完自动下一条',
    subtitle: '开启时自动连播；关闭时循环当前视频；评论或设置打开时不切换',
    leading: Icon(Icons.skip_next_outlined),
    setKey: SettingBoxKey.shortVideoAutoNext,
  ),
  const SwitchModel(
    title: '竖屏默认静音',
    subtitle: '每次进入竖屏时静音；播放页仍可临时切换声音',
    leading: Icon(Icons.volume_off_outlined),
    setKey: SettingBoxKey.shortVideoMuted,
  ),
  const WidgetModel(
    searchTitle: '竖屏固定倍速',
    searchSubtitle: '固定倍率 长按加速 播放速度',
    child: FixedSpeedSetting(portrait: true, switchOnly: true),
  ),
  const WidgetModel(child: ShortVideoSettingSection('画面与手势')),
  const SwitchModel(
    title: '清屏播放',
    subtitle: '默认隐藏竖屏控件；双击画面临时显示或隐藏，字幕和弹幕不受影响',
    leading: Icon(Icons.hide_source_outlined),
    setKey: SettingBoxKey.shortVideoCleanScreen,
  ),
  const SwitchModel(
    title: '显示系统顶部状态栏',
    subtitle: '竖屏播放时显示时间、电量和通知图标；关闭保持沉浸播放',
    leading: Icon(Icons.space_dashboard_outlined),
    setKey: SettingBoxKey.shortVideoShowStatusBar,
  ),
  PopupModel<ShortVideoAspect>(
    title: '画面比例',
    leading: const Icon(Icons.aspect_ratio),
    value: () => ShortVideoPreferences.read().aspect,
    items: ShortVideoAspect.values,
    onSelected: (value, refresh) async {
      try {
        await GStorage.setting.put(SettingBoxKey.shortVideoAspect, value.name);
        refresh();
      } catch (_) {
        SmartDialog.showToast('画面比例保存失败，请重试');
      }
    },
  ),
  PopupModel<ShortVideoFit>(
    title: '画面适配',
    leading: const Icon(Icons.fit_screen_outlined),
    value: () => ShortVideoPreferences.read().fit,
    items: ShortVideoFit.values,
    onSelected: (value, refresh) async {
      try {
        await GStorage.setting.put(SettingBoxKey.shortVideoFit, value.name);
        refresh();
      } catch (_) {
        SmartDialog.showToast('画面适配保存失败，请重试');
      }
    },
  ),
  const WidgetModel(
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text('默认原始比例、完整显示；固定比例会改变画面宽高，铺满裁切会隐藏边缘，拉伸铺满可能变形。'),
    ),
  ),
  PopupModel<ShortVideoSwipeStyle>(
    title: '竖屏滑动风格',
    leading: const Icon(Icons.swipe_vertical_outlined),
    value: () => ShortVideoPreferences.read().swipeStyle,
    items: ShortVideoSwipeStyle.values,
    onSelected: (value, setState) {
      GStorage.setting.put(SettingBoxKey.shortVideoSwipeStyle, value.name);
      setState();
    },
  ),
  const SwitchModel(
    title: '竖屏手势震动',
    subtitle: '切换停稳及播放操作时给予轻微反馈',
    leading: Icon(Icons.vibration_outlined),
    setKey: SettingBoxKey.shortVideoHaptics,
    defaultVal: true,
  ),
  const WidgetModel(child: ShortVideoSettingSection('字幕设置')),
  const SwitchModel(
    title: '竖屏字幕',
    subtitle: '与播放页字幕开关联动；无可用字幕时会提示',
    leading: Icon(Icons.closed_caption_outlined),
    setKey: SettingBoxKey.shortVideoSubtitles,
  ),
  const WidgetModel(
    searchTitle: '竖屏字幕样式',
    searchSubtitle: '语言 位置 字号 颜色 背景 加粗 阴影 对齐 行数',
    child: ShortVideoSubtitleSetting(),
  ),
  const WidgetModel(child: ShortVideoSettingSection('弹幕设置')),
  const SwitchModel(
    title: '竖屏弹幕',
    subtitle: '与竖屏底栏开关联动，仅当前视频加载弹幕',
    leading: Icon(Icons.subtitles_outlined),
    setKey: SettingBoxKey.shortVideoDanmaku,
  ),
  const WidgetModel(
    searchTitle: '竖屏弹幕样式',
    searchSubtitle: '字号 不透明度 显示区域',
    child: ExpansionTile(
      leading: Icon(Icons.format_size),
      title: Text('弹幕样式'),
      subtitle: Text('字号、不透明度和显示区域'),
      children: [ShortVideoDanmakuSetting()],
    ),
  ),
  const WidgetModel(child: ShortVideoSettingSection('网络与推荐')),
  const SwitchModel(
    title: '预加载下一条视频',
    subtitle: '停稳 400ms 后仅预加载下一条；默认仅 Wi-Fi 或有线网络',
    leading: Icon(Icons.downloading_outlined),
    setKey: SettingBoxKey.shortVideoPreload,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '本地个性化推荐',
    subtitle: '根据有效观看与互动调整排序；画像仅保存在本机，关闭后停止学习兴趣',
    leading: Icon(Icons.auto_awesome_outlined),
    setKey: SettingBoxKey.shortVideoPersonalized,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '仅竖向视频',
    subtitle: '只推荐元数据已标明竖向的视频；可能减少可用内容',
    leading: Icon(Icons.stay_current_portrait_outlined),
    setKey: SettingBoxKey.shortVideoOnlyVertical,
  ),
  const SwitchModel(
    title: '允许移动网络预加载',
    subtitle: '额外消耗流量；关闭时仍可正常播放当前视频',
    leading: Icon(Icons.network_cell_outlined),
    setKey: SettingBoxKey.shortVideoCellularPreload,
  ),
  NormalModel(
    title: '清除本地推荐记录',
    subtitle: '删除兴趣权重、已看记录和不感兴趣记录，不影响账号历史',
    leading: const Icon(Icons.delete_outline),
    onTap: (context, setState) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('清除本地推荐记录？'),
          content: const Text('仅清除本机竖屏推荐画像，后续推荐会重新学习。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        if (Get.isRegistered<ShortVideoController>()) {
          await Get.find<ShortVideoController>().clearProfile();
        } else {
          await RecommendationStorage().clear();
        }
        SmartDialog.showToast('本地推荐记录已清除');
      } catch (_) {
        SmartDialog.showToast('清除失败，请重试');
      }
    },
  ),
];

class ShortVideoSettingSection extends StatelessWidget {
  const ShortVideoSettingSection(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
