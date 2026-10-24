# Managed 交叉场景补充审查

日期：2026-10-23。分支：`codex/managed-navigation-runtime`。

本报告基于 `20261023-renderer-back-fixes` 修复后的工作区。本轮仅审查、运行诊断和
记录结果，没有修改生产代码、正式测试、生成物，也没有提交或推送。

## 结论

确认四类框架缺陷：三个 P1，一个 P2。既有 Flutter 746 项、Dart 55 项全部通过，
Analyzer 无问题，但新增边界探针仍失败，不能据此认定迁移稳定性已全面达标。

| 级别 | 不变量 | 已复现行为 |
| --- | --- | --- |
| P1 | 一次实际 Pop 的结果和移除回执只能属于一次操作 | 两个并发 maybePop 串结果，并都声称移除了同一个 Entry |
| P1 | 过期的平台 location 请求不能在新请求之后提交 | A 等待策略、B 已显示，A 的晚到决策又将页面改回 A |
| P1 | 退出 Scope 必须覆盖实际外层渲染寿命 | Shell reverse 尚未结束，分支正文已消失，Route Service 已 dispose |
| P2 | 页内返回与离开 Managed Entry 的 Guard 判断分离 | Guard 拒绝离页时，LocalHistoryEntry 也无法通过返回关闭 |

## 1. P1：并发 maybePop 覆盖结果并重复确认移除

位置：`packages/ccrouter/lib/src/managed_router.dart:911–918`、`935–943`。

复现：Home → Push A；同一事件循环内分别调用
`maybePopOutcome(result: 'first')` 和 `maybePopOutcome(result: 'second')`，再等待两者。

实际证据：

```text
Flutter Route.popped = first
CCRouter push Future = second
两个 CCPopOutcome 都是 managed，且 removedBackendEntryId 相同
```

Flutter 只移除一次 A。本问题不是已证明的侧滑双退，而是协调层的结果串写和重复移除回执。
业务可能拿到错误的保存/选择结果；依赖 outcome 的调用方也无法区分真正执行移除的操作。

根因：在 `await Navigator.maybePop` 前写共享 `_pendingRemovalResults`，没有同一
Route 的操作占用。第二次调用覆盖第一份结果；await 后仅凭 Entry 不再存在就声称自己
移除了它，没有核对本次调用实际产生的移除事件。

建议：按 Host/Outlet/实际 Route 建立短期操作归属，结果由实际 Pop 关联；同一 Route
尚未完成的重复请求不得覆盖结果或重复发出移除回执。避免简单排队后对下一页继续 Pop。
不同 Outlet 的独立返回不应互相串行。

必要回归：并发同页、独立 Outlet、混合 native/business/system、LocalHistory 消费、
PopScope 拒绝、await 期间 push/close/unmount/shutdown，断言 result、receipt 和 Scope
均归属准确且至多一次。

## 2. P1：旧平台请求在新 location 之后提交

位置：`packages/ccrouter/lib/src/managed_router.dart:2358–2369`，初始入口同样需要审查。

复现使用实际 `PlatformRouteInformationProvider.didPushRouteInformation`，不是直接调用
Adapter 或模拟导航结果：

1. 发送外部链接 `/detail/A`，Interceptor 返回尚未完成的 Future。
2. 发送 `/detail/B`，确认 B 已提交并显示。
3. 完成 A 的策略 Future，返回 `CCNavigationProceed`。
4. 当前 Store 和页面重新变成 `/detail/A`。

两个目标均明确启用 Deep Link，Host 允许相对路径；失败不是拒绝策略或无效测试夹具造成的。

根因：Delegate 将每次 RouteInformation 独立交给 Runtime；Runtime 默认允许并发导航，
而平台 location 入口没有自身的取代/取消语义。Flutter Router 的 transaction 检查只能
丢弃过期调用的最终 rebuild，不能撤销 Delegate 内部已经执行的 Store mutation。

建议：平台 ingress 维护每个 Host 的请求代次，并在 Runtime 提交前验证请求仍有效。
新 location 取代旧 location 时取消其 pending policy/defer continuation；晚到结果不得
提交。不能只在 `await openRouteInformation` 后检查代次，届时栈已被修改。
保持普通业务 push 的并发语义独立，不把整个 Runtime 改成全局 latest-wins。

必要回归：初始请求与新链接、连续链接、浏览器前进后退、相同当前 URI 取代旧请求、
redirect/recovery/defer、Host 隔离、离线/策略失败、关闭和 remount。

## 3. P1：Shell 退场中间帧丢失分支正文并提前销毁 Scope

位置：`packages/ccrouter/lib/src/managed_router.dart:1724–1732`，关联
`_CCManagedShellSurfaceState.build` 和 `_buildOutletPages`。

复现：Home → Push 一个只有首个分支 Entry 的 Shell → 返回。
分别使用 root Navigator 原生 Pop，以及 `CCRouter.navigator.maybePopOutcome()`
在分支耗尽后冒泡退出 Shell，两种路径都失败。

40ms 中间帧证据：

```text
外层 Shell animation.status = reverse
外层 Shell animation.value  = 0.8666666666666667
分支正文（包含 offstage 查找）= 0
Route Service disposals = 1
```

期望：逻辑 Entry/结果先结束，但正文与其 Scope 保留到实际外层 Shell 退出渲染结束。
当前空容器仍处于退场期间，存在空白/闪屏窗口。这不是 macOS 截图或真机黑屏的本轮证明，
但中间帧正文丢失和提前 dispose 已确定复现。

根因：Shell Pop 从当前 Store 删除全部分支，响应式 Shell 立刻把子 Navigator 投影成
placeholder。子 Route 自己的 completed 已结束，不能表示外层 Shell 还在渲染的寿命。
此前单 Page 的 exit signal 修复没有覆盖嵌套渲染所有权。

建议：为正在退出的 Shell 保留其渲染投影，将后代 Scope 的退出释放绑定到外层容器的
真实完成/销毁边界。active Store 不得保留已结束的逻辑 Entry。不能用任意毫秒延时延长 Scope。

必要回归：业务/原生退出、单/多分支、未激活分支、foreign popup、连续导航中断、
每个中间帧的 Route Service 访问、卸载和无后续帧 shutdown、一次释放及 GC。
普通 Go 的立即移除路径单列为对照，不将无存活退场 Route 的正文消失误报为同一缺陷。

## 4. P2：LocalHistory 被 Managed 离页 Guard 拦截

位置：`packages/ccrouter_core/lib/src/navigation.dart:76–78`；Managed target 解析及原生
PopEntry bridge 也需同步处理。

复现：left Outlet 顶部页配置 deny Guard，在该 Route 上添加一个 LocalHistoryEntry，
通过其 Context 调用 `CCRouter.navigator.maybePopOutcome`。

实际：返回 `guardDeniedCode=left_locked`，LocalHistory 的 onRemove 没执行；继续调用
该 Navigator 的原生 maybePop 同样被框架安装的 Guard gate 拦住。
Managed Entry、结果和 Scope 保持原状，但页内 UI 也无法通过 Back 退出。

根因：目标被识别为底层 Managed Entry，Runtime 在后端有机会消费 LocalHistory 前
执行离页 Guard；原生 PopEntry 的重试也按离页判断。框架未表达“只消费页内历史”的边界。

建议：后端先准确识别内部消费能力，仅在将要移除 Managed Entry 时运行该 Entry 的
Guard。保持本地 PopScope/Form 规则；LocalHistory 的消费 outcome 为 none，不能假报
managed removal。不要把内部历史伪装成 foreign Route 或制造假的业务 Entry。

必要回归：Guard deny/allow × 有/无 LocalHistory × managed/native/system，先消费内部
历史、再尝试离页；分别断言 UI、结果 pending、Guard、Scope 与 outcome。

## 候选方案与取舍

| 方案 | 收益 | 问题与成本 |
| --- | --- | --- |
| Demo 防抖、强制 focus、应用延时/禁用过渡 | 局部实现快 | 无法约束系统入口和其它消费者，会掩盖框架错误，不推荐 |
| 在现有 Managed/Runtime 边界补齐操作与渲染不变量 | 兼容现有业务 API，可逐问题对照回归 | 需增加精确内部协调和嵌套退出测试，推荐 |
| 再次整体重写 Backend 或引入业务公开 API | 可重排所有结构 | 成本高、影响面大，没有证据证明必要，不推荐 |

推荐顺序：

1. 将失败探针迁为正式回归，固定一次实际操作对应一次结果/回执的断言。
2. 修复并发 Pop 的操作归属，再修平台 ingress 的过期提交。
3. 修复 Shell 外层渲染寿命，补中间帧与终态释放测试。
4. 补 LocalHistory 消费判定，同时核对 native/managed 的一致性。
5. 重跑完整矩阵，再完成 macOS 实际窗口与 Android/iOS 手势验收。

## 为什么全绿后仍不断发现问题

已有回归覆盖很多单功能及顺序操作，但以下组合没有形成稳定断言：

- 并发请求 × 一份真实 Route.popped × 唯一移除 receipt；
- 平台请求先后顺序 × 异步策略完成顺序；
- 后代 Route.completed × 外层容器仍在渲染；
- 页内历史消费 × Managed 离页 Guard。

问题不是继续增加测试数量就能解决。需要先定义操作归属、失效边界、渲染 Owner 和
终态不变量，再用同一组断言跨来源、Host/Outlet、生命周期和并发交叉验证。
本轮没有证明旧 GoRouter 在这四项上的全部行为，故不作历史架构优劣的绝对比较。

## 本轮实际执行

| 检查 | 结果 |
| --- | --- |
| Framework + Demo + navigation_lab + analytics_flutter | 746 passed，exit 0 |
| analytics + analytics_firebase + tool | 55 passed，exit 0 |
| Workspace `fvm dart analyze` | No issues found，exit 0 |
| 新增诊断探针 | 7 项：5 failed / 2 passed；两个 Shell 失败属于同一缺陷 |
| `git diff --check` | passed |

探针中的 Shell Go teardown 对照，以及 nested Context 返回时被 PopScope 阻止的 root
foreign popup 对照均通过；后者正确报告 owner=none，未列为缺陷。

命令与本机证据：

```sh
fvm flutter test --no-pub packages/ccrouter_test/test demo/test demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test tool/test --reporter expanded
fvm dart analyze
fvm flutter test --no-pub /tmp/ccrouter_review_round3_probe_test.dart --reporter expanded --timeout 30s
```

- 探针源码：`/tmp/ccrouter_review_round3_probe_test.dart`（复用已有 fixture，不改正式测试）。
- 失败日志：`/tmp/ccrouter-review-round3-final-probe.log`。
- 既有 Flutter：`/tmp/ccrouter-review-round3-existing-suite.log`。
- Dart：`/tmp/ccrouter-review-round3-dart.log`。
- Analyzer：`/tmp/ccrouter-review-round3-analyze.log`。

本轮没有发现新的高置信度 not-disposed/not-GCed 泄漏；Shell 问题是提前释放，不能归类
为泄漏。未执行新的长期 RSS/性能测量、macOS 全按钮验收或 Android/iOS 真机手势复验。
未改声明或组件图，未重复运行 Generator/Analyzer Plugin 的独立测试与 Demo 生成检查。
