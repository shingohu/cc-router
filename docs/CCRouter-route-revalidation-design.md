# CCRouter Active Route Revalidation 设计

> 状态：当前已实现契约。适用于原生 Managed Backend 与明确实现所需可选 SPI 的自定义 Backend。
> GoRouter 兼容包已移除；历史对照不代表当前可接入能力。

## 1. 问题与职责

Interceptor 只能决定新导航是否开始。页面已打开后，登录、Session、权限、合规或 Feature Flag
变化可能使 retained Entry 失效。把 GoRouter `refreshListenable` 复制到 Core 会让 Runtime 订阅
任意业务状态，模糊状态所有权，并引入重复刷新、重入和 listener 生命周期风险。

CCRouter 因此采用显式协调模型：

1. 应用状态 Owner 先原子提交自己的新状态；
2. Owner 调用 `CCRouter.revalidateActiveRoutes(reason: ...)`；
3. Runtime 对当前 immutable Entry snapshot 执行 Host 注册的 backend-neutral policy；
4. Runtime 按 Entry identity 应用 `keep / close / replace / reset`；
5. 调用方读取脱敏报告并决定是否观测或再次触发。

Runtime 不拥有认证、权限或 Feature Flag，也不订阅 `Listenable`、Stream 或状态管理框架。

## 2. 契约边界

`CCRouteRevalidationContext` 只提供脱敏 Entry、稳定 reason、Runtime-local revision、deadline 和
cancellation。它不暴露 arguments、Extra、result、Scope、Widget、Flutter Route 或 Adapter 对象。
Policy 可以读取应用拥有的稳定状态 facade，但不得：

- 发起导航或递归 revalidation；
- 操作 UI、记录日志/Analytics 或修改被评估状态；
- 保留 Context 或 Entry 相关对象；
- 把账号、Token、完整 URI 或用户输入放入 reason。

Host 以稳定 ID 注册 `CCGlobalRouteRevalidationPolicy`，Runtime 按 ID 排序。每个 Entry 的第一个
非 keep 决策生效；异步 policy 应配置 per-Entry timeout 并协作响应 cancellation。

## 3. 执行语义

重叠触发严格串行，每一轮开始时重新捕获 Entry snapshot 和 monotonic revision。执行分两阶段：

- Evaluation：全部 policy 成功后才允许变更；异常包装为脱敏
  `CCRouteRevalidationPolicyError`，超时为 `CCRouteRevalidationPolicyTimeoutError`，本轮零变更。
- Application：再次以 Runtime-owned Entry object identity 校验目标。并发导航导致目标失效时返回
  `stale`，绝不按 routeId、索引或当前栈顶替代。

决策含义：

- `keep`：保留 Entry；
- `close`：通过可选 `CCNavigationTargetedCloseAdapter` 精确删除；不支持时返回 `unsupported`；
- `replace`：仅当目标仍是原 Host/Outlet 栈顶时执行，经过普通解析、Interceptor 和 Failure Policy；
- `reset`：每个 Host 选择其最上层 reset 并抢占该 Host 其它决策；即使所选 reset 最终为
  `stale/unsupported`，也不会降级执行较低优先级动作或影响其它 Host。

目标 Intent、Interceptor redirect 和 Failure Policy recovery 的最终请求继续受 operation/placement
fence 约束：`replace` 不得改变操作或离开原 Host/Outlet，`reset` 不得改变操作或离开所选 Entry
的 Host；不兼容时返回 `unsupported`，不会触碰目标分区。Runtime 用 Entry 已解析的 concrete
Host 重建默认 placement，因此 active Host 或焦点变化不会把动作重新路由。Revalidation mutation
不参与普通业务导航的 `singleFlight/rejectDuplicate` 合并；replace 仅在其新 Entry 实际 commit 后
报告成功，不等待页面最终 Pop result。

这里的 commit 必须有明确凭据：可选 Host SPI `CCNavigationDispatchAdapter` 以同步方法返回
`CCNavigationDispatch`，表示 Backend 原子事务已完成；其 `result` Future 只表示最终页面结果。
拒绝必须在返回凭据前同步抛错，且不能修改旧栈。原生 Managed 和 Memory 实现该 SPI，MultiHost
按所选子 Host 转发；未知旧 Adapter 或不支持的子 Host 在导航前返回 `unsupported`。普通导航
继续兼容原 `navigate()`。不能通过等待一个 microtask、判断
Future 尚未完成，或把异步接纳 Future 包成凭据来推断成功。

方案取舍：仅在 Demo 增加 timeout/focus 无法修复 Core 的承诺；修改原 `navigate()` 返回类型
会破坏现有 Host；猜测 Future 时序无法覆盖延迟拒绝。选择可选 Host SPI，使原生 Backend 提供
可靠提交证明，旧 Backend 明确降级且保持普通导航兼容，业务 Facade 不暴露新的内部类型。

默认 Host 解析与结构声明独立：即使目标有 Shell/Parent/命名 Outlet，concrete Host 仍固定到
原 Entry，而目标的显式结构及非默认 Host 保留。redirect/recovery/resume 继续走相同规则。

Policy close 是 Host 安全/可用性策略撤销，不是用户 Pop，因此刻意绕过 PopGuard 和页面
`PopScope`。它完成目标 result channel 并触发一次 Route Scope 清理，保留 covering sibling、
foreign popup、其它 Outlet 和其它 Host。任何不确定性都返回 `unsupported`，不得退化为 Pop。

## 4. 并发、失败与生命周期

两阶段只保证 policy 评估失败前零变更，不提供跨独立 Backend 的可回滚事务。单个 Adapter 操作
仍遵循自身原子性契约；应用阶段若后续操作失败，已完成操作不会被 Runtime 猜测回滚。

Runtime shutdown 先取消 App Scope，使 pending policy wait 以 `CCRouteCancelledError` 结束，再等待
revalidation 队列静止并释放 Entries、Scopes 和 Adapter。若 Interceptor 已把 revalidation 导航
转为 Pending continuation，shutdown 会先取消该 continuation，再等待队列，避免循环等待。超时
Timer 与 cancellation listener 在
所有终态解除；晚到的 Future value/error 被消费，不会重启管线。Runtime 不创建长期业务状态
listener，因此此能力没有额外 listener disposal 所有权。

Backend close/reset 等待同样受 Runtime cancellation 约束。取消使框架等待结束，先让队列收敛，
再 dispose Adapter；不要求 Backend 的 Future 先完成。迟到结果与异常被消费，不能继续应用
决策。Dart Future 不提供强制取消，Backend 仍拥有停止其异步工作的责任。
已排队但尚未开始的 pass 同样以 `CCRouteCancelledError` 结束，不误报尚未初始化；迟到结果
不得重新写入 shutdown 已清空的导航或 Entry 历史。
Backend close 保留框架错误；其它异常归一为脱敏 `CCNavigationAdapterError`，不透传原始 message。
只有 Backend 明确确认 closed 后才清理对应 Runtime Entry。

## 5. Backend 与迁移

原生 Managed Stack 是主实现：identity、Host/Outlet 分区和 targeted close 均由 CCRouter 拥有。
`CCMultiHostNavigationAdapter` 把 exact close 路由到 Entry 的原 Host，不改变 active Host。

GoRouter 兼容 Backend、依赖和 Demo 入口已移除，历史双 Backend 对照不再是当前回归命令。
业务仍使用相同 Facade/Intent；Composition Root 迁移到 Managed。自定义 Backend 按具体 SPI
提供能力，缺少 exact close 或同步 commit 证明时返回 `unsupported`，不得猜测修改其它栈。

## 6. 验证要求

回归至少覆盖：exact covered close、replace acceptance、per-Host reset precedence、policy error/
timeout 零变更、重叠触发串行、导航重入拒绝、shutdown cancellation、注册校验、最终请求
operation/placement fence、MultiHost/Outlet 隔离、result 与 Scope 单次清理，以及原生 Managed Demo
feature matrix 和自定义 Adapter 的不支持分支。还需覆盖默认 placement 在 active Host 切换后的固定、同分区 Failure Policy recovery
的 commit acceptance、普通 `singleFlight` 隔离，以及无 timeout defer 的 shutdown cancellation。真实平台验收仍按
各 Backend 的窗口、系统返回和手势清单独立执行；Widget/Pure Dart 测试不能替代真机结论。

## 7. 反复 Review 的原因与验证收敛

此前验证存在三个具体缺口，并非全量测试数量不足：

1. 测试主要使用同步 Memory Adapter，默认其未完成 Future 就是页面已打开。旧 `navigate()`
   把接纳失败与最终结果放在同一通道，隐含假设被直接写入提前成功逻辑。
2. Host 固定只验证了默认 root，没有交叉验证声明 Shell/命名 Outlet 的目标；修复使用的
   placement override 恰好在这些结构分支被忽略。
3. shutdown 只验证了 policy/defer 等待，没有枚举 Backend close/reset 所有等待点与 dispose
   的依赖方向。因此取消前移修好了一个循环，却没有证明整个等待图能收敛。

前一轮把已有测试通过扩展为“问题均关闭”的结论过宽。今后的完成证据必须包含下面的语义
矩阵，并把未测试边界明确列出；不能把专项/全量通过当作所有场景正确的证明。

| 边界 | 必须验证的可观察结果 |
| --- | --- |
| 同步提交凭据、旧 Adapter、同步拒绝 | 拒绝不改变旧 Entry；无凭据不 dispatch；成功不等待 Pop |
| root、命名 Outlet、Shell × 非当前 Host | concrete Host 固定，结构保留，当前 Host 不被激活或变更 |
| direct、redirect、recovery、defer/resume | 每条路径保留 identity fence 与同一 acceptance 契约 |
| policy、defer、Backend close/reset × shutdown | 框架等待有界、Adapter 可 dispose、迟到成功/错误不复活管线 |
| Memory 与原生 Managed 渲染 | 返回值、实际页面、结果通道、Route Scope 单次清理同时验证 |

本轮先加入失败测试，证实 7 个边界断言失败，再修实现；进一步增加命名 Outlet/Shell 的组合
用例与真实 Managed Widget replacement。此矩阵限定当前能力的验收范围，不代替平台真机验收。
