import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';

class ShortVideoCandidate {
  ShortVideoCandidate(this.item)
    : vertical = orientation(item.uri),
      keywords = tokenize(item.title);
  final BaseRcmdVideoItemModel item;
  final bool? vertical;
  final Set<String> keywords;
  int get aid => item.aid!;
  int get author => item.owner.mid ?? 0;
  String? get zone => item is RcmdVideoItemAppModel
      ? (item as RcmdVideoItemAppModel).tname
      : null;
  int get duration => item.duration;

  static bool playable(BaseRcmdVideoItemModel item) =>
      item.goto == 'av' &&
      (item.aid ?? 0) > 0 &&
      (item is! RcmdVideoItemAppModel ||
          ((item.canPlay == null || item.canPlay == 1) &&
              !(item.cardType?.startsWith('ad_') ?? false)));

  static bool? orientation(String? uri) {
    Map<String, String>? params;
    try {
      params = Uri.tryParse(uri ?? '')?.queryParameters;
    } on FormatException {
      return null;
    }
    final width = int.tryParse(params?['player_width'] ?? '');
    final height = int.tryParse(params?['player_height'] ?? '');
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return params?['player_rotate'] == '1' ? width > height : height > width;
  }

  // Bounded title tokens; no extra metadata/tag requests or remote NLP.
  static Set<String> tokenize(String title) {
    final result = <String>{};
    final normalized = title.toLowerCase();
    final bounded = normalized.substring(0, normalized.length.clamp(0, 200));
    for (final match in RegExp(
      r'[a-z0-9]{2,20}|[\u4e00-\u9fff]{2,}',
      caseSensitive: false,
    ).allMatches(bounded)) {
      final word = match.group(0)!;
      if (RegExp(r'^[\u4e00-\u9fff]').hasMatch(word)) {
        for (var i = 0; i < word.length - 1 && result.length < 12; i++) {
          result.add(word.substring(i, i + 2));
        }
      } else {
        result.add(word);
      }
      if (result.length >= 12) break;
    }
    return result;
  }

  bool similarTo(ShortVideoCandidate other) {
    if (item.title == other.item.title) return true;
    if (keywords.isEmpty || other.keywords.isEmpty) return false;
    return keywords.intersection(other.keywords).length /
            keywords.union(other.keywords).length >
        0.65;
  }
}
