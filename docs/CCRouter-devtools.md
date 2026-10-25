# CCRouter DevTools 只读可视化

> 状态：1.x 已完成可嵌入只读面板、纯 Dart Snapshot/Trace Edge 协议和官方 DevTools
> Extension。Catalog/Runtime 联动、源码定位、组件依赖聚焦和能力调用链均已落地；生成式
> Host 自动装配已实现。后续只收敛诊断字段和性能，不增加 Runtime 控制操作。

## 定位

`ccrouter_devtools` 是一个可选的 Flutter Package，提供可嵌入 Host 的只读诊断面板
`CCRouterDevToolsPanel`。它不是 Runtime 控制台，也不是官方 Dart DevTools Extension：
面板不会导航、Pop、重试 InitTask、销毁 Scope、激活组件或修改 Adapter。

这样做的原因是 CCRouter 已经把诊断边界定义为“不可变、脱敏、有界”。将这些快照直接
暴露给一个可选 UI，可以满足开发期排障，又不会为了可视化而扩大业务 API 或破坏生命周期
所有权。跨进程和跨 SDK 工具使用独立的 `ccrouter_devtools_protocol` 纯 Dart Package；
嵌入式面板通过适配器把 Runtime 快照转换为协议对象，避免官方 Extension 复制 Runtime 数据模型。

## 接入

Host 直接依赖 `ccrouter_devtools` 后，`ccrouter generate` 会生成静态 Catalog，并将
`CCDevToolsHostIntegration` 写入 `CCHostAssembly`。Composition Root 只需把 Assembly
交给 `CCRouterHost.initialize`，不再手工注册或清理 VM Service Extension。本文统一维护
工具接入、Host 自动装配与生命周期规则；旧计划与阶段记录见[合并归档](archive/20261024-consolidation/README.md)。

仅在开发或内部诊断构建中加入依赖：

```yaml
dependencies:
  ccrouter_devtools:
    path: ../cc-router/packages/ccrouter_devtools
```

```dart
CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
```

必须是 Host 的直接依赖；组件传递依赖不会启用。Debug 默认注册，Profile 仅在
`--dart-define=CCROUTER_DEVTOOLS=true` 时注册，Release 强制关闭。`CCRouterHost.shutdown()` 开始时
会先清理 Provider 与 Catalog；页面、组件、Session 或单个 Navigation Host dispose 不参与该
isolate 级生命周期。

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

## Host 自动装配与生命周期

生成器只认 Host 对 `ccrouter_devtools` 的直接依赖，不扫描组件传递依赖决定 opt-in。
没有直接依赖时不生成 Tool Integration 或协议静态快照。生成 Catalog 只包含已验证的
Component、五类能力、Owner、静态关系、可移植源码位置与 fingerprint；未知关系显示 unresolved，
不猜测运行时调用。Host Assembly 携带只读 Integration 列表，并拒绝空或重复 Integration ID。

Host 使用唯一必需参数 `hostAssembly`。生成 Host 传入 `ccrouterGeneratedHostAssembly`，
手写 Host 使用 `CCHostAssembly.fromComponents`；不存在 loose `components/contractBundle`
与 Assembly 二选一的初始化方式。

依赖方向为 `ccrouter_devtools -> ccrouter Host SPI`，生成 Assembly 引用具体 Integration；
`ccrouter` 不反向依赖 DevTools。`CCHostToolIntegration` 只向 Composition Root 暴露同步
`id/onRuntimeReady/onRuntimeStopping`，不允许业务取得 Runtime、Registry、Scope 或 Adapter。

1. Runtime 完成组件和 Contract 校验并安装 Facade Resolver 后，调用 `onRuntimeReady`。
2. Integration 注册或更新 isolate endpoint，绑定生成 Catalog 和只读 Provider。
3. `CCRouterHost.shutdown` 开始时先调用 `onRuntimeStopping`，清空 Provider/Catalog，后续查询
   返回 uninitialized；再按 Runtime 原有顺序清理资源。
4. endpoint 无法注销，重初始化复用 handler；页面、单个 Navigation Host 和测试 Overlay
   不接管默认 Runtime 的工具生命周期。

工具注册、快照转换和停止失败均隔离为脱敏诊断，不能阻断初始化、业务调用或关闭。
回调必须同步短小，不能重入导航、解析 Service 或执行 Command。

Debug 默认开启，可用 `CCROUTER_DEVTOOLS=false` 关闭；Profile 默认关闭，可显式开启；Release
强制关闭，即使 define 为 true 也不得注册。开关只控制注册和交付，不保证依赖从 Release
构建图消失；需要完全隔离时由应用使用独立调试 Package/构建配置。

## 视图

- **Overview**：Runtime 状态、组件数、Managed Route Entry、Backend Entry、Pending
  导航、Failure 和 InitTask 数量；历史保留完整性、外部 Sink 投递健康和只读 Runtime
  navigation health。
- **Catalog**：搜索 Route、Service、Command、Event、InitTask，显示它是否出现在当前
  Runtime，并展示可复制的源码位置。Host 可以提供 `onOpenSource` 做 IDE/源码浏览器映射。
- **Components**：组件版本、必选/可选依赖组成的只读 Component Graph，支持搜索、聚焦和反向
  依赖查看。
- **Entries**：Managed Route Entry 的生命周期、Host/Outlet/Owner，以及 managed、foreign、
  opaque Backend Entry ledger。foreign/opaque 只表示观察结果，不代表可以由面板操作。
- **Timeline**：有界 Trace、导航生命周期事件和 Backend transition，显示稳定 ID、状态、
  Host/Outlet 和耗时，不显示 URI 参数或业务返回值。
- **Failures**：导航失败阶段、原因、错误类型、navigationId、Host/Outlet、attempt、
  recoveryDepth、initialRouteId、恢复选择、能力降级和等待策略决策的请求。恢复选择并不保证
  最终成功。正常取消以 warning 记录；最终 Sink status 为 cancelled，生命周期 phase 保持 failed。
- **InitTask DAG**：任务状态、Gate、Owner 和 `dependsOn` 边；缺失的依赖会明确标记，
  但面板不会尝试修复或重排任务。
- **Call Graph**：静态 Catalog 关系和当前有界 Trace Edge 的只读调用链。静态关系用于解释
  预期协作，Runtime 边用于确认本次实际发生的调用；两者不互相猜测或补全。

历史列表受已有容量限制，Pending/InitTask 是当前状态而非事件 ring。
默认 Provider 在订阅期间每 250ms 比较轻量 `CCRouter.diagnosticSnapshot`，仅在 Runtime
identity/revision 或独立 Sink 计数变化后通知重读完整快照，覆盖 Command/Service、InitTask、
延迟导航、Sink 完成和 shutdown/重初始化。面板在 TickerMode 关闭时取消订阅，恢复时立即
读快照；卸载时取消 Timer。手动刷新仍可用，不改变 Runtime。
七类事件历史分别显示 retained/capacity/omitted，capacity=0 为关闭保留；omitted 为容量关闭
或轮转造成的未保留，不包含外部 Sink 过滤和采样损失。Sink 单独显示 queued/capacity、inFlight、
peak、delivered/failed/dropped/closed；delivered 只表示 Sink 调用完成，不保证持久化上传。
Runtime navigation health 额外显示当前 Managed/退出中 Entry、挂起和 in-flight 导航、已跟踪
Host 生命周期、活动/保留 Backend Entry、Backend desync、观察队列深度以及生命周期累计计数。
`trackedNavigationHostCount`（协议 `trackedNavigationHosts`，界面 `trackedHosts`）只统计导航、
Pop 或 scoped navigator 按需捕获且尚未 detach 的 Host，不代表 Adapter 的完整注册表。
`inFlightNavigationCount` 仅统计 `singleFlight/rejectDuplicate` 的并发 gate，默认 `allow`
下可以为 0，不代表没有未完成导航。观察队列深度只包含等待交付的批次，容量为
`max(64, navigationDiagnosticCapacity)`；历史容量设为 0 不关闭观察交付。终态批次满载时
同步背压，重入仍保持等待容量和逐监听器 FIFO。结构变更先使健康缓存失效，再调用外部
Adapter／清理回调；稳定时复用不可变快照，健康读取本身不创建 Timer 或订阅。
Backend desync 包括 sequence gap（含 MultiHost 子 Host 序列跳号）和无法关联到具体 Entry
的 Managed Pop。MultiHost 在聚合前丢弃重复或倒退的子序列；注销清除旧注册的 desync，
同名新注册独立计数。
这些值是采样时的只读快照，不提供操作按钮，也不把 Foreign/opaque backend 事件解释成直接
`Navigator.pop` 次数。它们不能单独证明内存泄漏。
订阅者错误与已移除 Backend ledger 不在该七类历史列表内。空历史不能证明从未失败。
恢复需求采集属于应用，不进入 Runtime Snapshot 或 DevTools 面板；完整路由状态恢复尚未实现。

## Snapshot 协议

`ccrouter_devtools_protocol` 提供版本化的 `CCDevToolsSnapshotEnvelope`，包含可选的静态
`CCDevToolsStaticCatalogSnapshot`、当前 `CCDevToolsRuntimeSnapshot` 和有界
`CCDevToolsTraceEdge`。静态记录与运行时条目通过稳定 Route/Service/Command/Event/InitTask
或 Entry ID 关联；静态存在但运行时未安装、或运行时条目没有静态声明时，工具应显示“未解析”，
不能删除一侧或推断完整历史调用链。

协议版本仍为 1，以可选 `diagnostics` 与 `diagnosticHealth` 扩展固定白名单字段；
`diagnosticHealth.runtimeHealth` 提供上述 Runtime navigation health，旧 Producer 缺失时保持
null。
Runtime health 的 Host 计数使用 `trackedNavigationHosts`；新 reader 兼容旧
`registeredHosts` 键，但仍按“已跟踪生命周期数”解释，不将其推断为完整注册数。
diagnostics 包含 Failure、Fallback、Pending、InitTask；无任意 metadata Map，Pending
不导出 address/source，Failure 不导出业务取消 code。旧 reader 忽略未知字段；新 reader 对
旧 producer 缺失或 null 字段保持 null，UI 显示未提供而非零失败。存在但格式错误的已知字段
必须拒绝。Host/Outlet 未解析时不猜测；Failure Host 在解析前保留调用入口归属。

协议只允许源码位置、Owner、Host/Outlet、生命周期、稳定 Trace ID 和耗时等白名单字段，
不包含 URI 参数、Extra、Token、Widget、Navigator、业务返回值或任意业务 Map。Envelope
带有协议版本和捕获时间，解码方必须拒绝缺失字段和不支持的结构；协议升级通过新版本迁移，
不能静默把未知字段解释为可执行控制指令。

## 数据和隐私边界

面板消费 `CCRouter` 门面提供的只读 getter，永远不持有
`CCRouterRuntime`、`CCScope`、`Navigator`、Flutter `Route`、Widget、Extra、Token、完整 URI、
Query 值或业务结果。`CCRouterDevToolsSnapshot` 会再次复制列表边界，测试替身可以使用
`CCStaticDevToolsSnapshotProvider` 注入静态快照。

面板订阅在隐藏或 `dispose` 时移除；默认 Provider 的 Timer 回调隔离 listener 异常。面板不应被当作
审计日志、Replay 数据源或生产监控传输器。需要外部日志时，应使用 `CCDiagnosticsConfig`
与应用自己的日志 Sink。

## 官方 DevTools Extension

仓库现在提供独立的 `devtools/ccrouter_extension` Package。生成式 Host 会自动注册只读 VM
Service 入口。以下手工方式只用于测试或不使用生成 Host Assembly 的特殊 Host：

```dart
CCDevToolsServiceExtension.register(
  provider: const CCRouterDevToolsSnapshotProvider(),
);
```

Extension 通过 `ext.ccrouter.snapshot` 读取版本化 Envelope；它提供 Overview、Catalog、
Components、Call Graph 和 Diagnostics 五个只读页，使用手动 Refresh。Diagnostics 显示上述
四类诊断与健康状态，缺少协议扩展时明确标为未提供；静态 Catalog 与 Runtime Entry/Trace 按稳定 ID
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

## 验证与维护

回归覆盖直接/传递依赖、Debug/Profile/Release 开关、Catalog 一致性、启动失败隔离、
shutdown/重初始化、单 Host 卸载不影响 isolate endpoint、无缓存生成一致性和面板 listener
释放。静态声明、Runtime 事实与单次 Trace 分开呈现，面板不是审计或离线回放系统。
按日期记录的运行结果见[验证索引](validation/README.md)，发布门禁见
[Release Readiness](CCRouter-release-readiness.md)，不在本文重复维护测试数字或平台通过表。
