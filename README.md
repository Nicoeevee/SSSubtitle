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
  --web-header=Cross-Origin-Opener-Policy=same-origin `
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```

浏览器能否直接访问字幕服务取决于对方的 CORS 配置；遇到跨域错误时请参阅[开发指南](docs/development.md#web-构建与部署)。

## 使用方法

1. 选择一个视频文件。
2. 确认或修改自动生成的搜索名。
3. 选择候选字幕并在右侧分页预览。
4. 保存字幕。默认文件名沿用原视频的完整基名，仅替换扩展名，便于播放器自动索引。

完整快捷键、格式支持、隐私说明和当前功能边界见[用户指南](docs/user-guide.md)。

## 文档

- [用户指南](docs/user-guide.md)：完整操作、快捷键、格式、隐私与限制
- [开发指南](docs/development.md)：环境、代码生成、测试、Windows/Web 构建与部署
- [架构决策](docs/adr/0001-flutter-platform-shell-rust-subtitle-core.md)：Flutter 与 Rust 的职责边界
- [领域词汇](CONTEXT.md)：项目使用的核心术语
- [GitHub Issues](https://github.com/Nicoeevee/SSSubtitle/issues)：需求、缺陷与进度

