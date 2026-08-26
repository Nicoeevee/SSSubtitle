import 'package:material_ui/material_ui.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:ss_subtitle/app.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';
import 'package:ss_subtitle/src/theme/app_theme.dart';

void main() {
  test('AppTheme binds the bundled Noto Sans SC theme font', () async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final textThemes = <TextTheme>[
      AppTheme.light.textTheme,
      AppTheme.dark.textTheme,
    ];

    await GoogleFonts.pendingFonts();

    for (final textTheme in textThemes) {
      expect(textTheme.bodyMedium?.fontFamily, 'NotoSansSC_500');
      expect(textTheme.bodyMedium?.fontFamilyFallback, contains('NotoSansSC'));
    }
  });

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
    final selectButton = find.byKey(const Key('select-video-button'));
    expect(tester.widget<M3EFilledButton>(selectButton).size, M3EButtonSize.xs);
    expect(
      tester.getTopLeft(selectButton).dy,
      lessThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const Key('video-name-field'))).dy,
      ),
    );
    expect(
      tester.getSize(selectButton).height,
      lessThan(
        tester.getSize(find.byKey(const Key('video-name-field'))).height,
      ),
    );
    expect(tester.getSize(find.byType(Card).first).height, lessThan(220));
    final selectionSemantics = tester.widget<Semantics>(
      find.byKey(const Key('video-selection-semantics')),
    );
    expect(selectionSemantics.properties.label, '视频文件选择区域');
    expect(selectionSemantics.properties.hint, contains('拖拽视频文件'));
    expect(find.text('找到属于这部视频的字幕'), findsNothing);
    expect(find.text('选择视频、确认搜索名，再预览并保存匹配的 Subtitle Artifact。'), findsNothing);
    expect(find.text('选择本地视频后，只把可编辑的搜索名称发送给字幕服务，不上传视频内容。'), findsNothing);
    expect(find.text('跨平台字幕助手 · 不上传视频'), findsNothing);
    expect(
      find.ancestor(
        of: find.byIcon(Icons.manage_search_rounded),
        matching: find.byType(M3EContainer),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byIcon(Icons.closed_caption_off_outlined),
        matching: find.byType(M3EContainer),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('select-video-button')));
    await tester.pump();
    expect(find.textContaining('自动候选名'), findsNothing);
    final queryField = tester.widget<TextField>(
      find.byKey(const Key('query-field')),
    );
    expect(queryField.controller?.text, 'documentary_episode');
    final searchButton = find.byKey(const Key('search-button'));
    expect(tester.widget<M3EFilledButton>(searchButton).size, M3EButtonSize.xs);
    expect(
      tester.getTopLeft(searchButton).dy,
      lessThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const Key('query-field'))).dy,
      ),
    );
    expect(
      tester.getSize(searchButton).height,
      lessThan(tester.getSize(find.byKey(const Key('query-field'))).height),
    );

    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('documentary_episode 中文字幕.srt'), findsWidgets);
    expect(find.text('96%'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
    expect(find.textContaining('· SRT'), findsNothing);
    expect(find.text('第 1/2 页'), findsOneWidget);
    expect(find.text('第 1 行'), findsOneWidget);

    final previewLine = tester.widget<Text>(find.text('第 1 行'));
    expect(previewLine.style?.fontFamily, 'JetBrainsMono_500');
    expect(previewLine.style?.fontFamilyFallback, contains('NotoSansSC_500'));
    expect(find.byKey(const Key('preview-page-slider')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump();
    expect(find.text('第 2/2 页'), findsOneWidget);
    expect(find.text('第 31 行'), findsOneWidget);
  });

  testWidgets('narrow window stacks file and search actions without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SSSubtitleApp(
        core: _WidgetCore(),
        videoPicker: () async => 'documentary_episode.mp4',
      ),
    );

    final selectButton = find.byKey(const Key('select-video-button'));
    final videoField = find.byKey(const Key('video-name-field'));
    expect(
      tester.getTopLeft(selectButton).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(videoField).dy),
    );
    final selectionSemantics = tester.widget<Semantics>(
      find.byKey(const Key('video-selection-semantics')),
    );
    expect(selectionSemantics.properties.label, '视频文件选择区域');
    expect(selectionSemantics.properties.hint, contains('拖拽视频文件'));
    expect(tester.takeException(), isNull);

    await tester.tap(selectButton);
    await tester.pump();

    final searchButton = find.byKey(const Key('search-button'));
    final queryField = find.byKey(const Key('query-field'));
    expect(
      tester.getTopLeft(searchButton).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(queryField).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dropped video selects its name and prepares the search block', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(SSSubtitleApp(core: _WidgetCore()));

    final dropTarget = tester.widget<DropTarget>(
      find.byKey(const Key('video-drop-target')),
    );
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(r'C:\Media\documentary_episode.mp4')],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('video-name-field')))
          .controller
          ?.text,
      'documentary_episode.mp4',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('query-field')))
          .controller
          ?.text,
      'documentary_episode',
    );
    expect(find.byKey(const Key('search-button')), findsOneWidget);
  });

  testWidgets('preview page slider requests one discrete target page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final core = _WidgetCore();
    await tester.pumpWidget(
      SSSubtitleApp(
        core: core,
        videoPicker: () async => 'archive.example@documentary_episode.mp4',
      ),
    );

    await tester.tap(find.byKey(const Key('select-video-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pump();
    await tester.pump();

    final slider = find.byKey(const Key('preview-page-slider'));
    expect(slider, findsOneWidget);
    final sliderRect = tester.getRect(slider);
    await tester.dragFrom(
      Offset(sliderRect.left + 10, sliderRect.center.dy),
      Offset(sliderRect.width - 20, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    expect(core.previewRequests, [1, 2]);
    expect(find.text('第 2/2 页'), findsOneWidget);
  });

  testWidgets('wide layout switches Candidate and acquires it', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? openedPath;
    await tester.pumpWidget(
      SSSubtitleApp(
        core: _WidgetCore(),
        videoPicker: () async =>
            r'C:\Media\archive.example@documentary_episode.mp4',
        videoFolderOpener: (path) async {
          openedPath = path;
          return true;
        },
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
    expect(find.byKey(const Key('open-video-folder-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-video-folder-button')));
    await tester.pump();
    expect(openedPath, r'C:\Media\archive.example@documentary_episode.mp4');
  });
}

class _WidgetCore implements SubtitleCore {
  final List<int> previewRequests = [];

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
    previewRequests.add(page);
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
