import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/common/widgets/flutter/popup_menu.dart';
import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/pages/setting/common_setting.dart';
import 'package:PiliPlus/pages/setting/pages/play_speed_set.dart';
import 'package:PiliPlus/pages/setting/widgets/fixed_speed_setting.dart';
import 'package:PiliPlus/pages/short_video/controller.dart';
import 'package:PiliPlus/pages/short_video/view.dart';
import 'package:PiliPlus/utils/fixed_playback_speed.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

Widget app(Widget home) => GetMaterialApp(
  locale: const Locale('zh', 'CN'),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('zh', 'CN')],
  home: home,
);

class Feed extends ShortVideoController {
  Feed({this.count = 4, this.sourceGate});
  final int count;
  final Completer<void>? sourceGate;
  @override
  void recordExposure(BaseRcmdVideoItemModel item) {}
  @override
  void recordWeight(
    BaseRcmdVideoItemModel item,
    double weight, {
    int? revision,
  }) {}

  @override
  Future<void> refreshFeed() async {
    items.assignAll(
      List.generate(
        count,
        (i) => RcmdVideoItemModel.fromJson({
          'id': i + 1,
          'title': '测试视频 $i',
          'duration': 120,
          'owner': {'mid': 1, 'name': '作者'},
          'stat': <String, dynamic>{},
        }),
      ),
    );
  }

  @override
  Future<ShortVideoSource> sourceFor(BaseRcmdVideoItemModel item) async {
    if (item.aid == 2) await sourceGate?.future;
    return ShortVideoSource(
      url: 'https://example.invalid/${item.aid}',
      cid: item.aid!,
      isVertical: true,
    );
  }

  @override
  Future<void> loadMore() async {}
}

/// Only the native surface/engine is replaced. All page lifecycle callbacks,
/// item state, retained-player decisions, gestures and storage are production.
class RecordingPlayer implements Player {
  final events = RecordingStreams();
  bool playing = false;
  int opens = 0;
  int disposals = 0;
  int seeks = 0;
  Duration position = Duration.zero;
  double rate = 1;
  double volume = 0;
  Completer<void>? openGate;

  @override
  PlayerStream get stream => events;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #setMediaHeader:
        return null;
      case #open:
        opens++;
        position = Duration.zero;
        return openGate?.future ?? Future<void>.value();
      case #play:
        playing = true;
        events.playingEvents.add(true);
      case #pause:
        playing = false;
        events.playingEvents.add(false);
      case #setRate:
        rate = invocation.positionalArguments.first as double;
      case #setVolume:
        volume = invocation.positionalArguments.first as double;
      case #seek:
        seeks++;
        position = invocation.positionalArguments.first as Duration;
        events.positionEvents.add(position);
      case #dispose:
        disposals++;
        playing = false;
      default:
        return super.noSuchMethod(invocation);
    }
    return Future<void>.value();
  }

  Future<void> close() async {
    await events.playingEvents.close();
    await events.positionEvents.close();
    await events.completedEvents.close();
  }
}

class RecordingStreams implements PlayerStream {
  final playingEvents = StreamController<bool>.broadcast();
  final positionEvents = StreamController<Duration>.broadcast();
  final completedEvents = StreamController<bool>.broadcast();
  @override
  Stream<bool> get playing => playingEvents.stream;
  @override
  Stream<Duration> get position => positionEvents.stream;
  @override
  Stream<bool> get completed => completedEvents.stream;
  @override
  Stream<Duration> get duration => Stream.value(const Duration(seconds: 120));
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<String> get error => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final players = <RecordingPlayer>[];
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('pili-lifecycle-speed-');
    Hive.init(dir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    GStorage.localCache = await Hive.openBox('localCache');
    await GStorage.localCache.putAll({
      LocalCacheKey.buvid: 'test',
      LocalCacheKey.timeStamp: DateTime.now().millisecondsSinceEpoch,
      LocalCacheKey.mixinKey: 'test',
    });
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'code': -400,
                  'message': 'Metadata not needed by this fixture',
                },
              ),
            );
          },
        ),
      );
  });
  setUp(() async {
    await GStorage.setting.clear();
    await GStorage.video.clear();
    await GStorage.setting.put(SettingBoxKey.shortVideoPreload, false);
    players.clear();
  });
  tearDown(() async {
    Get.reset();
    for (final player in players) {
      await player.close();
    }
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester, {
    Completer<void>? openGate,
    Completer<void>? sourceGate,
    Future<bool> Function()? networkAllowed,
    int count = 4,
    bool failCreation = false,
  }) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Get.put<ShortVideoController>(Feed(count: count, sourceGate: sourceGate));
    await tester.pumpWidget(
      app(
        ShortVideoPage(
          networkAllowed: networkAllowed,
          playerFactory: () async {
            if (failCreation) throw StateError('fixture playback failure');
            final player = RecordingPlayer()..openGate = openGate;
            players.add(player);
            return (player: player, video: null);
          },
        ),
      ),
    );
    if (openGate == null) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.idle();
    await tester.pump();
    if (state == AppLifecycleState.resumed) await tester.pumpAndSettle();
  }

  Future<void> tapStored(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await GStorage.setting.flush();
      await GStorage.video.flush();
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'drag keeps outgoing playback live and style changes retain the player',
    (tester) async {
      await mount(tester);
      final player = players.single;
      final gesture = await tester.startGesture(const Offset(160, 500));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -130));
      await tester.pump(const Duration(milliseconds: 100));
      expect(player.playing, isTrue);
      expect(player.opens, 1);
      expect(players, hasLength(1));
      await gesture.cancel();
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.shortVideoSwipeStyle, 'quick'),
      );
      await tester.pumpAndSettle();
      expect(players, hasLength(1));
      expect(player.disposals, 0);
      expect(player.opens, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refresh resets playback ownership before the next drag', (
    tester,
  ) async {
    await mount(tester);
    tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(2);
    await tester.pumpAndSettle();
    final current = tester
        .widgetList<ShortVideoItem>(find.byType(ShortVideoItem))
        .singleWhere((w) => w.current);
    expect(current.item.aid, 3);
    current.onRefresh();
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(160, 500));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    final active = tester
        .widgetList<ShortVideoItem>(find.byType(ShortVideoItem))
        .singleWhere((w) => w.active);
    expect(active.item.aid, 1);
    await gesture.cancel();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'authorized preload survives dragging without midpoint playback changes',
    (tester) async {
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.shortVideoPreload, true),
      );
      final sourceGate = Completer<void>();
      var checks = 0;
      await mount(
        tester,
        sourceGate: sourceGate,
        networkAllowed: () async {
          checks++;
          return true;
        },
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(checks, 1);
      expect(players, hasLength(1));
      final gesture = await tester.startGesture(const Offset(160, 650));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -420));
      await tester.pump();
      expect(
        tester
            .widgetList<ShortVideoItem>(find.byType(ShortVideoItem))
            .singleWhere((item) => item.current)
            .item
            .aid,
        1,
      );
      sourceGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        players,
        hasLength(2),
        reason:
            'already authorized preparation is not thrown away during a drag',
      );
      expect(players.first.playing, isTrue);
      expect(players.last.playing, isFalse);
      expect(checks, 1, reason: 'no new preload scheduled during gesture');
      await gesture.moveBy(const Offset(0, 350));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(players.first.opens, 1);
      expect(players.last.opens, 1);
      expect(players.every((p) => p.disposals == 0), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preload starts only after settling and cancels for menu/background',
    (tester) async {
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.shortVideoPreload, true),
      );
      var checks = 0;
      await mount(
        tester,
        networkAllowed: () async {
          checks++;
          return true;
        },
      );
      expect(players, hasLength(1));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(players, hasLength(2));
      expect(players.where((p) => p.playing), hasLength(1));
      expect(checks, 1);
      await tester.tap(find.byTooltip('推荐操作').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('不感兴趣'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(checks, 1);
      Get.back();
      await tester.pumpAndSettle();
      final checksBeforeBackground = checks;
      await lifecycle(tester, AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 1));
      expect(checks, checksBeforeBackground);
      expect(players.every((p) => !p.playing), isTrue);
      await lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(players.where((p) => p.disposals == 0), hasLength(2));
      expect(players.first.opens, 1);
      expect(players.first.disposals, 0);
      expect(checks, checksBeforeBackground + 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing network policy revokes pending preload authorization', (
    tester,
  ) async {
    await tester.runAsync(
      () => GStorage.setting.put(SettingBoxKey.shortVideoPreload, true),
    );
    final sourceGate = Completer<void>();
    var allowed = true;
    await mount(
      tester,
      sourceGate: sourceGate,
      networkAllowed: () async => allowed,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(players, hasLength(1));
    allowed = false;
    await tester.runAsync(
      () =>
          GStorage.setting.put(SettingBoxKey.shortVideoCellularPreload, false),
    );
    await tester.pump();
    sourceGate.complete();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(players, hasLength(1));
    expect(players.single.playing, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('cellular policy denial never preloads but current video plays', (
    tester,
  ) async {
    await tester.runAsync(
      () => GStorage.setting.put(SettingBoxKey.shortVideoPreload, true),
    );
    await mount(tester, networkAllowed: () async => false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(players, hasLength(1));
    expect(players.single.playing, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'rapid page changes keep at most three players and rebase long queues',
    (tester) async {
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.shortVideoPreload, true),
      );
      await mount(tester, networkAllowed: () async => true, count: 45);
      final page = tester.widget<PageView>(find.byType(PageView)).controller!;
      for (final index in [1, 2, 3, 28, 29, 30]) {
        page.jumpToPage(index);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(
          players.where((p) => p.disposals == 0).length,
          lessThanOrEqualTo(3),
        );
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(Get.find<ShortVideoController>().items, hasLength(16));
      expect(page.page, 1);
      final active = players.singleWhere((p) => p.playing)
        ..position = const Duration(seconds: 23);
      await lifecycle(tester, AppLifecycleState.inactive);
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(active.position.inSeconds, 23);
      expect(active.opens, 1);
      expect(active.disposals, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'three consecutive playback failures stop automatic skipping and offer reload',
    (tester) async {
      await mount(tester, failCreation: true);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pumpAndSettle();
      }
      expect(find.text('连续播放失败，请检查网络后重新加载'), findsOneWidget);
      final page = tester.widget<PageView>(find.byType(PageView)).controller!;
      expect(page.page, 2);
      await tester.pump(const Duration(seconds: 3));
      expect(page.page, 2);
      expect(players, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'notification shade pauses immediately, retains position and resumes same player',
    (tester) async {
      await mount(tester);
      final player = players.single
        ..position = const Duration(seconds: 37)
        ..events.positionEvents.add(const Duration(seconds: 37));
      await tester.pump();
      for (var cycle = 0; cycle < 3; cycle++) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        // No build frame yet: background audio must still be stopped.
        await tester.idle();
        expect(player.playing, isFalse);
        expect(player.volume, 0);
        await tester.pump();
        expect(player.disposals, 0);
        await lifecycle(tester, AppLifecycleState.resumed);
        expect(player.playing, isTrue);
        expect(player.position.inSeconds, 37);
        expect(player.opens, 1);
        expect(player.seeks, 0);
        expect(players, hasLength(1));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(player.disposals, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual pause survives shade and full background/lock lifecycle',
    (tester) async {
      await mount(tester);
      final player = players.single;
      await tester.tapAt(const Offset(160, 280));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(player.playing, isFalse);
      player.position = const Duration(seconds: 52);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        await lifecycle(tester, state);
        expect(player.playing, isFalse);
        expect(player.disposals, 0);
      }
      expect(player.position.inSeconds, 52);
      expect(player.opens, 1);
      await tester.tapAt(const Offset(160, 280));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(player.playing, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'background while open is pending does not recreate or autoplay behind shade',
    (tester) async {
      final gate = Completer<void>();
      await mount(tester, openGate: gate);
      final player = players.single;
      await lifecycle(tester, AppLifecycleState.inactive);
      gate.complete();
      await tester.pumpAndSettle();
      expect(player.playing, isFalse);
      expect(player.disposals, 0);
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(player.playing, isTrue);
      expect(player.opens, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'full background resumes progress and rapid focus changes do not recreate',
    (tester) async {
      await mount(tester);
      final player = players.single..position = const Duration(seconds: 66);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
      ]) {
        await lifecycle(tester, state);
        expect(player.playing, isFalse);
        expect(player.disposals, 0);
      }
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(player.playing, isTrue);
      for (var i = 0; i < 5; i++) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpAndSettle();
      expect(player.position.inSeconds, 66);
      expect(player.opens, 1);
      expect(player.seeks, 0);
      expect(player.playing, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'portrait stored speed remains disabled until its switch is enabled',
    (tester) async {
      await tester.pumpWidget(
        app(
          const Scaffold(
            body: FixedSpeedSetting(portrait: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapStored(tester, find.text('2.0X'));
      expect(FixedPlaybackSpeed.read().rate, 2);
      expect(FixedPlaybackSpeed.read().enabled, isFalse);
      await tapStored(tester, find.text('竖屏固定倍速'));
      expect(FixedPlaybackSpeed.read().enabled, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'normal speed menu keeps the original temporary rate list',
    (tester) async {
      var rate = 1.25;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: StaticPopupMenuButton<double>(
              tooltip: '倍速',
              initialValue: rate,
              color: Colors.black.withValues(alpha: 0.8),
              itemBuilder: (_) => playbackSpeedMenuItems(
                currentRate: rate,
                rates: [1, 1.25, 1.5, 2],
                showFixedSwitch: false,
                onSelected: (value) => rate = value,
              ),
              child: const Text('打开倍速'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开倍速'));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
      expect(find.text('固定倍速设置'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('1.5X'), findsOneWidget);
      await tester.tap(find.text('1.5X'));
      await tester.pumpAndSettle();
      expect(rate, 1.5);
      expect(find.byType(Switch), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'portrait menu supports temporary speed and Android back without changing videos',
    (tester) async {
      await mount(tester);
      final first = players.single;
      await tester.tap(find.byTooltip('倍速').first);
      await tester.pumpAndSettle();
      expect(find.text('固定倍速'), findsOneWidget);
      await tester.tap(find.text('1.5X'));
      await tester.pumpAndSettle();
      expect(first.rate, 1.5);
      expect(FixedPlaybackSpeed.read().enabled, isFalse);
      await lifecycle(tester, AppLifecycleState.inactive);
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(first.rate, 1.5);
      await tester.tap(find.byTooltip('倍速').first);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ShortVideoPage), findsOneWidget);
      expect(find.text('竖屏固定倍速'), findsNothing);
      await tester.timedDrag(
        find.byType(PageView),
        const Offset(0, -540),
        const Duration(milliseconds: 650),
      );
      await tester.pumpAndSettle();
      expect(players.where((p) => p.playing).single.rate, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('autoplay off remains paused after shade', (tester) async {
    await tester.runAsync(
      () => GStorage.setting.put(SettingBoxKey.shortVideoAutoPlay, false),
    );
    await mount(tester);
    final player = players.single;
    expect(player.playing, isFalse);
    await lifecycle(tester, AppLifecycleState.inactive);
    await lifecycle(tester, AppLifecycleState.resumed);
    expect(player.playing, isFalse);
    expect(player.opens, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'portrait speed control persists, applies live, loops and follows next video',
    (tester) async {
      await mount(tester);
      final first = players.single..position = const Duration(seconds: 25);
      await tester.tap(find.byTooltip('倍速').first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      await tapStored(tester, find.byType(Switch));
      expect(find.text('1.75X'), findsOneWidget);
      await tapStored(tester, find.text('1.75X'));
      expect(first.rate, 1.75);
      expect(first.position.inSeconds, 25);
      expect(first.opens, 1);
      expect(find.text('竖屏固定倍速'), findsNothing);
      first.events.completedEvents.add(true);
      await tester.pumpAndSettle();
      expect(first.seeks, 1);
      expect(first.rate, 1.75);
      await tester.timedDrag(
        find.byType(PageView),
        const Offset(0, -540),
        const Duration(milliseconds: 650),
      );
      await tester.pumpAndSettle();
      expect(players.length, greaterThanOrEqualTo(2));
      expect(players.where((p) => p.playing).single.rate, 1.75);
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
      await mount(tester);
      expect(players.last.rate, 1.75);
      expect(FixedPlaybackSpeed.read().enabled, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long press restores fixed rate on release and lifecycle interruption',
    (tester) async {
      await tester.runAsync(
        () => GStorage.setting.putAll({
          SettingBoxKey.shortVideoFixedSpeedEnabled: true,
          SettingBoxKey.shortVideoFixedSpeed: 1.25,
        }),
      );
      await mount(tester);
      final player = players.single;
      final gesture = await tester.startGesture(const Offset(160, 280));
      await tester.pump(const Duration(milliseconds: 650));
      expect(player.rate, 2);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(player.rate, 1.25);
      final interrupted = await tester.startGesture(const Offset(160, 280));
      await tester.pump(const Duration(milliseconds: 650));
      expect(player.rate, 2);
      await lifecycle(tester, AppLifecycleState.inactive);
      expect(player.rate, 1.25);
      await interrupted.up();
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(player.rate, 1.25);
      expect(player.playing, isTrue);
      await tester.runAsync(
        () => GStorage.setting.put(
          SettingBoxKey.shortVideoFixedSpeedEnabled,
          false,
        ),
      );
      await tester.pumpAndSettle();
      expect(player.rate, 1);
      expect(FixedPlaybackSpeed.read().rate, 1.25);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('double tap toggles clean-screen mode without liking', (
    tester,
  ) async {
    await mount(tester);
    const center = Offset(160, 300);
    expect(find.byTooltip('竖屏设置'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up_alt_outlined), findsOneWidget);

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.byTooltip('竖屏设置'), findsNothing);
    expect(find.byIcon(Icons.thumb_up_alt_outlined), findsNothing);

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.byTooltip('竖屏设置'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up_alt_outlined), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ordinary default speed and portrait fixed speed are separately persisted',
    (tester) async {
      await tester.pumpWidget(app(const PlaySpeedPage()));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.tap(find.text('1.5').last);
      await tester.pumpAndSettle();
      await tapStored(tester, find.text('设置为默认倍速'));
      expect(GStorage.video.get(VideoBoxKey.playSpeedDefault), 1.5);
      expect(FixedPlaybackSpeed.read().enabled, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        app(const CommonSetting(settingType: SettingType.shortVideoSetting)),
      );
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 4 && find.text('竖屏固定倍速').hitTestable().evaluate().isEmpty;
        i++
      ) {
        await tester.timedDrag(
          find.byType(ListView),
          const Offset(0, -360),
          const Duration(milliseconds: 600),
        );
        await tester.pumpAndSettle();
      }
      await tapStored(tester, find.text('竖屏固定倍速'));
      await tester.ensureVisible(find.text('3.0X'));
      await tester.pumpAndSettle();
      await tapStored(tester, find.text('3.0X'));
      expect(FixedPlaybackSpeed.read().effectiveRate(), 3);
      expect(GStorage.video.get(VideoBoxKey.playSpeedDefault), 1.5);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  test('malformed fixed rate is safe and disabled rate uses fallback', () {
    for (final value in [null, '2', -1, 0, 99, double.nan, double.infinity]) {
      final pref = FixedPlaybackSpeed.fromMap({
        SettingBoxKey.shortVideoFixedSpeedEnabled: true,
        SettingBoxKey.shortVideoFixedSpeed: value,
      });
      expect(pref.effectiveRate(), 1.5);
    }
    expect(const FixedPlaybackSpeed(rate: 2).effectiveRate(1.25), 1.25);
  });
}
