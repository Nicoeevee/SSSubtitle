import 'package:flutter/foundation.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';

enum SearchStatus { idle, loading, ready, empty, error }

/// Coordinates relevance-checked Search, Preview-page, and Acquisition calls.
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
  String? savedVideoPath;

  int _totalPreviewPages = 0;
  int _searchGeneration = 0;
  int _previewGeneration = 0;

  SubtitleCandidate? get selectedCandidate => candidates.isEmpty
      ? null
      : candidates[selectedIndex.clamp(0, candidates.length - 1)];

  int get previewPageCount => _totalPreviewPages;

  List<String> get visiblePreviewLines => previewLines;

  void selectVideo(String fileName) {
    _searchGeneration++;
    _previewGeneration++;
    videoName = fileName.trim();
    suggestedQuery = _core.suggestedSearchName(videoName);
    query = suggestedQuery;
    status = SearchStatus.idle;
    candidates = const [];
    selectedIndex = 0;
    _clearPreview();
    downloading = false;
    savedVideoPath = null;
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

    final generation = ++_searchGeneration;
    _previewGeneration++;
    status = SearchStatus.loading;
    errorMessage = null;
    notice = null;
    savedVideoPath = null;
    candidates = const [];
    selectedIndex = 0;
    _clearPreview();
    notifyListeners();

    try {
      final found = await _core.search(normalized);
      if (generation != _searchGeneration) return;
      candidates = List<SubtitleCandidate>.unmodifiable(found);
      status = candidates.isEmpty ? SearchStatus.empty : SearchStatus.ready;
      notifyListeners();
      final candidate = selectedCandidate;
      if (candidate != null) {
        await _loadPreviewPage(
          candidate: candidate,
          page: 1,
          searchGeneration: generation,
        );
      }
    } on SubtitleCoreException catch (error) {
      if (generation != _searchGeneration) return;
      status = SearchStatus.error;
      errorMessage = _searchErrorMessage(error);
      candidates = const [];
      _clearPreview();
      notifyListeners();
    } catch (_) {
      if (generation != _searchGeneration) return;
      status = SearchStatus.error;
      errorMessage = '搜索失败，请稍后重试。';
      candidates = const [];
      _clearPreview();
      notifyListeners();
    }
  }

  Future<void> selectCandidate(int index) async {
    if (candidates.isEmpty) return;
    final target = index.clamp(0, candidates.length - 1);
    if (target == selectedIndex && previewLines.isNotEmpty) return;
    selectedIndex = target;
    notice = null;
    savedVideoPath = null;
    _clearPreview();
    notifyListeners();
    final candidate = selectedCandidate;
    if (candidate != null) {
      await _loadPreviewPage(
        candidate: candidate,
        page: 1,
        searchGeneration: _searchGeneration,
      );
    }
  }

  Future<void> moveSelection(int delta) =>
      selectCandidate(selectedIndex + delta);

  Future<void> firstCandidate() => selectCandidate(0);

  Future<void> lastCandidate() => selectCandidate(candidates.length - 1);

  Future<void> pageCandidates(int delta) =>
      selectCandidate(selectedIndex + delta * 5);

  Future<void> previousPreviewPage() {
    if (previewPage <= 0) return Future<void>.value();
    return _requestPreviewPage(previewPage);
  }

  Future<void> nextPreviewPage() {
    if (previewPage + 1 >= previewPageCount) return Future<void>.value();
    return _requestPreviewPage(previewPage + 2);
  }

  /// Requests an absolute, 1-based Preview page.
  Future<void> goToPreviewPage(int page) {
    if (page < 1 || page > previewPageCount || page == previewPage + 1) {
      return Future<void>.value();
    }
    return _requestPreviewPage(page);
  }

  Future<void> _requestPreviewPage(int page) {
    final candidate = selectedCandidate;
    if (candidate == null) return Future<void>.value();
    return _loadPreviewPage(
      candidate: candidate,
      page: page,
      searchGeneration: _searchGeneration,
    );
  }

  Future<void> downloadSelected() async {
    final candidate = selectedCandidate;
    if (candidate == null || downloading) return;
    final generation = _searchGeneration;
    downloading = true;
    notice = null;
    notifyListeners();
    try {
      final outcome = await _core.download(candidate, videoFileName: videoName);
      if (generation != _searchGeneration ||
          selectedCandidate?.id != candidate.id) {
        return;
      }
      notice = switch (outcome) {
        SubtitleSaveOutcome.saved => () {
          savedVideoPath = videoName;
          return '字幕已保存为 ${deriveSubtitleBaseName(videoName)}.${candidate.format.toLowerCase()}';
        }(),
        SubtitleSaveOutcome.cancelled => '已取消保存',
      };
    } on SubtitleCoreException catch (error) {
      if (generation == _searchGeneration &&
          selectedCandidate?.id == candidate.id) {
        if (error.kind == SubtitleFailureKind.candidateExpired) {
          _clearPreview();
        }
        notice = _downloadErrorMessage(error);
      }
    } catch (_) {
      if (generation == _searchGeneration &&
          selectedCandidate?.id == candidate.id) {
        notice = '下载失败，请稍后重试。';
      }
    } finally {
      if (generation == _searchGeneration) {
        downloading = false;
        notifyListeners();
      }
    }
  }

  void cancel() {
    _searchGeneration++;
    _previewGeneration++;
    status = SearchStatus.idle;
    candidates = const [];
    selectedIndex = 0;
    _clearPreview();
    downloading = false;
    savedVideoPath = null;
    notice = '已取消当前选择';
    errorMessage = null;
    notifyListeners();
  }

  Future<void> _loadPreviewPage({
    required SubtitleCandidate candidate,
    required int page,
    required int searchGeneration,
    String? successNotice,
  }) async {
    final requestGeneration = ++_previewGeneration;
    previewLoading = true;
    errorMessage = null;
    notice = null;
    notifyListeners();
    try {
      final result = await _core.preview(candidate, page);
      if (!_previewIsRelevant(
        searchGeneration: searchGeneration,
        requestGeneration: requestGeneration,
        candidateId: candidate.id,
      )) {
        return;
      }
      if (result.candidateId != candidate.id || result.page != page) {
        notice = '预览失败，请重试。';
        return;
      }
      previewPage = result.page - 1;
      _totalPreviewPages = result.totalPages;
      previewLines = List<String>.unmodifiable(result.lines);
      notice = successNotice;
    } on SubtitleCoreException catch (error) {
      if (!_previewIsRelevant(
        searchGeneration: searchGeneration,
        requestGeneration: requestGeneration,
        candidateId: candidate.id,
      )) {
        return;
      }
      if (error.kind == SubtitleFailureKind.candidateExpired) {
        _clearPreview();
        notice = '候选已过期，请重新搜索。';
      } else if (error.kind == SubtitleFailureKind.previewPageOutOfRange) {
        if (page == 1) {
          _clearPreview();
          notice = '预览失败，请重试。';
        } else {
          await _loadPreviewPage(
            candidate: candidate,
            page: 1,
            searchGeneration: searchGeneration,
            successNotice: '预览页码无效，已返回第 1 页。',
          );
        }
      } else {
        notice = '预览失败，请重试。';
      }
    } catch (_) {
      if (_previewIsRelevant(
        searchGeneration: searchGeneration,
        requestGeneration: requestGeneration,
        candidateId: candidate.id,
      )) {
        notice = '预览失败，请重试。';
      }
    } finally {
      if (_previewIsRelevant(
        searchGeneration: searchGeneration,
        requestGeneration: requestGeneration,
        candidateId: candidate.id,
      )) {
        previewLoading = false;
        notifyListeners();
      }
    }
  }

  bool _previewIsRelevant({
    required int searchGeneration,
    required int requestGeneration,
    required String candidateId,
  }) =>
      searchGeneration == _searchGeneration &&
      requestGeneration == _previewGeneration &&
      selectedCandidate?.id == candidateId;

  void _clearPreview() {
    previewLines = const [];
    previewPage = 0;
    _totalPreviewPages = 0;
    previewLoading = false;
  }

  static String _searchErrorMessage(SubtitleCoreException error) =>
      switch (error.kind) {
        SubtitleFailureKind.invalidSuggestedSearchName => '请输入搜索名称',
        SubtitleFailureKind.providerUnavailable => '搜索失败，请稍后重试。',
        _ => '搜索失败，请稍后重试。',
      };

  static String _downloadErrorMessage(SubtitleCoreException error) =>
      switch (error.kind) {
        SubtitleFailureKind.artifactTooLarge => '字幕文件过大，请选择其他候选。',
        SubtitleFailureKind.artifactInvalid => '字幕内容无效，请选择其他候选。',
        SubtitleFailureKind.candidateExpired => '候选已过期，请重新搜索。',
        SubtitleFailureKind.saveFailed => '保存失败，请稍后重试。',
        _ => '下载失败，请稍后重试。',
      };
}
