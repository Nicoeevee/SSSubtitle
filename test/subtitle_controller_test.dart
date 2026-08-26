import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ss_subtitle/src/controller/subtitle_controller.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';

void main() {
  test('derives a Suggested Search Name from the last @ marker', () {
    expect(
      deriveSearchName('archive.example@documentary_episode.mp4'),
      'documentary_episode',
    );
    expect(
      deriveSearchName('publisher@collection@concert_recording.mkv'),
      'concert_recording',
    );
    expect(deriveSearchName('travel_video.mp4'), 'travel_video');
  });

  test('keeps the source video name as a safe subtitle base name', () {
    expect(
      deriveSubtitleBaseName(
        r'C:\Media\archive.example@documentary_episode.mp4',
      ),
      'archive.example@documentary_episode',
    );
    expect(deriveSubtitleBaseName('travel_video.mkv'), 'travel_video');
    expect(
      deriveSubtitleBaseName('/media/family movie.2026.mkv'),
      'family movie.2026',
    );
    expect(deriveSubtitleBaseName('bad<name>? .mp4'), 'bad_name__');
    expect(deriveSubtitleBaseName('CON.mp4'), '_CON');
    expect(deriveSubtitleBaseName('com1.recording.mkv'), '_com1.recording');
    expect(deriveSubtitleBaseName('.mp4'), '.mp4');
    expect(deriveSubtitleBaseName(''), 'subtitle');
    expect(deriveSubtitleBaseName('...mp4'), 'subtitle');
  });

  test(
    'requests authoritative pages and keeps only the current page',
    () async {
      final core = _FakeCore();
      final controller = SubtitleController(core);

      controller.selectVideo('publisher@documentary_episode.mp4');
      expect(controller.query, 'documentary_episode');

      await controller.search();
      expect(controller.status, SearchStatus.ready);
      expect(controller.candidates, hasLength(2));
      expect(controller.visiblePreviewLines, hasLength(30));
      expect(controller.previewPageCount, 3);
      expect(core.requestedPages, [1]);

      await controller.nextPreviewPage();
      expect(controller.previewPage, 1);
      expect(controller.visiblePreviewLines.first, 'line 31');
      expect(core.requestedPages, [1, 2]);

      await controller.goToPreviewPage(3);
      expect(controller.previewPage, 2);
      expect(controller.visiblePreviewLines.first, 'line 61');
      expect(core.requestedPages, [1, 2, 3]);
      await controller.goToPreviewPage(4);
      expect(core.requestedPages, [1, 2, 3]);

      await controller.moveSelection(1);
      expect(controller.selectedIndex, 1);
      expect(controller.previewPage, 0);
      expect(controller.visiblePreviewLines.first, 'candidate 2 line 1');

      await controller.downloadSelected();
      expect(controller.notice, contains('.srt'));
    },
  );

  test(
    'cancel prevents a stale Preview completion from restoring state',
    () async {
      final core = _DelayedPreviewCore();
      final controller = SubtitleController(core);
      controller.selectVideo('episode.mkv');

      final search = controller.search();
      await Future<void>.delayed(Duration.zero);
      controller.cancel();
      core.previewCompleter.complete(
        const SubtitlePreviewPage(
          candidateId: 'candidate',
          lines: ['stale'],
          page: 1,
          totalPages: 1,
        ),
      );
      await search;

      expect(controller.candidates, isEmpty);
      expect(controller.previewLines, isEmpty);
      expect(controller.notice, '已取消当前选择');
    },
  );

  test('newer Search wins when completions are reversed', () async {
    final core = _ControlledCore();
    final controller = SubtitleController(core);
    controller.selectVideo('episode.mkv');

    controller.setQuery('first');
    final first = controller.search();
    controller.setQuery('second');
    final second = controller.search();

    core.searchRequests[1].completer.complete([_candidate('second')]);
    await Future<void>.delayed(Duration.zero);
    core.previewRequests.single.completer.complete(
      const SubtitlePreviewPage(
        candidateId: 'second',
        lines: ['second preview'],
        page: 1,
        totalPages: 1,
      ),
    );
    await second;

    core.searchRequests[0].completer.complete([_candidate('first')]);
    await first;

    expect(controller.selectedCandidate?.id, 'second');
    expect(controller.previewLines, ['second preview']);
  });

  test('newer Preview wins when completions are reversed', () async {
    final core = _ControlledCore(searchResults: [_candidate('candidate')]);
    final controller = SubtitleController(core);
    controller.selectVideo('episode.mkv');

    final search = controller.search();
    await Future<void>.delayed(Duration.zero);
    core.previewRequests.single.completer.complete(
      const SubtitlePreviewPage(
        candidateId: 'candidate',
        lines: ['page one'],
        page: 1,
        totalPages: 2,
      ),
    );
    await search;

    final older = controller.nextPreviewPage();
    final newer = controller.nextPreviewPage();
    core.previewRequests[2].completer.complete(
      const SubtitlePreviewPage(
        candidateId: 'candidate',
        lines: ['newer page two'],
        page: 2,
        totalPages: 2,
      ),
    );
    await newer;
    core.previewRequests[1].completer.complete(
      const SubtitlePreviewPage(
        candidateId: 'candidate',
        lines: ['older page two'],
        page: 2,
        totalPages: 2,
      ),
    );
    await older;

    expect(controller.previewPage, 1);
    expect(controller.previewLines, ['newer page two']);
  });

  test(
    'ignores a Preview result with a different Candidate identity',
    () async {
      final core = _ControlledCore(searchResults: [_candidate('candidate')]);
      final controller = SubtitleController(core);
      controller.selectVideo('episode.mkv');

      final search = controller.search();
      await Future<void>.delayed(Duration.zero);
      core.previewRequests.single.completer.complete(
        const SubtitlePreviewPage(
          candidateId: 'other',
          lines: ['wrong candidate'],
          page: 1,
          totalPages: 1,
        ),
      );
      await search;

      expect(controller.previewLines, isEmpty);
      expect(controller.notice, '预览失败，请重试。');
    },
  );

  test('ignores a Preview result for a different requested page', () async {
    final core = _ControlledCore(searchResults: [_candidate('candidate')]);
    final controller = SubtitleController(core);
    controller.selectVideo('episode.mkv');

    final search = controller.search();
    await Future<void>.delayed(Duration.zero);
    core.previewRequests.single.completer.complete(
      const SubtitlePreviewPage(
        candidateId: 'candidate',
        lines: ['wrong page'],
        page: 2,
        totalPages: 2,
      ),
    );
    await search;

    expect(controller.previewLines, isEmpty);
    expect(controller.notice, '预览失败，请重试。');
  });

  test(
    'cancel prevents a stale Search completion from restoring state',
    () async {
      final core = _ControlledCore();
      final controller = SubtitleController(core);
      controller.selectVideo('episode.mkv');

      final search = controller.search();
      controller.cancel();
      core.searchRequests.single.completer.complete([_candidate('stale')]);
      await search;

      expect(controller.candidates, isEmpty);
      expect(controller.previewLines, isEmpty);
      expect(controller.notice, '已取消当前选择');
    },
  );

  test('transient Preview failure keeps the last successful page', () async {
    final (controller, core) = await _readyController();

    final request = controller.nextPreviewPage();
    core.previewRequests[1].completer.completeError(
      const SubtitleCoreException(
        kind: SubtitleFailureKind.providerUnavailable,
        operation: 'preview',
      ),
    );
    await request;

    expect(controller.previewLines, ['last successful preview']);
    expect(controller.previewPage, 0);
    expect(controller.previewPageCount, 2);
    expect(controller.notice, '预览失败，请重试。');
  });

  test('CandidateExpired clears Preview and asks for another Search', () async {
    final (controller, core) = await _readyController();

    final request = controller.nextPreviewPage();
    core.previewRequests[1].completer.completeError(
      const SubtitleCoreException(
        kind: SubtitleFailureKind.candidateExpired,
        operation: 'preview',
      ),
    );
    await request;

    expect(controller.previewLines, isEmpty);
    expect(controller.previewPageCount, 0);
    expect(controller.notice, '候选已过期，请重新搜索。');
  });

  test('out-of-range Preview restores authoritative page one', () async {
    final (controller, core) = await _readyController();

    final request = controller.nextPreviewPage();
    core.previewRequests[1].completer.completeError(
      const SubtitleCoreException(
        kind: SubtitleFailureKind.previewPageOutOfRange,
        operation: 'preview',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(core.previewRequests.map((request) => request.page), [1, 2, 1]);
    core.previewRequests[2].completer.complete(
      const SubtitlePreviewPage(
        candidateId: 'candidate',
        lines: ['restored page one'],
        page: 1,
        totalPages: 2,
      ),
    );
    await request;

    expect(controller.previewLines, ['restored page one']);
    expect(controller.previewPage, 0);
    expect(controller.notice, '预览页码无效，已返回第 1 页。');
  });

  test('Internal Preview failure preserves usable state', () async {
    final (controller, core) = await _readyController();

    final request = controller.nextPreviewPage();
    core.previewRequests[1].completer.completeError(
      const SubtitleCoreException(
        kind: SubtitleFailureKind.internal,
        operation: 'preview',
      ),
    );
    await request;

    expect(controller.previewLines, ['last successful preview']);
    expect(controller.previewPage, 0);
    expect(controller.previewPageCount, 2);
    expect(controller.notice, '预览失败，请重试。');
  });

  test('Saved acquisition reports the generated subtitle name', () async {
    final (controller, _) = await _readyController(
      downloadOutcome: SubtitleSaveOutcome.saved,
    );

    await controller.downloadSelected();

    expect(controller.notice, '字幕已保存为 episode.srt');
    expect(controller.savedVideoPath, 'episode.mkv');
  });

  test('Cancelled platform save reports cancellation', () async {
    final (controller, _) = await _readyController(
      downloadOutcome: SubtitleSaveOutcome.cancelled,
    );

    await controller.downloadSelected();

    expect(controller.notice, '已取消保存');
  });

  test('typed SaveFailed reports a save failure', () async {
    final (controller, _) = await _readyController(
      downloadFailure: const SubtitleCoreException(
        kind: SubtitleFailureKind.saveFailed,
        operation: 'acquisition',
      ),
    );

    await controller.downloadSelected();

    expect(controller.notice, '保存失败，请稍后重试。');
  });

  test(
    'CandidateExpired Acquisition clears Preview and asks for Search',
    () async {
      final (controller, _) = await _readyController(
        downloadFailure: const SubtitleCoreException(
          kind: SubtitleFailureKind.candidateExpired,
          operation: 'acquisition',
        ),
      );

      await controller.downloadSelected();

      expect(controller.previewLines, isEmpty);
      expect(controller.previewPageCount, 0);
      expect(controller.notice, '候选已过期，请重新搜索。');
    },
  );

  test(
    'invalid Artifact keeps Candidate and last successful Preview',
    () async {
      final (controller, _) = await _readyController(
        downloadFailure: const SubtitleCoreException(
          kind: SubtitleFailureKind.artifactInvalid,
          operation: 'acquisition',
        ),
      );

      await controller.downloadSelected();

      expect(controller.selectedCandidate?.id, 'candidate');
      expect(controller.previewLines, ['last successful preview']);
      expect(controller.notice, '字幕内容无效，请选择其他候选。');
    },
  );
}

Future<(SubtitleController, _ControlledCore)> _readyController({
  SubtitleSaveOutcome downloadOutcome = SubtitleSaveOutcome.saved,
  SubtitleCoreException? downloadFailure,
}) async {
  final core = _ControlledCore(
    searchResults: [_candidate('candidate')],
    downloadOutcome: downloadOutcome,
    downloadFailure: downloadFailure,
  );
  final controller = SubtitleController(core);
  controller.selectVideo('episode.mkv');
  final search = controller.search();
  await Future<void>.delayed(Duration.zero);
  core.previewRequests.single.completer.complete(
    const SubtitlePreviewPage(
      candidateId: 'candidate',
      lines: ['last successful preview'],
      page: 1,
      totalPages: 2,
    ),
  );
  await search;
  return (controller, core);
}

SubtitleCandidate _candidate(String id) => SubtitleCandidate(
  id: id,
  name: '$id.srt',
  languages: const ['zh-CN'],
  format: 'SRT',
  matchScore: 90,
  matchReasons: const ['exact title'],
);

class _ControlledCore implements SubtitleCore {
  _ControlledCore({
    this.searchResults,
    this.downloadOutcome = SubtitleSaveOutcome.saved,
    this.downloadFailure,
  });

  final List<SubtitleCandidate>? searchResults;
  final SubtitleSaveOutcome downloadOutcome;
  final SubtitleCoreException? downloadFailure;
  final searchRequests =
      <({String query, Completer<List<SubtitleCandidate>> completer})>[];
  final previewRequests =
      <
        ({
          String candidateId,
          int page,
          Completer<SubtitlePreviewPage> completer,
        })
      >[];

  @override
  String suggestedSearchName(String fileName) => deriveSearchName(fileName);

  @override
  Future<List<SubtitleCandidate>> search(String query) {
    final results = searchResults;
    if (results != null) return Future<List<SubtitleCandidate>>.value(results);
    final completer = Completer<List<SubtitleCandidate>>();
    searchRequests.add((query: query, completer: completer));
    return completer.future;
  }

  @override
  Future<SubtitlePreviewPage> preview(SubtitleCandidate candidate, int page) {
    final completer = Completer<SubtitlePreviewPage>();
    previewRequests.add((
      candidateId: candidate.id,
      page: page,
      completer: completer,
    ));
    return completer.future;
  }

  @override
  Future<SubtitleSaveOutcome> download(
    SubtitleCandidate candidate, {
    required String videoFileName,
  }) async {
    final failure = downloadFailure;
    if (failure != null) throw failure;
    return downloadOutcome;
  }
}

class _FakeCore implements SubtitleCore {
  final requestedPages = <int>[];

  @override
  String suggestedSearchName(String fileName) => deriveSearchName(fileName);

  @override
  Future<List<SubtitleCandidate>> search(String query) async => [
    SubtitleCandidate(
      id: '1',
      name: 'candidate 1.srt',
      languages: ['zh-CN'],
      format: 'SRT',
      matchScore: 98,
      matchReasons: ['exact title'],
    ),
    SubtitleCandidate(
      id: '2',
      name: 'candidate 2.srt',
      languages: ['zh-TW'],
      format: 'SRT',
      matchScore: 90,
      matchReasons: ['language'],
    ),
  ];

  @override
  Future<SubtitlePreviewPage> preview(
    SubtitleCandidate candidate,
    int page,
  ) async {
    requestedPages.add(page);
    final lines = List<String>.generate(
      65,
      (index) => candidate.id == '2'
          ? 'candidate 2 line ${index + 1}'
          : 'line ${index + 1}',
    );
    final start = (page - 1) * 30;
    return SubtitlePreviewPage(
      candidateId: candidate.id,
      lines: lines.sublist(start, (start + 30).clamp(0, lines.length)),
      page: page,
      totalPages: 3,
    );
  }

  @override
  Future<SubtitleSaveOutcome> download(
    SubtitleCandidate candidate, {
    required String videoFileName,
  }) async => SubtitleSaveOutcome.saved;
}

class _DelayedPreviewCore extends _FakeCore {
  final previewCompleter = Completer<SubtitlePreviewPage>();

  @override
  Future<SubtitlePreviewPage> preview(SubtitleCandidate candidate, int page) =>
      previewCompleter.future;
}
