import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';

/// Explicit user selection, distinct from the recommendation queue.
class ShortVideoLaunch {
  const ShortVideoLaunch({required this.item, this.position = Duration.zero});
  final BaseRcmdVideoItemModel item;
  final Duration position;

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
