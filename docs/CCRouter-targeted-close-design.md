# 精确 RouteEntry 关闭

> 状态：当前契约适用于原生 Managed 与实现可选 exact-close SPI 的自定义 Backend。
> GoRouter 兼容包已移除；下文独立标注的旧 Backend 事务仅用于解释历史取舍。

状态：已实现可选 Adapter 能力；支持范围以本文件、API 和回归测试为准。

问题是 A 被 B/foreign Popup 覆盖后，异步完成仍需移除 A。普通 Pop 选择当前栈；
仅移除 Flutter Route 而不更新拥有它的逻辑 Stack，会在后续投影时复活 A。
应用层回调或当前页检查无法解决覆盖实例的所有权；给所有 Adapter 增加必需方法会破坏
兼容性。因此选择业务实例句柄 + 可选 Host Adapter SPI，旧 API 和默认 Pop 均保持。

## 所有权和失败

Runtime 为每个 entry 分配独立句柄，按对象身份匹配。公开构造出的句柄、相同字符串 ID、
过期/已关闭/旧 Runtime 句柄均不能代替原实例。句柄仅携带 sanitized ID，不持有 Runtime、
Context、Route、参数或结果。Host 不得将其序列化为可恢复导航能力。

业务从 `CCRouter.routeEntryHandleOf(context)` 在页面建立时捕获；Host payload 和页面 binding
携带无 Runtime 引用的 generation token，shutdown 或旧 Context/同 navigationId 跨代重用
均返回 null；resolver 用弱 key 关联 token。它不依赖 inherited
变化，也不搜索 active/top 页。`navigator.close` 验证原结果类型，然后对目标运行全局和
局部 PopGuard（business trigger），并复验 entry 存活。Guard 同步且禁止重入导航。
结果类型错误在 backend 之前抛 `CCRouteResultTypeError`；Adapter 异常用已有 sanitized
`CCNavigationAdapterError` 表达。结果 `closed/notFound/unsupported/guardDenied` 不包含
backend 对象或业务数据。不支持时绝不降级到 pop。

关闭精确完成原结果通道并启动该 Route Scope 的幂等释放；Future 不等待异步 Service
销毁。Observer、结果 Future、显式关闭和 Runtime shutdown 的重复清理仍通过原 entry
生命周期收敛。等待自定义 Adapter 返回时，原 Entry、Host 注册或 Runtime 结束会将 close
收敛为 `notFound`，解除框架 consumer 等待；已完成的精确回执保留其结果。迟到成功/错误
被消费，不能改变同名 replacement Host。Adapter 仍负责取消自己的外部异步工作。

## 当前 Managed Stack 事务边界

Managed Router Backend 是长期默认路径：Managed Adapter 按 Host/Outlet 持有 immutable
Stack 状态，`RouterDelegate + Navigator.pages` 负责投影；Runtime 管理 Entry、结果与 Scope。
`close` 按 Entry identity 查找目标；有活动 Flutter Route 且无需保留 foreign anchor 时先
精确 `removeRoute`，随后收敛尚未完成的 Store 移除；未渲染的实例直接移除 Store Entry。
需要保护 foreign Popup 时保留空 anchor，仅结束目标的逻辑状态与业务资源，不移除其承载
边界。不能用“先改 pages 再等待 Flutter 自动移除”代替这条精确关闭路径。
Shell structural Page、single Navigator Shell、stateful branch 和 adaptive named Outlet
均不冒充业务 RouteEntry；branch 切换只改变 active/visible/focused 状态，保留其它分支历史。

原生 Managed 支持声明式 Entry、被覆盖页面和 retained Shell branch 的 exact close，
不再继承 GoRouter 的 imperative-only 限制。最后一个 Managed Entry 在 foreign Popup 下
被关闭时，保留必要的空渲染锚点保护 Popup，但及时释放目标结果与业务 Scope。
MultiHost 按目标原始 concrete Host 转发，不切换 active Host，不影响其它 Outlet。

## 历史：GoRouter 兼容 Adapter 事务（已移除）

以下保留退役前的限制与算法，不能作为当前支持矩阵或接入代码。

Adapter 只在 active entry 保留实际 Flutter Route 的 WeakReference；声明树通过 Host-only
payload identity 与 ImperativeRouteMatch 对应，再核验原 Host/Outlet、Page key、Navigator
和 Route 存活。通过公开 Match/Shell 构造器只改目标及必要祖先，保留后续 siblings；
不能用会截断后缀的 RouteMatchList.remove，也不访问 go_router src/internal API。
所有 unsupported 返回均在提交前；底层违反同步提交契约时抛 AdapterError，不将潜在
变更误报为 unsupported。setNewRoutePath 不经过 URI parser/redirect。

无外部 onExit 时 setNewRoutePath 同步提交；在下一帧重建前精确 removeRoute，避免 Flutter
自动连带关闭属于目标 Page 的 pageless Popup。两个状态更新之间没有 await；目标结果
先精确完成，防止 Observer 给 null。全局和局部 CCRouter PopGuard 已由 Core 运行。

支持有 Observer 实际身份、已挂载的 push/replace 和 push 模式 open（无业务结果），
以及保留结构祖先的嵌套 Shell Outlet。声明式 go/reset、当前声明树不含的保留 Shell
分支、移除后清空 Shell，以及含外部 GoRoute.onExit 的树明确 unsupported。后者可能
异步或评估无关覆盖页，公开 GoRouter API 无法安全执行任意手术。尚未挂载或已离开声明树
的 imperative 实例不会冒称 closed。自定义/无 Observer Adapter 可返回 unsupported。

MultiHost 转发始终使用目标的 concrete Host，保持 active Host 与其它 Outlet；被注销
Host 返回 notFound。不能把最小实现解释为任意树编辑、原生多窗口或浏览器历史完整支持。

## 回归与回退

当前 `targeted_close_test.dart`、`targeted_close_core_test.dart` 与 Managed/Demo 回归验证
覆盖页不复活、相同地址的独立实例、Foreign Popup 保留、结果类型先验、Scope 单次清理、
声明式和 retained Shell branch 关闭、全局/局部 Guard、失效身份与 Host/Outlet 隔离。
Backend 等待边界回归覆盖 Entry/Host/Runtime 结束和迟到回执；API surface 测试保护 SPI 不进入
业务 barrel。原始失败、后续修复和各轮 suite 结果见[验证索引](validation/README.md)。

回退仅需停止调用 close；既有 pop/maybePop/go 等实现不走新增路径。无新依赖、插件或
生成契约，未修改业务协议。Web 浏览器历史、真实平台手势与性能结论必须按日期及环境
独立验收；不能从 exact-close 自动化推断任意结构栈编辑或完整状态恢复已支持。
