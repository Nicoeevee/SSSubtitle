import 'video_folder_stub.dart' if (dart.library.io) 'video_folder_io.dart';

typedef VideoFolderOpener = Future<bool> Function(String videoPath);

Future<bool> openVideoFolder(String videoPath) =>
    openVideoFolderImpl(videoPath);
