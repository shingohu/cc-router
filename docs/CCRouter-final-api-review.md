# CCRouter 最终 API 收口复审清单

## 1. 目的与执行时机

本文记录开发过程中的 API 精简候选，不代表现在立即删除，也不覆盖已经冻结的
功能决策。当前阶段继续完成既定能力，避免因为尚未接入的后续实现而误判字段无用。

在既定功能全部完成并通过全量回归后，必须重新扫描 `packages/*/lib`、生成器产物、
Demo 和测试，再逐项确认本文结论。最终处理需要同时满足：

- 生产链路中没有真实消费者，或同一语义可以从其他类型、字段可靠推导。
- 删除后不会削弱类型安全、混合路由隔离、生命周期、诊断或降级能力。
- Business API、Component API、Host SPI、Adapter SPI 和 Test API 边界清晰。
- 不再因为诊断快照持有业务参数、取消对象或其他长生命周期引用。
- 相关生成器、元数据、文档、测试和迁移说明在同一阶段更新。

## 2. 最终扫描范围

最终复审不能只统计字段引用次数，还要检查以下真实行为：

1. Annotation 到生成代码、组件元数据、宿主聚合物的完整数据流。
2. Runtime、Adapter、GoRouter、混合路由和 Deep Link 的生产消费路径。
3. 当前只被测试读取、但没有生产语义的字段和公开 Getter。
4. 可以由类型、接口实现关系或其他稳定身份推导的重复字段。
5. 诊断缓冲区、RouteEntry、Trace、Pending Navigation 的对象保留和内存释放。
6. 未实现、部分实现或只作为未来占位符公开的 API。
7. `package:ccrouter/ccrouter.dart` 是否仍错误导出 Host、Adapter、Runtime 或测试能力。

## 3. 优先删除候选

下列项目在当前实现中没有独立语义，最终扫描时优先确认删除：

- `CCRouteKind` 与 `CCRoutePlacement.routeKind`：Shell 已由独立定义表达，Route
  注册又明确拒绝 `shell`，合法值实际只有 `page`。
- `CCRouteDefinition.description`：描述只属于 Annotation、JSON 和 Markdown 文档，
  不应随每条 Route 常驻 Runtime。
- `CCShellDefinition.description`：当前没有 Runtime 或文档生成消费者。
- `CCActionReport.results`：Action Handler 返回 `void`，当前结果列表永远为空。
- `CCNavigationInterceptorContext.deadline`：导航管线当前从未提供该值。
- `CCRoutePattern.matchOnly`：可以由 `CCRegexPattern` 类型可靠推导。
- `CCRouteLocation.path`：当前生产链路构造后不再读取。
- `CCRouteEntryLifecycleEvent.state`：始终等于 `entry.lifecycleState`。
- `CCGoRouterNavigationEvent.result`：Flutter `NavigatorObserver` 回调不提供 Pop 结果。
- `CCBackendEntryLifecycleState.unknown`：当前没有生产路径会创建该状态。
- `CCPopOutcome.resultAvailable`：没有对应的结果值通道，Runtime 也不读取。
- `CCRouteEntryHandle.navigationId`：若 `routeEntryId` 保持跨 Runtime 唯一，则第二个
  身份只是在重复校验。
- `CCFlutterRouteDestination.componentId`：当前 Assembler 不读取，Runtime 已单独保存
  可信组件所有权。
- `CCGoRouterShellBinding.initialOutlet`：目前只重复声明 Runtime 值，不能证明
  GoRouter 的真实初始分支。

## 4. 重构后再删除或收敛

以下项目不能机械删除，需要先建立替代数据流或明确最终语义：

- 从 `CCRoutePlacement` 删除静态 `hostId`，改由本次导航的 Context、Host Resolver
  或显式 Host 选择产生 `CCNavigationRequest.hostId`。
- 从公共 `CCRouteEntrySnapshot` 删除 `arguments`。Runtime 可在当前 Entry 内部短期
  保留参数，但生命周期历史不得持续持有 Extra 或任意业务对象。
- 将 `CCTraceRecord.context` 替换为不包含 `CCCancellationToken` 的不可变 Trace
  快照，避免诊断缓冲区持有活动对象和监听器。
- 移除 `CCRoute`、`CCRouteContract` 对完整 `CCComponentDescriptor` 的重复引用。
  Internal Route 的 owner 应由实现 Package 的唯一组件推导；Contract-first Route
  在 Workspace 关联 Implementation 后确定 owner。
- 组件版本尽量从实现 Package 的 `pubspec.yaml` 推导，避免 Descriptor 与 Pub
  版本漂移。Runtime 只有在真正支持版本约束时才保存版本。
- 重新评估 `optionalDependencies`。当前它只影响 Registrar 排序，却没有能力探测、
  条件注册或降级行为。
- 重新评估 `CCServiceToken` 与 `CCServiceProvider.contract`。在独立 contracts
  Package 架构下，Dart 接口类型通常已经提供稳定的编译期身份；只有明确需要
  跨 isolate、动态二进制插件或字符串协议时才保留第二套 Token 身份。
- 合并 `CCNavigationLifecycleEvent`、`CCNavigationAspect`、
  `CCRouteVisibilityEvent` 与 `CCRouteEntryLifecycleEvent` 的重叠观察面。真正的
  Arrival/Visible 必须由已关联的 Backend 事件确认，不能在 Runtime commit 后立即猜测。
- 精简 `CCNavigationAdapterCapabilities`。可以通过 Optional SPI/interface 判断的
  Snapshot、Predictive Back、Exact Entry 和组合操作能力，不再同时保留容易矛盾的
  Boolean；Capability 只表达不能从类型推导的后端语义。
- 重新定义动态 `open`、`go` 和 `reset`。当前 GoRouter 与 Memory Adapter 对 `open`
  的栈行为不一致，`go` 与 `reset` 又没有可观察差异；应先明确动态目标解析与栈操作
  是两个维度，再决定保留哪些 Operation。

## 5. 暂不作为稳定公共 API 的候选

下列能力具有真实场景，但当前实现尚未形成完整生产闭环。最终扫描时应选择“完成后
公开”或“暂时移出公共 Barrel”，不能继续以半实现状态稳定暴露：

- Adaptive Layout 契约组：目前只有模型和测试，尚未接入 Host、Outlet 调度或
  Adapter。
- `CCServiceScope.component` 与 `CCServiceScope.route`：当前注册时会直接拒绝。
- `activateComponent` / `deactivateComponent`：当前只处理 Route 和 Shell，没有
  覆盖 Service、Handler、Scope、依赖级联及并发停用。
- `CCRouterApp` / `CCNavigationHost`：当前 Host ID 与 Navigator Key 尚未进入
  Runtime 或 Adapter 的 Host Registry。
- `CCMemoryNavigationAdapter`、Runtime 的低层注册方法和测试状态 Getter：应迁移到
  `ccrouter_test` 或仅由测试入口访问。
- `CCGoRouterAdapter` 中仅供测试读取的 routes、bindings、shellContracts、observers、
  lifecycleEvents 等快照 Getter。

## 6. API 边界复审

最终应避免 `package:ccrouter/ccrouter.dart` 全量转出 contracts/core。推荐分别审查：

- Business API：`CCRouter`、`CCNavigator`、生成的 Intent、业务错误和安全诊断快照。
- Component Author API：Annotation、Manifest、Registrar、受限 `CCRegistry` 和 Provider。
- Host API：初始化、Deep Link Ingress、Catalog、Host/Outlet 组合及诊断订阅。
- Adapter SPI：请求、Backend Entry、能力接口和生命周期上报。
- Test API：Test Host、Memory Adapter、Fixture、状态断言和故障注入。

公共业务入口不应暴露 Runtime 构造、Adapter dispose、Backend Bridge、Registrar 执行、
Scope 控制或测试状态。

## 7. 必须保留或谨慎处理

以下字段虽然可能存在重复数据，但承载不同安全或运行时语义，不能仅按引用数量删除：

- `CCNavigationRoute.deepLink`：GoRouter 可能独立接收平台 URL；删除前必须先保证后端
  入口不会绕过 Runtime Deep Link Policy。
- `CCNavigationOrigin` 与 `CCNavigationSource`：前者是可信安全来源，后者是业务埋点
  归因，不能合并。
- `parentRouteId`、`shellId`、`navigatorOutlet`：用于子路由、Shell、嵌套 Navigator
  和多 Pane 定位。
- Page、透明页、Dialog、BottomSheet 的 Presentation 字段：默认 Adapter 已有真实
  消费路径。
- `sessionId` 与 `accountId`：分别标识一次 Session 实例和稳定账号，语义不同。
- Backend Entry owner、stable entry ID 和 operation ID：它们是混合路由隔离及防止
  Foreign/Popup 错误关闭 Managed Route Scope 的基础。

## 8. 最终执行顺序

1. 完成既定功能，不在中途依据本文提前删除。
2. 执行全 Workspace 静态引用、生产数据流与 public export 扫描。
3. 执行全部 Generator、Core、Facade、GoRouter、Demo 和混合路由回归测试。
4. 增加对象保留、Listener/Timer 清理、Pending Future 和 Route Scope 的泄漏测试。
5. 先删除无行为字段，再处理需要迁移的数据模型与 API 分层。
6. 更新生成物 Schema 和迁移说明，重新生成全部 Demo 产物。
7. 再次执行全量测试、Analyze 和内存回归后，才冻结最终公共 API。
