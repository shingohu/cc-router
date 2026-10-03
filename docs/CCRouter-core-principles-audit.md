# CCRouter 核心价值与开发约定回归

> 本文主体保留 2026-09-30 的审查快照。后续 2026-10-03 全框架审查发现了新的未修复
> 缺陷，最新逐项结论与实施顺序见[全框架审查](CCRouter-framework-audit-2026-10-03.md)。
> 下文“没有本轮未解决 P0/P1”仅代表历史审查，不能作为当前无缺陷结论。

## 1. 审查结论

- 审查日期：2026-09-30
- 审查范围：路由 Runtime、业务 Facade、Host/Adapter SPI、GoRouter Adapter、生成器、
  Service、Command、Event、初始化任务、Demo、测试与诊断模型。
- 自动化基线：`dart analyze packages` 与 Demo Analyze 通过；`ccrouter_test` 354 项、Demo 36 项、
  Generator 249 项测试通过；Demo 生成物缓存与 `--no-cache` 两种 `--check` 均通过。根 Workspace
  Analyze 当前被 Analyzer Plugin Git bootstrap 的外部凭据获取失败阻断，不属于 Dart 诊断；此前
  macOS、iOS Simulator、Android、Web 和 OHOS 构建 smoke 结果未在本轮重复执行。
- 总体结论：当前实现满足 13 条约定在当前静态组件范围内的实现门槛，没有本轮审计发现且
  未解决的 P0/P1 实现缺陷；正式 Hosted 发布、迁移文档和长期生产观测仍未完成。本轮实际发现
  并修复了 InitTask 重叠 Gate 丢失新就绪任务、Generated SPI 只信任
  生成期身份、Adapter attach 失败状态残留，以及 Runtime/Multi-Host 清理被单点异常中断的问题；
  这些修复均已有回归测试，不能只归类为文档调整。
  Route、Service、Command、Event 和 InitTask 已形成边界明确的最小闭环。生成物职责、API 隔离、
  生命周期、取消与诊断已完成本轮收口；Service Contract 自动绑定、Provider 最小注解与消费组件
  方法级 Proxy 与 Command/Event/InitTask 注解生成已实现；Action Pipeline、动态
  组件治理、Restoration、真实平台多窗口和长期 RSS/Heap 趋势仍是明确后续项，不能因已有设计
  文档而视为已经实现。
  Host 初始化现已收敛为一个必填 `CCHostAssembly`：生成 Host、手写 Host 和测试使用同一原子
  快照，旧的 `components/contractBundle/hostAssembly` nullable 参数组合已删除。

本审查只记录事实和后续门槛，不因为某项容易实现就扩展公开 API。

## 2. 逐项对齐结果

| # | 约定 | 状态 | 当前证据与缺口 |
| --- | --- | --- | --- |
| 1 | 智能 | 基本满足 | 顶层 Component、Route/Codec、简单 Service Provider、Command/Event/InitTask Handler、私有 Registrar/Manifest、Host Catalog/文档均由单一 `ccrouter generate` 编排生成；稳定 Host barrel 只导出原子 `CCHostAssembly`，Manifest、Contract、Catalog 与可选 Tool Integration 不再拆分传递。Runtime 自动校验组件与最终注册边界，`--check` 提供不依赖 Git 的只读陈旧门禁。复杂 Service 与未注解迁移能力使用显式 Contribution，没有用反射或函数体扫描冒充自动化。 |
| 2 | 简单易用 | 基本满足 | 宿主使用 `CCRouter.initialize(hostAssembly: ...)`、按需 `runInitTasks`、`CCGoRouterApp()` 即可启动；默认 managed App 自动读取初始化时安装的 Catalog，不再重复传参。手写 Host 使用 `CCHostAssembly.fromComponents`，不再理解 nullable 参数互斥规则。业务统一通过 `CCRouter.navigator/service/command/event`。Route Service 仅在需要精确页面 Scope 时增加 `BuildContext`，高级 Shell、Multi Host、Trace 和 Gate 保持渐进可选。 |
| 3 | 功能强大 | 基本满足 | 已覆盖类型安全导航、Deep Link、拦截、生命周期、混合路由、诊断、多种 Presentation、App/Session/Route Service、一次性 Command、事实 Event 和启动 DAG，没有万能 Map 或混合消息接口。Action Pipeline、可靠持久消息和动态组件明确不属于 1.x。 |
| 4 | 可扩展性 | 基本满足 | Core 使用中立 Route Definition 与强类型能力契约；Catalog、Assembler、Adapter、Service Provider、Handler 和 Gate 均通过明确边界扩展。新导航后端复用同一 Catalog，跨组件 Service 通过注解稳定 ID 和自动绑定渐进提升，不访问 Runtime 私有表。 |
| 5 | 可测试 | 基本满足 | Pure Dart Runtime 覆盖 Scope、readiness、Command/Event、InitTask DAG、取消/超时/失败；Flutter Adapter、生成器和 Demo 均有回归。`ccrouter_test` 提供 Test Host/Service Override，并具备 Generator、Route Runtime、Service 和并发回收非门禁基准。长期平台内存趋势仍需持续积累。 |
| 6 | 最小公开 API | 基本满足 | Runtime、Scope、Memory Adapter、Host binding 以及控制 SPI 均从业务 barrel 隐藏；Registrar 只拿到注册面 `CCRegistry`。`CCRouter.initialize` 只接受一个必填 Host Assembly，稳定生成入口也只导出该值；Catalog 自动解析仅存在于 Host Binding，没有增加 `CCRouter.routeCatalog` 业务 getter。Query/旧 Action/ActionReport 已删除，通信只保留 Service、Command、Event 与 InitTask；Action Pipeline 等未成熟能力没有提前公开。 |
| 7 | 编译器校验与类型安全 | 基本满足 | Route 参数、Codec、ID、Pattern、Contract exposure、页面实现、barrel、组件图、Service、Command、Event 与 InitTask 所有权和冲突已有生成期校验；缺少 Host Assembly 或继续传递旧 `components` 参数会由标准 Dart Analyzer 直接拒绝，不依赖可选 Analyzer Plugin。InitTask metadata 会形成完整跨 Package DAG。Runtime 会根据实际安装的 Manifest 再次校验 Generated Service/Command/Event 的组件身份和依赖边，陈旧生成物或手工调用 generated bridge 不能伪造调用归属。 |
| 8 | 非侵入式 | 满足 | 不要求页面基类或 Mixin，不保存全局 `BuildContext`；可继续使用应用自己的 `MaterialApp.router`/`GoRouter`；attached Adapter 不销毁应用 Router。 |
| 9 | 可降级回退 | 基本满足 | 无法可靠降级的组合栈事务与精确 Entry 操作已从公开链删除。Service optional lookup 只吞“未注册”，不吞工厂/生命周期错误；Event Subscriber 失败按契约隔离；InitTask required/optional 失败以脱敏结果返回，只有 Host 显式选择严格模式才抛错。 |
| 10 | 明确生命周期 | 基本满足 | Runtime、Session、RouteEntry、Service Scope、Adapter、Backend 和 InitTask Owner/销毁顺序明确；App/Session/Route Service 自动持有与逆序释放，shutdown 取消并等待活动调用和 DAG。Runtime 与 Multi-Host 在 remover、PopGuard、Adapter 或 Scope 清理失败时仍继续释放其余资源并返回首个错误，Adapter attach/Host 注册失败会回滚部分绑定。1.x 组件集合只在初始化确定，不提供不完整的 activate/deactivate。 |
| 11 | 可观测可诊断可溯源 | 基本满足 | Navigation、Service、Command、Event Subscriber 和 InitTask 均记录稳定 ID、可信 Owner、Trace 父子关系、状态和耗时；历史与 Subscriber error 有界，错误只保留类型和安全摘要。URI、Extra、消息字段、Service 参数/返回值和异常消息不进入 retained diagnostics。 |
| 12 | 并发安全 | 基本满足 | 导航策略、Service singleton readiness、InitTask Gate drain 都有 single-flight；重叠 Gate 在活动 drain 期间会触发下一轮 DAG readiness 检查，直到没有新就绪任务，避免任务永久停留在 `pending`。Event Subscriber 并发但按稳定 ID 启动；timeout、caller/Scope/shutdown cancellation 和异步依赖环均有测试。共享状态由 Runtime/Scope 单 Owner 修改，回调重入受控。 |
| 13 | 性能和稳定 | 基本满足 | 热路径无反射；路由和 Workspace 候选使用索引，诊断队列有界。Service 同步 Provider 不增加异步切换，Singleton/readiness 缓存按 Scope 有界，Event/InitTask 仅在显式调用时调度。生成器使用精确依赖闭包、内容指纹、write-if-changed、并发锁和全量回退；缓存/无缓存逐字节一致，`ccrouter find` 只读取 Host 依赖闭包 Index。已有 Route、Service、并发与资源回收基线，长期内存趋势仍需版本间持续采样。 |

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
- 普通生成清理由框架标记但不再有 owner 的 `.component.g.dart`/`_ccrouter.g.dart` 聚合物，
  且只清理解析图中明确可写的 Package；同名手写文件和外部 path/Git/pub Package 保持不动；
- 没有生成能力的 Package 不创建 `ccrouter_generated`；最后一个受管产物删除后只清理真正为空
  的目录，存在未知文件时完整保留；
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

仓库已提供非门禁式 Generator、Runtime、Service scaling 和并发回收 benchmark，覆盖 Workspace
校验、Runtime 初始化、动态 URI 解析、Service 装配/查询/调用/readiness、并发 Push/Pop 和销毁。
动态 URI resolution 仍会遍历候选 Route/Pattern；生成器使用精确闭包、单 Package Index、内容缓存
和 Pattern 候选索引。基准只用于同机版本对比，不能把一次本机结果视为跨机器性能承诺。

生成器聚合已增加非门禁式基准脚本：

```sh
fvm dart run packages/ccrouter_test/benchmark/generator_scaling.dart
fvm dart run packages/ccrouter_test/benchmark/runtime_scaling.dart
fvm dart run packages/ccrouter_test/benchmark/runtime_concurrency.dart
fvm dart run packages/ccrouter_test/benchmark/service_scaling.dart
```

2026-09-27 在修复 benchmark 入口和 caller fixture 后重新执行当前本机 Dart JIT 基线：

- Generator 5000 Route 固定路径校验：`54.419ms`；
- Runtime 1000 Route 初始化 P50/P95：`455/527us`，动态 URI 打开：`424/3773us`，
  dispose：`39/55us`；
- 10 轮、每轮 100 个并发 Push/Pop：`cycleUsP50=3574`、`cycleUsP95=9208`，结束时
  `finalActiveEntries=1`、`finalPendingNavigations=0`、`finalAdapterEntries=1`；
- Service 1000 Provider 初始化 P50/P95：`3304/3627us`，`invokeServiceSync`：`4/13us`，
  dispose：`147/442us`，每轮实例计数均归零。

这些结果没有形成跨机器硬阈值。Runtime 动态打开 P95 相比 P50 波动明显，后续版本应在同机、同
SDK 和相同预热条件下比较趋势；不能仅凭单次样本认定回归，也不能通过减少生命周期或诊断工作
换取更低数字。持续 Push/Pop 后的台账恢复和 Service 实例归零只证明可观测状态有界，不替代真实
RSS/Heap 趋势；后者仍需在目标平台和生产应用中持续采样。Generator 测试与 Demo Analyzer 必须
串行执行，避免 Analyzer 短暂读取 Generator 测试创建的临时探针而产生假诊断。

### 已完成：P2-7 生成物最终审计

- 页面源码保持零 `part`、零生成文件 import；组件唯一 Route API 聚合内部 Intent factory，业务侧
  通过单一 generated API 获得 IDE 补全和自动导包；
- 单源码 Route、Route Binding、组件 Route Catalog、Package Bundle/Index、Host Catalog 和文档
  各自只有一个职责，没有重复声明公开 Intent 或重复构造 Runtime Route Definition；
- 组件业务 barrel 不再导出 Host-only intent；Host 装配入口集中在独立 host barrel，业务依赖不会
  意外获得 Host SPI；
- 非 nullable 且具有编译期空 List/Set 默认值的 Query 参数将空集合编码为缺失 key，解码恢复默认值；
  required、nullable 和非空默认集合继续严格拒绝无法无损表达的空集合；
- 默认缓存与 `--no-cache --check` 均验证 4 个组件、31 条路由和 8 个生成 Package，输出无差异；
  测试同时覆盖缓存损坏全量回退、并发生成锁、write-if-changed 和 stale cleanup。

### 已完成：P2-8 资源生命周期回归

- Runtime 连续 250 次 Push/Pop 后 Route Entry、Backend Entry 和 Pending Navigation 均为空，诊断
  history 保持容量上限；
- Host、Navigator Observer 和页面生命周期对象通过 leak tracker 回归；
- 自定义页面转场不再在 builder 中创建需要手动 dispose 的 `CurvedAnimation`，改用无独立所有权的
  `CurveTween` 链，并覆盖 Fade、Scale、右侧滑入和底部滑入的重复创建/销毁测试；
- 本轮发现并修复 Adapter attach、动态 Host 注册、初始多 Host 装配、Host 注销和 Runtime shutdown
  的失败路径：一个 listener remover、PopGuard 解绑或 Adapter 抛错不再跳过其余 owned resource；
  原始失败或首个 cleanup failure 仍返回调用方；
- 本轮基于 `not-disposed` 与 `not-GCed` 证据标准复查后，没有剩余高置信的框架自有资源泄漏。
  第三方 Adapter 的 remover 若抛错且其实现仍强引用 callback，框架无法替它解除引用；这是 Adapter
  SPI 的实现责任，框架会清除自身引用并继续释放其它资源。

本轮新增的私有 Runtime Resolver 只保存默认 Runtime 引用和 Zone-local overlay，不创建 Timer、
Listener、Stream、Overlay 或 Controller；Resolver 不拥有 Runtime，也不负责销毁，因此没有新增
可疑释放路径。嵌套 Test Host overlay 恢复测试和全量资源回归均通过。

### 已完成：P2-9 Service、Command、Event 与初始化任务闭环

- Service 生命周期与创建策略正交：App/Session/Route Scope 分别拥有 `singleton`/`newInstance` 实例，
  `CCDisposable` 由 Scope 逆序释放；Route Service 只通过 Managed Page 的精确绑定解析，不猜当前页；
- Lazy Service readiness 由显式异步 API 启动，Singleton 在当前 Scope single-flight，`newInstance` 每次
  初始化；同步解析不会偷跑 I/O，失败、timeout、caller cancellation 和 Scope cancellation 保持
  不同标准错误；
- 跨组件 Service 的稳定 Contract ID 与 Type lookup 共享 Provider/实例；Key 支持确定性多实现，
  optional lookup 只把真正缺失转为 null；测试替换留在 `ccrouter_test`；
- `@CCServiceContract` 生成内部 Token/metadata，`@CCService` 从唯一直接 Contract 自动生成简单
  Provider registration，Package 唯一 `CCComponent` 自动生成私有 Registrar/Manifest；复杂构造
  与 readiness 继续使用 `@CCComponentContribution`，不在 Annotation 中注入任意执行代码；
- Service/Command Contract alias 已作为全部消费者的默认 Client 成员名进入 metadata 和 shape
  fingerprint，Dependency alias 可局部覆盖；alias migration CLI/Analyzer Quick Fix 尚未实现；
- `CCCommand<R>` 是唯一的一对一操作消息，支持 `R` 与 `void`、单 Handler、timeout、取消、嵌套
  Trace 和 Runtime shutdown；读取能力保持在 Service，不再保留重复的 Query/Action 表面；
- `CCEvent` 只表达已经发生的事实；静态 Subscriber 并发执行且按 ID 稳定启动，一个 Subscriber
  失败只进入有界脱敏诊断，零订阅者成功，发布 deadline/cancellation 仍会终止整体操作；
- InitTask 在同步 `initialize()` 校验 ID、依赖和 DAG，Host 显式打开 Gate；同层并发、重叠触发
  single-flight；活动 drain 中打开的新 Gate 会继续 drain 到稳定状态。每任务 exactly-once，
  required/optional/skip、显式严格模式、timeout 和 shutdown 等待已有回归；
- Demo 通过真实 Runtime 覆盖 Command typed/void/timeout/cancel/error、Event 多订阅/隔离/零订阅/
  timeout、InitTask Gate/失败依赖，以及 Service 全部 Scope、创建策略、readiness、多实现、optional
  lookup 和自动销毁；
- Action Pipeline 等待动态预埋操作链的真实业务样本；Service 方法 Proxy 已采用显式消费依赖，
  只为真实跨组件 Contract 生成组件专属 Client；Command 已形成 Contract、唯一 Handler、显式
  消费依赖、组件专属 Client 和 metadata 已实现；Event Contract、静态 Subscription、Owner
  自动 Publication Client、metadata 和 Catalog 已实现；InitTask 的 Task Contract、顶层 Handler、
  类型化依赖、自动注册、DAG/Catalog 和 Workspace 校验也已实现。

Generated Service/Command/Event 的 Package exposure、Owner 和消费依赖先由 Generator/Workspace
Validator 校验，Runtime 再对实际安装组件图做二次校验。Event 的零 Subscriber 语义仍是成功
no-op；由于此时 Runtime 没有 Subscriber 可反推出 Contract Owner，它只能证明 Publisher 身份已
安装，无法独立证明手工 generated SPI 提供的 Publisher 就是 Contract Owner。正常业务 API 和
生成代码路径已阻止该调用方式；若未来要把 generated SPI 提升为独立防伪边界，需要新增 Event
Contract Runtime Registry，而不是改变零订阅者语义。

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
- 读取和长期能力使用 Service；唯一执行者的一次性操作使用 Command；已发生事实通知使用 Event；
  Runtime 一次性启动依赖使用 InitTask，不以万能消息类型互相替代。
- `CCRouter.initialize()` 保持同步原子装配；异步启动工作必须通过显式
  `runInitTasks(gate: ...)` 等待，Service readiness 不隐藏在全局启动中。
- 组件集合在初始化时一次确定。1.x 不提供不完整的动态 activate/deactivate，也不允许业务销毁
  Runtime、Scope、Adapter 或 Service 实例。
- 简单 Service 使用生成注册，跨组件 Service 使用显式消费声明生成方法 Proxy；复杂 Service 和
  未注解迁移能力使用显式 Contribution，InitTask 使用专用 Contract/Handler 生成。当前 Proxy
  不支持的方法形态只有在真实
  所有权与取消语义明确后才扩展。

## 6. 本轮修复与残余风险

本轮核心价值回归不是“全部满足”的形式化勾选，实际收敛了四类问题：

1. **并发确定性**：重叠 InitTask Gate 过去可能复用一个即将完成的 Future，却不再检查新 Gate
   解锁的任务；现在共享 drain 会运行到 DAG quiescent。
2. **纵深类型安全**：Generated Service/Command/Event 过去主要依赖生成期身份；现在 Runtime 会
   拒绝未安装组件、Contract/Handler 不一致和缺失依赖边，再进入业务执行与 Trace。
3. **失败原子性**：Adapter attach 或 Host 注册中途失败过去可能留下 listener、ledger 或已插入
   Host；现在会回滚框架侧状态，并保持 Adapter 所有权契约。
4. **生命周期稳定性**：单个 cleanup 回调过去可能中断后续 Adapter、Scope 或 Host 释放；现在采用
   best-effort 全量清理并保留首个异常。
5. **Host 装配原子性**：Facade 过去以多个 nullable 参数表达生成与手写两种装配模式；现在统一
   接受一个必填 `CCHostAssembly`，手写工厂在 Runtime 可见前完成组件拓扑、Contract 与 Tool
   Integration 校验，稳定 Host barrel 不再并列暴露可混用的 Manifest/Catalog 顶层变量。

仍需明确保留以下边界，不能在 1.x 审计中误报为已完成：

- 长期 RSS/Heap 趋势、真实平台多窗口和不同 SDK/Adapter 版本性能仍需生产接入持续采样；当前
  benchmark 只证明有界状态和同机基线。
- 零 Subscriber Event 的 Contract Owner 独立 Runtime 证明需要额外 Registry；当前由生成期校验、
  Package 边界和实际安装 Publisher 校验共同保证正常集成路径。
- Action Pipeline、动态组件、Restoration、Navigator 1/2 新 Backend 和真实平台多窗口仍属于后续
  设计或 2.0 工作，不应为满足“功能强大”而提前扩张公开 API。

## 7. 本轮最终门禁

- `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test`：249 项通过；
- `fvm flutter test --concurrency=1 packages/ccrouter_test/test`：354 项通过；
- `fvm flutter test --concurrency=1 demo/test`：36 项通过；
- `fvm dart test --concurrency=1 packages/ccrouter_devtools_protocol/test`：4 项通过；
- `fvm flutter test --concurrency=1 packages/ccrouter_devtools/test`：7 项通过；
- `dart analyze && dart test`（`packages/ccrouter_analyzer_plugin`）：无问题，8 项通过；
- `fvm flutter analyze devtools/ccrouter_extension`：无问题；
- `fvm dart analyze packages` 与 Demo `fvm flutter analyze`：无问题；根 Workspace Analyze 因
  Analyzer Plugin Git bootstrap 无法读取外部 GitHub 凭据而在插件安装阶段失败，本轮没有将其
  误记为 Dart 代码失败或通过；
- `fvm dart run ccrouter_generator:ccrouter generate demo --check --profile` 与
  `--no-cache --check --profile`：生成物一致，缓存和无缓存路径均通过；
- `ccrouter find` 已验证 Route ID/Pattern 与 InitTask 稳定 ID，查询只读且受 Host 依赖闭包约束；
- `fvm flutter build macos --debug`、`ios --simulator --no-codesign`、`apk --debug`、`web` 和
  `hap --debug`：均成功；这些是当前 SDK/主机的构建 smoke，不等价于真实设备手势、原生多窗口
  或长期 RSS/Heap 无泄漏证明；
- Runtime/Service/Command/Event/InitTask 混合性能回归、Analytics 队列压力和资源释放回归通过；
  1x/10x/20x/30x 生成基准已覆盖冷/热路径，长期 RSS 仅作为同机趋势保存；
- `git diff --check`：通过。

后续扩展 Service Proxy 方法矩阵、Action Pipeline、动态组件、Android Predictive Back、
Restoration、真实平台多窗口或新 Adapter 时，必须补对应构建期、生命周期、并发、性能和平台
回归；它们不属于本轮已经实现的能力。
