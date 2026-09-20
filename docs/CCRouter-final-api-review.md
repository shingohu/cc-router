# CCRouter 最终 API 收口复审

## 1. 结论

本轮已完成路由生产数据流、生成器、Demo 聚合物、公共导出和长生命周期对象持有扫描。
处理原则不是按引用次数机械删除，而是同时验证类型安全、混合路由隔离、生命周期、诊断、
Host 扩展和降级语义。

当前路由 API 可以进入全量回归阶段。Service、Command、Query、Event 及尚未实现的组件动态
卸载完整语义不属于本轮范围，不能据此扩大或冻结对应 API。

## 2. 已删除的重复或无行为 API

以下字段没有独立运行时语义，已从手写代码、生成器、生成物和测试中同步删除：

- `CCRouteKind` 与 `CCRoutePlacement.routeKind`：Shell 已由 `CCShellDefinition` 独立表达，
  普通 Route 不需要只有一个合法值的枚举。
- Runtime `CCRouteDefinition.description` 和 `CCShellDefinition.description`：描述继续保留在
  Annotation、JSON 和 Markdown 文档，不随 Route 常驻 Runtime。
- `CCRoutePattern.matchOnly`：由 `CCRegexPattern` 类型直接推导。
- `CCActionReport.results`：Action Handler 只返回 `void`，结果列表没有真实数据来源。
- `CCRouteLocation.path`：生产链路没有独立消费者。
- `CCRouteEntryLifecycleEvent.state`：始终等于 `event.entry.lifecycleState`。
- `CCGoRouterNavigationEvent.result`：Flutter `NavigatorObserver` 不提供 Pop result。
- `CCBackendEntryLifecycleState.unknown`：没有合法创建路径。
- `CCPopOutcome.resultAvailable`：没有对应的结果值通道；类型安全结果继续由原 Push Future 管理。
- `CCRouteEntryHandle` 及精确 Entry 操作链：当前后端无法统一保证稳定身份、原子提交和混合栈隔离，完整删除并转为 Deferred 设计。
- `CCFlutterRouteDestination.componentId`：Assembler 不消费；Runtime 单独保存可信组件 owner。
- 未参与决策的 Capability Boolean：`supportsForeignEntryObservation`、
  `supportsBackendEntryIdentity`、`supportsInitialStackSnapshot`、
  `supportsOpaqueUiObservation`。可选能力改由对应 SPI 类型判断。

## 3. 已完成的对象持有收敛

- `CCRouteEntrySnapshot` 不再保存 Arguments，避免历史快照长期持有 `extra` 或业务对象。
- `CCRouteEntrySnapshot`、Pending Navigation 和 Backend 诊断统一使用
  `CCRouteAddressSummary`；Backend ledger 不再保存完整 location，原始 Adapter event 也不会进入
  retained history。
- `CCTraceRecord.context` 改为不可变 `CCTraceContextSnapshot`，不再持有活动
  `CCCancellationToken` 或其监听器。
- Route Scope close Future 只在 pending 期间保留，完成或失败后立即移除。
- Pending Navigation 的 Timer 在恢复、取消、超时、Session 关闭和 Runtime dispose 时取消。
- Aspect record 只有在导航终态和 RouteEntry dispose 都完成后释放；Runtime dispose 兜底清空。
- Backend event、failure、visibility、lifecycle、restoration 和 trace 历史均为有界缓冲。
- Backend ledger 始终保留 active 结构条目，只对 removed 诊断历史做有界淘汰；容量为 0 时
  不保留 removed 历史，但仍保留 active identity 和有界 operation 去重。
- 动态 Host detach 会清理该 Host 的 sequence/desync 状态，允许同 ID Host 重新接入。
- Multi Host Registry 在 RouteEntry 移除和 Adapter dispatch 失败时释放
  `navigationId -> hostId` 索引，不依赖 Backend Observer 必须存在。
- Multi Host 初始化、动态注册和卸载均为同步原子事务；失败注册不会写入 Registry，Adapter
  只执行一次同步清理。异步 Scope 和 Backend 资源由 `CCRouter.shutdown()` 统一等待。
- 恢复机会 Controller 的启动前信号缓冲有明确容量，不能在 Runtime 订阅前无限增长。
- GoRouter Observer、RouterDelegate、Predictive Back、Foreign Route Bridge、页面生命周期和恢复
  信号订阅均有对应 removal/dispose 路径。

## 4. 公共 API 边界

`package:ccrouter/ccrouter.dart` 已隐藏以下内部或 Host-only 能力：

- `CCRouterRuntime`、`CCScope`、`CCScopeState`；
- `CCMemoryNavigationAdapter`；
- `CCRouterAppBackend`；
- `CCPageLifecycleHostBridge`；
- Adapter、Request、Route 和 Shell SPI；
- Capability、Host binding、Backend Event/Snapshot 和 Managed Entry release SPI；
- Pop Coordinator、Pop Target、Pop Guard binding 和 evaluator SPI；
- Predictive Back 与 Restoration Source/Signal SPI。

这些能力分别由 Facade、`ccrouter_host.dart` 或 `ccrouter_test` 提供受控入口。组件 Registrar 仍只
接收受限 `CCRegistry`，业务代码不能创建、关闭或销毁 Runtime 和 Scope。

`CCNavigationAdapter` 仍是 Adapter Package 和 Host SPI 的公共类型，但只由
`package:ccrouter/ccrouter_host.dart` 显式导出，`package:ccrouter/ccrouter.dart` 使用对应
`hide` 清单保证业务入口不可见。页面生成 glue 返回 `CCRouteDefinition`，Host catalog 再通过
`CCFlutterRouteDestination.fromDefinition` 创建 Adapter-facing `CCNavigationRoute`，因此页面
library 不需要依赖 Host SPI。API surface 快照测试锁定两侧导出集合。

`CCRouter.initialize(components: ...)` 原子初始化全局配置和启动期组件集合。新应用由
`CCRouterAppBackend` 提供 Adapter，`CCRouterApp.managed` 通过框架私有协调器完成所有权转移。
Host/Adapter 的生命周期约束如下：

- Adapter 由 Backend 交给 `CCRouterApp.managed`，再由 Runtime 初始化、销毁；
- Adapter 初始化、初始 Backend Snapshot 和 dispose 都是同步事务，返回时状态已经稳定；
- 异步平台资源必须在 Backend 构造前准备，或在 `CCRouter.shutdown()` 阶段释放；
- Backend 绑定协调器属于框架内部实现，不从 `ccrouter_host.dart` 导出；
- dispose 后导航必须失败，且 Runtime 不允许重新初始化；
- managed Backend 在 Runtime 关闭后销毁自有 GoRouter，attach Backend 不销毁应用 Router；
- Session、组件、页面 Pop 均不能触发 Adapter dispose。

## 5. 明确保留的字段和能力

- `CCNavigationRoute.deepLink`：GoRouter 可能独立收到平台 URL，Adapter 仍需执行入口约束。
- `CCNavigationOrigin` 与 `CCNavigationSource`：分别表示可信安全来源和产品埋点归因。
- `parentRouteId`、`shellId`、`navigatorOutlet`：用于子路由、Shell、嵌套 Navigator 和多 Pane。
- Page、透明页、Dialog、BottomSheet Presentation：默认 Adapter 均有真实消费路径。
- `sessionId` 与 `accountId`：分别表示 Session 实例和稳定账号，不可合并。
- Backend owner、entry ID、operation ID：是混合路由隔离和精确生命周期关联的基础。
- `CCGoRouterShellBinding.initialOutlet`：Adapter 初始化会校验它与 Runtime Shell contract 一致。
- Adaptive Layout、`CCRouterApp` 和 Multi Host：已接入 Host/Outlet 调度并形成最小闭环。

## 6. 观察 API 的职责边界

以下观察面存在字段交集，但当前有不同消费者和生命周期，暂不合并：

- `CCNavigationLifecycleEvent`：请求的 requested/completed/failed 终态摘要和有界历史。
- `CCNavigationAspect`：全局 PV、来源、阶段耗时、到达、显示、隐藏和链路观察。
- `CCRouteVisibilityEvent`：Managed RouteEntry 的 will/did show/hide 配对通知。
- `CCRouteEntryLifecycleEvent`：Route Scope 从 resolving 到 disposed 的资源生命周期。
- `CCPageLifecycleMixin` / `CCPageLifecycleListener`：Flutter PageRoute 当前性与 App 前后台回调。

`completed` 对 Push 表示返回 Future 完成，不等于首次 Arrival；页面像素可见性也不能由
PageShow/PageHide 推导。继续保持这些边界比合并成万能生命周期回调更安全。

## 7. 暂缓能力

完整 Route Restoration 仅保留设计和脱敏机会诊断，当前事件固定为 `unsupported`。只有数据证明
存在真实恢复需求后，才重新设计版本化 Snapshot、路由显式 opt-in、契约升级与部分恢复。

以下非路由或后续能力不在本轮处理：

- `CCServiceScope.component` / `route`；
- Service Token 与独立 contracts Package 的最终收敛；
- 组件动态 activate/deactivate 对 Service、Handler、Scope 和依赖级联的完整语义；
- CLI 创建组件、契约提升与迁移自动化。

## 8. 回归门槛

冻结本轮路由 API 前必须全部通过：

1. 六个 framework Package 与 Demo analyze；
2. `packages/ccrouter_test/test` 全部 Flutter 测试；
3. `packages/ccrouter_test/generator_test` 全部 Dart 测试；
4. Demo 测试和标准 Workspace 生成流程；
5. `git diff --check`、生成物旧字段搜索和未跟踪生成物核对。
