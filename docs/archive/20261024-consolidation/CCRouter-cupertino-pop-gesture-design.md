> 归档日期：2026-10-24。原路径：`docs/CCRouter-cupertino-pop-gesture-design.md`。
> 此文件保存文档合并前的设计/实施快照；相对链接已重定位，正文中的旧 API、阶段状态与测试数字不代表当前能力。
> 现行入口与合并映射见[归档索引](README.md)。

# CCRouter Cupertino PopGuard 手势改造方案

## 1. 文档状态

- 状态：原生 Managed Backend 已实施；iOS 真机证据为注明日期的历史快照，GoRouter 兼容层已移除
- 范围：原生 Managed Backend 中默认不透明 iOS Page 的交互式返回手势
- 不改变：Core `CCPopGuard` 契约、业务导航入口和不支持场景的安全回退行为

本文解决一个具体问题：Managed Cupertino Page 安装 `CCPopGuard` 后，如何在不绕过
Guard 的前提下尽量保留系统边缘右滑返回体验。

## 2. 当前行为

Adapter 使用 Flutter `PopEntry` 在受保护页面上建立 Route 级 Pop gate。原生 Managed
Backend 拥有 Page/Route 的创建过程，因此可以在 Flutter 查询 `Route.popGestureEnabled`
时同步执行 Runtime Guard，并只为同一个当前 Route 临时打开 gate：

```text
Managed Route 没有 PopGuard -> 保留 Cupertino 默认右滑
Managed Route 存在 PopGuard，Guard deny -> 不启动右滑动画
Managed Route 存在 PopGuard，Guard allow -> 保留 Flutter 跟手动画并只提交一次 Pop
Foreign Route、PopupRoute、LocalHistoryEntry -> 只影响自身，不关闭底层 Managed Route
```

取消、Flutter 未真正启动手势、Route 移除、Guard unbind 和 Backend dispose 都会关闭或释放
临时 gate。自定义转场、Modal 和无法精确关联的 Route 采用
非交互安全回退，保证不能出现页面已经开始退出但 Runtime 仍保留 RouteEntry/Scope 的分裂。

## 3. 目标行为

当前第一阶段已确认并实现以下行为：

```text
系统返回/业务 maybePop
    -> 解析精确的 Host / Outlet / Backend Entry
    -> 执行同步 CCPopGuard
    -> Allow：业务 maybePop 临时打开 PopEntry 并完成一次 Runtime reconciliation；
             系统返回只临时打开精确 Route 自身门闩，重新检查完整 popDisposition，
             仅为 pop 时同步提交 Navigator Pop；本地 PopScope/Form 仍可拒绝
    -> Deny：RouteEntry、Scope 和结果 Future 保持不变

原生 Managed 默认不透明 iOS 页面在 Flutter 手势 eligibility 查询中同步执行 Guard。Allow
只打开精确 Route 的 `PopEntry`，随后由 Flutter 唯一驱动动画与 Pop；Deny 保持 gate 关闭且
页面不动。无 PopGuard 页面不注册 PopEntry，因此保留 Flutter/平台默认手势。
`CCPagePresentation` 未显式指定 `CCPageRouteType` 时仍使用 `platformDefault`，由 Host/Adapter
选择 Material 或 Cupertino 默认行为。
```

优化只针对 CCRouter 自己拥有的 Managed Cupertino Page，不把 Foreign Popup、Overlay、
`LocalHistoryEntry` 或第三方 Navigator 纳入 CCRouter 的生命周期管理。

## 4. 分层方案

### 4.1 Core 保持不变

- `CCPopGuard` 继续是同步、Adapter-neutral 的退出决策。
- `CCPopGuardContext` 使用实际退出的 Route Snapshot、Host、Outlet 和触发来源。
- `CCPopTrigger` 应区分 `gesture`、`system` 和 `predictiveBack`，不能把所有返回都记为
  `system`。
- Guard 异常继续 fail closed，不能因为手势路径而放宽安全策略。

### 4.2 Adapter 动态 Pop Gate

Adapter 使用 Flutter 当前支持的 `PopEntry` Route 级能力，为每个受保护 Managed Route
维护同步 `canPop` 状态：

- `true`：允许 Flutter 启动交互式返回；
- `false`：阻止交互式返回；
- Route 被移除、替换、停用或 Adapter dispose 时，解除所有 Pop Gate 引用。

Gate 只对 Runtime 传入 `hasPopGuard` 的受保护路由安装，并由精确 Backend Entry identity
关联，不能根据 Runtime 全局顶部 Entry 猜测。该标记不暴露 Guard ID 或可变 Runtime 状态。
Observer 仍只负责事实观察和关联，不能在手势已经提交后补做 veto。

### 4.3 能力探测与安全回退

动态手势能力属于 Adapter 内部能力，不要求业务配置。以下情况统一回退到保守行为：

- 自定义 Backend 不拥有对应 Page/Route 的创建过程；
- Route 尚未完成 Managed Entry 关联；
- Host、Outlet 或 Backend Entry 无法精确确定；
- Guard 状态无法在手势开始前同步得到；
- Shell/StatefulShell 分支切换正在提交；
- Adapter 已进入 dispose 或 unbind 阶段。

回退行为是禁用该 Managed Route 的交互式侧滑，并记录有界的能力回退诊断；不能把 Dialog
降级为 Page，也不能静默关闭底层 Route Scope。

### 4.4 异步确认

`CCPopGuard` 只做同步只读判断，不负责等待或展示确认对话框。异步确认由页面自己的 Flutter
`PopScope` / `Form` 或显式“离开”操作管理；框架没有公开 UI 协调器或 resume-token API。
能收到本地返回拒绝回调的路径可采用：

```text
页面本地 canPop = false
    -> 收到本地返回拒绝回调，或用户点击显式离开按钮
    -> 页面合并重复请求，展示一次确认 UI
    -> 用户确认
    -> 更新业务允许退出的状态，调用 CCRouter.navigator.pop（使用页面 Context）
    -> 完成一次 Managed Pop 和结果交付
```

用户取消时不改变 RouteEntry、Scope 或 Push Future。确认期间页面应合并重复请求；完成后
确认页面仍 mounted，显式 Pop 仍遵守原有同步 PopGuard，不能用确认结果绕过其它 Guard。
确认 UI 和导航不得放在 Guard 回调中。

iOS 的 `canPop: false` 会禁用边缘侧滑，用户滑动时可能根本没有拒绝回调，因此不能承诺
“拦截右滑后自动弹确认框”。需要提供显式离开/保存入口；允许退出后才恢复交互式手势。

## 5. 不采用的方案

### 5.1 仅使用 NavigatorObserver 事后拦截

Observer 回调发生在 Route 状态变化之后，无法可靠阻止已经开始的交互式返回，不能作为 Guard
实现。

### 5.2 用 GoRouter `onExit` 替代 Core PopGuard

`onExit` 还会覆盖 Go、Replace 和其他 location 变化，无法表达“只拦截退出当前 Managed Route”
的统一语义，也不能表达当前 backend-neutral 契约。此项为历史方案取舍，GoRouter 接入已移除。

### 5.3 让每个业务页面自行接入 PopScope

不要求每个业务页面为了框架 Guard 的手势兼容重复接线，框架自动管理对应 gate。
这不排除第 4.4 节的业务异步确认：页面拥有该 UI 和本地状态时，可以使用 PopScope。

## 6. 实施步骤

1. 原生 Managed Adapter 使用 `PopEntry` 保护 guarded Route。
2. 原生 Managed Adapter 将 Gate 与 `hasPopGuard`、精确 Route、Host/Outlet 和 Route 生命周期绑定。
3. 原生 Managed 默认不透明 iOS Route 在 `popGestureEnabled` 查询时同步求值并临时打开 gate。
4. 未开始的 eligibility、取消、提交、Route unmount、Guard unbind 和 Backend dispose 均会复位或释放 gate。
5. GoRouter 兼容层已退役；不再维护其 Route 子类或手势 fallback。

2026-10-03 修复补充：初始 Flutter `maybePop` 已执行 legacy willPop 判断。系统返回的
框架 Gate 放行后，保持同步并检查同一 Route 的全部 Flutter PopEntry，而不二次调用
异步 `maybePop`。这样避免重复调用业务 willPop，也避免临时放开的 Gate 跨 await 被另一个
返回请求使用。若当前 Route、Navigator 或 Gate identity 已变化，停止该次提交。`finally`
只恢复仍存活的同一门闩；不放开其它 Host/Outlet 的门闩。

## 7. 回归测试

至少覆盖：

1. 无 PopGuard 的 Cupertino Page 不注册 PopEntry，保留平台默认右滑。
2. Guard 允许时业务/系统返回只完成一次，RouteEntry、Scope 和 Push Future 一致。
3. Guard 拒绝时系统返回不移除页面，受保护页右滑不启动动画。
4. Guard 异常时 fail closed，并产生稳定诊断。
5. 异步确认取消、确认和重复触发均不会重复 Pop。
6. Foreign Popup、Overlay 和 LocalHistoryEntry 覆盖时不影响底层 Managed Route。
7. Shell、StatefulShell、多 Outlet 和多 Host 使用正确的 Pop 目标。
8. 系统返回、预测返回、AppBar 返回和右滑的触发来源可区分。
9. Route 替换、Host 注销和 Adapter dispose 后无残留 Pop Gate、Listener 或
   Route 引用。
10. 动态能力不可用时，保持“有 Guard 禁用侧滑”的安全 fallback。
11. 框架 allow/deny 与本地 PopScope/Form allow/deny 组合、拒绝回调打开 Foreign Popup、
    legacy willPop 调用次数和 typed result 完成次数均保持确定性。

## 8. 验收与退出条件

实现必须同时满足：

- 动态手势失败时安全回退，不改变现有业务语义；
- 不新增业务页面基类、Mixin、全局 `BuildContext` 或公开 Flutter Route API；
- 不影响 Foreign Route、第三方 Popup 和未绑定 Navigator；
- 不丢失 Pop 结果、Route Scope 或诊断终态；
- 通过 Core、Managed Demo、生命周期和资源释放回归。

如果任一 Flutter SDK/Backend 无法在手势开始前可靠执行同步 Guard，则继续使用保守策略，
不为了保留动画而引入不确定的栈状态。[2026-10-22 平台记录](../../validation/managed_navigation_platform_acceptance_20261022.md)
记录 Flutter 3.41.10-ohos-1.0.0 在 iPhone 13 / iOS 15.6.1 上的原生 Managed deny 不动、
allow 跟手、取消不清理和提交只清理一次。后续自动回归不能代替该设备的新版本真机复验；
最新源码与平台证据按[验证索引](../../validation/README.md)分别查阅。
