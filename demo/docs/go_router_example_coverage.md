# GoRouter 官方示例覆盖对照

## 对照原则

- 对照来源：Flutter `packages/go_router/example` 的 `main` 分支，核对日期 2026-09-20。
- Demo 验证 CCRouter 的后端中立语义，不在业务页面复制 `context.go`、`GoRouterState`
  或 named location 调用。
- GoRouter 专属装配只允许出现在 Host 侧；业务导航统一使用 `CCRouter.navigator` 和
  生成的 typed Intent。
- 无法保持类型、生命周期或跨后端一致性的能力不会为了“示例数量”进入公开 API。

## 已覆盖

| 官方示例 | CCRouter Demo 等价场景 | 状态 |
| --- | --- | --- |
| `main.dart` / `others/push.dart` | 首页、typed Push、Pop 与 typed result | 已覆盖 |
| `sub_routes.dart` | Shell Feed -> Detail，声明 `parentRouteId` | 已覆盖 |
| `path_and_query_parameters.dart` | `int` Path 与 `String/List<String>` Query Codec | 已覆盖 |
| `path_parameter_regex.dart` | Detail 的 `id: \d+` Path constraint | 已覆盖 |
| `redirection.dart` | Route Interceptor 的 Redirect | 已覆盖 |
| `async_redirection.dart` | Deferred Navigation、resume 与 timeout | 已覆盖 |
| `top_level_on_enter.dart` | Global Interceptor | 已覆盖 |
| `on_exit.dart` | PopGuard 拒绝或允许离开 | 已覆盖 |
| `exception_handling.dart` / `others/error_screen.dart` | 标准导航错误与 Failure Policy | 已覆盖 |
| `others/extra_param.dart` | `CCExtraParam` + `DemoExtraPayload` | 已覆盖，限定进程内 |
| `shell_route.dart` | 单嵌套 Navigator 的 Feed / Settings Shell | 已覆盖 |
| `push_with_shell_route.dart` | Shell 内打开 Root Navigator 透明页 | 已覆盖 |
| `shell_route_top_route.dart` | Host Shell 根据当前 URI/Route 构建外层导航状态 | 已覆盖于 Host 层 |
| `stateful_shell_route.dart` | 三分支 `StatefulShellRoute.indexedStack` | 已覆盖 |
| `others/custom_stateful_shell_route.dart` | Host 可用 `CCGoRouterRouteOverride` 自定义 Shell 容器 | 扩展点已覆盖，未复制 UI |
| `transition_animations.dart` / `others/transitions.dart` | Material、Cupertino、Fade、Scale、Bottom Slide、透明 Page | 已覆盖 |
| `others/nav_observer.dart` | Adapter Observer、Navigation Aspect 和页面生命周期 | 已覆盖 |
| `others/init_loc.dart` | `initialLocation` 直达 StatefulShell 分支详情 | 已覆盖 |
| `route_metadata.dart` | 结构化 Route Definition、Placement、Policy 与生成文档 | 等价覆盖，不开放任意 `Map` |
| `books/` | 参数、嵌套路由、Shell、重定向和错误策略的组合 | 能力分别覆盖，不重复建设第二套 App |

## 有意采用不同接口

| 官方示例 | CCRouter 决策 | 原因 |
| --- | --- | --- |
| `named_routes.dart` | 使用生成的 typed Intent 和稳定 Route ID | 避免业务依赖 GoRouter name/location 字符串 |
| `go_relative.dart` | 不向业务公开相对 location 导航 | 相对路径依赖当前后端栈上下文，难以跨 Adapter 保持确定语义 |
| `others/router_neglect.dart` | 留给 Web Host 配置 | URL history 策略不是组件路由契约 |

## 延后或未宣称支持

| 官方示例 | 当前状态 | 后续前提 |
| --- | --- | --- |
| `extra_codec.dart` | 仅支持进程内 typed Extra，不宣称可序列化恢复 | 完成显式 Extra Codec 与 Route Restoration 契约 |
| `routing_config.dart` | 不支持业务任意替换完整路由表 | 通过组件 `activate/deactivate` 提供有所有权和生命周期的动态路由 |
| `state_restoration/*` | 仅记录 restoration opportunity 诊断 | 完成 Route/Result/Session/Host 一致的恢复模型 |

## Host 与自适应布局补充验证

`lib/examples/multi_host_demo.dart` 不是 GoRouter 官方示例的复制。它在单个 Flutter View
内同时挂载两个 Host 和两个 GoRouter，用于验证 Host 选择、RouteEntry、Observer 与路由
状态隔离；同一入口还验证一个 Host 在横竖屏、桌面窗口缩放和模拟 hinge 下更新
`CCHostLayoutMetrics`，并切换 list/detail Outlet。它不代表原生多 Window 已完成；平台
Window/Engine 生命周期仍属于后续工作。
