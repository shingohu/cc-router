# CCRouter 初始化任务设计与实施计划

## 1. 状态与结论

- 状态：Runtime 与注解生成器闭环已实现
- 稳定入口：`CCRegistry.registerInitTask`、`CCRouter.runInitTasks`
- 已实现：Task Contract、Handler 注解、注册桥接、metadata、DAG 文档和 Workspace 校验
- 当前不做：自动重试、主线程标记、Session/前台周期任务、跨 Isolate 调度

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

命名边界：`CCRouter.initialize()` 建立并同步校验默认 Runtime；`CCRouter.shutdown()` 由应用
Owner 关闭它。`runInitTasks(gate: ...)` 是 InitTask Gate 执行入口，不是第二次初始化 Runtime；一次
调用可能执行零个、一个或多个新就绪任务。`CCInitTaskGate` 一旦打开就在当前 Runtime 生命周期
内保持打开，已经完成或失败的任务不会通过再次调用自动重试。

1. 组件在 Registrar 中注册 `CCInitTaskDefinition`，Owner 由 Runtime 注入。
2. `CCRouter.initialize()` 同步校验任务 ID、Gate、依赖、timeout、缺失节点和循环，不执行任务。
3. Host 在适当时机调用 `await CCRouter.runInitTasks(gate: CCInitTaskGate.appStarted)` 打开普通启动 Gate。
4. 隐私同意后调用 `await CCRouter.runInitTasks(gate: CCInitTaskGate.privacyGranted)`。
5. 其它自定义条件使用带稳定 ID 的 `const CCInitTaskGate`，例如远程配置完成。
6. Gate 打开后，依赖全部成功的同层任务按 ID 确定启动顺序，并发执行。
7. 同一 Runtime 中每个任务最多运行一次；重叠调用共享一个 single-flight DAG drain。
8. `required` 与 `optional` 业务失败都记录到不可变 `CCInitTaskRunResult`、Snapshot、Trace 和
   Diagnostics，不再由 `runInitTasks(gate: ...)` 默认抛出。
9. 失败不阻止独立任务和未来 Gate；仅依赖失败节点的任务标记为 `skipped`。
10. 每个任务有独立 timeout、cooperative cancellation、Trace Span、Owner 和耗时快照。
11. 无法降级的 Host 显式调用 `result.throwIfRequiredFailed()`；普通 Host 根据结果渲染自己的
    恢复或降级体验，不向生产用户展示框架异常。
12. Runtime shutdown、取消和非法状态仍直接抛出；shutdown 会取消并等待当前 DAG drain 收口，
    不允许任务在销毁后被标记成功。

Gate 只控制“何时允许执行”，不替代依赖。先打开 `privacyGranted` 而 `appStarted` 依赖尚未
运行时，任务继续 pending；后续打开 `appStarted` 后 Runtime 自动执行完整可达层。

## 5. API 示例

```dart
registry.registerInitTask(
  CCInitTaskDefinition(
    id: 'foundation.logging',
    gate: CCInitTaskGate.appStarted,
    failurePolicy: CCInitTaskFailurePolicy.required,
    run: (context) => logging.initialize(),
  ),
);

registry.registerInitTask(
  CCInitTaskDefinition(
    id: 'analytics.sdk',
    dependsOn: const ['foundation.logging'],
    gate: CCInitTaskGate.privacyGranted,
    failurePolicy: CCInitTaskFailurePolicy.optional,
    timeout: const Duration(seconds: 3),
    run: (context) => analytics.initialize(context.cancellation),
  ),
);

CCRouter.initialize(
  components: ccrouterGeneratedComponentManifests,
);
final initResult = await CCRouter.runInitTasks(
  gate: CCInitTaskGate.appStarted,
);
// 只有无法降级的 Composition Root 才启用严格模式：
// initResult.throwIfRequiredFailed();

// 用户明确同意隐私协议后：
await CCRouter.runInitTasks(gate: CCInitTaskGate.privacyGranted);
```

## 6. 失败、重试与降级

- Runtime 只保留错误类型，不保留原始异常消息或任务输入。
- 失败任务不会自动重试，避免重复初始化 SDK、数据库或有副作用资源。
- 需要网络重试的组件应把重试限制在任务实现内部，并保持 deadline/cancellation 可观察。
- `optional` 只表示不阻止独立任务，不表示依赖它的任务可以忽略失败。
- `required` 表示 Host 需要明确处理该失败，不表示 Runtime 自动阻止 `runApp()`；默认返回结果，
  严格启动由 Host 显式调用 `throwIfRequiredFailed()`。
- required 任务不能直接或间接依赖 optional 任务，避免“必需启动链”由可选能力决定。

## 7. 当前稳定 ID 与硬编码治理

任务 ID 和 Gate ID 是诊断、依赖 DAG、生成文档和跨组件协作的稳定机器标识，不能改成
随机值、对象身份或运行时类名推导。当前实现仍使用字符串，但必须遵守以下边界：

1. 组件内部任务 ID 集中放在组件自己的不可变常量类中，例如
   `DemoInitTaskIds`，Registrar、页面和测试不得重复书写同一个字符串。
2. 需要由 Host 或其他组件打开、依赖或观察的 Gate/任务 ID，放到独立的公共 Contract
   Library；实现包不能要求调用方导入 `src` 或 Registrar。
3. ID 使用组件或能力前缀，例如 `analytics.foundation`、`app.privacy.granted`，避免
   仅使用 `startup`、`ready` 等全局模糊名称。
4. `enum` 不能替代对外稳定 ID，因为枚举成员重命名可能意外改变诊断和依赖语义。
5. 生成器由显式 `CCInitTaskContract` 或 `@CCInitTask(id: ...)` 提供稳定 ID，并在
   生成阶段校验重复 ID、缺失依赖、循环依赖和跨 Package Contract exposure；运行时仍保留
   最终校验。

这种约定只收敛标识符来源，不把插件实现参数、隐私策略或业务配置提升到公共 Contract。
降级应在任务内部切换到明确的备用实现；框架不猜测替代任务。

## 8. 已完成实施项

- [x] 静态任务注册、可信组件 Owner 和最小业务 Facade。
- [x] 缺失依赖、重复 ID、自依赖、重复依赖、非法 Gate/timeout 和 DAG cycle 校验。
- [x] Gate、分层并发、稳定启动顺序、single-flight 和 exactly-once。
- [x] required/optional、失败分支隔离、显式严格模式和脱敏结果。
- [x] per-task timeout、Runtime shutdown cancellation 和销毁等待。
- [x] 有界 Trace 与不可变脱敏快照。
- [x] Pure Dart 测试覆盖并发、Gate、失败、校验、timeout、取消和幂等。

## 9. 生成器问题与决策

Runtime 能正确执行 InitTask，但手写注册存在以下生成期缺口：

- 任务 ID、依赖 ID 和 Registrar 代码需要重复维护，重命名或跨组件移动后容易漂移；
- Workspace 无法在构建期验证 Contract Owner、跨 Package exposure 和完整 DAG；
- Catalog 与 `ccrouter find` 负责定位任务、Gate 和源码位置；`ccrouter_devtools` 负责展示运行时
  任务状态、Gate 和依赖边；
- 重复 ID、缺失依赖和循环依赖只能在应用初始化时发现，反馈过晚。

不扫描 Registrar、Contribution 闭包或函数体猜测任务关系。这类启发式发现会遗漏动态注册，
也无法证明跨 Package 可见性。采用显式 Task Contract、顶层 Handler 注解和类型化依赖引用，
由生成器完成注册桥接、metadata、DAG 和静态校验；Runtime 保留所有最终边界校验。

InitTask 没有业务调用方，不生成类似 Route Intent、Service Proxy、Command Client 或 Event
Publication Client。Host 仍只通过 Gate 统一触发可达任务，不逐个调用任务。

## 10. 推荐声明模型

可被其它任务依赖或需要跨 Package 暴露的任务声明稳定 Contract：

```dart
const foundationLoggingInitTask = CCInitTaskContract(
  id: 'foundation.logging',
  componentId: foundationComponentId,
  description: '准备应用日志基础设施。',
);

const analyticsSdkInitTask = CCInitTaskContract(
  id: 'analytics.sdk',
  componentId: analyticsComponentId,
  description: '在隐私授权后初始化 Analytics SDK。',
);
```

Owner 实现 Package 使用顶层 Handler 注解声明执行配置：

```dart
@CCInitTask(
  contract: analyticsSdkInitTask,
  dependsOn: [foundationLoggingInitTask],
  gate: CCInitTaskGate.privacyGranted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
  timeout: Duration(seconds: 3),
)
Future<void> initializeAnalytics(
  CCInvocationContext context,
) async {
  await analytics.initialize(context.cancellation);
}
```

完全位于组件内部、不会成为其它任务依赖目标的独立任务可以省略 Contract：

```dart
@CCInitTask(
  id: 'analytics.cache_warmup',
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
)
Future<void> warmupAnalyticsCache() async {}
```

此时生成器创建 package-private 的任务描述。`contract` 与 `id` 必须且只能设置一个；一个内部
任务一旦需要被其它任务引用，就提升为显式 `CCInitTaskContract`。组件内 Contract 可以保持
Package 私有，只有真实跨组件依赖才通过公共 contracts Package barrel 导出。

`CCInitTaskGate` 已经是带稳定 ID 的类型化值，因此不再增加语义重复的 Gate Contract。
`CCRouter.runInitTasks`、`@CCInitTask` 和手写 `CCInitTaskDefinition` 都要求显式 Gate，避免
开发者无意依赖隐式启动时机。框架内置 `appStarted` 与 `privacyGranted`；CLI Scaffold 会
显式生成 `appStarted`，自定义 Gate 使用公共 `const CCInitTaskGate`，
由 Host 在条件成立时显式打开。跨 Package 使用的 Gate 必须从公共 contracts Package 导出；
它是普通 Dart 常量，由 Analyzer 的 Package API 边界校验，不额外建立第二套 Gate 注册表。

为了让 `CCInitTaskContract`、`@CCInitTask`、Gate 和 failure policy 都能被 Pure Dart contracts
Package 使用，实施时应把纯值类型 `CCInitTaskGate` 与
`CCInitTaskFailurePolicy` 下沉到 `ccrouter_contracts`。`ccrouter` 与 `ccrouter_core`
继续通过现有公共 barrel 转出这些类型，业务侧导入方式和 Runtime 语义不变。

## 11. Handler 约束

第一阶段只允许公开、顶层、非泛型函数，签名必须是以下之一：

```dart
void task();
Future<void> task();
FutureOr<void> task();
void task(CCInvocationContext context);
Future<void> task(CCInvocationContext context);
FutureOr<void> task(CCInvocationContext context);
```

不允许实例方法、泛型函数、多参数、可选/命名参数、业务返回值、`BuildContext` 或注解中的任意
闭包。任务依赖的能力通过现有 Service/Composition Root 获取；生成器不从函数体推断依赖，
也不创建第二套隐式依赖注入容器。

## 12. 生成物与 API 隔离

```text
lib/src/ccrouter_generated/
├── init_task/...init_task.g.dart
├── component/...component.g.dart
└── metadata/ccrouter_package.json
```

- `init_task.g.dart` 包含 Package 内部 Handler registration bridge；
- 现有 `component.g.dart` 直接聚合任务桥接，不再增加一层 capability bridge；
- 现有 Package/Host Catalog 聚合任务、Gate、Owner 和依赖边，不新增独立 InitTask Catalog 文件；
- 现有 metadata 记录稳定 ID、Owner、Gate、失败策略、timeout、依赖及可移植源码位置；
- `cc_catalog.md` 从同轮 metadata 派生可读 DAG，并支持 `ccrouter find`；运行时任务状态和
  依赖边由只读 `ccrouter_devtools` 面板展示；
- 没有 InitTask 声明时不创建相关文件或空目录；
- 业务 barrel 只导出真实跨组件使用的 Contract/Gate，不公开生成注册控制器。

生成代码等价于当前手写 `CCInitTaskDefinition` 注册，但生成 SPI 保持内部可见；业务代码不能
直接执行 Handler，也不能伪造 Owner 或绕过 Gate。

## 13. 生成期校验

1. Task ID 全 Workspace 唯一并符合稳定 ID 语法，Contract Owner 必须存在，description 必须
   满足长度和安全文本限制。
2. `contract` 与 `id` 必须且只能设置一个；同一 Contract 只能有一个 Handler。
3. Handler 所在组件必须等于 Contract Owner，且签名满足第 11 节约束。
4. `dependsOn` 只接受 `CCInitTaskContract` 常量，禁止字符串依赖和实现函数引用。
5. 依赖必须存在，禁止自依赖、重复依赖和 DAG cycle。
6. 跨 Package Contract 必须经 Generator 检查的 public barrel 导出；跨 Package Gate 作为普通
   Dart 常量由 Analyzer 检查 Package API 边界。调用侧必须具有合法依赖，不能导入其它
   Package 的 `src` 或生成实现文件。
7. 跨组件硬依赖的 Task Owner 必须出现在当前组件的 required `dependencies`；optional
   component 不能满足一个必须成功的 DAG 依赖。
8. Gate ID 必须合法；同一 ID 的 Gate 声明必须一致。
9. failure policy 必须显式声明为受支持的枚举值；required Handler 必须使用
   `CCInitTaskContract`，不能只提供内部字符串 ID。
10. timeout 必须大于零；异步 required Handler 必须声明正 timeout。
11. required 任务不能直接或间接依赖 optional 任务；Generator 和 Runtime 都拒绝该 DAG。
12. 生成错误必须包含 Package、组件、任务 ID、依赖和源码位置。

Generator 校验不替代 Runtime。手写 Contribution、自定义 Registrar、陈旧生成物或外部 Package
仍可能进入运行时边界，因此 Runtime 继续拒绝重复 ID、缺失依赖、非法 Gate/timeout 和循环。

## 14. Runtime 与生命周期保持项

- `CCRouter.initialize()` 继续同步完成配置和组件装配，不隐式执行异步任务；
- Host 继续通过 `CCRouter.runInitTasks(gate: ...)` 明确打开 Gate；
- 同一 Runtime 中任务保持 single-flight、exactly-once 和同层稳定启动/并发执行；
- `runInitTasks(gate: ...)` 返回不可变 `CCInitTaskRunResult`；required/optional 失败不会默认抛出，失败依赖
  分支 `skipped`，无关分支和未来 Gate 继续；
- `throwIfRequiredFailed()` 是 Composition Root 的显式严格模式，不是 Runtime 默认策略；
- per-task timeout 作为任务失败进入结果，Runtime shutdown/cancellation 仍直接终止调用；
- Runtime shutdown 负责取消并等待当前 DAG drain，组件停用、Session 关闭和页面 Pop 不触发任务销毁；
- Trace、Snapshot 和应用诊断继续只保留稳定 ID、Owner、状态、耗时及脱敏错误类型；
- 生成器不生成或执行任意启动业务逻辑，Handler 始终由开发者手写。

## 15. 已完成实施与回归

1. [x] 将 Gate/failure policy 纯值契约下沉到 `ccrouter_contracts`，新增 `CCInitTaskContract` 和
   `@CCInitTask` 声明模型，并保持现有公共 barrel 导入兼容。
2. [x] 实现单 Package Contract/Handler 发现、签名校验和 registration bridge。
3. [x] 直接接入现有私有组件 Registrar，并覆盖无声明时不生成文件或目录。
4. [x] 扩展现有 Package metadata/Host Catalog、Workspace 聚合、跨 Package Contract exposure 和完整 DAG 校验。
5. [x] 扩展 `ccrouter find` 和现有 Markdown Catalog 的 DAG 视图，不增加业务调用 Client。
6. [x] Demo 覆盖 `appStarted`、隐私授权、自定义 Gate、依赖并发、optional 失败、skip、timeout
   和 Runtime shutdown。
7. [x] 回归 Generator golden/增量/清理/`--check`、Runtime 手写兜底、Analyzer、Demo、并发、
   诊断脱敏和资源释放。
8. [x] 更新 README 与 Integration Skill 的使用示例和能力状态。

## 16. 明确不纳入本轮

- 自动重试、周期任务、前后台重复任务和持久化任务；
- Page、Route 或 Session Scope InitTask；
- Runtime 动态增加或移除任务；
- 线程、主线程、Isolate 或 `background = true` 之类无法兑现的调度标记；
- 隐式预热所有 Lazy Service；
- 根据函数名、函数体、Registrar 闭包或依赖 Package 猜测任务和依赖；
- 业务逐任务调用 API，或把 InitTask 扩展成通用后台任务调度器。
