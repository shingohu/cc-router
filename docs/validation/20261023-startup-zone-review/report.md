# InitTask 重入与共享初始化 error Zone 审查

状态更新：本报告保留审查时的失败证据；问题现已修复并纳入默认回归，见
[修复与验证报告](../20261023-shared-lifecycle-contract-fixes/report.md)。

2026-10-23；工作树 `managed-navigation-runtime/cc-router`，分支
`codex/managed-navigation-runtime`，HEAD `09cb21d`。

本轮只增加显式审查复现和报告，不修改生产实现、Demo、生成物，不提交或推送。
复现文件不以 `_test.dart` 结尾，必须显式执行；它们验证期望契约，当前实现存在失败。

## 结论与根因

确认三项新问题，归属两个横向不变量：外部同步回调执行前发布共享状态；共享执行
跨 error Zone 时不能直接复用会以 error 完成的 Future。本轮没有修复生产代码。

### P1：跨 error Zone shutdown 卡住，App Service 没有释放，Host 无法重新初始化

位置：`packages/ccrouter_core/lib/src/runtime_host.dart:1943`，尤其是
`await initTaskRun`。公共入口是 `CCRouterHost.runInitTasks/shutdown`。

步骤：

1. Host 初始化，解析一个 App-scoped disposable Service。
2. 在一个 `runZonedGuarded` error Zone 启动 InitTask，任务等待自身 cancellation。
3. 在另一个 error Zone 调用 `CCRouterHost.shutdown()`，各调用者都在自己的 Zone
   内处理返回 Future，没有在测试代码中跨 Zone 直接 await error Future。

实际结果：任务已返回 `CCInvocationCancelledError`；shutdown 未结束；Service
dispose 次数为 0；再次 initialize 抛 `CCRouterAlreadyInitializedError`；启动任务
的 Zone 还收到一次未处理取消错误。Core 复现与公共 Host 复现一致。同一 error
Zone 的 shutdown 对照通过，普通 Host 跨 Zone shutdown 的既有回归也通过。

根因：`_initTaskRun` 保存启动者 Zone 中的 error Future，shutdown 从另一个 error
Zone await。Dart 不把异步 error 传过不同 error Zone，因此这里的 catch 也无法执行。
Host 外层已有的 cleanup outcome 桥不能修复 Core 内部卡住的 await。

影响：清理停在 Route/Adapter/App Scope 释放前，框架 Host 的 shutdown gate 一直
占用。已证明 `not-disposed` 的 App Service；没有进行 heap/GC 或设备内存认证。
200ms watchdog 仅用于探测未完成，不是框架 shutdown 性能 SLA；任务已经取消且
没有剩余应用工作，这是内部错误传递被截断，而非 initializer 忽略协作取消。

最小修复方向：内部 drain 以成功 Future 携带 completion/failure 数据，shutdown
等待内部 outcome；各调用者在自己的 error Zone 中恢复原错误与堆栈。保留错误
隔离、单次清理和 Host 现有的重复 shutdown 行为。

### P1：同步重入 Gate 会重复执行 InitTask，并提前返回未完成的 drain

位置：`packages/ccrouter_core/lib/src/runtime_host.dart:1753`。

`_drainAndReleaseInitTasks()` 可以同步进入任务回调，但 `_initTaskRun` 要等它返回
Future 后才赋值。Host-owned 回调在此窗口再次打开同一或另一 Gate，会启动第二个
drain；内层启动了外层 ready 列表里尚未标记 running 的同层任务，外层随后又启动
一次。两个复现均得到 siblingRuns=2，违反 exactly-once。

另一复现中，启动任务同步打开 privacy Gate，privacy 任务停在显式 Completer 上，
首个 drain 却已经成功返回。普通的非重入重叠调用仍共享同一 Future，正常对照通过。
这里没有让任务 await 自己所属的 drain；这种自等待不是本 finding 的前提。

影响：一次性 SDK 初始化或订阅安装可能重复，Host 可能在新打开 Gate 的工作仍
running 时误以为启动已完成。复现用计数器验证执行次数，不声称已产生供应商副作用。

最小修复方向：在任何任务或外部回调开始前，先建立 Completer/运行记录并发布
single-flight 状态，再驱动 DAG；保留 Gate 合并、独立 ready 任务并行、失败跳过、
shutdown 取消，并检查 release 只清理当前运行记录。

### P2：共享 Service readiness 与 singleFlight 导航的失败无法到达跨 Zone 等待者

位置：

- `packages/ccrouter_core/lib/src/scope.dart:68`，共享 readiness Future 的等待路径；
- `packages/ccrouter_core/lib/src/navigation.dart:571`，`_observeSharedNavigation`
  直接 await 原调用者 Future。

Service 复现：两个调用方在不同 error Zone 同时等待一个 singleton initializer；
初始化失败后首个调用者得到 `CCServiceInitializationError`，第二个无结果，原 Zone
出现额外未处理错误。initializer 只执行一次。相同 error Zone 的失败、跨 Zone 的
成功，以及初始化已经结束后再加入的调用均通过；不把这些正常情况扩大报告为缺陷。

导航复现：两个不同 error Zone 对同一路由发起 singleFlight Go，异步 Interceptor
返回 `CCNavigationCancel`。只执行一次 policy，首个调用者收到
`CCRouteCancelledError`，共享调用者无结果；两个独立导航 observation 只有一个
产生 terminal Aspect，原 Zone 出现额外未处理取消错误。相同 error Zone 的取消与
跨 Zone 成功对照通过。Aspect 是延迟观察，测试在正确的 event-loop 边界后断言。

这两条路径与 shutdown 具有相同的共享 error Future 根因，但影响是业务等待与
导航观察无法终结。未配置调用超时的等待者可能一直等待；外部增加 timeout 只能
获得超时，不能恢复应收到的原始失败，也不能补齐 terminal observation。

最小修复方向：共享执行记录保存内部 outcome，在加入者自己的 error Zone 重建
失败，保留原 error identity/stack、Trace/导航 identity、single-flight 的一次执行
以及失败 readiness 不自动重试的契约；不要按 Zone 分裂初始化/导航成多次执行。

## 方案取舍与推荐顺序

| 方案 | 收益和代价 | 判断 |
| --- | --- | --- |
| Demo 增加 timeout、要求业务只用一个 Zone | 局部绕过挂起，原错误与清理仍不正确 | 不推荐作为框架修复 |
| 按 Zone 分开初始化/导航，或全局串行执行 | 避开部分共享问题，但破坏 singleton/单次导航，可能自等待 | 不推荐 |
| 先发布运行记录，私有共享 outcome 按调用 Zone 交付 | 保留 API 和共享执行；需验证错误身份、堆栈、取消、晚到清理 | 推荐 |

建议顺序：

1. 先补正常发现的失败回归，修复 InitTask 运行记录的同步发布；继续保留同 Zone
   重叠调用的现有共享行为。
2. 修复 Core 内部 InitTask outcome 与 shutdown 的等待，验证公共 Host 能重新初始化、
   所有 Scope/Adapter/Service 恰好释放一次。
3. 将相同的私有 outcome 原则应用到 readiness 和导航 singleFlight，覆盖成功、
   失败、取消、timeout、晚加入和 caller/Host/Runtime 终止。
4. 再跑全量回归与生成检查；行为修复时同步 README、集成 Skill 和相关 reference。
   不新增业务 API，不要求应用导入 Runtime 或内部 SPI。

## 为什么仍在发现问题

前轮重点覆盖了导航 identity、Host 注册事务和异步交接取消，但没有把以下不变量
统一应用到所有能力：

- 发布共享状态必须先于任何可重入回调。MultiHost 已处理，InitTask 调度仍有独立缺口。
- 执行共享不等于共享一个 error Future。Host cleanup 外层已有跨 Zone 保护，内部
  InitTask、Service readiness 和导航 singleFlight 仍直接共享错误传递。
- 普通重叠、回调同步重入、异步恢复、相同 error Zone、不同 error Zone 是不同测试
  维度。只测顺序成功与普通并发，不能证明这些边界。

本轮按共同机制扩展到 Service 和导航，避免只修一个挂起点。后续修复应把这些
维度加入共享运行记录的常规回归，而不是继续按 Demo 按钮逐个加补丁。

## 验证范围与结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Gate 重入、readiness 与 shutdown 探针 | 15 项：9 对照通过、6 个有效失败 | [repros.log](repros.log) |
| singleFlight 导航 error Zone 探针 | 4 项：3 对照通过、1 个有效失败 | [navigation-zone.log](navigation-zone.log) |
| 原有 Flutter/Demo 常规回归 | 924 通过 | [flutter.log](flutter.log) |
| 应用 analytics 与工具测试 | 55 通过 | [dart.log](dart.log) |
| Workspace analyze | No issues found | [analyze.log](analyze.log) |

显式复现命令（返回非零是期望契约未被满足，不是修复成功）：

```sh
fvm flutter test --no-pub \
  packages/ccrouter_test/test/review_repros/init_task_reentrancy/repro.dart \
  packages/ccrouter_test/test/review_repros/init_task_reentrancy/error_zone_repro.dart \
  packages/ccrouter_test/test/review_repros/init_task_reentrancy/host_shutdown_repro.dart \
  --reporter expanded
fvm flutter test --no-pub \
  packages/ccrouter_test/test/review_repros/init_task_reentrancy/navigation_zone_repro.dart \
  --reporter expanded
```

常规回归命令：

```sh
fvm flutter test --no-pub packages/ccrouter_test/test demo/test \
  demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test \
  tool/test --reporter expanded
fvm dart analyze
```

本轮常规回归包括已有 Route/close/Back/Shell/Outlet/MultiHost/revalidation、Service
Scope/readiness、Command/Event 嵌套调用、InitTask DAG/失败策略、diagnostics 和
UI Fragment 场景；不代表所有调度、平台与性能已穷举。未修改生成输入，未执行本轮
生成/独立 Analyzer Plugin/Generator 专项测试；没有新增 macOS 真实窗口、Android/iOS
手势或性能内存认证。

没有新增 Demo 按钮：已有能力页包含 InitTask Gate、Service 和并发导航演示，本轮
缺口需要同步重入与隔离 error Zone 的调度夹具，普通点击无法可靠覆盖。保留失败
证据比加入掩盖失败的业务 timeout 更合适。生产修复后应把这些显式复现迁入默认
回归发现，不能把当前 924 通过误写成新增边界也已通过。
