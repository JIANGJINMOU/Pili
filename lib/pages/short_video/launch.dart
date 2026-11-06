import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/pages/short_video/search_feed.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';

/// Explicit user selection, distinct from the recommendation queue.
class ShortVideoLaunch {
  const ShortVideoLaunch({
    required this.item,
    this.position = Duration.zero,
    this.creatorMid,
    this.searchFeed,
    this.searchItems,
  });
  final BaseRcmdVideoItemModel item;
  final Duration position;
  final int? creatorMid;
  final ShortVideoSearchFeed? searchFeed;
  final List<BaseRcmdVideoItemModel>? searchItems;

  factory ShortVideoLaunch.fromCreator({
    required int mid,
    required int aid,
    required String bvid,
    required int cid,
    String? title,
    String? cover,
    Duration position = Duration.zero,
  }) => ShortVideoLaunch(
    creatorMid: mid,
    position: position,
    item: RcmdVideoItemModel.fromJson({
      'id': aid,
      'bvid': bvid,
      'cid': cid,
      'goto': 'av',
      'title': title ?? '',
      'pic': cover,
      'duration': 0,
      'owner': {'mid': mid},
      'stat': <String, dynamic>{},
    }),
  );

  factory ShortVideoLaunch.fromDetail({
    required VideoDetailData detail,
    required int aid,
    required String bvid,
    required int cid,
    required Duration position,
  }) {
    final part = detail.pages?.where((p) => p.cid == cid).firstOrNull;
    final dimension = part?.dimension ?? detail.dimension;
    final width = dimension?.width ?? 0;
    final height = dimension?.height ?? 0;
    return ShortVideoLaunch(
      position: position < Duration.zero ? Duration.zero : position,
      item: RcmdVideoItemModel.fromJson({
        'id': aid,
        'bvid': bvid,
        'cid': cid,
        'goto': 'av',
        'title': part?.part?.isNotEmpty == true
            ? part!.part
            : (detail.title ?? ''),
        'pic': part?.firstFrame ?? detail.pic,
        'duration': part?.duration ?? detail.duration ?? 0,
        'owner': detail.owner?.toJson() ?? <String, dynamic>{},
        'stat': {
          'view': detail.stat?.view,
          'like': detail.stat?.like,
          'danmaku': detail.stat?.danmaku,
        },
        if (width > 0 && height > 0)
          'uri':
              'bilibili://video/$aid?player_width=$width&player_height=$height',
      }),
    );
  }
}
