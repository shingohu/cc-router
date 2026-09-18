# CCRouter 混合路由改造设计

## 文档状态

- 版本：v0.1 Draft
- 状态：阶段一已实现，阶段二核心台账已实现，阶段四桥接和能力声明已部分实现
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

由 CCRouter 创建并管理的路由，包括普通页面、跨组件页面、需要类型安全返回值的 Dialog 或 BottomSheet，以及需要拦截、埋点、Deep Link、恢复或 Route Scope 的业务流程。

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
├── routeId?
├── hostId
├── navigatorOutlet
├── location?
└── lifecycleState
```

规则：

- `managed` 条目由 CCRouter 创建，可以驱动 RouteEntry 生命周期；
- `foreign` 条目由外部 Navigator 或第三方组件创建，只参与观察；
- `opaque` 条目无法可靠识别，只保留隔离状态和诊断信息；
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

事件处理必须按 Host 和 Outlet 分区、串行处理、支持重复事件去重、检测事件序列断层、区分 CCRouter 发起的操作和外部操作，并在关联失败时进入 `opaque` 或 `desynchronized` 状态，而不是猜测删除。

## 5. Pop 协调

`maybePop` 不能只使用一个布尔值表示结果。建议引入：

```text
CCPopOutcome
├── handled
├── removedBackendEntryId?
├── removedOwner: managed | foreign | none
└── resultAvailable
```

处理规则：

- 系统返回、手势返回和预测返回优先经过 Adapter 的 Pop Coordinator；
- Pop 被 `PopScope`、表单保护或手势状态拒绝时，Managed Route 保持存活；
- Foreign Popup 消费返回时，只移除 Foreign Entry；
- 只有 `removedOwner == managed` 时，Runtime 才关闭对应 Route Scope；
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

跨组件打开、需要类型安全参数或返回值、需要权限或登录拦截、需要独立埋点或 Route Scope、需要 Deep Link 或状态恢复，以及属于完整业务流程的 Dialog 或 BottomSheet。

`CCDialogPresentation` 和 `CCModalBottomSheetPresentation` 表示被 CCRouter 管理的模态目的地，不代表所有 Flutter Dialog 或 BottomSheet。

## 8. Adapter 能力声明

Adapter 初始化时声明能力：

```text
supportsForeignEntryObservation
supportsBackendEntryIdentity
supportsInitialStackSnapshot
supportsAtomicPopAndPush
supportsPushAndRemoveUntil
supportsNestedNavigators
supportsStatefulShell
supportsModalRoutes
supportsPredictiveBack
```

Runtime 根据能力选择正常执行、明确记录的降级实现或初始化失败。禁止静默把有返回值的组合操作降级为无法保证语义的多个操作。

`supportsInitialStackSnapshot` 不是所有 Flutter Navigator 都能实现的能力。无法提供完整快照时，Adapter 必须明确声明限制，Runtime 进入隔离或不确定状态。

## 9. 多 Window 与自适应布局

后续将 `hostId` 加入 `CCNavigationRequest`、`CCRouteEntrySnapshot`、`CCBackendEntry`、导航生命周期事件、后端事件和诊断记录。

不同 Window、折叠屏 Pane、外接显示器和多 Display Host 的导航栈必须相互隔离。Route Contract、Intent 和参数保持一致，呈现方式由 Host、Shell 和 Adaptive Layout 决定。

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
- [x] Runtime 仅将身份事件写入台账，不根据台账事件删除 Managed RouteEntry；
- [x] 增加初始后端栈快照，并在台账中保留 Host/Outlet 分区；
- [x] 将 Pop 协调升级为显式 `CCPopOutcome`，旧 Adapter 仍可通过 Boolean API 降级。

### 阶段三：Pop Coordinator

- [x] 引入 `CCPopOutcome`；
- [x] Managed outcome 才允许 Runtime 关闭对应 RouteEntry，Foreign/Opaque/None 只返回诊断；
- [ ] 统一系统返回、手势返回、预测返回和业务 Pop；
- [x] 完善 Pop 拒绝、结果和生命周期语义；
- [x] 业务 `CCRouter.navigator.pop` 通过 ownership-aware coordinator 执行，Foreign/Opaque
  Entry 不会关闭底层 Managed RouteEntry；
- [x] 预留预测返回 Adapter SPI，只有 committed 且可关联 Managed identity 的事件才允许
  关闭 RouteEntry；started、updated、cancelled 都不会销毁 Scope；

系统返回和手势返回已经通过 `maybePopOutcome` 进入同一 ownership 判定管线；预测返回仍由
`supportsPredictiveBack` 能力声明控制，当前 GoRouter Adapter 保守声明不支持，后续接入平台
预测手势回调后再完成统一提交和取消阶段。

### 阶段四：Foreign Route Bridge

- [x] 支持第三方 Navigator 通过 Host Bridge 显式上报；
- [x] 支持外部 Route 的身份和生命周期观察；
- [x] 为 Overlay 和 LocalHistoryEntry 提供可选诊断桥；
- 不把 Foreign UI 暴露为业务路由 API。

Adapter 能力声明已提供为可选的 `CCNavigationAdapterCapabilitySource` SPI。
GoRouter 和内存 Adapter 会声明各自已实现的组合导航、嵌套 Navigator、模态路由、
Foreign/Opaque 观察等能力；Runtime 已在初始化和组合导航执行前进行能力校验，
不再静默降级为无法保证语义的操作。

### 阶段五：Host 与多 Window

- 完善 Host/Outlet 注册；
- 增加 Window/Display 隔离；
- 支持折叠屏、多 Pane 和多窗口状态。

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
