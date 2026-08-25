import 'package:flutter/foundation.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';

enum SearchStatus { idle, loading, ready, empty, error }

class SubtitleController extends ChangeNotifier {
  SubtitleController(this._core);

  static const previewPageSize = 30;
  final SubtitleCore _core;

  String videoName = '';
  String suggestedQuery = '';
  String query = '';
  SearchStatus status = SearchStatus.idle;
  String? errorMessage;
  String? notice;
  List<SubtitleCandidate> candidates = const [];
  int selectedIndex = 0;
  List<String> previewLines = const [];
  int previewPage = 0;
  bool previewLoading = false;
  bool downloading = false;

  SubtitleCandidate? get selectedCandidate => candidates.isEmpty
      ? null
      : candidates[selectedIndex.clamp(0, candidates.length - 1)];

  int get previewPageCount =>
      previewLines.isEmpty ? 0 : (previewLines.length / previewPageSize).ceil();

  List<String> get visiblePreviewLines {
    final start = previewPage * previewPageSize;
    if (start >= previewLines.length) return const [];
    final end = (start + previewPageSize).clamp(0, previewLines.length);
    return previewLines.sublist(start, end);
  }

  void selectVideo(String fileName) {
    videoName = fileName.trim();
    suggestedQuery = _core.suggestedSearchName(videoName);
    query = suggestedQuery;
    status = SearchStatus.idle;
    candidates = const [];
    previewLines = const [];
    notice = null;
    errorMessage = null;
    notifyListeners();
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  Future<void> search() async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      status = SearchStatus.error;
      errorMessage = '请输入搜索名称';
      notifyListeners();
      return;
    }
    status = SearchStatus.loading;
    errorMessage = null;
    notice = null;
    notifyListeners();
    try {
      candidates = await _core.search(normalized);
      selectedIndex = 0;
      status = candidates.isEmpty ? SearchStatus.empty : SearchStatus.ready;
      if (candidates.isNotEmpty) await _loadPreview();
    } catch (_) {
      status = SearchStatus.error;
      errorMessage = '搜索失败，请稍后重试。';
      candidates = const [];
      previewLines = const [];
    }
    notifyListeners();
  }

  Future<void> selectCandidate(int index) async {
    if (candidates.isEmpty) return;
    final target = index.clamp(0, candidates.length - 1);
    if (target == selectedIndex && previewLines.isNotEmpty) return;
    selectedIndex = target;
    previewPage = 0;
    notice = null;
    notifyListeners();
    await _loadPreview();
    notifyListeners();
  }

  Future<void> moveSelection(int delta) =>
      selectCandidate(selectedIndex + delta);

  Future<void> firstCandidate() => selectCandidate(0);

  Future<void> lastCandidate() => selectCandidate(candidates.length - 1);

  Future<void> pageCandidates(int delta) =>
      selectCandidate(selectedIndex + delta * 5);

  void previousPreviewPage() {
    if (previewPage > 0) {
      previewPage--;
      notifyListeners();
    }
  }

  void nextPreviewPage() {
    if (previewPage + 1 < previewPageCount) {
      previewPage++;
      notifyListeners();
    }
  }

  Future<void> downloadSelected() async {
    final candidate = selectedCandidate;
    if (candidate == null || downloading) return;
    downloading = true;
    notice = null;
    notifyListeners();
    try {
      notice = await _core.download(candidate, videoFileName: videoName);
    } catch (_) {
      notice = '下载失败，请稍后重试。';
    } finally {
      downloading = false;
      notifyListeners();
    }
  }

  void cancel() {
    status = SearchStatus.idle;
    candidates = const [];
    previewLines = const [];
    previewPage = 0;
    notice = '已取消当前选择';
    notifyListeners();
  }

  Future<void> _loadPreview() async {
    final candidate = selectedCandidate;
    if (candidate == null) return;
    previewLoading = true;
    previewLines = const [];
    notifyListeners();
    try {
      previewLines = await _core.preview(candidate);
    } catch (_) {
      previewLines = const ['预览失败，请重试。'];
    } finally {
      previewLoading = false;
    }
  }
}
