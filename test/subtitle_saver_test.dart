import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss_subtitle/src/platform/subtitle_saver.dart';

void main() {
  test('Windows 使用 file_selector 另存且不调用 file_saver', () async {
    String? capturedSuggestedName;
    String? selectedPath;
    Uint8List? writtenBytes;
    var fallbackCalled = false;
    final saver = PlatformSubtitleSaver(
      platform: TargetPlatform.windows,
      isWeb: false,
      windowsLocationPicker:
          ({required String suggestedName, required String extension}) async {
            expect(extension, 'srt');
            capturedSuggestedName = suggestedName;
            return r'C:\selected\documentary_episode.srt';
          },
      bytesWriter:
          ({
            required String path,
            required String name,
            required Uint8List bytes,
            required String mimeType,
          }) async {
            selectedPath = path;
            writtenBytes = bytes;
            expect(name, 'documentary_episode.srt');
            expect(mimeType, 'application/x-subrip');
          },
      fallbackSaver:
          ({
            required String baseName,
            required String extension,
            required Uint8List bytes,
            required String mimeType,
          }) async {
            fallbackCalled = true;
            return true;
          },
    );
    final bytes = Uint8List.fromList([1, 2, 3]);

    final saved = await saver.save(
      baseName: 'documentary_episode',
      extension: 'srt',
      bytes: bytes,
      mimeType: 'application/x-subrip',
    );

    expect(saved, isTrue);
    expect(capturedSuggestedName, 'documentary_episode.srt');
    expect(selectedPath, r'C:\selected\documentary_episode.srt');
    expect(writtenBytes, bytes);
    expect(fallbackCalled, isFalse);
  });

  test('Windows 取消另存时不写入文件', () async {
    var writeCalled = false;
    final saver = PlatformSubtitleSaver(
      platform: TargetPlatform.windows,
      isWeb: false,
      windowsLocationPicker: ({
        required String suggestedName,
        required String extension,
      }) async => null,
      bytesWriter:
          ({
            required String path,
            required String name,
            required Uint8List bytes,
            required String mimeType,
          }) async {
            writeCalled = true;
          },
    );

    final saved = await saver.save(
      baseName: 'documentary_episode',
      extension: 'ass',
      bytes: Uint8List.fromList([1]),
      mimeType: 'text/x-ssa',
    );

    expect(saved, isFalse);
    expect(writeCalled, isFalse);
  });
}
