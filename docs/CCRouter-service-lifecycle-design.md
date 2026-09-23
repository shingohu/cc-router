# CCRouter Service 生命周期设计

## 1. 目标与边界

Service 是组件提供、通过稳定契约访问、由 Runtime 管理生命周期的长期能力对象。
它不是页面状态容器、全局事件总线、路由代理或通用 RPC 接口。

Service 生命周期回答“谁拥有实例、何时销毁”；实例创建方式单独由
`CCServiceCreationPolicy` 表达。页面显示/隐藏、一次调用和每次创建不属于同一个维度。

## 2. 两个独立维度

```text
Service Lifetime        App / Session / Route
Service Creation Policy Singleton / Factory
Service Readiness       Synchronous / Lazy async initializer
```

### 2.1 Lifetime

| Lifetime | Owner | 创建/销毁边界 | 典型场景 |
| --- | --- | --- | --- |
| App | Runtime | 首次解析创建，Runtime dispose 时销毁 | 网络客户端、配置、日志、埋点 |
| Session | 登录 Session | Session 打开后首次解析，closeSession 时销毁 | 账号信息、购物车、用户缓存 |
| Route | 一个具体 RouteEntry | RouteEntry 创建期间创建，Entry 最终移除后销毁 | 编辑控制器、页面草稿、WebView 控制器 |

App、Session 和 Route 三种 Lifetime 均已启用。Route Scope 只由 Runtime 创建、取消和
关闭；业务代码不能构造 Scope，也不能把不可用的 Lifetime 静默降级到 App Scope。1.x
不提供 Component Lifetime；组件是静态装配与能力所有权边界，不是可独立关闭的资源 Scope。

### 2.2 Creation Policy

| Policy | 语义 | 适用对象 |
| --- | --- | --- |
| Singleton | 在所属 Lifetime 内懒创建并缓存一个实例 | 有状态 Repository、客户端、缓存、控制器 |
| Factory | 每次解析创建新实例 | 无状态、不可变、轻量辅助对象 |

Factory 不代表“调用结束立即销毁”。同步解析没有可靠的 end-of-use 信号；如果 Factory
实例实现 `CCDisposable`，仍由当前父 Scope 持有并在 Scope 关闭时释放。因此需要严格释放的
资源应使用 Scope-owned Singleton 或显式操作对象，不应把 Factory 当作临时资源容器。

### 2.3 Readiness

Provider Factory 始终同步创建实例，使 Runtime 可以先把实例纳入明确 Scope。确实需要 I/O
或异步准备的 Provider 可以额外声明 `initializer`：

- `CCRouter.serviceAsync<T>()` 或生成 Proxy 的异步方法首次触发初始化；框架启动不因此变成异步。
- 同步 Proxy 方法保留契约原本的返回类型，不会隐式等待或启动 initializer；它在
  Provider 未 Ready 时抛出 `CCServiceNotReadyError`。
- Singleton 在每个 Scope 内 single-flight 初始化一次；并发调用等待同一个 Future。
- Factory 每次异步解析创建并初始化一个新实例，仍由当前 Scope 负责最终释放。
- `service<T>()` 不会隐式启动异步工作；初始化完成前返回 `CCServiceNotReadyError`。
- 初始化失败在当前 Singleton/Scope 内保持稳定，不自动重试有副作用的操作；业务重试策略应写在
  initializer 内。新的 Session 或 Route Scope 会获得新的实例和 readiness 状态。
- Session close、RouteEntry 移除和 Runtime shutdown 会取消 Owner Scope 的 readiness context；
  initializer 必须配合 cancellation，Dart Future 本身不能被强制终止。
- Singleton 初始化由 Scope 共享：单个等待者的 cancellation/timeout 只停止该等待者，不能让
  一个短生命周期调用者永久破坏整个 Scope 的共享 Service。Factory readiness 不共享实例，
  因此同时服从 caller 和 Owner Scope cancellation。
- 参数、实例和错误消息不进入 Trace；失败只保留稳定 Service identity 与 error type。

异步 Factory 返回 `Future<T>` 不纳入 1.x：实例完成前没有可交付的 Scope 所有权，关闭与晚到
结果的销毁容易产生竞态。同步 Factory + 可选 initializer 将所有权和 readiness 两个维度分开。

### 2.4 依赖生命周期矩阵

| Consumer | 允许依赖 |
| --- | --- |
| App | App |
| Session | App、Session |
| Route | App、同一个 RouteEntry 的 Route |

对象不能捕获可能先于自己销毁的依赖。Session 与 Route 是相互独立的生命周期：关闭
Session 和 Pop 页面不能互相隐式替代。App Factory 作为窄 Scope Consumer 的构造依赖时，
其 disposable 实例由 Consumer 的具体 Scope 接管，避免资源存活超过使用方。

## 3. 页面级对象与页面生命周期

页面级对象有真实使用场景，但所有权必须绑定 `RouteEntry`，不能绑定 Widget rebuild 或
`BuildContext` 生命周期。以下事件不会销毁 Route Lifetime：

- PageShow/PageHide；
- 页面被其他页面覆盖；
- Shell 分支暂时隐藏；
- Dialog、BottomSheet、Popup 或 LocalHistory 覆盖；
- App 进入后台。

只有 Managed `RouteEntry` 永久移除后才关闭 Route Lifetime。页面生命周期仍由
`CCPageLifecycleMixin` / `CCPageLifecycleListener` 提供；Service 不自动接收
`onResume`、`onPause`、`PageShow` 或 `PageHide`。

Route Service 不能通过全局 `CCRouter.service<T>()` 猜测当前页面，因为同一个页面可以
同时打开多个 Entry。自动 Flutter Host 在页面外层注入不可变 Navigation ID，页面通过
`CCRouter.routeService<T>(context)` 读取该精确绑定；这里的 `BuildContext` 只用于查找 ID，
不创建、不拥有、也不关闭 Scope。Core 仍可按 ID 在 Pure Dart 测试中完成同一语义。

初始位置、Foreign Route 和未调用 `CCRouterHostBinding.bindRouteEntry` 的手写 Host Route
没有 Managed RouteEntry，因此不能解析 Route Service。GoRouter 自动 Assembler 已完成绑定；
手写 Route builder 必须同时解包业务 Extra 并包裹 RouteEntry binding。

## 4. Session 与 App 语义

Session 表示一次账号会话，不表示 App 前后台、页面切换或闲置状态。Session close 必须：

1. 拒绝新的 Session Service 解析；
2. 取消 Scope 内未完成调用；
3. 按逆创建顺序释放实例；
4. 清空缓存并使旧实例引用失效。

App Service 只在 Runtime dispose 时释放。账号切换必须先完整关闭旧 Session，再打开新
Session；不能让旧 Service 引用自动指向新账号。

## 5. 与开源框架的对应关系

- ARouter/TheRouter 的 Singleton/NewInstance 主要是缓存和创建策略，不是页面生命周期。
- TheRouter 的 Service 用于跨模块能力；初始化任务和一次性 Action 是独立能力。
- flutter_modular 将 Module DI 与 Page State 分开，页面状态在 Route 离开时销毁。
- get_it 将 Scope 与 Singleton/LazySingleton/Factory 分开，并支持 Scope dispose。

CCRouter 采用相同的维度拆分，但保留组件所有权、RouteEntry 精确关联和类型安全契约。

## 6. 当前实施状态

- App、Session、Route 与 Singleton/Factory 已实现；Factory 使用
  `CCServiceCreationPolicy.factory`。
- `ccrouter_test` 已提供隔离 Test Host 的 Service Override；Override 只能替换已注册
  Provider，沿用原 Scope 和创建策略，默认清除生产 initializer 并可选替换为测试
  readiness；缺失或重复目标在 Host 创建阶段失败。
- Component Lifetime 已从 1.x 移除。
- Route Lifetime 已接入 Core、Flutter Facade 和 GoRouter 自动 Assembler。
- 可选 lazy async initializer、single-flight readiness、稳定失败、循环检测以及 Scope/caller
  cancellation 已实现；普通同步 Provider 不增加初始化成本。
- Page 生命周期与 Service 生命周期保持独立。
- Service Proxy 的 Runtime 与手写生成形态已验证；自动 metadata/Proxy 生成在
  真实契约数量达到实施阈值前后置。动态注册/卸载保持 2.0 候选。

完整动态组件治理属于 2.0 候选。重新评估前必须同时解决组件依赖级联、能力原子切换、
活跃 Route 协调，以及 Handler、订阅和诊断状态的确定性清理，不能只关闭一部分 Service。

## 7. 验收要求

- Scope 只决定所有权和销毁，不决定是否缓存。
- Creation Policy 只决定创建和缓存，不改变实例 Owner。
- Factory 的 `CCDisposable` 不得在单次解析结束时被错误销毁。
- Route Scope 只能由精确 RouteEntry 关闭，不能由 PageHide、Popup 或未知外部 Pop 触发。
- 所有生命周期关闭必须可取消、可等待、幂等，并通过纯 Dart 测试验证。
- Readiness 不改变实例 Owner；失败不隐式重试，等待者取消不污染 Singleton readiness，
  Factory readiness 不被 Scope 无界缓存。
