import 'dart:async';

import 'package:dio/dio.dart';
import 'package:PiliPlus/services/ai_chat/ai_chat_service.dart';
import 'package:PiliPlus/pages/short_video/subtitle_preferences.dart';

import 'package:PiliPlus/grpc/dm.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

class ShortVideoCaption {
  const ShortVideoCaption(this.from, this.to, this.text);
  final double from, to;
  final String text;

  static List<ShortVideoCaption> parse(List body) {
    final captions = <ShortVideoCaption>[];
    for (final row in body.take(10000)) {
      if (row is! Map) continue;
      final from = row['from'], to = row['to'], text = row['content'];
      if (from is num &&
          to is num &&
          text is String &&
          from.isFinite &&
          to.isFinite &&
          from >= 0 &&
          to > from &&
          text.trim().isNotEmpty) {
        captions.add(ShortVideoCaption(from.toDouble(), to.toDouble(), text));
      }
    }
    return captions..sort((a, b) => a.from.compareTo(b.from));
  }

  static String at(List<ShortVideoCaption> captions, Duration position) {
    final seconds = position.inMilliseconds / 1000;
    var low = 0, high = captions.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (captions[mid].from <= seconds) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low == 0) return '';
    final caption = captions[low - 1];
    return seconds < caption.to ? caption.text : '';
  }
}

typedef ShortVideoSubtitleLoader = Future<List<ShortVideoCaption>> Function(
  int aid,
  String bvid,
  int cid,
);

Future<List<ShortVideoCaption>> loadShortVideoSubtitles(
  int aid,
  String bvid,
  int cid, {
  ShortVideoSubtitleLanguage language = ShortVideoSubtitleLanguage.auto,
}) async {
  final result = await VideoHttp.playInfo(bvid: bvid, cid: cid);
  if (result case Success(:final response)) {
    final tracks = [...?response.subtitle?.subtitles];
    // Reuse the detail player's guest fallback, without bypassing login gates.
    if (tracks.isEmpty && !Accounts.heartbeat.isLogin) {
      final fallback = await DmGrpc.dmView(aid, cid);
      if (fallback case Success(:final response)) {
        tracks.addAll(
          response.subtitle.subtitles.map(
            (track) => Subtitle(
              lan: track.lan,
              subtitleUrl: track.subtitleUrl,
            ),
          ),
        );
      }
    }
    final track = selectShortVideoSubtitle(tracks, language);
    if (track == null) return const [];
    // The shared HTTP helper accepts protocol-relative URLs.
    final url = track.subtitleUrl!.replaceFirst(RegExp(r'^https?:'), '');
    final body = await VideoHttp.fetchSubtitleBody(url);
    if (body == null) throw StateError('字幕内容为空');
    return ShortVideoCaption.parse(body);
  }
  throw StateError('字幕加载失败');
}

Subtitle? selectShortVideoSubtitle(
  Iterable<Subtitle> tracks,
  ShortVideoSubtitleLanguage language,
) {
  final available = tracks
      .where((t) => t.subtitleUrl?.isNotEmpty == true)
      .toList();
  bool matches(Subtitle track) =>
      track.lan
          .toLowerCase()
          .replaceFirst('ai-', '')
          .split(RegExp('[-_]'))
          .first ==
      language.code;
  available.sort((a, b) {
    if (language != ShortVideoSubtitleLanguage.auto &&
        matches(a) != matches(b)) {
      return matches(a) ? -1 : 1;
    }
    return a.compareTo(b);
  });
  return available.firstOrNull;
}

typedef ShortVideoSubtitleTranslator = Future<String> Function({
  required String text,
  required String target,
  required CancelToken cancelToken,
});

/// Only the visible cue can be translated; never upload a whole subtitle file.
class ShortVideoSubtitles extends StatefulWidget {
  const ShortVideoSubtitles({
    super.key,
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.position,
    this.loader,
    this.preferences = const ShortVideoSubtitlePreferences(),
    this.translationActive = true,
    this.translator = AiChatService.translateSubtitleText,
  });
  final int aid, cid;
  final String bvid;
  final ValueListenable<Duration> position;
  final ShortVideoSubtitleLoader? loader;
  final ShortVideoSubtitlePreferences preferences;
  final bool translationActive;
  final ShortVideoSubtitleTranslator translator;

  @override
  State<ShortVideoSubtitles> createState() => _ShortVideoSubtitlesState();
}

class _ShortVideoSubtitlesState extends State<ShortVideoSubtitles>
    with WidgetsBindingObserver {
  List<ShortVideoCaption> _captions = const [];
  String? _status = '正在加载字幕…';
  int _generation = 0, _translationGeneration = 0;
  Timer? _statusTimer, _debounce;
  CancelToken? _request;
  final _translations = <String, String>{};
  String _scheduledCue = '';
  bool _translationFailed = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.position.addListener(_onPosition);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // Background Flutter frames may stop: cancellation must not await a rebuild.
    if (_foreground) {
      _onPosition();
    } else {
      _cancelTranslation();
    }
  }

  void _cancelTranslation({bool clear = false}) {
    ++_translationGeneration;
    _debounce?.cancel();
    _request?.cancel('Subtitle context changed');
    _request = null;
    _scheduledCue = '';
    if (clear) {
      _translations.clear();
      _translationFailed = false;
    }
  }

  @override
  void didUpdateWidget(covariant ShortVideoSubtitles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      oldWidget.position.removeListener(_onPosition);
      widget.position.addListener(_onPosition);
    }
    final reload =
        oldWidget.cid != widget.cid ||
        oldWidget.bvid != widget.bvid ||
        oldWidget.aid != widget.aid ||
        oldWidget.preferences.language != widget.preferences.language;
    if (reload) {
      _cancelTranslation(clear: true);
      _captions = const [];
      _status = '正在加载字幕…';
      unawaited(_load());
    } else {
      if (oldWidget.preferences.target != widget.preferences.target ||
          oldWidget.preferences.translate != widget.preferences.translate) {
        _cancelTranslation(clear: true);
      } else if (oldWidget.translationActive != widget.translationActive) {
        _cancelTranslation();
      }
      _onPosition();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _statusTimer?.cancel();
    try {
      final captions =
          await (widget.loader?.call(widget.aid, widget.bvid, widget.cid) ??
                  loadShortVideoSubtitles(
                    widget.aid,
                    widget.bvid,
                    widget.cid,
                    language: widget.preferences.language,
                  ))
              .timeout(const Duration(seconds: 15));
      if (!mounted || generation != _generation) return;
      setState(() {
        _captions = captions;
        _status = captions.isEmpty ? '该视频暂无可用字幕' : null;
      });
      _onPosition();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _status = '字幕加载失败，可关闭后重新开启');
    }
    if (_status != null) {
      _statusTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _status = null);
      });
    }
  }

  void _onPosition() {
    if (!_foreground ||
        !widget.preferences.translate ||
        !widget.translationActive ||
        _translationFailed ||
        _request != null) {
      return;
    }
    final cue = ShortVideoCaption.at(_captions, widget.position.value);
    if (cue == _scheduledCue) return;
    _scheduledCue = cue;
    _debounce?.cancel();
    if (cue.isEmpty || cue.length > 600 || _translations.containsKey(cue)) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _translate(cue));
  }

  Future<void> _translate(String cue) async {
    final generation = _translationGeneration;
    final token = _request = CancelToken();
    try {
      final translated = await widget
          .translator(
            text: cue,
            target: widget.preferences.target.label,
            cancelToken: token,
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              token.cancel('Subtitle translation timed out');
              throw TimeoutException('Subtitle translation timed out');
            },
          );
      if (!mounted || generation != _translationGeneration) return;
      if (translated.trim().isEmpty || translated.length > 2000) {
        throw StateError('Invalid subtitle translation');
      }
      setState(() {
        if (_translations.length >= 80) {
          _translations.remove(_translations.keys.first);
        }
        _translations[cue] = translated.trim();
      });
    } catch (_) {
      if (!mounted || generation != _translationGeneration) return;
      // Fail closed to original text; no automatic retry or request storm.
      setState(() => _translationFailed = true);
    } finally {
      if (mounted && generation == _translationGeneration) {
        _request = null;
        _scheduledCue = '';
        _onPosition();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.position.removeListener(_onPosition);
    _cancelTranslation();
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ValueListenableBuilder<Duration>(
      valueListenable: widget.position,
      builder: (context, position, _) {
        final original = _status ?? ShortVideoCaption.at(_captions, position);
        if (original.isEmpty) return const SizedBox.shrink();
        final p = widget.preferences;
        final translated = p.translate ? _translations[original] : null;
        final text = translated == null || translated == original
            ? original
            : p.bilingual
            ? '$original\n$translated'
            : translated;
        return Align(
          heightFactor: 1,
          widthFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: p.backgroundOpacity),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      text,
                      textAlign: p.align.align,
                      maxLines: p.bilingual && translated != null
                          ? 6
                          : p.lines.count,
                      overflow: TextOverflow.ellipsis,
                      style: p.textStyle,
                    ),
                  ),
                  if (_translationFailed)
                    const Text(
                      '翻译暂不可用，显示原字幕',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
