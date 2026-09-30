import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'package:PiliPlus/pages/short_video/player.dart';

/// Reservations include in-flight creation and pending native disposal.
class ShortVideoPlayerPool {
  int _reserved = 0;
  Completer<void> _changed = Completer<void>();
  final _players = <Player>{};
  int get reserved => _reserved;
  Future<ShortVideoPlayerHandle?> acquire(
    ShortVideoPlayerFactory create,
    bool Function() relevant,
  ) async {
    while (_reserved >= 3) {
      await _changed.future;
      if (!relevant()) return null;
    }
    if (!relevant()) return null;
    _reserved++;
    late final ShortVideoPlayerHandle handle;
    try {
      handle = await create();
    } catch (_) {
      _free();
      rethrow;
    }
    _players.add(handle.player);
    if (!relevant()) {
      await release(handle.player);
      return null;
    }
    return handle;
  }

  Future<void> release(Player player) async {
    if (!_players.remove(player)) return;
    try {
      await player.dispose();
    } finally {
      _free();
    }
  }

  void _free() {
    _reserved--;
    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();
  }
}
