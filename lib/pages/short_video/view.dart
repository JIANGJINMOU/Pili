import 'package:PiliPlus/pages/short_video/progress_bar.dart';

import 'dart:async';

import 'package:PiliPlus/pages/short_video/launch.dart';
import 'package:PiliPlus/pages/short_video/system_ui.dart';

import 'package:PiliPlus/pages/short_video/comment_layout.dart';

import 'package:PiliPlus/pages/short_video/subtitles.dart';

import 'package:PiliPlus/pages/short_video/danmaku.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:PiliPlus/pages/short_video/preload_scheduler.dart';
import 'package:PiliPlus/pages/short_video/player_pool.dart';
import 'package:PiliPlus/pages/short_video/recommendation/watch_session.dart';

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/reply.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/pages/short_video/comment_sheet.dart';
import 'package:PiliPlus/pages/short_video/controller.dart';
import 'package:PiliPlus/pages/short_video/pager.dart';
import 'package:PiliPlus/pages/short_video/player.dart';
import 'package:PiliPlus/pages/setting/widgets/fixed_speed_setting.dart';
import 'package:PiliPlus/utils/fixed_playback_speed.dart';
import 'package:PiliPlus/common/widgets/flutter/popup_menu.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/pages/short_video/preferences.dart';
import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/setting/common_setting.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class ShortVideoPage extends StatefulWidget {
  const ShortVideoPage({
    super.key,
    this.playerFactory = createShortVideoPlayer,
    this.networkAllowed,
    this.initialLaunch,
  });
  final ShortVideoPlayerFactory playerFactory;
  final Future<bool> Function()? networkAllowed;
  final ShortVideoLaunch? initialLaunch;

  @override
  State<ShortVideoPage> createState() => _ShortVideoPageState();
}

class _ShortVideoPageState extends State<ShortVideoPage>
    with WidgetsBindingObserver {
  late final ShortVideoController _controller;
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _appActive =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool _muted = false;
  late ShortVideoPreferences _preferences;
  StreamSubscription<dynamic>? _settingsSubscription;
  bool _scrolling = false;
  bool _settingsOpen = false;
  bool _advancing = false;
  bool _overlayOpen = false;
  int _settledIndex = 0;
  int? _preloadIndex;
  late final ShortVideoPreloadScheduler _preloader;
  final _playerPool = ShortVideoPlayerPool();
  int _failures = 0;
  bool _rebasing = false;
  Worker? _launchWorker;

  bool get _preloadAllowed =>
      _preferences.enabled &&
      _preferences.preload &&
      _failures == 0 &&
      _appActive &&
      !_settingsOpen &&
      !_overlayOpen;

  bool get _mayPreload => _preloadAllowed && !_scrolling;

  void _schedulePreload({bool preserveAuthorized = false}) {
    _preloader.cancel();
    if (preserveAuthorized &&
        _preloadAllowed &&
        _preloadIndex == _currentIndex + 1) {
      return;
    }
    if (mounted && _preloadIndex != null) {
      setState(() => _preloadIndex = null);
    }
    if (_mayPreload) _preloader.schedule(_currentIndex);
  }

  Future<bool> _networkAllowed() async {
    if (widget.networkAllowed case final check?) return check();
    final networks = await Connectivity().checkConnectivity();
    return networks.contains(ConnectivityResult.wifi) ||
        networks.contains(ConnectivityResult.ethernet) ||
        (_preferences.cellularPreload &&
            networks.contains(ConnectivityResult.mobile));
  }

  void _playbackFailed(int index) {
    if (!mounted || index != _currentIndex) return;
    // Never skip the current video just because the network is unavailable.
    _preloader.cancel();
    setState(() {
      _failures = 1;
      _preloadIndex = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _preferences = ShortVideoPreferences.read();
    _muted = _preferences.muted;
    _preloader = ShortVideoPreloadScheduler((index) {
      if (mounted && _mayPreload && index == _currentIndex) {
        setState(() => _preloadIndex = index + 1);
      }
    }, networkAllowed: _networkAllowed);
    if (_preferences.preload && _preferences.enabled) _preloader.schedule(0);
    final args = Get.arguments;
    _controller = Get.put(
      ShortVideoController(
        preferences: _preferences,
        initialLaunch:
            widget.initialLaunch ?? (args is ShortVideoLaunch ? args : null),
      ),
    );
    _launchWorker = ever(_controller.launchRevision, (_) {
      if (!mounted) return;
      _preloader.cancel();
      setState(() {
        _currentIndex = _settledIndex = 0;
        _preloadIndex = null;
        _scrolling = _overlayOpen = false;
        _failures = 0;
      });
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      _schedulePreload();
      WidgetsBinding.instance.addPostFrameCallback((_) => _applySystemBars());
    });
    _settingsSubscription = GStorage.setting.watch().listen((event) {
      if (!mounted || !event.key.toString().startsWith('shortVideo')) return;
      final previous = _preferences;
      setState(() {
        _preferences = ShortVideoPreferences.read();
        if (!_preferences.enabled) {
          _scrolling = false;
          _overlayOpen = false;
        }
        if (previous.muted != _preferences.muted) _muted = _preferences.muted;
      });
      _controller.preferences = _preferences;
      if (previous.showStatusBar != _preferences.showStatusBar) {
        _applySystemBars();
      }
      if (_preferences.enabled &&
          !previous.enabled &&
          _controller.items.isEmpty) {
        unawaited(_controller.refreshFeed());
      } else if (previous.onlyVertical != _preferences.onlyVertical) {
        _controller.items.clear();
        unawaited(_refresh());
      }
      _schedulePreload();
    });
    WidgetsBinding.instance.addObserver(this);
    if (PlatformUtils.isMobile) {
      portraitUpMode();
      WidgetsBinding.instance.addPostFrameCallback((_) => _applySystemBars());
    }
  }

  void _applySystemBars() {
    if (mounted &&
        PlatformUtils.isMobile &&
        !_settingsOpen &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(applyShortVideoSystemBars(_preferences.showStatusBar));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active) _applySystemBars();
    if (active != _appActive && mounted) {
      setState(() => _appActive = active);
      _schedulePreload();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settingsSubscription?.cancel();
    _launchWorker?.dispose();
    _preloader.dispose();
    _pageController.dispose();
    Get.delete<ShortVideoController>();
    if (PlatformUtils.isMobile) {
      showSystemBar();
      fullMode();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    _failures = 0;
    _preloader.cancel();
    if (mounted) {
      setState(() {
        _currentIndex = 0;
        _settledIndex = 0;
        _preloadIndex = null;
        _scrolling = false;
      });
    }
    if (_pageController.hasClients) _pageController.jumpToPage(0);
    await _controller.refreshFeed();
    if (mounted) _schedulePreload();
  }

  Future<void> _goToNext(int index) async {
    if (_advancing ||
        _overlayOpen ||
        _scrolling ||
        _settingsOpen ||
        !_appActive ||
        !_preferences.enabled ||
        index != _currentIndex) {
      return;
    }
    _advancing = true;
    try {
      if (index + 1 >= _controller.items.length) await _controller.loadMore();
      if (!mounted ||
          _overlayOpen ||
          _scrolling ||
          _settingsOpen ||
          !_appActive ||
          !_preferences.enabled ||
          index != _currentIndex) {
        return;
      }
      if (index + 1 < _controller.items.length && _pageController.hasClients) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _pageController.jumpToPage(index + 1);
        } else {
          await _pageController.animateToPage(
            index + 1,
            duration: Duration(
              milliseconds:
                  _preferences.swipeStyle == ShortVideoSwipeStyle.quick
                  ? 220
                  : 320,
            ),
            curve: Curves.easeOutCubic,
          );
        }
      } else {
        SmartDialog.showToast('暂时没有更多视频');
      }
    } finally {
      _advancing = false;
    }
  }

  void _toggleMuted() {
    if (_preferences.haptics) HapticFeedback.selectionClick();
    setState(() => _muted = !_muted);
  }

  Future<void> _openSettings() async {
    if (_settingsOpen) return;
    setState(() => _settingsOpen = true);
    _schedulePreload();
    try {
      await Get.to(
        () => const CommonSetting(settingType: SettingType.shortVideoSetting),
      );
    } finally {
      if (mounted) {
        setState(() => _settingsOpen = false);
        _schedulePreload();
        _applySystemBars();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_preferences.enabled) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('竖屏视频')),
        body: _CenteredStatus(
          icon: Icons.smart_display_outlined,
          message: '竖屏视频已关闭',
          actionText: '竖屏设置',
          onAction: _openSettings,
        ),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Obx(() {
          if (_controller.items.isEmpty) {
            final loading = _controller.isInitialLoading.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                _CenteredStatus(
                  icon: loading
                      ? Icons.smart_display_rounded
                      : Icons.cloud_off_rounded,
                  message: loading
                      ? '正在准备竖屏视频…'
                      : (_controller.errorMessage.value ?? '加载失败'),
                  loading: loading,
                  actionText: loading ? null : '重试',
                  onAction: loading ? null : _refresh,
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 4,
                  left: 8,
                  child: _PortraitBackButton(onPressed: Get.back),
                ),
              ],
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              ShortVideoPager(
                key: ValueKey(_controller.launchRevision.value),
                controller: _pageController,
                style: _preferences.swipeStyle,
                scrollEnabled: !_overlayOpen && !_settingsOpen,
                itemCount: _controller.items.length,
                itemKey: (index) => ValueKey(_controller.items[index].aid),
                findChildIndexCallback: (key) {
                  final index = _controller.items.indexWhere(
                    (item) => ValueKey(item.aid) == key,
                  );
                  return index < 0 ? null : index;
                },
                onScrollingChanged: (scrolling) {
                  if (mounted && scrolling != _scrolling) {
                    setState(() => _scrolling = scrolling);
                    // Stop new speculative work, but do not revoke an already
                    // authorized next-player preparation halfway through open().
                    if (scrolling) _preloader.cancel();
                  }
                },
                onSettled: (index) {
                  if (!mounted || _rebasing) return;
                  if (_settledIndex != index) {
                    if (_preferences.haptics) HapticFeedback.selectionClick();
                    _controller.onPageChanged(index);
                  }
                  setState(() {
                    _settledIndex = index;
                    _currentIndex = index;
                  });
                  _rebasing = true;
                  final removed = _controller.trimBefore(index);
                  if (removed > 0 && _pageController.hasClients) {
                    _currentIndex = index - removed;
                    _settledIndex = _currentIndex;
                    _pageController.jumpToPage(_currentIndex);
                    setState(() {});
                  }
                  _rebasing = false;
                  _schedulePreload(preserveAuthorized: true);
                },
                // Crossing the halfway point isn't a committed video change.
                // Keep ownership stable until the gesture/settling has finished.
                onPageChanged: (_) {},
                itemBuilder: (context, index) {
                  final item = _controller.items[index];
                  return ShortVideoItem(
                    key: ValueKey(item.aid ?? item.bvid),
                    item: item,
                    controller: _controller,
                    playerFactory: widget.playerFactory,
                    playerPool: _playerPool,
                    current: index == _currentIndex,
                    scrolling: _scrolling,
                    onPlaybackError: () => _playbackFailed(index),
                    onPlaybackReady: () {
                      if (mounted && index == _currentIndex) {
                        _failures = 0;
                        // A small first batch must not strand the user on one
                        // looping video. Refill only after playback is ready.
                        if (_controller.items.length - index < 6) {
                          unawaited(_controller.loadMore());
                        }
                      }
                    },
                    active:
                        index == _currentIndex && _appActive && !_settingsOpen,
                    preload:
                        _preloadAllowed &&
                        index == _preloadIndex &&
                        index == _currentIndex + 1,
                    // Losing focus (notification shade, lock screen) must pause,
                    // not destroy the current session and reset its position.
                    retain:
                        index == _currentIndex ||
                        ((index - _currentIndex).abs() <= 1 && _appActive),
                    preferences: _preferences,
                    muted: _muted,
                    onToggleMuted: _toggleMuted,
                    onRefresh: _refresh,
                    onNext: () => _goToNext(index),
                    onSettings: _openSettings,
                    onPanelChanged: (open) {
                      if (mounted && open != _overlayOpen) {
                        setState(() => _overlayOpen = open);
                        _schedulePreload();
                      }
                    },
                  );
                },
              ),
              if (_controller.isLoadingMore.value)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 58,
                  left: 0,
                  right: 0,
                  child: const Center(
                    child: _FeedStatusChip(
                      icon: Icons.downloading_rounded,
                      label: '正在加载更多',
                    ),
                  ),
                )
              else if (_controller.loadMoreError.value != null)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 58,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _FeedStatusChip(
                      icon: Icons.refresh_rounded,
                      label: _controller.loadMoreError.value!,
                      onTap: _controller.loadMore,
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class ShortVideoItem extends StatefulWidget {
  const ShortVideoItem({
    super.key,
    required this.item,
    required this.controller,
    required this.active,
    required this.preload,
    required this.muted,
    required this.onToggleMuted,
    required this.onRefresh,
    required this.onNext,
    this.onSettings,
    this.onPanelChanged,
    this.retain = false,
    this.playerPool,
    this.current = true,
    this.scrolling = false,
    this.onPlaybackError,
    this.onPlaybackReady,
    this.preferences = const ShortVideoPreferences(),
    this.loadReplies = ReplyHttp.replyList,
    this.playerFactory = createShortVideoPlayer,
  });

  final BaseRcmdVideoItemModel item;
  final ShortVideoController controller;
  final bool active;
  final bool preload;
  final bool muted;
  final VoidCallback onToggleMuted;
  final VoidCallback onRefresh;
  final VoidCallback onNext;
  final ShortVideoReplyLoader loadReplies;
  final VoidCallback? onSettings;
  final ValueChanged<bool>? onPanelChanged;
  final bool retain;
  final ShortVideoPlayerPool? playerPool;
  final bool current;
  final bool scrolling;
  final VoidCallback? onPlaybackError;
  final VoidCallback? onPlaybackReady;
  final ShortVideoPreferences preferences;
  final ShortVideoPlayerFactory playerFactory;

  @override
  State<ShortVideoItem> createState() => _ShortVideoItemState();
}

enum _ShortVideoPanel { none, coin }

class _ShortVideoItemState extends State<ShortVideoItem>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Player? _player;
  ShortVideoWatchSession _watch = ShortVideoWatchSession();
  bool _exposed = false;
  int _profileRevision = -1;
  bool _completionHandled = false;
  bool _reportedError = false;
  Timer? _retryTimer, _stallTimer, _errorConfirmationTimer;
  String? _pendingPlaybackError;
  Duration _healthyProgress = Duration.zero;
  bool _retrying = false;
  int _retryAttempts = 0;
  Duration _resumePosition = Duration.zero;
  int? _resumeQuality;

  void _cancelRecoveryTimers() {
    _errorConfirmationTimer?.cancel();
    _errorConfirmationTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  void _scheduleRecovery() {
    if (!mounted ||
        !_canPlay ||
        _error == null ||
        _retrying ||
        _retryTimer != null ||
        _retryAttempts >= 3) {
      return;
    }
    _retryTimer = Timer(Duration(seconds: 1 << _retryAttempts), () {
      _retryTimer = null;
      if (mounted && _canPlay && _error != null) {
        unawaited(_retry(automatic: true));
      }
    });
  }

  void _updateRecoveryTimers() {
    if (!_canPlay) {
      _cancelRecoveryTimers();
      return;
    }
    if (_pendingPlaybackError != null && _error == null && !_loading) {
      _errorConfirmationTimer ??= Timer(const Duration(seconds: 3), () {
        _errorConfirmationTimer = null;
        if (!mounted || !_canPlay || _pendingPlaybackError == null) return;
        _setState(() => _error = _pendingPlaybackError);
        _pendingPlaybackError = null;
        _reportError();
      });
    }
    if (_error != null) _scheduleRecovery();
    if (_buffering && !_loading && !_retrying && _retryAttempts < 3) {
      _stallTimer ??= Timer(const Duration(seconds: 12), () {
        _stallTimer = null;
        if (mounted && _canPlay && _buffering) {
          _setState(() => _error = '网络缓冲超时，请稍候或重新加载');
          _reportError();
        }
      });
    } else {
      _stallTimer?.cancel();
      _stallTimer = null;
    }
  }

  Future<void> _disposePlayer(Player player) async {
    try {
      await (widget.playerPool?.release(player) ?? player.dispose());
    } catch (error, stack) {
      logger.w('short-video disposal', error: error, stackTrace: stack);
    }
  }

  void _trackWatch() {
    if (_profileRevision != widget.controller.profileRevision) {
      _profileRevision = widget.controller.profileRevision;
      _watch = ShortVideoWatchSession();
      _exposed = false;
    }
    final watching =
        _canPlay &&
        _playing &&
        !_buffering &&
        (_videoController == null || _firstFrameReady) &&
        !_speedMenuOpen &&
        !_scrubbing &&
        !_commentsOpen &&
        _panel == _ShortVideoPanel.none;
    if (_watch.closed && watching) _watch = ShortVideoWatchSession();
    _watch.playing(
      watching && widget.preferences.personalized,
      rate: _speeding ? _longPressRate : _baseRate,
    );
    if (watching && !_exposed && !_watch.failed) {
      _exposed = true;
      widget.controller.recordExposure(widget.item);
      widget.onPlaybackReady?.call();
    }
  }

  void _settleWatch({bool completed = false, bool leaving = false}) {
    final delta = _watch.settle(
      duration: _duration > Duration.zero
          ? _duration
          : Duration(seconds: widget.item.duration.clamp(0, 86400)),
      completed: completed,
      leaving: leaving,
    );
    widget.controller.recordWeight(
      widget.item,
      delta,
      revision: _profileRevision,
    );
  }

  void _feedback(ShortVideoFeedback feedback, {bool enabled = true}) {
    if (!widget.preferences.personalized) return;
    widget.controller.recordWeight(
      widget.item,
      _watch.feedback(feedback, enabled: enabled),
      revision: _profileRevision,
    );
  }

  void _reportError() {
    _healthyProgress = Duration.zero;
    _scheduleRecovery();
    _watch.failed = true;
    _watch.playing(false);
    if (widget.active && !_reportedError) {
      _reportedError = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active && _error != null) {
          widget.onPlaybackError?.call();
        }
      });
    }
  }

  VideoController? _videoController;
  ShortVideoSource? _source;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(
    Duration.zero,
  );
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _loading = false;
  bool _liked = false;
  bool _likeBusy = false;
  bool _isCoined = false;
  int _userCoinCount = 0;
  bool _coinBusy = false;
  bool _isFavorited = false;
  bool _favoriteBusy = false;
  bool _isFollowing = false;
  bool _followBusy = false;
  late bool _cleanScreen = widget.preferences.cleanScreen;
  late bool _subtitlesEnabled = widget.preferences.subtitlesEnabled;

  bool _qualityBusy = false;
  bool _scrubbing = false;
  late bool _danmakuEnabled =
      GStorage.setting.get(
        SettingBoxKey.shortVideoDanmaku,
        defaultValue: false,
      ) ==
      true;
  int? _selectedQuality;
  bool _speeding = false;
  bool _speedMenuOpen = false;
  double _temporaryRate = 1;
  double get _baseRate => widget.preferences.fixedSpeed.enabled
      ? widget.preferences.fixedSpeed.rate
      : _temporaryRate;
  double get _longPressRate => _baseRate < 2 ? 2 : _baseRate;
  String? _error;
  int _generation = 0;
  Future<void>? _prepareFuture;
  bool _metadataLoaded = false;
  int _viewCount = 0;
  int _likeCount = 0;
  int _coinCount = 0;
  int _replyCount = 0;
  int _favoriteCount = 0;
  int _shareCount = 0;
  int? _authorMid;
  String? _authorName;
  String? _authorFace;
  _ShortVideoPanel _panel = _ShortVideoPanel.none;
  bool _commentsOpen = false;
  late final AnimationController _commentAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 220),
  );
  final ValueNotifier<double> _commentExtent = ValueNotifier(.5);
  bool _firstFrameReady = false;
  bool _userPaused = false;
  bool _routeCovered = false;
  int _playbackRevision = 0;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _canPlay =>
      widget.active &&
      _foreground &&
      !_userPaused &&
      !_routeCovered &&
      !_qualityBusy;

  String get _bvid => widget.item.bvid ?? IdUtils.av2bv(widget.item.aid!);

  @override
  void initState() {
    super.initState();
    _viewCount = widget.item.stat.view ?? 0;
    _likeCount = widget.item.stat.like ?? 0;
    _replyCount = widget.item.stat.danmu ?? 0;
    _authorMid = widget.item.owner.mid;
    _authorName = widget.item.owner.name;
    _isFollowing = widget.item.isFollowed;
    _resumePosition = widget.controller.takeInitialPosition(widget.item);
    _userPaused = !widget.preferences.autoPlay;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_syncPlayback());
  }

  @override
  void didUpdateWidget(covariant ShortVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences.personalized != widget.preferences.personalized) {
      _watch = ShortVideoWatchSession();
    }
    _danmakuEnabled = widget.preferences.danmakuEnabled;
    _subtitlesEnabled = widget.preferences.subtitlesEnabled;
    if (oldWidget.preferences.cleanScreen != widget.preferences.cleanScreen) {
      _cleanScreen = widget.preferences.cleanScreen;
    }
    _trackWatch();
    if (!widget.current && !widget.scrolling) {
      _settleWatch(leaving: true);
    } else if (!widget.active) {
      _settleWatch();
    }
    if (widget.active && _error != null) _reportError();
    if (oldWidget.preferences.fixedSpeed.enabled &&
        !widget.preferences.fixedSpeed.enabled) {
      _temporaryRate = 1;
    }
    if (oldWidget.preferences.autoPlay != widget.preferences.autoPlay) {
      _userPaused = !widget.preferences.autoPlay;
    }
    if (oldWidget.active != widget.active ||
        oldWidget.preload != widget.preload ||
        oldWidget.retain != widget.retain ||
        oldWidget.muted != widget.muted ||
        oldWidget.preferences.autoPlay != widget.preferences.autoPlay ||
        oldWidget.preferences.playbackRate != widget.preferences.playbackRate ||
        oldWidget.preferences.fixedSpeed.enabled !=
            widget.preferences.fixedSpeed.enabled) {
      unawaited(_syncPlayback());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    _trackWatch();
    if (!foreground) _settleWatch();
    // Pause immediately: in paused/hidden state Flutter may not build a frame,
    // so waiting for the parent's next rebuild could leave audio running.
    unawaited(_syncPlayback());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelRecoveryTimers();
    _generation++;
    _playbackRevision++;
    _disposeSubscriptions();
    _watch.playing(false);
    _settleWatch();
    if (_player case final player?) unawaited(_disposePlayer(player));
    _commentAnimation.dispose();
    _commentExtent.dispose();
    _positionNotifier.dispose();
    super.dispose();
  }

  Future<void> _syncPlayback() async {
    _updateRecoveryTimers();
    _trackWatch();
    final revision = ++_playbackRevision;
    try {
      if (!widget.active && !widget.preload && !widget.retain) {
        await _releasePlayer();
        return;
      }
      if (_foreground && (widget.active || widget.preload)) {
        await _ensurePrepared();
      }
      if (!mounted || revision != _playbackRevision) return;
      final player = _player;
      if (player == null) return;
      final play = _canPlay;
      if (!play && _speeding) _setState(() => _speeding = false);
      await player.setVolume(play && !widget.muted ? 100 : 0);
      if (!mounted || revision != _playbackRevision || player != _player) {
        return;
      }
      await player.setRate(
        _speeding ? _longPressRate : _baseRate,
      );
      if (!mounted || revision != _playbackRevision || player != _player) {
        return;
      }
      if (play) {
        await player.play();
      } else {
        await player.pause();
      }
      if (mounted && widget.active && _foreground) _loadMetadataOnce();
    } catch (error) {
      if (mounted && revision == _playbackRevision) {
        _setState(() {
          _loading = false;
          _error = '播放失败，请重试';
        });
        _reportError();
      }
    }
  }

  Future<void> _ensurePrepared() async {
    // Wait for open() even when a controller is already attached. Calling play
    // on a half-initialized preloaded player caused intermittent blank frames.
    if (_prepareFuture case final pending?) return pending;
    if (_player != null) return;
    late final Future<void> future;
    future = _preparePlayer().whenComplete(() {
      if (identical(_prepareFuture, future)) _prepareFuture = null;
    });
    _prepareFuture = future;
    await future;
  }

  Future<void> _preparePlayer() async {
    final generation = ++_generation;
    Player? ownedPlayer;
    var attached = false;
    if (widget.active) {
      _setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final source = await widget.controller
          .sourceFor(widget.item)
          .timeout(const Duration(seconds: 20));
      if (!_mayPrepare(generation)) return;
      if (widget.preferences.onlyVertical &&
          !source.isVertical &&
          !widget.controller.isExplicitVideo(widget.item)) {
        throw StateError('该视频不是竖向视频');
      }
      final handle = widget.playerPool == null
          ? await widget.playerFactory()
          : await widget.playerPool!.acquire(
              widget.playerFactory,
              () => _mayPrepare(generation),
            );
      if (handle == null) return;
      final player = handle.player;
      ownedPlayer = player;
      if (!_mayPrepare(generation)) {
        await _disposePlayer(player);
        return;
      }
      _watch = ShortVideoWatchSession();
      _reportedError = false;
      final videoController = handle.video;
      player.setMediaHeader(
        userAgent: BrowserUa.pc,
        referer: HttpString.baseUrl,
      );
      _player = player;
      attached = true;
      _videoController = videoController;
      _source = source;
      _selectedQuality = source.qualityUrls.containsKey(_resumeQuality)
          ? _resumeQuality
          : source.quality;
      _listenTo(player);
      _setState(() => _firstFrameReady = false);
      if (videoController != null) {
        unawaited(
          videoController.waitUntilFirstFrameRendered
              .then<void>((_) {
                if (_shouldKeepPlayer(generation) &&
                    identical(_player, player)) {
                  _setState(() => _firstFrameReady = true);
                  _trackWatch();
                }
              })
              .catchError((Object _) {}),
        );
      }
      await player.setVolume(0);
      await player
          .open(
            Media(
              source.qualityUrls[_selectedQuality] ?? source.url,
              extras: const {
                'cache': 'yes',
                'cache-secs': '6',
                'demuxer-max-bytes': '33554432',
              },
            ),
            play: false,
          )
          .timeout(const Duration(seconds: 20));
      if (!_shouldKeepPlayer(generation)) return;
      if (_resumePosition > Duration.zero) {
        await player.seek(_resumePosition);
        if (!_shouldKeepPlayer(generation)) return;
        _positionNotifier.value = _resumePosition;
        _resumePosition = Duration.zero;
      }
      _setState(() => _loading = false);
      _updateRecoveryTimers();
    } catch (error) {
      if (!mounted || generation != _generation) {
        if (!attached && ownedPlayer != null) await _disposePlayer(ownedPlayer);
        return;
      }
      _disposeSubscriptions();
      _player = null;
      _videoController = null;
      _source = null;
      if (ownedPlayer != null) await _disposePlayer(ownedPlayer);
      if (!mounted || generation != _generation) return;
      _setState(() {
        _loading = false;
        _buffering = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
      _reportError();
    }
  }

  bool _mayPrepare(int generation) =>
      mounted &&
      _foreground &&
      (widget.active || widget.preload) &&
      generation == _generation;

  bool _shouldKeepPlayer(int generation) =>
      mounted &&
      (widget.active || widget.preload || widget.retain) &&
      generation == _generation;

  void _loadMetadataOnce() {
    if (_metadataLoaded) return;
    _metadataLoaded = true;
    unawaited(
      _loadMetadata().catchError((Object error, StackTrace stack) {
        _metadataLoaded = false;
        logger.w('short-video metadata', error: error, stackTrace: stack);
      }),
    );
  }

  void _listenTo(Player player) {
    _disposeSubscriptions();
    _subscriptions.addAll([
      player.stream.playing.listen(
        (value) {
          if (!mounted || !identical(player, _player)) return;
          if (value != _playing) _setState(() => _playing = value);
          _trackWatch();
        },
      ),
      player.stream.buffering.listen(
        (value) {
          if (!mounted || !identical(player, _player)) return;
          if (value != _buffering) _setState(() => _buffering = value);
          _updateRecoveryTimers();
          _trackWatch();
        },
      ),
      player.stream.position.listen(
        (value) {
          if (!mounted || !identical(player, _player)) return;
          final delta = value - _positionNotifier.value;
          _positionNotifier.value = value;
          // Native error/buffering events can describe a recovered CDN request.
          // Actual forward playback wins; seeks do not reset the retry budget.
          if (_canPlay &&
              !_loading &&
              !_qualityBusy &&
              delta > Duration.zero &&
              delta <= const Duration(seconds: 2)) {
            _healthyProgress += delta;
            if (_buffering) _setState(() => _buffering = false);
            _pendingPlaybackError = null;
            _cancelRecoveryTimers();
            if (_error != null) {
              _setState(() => _error = null);
              _watch.failed = false;
              _reportedError = false;
              _trackWatch();
              widget.onPlaybackReady?.call();
            }
            if (_healthyProgress >= const Duration(seconds: 5)) {
              _retryAttempts = 0;
            }
            // Re-arm from the last progress, not from a stale buffering flag.
            _updateRecoveryTimers();
          }
        },
      ),
      player.stream.duration.listen(
        (value) {
          if (!mounted || !identical(player, _player)) return;
          if (value != _duration) _setState(() => _duration = value);
        },
      ),
      player.stream.completed.listen((completed) {
        if (!mounted || !identical(player, _player)) return;
        _trackWatch();
        if (!completed) _completionHandled = false;
        if (completed && _canPlay && !_scrubbing && !_completionHandled) {
          _completionHandled = true;
          // Seeking to the end isn't a completion signal for recommendations.
          if (!_qualityBusy &&
              !_commentsOpen &&
              !_speedMenuOpen &&
              _panel == _ShortVideoPanel.none &&
              _duration > Duration.zero &&
              _watch.watchedMs > 0 &&
              _watch.mediaMs >= _duration.inMilliseconds * 0.8) {
            _settleWatch(completed: true);
          }
          if (widget.preferences.autoNext &&
              !_qualityBusy &&
              !_speedMenuOpen &&
              !_commentsOpen &&
              _panel == _ShortVideoPanel.none) {
            widget.onNext();
          } else {
            unawaited(
              player.seek(Duration.zero).then((_) {
                if (mounted && identical(player, _player) && _canPlay) {
                  return player.play();
                }
              }),
            );
          }
        }
      }),
      player.stream.error.listen((error) {
        if (!mounted || !identical(player, _player)) return;
        if (error.isNotEmpty && !_qualityBusy) {
          _pendingPlaybackError = error;
          _updateRecoveryTimers();
        }
      }),
    ]);
  }

  Future<void> _releasePlayer() async {
    _cancelRecoveryTimers();
    _pendingPlaybackError = null;
    _healthyProgress = Duration.zero;
    _generation++;
    _prepareFuture = null;
    _disposeSubscriptions();
    final player = _player;
    _player = null;
    _videoController = null;
    _source = null;
    _positionNotifier.value = Duration.zero;
    _setState(() {
      _playing = false;
      _buffering = false;
      _loading = false;
      _duration = Duration.zero;
      _speeding = false;
      _firstFrameReady = false;
    });
    if (player != null) {
      try {
        await player.pause();
      } finally {
        await _disposePlayer(player);
      }
    }
  }

  Future<void> _retry({bool automatic = false}) async {
    if (_retrying ||
        !mounted ||
        !widget.active ||
        !_foreground ||
        _routeCovered) {
      return;
    }
    _retrying = true;
    _cancelRecoveryTimers();
    if (automatic) {
      _retryAttempts++;
    } else {
      _retryAttempts = 0;
    }
    final position = _positionNotifier.value;
    if (position > Duration.zero) _resumePosition = position;
    _resumeQuality = _selectedQuality ?? _resumeQuality;
    _watch = ShortVideoWatchSession();
    _reportedError = false;
    _exposed = false;
    widget.controller.invalidateSource(widget.item);
    try {
      await _releasePlayer();
      if (mounted && widget.active && _foreground && !_routeCovered) {
        await _syncPlayback();
      }
    } finally {
      _retrying = false;
      if (mounted) _updateRecoveryTimers();
    }
  }

  void _disposeSubscriptions() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }

  void _setState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
      _trackWatch();
    }
  }

  Future<void> _togglePlayback() async {
    final player = _player;
    if (player == null || !widget.active) return;
    if (widget.preferences.haptics) HapticFeedback.selectionClick();
    _userPaused = !_userPaused;
    await _syncPlayback();
  }

  void _toggleCleanScreen() {
    if (widget.preferences.haptics) HapticFeedback.selectionClick();
    _setState(() => _cleanScreen = !_cleanScreen);
  }

  Future<void> _exitCleanScreen() async {
    if (!_cleanScreen && !_commentsOpen) return;
    _setState(() => _cleanScreen = false);
    // Exiting the persistent mode must also apply to the next video/re-entry.
    try {
      await GStorage.setting.put(SettingBoxKey.shortVideoCleanScreen, false);
    } catch (_) {
      SmartDialog.showToast('已退出清屏，但默认设置保存失败');
    }
  }

  Future<void> _startFastPlayback() async {
    final player = _player;
    if (player == null || !_playing || !_canPlay) return;
    if (widget.preferences.haptics) HapticFeedback.mediumImpact();
    _setState(() => _speeding = true);
    await _syncPlayback();
  }

  Future<void> _stopFastPlayback() async {
    final player = _player;
    if (player == null || !_speeding) return;
    _setState(() => _speeding = false);
    await _syncPlayback();
  }

  Future<void> _selectSpeed(double rate) async {
    if (FixedPlaybackSpeed.read().enabled) {
      await GStorage.setting.put(FixedPlaybackSpeed.rateKey, rate);
    } else {
      _setState(() => _temporaryRate = rate);
      await _syncPlayback();
    }
  }

  Future<void> _openSpeedMenu(BuildContext buttonContext) async {
    if (_speedMenuOpen) return;
    _speedMenuOpen = true;
    _trackWatch();
    _settleWatch();
    widget.onPanelChanged?.call(true);
    try {
      await showStaticPositionMenu<double>(
        context: buttonContext,
        initialValue: _baseRate,
        color: Colors.black.withValues(alpha: 0.8),
        menuPadding: EdgeInsets.zero,
        menuItemOuterPadding: EdgeInsets.zero,
        menuItemStateLayerColor: Colors.white,
        constraints: const BoxConstraints(minWidth: 176, maxWidth: 220),
        requestFocus: false,
        items: playbackSpeedMenuItems(
          portrait: true,
          currentRate: _baseRate,
          rates: Pref.speedList,
          onSelected: _selectSpeed,
        ),
      );
    } finally {
      _speedMenuOpen = false;
      if (mounted) {
        _trackWatch();
        widget.onPanelChanged?.call(false);
      }
    }
  }

  Future<void> _openFeedMenu(BuildContext buttonContext) async {
    if (_speedMenuOpen) return;
    _speedMenuOpen = true;
    _trackWatch();
    _settleWatch();
    widget.onPanelChanged?.call(true);
    String? action;
    try {
      action = await showStaticPositionMenu<String>(
        context: buttonContext,
        color: Colors.black.withValues(alpha: 0.9),
        items: const [
          PopupMenuItem(
            value: 'dislike',
            child: Text('不感兴趣', style: TextStyle(color: Colors.white)),
          ),
          PopupMenuItem(
            value: 'refresh',
            child: Text('刷新推荐', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    } finally {
      _speedMenuOpen = false;
      if (mounted) {
        _trackWatch();
        widget.onPanelChanged?.call(false);
      }
    }
    if (!mounted) return;
    if (action == 'dislike') {
      widget.controller.dislike(widget.item);
      widget.onNext();
    } else if (action == 'refresh') {
      widget.onRefresh();
    }
  }

  Future<void> _seekTo(double fraction) async {
    final player = _player;
    if (player == null || _duration <= Duration.zero) return;
    final safeFraction = fraction.clamp(0.0, 1.0);
    await player.seek(
      Duration(milliseconds: (_duration.inMilliseconds * safeFraction).round()),
    );
  }

  Future<void> _loadMetadata() async {
    final introResult = await VideoHttp.videoIntro(bvid: _bvid);
    if (!mounted) return;
    if (introResult case Success(:final response)) {
      final stat = response.stat;
      _setState(() {
        _authorMid = response.owner?.mid ?? _authorMid;
        _authorName = response.owner?.name ?? _authorName;
        _authorFace = response.owner?.face ?? _authorFace;
        _viewCount = stat?.view ?? _viewCount;
        _likeCount = stat?.like ?? _likeCount;
        _coinCount = stat?.coin.toInt() ?? _coinCount;
        _replyCount = stat?.reply ?? _replyCount;
        _favoriteCount = stat?.favorite ?? _favoriteCount;
        _shareCount = stat?.share ?? _shareCount;
      });
    }
    final relationResult = await VideoHttp.videoRelation(bvid: _bvid);
    if (!mounted) return;
    if (relationResult case Success(:final response)) {
      _setState(() {
        _liked = response.like ?? _liked;
        _userCoinCount = response.coin?.toInt() ?? _userCoinCount;
        _isCoined = _userCoinCount > 0;
        _isFavorited = response.favorite ?? _isFavorited;
        _isFollowing = response.attention ?? _isFollowing;
      });
    }
  }

  bool _ensureLogin() {
    if (Get.find<AccountService>().isLogin.value) return true;
    SmartDialog.showToast('账号未登录');
    return false;
  }

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    if (widget.preferences.haptics) HapticFeedback.lightImpact();
    if (!_ensureLogin()) return;
    final previous = _liked;
    final newValue = !_liked;
    _setState(() {
      _likeBusy = true;
      _liked = newValue;
      _likeCount = (_likeCount + (newValue ? 1 : -1)).clamp(0, 1 << 31);
    });
    final result = await VideoHttp.likeVideo(bvid: _bvid, type: newValue);
    if (!mounted) return;
    if (result case Success()) {
      _feedback(ShortVideoFeedback.like, enabled: newValue);
      _setState(() => _likeBusy = false);
    } else {
      _setState(() {
        _likeBusy = false;
        _liked = previous;
        _likeCount = (_likeCount + (previous ? 1 : -1)).clamp(0, 1 << 31);
      });
      SmartDialog.showToast(result.toString());
    }
  }

  void _showCoinSheet() {
    if (_coinBusy || !_ensureLogin()) return;
    final remaining = 2 - _userCoinCount;
    if (remaining <= 0) {
      SmartDialog.showToast('这个视频已经投满 2 个币了');
      return;
    }
    if (widget.preferences.haptics) HapticFeedback.selectionClick();
    _setState(() => _panel = _ShortVideoPanel.coin);
    _trackWatch();
    _settleWatch();
    widget.onPanelChanged?.call(true);
  }

  Future<void> _submitCoin(int amount, bool alsoLike) async {
    _closePanel();
    await _coin(multiply: amount, alsoLike: alsoLike);
  }

  Future<void> _coin({required int multiply, required bool alsoLike}) async {
    if (widget.preferences.haptics) HapticFeedback.lightImpact();
    _setState(() => _coinBusy = true);
    final aid = widget.item.aid ?? IdUtils.bv2av(_bvid);
    final result = await VideoHttp.coinVideo(
      aid: aid,
      multiply: multiply,
      selectLike: alsoLike ? 1 : 0,
    );
    if (!mounted) return;
    if (result case Success()) {
      _setState(() {
        _coinBusy = false;
        _isCoined = true;
        _userCoinCount += multiply;
        _coinCount += multiply;
        if (alsoLike && !_liked) {
          _feedback(ShortVideoFeedback.like);
          _liked = true;
          _likeCount++;
        }
      });
      _feedback(ShortVideoFeedback.coin);
      SmartDialog.showToast('成功投出 $multiply 个币');
    } else {
      _setState(() => _coinBusy = false);
      SmartDialog.showToast(result.toString());
    }
  }

  Future<void> _toggleFollow() async {
    if (_followBusy || !_ensureLogin()) return;
    final mid = _authorMid;
    if (mid == null) return;
    final newValue = !_isFollowing;
    if (widget.preferences.haptics) HapticFeedback.lightImpact();
    _setState(() {
      _followBusy = true;
      _isFollowing = newValue;
    });
    final result = await VideoHttp.relationMod(
      mid: mid,
      act: newValue ? 1 : 2,
      reSrc: 11,
    );
    if (!mounted) return;
    if (result case Success()) {
      _feedback(ShortVideoFeedback.follow, enabled: newValue);
      _setState(() => _followBusy = false);
      SmartDialog.showToast(newValue ? '关注成功' : '已取消关注');
    } else {
      _setState(() {
        _followBusy = false;
        _isFollowing = !newValue;
      });
      SmartDialog.showToast(result.toString());
    }
  }

  Future<void> _openFullscreen() => _openDetail(fullscreen: true);

  Future<void> _toggleSubtitles() async {
    _setState(() => _subtitlesEnabled = !_subtitlesEnabled);
    try {
      await GStorage.setting.put(
        SettingBoxKey.shortVideoSubtitles,
        _subtitlesEnabled,
      );
    } catch (_) {
      SmartDialog.showToast('字幕设置保存失败');
    }
  }

  Future<void> _toggleDanmaku() async {
    _setState(() => _danmakuEnabled = !_danmakuEnabled);
    try {
      await GStorage.setting.put(
        SettingBoxKey.shortVideoDanmaku,
        _danmakuEnabled,
      );
    } catch (_) {
      SmartDialog.showToast('弹幕设置保存失败');
    }
  }

  Future<void> _openQualityMenu() async {
    final source = _source;
    final player = _player;
    if (source == null || player == null || _qualityBusy) return;
    _setState(() => _qualityBusy = true);
    widget.onPanelChanged?.call(true);
    try {
      await _syncPlayback();
      if (!mounted) return;
      final selected = await showModalBottomSheet<int>(
        context: context,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('清晰度（当前可用）')),
                for (final quality
                    in (source.qualityUrls.keys.toList()
                      ..sort((a, b) => b.compareTo(a))))
                  ListTile(
                    title: Text(_qualityLabel(quality)),
                    trailing: quality == (_selectedQuality ?? source.quality)
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(context, quality),
                  ),
              ],
            ),
          ),
        ),
      );
      if (!mounted ||
          player != _player ||
          selected == null ||
          selected == (_selectedQuality ?? source.quality)) {
        return;
      }
      final position = _positionNotifier.value;
      final previousUrl =
          source.qualityUrls[_selectedQuality ?? source.quality] ?? source.url;
      try {
        await player.open(Media(source.qualityUrls[selected]!), play: false);
        if (!mounted || player != _player) return;
        await player.seek(position);
        _setState(() => _selectedQuality = selected);
      } catch (_) {
        if (!mounted || player != _player) return;
        await player.open(Media(previousUrl), play: false);
        await player.seek(position);
        rethrow;
      }
    } catch (_) {
      if (mounted) SmartDialog.showToast('清晰度切换失败，请重试');
    } finally {
      if (mounted) {
        _setState(() => _qualityBusy = false);
        widget.onPanelChanged?.call(false);
        await _syncPlayback();
      }
    }
  }

  Future<void> _openDetail({bool fullscreen = false}) async {
    final source = _source;
    if (source == null || _routeCovered) return;
    if (!mounted) return;
    await _openRoute(
      () => PageUtils.toVideoPage(
        aid: widget.item.aid,
        bvid: widget.item.bvid,
        cid: source.cid,
        cover: widget.item.cover,
        title: widget.item.title,
        isVertical: source.isVertical,
        progress: _positionNotifier.value.inMilliseconds,
        extraArguments: {
          'shortVideoFullscreen': fullscreen,
          'shortVideoAutoplay': !_userPaused,
          'shortVideoOnReturn': (int cid, Duration position, bool inPip) {
            if (!mounted || cid != source.cid) return;
            if (inPip) _userPaused = true;
            _resumePosition = position;
            if (!_routeCovered) unawaited(_restoreRoutePosition());
          },
        },
      ),
    );
  }

  Future<void> _openAuthor() async {
    final mid = _authorMid;
    if (mid == null) return;
    await _openRoute(() => Get.toNamed('/member?mid=$mid'));
  }

  Future<void> _restoreRoutePosition() async {
    final player = _player;
    final position = _resumePosition;
    if (!mounted || player == null) return;
    _resumePosition = Duration.zero;
    try {
      await player.seek(position);
      if (mounted && identical(player, _player)) await _syncPlayback();
    } catch (error, stack) {
      logger.w('restore short-video progress', error: error, stackTrace: stack);
    }
  }

  Future<void> _openRoute(Future<dynamic>? Function() open) async {
    _routeCovered = true;
    await _syncPlayback();
    try {
      await open();
    } finally {
      _routeCovered = false;
      if (mounted) {
        if (PlatformUtils.isMobile) {
          await portraitUpMode();
          await applyShortVideoSystemBars(widget.preferences.showStatusBar);
        }
        final player = _player;
        if (player != null && _resumePosition > Duration.zero) {
          await player.seek(_resumePosition);
          _resumePosition = Duration.zero;
        }
        await _syncPlayback();
      }
    }
  }

  Future<void> _openFavorite() async {
    if (_favoriteBusy || !_ensureLogin()) return;
    final aid = widget.item.aid ?? IdUtils.bv2av(_bvid);
    final previous = _isFavorited;
    _setState(() {
      _favoriteBusy = true;
      _isFavorited = !previous;
      _favoriteCount = (_favoriteCount + (previous ? -1 : 1)).clamp(0, 1 << 31);
    });

    LoadingState<void> result;
    if (previous) {
      result = await FavHttp.unfavAll(rid: aid, type: 2);
    } else {
      final folders = await FavHttp.videoInFolder(
        mid: Accounts.main.mid,
        rid: aid,
        type: 2,
      );
      if (folders case Success(:final response)
          when response.list?.isNotEmpty == true) {
        result = await FavHttp.favVideo(
          resources: '$aid:2',
          addIds: response.list!.first.id.toString(),
        );
      } else {
        final message = switch (folders) {
          Error(:final errMsg) => errMsg,
          _ => null,
        };
        result = Error(message ?? '没有可用的收藏夹');
      }
    }

    if (!mounted) return;
    if (result.isSuccess) {
      _feedback(ShortVideoFeedback.favorite, enabled: !previous);
      _setState(() => _favoriteBusy = false);
      SmartDialog.showToast(previous ? '已取消收藏' : '已收藏至默认收藏夹');
    } else {
      _setState(() {
        _favoriteBusy = false;
        _isFavorited = previous;
        _favoriteCount = (_favoriteCount + (previous ? 1 : -1)).clamp(
          0,
          1 << 31,
        );
      });
      result.toast();
    }
  }

  Future<void> _openComments() async {
    if (_commentsOpen || !mounted) return;
    if (widget.preferences.haptics) HapticFeedback.selectionClick();
    final screen = MediaQuery.sizeOf(context);
    final ratio =
        widget.preferences.aspect.ratio ??
        _source?.displayAspectRatio ??
        16 / 9;
    final layout = ShortVideoCommentLayout.calculate(
      screen: screen,
      aspectRatio: ratio,
    );
    _commentExtent.value = screen.height > 0
        ? 1 - layout.videoHeight / screen.height
        : .5;
    _setState(() => _commentsOpen = true);
    _trackWatch();
    _settleWatch();
    widget.onPanelChanged?.call(true);
    try {
      final aid = widget.item.aid ?? IdUtils.bv2av(_bvid);
      await showShortVideoComments(
        context: context,
        aid: aid,
        commentCount: _replyCount,
        videoAspectRatio: ratio,
        transitionAnimationController: _commentAnimation,
        onSheetExtentChanged: (extent) {
          if (mounted && _commentsOpen) _commentExtent.value = extent;
        },
        loadReplies: widget.loadReplies,
        onCountChanged: (count) {
          if (mounted && count != _replyCount) {
            _setState(() => _replyCount = count);
          }
        },
      );
    } catch (error, stackTrace) {
      logger.e(
        'open short-video comments',
        error: error,
        stackTrace: stackTrace,
      );
      SmartDialog.showToast('评论面板打开失败，请重试');
    } finally {
      // Keep the compact media viewport until the modal's exit animation ends.
      if (mounted && _commentAnimation.value > 0) {
        try {
          await _commentAnimation.reverse().orCancel;
        } on TickerCanceled {
          // Disposed while the sheet was exiting.
        }
      }
      if (mounted) {
        _setState(() => _commentsOpen = false);
        _trackWatch();
        widget.onPanelChanged?.call(false);
      }
    }
  }

  void _closePanel() {
    _setState(() => _panel = _ShortVideoPanel.none);
    widget.onPanelChanged?.call(false);
  }

  Future<void> _share() async {
    if (widget.preferences.haptics) HapticFeedback.selectionClick();
    await ShareUtils.shareText(
      '${widget.item.title}\nhttps://www.bilibili.com/video/$_bvid',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final topPadding = MediaQuery.paddingOf(context).top;
    final compact = MediaQuery.sizeOf(context).height < 720;
    // Legacy fill is ignored; cropping/stretching now requires explicit choice.
    final fit = widget.preferences.fit.fit;
    final aspectRatio = widget.preferences.aspect.ratio;

    return PopScope(
      canPop:
          !widget.current || (_panel == _ShortVideoPanel.none && !_cleanScreen),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.current) {
          if (_panel != _ShortVideoPanel.none) {
            _closePanel();
          } else if (_cleanScreen) {
            unawaited(_exitCleanScreen());
          }
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_commentAnimation, _commentExtent]),
              builder: (context, child) => TweenAnimationBuilder<double>(
                tween: Tween(begin: .5, end: _commentExtent.value),
                duration: const Duration(milliseconds: 180),
                child: child,
                builder: (context, extent, child) => LayoutBuilder(
                  builder: (context, constraints) {
                    final progress = Curves.easeOutCubic.transform(
                      _commentAnimation.value,
                    );
                    final height =
                        constraints.maxHeight * (1 - extent * progress);
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        key: const ValueKey('short-video-media-viewport'),
                        height: height,
                        width: constraints.maxWidth,
                        child: ClipRect(child: child),
                      ),
                    );
                  },
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  if (_videoController != null)
                    RepaintBoundary(
                      child: Video(
                        controller: _videoController!,
                        aspectRatio: aspectRatio,
                        fit: fit,
                        fill: Colors.black,
                        controls: (_) => const SizedBox.shrink(),
                        // A single lifecycle owner preserves user pause and position.
                        pauseUponEnteringBackgroundMode: false,
                        resumeUponEnteringForegroundMode: false,
                      ),
                    ),
                  if (_danmakuEnabled && widget.current && _source != null)
                    Positioned.fill(
                      top: _commentsOpen ? 8 : topPadding + 65,
                      bottom: _commentsOpen ? 40 : bottomPadding + 110,
                      child: ShortVideoDanmaku(
                        key: ValueKey(_source!.cid),
                        cid: _source!.cid,
                        fontSize: widget.preferences.danmakuFont,
                        opacity: widget.preferences.danmakuOpacity,
                        area: widget.preferences.danmakuArea,
                        position: _positionNotifier,
                        playing:
                            _canPlay &&
                            _playing &&
                            !_buffering &&
                            !_qualityBusy,
                        rate: _speeding ? _longPressRate : _baseRate,
                      ),
                    ),
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _firstFrameReady ? 0 : 1,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (aspectRatio == null)
                            NetworkImgLayer(
                              src: widget.item.cover,
                              width: MediaQuery.sizeOf(context).width,
                              height: MediaQuery.sizeOf(context).height,
                              borderRadius: BorderRadius.zero,
                              getPlaceHolder: () =>
                                  const ColoredBox(color: Color(0xFF111318)),
                              fit: fit,
                            )
                          else
                            FittedBox(
                              fit: fit,
                              child: SizedBox(
                                width: 1000 * aspectRatio,
                                height: 1000,
                                child: NetworkImgLayer(
                                  src: widget.item.cover,
                                  width: 1000 * aspectRatio,
                                  height: 1000,
                                  borderRadius: BorderRadius.zero,
                                  getPlaceHolder: () => const ColoredBox(
                                    color: Color(0xFF111318),
                                  ),
                                  fit: BoxFit.fill,
                                ),
                              ),
                            ),
                          const ColoredBox(color: Color(0x52000000)),
                        ],
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutBack,
                              ),
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                        child:
                            widget.active &&
                                _userPaused &&
                                !_playing &&
                                !_loading &&
                                _error == null
                            ? Container(
                                key: const ValueKey('paused'),
                                width: 66,
                                height: 66,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.4),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 44,
                                ),
                              )
                            : const SizedBox(key: ValueKey('playing')),
                      ),
                    ),
                  ),
                  if (widget.active &&
                      _error == null &&
                      (_loading ||
                          _buffering ||
                          (_videoController != null &&
                              !_firstFrameReady &&
                              !_userPaused)))
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 48,
                          height: 48,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.48),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.4,
                          ),
                        ),
                      ),
                    ),
                  if (_subtitlesEnabled && widget.current && _source != null)
                    Positioned.fill(
                      left: 20,
                      right: _cleanScreen || _commentsOpen ? 20 : 82,
                      top: _commentsOpen ? 8 : topPadding + 72,
                      bottom: _commentsOpen
                          ? 12
                          : bottomPadding + (_cleanScreen ? 32 : 225),
                      child: Align(
                        alignment:
                            widget.preferences.subtitles.position.alignment,
                        child: ShortVideoSubtitles(
                          key: ValueKey('subtitles-${_source!.cid}'),
                          preferences: widget.preferences.subtitles,
                          translationActive:
                              _canPlay &&
                              _playing &&
                              !_buffering &&
                              !widget.scrolling,
                          aid: widget.item.aid!,
                          bvid: _bvid,
                          cid: _source!.cid,
                          position: _positionNotifier,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!_cleanScreen && !_commentsOpen)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.2, 0.58, 1],
                  colors: [
                    Color(0x99000000),
                    Color(0x18000000),
                    Colors.transparent,
                    Color(0xE8000000),
                  ],
                ),
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlayback,
              onDoubleTap: _toggleCleanScreen,
              onLongPressStart: (_) => _startFastPlayback(),
              onLongPressEnd: (_) => _stopFastPlayback(),
              onLongPressCancel: _stopFastPlayback,
            ),
          ),
          if (_cleanScreen && !_commentsOpen && widget.current)
            Positioned(
              top: topPadding + 8,
              right: 12,
              child: FilledButton.tonalIcon(
                key: const ValueKey('exit-short-video-clean-screen'),
                onPressed: _exitCleanScreen,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.fullscreen_exit_rounded, size: 20),
                label: const Text('退出清屏'),
              ),
            ),
          if (!_cleanScreen && !_commentsOpen)
            Positioned(
              top: topPadding + 4,
              left: 8,
              right: 8,
              child: _PortraitTopBar(
                viewCount: _viewCount,
                onBack: Get.back,
                onSettings:
                    widget.onSettings ??
                    () => _openRoute(
                      () => Get.to(
                        () => const CommonSetting(
                          settingType: SettingType.shortVideoSetting,
                        ),
                      ),
                    ),
                onSearch: () => _openRoute(() => Get.toNamed('/search')),
                onMore: _openFeedMenu,
              ),
            ),
          if (_speeding)
            Positioned(
              top: topPadding + 66,
              left: 0,
              right: 0,
              child: Center(
                child: _FeedStatusChip(
                  icon: Icons.fast_forward_rounded,
                  label: '松开恢复 · ${FixedPlaybackSpeed.label(_longPressRate)}',
                ),
              ),
            ),
          if (_error != null)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 36),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: _retry,
                          child: const Text('重新加载'),
                        ),
                        TextButton(
                          onPressed: widget.onNext,
                          child: const Text('下一条'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (!_cleanScreen && !_commentsOpen)
            Positioned(
              left: 16,
              right: 82,
              bottom: bottomPadding + (compact ? 78 : 84),
              child: _VideoDescription(
                item: widget.item,
                authorName: _authorName,
                authorFace: _authorFace,
                isFollowing: _isFollowing,
                followBusy: _followBusy,
                onAuthorTap: _openAuthor,
                onFollow: _toggleFollow,
              ),
            ),
          if (!_cleanScreen && !_commentsOpen)
            Positioned(
              right: 7,
              bottom: bottomPadding + (compact ? 84 : 94),
              child: Column(
                children: [
                  _ActionButton(
                    semanticLabel: _liked ? '取消点赞' : '点赞',
                    icon: _liked
                        ? Icons.thumb_up_alt
                        : Icons.thumb_up_alt_outlined,
                    color: _liked ? const Color(0xFFFF6699) : Colors.white,
                    active: _liked,
                    compact: compact,
                    label: NumUtils.numFormat(_likeCount),
                    onPressed: _toggleLike,
                  ),
                  SizedBox(height: compact ? 7 : 11),
                  _ActionButton(
                    semanticLabel: '投币',
                    icon: _isCoined
                        ? Icons.monetization_on_rounded
                        : Icons.monetization_on_outlined,
                    color: _isCoined ? const Color(0xFFFFC107) : Colors.white,
                    active: _isCoined,
                    compact: compact,
                    label: NumUtils.numFormat(_coinCount),
                    busy: _coinBusy,
                    onPressed: _showCoinSheet,
                  ),
                  SizedBox(height: compact ? 7 : 11),
                  _ActionButton(
                    semanticLabel: '评论',
                    icon: Icons.chat_bubble_rounded,
                    compact: compact,
                    label: NumUtils.numFormat(_replyCount),
                    onPressed: _openComments,
                  ),
                  SizedBox(height: compact ? 7 : 11),
                  _ActionButton(
                    semanticLabel: '收藏',
                    icon: _isFavorited
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: _isFavorited
                        ? const Color(0xFFFFC107)
                        : Colors.white,
                    active: _isFavorited,
                    compact: compact,
                    busy: _favoriteBusy,
                    label: NumUtils.numFormat(_favoriteCount),
                    onPressed: _openFavorite,
                  ),
                  SizedBox(height: compact ? 7 : 11),
                  _ActionButton(
                    semanticLabel: '分享',
                    icon: Icons.share_rounded,
                    compact: compact,
                    label: NumUtils.numFormat(_shareCount),
                    onPressed: _share,
                  ),
                ],
              ),
            ),
          if (!_cleanScreen && !_commentsOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomPadding + 53,
              child: ShortVideoProgressBar(
                key: ValueKey(_source?.cid),
                onDraggingChanged: (dragging) {
                  _scrubbing = dragging;
                  widget.onPanelChanged?.call(dragging);
                  _trackWatch();
                },
                positionListenable: _positionNotifier,
                duration: _duration,
                onSeek: _seekTo,
                haptics: widget.preferences.haptics,
              ),
            ),
          if (!_cleanScreen && !_commentsOpen)
            Positioned(
              left: 12,
              right: 12,
              bottom: bottomPadding + 8,
              child: _BottomPlaybackBar(
                muted: widget.muted,
                subtitlesEnabled: _subtitlesEnabled,
                onSubtitles: _toggleSubtitles,
                danmakuEnabled: _danmakuEnabled,
                onDanmaku: _toggleDanmaku,
                quality: _qualityLabel(
                  _selectedQuality ?? _source?.quality ?? 64,
                ),
                onQuality: _qualityBusy ? null : _openQualityMenu,
                onFullscreen: _openFullscreen,
                onToggleMuted: widget.onToggleMuted,
                onOpenDetail: _openDetail,
                speed: _baseRate,
                onSpeed: _openSpeedMenu,
              ),
            ),
          if (_panel != _ShortVideoPanel.none)
            Positioned.fill(
              child: _InlineBottomPanel(
                onDismiss: _closePanel,
                child: switch (_panel) {
                  _ShortVideoPanel.coin => _CoinPickerSheet(
                    maxCoins: 2 - _userCoinCount,
                    alreadyLiked: _liked,
                    onSubmit: _submitCoin,
                    haptics: widget.preferences.haptics,
                  ),
                  _ShortVideoPanel.none => const SizedBox.shrink(),
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PortraitBackButton extends StatelessWidget {
  const _PortraitBackButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _TopIconButton(
    icon: Icons.arrow_back_ios_new_rounded,
    tooltip: '返回',
    onPressed: onPressed,
  );
}

class _PortraitTopBar extends StatelessWidget {
  const _PortraitTopBar({
    required this.viewCount,
    required this.onBack,
    required this.onSettings,
    required this.onSearch,
    required this.onMore,
  });

  final int viewCount;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback onSearch;
  final ValueChanged<BuildContext> onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PortraitBackButton(onPressed: onBack),
        const SizedBox(width: 9),
        Expanded(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.26),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '推荐',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Container(
                  width: 3,
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF6699),
                    shape: BoxShape.circle,
                  ),
                ),
                const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white70,
                  size: 16,
                ),
                Flexible(
                  child: Text(
                    NumUtils.numFormat(viewCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        _TopIconButton(
          icon: Icons.search_rounded,
          tooltip: '搜索',
          onPressed: onSearch,
        ),
        Builder(
          builder: (context) => _TopIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: '推荐操作',
            onPressed: () => onMore(context),
          ),
        ),
        _TopIconButton(
          icon: Icons.tune_rounded,
          tooltip: '竖屏设置',
          onPressed: onSettings,
        ),
      ],
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      color: Colors.white,
      iconSize: 25,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(40),
        backgroundColor: Colors.black.withValues(alpha: 0.26),
        side: const BorderSide(color: Colors.white12),
        shadowColor: Colors.black54,
      ),
      icon: Icon(icon, shadows: const [Shadow(blurRadius: 8)]),
    );
  }
}

class _VideoDescription extends StatelessWidget {
  const _VideoDescription({
    required this.item,
    required this.authorName,
    required this.authorFace,
    required this.isFollowing,
    required this.followBusy,
    required this.onAuthorTap,
    required this.onFollow,
  });

  final BaseRcmdVideoItemModel item;
  final String? authorName;
  final String? authorFace;
  final bool isFollowing;
  final bool followBusy;
  final VoidCallback onAuthorTap;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final owner = authorName?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: onAuthorTap,
              child: Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: const Color(0xFFFF6699),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 10),
                  ],
                ),
                child: NetworkImgLayer(
                  src: authorFace,
                  width: 36,
                  height: 36,
                  type: ImageType.avatar,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: GestureDetector(
                onTap: onAuthorTap,
                child: Text(
                  owner?.isNotEmpty == true ? owner! : '未知UP主',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black87)],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
              height: 30,
              child: FilledButton.tonal(
                onPressed: followBusy ? null : onFollow,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  backgroundColor: isFollowing
                      ? Colors.white.withValues(alpha: 0.22)
                      : const Color(0xFFFF6699),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white24,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: isFollowing ? Colors.white24 : Colors.transparent,
                    ),
                  ),
                ),
                child: followBusy
                    ? const SizedBox.square(
                        dimension: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: Colors.white,
                        ),
                      )
                    : Text(isFollowing ? '已关注' : '+ 关注'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            height: 1.36,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 8, color: Colors.black87)],
          ),
        ),
        if (item.rcmdReason?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              item.rcmdReason!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.semanticLabel,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = Colors.white,
    this.active = false,
    this.compact = false,
    this.busy = false,
  });

  final String semanticLabel;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;
  final bool active;
  final bool compact;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$semanticLabel，$label',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy ? null : onPressed,
        child: SizedBox(
          width: 58,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: compact ? 40 : 44,
                height: compact ? 40 : 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? color.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.34),
                  border: Border.all(
                    color: active
                        ? color.withValues(alpha: 0.42)
                        : Colors.white12,
                  ),
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        icon,
                        color: color,
                        size: compact ? 25 : 27,
                        shadows: const [
                          Shadow(blurRadius: 7, color: Colors.black87),
                        ],
                      ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineBottomPanel extends StatelessWidget {
  const _InlineBottomPanel({
    required this.child,
    required this.onDismiss,
  });

  final Widget child;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) {},
      onVerticalDragUpdate: (_) {},
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.48)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Transform.translate(
                offset: Offset(0, (1 - value) * 64),
                child: Opacity(opacity: value, child: child),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoinPickerSheet extends StatefulWidget {
  const _CoinPickerSheet({
    required this.maxCoins,
    required this.alreadyLiked,
    required this.onSubmit,
    required this.haptics,
  });

  final int maxCoins;
  final bool haptics;
  final bool alreadyLiked;
  final void Function(int amount, bool alsoLike) onSubmit;

  @override
  State<_CoinPickerSheet> createState() => _CoinPickerSheetState();
}

class _CoinPickerSheetState extends State<_CoinPickerSheet> {
  int _amount = 1;
  bool _alsoLike = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 17),
              const Text(
                '为喜欢的内容投币',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _coinOption(context, 1)),
                  if (widget.maxCoins >= 2) ...[
                    const SizedBox(width: 12),
                    Expanded(child: _coinOption(context, 2)),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: widget.alreadyLiked || _alsoLike,
                onChanged: widget.alreadyLiked
                    ? null
                    : (value) => setState(() => _alsoLike = value),
                title: Text(widget.alreadyLiked ? '已经点赞' : '同时点赞'),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: () => widget.onSubmit(
                    _amount,
                    !widget.alreadyLiked && _alsoLike,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6699),
                    foregroundColor: Colors.white,
                  ),
                  child: Text('投 $_amount 个币'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coinOption(BuildContext context, int amount) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _amount == amount;
    return Material(
      color: selected
          ? const Color(0xFFFF6699).withValues(alpha: 0.12)
          : colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? const Color(0xFFFF6699)
              : colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (widget.haptics) HapticFeedback.selectionClick();
          setState(() => _amount = amount);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Column(
            children: [
              Icon(
                Icons.monetization_on_rounded,
                color: selected ? const Color(0xFFFFB300) : colorScheme.outline,
                size: 32,
              ),
              const SizedBox(height: 5),
              Text(
                '$amount 个硬币',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? const Color(0xFFFF6699) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _qualityLabel(int code) =>
    VideoQuality.values
        .where((quality) => quality.code == code)
        .firstOrNull
        ?.shortDesc ??
    '$code';

class _BottomPlaybackBar extends StatelessWidget {
  const _BottomPlaybackBar({
    required this.muted,
    required this.onToggleMuted,
    required this.onOpenDetail,
    required this.speed,
    required this.onSpeed,
    required this.subtitlesEnabled,
    required this.onSubtitles,
    required this.danmakuEnabled,
    required this.onDanmaku,
    required this.quality,
    required this.onQuality,
    required this.onFullscreen,
  });
  final bool muted, danmakuEnabled, subtitlesEnabled;
  final VoidCallback onSubtitles;
  final VoidCallback onToggleMuted, onOpenDetail, onDanmaku, onFullscreen;
  final VoidCallback? onQuality;
  final double speed;
  final String quality;
  final ValueChanged<BuildContext> onSpeed;
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      IconButton(
        tooltip: danmakuEnabled ? '关闭弹幕' : '打开弹幕',
        onPressed: onDanmaku,
        color: danmakuEnabled ? Colors.lightBlueAccent : Colors.white54,
        icon: const Icon(Icons.subtitles_outlined),
      ),
      IconButton(
        tooltip: subtitlesEnabled ? '关闭字幕' : '打开字幕',
        onPressed: onSubtitles,
        color: subtitlesEnabled ? Colors.lightBlueAccent : Colors.white54,
        icon: const Icon(Icons.closed_caption_outlined),
      ),
      TextButton(
        onPressed: onQuality,
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 2),
        ),
        child: Text(
          quality,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      Tooltip(
        message: '倍速',
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => onSpeed(context),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 2),
            ),
            child: Text(
              '${speed}X',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: muted ? '打开声音' : '静音',
        onPressed: onToggleMuted,
        color: Colors.white,
        icon: Icon(
          muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        ),
      ),
      IconButton(
        tooltip: '完整详情',
        onPressed: onOpenDetail,
        color: Colors.white,
        icon: const Icon(Icons.info_outline),
      ),
      IconButton(
        tooltip: '全屏',
        onPressed: onFullscreen,
        color: Colors.white,
        icon: const Icon(Icons.screen_rotation_rounded),
      ),
    ].map((child) => Expanded(child: child)).toList(),
  );
}

class _FeedStatusChip extends StatelessWidget {
  const _FeedStatusChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 17),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  const _CenteredStatus({
    required this.icon,
    required this.message,
    this.loading = false,
    this.actionText,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final bool loading;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            if (loading) ...[
              const SizedBox(height: 18),
              const CircularProgressIndicator(color: Colors.white),
            ],
            if (actionText != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(actionText!)),
            ],
          ],
        ),
      ),
    );
  }
}
