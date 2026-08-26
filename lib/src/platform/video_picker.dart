import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';

typedef VideoNamePicker = Future<String?> Function();

/// Extensions accepted by both the native picker and the drop target.
const supportedVideoExtensions = <String>[
  'mp4',
  'mkv',
  'avi',
  'mov',
  'wmv',
  'm4v',
  'ts',
  'webm',
];

bool isSupportedVideoFileName(String value) {
  final normalized = value.trim().replaceAll('\\', '/');
  final basename = normalized.split('/').last;
  final queryStart = basename.indexOf('?');
  final withoutQuery = queryStart < 0
      ? basename
      : basename.substring(0, queryStart);
  final dot = withoutQuery.lastIndexOf('.');
  if (dot < 0 || dot == withoutQuery.length - 1) return false;
  return supportedVideoExtensions.contains(
    withoutQuery.substring(dot + 1).toLowerCase(),
  );
}

const _videoTypes = XTypeGroup(
  label: '视频文件',
  extensions: supportedVideoExtensions,
);

Future<String?> pickVideoName() async {
  final file = await openFile(acceptedTypeGroups: const [_videoTypes]);
  if (file == null) return null;
  // Browsers expose an object URL as XFile.path; keep the user-visible name
  // there, while native pickers provide the absolute path needed for an
  // adjacent subtitle save.
  if (kIsWeb || file.path.isEmpty) return file.name;
  return file.path;
}
