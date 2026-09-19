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

## 组件模块与生成

新增组件统一放到 `modules/`，作为独立 Flutter 库包；平台目录由 demo 宿主持有。
当前 `modules/order` 展示页面注解、生成契约、组件注册和类型安全页面返回；组件身份与
Registrar 分别位于 `lib/src/demo_order_component.dart` 和
`lib/src/demo_order_component_registrar.dart`。
宿主负责 GoRouter 绑定，业务跳转仍统一通过 `CCRouter.navigator`。

demo 和组件包已加入根 Dart workspace，使用本仓库内框架源码与统一锁文件，
不再需要 `pubspec_overrides.yaml` 路径覆盖。新增组件时也应加入根 `workspace` 列表，
并在组件 `pubspec.yaml` 中声明 `resolution: workspace`。

在仓库根目录生成 Demo 的全部组件路由：

```sh
fvm dart run build_runner build --workspace
fvm dart run ccrouter_generator:ccrouter_generator demo \
  --generate-component-registrars
```

聚合路由目录生成到 `demo/ccrouter_generated/metadata/cc_routes.json` 和
`demo/ccrouter_generated/metadata/cc_routes.md`。

路由声明参考 `modules/order/lib/src/order_detail_page.dart`，生成器约束与测试命令见
[生成器说明](../packages/ccrouter_generator/README.md)。
