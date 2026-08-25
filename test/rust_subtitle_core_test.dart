import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss_subtitle/src/core/rust_subtitle_core.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';
import 'package:ss_subtitle/src/platform/subtitle_saver.dart';
import 'package:ss_subtitle/src/rust/api/workflow.dart' as rust_workflow;

void main() {
  group('RustSubtitleCore failure mapping', () {
    test('maps every generated failure kind at the search seam', () async {
      final expected =
          <(rust_workflow.SubtitleFailureKind, SubtitleFailureKind)>[
            (
              rust_workflow.SubtitleFailureKind.invalidSuggestedSearchName,
              SubtitleFailureKind.invalidSuggestedSearchName,
            ),
            (
              rust_workflow.SubtitleFailureKind.candidateExpired,
              SubtitleFailureKind.candidateExpired,
            ),
            (
              rust_workflow.SubtitleFailureKind.providerUnavailable,
              SubtitleFailureKind.providerUnavailable,
            ),
            (
              rust_workflow.SubtitleFailureKind.artifactTooLarge,
              SubtitleFailureKind.artifactTooLarge,
            ),
            (
              rust_workflow.SubtitleFailureKind.artifactInvalid,
              SubtitleFailureKind.artifactInvalid,
            ),
            (
              rust_workflow.SubtitleFailureKind.previewPageOutOfRange,
              SubtitleFailureKind.previewPageOutOfRange,
            ),
            (
              rust_workflow.SubtitleFailureKind.internal,
              SubtitleFailureKind.internal,
            ),
          ];

      for (final (rustKind, dartKind) in expected) {
        final core = RustSubtitleCore(
          searchOperation: (query) async {
            throw rust_workflow.SubtitleFailure(
              operation: rust_workflow.SubtitleOperation.search,
              kind: rustKind,
              detail: 'safe-detail',
            );
          },
        );

        await _expectTypedFailure(
          () => core.search('episode'),
          dartKind,
          'search',
          detail: 'safe-detail',
        );
      }
    });

    test('preserves Preview and Acquisition operation context', () async {
      final candidate = _candidate();
      final previewCore = RustSubtitleCore(
        previewOperation: (candidateId, page) async {
          throw const rust_workflow.SubtitleFailure(
            operation: rust_workflow.SubtitleOperation.preview,
            kind: rust_workflow.SubtitleFailureKind.candidateExpired,
          );
        },
      );
      await _expectTypedFailure(
        () => previewCore.preview(candidate, 1),
        SubtitleFailureKind.candidateExpired,
        'preview',
      );

      final acquisitionCore = RustSubtitleCore(
        acquireOperation: (candidateId) async {
          throw const rust_workflow.SubtitleFailure(
            operation: rust_workflow.SubtitleOperation.acquisition,
            kind: rust_workflow.SubtitleFailureKind.artifactInvalid,
          );
        },
      );
      await _expectTypedFailure(
        () => acquisitionCore.download(candidate, videoFileName: 'episode.mkv'),
        SubtitleFailureKind.artifactInvalid,
        'acquisition',
      );
    });
  });

  group('RustSubtitleCore acquisition seam', () {
    for (final format in rust_workflow.SubtitleFormat.values) {
      test('derives ${format.name} extension and MIME type', () async {
        Uint8List? receivedBytes;
        String? receivedExtension;
        String? receivedMimeType;
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final saver = PlatformSubtitleSaver(
          platform: TargetPlatform.windows,
          isWeb: false,
          windowsLocationPicker: ({
            required suggestedName,
            required extension,
          }) async => r'C:\selected\episode.subtitle',
          bytesWriter:
              ({
                required path,
                required name,
                required bytes,
                required mimeType,
              }) async {
                receivedBytes = bytes;
                receivedExtension = name.split('.').last;
                receivedMimeType = mimeType;
              },
        );
        final core = RustSubtitleCore(
          saver: saver,
          acquireOperation: (candidateId) async =>
              rust_workflow.SubtitleArtifact(
                candidateId: candidateId,
                bytes: bytes,
                format: format,
              ),
        );

        final outcome = await core.download(
          _candidate(),
          videoFileName: 'episode.mkv',
        );

        expect(outcome, SubtitleSaveOutcome.saved);
        expect(receivedBytes, same(bytes));
        expect(receivedExtension, format.name);
        expect(receivedMimeType, _expectedMimeType(format));
      });
    }

    test('returns typed Saved and never exposes artifact bytes', () async {
      final core = RustSubtitleCore(
        saver: _windowsSaver((_) async => true),
        acquireOperation: (candidateId) async => rust_workflow.SubtitleArtifact(
          candidateId: candidateId,
          bytes: Uint8List.fromList([7, 8, 9]),
          format: rust_workflow.SubtitleFormat.srt,
        ),
      );

      final outcome = await core.download(
        _candidate(),
        videoFileName: 'episode.mkv',
      );

      expect(outcome, isA<SubtitleSaveOutcome>());
      expect(outcome, isNot(isA<Uint8List>()));
    });

    test('maps a platform cancellation to typed Cancelled', () async {
      final core = RustSubtitleCore(
        saver: PlatformSubtitleSaver(
          platform: TargetPlatform.windows,
          isWeb: false,
          windowsLocationPicker: ({
            required suggestedName,
            required extension,
          }) async => null,
        ),
        acquireOperation: (candidateId) async => rust_workflow.SubtitleArtifact(
          candidateId: candidateId,
          bytes: Uint8List.fromList([1]),
          format: rust_workflow.SubtitleFormat.srt,
        ),
      );

      final outcome = await core.download(
        _candidate(),
        videoFileName: 'episode.mkv',
      );

      expect(outcome, SubtitleSaveOutcome.cancelled);
    });

    test('maps a platform saver exception to typed SaveFailed', () async {
      final core = RustSubtitleCore(
        saver: _windowsSaver((_) async => throw StateError('disk unavailable')),
        acquireOperation: (candidateId) async => rust_workflow.SubtitleArtifact(
          candidateId: candidateId,
          bytes: Uint8List.fromList([1]),
          format: rust_workflow.SubtitleFormat.srt,
        ),
      );

      await _expectTypedFailure(
        () => core.download(_candidate(), videoFileName: 'episode.mkv'),
        SubtitleFailureKind.saveFailed,
        'acquisition',
      );
    });
  });
}

SubtitleCandidate _candidate() => SubtitleCandidate(
  id: 'candidate',
  name: 'episode.srt',
  languages: const ['en'],
  format: 'SRT',
  matchScore: 90,
  matchReasons: const ['exact title'],
);

PlatformSubtitleSaver _windowsSaver(
  Future<bool> Function(Uint8List bytes) result,
) => PlatformSubtitleSaver(
  platform: TargetPlatform.windows,
  isWeb: false,
  windowsLocationPicker: ({required suggestedName, required extension}) async =>
      r'C:\selected\episode.subtitle',
  bytesWriter:
      ({
        required path,
        required name,
        required bytes,
        required mimeType,
      }) async {
        await result(bytes);
      },
);

String _expectedMimeType(rust_workflow.SubtitleFormat format) =>
    switch (format) {
      rust_workflow.SubtitleFormat.srt => 'application/x-subrip',
      rust_workflow.SubtitleFormat.vtt => 'text/vtt',
      rust_workflow.SubtitleFormat.ass ||
      rust_workflow.SubtitleFormat.ssa => 'text/x-ssa',
    };

Future<void> _expectTypedFailure(
  Future<Object?> Function() operation,
  SubtitleFailureKind kind,
  String operationName, {
  String? detail,
}) async {
  try {
    await operation();
    fail('expected SubtitleCoreException');
  } on SubtitleCoreException catch (error) {
    expect(error.kind, kind);
    expect(error.operation, operationName);
    expect(error.detail, detail);
  }
}
