# CCRouter Demo

CCRouter 的 Flutter 开发工程，使用 FVM `ohos/oh-3.41.9-release` SDK，包含 Android、iOS、macOS、Web 和 OHOS 平台目录。

## Android Studio

直接打开本目录：

```text
/Users/shingo/develop/LiberLive/cc-router/demo
```

Flutter SDK 选择：

```text
/Users/shingo/develop/LiberLive/cc-router/demo/.fvm/flutter_sdk
```

工程入口为 `lib/main.dart`。示例通过 `CCRouter.initialize(components: ...)` 让门面创建并持有 Runtime，通过 `CCRouter.shutdown()` 统一销毁；应用本身不直接管理 Runtime。登录会话使用带 `accountId` 的 Session，示例同时展示组件 Manifest 和 Command 调用。

## 开发命令

```sh
fvm flutter pub get
fvm flutter analyze
fvm flutter test
fvm flutter run
```

OHOS 原生模块位于 `ohos/`。在该目录中可使用：

```sh
devecocli build
```

本地联调通过 `pubspec_overrides.yaml` 将 `ccrouter`、`ccrouter_core` 和 `ccrouter_contracts` 全部指向仓库内源码，避免混用 Hosted 包。
