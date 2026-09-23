# CCRouter Service 实施计划

> 生命周期和创建策略的最终语义见 [CCRouter Service 生命周期设计](CCRouter-service-lifecycle-design.md)。

## 1. 文档状态

- 状态：Service 子系统实施清单，1.x 生命周期模型已收敛为 App、Session、Route
- 范围：Service Provider、Token/Key、Scope、生命周期和跨组件契约
- 不包含：CLI 2.0、Service 代码生成器、动态组件交付和远程 RPC

本文只记录 Service 的实施边界和验收顺序。实际状态以本文件和测试为准，不能把架构设计中
尚未实现的能力当成公开 API。

## 2. 当前已实现

- App、Session、Route 三种已启用 Service Lifetime；实例按 Lifetime 懒创建并按
  `CCServiceCreationPolicy` 选择缓存或每次创建。
- Route Lifetime 使用 Managed Navigation ID 精确关联 RouteEntry；普通
  `CCRouter.service()` 不猜测当前页面，Flutter 页面通过
  `CCRouter.routeService(context)` 读取 Host 自动注入的不可变绑定。
- `CCServiceToken<T>` 支持跨 Package 稳定契约身份。
- `CCServiceKey<T>` 支持同一契约的命名实现。
- `ccrouter_test` 提供 `CCServiceOverride<T>`，可在隔离 `CCRouterTestHost`
  中按类型、Token 和 Key 替换已注册 Provider；替身沿用原 Provider 的 Scope、创建策略和销毁边界。
- 未命名 Provider 自动作为默认实现；多个默认实现和重复 Key 在注册时失败。
- Provider Factory 接收 `CCInvocationContext`，可以读取当前 Scope 的取消和 Deadline 信息。
- Provider 可声明 lazy async `initializer`；`serviceAsync` 与生成代理会等待 Ready，Singleton
  在每个 Scope 内 single-flight，Factory 每次初始化，原同步 API 不会偷偷启动异步工作。
- Readiness 失败被脱敏并在当前 Singleton/Scope 内保持稳定；初始化依赖循环会确定失败，新的
  Session/Route Scope 拥有新的 readiness 状态。
- 跨组件生成代理可通过独立的 `ccrouter_generated.dart` 边界执行方法级 Service
  Invocation；普通业务 barrel 不导出底层 callback bridge。
- Service Invocation 会记录 Token、Key、method ID、显式 caller component、Provider owner、
  Scope、父子 Span、耗时和终态，但不记录参数、返回对象或任意业务文本。
- Session 关闭、RouteEntry 移除和 Runtime shutdown 会取消各自 Scope 内仍在执行的 Service
  Invocation；调用方也可以提供更短的 timeout 或 cancellation token。
- `CCDisposable` 实例由 Scope 按逆创建顺序销毁，单项失败和超时不会阻塞其它实例。
- Session 关闭会拒绝新的 Session Service 解析，并释放 Session-owned 实例。
- 服务仍由组件 Registrar 手动注册；Demo 已用消费方强类型 Proxy 验证跨组件
  Invocation 边界，当前仍没有 Service 注解生成器或自动 Proxy 生成。
- `CCRouterTestHost.run` 通过 Zone-local Runtime Overlay 让生成 Proxy 和静态 Facade
  在独立 Test Host 上运行；Overlay 不修改生产默认 Runtime，不接管
  `initialize`/`shutdown` 或 Host Backend 绑定。

## 3. 第一阶段：注册边界与确定性

第一阶段只强化不会改变调用模型的边界：

1. Token ID 和 Key 名称使用统一的稳定标识语法和长度上限。
2. 注册时拒绝非法 Contract/Key 值，并保留安全、可诊断的注册错误。
3. 保持 Type lookup、Token lookup、Key lookup 和已有 Scope 语义不变。
4. 增加非法值、重复值、默认选择和跨 Runtime 回归测试。

第一阶段已完成：除上述注册校验外，缺失 Provider、Token 类型不匹配、循环构造和未激活
Session Scope 均返回稳定的 Service 错误子类型；缺失命名实现会保留稳定 Key 诊断字段。

1.x 不提供 Component Scope 或组件运行时激活/停用；Route Scope 已绑定 RouteEntry 的最终
移除事件。页面级对象不等同于 PageShow/PageHide；Factory 也不等同于调用结束销毁。

## 4. 后续实施顺序

### 4.1 组件边界（1.x 已冻结）

- Provider 保留 Runtime 注入的 owner component ID，用于静态所有权、诊断和 Route Scope 关联。
- 组件集合由 Composition Root 在初始化时一次确定；可选组件通过是否装配 Manifest 决定。
- 登录、权限和 Feature Flag 使用 Interceptor，账号资源使用 Session Scope，页面资源使用 Route Scope。
- 1.x 不提供 Component Scope、`activateComponent` 或 `deactivateComponent`，避免产生只停用部分能力的伪动态组件语义。
- 动态组件治理进入 2.0 候选；只有依赖级联、Handler/订阅/诊断清理、活跃 Route 协调和原子能力切换形成完整协议后才重新评估。

### 4.2 Route Scope（已完成）

- Core 按 Managed Navigation ID 精确解析具体 RouteEntry，不从全局可见页或栈顶猜测。
- Flutter Host 只通过私有 Inherited binding 将 ID 交给
  `CCRouter.routeService(context)`；`BuildContext` 是查找入口，不是 Scope Owner 或销毁信号。
- Route 永久移除后关闭 Route Scope；Page hide、Popup、LocalHistory、PopGuard 拒绝和普通
  rebuild 不触发关闭。
- 同一路由重复 Push 拥有独立 Scope；旧 ID 在 Entry 移除后返回稳定的 Scope unavailable 错误。
- 自动 GoRouter Assembler 已接入；手写 Host Route 必须配对使用
  `CCRouterHostBinding.decodeRouteExtra` 与 `bindRouteEntry`。

### 4.3 Service 调用链（基础边界已完成）

- Core 已提供由稳定 Token 和 method ID 驱动的 Invocation primitive，覆盖 Provider 解析、实例
  获取、方法执行、父子 Trace、deadline、caller cancellation 和 Scope cancellation。
- `package:ccrouter/ccrouter_generated.dart` 只为生成代码导出
  `CCRouterGeneratedServiceBinding`；业务继续只导入 `ccrouter.dart` 并使用生成的强类型 Proxy。
- Route Service Invocation 必须携带精确 Managed Navigation ID；App/Session Service 明确拒绝
  Navigation ID，不能静默忽略过期页面身份。
- 普通本地 Service 不生成 Proxy，保持直接 `CCRouter.service<T>()`；跨组件 Service 再按契约
  选择生成方法代理，避免对每个本地调用增加 Future、Zone 和 Trace 成本。
- Runtime 与 Demo 已验证可选的跨组件强类型 Proxy；同步契约经 `invokeSync`
  保持同步返回类型，异步契约经 `invoke` 承载 readiness、timeout 和 cancellation。
- 同步 Proxy 不会暗中启动 initializer；Provider 未 Ready 时抛出
  `CCServiceNotReadyError`。Factory + initializer 每次都需要异步准备，因此不能供
  同步 Proxy 方法直接调用。
- Demo 中 `demo_payment` 和 `demo_navigation_lab` 各自持有消费方 Proxy，并固定精确
  caller component identity。这是生成形态验证，不是要求业务长期手写。
- 后续自动 Proxy 只生成接口中可验证的方法，不采用反射、方法名字符串分派、
  万能 `Map` 或运行时参数 Codec。

### 4.4 Async Service Readiness（已完成）

- Factory 保持同步并先把实例交给 Scope；可选 initializer 只表达 readiness，不改变 Owner。
- `serviceAsync`、`serviceOrNullAsync` 和对应 Route API 提供显式等待；同步 API 对尚未 Ready 的
  Provider 返回 `CCServiceNotReadyError`。
- Singleton 初始化成功或失败都在当前 Scope 内保持稳定，防止并发重复副作用；Runtime 不猜测
  retry。Factory 每次独立初始化且不在 Scope 内累计 readiness record。
- Session/Route/App Owner Scope cancellation 会终止对应 initializer；单个等待者的 caller
  cancellation/deadline 只停止等待，不污染共享 Singleton readiness。Factory readiness 随调用
  取消，因为其实例不与其他等待者共享。
- 初始化错误只记录 Service identity 与 error type，不保留业务错误消息、参数或返回对象。

### 4.5 生成器与 CLI（1.x 评估完成）

- Service Registrar 先保持手动维护，避免为低频变化的能力增加生成冲突。
- 当前样本只有 1 个跨 Package Service Contract、1 个方法和 2 个消费方 Proxy；
  两个 Proxy 合计 36 行，真实差异只有 caller component identity。这足以验证
  Runtime 形态，但不足以在 1.x 冻结一套 Service 注解和 metadata 协议。
- 1.x 跨组件稳定入口仍是独立 contracts Package 中的接口和 Token，消费方可通过
  `CCRouter.service(contract: ...)` 直接获取强类型实现。Demo 手写 Proxy 只是生成形态
  验证夹具，不是推荐的长期开发流程。
- 自动 Service Proxy 在出现以下任一真实信号后重新评估：至少 3 个 promoted
  Contract 且 5 个消费关系；同一 Contract 被至少 3 个组件消费；或者已出现
  method ID、caller identity 或方法签名漂移缺陷。
- 达到阈值后，消费组件必须显式声明自己使用的 Contract，生成器据此输出调用方
  Proxy。不允许从 Package 依赖猜测所有 Service，也不允许运行时传入可伪造的
  caller component ID。
- CLI 2.0 再考虑契约提升、Override、迁移和一键校验。

## 5. 验收门槛

- 所有 Provider 标识校验在注册阶段确定失败，不依赖解析顺序。
- App/Session/Route/Singleton/Factory 的生命周期测试全部保持通过。
- Session close、Runtime dispose、Factory failure 和 disposal timeout 不产生实例残留。
- 同一 Token 的类型不匹配、重复默认实现和命名冲突均返回稳定错误。
- Core Service 契约不依赖 BuildContext、反射、字符串方法调用或万能 Map；Flutter
  `routeService(context)` 只读取精确 Host 绑定，不参与实例所有权或销毁判断。
