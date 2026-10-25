# CCRouter Demo

框架接入与能力边界统一查阅[现行规范索引](../docs/README.md)；路由、Shell、Outlet 和混合导航见[Managed 路由规范](../docs/CCRouter-route-design.md)，系统返回及平台手势见[返回协调规范](../docs/CCRouter-predictive-back.md)。本页维护 Demo 场景与操作，不复制框架规则。

产品埋点已归应用侧：[`demo_analytics`](modules/analytics/README.md)、
[`demo_analytics_flutter`](modules/analytics_flutter/README.md) 和
[`demo_analytics_firebase`](modules/analytics_firebase/README.md) 都是 Demo library，
不属于框架依赖或发布能力。公开类型使用 `AppAnalytics…` / `AppNavigationAnalyticsBridge`；
CCRouter 仅提供导航生命周期观察，PV/停留/滚动/曝光规则由应用决定。

CCRouter 的 Flutter 开发工程，使用 FVM `ohos/oh-3.41.9-release` SDK，包含 Android、iOS、macOS、Web 和 OHOS 平台目录。

Demo 图标采用 CCRouter 双 C + 路由箭头设计；SVG 母版、平台导出命令及尺寸规范见
[品牌资源说明](../docs/brand/ccrouter-icon-v1/README.md)。

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
`CCRouterHost.initialize(hostAssembly: ...)` 和
`CCRouterHost.runInitTasks(gate: CCInitTaskGate.appStarted)`，再通过 `CCManagedRouterApp` 的一次性
`backendFactory` 复用 Demo Shell/Outlet Backend，并自动创建 `MaterialApp.router` 与 Managed
Host；业务代码不接触导航 Backend。

原生 Managed Shell 装配集中在 `lib/demo_managed_router_backend.dart`，旧 GoRouter 装配与入口已移除。
Shell 树、相对路径、分支顺序和切换策略仍显式配置；自适应面板使用原生 `CCManagedOutlet`，
本地列表/详情由 `baseBuilder` 提供，不额外创建手写 Navigator。Stateful Shell 首次进入空分支时创建根页，返回已访问分支时只激活 Outlet，
因此保留分支 Stack 与 Widget State；重选当前分支才重置到根页。这些是 Host 装配策略，
业务页面不读取 Managed Stack。

`modules/navigation_lab` 是可交互的路由功能实验室，覆盖 typed navigation、动态 URI、
栈操作、拦截和重定向、Failure Policy、Aspect、页面/应用生命周期、展示动画、
Managed Modal、Foreign/Overlay 隔离、ShellRoute、StatefulShellRoute、嵌套子路由和
typed Extra。完整的 macOS 验证矩阵、已修复问题和 Adapter 限制见
[路由验证记录](docs/route_validation.md)和[统一验证索引](../docs/validation/README.md)，与 Flutter 官方 GoRouter 示例的历史差异见
[GoRouter 示例覆盖对照](docs/go_router_example_coverage.md)（不是当前 Backend 接入规范）。固定 seed 的 Semantic Monkey、
真实窗口 Accessibility Monkey 和小窗口回归方法见
[macOS Monkey 验证记录](docs/macos_monkey_validation.md)。

Demo 全部使用原生 Managed Backend，包括默认入口、多 Host、自适应 Pane 和预测返回。
`test/demo_router_backend_test.dart` 检查接入与展示；
`test/managed_demo_feature_matrix_test.dart` 和 `test/managed_parity_regression_test.dart`
保留迁移期的行为断言，直接验证原生路径。历史 GoRouter 对照报告保留为证据，
不再提供可运行的兼容入口。

`lib/multi_host_demo.dart` 的“Host 生命周期”由 Host 层管理辅助 Backend：点击“发起延迟
导航”→“关闭并重开 Host”，旧请求应显示 `host_detached`；点击“新实例导航”应立即成功，
再“放行旧决策”不应改变当前页面。样例释放旧 Backend、卸载旧 `CCRouterApp` 后再挂载
相同逻辑 ID 的新实例，组件不接触 Host 注册。自动化见 `test/host_lifecycle_lab_test.dart`。

首页“展示”→“类型化 UI Fragment”（`/ui-fragments`）使用真实生成 Host：
`navigation_lab` 只依赖 `order_contracts`，订单组件提供摘要、推荐和动作面板三个 Renderer。
可验证两个摘要实例备注独立、切换 Tab 保留备注、更新 Props 保持 State、模拟账号 Key
重建、推荐加载错误与重试。Fake 请求归 B 的 State 所有，卸载时取消并释放 controller。
入口和边界见[UI Fragment 接入指导](../skills/ccrouter-integration-development/references/ui-fragments.md)，
自动化验证见 [UI Fragment Demo 测试](test/ui_fragment_demo_test.dart)。
推荐列表 Tab 中的 `order.panel` 还演示 sealed Action：无载荷设置请求与四类嵌套目标，
使用基类 final id、const super 转发及 part 声明，消费方分别做穷尽 switch。旧 enum/DTO
示例继续保留作为兼容对照。见 [sealed Action 测试](test/ui_action_union_demo_test.dart)。

首页的“组件能力实验室”使用真实 Runtime 展示非路由能力：

- Command：typed result、`void`、timeout、caller cancellation 和 Handler error；
- Event：并发多订阅者、Subscriber 异常隔离、零订阅者和 timeout；
- InitTask：App Started DAG、required/optional 状态、失败依赖 skip 和手动 Privacy Gate；
- Service：App/Session/Route Scope、singleton/newInstance、lazy readiness single-flight、命名多实现、
  可选查找，以及 Session/Route 关闭时自动 dispose；首页还通过生成的组件专属 Proxy 验证
  跨组件同步方法、Future、getter、caller attribution 和方法级 Trace。
- 诊断：typed Subscriber ID、分类 Sink、失败隔离、采样策略和有界 Trace Bundle；首页“实时诊断”
  会展示脱敏 Sink 事件、Managed/Backend Entries 与最近一次 Trace 聚合；失败日志保留
  Host/Outlet、reason、attempt 和 recoveryDepth。打开只读 DevTools 的 Overview 可核对历史
  retained/capacity/omitted 和 Sink delivery health；在其他窗口触发非导航能力后可观察自动刷新。
- KV Storage：基本类型和 JSON Map 的类型化读写，以及全局、游客、用户、API 环境、硬件五类
  命名空间隔离。Demo 已通过 Scoped Facade 和 Host-owned Context Provider 避免业务每次手传
  user/environment/device ID，并使用内存 Backend 保证可重复测试。生产实现可替换为文件、数据库
  或 Secure Storage；命名空间不等于加密边界。真实 Session/Environment/Device Contract、游客
  迁移和持久化接入见 [KV Storage Demo 改造方案](docs/kv-storage-demo-migration.md)。
- Network：`modules/network` 提供后端中立请求、授权/日志拦截、动态 Header 和 API 环境，
  默认 Backend 使用 Dio，仍属于 Demo/应用层。注册的 `DemoNetworkServiceImpl` 实现
  `CCDisposable`，App Scope 关闭时等待 Client → Dio 释放，清除 Token/日志并忽略晚到日志。
  业务不手动 dispose；测试用 `withBackend` 注入可观察 Fake，见
  [Network 生命周期回归](test/network_lifecycle_test.dart)。

这些示例用于观察边界而不是模拟万能 EventBus：读取状态走 Service，需要唯一执行者的操作走
Command，已经发生的事实才发布 Event，一次性启动依赖使用 InitTask。

`modules/web_contracts` 和 `modules/web` 展示共享 WebView 容器：公开 allowlist URL 使用
Query Codec，认证 URL 与 Header 使用进程内 Extra；标准 HTTPS 外部链接由 Host mapper
转换后进入 CCRouter。契约、安全边界和手动验证见
[共享 WebView 容器路由](docs/web_container_routing.md)。

macOS 外部 URL Scheme、冷启动和运行中唤醒的手动验证步骤见
[外部 Deep Link 验证](docs/external_deep_link.md)。

Host 与自适应布局示例已使用原生 `CCManagedMultiHostBackend`：双 Host 模式把两个独立
Managed Stack 与 RouterConfig 同时显示在一个
Flutter View 中，验证 Host 选择、路由栈和 RouteEntry 生命周期互不串扰；自适应模式
保持同一个 Host，根据手机横竖屏、桌面窗口缩放和模拟 hinge 更新
应用自己的 `DemoHostLayoutMetrics` / `DemoAdaptiveLayoutPolicy`，再调用 Host SPI
`setActiveOutlets`，在单 `adaptive.list` Outlet 与大屏 list/detail 双 Outlet 之间切换。
600/840 断点和 hinge 策略不进入 CCRouter；`demo/lib/restoration_demand.dart` 是独立的
可选恢复需求采集示例，未接入真实平台源，也不代表实现了导航状态恢复：

详情中的“在此 Outlet 打开栈页”实际 push Managed 页面；返回后保留本地选中项。
导航实验室还提供 Regex alias、内部链接外部拒绝、Pending 取消、覆盖页下的 identity close、
Revalidation keep/close/replace/reset，以及 Workspace 详情跨 Shell push 后返回的入口。
较早逐项矩阵见 [2026-10-22 全量能力审查](../docs/validation/managed_full_review_20261022.md)。
后续[Host 事件身份修复与 macOS 实窗复验](../docs/validation/20261023-host-event-identity-fixes/report.md)
覆盖多轮重开、旧请求放行、双 Host 与自适应操作；[2026-10-24 源码回归](../docs/validation/20261024-backend-wait-fixes/report.md)
覆盖最新等待/所有权修复。各日期和范围独立，统一入口为[验证索引](../docs/validation/README.md)。

```sh
fvm flutter run -d macos -t lib/multi_host_demo.dart
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

### Android 预测返回 A/B 验证

默认 `lib/main.dart` 使用 Managed 且保持 `enablePredictiveBack=false`。开启入口分别为：

```sh
# 原生 Managed Backend
fvm flutter run -t lib/main_predictive_back.dart
# Managed 旧入口别名
fvm flutter run -t lib/main_managed_predictive_back.dart
fvm flutter test test/predictive_back_demo_test.dart
```

两个入口共享页面、场景和诊断语义，但必须分别完成平台手势验收；一个入口通过不能代替另一个。

从“导航 → Push + typed result”开始左/右边缘手势：取消应保留详情且不新增正式离页；
提交应只返回一层。开启版本在诊断事件中显示 `Predictive back · started/cancelled/committed`，
不逐帧记录 update。关闭版本仍可能有 Flutter 自带预测动画，但不产生这些 CCRouter 阶段事件。
自动桥未接管 start 时，Host 可从 `backend.adapter.predictiveBackFallbacks` 查看有界、脱敏的
稳定原因；关闭版本该列表始终为空。
“策略 → PopGuard 未保存表单”保留非交互拒绝，保存后再返回；“Shell / StatefulShell”详情
验证嵌套 Outlet，手势中切换分支后旧提交不能退出新分支。自建 Shell Page 已显式传入 Host handler。
每次切换 Backend 或开关都重新启动 Demo，不在进行中的手势里切换配置。
Demo widget 回归还覆盖 Shell / StatefulShell 详情上的根弹窗：先弹出时返回只关闭弹窗，
手势中弹出时取消旧预览，弹窗先关闭也不能恢复旧提交；后续独立手势仍正常。
“展示 → 类型化 UI Fragment”还覆盖组合回归：取消保留输入内容与页面，提交后退出一层并卸载
Fragment；对应 Widget 测试使用真实生成 Host，不代表已完成该场景的真机动画验收。

Managed 的三星 Android 16 预测返回与 iPhone 13 侧滑真机结果见
[2026-10-22 平台验收](../docs/validation/managed_navigation_platform_acceptance_20261022.md)。
[2026-10-15 三星记录](../docs/validation/android_predictive_back_samsung_20261015.md)保留旧 Backend
的历史冒烟；不能当作当前 Managed 复验。之后的 Widget 回归不自动更新这些真机结论。

自动化测试覆盖上述场景；Demo Manifest 已在 `<application>` 显式设置
`android:enableOnBackInvokedCallback="true"`。系统派发、最终 Manifest 合并结果、IME、
WebView/原生 Activity 和返回桌面仍须在目标设备验证。入口不修改 targetSdk 或系统手势设置。

OHOS 原生模块位于 `ohos/`。在该目录中可使用：

```sh
devecocli build
```

根 `ohos/hvigorfile.ts` 在 Flutter `FlutterTask` 前注册 CCRouter preflight。它使用
`ohos/local.properties` 中 Flutter SDK 自带的 Dart 执行与 `flutter build` wrapper 相同的
Host generation：没有 watch 时执行 one-shot；已有 active watch 时等待并复用当前精确 cycle，
不会启动第二个 writer。只有生成或校验失败才阻止 HAP 编译。紧急恢复或 A/B 可对单次构建设置
`CCROUTER_DISABLE_HVIGOR_PREFLIGHT=1`；绕过后需自行先运行 Host generation check。

仓库不保存 OHOS 签名证书、Profile、KeyStore 路径或密码。真机安装或签名构建前，开发者应
在本机 DevEco Studio 中配置自己的签名材料，并确保这些本地值不会提交到
`ohos/build-profile.json5`。

## 独立字体内存诊断

`tool/native_font_probe.dart` 是不初始化 CCRouter 的纯 Flutter 对照入口，不属于普通
Demo 功能或路由 API。它先等待 15 秒，再以 400ms 间隔重复渲染 72 种固定字体组合三轮，
结束后停留观察。用于区分系统字体/引擎分配与导航资源；不能据此证明框架没有泄漏。

```sh
# 在 demo/ 执行；该产物会替换通常的 app-profile.apk，先另存需要保留的原 APK。
fvm flutter build apk --profile --no-pub --target-platform android-arm64 -t tool/native_font_probe.dart
```

同进程的采样、内存压力与还原记录见[Native 分配归因](../docs/validation/20261024-native-attribution/report.md)。
回到普通 Demo 时重新选择 `lib/main.dart` 构建/运行。

## 组件模块与生成

新增组件统一放到 `modules/`，作为独立 Flutter 库包；平台目录由 demo 宿主持有。
当前 `modules/order_contracts` 和 `modules/web_contracts` 是不依赖 Flutter 的
Contract-first Package；
`modules/order` 只提供订单页面实现，`modules/payment` 只依赖订单契约而不依赖订单页面。
订单组件 ID 位于 owner contract，实现 Package 在
`lib/src/demo_order_component.dart` 声明唯一的顶层 `const CCComponent`；Route 与简单
Service 由生成器自动装配，没有专用声明模型的能力放入 `@CCComponentContribution`。
组件生成后端中立的页面 Catalog，宿主只导出原子的
`ccrouterGeneratedHostAssembly`；`CCRouterHost.initialize` 安装该快照后，默认 managed Host
通过 Host-only Binding 自动读取同一份 Catalog；
`CCManagedRouterApp` 从 Catalog 创建原生 Managed Backend；它只绑定 Host 和 Backend，
不初始化或关闭 Runtime。最终由应用
Composition Root 显式调用 `CCRouterHost.shutdown`。业务跳转仍统一通过 `CCRouter.navigator`。
组件 Registrar、Manifest 与 Route Catalog 由独立 `.component.g.dart` 自动生成，并聚合到
Host Assembly；组件业务 barrel 不导出 Registrar 或 Manifest。
订单详情路由由 `@CCRouteContract` 声明，页面通过 `@CCRouteImplementation` 绑定；跨组件
只导入 `demo_order_contracts`，页面 Widget、注册入口和构造 glue 留在 `demo_order`。
order/web 的 Owner barrel 复用业务 barrel，仅额外导出 Implementation 绑定所需的 Contract
标记。业务 barrel 仍使用明确 `show` 列表维护公开边界；Catalog 的公开入口索引保留这层
明确声明的业务入口，Owner barrel 不作为推荐业务导入路径。
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
Manifest 和 Catalog 保持在同一个 Assembly 快照中，
该入口在内部转发 `host/ccrouter_host.routes.g.dart`。每个参与 Package 同时在
`lib/src/ccrouter_generated/metadata/ccrouter_package.json` 发布 Index；Runtime 组件通过
`lib/src/ccrouter_generated/host/<package>_ccrouter.g.dart` 的分层 Bundle 装配，纯 contracts Package 保持 Pure Dart，
只发布 Index。组件增删普通页面后重新运行
上述统一命令即可，`main.dart` 不再逐条维护页面或 Adapter binding。宿主自身未注解的本地组件仍由应用显式安装。

契约声明参考 `modules/order_contracts/lib/src/order_detail_route_contract.dart`，页面绑定参考
`modules/order/lib/src/order_detail_page.dart`，生成器约束与测试命令见
[生成器说明](../packages/ccrouter_generator/README.md)。


初始化、关闭和 Gate 执行通过 Host-only 的 `CCRouterHost`，组件只导入业务入口。
能力实验页通过 `DemoInitializationActions` 提出隐私／超时场景请求，
`lib/demo_initialization.dart` 在单 Host 和多 Host 树中安装回调并选择 Gate。
组件不持有通用 Gate 执行器，也不控制默认 Runtime 生命周期。
