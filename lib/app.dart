import 'package:material_ui/material_ui.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';
import 'package:ss_subtitle/src/platform/video_folder.dart';
import 'package:ss_subtitle/src/platform/video_picker.dart';
import 'package:ss_subtitle/src/theme/app_theme.dart';
import 'package:ss_subtitle/src/ui/subtitle_home_page.dart';

class SSSubtitleApp extends StatelessWidget {
  const SSSubtitleApp({
    required this.core,
    this.videoPicker,
    this.videoFolderOpener,
    super.key,
  });

  final SubtitleCore core;
  final VideoNamePicker? videoPicker;
  final VideoFolderOpener? videoFolderOpener;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSSubtitle',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: SubtitleHomePage(
        core: core,
        videoPicker: videoPicker,
        videoFolderOpener: videoFolderOpener,
      ),
    );
  }
}
