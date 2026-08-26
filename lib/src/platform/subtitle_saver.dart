import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

typedef SaveLocationPicker = Future<String?> Function({
  required String suggestedName,
  required String extension,
});
typedef SubtitleBytesWriter = Future<void> Function({
  required String path,
  required String name,
  required Uint8List bytes,
  required String mimeType,
});
typedef FallbackSubtitleSaver = Future<bool> Function({
  required String baseName,
  required String extension,
  required Uint8List bytes,
  required String mimeType,
});

/// Hands a subtitle artifact to the platform and chooses its save location.
class PlatformSubtitleSaver {
  PlatformSubtitleSaver({
    TargetPlatform? platform,
    bool? isWeb,
    SaveLocationPicker? windowsLocationPicker,
    SubtitleBytesWriter? bytesWriter,
    FallbackSubtitleSaver? fallbackSaver,
  }) : _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb ?? kIsWeb,
       _windowsLocationPicker =
           windowsLocationPicker ?? _pickWindowsSaveLocation,
       _bytesWriter = bytesWriter ?? _writeBytes,
       _fallbackSaver = fallbackSaver ?? _saveWithFileSaver;

  final TargetPlatform _platform;
  final bool _isWeb;
  final SaveLocationPicker _windowsLocationPicker;
  final SubtitleBytesWriter _bytesWriter;
  final FallbackSubtitleSaver _fallbackSaver;

  Future<bool> save({
    required String baseName,
    required String extension,
    required Uint8List bytes,
    required String mimeType,
    String? sourceVideoPath,
  }) async {
    if (!_isWeb && _platform == TargetPlatform.windows) {
      final name = '$baseName.$extension';
      final path =
          _subtitlePathBesideVideo(sourceVideoPath ?? '', name) ??
          await _windowsLocationPicker(
            suggestedName: name,
            extension: extension,
          );
      if (path == null) return false;
      await _bytesWriter(
        path: path,
        name: name,
        bytes: bytes,
        mimeType: mimeType,
      );
      return true;
    }

    return _fallbackSaver(
      baseName: baseName,
      extension: extension,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  /// Returns the subtitle path next to a selected video file.
  ///
  /// The picker returns an absolute path on native Windows. Keeping this
  /// small path operation here lets the save flow avoid reopening a save
  /// dialog while retaining the dialog as a backwards-compatible fallback
  /// for manually entered video names.
  static String? _subtitlePathBesideVideo(String sourceVideoPath, String name) {
    final normalized = sourceVideoPath.trim();
    if (normalized.isEmpty) return null;
    final separatorIndex = normalized.lastIndexOf(RegExp(r'[\\/]'));
    if (separatorIndex < 0) return null;
    return '${normalized.substring(0, separatorIndex + 1)}$name';
  }

  static Future<String?> _pickWindowsSaveLocation({
    required String suggestedName,
    required String extension,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        XTypeGroup(label: '字幕文件', extensions: [extension]),
      ],
    );
    return location?.path;
  }

  static Future<void> _writeBytes({
    required String path,
    required String name,
    required Uint8List bytes,
    required String mimeType,
  }) => XFile.fromData(bytes, name: name, mimeType: mimeType).saveTo(path);

  static Future<bool> _saveWithFileSaver({
    required String baseName,
    required String extension,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final path = await FileSaver.instance.saveAs(
      name: baseName,
      bytes: bytes,
      fileExtension: extension,
      mimeType: MimeType.custom,
      customMimeType: mimeType,
    );
    return path != null;
  }
}
