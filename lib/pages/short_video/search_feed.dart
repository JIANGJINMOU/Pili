import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/common/search/search_type.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models/search/result.dart';

class ShortVideoSearchFeed {
  ShortVideoSearchFeed(String query, {this.fetch}) : query = query.trim();
  late final _words = query
      .toLowerCase()
      .replaceAll('#', ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  final String query;
  final Future<LoadingState<SearchVideoData>> Function(String, int)? fetch;
  int _page = 1;
  bool ended = false;

  bool _matches(SearchVideoItemModel item) {
    final text = '${item.title} ${item.tag ?? ''}'.toLowerCase();
    return _words.isNotEmpty && _words.every(text.contains);
  }

  Future<List<BaseRcmdVideoItemModel>> load() async {
    for (var batch = 0; batch < 3 && !ended; batch++) {
      final result =
          await (fetch?.call(query, _page) ??
              SearchHttp.searchByType<SearchVideoData>(
                searchType: SearchType.video,
                keyword: query,
                page: _page,
                order: 'totalrank',
                onSuccess: (_) {},
              ));
      if (result case Success(:final response)) {
        final items = response.list ?? [];
        ended =
            items.isEmpty ||
            (response.numResults != null && _page * 20 >= response.numResults!);
        _page++;
        final videos = items
            .where(
              (v) =>
                  (v.aid ?? 0) > 0 &&
                  v.isLive != true &&
                  v.isPugv != true &&
                  _matches(v),
            )
            .map(
              (v) => RcmdVideoItemModel.fromJson({
                'id': v.aid,
                'bvid': v.bvid,
                'cid': v.cid,
                'goto': 'av',
                'title': v.title,
                'pic': v.cover,
                'duration': v.duration,
                'owner': {'mid': v.owner.mid, 'name': v.owner.name},
                'stat': {'view': v.stat.view, 'danmaku': v.stat.danmu},
              }),
            )
            .toList();
        if (videos.isNotEmpty) return videos;
      } else {
        throw StateError('搜索失败，请重试');
      }
    }
    return [];
  }
}
