# CCRouter Service 生命周期设计

> 文档状态：架构 1.x 当前契约。公开生命周期仅包含 App、Session、Route；组件动态激活与
> 任意 Feature Scope 不属于当前实现。

## 1. 目标与边界

Service 是组件提供、通过稳定契约访问、由 Runtime 管理生命周期的长期能力对象。
它不是页面状态容器、全局事件总线、路由代理或通用 RPC 接口。

Service 生命周期回答“谁拥有实例、何时销毁”；实例创建方式单独由
`CCServiceCreationPolicy` 表达。页面显示/隐藏、一次调用和每次创建不属于同一个维度。

## 2. 两个独立维度

```text
Service Lifetime        App / Session / Route
Service Creation Policy singleton / newInstance
Service Readiness       Synchronous / Lazy async initializer
```

### 2.1 Lifetime

| Lifetime | Owner | 创建/销毁边界 | 典型场景 |
| --- | --- | --- | --- |
| App | Runtime | 首次解析创建，Runtime dispose 时销毁 | 网络客户端、配置、日志、埋点 |
| Session | 登录 Session | Session 打开后首次解析，closeSession 时销毁 | 账号信息、购物车、用户缓存 |
| Route | 一个具体 RouteEntry | Entry 存活时懒创建；退出渲染期结束后释放，精确 close 及时释放 | 编辑控制器、页面草稿、WebView 控制器 |

App、Session 和 Route 三种 Lifetime 均已启用。Route Scope 只由 Runtime 创建、取消和
关闭；业务代码不能构造 Scope，也不能把不可用的 Lifetime 静默降级到 App Scope。1.x
不提供 Component Lifetime；组件是静态装配与能力所有权边界，不是可独立关闭的资源 Scope。

### 2.2 Creation Policy

| Policy | 语义 | 适用对象 |
| --- | --- | --- |
| `singleton` | 在所属 Lifetime 内懒创建并缓存一个实例 | 有状态 Repository、客户端、缓存、控制器 |
| `newInstance` | 每次解析创建新实例 | 无状态、不可变、轻量辅助对象 |

`newInstance` 不代表“调用结束立即销毁”。同步解析没有可靠的 end-of-use 信号；如果实例
实现 `CCDisposable`，仍由当前父 Scope 持有并在 Scope 关闭时释放。因此需要严格释放的
资源应使用 Scope-owned singleton 或显式操作对象，不应把 `newInstance` 当作临时资源容器。

### 2.3 Readiness

Provider Factory 始终同步创建实例，使 Runtime 可以先把实例纳入明确 Scope。确实需要 I/O
或异步准备的 Provider 可以额外声明 `initializer`：

- `CCRouter.serviceAsync<T>()` 或生成 Proxy 的异步方法首次触发初始化；框架启动不因此变成异步。
- 同步 Proxy 方法保留契约原本的返回类型，不会隐式等待或启动 initializer；它在
  Provider 未 Ready 时抛出 `CCServiceNotReadyError`。
- Singleton 在每个 Scope 内 single-flight 初始化一次；并发调用等待同一个 Future。
- 每个 initializer 使用独立的活跃等待节点，Singleton 节点由 Scope/Provider 共享，调用
  另一个未完成 Service 时登记有计数的等待关系。两个或多个独立根形成的等待环同样抛出
  `CCCircularServiceDependencyError`，不只检查单根调用的 Zone 祖先链。
- 节点/Future 在业务 initializer 回调前发布；等待完成、调用者取消或超时后移除对应关系，
  initializer 终态和 Scope 取消时清空出边。不同 Runtime、Scope 和 Key 不混用节点。
- `newInstance` 每次异步解析创建并初始化一个新实例，仍由当前 Scope 负责最终释放。
- `service<T>()` 不会隐式启动异步工作；初始化完成前返回 `CCServiceNotReadyError`。
- 初始化失败在当前 Singleton/Scope 内保持稳定，不自动重试有副作用的操作；业务重试策略应写在
  initializer 内。新的 Session 或 Route Scope 会获得新的实例和 readiness 状态。
- Session close、Route Scope 关闭和 Runtime shutdown 会取消 Owner Scope 的 readiness context；
  initializer 必须配合 cancellation，Dart Future 本身不能被强制终止。
- Singleton 初始化由 Scope 共享：单个等待者的 cancellation/timeout 只停止该等待者，不能让
  一个短生命周期调用者永久破坏整个 Scope 的共享 Service。`newInstance` readiness 不共享实例，
  因此同时服从 caller 和 Owner Scope cancellation。
- 参数、实例和错误消息不进入 Trace；失败只保留稳定 Service identity 与 error type。

等待者取消、超时或其原 Session/Route 结束时，框架解除该等待者的内部订阅，释放 caller Zone；
共享 initializer 仍由实际 Owner 决定终态。Owner 关闭不等待业务 I/O 完成，已接纳的等待者收到
`CCInvocationCancelledError`；迟到错误被消费，不重新启动初始化。共享成功/失败分别交付到
各等待者自己的 error Zone。业务仍须处理各自返回的 Future，并负责外部任务的协作取消。

Scope、token、缓存 readiness、Scope-owned Factory 和 Singleton initializer 使用 Runtime
创建时的 Host Zone，同时保留框架 Trace、依赖关系与重入门禁；不会采用首次消费者的任意
Zone 值作为共享配置。`newInstance` initializer 继续保留 caller cancellation 链。业务上下文
应显式传参；这不保证释放业务回调自己直接捕获的对象。

异步实例构造函数返回 `Future<T>` 不纳入 1.x：实例完成前没有可交付的 Scope 所有权，关闭与晚到
结果的销毁容易产生竞态。同步实例构造函数 + 可选 initializer 将所有权和 readiness 两个维度分开。

### 2.4 依赖生命周期矩阵

| Consumer | 允许依赖 |
| --- | --- |
| App | App |
| Session | App、Session |
| Route | App、同一个 RouteEntry 的 Route |

对象不能捕获可能先于自己销毁的依赖。Session 与 Route 是相互独立的生命周期：关闭
Session 和 Pop 页面不能互相隐式替代。App `newInstance` 作为窄 Scope Consumer 的构造依赖时，
其 disposable 实例由 Consumer 的具体 Scope 接管，避免资源存活超过使用方。

## 3. 页面级对象与页面生命周期

页面级对象有真实使用场景，但所有权必须绑定 `RouteEntry`，不能绑定 Widget rebuild 或
`BuildContext` 生命周期。以下事件不会销毁 Route Lifetime：

- PageShow/PageHide；
- 页面被其他页面覆盖；
- Shell 分支暂时隐藏；
- Dialog、BottomSheet、Popup 或 LocalHistory 覆盖；
- App 进入后台。

原生 Managed 的逻辑 Entry、Flutter 渲染与 Scope 释放分为以下边界：

- 普通 Pop 先移除活动 Entry 并交付结果，退出页面及 Route Scope 保留到 Flutter 退出渲染结束，
  使转场期间 rebuild 仍可解析原 Route Service；退出期间不应启动新的业务工作。
- 精确 close 及时结束目标的结果与 Scope；覆盖页面和 Foreign Popup 不随之关闭。
- renderer 卸载本身不等于逻辑 Entry 移除；释放旧 Route/Guard 等渲染引用，保留 Entry identity、
  pending result 和 Route Scope，重挂时可继续使用。Widget State 仍服从 Flutter 生命周期。
- Runtime shutdown 取消退出渲染等待，不依赖下一帧；资源只清理一次，异步 dispose 可继续等待。

自定义 Backend 可通过 Host-only `CCNavigationRouteExitBinding` 声明退出渲染边界；业务不得调用
该 SPI。页面生命周期仍由 `CCPageLifecycleMixin` / `CCPageLifecycleListener` 提供；Service
不自动接收 `onResume`、`onPause`、`PageShow` 或 `PageHide`。

Route Service 不能通过全局 `CCRouter.service<T>()` 猜测当前页面，因为同一个页面可以
同时打开多个 Entry。自动 Flutter Host 在页面外层注入不可变 Navigation ID，页面通过
`CCRouter.routeService<T>(context)` 读取该精确绑定；这里的 `BuildContext` 只用于查找 ID，
不创建、不拥有、也不关闭 Scope。Core 仍可按 ID 在 Pure Dart 测试中完成同一语义。

原生 Managed 启动导航创建的初始页面与后续导航页面一样拥有 RouteEntry 和 Route Scope。
Foreign Route、`CCManagedOutlet.baseBuilder` 本地 surface，以及未建立精确 Entry binding 的
手写 Host Route 没有自己的 Managed Route Scope。自定义 Host 的绑定与 Extra 解包属于
Composition Root/SPI，业务页面不能手工制造 Scope 或借用底层页面的身份。

## 4. Session 与 App 语义

Session 表示一次账号会话，不表示 App 前后台、页面切换或闲置状态。Session close 必须：

1. 拒绝新的 Session Service 解析；
2. 取消 Scope 内未完成调用；
3. 按逆创建顺序释放实例；
4. 清空缓存并使旧实例引用失效。

App Service 只在 Runtime dispose 时释放。账号切换必须先完整关闭旧 Session，再打开新
Session；不能让旧 Service 引用自动指向新账号。

### 4.1 取消回调与清理失败隔离

取消通知是同步、协作式的，不得成为跳过资源清理的原因：

- Token 先确定已取消并移除其持有的回调集合，再逐个通知本次回调快照；某个回调抛错
  仍继续通知其余回调，最后向取消调用方重抛首个错误及其原始 StackTrace。
- Token 重复取消是空操作。已取消 Token 新增 Listener 时立即通知，异常直接返回给
  注册调用方；它不会重新进入 Token 持有的集合。
- Scope 在取消前建立唯一的关闭 Future，并拒绝新解析；取消错误与 Service dispose 错误
  一样进入内部 `disposalErrors`，其余实例仍逆序释放，最终进入 closed。
- Runtime 在取消前建立唯一的 shutdown Future；早期 App 取消失败不会跳过 Route、Session、
  App、Adapter 和 Listener 清理。结构化清理结束后再向 Owner 返回首个失败。
- Facade 在任何停止回调之前建立 shutdown 门禁。取消回调中再次 shutdown 只能等待
  同一轮清理，不能提前完成，也不能在旧 Runtime 尚未清理时重新 initialize。

这不赋予 Service 或页面调用 shutdown 的权限；生命周期仍由 Composition Root/Runtime
拥有。取消回调应保持同步、短小且无异常，业务不得在自己负责的 dispose 中等待同一
Owner 的关闭 Future，以免形成自等待。

## 5. 与开源框架的对应关系

- ARouter/TheRouter 的 Singleton/NewInstance 主要是缓存和创建策略，不是页面生命周期。
- TheRouter 的 Service 用于跨模块能力；初始化任务和一次性 Action 是独立能力。
- flutter_modular 将 Module DI 与 Page State 分开，页面状态在 Route 离开时销毁。
- get_it 将 Scope 与 Singleton/LazySingleton/Factory 分开，并支持 Scope dispose；CCRouter 对应语义命名为 `newInstance`。

CCRouter 采用相同的维度拆分，但保留组件所有权、RouteEntry 精确关联和类型安全契约。

## 6. 当前实施状态

本文件维护 Provider、Scope、readiness 和释放语义；生成 Client 的声明与方法支持矩阵只在
[Service Proxy 规范](CCRouter-service-proxy-generation-design.md)维护。原实施计划已合并，
阶段顺序与旧 benchmark 记录见[合并归档](archive/20261024-consolidation/README.md)。

- App、Session、Route 与 `singleton`/`newInstance` 已实现；每次解析创建使用
  `CCServiceCreationPolicy.newInstance`。
- `ccrouter_test` 已提供隔离 Test Host 的 Service Override；Override 只能替换已注册
  Provider，沿用原 Scope 和创建策略，默认清除生产 initializer 并可选替换为测试
  readiness；缺失或重复目标在 Host 创建阶段失败。
- Component Lifetime 已从 1.x 移除。
- Route Lifetime 已接入 Core、Flutter Facade 和原生 Managed Host；GoRouter 兼容包已移除。
- 可选 lazy async initializer、single-flight readiness、稳定失败、循环检测以及 Scope/caller
  cancellation 已实现；普通同步 Provider 不增加初始化成本。
- Page 生命周期与 Service 生命周期保持独立。
- Service Proxy Runtime、`@CCServiceContract` Token、`@CCService` Provider registration、
  自动 Registrar 和 metadata/Catalog 已实现。消费组件通过显式
  `CCServiceDependency<T>` 生成方法级 Proxy；Proxy 每次调用解析当前 Scope，不拥有实例，
  Session 切换后不会保留旧 Provider。动态注册/卸载保持 2.0 候选。

完整动态组件治理属于 2.0 候选。重新评估前必须同时解决组件依赖级联、能力原子切换、
活跃 Route 协调，以及 Handler、订阅和诊断状态的确定性清理，不能只关闭一部分 Service。

## 7. 验收要求

Provider 的 Contract ID/Key 在注册时验证稳定语法；多个默认实现、重复 Key、Token 类型不匹配、
未打开的 Session 和构造依赖环都返回相应 Service 错误，不能依赖解析顺序碰巧成功。
跨组件调用使用显式 required Owner 与精确消费依赖；不从 Pub 依赖图猜测 Service。

测试使用 `CCRouterTestHost` 的 Override，替换已注册 Provider，并沿用其 Lifetime/创建策略。
默认清除生产 initializer，需要时显式安装测试 readiness；缺失或重复目标在 Test Host 创建时
失败。Zone-local Overlay 不修改默认 Runtime，也不接管生产 Host Backend 或 initialize/shutdown。

Invocation 诊断只记录稳定 Service/Key/method/caller/Owner identity、Scope、Trace、耗时与终态，
不记录参数、业务返回值或原始异常文本。性能验证须同时确认 Scope 关闭后的 disposable 实例
归零；同机 P50/P95 只证明对应样本，不用历史 benchmark 声称当前性能。

- Scope 只决定所有权和销毁，不决定是否缓存。
- Creation Policy 只决定创建和缓存，不改变实例 Owner。
- `newInstance` 创建的 `CCDisposable` 不得在单次解析结束时被错误销毁。
- Route Scope 只能由精确 RouteEntry 关闭，不能由 PageHide、Popup 或未知外部 Pop 触发。
- 所有生命周期关闭必须可取消、可等待、幂等，并通过纯 Dart 测试验证。
- Readiness 不改变实例 Owner；失败不隐式重试，等待者取消不污染 Singleton readiness，
  `newInstance` readiness 不被 Scope 无界缓存。
