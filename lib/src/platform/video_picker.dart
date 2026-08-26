import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';

typedef VideoNamePicker = Future<String?> Function();

const _videoTypes = XTypeGroup(
  label: '视频文件',
  extensions: ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'm4v', 'ts', 'webm'],
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
