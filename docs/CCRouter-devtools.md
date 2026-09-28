# CCRouter DevTools 只读可视化

> 状态：1.x 已完成可嵌入只读面板、纯 Dart Snapshot/Trace Edge 协议和官方 DevTools
> Extension。Catalog/Runtime 联动、源码定位、组件依赖聚焦和能力调用链均已落地；后续只做
> 诊断字段扩展和性能维护，不增加 Runtime 控制操作。

## 定位

`ccrouter_devtools` 是一个可选的 Flutter Package，提供可嵌入 Host 的只读诊断面板
`CCRouterDevToolsPanel`。它不是 Runtime 控制台，也不是官方 Dart DevTools Extension：
面板不会导航、Pop、重试 InitTask、销毁 Scope、激活组件或修改 Adapter。

这样做的原因是 CCRouter 已经把诊断边界定义为“不可变、脱敏、有界”。将这些快照直接
暴露给一个可选 UI，可以满足开发期排障，又不会为了可视化而扩大业务 API 或破坏生命周期
所有权。跨进程和跨 SDK 工具使用独立的 `ccrouter_devtools_protocol` 纯 Dart Package；
嵌入式面板通过适配器把 Runtime 快照转换为协议对象，避免官方 Extension 复制 Runtime 数据模型。

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
- **Catalog**：搜索 Route、Service、Command、Event、InitTask，显示它是否出现在当前
  Runtime，并展示可复制的源码位置。Host 可以提供 `onOpenSource` 做 IDE/源码浏览器映射。
- **Components**：组件版本、必选/可选依赖组成的只读 Component Graph，支持搜索、聚焦和反向
  依赖查看。
- **Entries**：Managed Route Entry 的生命周期、Host/Outlet/Owner，以及 managed、foreign、
  opaque Backend Entry ledger。foreign/opaque 只表示观察结果，不代表可以由面板操作。
- **Timeline**：有界 Trace、导航生命周期事件和 Backend transition，显示稳定 ID、状态、
  Host/Outlet 和耗时，不显示 URI 参数或业务返回值。
- **Failures**：导航失败阶段、原因、错误类型、恢复结果、能力降级和等待策略决策的请求。
- **InitTask DAG**：任务状态、Gate、Owner 和 `dependsOn` 边；缺失的依赖会明确标记，
  但面板不会尝试修复或重排任务。
- **Call Graph**：静态 Catalog 关系和当前有界 Trace Edge 的只读调用链。静态关系用于解释
  预期协作，Runtime 边用于确认本次实际发生的调用；两者不互相猜测或补全。

所有列表都来自 CCRouter 已有的容量限制。刷新和事件订阅只重新读取快照，不改变 Runtime。

## Snapshot 协议

`ccrouter_devtools_protocol` 提供版本化的 `CCDevToolsSnapshotEnvelope`，包含可选的静态
`CCDevToolsStaticCatalogSnapshot`、当前 `CCDevToolsRuntimeSnapshot` 和有界
`CCDevToolsTraceEdge`。静态记录与运行时条目通过稳定 Route/Service/Command/Event/InitTask
或 Entry ID 关联；静态存在但运行时未安装、或运行时条目没有静态声明时，工具应显示“未解析”，
不能删除一侧或推断完整历史调用链。

协议只允许源码位置、Owner、Host/Outlet、生命周期、稳定 Trace ID 和耗时等白名单字段，
不包含 URI 参数、Extra、Token、Widget、Navigator、业务返回值或任意业务 Map。Envelope
带有协议版本和捕获时间，解码方必须拒绝缺失字段和不支持的结构；协议升级通过新版本迁移，
不能静默把未知字段解释为可执行控制指令。

## 数据和隐私边界

面板消费 `CCRouter` 门面提供的只读 getter 与观察 listener，永远不持有
`CCRouterRuntime`、`CCScope`、`Navigator`、Flutter `Route`、Widget、Extra、Token、完整 URI、
Query 值或业务结果。`CCDevToolsSnapshot` 会再次复制列表边界，测试替身可以使用
`CCStaticDevToolsSnapshotProvider` 注入静态快照。

面板的 listener 在 `dispose` 时全部移除；监听器异常由 Runtime 自己隔离。面板不应被当作
审计日志、Replay 数据源或生产监控传输器。需要外部日志时，应使用 `CCDiagnosticsConfig`
与应用自己的日志 Sink。

## 官方 DevTools Extension

仓库现在提供独立的 `devtools/ccrouter_extension` Package。Host 的 Debug Composition Root
可以注册一次只读 VM Service 入口：

```dart
CCDevToolsServiceExtension.register(
  provider: const CCRouterDevToolsSnapshotProvider(),
);
```

Extension 通过 `ext.ccrouter.snapshot` 读取版本化 Envelope；它提供 Overview、Catalog、
Components 和 Call Graph 四个只读页，并将静态 Catalog 与 Runtime Entry/Trace 按稳定 ID
关联。它不能导航、重试、销毁 Scope、激活组件或修改 Adapter。发布前使用支持 Web
的稳定 Flutter SDK 执行：

```bash
flutter build web --release
dart run devtools_extensions validate --package=devtools/ccrouter_extension
dart run devtools_extensions build_and_copy \
  --source=devtools/ccrouter_extension \
  --dest=devtools/ccrouter_extension/extension/devtools
```

当前仓库的 OHOS Flutter SDK 不能运行 `dart:js_interop` Web widget test，因此 Extension
门禁是稳定 SDK 的 Web 构建加官方 validate；框架和 Demo 仍使用项目默认 FVM 验证。Extension
显示源码 URI，但不绑定本机 IDE；需要跳转时由 Host/开发工具自行建立 Package URI 到工作区
文件的映射。
