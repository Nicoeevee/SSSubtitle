# SSSubtitle

SSSubtitle 是一款使用 Flutter 与 Rust 构建的字幕搜索、预览和下载工具，面向桌面端与 Web；当前持续开发和验证 Windows 与 Web。

> [!IMPORTANT]
> 当前字幕来源使用未公开、无稳定性保证的第三方接口。搜索名会通过 HTTPS 发送给字幕提供方，但视频内容不会上传。

## 快速开始

准备 [Flutter 3.47.1](https://docs.flutter.dev/get-started/install/windows/desktop) 或兼容版本，以及 [Rust 1.98](https://www.rust-lang.org/tools/install) 或兼容版本。

### Windows

```powershell
git clone https://github.com/Nicoeevee/SSSubtitle.git
Set-Location SSSubtitle
flutter pub get
flutter run -d windows
```

### Web

Web 还需要 Rust nightly、`rust-src`、`wasm-pack` 和 `flutter_rust_bridge_codegen` 2.13.0。完成环境配置后运行：

```powershell
flutter pub get
flutter_rust_bridge_codegen build-web --release
flutter run -d chrome `
  --cross-origin-isolation
```

`--cross-origin-isolation` 是 Web 版 FRB Worker 的必需启动参数；其他部署方式的响应头配置见[开发指南](docs/development.md#web-构建与部署)。

浏览器能否直接访问字幕服务取决于对方的 CORS 配置；遇到跨域错误时请参阅[开发指南](docs/development.md#web-构建与部署)。

## 使用方法

1. 选择一个视频文件。
2. 确认或修改自动生成的搜索名。
3. 选择候选字幕，并在候选/预览区域分页预览。
4. 保存字幕。默认文件名沿用原视频的完整基名，仅替换扩展名，便于播放器自动索引。

完整快捷键、格式支持、隐私说明和当前功能边界见[用户指南](docs/user-guide.md)。

## 文档

- [用户指南](docs/user-guide.md)：完整操作、快捷键、格式、隐私与限制
- [开发指南](docs/development.md)：环境、代码生成、测试、Windows/Web 构建与部署
- [UI/UX Pro Max 设计系统](design-system/sssubtitle/MASTER.md)：Material 3 桌面字幕工具的颜色、字体、间距和交互规则
- [m3e_core 研究笔记](docs/agents/m3e-core-research.md)：Material 3 Expressive API 选型、集成边界与跨平台验收
- [架构决策](docs/adr/0001-flutter-platform-shell-rust-subtitle-core.md)：Flutter 与 Rust 的职责边界
- [Liquid Glass 任务计划](docs/agents/liquid-glass-easy-plan.md)：`liquid_glass_easy` 的分阶段迁移任务与验收边界
- [ADR-0003：Liquid Glass presentation layer](docs/adr/0003-liquid-glass-presentation-layer.md)：Glass 包装边界、Material 保留范围与实验验收记录
- [领域词汇](CONTEXT.md)：项目使用的核心术语
- [GitHub Issues](https://github.com/Nicoeevee/SSSubtitle/issues)：需求、缺陷与进度
