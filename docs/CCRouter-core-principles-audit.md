# CCRouter 核心价值与开发约定回归

## 1. 审查结论

- 审查日期：2026-09-20
- 审查范围：路由 Runtime、业务 Facade、Host/Adapter SPI、GoRouter Adapter、生成器、
  Demo、测试与诊断模型。
- 自动化基线：`dart analyze` 通过；Framework 192 项、Demo 6 项、Generator 78 项测试通过；
  macOS debug build 和交互验证通过。
- 总体结论：13 条约定的架构方向成立，但当前不能认定为全部对齐。没有阻断 Demo 的 P0
  问题；存在 5 项 P1 和 6 项 P2 欠账，应在冻结路由公开 API 前优先处理 P1。

本审查只记录事实和后续门槛，不因为某项容易实现就扩展公开 API。

## 2. 逐项对齐结果

| # | 约定 | 状态 | 当前证据与缺口 |
| --- | --- | --- | --- |
| 1 | 智能 | 部分满足 | Route/Codec/Manifest/组件索引/Host Catalog/文档均可生成；Runtime 自动校验并装配。缺口是 Workspace 聚合仍需在 `build_runner` 后手动执行第二条 CLI，且无增量缓存或生成物陈旧门禁。 |
| 2 | 简单易用 | 基本满足 | Demo 宿主只需 `CCRouter.initialize`、`CCGoRouterBackend.managed`、`CCRouterApp.managed` 和 `MaterialApp.router`。Shell、Multi Host、Aspect 等均为可选能力；生成阶段的两条命令仍增加首次接入成本。 |
| 3 | 功能强大 | 基本满足 | 已覆盖类型安全导航、Deep Link、拦截、生命周期、混合路由、诊断和多种 Presentation，没有万能 Map 导航接口。组合栈事务与精确 Entry 操作已从 v0.1 API 删除并标记 Deferred；设备 Predictive Back 和 Restoration 仍是明确限制。 |
| 4 | 可扩展性 | 基本满足 | Core 使用中立 Route Definition；Catalog、Assembler、Adapter 与能力 SPI 分层。新后端可复用 Contract/Catalog。业务 barrel 仍透出 Adapter SPI，边界尚未完全收口。 |
| 5 | 可测试 | 基本满足 | Pure Dart Runtime/Memory Adapter、Flutter Adapter、生成器和 Demo 都有回归；`ccrouter_test` 已提供 Test Host。尚无正式性能、长时间运行和大规模路由表基准。 |
| 6 | 最小公开 API | 部分满足 | Runtime、Scope、Memory Adapter 和 Host binding 已从业务 barrel 隐藏；Registrar 只拿到 `CCRegistry`。但 `ccrouter.dart` 仍通过 contracts barrel 暴露 Adapter、Request、Capability 和多个后端控制 SPI。 |
| 7 | 编译器校验与类型安全 | 部分满足 | 参数、Codec、Route ID、Pattern、Contract exposure、页面实现和 barrel 导出已有生成期校验。组件依赖缺失/环、拦截器/PopGuard 引用和 Adapter 能力主要仍在 Runtime 才失败。 |
| 8 | 非侵入式 | 满足 | 不要求页面基类或 Mixin，不保存全局 `BuildContext`；可继续使用应用自己的 `MaterialApp.router`/`GoRouter`；attached Adapter 不销毁应用 Router。 |
| 9 | 可降级回退 | 部分满足 | 无法可靠降级的组合栈事务与精确 Entry 操作已从公开能力链删除，不再静默模拟。解析前失败和观察能力降级仍没有统一进入 failure/diagnostic 记录。 |
| 10 | 明确生命周期 | 基本满足 | Runtime、Session、RouteEntry、Scope、Adapter、Backend 的 Owner 和销毁顺序明确，幂等与 pending Future 已有测试。组件 activate/deactivate 当前只覆盖 Route/Shell，完整 Service/Handler/Scope 生命周期仍按设计暂缓。 |
| 11 | 可观测可诊断可溯源 | 部分满足 | navigationId、来源、Owner、阶段耗时、bounded history、Listener 异常隔离均已具备。RouteEntry、Backend 和 Pending 快照仍可能保留完整 URI/location；部分前置失败没有事件。 |
| 12 | 并发安全 | 部分满足 | 初始化/销毁、Session、Adapter 生命周期和导航并发策略已有确定语义，Defer/Timeout/Cancel 有回归。拦截器及普通 Listener 的重入保护不完整，并发 key 未覆盖 Extra，且并发短路会遗留 Aspect record。 |
| 13 | 性能和稳定 | 未形成量化闭环 | 热路径无反射，路由 ID 使用索引，缓存有界，错误不被吞掉。但没有 benchmark、内存增长门槛或版本对比；动态 URI 解析和 Workspace 扫描仍为线性全量工作，观察回调同步阻塞导航。 |

## 3. P1 问题

### P1-1 并发短路会遗留 Navigation Aspect record

`_executeNavigationWithFailurePolicy` 在进入并发门前创建 Aspect record。`rejectDuplicate`
抛错或 `singleFlight` 直接返回已有 Future 时，没有生成本次 request 的 `after/lost`，也没有调用
`_discardNavigationObservation`。重复触发会让 `_navigationAspectRecords` 增长到 Runtime dispose。

建议：让并发门返回结构化结果 `accepted/rejected/shared`。Rejected 必须发出稳定 lost/after；Shared
必须记录 coalesced 关系并释放第二个 observation。补充重复调用、长时间循环和 dispose 回归。

### P1-2 并发 key 忽略 Extra，可能错误合并不同请求

当前 key 只包含 Host、Outlet、Operation、Route ID 和 normalized URI。两个 URI 相同但 Extra
不同的 typed navigation 在 `singleFlight` 下会共享第一个页面和结果，在 `rejectDuplicate` 下会误拒绝。

建议：首版对含 Extra 的 Route 禁止 `singleFlight/rejectDuplicate`，或增加由生成契约提供的稳定
dedupe key。不能对任意业务对象调用 `toString`、深比较或持久 hash。

### P1-3 重入保护没有覆盖 Interceptor 和普通 Listener

Aspect、Failure Policy 和 PopGuard 有 `_navigationCallbackActive`/Zone 保护，但
`CCNavigationInterceptor.intercept`、Navigation/Failure/Visibility/RouteEntry/Backend Listener
没有统一进入受控回调区。注释虽然禁止递归导航，Runtime 仍可能同步进入第二次 Adapter 操作。

建议：所有框架回调统一通过内部 callback runner，明确 decision callback 与 observer callback；
回调内同步导航稳定抛 `CCNavigationReentrancyError`，异步排队只能通过显式 post-navigation API。

### P1-4 Retained diagnostics 仍包含完整 URI/location

以下公开或有界历史会保存参数值：

- `CCPendingNavigation.uri`；
- `CCRouteEntrySnapshot.normalizedUri`，以及包含该快照的 Visibility/Entry 事件；
- `CCNavigationBackendEvent.uri/location`；
- `CCBackendEntry.location`。

这些字段可能包含 Query、Path 用户标识或第三方 RouteSettings 内容，与“日志/诊断默认不记录完整
URI”不一致。

建议：拆分 operational snapshot 与 sanitized diagnostic snapshot。栈 predicate 所需 URI 只留在
Runtime/Adapter 控制面；业务诊断默认只暴露 routeId、routePattern、Host/Outlet 和参数 presence。
确需原始位置时使用 Host-only、即时读取、显式 opt-in，且不得进入 retained history。

### P1-5 同步 Observer 可阻塞导航热路径

Aspect、Navigation Listener、RouteEntry/Visibility Listener 和 Backend Listener 都在导航或
Navigator callback 栈内同步执行。异常已隔离，但长耗时 CPU、同步 IO 或大量 listener 仍会直接增加
页面跳转延迟；目前没有采样、队列或 backpressure。

建议：决策钩子继续同步；纯观察钩子写入有界内部事件队列后异步 drain。明确 overflow 策略，只允许
丢弃非关键重复观察，失败终态和生命周期终态不可丢失。

## 4. P2 问题

### P2-1 业务 barrel 暴露了 Host/Adapter SPI

`package:ccrouter/ccrouter.dart` 直接导出大部分 `ccrouter_contracts`，因此业务可以看到并实现
`CCNavigationAdapter`、`CCNavigationRequest`、Capability Source、Backend Source、Pop
Coordinator 和 Exact Entry SPI。虽然正常入口不会使用它们，但没有满足最小权限。

建议：将 SPI 拆到独立 `ccrouter_host`/`ccrouter_adapter_contracts` library，或在业务 barrel 使用
完整 hide/show 清单；Adapter package 直接依赖 SPI library。

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

1. 修复 P1-1、P1-2、P1-3，并增加并发循环、重入和 Aspect 释放测试。
2. 设计 sanitized diagnostic snapshot，处理 P1-4；这是数据边界变更，应先写迁移说明。
3. 将纯观察回调改为有界异步分发，解决 P1-5，并建立顺序/overflow 测试。
4. 收口业务 barrel 的 Adapter SPI，补 API surface 快照测试。
5. 补 pre-dispatch failure/capability fallback 事件和 Workspace 依赖图校验。
6. 合并生成入口并建立 benchmark；得到基线前不做缓存和索引优化。

每一项完成后必须运行 analyze、Framework/Demo/Generator 全量测试，并重新执行 macOS Demo
交互回归。涉及 Android Predictive Back 时另加真实 Android 设备验证。
