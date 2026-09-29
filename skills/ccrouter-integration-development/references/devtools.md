# DevTools 只读面板

使用 `ccrouter_devtools` 只读查看组件、路由、Backend、Trace、Failure/Fallback 和 InitTask
DAG。它是可选的 Host 调试 UI，不是业务能力，也不替代 `ccrouter_analyzer_plugin` 或
`ccrouter generate --check`。

```dart
import 'package:ccrouter_devtools/ccrouter_devtools.dart';

final panel = CCRouterDevToolsPanel(onOpenSource: openInProjectEditor);
```

当 Host 直接依赖 `ccrouter_devtools` 并重新生成时，生成的 Host Assembly 会安装静态
`CCDevToolsStaticCatalogSnapshot`。它包含 Component 节点、Route/Service/Command/Event/
InitTask 源码记录和可证明的能力关系，面板默认读取该 Catalog。`onOpenSource` 由应用决定如何把安全的
`package:` URI 映射到 IDE、源码浏览器或复制操作；框架不会假设本机存在某个编辑器。

开发者不应从面板触发导航、Pop、Retry、Scope dispose、组件激活或 Adapter 操作；这些能力
没有对外开放。面板未发现 Runtime 时只显示空状态。生产工程应通过 build flag 或依赖配置
决定是否包含该 Package。

面板显示的数据均为 CCRouter 已经脱敏和限容量的快照，不包含完整 URI、参数、Extra、Token、
Widget、Navigator 或业务返回对象。需要采集应用日志时使用 `CCDiagnosticsConfig`，不要从
面板文本反向解析业务数据。

需要把诊断发送到官方 DevTools Extension、CLI 或测试进程时，使用纯 Dart
`ccrouter_devtools_protocol` 中的 `CCDevToolsSnapshotEnvelope`。静态 Catalog 和 Runtime
通过稳定 ID 关联。面板提供 Catalog 搜索与 Runtime 活跃标记、Component 依赖图的聚焦和反向
依赖查看，以及静态能力关系和 Runtime Trace 的只读调用链视图。协议允许源码位置、Owner、Host/Outlet、生命周期、Trace ID 和耗时，禁止
序列化 Runtime、Navigator、Widget、完整 URI、参数、Token 或业务对象。协议没有控制命令，
工具断连或静态 Catalog 缺失不能改变应用运行结果。

官方 Extension 使用相同的 Envelope，提供 Overview、Catalog、Components 和 Call Graph 四个
只读页。它可以显示源码位置和关系边，但不能直接打开 IDE；应用需要在 Host 侧提供编辑器映射。
Demo 的生成 Catalog 覆盖 Route、Service、Command、Event、InitTask 和跨组件依赖，可通过
“诊断”页面或 DevTools Extension 验证静态/动态关联。生成器只在 Host 直接依赖
`ccrouter_devtools` 时写入 Tool Integration；传递依赖不会隐式启用。Debug 默认开启，Profile
需要 `--dart-define=CCROUTER_DEVTOOLS=true`，Release 始终关闭。初始化与清理跟随默认 Runtime，
任意页面、组件或 Navigation Host dispose 都不能清理 isolate endpoint。手工注册只保留给
测试或不使用生成 Host Assembly 的特殊 Host。详见
[`docs/CCRouter-devtools-host-integration-plan.md`](../../../docs/CCRouter-devtools-host-integration-plan.md)。
