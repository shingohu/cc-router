# CCRouter Navigator 1.0 / 2.0 Backend 可行性与实施计划

## 1. 结论

本调研基于当前 CCRouter Adapter/Host/Catalog 契约，以及本机 FVM 默认
Flutter `3.41.10-ohos-1.0.0`、Dart `3.11.5` 的 Framework 源码。

结论分为四点：

1. **Navigator 1.0 可实现可靠的渐进式 Backend**，优先解决仍使用
   `MaterialApp`、`navigatorKey`、`Navigator.push` 的既有工程；前提是每个接入的
   Navigator 都安装 CCRouter Observer，并明确 Adapter 是否拥有整个栈。
2. **Navigator 2.0 不是一个可直接适配的具体路由后端**。任意
   `RouterDelegate` 只统一提供 `setNewRoutePath`、`popRoute`、`build` 和可选
   `currentConfiguration`，没有统一的 Push、Replace、页面构建、Entry identity
   或结果通道，不能实现“万能 Navigator 2.0 Adapter”。
3. 可以实现一个 **CCRouter 自己拥有状态模型的 Pages/Router Backend**。它使用
   `RouterDelegate + RouteInformationParser + Navigator.pages`，能够完整控制页面栈、
   浏览器 URL 和系统 Back；它应被准确命名为 Pages Backend，而不是宣称适配所有
   Navigator 2.0 实现。
4. 对应用自定义 `RouterDelegate`，只能提供显式 Host Driver SPI。应用负责把
   Push/Replace/Go/Reset、栈快照和 Entry 事件接入 CCRouter；框架不能通过反射、
   `BuildContext` 或猜测 Delegate 内部状态完成自动适配。

推荐顺序是：先实现 Navigator 1.0 root Outlet 最小闭环，再补混合路由和多 Outlet；
Pages Backend 作为下一独立阶段。暂不实现通用 RouterDelegate attach。

## 2. 当前架构提供的基础

以下现有能力可以直接复用，不需要重做业务路由模型：

- `CCFlutterRouteCatalog` 已提供 Route Definition 与 Flutter 页面 Builder；
- `CCNavigationAdapter` 已固定 Push、Replace、Go、Reset、Open、Pop、MaybePop、
  CanPop 和同步 Dispose 语义；
- `CCNavigationHost` 已持有 root 及命名 Outlet 的 `GlobalKey<NavigatorState>`；
- Runtime 已维护 Managed/Foreign/Opaque Backend Entry 台账，不会按栈位置猜测 Pop；
- `CCNavigationBackendEvent` 已包含 Entry ID、Operation ID、Host、Outlet、前序 Entry、
  Owner 和可见性事件；
- `CCNavigationHostRegistry` 已支持多个独立 Host；
- Route Presentation 已覆盖 Material、Cupertino、透明 Page、自定义 Transition、
  Dialog 和 Modal BottomSheet；
- Runtime 在 Adapter 能力不足时已有显式错误和有界降级诊断边界。

当前 GoRouter 包中的 `CCGoRouterPage`、`CCGoRouterBottomSheetPage` 和
`CCGoRouterDialogPage` 实际是 Flutter `Page`/`Route` 工厂，不依赖 GoRouter 匹配逻辑。
这部分已提取为 `ccrouter` Host-only 层的 `CCFlutterRouteFactory`、
`CCFlutterPage`、`CCFlutterBottomSheetPage` 和 `CCFlutterDialogPage`。现有 GoRouter
API 通过兼容包装继续保留原类型和函数名；新 Backend 必须复用中立 Factory，不得复制
Material、Cupertino、透明转场、Dialog 或 BottomSheet 的 Presentation 实现。

## 3. Flutter API 事实

### 3.1 Navigator 1.0

`NavigatorState` 原生具备以下能力：

- `push` 和 `pushReplacement` 返回 Route 的 `popped` Future，可保留类型安全结果；
- `pop`、`maybePop` 和 `canPop` 支持系统 Back、`PopScope` 和 Route 内部 Pop；
- `NavigatorObserver` 提供 `didPush`、`didPop`、`didRemove`、`didReplace`、
  `didChangeTop` 和手势回调；
- Dialog、Modal BottomSheet 和普通 Page 都可以作为真实 Route 压入同一 Navigator；
- `LocalHistoryEntry` 被消费时 `Route.didPop` 返回 false，不触发真实 Route 移除；
- `OverlayEntry`、`MenuAnchor` 和第三方自建 Overlay 不属于 Navigator 栈。

因此，只要 Observer 覆盖完整，Adapter 可以精确区分 Managed Route、同 Navigator 上的
Foreign Route，以及没有发生 Route 移除的 LocalHistory/Overlay 行为。

### 3.2 Navigator 2.0 / Pages API

Flutter 的 `RouterDelegate<T>` 只规定：

- 外部 RouteInformation 到来时调用 `setNewRoutePath(T)`；
- 系统 Back 调用 `popRoute()`；
- `build()` 返回当前导航 Widget；
- 可选 `currentConfiguration` 用于浏览器历史和状态恢复。

它没有规定如何 Push、Replace、选择 Outlet、创建 Page、标识 Entry 或传递 Pop result。
这些都是具体 Router 的状态模型。GoRouter 已经是其中一种具体实现，现有
`ccrouter_go_router` 正是适配这个具体模型，而不是“适配 Navigator 2.0”本身。

`Navigator.pages` 在 Flutter 3.41 使用 `onDidRemovePage` 同步应用状态；旧的
`onPopPage` 已弃用。`onDidRemovePage` 不携带 Pop result，因此 Pages Backend 必须让
自有 Page 在 `createRoute` 时绑定 `Route.popped`，用精确 Route/Entry 句柄完成结果 Future，
不能从 Observer 事件中猜测结果。

Pages Navigator 允许在 Page-based Route 上方 Push pageless Route。Flutter 会把这些
pageless Route 绑定到下方 Page；移除该 Page 时，上方 pageless Route 也可能一并移除。
Backend 必须消费完整 Observer 事件并按 Route identity 更新 Foreign/Managed 台账。

## 4. 能力矩阵

| 能力 | Navigator 1 owned | Navigator 1 shared attach | CCRouter Pages Backend | 任意 RouterDelegate attach |
| --- | --- | --- | --- | --- |
| 类型安全 Push / result | 可完整实现 | 可完整实现 | 可完整实现 | 无统一接口，需 Driver |
| Replace / result | 可完整实现 | 可完整实现 | 可完整实现 | 需 Driver |
| 动态 URI Open-Push | Runtime 解析后可完整实现 | 可完整实现 | 可完整实现 | 需 Driver |
| root Route Go | 可清理自有 Outlet 后重建 | 默认不可清理共享栈 | 可由 Pages 模型原子提交 | 需 Driver |
| root Host Reset | 单 Outlet 可完整实现 | 仅显式授予栈所有权后可用 | 可由 Pages 模型原子提交 | 需 Driver |
| Parent/Shell Go 重建 | 需 Route Tree/Host Binding | 不自动支持 | 需 Pages Shell Binding | 需 Driver |
| Pop / MaybePop / CanPop | 可完整实现 | 可完整实现 | 可完整实现 | `popRoute` 只有 Boolean，不足以确认 Owner |
| 外部直接 Navigator Push/Pop | 完整 Observer 下可兼容 | 完整 Observer 下可兼容 | 同 Navigator 的 pageless Route 可兼容 | 取决于 Driver |
| Dialog / BottomSheet | 可作为真实 Route 支持 | 可支持 | 可作为 Page-backed Route 支持 | 取决于具体 Router |
| LocalHistory / Overlay | 不误删 Managed Entry | 不误删 Managed Entry | 不误删 Managed Entry | 无 Driver 时不可观察，但不得影响 CCRouter |
| 多 Outlet | 显式绑定后可实现 | 显式绑定后可实现 | 自有模型可实现 | 需 Driver |
| Stateful Shell | 不是 Navigator 1 原生概念，需 Host Coordinator | 需 Host Coordinator | 可通过多分支 Pages 模型实现 | 需 Driver |
| Web URL / 浏览器前后退 | 不提供 Router 信息同步 | 由宿主自行负责 | 可完整实现 | 由应用 Delegate 负责 |
| Predictive Back | 后续显式 Bridge | 后续显式 Bridge | 后续显式 Bridge | 取决于 Driver |
| State Restoration | 当前仅记录机会，暂不承诺 | 同左 | Router 原生可承载，但 CCRouter 仍暂缓 | 由应用负责 |
| 多 Host / Flutter View | 每 Host 一个 Backend，可组合 | 可组合 | 可组合 | 每 Host 独立 Driver |

## 5. 关键设计问题

### 5.1 Go/Reset 不能在共享栈中猜测

对 Navigator 1.0 直接调用 `pushAndRemoveUntil(..., (_) => false)` 虽然能制造清栈效果，
但会删除宿主根页面、第三方 Route 或未纳入 CCRouter 的业务页面。它违反“经过 CCRouter 的
路由不出错，非 CCRouter 的尽量兼容，无法兼容也不能影响 CCRouter”的混合路由原则。

因此必须区分：

- **owned stack**：Backend 拥有目标 Navigator 的完整栈，可以执行 root Go/Reset；
- **shared stack**：Backend 只拥有自己创建的 Entry。Push、Replace 和 Pop 可用，Go/Reset
  在没有 Host Driver 时必须在任何栈变更前抛出稳定能力错误；
- **bounded stack**：宿主显式提供可重建边界和 Driver，由宿主定义固定 Main Tab/root 如何保留。

不提供默认 Route predicate，不根据 Route name、当前位置或“第一个页面”猜边界。

### 5.2 Nested Parent 和 Shell 需要 Host 结构

一个最终 `CCNavigationRequest` 只表示已解析目的地，不能凭空得到宿主 Shell Widget、各分支
Navigator、父页面业务参数和自适应布局。因此：

- 普通 root Route 可以自动装配；
- `parentRouteId`、`shellId` 或非 root Outlet 必须匹配显式 Host Binding；
- Stateful Shell 必须由 Host 提供分支容器、Outlet key 和激活事件；
- Backend 初始化时校验 Catalog、Runtime Shell 与 Host Binding 一致，缺失时直接失败。

### 5.3 Observer 覆盖决定精确生命周期

只有所有受管 Navigator 都安装同一个 Backend 创建的 Observer，Adapter 才能声明：

- `supportsBackendVisibilityObservation = true`；
- `supportsManagedPopObservation = true`。

覆盖不完整时，两项能力必须为 false。未知 Pop 只能进入诊断，不能删除 Runtime 顶部
RouteEntry。独立第三方 Navigator 未绑定时保持隔离；需要纳入生命周期时，由 Host 使用
显式 Foreign Route Bridge 或 Driver 上报。

### 5.4 Navigator 挂载时序

Navigator 1 Adapter 依赖 `GlobalKey<NavigatorState>.currentState`，而 Navigator State 只有
Widget 挂载后才存在。禁止保存全局 `BuildContext`、静默排队无限期请求或把未挂载当成初始化成功。

当前 `CCRouterApp.managed` 在自身 `initState` 同步 attach，然后才挂载 descendant
`MaterialApp`/`Navigator`。Navigator 1 Backend 此时无法验证 `currentState` 和 Observer。
反过来把 `CCRouterApp.managed` 放入 Navigator 的初始 Route 虽然能拿到 State，但后续 Push
产生的是该初始 Route 的兄弟节点，不在 CCRouterApp 的 Inherited Host scope 下，页面生命周期
Mixin/Listener 会失效。两种直接拼接方式都不应进入正式 API。

阶段 0 必须先增加一个窄的 Host readiness handshake：

- `CCRouterApp` 仍位于 `MaterialApp`/Router 之上，确保所有 Route 都继承同一 Host scope；
- Navigator package 提供 root Outlet bootstrap，只挂载 Navigator 基础结构，在 Backend attach
  成功前不挂载业务入口子树；
- Backend 在 key 已挂载、Observer 已绑定后发出一次 ready 信号；
- CCRouter 的现有绑定协调器收到 ready 后再原子 attach Adapter；
- ready 前不接受业务导航，不缓存任意数量的请求；失败时不转移 Adapter 所有权；
- attach 后若 Navigator 被替换或 Observer 脱离，Host 进入明确 detached/error 状态，不继续导航。

这个 handshake 属于 Host/Backend SPI，不进入业务 barrel，也不能改变 GoRouter Backend 当前的
同步 ready 快路径。没有完成该前置改造前，不应开始实现 Navigator 1 Adapter。

Pages Backend 的状态模型可在 Router Widget 挂载前接受配置，因此没有相同的 key readiness
问题；Page 实际渲染仍由正常 Flutter 生命周期负责。

### 5.5 Presentation 不能复制两套

Navigator 1 使用 `Route`，Pages Backend 和 GoRouter 使用 `Page.createRoute`，但 Material、
Cupertino、透明度、转场、Dialog、BottomSheet 的契约相同。应提取中立 Factory：

```text
CCRoutePresentation
        |
        v
CCFlutterRouteFactory (Host-only)
        |-- createRoute(...)
        `-- createPage(...)
```

现有 `ccGoRouterPage` 等 API 保留为兼容包装。组件和业务仍看不到 Factory、Navigator 或
Adapter 控制对象。

## 6. 推荐包与 API 边界

新增一个可选 Flutter 包 `ccrouter_navigator`，避免把 Navigator 实现放入 Core：

```text
ccrouter_contracts       Adapter-neutral contracts
ccrouter_core            Runtime / Registry / lifecycle
ccrouter                 Flutter Host / neutral Catalog / Route Factory
ccrouter_go_router       Existing concrete GoRouter backend
ccrouter_navigator       Navigator 1 backend + owned Pages backend
```

`ccrouter_navigator` 的 Host API 建议包括：

- `CCNavigatorBackend`：Navigator 1.0 managed/attach 资源所有者；
- `CCNavigatorAdapter`：只由 Backend 转交 Runtime；
- `CCNavigatorNavigationObserver`：每个绑定 Outlet 的精确事件源；
- `CCNavigatorOutletBinding`：key、observer、栈所有权和 Outlet identity；
- `CCPagesRouterBackend`：CCRouter-owned RouterDelegate/Parser/Provider；
- `CCPagesShellBinding`：宿主提供的 Shell Widget 与持久分支结构；
- 后期按真实需求增加 `CCNavigator2Driver`，仅供自定义 RouterDelegate 的 Host 接入。

业务 API 不新增第二套导航调用，仍只使用：

```dart
CCRouter.navigator.push(...);
CCRouter.navigator.replace(...);
CCRouter.navigator.go(...);
CCRouter.navigator.reset(...);
CCRouter.navigator.pop(...);
```

不公开 Route 台账、可变 Pages List、Observer 发布方法、Runtime 销毁入口或任意
`BuildContext` 导航接口。

## 7. 分阶段实施计划

### 阶段 0：共享 Flutter Route Factory

当前进度：Factory 提取、GoRouter 兼容包装和 Presentation 回归测试已完成；Host
readiness handshake 与 root Outlet bootstrap 仍未实现，不能据此宣称 Navigator 1 Backend
已经可用。

1. 将 Page/Route Presentation 构建从 `ccrouter_go_router` 提取到 `ccrouter` Host-only 层；
2. GoRouter 旧函数和类型使用兼容包装，行为与 public API 不变；
3. 为需要 Widget 挂载的 Backend 增加 Host-only readiness handshake 和 root Outlet bootstrap，
   保持 GoRouter 同步 attach 行为不变；
4. 对 Material、Cupertino、透明 Page、五种 Transition、Dialog 和 BottomSheet 做快照式 Widget
   回归；
5. 验证 `ccrouter.dart` 业务 barrel 不新增 Host SPI，并覆盖 ready、失败、卸载和重复绑定顺序。

预计 2～4 个工程日。

### 阶段 1：Navigator 1 root Outlet 最小闭环

1. 新建 `ccrouter_navigator` Package；
2. 实现 routeId 到 `CCFlutterRouteDestination` 的 O(1) 索引；
3. 实现 Managed Route identity、Push/Replace/result、Pop/MaybePop/CanPop；
4. 实现 Open-Push、普通 Page、透明 Page、Dialog 和 BottomSheet；
5. 安装 Observer，产生 Push/Replace/Pop/Remove/TopChanged 事件；
6. owned root 栈支持 root Go/Reset；shared attach 对 Go/Reset 在变更前返回能力错误；
7. root Outlet bootstrap 在 Observer ready 后才放行业务入口子树；
8. Adapter dispose 只解除监听和完成自有 pending，不销毁应用 Navigator。

阶段 1 不声明 Nested Navigator、Stateful Shell、Predictive Back 或 Restoration 能力。

预计 4～6 个工程日。

### 阶段 2：混合路由、多 Outlet 和 Host

1. 增加显式 `CCNavigatorOutletBinding`，逐 Outlet 校验 key 与 Observer；
2. 同 Navigator 的普通 Route、PopupRoute 和直接 `Navigator.pop(result)` 进入 Foreign/Managed
   精确台账；
3. LocalHistory、Overlay、MenuAnchor 和未绑定 Navigator 不改变 Managed RouteEntry；
4. 接入 `CCNavigationHostRegistry`，验证两个 Host 和多个 Flutter View 的隔离；
5. 增加 Host-owned Shell Coordinator，上报 `outletActivated/outletsChanged`；
6. Observer 覆盖完整后才开启 Visibility 和 Managed Pop capabilities。

预计 4～6 个工程日。

### 阶段 3：CCRouter-owned Pages Backend

1. 定义不可变 Pages Stack Model，每个 Entry 使用稳定 `backendEntryId` 和 Page key；
2. 实现 RouterDelegate、RouteInformationParser、RouteInformationProvider 和 BackButtonDispatcher；
3. Push/Replace/Go/Reset 先计算完整新状态，再一次提交并通知，避免部分栈更新；
4. Page `createRoute` 绑定 `Route.popped`，保留类型安全结果；
5. `onDidRemovePage` 只更新模型，不从列表位置猜 Owner；
6. 增加 Parent/Shell/Stateful Branch Binding 和浏览器前进后退回归；
7. 与 GoRouter 使用同一 Route Definition、Catalog 和 Presentation Factory。

预计 8～12 个工程日。这个阶段必须独立提交和 A/B Demo，不与 Navigator 1 Backend 混在一次
变更中。

### 阶段 4：自定义 RouterDelegate Driver（按需）

只有出现真实应用需求时才定义 Host-only `CCNavigator2Driver`。Driver 至少必须提供：

- 支持的操作与结构能力；
- Push/Replace/Go/Reset/Pop 的确定语义；
- 初始完整栈快照；
- identity-bearing Entry 事件；
- Host/Outlet/Shell 归属；
- 同步初始化、同步 dispose 和异步操作失败边界。

缺少任一项时不得声明精确 Managed Pop 或 Visibility。预计 SPI 与测试 3～5 个工程日，具体
应用 Driver 成本另计。

## 8. 测试与验收门槛

每阶段至少覆盖：

1. Push、Replace、Go、Reset、Open-Push、Open-Go、Pop、MaybePop 和返回结果；
2. 系统 Back、iOS 手势、`PopScope` 拒绝、LocalHistory 消费；
3. Dialog、BottomSheet、普通 PopupRoute、OverlayEntry、MenuAnchor；
4. 同 Navigator 的 Foreign Push/Pop 不误删 Managed Entry；
5. 未绑定独立 Navigator 永远不影响 CCRouter 台账；
6. root、Shell、Stateful Branch、多 Outlet 与多 Host 隔离；
7. 页面可见性、RouteEntry 生命周期、Aspect、Failure 和 Trace 顺序；
8. Adapter attach/dispose 幂等，应用拥有的 Navigator/Router 不被销毁；
9. pending result 在 Pop、Replace、Go、Reset、Host detach 和 Runtime dispose 时确定终止；
10. `leak_tracker_flutter_testing` 验证 Observer、Route、Completer、Listener 和 Host 不残留；
11. 250 次以上 Push/Pop 台账有界回归，以及并发导航和重入拒绝；
12. Generator、Framework、Demo、macOS 真机与 Web 浏览器历史回归。

## 9. 暂不承诺的能力

- 不提供可自动适配任意 `RouterDelegate` 的通用 Navigator 2.0 Adapter；
- 不在 shared Navigator 栈中自动清除 Foreign Route；
- 不根据 Route name、Widget 类型或栈位置推断 Entry Owner；
- 不把 Overlay、Menu 或 persistent BottomSheet 伪装成 CCRouter Route；
- 不在首版恢复跨进程 Route result、任意 Extra 或完整 Stateful Shell 栈；
- 不因 Flutter 提供 restorable API 就提前宣称 CCRouter 已支持状态恢复；
- 不为未完整绑定 Observer 的 Navigator 声明精确生命周期能力。

以上限制不是功能缺失的掩盖，而是保证混合路由、生命周期和所有权不会因后端差异而失真。
