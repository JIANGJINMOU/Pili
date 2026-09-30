import 'package:PiliPlus/utils/fixed_playback_speed.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// Both players share the original compact speed-list presentation.
List<PopupMenuEntry<double>> playbackSpeedMenuItems({
  required double currentRate,
  required List<double> rates,
  required ValueChanged<double> onSelected,
  bool portrait = false,
  bool showFixedSwitch = true,
}) => [
  if (showFixedSwitch)
    PopupMenuItem<double>(
      enabled: false,
      padding: EdgeInsets.zero,
      height: 48,
      child: FixedSpeedSetting(
        portrait: portrait,
        switchOnly: true,
        compact: true,
        currentRate: () => currentRate,
      ),
    ),
  for (final rate in ({...rates, currentRate}.toList()..sort()))
    PopupMenuItem<double>(
      value: rate,
      height: 35,
      padding: const EdgeInsets.only(left: 30, right: 16),
      onTap: () => onSelected(rate),
      child: Text(
        '${rate}X',
        style: const TextStyle(color: Colors.white, fontSize: 13),
        semanticsLabel: '$rate倍速',
      ),
    ),
];

class FixedSpeedSetting extends StatelessWidget {
  const FixedSpeedSetting({
    super.key,
    this.portrait = false,
    this.switchOnly = false,
    this.compact = false,
    this.currentRate,
  });
  final bool portrait;
  final bool switchOnly;
  final bool compact;
  final double Function()? currentRate;

  Future<void> _save(String key, Object value) =>
      GStorage.setting.put(key, value);

  Future<void> _toggle(bool enabled) async {
    await GStorage.setting.putAll({
      FixedPlaybackSpeed.enabledKey: enabled,
      if (enabled && currentRate != null)
        FixedPlaybackSpeed.rateKey: currentRate!(),
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: GStorage.setting.watch(),
    builder: (context, _) {
      final speed = FixedPlaybackSpeed.read();
      final title = portrait ? '竖屏固定倍速' : '固定倍速';
      if (compact) {
        return Row(
          children: [
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                portrait ? '固定倍速' : title,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            Switch(value: speed.enabled, onChanged: _toggle),
            const SizedBox(width: 8),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            title: Text(title),
            subtitle: Text(
              portrait ? '开启后记住所选倍率；关闭后仅当前视频临时调速' : '开启后记住所选倍率',
            ),
            value: speed.enabled,
            controlAffinity: ListTileControlAffinity.trailing,
            onChanged: _toggle,
          ),
          if (!switchOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: PlaybackSpeedGrid(
                rates: Pref.speedList,
                selected: speed.rate,
                onSelected: (rate) => _save(FixedPlaybackSpeed.rateKey, rate),
              ),
            ),
        ],
      );
    },
  );
}

/// Exactly two rows; extra custom speeds scroll horizontally instead of
/// squeezing labels or making the settings page arbitrarily tall.
class PlaybackSpeedGrid extends StatelessWidget {
  const PlaybackSpeedGrid({
    super.key,
    required this.rates,
    required this.selected,
    required this.onSelected,
  });
  final List<double> rates;
  final double selected;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    final values = ({...rates, selected}.toList()..sort());
    final columns = (values.length / 2).ceil();
    final colors = Theme.of(context).colorScheme;
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      3.0,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < columns * 68.0 * scale
            ? columns * 68.0 * scale
            : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: GridView.builder(
              key: const ValueKey('fixed-speed-grid'),
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: 44 * scale,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: values.length,
              itemBuilder: (context, index) {
                final rate = values[index];
                final active = rate == selected;
                return Semantics(
                  selected: active,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      backgroundColor: active
                          ? colors.primary
                          : colors.surfaceContainerHighest,
                      foregroundColor: active
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => onSelected(rate),
                    child: Text('${rate}X', maxLines: 1),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
