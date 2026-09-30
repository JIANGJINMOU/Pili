import 'dart:async';

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/reply.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/models_new/reply/data.dart';
import 'package:PiliPlus/models_new/reply/reply.dart';
import 'package:PiliPlus/models_new/reply2reply/data.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
// Keep widgets, themes and MaterialLocalizations in the app's material_ui
// family. Flutter's material.dart uses different inherited/localization types.
import 'package:material_ui/material_ui.dart';

typedef ShortVideoReplyLoader = Future<LoadingState<ReplyData>> Function({
  required bool isLogin,
  required int oid,
  required String nextOffset,
  required int type,
  required int page,
  int sort,
});

typedef ShortVideoThreadLoader = Future<LoadingState<ReplyReplyData>> Function({
  required bool isLogin,
  required int oid,
  required int root,
  required int pageNum,
  required int type,
  bool isCheck,
});

typedef ShortVideoCommentSender = Future<LoadingState<void>> Function({
  required int type,
  required int oid,
  required String message,
  int? root,
  int? parent,
});

typedef ShortVideoCommentLiker = Future<LoadingState<void>> Function({
  required int type,
  required int oid,
  required int rpid,
  required int action,
});

Future<LoadingState<void>> _sendShortVideoComment({
  required int type,
  required int oid,
  required String message,
  int? root,
  int? parent,
}) async {
  final result = await VideoHttp.replyAdd(
    type: type,
    oid: oid,
    message: message,
    root: root,
    parent: parent,
  );
  return result.isSuccess ? const Success(null) : Error(result.toString());
}

Future<void> showShortVideoComments({
  required BuildContext context,
  required int aid,
  required int commentCount,
  required ValueChanged<int> onCountChanged,
  ShortVideoReplyLoader loadReplies = ReplyHttp.replyList,
  ShortVideoThreadLoader loadThread = ReplyHttp.replyReplyList,
  ShortVideoCommentSender sendComment = _sendShortVideoComment,
  ShortVideoCommentLiker likeComment = ReplyHttp.likeReply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    enableDrag: true,
    isDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.52),
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * 0.78,
      width: double.infinity,
      child: _ShortVideoCommentSheet(
        aid: aid,
        loadReplies: loadReplies,
        loadThread: loadThread,
        sendComment: sendComment,
        likeComment: likeComment,
        commentCount: commentCount,
        onClose: () => Navigator.of(sheetContext).pop(),
        onCountChanged: onCountChanged,
      ),
    ),
  );
}

class _ShortVideoCommentSheet extends StatefulWidget {
  const _ShortVideoCommentSheet({
    super.key,
    required this.aid,
    required this.loadReplies,
    required this.loadThread,
    required this.sendComment,
    required this.likeComment,
    this.pendingLikes,
    required this.commentCount,
    required this.onClose,
    required this.onCountChanged,
    this.root,
    this.onBack,
    this.onReplySent,
    this.onLikeChanged,
    this.focusComposer = false,
  });

  final int aid;
  final ShortVideoReplyLoader loadReplies;
  final ShortVideoThreadLoader loadThread;
  final ShortVideoCommentSender sendComment;
  final ShortVideoCommentLiker likeComment;
  final Set<int>? pendingLikes;
  final ReplyItemModel? root;
  final VoidCallback? onBack;
  final VoidCallback? onReplySent;
  final VoidCallback? onLikeChanged;
  final bool focusComposer;
  final int commentCount;
  final VoidCallback onClose;
  final ValueChanged<int> onCountChanged;

  @override
  State<_ShortVideoCommentSheet> createState() =>
      _ShortVideoCommentSheetState();
}

class _ShortVideoCommentSheetState extends State<_ShortVideoCommentSheet> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<ReplyItemModel> _comments = [];
  late final Set<int> _pendingLikes = widget.pendingLikes ?? <int>{};
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  bool _isEnd = false;
  String? _error;
  String _nextOffset = '';
  int _page = 1;
  int _sort = 1;
  late int _count = widget.commentCount;
  ReplyItemModel? _activeThread;
  ReplyItemModel? _replyTo;
  bool _focusThreadComposer = false;
  int _loadGeneration = 0;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_load(refresh: true));
    if (widget.focusComposer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_activeThread == null &&
        _error == null &&
        _scrollController.hasClients &&
        _scrollController.position.extentAfter < 320) {
      unawaited(_load());
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (!refresh && (_loading || _loadingMore || _isEnd)) {
      return;
    }
    final generation = refresh ? ++_loadGeneration : _loadGeneration;
    if (refresh) {
      _page = 1;
      _nextOffset = '';
      _isEnd = false;
      _error = null;
      setState(() {
        _loading = true;
        _loadingMore = false;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final List<ReplyItemModel> incoming;
      final int? total;
      final bool isEnd;
      String? nextOffset;
      final root = widget.root;
      if (root == null) {
        final result = await widget.loadReplies(
          isLogin: Accounts.main.isLogin,
          oid: widget.aid,
          nextOffset: _nextOffset,
          type: 1,
          page: _page,
          sort: _sort,
        );
        if (result case Success(:final response)) {
          incoming = [
            if (refresh) ...?response.topReplies,
            ...?response.replies,
          ];
          total = response.cursor?.allCount;
          nextOffset = response.cursor?.paginationReply?.nextOffset;
          isEnd = response.cursor?.isEnd ?? incoming.isEmpty;
        } else {
          throw result;
        }
      } else {
        final result = await widget.loadThread(
          isLogin: Accounts.main.isLogin,
          oid: widget.aid,
          root: root.rpid!,
          pageNum: _page,
          type: 1,
        );
        if (result case Success(:final response)) {
          incoming = response.replies ?? [];
          total = response.page?.count ?? response.root?.rcount;
          final size = response.page?.size ?? 20;
          isEnd =
              incoming.isEmpty ||
              (size > 0 && incoming.length < size) ||
              (total != null && _page * size >= total);
        } else {
          throw result;
        }
      }
      if (!mounted || generation != _loadGeneration) return;
      final known = refresh
          ? <int>{}
          : _comments.map((item) => item.rpid).whereType<int>().toSet();
      final unique = incoming.where((item) {
        final id = item.rpid;
        return id == null || known.add(id);
      });
      setState(() {
        if (refresh) _comments.clear();
        _comments.addAll(unique);
        _nextOffset = nextOffset ?? _nextOffset;
        _isEnd = isEnd;
        _page++;
        _loading = false;
        _loadingMore = false;
        _error = null;
        if (total != null) _count = total;
      });
      if (total != null) widget.onCountChanged(total);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  void _openThread(ReplyItemModel item, {bool compose = false}) {
    if (item.rpid == null || item.rpid! <= 0) return;
    _focusNode.unfocus();
    setState(() {
      _activeThread = item;
      _focusThreadComposer = compose;
    });
  }

  void _closeThread() {
    FocusScope.of(context).unfocus();
    setState(() => _activeThread = null);
  }

  void _selectReply(ReplyItemModel item) {
    if (_sending) return;
    if (widget.root == null) {
      _openThread(item, compose: true);
    } else if (item.rpid != null && item.rpid! > 0) {
      setState(() {
        _replyTo = item;
        _sendError = null;
      });
      _focusNode.requestFocus();
    }
  }

  Future<void> _toggleSort() async {
    HapticFeedback.selectionClick();
    setState(() => _sort = _sort == 1 ? 0 : 1);
    await _load(refresh: true);
  }

  Future<void> _toggleCommentLike(ReplyItemModel item) async {
    if (!Accounts.main.isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    final rpid = item.rpid;
    if (rpid == null || !_pendingLikes.add(rpid)) return;
    final wasLiked = item.action == 1;
    final oldAction = item.action;
    final oldLikes = item.like;
    setState(() {
      item.action = wasLiked ? 0 : 1;
      item.like = ((item.like ?? 0) + (wasLiked ? -1 : 1)).clamp(0, 1 << 31);
    });
    try {
      final result = await widget.likeComment(
        type: 1,
        oid: widget.aid,
        rpid: rpid,
        action: wasLiked ? 0 : 1,
      );
      if (!result.isSuccess) throw result;
    } catch (_) {
      // Restore exact values, including zero/null counts; do not apply a
      // second delta to a model shared between the main and reply sheets.
      item
        ..action = oldAction
        ..like = oldLikes;
      if (mounted) {
        setState(() {});
        SmartDialog.showToast('点赞失败，请重试');
      }
    } finally {
      _pendingLikes.remove(rpid);
      // The thread can have closed while the request was pending. Its root
      // model is shared with the parent, which still needs to repaint rollback.
      widget.onLikeChanged?.call();
    }
  }

  Future<void> _sendComment() async {
    if (_sending) return;
    if (!Accounts.main.isLogin) {
      setState(() => _sendError = '登录后才能发表评论');
      return;
    }
    final message = _textController.text.trim();
    if (message.isEmpty) return;
    FocusScope.of(context).unfocus();
    final target = _replyTo ?? widget.root;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final result = await widget.sendComment(
        type: 1,
        oid: widget.aid,
        message: message,
        root: widget.root?.rpid,
        parent: target?.rpid,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        _textController.clear();
        setState(() {
          _count++;
          _replyTo = null;
        });
        widget.onCountChanged(_count);
        widget.onReplySent?.call();
        await _load(refresh: true);
      } else {
        setState(() => _sendError = result.toString());
      }
    } catch (error) {
      if (mounted) setState(() => _sendError = '发送失败，请重试');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = _activeThread;
    return PopScope(
      canPop: thread == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _activeThread != null) _closeThread();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(offstage: thread != null, child: _buildSheet(context)),
          if (thread != null)
            _ShortVideoCommentSheet(
              key: ValueKey(thread.rpid),
              aid: widget.aid,
              root: thread,
              commentCount:
                  thread.rcount ?? thread.count ?? thread.replies?.length ?? 0,
              loadReplies: widget.loadReplies,
              loadThread: widget.loadThread,
              sendComment: widget.sendComment,
              likeComment: widget.likeComment,
              pendingLikes: _pendingLikes,
              onLikeChanged: () {
                if (mounted) setState(() {});
              },
              focusComposer: _focusThreadComposer,
              onBack: _closeThread,
              onClose: widget.onClose,
              onCountChanged: (count) {
                if (mounted) setState(() => thread.rcount = count);
              },
              onReplySent: () {
                if (!mounted) return;
                setState(() => _count++);
                widget.onCountChanged(_count);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 250) widget.onClose();
              },
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: TextButton.icon(
                        onPressed: widget.root == null
                            ? _toggleSort
                            : widget.onBack,
                        icon: Icon(
                          widget.root == null
                              ? Icons.swap_vert_rounded
                              : Icons.arrow_back_ios_new_rounded,
                          size: 17,
                        ),
                        label: Text(
                          widget.root == null
                              ? (_sort == 1 ? '热门' : '最新')
                              : '评论',
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.root != null
                            ? '${NumUtils.numFormat(_count)} 条回复'
                            : (_count > 0
                                  ? '${NumUtils.numFormat(_count)} 条评论'
                                  : '评论'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: '关闭评论',
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            Expanded(child: _buildCommentBody(colorScheme)),
            Divider(height: 1, color: colorScheme.outlineVariant),
            _buildComposer(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentBody(ColorScheme colorScheme) {
    final hasRows = !_loading && _comments.isNotEmpty;
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (widget.root case final root?)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  key: const ValueKey('thread-root-comment'),
                  children: [
                    _ShortCommentTile(
                      item: root,
                      onLike: () => _toggleCommentLike(root),
                      onReply: () => _selectReply(root),
                    ),
                    Divider(height: 1, color: colorScheme.outlineVariant),
                  ],
                ),
              ),
            ),
          if (!hasRows)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildListBody(colorScheme),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              sliver: SliverList.builder(
                itemCount: _comments.length + 1,
                itemBuilder: (context, index) =>
                    _buildCommentRow(colorScheme, index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListBody(ColorScheme colorScheme) {
    if (_loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 32,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_error != null && _comments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 44, color: colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                _error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: () => _load(refresh: true),
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
    }
    if (_comments.isEmpty) {
      return Center(
        child: Text(
          widget.root == null ? '还没有评论，来抢沙发吧' : '还没有回复，来说两句吧',
          style: TextStyle(color: colorScheme.outline),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCommentRow(ColorScheme colorScheme, int index) {
    if (index == _comments.length) {
      return InkWell(
        onTap: _error == null ? null : _load,
        child: SizedBox(
          height: 54,
          child: Center(
            child: _loadingMore
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _error != null
                        ? '加载失败，点击重试'
                        : (_isEnd ? '没有更多了' : '继续上滑加载'),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.outline,
                    ),
                  ),
          ),
        ),
      );
    }
    return _ShortCommentTile(
      item: _comments[index],
      onLike: () => _toggleCommentLike(_comments[index]),
      onReply: () => _selectReply(_comments[index]),
      onOpenThread: widget.root == null
          ? () => _openThread(_comments[index])
          : null,
    );
  }

  Widget _buildComposer(ColorScheme colorScheme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_replyTo != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '回复 @${_replyTo!.member?.uname ?? '用户'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.primary),
                    ),
                  ),
                  IconButton(
                    tooltip: '取消指定回复',
                    onPressed: _sending
                        ? null
                        : () => setState(() => _replyTo = null),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            if (_sendError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _sendError!,
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 3,
                    enabled: !_sending,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendComment(),
                    decoration: InputDecoration(
                      hintText: !Accounts.main.isLogin
                          ? '登录后参与评论'
                          : widget.root == null
                          ? '留下你的精彩评论…'
                          : '回复 @${(_replyTo ?? widget.root)!.member?.uname ?? '用户'}',
                      isDense: true,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                IconButton.filled(
                  tooltip: '发送评论',
                  onPressed: _sending ? null : _sendComment,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6699),
                    foregroundColor: Colors.white,
                  ),
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortCommentTile extends StatelessWidget {
  const _ShortCommentTile({
    required this.item,
    required this.onLike,
    required this.onReply,
    this.onOpenThread,
  });

  final ReplyItemModel item;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback? onOpenThread;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final member = item.member;
    final replies = item.replies ?? const <ReplyItemModel>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              final mid = member?.mid;
              if (mid != null) Get.toNamed('/member?mid=$mid');
            },
            child: ClipOval(
              child: NetworkImgLayer(
                src: member?.avatar,
                width: 38,
                height: 38,
                type: ImageType.avatar,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member?.uname ?? '用户',
                  style: TextStyle(
                    color: colorScheme.outline,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: item.rpid == null ? null : onReply,
                  child: Text(
                    item.content?.message ?? '',
                    style: const TextStyle(fontSize: 15, height: 1.35),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  [item.replyControl?.timeDesc, item.replyControl?.location]
                      .whereType<String>()
                      .where((value) => value.isNotEmpty)
                      .join('  '),
                  style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
                ),
                TextButton(
                  onPressed: item.rpid == null ? null : onReply,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 32),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    alignment: Alignment.centerLeft,
                  ),
                  child: const Text('回复'),
                ),
                if (onOpenThread != null &&
                    (replies.isNotEmpty ||
                        (item.rcount ?? item.count ?? 0) > 0)) ...[
                  const SizedBox(height: 7),
                  InkWell(
                    onTap: onOpenThread,
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final reply in replies.take(2))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${reply.member?.uname ?? '用户'}：',
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    TextSpan(
                                      text: reply.content?.message ?? '',
                                    ),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '共 ${item.rcount ?? item.count ?? replies.length} 条回复',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          InkResponse(
            onTap: onLike,
            radius: 24,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              child: Column(
                children: [
                  Icon(
                    item.action == 1
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 20,
                    color: item.action == 1
                        ? const Color(0xFFFF6699)
                        : colorScheme.outline,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    NumUtils.numFormat(item.like ?? 0),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
