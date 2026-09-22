# CCRouter Cupertino PopGuard 手势改造方案

## 1. 文档状态

- 状态：设计记录，暂不实施
- 范围：GoRouter/Flutter Adapter 中 Managed Cupertino Page 的交互式返回手势
- 不改变：Core `CCPopGuard` 契约、业务导航入口和当前安全回退行为

本文解决一个具体问题：Managed Cupertino Page 安装 `CCPopGuard` 后，如何在不绕过
Guard 的前提下尽量保留系统边缘右滑返回体验。

## 2. 当前行为

当前 Adapter 使用 Route 级 Pop gate，在系统返回、业务 `maybePop` 和交互式返回提交前
调用 Runtime 的同步 PopGuard。由于 Flutter 不能可靠地在交互式手势开始时等待一个异步
框架回调，受保护的 Cupertino Route 采用保守策略：

```text
Managed Route 没有 PopGuard -> 保留 Cupertino 默认右滑
Managed Route 存在 PopGuard -> 禁用右滑，业务/系统返回仍执行 Guard
Foreign Route、PopupRoute、LocalHistoryEntry -> 只影响自身，不关闭底层 Managed Route
```

该策略是有意的安全回退，不是错误行为。它保证 Guard 拒绝时不会出现页面已经开始退出、
但 Runtime 仍认为 RouteEntry 和 Scope 存活的状态分裂。

## 3. 目标行为

在 Flutter Route API 能够提供可靠的动态 Pop Gate 时，支持以下行为：

```text
开始右滑
    -> 解析精确的 Host / Outlet / Backend Entry
    -> 执行同步 CCPopGuard
    -> Allow：允许交互式 Pop 并完成一次 Runtime reconciliation
    -> Deny：不启动或取消手势，RouteEntry、Scope 和结果 Future 保持不变
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

Adapter 优先使用 Flutter 当前支持的 `PopScope`/`PopEntry` 等 Route 级能力，为每个 Managed
Route 维护同步 `canPop` 状态：

- `true`：允许 Flutter 启动交互式返回；
- `false`：阻止交互式返回；
- Route 被移除、替换、停用或 Adapter dispose 时，解除所有 Pop Gate 引用。

动态 Gate 必须由精确 Backend Entry identity 驱动，不能根据 Runtime 全局顶部 Entry 猜测。
Observer 仍只负责事实观察和关联，不能在手势已经提交后补做 veto。

### 4.3 能力探测与安全回退

动态手势能力属于 Adapter 内部能力，不要求业务配置。以下情况统一回退到当前行为：

- Flutter SDK 没有可靠的动态 Pop Gate API；
- Route 尚未完成 Managed Entry 关联；
- Host、Outlet 或 Backend Entry 无法精确确定；
- Guard 状态无法在手势开始前同步得到；
- Shell/StatefulShell 分支切换正在提交；
- Adapter 已进入 dispose 或 unbind 阶段。

回退行为是禁用该 Managed Route 的交互式侧滑，并记录有界的能力回退诊断；不能把 Dialog
降级为 Page，也不能静默关闭底层 Route Scope。

### 4.4 异步确认

`CCPopGuard` 不负责等待确认对话框。需要异步确认时采用：

```text
canPop = false
    -> 用户尝试右滑/系统返回
    -> Host/Adapter 的 UI 协调器展示确认 UI
    -> 用户确认
    -> 使用一次性 resume token 重新发起 CCRouter.pop
    -> 完成一次 Managed Pop 和结果交付
```

用户取消时不改变 RouteEntry、Scope 或 Push Future。resume token 必须防止确认后的主动 Pop
再次触发同一确认逻辑，也不能允许回调同步递归导航。

## 5. 不采用的方案

### 5.1 仅使用 NavigatorObserver 事后拦截

Observer 回调发生在 Route 状态变化之后，无法可靠阻止已经开始的交互式返回，不能作为 Guard
实现。

### 5.2 用 GoRouter `onExit` 替代 Core PopGuard

`onExit` 还会覆盖 Go、Replace 和其他 location 变化，无法表达“只拦截退出当前 Managed Route”
的统一语义，也不能复用到未来 Navigator Backend，因此不作为 Core 契约。

### 5.3 让每个业务页面自行接入 PopScope

这会引入页面样板、重复状态和生命周期泄漏风险，违反非侵入式与自动配置原则。业务页面不应
为了 CCRouter 手势兼容而修改自己的返回逻辑。

## 6. 实施步骤

1. 确认目标 Flutter SDK 中 `PopScope`/`PopEntry` 的动态行为、预测返回兼容性和 Cupertino
   交互式 Pop 时序。
2. 在 GoRouter Adapter 内提取 Managed Route Pop Gate SPI，保留当前禁用侧滑逻辑作为 fallback。
3. 将 Gate 与 Backend Entry identity、Host、Outlet 和 Route Scope 生命周期绑定。
4. 增加 `gesture` 触发来源和一次性 resume token，防止异步确认重复 Pop。
5. 增加能力回退诊断，区分动态 Gate 成功、主动禁用和 API 不支持。
6. 先在 Demo 开启内部实验开关，与当前保守模式做 A/B 回归；通过后再决定是否默认启用。
7. 只有在 Flutter SDK 和 GoRouter 的时序行为稳定后，才考虑移除实验开关。

## 7. 回归测试

至少覆盖：

1. 无 PopGuard 的 Cupertino Page 保留右滑。
2. Guard 允许时右滑成功，RouteEntry、Scope 和 Push Future 只完成一次。
3. Guard 拒绝时右滑不启动或被取消，页面和 Scope 保持存活。
4. Guard 异常时 fail closed，并产生稳定诊断。
5. 异步确认取消、确认和重复触发均不会重复 Pop。
6. Foreign Popup、Overlay 和 LocalHistoryEntry 覆盖时不影响底层 Managed Route。
7. Shell、StatefulShell、多 Outlet 和多 Host 使用正确的 Pop 目标。
8. 系统返回、预测返回、AppBar 返回和右滑的触发来源可区分。
9. Route 替换、组件停用、Host 注销和 Adapter dispose 后无残留 Pop Gate、Listener 或
   Route 引用。
10. 动态能力不可用时，行为与当前“有 Guard 禁用侧滑”完全一致。

## 8. 验收与退出条件

实现必须同时满足：

- 动态手势失败时安全回退，不改变现有业务语义；
- 不新增业务页面基类、Mixin、全局 `BuildContext` 或公开 Flutter Route API；
- 不影响 Foreign Route、第三方 Popup 和未绑定 Navigator；
- 不丢失 Pop 结果、Route Scope 或诊断终态；
- 通过 Core、GoRouter、Demo、生命周期和资源释放回归。

如果任一 Flutter SDK 版本无法在手势开始前可靠执行同步 Guard，则继续使用当前保守策略，
不为了保留动画而引入不确定的栈状态。
