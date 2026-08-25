import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss_subtitle/app.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';

void main() {
  testWidgets('compact layout searches, previews, and requests another page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SSSubtitleApp(
        core: _WidgetCore(),
        videoPicker: () async => 'archive.example@documentary_episode.mp4',
      ),
    );
    expect(find.text('等待搜索'), findsOneWidget);

    await tester.tap(find.byKey(const Key('select-video-button')));
    await tester.pump();
    expect(find.text('自动候选名：documentary_episode'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('documentary_episode 中文字幕.srt'), findsWidgets);
    expect(find.text('第 1/2 页'), findsOneWidget);
    expect(find.text('第 1 行'), findsOneWidget);

    final nextPage = find.byKey(const Key('next-preview-page'));
    await tester.drag(
      find.byKey(const Key('compact-scroll')),
      const Offset(0, -700),
    );
    await tester.pump();
    await tester.tap(nextPage);
    await tester.pump();
    await tester.pump();
    expect(find.text('第 2/2 页'), findsOneWidget);
    expect(find.text('第 31 行'), findsOneWidget);
  });

  testWidgets('wide layout switches Candidate and acquires it', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SSSubtitleApp(
        core: _WidgetCore(),
        videoPicker: () async => 'archive.example@documentary_episode.mp4',
      ),
    );
    await tester.tap(find.byKey(const Key('select-video-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('第二候选.ass'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(
      find.text('字幕已保存为 archive.example@documentary_episode.ass'),
      findsOneWidget,
    );
  });
}

class _WidgetCore implements SubtitleCore {
  @override
  String suggestedSearchName(String fileName) => deriveSearchName(fileName);

  @override
  Future<List<SubtitleCandidate>> search(String query) async => [
    SubtitleCandidate(
      id: 'first',
      name: '$query 中文字幕.srt',
      languages: const ['简体中文'],
      format: 'SRT',
      matchScore: 96,
      matchReasons: const ['文件名完全匹配'],
    ),
    SubtitleCandidate(
      id: 'second',
      name: '第二候选.ass',
      languages: ['简体中文'],
      format: 'ASS',
      matchScore: 88,
      matchReasons: ['时长接近'],
    ),
  ];

  @override
  Future<SubtitlePreviewPage> preview(
    SubtitleCandidate candidate,
    int page,
  ) async {
    final lines = List<String>.generate(45, (index) => '第 ${index + 1} 行');
    final start = (page - 1) * 30;
    return SubtitlePreviewPage(
      candidateId: candidate.id,
      lines: lines.sublist(start, (start + 30).clamp(0, lines.length)),
      page: page,
      totalPages: 2,
    );
  }

  @override
  Future<SubtitleSaveOutcome> download(
    SubtitleCandidate candidate, {
    required String videoFileName,
  }) async => SubtitleSaveOutcome.saved;
}
