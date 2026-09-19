# CCRouter

Flutter 组件化运行时的 v0.1 原型。目前先实现不依赖 Flutter 和 `BuildContext` 的纯 Dart 核心，尚未完成架构文档中的全部功能。

## Workspace

- `packages/ccrouter_contracts`：消息契约、Service Key、调用上下文、取消信号与标准错误。
- `packages/ccrouter_core`：组件装配、服务注册与解析、Scope、消息调度和有界诊断记录。
- `packages/ccrouter`：公开静态门面和 Zone Runtime 隔离入口。
- `packages/ccrouter_go_router`：默认的 GoRouter 导航适配器。
- `packages/ccrouter_test`：隔离测试 Host 和 CCRouter 全量回归测试。
- `demo`：包含 Android、iOS、macOS、Web 和 OHOS 平台目录的 Flutter 开发工程。

要求 Dart SDK >= 3.9。包之间使用 SemVer 依赖，由 Pub Workspace 本地解析，不使用 `path:`。在私有 Hosted 配置完成前，所有包暂时设置为 `publish_to: none`。

```sh
fvm flutter pub get
dart analyze
fvm flutter test packages/ccrouter_test/test

# Flutter 示例（从 demo 目录执行）
cd demo
fvm flutter pub get
fvm flutter run
```

## 当前行为

业务 App 通过同步的 `CCRouter.initialize(components: ...)` 原子初始化框架全局配置和完整的启动期组件集合。`CCRouter` 内部创建并持有默认 Runtime，业务代码不直接管理它；App 退出或宿主销毁时等待异步的 `CCRouter.shutdown()`。默认 Runtime 存活期间重复初始化会明确失败，启动组件集合不能在初始化后追加或替换。

组件使用 `CCComponentManifest` 与手工 `CCComponentRegistrar` 装配。Runtime 检查重复组件 ID、必需依赖、循环依赖和重复能力；Registrar 按依赖顺序与稳定 ID 顺序执行。未来生成器生成同样的 Registrar。

Service 支持强类型默认实现、命名实现、懒创建和构造期间的循环依赖检测。无 Key 的 Provider 为默认实现，命名 Provider 可显式设为默认；禁止多个默认实现。`serviceOrNull` 只允许缺失注册，不吞掉 Factory 或 Scope 错误。

App 和 Session Scope 缓存实例。用户登录成功或恢复有效登录态后调用 `CCRouter.openSession(accountId: ...)`；主动退出、Token 失效、账号切换或强制下线时调用 `closeSession()`。App 进入后台和页面切换不关闭 Session。关闭时取消 Scope 信号并按逆构造顺序销毁实例，重新登录创建新的 Session ID 和服务实例。App Factory 不允许捕获 Session Service。

每次被 Runtime 接受的导航都会创建独立的 RouteEntry 和 Route Scope。Entry 按 `resolving -> pushed -> visible -> hidden -> popping -> removed -> disposed` 记录生命周期；页面被覆盖、重建或 App 进入后台不会关闭 Scope，只有 Entry 永久离开导航结构时才会关闭。Runtime 销毁时会等待尚未完成的 Route Scope 关闭，并通过有界事件记录提供诊断信息。

Command/Query 一对一返回强类型异步结果，支持超时和取消，并向嵌套调用传递 Deadline、取消信号和 Trace。取消是协作式的：框架结束等待并通知 Handler，不会强行停止 Dart 代码或回滚副作用。同步阻塞代码不能被 Timer 抢占。

Action 按 Handler ID 串行执行，首个错误结束调用；Event 并行发送且订阅者失败隔离。Event 返回 `Future<void>`，供调用者等待本次分发完成。诊断记录有界且不记录业务参数或异常消息。

业务工程只导入 `package:ccrouter/ccrouter.dart`。该门面不导出 `CCRouterRuntime`、`CCScope` 或 `CCScopeState`；组件 Registrar 只接收注册能力受限的 `CCRegistry`。`CCRouterRuntime.forTesting` 仅保留给 `ccrouter_core` 自身的低层回归测试使用；面向框架使用者、组件作者、测试宿主、Mock 和集成测试的测试 API 与新增测试统一放入独立的 `ccrouter_test` 包，业务生产代码不得导入 `ccrouter_core/src/` 或依赖 Core 内部测试入口。

## 后续里程碑

1. Route Contract、URL Codec、RouteEntry、Route Scope 和 Flutter Navigator 2.0 适配器（基础能力已完成，适配器持续补齐后端差异）。
2. 注解、Registrar 聚合和代码生成阶段校验。
3. Service Proxy、方法级拦截、Scope 失效检查与 Middleware。
4. InitTask DAG/Gate、组件作用域、`activateComponent` / `deactivateComponent`、Mock Override 和专用测试包。
5. 契约版本与可见性检查、诊断导出和私有 Hosted 发布流水线。

当前返回真实 Service 实例，尚无生成代理，不能拦截旧实例的方法调用或自动追踪 Service 方法。当前 Trace 覆盖消息调度，不包含 Service 方法、导航或 Native 调用。Action 优先级/短路、组件版本兼容与构建期校验也尚未实现。

路由 Runtime 已支持按稳定 ID 排序的全局拦截器、按路由声明顺序执行的路由拦截器、类型安全 Intent/URI 重定向、可信 Origin 继承、取消和重定向循环检测，以及 RouteEntry/Route Scope 生命周期追踪。注解生成器和路由文档导出仍待实现。

完整目标见 [架构设计](docs/CCRouter-v0.1-architecture.md)，路由的详细设计见 [路由子系统设计](docs/CCRouter-route-design.md)。
