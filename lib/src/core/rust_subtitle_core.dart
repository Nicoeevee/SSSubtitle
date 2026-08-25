// ignore_for_file: library_private_types_in_public_api

import 'package:ss_subtitle/src/core/subtitle_core.dart';
import 'package:ss_subtitle/src/platform/subtitle_saver.dart';
import 'package:ss_subtitle/src/rust/api/simple.dart' as rust_simple;
import 'package:ss_subtitle/src/rust/api/workflow.dart' as rust_workflow;

typedef _SearchOperation =
    Future<List<rust_workflow.WorkflowSubtitleCandidate>> Function(
      String query,
    );
typedef _PreviewOperation =
    Future<rust_workflow.WorkflowSubtitlePreviewPage> Function(
      String candidateId,
      int page,
    );
typedef _AcquireOperation = Future<rust_workflow.SubtitleArtifact> Function(
  String candidateId,
);

/// Production adapter for the three asynchronous Rust subtitle operations and
/// the platform saver. Generated bridge types stop at this boundary.
class RustSubtitleCore implements SubtitleCore {
  RustSubtitleCore({
    PlatformSubtitleSaver? saver,
    _SearchOperation? searchOperation,
    _PreviewOperation? previewOperation,
    _AcquireOperation? acquireOperation,
  }) : _saver = saver ?? PlatformSubtitleSaver(),
       _searchOperation =
           searchOperation ??
           ((query) =>
               rust_workflow.searchSubtitles(suggestedSearchName: query)),
       _previewOperation =
           previewOperation ??
           ((candidateId, page) => rust_workflow.previewSubtitle(
             candidateId: candidateId,
             page: page,
           )),
       _acquireOperation =
           acquireOperation ??
           ((candidateId) =>
               rust_workflow.acquireSubtitle(candidateId: candidateId));

  final PlatformSubtitleSaver _saver;
  final _SearchOperation _searchOperation;
  final _PreviewOperation _previewOperation;
  final _AcquireOperation _acquireOperation;

  @override
  String suggestedSearchName(String fileName) =>
      rust_simple.deriveSearchName(filename: fileName);

  @override
  Future<List<SubtitleCandidate>> search(String query) async {
    try {
      final remote = await _searchOperation(query);
      return remote
          .map(
            (candidate) => SubtitleCandidate(
              id: candidate.id,
              name: candidate.name,
              languages: List<String>.unmodifiable(candidate.languages),
              format: candidate.format.name.toUpperCase(),
              matchScore: candidate.matchScore.toInt(),
              matchReasons: candidate.matchReasons
                  .map(_localizeMatchReason)
                  .toList(growable: false),
            ),
          )
          .toList(growable: false);
    } on rust_workflow.SubtitleFailure catch (failure) {
      throw _mapRustFailure(failure);
    } catch (_) {
      throw const SubtitleCoreException(
        kind: SubtitleFailureKind.internal,
        operation: 'search',
      );
    }
  }

  @override
  Future<SubtitlePreviewPage> preview(
    SubtitleCandidate candidate,
    int page,
  ) async {
    try {
      final remote = await _previewOperation(candidate.id, page);
      return SubtitlePreviewPage(
        candidateId: remote.candidateId,
        lines: List<String>.unmodifiable(remote.lines),
        page: remote.page,
        totalPages: remote.totalPages,
      );
    } on rust_workflow.SubtitleFailure catch (failure) {
      throw _mapRustFailure(failure);
    } catch (_) {
      throw const SubtitleCoreException(
        kind: SubtitleFailureKind.internal,
        operation: 'preview',
      );
    }
  }

  @override
  Future<SubtitleSaveOutcome> download(
    SubtitleCandidate candidate, {
    required String videoFileName,
  }) async {
    try {
      final artifact = await _acquireOperation(candidate.id);
      final extension = artifact.format.name;
      final saved = await _saver.save(
        baseName: deriveSubtitleBaseName(videoFileName),
        bytes: artifact.bytes,
        extension: extension,
        mimeType: _mimeType(extension),
      );
      return saved ? SubtitleSaveOutcome.saved : SubtitleSaveOutcome.cancelled;
    } on rust_workflow.SubtitleFailure catch (failure) {
      throw _mapRustFailure(failure);
    } on SubtitleCoreException {
      rethrow;
    } catch (_) {
      throw const SubtitleCoreException(
        kind: SubtitleFailureKind.saveFailed,
        operation: 'acquisition',
      );
    }
  }

  static String _localizeMatchReason(rust_workflow.MatchReason reason) {
    return switch (reason.kind) {
      rust_workflow.MatchReasonKind.exactTitle => '文件名完全匹配',
      rust_workflow.MatchReasonKind.titleContains => '文件名匹配',
      rust_workflow.MatchReasonKind.languageMatch =>
        '语言：${reason.value ?? '未标注'}',
      rust_workflow.MatchReasonKind.providerScore => 'Provider 评分',
      rust_workflow.MatchReasonKind.fingerprintMatch => '指纹匹配',
      rust_workflow.MatchReasonKind.supportedFormat => '支持的字幕格式',
    };
  }

  static SubtitleCoreException _mapRustFailure(
    rust_workflow.SubtitleFailure failure,
  ) {
    final kind = switch (failure.kind) {
      rust_workflow.SubtitleFailureKind.invalidSuggestedSearchName =>
        SubtitleFailureKind.invalidSuggestedSearchName,
      rust_workflow.SubtitleFailureKind.candidateExpired =>
        SubtitleFailureKind.candidateExpired,
      rust_workflow.SubtitleFailureKind.providerUnavailable =>
        SubtitleFailureKind.providerUnavailable,
      rust_workflow.SubtitleFailureKind.artifactTooLarge =>
        SubtitleFailureKind.artifactTooLarge,
      rust_workflow.SubtitleFailureKind.artifactInvalid =>
        SubtitleFailureKind.artifactInvalid,
      rust_workflow.SubtitleFailureKind.previewPageOutOfRange =>
        SubtitleFailureKind.previewPageOutOfRange,
      rust_workflow.SubtitleFailureKind.internal =>
        SubtitleFailureKind.internal,
    };
    return SubtitleCoreException(
      kind: kind,
      operation: failure.operation.name,
      detail: failure.detail,
    );
  }

  static String _mimeType(String extension) => switch (extension) {
    'srt' => 'application/x-subrip',
    'vtt' => 'text/vtt',
    'ass' || 'ssa' => 'text/x-ssa',
    _ => 'text/plain',
  };
}
