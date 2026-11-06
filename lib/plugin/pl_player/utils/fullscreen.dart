import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/utils/desktop/window_controller.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:flutter/services.dart'
    show SystemChrome, SystemUiOverlay, DeviceOrientation;

bool _isDesktopFullScreen = false;

void enterDesktopFullScreen({bool inAppFullScreen = false}) {
  if (!inAppFullScreen && !_isDesktopFullScreen) {
    WindowController.instance.window?.isFullScreen = _isDesktopFullScreen =
        true;
  }
}

void exitDesktopFullScreen() {
  if (_isDesktopFullScreen) {
    WindowController.instance.window?.isFullScreen = _isDesktopFullScreen =
        false;
  }
}

List<DeviceOrientation>? _lastOrientation;
Future<void>? _setPreferredOrientations(List<DeviceOrientation> orientations) {
  if (DeviceUtils.isChromeOS) return null;

  if (_lastOrientation == orientations) {
    return null;
  }
  _lastOrientation = orientations;
  return SystemChrome.setPreferredOrientations(orientations);
}

Future<void>? portraitUpMode() {
  return _setPreferredOrientations(const [.portraitUp]);
}

Future<void>? portraitDownMode() {
  return _setPreferredOrientations(const [.portraitDown]);
}

Future<void>? landscapeLeftMode() {
  return _setPreferredOrientations(const [.landscapeLeft]);
}

Future<void>? landscapeRightMode() {
  return _setPreferredOrientations(const [.landscapeRight]);
}

Future<void>? fullMode() {
  return _setPreferredOrientations(
    const [.portraitUp, .portraitDown, .landscapeLeft, .landscapeRight],
  );
}

bool _showSystemBar = true;
bool _statusBarOnly = false;
bool get showSystemBar_ => _showSystemBar;
Future<void>? hideSystemBar({bool force = false}) {
  if (!_showSystemBar && !_statusBarOnly && !force) {
    return null;
  }
  _showSystemBar = false;
  _statusBarOnly = false;
  return SystemChrome.setEnabledSystemUIMode(.immersiveSticky);
}

Future<void> showStatusBarOnly() {
  _showSystemBar = false;
  _statusBarOnly = true;
  return SystemChrome.setEnabledSystemUIMode(
    .manual,
    overlays: const [SystemUiOverlay.top],
  );
}

//退出全屏显示
Future<void>? showSystemBar() {
  if (_showSystemBar) {
    return null;
  }
  _showSystemBar = true;
  _statusBarOnly = false;
  return SystemChrome.setEnabledSystemUIMode(
    Platform.isAndroid && DeviceUtils.sdkInt < 29 ? .manual : .edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
}
