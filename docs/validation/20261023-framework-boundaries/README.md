# 框架与应用职责收口

日期：2026-10-23。分支：`codex/managed-navigation-runtime`，未提交、未推送。

## 问题与取舍

埋点实现迁到 Demo 后，Core 仍接收 Visitor/Application Session 身份；恢复需求统计占用
Runtime 初始化、订阅、队列和 DevTools；MultiHost 同时负责布局策略与导航可见性。
这些依赖使产品选择进入框架生命周期，修改应用策略需要改动框架。

保留可选框架模块可减少 Host 迁移，但继续扩大框架职责；逐页面独立实现又会重复资源管理。
本次采用应用统一实现加最窄 Host SPI：导航观察、独立 Stack、Outlet 可见性和 Route Scope
继续归框架，产品身份、需求收集与布局选择归应用。没有保留旧 SPI 别名。

README、接入 Skill、DevTools、架构及混合路由说明同步当前边界；历史审查和旧 Demo 验收
保留原结果，并显式标注已退役的身份、恢复需求与布局策略实现，避免误用为当前能力证明。

## 实现与迁移

1. 移除 `CCNavigationTelemetryContext/Provider`、Host 初始化参数及 Aspect 上的身份字段。
   框架继续提供 navigationId、Route、Host、Outlet、Source、阶段耗时和生命周期事实。
   Demo 使用 `AppAnalyticsIdentity` 与桥的 `identityProvider`，快照保存在应用的有界 Map。
   首次 Found 观察交付时捕获（Arrival/Show fallback），重定向和隐藏后重现继续使用同一快照。
   因观察异步交付，这不是导航调用瞬间的身份；需要精确操作归属的应用应在自己的动作边界关联。
   成功 After 不提前释放仍活跃 Entry 的快照；失败、移除、dispose 负责释放。
   Consent/账号切换前调用 `resetTracking()`；dispose 清空 Provider 并阻止旧观察重新填充。
2. 移除恢复需求 Source/Controller、Runtime 专用历史与订阅、facade 入口、诊断类别及
   DevTools 分区。可选 `DemoRestorationDemandRecorder` 位于 `demo/lib/restoration_demand.dart`，
   无需初始化 Runtime；应用显式传入真实平台证据，负责 Consent、平台订阅和导出。
   示例只保留有界、脱敏的需求信号，dispose 清空历史、导出 callback 并拒绝迟到报告。
   它未接入真实平台源，不实现导航栈恢复，也不提供 replay。
3. 将自适应布局模型和原 600/840 断点迁到 `demo/lib/adaptive_layout.dart`，类型改用
   `Demo…`。应用选择单双栏与模拟 hinge 策略，调用
   `CCMultiHostNavigationAdapter.setActiveOutlets(hostId: ..., outlets: ...)`。
   新 Host SPI 先校验非空、不重复、不空白的集合和 Host，再复制集合、发布可见性事实；
   不改变活动 Host，不移动 Stack，不关闭 Entry 或 Scope，不保留布局历史/监听器。

业务 typed Intent、push/close、Service、Command、Event、InitTask、Session Scope、UI Fragment、
Deep Link 入口和信任校验保留。Flutter Page/MaterialApp 的 restoration 参数透传继续保留，
它们不等于 CCRouter 已实现完整路由恢复。

旧 Host 初始化参数、Aspect 的 `telemetryContext` 和
`updateHostLayout/adaptiveLayouts/addAdaptiveLayoutListener` 是破坏性接入变化；
仓库仍在首次发布前，Demo 与文档同步迁移。所有改动留在原 worktree，未提交，
保留已有导航重构；回退应按本轮 diff 逐项恢复，不能重置整个工作区。

## 生命周期与回归重点

- 身份归属：重定向、并发 Entry、成功 After 后保留、移除/失败释放、匿名 ID 校验、Provider
  异常隔离、Consent reset、dispose 后迟到观察和 1024 项容量边界。Provider 同步触发
  dispose/reset/撤回 Consent 的三个用例先复现失败，再通过 revision 与状态复核修复；
  旧回调返回后不会重新保存身份或发布 PV（[修复前失败证据](identity-before.log)，
  修复后结果包含于下表 Dart 全量）。
- 恢复需求：初始化前证据、运行中追加、容量淘汰、脱敏、导出失败隔离、幂等 dispose 和迟到报告。
- 布局：窄屏/宽屏/模拟 hinge、真实 Managed Outlet 页面和 typed result；非法输入不发布事件，
  调用方列表修改不改变快照，另一个 Host 的可见性及活动 Host 不变。
- Scope：四个跨 Host/Outlet Entry 保持原 identity 与同一 Route Service，隐藏/恢复不完成 Push
  Future、不销毁 Scope；Runtime 退出后四个结果完成，各 Service 只销毁一次。
- API：编译探针确认旧身份、恢复需求、布局策略类型不能再从框架 Contracts 导入。

## 验证

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| Framework + Demo + navigation_lab + 应用 Flutter 埋点 | 最终 705 项通过，包含 semantic monkey 和返回手势回归 | [Flutter](flutter-tests.log) |
| 应用 Dart 埋点 + Firebase + 仓库工具 | 最终 55 项通过，含身份归属与同步回调重入回归 | [Dart](dart-tests.log) |
| 强化 Host/API 专项 | 37 项通过，已包含于上述 Flutter 全量，不重复累加 | [Host](host-regression.log) |
| 完整 Generator / CLI 回归 | 645 项通过，1 项远程 Analyzer 安装冒烟按配置跳过 | [Generator](generator-tests.log) |
| Workspace analyze | No issues found | [Analyze](analyze.log) |
| Demo generate / 无缓存 freshness | 6 components、34 routes、11 generated Packages，通过 | [生成](generate.log)、[检查](generate-check.log) |
| 独立 Order Example 无缓存 freshness | 2 components、2 routes、3 generated Packages，通过 | [Example](order-check.log) |
| macOS 默认 Demo Debug 构建 | 通过 | [构建](macos-build.log) |
| 双 Skill 隔离安装及真实 CLI 检查 | 通过 | [Skill](skills.log) |

Generator 跳过项为 `analyzer_installation_smoke_test.dart` 中需要显式启用
`CCROUTER_ANALYZER_NETWORK_SMOKE=1` 的远程 Git/Pub 安装测试；本轮未修改 Analyzer Plugin。
文档链接、release sensitivity 和 `git diff --check` 通过；生成物只通过 CLI 刷新，没有手改。

本轮未重新进行真实窗口、Android/iOS 真机手势或长期内存/RSS 验收。自动化测试和构建
不能替代这些平台证据。恢复需求示例未接入真实平台源；完整路由状态恢复仍未实现。
结构性资源检查和专项生命周期测试没有发现本轮新增的高置信泄漏，但不声称生产长期无泄漏。
