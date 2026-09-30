import 'dart:math';

import 'package:PiliPlus/pages/short_video/recommendation/candidate.dart';
import 'package:PiliPlus/pages/short_video/recommendation/user_profile.dart';

class RecommendationEngine {
  RecommendationEngine({Random? random}) : random = random ?? Random();
  final Random random;

  double score(ShortVideoCandidate c, ShortVideoProfile p, bool personalized) {
    var score = c.vertical == true ? 35.0 : (c.vertical == null ? 5.0 : 0.0);
    if (c.duration > 0 && c.duration <= 180) score += 12;
    if (personalized) {
      score += (p.authors['${c.author}'] ?? 0) * 1.4;
      score += (p.zones[c.zone] ?? 0) * 1.2;
      score +=
          c.keywords
              .fold<double>(0, (v, k) => v + (p.keywords[k] ?? 0))
              .clamp(-25, 25) *
          0.8;
    }
    if (p.recent.contains(c.aid)) score -= 1000;
    if (p.recentAuthors.contains(c.author)) score -= 15;
    return score;
  }

  List<ShortVideoCandidate> select(
    Iterable<ShortVideoCandidate> candidates,
    ShortVideoProfile profile, {
    int count = 15,
    bool personalized = true,
    List<ShortVideoCandidate> history = const [],
  }) {
    final pool = candidates
        .where((c) => !profile.disliked.contains(c.aid))
        .toList();
    final scores = {
      for (final c in pool)
        c.aid: score(c, profile, personalized) + random.nextDouble() * 6,
    };
    pool.sort((a, b) => scores[b.aid]!.compareTo(scores[a.aid]!));
    final result = <ShortVideoCandidate>[];
    final tail = [...history];
    while (pool.isNotEmpty && result.length < count) {
      final authors = tail
          .skip((tail.length - 8).clamp(0, tail.length))
          .map((c) => c.author)
          .toSet();
      var allowed = pool.where((c) {
        if (c.author > 0 && authors.contains(c.author)) return false;
        if (tail.isNotEmpty && c.similarTo(tail.last)) return false;
        if (c.zone != null &&
            tail.length >= 2 &&
            tail.last.zone == c.zone &&
            tail[tail.length - 2].zone == c.zone) {
          return false;
        }
        return true;
      }).toList();
      // Sparse feeds degrade gracefully rather than becoming unplayable.
      if (allowed.isEmpty) allowed = pool;
      final exploring =
          (history.length + result.length + 1) % 7 == 0 && allowed.length >= 3;
      final index = exploring
          ? (allowed.length ~/ 3) +
                random.nextInt((allowed.length ~/ 3).clamp(1, allowed.length))
          : 0;
      final chosen = allowed[index];
      result.add(chosen);
      tail.add(chosen);
      pool.remove(chosen);
    }
    return result;
  }
}
