# SSSubtitle

SSSubtitle 是一个以 Flutter 构建跨平台界面、以 Rust 处理字幕业务的字幕搜索、预览与下载应用。当前 MVP 使用迅雷字幕接口，支持 Windows、macOS、Linux、Android、iOS 与 Web 的统一工程结构。

> 迅雷字幕接口未公开文档，也没有稳定性保证。搜索名称会作为 HTTPS GET 查询参数发送给迅雷；视频内容不会上传。Web 是否能直接搜索和下载还取决于迅雷与字幕 CDN 的 CORS 响应头。

## 当前能力

- 通过系统文件选择器选择视频，并按 v9 规则生成可编辑搜索名：去掉最后一个扩展名；若名称包含 `@`，取最后一个 `@` 后的非空部分。
- 调用真实迅雷字幕搜索接口；Flutter 不接触供应商 URL 或原始 JSON。
- Rust 统一执行候选归一化与排序，展示语言、格式、上游评分和匹配理由。
- 首次预览时按需下载字幕并在内存缓存；每页显示 30 行。
- 支持 UTF-8、UTF-8 BOM、UTF-16LE、UTF-16BE 与 GBK/CP936 回退。
- 支持 SRT、ASS、SSA、VTT，并拒绝 HTML、JSON、空内容、过短内容和超过 20 MiB 的响应。
- `↑/↓` 切换候选，`←/→` 预览翻页，`Home/End` 跳到首尾，`PageUp/PageDown` 快速移动，`Enter` 保存，`Esc` 取消。
- 打开平台保存对话框，由用户选择字幕保存位置。建议文件名沿用原视频的完整基名，仅替换扩展名；保存到视频同一目录后，播放器可按同名规则自动索引。
- Rust 已实现迅雷 CID 的高性能范围计划：大文件只需读取三个 `0x5000` 字节区段，总计约 60 KiB；小文件读取全部内容。

## 当前边界

- 文件选择器目前只把视频名称交给工作流；视频范围读取、CID 计算和可选时长尚未接入 UI，因此当前排序主要使用名称、语言、格式及迅雷评分。Rust 的 CID 算法和严格输入校验已有测试覆盖，可作为下一步接线基础。
- 不计算 GCID。旧 PowerShell 工具也只显示服务端候选的 GCID，没有经过验证的本地 GCID 算法。
- Web 的 `reqwest`/Fetch 路径无法设置浏览器禁止的 User-Agent 与 Referer，也不能观察每个中间重定向；它会校验最终 HTTPS URL、域名和响应大小，但没有原生端的 15/30 秒请求超时。完整 Web 功能需要实际 CORS 验证，必要时使用自有、域名白名单的中继服务。
- 当前没有批量扫描、目录监视、字幕编辑、翻译、同步或嵌入字幕提取。

## 架构

```text
Flutter
  ├─ Material 3 响应式界面、键盘与无障碍交互
  ├─ 系统文件选择
  └─ 系统保存/浏览器下载
          │
          │ flutter_rust_bridge 2.12.0
          ▼
Rust
  ├─ 搜索名规范化与 CID 范围计划
  ├─ 迅雷协议、URL 注册表与网络安全限制
  ├─ 候选归一化、评分与稳定排序
  └─ 下载校验、编码检测和预览分页
```

`lib/src/rust/` 与 `rust/src/frb_generated.rs` 是生成代码，不应手工编辑。Flutter Widget 和 Controller 只依赖 `SubtitleCore`；生成类型集中在 `RustSubtitleCore` 适配器中。详细决策见 [`docs/adr/0001-flutter-platform-shell-rust-subtitle-core.md`](docs/adr/0001-flutter-platform-shell-rust-subtitle-core.md)。

## 环境

- Flutter 3.47.1 / Dart 3.13.1 或兼容版本
- Rust 1.96 或兼容版本
- `flutter_rust_bridge_codegen` 2.12.0
- Web 构建还需要 Rust nightly、`rust-src`、`wasm32-unknown-unknown` 和 `wasm-pack`

FRB 的 Dart runtime、Rust runtime、codegen 与 macros 必须保持同一版本。本项目将 Dart 与 Rust 依赖固定为 `2.12.0`，使用该版本的 Cargokit + `rust_builder` 集成；不要混用 2.13 的 Native Assets 初始化说明。

## 开发

```powershell
flutter pub get
flutter_rust_bridge_codegen generate
flutter run -d windows
```

Rust API 变化后重新生成桥接：

```powershell
flutter_rust_bridge_codegen generate
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

## 构建

原生平台使用普通 Flutter 命令；实际构建目标仍受宿主机工具链限制，例如 iOS/macOS 需要 macOS 与 Xcode。

```powershell
flutter build windows
flutter build apk
flutter build linux
flutter build macos
flutter build ios
```

FRB 2.12 的 Web 需要先构建 Rust WASM：

```powershell
flutter_rust_bridge_codegen build-web --release
flutter build web --release
```

开发服务器和生产服务器必须发送跨源隔离响应头：

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

参考：[flutter_rust_bridge 2.12.0](https://pub.dev/packages/flutter_rust_bridge/versions/2.12.0)、[FRB Web 跨源说明](https://cjycode.com/flutter_rust_bridge/manual/miscellaneous/web-cross-origin)、[FRB WASM 限制](https://cjycode.com/flutter_rust_bridge/manual/miscellaneous/wasm-limitations)。

## 安全与隐私

- 搜索请求只发送用户确认后的搜索名称；本地 CID 与视频时长不会发送给迅雷。
- 搜索名作为 HTTPS GET 查询参数传输，可能出现在提供方、代理或浏览器的网络诊断记录中。应用自身不记录搜索名；对此有严格要求时，请在搜索前改用不含敏感信息的别名。
- 下载 URL 保存在 Rust 进程内的有界注册表中，只以不透明候选 ID 跨越 FRB。
- 字幕保存名只沿用用户已选择的原视频文件基名，不使用第三方候选名；保存完成提示不显示本地绝对路径，保存后会从 Flutter 内存缓存中移除已下载字节。
- 原生下载只允许 HTTPS 标准端口以及 `xunlei.com`、`geilijiasu.com` 的真实 DNS 后缀，并逐跳限制最多 5 次重定向。
- 搜索响应上限 2 MiB；字幕按流读取并在超过 20 MiB 时立即中止。
- SHA-1 CID 只用于兼容迅雷内容标识，绝不能当作安全完整性证明。

## 项目约定

- 项目事项与规格保存在 [`Nicoeevee/SSSubtitle` GitHub Issues](https://github.com/Nicoeevee/SSSubtitle/issues)，规则见 [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md)。
- 领域词汇见 [`CONTEXT.md`](CONTEXT.md)。
- 项目级代理约定见 [`AGENTS.md`](AGENTS.md)。
