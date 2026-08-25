class SubtitleCandidate {
  SubtitleCandidate({
    required this.id,
    required this.name,
    required this.languages,
    required this.format,
    required this.matchScore,
    required this.matchReasons,
  });

  final String id;
  final String name;
  final List<String> languages;
  final String format;
  final int matchScore;
  final List<String> matchReasons;
}

class SubtitlePreviewPage {
  const SubtitlePreviewPage({
    required this.candidateId,
    required this.lines,
    required this.page,
    required this.totalPages,
  });

  final String candidateId;
  final List<String> lines;
  final int page;
  final int totalPages;
}

enum SubtitleSaveOutcome { saved, cancelled }

enum SubtitleFailureKind {
  invalidSuggestedSearchName,
  candidateExpired,
  providerUnavailable,
  artifactTooLarge,
  artifactInvalid,
  previewPageOutOfRange,
  saveFailed,
  internal,
}

class SubtitleCoreException implements Exception {
  const SubtitleCoreException({
    required this.kind,
    required this.operation,
    this.detail,
  });

  final SubtitleFailureKind kind;
  final String operation;
  final String? detail;

  @override
  String toString() => 'SubtitleCoreException($operation, $kind)';
}

abstract interface class SubtitleCore {
  String suggestedSearchName(String fileName);

  Future<List<SubtitleCandidate>> search(String query);

  Future<SubtitlePreviewPage> preview(SubtitleCandidate candidate, int page);

  Future<SubtitleSaveOutcome> download(
    SubtitleCandidate candidate, {
    required String videoFileName,
  });
}

String deriveSearchName(String fileName) {
  final normalized = fileName.trim().replaceAll('\\', '/');
  final leaf = normalized.split('/').last;
  final dot = leaf.lastIndexOf('.');
  final stem = dot > 0 ? leaf.substring(0, dot) : leaf;
  final marker = stem.lastIndexOf('@');
  return (marker >= 0 ? stem.substring(marker + 1) : stem).trim();
}

String deriveSubtitleBaseName(String videoFileName) {
  final normalized = videoFileName.trim().replaceAll('\\', '/');
  final leaf = normalized.split('/').last;
  final dot = leaf.lastIndexOf('.');
  final stem = (dot > 0 ? leaf.substring(0, dot) : leaf).trim();
  var sanitized = stem
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceFirst(RegExp(r'[ .]+$'), '')
      .trim();
  if (RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(sanitized)) {
    sanitized = '_$sanitized';
  }
  return sanitized.isEmpty ? 'subtitle' : sanitized;
}

class DemoSubtitleCore implements SubtitleCore {
  @override
  String suggestedSearchName(String fileName) => deriveSearchName(fileName);

  @override
  Future<List<SubtitleCandidate>> search(String query) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (query.trim().isEmpty) return const [];
    return [
      SubtitleCandidate(
        id: 'demo-1',
        name: '$query 简体中文.ass',
        languages: const ['简体中文'],
        format: 'ASS',
        matchScore: 96,
        matchReasons: const ['文件名完全匹配', '时长接近', '高清片源'],
      ),
      SubtitleCandidate(
        id: 'demo-2',
        name: '$query 繁體中文.srt',
        languages: const ['繁體中文'],
        format: 'SRT',
        matchScore: 89,
        matchReasons: const ['文件名匹配', '时长接近'],
      ),
      SubtitleCandidate(
        id: 'demo-3',
        name: '$query 双语字幕.srt',
        languages: const ['中英双语'],
        format: 'SRT',
        matchScore: 82,
        matchReasons: const ['关键词匹配', '用户高评分'],
      ),
    ];
  }

  @override
  Future<SubtitlePreviewPage> preview(
    SubtitleCandidate candidate,
    int page,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final lines = List<String>.generate(74, (index) {
      final line = index + 1;
      if (line % 3 == 1) return '${(line / 3).ceil()}';
      if (line % 3 == 2) {
        final second = ((line / 3).floor() * 4).toString().padLeft(2, '0');
        return '00:00:$second,000 --> 00:00:$second,800';
      }
      return '这是「${candidate.name}」的演示字幕第 ${(line / 3).floor()} 条。';
    });
    final totalPages = (lines.length / 30).ceil();
    final start = (page - 1) * 30;
    return SubtitlePreviewPage(
      candidateId: candidate.id,
      lines: start >= lines.length
          ? const []
          : lines.sublist(start, (start + 30).clamp(0, lines.length)),
      page: page,
      totalPages: totalPages,
    );
  }

  @override
  Future<SubtitleSaveOutcome> download(
    SubtitleCandidate candidate, {
    required String videoFileName,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return SubtitleSaveOutcome.saved;
  }
}
