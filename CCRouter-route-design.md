# CCRouter 路由子系统设计

## 文档状态

- 版本：v0.1 Draft
- 状态：设计评审，尚未实现
- 适用范围：Flutter 应用及其组件化路由契约
- 默认导航后端：`go_router`
- 核心约束：业务跳转统一通过 `CCRouter.navigator`，Core 不依赖 Flutter、`BuildContext` 或 `go_router`

本文档细化 [CCRouter v0.1 架构设计](CCRouter-v0.1-architecture.md) 中的路由部分。文中的 API 用于冻结语义和实现边界，不表示当前仓库已经提供这些 API。

---

## 1. 目标

路由子系统需要解决以下问题：

1. 组件通过类型安全的契约跳转，不直接依赖目标页面实现。
2. 一个路由可以拥有主 Path、历史别名和外部链接 Path，并保持调用端与接收端一致。
3. Path、Query 和内存 Extra 参数由生成代码编码、解析并注入页面。
4. 默认适配 `go_router`，同时允许实现其他导航适配器。
5. 路由注册、拦截、生命周期、埋点和诊断使用同一条调用链。
6. 路由契约按组件和可见性生成，不创建包含全部业务路由的全局 `Routes` 类。
7. 生成机器可读及开发者可读的路由文档。
8. 为后续 `activateComponent` / `deactivateComponent` 保留路由所有权和生命周期信息。

## 2. 非目标

v0.1 不包含：

- 运行时下载或加载未编译进 App 的 Dart 页面。
- 在 Core 中重新实现 Flutter Navigator 或 `go_router` 的匹配算法。
- 通过任意字符串代码、反射或 `Map<String, dynamic>` 构造页面。
- 同时内置 Navigator 1.0、GetX 等多个后端。
- 把路由可见性当作登录、权限或数据安全机制。
- 自动采集和上报全部路由参数。

---

## 3. 核心原则

### 3.1 稳定 ID 与 Path 分离

每个路由必须有一个稳定且全局唯一的 `routeId`。Path 是可变的寻址规则，不是路由身份。

```text
routeId: orders.detail
primaryPath: /orders/:orderId
aliases:
  - /order/detail/:orderId
  - /o/:orderId
```

修改主 Path 或增加别名不能改变 `routeId`。注册冲突、埋点、Trace、组件所有权和文档引用均使用 `routeId`。

### 3.2 声明、调用和实现分离

```text
@CCRoute 页面声明
        |
        v
类型安全 Route Intent + Codec + Route Definition
        |
        v
组件 Route Registrar
        |
        v
CCRouter.navigator / Route Runtime
        |
        v
CCNavigationAdapter
        |
        +-- CCGoRouterAdapter
        +-- 自定义 Adapter
```

- 生成的 Route API 只构造意图，不执行跳转。
- `CCRouter.navigator` 是业务代码唯一的导航入口。
- Runtime 负责注册、解析、拦截、生命周期、Trace 和埋点。
- Adapter 只负责把已经解析的导航操作映射到具体导航后端。

### 3.3 生成优先

- 不使用 `dart:mirrors` 或运行时反射。
- 参数类型、默认值、可空性和 import 由 Analyzer 解析。
- 生成使用标准 Dart Builder / `build_runner`，支持增量构建。
- 本地构建与 CI 使用同一套分析语义，不提供正确性不同的 fast/full 模式。

---

## 4. 分层与包边界

第一阶段优先在现有包中稳定 Pure Dart 契约和 Runtime：

```text
ccrouter_contracts  Route 注解、Intent、Codec、值类型、错误和 SPI 契约
ccrouter_core       Route Registry、匹配、拦截、RouteEntry、埋点调度
ccrouter            Flutter 业务门面、CCNavigator 和 CCRouterApp
```

需要时再增加：

```text
ccrouter_generator  Analyzer、Builder、生成器和文档导出器
ccrouter_go_router  默认 go_router Adapter
```

`ccrouter` 是面向 Flutter 业务的门面包，可以依赖 Flutter SDK；Pure Dart 使用者依赖 `ccrouter_contracts` 或 `ccrouter_core`。共享页面 Target 先由 `ccrouter` 提供，不额外创建只有少量声明的 `ccrouter_flutter`。

`ccrouter_core` 始终不得依赖：

- Flutter SDK
- `Widget`、`BuildContext`、`Page`
- `GoRouter`、`GoRouterState`、`GoRoute`

---

## 5. 路由声明

建议的声明形式如下：

```dart
@CCRoute<OrderResult>(
  id: 'orders.detail',
  paths: [
    CCPath(
      '/orders/:orderId',
      primary: true,
      constraints: {'orderId': r'\d+'},
    ),
    CCPath('/order/detail/:orderId'),
    CCPath('/o/:orderId'),
  ],
  visibility: CCRouteVisibility.exported,
  visibleTo: ['checkout', 'customer_service'],
  deepLink: CCDeepLinkPolicy.enabled,
  description: '展示订单详情。',
  interceptors: ['auth.required'],
  tracking: CCRouteTracking(eventName: 'order_detail_view'),
)
final class OrderDetailPage {
  const OrderDetailPage({
    required this.orderId,
    @CCQueryParam() this.tab,
    @CCExtraParam() this.snapshot,
  });

  /// 订单 ID。
  @CCTrackingParam(name: 'order_id')
  final int orderId;

  /// 首次展示的标签。
  final String? tab;

  /// 仅用于应用内跳转的订单快照。
  final OrderSnapshot? snapshot;
}
```

注解必须只接受编译期常量，不允许注入原始 Dart 代码字符串。

### 5.1 路由声明字段

| 字段 | 必填 | 语义 |
| --- | --- | --- |
| `id` | 是 | 全局唯一且稳定的路由身份 |
| `paths` | 是 | 一个主 Path 和零个或多个匹配别名 |
| `visibility` | 否 | 默认仅组件内部可见 |
| `visibleTo` | 否 | 对外导出时允许消费的组件 ID |
| `deepLink` | 否 | 是否允许从 App 外部解析 |
| `description` | 否 | 文档、IDE 提示和诊断说明 |
| `interceptors` | 否 | 有序的路由级拦截器 ID |
| `tracking` | 否 | 稳定埋点事件名及静态标签 |
| `presentation` | 否 | 中立的展示意图，不直接表达 `MaterialPage` 等类型 |

### 5.2 构造器选择

- 默认分析未命名构造器。
- 页面存在多个可用构造器时必须显式标记目标构造器。
- 生成阶段拒绝私有但无法通过同 library 访问的构造器。
- 生成代码需要访问私有实现时使用 `part` / `part of`，不能为了生成器提升内部 API 可见性。

---

## 6. 多 Path 与双端统一

### 6.1 主 Path 和别名

每个路由只能有一个可反向生成的主 Path：

- 业务调用生成地址时始终使用主 Path。
- 内部旧链接、Web URL 和 Deep Link 可以匹配别名。
- 匹配别名后，Runtime 仍解析为同一个 `routeId`。
- 是否把别名重定向到主 Path 由 Adapter 策略决定。

### 6.2 内部地址与外部 URI

Runtime 先把外部 URI 归一化为内部 Location：

```text
https://m.example.com/orders/100?tab=items
ccrouter://orders/100?tab=items
/orders/100?tab=items
                  |
                  v
routeId = orders.detail
arguments = OrderDetailRouteArgs(orderId: 100, tab: items)
```

Scheme 和 Host 白名单属于应用级 Deep Link 配置；路由只声明自己是否允许外部进入。外部 URI 的完整原文默认不进入日志或埋点。

### 6.3 正则约束

优先支持“Path 模板 + 命名参数正则约束”：

```dart
CCPath(
  '/users/:userId',
  constraints: {'userId': r'[1-9]\d*'},
)
```

生成器必须检查：

- 约束只能引用模板中存在的参数。
- 正则能够编译。
- 不允许捕获组影响参数索引；应使用非捕获组。
- 多个 Path 之间不能形成无法确定优先级的歧义匹配。

完整任意正则不是可逆的，不能独立作为主 Path。如果后续支持完整正则，只能作为 `matchOnly` 别名，并且必须同时存在可生成 URL 的主 Path。

### 6.4 匹配顺序

匹配不能依赖注册顺序。生成器和 Runtime 使用固定优先级：

```text
静态 Path
  > 带正则约束的参数 Path
  > 普通参数 Path
  > catch-all Path
```

同优先级存在重叠且无法证明唯一时，应用聚合构建必须失败。

---

## 7. 参数与自动注入

### 7.1 参数来源

参数分为三类：

| 来源 | 用途 | 可用于 Deep Link | 持久化 |
| --- | --- | --- | --- |
| Path | 路由身份所需参数 | 是 | 是 |
| Query | 可选筛选、入口和展示参数 | 是 | 是 |
| Extra | 复杂内存对象或优化数据 | 否 | 否 |

自动推断规则：

1. 构造参数名出现在 Path 模板中时，自动视为 Path 参数。
2. Query 参数必须通过注解或生成配置显式声明。
3. Extra 参数必须显式标记，不允许自动把未知对象放入 Extra。
4. 一个参数不能同时来自多个来源。

### 7.2 Codec

每个路由生成独立的类型安全 Codec：

```dart
abstract interface class CCRouteCodec<A> {
  A decode(CCEncodedRouteArguments input);

  CCEncodedRouteArguments encode(A arguments);
}
```

Codec 负责：

- Path 参数转义与解码。
- Query 参数的缺失、重复值和默认值处理。
- `String`、`int`、`double`、`bool`、`enum`、可空值及集合的标准转换。
- 通过显式注册的字段 Codec 支持自定义值类型。
- 输出带路由 ID、参数名和安全原因的 `CCRouteParameterError`。

业务 API、Route Intent 和拦截器不暴露 `Map<String, dynamic>`。Map 只允许出现在生成器内部或受控的编码边界。

### 7.3 Extra 约束

- Extra 只能用于当前进程内导航。
- 外部 URI、状态恢复和跨 Isolate 解析时 Extra 必须为空。
- 页面不得依赖 Extra 才能完成 Deep Link 的基本展示。
- Adapter 必须按 `routeEntryId` 绑定 Extra，不能只按 Path 建立全局缓存。

---

## 8. 类型安全 Intent 与统一调用

生成器为每个组件生成路由 API：

```dart
abstract final class OrderRoutes {
  /// 创建订单详情导航意图。
  static CCRouteIntent<OrderResult> detail({
    required int orderId,
    String? tab,
    OrderSnapshot? snapshot,
  }) => _OrderDetailIntent(
    orderId: orderId,
    tab: tab,
    snapshot: snapshot,
  );
}
```

生成类型只创建不可变 Intent，不包含 `push()`、`replace()` 或 Adapter 调用。

业务统一通过 `CCRouter.navigator`：

```dart
final OrderResult? result = await CCRouter.navigator.push<OrderResult>(
  OrderRoutes.detail(orderId: 100, tab: 'items'),
  context: context,
  source: const CCNavigationSource.feature('home.order_banner'),
);
```

建议的 Flutter 门面 API：

```dart
abstract final class CCRouter {
  static CCNavigator get navigator;
}

abstract interface class CCNavigator {
  Future<R?> push<R>(
    CCRouteIntent<R> intent, {
    BuildContext? context,
    CCNavigationSource? source,
  });

  Future<R?> replace<R>(
    CCRouteIntent<R> intent, {
    BuildContext? context,
    CCNavigationSource? source,
  });

  Future<void> go(
    CCRouteIntent<void> intent, {
    BuildContext? context,
    CCNavigationSource? source,
  });

  Future<void> reset(
    CCRouteIntent<void> intent, {
    BuildContext? context,
    CCNavigationSource? source,
  });

  Future<void> open(
    Uri uri, {
    BuildContext? context,
    CCNavigationSource? source,
  });

  void pop<R>({R? result, BuildContext? context});

  bool canPop({BuildContext? context});
}
```

`push<R>` 和 `replace<R>` 返回 `Future<R?>`。系统返回、无值 Pop 或 RouteEntry 被允许取消时完成 `null`；解析、拦截或 Adapter 失败时抛出标准错误。

`BuildContext` 只在调用瞬间用于解析最近的 Navigator Outlet，解析完成后不得保存或传入 Core。未传 Context 时使用 Adapter 配置的默认根 Outlet。非 Widget 调用方后续可以通过显式 Outlet 引用选择非根导航栈。

不提供 `CCRouter.push()` 等重复快捷入口，也不提供绕过 `CCRouter.navigator` 直接执行生成 Intent 的公开方法。

---

## 9. 组件所有权与可见性

### 9.1 可见性模型

路由默认只对所属组件可见：

```dart
enum CCRouteVisibility {
  component,
  exported,
}
```

- `component`：只生成组件内部调用入口。
- `exported`：额外生成稳定的对外路由契约。
- `visibleTo`：可选的允许消费组件列表。
- 消费方必须显式依赖提供方组件或其契约包。

Deep Link 可见性独立于组件可见性。`exported` 不表示允许外部 URI；允许 Deep Link 也不表示绕过权限拦截器。

### 9.2 生成文件布局

```text
order_component/lib/
├── order_route_contracts.dart
└── src/generated/
    ├── order_routes.internal.g.dart
    ├── order_route_codecs.g.dart
    └── order_route_registrar.g.dart
```

- `order_route_contracts.dart` 只导出 `exported` 路由及其参数、结果契约。
- 内部文件包含组件全部路由，但不从公共 barrel 导出。
- 应用级生成器不生成暴露全部路由的全局 `Routes` 类。
- Registrar 注册全部已装配路由，与业务 API 的可见性裁剪相互独立。

Dart 没有 package-private 或 friend package。`lib/src`、显式 export、`implementation_imports` lint、组件依赖检查和 CI 共同形成工程边界，但不是安全边界。真正的授权仍由 Runtime 和拦截器完成。

### 9.3 动态组件关系

每个 Route Definition 必须记录 `ownerComponentId`。组件停用后：

- 新导航请求返回 `CCRouteUnavailableError`，或由未来的激活策略先调用 `activateComponent`。
- 已存在 RouteEntry 的处理由停用策略决定，不能静默销毁。
- Registrar、路由定义和 Adapter binding 必须按组件成组移除。

v0.1 只建立所有权模型，不实现运行时激活和停用。

---

## 10. Route Definition 与 Registry

中立 Route Definition 至少包含：

```text
routeId
ownerComponentId
paths
visibility
visibleTo
deepLinkPolicy
codec
interceptorIds
trackingDefinition
presentation
parentRouteId / shellId / navigatorOutlet
description / deprecation
```

Registry 的组件作者接口只允许注册：

```dart
CCRegistry.registerRoute(definition);
CCRegistry.registerRouteInterceptor(id, factory);
```

Registrar 不能解析路由、导航、访问 Adapter 或关闭 Runtime。

Registry 在冻结前检查：

- 重复 Route ID。
- 重复或缺失主 Path。
- 重复 Interceptor ID。
- 未声明的所属组件。
- 未知父路由、Shell 或 Outlet。
- 非法可见组件。
- 静态可判断的 Path 冲突。

---

## 11. 两层拦截器

业务层只提供两层导航拦截器：

```text
Global Interceptors
        |
        v
Route Interceptors
        |
        v
Navigation Adapter
```

组件激活、Route Registry 状态和参数校验属于 Runtime 前置检查，不形成第三层业务拦截器。

拦截结果使用明确语义：

```text
proceed   继续，可携带修改后的 Intent
redirect  改为新的 Intent，并保留原始导航上下文
cancel    终止导航，返回标准取消原因
```

规则：

- Global 按稳定 ID 排序或显式顺序执行。
- Route Interceptor 按注解声明顺序执行。
- Interceptor 可以异步执行并接收取消信号与 Deadline。
- Redirect 重新进入必要的解析和拦截流程。
- Runtime 必须检测重定向循环并限制最大重定向次数。
- Interceptor 不允许直接调用 Adapter。
- 错误、取消和重定向均进入 Trace 与路由埋点事件。

---

## 12. Navigation Adapter

`CCNavigationAdapter` 是框架扩展 SPI，不是普通业务 API。它接收已经解析的 RouteEntry 和导航操作：

```text
push
replace
go
reset
pop
canPop
```

Adapter 必须报告：

- RouteEntry 已加入或移出栈。
- RouteEntry 可见、被覆盖或重新可见。
- 系统返回、手势返回和外部栈修改。
- 后端无法支持的路由能力。

默认 `CCGoRouterAdapter` 负责：

- 把中立 Route Definition 转换为 `GoRoute`/Shell 路由结构。
- 注册主 Path 与别名。
- 关联 Path、Query、Extra 和 RouteEntry。
- 将 `go_router` 栈变化映射为统一生命周期。
- 将平台传入 URI 交给 `CCRouter.open` 的内部管线处理。

Generator 不直接生成 `GoRoute`。自定义 Adapter 消费同一份 Definition 和 Intent。

### 12.1 Shell 与多导航栈

Shell 关系必须显式声明，不能通过 `/index/` 等 Path 前缀猜测：

```text
parentRouteId
shellId
navigatorOutlet
routeKind
```

Adapter 初始化时声明能力集合。路由要求 Shell、透明页面或自定义转场而 Adapter 不支持时，初始化必须失败，不能静默降级。

### 12.2 BuildContext 与 Outlet 解析

- 传入 `BuildContext` 时，Flutter 门面解析距离该 Context 最近的 CCRouter Outlet。
- 未传 Context 时使用 Adapter 初始化时声明的默认根 Outlet。
- Context 不进入 Intent、Route Definition、RouteEntry 或 Core Runtime。
- Context 已失效、未挂载或无法解析 Outlet 时返回标准导航错误。
- Shell 和嵌套 Navigator 必须通过显式 Outlet 关系确定，不能退回全局 Context 猜测。

### 12.3 CCRouterApp

`CCRouterApp` 是包裹 Flutter App 的集成宿主：

```dart
CCRouterApp(
  child: MaterialApp.router(
    routerConfig: navigationAdapter.router,
  ),
);
```

它负责：

- 安装 Flutter App 生命周期监听。
- 提供供页面 Context 查询的 Inherited 路由作用域。
- 绑定默认根 Outlet、Navigator Observer 和 Adapter 生命周期。
- 将 Flutter 页面挂载关系关联到 RouteEntry。
- 宿主销毁时释放 Flutter 侧订阅和引用。

`CCRouterApp` 不保存所谓全局 `BuildContext`。Wrapper Context 可能位于 `MaterialApp` 或 Navigator 上方，也可能在重建后失效；无 Context 导航必须使用 Adapter 持有的 `GoRouter` 或根 `navigatorKey`。

---

## 13. RouteEntry 与生命周期

每次导航创建独立 RouteEntry：

```text
CCRouteEntry<R>
├── routeEntryId
├── routeId
├── ownerComponentId
├── normalizedUri
├── arguments
├── navigationContext
├── resultCompleter<R?>
├── routeScope
├── navigatorOutlet
└── lifecycleState
```

统一生命周期：

```text
created -> resolving -> pushed -> visible -> hidden
        -> visible -> popping -> removed -> disposed
```

- Widget rebuild 不改变 RouteEntry 生命周期。
- App 前后台状态与路由显隐是不同事件。
- IndexedStack 非活动分支视为 hidden，但不销毁 Route Scope。
- 交互式返回手势确认前不能销毁 Route Scope。
- 只有 RouteEntry 永久移出导航结构后才能 dispose。
- 页面无需继承框架 State 或混入特定 Widget mixin。

---

## 14. Deep Link

外部导航流程：

```text
Platform URI
  -> Scheme/Host 白名单
  -> Path 匹配
  -> Deep Link 可见性检查
  -> Codec 参数解析
  -> CCRouter 导航管线
  -> 两层拦截器
  -> Adapter
```

安全规则：

- Scheme 和 Host 使用精确配置，不接受隐式通配。
- Route 必须显式启用 Deep Link。
- Query 中未知参数默认忽略还是报错需要由路由策略明确声明。
- 敏感参数不得出现在 URI 中。
- 外部请求不接受 Extra。
- 所有外部导航仍经过权限和登录拦截器。
- 白名单配置必须真实参与解析流程，并有拒绝场景测试。

---

## 15. 路由埋点来源与数据

### 15.1 来源

来源由框架自动信息和业务入口信息组成：

```dart
const CCNavigationSource.feature('home.order_banner');
const CCNavigationSource.deepLink('universal_link');
const CCNavigationSource.notification('order_status_push');
```

框架自动补充：

- 来源 Route ID 和 RouteEntry ID。
- 来源组件 ID。
- 目标 Route ID 和所属组件。
- push、replace、go、reset 或 deepLink 操作。
- `navigationId`、`traceId` 和 Session ID。
- 请求时间、完成时间和耗时。

Redirect 必须保留最初来源和 `navigationId`，同时记录请求路由、实际路由和重定向链。

### 15.2 数据白名单

禁止自动上报全部路由参数。只有显式标记的字段进入埋点投影：

```dart
@CCTrackingParam(name: 'order_id')
final int orderId;
```

生成器只允许安全的基础值或经过显式 Serializer 处理的值。Extra、页面对象、Token、完整 URI 和返回对象默认不进入事件。

### 15.3 事件模型

Runtime 产生以下中立事件：

```text
requested
redirected
blocked
navigationStarted
shown
hidden
completed
failed
```

事件至少包含：

- `navigationId`、`traceId`、RouteEntry ID。
- 请求路由和最终路由。
- 来源、操作和组件信息。
- 安全的静态标签及字段投影。
- 状态、耗时和安全错误码。

### 15.4 Observer

框架不依赖具体埋点 SDK，只暴露只读观察接口：

```dart
abstract interface class CCRouteTelemetryObserver {
  void onRouteEvent(CCRouteTelemetryEvent event);
}
```

- Observer 失败必须隔离，不能阻塞导航。
- 是否批量、采样和上传由应用集成层决定。
- Trace 用于技术诊断，Telemetry 用于产品分析，二者共享关联 ID 但不混为同一接口。

---

## 16. 路由文档生成

生成器输出两种格式：

```text
cc_routes.json
cc_routes.md
```

`cc_routes.json` 用于 CI、跨端工具和文档平台；描述信息作为结构化字段保存，不使用 JSON 注释。`cc_routes.md` 用于开发者阅读。

每条路由包含：

- Route ID、主 Path、别名和正则约束。
- 所属组件、可见性和 `visibleTo`。
- 是否支持 Deep Link。
- 参数名、来源、类型、必填性、默认值和说明。
- 返回类型。
- 两层拦截器中的路由级配置。
- 埋点事件名、允许字段及说明。
- Shell、父路由、Outlet 和展示意图。
- 页面与参数 DartDoc。
- 废弃状态、替代路由和源码位置。

默认生成两类视图：

```text
internal  包含当前应用装配的全部路由
public    只包含对外导出的路由契约
```

文档、Intent、Codec 和 Registrar 必须来自同一份分析模型，不能从 `GoRoute` 或运行时代码反向推导。

---

## 17. 错误模型

路由子系统至少需要稳定错误类型：

```text
CCRouteNotFoundError
CCRouteUnavailableError
CCRouteParameterError
CCRouteVisibilityError
CCRouteResultTypeError
CCRouteRedirectLoopError
CCRouteCancelledError
CCNavigationAdapterError
CCNavigationCapabilityError
```

错误包含安全消息、Route ID、调用或导航 ID 和稳定错误码。原始参数、完整 URI、Extra 和业务返回值不得默认进入错误字符串。

---

## 18. 生成阶段校验

组件级生成必须检查：

- Route ID、Path 和参数声明格式。
- 主 Path 唯一且可反向生成。
- Path 参数与构造参数一致。
- Query/Extra 注解不冲突。
- 参数类型存在可用 Codec。
- Tracking 字段符合隐私与序列化要求。
- 所有生成的公开类型和成员具有 DartDoc。

应用聚合阶段必须检查：

- Route ID 全局唯一。
- 主 Path、别名和正则匹配不存在确定性冲突。
- `ownerComponentId` 和 `visibleTo` 引用有效组件。
- 跨组件路由消费满足依赖和可见性约束。
- Interceptor、Shell、父路由和 Outlet 引用有效。
- Adapter 支持所有已装配路由要求的能力。
- 生成排序稳定，重复构建产物一致。

---

## 19. API 隔离

### 19.1 业务 API

业务组件只使用：

- `CCRouter.navigator`
- 当前组件内部生成的 Routes API
- 依赖组件显式导出的 Route Contracts
- Intent、Source、结果、错误等不可变契约

### 19.2 组件作者 API

组件作者可以使用：

- `CCRoute` 及参数注解
- `CCComponentRegistrar`
- 受限 `CCRegistry`
- Interceptor 契约和公开 Codec 扩展点

### 19.3 Adapter SPI

Adapter 实现者可以使用单独导出的：

- `CCNavigationAdapter`
- RouteEntry 只读快照
- Adapter capability 和生命周期报告接口

业务门面不导出 Runtime 构造、内部 Route Registry、可变 RouteEntry、Scope 或 Adapter 控制器。框架内部跨文件访问使用 library privacy 和 `part` / `part of`。

---

## 20. 实现阶段

### 阶段 A：Pure Dart 路由契约

- Route ID、Path、可见性、Intent、Codec 和错误。
- `CCRegistry.registerRoute`。
- `CCRouter.navigator` 及 `push/replace/go/reset/open/pop/canPop` 门面。
- 内存测试 Adapter。

### 阶段 B：Runtime 管线

- Route Registry 和确定性匹配。
- 两层拦截器及 Redirect 循环检测。
- RouteEntry、返回值和生命周期。
- Trace 与 Telemetry Observer。

### 阶段 C：生成器

- 页面和构造参数分析。
- Intent、Codec、Definition、Registrar 和组件契约生成。
- 跨组件可见性及聚合校验。
- JSON/Markdown 文档导出。

### 阶段 D：GoRouter Adapter

- 主 Path、别名、Query、Extra 和返回值。
- Shell、Outlet 和生命周期同步。
- Deep Link 入口。
- 可选 BuildContext 的 Outlet 解析和 `CCRouterApp` 集成。
- Android、iOS、Web 和 OHOS 示例验证。

### 阶段 E：动态组件生命周期

- Route 和 binding 按组件激活、停用。
- 活跃 RouteEntry 的停用策略。
- 自动激活策略和诊断事件。

---

## 21. 验收场景

1. 组件内部路由不会出现在对外契约中。
2. 外部组件只能通过显式导出的类型安全 Intent 调用路由。
3. 所有业务跳转统一经过 `CCRouter.navigator`，无法通过生成 API 绕过拦截器。
4. 一个路由可以通过主 Path、历史别名和允许的 Deep Link 解析为同一个 Route ID。
5. 正则约束失败时返回参数或未匹配错误，不进入页面 Factory。
6. Path、Query 和 Extra 正确注入类型化页面参数。
7. 同一路由打开两次时返回值和 Route Scope 不串联。
8. Global Interceptor 先于 Route Interceptor，Redirect 保留来源并能检测循环。
9. 未激活组件的路由不能导航。
10. Shell 非活动分支触发 hidden，但不销毁 Route Scope。
11. Deep Link 必须同时通过 Host 白名单、路由外部可见性和权限拦截器。
12. 埋点记录来源、重定向链和安全字段，不泄漏 Extra 或完整 URI。
13. Observer 异常不影响导航结果。
14. 自定义 Adapter 与 GoRouter Adapter 消费相同的 Route Definition。
15. 生成的 JSON、Markdown、Intent、Codec 和 Registrar 描述一致。
16. 所有公开及内部框架声明遵守 DartDoc 和 API 隔离规则。

---

## 22. 已冻结决策与待评审项

### 已冻结

- 业务导航统一通过 `CCRouter.navigator`。
- `BuildContext` 可选，仅在 Flutter 门面即时解析 Outlet；无 Context 时使用默认根 Outlet。
- `CCRouterApp` 负责 Flutter 集成，但不保存全局 Context。
- Core 保持 Pure Dart。
- 默认使用 GoRouter Adapter，允许自定义 Adapter。
- 生成中立 Definition，不直接生成 `GoRoute`。
- Route ID 与 Path 分离。
- 支持一个主 Path、多个别名和参数正则约束。
- 使用类型安全 Intent 和生成 Codec，不以参数 Map 作为业务契约。
- 路由默认仅组件内部可见，对外契约显式生成。
- 业务拦截器只有 Global 和 Route 两层。
- 埋点来源和字段白名单进入统一 Runtime 管线。
- 输出 JSON 和带 DartDoc 的 Markdown 路由文档。

### 待实现时验证

- 完整 `matchOnly` 正则别名是否进入 v0.1。
- `replace` 对被替换 RouteEntry Future 的标准完成语义。
- Query 未知字段默认忽略还是严格失败。
- `visibleTo` 只做构建期治理，还是同时引入可信调用方身份进行 Runtime 校验。
- GoRouter 对 Shell、多别名和交互式返回的版本兼容范围。

---

## 23. 参考实现取舍

路由生成体验参考 `ff_annotation_route`，但不复制其运行时结构。

采用：

- 页面构造参数分析和 IDE 友好的生成 API。
- 自动类型 import、组件/Package 聚合和稳定生成结果。
- 路由级与全局拦截能力。
- Deep Link、Shell、转场和生命周期扩展点。
- 生成路由元数据及开发文档。

改造：

- 参数辅助 Map 改为类型安全 Intent 和 Route Codec。
- 路由名称改为稳定 Route ID、主 Path 和别名的分离模型。
- 页面生命周期改为 Adapter 上报的 RouteEntry 生命周期。
- 多导航后端改为消费同一份中立 Definition，而不是切换生成模板。
- 多 Package 扫描改为组件 Registrar 和应用聚合校验。

不采用：

- 由 Core Generator 直接生成 `GoRoute` 或其他后端对象。
- `codes`、`exts`、原始 import 字符串和任意代码注入。
- 全局可变参数转换器、全局 Navigator 或生命周期单例。
- 页面必须继承特定 State 或混入 Widget 生命周期类型。
- 自定义 CLI 作为主要生成入口，以及正确性不同的 fast/full 模式。
- 通过 Path 前缀猜测 Shell 结构。
