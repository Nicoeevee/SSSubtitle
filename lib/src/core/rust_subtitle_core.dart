import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';
import 'package:ss_subtitle/src/platform/subtitle_saver.dart';
import 'package:ss_subtitle/src/rust/api/simple.dart' as rust_simple;
import 'package:ss_subtitle/src/rust/api/xunlei.dart' as rust_xunlei;

typedef SubtitlePreviewPageLoader =
    ({List<String> lines, int totalPages}) Function(int page);

/// Loads every one-based Rust preview page exactly once, in order.
List<String> collectSubtitlePreviewLines(SubtitlePreviewPageLoader loadPage) {
  final first = loadPage(1);
  final lines = <String>[...first.lines];
  for (var page = 2; page <= first.totalPages; page++) {
    lines.addAll(loadPage(page).lines);
  }
  return lines;
}

/// Production adapter for the Rust subtitle engine and the platform saver.
///
/// Generated bridge types stop here. Widgets and controllers only see the
/// stable [SubtitleCore] interface.
class RustSubtitleCore implements SubtitleCore {
  RustSubtitleCore({PlatformSubtitleSaver? saver})
    : _saver = saver ?? PlatformSubtitleSaver();

  final Map<String, Uint8List> _downloadCache = {};
  final PlatformSubtitleSaver _saver;

  @override
  String suggestedSearchName(String fileName) =>
      rust_simple.deriveSearchName(filename: fileName);

  @override
  Future<List<SubtitleCandidate>> search(String query) async {
    final remote = await rust_xunlei.searchXunlei(query: query);
    final byId = {for (final item in remote) item.candidateId: item};
    final ranked = rust_simple.rankSubtitleCandidates(
      candidates: remote
          .map(
            (item) => rust_simple.SubtitleCandidate(
              id: item.candidateId,
              name: item.name,
              cid: null,
              durationMillis: item.durationMs,
              language: item.languages.isEmpty
                  ? null
                  : item.languages.join(' / '),
              format: item.extension_,
              upstreamScore: PlatformInt64Util.from(
                (item.upstreamScore ?? 0).round(),
              ),
              fingerprintMatch: (item.fingerprintScore ?? 0) > 0,
            ),
          )
          .toList(growable: false),
      context: rust_simple.CandidateRankingContext(
        searchName: query,
        preferredLanguages: const ['简体中文', 'zh-CN', '中文'],
        preferredFormats: const ['srt', 'ass', 'ssa', 'vtt'],
      ),
    );

    return ranked
        .map((item) {
          final source = byId[item.candidate.id]!;
          return SubtitleCandidate(
            id: source.candidateId,
            name: source.name,
            language: source.languages.isEmpty
                ? '语言未标注'
                : source.languages.join(' / '),
            format: source.extension_.toUpperCase(),
            score: item.score.toInt(),
            reasons: _matchReasons(source),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<String>> preview(SubtitleCandidate candidate) async {
    final bytes = await _bytesFor(candidate);
    return collectSubtitlePreviewLines((page) {
      final preview = rust_simple.subtitlePreviewPage(
        bytes: bytes,
        page: page,
        format: candidate.format,
      );
      return (lines: preview.lines, totalPages: preview.totalPages);
    });
  }

  @override
  Future<String> download(
    SubtitleCandidate candidate, {
    required String videoFileName,
  }) async {
    final bytes = await _bytesFor(candidate);
    final extension = candidate.format.toLowerCase();
    final baseName = deriveSubtitleBaseName(videoFileName);
    final saved = await _saver.save(
      baseName: baseName,
      bytes: bytes,
      extension: extension,
      mimeType: _mimeType(extension),
    );
    if (!saved) return '已取消保存';
    _downloadCache.remove(candidate.id);
    return '字幕已保存为 $baseName.$extension';
  }

  Future<Uint8List> _bytesFor(SubtitleCandidate candidate) async {
    final cached = _downloadCache[candidate.id];
    if (cached != null) return cached;
    final bytes = await rust_xunlei.downloadXunlei(candidateId: candidate.id);
    _downloadCache[candidate.id] = bytes;
    return bytes;
  }

  static List<String> _matchReasons(rust_xunlei.XunleiCandidate candidate) {
    final reasons = <String>['Rust 本地名称与格式排序'];
    if (candidate.languages.isNotEmpty) {
      reasons.add('语言：${candidate.languages.join(' / ')}');
    }
    if ((candidate.upstreamScore ?? 0) > 0) {
      reasons.add('迅雷评分：${candidate.upstreamScore!.toStringAsFixed(0)}');
    }
    if ((candidate.fingerprintScore ?? 0) > 0) {
      reasons.add('指纹评分：${candidate.fingerprintScore!.toStringAsFixed(0)}');
    }
    if (candidate.durationMs != null) {
      reasons.add('字幕时长：${_formatDuration(candidate.durationMs!)}');
    }
    return reasons;
  }

  static String _formatDuration(BigInt milliseconds) {
    final seconds = milliseconds ~/ BigInt.from(1000);
    final hours = seconds ~/ BigInt.from(3600);
    final minutes = (seconds % BigInt.from(3600)) ~/ BigInt.from(60);
    final remainder = seconds % BigInt.from(60);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${remainder.toString().padLeft(2, '0')}';
  }

  static String _mimeType(String extension) => switch (extension) {
    'srt' => 'application/x-subrip',
    'vtt' => 'text/vtt',
    'ass' || 'ssa' => 'text/x-ssa',
    _ => 'text/plain',
  };
}
