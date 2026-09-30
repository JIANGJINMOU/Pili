import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

typedef ShortVideoPlayerHandle = ({Player player, VideoController? video});
typedef ShortVideoPlayerFactory = Future<ShortVideoPlayerHandle> Function();

/// Keep native creation together; lifecycle/pause decisions belong to the page.
Future<ShortVideoPlayerHandle> createShortVideoPlayer() async {
  final player = await Player.create(
    configuration: const PlayerConfiguration(
      logLevel: kDebugMode ? MPVLogLevel.warn : MPVLogLevel.error,
    ),
  );
  try {
    final video = await VideoController.create(
      player,
      configuration: const VideoControllerConfiguration(
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );
    return (player: player, video: video);
  } catch (_) {
    await player.dispose();
    rethrow;
  }
}
