import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The sheet starts directly below the fitted video, not at a fixed half-screen.
class ShortVideoCommentLayout {
  const ShortVideoCommentLayout(this.videoHeight, this.sheetHeight);
  final double videoHeight, sheetHeight;

  factory ShortVideoCommentLayout.calculate({
    required Size screen,
    required double aspectRatio,
    double keyboardInset = 0,
  }) {
    final width = math.max(0.0, screen.width);
    final height = math.max(0.0, screen.height);
    final inset = keyboardInset.isFinite
        ? keyboardInset.clamp(0.0, height)
        : 0.0;
    final available = height - inset;
    final ratio = aspectRatio.isFinite && aspectRatio > 0
        ? aspectRatio
        : 16 / 9;
    // Preserve a usable comment area even with a keyboard or a small window.
    final maxVideo = available - math.min(280.0, available * .6);
    final naturalHeight = width / ratio;
    final preferred = ratio >= 1
        ? naturalHeight
        : math.min(naturalHeight, height * .42);
    final videoHeight = math.min(preferred, maxVideo).clamp(0.0, available);
    return ShortVideoCommentLayout(videoHeight, available - videoHeight);
  }
}
