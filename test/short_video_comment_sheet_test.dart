import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/reply.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/reply/content.dart';
import 'package:PiliPlus/models_new/reply/cursor.dart';
import 'package:PiliPlus/models_new/reply/data.dart';
import 'package:PiliPlus/models_new/reply/reply.dart';
import 'package:PiliPlus/models_new/reply/member.dart';
import 'package:PiliPlus/models_new/reply2reply/data.dart';
import 'package:PiliPlus/models_new/reply2reply/page.dart';
import 'package:PiliPlus/pages/short_video/comment_sheet.dart';
import 'package:PiliPlus/pages/short_video/controller.dart';
import 'package:PiliPlus/pages/short_video/view.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

Future<LoadingState<ReplyData>> _loadReplies({
  required bool isLogin,
  required int oid,
  required String nextOffset,
  required int type,
  required int page,
  int sort = 1,
}) async => Success(
  ReplyData(
    cursor: ReplyCursor(allCount: 32, isEnd: true),
    replies: List.generate(
      32,
      (index) => ReplyItemModel(
        rpid: index + 1,
        content: ReplyContent(message: '评论内容 $index'),
      ),
    ),
  ),
);

Future<void> _pumpFeed(
  WidgetTester tester, {
  ShortVideoReplyLoader loadReplies = _loadReplies,
  ValueChanged<int>? onPageChanged,
  Brightness brightness = Brightness.light,
  bool useVideoCard = false,
  int initialPage = 0,
  ShortVideoThreadLoader loadThread = _loadThread,
  ShortVideoCommentSender sendComment = _sendComment,
  ShortVideoCommentLiker likeComment = ReplyHttp.likeReply,
}) async {
  final pageController = PageController(initialPage: initialPage);
  addTearDown(pageController.dispose);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Match main.dart: GetX uses material_ui, including its localization types.
  await tester.pumpWidget(
    GetMaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN')],
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: PageView.builder(
          controller: pageController,
          scrollDirection: Axis.vertical,
          itemCount: 3,
          onPageChanged: onPageChanged,
          itemBuilder: (context, index) => useVideoCard
              ? ShortVideoItem(
                  item: RcmdVideoItemModel.fromJson({
                    'id': 123,
                    'title': '测试视频',
                    'duration': 60,
                    'owner': {'mid': 1, 'name': '测试作者'},
                    'stat': {'view': 100, 'like': 10, 'danmaku': 32},
                  }),
                  controller: ShortVideoController(),
                  active: false,
                  preload: false,
                  muted: false,
                  onToggleMuted: () {},
                  onRefresh: () {},
                  onNext: () {},
                  loadReplies: loadReplies,
                )
              : Center(
                  child: TextButton(
                    child: Text('打开评论 $index'),
                    onPressed: () => unawaited(
                      showShortVideoComments(
                        context: context,
                        aid: 123,
                        commentCount: 32,
                        onCountChanged: (_) {},
                        loadReplies: loadReplies,
                        loadThread: loadThread,
                        sendComment: sendComment,
                        likeComment: likeComment,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<LoadingState<void>> _sendComment({
  required int type,
  required int oid,
  required String message,
  int? root,
  int? parent,
}) async => const Success(null);

Future<LoadingState<ReplyData>> _loadWithThreads({
  required bool isLogin,
  required int oid,
  required String nextOffset,
  required int type,
  required int page,
  int sort = 1,
}) async {
  final result = await _loadReplies(
    isLogin: isLogin,
    oid: oid,
    nextOffset: nextOffset,
    type: type,
    page: page,
    sort: sort,
  );
  result.data.replies![0] = ReplyItemModel(
    rpid: 100,
    rcount: 3,
    member: ReplyMember(uname: '楼主'),
    content: ReplyContent(message: '有回复的主评论'),
    replies: [
      ReplyItemModel(
        rpid: 101,
        root: 100,
        member: ReplyMember(uname: '回复者1'),
        content: ReplyContent(message: '预览回复'),
      ),
    ],
  );
  result.data.replies![1] = ReplyItemModel(
    rpid: 200,
    rcount: 1,
    content: ReplyContent(message: '没有预览的主评论'),
  );
  return result;
}

Future<LoadingState<ReplyReplyData>> _loadThread({
  required bool isLogin,
  required int oid,
  required int root,
  required int pageNum,
  required int type,
  bool isCheck = false,
}) async => Success(
  ReplyReplyData(
    page: ReplyPage(num: pageNum, size: 20, count: 3),
    replies: List.generate(
      3,
      (index) => ReplyItemModel(
        rpid: root + index + 1,
        root: root,
        member: ReplyMember(uname: '回复者${index + 1}'),
        content: ReplyContent(message: '完整回复 $root-${index + 1}'),
      ),
    ),
  ),
);

void _loginForTest() {
  final previous = Accounts.main;
  Accounts.accountMode[AccountType.main.index] = LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': 'test'}),
    'test-access',
    'test-refresh',
  );
  addTearDown(() => Accounts.accountMode[AccountType.main.index] = previous);
}

void main() {
  late Directory storageDir;
  setUpAll(() async {
    storageDir = await Directory.systemTemp.createTemp('short-comment-test-');
    Hive.init(storageDir.path);
    GStorage.localCache = await Hive.openBox('localCache');
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    // Avoid an unawaited first-run ID write inside the widget test's fake clock.
    await GStorage.localCache.put(LocalCacheKey.buvid, 'short-comment-test');
  });
  tearDownAll(() async {
    await Hive.close();
    await storageDir.delete(recursive: true);
  });
  tearDown(Get.reset);

  testWidgets('failed thread root like repaints parent after returning', (
    tester,
  ) async {
    _loginForTest();
    final gate = Completer<LoadingState<void>>();
    await _pumpFeed(
      tester,
      loadReplies: _loadWithThreads,
      likeComment: ({
        required type,
        required oid,
        required rpid,
        required action,
      }) => gate.future,
    );
    await tester.tap(find.text('打开评论 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('共 3 条回复'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('thread-root-comment')),
        matching: find.byIcon(Icons.favorite_border_rounded),
      ),
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    gate.completeError(StateError('late failure'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending likes ignore repeated taps and late failures are safe', (
    tester,
  ) async {
    _loginForTest();
    var calls = 0;
    final gate = Completer<LoadingState<void>>();
    await _pumpFeed(
      tester,
      likeComment:
          ({required type, required oid, required rpid, required action}) {
            calls++;
            return gate.future;
          },
    );
    await tester.tap(find.text('打开评论 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.favorite_rounded).first);
    await tester.pump();
    expect(calls, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    gate.completeError(StateError('network closed'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'thread root and replies share one scrolling surface',
    (tester) async {
      var video = 1;
      await _pumpFeed(
        tester,
        initialPage: 1,
        onPageChanged: (value) => video = value,
        loadReplies: _loadWithThreads,
        loadThread:
            ({
              required isLogin,
              required oid,
              required root,
              required pageNum,
              required type,
              isCheck = false,
            }) async => Success(
              ReplyReplyData(
                page: ReplyPage(num: 1, size: 30, count: 30),
                replies: List.generate(
                  30,
                  (i) => ReplyItemModel(
                    rpid: 1000 + i,
                    root: root,
                    content: ReplyContent(message: '子评论测试 $i'),
                  ),
                ),
              ),
            ),
      );
      await tester.tap(find.text('打开评论 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('共 3 条回复'));
      await tester.pumpAndSettle();
      final root = find.byKey(
        const ValueKey('thread-root-comment'),
        skipOffstage: false,
      );
      final before = tester.getTopLeft(root).dy;
      await tester.timedDrag(
        find.byType(CustomScrollView),
        const Offset(0, -240),
        const Duration(milliseconds: 650),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(root).dy, lessThan(before - 100));
      expect(video, 1);
      expect(find.byType(SingleChildScrollView), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('32 条评论'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reply preview and count open the thread, back preserves scroll',
    (tester) async {
      var video = 1;
      final requests = <(int, int, int)>[];
      await _pumpFeed(
        tester,
        initialPage: 1,
        onPageChanged: (value) => video = value,
        loadReplies: _loadWithThreads,
        loadThread:
            ({
              required isLogin,
              required oid,
              required root,
              required pageNum,
              required type,
              isCheck = false,
            }) {
              requests.add((oid, root, pageNum));
              return _loadThread(
                isLogin: isLogin,
                oid: oid,
                root: root,
                pageNum: pageNum,
                type: type,
              );
            },
      );
      await tester.tap(find.text('打开评论 1'));
      await tester.pumpAndSettle();
      final mainScroll =
          tester
                .widget<CustomScrollView>(find.byType(CustomScrollView))
                .controller!
            ..jumpTo(30);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('预览回复', findRichText: true));
      await tester.pumpAndSettle();
      expect(requests, [(123, 100, 1)]);
      expect(find.text('3 条回复'), findsOneWidget);
      expect(find.text('完整回复 100-3'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(video, 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('32 条评论'), findsOneWidget);
      expect(mainScroll.offset, 30);
      // Counts remain clickable even when there was no inline reply preview.
      await tester.tap(find.text('共 1 条回复'));
      await tester.pumpAndSettle();
      expect(requests.last, (123, 200, 1));
      expect(find.text('完整回复 200-1'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '评论'));
      await tester.pumpAndSettle();
      expect(find.text('32 条评论'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reply pagination deduplicates and network error can retry', (
    tester,
  ) async {
    var calls = 0;
    final pages = <int>[];
    await _pumpFeed(
      tester,
      loadReplies: _loadWithThreads,
      loadThread:
          ({
            required isLogin,
            required oid,
            required root,
            required pageNum,
            required type,
            isCheck = false,
          }) async {
            calls++;
            pages.add(pageNum);
            if (calls == 1) return const Error('回复加载失败');
            if (calls == 3) return const Error('下一页加载失败');
            final ids = pageNum == 1 ? List.generate(6, (i) => i + 1) : [6, 7];
            return Success(
              ReplyReplyData(
                page: ReplyPage(num: pageNum, size: 6, count: 7),
                replies: ids
                    .map(
                      (id) => ReplyItemModel(
                        rpid: id + 100,
                        root: 100,
                        content: ReplyContent(message: '分页回复 $id'),
                      ),
                    )
                    .toList(),
              ),
            );
          },
    );
    await tester.tap(find.text('打开评论 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('共 3 条回复'));
    await tester.pumpAndSettle();
    expect(find.text('回复加载失败'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    // Continuous pointer updates match touch input (the project's scroll
    // position patch consumes the first update to set its direction).
    await tester.timedDrag(
      find.byType(CustomScrollView),
      const Offset(0, -300),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(pages, [1, 1, 2]);
    final repliesScroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    expect(repliesScroll.offset, greaterThan(0));
    await tester.timedDrag(
      find.byType(CustomScrollView),
      const Offset(0, -200),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(pages, [1, 1, 2]);
    expect(find.text('加载失败，点击重试'), findsOneWidget);
    await tester.tap(find.text('加载失败，点击重试'));
    await tester.pumpAndSettle();
    await tester.timedDrag(
      find.byType(CustomScrollView),
      const Offset(0, -150),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(pages, [1, 1, 2, 2]);
    expect(find.text('分页回复 6'), findsOneWidget);
    expect(find.text('分页回复 7'), findsOneWidget);
    expect(find.text('没有更多了'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late reply request cannot overwrite a different thread', (
    tester,
  ) async {
    final pending = Completer<LoadingState<ReplyReplyData>>();
    await _pumpFeed(
      tester,
      loadReplies: _loadWithThreads,
      loadThread:
          ({
            required isLogin,
            required oid,
            required root,
            required pageNum,
            required type,
            isCheck = false,
          }) => root == 100
          ? pending.future
          : _loadThread(
              isLogin: isLogin,
              oid: oid,
              root: root,
              pageNum: pageNum,
              type: type,
            ),
    );
    await tester.tap(find.text('打开评论 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('共 3 条回复'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '评论'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('共 1 条回复'));
    await tester.pumpAndSettle();
    pending.complete(
      await _loadThread(
        isLogin: false,
        oid: 123,
        root: 100,
        pageNum: 1,
        type: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('完整回复 200-1'), findsOneWidget);
    expect(find.text('完整回复 100-1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'replying to a child sends its parent and root, retry keeps draft',
    (tester) async {
      _loginForTest();
      final sent = <(int?, int?, String)>[];
      await _pumpFeed(
        tester,
        loadReplies: _loadWithThreads,
        sendComment:
            ({
              required type,
              required oid,
              required message,
              root,
              parent,
            }) async {
              sent.add((root, parent, message));
              return sent.length == 1
                  ? const Error('发送失败，请重试')
                  : const Success(null);
            },
      );
      await tester.tap(find.text('打开评论 0'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '一级评论草稿');
      await tester.tap(find.text('共 3 条回复'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完整回复 100-2'));
      await tester.pumpAndSettle();
      expect(find.text('回复 @回复者2'), findsWidgets);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomRight(find.byTooltip('发送评论')).dy,
        lessThanOrEqualTo(544),
      );
      await tester.enterText(find.byType(TextField), '给指定回复者的内容');
      await tester.tap(find.byTooltip('发送评论'));
      await tester.pumpAndSettle();
      expect(sent.single, (100, 102, '给指定回复者的内容'));
      expect(find.text('发送失败，请重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '给指定回复者的内容',
      );
      await tester.tap(find.byTooltip('发送评论'));
      await tester.pumpAndSettle();
      expect(sent.length, 2);
      expect(sent.last, sent.first);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      await tester.tap(find.widgetWithText(TextButton, '评论'));
      await tester.pumpAndSettle();
      expect(find.text('33 条评论'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '一级评论草稿',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reply button targets the root and cancelling a child resets it',
    (tester) async {
      _loginForTest();
      final sent = <(int?, int?, String)>[];
      await _pumpFeed(
        tester,
        loadReplies: _loadWithThreads,
        sendComment:
            ({
              required type,
              required oid,
              required message,
              root,
              parent,
            }) async {
              sent.add((root, parent, message));
              return const Success(null);
            },
      );
      await tester.tap(find.text('打开评论 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '回复').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      expect(find.text('回复 @楼主'), findsOneWidget);
      await tester.tap(find.text('完整回复 100-1'));
      await tester.pumpAndSettle();
      expect(find.text('回复 @回复者1'), findsWidgets);
      await tester.tap(find.byTooltip('取消指定回复'));
      await tester.pumpAndSettle();
      expect(find.text('回复 @楼主'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '回复楼主');
      await tester.tap(find.byTooltip('发送评论'));
      await tester.pumpAndSettle();
      expect(sent.single, (100, 100, '回复楼主'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty thread stays open, guest cannot send a reply', (
    tester,
  ) async {
    var sends = 0;
    await _pumpFeed(
      tester,
      loadReplies: _loadWithThreads,
      loadThread:
          ({
            required isLogin,
            required oid,
            required root,
            required pageNum,
            required type,
            isCheck = false,
          }) async => Success(
            ReplyReplyData(
              page: ReplyPage(count: 0, size: 20, num: 1),
              replies: [],
            ),
          ),
      sendComment:
          ({
            required type,
            required oid,
            required message,
            root,
            parent,
          }) async {
            sends++;
            return const Success(null);
          },
    );
    await tester.tap(find.text('打开评论 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回复').first);
    await tester.pumpAndSettle();
    expect(find.text('还没有回复，来说两句吧'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '未登录回复');
    await tester.tap(find.byTooltip('发送评论'));
    await tester.pumpAndSettle();
    expect(sends, 0);
    expect(find.text('登录后才能发表评论'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭评论'));
    await tester.pumpAndSettle();
    expect(find.text('32 条评论'), findsNothing);
    expect(find.text('打开评论 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real video card comment icon and composer both open the panel', (
    tester,
  ) async {
    await _pumpFeed(tester, useVideoCard: true);
    expect(tester.takeException(), isNull);
    final commentPosition = tester.getCenter(
      find.byIcon(Icons.chat_bubble_rounded),
    );
    await tester.tapAt(commentPosition);
    // Once opened, the modal must intercept further taps at the same point.
    await tester.tapAt(commentPosition);
    await tester.pumpAndSettle();
    expect(find.text('评论内容 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭评论'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('留下你的精彩评论…'));
    await tester.pumpAndSettle();
    expect(find.text('评论内容 0'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opens and renders comments under the real material_ui app shell',
    (tester) async {
      await _pumpFeed(tester);
      await tester.tap(find.text('打开评论 0'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('32 条评论'), findsOneWidget);
      expect(find.text('评论内容 0'), findsOneWidget);
      expect(find.byTooltip('关闭评论'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);

      await tester.tap(find.byTooltip('关闭评论'));
      await tester.pumpAndSettle();
      expect(find.text('32 条评论'), findsNothing);

      await tester.tap(find.text('打开评论 0'));
      await tester.pumpAndSettle();
      expect(find.text('评论内容 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scrolling comments never changes the video; header drag dismisses',
    (tester) async {
      var video = 1;
      await _pumpFeed(
        tester,
        initialPage: 1,
        onPageChanged: (value) => video = value,
      );
      await tester.tap(find.text('打开评论 1'));
      await tester.pumpAndSettle();

      await tester.timedDrag(
        find.byType(CustomScrollView),
        const Offset(0, -380),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      expect(scroll.offset, greaterThan(0));
      expect(video, 1);
      expect(find.text('32 条评论'), findsOneWidget);
      await tester.timedDrag(
        find.byType(CustomScrollView),
        const Offset(0, 300),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      expect(video, 1);
      await tester.fling(find.text('32 条评论'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('32 条评论'), findsNothing);
      expect(video, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('barrier tap and Android back close only the sheet', (
    tester,
  ) async {
    var video = 0;
    await _pumpFeed(tester, onPageChanged: (value) => video = value);
    await tester.tap(find.text('打开评论 0'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 80));
    await tester.pumpAndSettle();
    expect(find.text('32 条评论'), findsNothing);

    await tester.tap(find.text('打开评论 0'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('32 条评论'), findsNothing);
    expect(find.text('打开评论 0'), findsOneWidget);
    expect(video, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending request remains dismissible and late result is harmless',
    (tester) async {
      final pending = Completer<LoadingState<ReplyData>>();
      await _pumpFeed(
        tester,
        loadReplies: ({
          required isLogin,
          required oid,
          required nextOffset,
          required type,
          required page,
          sort = 1,
        }) => pending.future,
      );
      await tester.tap(find.text('打开评论 0'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byTooltip('关闭评论'));
      await tester.pumpAndSettle();
      pending.complete(Success(ReplyData(replies: [])));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('打开评论 0'), findsOneWidget);
    },
  );

  testWidgets('error, retry, empty state, dark theme and keyboard render', (
    tester,
  ) async {
    var calls = 0;
    await _pumpFeed(
      tester,
      brightness: Brightness.dark,
      loadReplies:
          ({
            required isLogin,
            required oid,
            required nextOffset,
            required type,
            required page,
            sort = 1,
          }) async => ++calls == 1
          ? const Error('测试网络错误')
          : Success(ReplyData(replies: [])),
    );
    await tester.tap(find.text('打开评论 0'));
    await tester.pumpAndSettle();
    expect(find.text('测试网络错误'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('还没有评论，来抢沙发吧'), findsOneWidget);
    await tester.tap(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('发送评论'), findsOneWidget);
    final sendBottom = tester.getBottomRight(find.byTooltip('发送评论')).dy;
    expect(sendBottom, lessThanOrEqualTo(844 - 300));
  });
}
