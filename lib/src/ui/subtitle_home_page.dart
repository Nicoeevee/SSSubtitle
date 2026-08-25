import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ss_subtitle/src/controller/subtitle_controller.dart';
import 'package:ss_subtitle/src/core/subtitle_core.dart';
import 'package:ss_subtitle/src/platform/video_picker.dart';
import 'package:ss_subtitle/src/theme/app_theme.dart';

class SubtitleHomePage extends StatefulWidget {
  const SubtitleHomePage({required this.core, this.videoPicker, super.key});

  final SubtitleCore core;
  final VideoNamePicker? videoPicker;

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
    videoController.text = name;
    controller.selectVideo(name);
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
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.subtitles_rounded),
                SizedBox(width: AppSpacing.xs),
                Text('SSSubtitle'),
              ],
            ),
            actions: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Center(child: Text('跨平台字幕助手')),
              ),
            ],
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
                      child: wide ? _wideLayout() : _compactLayout(),
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
              Expanded(child: _PreviewPanel(controller: controller)),
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
        SizedBox(height: 330, child: _CandidatePanel(controller: controller)),
        const SizedBox(height: AppSpacing.md),
        SizedBox(height: 480, child: _PreviewPanel(controller: controller)),
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
            Text('从视频开始', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '选择本地视频后，只把可编辑的搜索名称发送给字幕服务，不上传视频内容。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 680;
                final field = TextField(
                  key: const Key('video-name-field'),
                  controller: videoController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '视频文件名',
                    hintText: '例如 documentary_episode.mp4',
                    prefixIcon: Icon(Icons.movie_outlined),
                  ),
                  onSubmitted: controller.selectVideo,
                );
                final button = FilledButton.icon(
                  key: const Key('select-video-button'),
                  onPressed: onPickVideo,
                  icon: const Icon(Icons.video_file_outlined),
                  label: const Text('选择视频'),
                );
                return narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          field,
                          const SizedBox(height: AppSpacing.sm),
                          button,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: field),
                          const SizedBox(width: AppSpacing.sm),
                          button,
                        ],
                      );
              },
            ),
            if (controller.videoName.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Semantics(
                liveRegion: true,
                label: '自动候选搜索名 ${controller.suggestedQuery}',
                child: Text(
                  '自动候选名：${controller.suggestedQuery}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 680;
                  final field = TextField(
                    key: const Key('query-field'),
                    controller: queryController,
                    decoration: const InputDecoration(
                      labelText: '搜索名称（可修改）',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: controller.setQuery,
                    onSubmitted: (_) => controller.search(),
                  );
                  final button = FilledButton.icon(
                    key: const Key('search-button'),
                    onPressed: controller.status == SearchStatus.loading
                        ? null
                        : controller.search,
                    icon: const Icon(Icons.travel_explore_rounded),
                    label: const Text('搜索字幕'),
                  );
                  return narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            field,
                            const SizedBox(height: AppSpacing.sm),
                            button,
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: field),
                            const SizedBox(width: AppSpacing.sm),
                            button,
                          ],
                        );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
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
        return ListView.separated(
          key: const Key('candidate-list'),
          itemCount: controller.candidates.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
          itemBuilder: (context, index) {
            final item = controller.candidates[index];
            final selected = index == controller.selectedIndex;
            return Semantics(
              selected: selected,
              button: true,
              label: '${item.name}，匹配分 ${item.score}',
              child: Card(
                color: selected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerLow,
                child: InkWell(
                  key: Key('candidate-$index'),
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                  onTap: () => controller.selectCandidate(index),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Chip(label: Text('${item.score} 分')),
                          ],
                        ),
                        Text('${item.language} · ${item.format}'),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          item.reasons.join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
    }
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.controller});

  final SubtitleController controller;

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
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _previewBody(context)),
            const SizedBox(height: AppSpacing.sm),
            _PreviewControls(controller: controller),
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
        borderRadius: BorderRadius.circular(AppSpacing.sm),
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onInverseSurface,
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewControls extends StatelessWidget {
  const _PreviewControls({required this.controller});

  final SubtitleController controller;

  @override
  Widget build(BuildContext context) {
    final hasCandidate = controller.selectedCandidate != null;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      alignment: WrapAlignment.center,
      children: [
        IconButton.outlined(
          key: const Key('previous-preview-page'),
          tooltip: '上一页（←）',
          onPressed: controller.previewPage > 0
              ? controller.previousPreviewPage
              : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton.outlined(
          key: const Key('next-preview-page'),
          tooltip: '下一页（→）',
          onPressed: controller.previewPage + 1 < controller.previewPageCount
              ? controller.nextPreviewPage
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        Tooltip(
          message: '保存到原视频所在目录，播放器即可按同名规则自动识别',
          child: FilledButton.icon(
            key: const Key('download-button'),
            onPressed: hasCandidate && !controller.downloading
                ? controller.downloadSelected
                : null,
            icon: controller.downloading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt_rounded),
            label: Text(controller.downloading ? '准备保存' : '另存字幕'),
          ),
        ),
        OutlinedButton.icon(
          key: const Key('cancel-button'),
          onPressed: hasCandidate ? controller.cancel : null,
          icon: const Icon(Icons.close_rounded),
          label: const Text('取消'),
        ),
        Tooltip(
          message: '↑↓ 切换候选 · ←→ 预览翻页 · Home/End 首尾 · PageUp/PageDown 快选 · Enter 另存 · Esc 取消',
          child: const IconButton(
            onPressed: null,
            icon: Icon(Icons.keyboard_alt_outlined),
          ),
        ),
      ],
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
                  const CircularProgressIndicator()
                else
                  Icon(
                    icon,
                    size: AppSpacing.xl,
                    color: Theme.of(context).colorScheme.primary,
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
