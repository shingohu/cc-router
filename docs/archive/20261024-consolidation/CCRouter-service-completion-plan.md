> 归档日期：2026-10-24。原路径：`docs/CCRouter-service-completion-plan.md`。
> 此文件保存文档合并前的设计/实施快照；相对链接已重定位，正文中的旧 API、阶段状态与测试数字不代表当前能力。
> 现行入口与合并映射见[归档索引](README.md)。

# CCRouter Service 实施计划

> 生命周期和创建策略的最终语义见 [CCRouter Service 生命周期设计](../../CCRouter-service-lifecycle-design.md)。

## 1. 文档状态

- 状态：Service 子系统实施清单，1.x 生命周期模型已收敛为 App、Session、Route
- 范围：Service Provider、稳定 Contract ID/Key、Scope、生命周期、跨组件契约、显式消费依赖和方法级 Proxy 生成
- 不包含：CLI 2.0、动态组件交付、远程 RPC、Stream/callback 代理

本文只记录 Service 的实施边界和验收顺序。实际状态以本文件和测试为准，不能把架构设计中
尚未实现的能力当成公开 API。

## 2. 当前已实现

- App、Session、Route 三种已启用 Service Lifetime；实例按 Lifetime 懒创建并按
  `CCServiceCreationPolicy` 选择缓存或每次创建。
- Route Lifetime 使用 Managed Navigation ID 精确关联 RouteEntry；普通
  `CCRouter.service()` 不猜测当前页面，Flutter 页面通过
  `CCRouter.routeService(context)` 读取 Host 自动注入的不可变绑定。
- Runtime 使用稳定 Contract ID 支持跨 Package 契约身份；普通业务只按接口类型解析，
  `CCServiceToken<T>` 仅保留在生成支持、低层 Component SPI 和测试边界。
- `CCServiceKey<T>` 支持同一契约的命名实现。
- `ccrouter_test` 提供 `CCServiceOverride<T>`，可在隔离 `CCRouterTestHost`
  中按类型、Token 和 Key 替换已注册 Provider；替身沿用原 Provider 的 Scope、
  创建策略和销毁边界，但默认清除生产 initializer，可显式安装测试 readiness。
- 未命名 Provider 自动作为默认实现；多个默认实现和重复 Key 在注册时失败。
- Provider Factory 接收 `CCInvocationContext`，可以读取当前 Scope 的取消和 Deadline 信息。
- Provider 可声明 lazy async `initializer`；`serviceAsync` 与生成代理会等待 Ready，Singleton
  在每个 Scope 内 single-flight，`newInstance` 每次初始化，原同步 API 不会偷偷启动异步工作。
- Readiness 失败被脱敏并在当前 Singleton/Scope 内保持稳定；初始化依赖循环会确定失败，新的
  Session/Route Scope 拥有新的 readiness 状态。
- 跨组件生成代理可通过独立的 `ccrouter_generated.dart` 边界执行方法级 Service
  Invocation；普通业务 barrel 不导出底层 callback bridge。
- Service Invocation 会记录 Token、Key、method ID、显式 caller component、Provider owner、
  Scope、父子 Span、耗时和终态，但不记录参数、返回对象或任意业务文本。
- Session 关闭、Route Scope 关闭和 Runtime shutdown 会取消各自 Scope 内仍在执行的 Service
  Invocation；调用方也可以提供更短的 timeout 或 cancellation token。
- `CCDisposable` 实例由 Scope 按逆创建顺序销毁，单项失败和超时不会阻塞其它实例。
- Session 关闭会拒绝新的 Session Service 解析，并释放 Session-owned 实例。
- `@CCServiceContract` 已生成内部强类型 Token/metadata；`@CCService` 会为简单同步构造实现
  推导唯一直接 Contract 或内部 ID，生成 Provider registration，并由 Package 唯一 Component
  的自动 Registrar 装配。
- 带参构造、依赖注入、自定义 Factory 和 async initializer 保持显式
  `@CCComponentContribution`。
- 消费组件通过 `CCServiceDependency<T>` 显式声明跨组件 Contract；生成器输出组件专属 Client，
  自动固定 Token、Key、method ID、caller identity 和参数转发，不从全部 Package 依赖猜测能力。
- `CCRouterTestHost.run` 通过 Zone-local Runtime Overlay 让生成 Proxy 和静态 Facade
  在独立 Test Host 上运行；Overlay 不修改生产默认 Runtime，不接管
  `initialize`/`shutdown` 或 Host Backend 绑定。
- 非门禁 `service_scaling.dart` benchmark 覆盖 Provider 规模、Singleton 热查询、同步
  Invocation Trace、`newInstance` readiness 和 Scope dispose，并在每轮校验 disposable 实例归零。

## 3. 第一阶段：注册边界与确定性

第一阶段只强化不会改变调用模型的边界：

1. Token ID 和 Key 名称使用统一的稳定标识语法和长度上限。
2. 注册时拒绝非法 Contract/Key 值，并保留安全、可诊断的注册错误。
3. 保持 Type lookup、Token lookup、Key lookup 和已有 Scope 语义不变。
4. 增加非法值、重复值、默认选择和跨 Runtime 回归测试。

第一阶段已完成：除上述注册校验外，缺失 Provider、Token 类型不匹配、循环构造和未激活
Session Scope 均返回稳定的 Service 错误子类型；缺失命名实现会保留稳定 Key 诊断字段。

1.x 不提供 Component Scope 或组件运行时激活/停用；Route Scope 绑定精确 Entry 的生命周期，
普通 Pop 还保留退出渲染期。页面级对象不等同于 PageShow/PageHide；`newInstance` 也不等同于
调用结束销毁。

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
- 普通 Pop 先完成结果并移除活动 Entry，退出渲染结束后关闭 Scope；精确 close 及时释放目标
  Scope。shutdown 不等待 Flutter 帧。Page hide、Popup、LocalHistory、Guard 拒绝与普通 rebuild
  不触发关闭；renderer 卸载保留逻辑 Entry/Scope 供重挂。
- 同一路由重复 Push 拥有独立 Scope；Scope 关闭后旧 ID 返回稳定的 Scope unavailable 错误。
- 原生 Managed 包含启动初始页的自动绑定；Foreign Route 和 Outlet 本地 base surface 不创建
  Managed Scope。自定义绑定属于 Host SPI；GoRouter 自动 Assembler 与兼容包已移除。
- 共享 readiness 的等待者取消仅解除自身订阅；实际 Owner 结束才终止共享等待。Scope、token、
  readiness 缓存及共享 Factory/initializer 不长期采用首次 caller Zone；失败交付到各 caller
  error Zone，`newInstance` 初始化保留 caller 取消链。完整语义见生命周期设计第 2.3 节。

### 4.3 Service 调用链（已完成）

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
  `CCServiceNotReadyError`。`newInstance` + initializer 每次都需要异步准备，因此不能供
  同步 Proxy 方法直接调用。
- Demo 中 `demo_payment` 和 `demo_navigation_lab` 各声明一个精确消费依赖，生成组件专属
  Proxy 并固定 caller component identity；手写 Proxy 已删除。
- 自动 Proxy 只生成普通实例方法和 getter，支持同步/Future 返回、方法级泛型与常用参数；
  泛型 Contract、Contract 继承、setter/operator、Stream/FutureOr、callback、Flutter 与私有
  `src` 类型生成失败。
  不采用反射、万能 `Map` 或运行时参数 Codec。

### 4.4 Async Service Readiness（已完成）

- Provider 的实例构造函数保持同步并先把实例交给 Scope；可选 initializer 只表达 readiness，不改变 Owner。
- `serviceAsync`、`serviceOrNullAsync` 和对应 Route API 提供显式等待；同步 API 对尚未 Ready 的
  Provider 返回 `CCServiceNotReadyError`。
- Singleton 初始化成功或失败都在当前 Scope 内保持稳定，防止并发重复副作用；Runtime 不猜测
  retry。`newInstance` 每次独立初始化且不在 Scope 内累计 readiness record。
- Session/Route/App Owner Scope cancellation 会终止对应 initializer；单个等待者的 caller
  cancellation/deadline 只停止等待，不污染共享 Singleton readiness。`newInstance` readiness 随调用
  取消，因为其实例不与其他等待者共享。
- 初始化错误只记录 Service identity 与 error type，不保留业务错误消息、参数或返回对象。

### 4.5 生成器与 CLI（最小闭环已完成）

- 实现 Package 只声明一个顶层 `const CCComponent`；内部 Route、简单 Service 和
  Contribution 自动绑定该 Owner，生成私有 Registrar、Manifest、Catalog 和 Package Index。
- contracts Package 可服务多个 Component。每个 `@CCServiceContract` 显式声明
  `CCComponentId` 和稳定 ID；业务 barrel 使用 `show` 导出接口，不导出生成 Token。
- `@CCService` 只覆盖 public concrete non-generic class 的 unnamed zero-argument generative
  constructor，支持 Scope、`singleton/newInstance`、Key、default，并自动绑定唯一直接
  Contract。多个直接 Contract、Contract 与 `id` 并存、间接继承猜测都会生成失败。
- 复杂创建与 readiness 继续使用 `@CCComponentContribution`，避免在注解中增加任意 Factory
  或异步代码入口。Command 与 Event 使用各自的显式 Contract/Handler/Subscription 声明生成；
  未注解迁移能力仍保持 Contribution；InitTask 使用专用 Contract/Handler 生成，不扫描函数体猜 metadata。
- Service contract/implementation 已进入 workspace ownership/conflict 校验、Package Index、
  Capability Catalog、Host 聚合和 metadata 内容缓存；无生成物时不创建生成目录。
- 1.x 跨组件稳定入口是独立 contracts Package 中的接口、稳定 ID 与消费组件生成 Client；
  `CCServiceToken<T>` 不进入普通业务 Facade。
- 消费组件必须显式声明 Contract 后才生成 Proxy；Package 依赖扫描只负责发现元数据，不能
  自动授予或生成全部 Service。Workspace 再次校验 Contract Owner 和 required dependency。
- [x] 保持 `dependencies`、`serviceDependencies` 和 `commandDependencies` 的显式语义不变；
  Generator/Workspace Validator 批量阻止缺失 Owner。`ccrouter_analyzer_plugin` 已从 Pub 精确依赖图
  和生成 metadata 建立 Owner 索引并实时诊断；仅当 required 列表可直接编辑、Owner 唯一且现有
  公共 import 精确暴露对应 `CCComponentId` 时提供 Quick Fix。它不静默扫描 Package 源码、不插入
  import、不修改变量/spread/条件集合，最终门禁仍由 Generator 承担。
- [x] `CCServiceContract.alias`、`CCCommandContract.alias` 已提供跨消费组件统一的默认 Client
  成员名，`CCServiceDependency.alias`、`CCCommandDependency.alias` 可做消费组件级覆盖；命名
  优先级为 Dependency alias、Contract alias、类型名推导。默认推导保持后缀移除与首字母小写，
  不增加可能随版本变化的 acronym 启发式。Contract alias 进入 metadata 和 shape fingerprint。
- [x] 命名空间 Facade 已评估但不纳入当前 API：全局 `Network.client` 会引入导入冲突并隐藏
  消费组件 caller identity；当前使用 `<Component>Services.network`。只有生产场景证明两层命名
  的收益后，才评估组件局部 `<Component>Api.network.client`，且仍必须保留独立 Proxy、Owner
  校验和 Trace 归属。
- 完整方法矩阵、生命周期、错误和回退见
  [Service Proxy 自动生成设计](../../CCRouter-service-proxy-generation-design.md)。
- CLI 2.0 再考虑契约提升、Override、迁移和一键校验。

## 5. 验收门槛

- 所有 Provider 标识校验在注册阶段确定失败，不依赖解析顺序。
- App/Session/Route/`singleton`/`newInstance` 的生命周期测试全部保持通过。
- Session close、Runtime dispose、实例构造失败和 disposal timeout 不产生实例残留。
- Service 性能回归使用同机 P50/P95 趋势比较，不设置跨机器硬阈值；性能样本必须同时验证
  Scope 销毁后的存活实例为零。
- 同一 Token 的类型不匹配、重复默认实现和命名冲突均返回稳定错误。
- 冷生成必须直接从 Contract annotation 一次完成 Token、Provider、Component assembly、
  Package Index 与 Host Catalog；不能依赖先生成 Token、第二次再识别 Provider。
- Service metadata 的新增、内容变化、重命名和删除必须使缓存失效；缓存与 `--no-cache`
  输出逐字节一致。
- 没有 `serviceDependencies` 的组件不得生成空 Service API；删除最后一个声明后清理陈旧受管文件。
- Core Service 契约不依赖 BuildContext、反射、字符串方法调用或万能 Map；Flutter
  `routeService(context)` 只读取精确 Host 绑定，不参与实例所有权或销毁判断。
