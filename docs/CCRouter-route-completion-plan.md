# CCRouter 路由完成计划

## 文档状态

- 版本：v0.2
- 状态：P0、P1 和 P2 路由闭环已完成；完整 Route Restoration 明确暂缓
- 职责：五份路由文档中的唯一实施状态清单，不替代路由语义、契约或混合路由设计

本文中的勾选项表示当前仓库已实现并具有对应回归覆盖。其他设计文档不再重复维护任务
完成状态；若描述与本清单冲突，应先核对当前代码和测试，再同步修正文档。

## 1. 范围

本文是路由子系统从当前实现到可冻结 API 的执行清单。范围包括路由 Contract、Runtime、
Flutter Facade、GoRouter Adapter、路由 Generator、Demo 路由接入、测试和路由设计文档。

以下内容不在本轮范围内：

- CI、发布流水线和远端自动化；
- Service、Command、Query、Event 等非路由能力扩展；
- 接管第三方 Overlay 或未提供观察信号的独立导航系统；
- 为不具备原子能力的后端伪造一致性保证。

## 2. 完成原则

1. 经过 CCRouter 的路由必须保持 RouteEntry、Scope、返回值和诊断一致。
2. Foreign Route 尽量观察；无法关联时隔离，禁止猜测修改 Managed Route。
3. Interceptor 只负责决策，Aspect 只负责观察，Lifecycle 只描述对应维度的状态。
4. 平台和后端差异由 Host/Adapter SPI 承担，业务 API 不暴露 Flutter Route 对象。
5. 每项先增加失败或边界测试，再实现并执行专项与全量回归。
6. 所有缓存、Listener、Timer、Continuation 和 Route 引用必须有明确释放路径。

## 3. 实施阶段

### P0-1 导航决策管线

- [x] 移除 `CCNavigationAspect.before` 的决策能力，Aspect 变为纯观察接口；
- [x] 保证 Global Interceptor 后接 Route Interceptor 的唯一确定顺序；
- [x] 修复 `CCNavigationDefer` 恢复组合导航时退化为普通 `navigate` 的问题；
- [x] 为 Interceptor 增加真实 Deadline/Timeout 和专用错误；
- [x] 校验路由级 Interceptor 的组件所有权；
- [x] 覆盖 Redirect、Cancel、Defer、超时、异常、Session/Runtime 清理和内存释放。

### P0-2 Pop 决策

- [x] 增加 Adapter 中立的 `CCPopGuard` 决策契约；
- [x] 统一业务 Pop、系统返回、手势返回和预测返回的 Guard 管线；
- [x] Guard 拒绝或交互手势取消时不得关闭 RouteEntry 和 Scope；
- [x] Foreign、Opaque 和 LocalHistoryEntry 消费返回时不得触发 Managed Guard 销毁语义。

### P0-3 失败与兜底

- [x] 统一路由未找到、参数非法、Deep Link 拒绝、组件不可用和 Adapter 失败事件；
- [x] 增加 Host 级只读 Failure Policy，支持明确的兜底或重定向；
- [x] 兜底链保留 Origin、Source、Navigation ID，并限制循环；
- [x] 参数和 Extra 不进入不受控日志、Aspect 或持久化数据。

### P0-4 Backend Identity 与可见性

- [x] 用已确认的 Backend Entry identity 驱动 Runtime RouteEntry 显示状态；
- [x] 消除 Runtime commit 即假定真实到达的时序；
- [x] 关联 GoRouter root、Shell Observer，并通过 RouterDelegate 自动观察 StatefulShell 分支；
- [x] 覆盖 Foreign PageRoute、PopupRoute、独立 Navigator、事件重复和序列断层；
- [x] StatefulShell 切换只 Hide/Show，不销毁非活动分支 Scope。

GoRouter 的 Observer 必须在应用构建 Router 时由 Host/Assembler 安装，Flutter 不支持在 Router
创建后安全注入 Observer。Adapter 对已安装的 Observer 自动完成 Backend identity 关联；如果
Observer 只覆盖部分 Managed Outlet，Adapter 会关闭延迟 Arrival，避免未覆盖页面永久停留在
`pushed`。StatefulShell 分支切换不依赖 Navigator top 变化，由 RouterDelegate 单独上报
`outletActivated`。

### P1-1 Host、窗口与自适应布局

- [x] 增加 Runtime 多 Host Registry 和动态 Host Resolver；
- [x] 隔离 Window、Display、Shell 和 Outlet 的栈、返回与诊断状态；
- [x] 将 Adaptive Layout 契约接入 Host/Outlet 调度；
- [x] 支持单 Pane、双 Pane和折叠状态变化，并明确窗口关闭时不隐式迁移 Live Route。

Host 卸载会关闭该 Host 的 RouteEntry 和 Scope，并安全完成 pending result；其他 Host 不受影响。
Live Route 的跨窗口迁移存在 Widget、Scope、返回值和后端状态所有权问题，因此不做隐式迁移。
未来如需迁移，只能通过显式新导航或单独设计的状态恢复流程重建。

### P1-2 可观测性

- [x] Aspect 事件补齐安全的 Host、Outlet、Owner、Referrer 和 Redirect Chain；
- [x] 区分首次 Arrival、恢复显示、Hide、Removed 和 Disposed；
- [x] 拆分 Resolve、Intercept、Dispatch、Arrival、Stay 和 Total 耗时；
- [x] 提供 Telemetry Context SPI，不暴露原始账号或任意业务对象；
- [x] 明确 PV 由 Arrival/Show 产生，UV 由外部分析层结合匿名访客身份聚合。

### P1-3 路由状态恢复（暂缓，仅保留设计与需求观测）

- [x] 增加 `CCRouteRestorationOpportunityEvent`，记录平台重建或异常 Session 的恢复机会；
- [x] 事件固定标记 `unsupported`，不伪装已经执行恢复；
- [x] 只记录 Route ID、Host/Outlet 数量、版本指纹和匿名 Telemetry Context；
- [x] 禁止记录完整 URI、参数、账号、Arguments、Extra 或任意业务对象；
- [ ] 定义版本化、Adapter 中立的 Route Restoration Snapshot（数据证明有需求后再启动）；
- [ ] 实现重新解析、安全校验、契约升级和部分恢复（非当前版本阻塞项）。

完整状态恢复暂不进入生产 API。后续只有在恢复机会率、受影响 Route 分布、多窗口恢复占比等
Telemetry 数据证明收益后才重新立项；届时必须采用路由显式 opt-in，且不能持久化 Widget、
BuildContext、Flutter Route、Scope、Extra 或返回 Completer。

### P2 生成器与最终收口

- [x] 支持显式集合 Query 和自定义 Query Codec；
- [x] 完善继承参数、复杂构造器和导入分析；
- [x] 路由文档增加组件、Shell、Outlet、来源和“当前不支持恢复”的能力视图；
- [x] 执行最终 API 暴露、重复字段和半实现能力扫描；
- [x] 执行 Listener、Timer、Pending Navigation、Route/Backend Entry 和 Scope 泄漏回归；
- [x] 完成全部路由专项、Generator 和 Workspace 回归。

### P3 应用集成入口

- [x] 分别生成 Runtime Manifest 集合和后端 Route Catalog，并通过 Catalog 的组件版本来源
  校验两者一致性；
- [x] 应用通过 `CCRouter.initialize(components: ...)` 原子初始化，并显式调用 `shutdown`；
- [x] `CCRouterApp.managed` 只绑定 Host 与 Backend，并在 Adapter 绑定完成前阻止业务子树
  挂载；
- [x] Adapter 注入由 `CCRouterApp.managed` 的私有协调器完成，不开放独立 Controller；
- [x] `CCGoRouterBackend.managed` 自动组装 Root Observer、GoRouter、Binding 和 Adapter；
- [x] `CCGoRouterBackend.attach` 保留已有 GoRouter 的应用所有权；
- [x] 默认 `CCRouterApp(child:)` 保持不拥有 Runtime 的兼容语义；
- [x] 覆盖绑定成功、失败安全 UI、显式销毁顺序、Router 所有权和生成器聚合回归；
- [ ] 提供 Navigator 1.0 Backend，供无法迁移到 Router API 的已有项目渐进接入。

## 4. 回归要求

每个阶段至少执行：

```text
受影响 Package analyze
新增专项测试
packages/ccrouter_test/test 全量测试
packages/ccrouter_test/generator_test（涉及生成器时）
git diff --check
```

Demo 中与本轮无关的用户工作区改动不回退；如果其未完成代码阻止 Demo analyze，单独记录，
不以修改或删除用户代码作为绕过方式。
