# SSSubtitle 开发指南

## 支持与验证范围

项目面向桌面端与 Web。当前持续开发和发布验证只覆盖 Windows 与 Web；Android 与 iOS 工程和插件入口已经移除，不再运行移动端构建，也不再把 Android Gradle、Android Gradle Plugin、Kotlin 或 CocoaPods 依赖纳入升级验收。Linux 与 macOS 桌面工程壳仍保留，但当前不作为发布门禁。

如果需要修复或重新生成 Flutter 平台工程，必须显式限制平台，避免重新创建 Android 与 iOS 目录：

```powershell
flutter create --platforms=windows,linux,macos,web .
```

## 环境

- Flutter 3.47.1 / Dart 3.13.1 或兼容版本
- Rust 1.98 或兼容版本
- `flutter_rust_bridge_codegen` 2.13.0
- Web 额外需要 Rust nightly、`rust-src` 和 `wasm-pack`

FRB 的 Dart runtime、Rust runtime、codegen 与 macros 必须保持同一版本。本项目统一使用 2.13.0，并继续采用 Cargokit + `rust_builder` 集成。若迁移到 Native Assets，应按官方迁移指南完整替换构建后端，不能混用两套集成文件。

`rust_builder/cargokit` 来自 FRB 2.13 固定的 Cargokit 提交 `6f7144d192b04075acd73af2656cdebb1d3e4055`，并同步当前 Dart 构建依赖、格式以及上游测试和文档。它是项目内维护的 vendored 构建组件，不应被其他版本的 Cargokit 文件局部覆盖。

## Liquid Glass 实验记录

2026-08-26 在独立 worktree 中验证了 `liquid_glass_easy: 4.1.1` 的 presentation-layer 方案。该 worktree 的实验代码不并入 `main`；本节只保留可复用的 API、渲染和验收结论，不能视为 GitHub Issues #1–#6 已完成。

- 官方 4.1.1 API 使用 `LiquidGlassLens`、`LiquidGlassStyle` 与 `LiquidGlassView`；Skia/Web 需要祖先 `LiquidGlassView(backgroundWidget: ...)` 才能捕获背景，Impeller 不需要该 View。直接 package import 应继续限制在应用自有的 Glass wrapper/theme 边界。
- 最稳的页面结构是固定的 Mesh Gradient 作为捕获背景，完整 `Scaffold` 位于单一 Glass view 内；App Shell、固定的搜索/候选/预览面板和少量操作控件使用 Glass，TextField、候选列表项、Chip、字幕正文及高频滚动内容保留 Material 3。
- 背景可用固定的程序化 Mesh Gradient 取代图片资源，避免网络请求和图片授权风险。中文字体实验使用 Google Fonts 的 Noto Sans SC，并离线打包 Regular、Medium、SemiBold、Bold 与 OFL 许可证；生产入口关闭 runtime fetching，Windows/Web 启动不依赖 Google CDN。

### 实验门禁与截图

- Flutter 3.47.1、Dart 3.13.1、`flutter_rust_bridge` 2.13.0 环境下，`flutter build windows --release`、`flutter_rust_bridge_codegen build-web --release` 与 `flutter build web --release` 均退出码为 0。Web 产物为 `dart2js + CanvasKit`；Wasm dry-run 仅报告 hosted FRB 依赖的 `invalid_runtime_check_with_js_interop_types` 非阻塞警告。
- 使用带 `Cross-Origin-Opener-Policy: same-origin` 与 `Cross-Origin-Embedder-Policy: require-corp` 的本地 release server，并通过 Chrome DevTools Protocol 等待首帧后截取了实际页面：[CanvasKit Web Glass 验收截图](validation/liquid-glass-web-2026-08-26.png)。截图显示 Mesh Gradient、半透明 Glass 面板/操作组和中文文本均已渲染，初始搜索、候选空态和预览空态布局没有溢出。
- Windows 调试日志记录 `Using the Impeller rendering backend (OpenGLESSDF)`，但当前环境无法取得可靠的桌面窗口像素截图；因此该记录不能替代真实 Windows 前台窗口的 Light/Dark、缩放和交互截图。
- 尚未用真实浏览器完成 Light/Dark、缩放、长列表/正文滚动、搜索/保存 loading、键盘全流程和掉帧测量；这些仍是后续 Issue 验收项。Widget test、Web build 或 `flutter_tester` 不能代替这些运行时证据。

## 架构与生成代码

Flutter 负责 Material 3 界面、键盘与无障碍交互、系统文件选择，以及平台保存或浏览器下载；Rust 负责搜索名规范化、CID 范围计划、提供方协议、候选归一化与排序、下载校验、编码检测和预览分页。

详细职责边界见[架构决策](adr/0001-flutter-platform-shell-rust-subtitle-core.md)。

`lib/src/rust/` 与 `rust/src/frb_generated.rs` 是生成代码，不应手工编辑。Flutter Widget 和 Controller 只依赖 `SubtitleCore`，生成类型集中在 `RustSubtitleCore` 适配器中。

Rust API 变化后重新生成桥接代码：

```powershell
flutter_rust_bridge_codegen generate
```

## 本地开发

```powershell
flutter pub get
flutter_rust_bridge_codegen generate
flutter run -d windows
```

常用质量门：

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test

Set-Location rust
cargo fmt --all -- --check
cargo test
cargo clippy --all-targets -- -D warnings
```

## Windows 构建

```powershell
flutter build windows --release
```

## Web 构建与部署

FRB Web 构建分为 Rust WASM 与 Flutter Web 两步：

```powershell
flutter_rust_bridge_codegen build-web --release
flutter build web --release
```

开发服务器和生产服务器必须发送以下跨源隔离响应头：

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

本地运行示例：

```powershell
flutter run -d chrome `
  --web-header=Cross-Origin-Opener-Policy=same-origin `
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```

即使应用构建成功，字幕服务仍可能拒绝浏览器跨域请求。生产环境如需中继，应仅代理明确白名单中的服务方域名，不能开放任意 URL 转发。

参考资料：

- [flutter_rust_bridge 2.13.0](https://pub.dev/packages/flutter_rust_bridge/versions/2.13.0)
- [FRB Web 跨源说明](https://cjycode.com/flutter_rust_bridge/manual/miscellaneous/web-cross-origin)
- [FRB WASM 限制](https://cjycode.com/flutter_rust_bridge/manual/miscellaneous/wasm-limitations)
