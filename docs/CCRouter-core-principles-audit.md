# CCRouter 核心价值与开发约定回归

## 1. 审查结论

- 审查日期：2026-09-22
- 审查范围：路由 Runtime、业务 Facade、Host/Adapter SPI、GoRouter Adapter、生成器、
  Demo、测试与诊断模型。
- 自动化基线：`dart analyze` 与 Demo Analyzer 通过；Framework 250 项、Demo 25 项、
  Generator 131 项测试通过；默认缓存和 `--no-cache` 生成检查逐字节等价；macOS debug
  build 通过。
- 总体结论：当前实现满足 13 条约定在 v0.1 路由范围内的发布门槛，没有 P0 或 P1 问题。
  生成物职责、API 隔离、增量/全量等价、生命周期和资源释放已完成本轮收口；Adapter 能力的
  更多构建期前移、Restoration、真实平台多窗口和长期 RSS/Heap 趋势仍是明确的后续能力，不能
  因本轮通过而视为已经实现。

本审查只记录事实和后续门槛，不因为某项容易实现就扩展公开 API。

## 2. 逐项对齐结果

| # | 约定 | 状态 | 当前证据与缺口 |
| --- | --- | --- | --- |
| 1 | 智能 | 基本满足 | Route/Codec/Manifest/组件索引/Host Catalog/文档均由单一 `ccrouter generate` 编排生成；Runtime 自动校验并装配，`--check` 提供不依赖 Git 的只读陈旧门禁。生成器已按 Host Pub 运行时闭包精确发现 workspace/path/Git/pub 与传递 Package，并生成发布级 Index/Bundle。 |
| 2 | 简单易用 | 基本满足 | Demo 宿主只需 `CCRouter.initialize`、`CCGoRouterBackend.managed`、`CCRouterApp.managed` 和 `MaterialApp.router`；生成也已收敛为一条命令。Shell、Multi Host、Aspect 和 CI check 等高级能力保持可选。 |
| 3 | 功能强大 | 基本满足 | 已覆盖类型安全导航、Deep Link、拦截、生命周期、混合路由、诊断和多种 Presentation，没有万能 Map 导航接口。组合栈事务与精确 Entry 操作已从 v0.1 API 删除并标记 Deferred；设备 Predictive Back 和 Restoration 仍是明确限制。 |
| 4 | 可扩展性 | 基本满足 | Core 使用中立 Route Definition；Catalog、Assembler、Adapter 与能力 SPI 分层。新后端可复用 Contract/Catalog；Host/Adapter 实现通过独立 `ccrouter_host.dart` 获取 SPI，业务 barrel 不再暴露该能力。 |
| 5 | 可测试 | 基本满足 | Pure Dart Runtime/Memory Adapter、Flutter Adapter、生成器和 Demo 都有回归；`ccrouter_test` 已提供 Test Host，并具备 5000 Route Generator 与 1000 Route Runtime 非门禁基准。长时间运行与跨版本内存趋势仍需持续积累。 |
| 6 | 最小公开 API | 基本满足 | Runtime、Scope、Memory Adapter、Host binding 以及 Adapter/Request/Capability/Backend 控制 SPI 已从业务 barrel 隐藏；Registrar 只拿到 `CCRegistry`，Host 组合根按需导入 `ccrouter_host.dart`。API surface 快照测试防止 SPI 意外回流。 |
| 7 | 编译器校验与类型安全 | 部分满足 | 参数、Codec、Route ID、Pattern、Contract exposure、页面实现、barrel 导出和组件依赖图已有生成期校验。拦截器/PopGuard 引用和 Adapter 能力主要仍在 Runtime 才失败。 |
| 8 | 非侵入式 | 满足 | 不要求页面基类或 Mixin，不保存全局 `BuildContext`；可继续使用应用自己的 `MaterialApp.router`/`GoRouter`；attached Adapter 不销毁应用 Router。 |
| 9 | 可降级回退 | 基本满足 | 无法可靠降级的组合栈事务与精确 Entry 操作已从公开能力链删除，不再静默模拟。解析前失败始终进入 Failure 记录；实际采用 Runtime visibility 或 partition-local reconciliation 时产生独立 capability fallback 事件。 |
| 10 | 明确生命周期 | 基本满足 | Runtime、Session、RouteEntry、Scope、Adapter、Backend 的 Owner 和销毁顺序明确，幂等与 pending Future 已有测试。组件 activate/deactivate 当前只覆盖 Route/Shell，完整 Service/Handler/Scope 生命周期仍按设计暂缓。 |
| 11 | 可观测可诊断可溯源 | 基本满足 | navigationId、来源、Owner、阶段耗时、bounded history、Listener 异常隔离均已具备。Pending、RouteEntry、Backend history/ledger 已使用安全地址摘要，完整 URI/location 只留在即时 operational pipeline；request 创建前的解析/参数失败和实际能力回退也有独立安全事件。 |
| 12 | 并发安全 | 基本满足 | 初始化/销毁、Session、Adapter 生命周期和导航并发策略已有确定语义，Defer/Timeout/Cancel 有回归。并发短路具有完整 Aspect 终态；Extra 请求明确独立执行；Interceptor、Policy、Guard、Aspect 和普通 Listener 统一使用 Zone 重入保护。 |
| 13 | 性能和稳定 | 基本满足 | 热路径无反射，路由 ID 与 Workspace Pattern 候选均使用索引，缓存与观察队列有界，纯观察回调不再同步阻塞导航，错误不被吞掉。生成器复用 build_runner 增量图，只扫描 Host 依赖闭包中的 Package metadata，使用内容指纹缓存、write-if-changed、并发锁和全量回退；已建立同机 benchmark 和资源生命周期回归。长期内存趋势仍需版本间持续采样，动态 URI 解析仍为线性工作。 |

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

### 已完成：P2-5 Telemetry/source 稳定标识校验

- `CCNavigationSource.id` 使用最大 64 字符的稳定分段标识语法，拒绝空白、URL 和凭证式字符；
- 匿名 Visitor/App Session ID 使用独立的有界 opaque 语法，允许 UUID 风格的数字开头；
- 非法来源和 Telemetry Context 安全降级为无 attribution 导航，并记录不包含原值的有界诊断；
- Framework DartDoc 和回归测试明确禁止账号、完整 URI、Token、设备 ID 与业务 Payload。

### 已完成首批基线：P2-6 性能与稳定性基准

仓库已提供非门禁式 Generator、Runtime scaling 和并发回收 benchmark，覆盖 Workspace 校验、Runtime 初始化、
动态 URI 解析、并发 Push/Pop 和销毁。动态 URI resolution 仍会遍历所有 Route/Pattern；生成器虽已改为精确闭包、
单 Package Index、内容缓存和 Pattern 候选索引，但基准只用于同机版本对比，不能把一次本机结果
视为跨机器性能承诺。

10/100/1000 Route 初始化、动态解析和 Runtime dispose p50/p95 已形成首批基线；持续 Push/Pop
后的台账有界性由回归测试覆盖。新增 10 轮、每轮 100 个并发 Push/Pop 的回收基准，峰值
`activeRouteEntries=101`，每轮结束均回到 1 个根 Entry，`pendingNavigations=0`，Adapter 栈也回到 1。
这验证了可观测的 Runtime 保留状态边界，但不替代真实 RSS/Heap 趋势；后者仍需在目标平台和应用中持续采样。
本次 OHOS SDK 本机 JIT 运行的 10 轮耗时为 `cycleUsP50=6994`、`cycleUsP95=10363`，仅作为同机
回归参考，不作为跨平台阈值。

2026-09-22 自动化质量维护复测结果如下，作为当前同机回归基线，不作为跨平台性能承诺：

- Runtime 10/100/1000 Route 初始化 P50/P95：`111/203us`、`146/356us`、`550/1298us`；
- Runtime 10/100/1000 Route 动态 URI 打开 P50/P95：`96/332us`、`186/392us`、`430/1089us`；
- Runtime 10/100/1000 Route dispose P50/P95：`33/88us`、`64/100us`、`59/295us`；
- 10 轮、每轮 100 个并发 Push/Pop：`cycleUsP50=7816`、`cycleUsP95=22726`，峰值
  `activeRouteEntries=101`，每轮结束恢复到 `finalActiveEntries=1`、
  `finalPendingNavigations=0`、`finalAdapterEntries=1`；
- Generator 10/100/500/1000/5000 Route 校验：`1.058/5.704/18.989/29.385/99.37ms`。

本次自动复测没有发现状态残留、性能异常或失败回归。并发执行 Generator 测试与 Demo Analyzer
会短暂读取 Generator 测试创建的临时探针，因此质量门禁必须串行执行；串行复测后 Demo Analyzer
恢复为无诊断。这是测试编排约束，不是生产代码依赖。

生成器聚合已增加非门禁式基准脚本：

```sh
fvm dart run packages/ccrouter_test/benchmark/generator_scaling.dart
fvm dart run packages/ccrouter_test/benchmark/runtime_scaling.dart
fvm dart run packages/ccrouter_test/benchmark/runtime_concurrency.dart
```

2026-09-20 本机 Dart JIT 预热后，旧 Validator 在 10/100/500/1000 Route 下分别为
`0.88ms`、`6.36ms`、`108.84ms`、`447.00ms`。加入 Type、URI Authority、Specificity 和固定段
倒排候选索引后，同一输入分别为 `0.88ms`、`2.78ms`、`6.02ms`、`19.31ms`，5000 Route 为
`60.74ms`。索引只筛选候选，最终冲突仍由原精确比较器确认；Wildcard 保守回退到同优先级全比较。
同机 Runtime 20 次生命周期与 100 次动态打开样本中，1000 Route 初始化 p50/p95 为
`461us/565us`，动态 URI 打开为 `375us/560us`，dispose 为 `37us/42us`。后续仍需补充并发压力
和跨版本内存趋势基线；本次已补充并发压力复测，但长期 RSS/Heap 趋势仍需持续采样。后者属于
持续观测工作，不是通过一次本机运行即可关闭的功能项。

### 已完成：P2-7 生成物最终审计

- 页面源码保持零 `part`、零生成文件 import；组件唯一 Route API 聚合内部 Intent factory，业务侧
  通过单一 generated API 获得 IDE 补全和自动导包；
- 单源码 Route、Route Binding、组件 Route Catalog、Package Bundle/Index、Host Catalog 和文档
  各自只有一个职责，没有重复声明公开 Intent 或重复构造 Runtime Route Definition；
- 组件业务 barrel 不再导出 Host-only intent；Host 装配入口集中在独立 host barrel，业务依赖不会
  意外获得 Host SPI；
- 非 nullable 且具有编译期空 List/Set 默认值的 Query 参数将空集合编码为缺失 key，解码恢复默认值；
  required、nullable 和非空默认集合继续严格拒绝无法无损表达的空集合；
- 默认缓存与 `--no-cache --check` 均验证 4 个组件、30 条路由和 7 个生成 Package，输出无差异；
  测试同时覆盖缓存损坏全量回退、并发生成锁、write-if-changed 和 stale cleanup。

### 已完成：P2-8 资源生命周期回归

- Runtime 连续 250 次 Push/Pop 后 Route Entry、Backend Entry 和 Pending Navigation 均为空，诊断
  history 保持容量上限；
- Host、Navigator Observer 和页面生命周期对象通过 leak tracker 回归；
- 自定义页面转场不再在 builder 中创建需要手动 dispose 的 `CurvedAnimation`，改用无独立所有权的
  `CurveTween` 链，并覆盖 Fade、Scale、右侧滑入和底部滑入的重复创建/销毁测试；
- 本轮基于 `not-disposed` 与 `not-GCed` 证据标准复查后，没有剩余高置信内存泄漏。

## 5. 已确认符合且应保持的边界

- 默认 Runtime 由 `CCRouter` 创建和销毁，业务不构造 Runtime/Scope。
- Registrar 只接收受限 `CCRegistry`，组件不获得 Runtime。
- 生成 Route Intent 和结果类型是业务导航主入口；动态 URI 是明确的兼容入口。
- GoRouter managed/attach 所有权不同，attach 不销毁应用 Router。
- 外部 Popup、Overlay 和 LocalHistory 不会按位置误删 Managed RouteEntry。
- Adapter 不支持某项语义时在变更栈前失败，不做不等价模拟。
- `CCNavigationFailureAttempt` 区分原始请求、拦截器重定向、Failure Policy 恢复和 pending
  resume；Failure Policy 不再通过模糊的 stage 或异常文本猜测来源。
- `ccrouter clean` 只删除可写 Package 中带 CCRouter 标记的生成源码，用户文件、只读依赖和
  build_runner 缓存均保留；清理后可由 `generate` 完整恢复。
- Managed Cupertino Route 安装 PopGuard 时禁用交互侧滑，保证手势不能绕过 Guard；Foreign
  Popup/LocalHistory 仍只影响自身，不会关闭底层 Managed Route Scope。
- Route/Session/Adapter pending Future 在 Pop、Reset、Go 和 shutdown 路径都有终止行为。
- Trace、Lifecycle、Failure、Aspect 和 Backend 历史均有容量边界，subscriber error 有界。
- 页面生命周期不要求业务继承基类；Mixin 和 Listener 均为可选。
- contracts Package 可以保持 Pure Dart，页面实现和后端依赖不进入跨组件契约。

## 6. 本轮最终门禁

- `fvm dart test packages/ccrouter_test/generator_test`：131 项通过；
- `fvm flutter test packages/ccrouter_test/test`：250 项通过；
- `fvm flutter test demo/test`：25 项通过；
- `fvm dart analyze`、`fvm flutter analyze demo`：无问题；
- `ccrouter generate demo --check` 与 `--no-cache --check`：生成物同步且等价；
- `fvm flutter build macos --debug`：成功生成 `ccrouter_demo.app`；
- `git diff --check`：通过。

后续增加 Android Predictive Back、Restoration、真实平台多窗口或新 Adapter 时，必须补对应平台
真机验证和能力回归；它们不属于本轮已经实现的路由能力。
