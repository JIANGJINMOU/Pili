import 'package:PiliPlus/models/common/search/video_search_type.dart';

import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/short_video/search_feed.dart';
import 'package:PiliPlus/pages/short_video/search_sheet.dart';
import 'package:PiliPlus/pages/short_video/controller.dart';
import 'package:PiliPlus/pages/short_video/launch.dart';
import 'package:PiliPlus/pages/short_video/preferences.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

SearchVideoItemModel video(
  int id,
  String title, {
  String tags = '',
  String desc = '',
}) => SearchVideoItemModel.fromJson({
  'aid': id,
  'bvid': IdUtils.av2bv(id),
  'title': title,
  'duration': '1:00',
  'tag': tags,
  'description': desc,
  'mid': 42,
  'author': 'UP',
});

void main() {
  test('search matches title and tags, excludes description-only results, and retries same page', () async {
    final calls = <(String, int)>[];
    var fail = true;
    final feed = ShortVideoSearchFeed(
      ' 猫 ',
      fetch: (q, page) async {
        calls.add((q, page));
        if (fail) {
          fail = false;
          return const Error('offline');
        }
        return Success(
          SearchVideoData(
            numResults: 40,
            list: page == 1
                ? [
                    video(1, '<em>猫</em>的日常'),
                    video(2, '宠物', tags: '猫,萌宠'),
                    video(3, '狗', desc: '猫'),
                  ]
                : [video(4, '猫的旅行')],
          ),
        );
      },
    );
    await expectLater(feed.load(), throwsStateError);
    expect((await feed.load()).map((v) => v.aid), [1, 2]);
    expect((await feed.load()).single.aid, 4);
    expect(await feed.load(), isEmpty);
    expect(calls, [('猫', 1), ('猫', 1), ('猫', 2)]);
  });

  test('search queue starts at first result, deduplicates and never requests recommendations', () async {
    final feed = ShortVideoSearchFeed(
      '猫',
      fetch: (_, page) async => Success(
        SearchVideoData(
          numResults: 40,
          list: page == 1
              ? [video(1, '猫'), video(2, '猫')]
              : [video(2, '猫'), video(3, '猫')],
        ),
      ),
    );
    final first = await feed.load();
    final controller = ShortVideoController(
      initialLaunch: ShortVideoLaunch(
        item: first.first,
        searchFeed: feed,
        searchItems: first,
      ),
      metadataLoader: (_) async =>
          throw StateError('must not load recommendations'),
    )..onInit();
    expect(controller.items.map((v) => v.aid), [1, 2]);
    expect(controller.searchQuery, '猫');
    await controller.loadMore();
    expect(controller.items.map((v) => v.aid), [1, 2, 3]);
    await controller.loadMore();
    expect(controller.items.length, 3);
    controller.onClose();
  });

  test('horizontal filter rejects vertical and unknown metadata and resolves legacy conflicts', () {
    final prefs = ShortVideoPreferences.fromMap({
      SettingBoxKey.shortVideoOnlyHorizontal: true,
      SettingBoxKey.shortVideoOnlyVertical: true,
    });
    expect(prefs.onlyHorizontal, isTrue);
    expect(prefs.onlyVertical, isFalse);
    expect(prefs.acceptOrientation(false), isTrue);
    expect(prefs.acceptOrientation(true), isFalse);
    expect(prefs.acceptOrientation(null), isFalse);
  });

  testWidgets(
    'independent search submits first video and carries the query queue',
    (tester) async {
      ShortVideoLaunch? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<ShortVideoLaunch>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ShortVideoSearchSheet(
                      feedFactory: (query) => ShortVideoSearchFeed(
                        query,
                        fetch: (_, _) async => Success(
                          SearchVideoData(numResults: 1, list: [video(5, '猫')]),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('打开搜索'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '猫');
      await tester.pump();
      await tester.tap(find.text('搜索并播放'));
      await tester.pumpAndSettle();
      expect(result!.item.aid, 5);
      expect(result!.searchFeed!.query, '猫');
      expect(result!.searchItems!.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'every video zone is a keyword and submitting is explicit and guarded',
    (tester) async {
      var calls = 0;
      String? query;
      final pending = Completer<LoadingState<SearchVideoData>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShortVideoSearchSheet(
              feedFactory: (q) => ShortVideoSearchFeed(
                q,
                fetch: (q, _) {
                  calls++;
                  query = q;
                  return pending.future;
                },
              ),
            ),
          ),
        ),
      );
      expect(
        find.byType(ChoiceChip),
        findsNWidgets(VideoZoneType.values.length - 1),
      );
      for (final zone in VideoZoneType.values.skip(1)) {
        expect(find.widgetWithText(ChoiceChip, zone.label), findsOneWidget);
      }
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '生活'));
      await tester.tap(find.widgetWithText(ChoiceChip, '生活'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '生活',
      );
      expect(calls, 0);
      await tester.tap(find.text('搜索并播放'));
      await tester.pump();
      expect(query, '生活');
      expect(calls, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .every((c) => c.onSelected == null),
        isTrue,
      );
      pending.complete(const Error('offline'));
      await tester.pumpAndSettle();
      expect(find.text('搜索失败，请检查网络后重试'), findsOneWidget);
      expect(find.text('继续查找'), findsNothing);
      await tester.ensureVisible(find.byTooltip('清空关键词'));
      await tester.tap(find.byTooltip('清空关键词'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search stays scrollable with keyboard, large text and landscape',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final (size, brightness, keyboard) in const [
        (Size(375, 812), Brightness.light, 0.0),
        (Size(375, 667), Brightness.dark, 280.0),
        (Size(812, 375), Brightness.dark, 140.0),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewInsets: EdgeInsets.only(bottom: keyboard),
                textScaler: const TextScaler.linear(1.6),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const Scaffold(body: ShortVideoSearchSheet()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(ChoiceChip, VideoZoneType.values.last.label),
        );
        await tester.pumpAndSettle();
        final button = tester.getRect(find.byType(FilledButton));
        expect(button.bottom, lessThanOrEqualTo(size.height - keyboard));
        expect(button.height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      }
    },
  );
}
