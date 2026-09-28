# DevTools 只读面板

使用 `ccrouter_devtools` 只读查看组件、路由、Backend、Trace、Failure/Fallback 和 InitTask
DAG。它是可选的 Host 调试 UI，不是业务能力，也不替代 `ccrouter_analyzer_plugin` 或
`ccrouter generate --check`。

```dart
import 'package:ccrouter_devtools/ccrouter_devtools.dart';

const panel = CCRouterDevToolsPanel();
```

开发者不应从面板触发导航、Pop、Retry、Scope dispose、组件激活或 Adapter 操作；这些能力
没有对外开放。面板未发现 Runtime 时只显示空状态。生产工程应通过 build flag 或依赖配置
决定是否包含该 Package。

面板显示的数据均为 CCRouter 已经脱敏和限容量的快照，不包含完整 URI、参数、Extra、Token、
Widget、Navigator 或业务返回对象。需要采集应用日志时使用 `CCDiagnosticsConfig`，不要从
面板文本反向解析业务数据。

需要把诊断发送到官方 DevTools Extension、CLI 或测试进程时，使用纯 Dart
`ccrouter_devtools_protocol` 中的 `CCDevToolsSnapshotEnvelope`。静态 Catalog 和 Runtime
通过稳定 ID 关联；协议允许源码位置、Owner、Host/Outlet、生命周期、Trace ID 和耗时，禁止
序列化 Runtime、Navigator、Widget、完整 URI、参数、Token 或业务对象。协议没有控制命令，
工具断连或静态 Catalog 缺失不能改变应用运行结果。
