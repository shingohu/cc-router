# CCRouter

CCRouter 是一个面向 Flutter 大型应用的组件化运行时与类型安全路由框架。它把组件装配、路由契约、导航策略、生命周期、跨组件能力调用和诊断统一到稳定的 Core Contract，同时允许 Host 选择 GoRouter 或后续其他导航后端。

当前版本为 `0.1.0`，适合在本仓库 Workspace、Demo 和受控业务试点中验证。所有 Package 目前均为 `publish_to: none`，尚未发布到 pub.dev 或私有 Hosted；接入外部工程前需要先完成正式发布，或使用受控 Git 依赖。不要把本仓库的 Workspace 依赖写法直接复制到另一个仓库。

## 为什么使用 CCRouter

- **组件边界明确**：组件只通过 Manifest、Route Contract、Service Contract、Command 和 Event 协作，不依赖其他组件页面实现。
- **导航类型安全**：生成的 Intent 编译期约束参数与返回值，避免散落的字符串 Path 和 `Map<String, dynamic>`。
- **后端可替换**：业务只调用 `CCRouter.navigator`；GoRouter 由独立 Adapter Package 接入。
- **生命周期可控**：Runtime、Session、Route Entry、Service 与 Adapter 均有明确 Owner 和销毁顺序。
- **策略与观察分离**：Interceptor/PopGuard 负责决策，Aspect、Lifecycle 与诊断事件负责观察。
- **生成优先**：路由注册、Package Index、Host Catalog 和文档由统一命令生成，不使用运行时反射。
- **混合导航安全**：Foreign Route、Dialog、Popup、Overlay 不应误删 CCRouter 管理的 Route Scope。
- **可测试、可诊断**：Pure Dart Runtime 测试、Flutter Host 测试、有界 Trace 和稳定错误类型均有独立入口。

## Package 结构

| Package | 用途 | 业务是否直接依赖 |
| --- | --- | --- |
| `ccrouter_contracts` | Pure Dart Route、Service、Command、Event、错误与导航契约 | 仅独立 contracts Package |
| `ccrouter_core` | Runtime、Registry、Scope、调度和诊断实现 | 否 |
| `ccrouter` | Flutter 业务门面、`CCRouterApp`、页面生命周期 | 是 |
| `ccrouter_go_router` | 默认 GoRouter Backend、Assembler、Observer 与 Shell 接入 | 仅 Host |
| `ccrouter_generator` | 注解处理、Host 聚合、校验、查找与清理 CLI | 仅 dev dependency |
| `ccrouter_test` | 面向集成者的测试 Host、Fake 与测试辅助能力 | 仅 test/dev dependency |
| `demo` | Android、iOS、macOS、Web、OHOS 平台 Host 和完整能力示例 | 示例 |
| `demo/modules/*` | 示例组件与独立 contracts Package | 示例 |

业务与组件默认只导入：

```dart
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
```

只有应用 Composition Root 可以导入 `ccrouter_go_router` 和 `package:ccrouter/ccrouter_host.dart`。业务代码不得导入 `ccrouter_core/src/*`、Adapter 或 Host SPI。

## 当前能力

| 能力 | 状态 | 说明 |
| --- | --- | --- |
| 启动期组件装配 | 已支持 | 依赖排序、重复 ID、缺失依赖和循环依赖校验 |
| 注解路由与类型安全 Intent | 已支持 | Path、URI、custom scheme、Regex、多 Pattern、Query、Extra、typed result |
| 页面展示 | 已支持 | 平台默认、Material、Cupertino、fade、scale、bottom-up、透明全屏 |
| Modal Route | 已支持 | Dialog、modal bottom sheet，可选择是否纳入 CCRouter 契约与生命周期 |
| 导航操作 | 已支持 | `push`、`replace`、`go`、`reset`、`open`、`pop`、`maybePop`、`canPop` |
| GoRouter Backend | 已支持 | 新工程 managed 模式和已有 GoRouter attach 模式 |
| Shell / StatefulShell / Outlet | 已支持 | 显式 Host 装配，支持多 Outlet 与调用级 Context 定位 |
| Deep Link | 已支持 | Platform、Notification、QR 入口，Host allowlist 与 Route policy 双重校验 |
| Interceptor / Redirect / Defer | 已支持 | 全局与路由级策略、超时、取消、Pending 恢复 |
| PopGuard | 已支持 | 业务 Pop、系统返回、Cupertino 手势和预测返回进入统一判断 |
| Aspect / Trace / Telemetry | 已支持 | 有界、脱敏、观察异常隔离 |
| 页面生命周期 | 已支持 | `PageShow/PageHide` 与前后台，Mixin 和 Listener 两种形式 |
| Service | 已支持 | App/Session/Route Scope，singleton/factory，key/token，lazy async readiness |
| Command | 已支持 | 单 Handler、强类型结果、`void`、取消、超时与 Trace |
| Event | 已支持 | 零到多个订阅者、稳定顺序、失败隔离 |
| InitTask | 已支持 | 一次性 DAG、Gate、必需/可选失败策略 |
| 生成器增量缓存与门禁 | 已支持 | `--check`、`--no-cache`、`--profile`、并发锁、原子写入 |
| 生成索引和源码定位 | 已支持 | Package/Host Catalog、`ccrouter find` |
| Navigator 1.0 Backend | 暂不支持 | 2.0 阶段候选 |
| 通用 Navigator 2.0 Backend | 暂不支持 | 2.0 阶段候选 |
| 动态组件安装/卸载 | 暂不支持 | 当前组件集合在 `initialize` 时固定 |
| Action Pipeline | 暂不支持 | 等真实优先级、短路、白名单场景成熟后再设计 |
| 完整状态恢复 | 暂不支持 | 当前只记录脱敏的 restoration opportunity |
| Service/Command/Event 注解生成 | 暂不支持 | 当前样板量不足，仍在 Registrar 中显式注册 |

GoRouter 当前无法可靠提供原子 `pushAndRemoveUntil`、精确 `removeRoute/removeRouteBelow` 和 `replaceRouteBelow`。CCRouter 不公开语义不完整的替代方法，也不会把它们静默拆成多个普通操作。

## 环境要求

- Dart SDK `^3.10.0`
- Flutter SDK：本仓库默认使用 FVM 配置的 Flutter/OHOS Flutter SDK
- GoRouter `^17.5.0`

首次运行：

```bash
fvm flutter pub get
fvm dart analyze
fvm flutter test packages/ccrouter_test/test
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test
fvm flutter test demo
```

运行 macOS Demo：

```bash
cd demo
fvm flutter run -d macos
```

## 最小接入

### 1. 声明组件

每个组件定义一个稳定 descriptor，并用一个 Registrar 注册能力：

```dart
import 'package:ccrouter/ccrouter.dart';

const orderComponent = CCComponentDescriptor(
  id: 'order_component',
  version: '1.0.0',
  dependencies: ['account_component'],
);

part 'ccrouter_generated/component/order_component_registrar.component.g.dart';

@CCComponent(orderComponent)
final class _OrderComponentRegistrar implements CCComponentRegistrar {
  const _OrderComponentRegistrar();

  @override
  void register(CCRegistry registry) {
    orderComponentGeneratedRoutes.register(registry);
    // Service、Command、Event、InitTask 和策略在这里显式注册。
  }
}
```

组件实现类、Registrar 和生成装配入口不要从业务 barrel 导出。组件间使用公开 contracts Package 或明确的 public contract library。

### 2. 声明组件内路由

```dart
import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

import 'ccrouter_generated/component/order_component.route_api.g.dart';

@CCRoute<String>(
  component: orderComponent,
  id: 'order.detail',
  pattern: CCPathPattern('/orders/:orderId'),
  description: '订单详情，确认后返回订单编号。',
)
final class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({
    required this.orderId,
    @CCQueryParam() this.tab = 'summary',
    super.key,
  });

  final int orderId;
  final String tab;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('订单 #$orderId')),
    body: FilledButton(
      onPressed: () => CCRouter.navigator.pop(result: 'confirmed:$orderId'),
      child: const Text('确认'),
    ),
  );
}
```

页面源码**不需要**添加 `.route.g.dart` 的 `part`。执行生成后，IDE 可从组件唯一的 `*.route_api.g.dart` 自动补全路由 API。

单一地址使用 `pattern`；兼容旧 Path 或多入口时使用 `patterns`。两者不能同时设置。多值中只有一个可逆 Pattern 时会自动成为 primary；多个可逆 Pattern 必须显式指定唯一 primary；只有 Regex 且无法反向构造 URI 时生成失败。

### 3. 生成代码

从 Workspace 根目录执行：

```bash
fvm dart run ccrouter_generator:ccrouter generate demo
```

统一命令会运行所需的 build_runner、生成 Package 内路由代码、组件索引、Host Bundle、Catalog 和文档。生成文件位于各 Package 的 `lib/src/ccrouter_generated/`，禁止手工编辑。

### 4. 初始化 Host

Host 使用生成的 Manifest 与 Catalog。新项目默认使用 managed GoRouter Backend：

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    CCGoRouterApp(
      catalog: ccrouterGeneratedRouteCatalog,
      components: ccrouterGeneratedComponentManifests,
    ),
  );
}
```

上面的 `CCGoRouterApp` 会自动装配 managed GoRouter、Root Observer、Adapter、Host
和 `MaterialApp.router`。传入 `components` 是只包含基础组件注册的启动简写；如果需要全局拦截器、Deep Link 白名单、Aspect、Telemetry 或其它配置，仍应显式调用
`CCRouter.initialize`，然后省略 `components`：

```dart
CCRouter.initialize(
  components: ccrouterGeneratedComponentManifests,
  globalInterceptors: const [...],
);
await CCRouter.runInitialization();
runApp(CCGoRouterApp(catalog: ccrouterGeneratedRouteCatalog));
```

`CCRouter.initialize` 同步完成全局配置和启动组件注册；`CCGoRouterApp` 不会在卸载时隐式 shutdown Runtime。应用最终退出或测试 Host 销毁时执行：

```dart
await CCRouter.shutdown();
```

不要在页面 Pop、组件页面销毁、App 后台或 Session 关闭时 shutdown。Runtime 会先销毁它拥有的 Adapter，再释放 managed Backend 创建的 GoRouter；attach 模式不会销毁应用自己创建的 GoRouter。

已有 GoRouter 工程使用 `CCGoRouterBackend.attach`，把生成 bindings、Host 和已经安装到 Router 的 Observer 显式交给 CCRouter。需要自定义 Backend 或完整 Widget 树时，仍可使用 `CCRouterApp.managed`。完整 Shell/Outlet 示例见 [`demo/lib/demo_router_backend.dart`](demo/lib/demo_router_backend.dart)。

## 类型安全导航

业务导航统一经过 `CCRouter.navigator`：

```dart
final result = await CCRouter.navigator.push<String>(
  OrderComponentRoutes.detail(orderId: 42, tab: 'payment'),
  source: const CCNavigationSource.feature('checkout'),
);

await CCRouter.navigator.replace<void>(AccountRoutes.login());
await CCRouter.navigator.go<void>(HomeRoutes.home());
await CCRouter.navigator.reset<void>(HomeRoutes.home());

final handled = await CCRouter.navigator.maybePop();
CCRouter.navigator.pop(result: 'confirmed');
```

语义：

- `push`：在当前栈上新增 Entry，并在该 Entry 被移除时返回强类型结果。
- `replace`：替换当前 CCRouter 管理的 Entry。
- `go`：采用后端 declarative location 语义，与 GoRouter `go` 对齐；可能重建匹配栈。
- `reset`：明确把目标设置为新的根位置。
- `open`：匹配应用内部动态 URI，默认以 push 方式打开，不提供 typed Pop result。
- `maybePop`：尊重 PopGuard、Flutter `PopScope`、LocalHistory 与 foreign popup，返回后端是否处理。
- `pop`：业务主动返回；返回值必须与 Route 的结果类型一致，否则抛出标准导航错误且页面不会被错误移除。

禁止业务代码直接调用 `Navigator.push/pop`、`GoRouter.push/go` 或 Adapter 来操作 CCRouter 管理的页面。临时、局部且不需要组件契约的 Flutter Dialog/BottomSheet 可以继续使用原生 API；它们属于 foreign/overlay，不应改变 Managed Route Scope。

### BuildContext 与 Outlet

通常不传 `BuildContext`，行为与全局 Host 路由一致。只有同一路由需要按调用位置落入当前 Shell、Pane 或嵌套 Navigator 时才传：

```dart
await CCRouter.navigator.push<void>(
  DetailRoutes.detail(id: 1),
  context: context,
);
```

Context 只用于严格解析最近的 Host/Outlet，不会被全局保存。解析失败会报错，不会猜测另一个 Host 或 Outlet。

### 动态 URI

应用内部运行时地址使用：

```dart
await CCRouter.navigator.open(Uri.parse('/orders/42?tab=payment'));
await CCRouter.navigator.open(Uri.parse('myapp://order/42'));
await CCRouter.navigator.open(
  Uri.parse('https://example.com/web?url=https%3A%2F%2Fflutter.dev'),
);
```

匹配在 URI 结构层完成，Path segment 与 Query 按 Codec 解码；不要先对完整 URI 做字符串级 `decodeComponent`。需要传递标准网页 URL 时，把它作为 Query 参数或 typed argument，不要把未转义 URL 拼进另一个 Query。

### Path、URI 与参数

路由支持：

- 标准 Path：`/orders/:orderId`
- 完整 URL：`https://example.com/orders/:orderId`
- custom scheme：`myapp://order/:orderId`
- Regex：用于只匹配、不反向生成的兼容入口
- 多 Pattern 指向同一页面
- Path 参数自动转换
- `@CCQueryParam` 标量、enum、`List<T>`、`Set<T>` 与自定义 Codec
- `@CCExtraParam` 进程内对象，不写入 URI、文档或诊断

外部可分享数据应进入 Path/Query；Token、Controller、大对象和不可序列化状态不得放入 URL。`Extra` 只适合进程内短生命周期数据，不能依赖它做 Deep Link、状态恢复或跨进程传递。

## 跨组件 Route Contract

组件内路由默认保持内部。只有另一个组件确实需要调用时，才把契约提升到独立 Pure Dart contracts Package：

```dart
// order_contracts
@CCRouteContract<String>(
  component: orderComponent,
  id: 'order.detail',
  pattern: CCPathPattern('/orders/:orderId'),
)
abstract class OrderDetailRouteContract {
  const OrderDetailRouteContract({
    required this.orderId,
    @CCQueryParam() this.tab = 'summary',
  });

  final int orderId;
  final String tab;
}
```

页面组件只绑定实现：

```dart
@CCRouteImplementation(OrderDetailRouteContract)
final class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({required this.orderId, this.tab = 'summary', super.key});
  // ...
}
```

消费者依赖 `order_contracts`，不依赖 `order` 页面 Package。保持原 route ID、wire name 和结果类型，可以把既有 `@CCRoute` 平滑提升为 `@CCRouteContract`。契约可见性由 Package 依赖和 barrel export 决定，不再额外维护 `visibility`、`visibleTo` 或 `contractMode`。

## 页面展示与动画

`CCRoute.presentation` 是后端中立描述。当前支持：

- 平台默认 PageRoute
- Material / Cupertino
- fade / scale / 从底部滑入
- 透明全屏 Page
- Dialog Route
- Modal Bottom Sheet Route

普通页面可以使用从底部滑入与透明背景，例如海报分享页。Dialog/BottomSheet 只有在需要跨组件类型安全契约、Interceptor、Trace、Route Scope 或统一返回值时才应建模为 CCRouter Route；单页面局部提示继续用 Flutter API，避免把所有 Overlay 都升级成全局路由。

## Deep Link

内部动态地址与外部不可信输入必须分开：

```dart
// 内部
await CCRouter.navigator.open(Uri.parse('/orders/42'));

// Universal Link / App Link / custom scheme
await CCDeepLinkIngress.fromPlatform(uri);

// 通知
await CCDeepLinkIngress.fromNotification(uri);

// 二维码
await CCDeepLinkIngress.fromQrCode(uri);
```

外部 URI 必须同时通过：

1. Host 的 `CCDeepLinkIngressPolicy` allowlist。
2. 目标 Route 的 `CCDeepLinkPolicy.enabled`。

默认 Host policy 为 `denyAll`，默认 Route policy 为 disabled。`CCNavigationSource.deepLink` 只记录来源，不能把内部请求伪装成受信任外部入口。

外部入口默认使用 push，保留固定首页或主 Tab 的返回路径；Host 可显式选择 `CCDeepLinkOpenMode.go` 来重建 declarative Shell location。选择栈行为不会绕过安全策略。

平台模拟和手工验证入口见 [`demo/README.md`](demo/README.md)。

## Interceptor、Defer 与失败恢复

Interceptor 是**导航前决策**，适合：

- 登录与账号状态
- 权限或合规同意
- 维护模式、强制升级、Feature Flag
- 安全风控
- redirect 到登录/说明页
- defer 原请求，外部条件满足后恢复

全局 Interceptor 在 `CCRouter.initialize` 注入；路由级 Interceptor 在组件 Registrar 注册，并由注解中的稳定 ID 引用。它们可以返回 proceed、cancel、redirect 或 defer。

不要在 Interceptor 中调用 `CCRouter.navigator` 或 Adapter，也不要用它做 PV/UV、页面到达回调或业务数据加载。异步 Interceptor 必须有明确超时和取消语义。

`CCNavigationDefer` 会把原请求保存为 Pending Navigation。登录、授权或设备解锁成功后由 Host 调用 `resumePendingNavigation`；放弃流程时调用 `cancelPendingNavigation`。Failure Policy 仅处理稳定的解析、Codec、Adapter 等失败，默认传播错误；它不应吞掉编程错误或把未知地址静默送往错误页面。

## PopGuard

PopGuard 用于页面离开前可同步判断的规则，例如内存中的未保存编辑状态、不可中断步骤或受控流程。它必须同步且快速。需要弹确认框、网络请求或异步保存时使用 Flutter `PopScope` 管理 UI，再在确认后调用 `CCRouter.navigator.pop`。不要从 Guard 内再次发起导航。

系统返回、普通 Pop、Cupertino 手势和 Android predictive back 都进入统一协调；foreign Popup 或 `LocalHistoryEntry` 消费返回时不会关闭底层 Managed Route Scope。

## Aspect、Trace、Telemetry 与生命周期

`CCNavigationAspect` 只观察导航阶段，不做决策。它适合 PV/UV 与来源归因、route found/arrival/completion/failure 观察、耗时、跨 Host/Outlet 链路追踪和脱敏日志。Aspect 回调异常会被隔离；回调中不得同步重入导航。请求参数、完整 URI、Extra、Token 和业务返回对象不会进入默认诊断记录。

页面需要当前 Route 与 App 前后台回调时，可以选择 Mixin：

```dart
final class DetailState extends State<DetailPage>
    with CCPageLifecycleMixin<DetailPage> {
  @override
  void onPageShow() {}

  @override
  void onPageHide() {}

  @override
  void onForeground() {}

  @override
  void onBackground() {}
}
```

或组合式 Listener：

```dart
CCPageLifecycleListener(
  onPageShow: () {},
  onPageHide: () {},
  child: const DetailBody(),
)
```

`PageShow/PageHide` 表示 PageRoute 是否为其 active Outlet 的当前主 Route，不代表物理像素是否仍可见。Widget 创建与销毁仍使用 Flutter `initState/dispose`。资源所有权不要交给曝光回调；页面实例资源应使用 Route Service。

## Host、Shell 与 Outlet

`CCNavigationHost` 是框架对一个独立 Flutter navigation tree / Flutter View 的映射，不等同于平台 Window：

- 手机横竖屏、桌面窗口缩放：通常仍是同一个 Host，只更新 metrics。
- 折叠屏展开或折痕变化：通常仍是一个 Host，调整布局和 Outlet。
- 大屏左列表右详情：一个 Host，两个 Outlet。
- Bottom Tab、`ShellRoute`、`StatefulShellRoute`：一个 Host，多个 Shell/Outlet。
- Dialog、BottomSheet、Popup：属于当前 Host 的 Route 或 Overlay，不是新 Window。

真实 macOS/Windows/iPadOS 多窗口可以映射为多个 Host，但当前只提供底层隔离和接入能力，不宣称已经完成所有平台多窗口生命周期集成。

Shell 与 nested route 是 Host 拓扑，生成器不会猜测。Host 使用 `CCGoRouterRouteOverride`、`CCGoRouterShellBinding` 和 Outlet Observer 显式装配，业务页面仍只使用 `CCRouter.navigator`。

## Service

Service 表达可重复调用、可能持有状态或资源的长期能力。选择最窄 Scope：

| Scope | 创建与销毁 | 适合场景 |
| --- | --- | --- |
| `app` | 首次解析到 Runtime shutdown | 配置、网络门面、全局缓存 |
| `session` | 登录 Session 内首次解析到 logout/account switch | 用户资料、账号缓存、鉴权能力 |
| `route` | 某个 Managed RouteEntry 内首次解析到 Entry 永久移除 | 页面 Controller、草稿、页面订阅 |

Registrar 注册：

```dart
registry.registerService<OrderRepository>(
  CCServiceProvider(
    scope: CCServiceScope.session,
    factory: (_) => OrderRepositoryImpl(),
  ),
);
```

解析：

```dart
final repository = CCRouter.service<OrderRepository>();
final optional = CCRouter.serviceOrNull<OptionalCapability>();
final readyService = await CCRouter.serviceAsync<RemoteConfigService>();
final controller = CCRouter.routeService<OrderDraftController>(context);
```

- 默认 `singleton` 是每个 Scope 一个懒实例。
- `factory` 每次解析创建新实例，但需要销毁的实例仍由 Scope 统一拥有；不要用它模拟手工 dispose 的临时对象。
- `initializer` 只用于实例无法在同步构造后立即工作的异步 readiness；调用方必须使用 `serviceAsync`。
- 多实现使用 `CCServiceKey<T>`；跨 Package 稳定契约使用 `CCServiceToken<T>`。
- 实现 `CCDisposable` 的实例由 Scope 按逆构造顺序自动销毁，业务不得自行 dispose。
- `serviceOrNull` 只把“未注册”转换为 null，不吞掉 Factory、Scope 或初始化错误。

Session 由认证流程显式管理：

```dart
CCRouter.openSession(accountId: account.id);
await CCRouter.closeSession();
```

App 后台、页面切换和普通 Pop 都不会关闭 Session。退出登录、Token 失效、账号切换或强制下线才关闭。

## Command

Command 表达“由唯一 Owner 执行的一次性动作”，可返回强类型结果，也可使用 `void`：

```dart
final class SubmitOrder implements CCCommand<String> {
  const SubmitOrder(this.orderId);
  final int orderId;
}

registry.registerCommand<SubmitOrder, String>((command, context) async {
  if (context.cancellation.isCancelled) {
    throw const CCInvocationCancelledError();
  }
  return 'receipt:${command.orderId}';
});

final receipt = await CCRouter.command(
  const SubmitOrder(42),
  timeout: const Duration(seconds: 10),
);
```

适合创建订单、提交支付、刷新远端数据等一对一操作。状态读取或多次方法调用使用 Service；“已经发生”的广播使用 Event。取消是协作式的，框架可以结束等待并发出 cancellation，但不能强制停止同步 Dart 代码或回滚已发生的副作用。

## Event

Event 表达已经发生的事实，Publisher 不依赖订阅者结果：

```dart
final class OrderPaid implements CCEvent {
  const OrderPaid(this.orderId);
  final String orderId;
}

registry.registerEvent<OrderPaid>(
  'analytics.order-paid',
  (event, _) => analytics.track(event.orderId),
);

await CCRouter.event(const OrderPaid('42'));
```

同一 Event 可以没有订阅者或有多个订阅者。订阅按稳定 ID 确定启动顺序，单个订阅者失败不会阻止其他订阅者；调用 Future 在本次分发完成后结束。需要唯一处理者、返回值或业务成功语义时使用 Command，不要使用 Event。

## InitTask

InitTask 是 Runtime 生命周期内只执行一次的启动任务 DAG，适合 SDK 初始化、基础配置加载和具有明确依赖关系的启动工作：

```dart
registry.registerInitializationTask(
  CCInitializationTask(
    id: 'analytics.initialize',
    dependsOn: const ['privacy.load'],
    gate: const CCInitializationGate('privacy.granted'),
    failurePolicy: CCInitializationFailurePolicy.optional,
    run: (_) async => analytics.initialize(),
  ),
);
```

Host 在 `CCRouter.initialize` 后调用 `CCRouter.runInitialization()`。Runtime 会校验重复 ID、缺失依赖与循环依赖。必需任务失败会阻止初始化完成；可选任务失败可诊断但不阻断无依赖分支。单个 Service 的异步准备应放在 `CCServiceProvider.initializer`，不要创建 InitTask 预热所有 Service。

## 生成器

常用命令：

```bash
# 生成/增量更新
fvm dart run ccrouter_generator:ccrouter generate demo

# CI 只读一致性门禁；发现变化后恢复现场并返回非零
fvm dart run ccrouter_generator:ccrouter generate demo --check

# 禁用 metadata 缓存，验证参考全量路径
fvm dart run ccrouter_generator:ccrouter generate demo --no-cache

# 输出阶段耗时和缓存命中率
fvm dart run ccrouter_generator:ccrouter generate demo --profile

# 查找 route ID 或声明 Pattern 的组件、契约、页面源码
fvm dart run ccrouter_generator:ccrouter find order.detail demo
fvm dart run ccrouter_generator:ccrouter find '/orders/:orderId' demo

# 只清理 CCRouter 标记的生成源码
fvm dart run ccrouter_generator:ccrouter clean demo
```

生成目录统一为：

```text
lib/src/ccrouter_generated/
├── binding/     # Flutter 页面构造 bridge
├── component/   # Manifest、组件 Route API、组件路由索引
├── contract/    # 独立 Pure Dart Route Contract
├── host/        # Host 聚合入口
├── metadata/    # Package Index、Host routes、可读 Catalog
└── route/       # 组件内部 Route contract/registration bridge
```

并非每个 Package 都会生成全部子目录；Package Bundle 与 Host 聚合代码按 Package 角色写入 `host/`。

页面新增后只需添加注解并重新执行 `generate`；不要手写生成文件、逐页修改 Registrar 或给页面添加 generated `part`。Registrar 的 `.component.g.dart` 是唯一必须保留的 `part`，用于同 library 的私有 Registrar Manifest。

详细生成规则见 [`packages/ccrouter_generator/README.md`](packages/ccrouter_generator/README.md)。

## 测试

框架使用者的测试能力统一放在 `ccrouter_test`，生产代码不要访问 Runtime 私有构造器。测试至少覆盖 Route Intent、Interceptor、PopGuard、Scope 销毁、Command 取消/超时、Event 失败隔离、InitTask DAG 和 Host/Outlet 混合导航。

完整回归：

```bash
fvm dart analyze
fvm flutter test packages/ccrouter_test/test
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test
fvm flutter test demo
fvm dart run ccrouter_generator:ccrouter generate demo --check
```

## API 边界

业务和组件代码应遵守：

- 只通过 `CCRouter.navigator` 导航 CCRouter 管理的页面。
- 只通过生成的 Intent 调用静态已知路由；动态地址使用 `open`。
- 不访问 `CCRouterRuntime`、`CCScope`、Registry 内部表、Adapter Controller 或销毁入口。
- 不从业务代码导入 `ccrouter_host.dart`、`ccrouter_core/src/*` 或生成 binding/package/host 文件。
- 不把 Registrar、Manifest、页面实现或组件 private 类型当作跨组件契约。
- 不手工 dispose 框架拥有的 Service、Adapter 或 Route Scope。
- 不在 Interceptor、Aspect、Lifecycle callback 中同步递归导航。
- 不把完整 URI、Token、Extra、参数或返回对象写入日志和 Telemetry。

生成器与 Analyzer 会尽量把 Route ID、Pattern、Codec、参数、跨 Package import 和内部 API 误用提前到构建期，但 `src` 目录本身不是 Dart 的强私有边界；CI 必须保留 analyze 与 `generate --check`。

## AI 集成开发 Skill

仓库提供 [`skills/ccrouter-integration-development/SKILL.md`](skills/ccrouter-integration-development/SKILL.md)，供 Codex 或其他支持 Markdown Skill 的 AI Agent 在业务集成开发时使用。它会强制 Agent：

- 先判断应使用 Route、Service、Command、Event 还是 InitTask。
- 页面导航统一走 `CCRouter.navigator`。
- 正确区分 Interceptor、PopGuard、Aspect 和页面生命周期。
- 遵守 Host SPI、组件实现与 contracts Package 的依赖边界。
- 不虚构当前尚未实现的 Action Pipeline、动态组件或 Service 注解。
- 生成后执行 analyze、针对性测试与 `generate --check`。

将完整的 `skills/ccrouter-integration-development/` 目录复制或同步到集成工程的 `skills/` 下，不要只复制 `SKILL.md`，因为能力决策、实现模式和审查清单位于 `references/`。然后在集成工程的 Agent 规则中加入：

```text
When implementing or reviewing Flutter features that use CCRouter, read and
follow skills/ccrouter-integration-development/SKILL.md.
```

支持显式 Skill 调用的客户端也可以直接使用：

```text
$ccrouter-integration-development 为订单组件新增详情页，并返回类型安全的确认结果。
```

Skill 采用短主文件和按需 reference 结构，既适合日常编码，也可用于代码审查。框架公开 API、生命周期、错误语义、生成命令、支持状态或推荐 Demo 用法发生变化时，维护者必须同步审查本 README、Integration Skill 及其 references。

## 进一步阅读

- [`demo/README.md`](demo/README.md)：可交互能力清单和真机验证方式
- [`docs/CCRouter-v0.1-architecture.md`](docs/CCRouter-v0.1-architecture.md)：总体架构
- [`docs/CCRouter-route-design.md`](docs/CCRouter-route-design.md)：路由设计
- [`docs/CCRouter-component-framework-comparison.md`](docs/CCRouter-component-framework-comparison.md)：与其他组件化框架的能力对比和后续缺口
- [`docs/CCRouter-service-lifecycle-design.md`](docs/CCRouter-service-lifecycle-design.md)：Service 生命周期设计
- [`docs/CCRouter-command-design.md`](docs/CCRouter-command-design.md)：Command 设计
- [`docs/CCRouter-event-design.md`](docs/CCRouter-event-design.md)：Event 设计
- [`docs/CCRouter-initialization-task-design.md`](docs/CCRouter-initialization-task-design.md)：InitTask 设计
- [`docs/CCRouter-core-principles-audit.md`](docs/CCRouter-core-principles-audit.md)：核心价值回归

设计文档用于解释约束与演进方向；实际可用 API 以当前 public barrel、生成器校验和 Demo 回归为准。
