# CCRouter 路由子系统设计

## 文档状态

- 版本：v0.1 Draft
- 状态：增量实现中，Pattern、导航主链路与内存 Adapter 已实现
- 适用范围：Flutter 应用及其组件化路由契约
- 默认导航后端：`go_router`
- 核心约束：业务跳转统一通过 `CCRouter.navigator`，Core 不依赖 Flutter、`BuildContext` 或 `go_router`

本文档细化 [CCRouter v0.1 架构设计](CCRouter-v0.1-architecture.md) 中的路由部分。文中的 API 用于冻结语义和实现边界，不表示当前仓库已经提供这些 API。

混合路由的隔离、Foreign Route 兼容和第三方 Popup 改造方案见：[CCRouter 混合路由改造设计](CCRouter-hybrid-routing-design.md)。

---

## 1. 目标

路由子系统需要解决以下问题：

1. 组件通过类型安全的契约跳转，不直接依赖目标页面实现。
2. 一个路由可以拥有主寻址 Pattern、历史 Path、完整 URL、自定义 Scheme 和正则别名，并保持调用端与接收端一致。
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

### 3.1 稳定 ID 与寻址 Pattern 分离

每个路由必须有一个稳定且全局唯一的 `routeId`。Path、完整 URL、自定义 Scheme 和兼容正则都是可变的寻址规则，不是路由身份。

```text
routeId: orders.detail
primaryPattern: /orders/:orderId
aliases:
  - https://m.example.com/orders/:orderId
  - ccrouter://orders/detail/:orderId
  - ^https://legacy\.example\.com/order/(?<orderId>\d+)$
```

修改主 Pattern 或增加别名不能改变 `routeId`。注册冲突、埋点、Trace、组件所有权和文档引用均使用 `routeId`。

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
  patterns: [
    CCPathPattern(
      '/orders/:orderId',
      primary: true,
      constraints: {'orderId': r'\d+'},
    ),
    CCPathPattern('/order/detail/:orderId'),
    CCUriPattern('https://m.example.com/orders/:orderId'),
    CCUriPattern('ccrouter://orders/detail/:orderId'),
    CCRegexPattern(
      r'https://legacy\.example\.com/order/(?<orderId>\d+)',
    ),
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
| `patterns` | 是 | 一个可反向生成的主 Pattern 和零个或多个 Path、URI 或正则匹配别名 |
| `visibility` | 否 | 默认仅组件内部可见 |
| `visibleTo` | 否 | 对外导出时允许消费的组件 ID |
| `deepLink` | 否 | 是否允许从 App 外部解析 |
| `description` | 否 | 文档、IDE 提示和诊断说明 |
| `interceptors` | 否 | 有序的路由级拦截器 ID |
| `tracking` | 否 | 稳定埋点事件名及静态标签 |
| `presentation` | 否 | 中立的 Page、底部弹出或 Dialog 展示意图，默认作为平台默认 Page 展示 |

### 5.2 展示模型

展示模型描述路由拥有者确定的展示语义。调用方不能在单次跳转时覆盖它，否则同一个 Route ID 会产生不稳定的生命周期、返回值和埋点语义。

```dart
sealed class CCRoutePresentation {
  const CCRoutePresentation();
}

enum CCPageRouteType {
  platformDefault,
  material,
  cupertino,
}

enum CCPageTransitionType {
  platformDefault,
  fade,
  scale,
  slideFromRight,
  slideFromBottom,
  none,
}

enum CCDialogRouteType {
  platformDefault,
  material,
  cupertino,
}

final class CCPagePresentation extends CCRoutePresentation {
  const CCPagePresentation({
    this.routeType = CCPageRouteType.platformDefault,
    this.transition = CCPageTransitionType.platformDefault,
    this.opaque = true,
    this.fullscreenDialog = false,
  });

  final CCPageRouteType routeType;
  final CCPageTransitionType transition;
  final bool opaque;
  final bool fullscreenDialog;
}

final class CCModalBottomSheetPresentation extends CCRoutePresentation {
  const CCModalBottomSheetPresentation({
    this.isDismissible = true,
    this.enableDrag = true,
    this.isScrollControlled = false,
    this.showDragHandle,
    this.useSafeArea = false,
  });

  final bool isDismissible;
  final bool enableDrag;
  final bool isScrollControlled;
  final bool? showDragHandle;
  final bool useSafeArea;
}

final class CCDialogPresentation extends CCRoutePresentation {
  const CCDialogPresentation({
    this.routeType = CCDialogRouteType.platformDefault,
    this.barrierDismissible,
    this.useSafeArea = true,
  });

  final CCDialogRouteType routeType;
  final bool? barrierDismissible;
  final bool useSafeArea;
}
```

- `CCPageRouteType` 对应页面 Route 家族，不等同于一个固定动画；Flutter 的 Material Route 仍可通过 `PageTransitionsTheme` 按平台适配。
- `CCDialogRouteType` 单独描述 Dialog Route 家族，不能复用 Page Route 类型；`platformDefault` 跟随宿主应用的 Dialog 风格。
- `platformDefault` 由 Adapter、宿主应用类型和目标平台共同决定，普通页面应优先使用该默认值。
- `opaque` 与 Flutter `Route.opaque` 语义一致；透明页面使用 `false`，不再单独定义 `Surface` 枚举。
- `transition` 描述普通页面的进入和返回动画；`slideFromBottom` 用于全屏页面从底部滑入，例如海报分享或预览页。它仍然是普通 Page，不等同于模态 BottomSheet。
- `fullscreenDialog` 只表示全屏对话式 Page，不表示底部弹出。
- `CCModalBottomSheetPresentation` 表示进入导航栈的模态底部弹出，适用于筛选、选择和短表单；不会阻止底层交互的持久 BottomSheet 属于页面内部状态，不声明成 Route。
- `CCDialogPresentation` 表示进入导航栈的居中模态 Dialog，适用于需要跨组件类型安全返回、拦截、埋点或恢复的流程；页面内部临时确认框和错误提示不需要注册成路由。
- Dialog 的 `barrierDismissible` 为 `null` 时保留平台默认行为：Material 默认可点击遮罩关闭，Cupertino 默认不可关闭；显式布尔值用于跨平台覆盖。
- 颜色、圆角、阴影等视觉样式由应用主题和 Adapter 配置，不进入跨组件路由契约。
- Adapter 不支持指定页面类型、透明页面、底部弹出或 Dialog 时，必须在初始化阶段报告能力错误，不能静默改成普通页面。
- GoRouter 绑定需要通过 `ccGoRouterPage(...)` 返回自定义 Page，才能保留非默认转场、透明度或 `fullscreenDialog`；普通 `builder` 不能安全表达这些语义。
- 允许 Deep Link 的底部弹出必须具有可确定的承载页面或父路由；不能在空白导航栈上直接展示。具体关系在 Shell、父路由和 Outlet 模型中声明。

例如海报分享页可以声明为透明的全屏普通 Page，并从底部滑入：

```dart
const posterPresentation = CCPagePresentation(
  transition: CCPageTransitionType.slideFromBottom,
  opaque: false,
  fullscreenDialog: true,
);

GoRoute(
  path: '/poster/share',
  pageBuilder: (_, state) => ccGoRouterPage(
    key: state.pageKey,
    child: const PosterSharePage(),
    presentation: posterPresentation,
  ),
);
```

页面本身需要使用透明背景，才能让下方页面可见；如果需要遮罩、拖拽关闭或底部高度约束，应改用 `CCModalBottomSheetPresentation`。

### 5.3 构造器选择

- 默认分析未命名构造器。
- 页面存在多个可用构造器时必须显式标记目标构造器。
- 生成阶段拒绝私有但无法通过同 library 访问的构造器。
- 生成代码需要访问私有实现时使用 `part` / `part of`，不能为了生成器提升内部 API 可见性。

---

## 6. 多 Pattern 与双端统一

### 6.1 主 Pattern 和别名

每个路由只能有一个可反向生成的主 Pattern：

- 业务调用生成地址时始终使用主 Pattern。
- 主 Pattern 必须是 `CCPathPattern` 或 `CCUriPattern`，不能是 `matchOnly`。
- 内部旧链接、Web URL、自定义 Scheme 和兼容正则可以作为别名。
- 匹配别名后，Runtime 仍解析为同一个 `routeId`。
- 是否把别名重定向到主 Pattern 由 Adapter 策略决定。

### 6.2 Path 与结构化 URI

Runtime 使用 `Uri` 保留并解析地址结构，不把 Scheme 或 Host 拼接进 Path，也不把完整 URL 当成不透明字符串键：

```text
https://m.example.com/orders/100?tab=items
ccrouter://orders/100?tab=items
/orders/100?tab=items
                  |
                  v
routeId = orders.detail
arguments = OrderDetailRouteArgs(orderId: 100, tab: items)
```

- `CCPathPattern` 只比较 URI 的 Path，可同时承接应用内 Path 和任意 Authority 下的同 Path 地址。
- `CCUriPattern` 比较 Scheme、Host、有效端口和 Path；Scheme、Host 不区分大小写，Path 区分大小写。
- Query 独立解析并保留重复值；Fragment 不参与路由身份匹配。
- URI Pattern 必须是包含 Scheme、Authority 和 Host 的绝对 URI，且不能内嵌 Query、Fragment 或 User Info。

Scheme 和 Host 的应用级白名单仍属于 Deep Link 入口配置；`CCUriPattern` 只描述某条路由接受的地址，并不能替代入口信任校验。外部 URI 的完整原文默认不进入日志或埋点。

### 6.3 正则约束

优先支持“Path 模板 + 命名参数正则约束”：

```dart
CCPathPattern(
  '/users/:userId',
  constraints: {'userId': r'[1-9]\d*'},
)
```

生成器必须检查：

- 约束只能引用模板中存在的参数。
- 正则能够编译。
- 多个同层 Pattern 之间不能形成无法确定优先级的歧义匹配。

无法用结构化模板表达的兼容地址使用 `CCRegexPattern`。它对移除 Query 和 Fragment 后的完整地址进行全匹配，命名捕获组作为 Path 参数交给 Codec。完整正则不可逆，因此始终是 `matchOnly`，不能作为主 Pattern，并且路由必须同时存在一个可生成地址的主 Pattern。

### 6.4 匹配顺序

匹配不能依赖注册顺序。生成器和 Runtime 使用固定优先级：

```text
结构化 URI Pattern
  > Path Pattern
  > 完整 Regex Pattern

同一结构化层内：

静态段
  > 带正则约束的参数 Path
  > 普通参数 Path
  > catch-all Path
```

同优先级、同具体度存在重叠且无法证明唯一时，应用聚合构建必须失败；静态阶段无法判断的正则重叠在 Runtime 命中时抛出 `CCRouteAmbiguityError`，绝不使用声明顺序或 Map 迭代顺序选路。

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

### 8.1 栈操作扩展边界

`CCNavigator` 不机械复制 Flutter `Navigator` 的所有方法，而是只暴露具有稳定跨 Adapter 语义的栈操作。建议分阶段支持：

| 方法 | 决策 | 说明 |
| --- | --- | --- |
| `maybePop` | 支持 | 返回 `Future<bool>`，用于系统返回、手势返回和页面自行拒绝返回的场景；不能简单用 `canPop` 加 `pop` 替代。 |
| `popAndPush` | 支持 | 以类型安全 `CCRouteIntent` 作为新页面目标，旧页面结果使用显式的 `Object?`；不暴露 Flutter `Route`。 |
| `popUntil` | 支持 | 通过稳定的 Route ID、RouteEntry ID 或框架提供的只读快照谓词定位保留点，不接受 Flutter `RoutePredicate`。 |
| `popUntilWithResult` | 暂缓后支持 | 需要先定义结果传递给每个被移除 RouteEntry、遇到拒绝 Pop 或没有匹配目标时的完整语义，不能直接照搬第三方扩展方法。 |
| `pushAndRemoveUntil` | 支持 | 是 `pushNamedAndRemoveUntil` 的类型安全替代；新页面使用 Intent，保留条件使用稳定快照谓词。 |
| `replaceRouteBelow` | 暂缓 | 依赖可持久引用某个 RouteEntry 的跨 Adapter 句柄，当前 Runtime 尚未公开该句柄。 |
| `removeRoute` / `removeRouteBelow` | 暂缓 | 属于精确操作某个 RouteEntry 的底层能力；应先设计不暴露 Flutter `Route` 的 `CCRouteEntryHandle` 和结果完成语义。 |
| `popAndPushNamed` / `pushNamedAndRemoveUntil` | 不提供 | 路由系统使用稳定 Route ID、生成的 Intent 和动态 `open(Uri)`，不再增加字符串 Name API。需要动态地址时使用 `open` 组合操作。 |

带目标页面的组合操作 `popAndPush` 与 `pushAndRemoveUntil` 必须作为一个 Runtime 导航请求进入拦截器、埋点和 Adapter 管线，不能由业务代码先调用 `pop` 再调用 `push` 拼接，否则无法保证导航 ID、失败回滚和结果完成的一致性。`maybePop` 与 `popUntil` 虽然没有目标页面，仍必须经过 Runtime 的 Adapter 控制操作边界。Adapter SPI 不向 Core 暴露 `BuildContext`、Flutter `Route` 或 `NavigatorState`。

`push<R>` 和 `replace<R>` 返回 `Future<R?>`。系统返回、无值 Pop 或 RouteEntry 被允许取消时完成 `null`；解析、拦截或 Adapter 失败时抛出标准错误。

`BuildContext` 只在调用瞬间用于解析最近的 Navigator Outlet，解析完成后不得保存或传入 Core。未传 Context 时使用 Adapter 配置的默认根 Outlet。非 Widget 调用方后续可以通过显式 Outlet 引用选择非根导航栈。

当前 Pure Dart 导航主链路已经实现 `push/replace/go/reset/open/pop/canPop`，以及 `maybePop`、类型安全的 `popAndPush`、`popUntil` 和 `pushAndRemoveUntil`；主 Pattern 地址生成、中立 Adapter SPI 和内存 Adapter 也已实现。`BuildContext` 参数与 Outlet 解析将在 `CCRouterApp` 和 GoRouter Adapter 阶段接入；在此之前所有调用使用 Adapter 的默认导航栈，Core 始终不接收 Flutter 类型。

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
- `visibleTo`：可选的允许消费组件列表；为空表示不按组件名单限制公开契约，应仅用于有意提供给全应用的稳定入口。
- 消费方必须显式依赖提供方组件或其契约包。

`CCRouteVisibility` 和 `visibleTo` 只用于生成代码、导出裁剪、文档和 CI 依赖检查。Runtime 不接收可伪造的调用方组件 ID，也不执行调用方可见性校验；它只保存可信的 `ownerComponentId`，用于组件生命周期、诊断、埋点和后续卸载。

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
patterns
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
- 重复、缺失或不可反向生成的主 Pattern。
- 重复 Interceptor ID。
- 未声明的所属组件。
- 未知父路由、Shell 或 Outlet。
- `component` 路由同时声明 `visibleTo` 等定义内冲突。
- 静态可判断的同层 Pattern 冲突。

`visibleTo` 引用、跨组件依赖和导出范围由生成器、应用聚合检查及 CI 验证，不由 Runtime 根据调用方身份执行。

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
- 注册主 Pattern 与别名。
- 关联 Path、Query、Extra 和 RouteEntry。
- 将 `go_router` 栈变化映射为统一生命周期。
- 将平台传入 URI 交给 `CCRouter.open` 的内部管线处理。

Generator 不直接生成 `GoRoute`。自定义 Adapter 消费同一份 Definition 和 Intent。

Adapter 生命周期由 `CCRouterRuntime` 统一拥有：初始化完成前拒绝导航，成功
初始化后才进入 active 状态，Runtime dispose 时调用一次 Adapter dispose；dispose
后不能再次初始化或导航。Session 关闭、组件停用和单个 RouteEntry Pop 只影响各自
的 Scope 或栈状态，不触发 Adapter dispose。GoRouter Adapter 不销毁应用创建的
`GoRouter`，只清理自身的绑定和 RouteEntry 状态。

### 12.1 Shell 与多导航栈

Shell 关系必须显式声明，不能通过 `/index/` 等 Path 前缀猜测：

```text
parentRouteId
shellId
navigatorOutlet
```

这些字段由 `CCRoutePlacement` 承载。普通单栈页面使用默认的 `root` Outlet；
Tab、主从双栏或嵌套 Navigator 必须声明稳定的 `shellId`、`parentRouteId` 和
`navigatorOutlet`。持久化容器通过组件 Registrar 的 `registerShell` 单独注册
`CCShellDefinition`，不再把 Shell 伪装成带 Path 和 Codec 的普通 Route。

`CCShellDefinition` 声明稳定的 `shellId`、Shell 类型、有序 Outlet 列表和默认
Outlet。`CCShellType.singleNavigator` 对应一个共享历史的嵌套 Navigator；
`CCShellType.statefulBranches` 对应多个保持独立历史的分支。Stateful Shell 的 Outlet
顺序属于契约，必须与后端分支顺序一致。Shell 定义按组件保存所有权，组件停用时，
所有指向该 Shell 的路由都会拒绝新的导航；现有页面不会因此自动 Pop。

Runtime 在全部组件注册完成后统一验证 Route Placement，因此跨组件 Shell 引用不依赖
Registrar 执行顺序。未知 Shell、未知 Outlet、重复 Outlet、无效默认 Outlet，以及旧的
`CCRouteKind.shell` Route 声明都会在初始化或注册阶段明确失败。BottomSheet/Dialog
仍由 Route Presentation 描述，不能用 Shell 或 Outlet 代替展示语义。

Adapter 初始化时声明能力集合。路由要求 Shell、指定 Page/Dialog Route 类型、透明页面、底部弹出、Dialog 或自定义转场而 Adapter 不支持时，初始化必须失败，不能静默降级。

### 12.2 自适应主从布局

“小屏列表、大屏左列表右详情”属于自适应主从布局（Master-Detail/List-Detail），不是普通的子路由，也不自动等同于 `ShellRoute` 或 `StatefulShellRoute`。

推荐使用同一组类型安全 Route Contract：

```text
orders
├── orders.list
└── orders.detail
```

- 小屏使用单列 Navigator 栈，列表打开详情时执行 `push`。
- 大屏使用显式的 List Outlet 和 Detail Outlet，同时显示列表与当前详情。
- 详情 Route ID、Intent 和 Codec 在两种布局中保持一致，不能按屏幕尺寸生成两套路由契约。
- 如果左右区域需要各自保留导航历史，可由 Shell 承载两个独立 Navigator；如果只是列表加当前选中详情，使用自适应页面容器即可。
- 底部 Tab 等多个长期并行分支才适合 `StatefulShellRoute`；主从布局不能默认建模为 Stateful Shell。

Shell 负责持久化导航容器和 Outlet，主从容器负责根据屏幕尺寸选择栈式或双栏呈现。后续应增加适配器中立的布局/容器元数据，并由 GoRouter Adapter 映射到 `ShellRoute` 或相应的多 Outlet 结构。

### 12.3 大屏、折叠屏与多窗口扩展

路由目的地必须与设备形态解耦。相同的 Route ID、Intent 和参数契约，应根据窗口和显示设备条件选择不同的 Shell、Outlet 和呈现方式，不为手机、平板、折叠屏或桌面分别复制路由。

后续适配模型至少需要覆盖：

- Window Size Class：`compact`、`medium`、`expanded`，并支持窗口自由调整和横竖屏变化。
- Display Feature：折痕、铰链、屏幕切口和不可用区域，避免内容或交互控件跨越遮挡区域。
- Fold Posture：平铺、半折、桌面姿态和双屏展开时的布局切换。
- 多 Window/Display：导航状态按 Window 或 Navigation Host 隔离，不能只依赖进程级单例栈。
- 自适应 Modal：Dialog、Bottom Sheet 和全屏页面可根据可用空间切换，但 Route Contract 保持不变。
- 状态恢复：窗口尺寸、当前 Shell 分支、Outlet 栈、选中详情和进程重建后的恢复标识。
- Web/桌面历史：浏览器前进后退、刷新、外部窗口和 URL 状态同步。
- 系统返回：键盘、手势、预测返回和多 Pane 场景下的返回目标选择。
- 无障碍与输入设备：大字体、键盘、鼠标、手写笔等导致布局变化时，导航状态不能丢失。
- 特殊窗口：画中画、沉浸式全屏和外接屏幕需要独立 Host/Outlet 策略。

建议新增适配器中立的 `Window Context`、`Display Feature` 和 `Adaptive Presentation Policy` 概念。Shell 负责持久化导航容器，Adaptive Layout 负责选择单列、双栏或多 Pane，Window/Display Host 负责绑定实际导航栈。

实现优先级：先完成 Size Class、主从双 Outlet、Modal 自适应和旋转/调整大小状态保持；再支持折叠姿态、多窗口、深链进入指定 Pane 和状态恢复；最后扩展外接屏幕、PiP、预测返回和输入设备驱动的导航策略。

### 12.4 BuildContext 与 Outlet 解析

- 传入 `BuildContext` 时，Flutter 门面解析距离该 Context 最近的 CCRouter Outlet。
- 未传 Context 时使用 Adapter 初始化时声明的默认根 Outlet。
- Context 不进入 Intent、Route Definition、RouteEntry 或 Core Runtime。
- Context 已失效、未挂载或无法解析 Outlet 时返回标准导航错误。
- Shell 和嵌套 Navigator 必须通过显式 Outlet 关系确定，不能退回全局 Context 猜测。

### 12.5 混合路由兼容原则

混合路由的最高优先级是：**经过 CCRouter 的路由必须保持正确；非 CCRouter 路由尽量兼容；无法确认或兼容时，必须隔离外部变化，不能影响 CCRouter 路由。**

具体规则：

- Managed Route 的 RouteEntry、Route Scope、返回值、拦截器和生命周期由 Runtime 完整负责，Adapter 不能用不确定的后端事件覆盖这些状态。
- Foreign Navigator Route、Overlay、LocalHistoryEntry 和第三方浮层可以被观察，但没有权限关闭或修改 Managed RouteEntry。
- 外部事件缺少稳定 Backend Entry 身份时，标记为 `foreign` 或 `opaque`，只记录诊断，不根据事件类型猜测删除 CCRouter 栈。
- 系统返回、手势返回和 `maybePop` 只有在明确确认被移除的是 Managed Entry 时，才能关闭对应 Route Scope。
- 第三方路由需要完整生命周期同步时，必须通过同一 Navigator 的 Observer、`ForeignRouteBridge` 或自定义 Adapter 显式接入；未接入的外部栈按隔离模式处理。
- 兼容性降级优先选择“状态未知但不破坏 CCRouter”，而不是“强行同步但可能误删 CCRouter 路由”。
- 所有无法兼容的外部行为必须进入有界诊断记录，并提供 Host/Adapter 层的修复入口，不能静默改变业务路由结果。

### 12.6 可选 CCRouterApp Host

`CCRouterApp` 是可选的 Flutter 集成 Host，不是业务 App 必须嵌套的第二个 `MaterialApp`。简单应用可以直接把 GoRouter Adapter 绑定到 `MaterialApp.router`；需要 Shell、Outlet、外部 Deep Link、生命周期、埋点或多窗口能力时使用 `CCRouterApp`：

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

### 14.1 外部来源判定

`CCDeepLinkPolicy` 判断的是导航请求的可信入口来源，而不是 URI 的文本形态。完整 `https` URL 可能由应用内部主动打开，平台 Deep Link 也可能被归一化成 `/orders/100`，因此不能根据 Scheme、Host 或是否为绝对 URI 推断外部性。

Runtime 为每次导航保存框架内部的 Origin，至少区分：

```text
internal            类型安全 Intent、应用内 open、状态恢复
externalPlatform    Universal Link、App Link、自定义 Scheme、Initial URI
externalNotification 外部通知载荷中的 URI
externalQr          扫码等不可信外部输入
```

- `CCRouterApp`、平台 Adapter 或应用 Composition Root 持有的受控 Host 入口负责创建外部 Origin。
- 普通业务导航 API 不暴露 `external` 布尔值，也不能把内部请求伪装成外部请求或把外部请求降级为内部请求。
- `CCRouter.navigator.open(uri)` 默认表示应用内主动打开；外部 URI 必须从受控 Deep Link Ingress 进入。
- `CCDeepLinkIngress.fromPlatform(uri)`、`fromNotification(uri)` 和
  `fromQrCode(uri)` 是当前公开门面中的固定入口；它们不接受任意 Origin 参数，
  分别写入对应的外部 Origin 后进入同一 Runtime 管线。
- `CCNavigationSource` 是业务可填写的埋点来源，不是安全信任标记；`CCNavigationSource.deepLink(...)` 本身不能启用或绕过 `CCDeepLinkPolicy`。
- Redirect 必须继承最初 Origin，直到整条导航完成，不能通过重定向绕过 Deep Link Policy。
- “其他业务组件调用”属于应用内导航，组件契约可见性与 Deep Link 外部来源判定互不替代。

Core 当前的 `external` 参数只作为内部实现阶段的等价信号；公开门面通过
`CCDeepLinkIngress` 收敛为固定的不可配置 Origin。`CCRouterApp`、平台 Adapter
或应用 Composition Root 负责在真实平台事件到达时调用相应入口。

### 14.2 外部导航流程

外部导航流程：

```text
Platform URI
  -> 可信 Ingress 标记外部 Origin
  -> Scheme/Host 白名单
  -> Pattern 匹配
  -> Deep Link Policy 检查
  -> Codec 参数解析
  -> CCRouter 导航管线
  -> 两层拦截器
  -> Adapter
```

安全规则：

- Scheme 和 Host 使用精确配置，不接受隐式通配。
- Route 必须显式启用 Deep Link。
- 外部 Origin 必须由可信入口创建，不能由 URI 形态或埋点 Source 推断。
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

`CCNavigationSource` 只描述产品埋点语义；框架内部 Origin 单独记录入口信任级别并驱动 `CCDeepLinkPolicy`。二者可以相关但不能互相推导，例如应用内部推广位可以打开完整 Web URL，外部平台入口也可能携带普通 Path。

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

- Route ID、主 Pattern、Path/URI/Regex 别名和正则约束。
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
CCRouteAmbiguityError
CCRouteUnavailableError
CCRouteParameterError
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

- Route ID、Pattern 和参数声明格式。
- 主 Pattern 唯一、非 `matchOnly` 且可反向生成。
- Path 与 URI Pattern 参数和构造参数一致。
- Query/Extra 注解不冲突。
- 参数类型存在可用 Codec。
- Tracking 字段符合隐私与序列化要求。
- 所有生成的公开类型和成员具有 DartDoc。

应用聚合阶段必须检查：

- Route ID 全局唯一。
- 主 Pattern、别名和正则匹配不存在确定性冲突。
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

### 19.4 测试 API

`ccrouter_core/test` 只保留 Core 包内部实现的低层回归测试。面向框架使用者、组件作者、测试宿主、Mock、导航测试和集成测试的新增测试代码与测试 API 统一放入 `ccrouter_test` 包；该包负责提供受控 Test Host、Runtime Overlay、Adapter 替身和断言工具。业务生产代码不得导入 `ccrouter_core/src/` 或依赖 Core 内部测试入口。

---

## 20. 实现阶段

### 阶段 A：Pure Dart 路由契约

- 已实现 Route ID、Path/URI/Regex Pattern、可见性、Intent、Codec 和错误。
- 已实现 `CCRegistry.registerRoute`。
- 已实现 `CCRouter.navigator` 及 `push/replace/go/reset/open/pop/canPop`、`maybePop`、`popAndPush`、`popUntil`、`pushAndRemoveUntil` 门面。
- 已实现主 Pattern 反向生成、动态 URI 解析和内存测试 Adapter。

### 阶段 B：Runtime 管线

- Route Registry 和确定性匹配。
- 两层拦截器及 Redirect 循环检测。
- RouteEntry、返回值和生命周期。
- Trace 与 Telemetry Observer。

当前已实现 Route Registry 的两层拦截器基础管线：应用宿主通过
`CCGlobalNavigationInterceptor` 提供全局策略，组件通过
`CCRegistry.registerRouteInterceptor` 注册路由策略，`CCRouteDefinition.interceptorIds`
保留路由级声明顺序。拦截结果支持继续、类型安全 Intent/URI 重定向和取消；重定向
沿用原始 `navigationId` 与 `CCNavigationOrigin`，并由 Runtime 限制最大次数。RouteEntry、
Route Scope、拦截上下文的 Deadline 配置和完整遥测投影仍待后续实现。

### 阶段 C：生成器

- 页面和构造参数分析。
- Intent、Codec、Definition、Registrar 和组件契约生成。
- 跨组件可见性及聚合校验。
- JSON/Markdown 文档导出。

### 阶段 D：GoRouter Adapter

当前已建立 `ccrouter_go_router` 包的基础适配器边界。它接收应用自行配置的
`GoRouter`，将 Runtime 已解析的 Page 请求映射到 GoRouter，并保留路由所有权、
来源和 URI 由 Core 管理。GoRouter 仍由应用负责创建和提供页面构造器。

组件或应用组合根可以为每个 Runtime 路由提供一个
`CCGoRouterRouteBinding(routeId, goRoute, presentationKind)`。绑定只关联稳定的 CCRouter Route ID
与应用拥有的 `GoRoute`，并声明其 `pageBuilder` 返回的 Page 家族，不会注册、修改或销毁 `GoRouter`。当提供绑定集合时，
Adapter 初始化会校验 Runtime 路由与绑定 ID 一一对应；根页面或其他不属于
CCRouter 契约的 GoRouter 路由可以继续由应用独立保留。

当前已支持 Modal BottomSheet 和 Dialog，但必须由绑定的 `GoRoute.pageBuilder`
显式返回 `CCGoRouterBottomSheetPage` 或 `CCGoRouterDialogPage`；适配器不会改写应用拥有的
`GoRoute`，也不会把普通 Page 静默降级为模态展示。两类模态 Page 都保留 GoRouter
栈条目，因此 `push` Future、`pop` 返回值、遮罩/拖拽配置和生命周期仍由 Navigator
处理。Material 与 Cupertino Dialog 可通过 `CCDialogRouteType` 选择，BottomSheet
配置映射到 Flutter 的 `ModalBottomSheetRoute`。`popAndPush`、`popUntil` 和 `pushAndRemoveUntil` 已通过 GoRouter 的 Navigator 与
imperative API 接入。由于 GoRouter 没有完全对应的公开原子组合 API，Adapter 会在
一次 Runtime 操作内完成后端 Pop/Push 序列，并保持返回值与 Predicate 语义。
GoRouter Adapter 通过 `navigatorKeys` 接收应用拥有的 Outlet Navigator，并可把带有
`shellId`/`navigatorOutlet` placement 的子路由映射到已有 `ShellRoute` Navigator；
也可以通过 `CCGoRouterShellBinding` 一次声明 Shell 和全部分支 key。Runtime 会把
组件注册的 `CCNavigationShell` 快照交给 Adapter；Adapter 校验 Shell 类型、Outlet
集合、默认 Outlet、Outlet 顺序和实际 Navigator key。缺少绑定、绑定多余、类型不一致或 Stateful
分支顺序不一致时初始化会明确失败。已有 `StatefulShellRoute` 的分支可以通过 `go`
切换并保留 GoRouter 自己的分支状态；Shell 的 Widget、Builder 和 GoRouter Route
仍由应用创建，Adapter 不会修改应用路由树，也不会静默把目标栈改成根 Navigator。
生命周期桥使用 `CCGoRouterNavigationObserver`，由应用添加到 root Navigator、
`ShellRoute.observers` 或 `StatefulShellBranch.observers`。Observer 只发出带 Outlet
标识的 Push/Pop/Replace/Remove 事件，适合埋点、诊断和生命周期同步；它不在回调中
保存 `BuildContext`，也不允许同步触发 CCRouter 导航。当前 Flutter Observer API
不保证提供 Pop 返回值，因此事件中的 `result` 可能为空。
`CCGoRouterAdapter` 可以通过 `observers` 参数订阅这些事件，并以
`lifecycleEventCapacity` 保留有界快照；Runtime dispose 时会自动解除订阅。外部
Deep Link 仍必须先经过 Core 的 `CCDeepLinkIngress` 和策略校验，校验通过后由
Adapter 的 `go` 进入目标 Shell 分支，不根据 URI 形态绕过策略。

- 主 Pattern、别名、Query、Extra 和返回值。
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
4. 一个路由可以通过主 Pattern、完整 URL、自定义 Scheme、历史别名和完整正则解析为同一个 Route ID。
5. 正则约束失败时返回参数或未匹配错误，不进入页面 Factory；完整正则只允许全匹配。
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
- Route ID 与寻址 Pattern 分离。
- 支持一个可生成地址的主 Pattern，以及多个 Path、结构化 URI、完整 Regex 别名和参数正则约束。
- Pattern 固定按结构化 URI、Path、完整 Regex 排序；同优先级歧义显式失败。
- 使用类型安全 Intent 和生成 Codec，不以参数 Map 作为业务契约。
- 路由默认仅组件内部可见，对外契约显式生成。
- `visibleTo` 只做生成期和 CI 治理，Runtime 不校验调用方组件身份。
- 展示契约区分 Page、模态 BottomSheet 与 Dialog；Page 和 Dialog 分别使用独立的 Route Type 表达 Flutter 对应语义。
- 业务拦截器只有 Global 和 Route 两层。
- 埋点来源和字段白名单进入统一 Runtime 管线。
- Deep Link 外部性由可信 Ingress 创建的内部 Origin 决定，不根据 URL 形态或业务 `CCNavigationSource` 推断。
- 输出 JSON 和带 DartDoc 的 Markdown 路由文档。

### 待实现时验证

- `replace` 对被替换 RouteEntry Future 的标准完成语义。
- Query 未知字段默认忽略还是严格失败。
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
- 路由名称改为稳定 Route ID、主 Pattern 和别名的分离模型。
- 页面生命周期改为 Adapter 上报的 RouteEntry 生命周期。
- 多导航后端改为消费同一份中立 Definition，而不是切换生成模板。

TheRouter 的完整 URL、自定义 Scheme、多 Path 和正则能力用于校准 CCRouter 的能力范围，但不照搬其不透明字符串键与正则启发式检测。CCRouter 使用显式 Pattern 类型、结构化 URI 比较和完整正则匹配，使地址生成、参数注入、冲突诊断和跨端文档都能共享同一语义。
- 多 Package 扫描改为组件 Registrar 和应用聚合校验。

不采用：

- 由 Core Generator 直接生成 `GoRoute` 或其他后端对象。
- `codes`、`exts`、原始 import 字符串和任意代码注入。
- 全局可变参数转换器、全局 Navigator 或生命周期单例。
- 页面必须继承特定 State 或混入 Widget 生命周期类型。
- 自定义 CLI 作为主要生成入口，以及正确性不同的 fast/full 模式。
- 通过 Path 前缀猜测 Shell 结构。
