# 挂起工作所有权修复与 main 同场景对比

2026-10-23；工作树 `managed-navigation-runtime/cc-router`；分支
`codex/managed-navigation-runtime`，HEAD 基线
`09cb21d78381bbdeab431cf6bca279f909827db1`，叠加已有未提交成果。

本轮修复 [上一轮确认的三个 P2](../20261023-pending-work-review/report.md)，
并针对用户的疑问对照本地 `main`。未提交、推送或修改用户的主工作树。

## 结论与根因

三项均已修复，原 27 个探针全部通过，并与新增边界一起作为 63 项默认回归发现。
本地 `main` 也复现了这三个问题：它们位于共享 Core／Host，不是 Managed 独有，
保留 GoRouter 不能解决它们。此结论不等于此前所有发现都来自 main，或整个新架构已被
证明没有回归。

两项内存问题都属于 **not-GCed**：清理已执行，但未返回的业务 Future 仍经框架
continuation 保留已结束的拥有者。第三项是 MultiHost 构造期缺少实例唯一所有权校验，
与动态注册校验不一致。单独断言 dispose 次数或外层调用取消不足以验证这些边界。

## 候选方案与实施

| 方案 | 收益／限制 | 本轮选择 |
| --- | --- | --- |
| 要求业务 Future 总能取消，或增加 timeout | 无法强制停止 Dart Future；外层 timeout 不解除内部闭包保留 | 不作为框架修复 |
| 清空所有调用链 token | 会破坏旧 Session／Route 回调的调用准入 fence | 不采用 |
| 结算实际 owner 的 readiness，隔离业务 await 捕获环境 | 不新增公开 API；需要同时验证共享、取消、迟到错误和跨 Zone 语义 | 已完成 |
| 最终 dispose 时对重复 Adapter 去重 | 仍有重复初始化、绑定和 detach 冲突 | 不采用 |
| 接管前完整验证所有初始 Host／Adapter identity | 无效输入不触及调用方资源；与动态入口一致 | 已完成 |

1. `_ServiceReadinessRecord` 在实际 initializer owner 取消时立即结算，清理依赖边与
   cancellation listener；终态只写入一次。遗留 Future 的成功／失败被消费，不能覆盖终态。
2. Service initializer 的用户 await 移到私有 `service_initialization.dart`。执行环境
   不捕获 `_resolveReady` 的 Runtime、Scope、RouteEntry 局部变量。保留原非拥有 Zone
   identity、弱 construction owner、调用链 token 和精确 Route 归属。
3. `_resolveReady` 在失败交接处重查调用者取消，防止不同 error Zone 的等待者在同一次
   owner 关闭时收到不同取消语义。已进入的调用统一收到 `CCInvocationCancelledError`；
   正常初始化失败仍保留原错误 identity／stack，singleton 不受单个 waiter 取消影响。
4. Event Subscriber await 移到私有 `event_execution.dart`，与拥有 Runtime 的 fan-out
   闭包环境分开。继续使用原 `_invoke` 的 Trace、deadline、错误隔离与 cancellation lineage。
5. MultiHost 构造器先完成全部 HostBinding／identity 校验，再创建任何 ownership record。
   同实例被拒绝，不初始化或 dispose 输入；两个重载 `==` 的不同实例仍合法。
6. 同步 README 中英、集成 Skill／实现参考／review checklist 和框架内存审查参考。

实现均为私有修复，不增加业务导航 API、运行时开关或框架依赖。需要回退时可以单独回退
这些内部修改及对应契约文档；不修改路由后端选择。

## 与本地 main 的实测对比

基线为本地 `main`：`12a6b0fb9746195dfeeb2e8583bfeb9565700836`，未 fetch 远端，
不声称这是远端最新 main。使用 `git archive main` 导出至
`/tmp/ccrouter-main-comparison.wAgoMs`，单独解析依赖，未借用当前工作树的 package config。
Flutter／Dart 版本见 [当前 SDK](flutter-version.json) 与 [main SDK](main-flutter-version.json)。

相同的三个探针文件共 27 项，使用相同 WeakReference／forceGC 断言：

| 场景 | 本地 main | 本轮修复后 |
| --- | --- | --- |
| 挂起 initializer：App／Session／Route × singleton／newInstance，6 项 | 6 失败：Runtime 保留；Route payload 也保留 | 6 通过 |
| initializer 先完成再关闭的对照，6 项 | 6 通过 | 6 通过 |
| 挂起 Event：legacy／typed／generated，3 项 | 3 失败：Runtime 保留 | 3 通过 |
| Event 先完成的对照，3 项 | 3 通过 | 3 通过 |
| Command／普通 Service method／InitTask，挂起及完成，6 项 | 4 通过；挂起 Command 和 InitTask 失败 | 6 通过 |
| 构造重复 Adapter identity，1 项 | 失败：接受配置且 dispose 两次 | 通过：拒绝且 dispose 零次 |
| 正常独立子 Adapter，1 项 | 通过 | 通过 |
| 动态注册已有 Adapter identity，1 项 | 失败：接受复用 | 通过：拒绝且不提前 dispose |
| 合计 | **14 通过／13 失败** | **27 通过** |

main 多出的 3 项失败反映此前工作树已修复的共享生命周期边界，不是本轮新增三种缺陷。
证据：[main 最终有效探针](main-probes-compatible.log)、[当前原探针](probes.log)。

首次 main 探针导入的共用 fixture 包含一个未执行的方法，使用了 main 尚不存在的
snapshot `handle` getter，导致 readiness 文件编译失败；见 [初次日志](main-probes.log)。
仅将快照副本中该未执行方法改为 main 已有的
`runtime.routeEntryHandleForNavigation(entry.navigationId)` 后重跑。未改 main 生产源码，
未改实际探针输入或 GC 断言；最终统计只采用兼容后的有效 27 项。
依赖解析见 [main-pub.log](main-pub.log)。

## 默认回归矩阵与实际结果

新增 `pending_work_ownership_regression_test.dart` 包含：

- 原 27 个 review 探针，正式纳入默认 suite。
- 4 项 Session／Route × creation policy 的 GC：Runtime 继续存活，旧 Scope／payload
  可回收，迟到失败被消费、Service 清理一次，新 Session 不受影响。
- 12 项 readiness：三种 Scope × 两种 policy × 迟到成功／失败，在独立 error Zone
  中取消等待，singleton 同时包含两个独立 Zone waiter；核对清理、错误与终态观察次数。
- 18 项 Event：三入口 × 显式取消／总 deadline／shutdown × 迟到成功／失败；
  核对取消结果、Subscriber 隔离、Trace 次数和无未捕获迟到错误。
- 2 项 MultiHost：重载 equality 的不同实例、后置无效 Host 输入与可重新接管的正常对照。

跨 Zone 迟到错误夹具最初把原始 error Future 创建于测试 Zone，Dart 会阻止其错误跨越
guarded error Zone。已更正为在业务生产者 Zone 创建 Future，未降低断言。
专项初跑同时发现了第二个 singleton waiter 的 `CCScopeClosedError` 竞态，已在
`_resolveReady` 交接处修正；见 [初跑](focused.log) 与 [修复后](focused-fixed.log)。

| 检查 | 实际结果 | 证据 |
| --- | --- | --- |
| 新 63 项及共享执行／Service 准入／invocation／construction 专项 | 219 通过 | [focused-fixed.log](focused-fixed.log) |
| 框架、Demo、导航、analytics Flutter、支付、存储、Order example | **1390 通过**，包含新 63 项 | [flutter.log](flutter.log) |
| analytics／Firebase／tool Dart suite | **55 通过** | [dart.log](dart.log) |
| Workspace analyze | No issues found | [analyze-final.log](analyze-final.log) |
| Demo generation freshness | 复用有效 watch cycle 112；up to date | [generation.log](generation.log) |
| 文档检查 | 检查器选择的 121 份 Markdown 通过 | [documentation.log](documentation.log) |
| 差异检查 | `git diff --check` 通过 | 工作树 |

没有停止已有 Demo watch，也没有启动竞争生成器或手工修改生成物。
无新增 Demo 页面：永不完成的 Future／无效重复 Adapter 是框架回归夹具，不是推荐的
应用交互模式；正常 Service／Event／Host 场景仍由现有 Demo 和全量测试覆盖。

## 为什么多轮 review 仍发现问题

此前验收主要围绕可见功能结果、取消结果与清理次数；逐轮修复虽然增加了测试，
却没有完整交叉“调用已返回但遗留回调仍存在”和“外层已取消但业务 Future 仍未返回”
两种状态。构造与动态注册入口的所有权校验也没有一并比较。此前据常规全量通过判断
稳定性充分，结论偏早；这些遗漏不能用测试数量或“本来就是旧问题”解释过去。

本轮具体改变是把上述 owner × 工作状态 × 入口 × error Zone × 迟到结果矩阵写入默认
suite 与审查规则，而不是继续只添加手动探针。之后的修改应按行为分组交叉验证；
发现偏差要继续区分旧 main 问题与重构回归，不再以“所有方面优于旧架构”作无条件结论。

本轮没有新增 macOS 实窗、Android／iOS 真机手势、长期 monkey 或进程 heap／性能测量。
GC 单测不能替代这些验收。没有修改独立 Analyzer Plugin／Generator 生产源码；
本次比较也不是 main 与当前架构的完整功能／性能基准。
