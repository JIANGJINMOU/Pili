import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';

Future<void> applyShortVideoSystemBars(bool showStatusBar) async {
  if (showStatusBar) {
    await showStatusBarOnly();
  } else {
    // Another route or the notification shade may have changed native overlays.
    await hideSystemBar(force: true);
  }
}
