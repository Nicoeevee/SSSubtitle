import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss_subtitle/src/core/rust_subtitle_core.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';
import 'package:ss_subtitle/src/platform/subtitle_saver.dart';
import 'package:ss_subtitle/src/rust/frb_generated.dart';

Future<void> runRustWorkflowSmoke() async {
  await RustLib.init();
  Uint8List? savedBytes;
  var cancelSave = false;
  final saver = PlatformSubtitleSaver(
    platform: TargetPlatform.windows,
    isWeb: kIsWeb,
    windowsLocationPicker:
        ({required String suggestedName, required String extension}) async {
          return cancelSave ? null : r'C:\offline-smoke\subtitle.srt';
        },
    bytesWriter:
        ({
          required String path,
          required String name,
          required Uint8List bytes,
          required String mimeType,
        }) async {
          savedBytes = bytes;
        },
    fallbackSaver:
        ({
          required String baseName,
          required String extension,
          required Uint8List bytes,
          required String mimeType,
        }) async {
          if (!cancelSave) savedBytes = bytes;
          return !cancelSave;
        },
  );
  final core = RustSubtitleCore(saver: saver);

  final candidates = await observeHeartbeat(
    'Search',
    () => core.search('Documentary Episode'),
  );
  final documentary = candidates.firstWhere(
    (candidate) => candidate.name.contains('Documentary Episode'),
  );
  final nearLimit = candidates.firstWhere(
    (candidate) => candidate.name == 'Near Limit Fixture.srt',
  );

  final firstPage = await observeHeartbeat(
    'Preview page 1',
    () => core.preview(documentary, 1),
  );
  final laterPage = await observeHeartbeat(
    'Preview later page',
    () => core.preview(documentary, firstPage.totalPages),
  );
  final returnedFirstPage = await observeHeartbeat(
    'Preview page 1 again',
    () => core.preview(documentary, 1),
  );
  expect(laterPage.page, firstPage.totalPages);
  expect(returnedFirstPage.lines, firstPage.lines);

  final switchedPage = await observeHeartbeat(
    'Candidate switch',
    () => core.preview(candidates[1], 1),
  );
  expect(switchedPage.candidateId, candidates[1].id);

  final saved = await observeHeartbeat(
    'Acquisition save',
    () => core.download(documentary, videoFileName: 'documentary_episode.mp4'),
  );
  expect(saved, SubtitleSaveOutcome.saved);
  expect(savedBytes, isNotNull);

  cancelSave = true;
  final cancelled = await observeHeartbeat(
    'Acquisition cancellation',
    () => core.download(documentary, videoFileName: 'documentary_episode.mp4'),
  );
  expect(cancelled, SubtitleSaveOutcome.cancelled);

  final nearLimitPage = await observeHeartbeat(
    'Near-limit first materialization',
    () => core.preview(nearLimit, 1),
  );
  expect(nearLimitPage.lines, isNotEmpty);
}

Future<T> observeHeartbeat<T>(
  String label,
  Future<T> Function() operation,
) async {
  var ticks = 0;
  final timer = Timer.periodic(
    const Duration(milliseconds: 1),
    (_) => ticks += 1,
  );
  try {
    final result = await operation();
    expect(
      ticks,
      greaterThan(0),
      reason: '$label completed without an event-loop heartbeat',
    );
    return result;
  } finally {
    timer.cancel();
  }
}
