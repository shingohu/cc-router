# 外部导航等待与所有权边界修复、扩大回归

日期：2026-10-24。工作树：
`/Users/shingo/.codex/worktrees/managed-navigation-runtime/cc-router`，
分支 `codex/managed-navigation-runtime`，HEAD
`09cb21d78381bbdeab431cf6bca279f909827db1` 及此前未提交成果。
本轮未提交、推送、删除或回退已有成果，未修改主工作树。

## 结论

原 [Pop 等待审查](../20261024-pop-wait-review/report.md) 的两项问题已修复。
随后扩大到 live-owner GC、共享 readiness、工厂执行上下文、独立 error Zone、
同步 Guard/Adapter 重入和真实 Demo Widget/Monkey 场景，修复了同类所有权缺口、
Guard 期间同名 Host 重建的 Back 转移，以及测试夹具的时钟/滚动同步问题。

最终 Flutter 默认回归 **1537 项通过**，其中本轮新增默认边界回归 **96 项**。
最后一轮对已修改路径的代码审查没有发现新的高置信、可复现问题。
这不是“任何外部 Adapter 或所有平台上绝对无问题”的证明。

## 根因和实际修复

### 1. 挂起 Pop / close 的生命周期不受 Core 所有者约束

原来直接 await 自定义 Adapter 的 Future。Runtime/Host 已退役，甚至 close 的原 Entry
已被替换，外部任务仍可保留等待帧、调用者 Zone 和旧 Entry 参数，属于 not-GCed。

新增私有 `navigation_backend_wait.dart`，以可断开的完成 relay 管理等待。
App/Host 结束立即结束框架等待；精确 close 另外观察原 Entry 的逻辑移除信号。
终态清除 consumer Completer、token listener 和 Timer。外部 Future 只保留不含
Runtime/Entry 的小 relay，迟到成功/失败均被消费。

Pop 退役结果为 `handled: true` 且没有 removal，避免系统 Back 落入新 Host；
close 退役结果为 `notFound`。Entry 移除有一个零时长事件循环宽限，允许同一关闭事务
微任务中的真实 receipt 优先完成；不会等待 outgoing UI frame。
停止 Adapter 自己的外部任务仍是 Adapter 的责任。

### 2. 初始栈缺少 registration，以及 Guard 前的身份捕获过晚

Pop 不再依赖先前 Runtime 导航建立 token。只有 initial snapshot、foreign 或空栈时
也会在准入时建立具体 Host registration，旧回执不能污染同名新 Host 的失同步诊断。

扩大审查还证明：若同步 Guard 间接注销并重建同名 Host，Guard 之后才捕获身份会把
旧 Back 发给 replacement。新增同步 business Pop / 异步 Back 两个失败用例后，
将身份捕获提前至 Guard 执行前。Guard 返回 allow 也只授权原 registration；
它已退役时消费原 Back，新 Back 仍可正常进入 replacement。
Guard 仍是同步只读决策，不将该防护描述为推荐在 Guard 中操作 Host。

### 3. 长期拥有者采用了首次调用者 Zone

保持 Runtime 和 Route/Session/shared Service 活跃的 GC 对照进一步确认：
Scope/token 创建、缓存 readiness（成功、失败、首 waiter 取消）和工厂注册的 pending
回调可间接保留首次 caller Zone。仅测 shutdown 后 GC 无法发现这些长期保留。

这些所有者状态、Scope-owned factory 和 singleton initializer 改在 Runtime 创建时的
Host Zone 执行；显式传递框架 Trace、依赖链、实际 Scope 与导航回调重入限制。
不采用任意业务 Zone 值配置共享 Service。`newInstance` 初始化继续保留原调用者的取消链。
错误通过数据 relay 回到各 caller error Zone，保留原框架错误和堆栈。

### 4. Demo 测试夹具混用真实和虚拟时钟

在真实 `setUp` Zone 创建 Runtime，再只推进 Widget fake clock，不能驱动现在明确属于
Host 上下文的工作。实际暴露为 readiness 状态尚未完成、系统返回页面断言失败、
Monkey 和 Shell close 等待超时。

将相关 Demo Runtime 创建移入 `testWidgets` 回调或其挂载 helper；启动 InitTasks
以有界 fake-clock pumping 等待，保留所有业务断言、时限和 Monkey 步数。
依赖真实 deadline 的测试继续显式使用 `runAsync`。
诊断页滚动后等待布局稳定并重新确保标题可见，避免 lazy 子项尚未进入有效布局时断言摘要。
未用 sleep、放宽结果或增大超时来掩盖失败。

## 方案取舍与实施闭环

| 方案 | 评价 |
| --- | --- |
| 只要求应用/Adapter 自行完成所有 Future | 无法统一覆盖原 Entry 单独结束；等待帧仍可能保留 caller Zone |
| 在各 await 处添加 Future.any | 可提前返回，但未保证解除长期 producer 对 consumer Zone 的保留 |
| 新增公开取消/回退 API 或扩展结果枚举 | 扩大业务接口，不是修复既有承诺所必需 |
| Core 私有 relay + 具体 registration + Host-owned 执行上下文 | 本轮采用；集中所有权、保留业务接口，代价是明确上下文语义并补跨 Zone/重入验证 |

执行顺序为：保存修复前探针 → 私有所有权修复 → 扩展 live-owner/error Zone/Guard
用例 → 修复新证实缺口 → 原 Demo 功能与 Monkey 回归 → 最终全量/分析/生成/文档校验。
新增实现保持在 Core library 私有 part，没有新增业务 Facade API，也没有让组件调用 Host SPI。
内部 relay 可单独审查回退；回退后会重新出现本报告记录的故障，不能当作无代价 fallback。

本轮没有新的业务能力或缺失入口需要增加 Demo 按钮。现有 Demo 已提供 Service readiness、
系统返回、Shell、多 Host 和 close 等场景；外部 Adapter、跨 error Zone 与 GC 采用框架
回归夹具表达，避免将内部 SPI 故障包装为推荐业务接入方式。

## 验证证据

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| 框架 + Demo + navigation_lab + analytics Flutter + payment + kv_storage + order example | 1537 项通过 | [flutter.log](flutter.log) |
| analytics / analytics_firebase / tool Dart suites | 55 项通过 | [dart.log](dart.log) |
| 根静态分析 | 无问题 | [analyze.log](analyze.log) |
| Demo 完整 Builder `--no-cache --check` | 6 组件、34 路由、11 Packages 一致 | [generation.log](generation.log) |
| Generator Contract/API 隔离专项 | 4 项通过 | [generator-boundary.log](generator-boundary.log) |
| 文档校验 | 通过 | [documentation.log](documentation.log) |
| Dart 格式 / git diff --check | 17 个相关文件格式无变化；diff 无错误 | 最终命令结果 |

默认 Flutter 命令：

```sh
fvm flutter test packages/ccrouter_test/test demo/test demo/modules/navigation_lab/test demo/modules/analytics_flutter/test demo/modules/payment/test demo/modules/kv_storage/test demo/modules/order/example/test --reporter expanded
```

新增回归入口：

- `packages/ccrouter_test/test/backend_wait_lifecycle_regression_test.dart`：44 项。
- `packages/ccrouter_test/test/backend_wait_boundaries_test.dart`：52 项。

Monkey 为三个固定种子、每种子 120 步，保留导航 identity/Scope/Flutter 错误检查。
完整套件包含重复 iOS 侧滑只移除一项、取消侧滑保持 identity、手势期间 shutdown、
predictive bridge、LocalHistory、foreign popup、多 Host/Outlet、Shell、父栈、
defer/revalidation、Session 更替、readiness 依赖环及 GC 对照。
这些 Widget/桥接测试不等于操作系统真实手势验收。

修复前与定位证据：

- 原两项缺口：[原审查日志](../20261024-pop-wait-review/boundaries.log)。
- 首 caller Route/Session、readiness、factory 保留：本目录 `owner-*-before.log`。
- Guard 内同名重建：`guard-host-before.log` 两项失败，`guard-host-fixed.log` 两项通过。
- 初次全量与 Demo 夹具定位：`cycle-before-fixture.log`、`demo-fixture-before.log`。

## 限制与状态

本轮未重新进行 macOS 真实窗口、Android/iOS 真机手势、原生 heap 或长时间性能基准。
没有用单次测试耗时宣称性能提升，也没有将 GC 探针当作全应用 RSS 上界。
未修改 Generator 或 Analyzer Plugin 生产逻辑；Generator 只执行相关边界专项与实际 Demo
Builder 校验，未重跑其全量 suite；未执行 isolated Analyzer Plugin suite。
README（中英）、integration Skill/实现模式/审查表和相关 DartDoc 已同步。
