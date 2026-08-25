import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ss_subtitle/app.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';
import 'package:ss_subtitle/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('launches the subtitle workflow with the Rust runtime', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      SSSubtitleApp(
        core: DemoSubtitleCore(),
        videoPicker: () async => 'archive.example@documentary_episode.mp4',
      ),
    );

    expect(find.text('SSSubtitle'), findsOneWidget);
    expect(find.text('从视频开始'), findsOneWidget);
    expect(find.text('搜索字幕'), findsOneWidget);
  });
}
