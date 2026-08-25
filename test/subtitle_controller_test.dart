import 'package:flutter_test/flutter_test.dart';
import 'package:ss_subtitle/src/controller/subtitle_controller.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';

void main() {
  test('从最后一个 @ 后提取自动搜索名', () {
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

  test('字幕保存基名保留原视频文件名', () {
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

  test('搜索、候选切换和每 30 行分页形成完整状态流', () async {
    final controller = SubtitleController(_FakeCore());

    controller.selectVideo('publisher@documentary_episode.mp4');
    expect(controller.query, 'documentary_episode');

    await controller.search();
    expect(controller.status, SearchStatus.ready);
    expect(controller.candidates, hasLength(2));
    expect(controller.visiblePreviewLines, hasLength(30));
    expect(controller.previewPageCount, 3);

    controller.nextPreviewPage();
    expect(controller.previewPage, 1);
    expect(controller.visiblePreviewLines.first, '第 31 行');

    await controller.moveSelection(1);
    expect(controller.selectedIndex, 1);
    expect(controller.previewPage, 0);
    expect(controller.visiblePreviewLines.first, '第二字幕 第 1 行');

    await controller.downloadSelected();
    expect(controller.notice, '已下载 publisher@documentary_episode.srt');
  });
}

class _FakeCore implements SubtitleCore {
  @override
  String suggestedSearchName(String fileName) => deriveSearchName(fileName);

  @override
  Future<List<SubtitleCandidate>> search(String query) async => const [
    SubtitleCandidate(
      id: '1',
      name: '第一字幕.srt',
      language: '简体中文',
      format: 'SRT',
      score: 98,
      reasons: ['完全匹配'],
    ),
    SubtitleCandidate(
      id: '2',
      name: '第二字幕.srt',
      language: '繁体中文',
      format: 'SRT',
      score: 90,
      reasons: ['时长匹配'],
    ),
  ];

  @override
  Future<List<String>> preview(SubtitleCandidate candidate) async =>
      List.generate(
        65,
        (index) => '${candidate.id == '2' ? '第二字幕 ' : ''}第 ${index + 1} 行',
      );

  @override
  Future<String> download(
    SubtitleCandidate candidate, {
    required String videoFileName,
  }) async =>
      '已下载 ${deriveSubtitleBaseName(videoFileName)}.'
      '${candidate.format.toLowerCase()}';
}
