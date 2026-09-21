# CCRouter 路由专项问题分析

## 1. 范围与结论

- 分析日期：2026-09-20
- 范围：Demo PopGuard、Flutter/GoRouter 返回链路、导航失败分类，以及 Framework/Generator
  的异步方法。
- 本文只记录事实、候选方案和实施顺序，不改变当前代码行为或公开 API。

结论：

1. Demo 的 PopGuard 页面可通过系统手势返回，符合当前实现，但不符合框架文档宣称的完整
   PopGuard 语义。这是框架与 GoRouter/Flutter Route 集成缺口，不能只由 Demo 修补。
2. `CCNavigationFailureStage.resolution` 应保留，它表示失败所在的管线阶段；当前真正缺少的是
   可供 Policy 稳定分支的失败原因，以及“原请求、拦截器重定向、Failure Policy 恢复”目标身份。
3. 当前主要异步 API 都有真实异步原因。只有少量实现级 `async` 可以机械去除，但公开契约仍须
   返回 Future，收益很低，不建议为此扩大 API 或制造同步/异步两套入口。

## 2. PopGuard 与系统手势返回

### 2.1 当前行为的根因

Demo 的 AppBar 返回按钮调用 `CCRouter.navigator.maybePopOutcome`，因此会先进入 Runtime 的
Global/Route PopGuard 管线。系统返回和 Cupertino 侧滑手势则由 Flutter `Navigator` 直接驱动：

1. `DemoGuardedPage` 没有 `PopScope` 或其它 Flutter Route 级退出门禁；
2. 当前 `CCGoRouterNavigationObserver` 只处理 `didPop`、`didChangeTop` 等已提交的变化；即使后续
   覆写 `NavigatorObserver.didStartUserGesture`，该回调也只能观察已经开始的手势，不能否决它；
3. `CCGoRouterAdapter.bindPopGuardEvaluator` 当前只把 evaluator 交给可选的 Predictive Back Bridge，
   普通系统返回和 Cupertino 手势没有对应的前置桥；
4. 系统手势完成后，Observer 会正确同步 Backend Entry 与 Runtime RouteEntry，但此时 Guard 已经
   没有机会拒绝 Pop。

因此当前表现是“生命周期同步正确，但退出策略被绕过”。它不是第三方 Foreign Route 的兼容问题，
因为被移除的正是 CCRouter Managed Route。

### 2.2 是否属于预期行为

从当前代码看，这是可以解释的既有行为；从公开语义和现有设计文档看，它不是可接受的最终行为。
Route 注解已经声明 `popGuards`，框架文档也承诺业务 Pop、系统返回和普通手势进入统一 Guard 管线。
如果系统手势可以绕过 Guard，则相同页面会因返回入口不同而得到不同结果，未保存表单和强制流程
都可能被意外关闭。

该问题建议定为 **P1 语义缺口**：不会直接导致崩溃，但破坏明确的退出保护契约。

### 2.3 候选方案

| 方案 | 优点 | 缺点与风险 | 结论 |
| --- | --- | --- | --- |
| Demo 页面自行增加 `PopScope` | 工作量小，可立即阻止演示页面侧滑 | 每个业务页面都要记住接入；与“非侵入式”和注解自动配置冲突；只能掩盖框架缺口 | 不作为正式方案 |
| GoRouter `onExit` 对接 PopGuard | 接近 GoRouter 声明式退出边界；可以覆盖一部分系统返回和 location 变化 | 后端专用；`onExit` 还会覆盖 Go/Replace 等非 Pop 离开，需要重新定义 Guard 语义；不能自然复用到 Navigator 1.0/2.0 Adapter | 可作为 GoRouter 实验路径，不作为 Core 契约 |
| 在 Adapter/Assembler 创建的 Flutter Route 上安装统一 Pop Gate | Managed Route 身份明确；可以在 Navigator 真正提交 Pop 前决策；业务页面无感；便于复用到未来 Navigator Adapter | 必须正确处理 Cupertino 手势、Android Back、Predictive Back、允许后的二次 Pop、防重入和 Widget 更新；实现成本最高 | 推荐方向 |

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

实施前应先增加失败回归：脏表单分别通过 AppBar、系统 Back、Cupertino 手势和 Predictive Back
返回时均保持页面；保存后四种入口均只能移除同一个 Managed Entry。实现完成后再修正当前
“普通手势已经统一进入 Guard”的设计文档表述。

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

Demo 的 `DemoNavigationFailurePolicy` 仅判断 `stage == resolution`，因此上述场景都会打开同一个
Failure 页面。业务如果改为判断 `errorType` 字符串，又会依赖实现类名，不是稳定类型安全契约。

拦截器重定向还存在第二层精度问题：重定向目标解析失败时，Failure Context 可能仍保留原始已解析
Route ID；`recoveryDepth` 只表示 Failure Policy 的恢复次数，无法说明失败发生在原请求、拦截器
重定向目标还是 Failure Policy 恢复目标。动态 URI 未匹配时也不存在可安全公开的目标 Route ID。

### 3.2 是否需要细分 Stage

不建议删除 `resolution`，也不建议把每个错误都升级为新的 Stage。Stage 用于回答“失败发生在导航
管线哪一段”，适合耗时、故障率和粗粒度 Policy；路由未找到、歧义和 Deep Link 拒绝仍然发生在
同一个解析阶段。

建议增加与 Stage 正交的稳定枚举，例如 `CCNavigationFailureReason`：

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

仅增加 Reason 可以解决“只对 routeNotFound 兜底”，但不足以完整描述重定向链。建议同时记录一个
稳定的失败尝试来源：

- `request`：原始 typed Intent 或 dynamic URI；
- `interceptorRedirect`：拦截器选择的新目标；
- `failureRecovery`：Failure Policy 的 Redirect/Fallback 目标；
- `pendingResume`：恢复 Deferred Navigation 时重新解析。

Context 应区分 `originalRouteId` 与 `failedRouteId`。只有已知且经过标识校验的 Route ID 才能写入；
未匹配 dynamic URI 的 `failedRouteId` 必须为 null。现有 `recoveryDepth` 继续表达 Failure Policy 链，
拦截器重定向深度使用独立字段，不能混用。

推荐 Policy 写法最终应是：

```dart
if (context.reason == CCNavigationFailureReason.routeNotFound) {
  return CCNavigationFailureFallback.toIntent(notFoundIntent);
}
return const CCNavigationFailurePropagate();
```

### 3.4 兼容与实施顺序

1. 先为现有错误类型建立穷尽的 Stage + Reason 映射测试；未知第三方错误只能映射为 `unknown`。
2. 补原请求、拦截器重定向、Policy 恢复和 Pending Resume 四类目标身份测试。
3. 以向后兼容字段增加 Reason；在迁移期保留 `errorType` 仅用于诊断，不再推荐 Policy 分支。
4. Demo 只对 `routeNotFound` 进入 404/Fallback，其它 resolution failure 默认传播或使用独立安全页。
5. 更新 Failure 文档和导出路由文档，明确 Stage、Reason、Attempt 三个维度的职责。

该项建议定为 **P1 Policy 精度问题**。优先级低于 PopGuard 绕过，但应在扩展更多 Failure Policy
场景前完成，避免业务形成基于 `errorType` 字符串的事实契约。

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

1. **P1：修复 Managed Route 的系统返回/手势 PopGuard 前置门禁**，先以失败测试锁定当前缺口。
2. **P1：增加 Failure Reason 与失败目标来源**，Demo 改为只对 route-not-found 兜底。
3. **P3：异步实现机械清理**，仅在相关文件再次修改时执行，不单独立项、不改变公开契约。

以上三项实施时应分别提交并回归；本文本身不代表这些能力已经完成。
