import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss_subtitle/app.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';

void main() {
  testWidgets('紧凑布局可从视频名搜索、预览并翻页', (tester) async {
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
    expect(find.text('第 2/2 页'), findsOneWidget);
    expect(find.text('第 31 行'), findsOneWidget);
  });

  testWidgets('宽屏布局支持键盘切换候选和下载', (tester) async {
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
      find.text('已保存 archive.example@documentary_episode.ass'),
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
      language: '简体中文',
      format: 'SRT',
      score: 96,
      reasons: const ['文件名完全匹配'],
    ),
    const SubtitleCandidate(
      id: 'second',
      name: '第二候选.ass',
      language: '简体中文',
      format: 'ASS',
      score: 88,
      reasons: ['时长接近'],
    ),
  ];

  @override
  Future<List<String>> preview(SubtitleCandidate candidate) async =>
      List.generate(45, (index) => '第 ${index + 1} 行');

  @override
  Future<String> download(
    SubtitleCandidate candidate, {
    required String videoFileName,
  }) async =>
      '已保存 ${deriveSubtitleBaseName(videoFileName)}.'
      '${candidate.format.toLowerCase()}';
}
