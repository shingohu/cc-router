# CCRouter 验证证据索引

更新日期：2026-10-24。这里集中导航验证记录，不替代[当前能力矩阵](../README.md)或
[发布门禁](../CCRouter-release-readiness.md)。每份报告只证明其注明源码、命令、设备和范围；
旧失败由后续修复报告闭环，不删除失败证据，也不改写历史测试数字。

## 最新源码自动化证据

[2026-10-24 诊断与 DevTools 修复](20261024-diagnostics/report.md)：失败 Host/Outlet 与恢复链归属、
取消告警、历史完整性、Sink 健康、非导航刷新及 optional 协议兼容；包含检查失败和复核边界。

[2026-10-24 遗留项收口](20261024-closure/report.md)：Demo Cupertino 正文、小屏标题、
遗留文案与图标资源修复，验收材料可逆脱敏，以及华为同引擎固定场景复测。

[2026-10-24 核心价值收口回归](20261024-core-value-final/report.md)：按 13 条约定复核框架、
生成、隔离 Plugin、Demo/独立 Host、工具、API 边界与压力场景。Generator 全量 668 项
通过、1 项远端 smoke 跳过；敏感信息门禁失败及真机遗留待办在报告中独立列明。

[2026-10-24 Host / Outlet 绑定导航与实现后 review](20261024-scoped-navigator/report.md)：
新增 `CCRouter.navigatorOf(context)`，修复真实 `default` Host 的归属歧义；
框架 1,411 项、Demo 113 项通过，包含旧对象换代拒绝和 Context / Runtime / Navigator GC 验证。

[2026-10-24 Managed 工具链接入修复](20261024-managed-tooling/report.md)记录 Generator 脚手架、
隔离 Analyzer、真实 LSP 和独立消费者验证；与下方 Runtime 回归的范围分别计数。
后续[两阶段推送与 Demo Plugin pin 验证](20261024-managed-tooling/pin-release.md)记录远端来源、
bootstrap 加载验证及现有 IDE 缓存边界。

[2026-10-24 外部导航等待与所有权修复](20261024-backend-wait-fixes/report.md)记录此前专项，
包含修复前失败、修复内容与原始日志：

| 项目 | 该轮结果与边界 |
| --- | --- |
| Flutter 框架、Demo 及报告所列模块 | 1537 项通过，包含 96 项新增边界回归 |
| 应用侧 analytics / analytics_firebase 与 tool Dart suite | 55 项通过；应用示例不是框架埋点能力 |
| Generator Contract/API 隔离专项 | 4 项通过；未重跑 Generator 全量或独立 Analyzer Plugin suite |
| 静态分析 | 无问题 |
| Demo Builder `--no-cache --check` | 6 组件、34 路由、11 Packages 一致；保留 build_runner 增量状态，不是冷构建基准 |
| Monkey / 返回组合 | 3 个固定 seed，每个 120 步；含重复/取消 iOS 侧滑等 Widget/桥接回归 |

该轮未重做 macOS 实窗、Android/iOS 真机手势、原生 heap 或长期性能。上述结果不证明当前
所有平台均无缺陷、不证明性能优于旧架构，也不自动关闭发布阻塞项。

## 真实平台与功能覆盖

[2026-10-24 Android Native 分配归因](20261024-native-attribution/report.md)：匹配 Engine
符号、完整随机负载 trace、诊断开关对照及不初始化 CCRouter 的纯 Flutter 字体复现。
原生字体分配、诊断开销和框架 Owner 分开归因；不延续旧 trace 的丢失数据。

[2026-10-24 华为 Android 真机 30 分钟 Monkey](20261024-huawei-monkey-30m/report.md)：
Profile 构建、内存/CPU/Flutter 帧、真实 UI 问题及系统录屏/温控干扰分段记录；
内存增长和长帧仍有待定位项，不能据此宣称零泄漏或全功能通过。

| 日期 | 记录 | 适用范围 |
| --- | --- | --- |
| 2026-10-23 | [Host 事件身份修复与 macOS 复验](20261023-host-event-identity-fixes/report.md) | 多轮同 ID 重开、旧请求、双 Host、自适应 Outlet；包含真实窗口通过记录 |
| 2026-10-23 | [macOS 生命周期原始失败](20261023-macos-host-lifecycle-acceptance/report.md) | 保留 P1/P2 复现及快照；修复和通过证据见上一行 |
| 2026-10-22 | [全量能力与 macOS 实窗矩阵](managed_full_review_20261022.md) | 能力、Demo 入口、当时自动化与桌面操作的逐项映射 |
| 2026-10-22 | [Managed 平台验收](managed_navigation_platform_acceptance_20261022.md) | macOS、Android（含三星）、iOS 真机/Simulator；各平台结论与未覆盖项分别列出 |
| 2026-10-22 | [重构功能对齐审查](managed_functional_parity_review_20261022.md) | 迁移期缺口与边界快照，不能独立代表当前缺口仍存在或均已关闭 |
| 2026-10-15 | [三星预测返回原始记录](android_predictive_back_samsung_20261015.md) | 旧 Backend/开关对照的历史证据；不是当前 Managed 真机验收入口 |

GoRouter 比较仅作历史证据，兼容包与入口已删除。当前运行方式见[Demo README](../../demo/README.md)。

## 2026-10-23—24 边界审查与修复记录

以下按主题归档，同一天内不从目录名称推断执行先后或源码身份。原始审查、修复与日志
分别保留；最终源码回归入口见上方 2026-10-24 报告。

| 主题 | 原始审查 | 修复/验证 |
| --- | --- | --- |
| Pop 等待、初始栈身份、Host Zone | [审查](20261024-pop-wait-review/report.md) | [修复及扩大回归](20261024-backend-wait-fixes/report.md) |
| 独立等待者、跨 Host Entry、预测返回观察 | [审查](20261023-independent-waiter-review/report.md) | [修复](20261023-independent-waiter-fixes/report.md) |
| 挂起工作、Host 聚合所有权 | [审查](20261023-pending-work-review/report.md) | [修复与 main 对照](20261023-pending-work-fixes/report.md) |
| Zone 保留与清理屏障 | [审查](20261023-construction-retention-review/report.md) | [修复](20261023-zone-retention-fixes/report.md) |
| 已结束调用与同步交付 | [审查](20261023-completed-invocation-review/report.md) | [修复](20261023-completed-invocation-fixes/report.md) |
| Session 准入、跨 Zone Resume | [审查](20261023-session-resume-review/report.md) | [修复](20261023-session-resume-fixes/report.md) |
| 同步重入与异步交接 | [审查](20261023-reentrant-boundary-review/report.md) | [修复](20261023-reentrant-boundary-fixes/report.md) |
| Host 换代与资源接管 | [扩大场景审查](20261023-expanded-scenario-review/report.md) | [修复](20261023-host-incarnation-fixes/report.md) |
| 来源隔离、异步 Host 归属 | [审查](20261023-partition-origin-review/report.md) | [修复](20261023-partition-origin-fixes/report.md) |
| 共享执行、订阅身份、UI/Contract 生命周期 | [启动与 Zone 审查](20261023-startup-zone-review/report.md)、[UI/观察者审查](20261023-ui-observer-contract-review/report.md) | [修复](20261023-shared-lifecycle-contract-fixes/report.md) |
| 返回、平台入口、渲染与可见性 | [交叉场景审查](20261023-cross-scenario-review/report.md) | [操作所有权](20261023-operation-ownership-fixes/report.md)、[Renderer/Back](20261023-renderer-back-fixes/report.md)、[导航生命周期](20261023-navigation-lifecycle-fixes/README.md) |

## 迁移、接入与较早专项

- [GoRouter 退役与原生 Managed 回归（2026-10-23）](go_router_retirement_20261023.md)。
- [框架与应用职责收口（2026-10-23）](20261023-framework-boundaries/README.md)。
- [应用侧埋点迁移（2026-10-23）](20261023-application-analytics/README.md)。
- [UI Fragment 独立接入技术验证（2026-10-20）](ui-fragment-adoption-20261020/README.md)。
- [消费者最小闭环（2026-10-19）](consumer-adoption-20261019/README.md)。
- [导航历史与容量（2026-10-19）](navigation-history-capacity-20261019.md)。
- [Diagnostic Sink 背压与 Host 清理（2026-10-19）](diagnostic-sink-backpressure-20261019.md)。
- [完整审查（2026-10-15）](20261015-full-review/REPORT.md)与[后续修复（2026-10-16）](20261015-full-review/FIXES-20261016.md)。

## 证据维护规则

- 新回归报告链接原始日志、失败与修复，注明实际覆盖的 suite；无效命令不算执行通过。
- 真实窗口、系统手势、构建 smoke、Widget 回归和性能/heap 分开记录，不能相互替代。
- 后续修复新增前向链接或索引，不重写旧报告的源码身份、失败事实、测试数和设备结果。
- README 与专项契约引用本索引或对应报告；完整日志保留在原目录，不复制成多份状态表。
- 保存日志前运行 `node tool/sanitize_validation_evidence.mjs` 检查本机路径；需要归一化时
  加 `--write`，工具先将所有原件备份到仓库外再修改，包含 tracked 和未追踪验收文件。
  仅做路径归一化，不能替代敏感信息扫描。提交前执行
  `fvm dart tool/release_sensitivity_check.dart --include-untracked`，暂存后仍执行原 tracked 门禁。
