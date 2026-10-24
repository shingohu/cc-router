# 请求来源与异步 Host 归属审查

日期：2026-10-23。工作树：`codex/managed-navigation-runtime`。
基线 HEAD：`09cb21d`（make managed navigation the default demo backend）。

本轮为 review，未修改框架、Demo 或正式测试，未提交、推送。新增的是本目录中的
审查报告、诊断探针快照和验证日志。保留之前的修复及审查记录。

## 结论

发现 **3 类已复现缺陷**，涉及 **4 条失败路径**；5 条对照路径通过。
现有 775 项 Flutter、55 项 Dart 测试及 Workspace analyzer 全部通过，说明现有回归
没有覆盖这些组合，不能据此宣称所有场景已稳定。

这三处根因在 HEAD 中已有同样的实现；并发 key 文件没有未提交差异，redirect、recovery
及 MultiHost 回执处也能在 HEAD 找到同样的关键逻辑。因此不能将本轮发现直接归因于
当前未提交的重构修改。没有对 GoRouter 历史版本重跑探针，也没有证明它们早于整个
Managed 迁移，不能声称“旧后端必然也有”或“重构前更差”。

## Findings

### P1：singleFlight 跨 origin 合并，跳过后一请求的来源策略

位置：`packages/ccrouter_core/lib/src/navigation_concurrency.dart:44–51`，
`packages/ccrouter_core/lib/src/navigation.dart:482–493`。

启用 `CCNavigationConcurrencyPolicy.singleFlight`，内部 `open('/detail/A')` 在
Interceptor 等待时，通知入口对相同 URI 发起相同 Open 操作。配置的 Interceptor 对
外部来源应返回 `CCNavigationCancel('external_requires_consent')`。

实际外部 Interceptor 执行 **0 次**，通知调用成功共享内部请求结果；其自身来源策略被
跳过。目标已允许 Deep Link，Host ingress 校验也已通过，本例没有证明绕过 route
deepLink admission 或 Host allowlist，问题限于每次请求的 Interceptor 判断。

根因是并发 key 只包含 Host、Outlet、operation、openMode、routeId 和 URI，不含
`CCNavigationOrigin`；合并发生在后一请求运行 Interceptor 之前。默认 `allow` 模式
没有该问题。对照证实 `allow` 下外部策略执行一次并拒绝；同 origin 的 singleFlight
仍只检查和提交一次。

建议至少按精确 origin 隔离请求，覆盖 internal/platform/notification/QR 各来源。
`CCNavigationSource` 的既有契约是 telemetry attribution，不应把它当作信任来源；
是否纳入去重应另按公开等价语义评估，不能以 source 取代 origin。若要求每次调用都独立
运行动态授权策略，则需明确“策略通过后才合并提交”的更大语义变更。

### P1：异步 redirect / Failure Policy recovery 会修改后来聚焦的 Host

位置：`packages/ccrouter_core/lib/src/navigation.dart:610–617,713–723,868–875`；
`packages/ccrouter_core/lib/src/navigation_failure.dart:225–235`。

active Host 为 primary，无 context 的业务 `go(A)` 已构造 primary 的请求；其
Interceptor 等待时激活 secondary，再返回到默认 placement 的 B 的 redirect。
实际 primary 保持首页，**secondary 被 Go 为 B**。单独用 Failure Policy 等待后恢复到
B，也得到同样结果。由此可能替换另一导航区域的当前内容，违反一次操作的归属稳定性。

根因是 redirect/recovery 重新 prepare 并构造 request 时沿用空的 placementOverride，
将 default Host 再次解析为当时 active Host。普通异步 Proceed 复用既有 request，
不会改投；传入 primary context 的 redirect，以及 defer/resume 的 redirect 均保持
primary，三个对照通过。已有 pending/revalidation 的 Host 固定没有覆盖普通业务的
redirect/recovery。

建议在操作开始处捕获 concrete Host，跨解析、redirect、recovery 和恢复路径保留它。
只固定默认 Host 的归属，仍尊重目标显式声明的 Host、Shell、Outlet 和 parent 结构。
对尚未成功解析目标便失败的调用，也应明确 recovery 使用哪个 Host。不要用“所有
redirect 强制 root placement”修复，否则会破坏现有导航拓扑。

### P2：等待中的 maybePop 回执写成后来 active 的 Host

位置：`packages/ccrouter/lib/src/multi_host.dart:440–457`。

primary Push A，通过真实 Flutter Route 的异步 willPop 暂停
`CCRouter.navigator.maybePopOutcome(result: 'primary-result')`，等待期间激活 secondary，
再允许 Pop。实际 primary 的 A 正确移除、原 push 得到 `primary-result`，secondary
仍在首页，**但 outcome.hostId 为 secondary**。

本例在失败断言前已校验实际栈和结果，故不将它夸大为误删 secondary 或双退。
它仍会向依赖公开回执进行归属判断的调用方报告错误导航区域。

根因是开始时捕获 child adapter，`.then` 完成时却再次读取 `_activeHostId`，覆盖
child outcome；fallback Outlet 也读取终态的 activePopTarget。建议捕获实际 dispatch
Host 和必要 fallback，保留 child 提供的真实 Outlet，避免完成阶段重新选择目标。
同步 Pop 及 scoped forwarding 有相邻的回执重写逻辑，应在修复时一起增加真实 Route
验证；本轮没有未经复现将这些邻近路径另列为缺陷。

## 诊断与对照

探针使用真实 Runtime、`CCManagedMultiHostBackend`、Flutter Router/Navigator，复用
正式回归 fixture 的公开辅助类型。没有 mock 导航结果。异步边界使用 Completer，
Back 使用真实 Route willPop gate；deprecated API 仅用于诊断，探针中局部 ignore。

| 场景 | 当前结果 |
| --- | --- |
| singleFlight：internal 与 notification 相同 URI | 失败：外部策略 0 次、调用成功 |
| 无 context：等待 redirect 时切 Host | 失败：B 进入 secondary |
| 无 context：等待 Failure Policy 时切 Host | 失败：B 进入 secondary |
| 无 context：等待 maybePop 时切 Host | 失败：回执 Host 错；实际栈及 result 正确 |
| allow：internal 与 notification 相同 URI | 通过：外部策略独立拒绝 |
| 同 origin singleFlight | 通过：只检查和提交一次 |
| 无 context：等待 Proceed 时切 Host | 通过：仍进入 primary |
| 有 primary context：等待 redirect 时切 Host | 通过：仍进入 primary |
| defer/resume 后 redirect、期间切 Host | 通过：仍进入 primary |

最终探针结果：**5 passed / 4 failed**，见 `probe.log`。4 项失败均来自行为断言，
不是 fixture 编译或装配错误。原始三项失败在补充探针前后也重复出现。
`probe.dart.txt` 是实际诊断源码快照，未放入正式测试目录，以免将预期失败加入日常
全量 gate；修复时应先转为正式回归。复现可在本工作树执行：

```sh
cp docs/validation/20261023-partition-origin-review/probe.dart.txt /tmp/ccrouter_review_partition_origin_probe_test.dart
fvm flutter test --no-pub /tmp/ccrouter_review_partition_origin_probe_test.dart --reporter expanded --timeout 30s
```

快照中的两个 fixture import 为本工作树绝对路径；移动 checkout 后需先调整。

## 验证范围及边界

| 检查 | 结果 / 证据 |
| --- | --- |
| `fvm flutter test --no-pub packages/ccrouter_test/test demo/test demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded` | 775 passed，`flutter-tests.log` |
| `fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test tool/test --reporter expanded` | 55 passed，`dart-tests.log` |
| `fvm dart analyze`（根 Workspace） | No issues found，`analysis.log` |
| 新增诊断探针 | 5 passed / 4 failed，`probe.log` |

静态审查重点包括 Core 的请求准入/并发/redirect/recovery/defer、MultiHost 的分发与
回执、Managed 返回和 exact close、Shell 退出投影、Page/Route 生命周期、renderer
detach/dispose、平台 location 的 supersede。上述现有自动化包含前轮 ownership、
LocalHistory、Guard、手势重入、Shell 和适配布局的回归，不能视作每种参数排列都测过。

本轮没有确认新的内存泄漏；这不构成长时 heap、帧率或内存压力认证。没有重新运行
macOS 全按钮遍历、monkey 或 Android/iOS 真机手势。上轮真实窗口结果仍是历史证据，
不能替代本轮新增异步交叉测试。本轮未修改 Generator 或隔离 Analyzer Plugin，也未
声称执行其全部专项测试或更新 Demo pin。

## 方案取舍与后续顺序

| 候选方案 | 收益 | 代价 / 判断 |
| --- | --- | --- |
| 应用强制传 context、不使用 singleFlight、等待时禁止切焦点 | 应用侧可局部规避 | 缩减既有能力，context-free 调用和正确来源策略仍无框架保证，不作最终方案 |
| 全局串行化全部导航 | 部分交叉顺序被阻断 | 牺牲独立 Host/Outlet 并发，Push 生命周期和焦点语义也会变化，不推荐 |
| 现有 Runtime 内完善请求等价性和稳定操作归属 | 不增加业务 API，保留独立导航和真实 Flutter Route | 需跨路径统一不变量并验证显式 placement，推荐 |

推荐实施顺序：

1. 将四条失败路径和五条正向对照转为正式回归，先保留失败基线。
2. 修复 origin 去重隔离，验证所有外部来源以及同来源的共享/错误传播。
3. 统一一次导航的 concrete Host 归属，覆盖 typed/URI、redirect/recovery/defer、
   默认/显式 Host 和 Shell/Outlet，不改变已有业务调用签名。
4. 修复 MultiHost 返回回执，验证焦点切换、Host 注销、shutdown、foreign Popup、
   LocalHistory 与结果仅完成一次。
5. 扩展不变量矩阵后重跑全量；同步真实支持行为的 README、Integration Skill 和相关
   reference；最后复验 macOS 多 Host 快速交替操作及移动返回手势。

反复 review 出问题的直接原因是测试以单个功能为主，而“两个请求是否等价”和“一次
异步操作属于谁”没有在所有路径统一验证。已有 pending/revalidation 修正了归属，
普通 redirect/recovery 却重新解析；child 正确完成 Pop，聚合层又改写回执。今后应将
origin × 并发策略，以及 context/default/explicit placement × Proceed/redirect/
recovery/defer × focus/unregister/shutdown 的关键交叉固化为契约回归，而非仅增加顺序
点击次数。有限审查仍不能证明不存在任何其它问题。
