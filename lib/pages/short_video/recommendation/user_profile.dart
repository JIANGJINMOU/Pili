import 'package:PiliPlus/pages/short_video/recommendation/candidate.dart';

class ShortVideoProfile {
  final authors = <String, double>{};
  final zones = <String, double>{};
  final keywords = <String, double>{};
  final recent = <int>{};
  final disliked = <int>{};
  final recentAuthors = <int>[];

  void seen(ShortVideoCandidate candidate) {
    recent
      ..remove(candidate.aid)
      ..add(candidate.aid);
    while (recent.length > 1000) {
      recent.remove(recent.first);
    }
    if (candidate.author > 0) {
      recentAuthors.add(candidate.author);
      if (recentAuthors.length > 8) recentAuthors.removeAt(0);
    }
  }

  void apply(ShortVideoCandidate candidate, double weight) {
    if (weight == 0 || !weight.isFinite) return;
    void update(Map<String, double> map, String? key, int limit) {
      if (key == null || key.isEmpty) return;
      final old = map.remove(key) ?? 0;
      map[key] = (old * 0.95 + weight).clamp(-40.0, 40.0);
      while (map.length > limit) {
        map.remove(map.keys.first);
      }
    }

    if (candidate.author > 0) update(authors, '${candidate.author}', 200);
    update(zones, candidate.zone, 100);
    for (final word in candidate.keywords) {
      update(keywords, word, 300);
    }
  }

  void dislike(ShortVideoCandidate candidate) {
    disliked
      ..remove(candidate.aid)
      ..add(candidate.aid);
    while (disliked.length > 1000) {
      disliked.remove(disliked.first);
    }
  }

  Map<String, dynamic> toMap() => {
    'version': 1,
    'authors': Map.of(authors),
    'zones': Map.of(zones),
    'keywords': Map.of(keywords),
    'recent': recent.toList(),
    'disliked': disliked.toList(),
    'recentAuthors': List.of(recentAuthors),
  };

  static ShortVideoProfile fromMap(Object? raw) {
    final p = ShortVideoProfile();
    if (raw is! Map || raw['version'] != 1) return p;
    void scores(String name, Map<String, double> target, int cap) {
      final data = raw[name];
      if (data is! Map) return;
      for (final entry in data.entries) {
        final value = entry.value;
        if (entry.key is String &&
            (entry.key as String).length <= 100 &&
            value is num &&
            value.isFinite) {
          target[entry.key as String] = value.toDouble().clamp(-40, 40);
          if (target.length > cap) target.remove(target.keys.first);
        }
      }
    }

    scores('authors', p.authors, 200);
    scores('zones', p.zones, 100);
    scores('keywords', p.keywords, 300);
    for (final key in ['recent', 'disliked', 'recentAuthors']) {
      final data = raw[key];
      if (data is! List) continue;
      final ids = data.whereType<int>().where((id) => id > 0).toList();
      if (key == 'recentAuthors') {
        p.recentAuthors.addAll(ids.skip((ids.length - 8).clamp(0, ids.length)));
      } else {
        (key == 'recent' ? p.recent : p.disliked).addAll(
          ids.skip((ids.length - 1000).clamp(0, ids.length)),
        );
      }
    }
    return p;
  }
}
