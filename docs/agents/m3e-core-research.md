# m3e_core / Material 3 Expressive 研究笔记

> 核查日期：2026-08-26。本文只使用包作者在 pub.dev/GitHub 发布的包页、README、API 文档与源码，以及 Flutter 官方 material_ui 包文档。版本和平台元数据以核查日的 pub.dev API/包页为准；研究阶段不直接修改依赖或 UI，当前 worktree 的落地结果由后续实现任务完成。

## 先给结论（ponytail 边界）

对 SSSubtitle，最小而完整的落地路径是：

1. 以 m3e_core: ^1.1.1 加 material_ui: ^1.1.0 为基础，把应用自有 Material import 迁移到 package:material_ui/material_ui.dart。
2. 先采用四类直接能改善现有工作流的 API：M3EColorScheme（主题）、M3EButton 的几个具体按钮（动作层级）、M3ECardList（候选结果列表）、M3ELoadingIndicator/M3ECircularProgressIndicator（搜索与预览状态）。
3. 保留当前搜索、候选选择、预览分页、下载、键盘快捷键、Semantics、Rust/FRB 接口和预览字幕的等宽可读性。M3E 只改变 Flutter 表现层，不改变领域状态或分页契约。
4. 只有在页面真的有对应语义时才增加 M3EExpandableCardList 或 M3EDropdownMenu；不要为了“用全套组件”而加入 dismiss、浮动工具栏、Slider、Seekbar、下拉刷新或全局异形裁剪。
5. 把 Windows/Web 的真实构建和运行作为门禁。m3e_core 自身 pubspec 的 Flutter plugin 平台声明只有 Android；这不等于其所有纯 Flutter widget 不能编译到 Web/Windows，但不能从组件页的展示平台直接推断完整跨平台行为。

本次实现已按上述边界落地：`pubspec.yaml` 锁定 `m3e_core: 1.1.1` 与 `material_ui: 1.1.0`；`AppTheme` 使用 `M3EColorScheme`/`M3ETypography`，工作台使用 M3E buttons、`M3ECardList`、loading 与 progress indicators；Rust/FRB 和字幕正文的等宽分页列表保持不变。验证结果由任务结束时的 `flutter analyze`、`flutter test`、Windows release 与 Web/WASM release 构建提供，真实 Chrome/Worker smoke 仍按下方门禁单独记录。

研究时工作树的 pubspec.yaml 已列出 m3e_core: 1.1.1 与 material_ui: 1.1.0，且本地 Flutter 为 3.47.1 / Dart 3.13.1；它满足两者的最低 SDK 要求。研究笔记本身不负责执行依赖或应用代码修改，当前落地状态以上一节为准。

## 1. 版本、安装与迁移

### 1.1 核查到的版本和约束

下表是核查日的最新版本快照。版本号可随 pub.dev 发布变化，实施时仍应重新执行 flutter pub outdated 或读取 pub.dev API。

| 包 | 核查日最新版本 | 最低约束/平台要点 | 在 SSSubtitle 中的角色 |
| --- | --- | --- | --- |
| [m3e_core](https://pub.dev/packages/m3e_core) | 1.1.1 | Dart ^3.11.0，Flutter >=3.47.0；官方 [pubspec.yaml](https://raw.githubusercontent.com/Mudit200408/m3e_core/refs/heads/main/pubspec.yaml) 的 plugin platforms 只声明 Android | 首选聚合依赖；包含主要 M3E widget/API |
| [material_ui](https://pub.dev/packages/material_ui) | 1.1.0 | Dart ^3.12.0，Flutter >=3.44.0；pub.dev 包页列出 Android/iOS/Linux/macOS/Web/Windows | M3E 1.1.x 的 Material 基础层，需与 m3e_core 一起迁移 |
| [m3e_card_list](https://pub.dev/packages/m3e_card_list) | 1.0.0 | Flutter >=3.47.0；卡片列表、Sliver、Column 形态 | 已由 m3e_core 聚合；候选列表首选 |
| [m3e_dismissible](https://pub.dev/packages/m3e_dismissible) | 1.0.0 | Flutter >=3.47.0；带邻居牵引的 dismiss 动画 | 当前工作流暂无“滑动删除”语义，不引入 |
| [m3e_expandable](https://pub.dev/packages/m3e_expandable) | 1.0.0 | Flutter >=3.47.0；data/builder、进度驱动展开动画 | 仅在候选确有附加详情时采用 |
| [m3e_dropdown_menu](https://pub.dev/packages/m3e_dropdown_menu) | 1.0.0 | Flutter >=3.47.0；搜索、异步、单选/多选、chip | 未来有筛选/来源选择时再采用 |
| [m3e_buttons](https://pub.dev/packages/m3e_buttons) | 1.0.0 | Flutter >=3.47.0；filled/tonal/elevated/outlined/text、toggle、split | 搜索、选择、下载、分页动作 |
| [m3e_color_scheme](https://pub.dev/packages/m3e_color_scheme) | 1.0.0 | Flutter >=3.47.0；seed、variant、contrast | 若聚合 barrel 的颜色 API 在分析器中可用，直接使用；不必额外加包 |
| [m3e_progress_indicator](https://pub.dev/packages/m3e_progress_indicator) | 1.0.0 | Flutter >=3.47.0；linear/circular/wavy、确定/不确定进度 | 搜索/下载有真实进度时采用 |
| [m3e_loading_indicator](https://pub.dev/packages/m3e_loading_indicator) | 1.0.0 | Flutter >=3.47.0；形状 morphing、contained、pull-to-refresh | 搜索或预览等待状态采用；不采用下拉刷新形态 |
| [m3e_floating_toolbar](https://pub.dev/packages/m3e_floating_toolbar) | 1.0.0 | Flutter >=3.47.0；水平/垂直、FAB、滚动退出 | 当前动作已有可见按钮和键盘路径，暂不采用 |
| [m3e_slider](https://pub.dev/packages/m3e_slider) | 1.0.0 | Flutter >=3.47.0；spring、tick、haptic | 当前无数值筛选参数，暂不采用 |
| [m3e_seekbar](https://pub.dev/packages/m3e_seekbar) | 1.0.0 | Flutter >=3.47.0；媒体式 seek、buffered track、键盘导航 | 当前没有媒体播放时间轴，暂不采用 |
| [flutter_m3shapes_extended](https://pub.dev/packages/flutter_m3shapes_extended) | 2.0.0 | Flutter >=3.47.0；M3 shape/custom clipper | 只可作为少量品牌/空状态点缀，不全局套用 |
| [m3e_haptics](https://pub.dev/packages/m3e_haptics) | 1.0.0 | 组件页提供跨平台 fallback；其 plugin 元数据仍需按目标平台验证 | Web/桌面保持 none 或极少量明确动作反馈 |
| [m3e_typography](https://pub.dev/packages/m3e_typography) | 0.0.1 | Flutter >=3.47.0；仍是 0.x API | 可评估 emphasized text extension；字幕正文优先可读性 |

m3e_core 1.1.x 的官方 README 明确要求 Flutter 3.47+ 和独立的 material_ui；Flutter 3.47 以下应使用旧线 m3e_core ^0.1.6，但不应为了兼容旧 SDK 而把 SSSubtitle 降回旧 API。参考：[m3e_core README（版本与安装）](https://github.com/Mudit200408/m3e_core#readme)。

### 1.2 安装方式

实施时可使用：

~~~powershell
flutter pub add m3e_core:^1.1.1
flutter pub add material_ui:^1.1.0
~~~

最小导入形态来自官方 [m3e_core.dart barrel 源码](https://raw.githubusercontent.com/Mudit200408/m3e_core/refs/heads/main/lib/m3e_core.dart)：

~~~dart
import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';
~~~

barrel 当前导出 common、card、dismissible、dropdown、expandable、shapes、buttons、floating toolbar、slider、progress、loading、seekbar 和 typography 模块。若只需要聚合包提供的 API，不要同时为每个组件重复添加独立包；这符合 ponytail 的最小依赖边界。只有当聚合包的导出不满足某个明确功能，才单独依赖组件包并锁定其版本。

### 1.3 material_ui 迁移注意事项

material_ui 是 Flutter 官方维护的、从 package:flutter/material.dart 解耦出来的 Material UI 库，不是 m3e_core 自己的替代实现。官方包页和 API 文档给出的迁移路径是：

- 自有 UI 文件中的 package:flutter/material.dart 按需替换为 package:material_ui/material_ui.dart；仅需要基础 widget 时继续使用 package:flutter/widgets.dart，不要机械替换所有 Flutter import。
- 可先执行官方提供的 dart fix --apply --code=migrate_design_widgets，然后逐个解决分析器错误和第三方包兼容性。
- 若旧第三方 widget 仍依赖 Flutter 原始 Material 类型，在 MaterialApp.builder 或对应子树使用官方 MaterialUiCompatibilityBridge；不要把整个业务层复制成两套 Material 类型。
- 保留 GlobalMaterialLocalizations.delegates 等官方本地化配置，并在真实 Web/Windows 运行时确认文本、焦点、快捷键与旧 Material 行为一致。

参考：[Flutter 官方 material_ui 包页](https://pub.dev/packages/material_ui)、[官方 API 文档](https://pub.dev/documentation/material_ui/latest/)。

## 2. API 清单与适用边界

完整符号以 [m3e_core API index](https://pub.dev/documentation/m3e_core/latest/m3e_core/) 为准。下面只列出本项目可落地的公共入口和关键参数；不把所有内部 token 或视觉常量复制进应用。

### 2.1 列表、卡片与展开

| API | 关键能力 | SSSubtitle 用法 |
| --- | --- | --- |
| M3ECard | 单个卡片构建块；需要 index、position、child、outerRadius、innerRadius、gap；支持颜色、padding、border/elevation、tap/hover/focus、semanticLabel 与 haptic | 用作面板内的单个可交互表面时保留明确语义；单个搜索面板不必为了 M3E 而伪装成列表 |
| M3ECardList | 需要 itemCount、itemBuilder；按首/中/尾项自动处理外半径；可调 outerRadius、innerRadius、gap、padding/margin、emptyBuilder、focus/hover、semantics、haptic | 候选结果的最佳切入点；一组结果有连贯的容器层级，比每个候选独立浮起更紧凑 |
| SliverM3ECardList / M3ECardColumn | 在 CustomScrollView 或非滚动 Column 中复用相同卡片外观 | 只有页面确实需要 sliver/Column 时采用，不为当前简单布局引入额外滚动层 |
| M3EDismissibleCardList / M3EDismissibleCardStyle | ListView.builder 只物化可见项；dismiss threshold、邻居牵引、spring、阈值 haptic；onDismiss 返回 Future<bool> 决定是否删除 | 当前候选是“选择”，不是“删除”；除非产品明确增加候选移除操作，否则不采用 |
| M3EExpandableCardList / M3EExpandableCardColumn / Sliver 变体 | data 构造或 builder 构造；builder 收到 progress；支持 allowMultipleExpanded、initiallyExpanded、controller、style、motion、expansion callback | 若候选行需要展开来源、语言、匹配信息，可以替代额外详情弹窗；没有附加详情时保持普通行 |
| M3EExpandableData | title 必填；可选 title/subtitle 样式、leading/trailing、body/bodyBuilder、最大行数 | 仅在数据模型已有稳定详情字段时映射，不为了展示组件 API 而捏造 body |

M3ECardList 的官方 API 说明了其与 ListView.builder/Sliver 的关系及空状态、焦点、hover、无障碍入口，参考 [M3ECardList API](https://pub.dev/documentation/m3e_core/latest/m3e_core/M3ECardList-class.html) 和 [m3e_card_list 包页](https://pub.dev/packages/m3e_card_list)。

### 2.2 下拉菜单

M3EDropdownMenu<T> 提供：

- 基本 items，以及 M3EDropdownMenu<T>.future 异步请求形态；
- 单选/多选、搜索、chip 动画、maxSelections、onSelectionChanged、onSearchChanged；
- M3EDropdownController<T>、M3EDropdownItem<T>、自定义 item/selected/empty builder、separator、validator；
- field/dropdown/chip/search/item style、圆角、open/close M3EMotion 和 haptic。

SSSubtitle 当前的主要输入是视频文件与字幕搜索 query，不需要把现有 TextField 变成“伪下拉菜单”。如果后续增加字幕来源、语言、排序或筛选，优先以一个有明确选项集合的 M3EDropdownMenu<T> 承载；自由文本仍使用普通输入框。

参考：[M3EDropdownMenu API](https://pub.dev/documentation/m3e_core/latest/m3e_core/M3EDropdownMenu-class.html)、[m3e_dropdown_menu 包页](https://pub.dev/packages/m3e_dropdown_menu)。

### 2.3 按钮、动作组与菜单

M3EButton 的公共入口包含 nullable onPressed、child、M3EButtonStyle/size/shape、M3EButtonDecoration、focus node、autofocus、semanticLabel、tooltip、hover/long-press、mouse cursor、feedback 和 splash factory；.icon 工厂用于图标加文字动作。具体实现包括：

- M3EFilledButton：当前状态下最重要的单一动作，例如 Search 或 Download；
- M3EElevatedButton：需要更明显层级时使用，但不要与 FilledButton 同时竞争；
- M3EOutlinedButton：次要动作，例如选择文件、取消；
- M3ETextButton：低强调的分页或辅助动作；
- toggle/split button：只有动作确实是状态切换或一个主动作加菜单时才使用。

m3e_buttons 包页还列出 xs–xl 尺寸、spring radius/padding/focus 动画、toggle group、split menu 和 decoration 系统。SSSubtitle 应先采用 filled/outlined/text 三种基础按钮，维持现有 Key、Semantics、快捷键和禁用状态；不要为了“Expressive”把一个动作拆成 toggle/split 结构。

参考：[M3EButton API](https://pub.dev/documentation/m3e_core/latest/m3e_core/M3EButton-class.html)、[m3e_buttons 包页](https://pub.dev/packages/m3e_buttons)。

### 2.4 颜色、主题与动效

M3EColorScheme.light/dark 接收必需的 seedColor，以及 contrastLevel（-1..1）、M3EColorVariant 和可选 system color scheme。当前 variant 枚举包括 tonalSpot、vibrant、fidelity、expressive、monochrome、neutral、rainbow、fruitSalad。该包强调 AOSP 对齐的 container role/对比度修正；Android 12+ 才有系统壁纸动态颜色同步路径，Web/桌面应使用程序化 seed/variant 和固定 fallback。

推荐：

- 仍使用 ThemeData(useMaterial3: true)；把 ColorScheme.fromSeed 的 seed 生成替换为 M3EColorScheme.light/dark，先从 tonalSpot 或 expressive 进行对比度验证。
- 保留系统亮/暗模式，不要把 expressive variant 误当成必须的亮色主题；验证搜索输入、错误状态、禁用按钮与字幕正文的文本对比度。
- 不把 OS wallpaper dynamic color 作为 Web/Windows 的必需输入。没有该输入时保持稳定的应用 seed。

M3EMotion 提供 spatial（形状/半径）和 effects（opacity/scale）两族的 fast/default/slow 预设，以及 custom(stiffness, damping, snapToEnd)。推荐普通按钮/卡片使用 standard default，只有少量层级变化使用 expressive default；页面应通过 MediaQuery 的动画可用性在需要时降低非必要动画。M3EMotion 没有替代业务状态机的职责。

参考：[m3e_color_scheme 包页](https://pub.dev/packages/m3e_color_scheme)、[M3EMotion API](https://pub.dev/documentation/m3e_core/latest/m3e_core/M3EMotion-class.html)。

### 2.5 加载、进度和 haptic

| API | 关键参数/行为 | 本项目决策 |
| --- | --- | --- |
| M3ECircularProgressIndicator | value: null 可表示不确定进度；可调 stroke、size、颜色等 | 搜索/预览开始但没有总量时替换现有圆形指示器 |
| M3ELinearProgressIndicator | value、颜色、最小高度、stroke cap、gap/stop/width；适合真实百分比 | 只有底层提供确定下载进度时使用；不把“正在等待”伪装成百分比 |
| M3ELinearWavyProgressIndicator / circular wavy | wavelength、waveSpeed、stroke 等表达性 wavy 进度 | 低频、确有确定进度的下载状态可试；搜索等待不需要 wavy 装饰 |
| M3ELoadingIndicator | 默认 morphing；value 为 0–1 或 null 的连续状态，可自定义 shapes/color | _MessageState 的等待状态优先使用小尺寸、稳定占位的 loading indicator |
| M3EContainedLoadingIndicator | 容器尺寸/padding、container/indicator color、shapes | 按钮内部需要保持尺寸稳定时可采用，避免文字跳动 |
| M3EPullToRefreshIndicator | child、onRefresh、controller/style；style 可配置触发距离、阻力、spring、haptic | 当前搜索是显式按钮/快捷键，不采用下拉刷新 |
| M3EHapticFeedback / applyHaptic / applyTypedHaptic | none/light/medium/heavy；config/listener/tracker；拖动纹理、速度 bump、bookend snap；不支持的平台有 fallback | Web/Windows 默认 none；必要时只对显式主动作使用 light，避免键盘和列表操作频繁震动 |

参考：[m3e_loading_indicator 包页](https://pub.dev/packages/m3e_loading_indicator)、[m3e_progress_indicator 包页](https://pub.dev/packages/m3e_progress_indicator)、[m3e_haptics 包页](https://pub.dev/packages/m3e_haptics)。

### 2.6 形状、浮动工具栏、Slider、Seekbar、Typography

- M3EShape、M3EContainer、Shapes 和 flutter_m3shapes_extended 可提供 Gem/Flower/Slanted 等 rounded polygon、clip、border/shadow/gradient。它适合品牌标记或空状态的一个视觉焦点，不适合把搜索输入、候选项和每一行字幕都裁成复杂形状。
- M3EHorizontalFloatingToolbar、M3EVerticalFloatingToolbar、FAB 变体支持 spring 展开、滚动退出、颜色/shape/motion/accessibility。SSSubtitle 的 Search/Download/Cancel/Prev/Next 已在上下文面板中可见，并且有键盘路径；浮动工具栏会增加遮挡和焦点跳转，因此首版不采用。
- M3ESlider、M3ERangeSlider 支持键盘焦点、tick snap、自定义 decoration/haptic；M3ESeekbar/M3EWavySeekbar 还支持 secondary buffered progress、媒体式键盘导航和不同 handle。当前 SSSubtitle 没有数值筛选设置，也没有媒体播放时间轴；不要用 slider/seekbar 代替候选选择或预览分页。
- M3ETypography 与 M3EEmphasizedContextExtension、M3EEmphasizedTextThemeExtension、M3EEmphasizedThemeDataExtension 提供 emphasized M3 typography 入口。标题、状态和按钮标签可评估 emphasized role；预览字幕仍以等宽、可扫描和稳定换行优先，不为变量字体引入额外字体资产。

参考：[flutter_m3shapes_extended 包页](https://pub.dev/packages/flutter_m3shapes_extended)、[m3e_floating_toolbar 包页](https://pub.dev/packages/m3e_floating_toolbar)、[m3e_slider 包页](https://pub.dev/packages/m3e_slider)、[m3e_seekbar 包页](https://pub.dev/packages/m3e_seekbar)；形状、工具栏、Slider、Seekbar、Typography 的聚合符号也可在 [m3e_core API index](https://pub.dev/documentation/m3e_core/latest/m3e_core/) 查到。

## 3. SSSubtitle 的具体集成方案

### 3.1 主题层

在 lib/src/theme/app_theme.dart 集中完成以下变化：

1. 使用 material_ui 的 ThemeData/ColorScheme 类型，并保留 useMaterial3: true。
2. 用 M3EColorScheme.light/dark 生成亮/暗方案，保持当前 seed 的品牌意图；先比较 tonalSpot 与 expressive，以正文/错误/禁用状态对比度和信息密度为决策依据。
3. 把按钮、surface、outline、focus 等 token 继续集中在 theme 文件，页面不直接散落颜色常量。
4. 若使用 typography extension，放在主题边界；预览字幕的 TextStyle(fontFamily: monospace) 作为内容特例保留。
5. 不把 Material UI 和 Flutter 原始 Material 类型混在同一个自有 widget API 中。第三方旧 Material 子树通过 MaterialUiCompatibilityBridge 隔离，避免向业务代码泄漏两套类型。

### 3.2 页面层级和排版

在不改变现有宽屏/紧凑屏断点和业务顺序的前提下，建议用以下层级重排：

1. App shell：保留单一工作流，顶部只放产品标题、当前状态/主题入口等必要信息；不要为了 Expressive 引入没有对应导航目的的 NavigationBar。
2. Search panel：作为稳定的面板 surface，视频选择、query 输入和 Search 按钮使用清晰的 primary/secondary 层级。搜索按钮用 M3EFilledButton，选择视频和取消用 M3EOutlinedButton 或 M3ETextButton；保留现有 Key、tooltip、Semantics、focus order 和快捷键。
3. Candidate panel：候选是重复、有序、可选择的数据集合，使用 M3ECardList/SliverM3ECardList；通过 itemBuilder 映射现有候选行，保留 selected color、semantic label、focus/hover 和选中状态。不要把每个候选再包一层普通 Card，避免双重表面。
4. Preview panel：外壳可用单个稳定 surface；字幕页内容继续用普通 ListView/等宽文本，保持精确页长、滚动、复制/阅读和视觉扫描。不要用 M3ECardList 把每一行字幕变成有间隙的浮动卡片。
5. Workflow actions：下载、上一页、下一页、取消沿用明确的按钮组；只有有真实异步任务时才显示 contained loading，且按钮宽度/焦点不能因 spinner 替换文字而跳动。
6. Status/empty/error：等待用 M3ELoadingIndicator，确定下载百分比才用 linear/wavy progress；无候选、错误和成功状态保持稳定布局，避免用过度装饰抢过字幕内容。

### 3.3 业务与可访问性边界

- Rust subtitle search、candidate ranking/projection、preview pagination/cache、acquisition 和 FRB adapter 不因 M3E 改动；只在 Flutter theme/widget 层替换表现。
- 保留现有候选选择、预览分页和下载事件的 Key、Semantics label、禁用状态、FocusNode、keyboard shortcut；M3E 的 semanticLabel、focus/hover/onFocusChange 只是接入点，不是删除现有无障碍契约的理由。
- 不用 dismiss gesture 代替选择，不用拖动 slider 代替分页，不用浮动 toolbar 隐藏键盘可达的动作。
- 对动画进行真实 Web/Windows 体验检查，并在系统要求减少动画时关闭非必要 morph/spring；这部分是应用级可访问性策略，不是 m3e_core 业务 API。

## 4. 限制、风险和验收门

### 4.1 平台限制

m3e_core 的官方源码 pubspec 明确声明了 Android plugin：

~~~yaml
flutter:
  plugin:
    platforms:
      android:
        package: com.android.m3e_core
        pluginClass: M3eCorePlugin
~~~

很多独立组件的 pub.dev 包页展示 Android/iOS/Linux/macOS/Web/Windows，但这与聚合包的 plugin metadata 不是同一件事。因而：

- 不能仅凭 pub.dev 的 Platforms 标签宣称 m3e_core 在 Web/Windows 的所有行为等价；
- 优先验证纯 Flutter widget 是否在目标平台正常编译和绘制；
- 任何 haptic、dynamic color、plugin channel 相关路径都要按目标平台实测，失败时提供无 haptic/固定 seed fallback；
- SSSubtitle 的发布门禁应包含真实 Chrome/Web Worker smoke 与 Windows 运行，而不是只把 Flutter Web 构建成功当作证据。

### 4.2 API 新鲜度和 breaking change

1. m3e_core 1.1.0+ 是 Material UI 迁移线，要求 Flutter 3.47+；旧线 README 还记录了从 0.1.0 起 bundled card/dismissible/expandable/dropdown 的 breaking change。
2. m3e_buttons 的早期版本包含 WidgetStateProperty 迁移和 decoration API 变化；m3e_expandable 1.0.0 也调整过 style、haptic、builder progress 和 motion API。不要照抄旧示例，优先以当前 API 页面和分析器为准。
3. m3e_typography 当前仍是 0.x；把它视为可选实验，不让它成为 SSSubtitle 首次迁移的阻塞依赖。
4. 依赖先保持聚合包单一入口；真正需要某个独立包时再添加，并在 pubspec.lock 和目标平台构建中锁定验证。

### 4.3 最小验收清单

完成实现后至少执行：

~~~powershell
flutter pub get
dart analyze
flutter test
~~~

然后在项目既定的 Chrome/Web Worker smoke 路径和 Windows 运行路径验证：

- Search、Preview、接近 Acquisition 上限时，UI 仍有事件心跳/响应，不因 M3E spring/morph 阻塞 Worker；
- 宽屏与紧凑屏的搜索→候选→预览→下载流程、键盘快捷键、focus/semantics 未回归；
- 亮色/暗色、禁用/错误/空状态、长候选标题、长字幕行无溢出且对比度足够；
- Web/Windows 没有因 Android-only plugin metadata、haptic 或 dynamic color 路径产生运行时异常；
- 只有真实确定进度才显示 determinate indicator，取消/失败不会留下持续动画或错误的 100%。

## 5. 一手资料索引

- [m3e_core pub.dev 包页](https://pub.dev/packages/m3e_core)
- [m3e_core pub.dev package metadata API](https://pub.dev/api/packages/m3e_core)
- [m3e_core API index](https://pub.dev/documentation/m3e_core/latest/m3e_core/)
- [m3e_core 官方 README/source repository](https://github.com/Mudit200408/m3e_core)
- [m3e_core 官方 pubspec.yaml](https://raw.githubusercontent.com/Mudit200408/m3e_core/refs/heads/main/pubspec.yaml)
- [m3e_core 官方 barrel lib/m3e_core.dart](https://raw.githubusercontent.com/Mudit200408/m3e_core/refs/heads/main/lib/m3e_core.dart)
- [Flutter 官方 material_ui 包页](https://pub.dev/packages/material_ui)
- [material_ui pub.dev package metadata API](https://pub.dev/api/packages/material_ui)
- [Flutter 官方 material_ui API 文档](https://pub.dev/documentation/material_ui/latest/)
- [m3e_card_list](https://pub.dev/packages/m3e_card_list) · [m3e_dismissible](https://pub.dev/packages/m3e_dismissible) · [m3e_expandable](https://pub.dev/packages/m3e_expandable)
- [m3e_dropdown_menu](https://pub.dev/packages/m3e_dropdown_menu) · [m3e_buttons](https://pub.dev/packages/m3e_buttons) · [m3e_color_scheme](https://pub.dev/packages/m3e_color_scheme)
- [m3e_progress_indicator](https://pub.dev/packages/m3e_progress_indicator) · [m3e_loading_indicator](https://pub.dev/packages/m3e_loading_indicator) · [m3e_haptics](https://pub.dev/packages/m3e_haptics)
- [m3e_floating_toolbar](https://pub.dev/packages/m3e_floating_toolbar) · [m3e_slider](https://pub.dev/packages/m3e_slider) · [m3e_seekbar](https://pub.dev/packages/m3e_seekbar)
- [flutter_m3shapes_extended](https://pub.dev/packages/flutter_m3shapes_extended) · [m3e_typography](https://pub.dev/packages/m3e_typography)
