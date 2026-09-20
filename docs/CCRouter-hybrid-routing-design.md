# CCRouter 混合路由改造设计

## 文档状态

- 版本：v0.2
- 状态：当前设计已实现；预测返回需由 Host 显式启用，完整路由状态恢复仍暂缓
- 适用范围：CCRouter、GoRouter、Flutter Navigator、第三方 Popup 和多 Window Host
- 关联设计：[CCRouter 路由子系统设计](CCRouter-route-design.md)

## 1. 总体原则

混合路由的最高优先级是：

> 经过 CCRouter 的路由必须保持正确；非 CCRouter 路由尽量兼容；无法确认或兼容时，必须隔离外部变化，不能影响 CCRouter 路由。

兼容性策略按以下顺序执行：

1. 优先保证 Managed Route 的 RouteEntry、Route Scope、返回值和生命周期正确。
2. 尽量观察和兼容 Foreign Route 及第三方 UI。
3. 无法建立可靠关联时进入隔离或 opaque 状态。
4. 禁止根据不完整事件猜测删除 CCRouter RouteEntry。

## 2. 路由分类

### 2.1 Managed Route

由 CCRouter 创建并管理的路由，包括普通页面、跨组件页面、需要类型安全返回值的 Dialog 或 BottomSheet，以及需要拦截、埋点、Deep Link 或 Route Scope 的业务流程。当前只记录脱敏的状态恢复需求，不执行路由状态恢复。

Managed Route 才拥有 `CCRouteEntry`、Route Scope、类型安全结果和 CCRouter 生命周期。

### 2.2 Foreign Navigator Route

通过同一个或其他 Navigator 创建，但没有由 CCRouter 创建的 Route，例如 `showDialog`、`showCupertinoDialog`、`showGeneralDialog`、第三方 PopupRoute、应用直接 Push 的 GoRoute，以及系统或宿主创建的页面。

Foreign Route 可以被观察，但没有权限关闭或修改 Managed RouteEntry。

### 2.3 Foreign UI

不属于 Navigator 栈的 UI，包括 `OverlayEntry`、`MenuAnchor`、`ScaffoldState.showBottomSheet` 使用的 `LocalHistoryEntry`、第三方 Overlay 系统和页面内部临时展示状态。

Foreign UI 默认不创建 CCRouter RouteEntry，不创建 Route Scope，也不参与 CCRouter 返回值语义。

## 3. Backend Entry 台账

Adapter 和 Runtime 之间增加适配器中立的后端条目模型。当前已提供不可变的
`CCBackendEntry` 台账快照，并通过 `CCRouter.backendEntries` 和
`CCRouter.activeBackendEntries` 提供诊断访问：

```text
CCBackendEntry
├── backendEntryId
├── owner: managed | foreign | opaque
├── routeEntryId?
├── navigationId?
├── routeId?
├── hostId
├── navigatorOutlet
├── location?
├── lifecycleState
└── visibilityState: visible | hidden | unknown
```

规则：

- `managed` 条目由 CCRouter 创建，可以驱动 RouteEntry 生命周期；
- `foreign` 条目由外部 Navigator 或第三方组件创建，只参与观察；
- `opaque` 条目无法可靠识别，只保留隔离状态和诊断信息；
- Backend Entry 是否仍在栈内与是否为 Outlet 当前页是两个独立维度；
- 只有明确关联到 `routeEntryId` 的条目才能关闭 Route Scope；
- 未知外部 Push/Pop 不得默认清空或删除 Managed 栈。

## 4. Backend 事件关联

仅根据 `push`、`pop`、`replace` 事件类型关联是不安全的。当前后端事件契约已预留并由
GoRouter Adapter 填充以下身份字段：

```text
backendEntryId
backendOperationId
navigationId?
previousEntryId?
hostId
navigatorOutlet
sequence
```

事件处理必须按 Host 和 Outlet 分区、串行处理、支持重复事件去重、检测事件序列断层、区分 CCRouter 发起的操作和外部操作，并在关联失败时进入 `opaque` 或 `desynchronized` 状态，而不是猜测删除。Push、Pop、Replace 和 Remove 只描述结构变化，页面显示状态由 `topChanged` 确认；StatefulShell 分支切换由 `outletActivated` 确认。

## 5. Pop 协调

`maybePop` 的布尔结果无法表达被移除条目的所有权，因此当前使用：

```text
CCPopOutcome
├── handled
├── removedBackendEntryId?
├── removedOwner: managed | foreign | opaque | none
├── trigger: system | gesture | predictiveBack | business | unknown
├── guardDeniedCode?
└── hostId?
```

处理规则：

- 系统返回、手势返回和预测返回优先经过 Adapter 的 Pop Coordinator；
- Pop 被 `PopScope`、表单保护或手势状态拒绝时，Managed Route 保持存活；
- Foreign Popup 消费返回时，只移除 Foreign Entry；
- 只有 `removedOwner == managed` 时，Runtime 才关闭对应 Route Scope；
- Typed result 继续由原始 Managed Push Future 管理，不放入 `CCPopOutcome`；
- 第三方 Route 的结果不能转换为 CCRouter 的泛型返回值；
- `LocalHistoryEntry` 被消费时不能误认为页面 Route 已经移除。

## 6. 外部路由接入

`CCRouterApp` 作为 Host 注册中心，管理 Root Navigator、Shell Navigator、第三方 Navigator、Window/Display Host、Observer、Outlet 和生命周期桥接。

第三方路由有两种接入方式：

1. 使用 CCRouter 已绑定并观察的同一个 Navigator；
2. 通过 `ForeignRouteBridge` 或自定义 Adapter 显式上报栈变化。

独立 Navigator 未绑定时，按隔离模式处理，不自动纳入 CCRouter，也不影响 CCRouter 栈。Overlay、LocalHistoryEntry 和无法观察的第三方浮层如果需要诊断，必须显式提供 Bridge；没有 Bridge 时只保证不影响 Managed Route。

当前 GoRouter 集成提供 Host-only 的 `CCGoRouterForeignRouteBridge`。应用组合根可以用
稳定 Handle 显式上报第三方 Route 的 Push、Replace、Pop 和 Remove；Bridge 只产生
Foreign Backend Entry 诊断，不执行导航，也不创建 RouteEntry、Route Scope 或业务结果。

## 7. Modal 与 BottomSheet 策略

所有弹窗不默认经过 CCRouter。

### 不经过 CCRouter

确认提示、Toast、Menu、页面内部筛选面板、一次性帮助提示、临时 BottomSheet、Overlay 和第三方临时浮层。

### 经过 CCRouter

跨组件打开、需要类型安全参数或返回值、需要权限或登录拦截、需要独立埋点或 Route Scope、需要 Deep Link，以及属于完整业务流程的 Dialog 或 BottomSheet。未来若实现状态恢复，也只覆盖显式加入恢复契约的 Managed Route。

`CCDialogPresentation` 和 `CCModalBottomSheetPresentation` 表示被 CCRouter 管理的模态目的地，不代表所有 Flutter Dialog 或 BottomSheet。

## 8. Adapter 能力声明

Adapter 初始化时声明能力：

```text
supportsBackendVisibilityObservation
supportsNestedNavigators
supportsStatefulShell
supportsModalRoutes
supportsPredictiveBack
supportsManagedPopObservation
```

Runtime 根据能力选择正常执行、明确记录的降级实现或初始化失败。组合栈事务和精确 Entry 操作当前不属于基础 Adapter 能力；后续只有在稳定身份、原子提交、混合栈隔离、失败回滚和生命周期语义完整时，才通过可选版本化 SPI 重新接入。禁止静默把有返回值的组合操作降级为无法保证语义的多个操作。

Foreign/Opaque 变化通过事件身份和 Bridge 隔离，不以一个宽泛 Capability Boolean 承诺。
初始栈快照同样不使用 Capability Boolean：支持该能力的 Adapter 实现可选 SPI
`CCNavigationBackendSnapshotSource`，不实现时 Runtime 只从开始观察后的事件建立台账，
不得猜测观察前的外部栈。

## 9. 多 Window 与自适应布局

当前 `hostId` 已进入 `CCNavigationRequest`、`CCRouteEntrySnapshot`、`CCBackendEntry`、后端事件和诊断记录。`CCNavigationHostRegistry` 将默认 Placement 动态解析到活动 Host，同时保持显式 Host 路由固定归属。

不同 Window、折叠屏 Pane、外接显示器和多 Display Host 的导航栈相互隔离。Route Contract、Intent 和参数保持一致，呈现方式由 Host、Shell 和 Adaptive Layout 决定。Host 卸载只销毁该 Host 的 Managed Entry 和 Scope，不把 Live Route 隐式迁移到其他窗口。

## 10. 分阶段实施

### 阶段一：修复错误同步

- [x] 外部未知 Push/Pop 不再直接修改 CCRouter 栈；
- [x] 增加第三方 Popup 不关闭底层 Route Scope 的测试；
- [x] 修复 `maybePop` 对 `LocalHistoryEntry` 的误判；
- [x] 外部事件无法关联时记录有界诊断。

### 阶段二：Backend Entry 台账

- [x] 增加 `CCBackendEntry`；
- [x] 增加 Managed/Foreign/Opaque 所有权；
- [x] 增加 `backendEntryId`、操作 ID 和事件序列；
- [x] Runtime 默认仅将身份事件写入台账；只有声明支持 Managed Pop 观察且带完整 identity
  的事件，才关闭对应 RouteEntry，不按顶部位置猜测删除；
- [x] 增加初始后端栈快照，并在台账中保留 Host/Outlet 分区；
- [x] 将 Pop 协调升级为显式 `CCPopOutcome`，旧 Adapter 仍可通过 Boolean API 降级。

### 阶段三：Pop Coordinator

- [x] 引入 `CCPopOutcome`；
- [x] Managed outcome 才允许 Runtime 关闭对应 RouteEntry，Foreign/Opaque/None 只返回诊断；
- [x] 统一系统返回、手势返回、预测返回和业务 Pop；
- [x] 完善 Pop 拒绝、结果和生命周期语义；
- [x] 业务 `CCRouter.navigator.pop` 通过 ownership-aware coordinator 执行，Foreign/Opaque
  Entry 不会关闭底层 Managed RouteEntry；
- [x] 预留预测返回 Adapter SPI，只有 committed 且可关联 Managed identity 的事件才允许
  关闭 RouteEntry；started、updated、cancelled 都不会销毁 Scope；

系统返回和手势返回已经通过 `maybePopOutcome` 进入同一 ownership 判定管线；预测返回仍由
`supportsPredictiveBack` 能力声明控制，GoRouter Adapter 默认不支持，但可由宿主显式开启
`enablePredictiveBack` 并通过 Host-only Bridge 转发平台阶段事件；未开启时仍保持保守隔离。
同步 `CCPopGuard` 在 Managed Entry 的业务 Pop、系统返回和手势进入 Adapter 前执行；
Predictive Back Host 必须在 commit 前调用 Bridge 的 `evaluateStart`。Foreign、Opaque 和
`LocalHistoryEntry` 不运行底层 Managed Entry 的 Guard。异步确认继续由 Flutter
`PopScope` 承担。

### 阶段四：Foreign Route Bridge

- [x] 支持第三方 Navigator 通过 Host Bridge 显式上报；
- [x] 支持外部 Route 的身份和生命周期观察；
- [x] 为 Overlay 和 LocalHistoryEntry 提供可选诊断桥；
- 不把 Foreign UI 暴露为业务路由 API。

Adapter 能力声明已提供为可选的 `CCNavigationAdapterCapabilitySource` SPI。
GoRouter 和内存 Adapter 会声明各自已实现的可见性观察、Managed Pop 观察、组合导航、
嵌套 Navigator、模态路由和精确 Entry 操作能力；Runtime 已在初始化和组合导航执行前进行能力校验，
不再静默降级为无法保证语义的操作。

### 阶段五：Host 与多 Window

- [x] 完成单 Host 的不可变 Root/Outlet Key 注册、挂载、卸载和重复绑定校验；
- [x] 让 GoRouter、Observer、Adapter 和 Backend Event 使用同一个 Host ID；
- [x] 将 Route Placement 的 `default` Host 解析成 Adapter 绑定的真实 Host ID；
- [x] 增加独立于 Route 可见性的 Flutter Host 前后台生命周期事件；
- [x] 建立 Runtime 多 Host Registry 和动态 Host Resolver；
- [x] 增加 Window/Display 隔离；
- [x] 支持 Size Class 驱动的单 Pane、双 Pane 和多 Pane Outlet 显示切换；
- [x] Host 卸载时精确清理所属 Entry、Scope、pending result 和 listener bridge。

## 11. 验收用例

1. CCRouter 页面通过系统返回正常 Pop。
2. 第三方 Popup Push/Pop 不关闭底层 Route Scope。
3. 第三方 Popup 消费系统返回时，底层 CCRouter 页面保持不变。
4. 直接 `showDialog`、`showModalBottomSheet` 不修改 CCRouter 栈。
5. `showBottomSheet` 的 LocalHistoryEntry 不误删 CCRouter 页面。
6. OverlayEntry 和 MenuAnchor 不产生 CCRouter RouteEntry。
7. CCRouter 管理的 Dialog Pop 正确关闭 Managed Entry。
8. 第三方独立 Navigator 不影响 CCRouter。
9. `maybePop` 被拒绝时 RouteEntry 保持存活。
10. 直接 `Navigator.pop(result)` 能完成 CCRouter 自己的 Push Future。
11. 多 Shell 分支上的 Foreign Popup 只影响所属 Outlet。
12. 多 Window 的 RouteEntry 和 Backend Entry 互不串扰。

## 12. 非目标

- 不接管第三方 Overlay 的内部实现；
- 不把所有弹窗强制转换成 CCRouter Route；
- 不为无法提供身份和事件的外部 UI 编造类型安全返回值；
- 不因为兼容第三方路由而牺牲 Managed Route 的生命周期正确性。
