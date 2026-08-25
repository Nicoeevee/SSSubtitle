import 'package:flutter_test/flutter_test.dart';
import 'package:ss_subtitle/src/core/rust_subtitle_core.dart';

void main() {
  test('预览按 Rust 的 1-based 页码不重不漏地加载', () {
    final requestedPages = <int>[];

    final lines = collectSubtitlePreviewLines((page) {
      requestedPages.add(page);
      return (lines: ['第 $page 页'], totalPages: 3);
    });

    expect(requestedPages, [1, 2, 3]);
    expect(lines, ['第 1 页', '第 2 页', '第 3 页']);
  });
}
