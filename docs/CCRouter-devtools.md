# CCRouter DevTools 只读可视化

> 状态：1.x 已完成可嵌入只读面板；官方 DevTools Extension 和静态 Catalog 联动列入正式发布前的
> P1 工具计划，必须先完成只读快照协议。

## 定位

`ccrouter_devtools` 是一个可选的 Flutter Package，提供可嵌入 Host 的只读诊断面板
`CCRouterDevToolsPanel`。它不是 Runtime 控制台，也不是官方 Dart DevTools Extension：
面板不会导航、Pop、重试 InitTask、销毁 Scope、激活组件或修改 Adapter。

这样做的原因是 CCRouter 已经把诊断边界定义为“不可变、脱敏、有界”。将这些快照直接
暴露给一个可选 UI，可以满足开发期排障，又不会为了可视化而扩大业务 API 或破坏生命周期
所有权。后续如果需要官方 DevTools Extension，可以复用同一套 Snapshot Provider，不需要
复制一套 Runtime 数据模型。

## 接入

仅在开发或内部诊断构建中加入依赖：

```yaml
dependencies:
  ccrouter_devtools:
    path: ../cc-router/packages/ccrouter_devtools
```

因为面板是 Flutter Widget，任何实际导入它的应用或组件都必须放在
`dependencies`；只有把面板封装在单独的 debug Package 并确保 Release 不编译该 Package
时，才适合使用 `dev_dependencies`。

在调试页面、Debug Drawer 或受控路由中嵌入：

```dart
import 'package:ccrouter_devtools/ccrouter_devtools.dart';

const diagnosticsPage = CCRouterDevToolsPanel();
```

应用仍然负责 Debug/Release 开关。面板不会自动初始化 `CCRouter`，Runtime 未初始化时
会显示空状态。生产构建可以不引入该 Package，或通过应用自己的 build flag 不挂载页面。

## 视图

- **Overview**：Runtime 状态、组件数、Managed Route Entry、Backend Entry、Pending
  导航、Failure 和 InitTask 数量，以及状态恢复需求信号。
- **Components**：组件版本、必选/可选依赖组成的只读 Component Graph。
- **Entries**：Managed Route Entry 的生命周期、Host/Outlet/Owner，以及 managed、foreign、
  opaque Backend Entry ledger。foreign/opaque 只表示观察结果，不代表可以由面板操作。
- **Timeline**：有界 Trace、导航生命周期事件和 Backend transition，显示稳定 ID、状态、
  Host/Outlet 和耗时，不显示 URI 参数或业务返回值。
- **Failures**：导航失败阶段、原因、错误类型、恢复结果、能力降级和等待策略决策的请求。
- **InitTask DAG**：任务状态、Gate、Owner 和 `dependsOn` 边；缺失的依赖会明确标记，
  但面板不会尝试修复或重排任务。

所有列表都来自 CCRouter 已有的容量限制。刷新和事件订阅只重新读取快照，不改变 Runtime。

## 数据和隐私边界

面板消费 `CCRouter` 门面提供的只读 getter 与观察 listener，永远不持有
`CCRouterRuntime`、`CCScope`、`Navigator`、Flutter `Route`、Widget、Extra、Token、完整 URI、
Query 值或业务结果。`CCDevToolsSnapshot` 会再次复制列表边界，测试替身可以使用
`CCStaticDevToolsSnapshotProvider` 注入静态快照。

面板的 listener 在 `dispose` 时全部移除；监听器异常由 Runtime 自己隔离。面板不应被当作
审计日志、Replay 数据源或生产监控传输器。需要外部日志时，应使用 `CCDiagnosticsConfig`
与应用自己的日志 Sink。

## 后续官方 DevTools Extension

当前仓库先交付可嵌入只读面板，避免引入在不同 Flutter SDK/DevTools 版本上不稳定的
`devtools_extensions` 依赖。正式发布前若要提供官方扩展，必须增加独立 `devtools/` Package，
通过版本化的只读 `CCDevToolsSnapshotProvider` 协议接入，并保持“只读、脱敏、有界”的边界；
具体视图、调用链和 Demo 验收以
[`CCRouter-pre-release-capability-plan.md`](CCRouter-pre-release-capability-plan.md) 为准。
