import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:ss_subtitle/src/controller/subtitle_controller.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';
import 'package:ss_subtitle/src/platform/video_folder.dart';
import 'package:ss_subtitle/src/platform/video_picker.dart';
import 'package:ss_subtitle/src/theme/app_theme.dart';

bool _hasDirectorySeparator(String path) => path.contains(RegExp(r'[\\/]'));

class SubtitleHomePage extends StatefulWidget {
  const SubtitleHomePage({
    required this.core,
    this.videoPicker,
    this.videoFolderOpener,
    super.key,
  });

  final SubtitleCore core;
  final VideoNamePicker? videoPicker;
  final VideoFolderOpener? videoFolderOpener;

  @override
  State<SubtitleHomePage> createState() => _SubtitleHomePageState();
}

class _SubtitleHomePageState extends State<SubtitleHomePage> {
  late final SubtitleController controller;
  late final TextEditingController videoController;
  late final TextEditingController queryController;

  @override
  void initState() {
    super.initState();
    controller = SubtitleController(widget.core)..addListener(_onChanged);
    videoController = TextEditingController();
    queryController = TextEditingController();
  }

  void _onChanged() {
    if (!mounted) return;
    if (queryController.text != controller.query) {
      queryController.value = TextEditingValue(
        text: controller.query,
        selection: TextSelection.collapsed(offset: controller.query.length),
      );
    }
    setState(() {});
  }

  Future<void> _pickVideo() async {
    final name = await (widget.videoPicker ?? pickVideoName)();
    if (!mounted || name == null || name.trim().isEmpty) return;
    videoController.text = _videoDisplayName(name);
    controller.selectVideo(name);
  }

  static String _videoDisplayName(String path) =>
      path.trim().replaceAll('\\', '/').split('/').last;

  Future<void> _openVideoFolder() async {
    final path = controller.savedVideoPath;
    if (path == null || !_hasDirectorySeparator(path)) return;
    final opened = await (widget.videoFolderOpener ?? openVideoFolder)(path);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('无法打开视频文件夹')));
  }

  @override
  void dispose() {
    controller
      ..removeListener(_onChanged)
      ..dispose();
    videoController.dispose();
    queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          controller.moveSelection(-1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          controller.moveSelection(1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            controller.previousPreviewPage,
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            controller.nextPreviewPage,
        const SingleActivator(LogicalKeyboardKey.home):
            controller.firstCandidate,
        const SingleActivator(LogicalKeyboardKey.end): controller.lastCandidate,
        const SingleActivator(LogicalKeyboardKey.pageUp): () {
          controller.pageCandidates(-1);
        },
        const SingleActivator(LogicalKeyboardKey.pageDown): () {
          controller.pageCandidates(1);
        },
        const SingleActivator(LogicalKeyboardKey.enter):
            controller.downloadSelected,
        const SingleActivator(LogicalKeyboardKey.escape): controller.cancel,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              'SSSubtitle',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1440),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: wide ? _wideLayout() : _compactLayout(),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _wideLayout() {
    return Column(
      children: [
        _SearchCard(
          controller: controller,
          videoController: videoController,
          queryController: queryController,
          onPickVideo: _pickVideo,
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 380,
                child: _CandidatePanel(controller: controller),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _PreviewPanel(
                  controller: controller,
                  onOpenVideoFolder: _openVideoFolder,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compactLayout() {
    return ListView(
      key: const Key('compact-scroll'),
      children: [
        _SearchCard(
          controller: controller,
          videoController: videoController,
          queryController: queryController,
          onPickVideo: _pickVideo,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(height: 300, child: _CandidatePanel(controller: controller)),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 480,
          child: _PreviewPanel(
            controller: controller,
            onOpenVideoFolder: _openVideoFolder,
          ),
        ),
      ],
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.controller,
    required this.videoController,
    required this.queryController,
    required this.onPickVideo,
  });

  final SubtitleController controller;
  final TextEditingController videoController;
  final TextEditingController queryController;
  final Future<void> Function() onPickVideo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                M3EContainer.pill(
                  height: 32,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Text(
                      '01',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('从视频开始', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 56,
              child: TextField(
                key: Key('video-name-field'),
                controller: videoController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: '视频文件名',
                  hintText: '例如 documentary_episode.mp4',
                  prefixIcon: Icon(Icons.movie_outlined),
                ),
                onSubmitted: controller.selectVideo,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: M3EFilledButton.icon(
                key: const Key('select-video-button'),
                onPressed: onPickVideo,
                icon: const Icon(Icons.video_file_outlined),
                label: const Text('选择视频'),
                size: M3EButtonSize.xs,
                decoration: const M3EButtonDecoration(
                  haptic: M3EHapticFeedback.light,
                ),
              ),
            ),
            if (controller.videoName.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 56,
                child: TextField(
                  key: Key('query-field'),
                  controller: queryController,
                  decoration: InputDecoration(
                    labelText: '搜索名称（可修改）',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: controller.setQuery,
                  onSubmitted: (_) => controller.search(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: M3EFilledButton.icon(
                  key: const Key('search-button'),
                  onPressed: controller.status == SearchStatus.loading
                      ? null
                      : controller.search,
                  icon: const Icon(Icons.travel_explore_rounded),
                  label: const Text('搜索字幕'),
                  size: M3EButtonSize.xs,
                  decoration: const M3EButtonDecoration(
                    haptic: M3EHapticFeedback.medium,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Production ranking uses a weighted 0–1680 score, while the demo core already
// supplies a 0–100 value. Keep the conversion in presentation code so the
// domain score remains available for ordering and diagnostics.
const _maxWeightedMatchScore = 1680;

int _matchPercentage(int score) {
  if (score <= 100) return score.clamp(0, 100).toInt();
  final bounded = score.clamp(0, _maxWeightedMatchScore);
  return ((bounded * 100) / _maxWeightedMatchScore)
      .round()
      .clamp(0, 100)
      .toInt();
}

class _CandidatePanel extends StatelessWidget {
  const _CandidatePanel({required this.controller});

  final SubtitleController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '字幕候选',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (controller.candidates.isNotEmpty)
                  Text(
                    '${controller.selectedIndex + 1}/${controller.candidates.length}',
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _candidateBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _candidateBody(BuildContext context) {
    switch (controller.status) {
      case SearchStatus.idle:
        return const _MessageState(
          icon: Icons.manage_search_rounded,
          title: '等待搜索',
          message: '选择视频并确认搜索名称后，候选字幕会显示在这里。',
        );
      case SearchStatus.loading:
        return const _MessageState(
          loading: true,
          title: '正在搜索字幕',
          message: '正在比较文件名、时长与字幕来源…',
        );
      case SearchStatus.empty:
        return const _MessageState(
          icon: Icons.search_off_rounded,
          title: '没有找到字幕',
          message: '尝试缩短搜索名称，或检查文件名是否正确。',
        );
      case SearchStatus.error:
        return _MessageState(
          icon: Icons.error_outline_rounded,
          title: '搜索遇到问题',
          message: controller.errorMessage ?? '未知错误',
        );
      case SearchStatus.ready:
        final scheme = Theme.of(context).colorScheme;
        return M3ECardList.builder(
          key: const Key('candidate-list'),
          itemCount: controller.candidates.length,
          itemBuilder: (context, index) {
            final item = controller.candidates[index];
            final selected = index == controller.selectedIndex;
            return Semantics(
              key: Key('candidate-$index'),
              selected: selected,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    M3EContainer.pill(
                      width: 62,
                      height: 36,
                      color: selected
                          ? scheme.secondary
                          : scheme.secondaryContainer,
                      child: Center(
                        child: Text(
                          '${_matchPercentage(item.matchScore)}%',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: selected
                                    ? scheme.onSecondary
                                    : scheme.onSecondaryContainer,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (item.languages.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              item.languages.join(' / '),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                          if (item.matchReasons.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              item.matchReasons.join(' · '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Icon(
                        Icons.check_circle_rounded,
                        color: scheme.primary,
                        semanticLabel: '已选择',
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
          onTap: (index) {
            controller.selectCandidate(index);
          },
          semanticLabelBuilder: (index) {
            final item = controller.candidates[index];
            return '${item.name}，匹配度 ${_matchPercentage(item.matchScore)}%';
          },
          color: scheme.surfaceContainerHigh,
          padding: const EdgeInsets.all(AppSpacing.sm),
          gap: AppSpacing.xs,
          haptic: M3EHapticFeedback.light,
          listPadding: EdgeInsets.zero,
        );
    }
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.controller,
    required this.onOpenVideoFolder,
  });

  final SubtitleController controller;
  final Future<void> Function() onOpenVideoFolder;

  @override
  Widget build(BuildContext context) {
    final candidate = controller.selectedCandidate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '字幕预览',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (controller.previewPageCount > 0)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '第 ${controller.previewPage + 1}/${controller.previewPageCount} 页',
                    ),
                  ),
              ],
            ),
            if (candidate != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                candidate.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (controller.previewPageCount > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              _PreviewPageSlider(controller: controller),
            ],
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _previewBody(context)),
            const SizedBox(height: AppSpacing.sm),
            _PreviewControls(
              controller: controller,
              onOpenVideoFolder: onOpenVideoFolder,
            ),
            if (controller.notice != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Semantics(
                liveRegion: true,
                child: Text(
                  controller.notice!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewBody(BuildContext context) {
    if (controller.previewLoading) {
      return const _MessageState(
        loading: true,
        title: '正在载入预览',
        message: '字幕只会按需载入一次。',
      );
    }
    if (controller.selectedCandidate == null) {
      return const _MessageState(
        icon: Icons.closed_caption_off_outlined,
        title: '尚未选择字幕',
        message: '搜索后选择候选，即可按每页 30 行预览。',
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(AppRadii.reading),
      ),
      child: Semantics(
        label: '字幕文本，每页 30 行',
        child: ListView.builder(
          key: const Key('preview-lines'),
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: controller.visiblePreviewLines.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Text(
              controller.visiblePreviewLines[index],
              style: _previewTextStyle(context),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _previewTextStyle(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onInverseSurface,
      height: 1.35,
    );
    final previewStyle = GoogleFonts.jetBrainsMono(textStyle: bodyStyle);
    final themeFamily = bodyStyle?.fontFamily;
    final themeFallback = bodyStyle?.fontFamilyFallback ?? const <String>[];
    final previewFallback =
        previewStyle.fontFamilyFallback ?? const <String>[];
    return previewStyle.copyWith(
      fontFamilyFallback: <String>[
        ...?(themeFamily == null ? null : <String>[themeFamily]),
        ...themeFallback,
        ...previewFallback,
      ],
    );
  }
}

class _PreviewPageSlider extends StatefulWidget {
  const _PreviewPageSlider({required this.controller});

  final SubtitleController controller;

  @override
  State<_PreviewPageSlider> createState() => _PreviewPageSliderState();
}

class _PreviewPageSliderState extends State<_PreviewPageSlider> {
  double? _draggingValue;
  int? _pendingPage;
  String? _interactionCandidateId;

  @override
  void didUpdateWidget(covariant _PreviewPageSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final candidateId = widget.controller.selectedCandidate?.id;
    final pageCount = widget.controller.previewPageCount;
    final pendingPage = _pendingPage;

    if (_interactionCandidateId != null &&
        _interactionCandidateId != candidateId) {
      _clearInteraction();
      return;
    }
    if (pendingPage != null &&
        (pendingPage > pageCount ||
            (!widget.controller.previewLoading &&
                widget.controller.previewPage + 1 != pendingPage))) {
      _clearInteraction();
    }
  }

  void _clearInteraction() {
    _draggingValue = null;
    _pendingPage = null;
    _interactionCandidateId = null;
  }

  int _pageForValue(double value, int pageCount) =>
      value.round().clamp(1, pageCount).toInt();

  void _onChangeStart(double value, int pageCount) {
    setState(() {
      _draggingValue = value.clamp(1.0, pageCount.toDouble()).toDouble();
      _pendingPage = null;
      _interactionCandidateId = widget.controller.selectedCandidate?.id;
    });
  }

  void _onChanged(double value, int pageCount) {
    setState(() {
      _draggingValue = value.clamp(1.0, pageCount.toDouble()).toDouble();
    });
  }

  void _onChangeEnd(double value, int pageCount) {
    final targetPage = _pageForValue(_draggingValue ?? value, pageCount);
    final currentPage = widget.controller.previewPage + 1;
    if (targetPage == currentPage) {
      setState(_clearInteraction);
      return;
    }

    setState(() {
      _draggingValue = targetPage.toDouble();
      _pendingPage = targetPage;
      _interactionCandidateId = widget.controller.selectedCandidate?.id;
    });
    unawaited(widget.controller.goToPreviewPage(targetPage));
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = widget.controller.previewPageCount;
    if (pageCount <= 0) return const SizedBox.shrink();

    final currentPage = widget.controller.previewPage + 1;
    final draggingValue = _draggingValue;
    final displayedPage = draggingValue == null
        ? currentPage
        : _pageForValue(draggingValue, pageCount);
    final enabled = pageCount > 1 && !widget.controller.previewLoading;

    return Semantics(
      container: true,
      slider: true,
      label: '预览进度',
      value: '第 $displayedPage/$pageCount 页',
      increasedValue: displayedPage < pageCount
          ? '第 ${displayedPage + 1}/$pageCount 页'
          : null,
      decreasedValue: displayedPage > 1
          ? '第 ${displayedPage - 1}/$pageCount 页'
          : null,
      onIncrease: enabled && displayedPage < pageCount
          ? () =>
                unawaited(widget.controller.goToPreviewPage(displayedPage + 1))
          : null,
      onDecrease: enabled && displayedPage > 1
          ? () =>
                unawaited(widget.controller.goToPreviewPage(displayedPage - 1))
          : null,
      child: SizedBox(
        height: 48,
        child: M3ESlider(
          key: const Key('preview-page-slider'),
          value: draggingValue ?? currentPage.toDouble(),
          min: 1,
          max: pageCount.toDouble(),
          divisions: pageCount > 1 ? pageCount - 1 : null,
          enabled: enabled,
          label: '第 $displayedPage/$pageCount 页',
          onChangeStart: enabled
              ? (value) => _onChangeStart(value, pageCount)
              : null,
          onChanged: enabled ? (value) => _onChanged(value, pageCount) : null,
          onChangeEnd: enabled
              ? (value) => _onChangeEnd(value, pageCount)
              : null,
        ),
      ),
    );
  }
}

class _PreviewControls extends StatelessWidget {
  const _PreviewControls({
    required this.controller,
    required this.onOpenVideoFolder,
  });

  final SubtitleController controller;
  final Future<void> Function() onOpenVideoFolder;

  @override
  Widget build(BuildContext context) {
    final hasCandidate = controller.selectedCandidate != null;
    final savedVideoPath = controller.savedVideoPath;
    final canOpenVideoFolder =
        savedVideoPath != null && _hasDirectorySeparator(savedVideoPath);
    return Center(
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          M3EOutlinedButton(
            key: const Key('previous-preview-page'),
            tooltip: '上一页（←）',
            onPressed: controller.previewPage > 0
                ? controller.previousPreviewPage
                : null,
            size: M3EButtonSize.xs,
            child: const Icon(Icons.chevron_left_rounded),
          ),
          M3EOutlinedButton(
            key: const Key('next-preview-page'),
            tooltip: '下一页（→）',
            onPressed: controller.previewPage + 1 < controller.previewPageCount
                ? controller.nextPreviewPage
                : null,
            size: M3EButtonSize.xs,
            child: const Icon(Icons.chevron_right_rounded),
          ),
          Tooltip(
            message: '保存字幕',
            child: M3EFilledButton.icon(
              key: const Key('download-button'),
              onPressed: hasCandidate && !controller.downloading
                  ? controller.downloadSelected
                  : null,
              icon: controller.downloading
                  ? const M3ECircularProgressIndicator(size: 20, strokeWidth: 2)
                  : const Icon(Icons.save_alt_rounded),
              label: Text(controller.downloading ? '保存中' : '保存字幕'),
              size: M3EButtonSize.md,
              decoration: const M3EButtonDecoration(
                haptic: M3EHapticFeedback.heavy,
              ),
            ),
          ),
          if (canOpenVideoFolder)
            M3EOutlinedButton.icon(
              key: const Key('open-video-folder-button'),
              onPressed: onOpenVideoFolder,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('打开视频文件夹'),
              size: M3EButtonSize.sm,
            ),
          M3EOutlinedButton.icon(
            key: const Key('cancel-button'),
            onPressed: hasCandidate ? controller.cancel : null,
            icon: const Icon(Icons.close_rounded),
            label: const Text('取消'),
            size: M3EButtonSize.sm,
          ),
          Tooltip(
            message: '↑↓ 切换候选 · ←→ 预览翻页 · Home/End 首尾 · PageUp/PageDown 快选 · Enter 保存 · Esc 取消',
            child: const IconButton(
              onPressed: null,
              icon: Icon(Icons.keyboard_alt_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.title,
    required this.message,
    this.icon,
    this.loading = false,
  });

  final String title;
  final String message;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: loading,
      label: '$title。$message',
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const M3EContainedLoadingIndicator(
                    width: 72,
                    height: 72,
                    padding: EdgeInsets.all(AppSpacing.xs),
                    semanticsLabel: '正在处理',
                  )
                else
                  M3EContainer.circle(
                    width: 56,
                    height: 56,
                    color: scheme.primaryContainer,
                    child: Icon(
                      icon,
                      size: 28,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
