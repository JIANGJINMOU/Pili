import 'package:PiliPlus/utils/storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class ShortVideoStyleSlider extends StatefulWidget {
  const ShortVideoStyleSlider({
    super.key,
    required this.label,
    required this.storageKey,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
  });
  final String label, storageKey, suffix;
  final double value, min, max;
  final int divisions;
  @override
  State<ShortVideoStyleSlider> createState() => _ShortVideoStyleSliderState();
}

class _ShortVideoStyleSliderState extends State<ShortVideoStyleSlider> {
  double? _dragValue;
  @override
  Widget build(BuildContext context) {
    final value = _dragValue ?? widget.value;
    final text = widget.suffix == '%'
        ? '${(value * 100).round()}%'
        : '${value.round()}px';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(widget.label)),
              Text(text),
            ],
          ),
          Slider(
            value: value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            label: text,
            onChanged: (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) async {
              try {
                await GStorage.setting.put(widget.storageKey, v);
              } catch (_) {
                SmartDialog.showToast('显示设置保存失败，请重试');
              } finally {
                if (mounted) setState(() => _dragValue = null);
              }
            },
          ),
        ],
      ),
    );
  }
}
