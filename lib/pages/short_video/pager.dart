import 'dart:math' as math;

import 'package:PiliPlus/pages/short_video/preferences.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

class ShortVideoPagePhysics extends PageScrollPhysics {
  const ShortVideoPagePhysics({required this.style, super.parent});

  factory ShortVideoPagePhysics.forStyle(ShortVideoSwipeStyle style) =>
      switch (style) {
        ShortVideoSwipeStyle.smooth => const ShortVideoPagePhysics(
          style: ShortVideoSwipeStyle.smooth,
          parent: ClampingScrollPhysics(),
        ),
        ShortVideoSwipeStyle.quick => const _QuickPagePhysics(
          parent: ClampingScrollPhysics(),
        ),
        ShortVideoSwipeStyle.simple => const _SimplePagePhysics(
          parent: ClampingScrollPhysics(),
        ),
      };
  final ShortVideoSwipeStyle style;

  @override
  ShortVideoPagePhysics applyTo(ScrollPhysics? ancestor) =>
      ShortVideoPagePhysics(style: style, parent: buildParent(ancestor));

  @override
  SpringDescription get spring => switch (style) {
    ShortVideoSwipeStyle.smooth => const SpringDescription(
      mass: 1,
      stiffness: 260,
      damping: 33,
    ),
    ShortVideoSwipeStyle.quick => const SpringDescription(
      mass: 1,
      stiffness: 1000,
      damping: 64,
    ),
    ShortVideoSwipeStyle.simple => super.spring,
  };

  @override
  double get minFlingVelocity => 100;

  @override
  double get maxFlingVelocity => 6000;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (style == ShortVideoSwipeStyle.simple ||
        position.outOfRange ||
        position.viewportDimension <= 0) {
      return super.createBallisticSimulation(position, velocity);
    }
    // This pager uses full-size pages. Project a smooth release, but let a
    // deliberate quick flick advance immediately. Never skip multiple pages.
    final extent = position.viewportDimension;
    final page = position.pixels / extent;
    final double targetPage;
    if (style == ShortVideoSwipeStyle.quick && velocity.abs() >= 180) {
      targetPage = velocity > 0 ? page.ceilToDouble() : page.floorToDouble();
    } else {
      final projected = page + velocity * 0.18 / extent;
      targetPage = projected.roundToDouble().clamp(
        page.floorToDouble(),
        page.ceilToDouble(),
      );
    }
    final target = (targetPage * extent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < toleranceFor(position).distance) {
      return null;
    }
    final distance = target - position.pixels;
    // The critically/over-damped spring can still cross its destination if
    // injected with excessive release velocity very close to that boundary.
    // Bound only velocity toward the target, retaining reversal gestures.
    final limit = distance.abs() * math.sqrt(spring.stiffness / spring.mass);
    final settlingVelocity = velocity * distance > 0
        ? velocity.clamp(-limit, limit)
        : velocity;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      settlingVelocity,
      tolerance: toleranceFor(position),
    );
  }
}

// Scrollable refreshes its position physics only when the runtime type changes.
// Distinct types apply a new style immediately while retaining the current page.
class _QuickPagePhysics extends ShortVideoPagePhysics {
  const _QuickPagePhysics({super.parent})
    : super(style: ShortVideoSwipeStyle.quick);
  @override
  _QuickPagePhysics applyTo(ScrollPhysics? ancestor) =>
      _QuickPagePhysics(parent: buildParent(ancestor));
}

class _SimplePagePhysics extends ShortVideoPagePhysics {
  const _SimplePagePhysics({super.parent})
    : super(style: ShortVideoSwipeStyle.simple);
  @override
  _SimplePagePhysics applyTo(ScrollPhysics? ancestor) =>
      _SimplePagePhysics(parent: buildParent(ancestor));
}

/// Edge-to-edge translation without zooming, rounded gaps, or per-frame rebuilds.
class ShortVideoPager extends StatelessWidget {
  const ShortVideoPager({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.onPageChanged,
    required this.onScrollingChanged,
    required this.onSettled,
    this.style = ShortVideoSwipeStyle.smooth,
    this.scrollEnabled = true,
    this.itemKey,
    this.findChildIndexCallback,
  });

  final PageController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<bool> onScrollingChanged;
  final ValueChanged<int> onSettled;
  final ShortVideoSwipeStyle style;
  final bool scrollEnabled;
  final Key Function(int)? itemKey;
  final int? Function(Key)? findChildIndexCallback;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        if (notification is ScrollStartNotification) {
          if (WidgetsBinding.instance.schedulerPhase ==
              SchedulerPhase.persistentCallbacks) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (controller.hasClients &&
                  controller.position.isScrollingNotifier.value) {
                onScrollingChanged(true);
              }
            });
          } else {
            onScrollingChanged(true);
          }
        } else if (notification is ScrollEndNotification) {
          // Scroll notifications arrive after layout. Update playback on the
          // next frame instead of marking the ancestor dirty during layout.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!controller.hasClients ||
                controller.position.isScrollingNotifier.value) {
              return;
            }
            onScrollingChanged(false);
            onSettled((controller.page ?? 0).round());
          });
        }
        return false;
      },
      child: PageView.builder(
        controller: controller,
        scrollDirection: Axis.vertical,
        // Our physics owns snapping; PageView otherwise inserts its own
        // PageScrollPhysics ahead of it and hides the release policy.
        pageSnapping: false,
        allowImplicitScrolling: true,
        physics: !scrollEnabled
            ? NeverScrollableScrollPhysics(
                parent: ShortVideoPagePhysics.forStyle(style),
              )
            : ShortVideoPagePhysics.forStyle(style),
        itemCount: itemCount,
        findChildIndexCallback: findChildIndexCallback,
        onPageChanged: onPageChanged,
        itemBuilder: (context, index) {
          return KeyedSubtree(
            key: itemKey?.call(index),
            child: RepaintBoundary(child: itemBuilder(context, index)),
          );
        },
      ),
    );
  }
}
