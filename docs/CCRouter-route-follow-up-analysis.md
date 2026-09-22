# CCRouter 路由专项问题分析

## 1. 范围与结论

- 分析日期：2026-09-20
- 范围：Demo PopGuard、Flutter/GoRouter 返回链路、导航失败分类，以及 Framework/Generator
  的异步方法。
- 本文只记录事实、候选方案和实施顺序，不改变当前代码行为或公开 API。

结论：

1. GoRouter Adapter 已为可识别的 Managed Route 安装 Route 级 Pop gate，系统返回和
   `routerDelegate.popRoute()` 会先经过 Runtime PopGuard；受保护的 Cupertino 页面会被
   Flutter 禁止侧滑，以避免手势绕过 Guard。Predictive Back 通过显式 Host bridge 接入。
   这部分已有回归覆盖；未来若要保留“Guard 允许时仍可侧滑”，需要 Flutter Route 层的可变
   `popDisposition` 方案，不能靠 Observer 事后拦截。
2. `CCNavigationFailureStage.resolution` 已保留，并已增加 `CCNavigationFailureReason`、
   `initialRouteId` 和恢复深度，Policy 可以稳定区分 route-not-found、Deep Link 拒绝、参数
   错误、拦截器超时和 Adapter 失败。后续只需继续补充原因映射和 Demo 策略回归，不再新增
   一套 Stage 枚举。
3. 当前主要异步 API 都有真实异步原因。只有少量实现级 `async` 可以机械去除，但公开契约仍须
   返回 Future，收益很低，不建议为此扩大 API 或制造同步/异步两套入口。

## 2. PopGuard 与系统手势返回

### 2.1 当前行为的根因

Demo 的 AppBar 返回按钮调用 `CCRouter.navigator.maybePopOutcome`，系统返回则由 GoRouter/Flutter
Navigator 驱动。当前 Adapter 在 Managed Route 被识别后安装 Route 级 Pop gate：系统返回会先
执行 Runtime Guard；Cupertino Route 因存在 gate 会关闭交互侧滑，避免手势绕过 Guard；预测返回
由显式 Predictive Back bridge 在提交前执行同一 evaluator。Foreign Route、PopupRoute 和
LocalHistoryEntry 不会触发 Managed Guard。

### 2.2 是否属于预期行为

当前实现已解决“系统返回直接绕过 Managed PopGuard”的主要问题。代价是受保护的 Cupertino
页面无法保留交互侧滑，即使 Guard 当前会允许 Pop；这是 Flutter Route 层动态
`popDisposition` 能力的优化候选，不应通过 Observer 事后拦截伪造。

### 2.3 候选方案

| 方案 | 优点 | 缺点与风险 | 结论 |
| --- | --- | --- | --- |
| Demo 页面自行增加 `PopScope` | 工作量小，可立即阻止演示页面侧滑 | 每个业务页面都要记住接入；与“非侵入式”和注解自动配置冲突；只能掩盖框架缺口 | 不作为正式方案 |
| GoRouter `onExit` 对接 PopGuard | 接近 GoRouter 声明式退出边界；可以覆盖一部分系统返回和 location 变化 | 后端专用；`onExit` 还会覆盖 Go/Replace 等非 Pop 离开，需要重新定义 Guard 语义；不能自然复用到 Navigator 1.0/2.0 Adapter | 可作为 GoRouter 实验路径，不作为 Core 契约 |
| 在 Adapter/Assembler 创建的 Flutter Route 上安装统一 Pop Gate | Managed Route 身份明确；可以在 Navigator 真正提交 Pop 前决策；业务页面无感；便于复用到未来 Navigator Adapter | 受保护 Cupertino Route 会禁用交互侧滑；若要动态恢复侧滑需 Flutter Route 层支持可变 `popDisposition` | 当前实现 |

推荐的正式方案是 Backend-neutral 的内部 Pop Gate 语义，由 Flutter Adapter 在 Route/PopEntry 边界
实现，不把 `BuildContext`、`Route` 或 `PopScope` 暴露给 Core 和业务。`NavigatorObserver` 继续只负责
观察与 Entry 关联，不能承担 veto。

### 2.4 实施约束

- 只有能够精确识别的 Managed 顶部 Entry 才运行 Guard；Foreign、Opaque、Popup 和
  `LocalHistoryEntry` 继续绕过底层 Managed Guard。
- Guard 拒绝后，RouteEntry、Route Scope、Push result Future 和 Backend Entry 必须保持不变。
- Guard 允许后只提交一次 Pop，不能因回调触发二次 Pop 或重复完成结果。
- 普通系统返回、Cupertino 手势、Android Back 和 Predictive Back 的触发类型必须保持可诊断。
- 同步 `CCPopGuard` 不负责显示确认对话框；异步确认仍使用明确的 UI 流程，确认后重新发起 Pop。
- 多 Host/Outlet 必须使用即将退出的实际分区，不能回退到 Runtime 全局顶部猜测。

现有回归覆盖 AppBar/Runtime Pop、系统 Back、Foreign Route、LocalHistory 和 Predictive Back
提交语义。Cupertino 交互侧滑的当前契约是：存在 Managed Guard 时不允许启动，以保证不会
绕过 Guard；后续若 Flutter 提供安全的可变 `popDisposition`，再单独补充“允许时保留侧滑”的测试。

## 3. Navigation Failure 分类

### 3.1 当前问题

`CCNavigationFailureStage` 当前表达管线阶段：

- `resolution`
- `parameters`
- `interception`
- `dispatch`
- `result`
- `unknown`

其中 `resolution` 同时包含：

- URI 没有匹配路由；
- 多条路由具有相同优先级和 specificity；
- 路由已注册但组件或 Shell 当前不可用；
- 外部 URI 在匹配前被 Host Ingress Policy 拒绝；
- URI 已匹配，但该路由禁止外部 Deep Link。

Demo 的 `DemoNavigationFailurePolicy` 现在只对 `reason == routeNotFound` 进入兜底页；其它
resolution 原因默认传播。业务如果改为判断 `errorType` 字符串，又会依赖实现类名，不是稳定
类型安全契约。

Failure Context 现在同时保留 `initialRouteId`、当前 `routeId`、`recoveryDepth` 和
`CCNavigationFailureAttempt`，可以区分原始请求、拦截器重定向、Failure Policy 恢复和 pending
resume。动态 URI 未匹配时仍不存在可安全公开的目标 Route ID。

### 3.2 是否需要细分 Stage

不建议删除 `resolution`，也不建议把每个错误都升级为新的 Stage。Stage 用于回答“失败发生在导航
管线哪一段”，适合耗时、故障率和粗粒度 Policy；路由未找到、歧义和 Deep Link 拒绝仍然发生在
同一个解析阶段。

当前已增加与 Stage 正交的稳定枚举 `CCNavigationFailureReason`：

| Stage | 建议 Reason |
| --- | --- |
| `resolution` | `routeNotFound`、`routeAmbiguous`、`routeUnavailable`、`deepLinkIngressRejected`、`deepLinkRouteRejected` |
| `parameters` | `invalidParameters` |
| `interception` | `cancelled`、`redirectLoop`、`interceptorFailed`、`interceptorTimedOut` |
| `dispatch` | `adapterFailure` |
| `result` | `resultTypeMismatch` |
| `unknown` | `unknown` |

不要把原始异常对象或 message 放入 Failure Context。Ingress 的细分原因已经是安全枚举，可以通过
受限字段或二级枚举表达；URI、Path/Query、Arguments、Extra 仍不得进入 Policy 和 retained event。

### 3.3 目标身份与恢复链

Attempt 字段用于描述失败尝试来源：

- `request`：原始 typed Intent 或 dynamic URI；
- `interceptorRedirect`：拦截器选择的新目标；
- `failureRecovery`：Failure Policy 的 Redirect/Fallback 目标；
- `pendingResume`：恢复 Deferred Navigation 时重新解析。

Context 使用 `initialRouteId` 与 `routeId` 区分原始和当前目标。只有已知且经过标识校验的 Route ID
才会写入；未匹配 dynamic URI 的当前 Route ID 保持 null。`recoveryDepth` 继续表达 Failure
Policy 链，Attempt 则表达当前失败来源，不能混用。

推荐 Policy 写法最终应是：

```dart
if (context.reason == CCNavigationFailureReason.routeNotFound) {
  return CCNavigationFailureFallback.toIntent(notFoundIntent);
}
return const CCNavigationFailurePropagate();
```

### 3.4 兼容与实施顺序

1. 现有错误类型必须继续保持穷尽的 Stage + Reason 映射；未知第三方错误只能映射为 `unknown`。
2. 已覆盖原请求、拦截器重定向、Policy 恢复和 Pending Resume 四类 Attempt 回归。
3. `errorType` 仅用于诊断，不作为 Policy 分支契约。
4. Demo 只对 `routeNotFound` 进入 404/Fallback，其它 resolution failure 默认传播或使用独立安全页。
5. 新增错误类型时同步更新 Stage、Reason 和 Attempt 映射及测试。

该项的核心契约已落地。后续只需在新增错误类型时同步更新 Stage/Reason 映射和回归测试，避免
业务形成基于 `errorType` 字符串的事实契约。

## 4. 异步方法审计

### 4.1 必须保持异步的契约

| 能力 | 保持异步的原因 |
| --- | --- |
| `push` / `replace` | Future 表示页面最终 Pop 结果，生命周期天然跨事件循环 |
| `maybePop` / `maybePopOutcome` | Flutter `Navigator.maybePop` 会等待 Route/PopScope 决策，Adapter 不能假设同步 |
| `go` / `reset` / `open` | 共享异步 Interceptor、Failure Policy、Adapter 和观察终态管线 |
| `resumePendingNavigation` | 必须重新执行解析、异步拦截和 Adapter dispatch |
| Interceptor / Failure Policy | `FutureOr` 同时支持本地同步策略和登录、权限、远端配置等异步策略 |
| Command / Query / Action / Event | Handler 可异步，并支持 timeout、cancellation、并发 subscriber |
| `closeSession` / Runtime `dispose` / Scope `close` | 必须等待 `CCDisposable`、Route Scope、Adapter/Backend 的有序释放 |
| Generator Builder 与 Package 扫描 | Analyzer、BuildStep 和文件 I/O 本身异步 |

将这些 API 改成同步会丢失等待语义、改变错误从 Future 到同步 throw 的时机，或迫使业务使用
未受控的 fire-and-forget，不符合明确生命周期和可测试原则。

### 4.2 已正确同步的边界

以下能力已经在成功返回时完成全部状态变更，应继续保持同步：

- `CCRouter.initialize` 和 Runtime `initialize`；
- Adapter attach、`initialize`、`dispose`；
- 组件注册以及 Route/Shell `activateComponent` / `deactivateComponent`；
- `openSession`；
- `canPop`、直接 `pop` / `popOutcome`；
- Registry 校验、Service 解析和只读诊断快照。

这组 API 不应因为周边 shutdown 或导航是异步就重新改回 Future。

### 4.3 仅可做机械清理的方法

下列实现可以去掉 `async` 关键字或改成 Future 链，但公开类型仍然是 Future：

- `CCGoRouterBackend.dispose`：当前只执行同步 `router.dispose()`；
- `CCMemoryNavigationAdapter.maybePopOutcome`：内存栈操作本身同步；
- Memory/GoRouter/MultiHost 的 `maybePop` 包装方法：只等待并提取 `outcome.handled`；
- 少量只做 `await backend.dispose()` 的私有转发函数。

这些调整最多减少一个状态机或一层包装，不会减少调用方的 `await`，也不会改变框架能力。它们不应
单独触发公开 API 变更，建议只在相关文件后续修改时顺手清理并保持错误时序测试。

### 4.4 不建议同步化的疑似候选

- `CCRouterAppBackend.dispose`：内置 GoRouter Backend 当前同步释放，但 SPI 必须允许未来 Backend
  等待平台或插件资源；统一 Future 比 `void/FutureOr` 两套处理更清晰。
- `CCDisposable.dispose`：保留 `FutureOr<void>`，这是 Scope 同时接纳同步和异步资源的必要边界。
- `CCNavigationAdapter.navigate`：Go/Reset 当前可能立即完成，但 Push/Replace 共享同一 SPI 并携带
  页面结果；拆分同步命令会增加 Adapter 面积和状态竞争。
- `maybePopOutcome`：即使 Memory Adapter 可同步，真实 Flutter Navigator 仍可能异步决定。

### 4.5 建议结论

本轮不建议实施公开 API 的异步收口。后续只做两类工作：

1. 通过 lint 或审查清理实现级“`async` 但无 `await`”，不改变方法返回类型；
2. 新增 API 时先判断是否存在真实等待点，没有等待点的初始化、注册、状态切换和销毁入口默认同步，
   只有跨页面结果、用户决策、I/O 或异步资源释放才返回 Future。

## 5. 推荐执行顺序

1. **已完成：Managed Route 的系统返回 PopGuard 前置门禁**，回归覆盖系统返回、Foreign Route、
   LocalHistory 和拒绝后 pending result 保持。
2. **已完成：Failure Reason 与失败目标身份**，后续按新增错误类型补映射测试；Demo 应只对
   `routeNotFound` 做 404/Fallback。
3. **P3：异步实现机械清理**，仅在相关文件再次修改时执行，不单独立项、不改变公开契约。

PopGuard 和 Failure Reason 已在代码与专项测试中完成；异步机械清理仍按相关文件修改时顺手处理。
