import 'package:PiliPlus/pages/short_video/controller.dart';
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
  const WidgetModel(child: _ShortVideoSection('基础播放')),
  const SwitchModel(
    title: '启用竖屏视频',
    subtitle: '立即生效；关闭后隐藏首页入口，停止竖屏播放，可在此重新开启',
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
  const WidgetModel(child: _ShortVideoSection('缓冲与显示')),
  const SwitchModel(
    title: '预加载下一条视频',
    subtitle: '停稳 400ms 后仅预加载下一条；默认仅 Wi-Fi 或有线网络',
    leading: Icon(Icons.downloading_outlined),
    setKey: SettingBoxKey.shortVideoPreload,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '竖屏默认静音',
    subtitle: '每次进入竖屏时静音；播放页仍可临时切换声音',
    leading: Icon(Icons.volume_off_outlined),
    setKey: SettingBoxKey.shortVideoMuted,
  ),
  const SwitchModel(
    title: '竖向视频铺满屏幕',
    subtitle: '开启可能裁切边缘；关闭显示完整画面，横向视频始终完整显示',
    leading: Icon(Icons.fit_screen_outlined),
    setKey: SettingBoxKey.shortVideoFill,
    defaultVal: true,
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
  const WidgetModel(child: _ShortVideoSection('播放速度')),
  const WidgetModel(
    searchTitle: '竖屏固定倍速',
    searchSubtitle: '固定倍率 长按加速 播放速度',
    child: FixedSpeedSetting(portrait: true),
  ),
  const WidgetModel(child: _ShortVideoSection('推荐与隐私')),
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

class _ShortVideoSection extends StatelessWidget {
  const _ShortVideoSection(this.title);
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
