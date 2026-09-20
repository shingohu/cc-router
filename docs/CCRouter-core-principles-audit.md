# CCRouter 核心价值与开发约定回归

## 1. 审查结论

- 审查日期：2026-09-20
- 审查范围：路由 Runtime、业务 Facade、Host/Adapter SPI、GoRouter Adapter、生成器、
  Demo、测试与诊断模型。
- 自动化基线：`dart analyze` 通过；Framework 216 项、Demo 19 项、Generator 78 项测试通过；
  最近一次 macOS debug build 和交互验证通过。
- 总体结论：13 条约定的架构方向成立，但当前不能认定为全部对齐。没有阻断 Demo 的 P0
  或 P1 问题；并发安全、retained diagnostics 数据边界和观察回调热路径已完成收口，仍有
  5 项 P2 欠账。

本审查只记录事实和后续门槛，不因为某项容易实现就扩展公开 API。

## 2. 逐项对齐结果

| # | 约定 | 状态 | 当前证据与缺口 |
| --- | --- | --- | --- |
| 1 | 智能 | 部分满足 | Route/Codec/Manifest/组件索引/Host Catalog/文档均可生成；Runtime 自动校验并装配。缺口是 Workspace 聚合仍需在 `build_runner` 后手动执行第二条 CLI，且无增量缓存或生成物陈旧门禁。 |
| 2 | 简单易用 | 基本满足 | Demo 宿主只需 `CCRouter.initialize`、`CCGoRouterBackend.managed`、`CCRouterApp.managed` 和 `MaterialApp.router`。Shell、Multi Host、Aspect 等均为可选能力；生成阶段的两条命令仍增加首次接入成本。 |
| 3 | 功能强大 | 基本满足 | 已覆盖类型安全导航、Deep Link、拦截、生命周期、混合路由、诊断和多种 Presentation，没有万能 Map 导航接口。组合栈事务与精确 Entry 操作已从 v0.1 API 删除并标记 Deferred；设备 Predictive Back 和 Restoration 仍是明确限制。 |
| 4 | 可扩展性 | 基本满足 | Core 使用中立 Route Definition；Catalog、Assembler、Adapter 与能力 SPI 分层。新后端可复用 Contract/Catalog；Host/Adapter 实现通过独立 `ccrouter_host.dart` 获取 SPI，业务 barrel 不再暴露该能力。 |
| 5 | 可测试 | 基本满足 | Pure Dart Runtime/Memory Adapter、Flutter Adapter、生成器和 Demo 都有回归；`ccrouter_test` 已提供 Test Host。尚无正式性能、长时间运行和大规模路由表基准。 |
| 6 | 最小公开 API | 基本满足 | Runtime、Scope、Memory Adapter、Host binding 以及 Adapter/Request/Capability/Backend 控制 SPI 已从业务 barrel 隐藏；Registrar 只拿到 `CCRegistry`，Host 组合根按需导入 `ccrouter_host.dart`。API surface 快照测试防止 SPI 意外回流。 |
| 7 | 编译器校验与类型安全 | 部分满足 | 参数、Codec、Route ID、Pattern、Contract exposure、页面实现和 barrel 导出已有生成期校验。组件依赖缺失/环、拦截器/PopGuard 引用和 Adapter 能力主要仍在 Runtime 才失败。 |
| 8 | 非侵入式 | 满足 | 不要求页面基类或 Mixin，不保存全局 `BuildContext`；可继续使用应用自己的 `MaterialApp.router`/`GoRouter`；attached Adapter 不销毁应用 Router。 |
| 9 | 可降级回退 | 部分满足 | 无法可靠降级的组合栈事务与精确 Entry 操作已从公开能力链删除，不再静默模拟。解析前失败和观察能力降级仍没有统一进入 failure/diagnostic 记录。 |
| 10 | 明确生命周期 | 基本满足 | Runtime、Session、RouteEntry、Scope、Adapter、Backend 的 Owner 和销毁顺序明确，幂等与 pending Future 已有测试。组件 activate/deactivate 当前只覆盖 Route/Shell，完整 Service/Handler/Scope 生命周期仍按设计暂缓。 |
| 11 | 可观测可诊断可溯源 | 基本满足 | navigationId、来源、Owner、阶段耗时、bounded history、Listener 异常隔离均已具备。Pending、RouteEntry、Backend history/ledger 已使用安全地址摘要，完整 URI/location 只留在即时 operational pipeline；剩余缺口是部分前置失败没有事件。 |
| 12 | 并发安全 | 基本满足 | 初始化/销毁、Session、Adapter 生命周期和导航并发策略已有确定语义，Defer/Timeout/Cancel 有回归。并发短路具有完整 Aspect 终态；Extra 请求明确独立执行；Interceptor、Policy、Guard、Aspect 和普通 Listener 统一使用 Zone 重入保护。 |
| 13 | 性能和稳定 | 部分满足 | 热路径无反射，路由 ID 使用索引，缓存与观察队列有界，纯观察回调不再同步阻塞导航，错误不被吞掉。但没有 benchmark、内存增长门槛或版本对比；动态 URI 解析和 Workspace 扫描仍为线性全量工作。 |

## 3. P1 问题

### 已完成：并发 Observation、Extra 与回调重入

- `rejectDuplicate` 为被拒请求产生独立 Navigation ID 和 `found/lost/after`，随后释放
  Observation；
- `singleFlight` 共享第一个 Future，但跟随调用保留独立 Navigation ID、Lifecycle 和 `after`
  终态，不创建第二个 RouteEntry；
- 携带 Extra 的请求不参与自动去重，避免比较、哈希或合并任意业务对象；
- Interceptor、Failure Policy、PopGuard、Telemetry Provider、Aspect 和所有 Runtime 路由 Listener
  统一进入 Runtime Zone；回调内同步调用及其派生异步任务发起导航均抛出
  `CCNavigationReentrancyError`；
- 专项测试覆盖拒绝、共享、Extra 独立执行、Interceptor 重入和 Listener 重入。

### 已完成：P1-1 Retained diagnostics 数据边界

- `CCPendingNavigation` 和 `CCRouteEntrySnapshot` 只暴露 `CCRouteAddressSummary`；
- Visibility 与 RouteEntry lifecycle 自动复用同一安全 Entry 快照；
- Adapter 原始 `CCNavigationBackendEvent` 只在回调调用栈中完成 identity 与 lifecycle 协调，进入
  Runtime history 和业务 Listener 前转换为 `CCNavigationBackendDiagnosticEvent`；
- Runtime backend ledger 不再保存 `location`，只保存 `CCRouteAddressSummary`，业务通过
  `CCBackendEntrySnapshot` 观察；
- 摘要仅包含 canonical `routePattern` 和 Path/Query/Fragment presence；Pattern 可以包含声明期
  Path 占位符名称，但不包含 Path 值、动态 Query 名和值、完整 URI 或第三方 RouteSettings
  location；
- Pending resume、Route 匹配和 Adapter 调度仍使用 Runtime 私有 request/record 中的 operational URI，
  不因脱敏改变导航语义；
- 专项测试覆盖带 Path 用户标识、Query Token、Fragment 和外部 backend location 的输入。

### 已完成：P1-2 Observer 有界异步分发

- Aspect、Navigation/Failure、RouteEntry/Visibility、Backend 和 Restoration Listener 统一进入
  Runtime 私有 FIFO 队列，在下一轮 event loop 分发；决策型 Interceptor/Policy/Guard 保持同步或
  显式 await；
- 队列容量复用 `navigationDiagnosticCapacity` 且最少为 64 个事件批次，避免低历史容量让常规
  导航频繁触发 backpressure；
- overflow 优先移除最旧非终态批次；全终态队列拒绝新非终态，只有新终态才同步释放最旧终态；
- Navigation `completed/failed`、Failure、RouteEntry `removed/disposed`、Aspect
  `lost/after/removed/disposed`、Backend `pop/remove/hostDetached` 不静默丢失；
- Listener 在 drain 前取消订阅会跳过排队回调；Runtime dispose 取消 Timer、flush 队列并清理
  Listener 和闭包，覆盖 `not-disposed` 与 `not-GCed` 风险；
- 专项测试覆盖异步边界、FIFO、取消订阅、两类 overflow、终态保护、dispose flush 和异步重入拒绝。

## 4. P2 问题

### 已完成：P2-1 业务 barrel 与 Host/Adapter SPI 隔离

- `package:ccrouter/ccrouter.dart` 使用完整 `hide` 清单隔离 Adapter、Request、Route、Capability、
  Backend Event/Snapshot、Pop Coordinator、Predictive Back 和 Restoration Source 等 Host SPI；
- `package:ccrouter/ccrouter_host.dart` 使用对应 `show` 清单提供 Host/Adapter 实现入口；
- 页面生成 glue 只返回组件已有的 `CCRouteDefinition`，由
  `CCFlutterRouteDestination.fromDefinition` 在 Host catalog 边界生成 `CCNavigationRoute`，页面
  library 不需要也不能额外导入 Host SPI；
- API surface 快照测试同时锁定业务隐藏集合、Host 导出集合和主要 SPI 类型可解析性。

### P2-2 前置失败和能力降级的诊断不完整

当 Route resolution、参数准备或 `_ensureAdapterCapability` 在 request 创建前失败，且没有安装
Failure Policy 时，调用方能收到标准错误，但 `recentNavigationFailures`、Lifecycle 和 Aspect 中没有
统一的终态记录。Observer coverage 的安全降级也只有 capability 状态，没有一次明确事件。

建议：增加不含 URI/Arguments 的 pre-dispatch failure envelope，记录 operation、routeId hint、stage、
capability、error type 和 fallback outcome。

### P2-3 Workspace Validator 不校验组件依赖图

组件 metadata 已包含 `dependencies/optionalDependencies`，但 Workspace Validator 目前只输出它们；
缺失依赖和依赖环仍由 Runtime 初始化发现。这类错误可以在聚合阶段前移。

建议：在 Validator 中增加 missing required dependency、self dependency、cycle 和可选依赖排序校验，
并复用 Runtime 的确定性拓扑规则测试向量。

### P2-4 Host 聚合仍是第二条手动命令

新增页面后 `build_runner --workspace` 只生成 Package 内产物，还必须再次执行带
`--generate-component-registrars` 的 CLI 才能刷新组件索引和 Host Catalog。遗漏时编译可能失败，
但自动配置体验仍不完整。

建议：短期提供单一 `ccrouter generate` 编排命令并校验工作区无陈旧生成物；长期评估增量 Package
图缓存。不要引入第二套生成语义。

### P2-5 Telemetry/source 标识只有弱校验

匿名 telemetry ID 只校验 trim 和长度，`CCNavigationSource.id` 没有运行时格式限制。调用方仍可误把
账号、URL 或 Token 放入这些字段。

建议：定义稳定标识字符集和较小长度上限；提供 debug 校验及 release 安全降级，文档继续明确禁止
PII/凭证。框架无法证明匿名性，但可以减少明显误用。

### P2-6 没有性能与稳定性基准门槛

仓库没有 benchmark/perf suite，也没有冷启动、初始化、路由规模、并发、销毁和内存增长基线。
当前 dynamic URI resolution 会遍历所有 Route/Pattern，Workspace CLI 递归全量扫描；小 Demo 正常
不能证明大型工程稳定。

建议首批建立 10/100/1000 Route 的初始化与解析 benchmark、1 万次并发门回归、持续 Push/Pop 后
内存台账稳定性、Runtime dispose p95，以及生成器冷/热运行指标。指标先记录基线，再决定优化。

## 5. 已确认符合且应保持的边界

- 默认 Runtime 由 `CCRouter` 创建和销毁，业务不构造 Runtime/Scope。
- Registrar 只接收受限 `CCRegistry`，组件不获得 Runtime。
- 生成 Route Intent 和结果类型是业务导航主入口；动态 URI 是明确的兼容入口。
- GoRouter managed/attach 所有权不同，attach 不销毁应用 Router。
- 外部 Popup、Overlay 和 LocalHistory 不会按位置误删 Managed RouteEntry。
- Adapter 不支持某项语义时在变更栈前失败，不做不等价模拟。
- Route/Session/Adapter pending Future 在 Pop、Reset、Go 和 shutdown 路径都有终止行为。
- Trace、Lifecycle、Failure、Aspect 和 Backend 历史均有容量边界，subscriber error 有界。
- 页面生命周期不要求业务继承基类；Mixin 和 Listener 均为可选。
- contracts Package 可以保持 Pure Dart，页面实现和后端依赖不进入跨组件契约。

## 6. 推荐处理顺序

1. 补 pre-dispatch failure/capability fallback 事件和 Workspace 依赖图校验。
2. 合并生成入口并建立 benchmark；得到基线前不做缓存和索引优化。

每一项完成后必须运行 analyze、Framework/Demo/Generator 全量测试，并重新执行 macOS Demo
交互回归。涉及 Android Predictive Back 时另加真实 Android 设备验证。
