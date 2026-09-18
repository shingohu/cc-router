# CCRouter Flutter 组件化框架 v0.1 架构设计

## 文档状态

- 版本：v0.1 Draft
- 框架名称：`CCRouter`
- 目标平台：Flutter 应用（Android、iOS，后续可扩展 Web、桌面）
- 公开 API：统一使用 `CCRouter` 静态 API
- 核心约束：运行时核心不依赖 `BuildContext`
- 工程分发决策：Git Monorepo + Pub Workspace + 私有 Hosted Pub

本文档描述 CCRouter 的架构边界、核心语义和 v0.1 的验收范围。代码示例用于表达契约，不表示 v0.1 已经完成全部实现。

路由子系统的详细契约、生成模型和实现阶段见 [CCRouter 路由子系统设计](CCRouter-route-design.md)。

---

## 1. 背景与问题

Flutter 的多 Package 或多业务模块应用在规模增长后，通常会遇到以下问题：

1. 页面之间通过直接 import 和具体 Widget 类型耦合。
2. 业务组件直接依赖其他组件的实现，而不是稳定契约。
3. 初始化代码集中堆积在 `main` 或 `Application` 入口。
4. 登录态服务、页面服务和全局服务的生命周期混在一起。
5. 异步调用、拦截、超时和取消没有统一语义。
6. 出错时只能看到零散日志，无法还原完整调用链。
7. 组件无法脱离主 App 独立运行和测试。
8. 多产品装配、Mock 替换和可选组件缺少统一机制。

CCRouter 的目标不是再提供一个单纯的路由库，而是提供一套组件运行时和配套工程工具，使组件之间通过可检查的契约协作。

---

## 2. 设计目标

### 2.1 必须支持

- 组件之间只依赖契约，不依赖实现。
- 统一静态入口，不要求业务代码传入 `BuildContext`。
- URL/Path 方式的页面寻址和 Deep Link。
- 页面导航的类型化返回结果。
- 强类型 Service 注册、发现、多实现和作用域管理。
- Command、Query、Action、Event 四类通信语义。
- 同步或异步请求响应、超时、取消和标准错误。
- 全局及局部拦截器和可追踪调用链。
- 初始化任务 DAG、自定义 Gate 和失败策略。
- App、Session、Component、Route、Transient 作用域。
- 组件独立运行、Mock 覆盖和测试 Runtime。
- 代码生成、冲突检查、依赖检查和契约文档生成。

### 2.2 v0.1 明确不做

- 运行时下载或动态加载新的 Dart 业务代码。
- 跨 App RPC 和完整的跨进程调用协议。
- 持久化 Event、事件重放和离线消息队列。
- 接管状态管理、网络库、数据库或 UI 设计体系。
- 重新实现完整的 Flutter `Navigator`。
- 第一版同时维护 Navigator 2.0、GoRouter、GetX 等多个行为不完全一致的后端。
- 通过远程配置执行任意方法名或任意本地代码。

---

## 3. 核心设计原则

1. **契约优先**：对外暴露的是稳定的 Route、Service、Command、Query、Action 和 Event 契约。
2. **语义分离**：页面导航、能力调用、请求响应和事实通知不能被压缩成一个万能接口。
3. **生成优先**：注册表、代理、参数 Codec 和检查结果尽量在编译/生成阶段确定。
4. **显式生命周期**：实例属于明确 Scope，Scope 关闭时由 Runtime 统一回收。
5. **调用有上下文**：每次框架调用都携带调用方、目标、Trace、Deadline 和取消信息。
6. **失败可治理**：错误、超时、取消、降级和重试都有标准语义。
7. **静态门面、实例内核**：业务使用静态 `CCRouter`，内部由可替换 Runtime 负责实际状态。
8. **确定性**：注册顺序、实现选择、事件顺序和拦截器顺序不能依赖偶然的 Package 加载顺序。
9. **渐进式接入**：现有 Flutter 工程可以先接入路由或服务，再逐步接入初始化、Trace 和组件治理。

---

## 4. 总体架构

```text
Annotations / Contracts
          |
Component Generated Registrar
          |
Application Manifest Aggregator
          |
CCRouter Static Facade
          |
Active Runtime Resolver
          |
CCRouterRuntime
├── Route Registry / Navigation Adapter
├── Service Registry / Generated Proxy
├── Command / Query Dispatcher
├── Action Dispatcher / Event Bus
├── Scope / Lifecycle Manager
├── Initialization DAG / Gate Manager
└── Tracing / Diagnostics
```

### 4.1 包边界建议

```text
ccrouter                 Flutter 业务门面、CCNavigator、CCRouterApp 和默认 Runtime 宿主
ccrouter_contracts       纯 Dart 契约、错误、Codec 接口和基础类型
ccrouter_core            Runtime、Registry、Scope、Dispatcher、Trace
ccrouter_annotations     Route、Service、Handler、InitTask 等注解
ccrouter_generator       Dart build_runner 代码生成器
ccrouter_go_router       默认 go_router 导航适配器
ccrouter_test             测试 Runtime、Override、TestHost 和断言工具
ccrouter_devtools         后续的可视化诊断工具
```

`ccrouter_core` 保持 Pure Dart；Flutter 相关类型只出现在 `ccrouter_flutter` 和业务组件的页面实现中。

这些是源码和依赖治理边界，不要求每个边界都成为业务方手工配置的依赖。v0.1 中，出现在公开传递依赖图里的 Package 必须可以独立发布；仅供开发或测试使用的 Package 可以标记为开发工具包。

### 4.2 源码、Workspace 与远程分发

CCRouter 的规范源码位于 Git Monorepo。根目录使用 Dart Pub Workspace 管理多个 Package，Workspace 只负责仓库内的本地解析、共享锁文件和一致性检查。

正式的 Package `pubspec.yaml` 必须保持来源无关：组件之间使用普通的 SemVer 版本约束，不写 `path:`，也不把开发分支或临时 Git URL 写入规范依赖。例如：

```yaml
name: ccrouter
version: 0.1.0
resolution: workspace

dependencies:
  ccrouter_core: ^0.1.0
  ccrouter_flutter: ^0.1.0
```

在 CCRouter Monorepo 内，Pub 会将满足约束的同名 Workspace 成员解析为本地 Package；Package 离开 Workspace 后，同一声明会解析到 Hosted 仓库。这保证本地开发和远程消费使用同一份依赖声明。

正式远程分发优先使用私有 Hosted Pub。Git 负责源码、评审、Release Tag 和 Commit 追溯，CI 负责按依赖 DAG 测试、生成、检查并发布 Package。业务工程只需要依赖公开门面包及其必要的开发工具包：

```yaml
dependencies:
  ccrouter: ^0.1.0

dev_dependencies:
  ccrouter_generator: ^0.1.0
```

如果业务工程需要跨仓库本地联调，使用不提交到 Git 的 `pubspec_overrides.yaml` 覆盖 CCRouter 依赖。覆盖必须包含实际进入依赖图的完整 CCRouter 闭包，不能只覆盖门面包，否则会产生本地与远程 Package 混用。CI 必须在没有 overrides 的干净环境中再次执行远程解析和测试。

Git 直接依赖是预览和 Hosted 暂不可用时的兜底渠道，不是多 Package 的正式分发方式：

```yaml
dependencies:
  ccrouter:
    git:
      url: https://git.example.com/mobile/cc-router.git
      ref: ccrouter-v0.1.0
      path: packages/ccrouter
```

远程 Git 依赖必须使用受保护的不可移动 Release Tag 或完整 Commit SHA，禁止依赖 `main`/`master`。由于 Git 依赖不会自动解析同仓库 Workspace sibling，若 Hosted 不可用，首选将 Git 分发边界收敛为一个无 sibling 传递依赖的 `ccrouter` Package；不把逐包 Git URL、消费者全量 overrides 或 Git Submodule 作为长期方案。

### 4.3 公开 API 与内部实现隔离

业务工程只允许依赖和导入 `package:ccrouter/ccrouter.dart`。门面包公开以下类型：

- `CCRouter` 静态业务 API。
- Command、Query、Action、Event、Session、错误和取消等契约类型。
- `CCComponentManifest`、`CCComponentRegistrar`、`CCRegistry` 和 Provider 等组件作者 API。
- 稳定的只读诊断记录类型。

门面包不得导出 `CCRouterRuntime`、`CCScope`、`CCScopeState`、Provider 内部存储、Dispatcher 或宿主创建函数。业务组件的 Registrar 只接收 `CCRegistry`；该接口只能注册能力，不能解析服务、执行消息、开关 Session、关闭 Runtime 或访问可变诊断状态。

框架实现文件使用 Dart library privacy 隔离。需要跨文件共享私有 Runtime 构造、Active Runtime 和生命周期入口时，使用 `part`/`part of` 归入同一 library，不为跨文件调用而提升为 public。下划线私有成员承担真正的内部 API；仅通过 barrel export 的显式 `show`/`hide` 控制业务可见面不能替代 library privacy，但可以作为第二层约束。

测试 Runtime 属于 `ccrouter_core` 的低层测试面，不通过 `ccrouter` 门面导出。`ccrouter_core/test` 只保留 Core 包内部实现的低层回归测试；面向框架使用者、组件作者、测试宿主、Mock、导航测试和集成测试的新增测试代码与测试 API 统一放入独立的 `ccrouter_test` 包，由该包提供受控测试宿主、Override 和断言工具。业务生产代码禁止直接导入 `ccrouter_core/src/` 或依赖任何 Core 内部测试入口。CI/Analyzer 必须启用依赖与实现导入检查，阻止业务 Package 绕过门面依赖内部包。

---

## 5. 术语与核心模型

### 5.1 Component

组件是一个可独立装配、运行和测试的业务或基础能力单元。组件拥有自己的代码、契约、实现、注册片段和测试宿主，但不一定对应一个单独的 Dart Package。

### 5.2 Contract

契约是组件之间依赖的稳定 API。契约可以是接口、不可变参数对象、结果对象、Route 描述、Command、Query、Action 或 Event 类型。

### 5.3 Capability

Capability 是可以被 Runtime 发现和调用的能力，包含 Route、Service Provider、Command Handler、Query Handler、Action Handler、Event Subscriber 和 InitTask。

### 5.4 Manifest

`CCComponentManifest` 是组件的机器可读描述，作为注册、依赖检查、文档和装配的统一数据源。至少包含：

- 组件 ID、版本和 Owner。
- 必需/可选组件依赖。
- 暴露和消费的契约。
- Route、Service、Handler、Subscriber 和 InitTask 描述。
- Scope、可见性、平台要求和权限要求。
- 失败、降级和兼容策略。

### 5.5 Runtime

`CCRouterRuntime` 是一个完整的组件运行环境。每个 Dart Isolate 默认拥有独立 Runtime；测试可以创建多个相互隔离的 Runtime。

### 5.6 Invocation

Invocation 是一次被 CCRouter 调度的调用。它有唯一的调用 ID，包含统一的上下文、结果状态和 Trace Span。

### 5.7 Scope

Scope 管理一组对象、订阅、任务和未完成调用的共同生命周期。v0.1 支持：

```text
App        Runtime 存活期间
Session    一次登录会话
Component  组件启用期间
Route      一次具体路由实例
Transient   每次获取或调用
```

---

## 6. 静态 API 设计

业务代码统一从 `CCRouter` 进入：

```dart
await CCRouter.initialize(
  components: [
    OrderComponentManifest.generated,
    PaymentComponentManifest.generated,
  ],
);

CCRouter.openSession(accountId: authenticatedUser.id);

final result = await CCRouter.navigator.push<AddressResult>(
  AddressRoutes.select(cityId: '310000'),
  context: context,
);

final account = CCRouter.service<AccountService>();

final order = await CCRouter.command(
  CreateOrderCommand(cartId: cartId),
);

final user = await CCRouter.query(CurrentUserQuery());

await CCRouter.action(ShowCampaignAction());

CCRouter.event(OrderCreatedEvent(order.id));
```

建议的正式门面如下：

```dart
abstract final class CCRouter {
  static Future<void> initialize({
    required Iterable<CCComponentManifest> components,
    required CCNavigationAdapter navigation,
  });

  static Future<void> shutdown();

  static void openSession({
    required String accountId,
    Map<String, Object?> metadata,
  });

  static Future<void> closeSession();

  static CCNavigator get navigator;

  static T service<T>({CCServiceKey<T>? key});
  static T? serviceOrNull<T>({CCServiceKey<T>? key});
  static List<T> services<T>();
  static bool hasService<T>({CCServiceKey<T>? key});

  static Future<R> command<R>(CCCommand<R> command);
  static Future<R> query<R>(CCQuery<R> query);
  static Future<CCActionReport> action(CCAction action);
  static void event(CCEvent event);

  static void trigger(CCGate gate);
}
```

### 6.1 静态 API 的内部实现约束

- `CCRouter.initialize()` 创建并持有默认 Runtime；业务 App 不直接创建或销毁 Runtime。
- `CCRouter.shutdown()` 停止新调用、销毁默认 Runtime 并清除 Active Runtime。
- 其余静态方法只负责转发到当前 Active Runtime。
- 不允许各子系统维护彼此独立的全局静态 Map。
- 测试和底层多 Engine/Isolate 宿主可以通过明确标记的测试 API 创建隔离 Runtime，并使用 Runtime Overlay，不修改默认 Runtime。
- 未初始化调用统一抛出 `CCRouterNotInitializedError`。
- 默认 Runtime 存活期间再次调用 `initialize()` 抛出 `CCRouterAlreadyInitializedError`；必须先等待 `shutdown()` 完成。
- 谁创建 Runtime，谁负责关闭它；正式 App 中所有权属于 `CCRouter`，隔离测试 Runtime 的所有权属于测试宿主。
- `BuildContext` 不是 Runtime、Service、Command、Query、Action 或 Event 的必需参数。

### 6.2 导航适配器绑定

Flutter 应用启动时显式绑定一个导航适配器。简单应用可以直接将 Adapter 的 router 交给 `MaterialApp.router`；需要 Shell、Outlet、Deep Link、生命周期、埋点或多窗口绑定时，再使用可选的 `CCRouterApp` Host：

```dart
await CCRouter.initialize(
  components: ApplicationManifest.generated,
  navigation: CCGoRouterAdapter(router: appRouter),
);

runApp(
  CCRouterApp(
    child: MaterialApp.router(routerConfig: appRouter),
  ),
);
```

适配器内部可以使用 `NavigatorState`、`RouterDelegate` 或其他 Flutter 机制，但这些细节不暴露给组件调用方。`CCRouterApp` 提供生命周期和 Outlet 绑定，不保存全局 `BuildContext`；无 Context 导航由 Adapter 的根 Outlet 执行。

---

## 7. 组件注册与代码生成

### 7.1 两阶段注册

每个组件单独生成注册片段：

```text
order_component  -> order_ccrouter.registrar.dart
payment_component -> payment_ccrouter.registrar.dart
```

应用构建阶段聚合片段：

```text
all registrars
    -> Application Manifest
    -> global validation
    -> generated CCRouter registry
```

这样组件可以独立测试和发布，App 聚合阶段负责全局冲突和依赖检查。

### 7.2 生成器职责

- 收集注解元素并解析契约。
- 生成 Route Descriptor、参数 Codec 和 URL Builder。
- 生成 Service Factory 和方法代理。
- 生成 Handler、Interceptor、Subscriber 和 InitTask 注册表。
- 生成组件 Manifest Registrar。
- 生成契约文档和调试元数据。
- 对重复 ID、模糊路由、多默认实现、未知依赖和初始化循环报错。

### 7.3 注册确定性

- Route、Service、Task、Handler 和 Event ID 必须全局唯一。
- 生产环境禁止静默覆盖。
- 多实现必须通过显式 Key 选择；不能依赖注册顺序或隐式最高优先级。
- 生成器应输出稳定排序的注册表，保证构建结果可复现。

---

## 8. Service 体系

### 8.1 服务声明与获取

契约包定义接口：

```dart
abstract interface class PaymentService {
  Future<PayResult> pay(PayRequest request);
}
```

提供方组件注册实现：

```dart
@CCService(
  contract: PaymentService,
  scope: CCServiceScope.session,
  exported: true,
)
final class PaymentServiceImpl implements PaymentService {
  PaymentServiceImpl(this.api);

  final PaymentApi api;

  @override
  Future<PayResult> pay(PayRequest request) => api.pay(request);
}
```

调用方：

```dart
final payment = CCRouter.service<PaymentService>();
final result = await payment.pay(request);
```

服务需要提前注册 Provider 描述，但不需要提前实例化，也不要求业务手动字段注入。默认使用构造函数注入和懒创建。

### 8.2 多实现

同一个服务契约允许多个实现：

```dart
abstract final class PaymentServices {
  static const wechat = CCServiceKey<PaymentService>('payment.wechat');
  static const alipay = CCServiceKey<PaymentService>('payment.alipay');
}

final payment = CCRouter.service(key: PaymentServices.wechat);
final all = CCRouter.services<PaymentService>();
```

规则：

- 无 Key 获取时只能存在一个显式默认实现。
- 多个默认实现生成阶段失败。
- 命名实现使用生成的强类型 Key，不鼓励裸字符串。
- `services<T>()` 返回稳定排序的全部实现。
- App 装配或测试 Overlay 可以显式 Override。

### 8.3 服务代理

跨组件核心 Service 由生成器生成 Proxy：

```text
caller -> Service Proxy -> Middleware/Trace/Scope Check -> implementation
```

Proxy 用于记录方法级调用、检查 Scope、传播取消和标准化错误。普通的纯本地工具服务可以选择不生成方法代理。

### 8.4 服务错误

至少定义：

```text
ServiceNotFoundError
AmbiguousServiceError
DuplicateDefaultServiceError
ServiceNotReadyError
ServiceScopeUnavailableError
CircularServiceDependencyError
ServiceCreationFailedError
ServiceScopeClosedError
```

---

## 9. Scope 与服务生命周期

### 9.1 Session Service

登录态服务属于 `SessionScope`。Session 表示一次经过认证的账号会话，不表示页面生命周期或 App 前后台状态。Provider 注册一次，实例随登录会话创建和销毁：

```dart
CCRouter.openSession(
  accountId: login.userId,
  metadata: {'tenantId': login.tenantId},
);

final account = CCRouter.service<AccountService>();

await CCRouter.closeSession();
```

生命周期：

```text
closed -> opening -> ready -> closing -> closed
```

退出时：

1. Session 标记为 `closing`，拒绝新的 Session Service 获取。
2. 取消 Scope 内未完成调用。
3. 关闭其 Route Scope 或执行必要的路由清理。
4. 按依赖逆序调用 `dispose()`。
5. 清空本次 Session 的实例缓存。
6. 标记为 `closed`。

Runtime 为每次打开生成唯一 `sessionId`，并记录 `accountId`、开启时间和非敏感元数据。用户主动退出、Token 失效且刷新失败、账号切换、强制下线或 Runtime 关闭时必须关闭 Session。App 进入后台、页面切换或临时无操作不关闭 Session。

重新登录创建全新的 `SessionScope`，按原 Provider Factory 重新实例化。账号切换必须先完整关闭旧 Session，再打开新 Session。旧 Service Proxy 永久失效，不能自动指向新会话。

### 9.2 Route Service

Route Service 绑定一次具体 `CCRouteEntry`，不是绑定 Widget 或 `BuildContext`。路由永久移出导航栈时，Route Scope 才销毁。

### 9.3 销毁协议

```dart
abstract interface class CCDisposable {
  FutureOr<void> dispose();
}
```

销毁要求：

- 先停止新调用，再取消旧调用。
- 依赖方先于被依赖方销毁。
- 单个服务销毁失败不阻塞其他服务。
- 异步销毁有超时。
- 关闭过程进入 Trace。
- Scope 关闭后的代理调用返回 `ServiceScopeClosedError`。

---

## 10. Navigator 设计

### 10.1 基本原则

- 所有业务跳转统一通过 `CCRouter.navigator`，生成的 Route API 只创建类型安全 Intent。
- Route ID 是稳定身份；一个路由可以拥有一个主 Pattern 和多个 Path、完整 URL、自定义 Scheme 或正则别名。
- Pattern 负责匹配页面；`CCRouteEntry` 负责一次导航实例的生命周期和返回值。
- Deep Link 外部性由 `CCRouterApp`、平台 Adapter 或受控 Host 入口写入的内部 Origin 决定，不根据 URL 形态或业务埋点 Source 推断；重定向必须继承原始 Origin。
- Core、Intent 和 Definition 不依赖 Flutter、`BuildContext` 或 `go_router`。
- 默认提供 GoRouter Adapter，同时允许自定义 Adapter 消费同一份中立 Definition。
- 路由展示契约区分普通 Page、模态 BottomSheet 与 Dialog；Page 和 Dialog 分别声明平台默认、Material 或 Cupertino Route 类型。
- 完整设计见 [CCRouter 路由子系统设计](CCRouter-route-design.md)。

### 10.2 路由声明

```dart
@CCRoute<AddressResult>(
  id: 'address.select',
  patterns: [CCPathPattern('/address/select', primary: true)],
  visibility: CCRouteVisibility.exported,
)
final class AddressSelectPage {
  const AddressSelectPage({required this.cityId});

  final String cityId;
}
```

支持：

```text
/order/detail/:orderId
/order/detail/1001?source=cart
ccrouter://order/detail/1001?source=cart
https://m.example.com/order/detail/1001?source=cart
```

Path Pattern、结构化 URI Pattern 和完整 Regex Pattern 按固定优先级解析；Query 与命名捕获参数交给生成的 Route Codec，业务 API 不暴露参数 Map：

```text
URL -> RouteCodec -> Typed Route Args -> Route Factory -> Widget
```

完整 URL 不天然等于外部 Deep Link，普通 Path 也不天然等于内部导航。类型安全 Intent 和应用内 `open` 使用内部 Origin；Universal Link、App Link、自定义 Scheme、通知 URI 和扫码输入通过受控 Ingress 使用外部 Origin 并执行 `CCDeepLinkPolicy`。业务可填写的导航 Source 只用于埋点，不能改变该信任属性。

当前基础实现已经提供 Adapter-neutral 的 `CCNavigator`、主 Pattern 地址生成、Runtime 导航请求、Adapter 生命周期、Pure Dart 内存 Adapter、可选 `CCRouterApp`、固定来源的 `CCDeepLinkIngress` 和独立的 `ccrouter_go_router` 适配器。GoRouter 适配器覆盖 Page 路由、BottomSheet/Dialog 模态 Page、已有 `ShellRoute` 的 Outlet Navigator 及基础栈操作；Shell 自身生成、`StatefulShellRoute` 分支编排和平台事件监听仍在后续 Flutter 集成阶段接入，Core 不保存或解释 Flutter 对象。模态路由必须在绑定的 `GoRoute.pageBuilder` 中显式返回 `CCGoRouterBottomSheetPage` 或 `CCGoRouterDialogPage`，并声明匹配的 `presentationKind`，适配器不会把普通 Page 静默降级为模态展示。
GoRouter Adapter 通过 `navigatorKeys` 接收应用拥有的 Outlet Navigator，可将带有
`shellId`/`navigatorOutlet` placement 的子路由绑定到已有 `ShellRoute` Navigator；
未提供对应 key 时初始化会拒绝。Shell 自身和 `StatefulShellRoute` 分支编排仍待专用
Shell binding 接入，这避免导航请求错误地落到根 Navigator。

小屏列表、大屏左列表右详情属于自适应主从布局（Master-Detail/List-Detail），应使用同一组类型安全的列表/详情 Route Contract。小屏采用单列 Navigator 栈，大屏采用显式 List Outlet 与 Detail Outlet；只有在两个区域需要独立导航历史时才由 Shell 承载两个 Navigator。底部 Tab 等多个长期并行分支才使用 `StatefulShellRoute`，不能把所有主从布局都建模为 Stateful Shell。

路由目的地必须与设备形态解耦。`CCRoutePlacement` 负责显式声明 parent、Shell、Navigator Outlet 和 route kind；后续再以 Window Size Class（compact/medium/expanded）、折痕与铰链等 Display Feature、Fold Posture、多 Window/Display Host、Adaptive Presentation Policy 和状态恢复标识描述呈现条件。相同 Route Contract 根据窗口条件选择单列、双栏、多 Pane、Dialog、Bottom Sheet 或全屏呈现。导航状态应按 Window/Host 隔离，而不是只依赖进程级单例栈。第一阶段优先实现窗口尺寸自适应、主从双 Outlet、Modal 自适应和旋转/调整大小状态保持，随后扩展折叠姿态、多窗口、指定 Pane 深链、Web 历史、PiP 和预测返回。

复杂对象默认不直接塞进 URL。需要传递内存对象时可使用 `extra`，但必须标记 `localOnly`，不可用于 Deep Link、跨 Isolate 或状态恢复。

### 10.3 返回结果

调用方：

```dart
final result = await CCRouter.navigator.push<AddressResult>(
  AddressRoutes.select(cityId: '310000'),
  context: context,
);
```

页面：

```dart
CCRouter.navigator.pop(
  result: AddressResult(addressId: selected.id),
  context: context,
);
```

每次导航都创建独立的 `CCRouteEntry<R>`：

```text
CCRouteEntry<R>
├── routeEntryId
├── normalizedUri
├── routeDescriptor
├── resultCompleter<R?>
├── routeScope
├── navigatorOutlet
├── traceContext
└── lifecycleState
```

同一 Path 同时打开两次时，两个 `routeEntryId` 各自对应自己的 Future，不会串结果。

返回规则：

- `pop(value)`：正常返回值。
- 系统返回、手势取消或无值返回：Future 完成 `null`。
- 路由不存在、参数非法或返回类型不匹配：抛出标准导航错误。
- RouteEntry 被强制移除时，必须明确是“取消”还是“外部移除”，并在诊断记录中区分。

### 10.4 路由生命周期

```text
created -> resolving -> pushed -> visible -> hidden
        -> visible -> popping -> removed -> disposed
```

页面 rebuild、被其他页面暂时覆盖或 App 进入后台不等于 Route Scope 销毁。只有 RouteEntry 永久移除时才销毁。

交互式返回手势在确认 Pop 前不得销毁 Scope。

### 10.5 导航操作

v0.1 最小 API：

```dart
CCRouter.navigator.push<R>(intent, context: context, source: ...);
CCRouter.navigator.replace<R>(intent, context: context, source: ...);
CCRouter.navigator.go(intent, context: context, source: ...);
CCRouter.navigator.reset(intent, context: context, source: ...);
CCRouter.navigator.open(uri, context: context, source: ...);
CCRouter.navigator.pop<R>(result: result, context: context);
CCRouter.navigator.canPop(context: context);
```

第一版优先保证一个 Flutter Router/Navigator 2.0 Adapter 的行为一致性，其他导航后端通过适配器扩展。

---

## 11. 通信模型

### 11.1 Command

请求执行一项有副作用的操作，通常一对一并返回结果：

```dart
final order = await CCRouter.command(
  CreateOrderCommand(cartId: cartId),
);
```

Command 应支持幂等键、Deadline、取消、重试策略和标准错误。

### 11.2 Query

请求读取数据，不表达业务副作用：

```dart
final user = await CCRouter.query(CurrentUserQuery());
```

### 11.3 Action

请求执行可被多个处理器响应的动作，允许优先级、短路和处理报告：

```dart
final report = await CCRouter.action(ShowCampaignAction());
```

Action 只能触发预先声明的白名单能力。远程配置不得提供任意方法名。

### 11.4 Event

表示已经发生的事实，一对多发布，不能依赖订阅者返回业务结果：

```dart
CCRouter.event(OrderCreatedEvent(order.id));
```

v0.1 默认：

- 不持久化、不重放。
- 订阅者相互隔离，某个订阅者失败不阻塞其他订阅者。
- 需要当前状态时使用 Service/Query/State，不使用 Sticky Event 模拟。
- 订阅生命周期绑定 Scope。

### 11.5 不同语义的边界

```text
进入页面             Route
执行一次操作         Command
查询数据             Query
调用长期能力         Service
触发预埋动作         Action
通知已发生事实       Event
```

---

## 12. 拦截器与调用链

### 12.1 统一调用上下文

```text
CCInvocationContext
├── invocationId
├── traceId
├── spanId
├── parentSpanId
├── callerComponent
├── targetComponent
├── operationType
├── scopeId
├── deadline
├── cancellationToken
└── metadata
```

### 12.2 调用流程

```text
创建 InvocationContext
        -> 前置 Middleware
        -> 解析目标
        -> 权限/状态检查
        -> 目标 Handler 或 Service Proxy
        -> 后置 Middleware
        -> 记录成功、失败、取消或降级
```

Route、Command、Query、Action 和 Service Proxy 可以拥有不同的类型化 Middleware 接口，但共享 Trace、超时和错误基础设施。

拦截器允许：

- 继续执行。
- 短路并返回结果。
- 重定向 Route。
- 中断并返回标准错误。

顺序必须由生成后的稳定顺序确定。不能允许拦截器既不继续也不结束调用；框架应检测超时和未闭合调用。

### 12.3 调用链日志

一次调用应可还原为树：

```text
Trace: checkout.submit
├── Route: /checkout
├── Command: CreateOrder
│   ├── Service: Inventory.reserve
│   └── Service: Payment.pay
│       └── NativeBridge: PaymentSDK
└── Event: OrderCreated
    ├── Subscriber: Analytics
    └── Subscriber: Coupon
```

每个 Span 至少记录开始时间、结束时间、耗时、能力 ID、调用方、目标、状态、错误码、重试/重定向/降级信息和 Scope。

参数和返回值默认只记录类型和安全摘要，必须支持脱敏、截断和字段白名单。

跨 Isolate、Native 或 H5 时在 Envelope/Channel 元数据中显式传递 TraceContext。日志系统故障不能影响业务调用。

### 12.4 Trace、Metric、Audit 区分

```text
Trace   解释一次调用为什么失败
Metric  观察整体耗时、成功率和资源开销
Audit   记录敏感操作的主体、时间和结果
```

---

## 13. 初始化任务编排

### 13.1 任务描述

每个 InitTask 至少包含：

- 全局唯一任务 ID。
- 所属组件和 Scope。
- `dependsOn` 依赖。
- `trigger/gate` 触发条件。
- 同步/异步和执行位置。
- 是否只执行一次、每会话一次或可重复执行。
- 超时、重试和失败策略。
- 是否属于启动关键路径。

### 13.2 依赖与触发分离

```text
依赖：config 必须先于 analytics
触发：用户同意隐私协议后 analytics 才可运行
```

典型 Gate：

```text
appStarted
firstFrameRendered
privacyGranted
sessionOpened
remoteConfigReady
appForeground
```

### 13.3 状态与失败策略

```text
blocked -> ready -> running -> succeeded
                           -> failed
                           -> skipped
```

任务支持：

```text
critical       失败阻止关键阶段完成
optional       记录失败，其他任务继续
degradable     切换备用能力
retryable      满足条件后允许重试
```

生成阶段必须检测未知依赖和循环依赖。运行时必须支持按 Gate 触发依赖任务的调度。

---

## 14. 错误、取消、超时与并发

### 14.1 标准错误分类

```text
CCRouterNotInitializedError
RouteNotFoundError
RouteParameterError
RouteResultTypeMismatchError
ServiceNotFoundError
CapabilityUnavailableError
PermissionDeniedError
InvocationTimeoutError
InvocationCancelledError
HandlerFailedError
InitializationFailedError
ScopeClosedError
ContractVersionError
```

错误应包含稳定错误码、调用 ID、Trace ID、能力 ID、可安全展示的消息和原始原因（仅在调试或受控日志中保留）。

### 14.2 取消和 Deadline

- 异步跨组件调用必须支持取消和 Deadline。
- Cancellation 向下游 Service、Command、Native Bridge 传播。
- Scope 关闭自动取消该 Scope 的未完成调用。
- 取消与业务失败必须区分。

### 14.3 并发与幂等

框架应预留或提供：

- 初始化 Single-flight。
- Command 幂等键和请求去重。
- 最大调用深度和循环检测。
- Event 订阅者的并行/串行策略。
- 重试次数、退避和不可重试错误声明。

---

## 15. 测试、Mock 与独立运行

### 15.1 测试 Runtime

由于公开 API 是静态的，测试不能直接修改永久全局注册表。`CCRouterTest.run` 创建隔离的 Test Runtime Overlay：

```dart
await CCRouterTest.run(
  components: [OrderComponentManifest.generated],
  overrides: [
    CCServiceOverride<PaymentService>.factory(
      create: (_) => FakePaymentService(),
    ),
  ],
  body: () async {
    final service = CCRouter.service<PaymentService>();
    // 组件业务代码不需要测试分支。
  },
);
```

支持：

```dart
CCServiceOverride<T>.value(instance)
CCServiceOverride<T>.factory(create: ...)
CCRouterTestHost(initialLocation: ...)
```

具有 Route 或 Session Scope 的替身必须使用 Factory，避免多个 Scope 共享同一个有状态实例。

### 15.2 测试结束清理

测试 Runtime 结束时自动：

- 取消未完成调用。
- 关闭 Route、Session 和 Component Scope。
- 销毁 Mock 和订阅。
- 检查未闭合 Trace。
- 检查资源泄漏。
- 恢复原 Active Runtime。

### 15.3 独立运行

每个组件应能在轻量 Test Host/Sandbox 中运行：

```text
ComponentTestHost
├── selected component manifest
├── Fake Service Registry
├── Test Navigation Adapter
├── Lifecycle Simulator
└── InitTask Runner
```

“独立运行”“独立发布”和“动态加载”是三个不同目标。v0.1 只要求前两者中的开发/测试能力，不承诺动态加载 Dart 代码。

---

## 16. 组件依赖与装配治理

### 16.1 依赖规则

- 业务组件禁止直接依赖其他业务组件实现。
- 组件可以依赖公共契约包。
- 必需依赖必须在 Manifest 中声明。
- 可选依赖缺失时必须有能力探测或降级策略。
- 检测组件依赖循环和 Scope 依赖倒置。
- 防止公共基础包聚合过多业务模型。

### 16.2 能力可见性

普通能力可以区分组件内部能力和显式导出的跨组件契约。路由使用更严格的双维模型：`component/exported` 控制组件契约可见性，Deep Link Policy 独立控制是否允许外部 URI。跨组件可见、允许外部进入和运行时授权互不等价，具体规则见 [路由子系统设计](CCRouter-route-design.md#9-组件所有权与可见性)。`visibleTo` 由生成器、文档和 CI 执行依赖与导出治理；Runtime 不接收或信任调用方组件 ID，也不把契约可见性作为运行时安全机制。

### 16.3 多产品装配

最终 App 是 Composition Root，决定：

- 装配哪些组件。
- 每个契约选择哪个实现。
- 哪些能力被 Feature Flag 禁用。
- 测试、预发和生产使用哪些 Provider。

运行时配置只能启用/禁用预先声明的能力，不能注册任意实现或执行任意代码。

### 16.4 运行时组件激活与停用（后续）

后续支持对已经编译进 App、且已由 Manifest 预先声明的组件进行运行时激活和停用。公开 API 使用 `activateComponent` / `deactivateComponent`，不使用容易被理解为下载或删除代码的 `install` / `uninstall`。

该能力不包含动态下载或加载新的 Dart 代码。实现前必须具备以下基础：

- 每项 Provider、Handler 和其他能力都记录所属组件。
- Component Scope 能够独立取消调用并按逆依赖顺序销毁资源。
- 激活时检查必需依赖，并按依赖顺序原子地开放能力。
- 停用时先拒绝新调用，再等待或取消执行中的调用。
- 存在已激活依赖方时拒绝停用，除非调用方明确选择级联策略。
- 停用完成后清除该组件拥有的注册、实例、订阅和诊断状态。

在上述能力完成前，组件集合只允许在 `CCRouter.initialize()` 时确定；不得通过简单增加 `unregister()` 绕过生命周期和依赖治理。

---

## 17. Flutter 边界

### 17.1 BuildContext

`BuildContext` 只属于 Flutter UI 适配层，不进入 Core Runtime 的核心契约。页面实现可以正常使用 Context 处理主题、MediaQuery 和局部 Widget 关系，但 CCRouter 的 Service、Command、Query、Action、Event、InitTask 和 Trace API 不要求它。

### 17.2 Navigator 与多导航栈

导航适配器应明确 Navigator Outlet/Scope，不能依赖“当前顶部 Navigator”猜测目标。RouteEntry 需要记录所属 Outlet 和唯一 ID。

### 17.3 原生能力

Android/iOS SDK、权限和 MethodChannel/Pigeon 应通过显式 Service 或 Command 契约接入。跨平台错误、超时、取消和 TraceContext 需要统一转换。

---

## 18. 可观测性与诊断 API

v0.1 先提供机器可读诊断接口，图形化 DevTools 后续实现：

```dart
CCRouter.diagnostics.recentTraces();
CCRouter.diagnostics.findByTraceId(traceId);
CCRouter.diagnostics.registeredCapabilities();
CCRouter.diagnostics.initializationTimeline();
CCRouter.diagnostics.exportReport();
```

诊断报告应包含：

- 当前组件和能力注册表。
- Route 栈和 RouteEntry 状态。
- Service 实例及其 Scope。
- 初始化 DAG、耗时和失败节点。
- 调用链、慢调用和超时。
- 重复注册、覆盖和降级记录。

---

## 19. v0.1 最小实现范围

建议第一阶段完成一条端到端纵向链路，而不是同时铺开所有功能：

1. Component Manifest 和生成 Component Registrar。
2. Route 注册、Path/URI/Regex Pattern 匹配、Path/Query Codec。
3. `CCRouter.navigator` 及 `push<T>()`、`replace()`、`go()`、`open()`、`pop<T>()`、`maybePop()`、`popAndPush()`、`popUntil()` 和 `pushAndRemoveUntil()`。
4. App、Session、Route 三种 Scope。
5. 强类型 Service Registry 和构造函数 Factory。
6. Command/Query 调度及基础 Middleware。
7. 基础 Action 和 Event。
8. InitTask DAG、Gate 和失败策略。
9. 标准错误、Deadline 和 Cancellation。
10. 自动 Trace、内存诊断记录和脱敏策略。
11. `CCRouterTest.run`、Service Override 和独立 Test Host。
12. 生成冲突检查、依赖检查和契约文档。

`*Named` 方法不纳入 API，`replaceRouteBelow`、`removeRoute` 和 `removeRouteBelow` 在 RouteEntry 句柄与结果语义明确前保持 Adapter 内部能力。`popUntilWithResult` 仍暂缓，待定义多 RouteEntry 结果传递和 Pop 拒绝语义后再实现。

暂缓图形化 DevTools、Native/Isolate RPC、多 Engine 共享、事件持久化和动态交付。

---

## 20. 验收场景

以下场景必须在架构测试中成立：

1. 订单组件调用支付契约，但不引用支付实现。
2. 同一服务存在多个实现时，默认实现和命名实现都能确定性解析。
3. 重复 Route、Service、Task ID 在生成阶段失败。
4. 标准 Path、完整 URL、自定义 Scheme、完整正则和 Query 可以解析为类型化参数。
5. 同一 URL 同时打开两次，两个调用方收到各自返回值。
6. 用户退出登录后，Session Service 被销毁，旧代理不能调用新会话。
7. 重新登录后，Session Service 按 Factory 创建新实例。
8. Route 永久移除后，Route Scope Service 按逆依赖顺序销毁。
9. 用户同意隐私协议后，相关 InitTask 按依赖顺序执行。
10. 一个可选组件初始化失败时，关键组件仍可继续启动。
11. Event 某个订阅者失败，不影响其他订阅者。
12. Command 超时或取消能向下游传播，并产生完整 Trace。
13. Mock 覆盖不修改组件业务代码，测试结束后全局状态恢复。
14. 一次下单操作可以还原 Route、Command、Service、Native 调用链。
15. 两个 Test Runtime 同时运行时互不污染。
16. 全部核心 API 在没有 `BuildContext` 的纯 Dart 测试中可调用。

---

## 21. 后续决策点

以下内容在 v0.1 原型验证后冻结：

- Route Contract 与 Widget Factory 的实现验证，语义以路由子系统设计为准。
- `navigate` 的 push/replace/reset 参数模型。
- Event 的默认并行/串行策略。
- Service Proxy 的方法拦截生成范围。
- 多 Navigator Outlet 的声明方式。
- Trace 采样、上报和与后端 OpenTelemetry 的关联方式。
- Native Adapter、Isolate Adapter 的 Envelope Schema。
- 契约版本兼容与废弃策略。

---

## 22. 总结

CCRouter v0.1 采用以下总体路线：

```text
静态 CCRouter 门面
+ 代码生成注册
+ 强类型契约
+ URL Navigator 与 Future 返回值
+ Service/Session/Route Scope
+ Command/Query/Action/Event 语义分层
+ InitTask DAG 与自定义 Gate
+ 统一 InvocationContext 和自动 Trace
+ 隔离 Test Runtime 与 Mock Overlay
```

核心边界是：**对开发者提供简单统一的静态 API，对内部保持强类型、可检查、可追踪、可治理的组件运行时。**
