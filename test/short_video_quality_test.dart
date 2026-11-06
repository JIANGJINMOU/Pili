import 'dart:io';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/utils/playback_quality.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/pages/short_video/controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final calls = <Map<String, dynamic>>[];
  var qualities = <int>[120, 116, 112, 80, 64];
  var supplement = false;
  var supplementFails = false;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('pili-portrait-quality-');
    Hive.init(dir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    await GStorage.localCache.putAll({
      LocalCacheKey.timeStamp: DateTime.now().millisecondsSinceEpoch,
      LocalCacheKey.mixinKey: 'test',
    });
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/x/frontend/finger/spi')) {
              handler.resolve(
                Response(requestOptions: options, data: {'code': -1}),
              );
              return;
            }
            calls.add(Map.of(options.queryParameters));
            final qn = options.queryParameters['qn'];
            if (supplementFails && qn == 112) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {'code': -1, 'message': 'offline'},
                ),
              );
              return;
            }
            final available = supplement && qn == 112 ? [112] : qualities;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'code': 0,
                  'data': {
                    'quality': available.first,
                    if (supplement)
                      'support_formats': [
                        {'quality': 112},
                      ],
                    'dash': {
                      'video': [
                        for (final q in available)
                          {
                            'id': q,
                            'base_url': 'https://video.invalid/$q',
                            'codecid': q > 80 ? 12 : 7,
                            'width': q == 120 ? 3840 : 1920,
                            'height': q == 120 ? 2160 : 1080,
                          },
                      ],
                    },
                  },
                },
              ),
            );
          },
        ),
      );
  });
  setUp(() async {
    await GStorage.setting.clear();
    await GStorage.setting.put(SettingBoxKey.buvid, 'test');
    calls.clear();
    supplement = false;
    supplementFails = false;
    qualities = [120, 116, 112, 80, 64];
    Accounts.accountMode[AccountType.video.index] = LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '1'}),
      null,
      null,
    );
    await GStorage.setting.put(SettingBoxKey.p1080, true);
  });
  tearDownAll(() async {
    Accounts.accountMode[AccountType.video.index] = AnonymousAccount();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<ShortVideoSource> resolve() => ShortVideoController().sourceFor(
    RcmdVideoItemModel.fromJson({
      'id': 1,
      'bvid': 'BV1xx411c7mD',
      'cid': 1,
      'duration': 60,
      'title': '4K',
      'owner': {'mid': 1},
      'stat': <String, dynamic>{},
    }),
  );

  test(
    'signed-in portrait requests full quality without forcing trial',
    () async {
      final source = await resolve();
      expect(calls.single['qn'], VideoQuality.hdrVivid.code);
      expect(calls.single.containsKey('try_look'), isFalse);
      expect(source.qualityUrls.keys, containsAll([120, 116, 112, 80, 64]));
      expect(
        source.quality,
        120,
      ); // Follow the ordinary full-screen default, within available qualities.
    },
  );

  test('network defaults share the ordinary player settings', () async {
    await GStorage.setting.putAll({
      SettingBoxKey.defaultVideoQa: 120,
      SettingBoxKey.defaultVideoQaCellular: 64,
    });
    expect(PlaybackQuality.forNetwork(true), 120);
    expect(PlaybackQuality.forNetwork(false), 64);
  });

  test(
    'saved quality applies to the next video without losing higher preference',
    () async {
      await PlaybackQuality.save(116);
      expect((await resolve()).quality, 116);
      qualities = [80, 64];
      expect((await resolve()).quality, 80);
      expect(await PlaybackQuality.preferred, 116);
      qualities = [120, 116, 80];
      expect((await resolve()).quality, 116);
    },
  );

  test(
    'quality below every available stream falls back to the lowest',
    () async {
      await PlaybackQuality.save(16);
      qualities = [120, 80, 64];
      expect((await resolve()).quality, 64);
      expect(await PlaybackQuality.preferred, 16);
    },
  );

  test('anonymous portrait honors the trial preference', () async {
    Accounts.accountMode[AccountType.video.index] = AnonymousAccount();
    await resolve();
    expect(calls.single['try_look'], 1);
    calls.clear();
    await GStorage.setting.put(SettingBoxKey.p1080, false);
    await resolve();
    expect(calls.single.containsKey('try_look'), isFalse);
  });

  test(
    'missing high-bitrate stream is supplemented like the ordinary player',
    () async {
      supplement = true;
      qualities = [120, 80, 64];
      final source = await resolve();
      expect(calls.map((c) => c['qn']), [129, 112]);
      expect(source.qualityUrls.keys, containsAll([120, 112, 80, 64]));
    },
  );

  test(
    'optional quality failure keeps the existing playable streams',
    () async {
      supplement = true;
      supplementFails = true;
      qualities = [120, 80, 64];
      final source = await resolve();
      expect(source.qualityUrls.keys, unorderedEquals([120, 80, 64]));
    },
  );

  test('quality menu only contains actual playable streams', () async {
    qualities = [80, 64];
    final source = await resolve();
    expect(source.qualityUrls.keys, unorderedEquals([80, 64]));
    expect(source.qualityUrls.containsKey(120), isFalse);
  });
}
