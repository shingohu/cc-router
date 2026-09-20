# CCRouter Demo 路由验证记录

## 验证基线

- 日期：2026-09-20
- 平台：macOS 真实 Flutter 应用
- Backend：`CCGoRouterBackend.managed`，`go_router 17.5.0`
- SDK：FVM `ohos/oh-3.41.9-release`（Flutter 3.41.10 OHOS / Dart 3.11.5）
- 组件：3
- 生成路由：28

Demo 的交互实现位于 `modules/navigation_lab`，宿主只负责初始化 CCRouter、
安装生成组件清单并挂载 GoRouter Backend。

## 功能矩阵

| 能力 | Demo 场景 | macOS 结果 |
| --- | --- | --- |
| Typed Push / result | Detail Page | 通过 |
| Path alias / custom scheme / full URL | Detail Page 多 Pattern | 通过 |
| External Deep Link ingress | UI 模拟 + macOS `ccrouter://` Scheme | 通过，保留 external origin 与 source |
| Path / Query 参数注入 | `int` 和 `List<String>` | 通过 |
| Replace | 同 routeId 更换 Level 参数 | 通过，旧 State 和 Route Scope 销毁 |
| Pop / maybePop | Detail、Stack、PopGuard | 通过 |
| Go / Reset | Stack Workbench | 通过 |
| Nested Route | Shell Feed -> Detail | 通过，子路由保持在声明的 Outlet |
| ShellRoute | Feed / Settings 共享 Shell | 通过 |
| Root Route from Shell | Shell 内打开透明全屏页 | 通过，不污染 Shell Outlet |
| StatefulShellRoute | Home / Activity / Profile | 通过，分支历史与 Widget State 保持 |
| Initial Deep Link into Shell | `/workspace/home/73` | 通过，直接进入 Home Outlet 的详情页 |
| Typed Extra | `DemoExtraPayload` | 通过，仅进程内传递，不进入 URL 或诊断 |
| Multi Host | Primary / Secondary 双 Router | 通过，Host 路由状态相互隔离 |
| Multi Outlet | Shell + 三个 Stateful Branch Outlet | 通过，每个 Outlet 独立 Key 与 Observer |
| Global / Route Interceptor | Proceed / Cancel | 通过 |
| Redirect / Defer / resume / Timeout | Policy Lab | 通过 |
| PopGuard | 未保存表单 | 拒绝和放行均通过 |
| Failure Policy | 未知路由转安全兜底页 | 通过 |
| Navigation Aspect | found/arrival/show/hide/removed/disposed/lost/after | 通过 |
| Source / Telemetry | Feature、Deep Link、匿名访客和 App Session | 通过 |
| Page lifecycle | Mixin 和 Listener 的 Show/Hide | 通过 |
| App lifecycle | macOS 最小化与恢复 | Background/Foreground 通过 |
| Page presentation | Material、Cupertino、Fade、Scale、Bottom Slide | 通过 |
| Transparent full-screen page | `opaque=false` 海报页 | 通过 |
| Managed Dialog / BottomSheet | typed result + RouteEntry | 通过 |
| Foreign Navigator / Popup | Navigator.push、Dialog、BottomSheet | 不误删 Managed Entry |
| Opaque UI | OverlayEntry、LocalHistory BottomSheet | 不污染 Managed 栈 |
| Session / Component Contract | 账号 Session、订单 Route/Service Contract | 通过 |
| Runtime diagnostics | RouteEntry、Backend Entry、Aspect Timeline | 通过 |
| Result / shutdown cleanup | Go、Reset、Runtime dispose 结束 pending result | 通过，无悬挂 Future |

## 已发现并修复

1. GoRouter 首页同时以 opaque snapshot 和 foreign observer event 记账，诊断中出现两个活跃 Entry。现在首次 Observer 回调会复用初始 snapshot identity。
2. 生成页面的 `RouteSettings.name` 是 routeId，Adapter 曾只按 resolved path 关联请求，导致 dynamic URI Pop 后 RouteEntry 残留。现已同时识别 routeId 与 path。
3. CCRouter `replace` 曾映射到 GoRouter `replace()`，后者复用 Page key 和 State，与 Route Scope 替换语义冲突。现改为 `pushReplacement()`，并由 Adapter 自有结果通道完成被替换页面的 Future，避免 GoRouter 14.8.1 遗留未完成 completer。
4. Failure fallback 默认 Replace 后不可 Pop，Demo 却使用内部 `open('/')` 返回，造成隐藏 Entry 残留。Demo 现显式使用 Push fallback，返回后为 `0 managed`。
5. GoRouter Adapter 在 Go、Reset 或 Runtime shutdown 时曾直接清空本地 Entry，导致已返回给业务的 typed result Future 永久等待，并残留 navigation/backend identity 映射。现在 Go/Reset 以 `null` 结束被移除页面的结果，shutdown 以 `CCNavigationAdapterError` 结束未完成结果，同时清理身份映射；动态 open 不创建对业务暴露的错误结果通道。
6. GoRouter 17 默认把 Shell 分支的 Navigator 事件转发给 root observers，曾导致同一个分支 Route 同时被标记为 root 和真实 Outlet。`CCGoRouterNavigationObserver` 现在忽略不属于其 Navigator 的转发事件，由对应 Outlet observer 保留唯一、准确的生命周期身份。
7. 双 Host Demo 启动时窗口宽度跨越布局断点，`Column`/`Row` 子树替换曾让 secondary Host 在旧 Owner 释放前被新 Owner 挂载。示例现保持同一 `Flex` 子树并只切换方向，回归测试会从窄屏扩到宽屏并检查 Flutter 异常。

## 已确认限制

1. `popAndPush`、`popUntil`、`pushAndRemoveUntil`、`removeRoute`、`removeRouteBelow` 和 `replaceRouteBelow` 已从业务 API、Runtime、Adapter SPI、Capability、内置 Adapter、Demo 与测试完整删除，不再以 capability error 或多步操作模拟。重新接入需先具备稳定 Entry identity、原子目标栈提交、混合栈隔离、PopGuard、失败回滚和结果/Scope 生命周期保证。
2. Predictive Back 不适用于 macOS 实测，已由 bridge 单测覆盖；最终仍需 Android 设备回归手势进度与取消。
3. Demo 已覆盖单 View 内的双 Host、Shell 和多 Outlet，但不等同于 macOS/iPadOS 原生多 Window 或多 Flutter Engine。原生 Window/Display 创建、销毁、恢复和 Host 迁移仍需平台接入后验证。
4. 完整 Route Restoration 按设计暂缓；当前只保留 restoration opportunity 诊断，不宣称可恢复业务栈。

## 官方 GoRouter 示例对照

本 Demo 不逐份复制 GoRouter 官方示例，而是验证后端中立的 CCRouter 等价语义。
完整映射、刻意不支持项和延后项见
[GoRouter 示例覆盖对照](go_router_example_coverage.md)。

## 回归命令

```sh
fvm dart analyze
fvm flutter test packages/ccrouter_test/test
fvm flutter test demo/test
fvm dart test packages/ccrouter_test/generator_test
fvm flutter build macos --debug
```

macOS 交互验证：

```sh
fvm flutter run -d macos
```
