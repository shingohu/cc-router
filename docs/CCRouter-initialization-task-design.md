# CCRouter 初始化任务设计与实施计划

## 1. 状态与结论

- 状态：1.x 最小闭环已实现
- 稳定入口：`CCRegistry.registerInitializationTask`、`CCRouter.runInitialization`
- 当前不做：注解生成、自动重试、主线程标记、Session/前台周期任务、跨 Isolate 调度

初始化任务用于 Runtime 完成同步组件装配后，执行一次性的异步启动工作，并在多个组件之间
表达明确依赖。它不改变 `CCRouter.initialize()` 的同步语义，也不替代 Service readiness。

## 2. 框架参考与取舍

- [AndroidX App Startup](https://developer.android.com/topic/libraries/app-startup) 通过
  `Initializer.dependencies()` 表达依赖并集中初始化，适合静态 Library startup。
- [TheRouter FlowTaskExecutor](https://github.com/HuolalaTech/hll-wp-therouter-android/wiki/FlowTaskExecutor)
  提供模块自动发现、依赖任务流和异步初始化，适合大型 Android 组件工程。
- [Alibaba BeeHive](https://github.com/alibaba/BeeHive) 通过 Module 与 App 生命周期事件组织
  iOS 模块初始化，但大量生命周期 Hook 不适合作为 Flutter Pure Dart Runtime 的默认公开面。
- Flutter Modular 主要管理 Module Route/DI 生命周期，没有一套必须复制的跨组件启动 DAG。

CCRouter 吸收“静态任务 + 显式依赖 + 统一诊断”，但不复制平台线程标记、反射扫描或大量
生命周期阶段。Dart 主 Isolate 上的同步工作无法被调度器抢占；CPU 密集工作应通过显式
Isolate/Service 能力完成，而不是给任务增加一个无法兑现的 `background = true`。

## 3. 与其他能力的边界

适合初始化任务：

- 日志、Crash、数据库等基础设施按依赖顺序完成一次性准备；
- 隐私同意后初始化 Analytics、Push 等 SDK；
- Remote Config ready 后装配依赖其结果的非关键能力；
- 多个互不依赖的组件启动工作并发执行，缩短启动关键路径。

不适合初始化任务：

- 组件 Manifest、Route、Service、Command/Event 注册：保持同步静态装配；
- 某个 Lazy Singleton 实例自己的异步准备：使用 `CCServiceInitializer`；
- 登录后每个 Session 都需要重新创建的状态：使用 Session Service；
- 页面进入/退出工作：使用页面与 Route 生命周期；
- 可重复业务操作：使用 Command 或 Service；
- 定时、后台或前台周期任务：使用平台后台任务和应用生命周期设施。

## 4. 执行模型

1. 组件在 Registrar 中注册 `CCInitializationTask`，Owner 由 Runtime 注入。
2. `CCRouter.initialize()` 同步校验任务 ID、Gate、依赖、timeout、缺失节点和循环，不执行任务。
3. Host 在适当时机调用 `await CCRouter.runInitialization()` 打开 `appStarted` Gate。
4. 自定义条件使用稳定 Gate，例如 `const CCInitializationGate('privacyGranted')`。
5. Gate 打开后，依赖全部成功的同层任务按 ID 确定启动顺序，并发执行。
6. 同一 Runtime 中每个任务最多运行一次；重叠调用共享一个 single-flight DAG drain。
7. `critical` 失败抛 `CCInitializationTaskError`，后续触发继续返回同一安全失败。
8. `optional` 失败不阻止独立任务；依赖失败节点的任务标记为 `skipped`。
9. 每个任务有独立 timeout、cooperative cancellation、Trace Span、Owner 和耗时快照。
10. Runtime shutdown 取消并等待当前 DAG drain 收口；不允许任务在销毁后被标记成功。

Gate 只控制“何时允许执行”，不替代依赖。先打开 `privacyGranted` 而 `appStarted` 依赖尚未
运行时，任务继续 pending；后续打开 `appStarted` 后 Runtime 自动执行完整可达层。

## 5. API 示例

```dart
const privacyGranted = CCInitializationGate('privacyGranted');

registry.registerInitializationTask(
  CCInitializationTask(
    id: 'foundation.logging',
    run: (context) => logging.initialize(),
  ),
);

registry.registerInitializationTask(
  CCInitializationTask(
    id: 'analytics.sdk',
    dependsOn: const ['foundation.logging'],
    gate: privacyGranted,
    failurePolicy: CCInitializationFailurePolicy.optional,
    timeout: const Duration(seconds: 3),
    run: (context) => analytics.initialize(context.cancellation),
  ),
);

CCRouter.initialize(components: ccrouterGeneratedComponents);
await CCRouter.runInitialization();

// 用户明确同意隐私协议后：
await CCRouter.runInitialization(gate: privacyGranted);
```

## 6. 失败、重试与降级

- Runtime 只保留错误类型，不保留原始异常消息或任务输入。
- 失败任务不会自动重试，避免重复初始化 SDK、数据库或有副作用资源。
- 需要网络重试的组件应把重试限制在任务实现内部，并保持 deadline/cancellation 可观察。
- `optional` 只表示不阻止独立任务，不表示依赖它的任务可以忽略失败。

## 7. 稳定 ID 与硬编码治理

任务 ID 和 Gate ID 是诊断、依赖 DAG、生成文档和跨组件协作的稳定机器标识，不能改成
随机值、对象身份或运行时类名推导。当前实现仍使用字符串，但必须遵守以下边界：

1. 组件内部任务 ID 集中放在组件自己的不可变常量类中，例如
   `DemoInitializationTaskIds`，Registrar、页面和测试不得重复书写同一个字符串。
2. 需要由 Host 或其他组件打开、依赖或观察的 Gate/任务 ID，放到独立的公共 Contract
   Library；实现包不能要求调用方导入 `src` 或 Registrar。
3. ID 使用组件或能力前缀，例如 `analytics.foundation`、`app.privacy.granted`，避免
   仅使用 `startup`、`ready` 等全局模糊名称。
4. `enum` 不能替代对外稳定 ID，因为枚举成员重命名可能意外改变诊断和依赖语义。
5. 生成器后续可以从声明生成 ID 常量，并在生成阶段校验重复 ID、缺失依赖、循环依赖和
   跨 Package Contract exposure；运行时仍保留最终校验。

这种约定只收敛标识符来源，不把插件实现参数、隐私策略或业务配置提升到公共 Contract。
- 降级应在任务内部切换到明确的备用实现；框架不猜测替代任务。

## 7. 已完成实施项

- [x] 静态任务注册、可信组件 Owner 和最小业务 Facade。
- [x] 缺失依赖、重复 ID、自依赖、重复依赖、非法 Gate/timeout 和 DAG cycle 校验。
- [x] Gate、分层并发、稳定启动顺序、single-flight 和 exactly-once。
- [x] critical/optional、失败依赖 skip 和安全错误缓存。
- [x] per-task timeout、Runtime shutdown cancellation 和销毁等待。
- [x] 有界 Trace 与不可变脱敏快照。
- [x] Pure Dart 测试覆盖并发、Gate、失败、校验、timeout、取消和幂等。

## 8. 生成器决策

当前任务通常数量少且配置稳定，先手写注册更容易验证真实依赖。1.x 不增加 InitTask 注解和
metadata。只有生产组件出现重复注册、任务 ID/依赖漂移或静态启动图可视化需求时，再与
Service/Command/Event 生成统一评估；届时生成阶段应把缺失依赖和循环前移为构建错误。
