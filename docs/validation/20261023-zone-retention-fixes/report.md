# Zone 保留路径与清理屏障修复

2026-10-23；工作树 `managed-navigation-runtime/cc-router`；分支
`codex/managed-navigation-runtime`，HEAD 基线 `09cb21d`。保留已有修改，未提交或推送。

## 问题、取舍与实现

本轮修复 [上一轮审查](../20261023-construction-retention-review/report.md)
确认的三项 P2。问题分别是构造 Zone 强持有 RouteEntry、调用 Zone 强持有 Runtime，
以及重复 TestHost 清理提前成功并隐藏原始失败。

仅要求应用取消所有后台工作不能解除框架的强引用；方法结束就清空 ownership 则会
破坏旧 Session/Route 调用的取消校验。采用最小内部修复：

1. TestHost 在触发 Runtime 清理前发布共享完成屏障，把错误及堆栈作为结果数据保存，
   再在每个调用者的 error Zone 恢复错误。并发、同步重入、完成后调用都等待同一次
   清理；资源仅销毁一次。禁止资源等待自身 Host 的 teardown。
2. invocation、construction、navigation operation 与 navigation callback 的
   Runtime 匹配统一使用不反向引用 Runtime 的私有身份 token。
3. construction owner 弱引用原始 Scope 和 Route-owned Entry。活跃及退出渲染中的
   Entry 仍由 Runtime 强持有；回收后的 owner 明确拒绝解析，不切换到新 Session
   或可见页面。App/Session 构造不继承首个 Route 调用者的 Entry。
4. 保留 immutable cancellation lineage、依赖生命周期验证、共享 singleton
   初始化独立性及精确的 new-instance 资源归属。Core Runtime.dispose 的同一 Future
   契约保持不变，没有新增公开 API 或变更导航方法签名。

扩大回归发现两条相邻路径，并在本轮一并修复：Route token 的 Future 通过创建时的
navigation-operation Zone 保留 Runtime；导航决策和观察者 callback Zone 直接持有
Runtime。先保留失败证据，再改身份引用；后者两项失败见
[navigation-callback-before.log](navigation-callback-before.log)。

## 回归范围与结果

新增 35 项默认回归：原始探针 9 项、TestHost 跨 Zone/时序/失败及同步重入 10 项，
App/Session/Route 构造和 Runtime GC、活跃 owner 对照、Route 首次触达 App 共享构造、
导航决策及观察者 Zone GC 共 16 项。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 新增回归与 invocation、admission、construction、Session、shared execution、cleanup 专项 | 280 通过 | [focused.log](focused.log) |
| 框架与 Demo 全量 Flutter 回归 | 1327 通过 | [flutter.log](flutter.log) |
| analytics / Firebase / tool Dart suite | 55 通过 | [dart.log](dart.log) |
| Workspace analyze | No issues found | [analyze.log](analyze.log) |
| Demo generation freshness | 复用有效 watch cycle 104；up to date | [generation.log](generation.log) |
| 文档检查 | 检查器选择的 121 份 Markdown 通过 | [documentation.log](documentation.log) |
| 差异检查 | `git diff --check` 通过 | 当前工作树 |

新增测试的最初执行包含两次 fixture 编译错误：遗漏 Core Provider import，以及误用
listener 方法名；均已修正。它们不属于产品失败或有效的失败回归，表中只统计有效运行。
首次 analyze 还发现新增测试的多余 import，已移除后重新执行分析；该改动不影响生产逻辑。

## 覆盖改进与边界

以往主要验证 dispose 次数、Service GC 和调用准入，遗漏了 Route payload、Runtime
本体和多个 teardown awaiter。这次把“Owner × 终态 × 遗留 Zone × 被保留对象 ×
多个等待者”写入框架内存审查 reference、集成 Skill 和 checklist；README 中英版与
接入模式同步清理错误语义。不能仅靠不断增加相似按钮或成功测试证明生命周期完整。

不增加 Demo UI：本轮缺陷属于内部保留路径和测试清理屏障，确定性 GC/异步回归比
重复业务按钮更能验证它们。应用直接捕获的对象、Timer、订阅仍由应用管理。

没有新增 macOS 实窗、Android/iOS 真机、长期 monkey 或进程 heap/性能测量。
GC 用例只证明所覆盖引用路径，不代表所有可能的后台工作都不泄漏。
多 Runtime A → B → A 的候选契约仍未定，不混入本轮修复或默认测试。
未改独立 Analyzer Plugin / Generator 生产代码，未运行其专属完整测试。
