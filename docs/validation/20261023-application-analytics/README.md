# 应用侧埋点迁移验证

日期：2026-10-23。分支：`codex/managed-navigation-runtime`，未提交/推送。

双可选框架包承担产品统计策略，维护边界超出组件与导航核心。保留官方可选包可减少迁移，
但继续扩大框架责任；每个页面自行实现又会重复口径和资源管理。本次将其迁为应用统一基础库，
保留实现与回归覆盖，框架只提供导航观察与诊断。

## 迁移

- 原框架包改为 `demo/modules/analytics`（`demo_analytics`）和
  `demo/modules/analytics_flutter`（`demo_analytics_flutter`），均为不发布的普通 library。
- 公开类型 `CCAnalytics…` 改为 `AppAnalytics…`，导航观察桥改为
  `AppNavigationAnalyticsBridge`，其 Aspect ID 改为 `demo.analytics.navigation`。
  无旧名兼容导出。框架原生 `CCNavigationAspect` 等通知 API 保持不变。
- Demo 页面/配置和 Firebase callback 映射采用应用侧类型；不额外增加 Service/Contract。
  核心框架与 `ccrouter_test` 不依赖两个新包。
- 原四个测试文件及埋点 benchmark 随实现迁移，CI 显式运行新路径。
  框架性能编排不再执行产品埋点队列，应用 benchmark 独立运行。
- 使用 `ccrouter clean packages/ccrouter_analytics` 清理旧包的两份生成物，
  再由 `generate demo` 重建当前 Host/Package 输出；没有手改生成文件。

## 实际结果

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| Framework + Demo + navigation_lab + 应用 Flutter 埋点 | 706 项通过 | [Flutter](analytics-move-flutter-tests.log) |
| Pure Dart 应用埋点 + Firebase | 33 项通过 | [Dart](analytics-move-dart-tests.log) |
| 上述 Dart + 仓库工具/Skill 回归 | 47 项通过（包含上述 33 项） | [Dart 与工具](analytics-move-final-dart-tests.log) |
| Workspace Analyze | No issues found | [Analyze](analytics-move-final-analyze.log) |
| Demo generate、uncached freshness | 6 components、34 routes、11 generated Packages，通过 | [生成](analytics-move-generate.log)、[检查](analytics-move-generate-check.log) |
| 独立 Order Example uncached freshness | 2 components、2 routes、3 generated Packages，通过 | [Example](analytics-move-order-check.log) |
| macOS 默认 Demo Debug 构建 | 通过 | [构建](analytics-move-macos-build.log) |
| 应用埋点 benchmark | 1000 入队、容量 64、峰值 64、丢弃 936、close 后 pending 0 | [应用基准](analytics-move-benchmark.log) |
| 框架性能编排 | Runtime scaling/concurrency、Service scaling、1000-cycle long run 全部完成 | [框架基准](analytics-move-framework-benchmarks.log) |

文档检查（121 份 tracked Markdown）、`git diff --check`、release sensitivity、
独立双 Skill bundle 与真实 CLI 检查均通过。迁入 Demo 后触发的 lint 已修正。
原测试覆盖了 Consent、投递失败/超时/重入、导航访问、Scope、前后台、曝光与监听清理。

本轮没有重跑完整 Generator 645 项，也没有重新做真实窗口或 Android/iOS 手势验收；
上轮证据不冒充本轮复验。性能值是单机单次趋势，不用于证明架构加速或长期无泄漏。
改动仍在既有 worktree 内，保留了此前未提交的导航重构与 GoRouter 退役工作。

当前接入边界见[应用侧埋点设计](../../CCRouter-analytics-and-auto-track-design.md)。
