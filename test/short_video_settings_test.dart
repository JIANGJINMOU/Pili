import 'package:PiliPlus/pages/short_video/display_preferences.dart';
import 'package:PiliPlus/pages/short_video/subtitle_preferences.dart';
import 'package:PiliPlus/pages/setting/widgets/short_video_subtitle_setting.dart';

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:PiliPlus/pages/short_video/system_ui.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';

import 'package:PiliPlus/pages/setting/models/short_video_settings.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';

import 'package:PiliPlus/pages/setting/widgets/fixed_speed_setting.dart';

import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/pages/setting/common_setting.dart';
import 'package:PiliPlus/pages/short_video/controller.dart';
import 'package:PiliPlus/pages/short_video/comment_layout.dart';
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
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
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
  test('subtitle settings are opt-in, bounded, and tolerate legacy fill', () {
    final defaults = ShortVideoPreferences.fromMap({
      SettingBoxKey.shortVideoFill: true,
    });
    expect(defaults.subtitles.translate, isFalse);
    expect(defaults.subtitles.fontSize, 16);
    expect(defaults.subtitles.language, ShortVideoSubtitleLanguage.auto);
    final p = ShortVideoSubtitlePreferences.fromMap({
      SettingBoxKey.shortVideoSubtitleTranslate: 'true',
      SettingBoxKey.shortVideoSubtitleTarget: 'auto',
      SettingBoxKey.shortVideoSubtitleFont: 200,
      SettingBoxKey.shortVideoSubtitleBackground: double.nan,
      SettingBoxKey.shortVideoSubtitleBilingual: 'false',
    });
    expect(p.translate, isFalse);
    expect(p.target, ShortVideoSubtitleLanguage.chinese);
    expect(p.fontSize, 28);
    expect(p.backgroundOpacity, .65);
    expect(p.bilingual, isTrue);
    expect(
      shortVideoSettings.whereType<SwitchModel>().any(
        (s) => s.setKey == SettingBoxKey.shortVideoFill,
      ),
      isFalse,
    );
  });

  test('display choices are safe and removed AI cannot remain active', () {
    final defaults = ShortVideoPreferences.fromMap({
      SettingBoxKey.shortVideoFill: true,
      SettingBoxKey.shortVideoAspect: 'unknown',
      SettingBoxKey.shortVideoFit: 42,
      SettingBoxKey.shortVideoSubtitleTranslate: true,
      SettingBoxKey.shortVideoSubtitlePosition: 'invalid',
      SettingBoxKey.shortVideoSubtitleLines: 100,
      SettingBoxKey.shortVideoSubtitleBold: 'true',
    });
    expect(defaults.aspect, ShortVideoAspect.original);
    expect(defaults.fit, ShortVideoFit.contain);
    expect(defaults.subtitles.translate, isFalse);
    expect(defaults.subtitles.position, ShortVideoSubtitlePosition.bottom);
    expect(defaults.subtitles.lines, ShortVideoSubtitleLines.three);
    expect(defaults.subtitles.bold, isFalse);
    for (final aspect in ShortVideoAspect.values) {
      for (final fit in ShortVideoFit.values) {
        final p = ShortVideoPreferences.fromMap({
          SettingBoxKey.shortVideoAspect: aspect.name,
          SettingBoxKey.shortVideoFit: fit.name,
        });
        expect(p.aspect, aspect);
        expect(p.fit.fit, fit.fit);
      }
    }
  });

  testWidgets('subtitle choices persist without AI controls', (tester) async {
    await tester.pumpWidget(
      app(
        const Scaffold(
          body: SingleChildScrollView(child: ShortVideoSubtitleSetting()),
        ),
      ),
    );
    expect(find.text('AI 字幕翻译'), findsNothing);
    expect(find.text('AI 服务配置'), findsNothing);
    await tapSetting(tester, '字幕位置');
    await tapSetting(tester, '顶部');
    expect(
      ShortVideoPreferences.read().subtitles.position,
      ShortVideoSubtitlePosition.top,
    );
    await tapSetting(tester, '字幕样式');
    await tapSetting(tester, '字幕颜色');
    await tapSetting(tester, '黄色');
    await tapSetting(tester, '字幕加粗');
    await tapSetting(tester, '字幕阴影');
    await tapSetting(tester, '字幕对齐');
    await tapSetting(tester, '左对齐');
    await tapSetting(tester, '字幕最大行数');
    await tapSetting(tester, '最多 4 行');
    final p = ShortVideoPreferences.read().subtitles;
    expect(p.color, ShortVideoSubtitleColor.yellow);
    expect(p.bold, isTrue);
    expect(p.shadow, isFalse);
    expect(p.align, ShortVideoSubtitleAlign.left);
    expect(p.lines.count, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('display ratio and fit settings persist independently', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const CommonSetting(settingType: SettingType.shortVideoSetting)),
    );
    await tester.pumpAndSettle();
    await tapSetting(tester, '画面比例');
    await tapSetting(tester, '4:3');
    await tapSetting(tester, '画面适配');
    await tapSetting(tester, '铺满裁切');
    expect(ShortVideoPreferences.read().aspect, ShortVideoAspect.classic);
    expect(ShortVideoPreferences.read().fit, ShortVideoFit.cover);
    await tapSetting(tester, '画面比例');
    await tapSetting(tester, '原始比例');
    await tapSetting(tester, '画面适配');
    await tapSetting(tester, '完整显示（默认）');
    expect(ShortVideoPreferences.read().aspect, ShortVideoAspect.original);
    expect(ShortVideoPreferences.read().fit, ShortVideoFit.contain);
  });

  testWidgets('grouped portrait settings fit narrow dark large-text viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Theme(
          data: ThemeData.dark(),
          child: const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 720),
              textScaler: TextScaler.linear(1.3),
            ),
            child: CommonSetting(
              settingType: SettingType.shortVideoSetting,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('你的竖屏体验'), findsNothing);
    expect(find.text('完整画面 · 独立偏好 · 即时生效'), findsNothing);
    expect(find.text('AI 字幕翻译'), findsNothing);
    expect(find.text('AI 服务配置'), findsNothing);
    expect(find.byType(Card), findsNWidgets(5));
    await tapSetting(tester, '竖屏字幕');
    expect(ShortVideoPreferences.read().subtitlesEnabled, isTrue);
    await tapSetting(tester, '字幕样式');
    await tester.ensureVisible(find.text('字幕背景'));
    await tester.pumpAndSettle();
    expect(find.text('字幕字号'), findsOneWidget);
    await tester.ensureVisible(find.text('清除本地推荐记录'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('status bar defaults hidden and rejects malformed persisted values', () {
    expect(ShortVideoPreferences.fromMap({}).showStatusBar, isFalse);
    expect(
      ShortVideoPreferences.fromMap({
        SettingBoxKey.shortVideoShowStatusBar: 'true',
      }).showStatusBar,
      isFalse,
    );
    expect(
      ShortVideoPreferences.fromMap({
        SettingBoxKey.shortVideoShowStatusBar: true,
      }).showStatusBar,
      isTrue,
    );
  });

  testWidgets(
    'status-only mode can hide again and restore ordinary system bars',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await applyShortVideoSystemBars(true);
      expect(calls.last.method, 'SystemChrome.setEnabledSystemUIOverlays');
      expect(calls.last.arguments, ['SystemUiOverlay.top']);
      await applyShortVideoSystemBars(false);
      expect(calls.last.arguments, 'SystemUiMode.immersiveSticky');
      await applyShortVideoSystemBars(true);
      await showSystemBar();
      expect(calls.last.arguments, 'SystemUiMode.edgeToEdge');
      expect(showSystemBar_, isTrue);
    },
  );

  testWidgets(
    'status bar switch persists and is restored when reopening settings',
    (tester) async {
      await tester.pumpWidget(
        app(const CommonSetting(settingType: SettingType.shortVideoSetting)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('显示系统顶部状态栏'));
      await tapSetting(tester, '显示系统顶部状态栏');
      expect(ShortVideoPreferences.read().showStatusBar, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        app(const CommonSetting(settingType: SettingType.shortVideoSetting)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('显示系统顶部状态栏'));
      await tapSetting(tester, '显示系统顶部状态栏');
      expect(ShortVideoPreferences.read().showStatusBar, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  test('comment geometry bounds portrait, keyboard and missing dimensions', () {
    ShortVideoCommentLayout layout(double ratio, [double inset = 0]) =>
        ShortVideoCommentLayout.calculate(
          screen: const Size(320, 720),
          aspectRatio: ratio,
          keyboardInset: inset,
        );
    expect(layout(9 / 16).videoHeight, closeTo(302.4, .01));
    expect(layout(9 / 16, 260).videoHeight, 184);
    expect(layout(16 / 9, 260).videoHeight, 180);
    for (final ratio in [0.0, -1.0, double.nan, double.infinity]) {
      expect(layout(ratio).videoHeight, 180);
      expect(
        ShortVideoSource(
          url: 'test',
          cid: 1,
          isVertical: false,
          aspectRatio: ratio,
        ).displayAspectRatio,
        16 / 9,
      );
    }
    for (final inset in [0.0, 260.0, 700.0, 720.0, 900.0]) {
      final result = layout(9 / 16, inset);
      expect(result.videoHeight, greaterThanOrEqualTo(0));
      expect(result.sheetHeight, greaterThanOrEqualTo(0));
      expect(
        result.videoHeight + result.sheetHeight,
        closeTo(720 - inset.clamp(0, 720), .01),
      );
    }
  });

  testWidgets(
    'player portrait entry uses callback and follows feature switch',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SizedBox(
              width: 32,
              height: 34,
              child: ShortVideoEntry(playerStyle: true, onOpen: () => opened++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.stay_current_portrait_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('竖屏视频'));
      expect(opened, 1);
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.shortVideoEnabled, false),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('竖屏视频'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('clean screen and subtitles default off and accept only boolean preferences', () {
    expect(ShortVideoPreferences.fromMap({}).cleanScreen, isFalse);
    final settings = ShortVideoPreferences.fromMap({
      SettingBoxKey.shortVideoCleanScreen: true,
      SettingBoxKey.shortVideoSubtitles: 'true',
    });
    expect(settings.cleanScreen, isTrue);
    expect(settings.subtitlesEnabled, isFalse);
    expect(
      shortVideoSettings.whereType<SwitchModel>().any(
        (s) => s.setKey == SettingBoxKey.shortVideoCleanScreen,
      ),
      isTrue,
    );
  });
  test('danmaku settings clamp malformed values safely', () {
    final p = ShortVideoPreferences.fromMap({
      SettingBoxKey.shortVideoDanmaku: true,
      SettingBoxKey.shortVideoDanmakuFont: 99,
      SettingBoxKey.shortVideoDanmakuOpacity: double.nan,
      SettingBoxKey.shortVideoDanmakuArea: -1,
    });
    expect(p.danmakuEnabled, isTrue);
    expect(p.danmakuFont, 30);
    expect(p.danmakuOpacity, .85);
    expect(p.danmakuArea, .2);
  });
  test('portrait settings keep fixed-speed switch without speed grid', () {
    final widgets = shortVideoSettings.whereType<WidgetModel>();
    final speed = widgets
        .map((e) => e.child)
        .whereType<FixedSpeedSetting>()
        .single;
    expect(speed.switchOnly, isTrue);
  });
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
        p.haptics,
      ],
      [false, false, true, false, true, false],
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
