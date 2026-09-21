# CCRouter 路由子系统设计

## 文档状态

- 版本：v0.2
- 状态：当前路由闭环已实现；完整 Route Restoration 和调用级 `BuildContext` Outlet 解析暂未实现
- 适用范围：Flutter 应用及其组件化路由契约
- 默认导航后端：`go_router`
- 核心约束：业务跳转统一通过 `CCRouter.navigator`，Core 不依赖 Flutter、`BuildContext` 或 `go_router`

本文档细化 [CCRouter v0.1 架构设计](CCRouter-v0.1-architecture.md) 中的路由部分。未标记为
Proposal 或“暂缓”的 API 名称应与当前仓库保持一致；实施完成状态统一以
[路由完成计划](CCRouter-route-completion-plan.md)为准。

注解生成器已实现页面注解、单库校验、类型安全 Arguments/Intent、标量 Path、标量及
repeated Query、显式 Query Codec、类型安全 Extra 校验、Definition、注册入口和中立页面工厂。使用 `part` 生成
`.route.g.dart`，页面契约固定为 library-private；Contract-first 公开契约需显式导出。
生成器同时输出组件级和路由级 JSON/Markdown，并按 Host 的已解析运行时 Package 依赖闭包
聚合检查组件与 Route ID、路由所有者、契约 exposure 和实现 Package，输出发布级 Package
Index、分层 Host Bundle 与应用级路由目录。当前仍不生成
GoRoute。独立纯契约文件的拆分方案见[契约文件设计](CCRouter-route-contract-design.md)，
实现范围与命令见
[生成器说明](../packages/ccrouter_generator/README.md)。

混合路由的隔离、Foreign Route 兼容和第三方 Popup 改造方案见：[CCRouter 混合路由改造设计](CCRouter-hybrid-routing-design.md)。

---

## 1. 目标

路由子系统需要解决以下问题：

1. 组件通过类型安全的契约跳转，不直接依赖目标页面实现。
2. 一个路由可以拥有主寻址 Pattern、历史 Path、完整 URL、自定义 Scheme 和正则别名，并保持调用端与接收端一致。
3. Path、Query 和内存 Extra 参数由生成代码编码、解析并注入页面。
4. 默认适配 `go_router`，同时允许实现其他导航适配器。
5. 路由注册、拦截、生命周期、埋点和诊断使用同一条调用链。
6. 路由契约按组件和声明形态生成，不创建包含全部业务路由的全局 `Routes` 类。
7. 生成机器可读及开发者可读的路由文档。
8. 以组件所有权驱动 Route/Shell 的 `activateComponent` / `deactivateComponent`，并为未来
   完整动态组件管理保留明确生命周期边界。

## 2. 非目标

当前路由范围不包含：

- 运行时下载或加载未编译进 App 的 Dart 页面。
- 在 Core 中重新实现 Flutter Navigator 或 `go_router` 的匹配算法。
- 通过任意字符串代码、反射或 `Map<String, dynamic>` 构造页面。
- 同时内置 Navigator 1.0、GetX 等多个后端。
- 把 Package 契约 exposure 当作登录、权限或数据安全机制。
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
- 本地构建与 CI 使用同一套分析语义；默认内容寻址缓存与 `--no-cache` 全量参考路径必须输出
  逐字节一致结果，缓存损坏或依赖身份变化时自动回退全量解析。

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
const orderComponent = CCComponentDescriptor(
  id: 'orders',
  version: '1.0.0',
);

@CCRoute<OrderResult>(
  component: orderComponent,
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
  deepLink: CCDeepLinkPolicy.enabled,
  description: '展示订单详情。',
  interceptors: ['auth.required'],
)
final class OrderDetailPage {
  const OrderDetailPage({
    required this.orderId,
    @CCQueryParam() this.tab,
    @CCExtraParam() this.snapshot,
  });

  /// 订单 ID。
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
| `pattern` / `patterns` | 二选一 | 单值自动作为主 Pattern；多值包含一个可反向生成的主 Pattern 和零个或多个 Path、URI 或正则匹配别名 |
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

- 单地址路由使用 `pattern`，生成器自动将可逆的 Path/URI Pattern 设为 primary。
- 多地址路由使用 `patterns`；如果其中只有一个可逆 Pattern，生成器自动设为 primary。
- 多地址路由存在多个可逆 Pattern 时必须显式指定 primary，不能根据匹配优先级或声明
  顺序猜测规范地址。
- `pattern` 与 `patterns` 不能同时设置。
- 业务调用生成地址时始终使用主 Pattern。
- 主 Pattern 必须是可反向生成的 `CCPathPattern` 或 `CCUriPattern`，不能是正则 Pattern。
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

Scheme、Host 和有效端口的应用级白名单由 `CCDeepLinkIngressPolicy` 配置；
`CCUriPattern` 只描述某条路由接受的地址，并不能替代入口信任校验。外部 URI
的完整原文默认不进入日志或埋点。

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

无法用结构化模板表达的兼容地址使用 `CCRegexPattern`。它对移除 Query 和 Fragment 后的
normalized encoded URI 进行全匹配；只有匹配成功后，Runtime 才会将每个命名捕获组
percent-decode 一次，再作为 Path 参数交给 Codec。这样 `%2F` 在匹配前仍是参数数据而不是
Path 分隔符，同时 Path、URI 和 Regex 三种 Pattern 最终交给 Codec 的参数均为 decoded
value。`+` 在 Path capture 中保持 `+`；只有 Query 使用 form encoding 语义将裸 `+`
解析为空格。

Regex 表达式本身看到的是 encoded URI。例如需要兼容参数的任意 percent-encoded 表达时，
应使用 `(?<value>[^/]+)` 捕获后交给 Codec 校验，而不是使用只接受 decoded 字符的表达式。
`%252F` 只解码一次得到 `%2F`，不能继续解码为 `/`。命名捕获如果截断 percent escape 或
UTF-8 code point，则该 Pattern 视为不匹配，不向业务暴露原值或底层 `FormatException`。
完整正则不可逆，不能作为主 Pattern，并且路由必须同时存在一个可生成地址的主 Pattern。

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

Query 集合只支持 `List<T>` 和 `Set<T>`，其中 `T` 必须是非空类型的 `String`、`int`、
`double`、`bool` 或 enum。集合使用 repeated key，例如 `?tag=a&tag=b`；List 保留顺序，
Set 解码时去重、编码时按 wire value 排序以生成稳定 URI。Intent 创建和 URI 解码都会复制为
不可变集合，调用方后续修改原集合不会改变导航参数。空集合没有可逆 URI 表达，因此编码和显式
空列表解码都会失败；需要表达特殊空状态时应设计明确的标量值或自定义 Codec。

复杂 Query 对象通过 `@CCQueryParam(codec: XxxQueryCodec)` 显式声明。Codec 必须是 concrete、
non-generic，并提供无参 `const` 未命名构造器，且 `CCRouteQueryCodec<T>` 的 `T` 必须与参数的
非空类型完全一致。生成边界会复制输入/输出字符串列表并把 Codec 异常统一转换为脱敏的
`CCRouteParameterError`；Codec 不应用于 secret、可变业务对象或仅进程内有效的数据。

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
  source: const CCNavigationSource.feature('home.order_banner'),
);
```

当前业务门面 API 的核心签名如下；完整定义以 `CCNavigator` 为准：

```dart
abstract final class CCRouter {
  static CCNavigator get navigator;
}

abstract interface class CCNavigator {
  Future<R?> push<R>(CCRouteIntent<R> intent, {CCNavigationSource? source});
  Future<R?> replace<R>(CCRouteIntent<R> intent, {CCNavigationSource? source});
  Future<bool> maybePop<R>({R? result});
  Future<CCPopOutcome> maybePopOutcome<R>({
    R? result,
    CCPopTrigger trigger = CCPopTrigger.system,
  });
  Future<void> go<R>(CCRouteIntent<R> intent, {CCNavigationSource? source});
  Future<void> reset<R>(CCRouteIntent<R> intent, {CCNavigationSource? source});
  Future<void> open(Uri uri, {CCNavigationSource? source});
  void pop<R>({R? result});
  bool canPop();
}
```

### 8.1 栈操作扩展边界

`CCNavigator` 不机械复制 Flutter `Navigator` 的所有方法，而是只暴露具有稳定跨 Adapter 语义的栈操作。当前决策如下：

| 方法 | 决策 | 说明 |
| --- | --- | --- |
| `maybePop` | 支持 | 保留 `Future<bool>` 兼容入口；需要归属信息时使用 `maybePopOutcome` 获取 `CCPopOutcome`，不能简单用 `canPop` 加 `pop` 替代。 |
| `popAndPush` | Deferred | 当前后端不能可靠保证 Pop 拒绝、旧页面结果、新页面结果和失败回滚属于同一个原子事务。 |
| `popUntil` | Deferred | 混合栈中必须先能按稳定后端身份区分 Managed、Foreign 和 Opaque Entry，并处理逐次 Pop 被拒绝。 |
| `popUntilWithResult` | 暂缓后支持 | 需要先定义结果传递给每个被移除 RouteEntry、遇到拒绝 Pop 或没有匹配目标时的完整语义，不能直接照搬第三方扩展方法。 |
| `pushAndRemoveUntil` | Deferred | 需要后端一次性提交目标栈，并保证失败回滚、pending result 和 Route Scope 一致。 |
| `replaceRouteBelow` | Deferred | 需要稳定 backend Entry identity 和不依赖栈位置的原子替换能力。 |
| `removeRoute` / `removeRouteBelow` | Deferred | 需要稳定 backend Entry identity，并保证 Foreign/Opaque Entry 不受影响。 |
| `popAndPushNamed` / `pushNamedAndRemoveUntil` | 不提供 | 路由系统使用稳定 Route ID、生成的 Intent 和动态 `open(Uri)`，不再增加字符串 Name API。需要动态地址时使用 `open` 组合操作。 |

上述 Deferred 操作已从业务 API、Runtime、基础 Adapter SPI、Capability、内置 Adapter、Demo 和测试中完整删除，不以多个现有操作拼接模拟。重新接入时应使用可选、版本化的栈事务 SPI，而不是继续扩张所有 Adapter 必须实现的基础接口。接入门槛包括：稳定 backend Entry identity、一次性或原子提交目标栈、Managed/Foreign/Opaque 隔离、Shell/Outlet/MultiHost 分区、PopGuard 拒绝语义、失败回滚，以及 pending result 与 Route Scope 生命周期一致。Adapter SPI 不向 Core 暴露 `BuildContext`、Flutter `Route` 或 `NavigatorState`。

`push<R>` 和 `replace<R>` 返回 `Future<R?>`。系统返回、无值 Pop 或 RouteEntry 被允许取消时完成 `null`；解析、拦截或 Adapter 失败时抛出标准错误。

`maybePopOutcome` 只有在 Adapter 明确返回 `removedOwner == managed` 时才允许
Runtime 关闭对应 RouteEntry；Foreign、Opaque 或未提供归属的 Pop 只报告结果，不
按栈顶猜测删除页面。

当前 `CCNavigator` 不接收 `BuildContext`。Host 和 Outlet 由生成 Intent 中的
`CCRoutePlacement`、活动 Host Resolver、Shell Binding 和 Adapter 默认 Host 共同解析。
未来如增加“按调用点选择最近 Outlet”的 Flutter 便利 API，只能在 Flutter 门面即时解析，
不得把 Context 保存或传入 Core；该 Proposal 不能改变现有无 Context API 的语义。

当前已实现 `push/replace/go/reset/open/pop/canPop`、`maybePop` 和 `maybePopOutcome`；
主 Pattern 地址生成、中立 Adapter SPI、内存 Adapter、GoRouter Adapter 与 Host/Outlet
调度也已实现。

不提供 `CCRouter.push()` 等重复快捷入口，也不提供绕过 `CCRouter.navigator` 直接执行生成 Intent 的公开方法。

---

## 9. 组件所有权与契约 Exposure

### 9.1 自动推导模型

路由不再声明 `visibility` 或消费者 allowlist，生成器根据契约形态唯一推导 exposure：

| 契约形态 | Exposure | 导入边界 |
| --- | --- | --- |
| 页面上的 `@CCRoute` | internal | 页面 library 内部 |
| 同 Package 的 `@CCRouteContract` + `@CCRouteImplementation` | package | 实现 Package 的公共 barrel |
| 独立 contracts Package 的 `@CCRouteContract` + 实现 Package 的 `@CCRouteImplementation` | external | contracts Package 的公共 barrel |

消费者必须在 `pubspec.yaml` 中直接依赖公开契约所在 Package，并通过该 Package 的
公共 barrel 导入生成的 Route 与 Arguments。Dart analyzer 和
`depend_on_referenced_packages` 负责验证真实依赖，避免维护一套无法限制 import 的
`visibleTo` 平行名单。

Runtime 不接收可伪造的调用方组件 ID，也不把 Package exposure 当作授权机制；它只
保存可信的 `ownerComponentId`，用于组件生命周期、诊断、埋点和后续卸载。Deep Link
Policy 同样独立：公开契约不表示允许外部 URI，允许 Deep Link 也不表示绕过权限拦截器。

### 9.2 生成文件布局

```text
order_contracts/lib/
├── order_contracts.dart
├── order_contracts_owner.dart
└── src/ccrouter_generated/contract/order_detail_route_contract.route.contract.g.dart

order_component/lib/src/
├── order_detail_page.dart
└── ccrouter_generated/route/order_detail_page.route.g.dart
```

- `order_contracts.dart` 只导出明确选定的 external 路由及其参数、结果契约。
- `order_contracts_owner.dart` 只供 owner 实现组件绑定 schema，不供业务调用方导入。
- 内部文件包含组件全部路由，但不从公共 barrel 导出。
- 应用级生成器不生成暴露全部路由的全局 `Routes` 类。
- Registrar 注册全部已装配路由，与业务 API 的 Package 导出边界相互独立。

Dart 没有 package-private 或 friend package。`lib/src`、显式 export、`implementation_imports` lint、组件依赖检查和 CI 共同形成工程边界，但不是安全边界。真正的授权仍由 Runtime 和拦截器完成。

### 9.3 动态组件关系

每个 Route Definition 必须记录 `ownerComponentId`。组件停用后：

- 新导航请求返回 `CCRouteUnavailableError`。
- 已存在 RouteEntry 保持存活，不能因组件停用被静默销毁或猜测 Pop。
- Runtime 已提供 Route 和 Shell 的 `activateComponent` / `deactivateComponent` 状态切换，
  并按组件所有权执行一致校验。

当前尚未提供面向应用的完整动态组件管理器，也不物理卸载 Registrar、Service、Handler、
Adapter binding 或依赖图。完整安装/卸载语义属于后续组件生命周期设计，不能由业务直接
操作隐藏的 Runtime API。

---

## 10. Route Definition 与 Registry

中立 Route Definition 至少包含：

```text
routeId
ownerComponentId
patterns
contract exposure（由声明形态生成，仅进入元数据）
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
- 公开契约缺少实现，或实现不属于声明的 owner Package。
- 静态可判断的同层 Pattern 冲突。

跨组件导入范围由公共 barrel、Pub 依赖、Analyzer 和 CI 验证，不由 Runtime 根据调用方身份执行。

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
proceed   继续当前请求，不改写 Intent
redirect  改为新的 Intent，并保留原始导航上下文
cancel    终止导航，返回标准取消原因
```

规则：

- Global 按稳定 ID 排序执行，当前不提供显式优先级。
- Route Interceptor 按注解声明顺序执行。
- Route Interceptor 只能由同组件的路由引用；跨组件共享策略必须注册为 Global Interceptor。
- Interceptor 可以异步执行并接收取消信号与 Deadline。
- Redirect 重新进入必要的解析和拦截流程。
- Runtime 必须检测重定向循环并限制最大重定向次数。
- Interceptor 不允许直接调用 Adapter。
- 错误、取消和重定向均进入 Trace 与路由埋点事件。
- 所有带目标路由的操作都经过拦截器，包括 Push、Replace、Go、Reset 和 Open；Pop 与 MaybePop 只有栈移除目标，不触发目标路由拦截器。

### 11.1 与常见注解路由框架的能力对齐

当前拦截器的基础语义已经覆盖常见注解路由框架的主要前置拦截场景，但不承诺与具体框架 API 逐项兼容：

已具备：

- 全局拦截器和组件路由级拦截器。
- 异步 `proceed`、`cancel` 和 Typed Intent/URI `redirect`。
- 登录、权限、Feature Flag、维护模式、首次引导和组件激活状态检查。
- `push`、`replace`、`go`、`reset` 和 `open` 的统一前置管线。
- 保留原始 `navigationId`、`origin` 和 `source` 的重定向，以及最大重定向次数保护。

已完成的增强：

- 注解和生成器自动生成 `interceptorIds`，减少手工维护。
- 拦截器执行使用真实 Deadline/Timeout，并以专用错误报告超时和执行异常。
- `CCNavigationDefer` 恢复时保留原始操作、目标和 RouteEntry 提交语义。

可选后续增强：

- 显式拦截器优先级配置；当前全局拦截器按稳定 ID 排序，路由拦截器按声明顺序执行。

导航完成后的 `onAfter`、失败 `onLost` 和 Resolve/Intercept/Dispatch/Arrival/Stay/Total
分阶段耗时已经由 `CCNavigationAspect` 提供，不再列为拦截器缺口。

因此，CCRouter 对齐的是拦截器的行为语义和类型安全边界，不复制 ff_annotation_route 或 TheRouter 的具体 API 形状。

### 11.2 Pop Guard

`CCPopGuard` 是独立于前置导航拦截器的同步退出决策。Host 提供的 Global Pop Guard 按
稳定 ID 排序，随后执行当前 Managed Route 在注解中声明的 `popGuards`。路由 Guard
只能引用同组件通过 `CCRegistry.registerRoutePopGuard` 注册的 ID。

系统返回、普通手势和业务 Pop 在 Adapter 执行前进入同一 Guard 管线。Predictive Back
由 Host 在平台 commit 前调用 `CCGoRouterPredictiveBackBridge.evaluateStart`；commit 后的
事件只用于确认 Backend Entry identity，不能再撤销系统手势。

Guard 只在即将移除的顶部 Backend Entry 被确认属于 CCRouter 时执行。Foreign、Opaque、
`LocalHistoryEntry` 和无法确认归属的第三方 UI 不执行底层页面 Guard，也不关闭 Managed
RouteEntry 或 Route Scope。拒绝结果保留当前 Entry，并通过 `guardDeniedCode` 提供稳定、
不含业务数据的原因；直接业务 `pop` 使用 `CCPopGuardDeniedError` 报告拒绝。

多 Host 或多 Outlet 场景通过 Adapter 的只读 `CCNavigationPopTarget` 先确定 active Host/Outlet，
再在该分区的 Backend Entry 台账中选择 Guard 目标。不同 Host 的事件 sequence 不参与比较；
managed outcome 缺少 `backendEntryId` 时只记录 Host desynchronized，不按 Runtime 顶部猜测删除。

Guard 必须同步、快速且无副作用，适合脏状态、强制流程和本地内存策略。需要弹确认框的
异步流程继续使用 Flutter `PopScope`，确认后再重新发起导航，避免阻塞 Predictive Back。

### 11.3 失败与兜底

Host 可以在初始化时提供唯一的 `CCNavigationFailurePolicy`，统一处理路由未找到、参数
非法、Deep Link 拒绝、组件不可用、拦截失败和 Adapter 失败。Policy 只接收
`CCNavigationFailureContext`：稳定 Navigation/Route ID、原始 Operation、Origin、Source、
失败阶段和错误类型；不接收原始 URI、Path/Query 值、Arguments、Extra、Pop result 或
backend Route。

Policy 可以明确选择：

- `CCNavigationFailurePropagate`：保留原错误；
- `CCNavigationFailureRedirect`：将原调用重定向到类型兼容目标；
- `CCNavigationFailureFallback`：打开 404、链接不支持或组件不可用页面，并让原调用以
  `null` 完成。

Redirect/Fallback 未指定 `operation` 时继承原调用的栈操作，避免 Push 失败后默认 Replace
并删除当前正常页面。显式指定 `open` 时可以同时提供独立 `openMode`，未提供时采用 Push；
继承原始 Open 时则保留原始 Open mode。

恢复目标必须是非组合操作，并重新执行解析、Deep Link Policy、组件状态、参数 Codec 和
完整拦截器链。恢复过程保留原始 `navigationId`、`origin` 和 `source`，最多连续恢复四次；
超出后抛出 `CCNavigationFailureRecoveryLoopError`。Policy 必须返回 Decision，不能直接
调用导航，避免重入和绕过循环检测。

所有失败无论是否安装 Policy，都以 `CCNavigationFailureEvent` 进入有界诊断；`recovered`
表示 Policy 是否选择 Redirect 或 Fallback。request 创建前无法可靠得到 Pattern、Placement、
Owner 和 Host，因此该阶段不伪造 Lifecycle/Aspect request，Failure Event 是权威终态 envelope。
Aspect 和普通 Navigation Lifecycle 只暴露已经解析出的参数化 `routePattern`，不再暴露实际 URI
值。Deep Link 命中但被路由策略禁用时使用独立 `CCDeepLinkRejectedError`，与真正未匹配的
`CCRouteNotFoundError` 区分。

### 11.4 重复导航与防抖策略

重复导航保护属于 Runtime 的并发策略，不作为普通 Route Interceptor 的临时实现。默认策略必须允许合法的重复页面：同一路由、同一 URI 连续 Push 也可以创建两个独立的 RouteEntry、Route Scope 和返回值通道。

Runtime 已提供可选的导航去重策略：

```text
allow           每次调用都执行，默认值。
rejectDuplicate 相同导航正在执行时拒绝后续调用。
singleFlight    相同导航正在执行时复用第一次调用的 Future。
```

重复判断使用结构化 Key：

```text
hostId + navigatorOutlet + operation + routeId + normalizedUri
```

相同路由但不同 Path 或 Query 参数不能被误判为重复；不同 Host、Shell 或 Outlet 也必须隔离。携带进程内 Extra 的请求不参与自动去重：Runtime 不能安全比较、序列化或哈希任意业务对象，因此 `rejectDuplicate` 和 `singleFlight` 都将其作为独立导航执行。去重状态在拦截取消、重定向失败、Adapter 失败、页面 Pop 和 Runtime dispose 时释放。`rejectDuplicate` 抛出标准 `CCNavigationDuplicateError` 并产生完整 `found/lost/after` 观察终态；`singleFlight` 复用同一个逻辑导航结果，不会创建第二个 RouteEntry，但共享调用仍拥有独立 Navigation ID、Lifecycle 和 `after` 终态。该策略不采用全局固定时间 debounce，避免延迟正常导航或误伤合法的重复 Push。

### 11.5 待认证导航与登录后恢复

未登录访问受保护路由时，拦截器可以返回 `CCNavigationDefer`。Core 已提供通用的 Pending Navigation/Continuation 能力，认证组件通过待处理 ID 决定何时恢复或取消，不在 Runtime 内硬编码登录业务。

待恢复导航至少保留：

- Runtime 内部保存原始 Typed Intent 解码结果或动态 URI；对外只提供不含 Typed 参数和 `Extra` 的安全快照。
- 原始 `navigationId`、`origin`、`source` 和目标组件。
- 内部导航需要保留的 `Extra`。
- 原始操作类型和结果完成通道。
- 超时、Session 和 Runtime 生命周期状态。

恢复流程必须重新执行路由解析、参数校验、组件激活检查和完整拦截器链，不能直接绕过策略进入页面。登录取消、恢复失败、Session 关闭、超时和 Runtime dispose 都必须清理待恢复导航；外部 Deep Link 的回跳目标还必须经过 Host 和 Deep Link 安全校验。

该能力用于登录、权限提升、首次引导和其他需要用户完成前置流程的场景。简单应用可以继续手动传递 `returnTo`，但不能将其视为跨组件 Typed Intent 和返回值的完整替代方案。

### 11.6 导航观察回调

CCRouter 不直接复制 TheRouter 的无类型 `NavigationCallback` API，而是将导航观察和业务返回值分开：

- `onArrival`：Managed RouteEntry 进入 `visible`，用于页面曝光、埋点、焦点恢复、预加载和跨组件生命周期通知。
- `onLost`：已建立安全请求后的拦截或 Adapter 失败会提供标准错误；路由未找到、参数非法、Deep Link 拒绝和组件不可用等解析前失败由 `CCNavigationFailureEvent` 覆盖。
- `onFound`：路由匹配成功但尚未进入页面，优先作为内部解析和性能诊断事件，不作为普通业务页面生命周期依赖。
- `onResult`：继续使用 `Future<R?>` 返回类型安全的页面结果，不增加无类型回调。

现有 `CCNavigationLifecyclePhase.completed` 不等同于 `onArrival`：对于 `push`，`completed` 可能要等页面 Pop 后才发生。当前由独立的 `CCNavigationAspect` 提供安全快照形式的 `onFound`、`onArrival`、`onLost` 和 `onAfter` 钩子，并在事件中提供从首次匹配开始的 `elapsed` 耗时，使匹配、到达、失败和结果完成的时机明确；跳转前决策统一由 Global/Route Interceptor 承担。

所有纯观察回调统一进入 Runtime 私有的有界 FIFO 队列，并在下一轮 event loop 分发，不占用
正常导航调用栈。诊断历史仍同步写入，调用方无需等待 Listener 才能读取快照。队列容量至少为
64 个事件批次并复用 Host 的 `navigationDiagnosticCapacity` 上限；overflow 优先丢弃最旧
非终态事件，终态事件通过明确 backpressure 保证不静默丢失。取消订阅会使尚未分发的回调失效；
Runtime dispose 会停止事件源、取消 Timer、flush 队列并清理 Listener/闭包。观察回调失败进入
有界诊断而不影响导航，回调及其派生异步任务都不能再次发起 Runtime 导航。

### 11.7 TheRouter 风格的全局 AOP

CCRouter 参考 TheRouter 的全局 AOP 使用场景，但不直接复制其无类型的单一
`NavigationCallback` API。当前能力和目标能力明确区分如下：

| 阶段 | 当前状态 | 目标职责 |
| --- | --- | --- |
| `before` | 已支持，由 `CCGlobalNavigationInterceptor` 提供 | 全局登录、权限、维护模式、强制升级、取消和重定向 |
| `found` | 已支持，并携带匹配耗时 | 记录匹配结果、解析耗时和被拦截前的诊断信息 |
| `arrival` | 已支持，并关联 Managed RouteEntry 和耗时 | 页面曝光、焦点恢复、预加载和跨组件到达通知 |
| `after` | 已支持，并报告成功、失败、取消和耗时 | 统一观察结果完成、失败、取消和页面离开 |

因此，`CCNavigationLifecyclePhase.completed` 也不能直接当作 `arrival`：对 `push`
来说，它通常要等页面 Pop 后、结果通道完成时才发生。当前 Global/Route Interceptor
与 `CCNavigationAspect` 共同覆盖 TheRouter 风格的决策与观察边界，同时保留 CCRouter
的类型安全快照和结果通道。

全局观察契约与 `CCGlobalNavigationInterceptor` 分离，统一命名为
`CCNavigationAspect`：

- 跳转前决策由 Global/Route Interceptor 提供，可以继续、取消或重定向。
- `onFound`、`onArrival`、`onLost` 和 `onAfter` 默认只观察，不改变目标路由。
- 所有阶段都接收不可变的导航/路由快照，不暴露 `Widget`、`BuildContext`、
  `Navigator` 或任意业务对象。
- 观察回调异常必须隔离并进入诊断，不能影响已经接受的导航。
- 回调及其派生异步任务中禁止再次发起导航，避免重入和递归导航链。
- 业务页面结果继续通过类型安全的 `Future<R?>` 返回，不增加无类型结果回调。

“全局唯一”表示所有 Runtime 导航经过同一条有序 AOP 管线，不表示只能注册一个
业务策略实例。内部仍允许多个具名观察器按稳定顺序组合，以支持埋点、日志、性能
统计、Deep Link 失败统计、A/B 策略和多 Host 诊断。

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

Adapter 生命周期由 `CCRouterRuntime` 统一拥有。Adapter `initialize`、初始 Backend Snapshot
读取和 `dispose` 都是同步事务：attach 返回时必须已经可以导航，失败必须在写入 Runtime
所有权前同步抛出，dispose 返回时监听器和内存索引必须已经清理。Adapter 不允许在这些方法
中执行网络、磁盘或 MethodChannel 等异步准备；此类资源由 Host 在构造 Backend 前准备。

`CCRouter.initialize` 同样同步完成全局配置和启动组件注册。`CCRouter.shutdown` 仍为异步，
因为它需要等待 Route/Session/App Scope、业务 Service dispose 和 Backend 自有资源。Session
关闭、组件停用和单个 RouteEntry Pop 只影响各自的 Scope 或栈状态，不触发 Adapter
dispose。GoRouter Adapter 自身不销毁 `GoRouter`，只清理绑定和 RouteEntry 状态；
`CCGoRouterBackend.managed` 创建的 Router 在 Runtime 完成 Adapter dispose 后由 Backend
释放，attach 模式下应用创建的 Router 始终由应用释放。

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
Registrar 执行顺序。未知 Shell、未知 Outlet、重复 Outlet、无效默认 Outlet，以及把
Shell 错误声明成普通 Route 的情况都会在初始化或注册阶段明确失败。BottomSheet/Dialog
仍由 Route Presentation 描述，不能用 Shell 或 Outlet 代替展示语义。

Adapter 初始化时声明能力集合。路由要求 Shell、指定 Page/Dialog Route 类型、透明页面、底部弹出、Dialog 或自定义转场而 Adapter 不支持时，初始化必须失败，不能静默降级。

只有能够保持安全边界的观察能力允许显式回退：缺少完整 backend visibility observation 时，
Runtime 在 commit 后维护 managed visibility；缺少 managed removal observation 时，Go/Open-Go
只 reconcile 目标 Host/Outlet partition。每次实际采用回退都会产生有界、脱敏的
`CCNavigationCapabilityFallbackEvent`，记录 Navigation/Route/Host/Outlet、缺失能力和最终行为，
不记录 URI、Arguments、Extra 或 backend Route。空 partition 不产生 removal 回退事件。

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

Shell 负责持久化导航容器和 Outlet，主从容器负责根据屏幕尺寸选择栈式或双栏呈现。
当前已提供适配器中立的 `CCHostLayoutMetrics`、`CCAdaptivePresentationPolicy`、
`CCAdaptiveOutletPolicy` 和 `CCAdaptiveHostLayout`；Host 根据布局结果切换活动 Outlet，
具体 Widget 结构和 GoRouter Shell 仍由应用组合根创建。

### 12.3 大屏、折叠屏与未来原生多窗口

路由目的地必须与设备形态解耦。相同的 Route ID、Intent 和参数契约，应根据窗口和显示设备条件选择不同的 Shell、Outlet 和呈现方式，不为手机、平板、折叠屏或桌面分别复制路由。

当前契约和 Host 调度已经覆盖：

- Window Size Class：`compact`、`medium`、`expanded`，并支持窗口自由调整和横竖屏变化。
- Display Feature：折痕、铰链、屏幕切口和不可用区域，避免内容或交互控件跨越遮挡区域。
- Fold Posture：平铺、半折、桌面姿态和双屏展开时的布局切换。
- 多 Host：独立 Router 或导航表面的状态按 Navigation Host 隔离，不能只依赖进程级单例栈。
- 自适应 Modal：Dialog、Bottom Sheet 和全屏页面可根据可用空间切换，但 Route Contract 保持不变。
- 状态恢复需求观测：只记录脱敏的重建机会，不保存或恢复 Outlet 栈和业务参数。
- Web/桌面历史：浏览器前进后退、刷新、外部窗口和 URL 状态同步。
- 系统返回：键盘、手势、预测返回和多 Pane 场景下的返回目标选择。
- 无障碍与输入设备：大字体、键盘、鼠标、手写笔等导致布局变化时，导航状态不能丢失。
- 特殊窗口：画中画、沉浸式全屏和外接屏幕需要独立 Host/Outlet 策略。

已新增适配器中立的 `CCHostLayoutMetrics`、`CCDisplayFeature` 和
`CCAdaptivePresentationPolicy` 合同。Shell 负责持久化导航容器，Adaptive Layout
负责选择单列、双栏或多 Pane，Navigation Host 负责绑定实际导航栈；
`CCRoutePlacement.hostId` 和导航请求的 `hostId` 用于隔离逻辑 Host。

Size Class、主从双 Outlet、Modal 自适应、Host 隔离和多 Pane Outlet 显示切换已经接入。
当前没有创建、识别或监听 macOS、Windows、iPadOS 原生 Window，也没有维护平台
Window ID。未来 Flutter 多窗口能力稳定后，平台桥接层负责把每个 Native Window 或
Flutter View 映射到一个 Root `CCNavigationHost`，并转发创建、激活、关闭和恢复信号。
Host 仍可在单 Flutter View 中表示嵌入式独立 Router，因此不是平台 Window 本身。
平台仍需按实际设备接入 Display Feature、外接屏、PiP 和预测返回信号；完整状态恢复
只有在真实需求数据证明收益后才重新立项。

#### 12.3.1 状态恢复的当前边界

当前版本不实现 Route Restoration，也不提供 Snapshot、restore API 或路由级恢复标记。框架只通过
`CCRouteRestorationOpportunitySource` 接收 Android Activity recreation、Apple State
Restoration、桌面窗口重开或异常 Session Marker 等 Host 证据，并记录固定为 `unsupported` 的
`CCRouteRestorationOpportunityEvent`。

该事件用于评估需求，不是恢复输入。事件只能包含上次顶部 Route ID、Host/Outlet 数量、应用版本、
组件目录指纹和匿名 Telemetry Context；禁止记录完整 URI、Path/Query 参数、Arguments、Extra、账号
标识或任意业务对象。普通冷启动和单纯前后台切换不能上报为恢复机会。

后续只有在恢复机会率、受影响 Route 分布和多窗口恢复占比证明收益后才重新立项。完整实现必须满足：

- 路由显式 opt-in，支付、登录、授权、一次性确认和依赖 Extra 的页面默认禁止恢复；
- Snapshot 版本化且 Adapter-neutral，只保存可序列化的 Route ID、规范 URI 和 Host/Outlet 结构；
- 恢复时重新执行路由解析、组件可用性、安全策略和 Interceptor；
- 契约升级、路由删除、组件缺失和部分失败必须产生明确报告；
- 不持久化 Widget、BuildContext、Flutter Route、Scope 或返回 Completer。

### 12.4 Outlet 解析与 BuildContext 边界

- 当前 `CCNavigator` 没有 `BuildContext` 参数。
- Runtime 根据 Route Placement、活动 Host Resolver、Shell 和 Outlet 契约选择目标栈。
- 未显式指定非默认 Host 时，使用 Adapter 绑定的默认 Host，而不是全局 Context。
- Shell 和嵌套 Navigator 必须通过显式 Outlet 关系确定，不能用 Context 猜测结构。
- 调用级最近 Outlet 解析仅保留为未来 Flutter 门面 Proposal；即使实现，Context 也不能进入
  Intent、Route Definition、RouteEntry 或 Core Runtime。

### 12.5 混合路由兼容原则

混合路由的最高优先级是：**经过 CCRouter 的路由必须保持正确；非 CCRouter 路由尽量兼容；无法确认或兼容时，必须隔离外部变化，不能影响 CCRouter 路由。**

具体规则：

- Managed Route 的 RouteEntry、Route Scope、返回值、拦截器和生命周期由 Runtime 完整负责，Adapter 不能用不确定的后端事件覆盖这些状态。
- Foreign Navigator Route、Overlay、LocalHistoryEntry 和第三方浮层可以被观察，但没有权限关闭或修改 Managed RouteEntry。
- 外部事件缺少稳定 Backend Entry 身份时，标记为 `foreign` 或 `opaque`，只记录诊断，不根据事件类型猜测删除 CCRouter 栈。
- 系统返回、手势返回和 `maybePop` 只有在明确确认被移除的是 Managed Entry 时，才能关闭对应 Route Scope。
- 第三方路由需要完整生命周期同步时，必须通过同一 Navigator 的 Observer、`ForeignRouteBridge` 或自定义 Adapter 显式接入；未接入的外部栈按隔离模式处理。
- GoRouter Host 可通过 `CCGoRouterForeignRouteBridge` 上报第三方 Route 的稳定身份和生命周期；该 Bridge 不属于 `CCRouter.navigator` 业务 API，也不能执行页面跳转。
- 兼容性降级优先选择“状态未知但不破坏 CCRouter”，而不是“强行同步但可能误删 CCRouter 路由”。
- 所有无法兼容的外部行为必须进入有界诊断记录，并提供 Host/Adapter 层的修复入口，不能静默改变业务路由结果。

### 12.6 CCRouterApp 与 Backend 所有权

`CCRouterApp` 提供两种互不混用的接入模式。应用组合根始终显式调用
`CCRouter.initialize(components: ...)/shutdown`。新应用优先使用 managed 模式绑定 Backend；
已有应用可继续使用默认构造器作为不拥有 Runtime 的 Host Wrapper，或者将已有 Router
包装为 attach Backend。

新应用的默认 GoRouter 接入：

```dart
CCRouter.initialize(
  components: ccrouterGeneratedComponentManifests,
);

final backend = CCGoRouterBackend.managed(
  catalog: ccrouterGeneratedRouteCatalog,
  hostRoutes: [
    GoRoute(path: '/', builder: (_, _) => const HomePage()),
  ],
);

CCRouterApp.managed(
  backend: backend,
  child: MaterialApp.router(
    routerConfig: backend.router,
  ),
);
```

managed 模式负责：

- 校验 Backend Route Catalog 携带的组件身份和版本与已经注册的 Runtime 组件一致，避免
  组件安装清单与路由 Catalog 漂移。
- Adapter 绑定成功前不挂载业务 App 子树，框架使用固定的空加载态。
- Adapter 绑定失败时上报 `FlutterError` 并展示不泄露异常内容的固定安全错误 UI。
- Widget 卸载只解除 App 生命周期和 Host 挂载观察，不关闭 Runtime 或 Backend。
- 应用调用 `CCRouter.shutdown` 时先释放 Runtime、Adapter、RouteEntry、Scope 和 Listener，
  再调用 Backend dispose 释放其自有 Router。
- 不自动打开或关闭 Session；Session 继续由登录、退出、切换账号等业务流程管理。

默认非 managed 构造器只负责：

- 安装 Flutter App 生命周期监听。
- 提供供 Host/Adapter 集成代码查询的 Inherited Host 作用域。
- 挂载和卸载 `CCNavigationHost`，并拒绝同一 Host 被两个 Widget Tree 同时持有。
- 将 Flutter App 前后台状态转发给 `onLifecycleChanged` 和内部页面生命周期桥。
- 在卸载时释放 `WidgetsBindingObserver`，但不销毁 Runtime、GoRouter 或 Navigator Key。

所有权矩阵：

| 资源 | managed GoRouter | attach GoRouter | 默认 Wrapper |
|---|---|---|---|
| Runtime | `CCRouter` 持有，应用组合根显式控制生命周期 | 同左 | 同左 |
| Adapter | Runtime 初始化并销毁 | Runtime 初始化并销毁 | 应用组合根注入 Runtime |
| GoRouter | Backend 创建并在 Runtime 关闭后销毁 | 应用创建并销毁 | 应用创建并销毁 |
| Host/Key | Backend 提供，App 挂载 | 应用提供，App 挂载 | 应用或 Wrapper 提供 |
| Session | 登录/退出业务显式管理 | 登录/退出业务显式管理 | 登录/退出业务显式管理 |

`CCRouterApp` 不复制 `MaterialApp` 的 Theme、Locale、Builder 等 UI 配置，也不把 Core
绑定到 Material 或 GoRouter。它替代的是应用层手写的 Host、Observer 和 Adapter 绑定样板；实际
Flutter App 仍作为 `child` 使用 `MaterialApp.router`、`CupertinoApp.router` 或其他
Router Widget。后续 Navigator 1.0 或其他后端通过同一个 `CCRouterAppBackend` 边界接入。

`CCNavigationHost` 是独立导航所有权域，保存不可变的 Root/Outlet Navigator Key
注册表。它可以填满一个 Flutter View，也可以表示同一 View 内的嵌入式独立 Router；
未来原生多窗口桥接为每个 Native Window 或 Flutter View 创建一个 Root Host。
同一个 Host 实例必须
同时用于 `GoRouter.navigatorKey`、`CCGoRouterNavigationObserver.hostId` 和
`CCGoRouterAdapter.host`。Adapter 会在启动阶段检查 Host、Router、Shell Outlet 和
Observer 是否一致；旧的 `navigatorKeys` 参数仍作为不使用 `CCRouterApp` 时的兼容路径。
路由 Placement 中的 `hostId: default` 是“当前 Adapter 的默认 Host”别名，Runtime 在
创建 `CCNavigationRequest` 和并发键时将其解析成 Adapter 的真实 Host ID；显式填写的
非默认 Host ID 不会被重写，交给单 Host Adapter 时会明确失败。

`CCRouterApp` 不保存所谓全局 `BuildContext`。Wrapper Context 可能位于 `MaterialApp` 或 Navigator 上方，也可能在重建后失效；无 Context 导航必须使用 Adapter 持有的 `GoRouter` 或根 `navigatorKey`。

---

## 13. RouteEntry 与生命周期

每次导航创建独立 RouteEntry：

```text
CCRouteEntry<R>
├── routeEntryId
├── routeId
├── ownerComponentId
├── operational normalizedUri (Runtime private)
├── diagnostic address summary (public snapshot)
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
- 页面无需继承框架 State；需要便利回调时可以选择 Mixin 或 Listener，不接入的页面
  不受影响。

### 13.1 多维页面与弹窗生命周期

页面生命周期不使用一个枚举同时表达 App 前后台、Route 显隐和资源销毁，而是
拆成三个相互独立的维度：

| 维度 | 典型状态 | 语义和来源 |
| --- | --- | --- |
| App 生命周期 | `resumed`、`inactive`、`hidden`、`paused`、`detached` | Flutter `AppLifecycleState`；由 `CCRouterApp.onLifecycleChanged` 和内部页面桥转发，不代表原生 Window 焦点，不自动 Pop 页面、关闭 Session 或销毁 Route Scope |
| Route 可见性 | `visible`、`covered`、`hidden`、`revealed` | 当前 Outlet 是否可见，以及是否被另一个 Route 覆盖；由 Runtime 的 RouteEntry 和 Adapter/Observer 协调 |
| RouteEntry 生命周期 | `created`、`resolving`、`pushed`、`popping`、`removed`、`disposed` | 一次具体打开实例的挂载、移除和 Scope 资源释放 |

这三个维度必须保持独立：App 进入后台不代表页面被 Pop；Shell 或 IndexedStack
分支变为非活动状态通常只进入 `hidden`，不能销毁 Route Scope；页面被弹窗覆盖
也不能误判为 RouteEntry 已 `removed`。

经过 CCRouter 的 Dialog、BottomSheet 和透明 Page 都拥有自己的 RouteEntry、返回值
和 Route Scope。Navigation Aspect 观察导航尝试与最终结果，页面/Route 当前状态由
Backend Observer 确认，资源销毁由 RouteEntry 生命周期确认。未经过 CCRouter 的
`OverlayEntry`、`MenuAnchor`、`LocalHistoryEntry` 和第三方浮层属于 Foreign/Backend
生命周期；无法确认归属时，必须保持 CCRouter 的 Managed RouteEntry 不变。

Runtime 通过 `CCRouteVisibilityEvent` 提供独立的 Managed Route 可见性观察，阶段包括
`willShow`、`didShow`、`willHide` 和 `didHide`。该事件只描述页面在所属 Outlet 中的
显示与隐藏，不代表 RouteEntry 已销毁；Route Scope 释放仍以
`CCRouteEntryLifecycleState.disposed` 为准。Flutter App 前后台状态继续由
`CCRouterApp.onLifecycleChanged` 提供，不与 Route 可见性或未来原生 Window 生命周期混合。

Flutter 页面按需使用以下任一便利 API，两者共享同一个 Host 页面台账：

```dart
class _OrderPageState extends State<OrderPage>
    with CCPageLifecycleMixin<OrderPage> {
  @override
  void onPageShow() {}

  @override
  void onPageHide() {}

  @override
  void onForeground() {}

  @override
  void onBackground() {}
}

CCPageLifecycleListener(
  onPageShow: () {},
  onPageHide: () {},
  onForeground: () {},
  onBackground: () {},
  child: const OrderPage(),
);
```

`onPageShow/onPageHide` 保持 `RouteAware` 的原始 PageRoute 语义：页面 Push、上层 Route
Pop、被另一 Route 覆盖或自身移除时触发，不表示透明 Route 下的像素可见性。Widget
rebuild 不产生事件；`onForeground/onBackground` 不替代 Page Show/Hide。页面对象的
创建和销毁继续使用 Flutter `initState/dispose`，最终 Route 退出埋点使用 Aspect 或
RouteEntry removed/disposed，不提供 `onPageDispose`。

`CCGoRouterNavigationObserver.didChangeTop` 向 Host 台账报告确认后的顶部 Route，因此
Foreign Dialog、BottomSheet 和普通 Navigator Push 可以 Hide/Show Managed 页面，但
不能删除它。非 Navigator `OverlayEntry` 不产生 Page 生命周期。Stateful Shell 切换和
多 Pane 同时显示由 Host SPI 更新活动 Outlet 集合，inactive Outlet 只 Hide、不销毁
Route Scope。

后续 Aspect 事件可提供以下稳定语义，但必须注明事件所属维度和时机：

```text
before       导航决策前，可取消或重定向
found        路由匹配成功
willShow     Route/Entry 即将可见
didShow      Route/Entry 已进入可见状态
willHide     Route/Entry 即将被覆盖或离开
didHide      Route/Entry 已离开可见状态
after        本次导航成功、失败、取消或结果完成
disposed     Route Scope 已完成释放
```

`didShow`/`didHide` 不能简单等同于 `NavigatorObserver.didPush`/`didPop`；后者是
后端栈事件，前者是 CCRouter 对 Managed RouteEntry 的生命周期投影。

---

## 14. Deep Link

### 14.1 外部来源判定

`CCDeepLinkPolicy` 判断的是导航请求的可信入口来源，而不是 URI 的文本形态。完整 `https` URL 可能由应用内部主动打开，平台 Deep Link 也可能被归一化成 `/orders/100`，因此不能根据 Scheme、Host 或是否为绝对 URI 推断外部性。

Runtime 为每次导航保存框架内部的 Origin，至少区分：

```text
internal            类型安全 Intent、应用内 open
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
- 外部 Origin 只表达安全信任边界，不决定导航栈行为。三个入口通过
  `CCDeepLinkOpenMode` 独立选择 `push` 或 `go`，默认 `push`，以保留固定 Root、
  主 Tab 和返回路径。
- `CCDeepLinkOpenMode.go` 用于需要按 URI 重建声明式 Shell/Outlet location 的入口；
  它与 GoRouter `go` 一致，只结束后端确认已离栈的 Managed RouteEntry；StatefulShell
  的 inactive branch 保持存活。`open-go` 复用同一语义，不升级成 Reset。
- 类型安全 `CCRouter.navigator.reset` 是独立的 Host 级重置操作，会结束目标 Host 的
  Managed RouteEntry 后建立新 location；不能用 `go` 或外部 Deep Link mode 隐式替代。
- GoRouter 的 `push` 不等价于 StatefulShell branch 切换。外部链接需要激活另一个
  Bottom Tab 或重建父 Shell 时应选 `go`；`push` 适合当前 Navigator 上方的详情页，
  不能承诺把此前 branch 转换为一条可 Pop 的页面历史。
- `CCNavigationSource` 是业务可填写的埋点来源，不是安全信任标记；`CCNavigationSource.deepLink(...)` 本身不能启用或绕过 `CCDeepLinkPolicy`。
- Redirect 必须继承最初 Origin，直到整条导航完成，不能通过重定向绕过 Deep Link Policy。
- Redirect 到动态 URI 时必须重新执行 Host 入口白名单，不能借由已通过校验的初始地址扩大可信 Authority。
- “其他业务组件调用”属于应用内导航，Package 契约 exposure 与 Deep Link 外部来源判定互不替代。

Core 当前的 `external` 参数只作为内部实现阶段的等价信号；公开门面通过
`CCDeepLinkIngress` 收敛为固定的不可配置 Origin。`CCRouterApp`、平台 Adapter
或应用 Composition Root 负责在真实平台事件到达时调用相应入口。

### 14.2 外部导航流程

外部导航流程：

```text
Platform URI
  -> 可信 Ingress 标记外部 Origin
  -> 选择 Push（默认）或 Go 栈行为
  -> Scheme/Host 白名单
  -> Pattern 匹配
  -> Deep Link Policy 检查
  -> Codec 参数解析
  -> CCRouter 导航管线
  -> 两层拦截器
  -> Adapter
```

安全规则：

- Host 在 `CCRouter.initialize(deepLinkIngressPolicy: ...)` 中配置应用拥有的
  Scheme、Host 和有效端口；默认 `denyAll`，不接受隐式通配。
- Path-only 外部输入默认拒绝。仅当 Host 已经验证或归一化通知、扫码或 Web
  输入时，才显式设置 `allowRelativePaths: true`；它仍不能绕过路由级策略。
- User Info、缺失 Scheme/Authority/Host 的绝对输入在 Pattern 匹配前拒绝。
- Route 必须显式启用 Deep Link。
- 外部 Origin 必须由可信入口创建，不能由 URI 形态或埋点 Source 推断。
- Query 中未知参数默认忽略还是报错需要由路由策略明确声明。
- 敏感参数不得出现在 URI 中。
- 外部请求不接受 Extra。
- 所有外部导航仍经过权限和登录拦截器。
- 白名单配置必须真实参与解析流程，并有拒绝场景测试。

示例：

```dart
CCRouter.initialize(
  components: components,
  deepLinkIngressPolicy: CCDeepLinkIngressPolicy(
    allowedAuthorities: [
      CCDeepLinkAuthorityRule(scheme: 'https', host: 'm.example.com'),
      CCDeepLinkAuthorityRule(scheme: 'ccrouter', host: 'orders'),
    ],
    allowRelativePaths: true,
  ),
);

await CCDeepLinkIngress.fromPlatform(uri); // 默认 Push，保留 Root/主 Tab

await CCDeepLinkIngress.fromPlatform(
  uri,
  mode: CCDeepLinkOpenMode.go, // 按 URI 重建声明式 location
);
```

未通过入口策略时抛出 `CCDeepLinkIngressRejectedError`；匹配到路由但该路由未开放
外部访问时抛出 `CCDeepLinkRejectedError`。两类错误均不保留原 URI。

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
- `navigationId`、解析后的 Host、Outlet 和重定向链。
- 请求时间、阶段耗时和最终结果。
- Host 可选提供的匿名 `CCNavigationTelemetryContext`。

Redirect 必须保留最初来源和 `navigationId`，同时记录请求路由、实际路由和重定向链。

### 15.2 数据边界

当前 `CCNavigationAspectRequest` 不包含 Arguments、Path/Query 实际值或 Extra，只提供稳定
Route Pattern、Route ID、Host、Outlet、owner、referrer、来源和重定向链。完整 URI、页面对象、
Token、账号 ID、Extra 和返回对象不得进入 Aspect。

Runtime 明确拆分 operational address 与 retained diagnostics：

- `CCNavigationRequest`、Pending internal record 和 Adapter 原始 backend event 可以在受控调用链内
  使用完整 URI，以完成匹配、恢复和 backend 协调；
- `CCPendingNavigation`、`CCRouteEntrySnapshot`、Visibility/Entry lifecycle、Backend history 和
  Backend ledger 只暴露 `CCRouteAddressSummary`；
- 摘要只保留 canonical `routePattern` 以及 Path/Query/Fragment 是否存在；Pattern 可以包含声明期
  Path 占位符名称，但不保留 Path 值、动态 Query 名和值、Fragment 文本或第三方 backend
  location；
- Adapter 原始 `CCNavigationBackendEvent` 不进入 retained history，Runtime 在同一回调调用栈完成
  协调后转换为 `CCNavigationBackendDiagnosticEvent`；
- 需要断言精确地址的 Host/Adapter 测试必须读取其自身 Router 或 Adapter operational state，不能把
  业务诊断快照作为可重放路由状态。

数据边界迁移关系：

```text
CCPendingNavigation.uri                  -> address
CCRouteEntrySnapshot.normalizedUri       -> address
CCNavigationBackendEvent retained view   -> CCNavigationBackendDiagnosticEvent
CCRouter.backendEntries location view    -> CCBackendEntrySnapshot.address
```

参数级产品埋点投影尚未提供公开注解。未来如引入，必须使用独立的显式白名单和 Serializer，
且不能改变路由 Codec、Pattern 或类型安全契约；该能力当前属于 Proposal。

### 15.3 事件模型

Runtime 通过 `CCNavigationAspect` 产生以下只读阶段：

```text
found
arrival
show
hide
removed
disposed
lost
after
```

`CCNavigationAspectTiming` 分别提供可观测的 `resolve`、`intercept`、`dispatch`、`arrival`、
`stay` 和 `total` 耗时。空值表示阶段未发生或后端无法可靠确认，不能伪造时间。

请求级 `requested/completed/failed` 摘要由独立的 `CCNavigationLifecycleEvent` 保留；
Route Scope 资源状态由 `CCRouteEntryLifecycleEvent` 描述。它们与 Aspect 有意分离，不能把
Push Future 完成误当成页面首次到达。

### 15.4 Aspect

框架不依赖具体埋点 SDK。应用注册一个或多个具名只读 Aspect，并把安全事件投影到自己的
分析系统：

```dart
CCNavigationAspect(
  id: 'analytics',
  onArrival: recordPageView,
  onShow: recordPageView,
  onLost: recordNavigationFailure,
  onAfter: recordNavigationTiming,
)
```

- Aspect 只观察，不能取消或重定向；决策只能由 Global/Route Interceptor 完成。
- Aspect 异常必须隔离，不能阻塞导航。
- Aspect 回调中禁止同步发起导航，避免重入。
- 是否批量、采样和上传由应用集成层决定。
- Trace 用于技术诊断，Telemetry 用于产品分析，两者不能混成一个可变回调接口。

---

## 16. 路由文档生成

生成器按 Package 输出机器目录和可读目录，统一放在各 Package 的
`lib/src/ccrouter_generated/metadata/`；可执行的 Dart 聚合代码放在同一根目录下的
`route/`、`binding/`、`contract/`、`component/` 和 `host/` 子目录：

```text
cc_routes.json
cc_routes.md
```

`cc_routes.json` 用于 CI、跨端工具和文档平台；描述信息作为结构化字段保存，不使用 JSON 注释。`cc_routes.md` 用于开发者阅读。

当前 Builder 元数据使用 schema v3：除由契约形态自动推导的 `exposure` 外，还记录
可移植的源码声明位置。聚合器兼容 schema v2 的文件级定位，并拒绝其它未知 schema。

Workspace 聚合器同时校验完整组件依赖图。required dependency 缺失、自依赖以及由
required/optional dependency 共同形成的环都会让生成失败；不存在的 optional dependency
不会阻断构建，存在时则参与环检测和顺序计算。`cc_routes.json` 中的组件按与 Runtime 装配一致的
确定性拓扑顺序输出：依赖先于消费者，组件 ID 和依赖 ID 作为稳定排序依据。

应用聚合元数据与组件级元数据统一位于 Host/Package 各自的
`lib/src/ccrouter_generated/metadata/`；参与
编译的 Dart 生成代码仍写入同一根目录的职责子目录。生成文档不进入
手写 `docs/`，避免机器产物与架构设计文档混合。

标准入口是单一 `ccrouter generate` 编排命令：它复用 build_runner 生成 Package 内产物，
随后完成 Workspace 校验、组件索引、Host Catalog 和文档聚合，不实现第二套 Builder 语义。
`generate --check` 仅快照 CCRouter 管理的输出，发现陈旧产物时恢复原现场并返回非零；该门禁
不依赖 Git 工作区状态。普通生成会删除带框架生成标记但已失去组件所有者的孤立聚合索引，
不会删除手写文件或其它工具的输出。

每条路由包含：

- Route ID、主 Pattern、Path/URI/Regex 别名和正则约束。
- 所属组件，以及自动推导的 internal/package/external exposure。
- 是否支持 Deep Link。
- 参数名、来源、类型、必填性、默认值和说明。
- 返回类型。
- 两层拦截器中的路由级配置。
- Shell、父路由、Outlet 和展示意图。
- 声明 Package/源码、可用导航来源，以及固定标记为 `unsupported` 的当前恢复能力。
- 注解中的路由说明与参数 DartDoc。

当前生成一个包含全部已装配路由的应用目录，并在每条记录上保留
`internal/package/external` exposure。需要公共视图时由文档平台或只读工具按 exposure
过滤，不额外生成容易与完整目录漂移的第二份路由表。

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
```

Adapter 缺失、能力不支持和后端执行失败统一使用 `CCNavigationAdapterError`；不再保留只有
名称差异、没有独立处理语义的 Capability Error。错误包含安全消息和必要的稳定身份，原始
参数、完整 URI、Extra 和业务返回值不得默认进入错误字符串。

---

## 18. 生成阶段校验

组件级生成必须检查：

- Route ID、Pattern 和参数声明格式。
- 主 Pattern 唯一且可反向生成；`CCRegexPattern` 只能作为匹配别名。
- Path 与 URI Pattern 参数和构造参数一致。
- Query/Extra 注解不冲突。
- 参数类型存在可用 Codec。
- 生成元数据和文档不得包含运行时参数值或 Extra。
- 所有生成的公开类型和成员具有 DartDoc。

应用聚合阶段必须检查：

- Route ID 全局唯一。
- 主 Pattern、别名和正则匹配不存在确定性冲突。
- `ownerComponentId` 引用有效组件。
- 公开契约存在且仅存在一个 owner 实现，并根据契约与实现 Package 自动推导 exposure。
- 非 internal 契约由公共 barrel 显式导出；消费者声明直接 Package 依赖。
- Interceptor、Shell、父路由和 Outlet 引用有效。
- Adapter 支持所有已装配路由要求的能力。
- 同层、同具体度且能够静态证明的 Path/URI/Regex Pattern 冲突；无法证明的复杂正则
  交由 Runtime 注册阶段处理。
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

Adapter 实现者和应用组合根只通过 `package:ccrouter/ccrouter_host.dart` 使用单独导出的：

- `CCNavigationAdapter`
- `CCNavigationRequest`、`CCNavigationRoute` 与只读 Backend 快照
- Adapter capability、Host binding、Pop 协调、Predictive Back 和生命周期报告接口

页面生成 glue 只向 Host catalog 返回已有的 `CCRouteDefinition`，由
`CCFlutterRouteDestination.fromDefinition` 在 Host 边界转换成 `CCNavigationRoute`，避免业务
页面为了生成代码导入 Host SPI。业务门面不导出 Runtime 构造、内部 Route Registry、可变
RouteEntry、Scope、Adapter 控制器或上述 Host SPI。框架内部跨文件访问使用 library privacy 和
`part` / `part of`。

### 19.4 测试 API

`ccrouter_core/test` 只保留 Core 包内部实现的低层回归测试。面向框架使用者、组件作者、测试宿主、Mock、导航测试和集成测试的新增测试代码与测试 API 统一放入 `ccrouter_test` 包；该包负责提供受控 Test Host、Runtime Overlay、Adapter 替身和断言工具。业务生产代码不得导入 `ccrouter_core/src/` 或依赖 Core 内部测试入口。

---

## 20. 实现阶段

### 阶段 A：Pure Dart 路由契约

- 已实现 Route ID、Path/URI/Regex Pattern、契约 exposure、Intent、Codec 和错误。
- 已实现 `CCRegistry.registerRoute`。
- 已实现 `CCRouter.navigator` 及 `push/replace/go/reset/open/pop/canPop`、`maybePop` 和 `maybePopOutcome` 门面。
- 已实现主 Pattern 反向生成、动态 URI 解析和内存测试 Adapter。

### 阶段 B：Runtime 管线

- 已实现 Route Registry 和确定性匹配。
- 已实现两层拦截器、Redirect 循环检测和超时/Defer 语义。
- 已实现 RouteEntry、返回值、Route Scope 和生命周期。
- 已实现 Trace、`CCNavigationAspect`、安全 Telemetry Context 和分阶段耗时。

当前已实现 Route Registry 的两层拦截器基础管线：应用宿主通过
`CCGlobalNavigationInterceptor` 提供全局策略，组件通过
`CCRegistry.registerRouteInterceptor` 注册路由策略，`CCRouteDefinition.interceptorIds`
保留路由级声明顺序。拦截结果支持继续、类型安全 Intent/URI 重定向和取消；重定向
沿用原始 `navigationId` 与 `CCNavigationOrigin`，并由 Runtime 限制最大次数。RouteEntry
生命周期和 `CCNavigationAspect` 的安全快照钩子已经接入；Route Scope、拦截上下文的
真实 Deadline/Timeout 和 Defer 恢复组合导航语义已经闭环；Resolve、Intercept、Dispatch、
Arrival、Stay 和 Total 分阶段耗时已经通过 Aspect 提供。

### 阶段 C：生成器

- 已实现页面和构造参数分析。
- 已实现 Intent、Codec、Definition、注册入口和组件契约生成。
- 已实现组件所有者、Route ID、契约 exposure、公开契约实现所有权、静态 Pattern 重叠以及公开 barrel
  `show` 导出的聚合校验。
- 已实现页面级及应用聚合级 JSON/Markdown 文档导出。
- 已实现组件 `CCFlutterRouteCatalog`、窄 Host integration library 和宿主 Catalog 聚合；
  普通路由变化不再要求宿主逐条维护页面 import、`GoRoute` 与 Binding。
- 已实现 Registrar 同库的组件 Manifest 生成和宿主 Manifest 聚合；无路由的 Service
  组件同样参与安装，private Registrar 不需要成为组件公共 API。
- 已实现 Contract-first 路由的独立 Pure Dart 契约文件；页面 `@CCRoute` 固定保持内部，
  `@CCRouteImplementation` 的页面 Part 只保留 owner 注册和构造 glue，workspace 校验要求
  公共 barrel 指向生成契约。
- 已实现 `List<T>`/`Set<T>` repeated Query、自定义 `CCRouteQueryCodec<T>`、继承参数、混合
  构造器和跨 Package Codec import 校验；生成文档已包含组件版本、声明来源、Host、Shell、
  Outlet、presentation、导航来源及当前 `restoration: unsupported` 能力视图。
- 待提供可选的 Route Scaffold CLI，用于创建页面模板、计算并写入正确的
  `.route.g.dart` `part` 路径、补齐 `@CCRoute` 声明，并触发首次标准生成。该工具只改善
  开发体验，不替代 `build_runner`、Analyzer 校验或 workspace 聚合校验，也不直接修改
  已有业务页面、公共 barrel 或 GoRouter 路由树；需要公开契约和后端绑定时只生成明确的
  待办提示，避免无意扩大 API 或改写应用导航结构。

### 阶段 D：GoRouter Adapter

当前已建立 `ccrouter_go_router` 包的基础适配器边界。它将 Runtime 已解析的 Page 请求
映射到 GoRouter，并保留路由所有权、来源和 URI 由 Core 管理。普通页面构造器由组件
生成的后端中立 `CCFlutterRouteCatalog` 提供。新应用使用
`CCGoRouterBackend.managed` 自动创建 Router、Root Observer、Assembler 和 Adapter；
已有应用使用 `CCGoRouterBackend.attach` 绑定自行配置且继续自行持有的 Router。

`CCGoRouterAssembler` 消费宿主聚合 Catalog，并从同一来源生成 `routes` 和
`CCGoRouterRouteBinding`，避免路由树与 Adapter 绑定分别维护。组件 Catalog 不引用
GoRouter，因此 Navigator 1.0、其他 Navigator 2.0 或自定义后端可以提供自己的
Assembler/Adapter。Shell、嵌套 Outlet、完整 Regex 兼容入口和自定义 Redirect 继续由
应用组合根通过 `CCGoRouterRouteOverride` 显式编排，自动装配不会猜测或扁平化结构。

`CCGoRouterRouteBinding(routeId, goRoute, presentationType)` 只关联稳定的 CCRouter Route ID
与应用拥有的 `GoRoute`，并声明其 `pageBuilder` 返回的 Page 家族，不会注册、修改或销毁 `GoRouter`。当提供绑定集合时，
Adapter 初始化会校验 Runtime 路由与绑定 ID 一一对应；根页面或其他不属于
CCRouter 契约的 GoRouter 路由可以继续由应用独立保留。

当前已支持 Modal BottomSheet 和 Dialog。自动装配根据 Presentation 生成对应 Page；
手写 Override 必须由 `GoRoute.pageBuilder` 显式返回 `CCGoRouterBottomSheetPage` 或
`CCGoRouterDialogPage`。适配器不会把普通 Page 静默降级为模态展示。两类模态 Page 都保留 GoRouter
栈条目，因此 `push` Future、`pop` 返回值、遮罩/拖拽配置和生命周期仍由 Navigator
处理。Material 与 Cupertino Dialog 可通过 `CCDialogRouteType` 选择，BottomSheet
配置映射到 Flutter 的 `ModalBottomSheetRoute`。GoRouter 没有公开的原子栈事务 API，
因此 `popAndPush`、`popUntil`、`pushAndRemoveUntil` 和精确 Entry 操作当前不属于
CCRouter 能力，Adapter 也不会用多个 imperative 操作模拟。
GoRouter Adapter 优先通过 `CCNavigationHost` 接收应用拥有的 Root/Outlet Navigator，
也保留 `navigatorKeys` 兼容入口，并可把带有
`shellId`/`navigatorOutlet` placement 的子路由映射到已有 `ShellRoute` Navigator；
也可以通过 `CCGoRouterShellBinding` 一次声明 Shell 和全部分支 key。Runtime 会把
组件注册的 `CCNavigationShell` 快照交给 Adapter；Adapter 校验 Shell 类型、Outlet
集合、默认 Outlet、Outlet 顺序和实际 Navigator key。缺少绑定、绑定多余、类型不一致或 Stateful
分支顺序不一致时初始化会明确失败。已有 `StatefulShellRoute` 的分支可以通过 `go`
切换并保留 GoRouter 自己的分支状态；Shell 的 Widget、Builder 和 GoRouter Route
仍由应用创建，Adapter 不会修改应用路由树，也不会静默把目标栈改成根 Navigator。
生命周期桥使用 `CCGoRouterNavigationObserver`，由应用添加到 root Navigator、
`ShellRoute.observers` 或 `StatefulShellBranch.observers`。Observer 只发出带 Outlet
和 Host 标识的 Push/Pop/Replace/Remove 事件，适合埋点、诊断和生命周期同步；它不在回调中
保存 `BuildContext`，也不允许同步触发 CCRouter 导航。Flutter `NavigatorObserver` 不提供
Pop result，因此 `CCGoRouterNavigationEvent` 不包含 `result`；类型安全结果由原始 Managed
Push Future 管理。
`CCGoRouterAdapter` 可以通过 `observers` 参数订阅这些事件，并以
`lifecycleEventCapacity` 保留有界快照；Runtime dispose 时会自动解除订阅。外部
Deep Link 仍必须先经过 Core 的 `CCDeepLinkIngress` 和策略校验，校验通过后由
Adapter 的 `go` 进入目标 Shell 分支，不根据 URI 形态绕过策略。

Go/Pop 的精确生命周期要求所有 Managed Outlet 安装对应 Observer。覆盖完整时，Go 只根据
真实 Remove/Pop identity 结束离栈 Entry；覆盖不完整时能力声明为 false，并使用仅替换目标
Host/Outlet 分区的确定性 fallback，不跨 sibling Outlet。Pop 目标从当前 GoRouter match tree
和每个 Route 的 `parentNavigatorKey` 推导，Root Modal 覆盖 Shell branch 时优先 Pop Root；
未挂载的非 Root Outlet 不回退 Root Navigator。

- 主 Pattern、别名、Query、Extra 和返回值。
- Shell、Outlet 和生命周期同步。
- Deep Link 入口。
- `CCRouterApp.managed` 与 `CCGoRouterBackend.managed/attach` 的初始化、Host、Key、
  Adapter 和 Router 所有权闭环已完成。
- Navigator 1.0 Backend 尚未实现；它应复用相同 App Backend SPI，不修改业务导航 API。
- 调用级 `BuildContext` 最近 Outlet 解析仍是可选 Proposal，不属于当前 API。
- 各平台示例验证属于集成工作，不改变 Adapter 契约。

### 阶段 E：动态组件生命周期

- Route 和 Shell 已能按组件激活、停用，并拒绝停用组件的新导航。
- 现有活跃 RouteEntry 不因组件停用被猜测 Pop。
- Service、Handler、Scope 和依赖级联的完整动态卸载语义不属于本轮路由 API 冻结范围。

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
11. Deep Link 必须同时通过 Host 白名单、路由 Deep Link Policy 和权限拦截器。
12. 埋点记录来源、重定向链和安全字段，不泄漏 Extra 或完整 URI。
13. Observer 异常不影响导航结果。
14. 自定义 Adapter 与 GoRouter Adapter 消费相同的 Route Definition。
15. 生成的 JSON、Markdown、Intent、Codec 和 Registrar 描述一致。
16. 所有公开及内部框架声明遵守 DartDoc 和 API 隔离规则。

---

## 22. 已冻结决策与兼容性观察

### 已冻结

- 业务导航统一通过 `CCRouter.navigator`。
- 当前 `CCNavigator` 不接收 `BuildContext`；Host/Outlet 由契约和 Host Resolver 决定。
- 调用级 Context 解析仅是未来 Flutter 便利层 Proposal，不得进入 Core。
- `CCRouterApp` 负责 Flutter 集成，但不保存全局 Context。
- Core 保持 Pure Dart。
- 默认使用 GoRouter Adapter，允许自定义 Adapter。
- 生成中立 Definition，不直接生成 `GoRoute`。
- Route ID 与寻址 Pattern 分离。
- 支持一个可生成地址的主 Pattern，以及多个 Path、结构化 URI、完整 Regex 别名和参数正则约束。
- Pattern 固定按结构化 URI、Path、完整 Regex 排序；同优先级歧义显式失败。
- 使用类型安全 Intent 和生成 Codec，不以参数 Map 作为业务契约。
- 路由默认仅组件内部可见，对外契约统一通过 Contract-first 声明显式生成。
- 契约 exposure 由声明形态推导；Package 依赖决定编译期可导入范围，Runtime 不校验调用方组件身份。
- 展示契约区分 Page、模态 BottomSheet 与 Dialog；Page 和 Dialog 分别使用独立的 Route Type 表达 Flutter 对应语义。
- 业务拦截器只有 Global 和 Route 两层。
- 导航来源、安全 Aspect 快照和匿名 Telemetry Context 进入统一 Runtime 管线。
- Deep Link 外部性由可信 Ingress 创建的内部 Origin 决定，不根据 URL 形态或业务 `CCNavigationSource` 推断。
- 输出 JSON 和带 DartDoc 的 Markdown 路由文档。

### 后续兼容性观察

- 当前生成 Codec 忽略未声明的 Query 字段以保持链接前向兼容；是否提供显式 Strict 模式仍需
  依据真实安全场景评估。
- GoRouter 对 Shell、多别名和交互式返回的版本兼容范围。
- 不同平台 Host 对 Display Feature、PiP 和预测返回信号的接入覆盖。
- 原生 macOS、Windows、iPadOS Window/Flutter View 与 Root Host 的平台桥接。

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
- 统一生成 CLI 负责 Package 精确发现、增量生成、聚合和只读校验；缓存与无缓存路径必须
  生成逐字节一致的结果。

TheRouter 的完整 URL、自定义 Scheme、多 Path 和正则能力用于校准 CCRouter 的能力范围，但不照搬其不透明字符串键与正则启发式检测。CCRouter 使用显式 Pattern 类型、结构化 URI 比较和完整正则匹配，使地址生成、参数注入、冲突诊断和跨端文档都能共享同一语义。
- 多 Package 扫描改为组件 Registrar 和应用聚合校验。

不采用：

- 由 Core Generator 直接生成 `GoRoute` 或其他后端对象。
- `codes`、`exts`、原始 import 字符串和任意代码注入。
- 全局可变参数转换器、全局 Navigator 或生命周期单例。
- 页面必须继承特定 State 或混入 Widget 生命周期类型。
- 通过 Path 前缀猜测 Shell 结构。

## 24. Capability Source Catalog

组件化后 Route 的声明、契约和页面实现可能分布在不同 Package。统一生成命令因此维护一份
版本化 Capability Source Catalog，并生成便于浏览的
`lib/src/ccrouter_generated/metadata/cc_catalog.md`：

- 组件 Package 只展示本 Package 贡献的能力；Host 展示运行时依赖闭包的合并视图。
- Source Reference 使用 Package URI 与 1-based line/column，不记录本机绝对路径。
- Contract-first Route 同时关联契约声明和页面实现；普通 `@CCRoute` 的声明与实现指向同一
  页面源码。
- Package Index 是机器事实来源，Markdown、后续 `ccrouter find` 和 DevTools 视图均由其
  派生，不能各自维护扫描规则。
- 当前只发布 Route 记录。Service、Command、Action、Event 需要等静态生成链路存在后再接入，
  不从手写 Registrar 启发式推断，避免目录看似完整但实际错误。

未来 DevTools 将静态 Catalog 与 Runtime 的 Host、RouteEntry、Trace 和诊断快照按稳定 ID、
Package 版本及内容指纹关联。静态目录回答“代码和契约在哪里”，Runtime 快照回答“当前发生了
什么”；本阶段不引入 VM Service Extension 或 Inspector 依赖。
