import 'dart:async';

import 'package:PiliPlus/pages/short_video/launch.dart';

import 'package:PiliPlus/pages/short_video/recommendation/candidate.dart';
import 'package:PiliPlus/pages/short_video/recommendation/user_profile.dart';
import 'package:PiliPlus/pages/short_video/recommendation/recommendation_engine.dart';
import 'package:PiliPlus/pages/short_video/recommendation/recommendation_storage.dart';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/utils/extension/dimension_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/pages/short_video/preferences.dart';
import 'package:get/get.dart';

class ShortVideoSource {
  const ShortVideoSource({
    required this.url,
    required this.cid,
    required this.isVertical,
    this.aspectRatio,
    this.quality = 64,
    this.qualityUrls = const {},
  });

  final String url;
  final int cid;
  final bool isVertical;
  final double? aspectRatio;
  double get displayAspectRatio =>
      aspectRatio != null && aspectRatio!.isFinite && aspectRatio! > 0
      ? aspectRatio!
      : (isVertical ? 9 / 16 : 16 / 9);
  final int quality;
  final Map<int, String> qualityUrls;
}

class ShortVideoController extends GetxController {
  ShortVideoController({
    this.preferences = const ShortVideoPreferences(),
    Future<LoadingState<List<BaseRcmdVideoItemModel>>> Function(int)?
    metadataLoader,
    this.sourceResolver,
    this.initialLaunch,
    RecommendationStorage? storage,
    RecommendationEngine? engine,
  }) : _metadataLoader =
           metadataLoader ??
           ((index) => VideoHttp.rcmdVideoListApp(freshIdx: index)),
       _storage = storage ?? RecommendationStorage(),
       _engine = engine ?? RecommendationEngine();

  final ShortVideoLaunch? initialLaunch;
  ShortVideoLaunch? _launch;
  Duration _launchPosition = Duration.zero;
  final launchRevision = 0.obs;

  bool isExplicitVideo(BaseRcmdVideoItemModel item) =>
      _launch != null &&
      _launch!.item.aid == item.aid &&
      _launch!.item.cid == item.cid;

  Duration takeInitialPosition(BaseRcmdVideoItemModel item) {
    if (!isExplicitVideo(item)) return Duration.zero;
    final position = _launchPosition;
    _launchPosition = Duration.zero;
    return position;
  }

  /// Invalidate old recommendation requests before replacing the current item.
  /// Explicit selections bypass recommendation-only orientation/history filters.
  void startFrom(ShortVideoLaunch launch) {
    if (isClosed) return;
    _feedEpoch++;
    _refreshingVertical = null;
    _refill = null;
    _pool.clear();
    _sourceCache.clear();
    _queued.add(launch.item.aid!);
    while (_queued.length > 1000) {
      _queued.remove(_queued.first);
    }
    _launch = launch;
    _launchPosition = launch.position < Duration.zero
        ? Duration.zero
        : launch.position;
    isInitialLoading.value = false;
    isLoadingMore.value = false;
    errorMessage.value = null;
    loadMoreError.value = null;
    items.assignAll([launch.item]);
    launchRevision.value++;
  }

  ShortVideoPreferences preferences;
  final Future<LoadingState<List<BaseRcmdVideoItemModel>>> Function(int)
  _metadataLoader;
  final Future<ShortVideoSource> Function(BaseRcmdVideoItemModel)?
  sourceResolver;
  final RecommendationStorage _storage;
  final RecommendationEngine _engine;
  ShortVideoProfile? _profile;
  ShortVideoProfile get profile => _profile ??= _storage.read();
  final items = <BaseRcmdVideoItemModel>[].obs;
  final isInitialLoading = false.obs;
  final isLoadingMore = false.obs;
  final errorMessage = RxnString();
  final loadMoreError = RxnString();
  final _pool = <int, ShortVideoCandidate>{};
  final _queued = <int>{};
  final Map<int, Future<ShortVideoSource>> _sourceCache = {};
  int _freshIdx = 0;
  bool? _refreshingVertical;
  int _feedEpoch = 0;
  Future<void>? _refill;
  int _refillEpoch = -1;
  Future<void> _writes = Future.value();
  int profileRevision = 0;
  int get candidateCount => _pool.length;
  int get sourceCacheCount => _sourceCache.length;

  @override
  void onInit() {
    super.onInit();
    if (preferences.enabled) {
      if (initialLaunch case final launch?) {
        startFrom(launch);
      } else {
        unawaited(refreshFeed());
      }
    }
  }

  void recordExposure(BaseRcmdVideoItemModel item) {
    if (isClosed || item.aid == null) return;
    profile.seen(ShortVideoCandidate(item));
    _save();
  }

  void recordWeight(
    BaseRcmdVideoItemModel item,
    double weight, {
    int? revision,
  }) {
    // Item disposal may checkpoint after Get closes this page's controller.
    // But a pre-clear watch session must never repopulate the cleared profile.
    if ((revision != null && revision != profileRevision) ||
        !preferences.personalized ||
        weight == 0 ||
        item.aid == null) {
      return;
    }
    profile.apply(ShortVideoCandidate(item), weight);
    _save();
  }

  void dislike(BaseRcmdVideoItemModel item) {
    if (item.aid == null) return;
    profile.dislike(ShortVideoCandidate(item));
    _pool.remove(item.aid);
    if (preferences.personalized) profile.apply(ShortVideoCandidate(item), -20);
    _save();
  }

  // Serialize snapshots and clear operations so an older write cannot restore
  // a profile after the user clears it. No periodic/per-frame disk writes.
  void _save() {
    // Storage snapshots before enqueueing; avoid serializing the bounded
    // profile twice for every exposure/interaction.
    _writes = _storage.save(profile).catchError((Object _) {});
  }

  Future<void> clearProfile() {
    _profile = ShortVideoProfile();
    profileRevision++;
    // Clearing learned history must not clear the visible queue's identity
    // set: the upstream feed may return these videos again on the next refill.
    _queued
      ..clear()
      ..addAll(items.map((item) => item.aid).whereType<int>());
    final clearing = _storage.clear();
    _writes = clearing.catchError((Object _) {});
    return clearing;
  }

  Future<void> get flushProfile => _writes;

  Future<void> refreshFeed() async {
    if (isClosed ||
        !preferences.enabled ||
        _refreshingVertical == preferences.onlyVertical) {
      return;
    }
    _refreshingVertical = preferences.onlyVertical;
    final epoch = ++_feedEpoch;
    isLoadingMore.value = false;
    isInitialLoading.value = true;
    errorMessage.value = null;
    loadMoreError.value = null;
    _pool.clear();
    _freshIdx = 0;
    try {
      // Cold entry should not wait for 2-3 recommendation requests to fill a
      // ranking pool. Start with the first eligible batch, refill on demand.
      await _ensurePool(epoch, items.isEmpty ? 1 : 30);
      if (isClosed || epoch != _feedEpoch) return;
      final next = _select();
      if (next.isEmpty) {
        errorMessage.value = preferences.onlyVertical
            ? '暂无已标注竖向的视频，可关闭“仅竖向视频”后重试'
            : '暂时没有新的视频，请稍后重试';
        if (items.isNotEmpty) loadMoreError.value = errorMessage.value;
      } else {
        _sourceCache.clear();
        items.assignAll(next);
      }
    } catch (error) {
      if (!isClosed && epoch == _feedEpoch) {
        errorMessage.value = _friendlyError(error);
        if (items.isNotEmpty) loadMoreError.value = errorMessage.value;
      }
    } finally {
      if (epoch == _feedEpoch) {
        _refreshingVertical = null;
        if (!isClosed) isInitialLoading.value = false;
      }
    }
  }

  Future<void> _ensurePool(int epoch, int target) {
    if (_refill != null && _refillEpoch == epoch) return _refill!;
    _refillEpoch = epoch;
    late final Future<void> request;
    request = _fillPool(epoch, target).whenComplete(() {
      if (identical(_refill, request)) _refill = null;
    });
    _refill = request;
    return request;
  }

  Future<void> _fillPool(int epoch, int target) async {
    for (var batch = 0; batch < 3 && _pool.length < target; batch++) {
      final result = await _metadataLoader(_freshIdx++);
      if (isClosed || epoch != _feedEpoch) return;
      if (result case Success(:final response)) {
        for (final item in response) {
          if (!ShortVideoCandidate.playable(item) ||
              _queued.contains(item.aid) ||
              profile.recent.contains(item.aid) ||
              profile.disliked.contains(item.aid)) {
            continue;
          }
          final candidate = ShortVideoCandidate(item);
          if (preferences.onlyVertical && candidate.vertical != true) continue;
          _pool.putIfAbsent(candidate.aid, () => candidate);
          if (_pool.length >= 100) break;
        }
      } else {
        if (_pool.isEmpty) throw StateError('推荐加载失败，请重试');
        break;
      }
    }
  }

  List<BaseRcmdVideoItemModel> _select() {
    final selected = _engine.select(
      _pool.values,
      profile,
      personalized: preferences.personalized,
      history: items
          .skip((items.length - 8).clamp(0, items.length))
          .map(ShortVideoCandidate.new)
          .toList(),
    );
    for (final candidate in selected) {
      _pool.remove(candidate.aid);
      _queued.add(candidate.aid);
      while (_queued.length > 1000) {
        _queued.remove(_queued.first);
      }
    }
    return selected.map((c) => c.item).toList();
  }

  Future<void> loadMore() async {
    if (isClosed ||
        !preferences.enabled ||
        isLoadingMore.value ||
        isInitialLoading.value) {
      return;
    }
    isLoadingMore.value = true;
    final epoch = _feedEpoch;
    loadMoreError.value = null;
    try {
      if (_pool.length < 20) await _ensurePool(epoch, 60);
      if (isClosed || epoch != _feedEpoch) return;
      final next = _select();
      if (next.isEmpty) {
        loadMoreError.value = '暂时没有新的视频，点击重试';
      } else {
        items.addAll(next);
      }
    } catch (_) {
      if (!isClosed && epoch == _feedEpoch) loadMoreError.value = '加载更多失败，点击重试';
    } finally {
      if (!isClosed && epoch == _feedEpoch) isLoadingMore.value = false;
    }
  }

  /// Called only while settled; the view rebases its PageController by this count.
  int trimBefore(int index) {
    if (index < 30) return 0;
    final removed = index - 1;
    items.removeRange(0, removed);
    return removed;
  }

  void onPageChanged(int index) {
    if (index >= items.length - 6) {
      unawaited(loadMore());
    } else if (_pool.length < 20 &&
        !isInitialLoading.value &&
        preferences.enabled) {
      // Metadata only: refill before the visible queue reaches its tail.
      unawaited(_ensurePool(_feedEpoch, 60).catchError((Object _) {}));
    }
    prefetchAround(index);
  }

  @override
  void onClose() {
    _feedEpoch++;
    _sourceCache.clear();
    _pool.clear();
    super.onClose();
  }

  // Cache maintenance only. The page's cancellable scheduler is the sole
  // preload owner; ranking candidates never resolves playback URLs.
  void prefetchAround(int index) {
    final nearby = items
        .skip((index - 2).clamp(0, items.length))
        .take(6)
        .map((item) => item.aid)
        .toSet();
    _sourceCache.removeWhere((aid, _) => !nearby.contains(aid));
  }

  Future<ShortVideoSource> sourceFor(BaseRcmdVideoItemModel item) {
    final aid = item.aid;
    if (aid == null) {
      return Future.error(StateError('视频缺少 aid'));
    }
    final cached = _sourceCache[aid];
    if (cached != null) return cached;

    late final Future<ShortVideoSource> future;
    future =
        Future<ShortVideoSource>.sync(
          () => (sourceResolver ?? _resolveSource)(item),
        ).catchError((Object error, StackTrace stack) {
          if (identical(_sourceCache[aid], future)) {
            _sourceCache.remove(aid);
          }
          return Future<ShortVideoSource>.error(error, stack);
        });
    while (_sourceCache.length >= 6) {
      _sourceCache.remove(_sourceCache.keys.first);
    }
    _sourceCache[aid] = future;
    return future;
  }

  void invalidateSource(BaseRcmdVideoItemModel item) {
    final aid = item.aid;
    if (aid != null) _sourceCache.remove(aid);
  }

  Future<ShortVideoSource> _resolveSource(
    BaseRcmdVideoItemModel item,
  ) async {
    final aid = item.aid!;
    final bvid = item.bvid ?? IdUtils.av2bv(aid);
    var cid = item.cid;
    double? pageAspectRatio;
    var isVertical = item.uri?.isVerticalFromUri == true;

    if (cid == null) {
      final page = await SearchHttp.ab2cWithDimension(aid: aid, bvid: bvid);
      cid = page?.cid;
      isVertical = page?.dimension?.isVertical ?? isVertical;
      final width = page?.dimension?.width ?? 0;
      final height = page?.dimension?.height ?? 0;
      if (width > 0 && height > 0) pageAspectRatio = width / height;
    }
    if (cid == null) {
      throw StateError('无法获取视频分P信息');
    }

    final result = await VideoHttp.videoUrl(
      avid: aid,
      bvid: bvid,
      cid: cid,
      qn: VideoQuality.high720.code,
      tryLook: true,
      videoType: VideoType.ugc,
    );
    if (result case Success(:final response)) {
      final source = _pickSource(response);
      final qualityUrls = <int, String>{};
      for (final video in response.dash?.video ?? []) {
        final selected = _pickSource(response, quality: video.id);
        if (selected != null && selected.$3 == video.id) {
          qualityUrls[video.id] = selected.$1;
        }
      }
      if (source == null) throw StateError('未获取到可用播放地址');
      return ShortVideoSource(
        url: source.$1,
        cid: cid,
        isVertical: source.$2 ?? isVertical,
        aspectRatio: source.$4 ?? pageAspectRatio,
        quality: source.$3,
        qualityUrls: qualityUrls.isEmpty ? {source.$3: source.$1} : qualityUrls,
      );
    }
    throw StateError(result.toString());
  }

  (String, bool?, int, double?)? _pickSource(
    PlayUrlModel playUrl, {
    int quality = 64,
  }) {
    final dash = playUrl.dash;
    if (dash?.video case final videos? when videos.isNotEmpty) {
      final candidates = videos.where((item) => item.id <= quality).toList();
      final pool = candidates.isEmpty ? [...videos] : candidates
        ..sort((a, b) {
          final quality = b.id.compareTo(a.id);
          if (quality != 0) return quality;
          return (a.codecid == 7 ? 0 : 1).compareTo(b.codecid == 7 ? 0 : 1);
        });
      final video = pool.first;
      final videoUrl = video.playUrls.firstOrNull;
      if (videoUrl != null) {
        final audioUrl = dash?.audio?.firstOrNull?.playUrls.firstOrNull;
        final mediaUrl = audioUrl == null
            ? videoUrl
            : 'edl://!no_chapters;%${videoUrl.length}%$videoUrl;'
                  '!new_stream;!no_chapters;%${audioUrl.length}%$audioUrl';
        final width = video.width;
        final height = video.height;
        return (
          mediaUrl,
          width != null && height != null ? height > width : null,
          video.id,
          width != null && height != null && width > 0 && height > 0
              ? width / height
              : null,
        );
      }
    }

    final durl = playUrl.durl?.firstOrNull?.playUrls.firstOrNull;
    return durl == null ? null : (durl, null, playUrl.quality ?? quality, null);
  }

  String _friendlyError(Object error) {
    return error.toString().replaceFirst('Bad state: ', '');
  }
}
