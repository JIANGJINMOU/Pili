import 'dart:async';
import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:PiliPlus/utils/storage.dart';

import 'dart:math';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/pages/short_video/controller.dart';
import 'package:PiliPlus/pages/short_video/preferences.dart';
import 'package:PiliPlus/pages/short_video/preload_scheduler.dart';
import 'package:PiliPlus/pages/short_video/player_pool.dart';
import 'package:PiliPlus/pages/short_video/recommendation/candidate.dart';
import 'package:PiliPlus/pages/short_video/recommendation/recommendation_engine.dart';
import 'package:PiliPlus/pages/short_video/recommendation/recommendation_storage.dart';
import 'package:PiliPlus/pages/short_video/recommendation/user_profile.dart';
import 'package:PiliPlus/pages/short_video/recommendation/watch_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:media_kit/media_kit.dart';

RcmdVideoItemAppModel item(
  int id, {
  int? author,
  String? zone,
  bool? vertical = true,
  int duration = 60,
  String? title,
  int canPlay = 1,
  String goto = 'av',
}) => RcmdVideoItemAppModel.fromJson({
  'param': '$id',
  'bvid': 'BVtest$id',
  'title': title ?? 'title$id',
  'card_goto': goto,
  'cover_left_text_1': '0',
  'cover_left_text_2': '0',
  'can_play': canPlay,
  'player_args': {'aid': id, 'cid': id, 'duration': duration},
  'args': {'up_id': author ?? id, 'up_name': 'author', 'tname': zone},
  'uri': vertical == null
      ? null
      : 'bilibili://video/$id?player_width=${vertical ? 720 : 1280}&player_height=${vertical ? 1280 : 720}',
});

class MemoryStorage extends RecommendationStorage {
  ShortVideoProfile value = ShortVideoProfile();
  int writes = 0;
  @override
  ShortVideoProfile read() => value;
  @override
  Future<void> save(ShortVideoProfile profile) async {
    writes++;
    value = ShortVideoProfile.fromMap(profile.toMap());
  }

  @override
  Future<void> clear() async {
    value = ShortVideoProfile();
  }
}

class DisposalPlayer implements Player {
  Completer<void>? gate;
  bool throwDispose = false;
  @override
  Future<void> dispose() async {
    if (gate != null) await gate!.future;
    if (throwDispose) throw StateError('dispose');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('late watch checkpoints cannot restore a cleared profile', () async {
    final storage = MemoryStorage();
    final c = ShortVideoController(storage: storage);
    final oldRevision = c.profileRevision;
    c.recordWeight(item(1), 5, revision: oldRevision);
    await c.clearProfile();
    c.recordWeight(item(1), 8, revision: oldRevision);
    await c.flushProfile;
    expect(storage.value.authors, isEmpty);
    c.recordWeight(item(2), 5, revision: c.profileRevision);
    await c.flushProfile;
    expect(storage.value.authors['2'], 5);
  });
  test(
    'synchronous source failures retain original error and evict the cache',
    () async {
      final failure = StateError('resolver failed before returning a Future');
      var fail = true;
      final c = ShortVideoController(
        storage: MemoryStorage(),
        sourceResolver: (_) {
          if (fail) throw failure;
          return Future.value(
            const ShortVideoSource(url: 'ok', cid: 1, isVertical: true),
          );
        },
      );
      await expectLater(c.sourceFor(item(1)), throwsA(same(failure)));
      expect(c.sourceCacheCount, 0);
      fail = false;
      expect((await c.sourceFor(item(1))).url, 'ok');
    },
  );

  test(
    'clearing learned history preserves visible queue deduplication',
    () async {
      final c = ShortVideoController(
        storage: MemoryStorage(),
        metadataLoader: (_) async =>
            Success(List.generate(4, (i) => item(i + 1))),
      );
      c.items.addAll([item(1), item(2), item(3)]);
      await c.clearProfile();
      await c.loadMore();
      expect(c.items.map((v) => v.aid).toList(), [1, 2, 3, 4]);
      expect(c.profile.recent, isEmpty);
    },
  );

  test(
    'orientation change supersedes pending refresh without stale results',
    () async {
      final oldResponse =
          Completer<LoadingState<List<BaseRcmdVideoItemModel>>>();
      var calls = 0;
      final c = ShortVideoController(
        storage: MemoryStorage(),
        metadataLoader: (_) {
          calls++;
          if (calls == 1) return oldResponse.future;
          return Future.value(
            Success(List.generate(30, (i) => item(1000 + i))),
          );
        },
      );
      final old = c.refreshFeed();
      c.preferences = const ShortVideoPreferences(onlyVertical: true);
      await c.refreshFeed();
      expect(calls, 2);
      expect(c.items, hasLength(15));
      final ids = c.items.map((v) => v.aid).toList();
      oldResponse.complete(Success([item(1, vertical: false)]));
      await old;
      expect(c.items.map((v) => v.aid).toList(), ids);
      expect(c.isInitialLoading.value, isFalse);
    },
  );

  test(
    'settings-only clear follows pending writes from a previous controller',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pili-recommendation-',
      );
      Hive.init(directory.path);
      GStorage.localCache = await Hive.openBox('recommendation');
      try {
        final controller = ShortVideoController()
          ..recordExposure(item(1))
          ..recordWeight(item(1), 8);
        await RecommendationStorage().clear();
        await controller.flushProfile;
        expect(RecommendationStorage().read().authors, isEmpty);
        expect(RecommendationStorage().read().recent, isEmpty);
        expect(
          GStorage.localCache.containsKey(RecommendationStorage.key),
          isFalse,
        );
      } finally {
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('URL cache stays at six and failed sources are retryable', () async {
    var requests = 0;
    var fail = false;
    final c = ShortVideoController(
      storage: MemoryStorage(),
      sourceResolver: (video) async {
        requests++;
        if (fail) throw StateError('network');
        return ShortVideoSource(
          url: 'url${video.aid}',
          cid: video.aid!,
          isVertical: true,
        );
      },
    );
    for (var i = 1; i <= 20; i++) {
      await c.sourceFor(item(i));
    }
    expect(c.sourceCacheCount, 6);
    expect(requests, 20);
    await c.sourceFor(item(20));
    expect(requests, 20);
    fail = true;
    await expectLater(c.sourceFor(item(21)), throwsStateError);
    fail = false;
    await c.sourceFor(item(21));
    expect(requests, 22);
    expect(c.sourceCacheCount, lessThanOrEqualTo(6));
  });

  test('metadata eligibility and unknown/malformed orientation', () {
    expect(ShortVideoCandidate.playable(item(1)), isTrue);
    expect(ShortVideoCandidate.playable(item(1, goto: 'ad_av')), isFalse);
    expect(ShortVideoCandidate.playable(item(1, canPlay: 0)), isFalse);
    expect(ShortVideoCandidate.orientation(null), isNull);
    expect(ShortVideoCandidate.orientation('bilibili://video/1?x=%'), isNull);
    expect(ShortVideoCandidate(item(1)).vertical, isTrue);
    expect(ShortVideoCandidate(item(1, vertical: false)).vertical, isFalse);
    expect(
      ShortVideoCandidate.tokenize('测试标题' * 100).length,
      lessThanOrEqualTo(12),
    );
  });
  test(
    'baseline and optional profile ranking preserve upstream candidates',
    () {
      final engine = RecommendationEngine(random: Random(1));
      final profile = ShortVideoProfile();
      final vertical = ShortVideoCandidate(item(1));
      final horizontal = ShortVideoCandidate(item(2, vertical: false));
      final unknown = ShortVideoCandidate(item(3, vertical: null));
      expect(engine.score(vertical, profile, false), 47);
      expect(engine.score(horizontal, profile, false), 12);
      expect(engine.score(unknown, profile, false), 17);
      profile.apply(horizontal, 40);
      expect(engine.score(horizontal, profile, true), greaterThan(47));
      expect(engine.score(horizontal, profile, false), 12);
      profile.seen(vertical);
      expect(engine.score(vertical, profile, false), lessThan(-900));
    },
  );
  test('diversity avoids last eight authors and three consecutive zones', () {
    final candidates = List.generate(
      60,
      (i) => ShortVideoCandidate(
        item(i + 1, author: i % 12 + 1, zone: 'z${i % 3}'),
      ),
    );
    final selected = RecommendationEngine(random: Random(1))
        .select(candidates, ShortVideoProfile(), count: 15);
    expect(selected.map((c) => c.aid).toSet(), hasLength(15));
    for (var i = 1; i < selected.length; i++) {
      final recent = selected.sublist((i - 8).clamp(0, i), i);
      expect(recent.any((c) => c.author == selected[i].author), isFalse);
      if (i >= 2) {
        expect(
          selected[i].zone == selected[i - 1].zone &&
              selected[i].zone == selected[i - 2].zone,
          isFalse,
        );
      }
    }
  });
  test('sparse diversity fallback never includes disliked IDs', () {
    final p = ShortVideoProfile()..dislike(ShortVideoCandidate(item(1)));
    final result = RecommendationEngine(random: Random(2)).select(
      List.generate(4, (i) => ShortVideoCandidate(item(i + 1, author: 1))),
      p,
    );
    expect(result.map((c) => c.aid), isNot(contains(1)));
    expect(result, hasLength(3));
  });
  test('local history and interest maps have strict size limits', () {
    final p = ShortVideoProfile();
    for (var i = 1; i <= 1100; i++) {
      final c = ShortVideoCandidate(item(i, zone: 'z$i'));
      p
        ..seen(c)
        ..apply(c, 5)
        ..dislike(c);
    }
    expect(p.recent, hasLength(1000));
    expect(p.disliked, hasLength(1000));
    expect(p.authors, hasLength(200));
    expect(p.zones, hasLength(100));
    expect(p.keywords, hasLength(300));
    expect(p.recentAuthors, hasLength(8));
    final restored = ShortVideoProfile.fromMap(p.toMap());
    expect(restored.toMap(), p.toMap());
    expect(
      ShortVideoProfile.fromMap({
        'version': 1,
        'authors': {'x': double.nan, 'y': 'bad'},
      }).authors,
      isEmpty,
    );
    expect(ShortVideoProfile.fromMap('bad').recent, isEmpty);
  });
  test('watch excludes buffering/background and uses elapsed time not seek position', () {
    var now = Duration.zero;
    final watch = ShortVideoWatchSession(now: () => now)..playing(true);
    now = const Duration(seconds: 10);
    watch.playing(false);
    now = const Duration(seconds: 300);
    expect(watch.settle(duration: const Duration(seconds: 20)), 1);
    expect(watch.watchedMs, 10000);
    expect(watch.settle(duration: const Duration(seconds: 20)), 0);
    watch.playing(true, rate: 2);
    now += const Duration(seconds: 5);
    watch.playing(false);
    expect(
      watch.settle(duration: const Duration(seconds: 20), completed: true),
      3,
    );
    expect(
      watch.settle(duration: const Duration(seconds: 20), leaving: true),
      0,
    );
  });
  test('quick skip only settles on departure, failures do not train', () {
    var now = Duration.zero;
    final watch = ShortVideoWatchSession(now: () => now)..playing(true);
    now = const Duration(seconds: 1);
    watch.playing(false);
    expect(watch.settle(duration: const Duration(seconds: 60)), 0);
    expect(
      watch.settle(duration: const Duration(seconds: 60), leaving: true),
      -5,
    );
    expect(
      watch.settle(duration: const Duration(seconds: 60), leaving: true),
      0,
    );
    final failed = ShortVideoWatchSession(now: () => now)..playing(true);
    now += const Duration(seconds: 1);
    failed.failed = true;
    expect(
      failed.settle(duration: const Duration(seconds: 60), leaving: true),
      0,
    );
    final untouched = ShortVideoWatchSession();
    expect(
      untouched.settle(duration: const Duration(seconds: 60), leaving: true),
      0,
    );
  });
  test('explicit feedback once, undo only previously credited actions', () {
    final w = ShortVideoWatchSession();
    expect(w.feedback(ShortVideoFeedback.favorite, enabled: false), 0);
    expect(w.feedback(ShortVideoFeedback.like), 5);
    expect(w.feedback(ShortVideoFeedback.like), 0);
    expect(w.feedback(ShortVideoFeedback.like, enabled: false), -5);
    expect(w.feedback(ShortVideoFeedback.like, enabled: false), 0);
  });
  test(
    'initial pool uses at most three metadata batches and zero playback URLs',
    () async {
      var calls = 0;
      final c = ShortVideoController(
        storage: MemoryStorage(),
        metadataLoader: (index) async {
          calls++;
          return Success(List.generate(12, (i) => item(index * 12 + i + 1)));
        },
      );
      await c.refreshFeed();
      expect(calls, 3);
      expect(c.items, hasLength(15));
      expect(c.candidateCount, 21);
      expect(c.sourceCacheCount, 0);
      await c.loadMore();
      expect(calls, 3); // consume existing metadata before more network work
      expect(c.items, hasLength(30));
      expect(c.sourceCacheCount, 0);
    },
  );
  test('duplicates, recent and strict vertical filtering cannot trigger unbounded fetch', () async {
    var calls = 0;
    final storage = MemoryStorage();
    storage.value.seen(ShortVideoCandidate(item(1)));
    final c = ShortVideoController(
      storage: storage,
      preferences: const ShortVideoPreferences(onlyVertical: true),
      metadataLoader: (_) async {
        calls++;
        return Success([
          item(1),
          item(2, vertical: false),
          item(3, vertical: null),
          item(4),
          item(4),
          item(5, canPlay: 0),
          item(6, goto: 'ad_av'),
        ]);
      },
    );
    await c.refreshFeed();
    expect(calls, 3);
    expect(c.items.map((i) => i.aid), [4]);
    await c.loadMore();
    expect(calls, 6);
    expect(c.items, hasLength(1));
  });
  test(
    'bounded metadata, queue compaction, and no duplicate long-session IDs',
    () async {
      final c = ShortVideoController(
        storage: MemoryStorage(),
        metadataLoader: (index) async =>
            Success(List.generate(100, (i) => item(index * 100 + i + 1))),
      );
      await c.refreshFeed();
      expect(c.candidateCount, 85);
      final seen = <int>{};
      for (var round = 0; round < 20; round++) {
        await c.loadMore();
        expect(c.candidateCount, lessThanOrEqualTo(100));
        if (c.items.length >= 45) {
          final current = c.items[30];
          for (final i in c.items.take(29)) {
            expect(seen.add(i.aid!), isTrue);
          }
          expect(c.trimBefore(30), 29);
          expect(identical(c.items[1], current), isTrue);
        }
        expect(c.items.length, lessThan(60));
      }
    },
  );
  test('refresh invalidates an older loadMore response', () async {
    final gate = Completer<LoadingState<List<BaseRcmdVideoItemModel>>>();
    var delay = false;
    var base = 0;
    final c = ShortVideoController(
      storage: MemoryStorage(),
      metadataLoader: (index) async {
        if (delay) {
          delay = false;
          return gate.future;
        }
        return Success(
          List.generate(30, (i) => item(base + index * 30 + i + 1)),
        );
      },
    );
    await c.refreshFeed();
    delay = true;
    final old = c.loadMore();
    base = 1000;
    await c.refreshFeed();
    gate.complete(Success(List.generate(30, (i) => item(500 + i))));
    await old;
    expect(c.items.every((i) => i.aid! > 1000), isTrue);
    expect(c.isLoadingMore.value, isFalse);
  });
  test(
    'local privacy switch and clear are serialized after queued writes',
    () async {
      final storage = MemoryStorage();
      final c = ShortVideoController(storage: storage)
        ..recordWeight(item(1), 5)
        ..recordExposure(item(1));
      await c.clearProfile();
      expect(storage.value.authors, isEmpty);
      expect(storage.value.recent, isEmpty);
      c
        ..preferences = const ShortVideoPreferences(personalized: false)
        ..recordWeight(item(2), 8);
      await c.flushProfile;
      expect(storage.value.authors, isEmpty);
      c.dislike(item(2));
      await c.flushProfile;
      expect(storage.value.disliked, contains(2));
    },
  );
  test('preload waits 400ms and rapid scrolling replaces pending decision', () {
    fakeAsync((time) {
      final indices = <int>[];
      final s = ShortVideoPreloadScheduler(
        indices.add,
        networkAllowed: () async => true,
      )..schedule(0);
      time.elapse(const Duration(milliseconds: 399));
      expect(indices, isEmpty);
      s.schedule(4);
      time.elapse(const Duration(milliseconds: 400));
      expect(indices, [4]);
      s.dispose();
    });
  });
  test('preload cancellation also invalidates an in-flight network check', () {
    fakeAsync((time) {
      final gate = Completer<bool>();
      final indices = <int>[];
      final s = ShortVideoPreloadScheduler(
        indices.add,
        networkAllowed: () => gate.future,
      )..schedule(1);
      time.elapse(const Duration(milliseconds: 400));
      s.cancel();
      gate.complete(true);
      time.flushMicrotasks();
      expect(indices, isEmpty);
      s.dispose();
    });
  });
  test('unknown/disallowed network never creates preload', () {
    fakeAsync((time) {
      final indices = <int>[];
      final s = ShortVideoPreloadScheduler(
        indices.add,
        networkAllowed: () async => false,
      )..schedule(0);
      time.elapse(const Duration(seconds: 2));
      expect(indices, isEmpty);
      s.dispose();
    });
  });
  test('native player reservations include pending disposal; stale waiters never create', () async {
    final pool = ShortVideoPlayerPool();
    final p = List.generate(3, (_) => DisposalPlayer());
    for (final player in p) {
      await pool.acquire(() async => (player: player, video: null), () => true);
    }
    expect(pool.reserved, 3);
    var relevant = true;
    var created = false;
    final waiting = pool.acquire(() async {
      created = true;
      return (player: DisposalPlayer(), video: null);
    }, () => relevant);
    p.first.gate = Completer<void>();
    final releasing = pool.release(p.first);
    await Future<void>.delayed(Duration.zero);
    expect(pool.reserved, 3);
    expect(created, isFalse);
    relevant = false;
    p.first.gate!.complete();
    await releasing;
    expect(await waiting, isNull);
    expect(created, isFalse);
    for (final player in p.skip(1)) {
      await pool.release(player);
    }
    expect(pool.reserved, 0);
  });
  test('failed stale disposal frees a reservation exactly once', () async {
    final pool = ShortVideoPlayerPool();
    var relevant = true;
    await expectLater(
      pool.acquire(() async {
        relevant = false;
        return (player: DisposalPlayer()..throwDispose = true, video: null);
      }, () => relevant),
      throwsStateError,
    );
    expect(pool.reserved, 0);
  });
}
