import 'package:material_ui/material_ui.dart';

/// The direct fullscreen entry never lays out a detail page, even while loading.
/// The caller supplies the same video player used by ordinary detail fullscreen.
class ShortVideoFullscreenSurface extends StatelessWidget {
  const ShortVideoFullscreenSurface({
    super.key,
    required this.player,
    required this.ready,
    required this.failed,
    required this.onExit,
    required this.onRetry,
  });
  final Widget player;
  final bool ready, failed;
  final VoidCallback onExit, onRetry;
  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('short-video-direct-fullscreen'),
    color: Colors.black,
    child: SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          player,
          if (!ready) ...[
            const ColoredBox(color: Colors.black),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!failed)
                    const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    failed ? '全屏视频加载失败' : '正在加载全屏视频…',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (failed)
                    TextButton(onPressed: onRetry, child: const Text('重试')),
                ],
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  tooltip: '返回竖屏',
                  onPressed: onExit,
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
