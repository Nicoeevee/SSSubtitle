import 'dart:io';

Future<bool> openVideoFolderImpl(String videoPath) async {
  final normalized = videoPath.trim();
  if (normalized.isEmpty) return false;

  final directory = File(normalized).parent.path;
  if (directory.isEmpty || directory == '.') return false;

  final (String, List<String>)? command = Platform.isWindows
      ? ('explorer.exe', <String>[directory])
      : Platform.isMacOS
      ? ('open', <String>[directory])
      : Platform.isLinux
      ? ('xdg-open', <String>[directory])
      : null;
  if (command == null) return false;

  final result = await Process.run(command.$1, command.$2);
  return result.exitCode == 0;
}
