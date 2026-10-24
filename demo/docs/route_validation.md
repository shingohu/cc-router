# CCRouter Demo 路由验证记录

> 历史记录：文中的 GoRouter 实现与验收对应原版本。2026-10-23 已移除兼容包；
> 当前原生 Managed 能力及回归以[退役记录](../../docs/validation/go_router_retirement_20261023.md)、API 和测试为准。
> 下表身份与恢复机会条目也属于历史验收；当前身份快照、恢复需求和布局策略归应用，
> 见[职责收口记录](../../docs/validation/20261023-framework-boundaries/README.md)。

当前 Managed 功能矩阵、后续修复及真实平台验收从[统一验证索引](../../docs/validation/README.md)
查阅。以下测试数和 macOS 结果保持原日期，不用新源码回归覆盖旧记录。

## 验证基线

- 日期：2026-09-20
- 平台：macOS 真实 Flutter 应用
- Backend：`CCGoRouterBackend.managed`，`go_router 17.5.0`
- SDK：FVM `ohos/oh-3.41.9-release`（Flutter 3.41.10 OHOS / Dart 3.11.5）
- macOS Host：首选启动 content 为 `800 × 800`、最小 content 为
  `480 × 640` logical points；实际尺寸和位置受当前显示器 `visibleFrame`
  限制，切换显示器后会重新计算有效约束
- 组件：4
- 生成路由：30

Demo 的交互实现位于 `modules/navigation_lab`，宿主只负责初始化 CCRouter、
安装生成组件清单并挂载 GoRouter Backend。

## 功能矩阵

| 能力 | Demo 场景 | macOS 结果 |
| --- | --- | --- |
| Typed Push / result | Detail Page | 通过 |
| Path alias / custom scheme / full URL | Detail Page 多 Pattern | 通过 |
| External Deep Link ingress | UI 模拟 + macOS `ccrouter://` Scheme | 通过，保留 external origin 与 source |
| Standard HTTPS Web Link | Host allowlist mapper -> public Web route | 通过，保留 external origin，拒绝非 allowlist URL |
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
| Shared WebView | public Query Codec + private Extra | 通过，私密 URL/Header 不进入 normalized URI |
| Multi Host | `CCGoRouterMultiHostBackend` 聚合 Primary / Secondary 双 Router | 通过，自动复用 Host Catalog，Host 路由状态相互隔离 |
| Host resize / orientation | 同一 `host.primary` 更新 `DemoHostLayoutMetrics` | 通过，Host ID 与路由所有权不变 |
| Fold / hinge | 模拟 separating `DemoDisplayFeature` | 通过，不创建 Host，只切换活动 Outlet |
| Adaptive list-detail | compact 单 Outlet / expanded 双 Outlet | 通过，`adaptive.list` 与 `adaptive.detail` 属于同一 Host |
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
| Semantic / Accessibility Monkey | 360 步 Widget 随机回归 + 120 步真实 macOS 操作 | 通过，累计修复 4 类 Demo 小窗口布局问题 |

## 已发现并修复

1. GoRouter 首页同时以 opaque snapshot 和 foreign observer event 记账，诊断中出现两个活跃 Entry。现在首次 Observer 回调会复用初始 snapshot identity。
2. 生成页面的 `RouteSettings.name` 是 routeId，Adapter 曾只按 resolved path 关联请求，导致 dynamic URI Pop 后 RouteEntry 残留。现已同时识别 routeId 与 path。
3. CCRouter `replace` 曾映射到 GoRouter `replace()`，后者复用 Page key 和 State，与 Route Scope 替换语义冲突。现改为 `pushReplacement()`，并由 Adapter 自有结果通道完成被替换页面的 Future，避免 GoRouter 14.8.1 遗留未完成 completer。
4. Failure fallback 默认 Replace 后不可 Pop，Demo 却使用内部 `open('/')` 返回，造成隐藏 Entry 残留。Demo 现显式使用 Push fallback，返回后为 `0 managed`。
5. GoRouter Adapter 在 Go、Reset 或 Runtime shutdown 时曾直接清空本地 Entry，导致已返回给业务的 typed result Future 永久等待，并残留 navigation/backend identity 映射。现在 Go/Reset 以 `null` 结束被移除页面的结果，shutdown 以 `CCNavigationAdapterError` 结束未完成结果，同时清理身份映射；动态 open 不创建对业务暴露的错误结果通道。
6. GoRouter 17 默认把 Shell 分支的 Navigator 事件转发给 root observers，曾导致同一个分支 Route 同时被标记为 root 和真实 Outlet。`CCGoRouterNavigationObserver` 现在忽略不属于其 Navigator 的转发事件，由对应 Outlet observer 保留唯一、准确的生命周期身份。
7. 双 Host Demo 曾在默认 macOS 窗口高度下使用上下布局，导致两个嵌入 App 的底部各溢出 16px；直接在断点切换不同布局子树又会让 secondary Host 在旧 Owner 释放前被新 Owner 挂载。示例现始终保持同一 `SingleChildScrollView -> SizedBox -> Row` 子树，窄窗口只增加横向滚动；回归测试使用接近真实默认窗口的尺寸并跨越宽度断点检查溢出和重复挂载异常。
8. macOS Monkey 将窗口缩小到约 490x350 logical pixels 后，PopGuard 页面底部溢出 33px。页面现使用安全区和可滚动约束，并增加 DPR 2 小窗口定向测试。
9. 同一轮 Monkey 打开 Failure fallback 时底部溢出 45px。兜底页已采用相同的自适应布局，并验证所有诊断字段和返回按钮仍可访问。
10. Demo 部分 fire-and-forget 导航未消费 Push Future，Runtime shutdown 正确终止 pending result 时会暴露未处理的 `CCNavigationAdapterError`。示例现通过统一观察 helper 消费结果并记录失败类型，框架仍保留明确的 shutdown 错误语义。
11. 双 Host 的嵌入式首页在宽而低的窗口中会压缩 `NavigationRail`，自适应示例在极窄窗口强制模拟 hinge 时也会把 List/Detail Pane 压到不可用宽度。Rail 现可纵向滚动；双 Pane 保留 `600` logical points 的最小内容宽度并允许横向滚动，列表和详情自身也支持紧凑布局与纵向滚动。对应低高度和 DPR 2 窄 Host 用例已加入回归。
12. macOS Runner 不再把固定 frame 高度作为窗口下限。它使用 `contentMinSize` 表达 `480 × 640` 的 Flutter 内容需求，以 `800 × 800` 作为首选启动 content，并按当前显示器 `visibleFrame` 限制尺寸和位置；显示器切换时会重新计算有效约束并释放 Notification observer。
13. 双 Host 页面内部导航曾继续使用默认 active Host，导致在 Secondary 页面点击路由却更新 Primary。Host 组装层现于 Pointer/Focus 进入每个 Router surface 时先激活对应 Host；回归测试按 Pane 子树验证双向 Push、并存 RouteEntry、typed result Pop 和精确清理，不再仅凭全局文本判断隔离成功。

完整的随机动作、状态不变量、问题归因和未覆盖边界见
[macOS Monkey 验证记录](macos_monkey_validation.md)。

## 已确认限制

1. `popAndPush`、`popUntil`、`pushAndRemoveUntil`、`removeRoute`、`removeRouteBelow` 和 `replaceRouteBelow` 已从业务 API、Runtime、Adapter SPI、Capability、内置 Adapter、Demo 与测试完整删除，不再以 capability error 或多步操作模拟。重新接入需先具备稳定 Entry identity、原子目标栈提交、混合栈隔离、PopGuard、失败回滚和结果/Scope 生命周期保证。
2. Predictive Back 不适用于 macOS 实测，已由 bridge 单测覆盖；最终仍需 Android 设备回归手势进度与取消。
3. Demo 已覆盖单 View 内的双 Host、窗口缩放/方向变化、模拟 hinge、list-detail、Shell 和多 Outlet，但不等同于 macOS/iPadOS 原生多 Window 或多 Flutter Engine。原生 Window/Display 创建、销毁、恢复和 Host 迁移仍需平台接入后验证。
4. 完整 Route Restoration 按设计暂缓；当前只保留 restoration opportunity 诊断，不宣称可恢复业务栈。
5. 标准 HTTPS Universal Link 的系统唤醒依赖应用 entitlement、Associated Domains 与服务端 AASA；Demo 只实测 Host mapper 和 WebView，不能用不受控制的公共域名伪造系统关联。
6. 私密 Web 示例的自定义 Header 只用于初始请求；生产认证仍需设计 Cookie/会话桥接、登出清理和多账号隔离，不能假设 Header 自动跨重定向持续注入。
7. macOS 输入日志中偶发的 `HardwareKeyboard` 重复 `KeyDownEvent` assertion 属于 Flutter SDK 与平台键盘状态同步问题，不是 CCRouter 导航或窗口布局错误。Demo 不捕获或吞掉该断言；升级 Flutter 后需要重新验证。

## 官方 GoRouter 示例对照

本 Demo 不逐份复制 GoRouter 官方示例，而是验证后端中立的 CCRouter 等价语义。
完整映射、刻意不支持项和延后项见
[GoRouter 示例覆盖对照](go_router_example_coverage.md)。

## 回归命令

```sh
fvm dart analyze
fvm flutter test packages/ccrouter_test/test
fvm flutter test demo/test
fvm flutter test demo/test/monkey_test.dart
fvm dart test packages/ccrouter_test/generator_test
fvm flutter build macos --debug
```

macOS 交互验证：

```sh
fvm flutter run -d macos
```
