# CCRouter Demo

CCRouter 的 Flutter 开发工程，使用 FVM `ohos/oh-3.41.9-release` SDK，包含 Android、iOS、macOS、Web 和 OHOS 平台目录。

## Android Studio

直接打开本目录：

```text
<repository-root>/demo
```

Flutter SDK 选择：

```text
<repository-root>/demo/.fvm/flutter_sdk
```

工程入口为 `lib/main.dart`。示例在 `runApp` 前显式调用
`CCRouter.initialize(hostAssembly: ...)` 和
`CCRouter.runInitTasks(gate: CCInitTaskGate.appStarted)`，再通过 `CCGoRouterApp` 的一次性
`backendFactory` 复用 Demo Shell/Outlet Backend，并自动创建 `MaterialApp.router` 与 managed
Host；业务代码不接触导航 Backend。

`modules/navigation_lab` 是可交互的路由功能实验室，覆盖 typed navigation、动态 URI、
栈操作、拦截和重定向、Failure Policy、Aspect、页面/应用生命周期、展示动画、
Managed Modal、Foreign/Overlay 隔离、ShellRoute、StatefulShellRoute、嵌套子路由和
typed Extra。完整的 macOS 验证矩阵、已修复问题和 Adapter 限制见
[路由验证记录](docs/route_validation.md)，与 Flutter 官方 GoRouter 示例的差异见
[GoRouter 示例覆盖对照](docs/go_router_example_coverage.md)。固定 seed 的 Semantic Monkey、
真实窗口 Accessibility Monkey 和小窗口回归方法见
[macOS Monkey 验证记录](docs/macos_monkey_validation.md)。

首页的“组件能力实验室”使用真实 Runtime 展示非路由能力：

- Command：typed result、`void`、timeout、caller cancellation 和 Handler error；
- Event：并发多订阅者、Subscriber 异常隔离、零订阅者和 timeout；
- InitTask：App Started DAG、required/optional 状态、失败依赖 skip 和手动 Privacy Gate；
- Service：App/Session/Route Scope、singleton/newInstance、lazy readiness single-flight、命名多实现、
  可选查找，以及 Session/Route 关闭时自动 dispose；首页还通过生成的组件专属 Proxy 验证
  跨组件同步方法、Future、getter、caller attribution 和方法级 Trace。
- 诊断：typed Subscriber ID、分类 Sink、失败隔离、采样策略和有界 Trace Bundle；首页“实时诊断”
  会展示脱敏 Sink 事件、Managed/Backend Entries 与最近一次 Trace 聚合。
- KV Storage：基本类型和 JSON Map 的类型化读写，以及全局、游客、用户、API 环境、硬件五类
  命名空间隔离。Demo 已通过 Scoped Facade 和 Host-owned Context Provider 避免业务每次手传
  user/environment/device ID，并使用内存 Backend 保证可重复测试。生产实现可替换为文件、数据库
  或 Secure Storage；命名空间不等于加密边界。真实 Session/Environment/Device Contract、游客
  迁移和持久化接入见 [KV Storage Demo 改造方案](docs/kv-storage-demo-migration.md)。

这些示例用于观察边界而不是模拟万能 EventBus：读取状态走 Service，需要唯一执行者的操作走
Command，已经发生的事实才发布 Event，一次性启动依赖使用 InitTask。

`modules/web_contracts` 和 `modules/web` 展示共享 WebView 容器：公开 allowlist URL 使用
Query Codec，认证 URL 与 Header 使用进程内 Extra；标准 HTTPS 外部链接由 Host mapper
转换后进入 CCRouter。契约、安全边界和手动验证见
[共享 WebView 容器路由](docs/web_container_routing.md)。

macOS 外部 URL Scheme、冷启动和运行中唤醒的手动验证步骤见
[外部 Deep Link 验证](docs/external_deep_link.md)。

Host 与自适应布局示例提供两个模式：双 Host 模式把两个独立 GoRouter 同时显示在一个
Flutter View 中，验证 Host 选择、路由栈和 RouteEntry 生命周期互不串扰；自适应模式
保持同一个 Host，根据手机横竖屏、桌面窗口缩放和模拟 hinge 更新
`CCHostLayoutMetrics`，并在单 `adaptive.list` Outlet 与大屏 list/detail 双 Outlet
之间切换：

```sh
fvm flutter run -d macos -t lib/examples/multi_host_demo.dart
```

该入口验证框架的多 Host、自适应布局和 Display Feature 语义，不等同于 macOS 原生多
Window；后者仍需要平台 Window 和 Flutter Engine 生命周期接入。

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

仓库不保存 OHOS 签名证书、Profile、KeyStore 路径或密码。真机安装或签名构建前，开发者应
在本机 DevEco Studio 中配置自己的签名材料，并确保这些本地值不会提交到
`ohos/build-profile.json5`。

## 组件模块与生成

新增组件统一放到 `modules/`，作为独立 Flutter 库包；平台目录由 demo 宿主持有。
当前 `modules/order_contracts` 和 `modules/web_contracts` 是不依赖 Flutter 的
Contract-first Package；
`modules/order` 只提供订单页面实现，`modules/payment` 只依赖订单契约而不依赖订单页面。
订单组件 ID 位于 owner contract，实现 Package 在
`lib/src/demo_order_component.dart` 声明唯一的顶层 `const CCComponent`；Route 与简单
Service 由生成器自动装配，没有专用声明模型的能力放入 `@CCComponentContribution`。
组件生成后端中立的页面 Catalog，宿主只导出原子的
`ccrouterGeneratedHostAssembly`，并通过其 `componentManifests` 和 `routeCatalog` 属性读取
同一代生成快照；
`CCGoRouterBackend.managed` 从 Catalog 自动创建 GoRouter routes、Adapter bindings 和
Root Observer。`CCGoRouterApp` 只绑定 Host 和 Backend，不初始化或关闭 Runtime；最终由应用
Composition Root 显式调用 `CCRouter.shutdown`。业务跳转仍统一通过 `CCRouter.navigator`。
组件 Registrar、Manifest 与 Route Catalog 由独立 `.component.g.dart` 自动生成，并聚合到
Host Assembly；组件业务 barrel 不导出 Registrar 或 Manifest。
订单详情路由由 `@CCRouteContract` 声明，页面通过 `@CCRouteImplementation` 绑定；跨组件
只导入 `demo_order_contracts`，页面 Widget、注册入口和构造 glue 留在 `demo_order`。
同一契约包还通过 `@CCServiceContract` 声明 `OrderSummaryService` 的稳定 ID；订单实现
直接 `implements` 该唯一 Contract，`@CCService()` 自动完成绑定与注册。支付与导航实验组件
分别声明 `CCServiceDependency<OrderSummaryService>`，使用各自生成的 `<Component>Services`
Client；生成 Token、method ID 和 caller ID 不进入手写消费方 API。

demo 和组件包已加入根 Dart workspace，使用本仓库内框架源码与统一锁文件，
不再需要 `pubspec_overrides.yaml` 路径覆盖。新增组件时也应加入根 `workspace` 列表，
并在组件 `pubspec.yaml` 中声明 `resolution: workspace`。

在仓库根目录生成 Demo 的全部组件路由：

```sh
fvm dart run ccrouter_generator:ccrouter generate demo
```

CI 或提交前以只读方式检查生成物是否已同步：

```sh
fvm dart run ccrouter_generator:ccrouter generate demo --check
```

聚合路由目录生成到 `demo/lib/src/ccrouter_generated/metadata/cc_routes.json` 和
`demo/lib/src/ccrouter_generated/metadata/cc_catalog.md`；宿主通过稳定的
`demo/lib/src/ccrouter_generated/ccrouter_host.api.g.dart` 只导出原子 Host Assembly，
Manifest 和 Catalog 通过 Assembly 属性读取，
该入口在内部转发 `host/ccrouter_host.routes.g.dart`。每个参与 Package 同时在
`lib/src/ccrouter_generated/metadata/ccrouter_package.json` 发布 Index；Runtime 组件通过
`lib/src/ccrouter_generated/host/<package>_ccrouter.g.dart` 的分层 Bundle 装配，纯 contracts Package 保持 Pure Dart，
只发布 Index。组件增删普通页面后重新运行
上述统一命令即可，`main.dart` 不再逐条添加组件 Manifest、`GoRoute` 或
`CCGoRouterRouteBinding`。宿主自身未注解的本地组件仍由应用显式安装。

契约声明参考 `modules/order_contracts/lib/src/order_detail_route_contract.dart`，页面绑定参考
`modules/order/lib/src/order_detail_page.dart`，生成器约束与测试命令见
[生成器说明](../packages/ccrouter_generator/README.md)。
