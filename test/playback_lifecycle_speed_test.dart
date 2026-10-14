import 'package:PiliPlus/pages/short_video/progress_bar.dart';
import 'package:PiliPlus/pages/short_video/fullscreen_surface.dart';
import 'package:PiliPlus/pages/short_video/subtitle_preferences.dart';
import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/services/ai_chat/ai_chat_service.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';

import 'dart:async';

import 'package:PiliPlus/pages/short_video/launch.dart';

import 'dart:io';

import 'package:PiliPlus/pages/short_video/subtitles.dart';

import 'package:PiliPlus/pages/short_video/danmaku.dart';
import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart'
    show DmSegMobileReply, DanmakuElem;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';

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
import 'package:media_kit/media_kit.dart' hide Subtitle;

Widget app(Widget home) => GetMaterialApp(
  locale: const Locale('zh', 'CN'),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('zh', 'CN')],
  getPages: [
    GetPage(
      name: '/videoV',
      page: () => Scaffold(
        body: Text(
          '详情播放器 ${Get.arguments['shortVideoFullscreen']} ${Get.arguments['progress']}',
        ),
      ),
    ),
  ],
  home: home,
);

class Feed extends ShortVideoController {
  Feed({
    this.count = 4,
    this.sourceGate,
    this.feedGate,
    this.aspectRatio,
    super.initialLaunch,
  });
  final double? aspectRatio;
  final Completer<void>? feedGate;
  final int count;
  int sourceRequests = 0;
  final requestedParts = <int>[];
  int moreRequests = 0;
  @override
  Future<void> loadMore() async {
    moreRequests++;
  }

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
    isInitialLoading.value = true;
    await feedGate?.future;
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
    isInitialLoading.value = false;
  }

  @override
  Future<ShortVideoSource> sourceFor(BaseRcmdVideoItemModel item) async {
    sourceRequests++;
    requestedParts.add(item.cid ?? item.aid!);
    if (item.aid == 2) await sourceGate?.future;
    return ShortVideoSource(
      url: 'https://example.invalid/${item.aid}',
      cid: item.cid ?? item.aid!,
      isVertical: aspectRatio == null || aspectRatio! < 1,
      aspectRatio: aspectRatio,
      qualityUrls: {
        64: 'https://example.invalid/720',
        32: 'https://example.invalid/480',
      },
    );
  }
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
    await events.errorEvents.close();
    await events.bufferingEvents.close();
  }
}

class RecordingStreams implements PlayerStream {
  final playingEvents = StreamController<bool>.broadcast();
  final positionEvents = StreamController<Duration>.broadcast();
  final completedEvents = StreamController<bool>.broadcast();
  final errorEvents = StreamController<String>.broadcast();
  final bufferingEvents = StreamController<bool>.broadcast();
  @override
  Stream<bool> get playing => playingEvents.stream;
  @override
  Stream<Duration> get position => positionEvents.stream;
  @override
  Stream<bool> get completed => completedEvents.stream;
  @override
  Stream<Duration> get duration => Stream.value(const Duration(seconds: 120));
  @override
  Stream<bool> get buffering => bufferingEvents.stream;
  @override
  Stream<String> get error => errorEvents.stream;
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
    Completer<void>? feedGate,
    Future<bool> Function()? networkAllowed,
    int count = 4,
    bool failCreation = false,
    double? aspectRatio,
    ShortVideoLaunch? initialLaunch,
  }) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Get.put<ShortVideoController>(
      Feed(
        count: count,
        sourceGate: sourceGate,
        feedGate: feedGate,
        aspectRatio: aspectRatio,
        initialLaunch: initialLaunch,
      ),
    );
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
    if (openGate == null && feedGate == null) {
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

  ShortVideoLaunch launch(int aid, int cid, int seconds) => ShortVideoLaunch(
    position: Duration(seconds: seconds),
    item: RcmdVideoItemModel.fromJson({
      'id': aid,
      'cid': cid,
      'title': '指定视频 $aid 分P $cid',
      'duration': 120,
      'owner': {'mid': 1, 'name': '作者'},
      'stat': <String, dynamic>{},
    }),
  );

  testWidgets(
    'scrub preview follows finger despite stale native ticks and commits once',
    (tester) async {
      final position = ValueNotifier(const Duration(seconds: 10));
      final gate = Completer<void>();
      final seeks = <double>[];
      final dragging = <bool>[];
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: ShortVideoProgressBar(
                  positionListenable: position,
                  duration: const Duration(seconds: 120),
                  haptics: false,
                  onDraggingChanged: dragging.add,
                  onSeek: (value) {
                    seeks.add(value);
                    return gate.future;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final track = find.byKey(const ValueKey('short-video-seek-track'));
      final rect = tester.getRect(track);
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * .2, rect.center.dy),
      );
      await gesture.moveTo(Offset(rect.left + rect.width * .5, rect.center.dy));
      await tester.pump();
      await gesture.moveTo(Offset(rect.left + rect.width * .8, rect.center.dy));
      position.value = const Duration(seconds: 11);
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(.8, .01),
      );
      expect(find.text('01:36'), findsOneWidget);
      expect(seeks, isEmpty);
      await gesture.up();
      await tester.pump();
      expect(seeks, hasLength(1));
      expect(seeks.single, closeTo(.8, .01));
      position.value = const Duration(seconds: 12);
      await tester.pump();
      expect(find.text('01:36'), findsOneWidget);
      gate.complete();
      await tester.pump();
      expect(find.text('01:36'), findsOneWidget);
      position.value = const Duration(seconds: 96);
      await tester.pump();
      expect(dragging, [true, false]);
      position.value = const Duration(seconds: 97);
      await tester.pump();
      expect(find.text('01:37'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      position.dispose();
    },
  );

  testWidgets(
    'rapid seek taps serialize native requests and retain latest target',
    (tester) async {
      final position = ValueNotifier(Duration.zero);
      final gates = <Completer<void>>[];
      final targets = <double>[];
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: ShortVideoProgressBar(
                  positionListenable: position,
                  duration: const Duration(seconds: 100),
                  haptics: false,
                  onSeek: (value) {
                    targets.add(value);
                    final gate = Completer<void>();
                    gates.add(gate);
                    return gate.future;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(
        find.byKey(const ValueKey('short-video-seek-track')),
      );
      Future<void> tap(double value) async {
        await tester.tapAt(
          Offset(rect.left + rect.width * value, rect.center.dy),
        );
        await tester.pump();
      }

      await tap(.2);
      await tap(.5);
      await tap(.9);
      expect(targets, hasLength(1));
      expect(find.text('01:30'), findsOneWidget);
      gates.first.complete();
      await tester.pump();
      expect(targets, hasLength(2));
      expect(targets.last, closeTo(.9, .01));
      gates.last.complete();
      position.value = const Duration(seconds: 90);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      position.dispose();
    },
  );

  testWidgets('cancelled scrub and unknown duration never seek', (
    tester,
  ) async {
    final position = ValueNotifier(Duration.zero);
    var seeks = 0;
    Widget bar(Duration duration) => app(
      Scaffold(
        body: Center(
          child: ShortVideoProgressBar(
            positionListenable: position,
            duration: duration,
            haptics: false,
            onSeek: (_) async {
              seeks++;
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(bar(const Duration(seconds: 100)));
    final track = find.byKey(const ValueKey('short-video-seek-track'));
    final gesture = await tester.startGesture(tester.getCenter(track));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expect(seeks, 0);
    await tester.pumpWidget(bar(Duration.zero));
    await tester.tap(track);
    await tester.pump();
    expect(seeks, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    position.dispose();
  });

  testWidgets('real portrait scrub locks page and does not spam native seek', (
    tester,
  ) async {
    await mount(tester);
    final player = players.single;
    final track = find
        .byKey(const ValueKey('short-video-seek-track'))
        .hitTestable();
    final rect = tester.getRect(track);
    final gesture = await tester.startGesture(
      Offset(rect.left + 20, rect.center.dy),
    );
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 2));
    await tester.pump();
    expect(player.seeks, 0);
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(player.seeks, 1);
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isNot(isA<NeverScrollableScrollPhysics>()),
    );
    expect(player.opens, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'direct fullscreen surface fills first frame and keeps same player during load',
    (tester) async {
      tester.view.physicalSize = const Size(720, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final playerKey = GlobalKey();
      var exits = 0, retries = 0;
      Widget surface(bool ready, bool failed) => app(
        ShortVideoFullscreenSurface(
          ready: ready,
          failed: failed,
          onExit: () => exits++,
          onRetry: () => retries++,
          player: SizedBox(key: playerKey, child: const Text('共享播放器')),
        ),
      );
      await tester.pumpWidget(surface(false, false));
      final element = playerKey.currentContext;
      expect(
        tester.getSize(
          find.byKey(const ValueKey('short-video-direct-fullscreen')),
        ),
        const Size(720, 320),
      );
      expect(find.text('正在加载全屏视频…'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      await tester.pumpWidget(surface(false, true));
      await tester.tap(find.text('重试'));
      expect(retries, 1);
      await tester.tap(find.byTooltip('返回竖屏'));
      expect(exits, 1);
      await tester.pumpWidget(surface(true, false));
      expect(playerKey.currentContext, same(element));
      expect(find.text('正在加载全屏视频…'), findsNothing);
      expect(find.text('共享播放器'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('explicit ratio and fit apply live without reopening player', (
    tester,
  ) async {
    await mount(tester, aspectRatio: 9 / 16);
    final player = players.first;
    final opens = player.opens;
    await tester.runAsync(
      () => GStorage.setting.putAll({
        SettingBoxKey.shortVideoAspect: 'classic',
        SettingBoxKey.shortVideoFit: 'cover',
      }),
    );
    await tester.pumpAndSettle();
    final viewport = find
        .byKey(const ValueKey('short-video-media-viewport'))
        .first;
    final fitted = tester
        .widgetList<FittedBox>(
          find.descendant(of: viewport, matching: find.byType(FittedBox)),
        )
        .where((v) => v.fit == BoxFit.cover)
        .first;
    final box = fitted.child! as SizedBox;
    expect(box.width! / box.height!, closeTo(4 / 3, .001));
    expect(player.opens, opens);
    await tester.runAsync(
      () => GStorage.setting.putAll({
        SettingBoxKey.shortVideoAspect: 'original',
        SettingBoxKey.shortVideoFit: 'contain',
      }),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<NetworkImgLayer>(
            find
                .descendant(
                  of: viewport,
                  matching: find.byType(NetworkImgLayer),
                )
                .first,
          )
          .fit,
      BoxFit.contain,
    );
    expect(player.opens, opens);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'subtitle style updates live and remains bounded in short viewport',
    (tester) async {
      final position = ValueNotifier(Duration.zero);
      var loads = 0, requests = 0;
      Widget captions(ShortVideoSubtitlePreferences preferences) => app(
        Center(
          child: SizedBox(
            width: 180,
            height: 90,
            child: ShortVideoSubtitles(
              aid: 1,
              bvid: 'test',
              cid: 1,
              position: position,
              preferences: preferences,
              loader: (_, _, _) async {
                loads++;
                return [ShortVideoCaption(0, 20, '字幕内容 ' * 30)];
              },
              translator:
                  ({
                    required text,
                    required target,
                    required cancelToken,
                  }) async {
                    requests++;
                    return 'unexpected';
                  },
            ),
          ),
        ),
      );
      await tester.pumpWidget(captions(const ShortVideoSubtitlePreferences()));
      await tester.pump(const Duration(seconds: 1));
      final p = ShortVideoSubtitlePreferences.fromMap({
        SettingBoxKey.shortVideoSubtitleTranslate: true,
        SettingBoxKey.shortVideoSubtitleColor: 'yellow',
        SettingBoxKey.shortVideoSubtitleBold: true,
        SettingBoxKey.shortVideoSubtitleShadow: false,
        SettingBoxKey.shortVideoSubtitleAlign: 'left',
        SettingBoxKey.shortVideoSubtitleLines: 'six',
        SettingBoxKey.shortVideoSubtitleFont: 28,
      });
      await tester.pumpWidget(captions(p));
      await tester.pump(const Duration(seconds: 1));
      final text = tester.widget<Text>(find.text('字幕内容 ' * 30));
      expect(text.style!.color, ShortVideoSubtitleColor.yellow.color);
      expect(text.style!.fontWeight, FontWeight.w700);
      expect(text.style!.shadows, isNull);
      expect(text.textAlign, TextAlign.left);
      expect(text.maxLines, 6);
      expect(loads, 1);
      expect(requests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      position.dispose();
    },
  );

  testWidgets(
    'legacy fill cannot crop portrait edges before or during comments',
    (tester) async {
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.shortVideoFill, true),
      );
      await mount(tester, aspectRatio: 9 / 16);
      final viewport = find
          .byKey(const ValueKey('short-video-media-viewport'))
          .first;
      void check() {
        final covers = tester.widgetList<NetworkImgLayer>(
          find.descendant(of: viewport, matching: find.byType(NetworkImgLayer)),
        );
        expect(covers, isNotEmpty);
        for (final cover in covers) {
          expect(cover.fit, BoxFit.contain);
          final sizes = applyBoxFit(
            cover.fit,
            const Size(1080, 1920),
            tester.getSize(viewport),
          );
          expect(sizes.source, const Size(1080, 1920));
          expect(sizes.destination.width, lessThanOrEqualTo(320));
        }
      }

      check();
      await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
      await tester.pumpAndSettle();
      check();
      await tester.tap(find.byTooltip('关闭评论'));
      await tester.pumpAndSettle();
      check();
      expect(players.single.opens, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'subtitle track language preference falls back and ignores unusable URLs',
    () {
      final tracks = [
        Subtitle(lan: 'en', subtitleUrl: '//en', isAi: false),
        Subtitle(lan: 'ai-zh', subtitleUrl: '//ai', isAi: true),
        Subtitle(lan: 'zh-CN', subtitleUrl: '//zh'),
        Subtitle(lan: 'ja', subtitleUrl: ''),
      ];
      expect(
        selectShortVideoSubtitle(
          tracks,
          ShortVideoSubtitleLanguage.auto,
        )?.subtitleUrl,
        '//zh',
      );
      expect(
        selectShortVideoSubtitle(
          tracks,
          ShortVideoSubtitleLanguage.english,
        )?.subtitleUrl,
        '//en',
      );
      expect(
        selectShortVideoSubtitle(
          tracks,
          ShortVideoSubtitleLanguage.japanese,
        )?.subtitleUrl,
        '//zh',
      );
      expect(
        selectShortVideoSubtitle([], ShortVideoSubtitleLanguage.auto),
        isNull,
      );
    },
  );

  test(
    'subtitle AI request is bounded, non-streaming and strips reasoning',
    () async {
      await GStorage.setting.putAll({
        SettingBoxKey.aiApiUrl: 'https://example.invalid/v1/',
        SettingBoxKey.aiModel: 'test-model',
        SettingBoxKey.aiApiKey: 'fixture-only',
      });
      final dio = Dio();
      addTearDown(dio.close);
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            expect(
              options.uri.toString(),
              'https://example.invalid/v1/chat/completions',
            );
            expect(options.data['stream'], isFalse);
            expect(options.data['model'], 'test-model');
            expect(options.data['messages'], hasLength(2));
            expect(options.data['messages'][1]['content'], 'hello');
            expect(options.headers['Authorization'], 'Bearer fixture-only');
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'choices': [
                    {
                      'message': {
                        'content': '<think>private reasoning</think>你好',
                      },
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
      expect(
        await AiChatService.translateSubtitleText(
          text: 'hello',
          target: '简体中文',
          cancelToken: CancelToken(),
          client: dio,
        ),
        '你好',
      );
      expect(requests, 1);
      await expectLater(
        AiChatService.translateSubtitleText(
          text: 'a' * 601,
          target: '英语',
          cancelToken: CancelToken(),
          client: dio,
        ),
        throwsStateError,
      );
      expect(requests, 1);
      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'choices': [false],
              },
            ),
          ),
        ),
      );
      await expectLater(
        AiChatService.translateSubtitleText(
          text: 'hello',
          target: '英语',
          cancelToken: CancelToken(),
          client: dio,
        ),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'subtitle translation is opt-in cached and style changes do not reload',
    (tester) async {
      final position = ValueNotifier(Duration.zero);
      var calls = 0, loads = 0;
      Widget captions({
        bool enabled = false,
        bool bilingual = true,
        double font = 16,
      }) => app(
        ShortVideoSubtitles(
          aid: 1,
          bvid: 'test',
          cid: 1,
          position: position,
          preferences: ShortVideoSubtitlePreferences(
            translate: enabled,
            bilingual: bilingual,
            fontSize: font,
          ),
          loader: (_, _, _) async {
            loads++;
            return const [
              ShortVideoCaption(0, 5, 'hello'),
              ShortVideoCaption(5, 10, 'world'),
            ];
          },
          translator:
              ({required text, required target, required cancelToken}) async {
                calls++;
                return text == 'hello' ? '你好' : '世界';
              },
        ),
      );
      await tester.pumpWidget(captions());
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 0);
      await tester.pumpWidget(captions(enabled: true));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('hello\n你好'), findsOneWidget);
      position.value = const Duration(seconds: 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      await tester.pumpWidget(
        captions(enabled: true, bilingual: false, font: 24),
      );
      expect(find.text('你好'), findsOneWidget);
      expect(tester.widget<Text>(find.text('你好')).style?.fontSize, 24);
      expect(loads, 1);
      position.value = const Duration(seconds: 6);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('世界'), findsOneWidget);
      position.value = Duration.zero;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('你好'), findsOneWidget);
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      position.dispose();
    },
  );

  testWidgets(
    'subtitle translation cancels on pause and rejects stale target responses',
    (tester) async {
      final position = ValueNotifier(Duration.zero);
      final requests = <(CancelToken, Completer<String>)>[];
      Widget captions({
        bool active = true,
        ShortVideoSubtitleLanguage target = ShortVideoSubtitleLanguage.chinese,
      }) => app(
        ShortVideoSubtitles(
          aid: 1,
          bvid: 'test',
          cid: 1,
          position: position,
          translationActive: active,
          preferences: ShortVideoSubtitlePreferences(
            translate: true,
            target: target,
          ),
          loader: (_, _, _) async => const [ShortVideoCaption(0, 30, 'hello')],
          translator: ({required text, required target, required cancelToken}) {
            final c = Completer<String>();
            requests.add((cancelToken, c));
            return c.future;
          },
        ),
      );
      await tester.pumpWidget(captions());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(requests, hasLength(1));
      expect(find.text('hello'), findsOneWidget);
      await tester.pumpWidget(captions(active: false));
      expect(requests.first.$1.isCancelled, isTrue);
      requests.first.$2.complete('旧译文');
      await tester.pump();
      expect(find.textContaining('旧译文'), findsNothing);
      await tester.pumpWidget(
        captions(target: ShortVideoSubtitleLanguage.japanese),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(requests, hasLength(2));
      await tester.pumpWidget(
        captions(target: ShortVideoSubtitleLanguage.english),
      );
      expect(requests[1].$1.isCancelled, isTrue);
      requests[1].$2.complete('古い');
      await tester.pump(const Duration(milliseconds: 400));
      expect(requests, hasLength(3));
      expect(find.textContaining('古い'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(requests.last.$1.isCancelled, isTrue);
      requests.last.$2.complete('late');
      await tester.pump();
      position.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'subtitle translation cancels background work before another frame',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final position = ValueNotifier(Duration.zero);
      final request = Completer<String>();
      CancelToken? token;
      var calls = 0;
      await tester.pumpWidget(
        app(
          ShortVideoSubtitles(
            aid: 1,
            bvid: 'test',
            cid: 1,
            position: position,
            preferences: const ShortVideoSubtitlePreferences(translate: true),
            loader: (_, _, _) async => const [
              ShortVideoCaption(0, 10, 'hello'),
            ],
            translator:
                ({required text, required target, required cancelToken}) {
                  calls++;
                  token = cancelToken;
                  return request.future;
                },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // No pump here: the observer itself must revoke the request.
      expect(token!.isCancelled, isTrue);
      request.complete('late');
      position.value = const Duration(seconds: 2);
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 1);
      expect(find.textContaining('late'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      position.dispose();
    },
  );

  testWidgets(
    'subtitle translation failure retains original without retry storm',
    (tester) async {
      final position = ValueNotifier(Duration.zero);
      var calls = 0;
      await tester.pumpWidget(
        app(
          ShortVideoSubtitles(
            aid: 1,
            bvid: 'test',
            cid: 1,
            position: position,
            preferences: const ShortVideoSubtitlePreferences(translate: true),
            loader: (_, _, _) async => const [
              ShortVideoCaption(0, 5, 'hello'),
              ShortVideoCaption(5, 10, 'world'),
            ],
            translator:
                ({required text, required target, required cancelToken}) {
                  calls++;
                  return Future<String>.error(StateError('offline'));
                },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('hello'), findsOneWidget);
      expect(find.text('翻译暂不可用，显示原字幕'), findsOneWidget);
      position.value = const Duration(seconds: 6);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('world'), findsOneWidget);
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      position.dispose();
    },
  );

  testWidgets(
    'detail launch plays selected part at current position even with vertical-only filter',
    (tester) async {
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.shortVideoOnlyVertical, true),
      );
      await mount(
        tester,
        initialLaunch: launch(99, 990, 37),
        aspectRatio: 16 / 9,
      );
      final feed = Get.find<ShortVideoController>() as Feed;
      expect(feed.items.single.aid, 99);
      expect(feed.requestedParts, [990]);
      expect(players.single.position, const Duration(seconds: 37));
      expect(players.single.opens, 1);
      expect(players.single.playing, isTrue);
      expect(find.textContaining('指定视频 99'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await lifecycle(tester, AppLifecycleState.inactive);
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(players.single.seeks, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'existing feed resets from another page and reopens a different part of same video',
    (tester) async {
      await mount(tester);
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(2);
      await tester.pumpAndSettle();
      final feed = (Get.find<ShortVideoController>() as Feed)
        ..startFrom(launch(3, 333, 42));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        0,
      );
      expect(feed.items.single.cid, 333);
      expect(feed.requestedParts.last, 333);
      expect(players.last.position, const Duration(seconds: 42));
      expect(players.last.playing, isTrue);
      expect(players.where((p) => p.playing), hasLength(1));
      feed.startFrom(launch(3, 444, 19));
      await tester.pumpAndSettle();
      expect(feed.requestedParts.last, 444);
      expect(players.last.position, const Duration(seconds: 19));
      expect(players.where((p) => p.playing), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'comment modal preserves original video brightness with transparent barrier',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('short-video-comment-panel'));
      expect(
        ModalRoute.of(tester.element(panel))!.barrierColor,
        Colors.transparent,
      );
      expect(players.single.playing, isTrue);
      await tester.tapAt(const Offset(160, 60));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(players.single.playing, isTrue);
      expect(players.single.opens, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  Future<void> tapStored(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await GStorage.setting.flush();
      await GStorage.video.flush();
    });
    await tester.pumpAndSettle();
  }

  testWidgets('danmaku only loads playing segments and pauses its canvas', (
    tester,
  ) async {
    final position = ValueNotifier(Duration.zero);
    final requested = <int>[];
    var playing = false;
    Widget content() => app(
      SizedBox(
        width: 320,
        height: 600,
        child: ShortVideoDanmaku(
          cid: 1,
          position: position,
          playing: playing,
          rate: 1,
          loader:
              ({
                required int cid,
                required int segmentIndex,
                int type = 1,
              }) async {
                requested.add(segmentIndex);
                return Success(
                  DmSegMobileReply(
                    elems: [DanmakuElem(content: '测试', progress: 100, mode: 1)],
                  ),
                );
              },
        ),
      ),
    );
    await tester.pumpWidget(content());
    expect(requested, isEmpty);
    playing = true;
    await tester.pumpWidget(content());
    await tester.pump();
    expect(requested, [1]);
    position.value = const Duration(milliseconds: 200);
    await tester.pump();
    expect(find.byType(DanmakuScreen<void>), findsOneWidget);
    playing = false;
    await tester.pumpWidget(content());
    position.value = const Duration(minutes: 7);
    await tester.pump();
    expect(requested, [1]);
    playing = true;
    await tester.pumpWidget(content());
    await tester.pump();
    expect(requested, [1, 2]);
    await tester.pumpWidget(const SizedBox.shrink());
    position.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'fullscreen opens existing detail player with progress and old icon',
    (tester) async {
      await mount(tester);
      final player = players.single;
      await player.seek(const Duration(seconds: 37));
      await tester.pump();
      expect(find.byIcon(Icons.screen_rotation_rounded), findsWidgets);
      await tester.tap(find.byTooltip('全屏').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('详情播放器 true 37000'), findsOneWidget);
      final onReturn =
          Get.arguments['shortVideoOnReturn']
              as void Function(int, Duration, bool);
      expect(player.playing, isFalse);
      Get.back();
      await tester.pumpAndSettle();
      expect(player.opens, 1);
      expect(player.playing, isTrue);
      onReturn(1, const Duration(seconds: 52), false);
      await tester.pumpAndSettle();
      expect(player.position, const Duration(seconds: 52));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'transient native error clears on progress without error UI or retry',
    (tester) async {
      await mount(tester);
      final player = players.single;
      player.events.errorEvents.add('temporary CDN request failed');
      await tester.pump();
      expect(find.text('重新加载'), findsNothing);
      for (var i = 1; i <= 8; i++) {
        player.events.positionEvents.add(Duration(seconds: i));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(players, hasLength(1));
      expect(find.text('重新加载'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('stale buffering flag cannot retry an advancing video', (
    tester,
  ) async {
    await mount(tester);
    final player = players.single;
    player.events.bufferingEvents.add(true);
    for (var i = 1; i <= 20; i++) {
      player.events.positionEvents.add(Duration(seconds: i));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(players, hasLength(1));
    expect(find.text('重新加载'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('confirmed failure recovery before retry cancels reload', (
    tester,
  ) async {
    await mount(tester);
    final player = players.single;
    player.events.errorEvents.add('offline');
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('重新加载'), findsOneWidget);
    player.events.positionEvents.add(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('重新加载'), findsNothing);
    expect(players, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'clean screen preference hides controls and double tap restores them',
    (tester) async {
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.shortVideoCleanScreen, true),
      );
      await mount(tester);
      expect(find.byTooltip('打开字幕'), findsNothing);
      await tester.tapAt(const Offset(160, 280));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(160, 280));
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开字幕'), findsOneWidget);
      expect(players, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'subtitle parsing filters malformed cues and supports backward seek',
    () {
      final cues = ShortVideoCaption.parse([
        {'from': 3, 'to': 4, 'content': '第二句'},
        {'from': 1, 'to': 2, 'content': '第一句'},
        {'from': double.nan, 'to': 4, 'content': '坏数据'},
        {'from': 4, 'to': 3, 'content': '坏数据'},
        null,
      ]);
      expect(cues, hasLength(2));
      expect(
        ShortVideoCaption.at(cues, const Duration(milliseconds: 3500)),
        '第二句',
      );
      expect(ShortVideoCaption.at(cues, const Duration(seconds: 2)), '');
      expect(ShortVideoCaption.at(cues, const Duration(seconds: 1)), '第一句');
    },
  );

  testWidgets(
    'subtitle loading is once per video and stale result cannot replace current cues',
    (tester) async {
      final position = ValueNotifier(Duration.zero);
      final old = Completer<List<ShortVideoCaption>>();
      var loads = 0;
      Widget captions(int cid) => app(
        ShortVideoSubtitles(
          aid: 1,
          bvid: 'test',
          cid: cid,
          position: position,
          loader: (aid, bvid, cid) async {
            loads++;
            return cid == 1
                ? old.future
                : [const ShortVideoCaption(1, 2, '当前字幕')];
          },
        ),
      );
      await tester.pumpWidget(captions(1));
      await tester.pumpWidget(captions(2));
      await tester.pump();
      position.value = const Duration(seconds: 1);
      await tester.pump();
      expect(find.text('当前字幕'), findsOneWidget);
      old.complete([const ShortVideoCaption(1, 2, '过期字幕')]);
      await tester.pump();
      expect(find.text('过期字幕'), findsNothing);
      expect(loads, 2);
      position.value = const Duration(seconds: 3);
      await tester.pump();
      expect(find.text('当前字幕'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      position.dispose();
    },
  );

  testWidgets('temporary errors during open cannot interrupt preparation', (
    tester,
  ) async {
    final open = Completer<void>();
    await mount(tester, openGate: open);
    final player = players.single;
    player.events.errorEvents.add('temporary CDN error during open');
    player.events.bufferingEvents.add(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 13));
    expect(find.text('重新加载'), findsNothing);
    expect(players, hasLength(1));
    open.complete();
    await tester.pump();
    player.events.positionEvents.add(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('重新加载'), findsNothing);
    expect(players, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'missing and failed subtitles have distinct feedback and never affect video errors',
    (tester) async {
      final position = ValueNotifier(Duration.zero);
      await tester.pumpWidget(
        app(
          ShortVideoSubtitles(
            aid: 1,
            bvid: 'test',
            cid: 1,
            position: position,
            loader: (_, _, _) async => [],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('该视频暂无可用字幕'), findsOneWidget);
      await tester.pumpWidget(
        app(
          ShortVideoSubtitles(
            aid: 1,
            bvid: 'test',
            cid: 2,
            position: position,
            loader: (_, _, _) async => throw StateError('offline'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('字幕加载失败，可关闭后重新开启'), findsOneWidget);
      expect(find.text('重新加载'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('字幕加载失败，可关闭后重新开启'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      position.dispose();
    },
  );

  testWidgets('comment sheet shrinks video and restores same playing session', (
    tester,
  ) async {
    await mount(tester);
    final player = players.single;
    await player.seek(const Duration(seconds: 37));
    await tester.pump();
    final viewport = find
        .byKey(const ValueKey('short-video-media-viewport'))
        .first;
    expect(tester.getSize(viewport).height, 720);
    await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(viewport).height, inExclusiveRange(302.4, 720));
    await tester.pumpAndSettle();
    expect(tester.getSize(viewport).height, closeTo(302.4, .01));
    expect(players, hasLength(1));
    expect(player.opens, 1);
    expect(player.position, const Duration(seconds: 37));
    expect(player.playing, isTrue);
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    await tester.tap(find.byTooltip('关闭评论'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(viewport).height, inExclusiveRange(302.4, 720));
    await tester.pumpAndSettle();
    expect(tester.getSize(viewport).height, 720);
    expect(players, hasLength(1));
    expect(player.opens, 1);
    expect(player.position, const Duration(seconds: 37));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final ratio in [16 / 9, 4 / 3, 21 / 9, 1.0]) {
    testWidgets('landscape comments fit top video without gap: $ratio', (
      tester,
    ) async {
      await mount(tester, aspectRatio: ratio);
      final player = players.single;
      await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
      await tester.pumpAndSettle();
      final viewport = find
          .byKey(const ValueKey('short-video-media-viewport'))
          .first;
      final panel = find.byKey(const ValueKey('short-video-comment-panel'));
      final videoRect = tester.getRect(viewport);
      final panelRect = tester.getRect(panel);
      expect(videoRect.top, 0);
      expect(videoRect.width, 320);
      expect(videoRect.height, closeTo(320 / ratio, .01));
      expect(panelRect.top, closeTo(videoRect.bottom, .01));
      expect(panelRect.bottom, 720);
      expect(players, hasLength(1));
      expect(player.opens, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭评论'));
      await tester.pumpAndSettle();
      expect(tester.getSize(viewport).height, 720);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'comment keyboard and drag update video viewport without recreation',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
      await tester.pumpAndSettle();
      final viewport = find
          .byKey(const ValueKey('short-video-media-viewport'))
          .first;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.getSize(viewport).height, closeTo(184, .1));
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('评论').first),
      );
      // Cross touch slop first, then exercise an actual drag update.
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 90));
      await tester.pump();
      expect(tester.getSize(viewport).height, greaterThan(302.4));
      await gesture.moveBy(const Offset(0, 230));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getSize(viewport).height, 720);
      expect(players, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'exit clean screen button is tappable while video loads and persists off',
    (tester) async {
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.shortVideoCleanScreen, true),
      );
      final open = Completer<void>();
      await mount(tester, openGate: open);
      expect(find.text('退出清屏'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('退出清屏'));
        await GStorage.setting.flush();
      });
      await tester.pump();
      expect(find.text('退出清屏'), findsNothing);
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(GStorage.setting.get(SettingBoxKey.shortVideoCleanScreen), false);
      open.complete();
      await tester.pumpAndSettle();
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
      await tester.pumpAndSettle();
      expect(find.text('退出清屏'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'system back exits clean mode even with another retained clean card',
    (tester) async {
      await tester.runAsync(() async {
        await GStorage.setting.put(SettingBoxKey.shortVideoCleanScreen, true);
        await GStorage.setting.put(SettingBoxKey.shortVideoPreload, true);
      });
      await mount(tester, networkAllowed: () async => true);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(players.length, greaterThan(1));
      await tester.runAsync(() async {
        await tester.binding.handlePopRoute();
        await GStorage.setting.flush();
      });
      await tester.pumpAndSettle();
      expect(find.byType(ShortVideoPage), findsOneWidget);
      expect(find.text('退出清屏'), findsNothing);
      expect(GStorage.setting.get(SettingBoxKey.shortVideoCleanScreen), false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'initial loading error and playback have a single aligned back button',
    (tester) async {
      final feed = Completer<void>();
      await mount(tester, feedGate: feed);
      expect(find.byTooltip('返回'), findsOneWidget);
      final initialRect = tester.getRect(find.byTooltip('返回'));
      final controller = Get.find<ShortVideoController>();
      controller.isInitialLoading.value = false;
      controller.errorMessage.value = '测试加载失败';
      await tester.pumpAndSettle();
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(tester.getRect(find.byTooltip('返回')), initialRect);
      feed.complete();
      await tester.pumpAndSettle();
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(tester.getRect(find.byTooltip('返回')), initialRect);
      expect(find.byType(BackButton), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('small first batch refills only after first video is ready', (
    tester,
  ) async {
    final open = Completer<void>();
    await mount(tester, openGate: open, count: 1);
    final controller = Get.find<ShortVideoController>() as Feed;
    expect(controller.moreRequests, 0);
    open.complete();
    await tester.pumpAndSettle();
    expect(controller.moreRequests, 1);
    expect(players.single.playing, true);
    expect(players.single.opens, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('network error retries same item and keeps playback progress', (
    tester,
  ) async {
    await mount(tester);
    final first = players.single;
    await first.seek(const Duration(seconds: 37));
    await tester.pump();
    first.events.errorEvents.add('connection reset');
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(players, hasLength(2));
    expect(players.last.position, const Duration(seconds: 37));
    expect(players.last.playing, isTrue);
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('buffering watchdog reloads same video at saved progress', (
    tester,
  ) async {
    await mount(tester);
    final player = players.single;
    await player.seek(const Duration(seconds: 29));
    player.events.bufferingEvents.add(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(players, hasLength(2));
    expect(players.last.position, const Duration(seconds: 29));
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('background cancels retry until playback resumes', (
    tester,
  ) async {
    await mount(tester);
    players.single.events.errorEvents.add('offline');
    await tester.pump();
    await lifecycle(tester, AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 15));
    expect(players, hasLength(1));
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(players, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'quality selection restores position and user pause without replacing player',
    (tester) async {
      await mount(tester);
      final player = players.single;
      await player.seek(const Duration(seconds: 37));
      await tester.pump();
      await tester.tapAt(const Offset(160, 280));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(player.playing, isFalse);
      await tester.tap(find.text('720P').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('480P'));
      await tester.pumpAndSettle();
      expect(players, hasLength(1));
      expect(player.opens, 2);
      expect(player.position, const Duration(seconds: 37));
      expect(player.playing, isFalse);
      expect(find.text('480P'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

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
    'repeated playback failures exhaust retries without skipping the video',
    (tester) async {
      await mount(tester, failCreation: true);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      expect((Get.find<ShortVideoController>() as Feed).sourceRequests, 4);
      expect(find.text('重新加载').hitTestable(), findsOneWidget);
      final page = tester.widget<PageView>(find.byType(PageView)).controller!;
      expect(page.page, 0);
      await tester.pump(const Duration(seconds: 3));
      expect(page.page, 0);
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
      expect(find.byType(PlaybackSpeedGrid), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      await tester.tap(find.byTooltip('倍速').hitTestable());
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
