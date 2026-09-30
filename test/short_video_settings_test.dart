import 'dart:io';

import 'package:PiliPlus/pages/setting/widgets/fixed_speed_setting.dart';

import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/pages/setting/common_setting.dart';
import 'package:PiliPlus/pages/short_video/controller.dart';
import 'package:PiliPlus/pages/short_video/entry.dart';
import 'package:PiliPlus/pages/short_video/pager.dart';
import 'package:PiliPlus/pages/short_video/preferences.dart';
import 'package:PiliPlus/pages/short_video/view.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

Widget app(Widget child) => GetMaterialApp(
  locale: const Locale('zh', 'CN'),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('zh', 'CN')],
  home: child,
);

Future<void> tapSetting(WidgetTester tester, String label) async {
  // Hive uses real file I/O; initiate the UI write outside the fake test clock.
  await tester.runAsync(() async {
    await tester.tap(find.text(label));
    await GStorage.setting.flush();
  });
  await tester.pumpAndSettle();
}

class RecordingController extends ShortVideoController {
  RecordingController({super.preferences});
  final requested = <int>[];
  @override
  Future<ShortVideoSource> sourceFor(BaseRcmdVideoItemModel item) async {
    requested.add(item.aid!);
    return const ShortVideoSource(url: 'test', cid: 1, isVertical: true);
  }
}

void main() {
  test('fast near-boundary releases never overshoot the destination page', () {
    for (final style in [
      ShortVideoSwipeStyle.smooth,
      ShortVideoSwipeStyle.quick,
    ]) {
      final physics = ShortVideoPagePhysics.forStyle(style);
      for (final release in [(570.0, 6000.0), (30.0, -6000.0)]) {
        final simulation = physics.createBallisticSimulation(
          FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: 1200,
            pixels: release.$1,
            viewportDimension: 600,
            axisDirection: AxisDirection.down,
            devicePixelRatio: 1,
          ),
          release.$2,
        )!;
        for (var frame = 0; frame <= 240; frame++) {
          expect(
            simulation.x(frame / 120),
            inInclusiveRange(-.001, 600.001),
            reason: '$style overshot at frame $frame',
          );
        }
      }
    }
  });
  late Directory storageDir;
  setUpAll(() async {
    storageDir = await Directory.systemTemp.createTemp('short-settings-test-');
    Hive.init(storageDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    GStorage.localCache = await Hive.openBox('localCache');
    await GStorage.localCache.put(LocalCacheKey.buvid, 'settings-test');
  });
  setUp(() => GStorage.setting.clear());
  tearDown(Get.reset);
  tearDownAll(() async {
    await Hive.close();
    await storageDir.delete(recursive: true);
  });

  testWidgets(
    'speed controls use a trailing switch and two rows at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(const Scaffold(body: FixedSpeedSetting(portrait: true))),
      );
      await tester.pumpAndSettle();
      final title = tester.getCenter(find.text('竖屏固定倍速'));
      expect(tester.getCenter(find.byType(Switch)).dx, greaterThan(title.dx));
      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('fixed-speed-grid')),
      );
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      final count =
          (grid.childrenDelegate as SliverChildBuilderDelegate).childCount!;
      expect((count / delegate.crossAxisCount).ceil(), 2);
      expect(find.byType(FilledButton), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  test('recommendation switches default conservatively and reject malformed values', () {
    final defaults = ShortVideoPreferences.fromMap({});
    expect(defaults.personalized, isTrue);
    expect(defaults.onlyVertical, isFalse);
    expect(defaults.cellularPreload, isFalse);
    final changed = ShortVideoPreferences.fromMap({
      SettingBoxKey.shortVideoPersonalized: false,
      SettingBoxKey.shortVideoOnlyVertical: true,
      SettingBoxKey.shortVideoCellularPreload: true,
    });
    expect(changed.personalized, isFalse);
    expect(changed.onlyVertical, isTrue);
    expect(changed.cellularPreload, isTrue);
    expect(
      ShortVideoPreferences.fromMap({
        SettingBoxKey.shortVideoCellularPreload: 'true',
      }).cellularPreload,
      isFalse,
    );
  });

  test(
    'default settings preserve existing entry and malformed values are safe',
    () {
      final defaults = ShortVideoPreferences.fromMap({});
      expect(defaults.enabled, isTrue);
      expect(defaults.autoPlay, isTrue);
      expect(defaults.autoNext, isFalse);
      expect(defaults.preload, isTrue);
      final bad = ShortVideoPreferences.fromMap({
        SettingBoxKey.shortVideoEnabled: 'false',
        SettingBoxKey.shortVideoSwipeStyle: 999,
      });
      expect(bad.enabled, isTrue);
      expect(bad.swipeStyle, ShortVideoSwipeStyle.smooth);
    },
  );

  test('all preferences round-trip through the stored settings map', () async {
    await GStorage.setting.putAll({
      SettingBoxKey.shortVideoEnabled: false,
      SettingBoxKey.shortVideoAutoPlay: false,
      SettingBoxKey.shortVideoAutoNext: true,
      SettingBoxKey.shortVideoPreload: false,
      SettingBoxKey.shortVideoMuted: true,
      SettingBoxKey.shortVideoFill: false,
      SettingBoxKey.shortVideoHaptics: false,
      SettingBoxKey.shortVideoSwipeStyle: 'quick',
    });
    await GStorage.setting.flush();
    final p = ShortVideoPreferences.read();
    expect(
      [
        p.enabled,
        p.autoPlay,
        p.autoNext,
        p.preload,
        p.muted,
        p.fill,
        p.haptics,
      ],
      [false, false, true, false, true, false, false],
    );
    expect(p.swipeStyle, ShortVideoSwipeStyle.quick);
  });

  test('cache maintenance never eagerly resolves playback URLs', () {
    final controller = RecordingController(
      preferences: const ShortVideoPreferences(preload: false),
    );
    controller.items.assignAll(
      List.generate(
        5,
        (i) => RcmdVideoItemModel.fromJson({
          'id': i + 1,
          'title': '视频 $i',
          'duration': 60,
          'owner': {'mid': 1, 'name': '作者'},
          'stat': <String, dynamic>{},
        }),
      ),
    );
    controller.prefetchAround(1);
    expect(controller.requested, isEmpty);
    controller
      ..preferences = const ShortVideoPreferences()
      ..prefetchAround(1);
    expect(controller.requested, isEmpty);
    controller
      ..preferences = const ShortVideoPreferences(enabled: false)
      ..prefetchAround(2);
    expect(controller.requested, isEmpty);
  });

  testWidgets(
    'master switch immediately hides home entry and can be reenabled',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          const Scaffold(
            body: Column(
              children: [
                ShortVideoEntry(),
                Expanded(
                  child: CommonSetting(
                    settingType: SettingType.shortVideoSetting,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('竖屏视频'), findsOneWidget);
      await tapSetting(tester, '启用竖屏视频');
      expect(ShortVideoPreferences.read().enabled, isFalse);
      expect(find.byTooltip('竖屏视频'), findsNothing);
      await tapSetting(tester, '启用竖屏视频');
      expect(find.byTooltip('竖屏视频'), findsOneWidget);
      await tapSetting(tester, '竖屏自动播放');
      await tapSetting(tester, '播完自动下一条');
      await tapSetting(tester, '预加载下一条视频');
      final p = ShortVideoPreferences.read();
      expect([p.autoPlay, p.autoNext, p.preload], [false, true, false]);
      await tester.runAsync(() => GStorage.setting.flush());
      await tester.pumpWidget(
        app(const CommonSetting(settingType: SettingType.shortVideoSetting)),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disabled direct route never starts a feed request and settings remain reachable',
    (tester) async {
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.shortVideoEnabled, false),
      );
      await tester.pumpWidget(app(const ShortVideoPage()));
      await tester.pumpAndSettle();
      expect(find.text('竖屏视频已关闭'), findsOneWidget);
      expect(Get.find<ShortVideoController>().isInitialLoading.value, isFalse);
      await tester.tap(find.text('竖屏设置'));
      await tester.pumpAndSettle();
      expect(find.text('启用竖屏视频'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'pager pauses during drag, settles once, supports reverse and cancelled swipes',
    (tester) async {
      final controller = PageController(initialPage: 1);
      addTearDown(controller.dispose);
      var scrolling = false;
      var selected = 1;
      final settled = <int>[];
      final builds = <int, int>{};
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: ShortVideoPager(
                controller: controller,
                itemCount: 5,
                itemBuilder: (_, index) {
                  builds[index] = (builds[index] ?? 0) + 1;
                  return ColoredBox(
                    color: Colors.black,
                    child: Center(child: Text('页 $index')),
                  );
                },
                onPageChanged: (index) => setState(() => selected = index),
                onScrollingChanged: (value) =>
                    setState(() => scrolling = value),
                onSettled: settled.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump();
      expect(scrolling, isTrue);
      final before = builds[1];
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump();
      }
      expect(
        builds[1],
        before,
        reason: 'video subtree is not rebuilt on every animation frame',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(scrolling, isFalse);
      expect(controller.page, closeTo(1, .001));
      final height = tester.getSize(find.byType(PageView)).height;
      await tester.timedDrag(
        find.byType(PageView),
        Offset(0, -height * .7),
        const Duration(milliseconds: 700),
      );
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(settled.last, 2);
      await tester.timedDrag(
        find.byType(PageView),
        Offset(0, height * .7),
        const Duration(milliseconds: 700),
      );
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(settled.last, 1);
      expect(scrolling, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings shortcut fits a narrow Android portrait screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = 0;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ShortVideoItem(
            item: RcmdVideoItemModel.fromJson({
              'id': 123,
              'title': '测试竖屏视频',
              'duration': 60,
              'owner': {'mid': 1, 'name': '作者'},
              'stat': {'view': 100000000},
            }),
            controller: ShortVideoController(),
            active: false,
            preload: false,
            muted: false,
            onToggleMuted: () {},
            onRefresh: () {},
            onNext: () {},
            onSettings: () => opened++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('竖屏设置'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open panels lock paging and closing restores swipes', (
    tester,
  ) async {
    final controller = PageController(initialPage: 1);
    addTearDown(controller.dispose);
    Widget screen(bool enabled) => app(
      Scaffold(
        body: ShortVideoPager(
          controller: controller,
          itemCount: 3,
          scrollEnabled: enabled,
          itemBuilder: (_, index) => Center(child: Text('页 $index')),
          onPageChanged: (_) {},
          onScrollingChanged: (_) {},
          onSettled: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(screen(false));
    await tester.pumpAndSettle();
    // A panel can open during settling. Lock input, not page alignment.
    final locked = controller.position.physics;
    expect(locked.shouldAcceptUserOffset(controller.position), isFalse);
    final settling = locked.createBallisticSimulation(
      FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 1200,
        pixels: 360,
        viewportDimension: 600,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1,
      ),
      0,
    );
    expect(settling, isNotNull);
    expect(settling!.x(3), closeTo(600, 1));
    await tester.timedDrag(
      find.byType(PageView),
      const Offset(0, -430),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(controller.page, 1);
    await tester.pumpWidget(screen(true));
    await tester.pumpAndSettle();
    await tester.timedDrag(
      find.byType(PageView),
      const Offset(0, -430),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(controller.page, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing swipe style updates physics without losing current page',
    (tester) async {
      final controller = PageController(initialPage: 2);
      addTearDown(controller.dispose);
      Widget screen(ShortVideoSwipeStyle style) => app(
        Scaffold(
          body: ShortVideoPager(
            controller: controller,
            itemCount: 5,
            style: style,
            itemBuilder: (_, index) => Center(child: Text('页 $index')),
            onPageChanged: (_) {},
            onScrollingChanged: (_) {},
            onSettled: (_) {},
          ),
        ),
      );
      await tester.pumpWidget(screen(ShortVideoSwipeStyle.smooth));
      await tester.pumpAndSettle();
      expect(controller.position.physics.spring.stiffness, 260);
      await tester.pumpWidget(screen(ShortVideoSwipeStyle.quick));
      await tester.pumpAndSettle();
      expect(controller.position.physics.spring.stiffness, 1000);
      expect(controller.page, 2);
      await tester.pumpWidget(screen(ShortVideoSwipeStyle.simple));
      await tester.pumpAndSettle();
      expect(controller.position.physics.spring.stiffness, isNot(1000));
      expect(controller.page, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'release policies reach PageView and have distinct trajectories',
    (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      final samples = <ShortVideoSwipeStyle, double>{};
      for (final style in ShortVideoSwipeStyle.values) {
        await tester.pumpWidget(
          app(
            ShortVideoPager(
              controller: controller,
              itemCount: 3,
              style: style,
              itemBuilder: (_, i) => Text('page $i'),
              onPageChanged: (_) {},
              onScrollingChanged: (_) {},
              onSettled: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final physics = controller.position.physics;
        FixedScrollMetrics metrics(double pixels) => FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 1200,
          pixels: pixels,
          viewportDimension: 600,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1,
        );
        final forward = physics.createBallisticSimulation(metrics(120), 300)!;
        final reverse = physics.createBallisticSimulation(metrics(480), -300)!;
        expect(
          forward.x(3),
          closeTo(style == ShortVideoSwipeStyle.smooth ? 0 : 600, 1),
        );
        expect(
          reverse.x(3),
          closeTo(style == ShortVideoSwipeStyle.smooth ? 600 : 0, 1),
        );
        samples[style] = physics
            .createBallisticSimulation(metrics(360), 0)!
            .x(.12);
        for (final velocity in [-6000.0, 6000.0]) {
          final simulation = physics.createBallisticSimulation(
            metrics(360),
            velocity,
          )!;
          expect(simulation.x(3), inInclusiveRange(-1, 601));
        }
      }
      expect(
        samples[ShortVideoSwipeStyle.quick]! -
            samples[ShortVideoSwipeStyle.smooth]!,
        greaterThan(65),
      );
      expect(
        (samples[ShortVideoSwipeStyle.quick]! -
                samples[ShortVideoSwipeStyle.simple]!)
            .abs(),
        greaterThan(20),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion and simple style have no extra transform', (
    tester,
  ) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    Widget pager(ShortVideoSwipeStyle style) => ShortVideoPager(
      controller: controller,
      itemCount: 3,
      style: style,
      itemBuilder: (_, index) => Text('页 $index'),
      onPageChanged: (_) {},
      onScrollingChanged: (_) {},
      onSettled: (_) {},
    );
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: pager(ShortVideoSwipeStyle.smooth),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PageView),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
    );
    await tester.pumpWidget(app(pager(ShortVideoSwipeStyle.simple)));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PageView),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
