import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// Scrubbing is local UI state. Native seeks are serialized, only on release.
class ShortVideoProgressBar extends StatefulWidget {
  const ShortVideoProgressBar({
    super.key,
    required this.positionListenable,
    required this.duration,
    required this.onSeek,
    required this.haptics,
    this.onDraggingChanged,
  });
  final ValueListenable<Duration> positionListenable;
  final Duration duration;
  final Future<void> Function(double) onSeek;
  final bool haptics;
  final ValueChanged<bool>? onDraggingChanged;
  @override
  State<ShortVideoProgressBar> createState() => _ShortVideoProgressBarState();
}

class _ShortVideoProgressBarState extends State<ShortVideoProgressBar> {
  double? _preview, _queued;
  bool _dragging = false, _seeking = false;
  Timer? _settleTimer;
  @override
  void initState() {
    super.initState();
    widget.positionListenable.addListener(_positionChanged);
  }

  @override
  void didUpdateWidget(covariant ShortVideoProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionListenable != widget.positionListenable) {
      oldWidget.positionListenable.removeListener(_positionChanged);
      widget.positionListenable.addListener(_positionChanged);
    }
  }

  void _positionChanged() {
    if (_preview == null || _dragging || _seeking) return;
    final target = widget.duration.inMilliseconds * _preview!;
    if ((widget.positionListenable.value.inMilliseconds - target).abs() <=
        1000) {
      _settleTimer?.cancel();
      if (mounted) setState(() => _preview = null);
    }
  }

  void _update(double x, double width) {
    if (widget.duration <= Duration.zero || width <= 0) return;
    _settleTimer?.cancel();
    setState(() => _preview = (x / width).clamp(0.0, 1.0));
  }

  void _start(double x, double width) {
    if (widget.duration <= Duration.zero) return;
    _update(x, width);
    if (!_dragging) {
      _dragging = true;
      widget.onDraggingChanged?.call(true);
      if (widget.haptics) HapticFeedback.selectionClick();
    }
  }

  void _endDrag() {
    if (_dragging) {
      _dragging = false;
      widget.onDraggingChanged?.call(false);
    }
  }

  void _cancel() {
    _endDrag();
    if (mounted) setState(() => _preview = null);
  }

  Future<void> _commit() async {
    _endDrag();
    if (_preview == null) return;
    _queued = _preview;
    if (_seeking) return;
    _seeking = true;
    try {
      while (_queued != null && mounted) {
        final target = _queued!;
        _queued = null;
        await widget.onSeek(target).timeout(const Duration(seconds: 8));
      }
    } catch (_) {
      _queued = null;
      if (mounted) {
        setState(() => _preview = null);
        SmartDialog.showToast('进度跳转失败，请重试');
      }
    } finally {
      _seeking = false;
      if (mounted && !_dragging) {
        _positionChanged();
        if (_preview != null) {
          // Do not snap back to a stale native timestamp on release.
          _settleTimer = Timer(const Duration(seconds: 2), () {
            if (mounted && !_dragging) setState(() => _preview = null);
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    widget.positionListenable.removeListener(_positionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Duration>(
    valueListenable: widget.positionListenable,
    builder: (context, position, _) {
      final progress =
          _preview ??
          (widget.duration.inMilliseconds <= 0
              ? 0.0
              : (position.inMilliseconds / widget.duration.inMilliseconds)
                    .clamp(0.0, 1.0));
      final shown = _preview == null
          ? position
          : Duration(
              milliseconds: (progress * widget.duration.inMilliseconds).round(),
            );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            SizedBox(
              width: widget.duration.inHours > 0 ? 48 : 34,
              child: Text(
                _format(shown),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Listener(
                  onPointerCancel: (_) => _cancel(),
                  child: GestureDetector(
                    key: const ValueKey('short-video-seek-track'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragDown: (d) =>
                        _update(d.localPosition.dx, constraints.maxWidth),
                    onHorizontalDragStart: (d) =>
                        _start(d.localPosition.dx, constraints.maxWidth),
                    onHorizontalDragUpdate: (d) =>
                        _update(d.localPosition.dx, constraints.maxWidth),
                    onHorizontalDragEnd: (_) => _commit(),
                    onHorizontalDragCancel: _cancel,
                    onTapUp: (d) {
                      _update(d.localPosition.dx, constraints.maxWidth);
                      _commit();
                    },
                    child: SizedBox(
                      height: 36,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: _dragging ? 5 : 3,
                            color: const Color(0xFFFF6699),
                            backgroundColor: Colors.white30,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          Align(
                            alignment: Alignment(progress * 2 - 1, 0),
                            child: Container(
                              width: _dragging ? 12 : 7,
                              height: _dragging ? 12 : 7,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _format(widget.duration),
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      );
    },
  );
}

String _format(Duration value) {
  final seconds = value.inSeconds.clamp(0, 359999);
  final mm = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final ss = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${(seconds ~/ 3600).toString().padLeft(2, '0')}:$mm:$ss'
      : '$mm:$ss';
}
