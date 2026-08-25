import 'package:file_selector/file_selector.dart';

typedef VideoNamePicker = Future<String?> Function();

const _videoTypes = XTypeGroup(
  label: '视频文件',
  extensions: ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'm4v', 'ts', 'webm'],
);

Future<String?> pickVideoName() async {
  final file = await openFile(acceptedTypeGroups: const [_videoTypes]);
  return file?.name;
}
