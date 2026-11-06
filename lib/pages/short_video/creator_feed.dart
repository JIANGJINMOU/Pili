import 'package:PiliPlus/http/member.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/space/space_archive/data.dart';
import 'package:PiliPlus/utils/id_utils.dart';

/// Cursor stays local to one UP feed, including retries and refreshes.
class CreatorVideoFeed {
  CreatorVideoFeed(this.mid, this.aid, {this.fetch});
  final int mid;
  final int aid;
  final Future<LoadingState<SpaceArchiveData>> Function(String, bool)? fetch;
  late String _cursor = aid.toString();
  bool _firstPage = true;
  bool ended = false;

  Future<List<BaseRcmdVideoItemModel>> load() async {
    if (ended) return [];
    final result =
        await (fetch?.call(_cursor, _firstPage) ??
            MemberHttp.spaceArchive(
              type: .video,
              mid: mid,
              aid: _cursor,
              order: .pubdate,
              sort: .desc,
              includeCursor: _firstPage ? true : null,
            ));
    if (result case Success(:final response)) {
      final items = response.item ?? [];
      final last = items.lastOrNull;
      final cursor =
          last?.param ??
          (last?.bvid == null ? null : IdUtils.bv2av(last!.bvid!).toString());
      ended =
          response.hasNext == false ||
          items.isEmpty ||
          cursor == null ||
          cursor == _cursor;
      if (cursor != null) _cursor = cursor;
      _firstPage = false;
      return items
          .where((v) => v.isPgc != true && v.isPugv != true && v.bvid != null)
          .map(
            (v) => RcmdVideoItemModel.fromJson({
              'id': IdUtils.bv2av(v.bvid!),
              'bvid': v.bvid,
              'cid': v.cid,
              'goto': 'av',
              'uri': v.uri,
              'title': v.title,
              'pic': v.cover,
              'duration': v.duration,
              'owner': {'mid': mid, 'name': v.owner.name},
              'stat': <String, dynamic>{},
            }),
          )
          .toList();
    }
    throw StateError('UP主视频加载失败，请重试');
  }
}
