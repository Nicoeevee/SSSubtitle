import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss_subtitle/src/ui/video_drop_target.dart';

void main() {
  group('videoPathFromDropItem', () {
    test('keeps the native filesystem path for supported video files', () {
      final item = DropItemFile(r'C:\Media\Episode 01.MP4');

      expect(videoPathFromDropItem(item), equals(r'C:\Media\Episode 01.MP4'));
    });

    test('uses the visible name for a web Blob URL', () {
      // The platform-specific XFile implementation used by the test runner
      // derives `name` from the path. A browser drop supplies the same name
      // explicitly while its path is a Blob URL.
      final item = DropItemFile('episode.webm');

      expect(videoPathFromDropItem(item, isWeb: true), equals('episode.webm'));
    });

    test('rejects directories and unsupported files', () {
      final directory = DropItemDirectory(r'C:\Media\Movies', [
        DropItemFile(r'C:\Media\Movies\episode.mp4'),
      ]);
      final textFile = DropItemFile(r'C:\Media\notes.txt');

      expect(videoPathFromDropItem(directory), isNull);
      expect(videoPathFromDropItem(textFile), isNull);
    });

    test('takes the first supported regular file from a multi-file drop', () {
      final items = [
        DropItemFile(r'C:\Media\poster.jpg'),
        DropItemDirectory(r'C:\Media\Movies', const []),
        DropItemFile(r'C:\Media\episode.mkv'),
        DropItemFile(r'C:\Media\later.avi'),
      ];

      expect(firstVideoPathFromDrop(items), equals(r'C:\Media\episode.mkv'));
    });
  });

  testWidgets('wraps its child with a desktop_drop DropTarget', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VideoDropTarget(
          onVideoDropped: (_) {},
          child: const SizedBox(
            width: 240,
            height: 120,
            child: Center(child: Text('选择视频')),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('video-drop-target')), findsOneWidget);
    expect(find.text('选择视频'), findsOneWidget);
    expect(find.text('松开以选择视频'), findsNothing);
  });

  testWidgets('forwards a native drop to the video-selection callback', (
    tester,
  ) async {
    String? droppedPath;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoDropTarget(
          onVideoDropped: (path) => droppedPath = path,
          child: const SizedBox(width: 240, height: 120),
        ),
      ),
    );

    final codec = const StandardMethodCodec();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Future<void> send(String method, Object? arguments) async {
      await messenger.handlePlatformMessage(
        'desktop_drop',
        codec.encodeMethodCall(MethodCall(method, arguments)),
        null,
      );
    }

    // desktop_drop receives an entered event before a Windows drop is
    // accepted; the coordinates are inside the test target's bounds.
    await send('entered', <double>[10, 10]);
    await tester.pump();
    expect(find.text('松开以选择视频'), findsOneWidget);

    await send('performOperation', <String>[r'C:\Media\episode.mp4']);
    await tester.pump();

    expect(droppedPath, equals(r'C:\Media\episode.mp4'));
    expect(find.text('松开以选择视频'), findsNothing);
  });
}
