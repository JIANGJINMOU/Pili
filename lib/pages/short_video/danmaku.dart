import 'dart:async';

import 'package:PiliPlus/grpc/dm.dart';
import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Only the visible video loads comments, one six-minute segment at a time.
class ShortVideoDanmaku extends StatefulWidget {
  const ShortVideoDanmaku({
    super.key,
    required this.cid,
    required this.position,
    required this.playing,
    required this.rate,
    this.fontSize = 18,
    this.opacity = .85,
    this.area = .45,
    this.loader = DmGrpc.dmSegMobile,
  });
  final double fontSize, opacity, area;
  final int cid;
  final ValueListenable<Duration> position;
  final bool playing;
  final double rate;
  final Future<LoadingState<DmSegMobileReply>> Function({
    required int cid,
    required int segmentIndex,
    int type,
  })
  loader;
  @override
  State<ShortVideoDanmaku> createState() => _ShortVideoDanmakuState();
}

class _ShortVideoDanmakuState extends State<ShortVideoDanmaku> {
  DanmakuController<void>? _canvas;
  final _segments = <int, List<DanmakuElem>>{};
  final _pending = <int>{};
  final _failed = <int>{};
  int _last = -1;
  DanmakuOption get _option => DanmakuOption(
    fontSize: widget.fontSize,
    area: widget.area,
    duration: 8 / widget.rate,
    staticDuration: 4 / widget.rate,
    hideSpecial: true,
    massiveMode: false,
  );

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_tick);
  }

  @override
  void didUpdateWidget(covariant ShortVideoDanmaku oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      oldWidget.position.removeListener(_tick);
      widget.position.addListener(_tick);
    }
    if (oldWidget.rate != widget.rate ||
        oldWidget.fontSize != widget.fontSize ||
        oldWidget.area != widget.area) {
      _canvas?.updateOption(_option);
    }
    _sync();
  }

  void _sync() {
    if (widget.playing) {
      _canvas?.resume();
      _tick();
    } else {
      _canvas?.pause();
    }
  }

  Future<void> _load(int segment) async {
    if (_segments.containsKey(segment) ||
        _pending.contains(segment) ||
        _failed.contains(segment)) {
      return;
    }
    // Seek bursts must not start unbounded background requests.
    if (_pending.isNotEmpty) return;
    _pending.add(segment);
    try {
      final result = await widget.loader(
        cid: widget.cid,
        segmentIndex: segment,
      );
      if (!mounted) return;
      if (result case Success(:final response)) {
        final entries =
            response.elems
                .where((e) => e.mode >= 1 && e.mode <= 5)
                .take(6000)
                .toList()
              ..sort((a, b) => a.progress.compareTo(b.progress));
        if (_segments.length >= 2) _segments.remove(_segments.keys.first);
        _segments[segment] = entries;
      } else {
        _failed.add(segment);
      }
    } catch (_) {
      if (mounted) _failed.add(segment);
    } finally {
      _pending.remove(segment);
    }
  }

  void _tick() {
    if (!widget.playing || _canvas == null) return;
    final now = widget.position.value.inMilliseconds;
    final segment = now ~/ 360000 + 1;
    unawaited(_load(segment));
    if (_last < 0 || now < _last || now - _last > 2000) {
      _canvas!.clear();
      _last = now - 1;
    }
    var count = 0;
    final entries = _segments[segment] ?? <DanmakuElem>[];
    var low = 0;
    var high = entries.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (entries[mid].progress <= _last) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (var index = low; index < entries.length; index++) {
      final entry = entries[index];
      if (entry.progress > now) break;
      if (count++ >= 12) break;
      _canvas!.addDanmaku(
        DanmakuContentItem<void>(
          entry.content,
          color: Color(0xff000000 | (entry.color & 0xffffff))
              .withValues(alpha: widget.opacity),
          type: switch (entry.mode) {
            4 => DanmakuItemType.bottom,
            5 => DanmakuItemType.top,
            _ => DanmakuItemType.scroll,
          },
        ),
      );
    }
    _last = now;
  }

  @override
  void dispose() {
    widget.position.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) => DanmakuScreen<void>(
          size: constraints.biggest,
          option: _option,
          createdController: (controller) {
            _canvas = controller;
            _sync();
          },
        ),
      ),
    ),
  );
}
