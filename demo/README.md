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
当前 `modules/order_contracts` 是不依赖 Flutter 的 Contract-first Package；
`modules/order` 只提供订单页面实现，`modules/payment` 只依赖订单契约而不依赖订单页面。
订单组件身份与 Registrar 分别通过 owner contract 和
`lib/src/demo_order_component_registrar.dart` 管理。
组件生成后端中立的页面 Catalog，宿主通过 `CCGoRouterAssembler` 一次性生成
GoRouter routes 和 Adapter bindings；业务跳转仍统一通过 `CCRouter.navigator`。
组件 Manifest 也由 Registrar 同库的 `.component.g.dart` Part 生成，并自动聚合到
`ccrouterGeneratedComponentManifests`；组件业务 barrel 不导出 Registrar 或 Manifest。
订单详情路由由 `@CCRouteContract` 声明，页面通过 `@CCRouteImplementation` 绑定；跨组件
只导入 `demo_order_contracts`，页面 Widget、注册入口和构造 glue 留在 `demo_order`。
同一契约包还声明 `OrderSummaryService` 与稳定 `CCServiceToken`；订单组件注册实现，支付
组件通过 Token 解析，Type 路径和 Token 路径共享同一个 Scope 实例。

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
`demo/ccrouter_generated/metadata/cc_routes.md`；宿主可执行的 Catalog 生成到
`demo/lib/ccrouter_generated/ccrouter_host.routes.g.dart`。组件增删普通页面后重新运行
上述命令即可，`main.dart` 不再逐条添加组件 Manifest、`GoRoute` 或
`CCGoRouterRouteBinding`。宿主自身未注解的本地组件仍由应用显式安装。

契约声明参考 `modules/order_contracts/lib/src/order_detail_route_contract.dart`，页面绑定参考
`modules/order/lib/src/order_detail_page.dart`，生成器约束与测试命令见
[生成器说明](../packages/ccrouter_generator/README.md)。
