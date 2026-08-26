import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ss_subtitle/src/platform/video_picker.dart';

/// Returns the value that should be passed to the existing video-selection
/// flow for a dropped file, or `null` when [item] is not a video file.
///
/// Native [DropItem] paths are real filesystem paths and must be preserved so
/// subtitle acquisition can save beside the video. Web drops expose a Blob
/// URL as [DropItem.path], so the user-visible file name is used there instead.
String? videoPathFromDropItem(DropItem item, {bool isWeb = kIsWeb}) {
  if (item is DropItemDirectory) return null;

  final path = item.path.trim();
  final name = item.name.trim();
  if (!isSupportedVideoFileName(name) && !isSupportedVideoFileName(path)) {
    return null;
  }

  if (isWeb || path.isEmpty) {
    if (name.isNotEmpty) return name;
    return _basename(path);
  }
  return path;
}

/// Selects the first video from a drop operation.
///
/// A desktop drop may contain several files or directories. The app has one
/// current Video Profile, so only the first supported regular video file is
/// accepted; directories and unrelated files are ignored.
String? firstVideoPathFromDrop(
  Iterable<DropItem> items, {
  bool isWeb = kIsWeb,
}) {
  for (final item in items) {
    final path = videoPathFromDropItem(item, isWeb: isWeb);
    if (path != null) return path;
  }
  return null;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.split('/').last;
}

/// Wraps a selection surface with a native/Web [DropTarget].
///
/// The widget keeps its overlay inside the child's existing bounds, so it can
/// be added around a compact search card without changing the card's layout.
/// While a file is dragged over the surface it shows a lightweight visual
/// affordance; only supported video files trigger [onVideoDropped].
class VideoDropTarget extends StatefulWidget {
  const VideoDropTarget({
    required this.child,
    required this.onVideoDropped,
    this.onRejected,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final ValueChanged<String> onVideoDropped;
  final VoidCallback? onRejected;
  final bool enabled;

  @override
  State<VideoDropTarget> createState() => _VideoDropTargetState();
}

class _VideoDropTargetState extends State<VideoDropTarget> {
  bool _dragging = false;

  void _setDragging(bool dragging) {
    if (!mounted || _dragging == dragging) return;
    setState(() => _dragging = dragging);
  }

  void _onDropDone(DropDoneDetails details) {
    _setDragging(false);
    final path = firstVideoPathFromDrop(details.files);
    if (path == null) {
      widget.onRejected?.call();
      return;
    }
    widget.onVideoDropped(path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      key: const Key('video-drop-target'),
      enable: widget.enabled,
      onDragEntered: (_) => _setDragging(true),
      onDragExited: (_) => _setDragging(false),
      onDragDone: _onDropDone,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Semantics(
                  liveRegion: true,
                  label: '松开以选择视频文件',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      border: Border.all(color: scheme.primary, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            '松开以选择视频',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: scheme.onPrimary),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
