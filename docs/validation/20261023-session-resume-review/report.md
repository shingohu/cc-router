# Session 旧工作与 Deferred Resume 扩展审查

> 状态更新：两项缺陷已修复并进入默认回归；最终结果和范围见
> [Session/Resume 修复报告](../20261023-session-resume-fixes/report.md)。
> 以下保留修复前复现与失败证据。

2026-10-23；工作树 `managed-navigation-runtime/cc-router`；分支
`codex/managed-navigation-runtime`。本轮只新增复现测试与审查记录，未修改生产实现。
前轮修复状态以 `20261023-shared-lifecycle-contract-fixes/report.md` 为准；本报告
不把历史失败当作新问题。

## 发现

### P1：已取消的旧 Session 工作仍能同步取得新账号的 Service

- 位置：`packages/ccrouter_core/lib/src/runtime_host.dart:2115`，尤其
  `2117–2126`；Session 选择入口在同文件 `2291–2297`。
- 条件：Session A 的 initializer 或已进入的 Service 方法在 await 中暂停；
  关闭 A、等待其调用返回取消、开启 B，然后恢复旧工作。
- 实际：旧工作中的 `service<AccountResource>()` 和
  `services<AccountResource>().single` 均成功构造并获得 B 的资源。
  探针确认旧 context 的 cancellation 已为 true；不是调用者忘记关闭 Session。
  同样条件的 `serviceAsync` 正确返回取消，未构造 B 的资源。
- 影响：旧账号的异步延续可进入新账号的 Service 对象图，造成跨账号读取或后续写入。
  本轮证明了资源取得与构造，不声称已发生真实业务数据泄漏。
- 根因：同步解析只验证 Scope 类别依赖和当前选中 Scope 是否 active。
  `_scopeForProvider` 对 session 始终选择可变的 `_sessionScope`，而 `_resolve`
  未检查当前父 Invocation 已取消、原 construction owner 已结束。
  仅检查新 Scope active 不能证明旧调用有权进入它。
- 建议：在同步解析进入 factory/cache 前统一检查当前 Invocation cancellation/deadline
  和 construction owner 的具体生命周期；同 Session 依赖不得从已关闭 owner 重新
  绑定到新 Session。覆盖 `service/services` 及其可空、Key、newInstance 等邻近
  入口，不扩大业务 API。不能只校验 construction owner：普通方法延续不在该 Zone 中。

12 项 Session 探针：未切账号的 6 项均成功；切账号后的异步 2 项正确取消；
同步 4 项有效失败（initializer/普通方法 × 单个/批量查找）。
这些失败检查的是框架对一次新解析的准入；框架无法停止已经进入的任意 Dart 业务代码，
也不承诺撤销业务自行持有的原对象引用。

### P2：跨 error Zone 的 Deferred Resume 在失败时不结束

- 位置：`packages/ccrouter_core/lib/src/navigation_pending.dart:304`，尤其 `306`。
- 条件：在 error Zone A 发起并 defer；在不同 error Zone B 调用
  `resumePendingNavigation`；恢复后的策略取消或抛错。
- 实际：A 的原导航 Future 正确收到 `CCRouteCancelledError` 或
  `CCNavigationInterceptorError`；B 的恢复 Future 在 2 秒 watchdog 后仍无结果，
  同一错误另到达 A 的 uncaught handler。两个调用均在各自 Zone 中注册了错误处理。
- 对照：同 error Zone 的成功/取消/抛错全部通过；不同 error Zone 的成功通过。
- 根因：恢复流程完成原 `record.completer` 后直接返回其 Future；该 error Future
  属于原 Zone，Dart 不会把它的失败正常传播给另一个 error Zone 的等待者。
  上轮 readiness/singleFlight 的私有 outcome 机制尚未覆盖这条 continuation 路径。
- 建议：两个调用者分别在自己的 Zone 得到 value/error/stack，内部共享成功完成的
  outcome 数据，或由恢复流程直接返回/抛出其本地结果并独立完成原调用；不得让恢复
  流程再次 await/return 原 error Future。保留同一导航身份、failure recovery 和
  re-defer 的语义，确保 terminal observation 不重复。

6 项 Resume 探针：4 项正常对照通过，跨 error Zone 的取消/抛错 2 项有效失败。
2 秒只是挂起检测上限，不是性能 SLA。

## 方案取舍与修复顺序

| 方案 | 收益 | 代价/限制 |
| --- | --- | --- |
| 业务自行检查 token、约定恢复始终同 Zone | 可临时降低触发机会 | 每个调用点重复防护，不能保证框架统一准入或恢复 Future 终态 |
| 增加业务公开 Session 参数、禁止使用 error Zone | 将限制转嫁给业务 | API/迁移成本高，破坏已有生命周期抽象，不建议 |
| 私有解析生命周期 fence + 本地结果/共享 outcome | 保留外部 API，修复两条底层不变量 | 需覆盖各解析入口和 continuation 的交叉路径，推荐 |

建议先修 P1，再修 P2：

1. 把本轮失败探针作为修复前证据保留，统一同步解析的 owner/Invocation 准入。
2. 复测普通方法与 initializer、单个/批量/可空/Key、新旧 Session；确认新账号独立
   调用仍正常、旧工作零新资源构造、各资源只释放一次。
3. 解除 Resume 对原 error Future 的依赖；扩展到 re-defer、超时、Host detach、
   shutdown 和 Failure Policy，核对原调用/恢复调用终态、原 error/stack 与观察次数。
4. 修复后用正常 `*_test.dart` 入口纳入默认 suite，同步 README、集成 Skill 和
   lifecycle/implementation guidance；再跑完整框架/Demo 回归。

## 本轮验证

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| 既有框架和 Demo Flutter suite | 1043 通过 | [flutter.log](flutter.log) |
| 新增显式探针 | 18 项：12 通过、6 有效失败，归为上述 2 个缺陷 | [repro.log](repro.log) |
| Workspace analyze | No issues found | [analyze.log](analyze.log) |
| 应用 analytics 与工具 Dart suite | 55 通过 | [dart.log](dart.log) |

探针位于
`packages/ccrouter_test/test/review_repros/session_and_resume/repro.dart`。
非 `_test.dart` 命名用于审查阶段显式运行，避免把尚未授权修复的已知失败混入默认
套件；这不是默认回归已覆盖这些缺陷的声明。

```sh
fvm flutter test --no-pub \
  packages/ccrouter_test/test/review_repros/session_and_resume/repro.dart \
  --reporter expanded
fvm flutter test --no-pub packages/ccrouter_test/test demo/test \
  demo/modules/navigation_lab/test demo/modules/analytics_flutter/test \
  --reporter expanded
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test \
  tool/test --reporter expanded
fvm dart analyze
```

既有 Flutter suite 包含 Managed 多 Host/Outlet、精确 close、Shell、foreign Popup、
重复/取消 iOS swipe、shutdown 与 swipe 交错等回归。本轮没有发现这些现有测试的新失败，
但不能据此宣称任意功能组合、所有平台都已认证。

## 为什么正常全量通过仍有新问题

前轮验证覆盖“旧 Service readiness 完成不能进入方法”，未覆盖旧方法/initializer
自己恢复后发起同步查找；覆盖共享 readiness/Gate/singleFlight 的 error Zone，未覆盖
defer/resume 的第二等待者。缺口是同一生命周期不变量在不同入口未形成组合覆盖。
后续修复应按“所有权代际 × 同步/异步入口 × 成功/失败/取消 × 原调用/恢复调用”扩展，
而不能只修本次失败行或继续增加孤立按钮。

Demo 已有 Session 开关、defer/resume 和 Service 展示，本轮没有新增业务能力或
缺失的用户展示入口；新增竞态用可控 Completer、Zone 和明确断言更容易稳定复现。
没有新增 Demo 按钮、手工编辑生成物或启动竞争生成器。未修改独立 Analyzer Plugin。
未执行新的 macOS 真实窗口或 Android/iOS 真机手势验收；Widget 回归不等同于真机
验收。本轮没有内存泄漏或性能认证结论。
