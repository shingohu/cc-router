# CCRouter 核心价值与开发约定回归

## 1. 审查结论

- 审查日期：2026-09-20
- 审查范围：路由 Runtime、业务 Facade、Host/Adapter SPI、GoRouter Adapter、生成器、
  Demo、测试与诊断模型。
- 自动化基线：`dart analyze` 通过；Framework 225 项、Demo 19 项、Generator 91 项测试通过；
  最近一次 macOS debug build 和交互验证通过。
- 总体结论：13 条约定的架构方向成立，但当前不能认定为全部对齐。没有阻断 Demo 的 P0
  或 P1 问题；并发安全、retained diagnostics 数据边界、观察回调热路径和组件依赖图前移校验
  和统一生成门禁已完成收口，仍有 2 项 P2 欠账。

本审查只记录事实和后续门槛，不因为某项容易实现就扩展公开 API。

## 2. 逐项对齐结果

| # | 约定 | 状态 | 当前证据与缺口 |
| --- | --- | --- | --- |
| 1 | 智能 | 基本满足 | Route/Codec/Manifest/组件索引/Host Catalog/文档均由单一 `ccrouter generate` 编排生成；Runtime 自动校验并装配，`--check` 提供不依赖 Git 的只读陈旧门禁。生成器已按 Host Pub 运行时闭包精确发现 workspace/path/Git/pub 与传递 Package，并生成发布级 Index/Bundle。 |
| 2 | 简单易用 | 基本满足 | Demo 宿主只需 `CCRouter.initialize`、`CCGoRouterBackend.managed`、`CCRouterApp.managed` 和 `MaterialApp.router`；生成也已收敛为一条命令。Shell、Multi Host、Aspect 和 CI check 等高级能力保持可选。 |
| 3 | 功能强大 | 基本满足 | 已覆盖类型安全导航、Deep Link、拦截、生命周期、混合路由、诊断和多种 Presentation，没有万能 Map 导航接口。组合栈事务与精确 Entry 操作已从 v0.1 API 删除并标记 Deferred；设备 Predictive Back 和 Restoration 仍是明确限制。 |
| 4 | 可扩展性 | 基本满足 | Core 使用中立 Route Definition；Catalog、Assembler、Adapter 与能力 SPI 分层。新后端可复用 Contract/Catalog；Host/Adapter 实现通过独立 `ccrouter_host.dart` 获取 SPI，业务 barrel 不再暴露该能力。 |
| 5 | 可测试 | 基本满足 | Pure Dart Runtime/Memory Adapter、Flutter Adapter、生成器和 Demo 都有回归；`ccrouter_test` 已提供 Test Host。尚无正式性能、长时间运行和大规模路由表基准。 |
| 6 | 最小公开 API | 基本满足 | Runtime、Scope、Memory Adapter、Host binding 以及 Adapter/Request/Capability/Backend 控制 SPI 已从业务 barrel 隐藏；Registrar 只拿到 `CCRegistry`，Host 组合根按需导入 `ccrouter_host.dart`。API surface 快照测试防止 SPI 意外回流。 |
| 7 | 编译器校验与类型安全 | 部分满足 | 参数、Codec、Route ID、Pattern、Contract exposure、页面实现、barrel 导出和组件依赖图已有生成期校验。拦截器/PopGuard 引用和 Adapter 能力主要仍在 Runtime 才失败。 |
| 8 | 非侵入式 | 满足 | 不要求页面基类或 Mixin，不保存全局 `BuildContext`；可继续使用应用自己的 `MaterialApp.router`/`GoRouter`；attached Adapter 不销毁应用 Router。 |
| 9 | 可降级回退 | 基本满足 | 无法可靠降级的组合栈事务与精确 Entry 操作已从公开能力链删除，不再静默模拟。解析前失败始终进入 Failure 记录；实际采用 Runtime visibility 或 partition-local reconciliation 时产生独立 capability fallback 事件。 |
| 10 | 明确生命周期 | 基本满足 | Runtime、Session、RouteEntry、Scope、Adapter、Backend 的 Owner 和销毁顺序明确，幂等与 pending Future 已有测试。组件 activate/deactivate 当前只覆盖 Route/Shell，完整 Service/Handler/Scope 生命周期仍按设计暂缓。 |
| 11 | 可观测可诊断可溯源 | 基本满足 | navigationId、来源、Owner、阶段耗时、bounded history、Listener 异常隔离均已具备。Pending、RouteEntry、Backend history/ledger 已使用安全地址摘要，完整 URI/location 只留在即时 operational pipeline；request 创建前的解析/参数失败和实际能力回退也有独立安全事件。 |
| 12 | 并发安全 | 基本满足 | 初始化/销毁、Session、Adapter 生命周期和导航并发策略已有确定语义，Defer/Timeout/Cancel 有回归。并发短路具有完整 Aspect 终态；Extra 请求明确独立执行；Interceptor、Policy、Guard、Aspect 和普通 Listener 统一使用 Zone 重入保护。 |
| 13 | 性能和稳定 | 部分满足 | 热路径无反射，路由 ID 使用索引，缓存与观察队列有界，纯观察回调不再同步阻塞导航，错误不被吞掉。生成器复用 build_runner 增量图，只扫描 Host 依赖闭包中的 Package metadata，使用内容指纹缓存、write-if-changed、并发锁和全量回退；仍缺少正式 benchmark、内存增长门槛或版本对比，动态 URI 解析仍为线性工作。 |

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

### 已完成：P2-2 前置失败和能力降级诊断

- Route resolution、参数准备、拦截和 Adapter 失败无论是否安装 Failure Policy，都会进入有界
  `CCNavigationFailureEvent`；事件只记录 navigation ID、operation、route ID hint、origin、stage、
  error type、recovery depth 和是否恢复；
- request 创建前无法可靠得到 Pattern、Placement、Owner 和 Host，因此不伪造 Lifecycle/Aspect
  request；Failure Event 是该阶段的权威终态 envelope；
- Observer 能力不足但可以保持语义时，独立记录
  `CCNavigationCapabilityFallbackEvent`，区分 backend visibility 的 Runtime commit 回退和
  managed removal 的 Host/Outlet partition-local reconciliation；
- capability fallback 只在实际采用回退时记录，包含稳定 Route/Host/Outlet 与枚举，不包含 URI、
  Arguments、Extra、Widget、Navigator 或 backend Route；
- 两类事件都使用有界 history；Listener 通过 Runtime FIFO 队列异步分发，capability fallback 作为
  非终态诊断可在队列压力下丢弃，failure 终态保持 backpressure 语义。

### 已完成：P2-3 Workspace Validator 组件依赖图校验

- required dependency 缺失、自依赖和 required/optional 混合依赖环在 Workspace 聚合阶段失败；
- 不存在的 optional dependency 保持允许，存在时作为普通依赖边参与排序和环检测；
- 聚合组件列表复用 Runtime 的确定性语义：组件 ID 与依赖 ID 均稳定排序，依赖先于消费者；
- Generator 专项测试覆盖缺失、自依赖、混合环、optional 缺失和确定性拓扑顺序，避免构建期与
  Runtime 初始化对同一合法依赖图产生不同装配顺序。

### 已完成：P2-4 统一生成入口与陈旧门禁

- `ccrouter generate` 自动发现 standalone Package 或 Dart workspace，先复用 build_runner，
  再执行 metadata 校验、组件索引、Host Catalog 和文档聚合；
- `generate --check` 只快照 CCRouter 管理的输出，发现 added/removed/modified 后恢复原现场并
  返回非零，不依赖 Git 状态，也不覆盖业务源码；
- 普通生成清理由框架标记但不再有 owner 的 `.routes.g.dart`/`_ccrouter.g.dart` 聚合物，
  且只清理解析图中明确可写的 Package；同名手写文件和外部 path/Git/pub Package 保持不动；
- 旧 metadata-only aggregate 路径仅保留兼容，不再作为标准开发流程；
- 从 Host `package_graph.json` 只沿正式 dependencies 计算闭包，通过 `package_config.json` 定位
  workspace/path/Git/pub Package，排除无关 workspace roots 和 devDependencies；
- 每个参与 Package 发布单一 `ccrouter_package.json`，Runtime Package 额外发布只 import 直接依赖
  的 `CCGeneratedPackageBundle`；Host 不直接 import 传递 Package，Diamond 依赖按版本与内容指纹
  去重；
- 默认缓存只复用 metadata 字节 SHA-256 完全一致的解析结果，损坏或 Schema/版本不兼容时全量
  回退；`--no-cache --check` 已作为逐字节等价参考路径，`--profile` 输出阶段耗时与命中率；
- workspace build_runner 使用 `asset:` filter 限制到 Host 闭包内可写的生成器 Package，并排除
  `ccrouter_generated` 目录作为二次 Builder 输入；外部 Package 只消费发布 Index；
- 两个生成进程通过版本化文件锁串行化，write-if-changed 使用同目录临时文件提交。正式规模
  benchmark 仍归 P2-6，不能用缓存掩盖全量路径错误。

### P2-5 Telemetry/source 标识只有弱校验

匿名 telemetry ID 只校验 trim 和长度，`CCNavigationSource.id` 没有运行时格式限制。调用方仍可误把
账号、URL 或 Token 放入这些字段。

建议：定义稳定标识字符集和较小长度上限；提供 debug 校验及 release 安全降级，文档继续明确禁止
PII/凭证。框架无法证明匿名性，但可以减少明显误用。

### P2-6 性能与稳定性基准尚不完整

仓库没有 benchmark/perf suite，也没有冷启动、初始化、路由规模、并发、销毁和内存增长基线。
当前 dynamic URI resolution 会遍历所有 Route/Pattern；生成器虽已改为精确闭包、单 Package
Index 和内容缓存，但小 Demo 的热运行数据仍不能证明 500/1000 Route 大型工程稳定。

建议首批建立 10/100/1000 Route 的初始化与解析 benchmark、1 万次并发门回归、持续 Push/Pop 后
内存台账稳定性、Runtime dispose p95，以及生成器冷/热运行指标。指标先记录基线，再决定优化。

生成器聚合已增加非门禁式基准脚本：

```sh
fvm dart run packages/ccrouter_test/benchmark/generator_scaling.dart
```

2026-09-20 本机 Dart JIT 预热后单次 Validator 基线为：10 Route `0.93ms`、100 Route
`6.47ms`、500 Route `107.94ms`、1000 Route `422.89ms`。数据表明 Pattern 冲突检查当前存在明显
二次增长；1000 Route 尚可用，但不能把该结果视为跨机器性能门槛。后续应为 Pattern 建立静态前缀
分桶后再比较，并补齐 Runtime 初始化、动态解析、并发与内存基准。

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

1. 收紧 Telemetry/source 稳定标识校验，同时保持匿名降级和诊断数据边界。
2. 建立 benchmark；得到基线前不做 Workspace 缓存和路由索引优化。

每一项完成后必须运行 analyze、Framework/Demo/Generator 全量测试，并重新执行 macOS Demo
交互回归。涉及 Android Predictive Back 时另加真实 Android 设备验证。
