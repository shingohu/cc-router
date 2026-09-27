# CCRouter Command 设计与实施计划

## 1. 状态与结论

- 状态：Runtime 与首版静态生成闭环已完成
- 稳定契约：`CCCommand<R>`、`CCRegistry.registerCommand`、`CCRouter.command`
- 已实现：Command Contract、Handler registration、消费依赖、Owner/Consumer Client、metadata 与 Catalog
- 当前不做：重试、幂等去重、持久化队列、远程 Command、Middleware 和 Action Pipeline

`CCCommand<R>` 表示调用方请求一个明确组件完成一次操作，并等待完成、失败或类型化结果。
它是请求/响应语义，不是长期能力接口，也不是事实广播。

## 2. 取舍依据

ARouter 和 Flutter Modular 主要提供 Route、Service/DI，不强制拆分 Command 与 Query。
MediatR 虽在应用层常使用 Command/Query 名称，稳定传输边界仍收敛为单 Handler 的
`IRequest<T>`；框架无法从类型系统保证 Query 无副作用。继续暴露两个行为完全相同的 API
只会增加学习、注册和生成成本，因此 CCRouter 保留一个 `CCCommand<R>`。

TheRouter ActionManager 面向动态来源和多处理器仲裁，与一对一 Command 不同。其候选方向
单独记录在 [Action Pipeline 候选计划](CCRouter-action-pipeline-plan.md)，不进入 1.x Command。

## 3. 使用场景

适合 Command：

- 创建订单、提交支付、保存草稿等一次性状态变更；
- 请求一个组件刷新远端缓存，并等待刷新完成；
- 触发扫码、分享或 Native Bridge 操作，并取得类型化结果；
- 不需要业务结果但必须知道完成或失败的操作，使用 `CCCommand<void>`。

不适合 Command：

- 可重复读取状态或需要多个方法的长期能力，使用 Service；
- 页面跳转和页面返回值，使用 Route；
- 通知多个订阅者一个事实已经发生，使用 Event；
- 动态来源、多候选处理器、优先级与短路，等待未来 Action Pipeline；
- 启动阶段的依赖编排，使用初始化任务。

不要为了保留 CQRS 名称创建只包装一次 Service getter 的 `GetXxxCommand`。读取是否会产生
副作用是业务规则，Runtime 无法可靠验证；公开 Service 接口更直接，也更适合重复调用。

## 4. 运行时语义

1. 每个 Command 类型只能注册一个 Handler，重复注册在 Runtime 初始化前失败。
2. Handler 的组件 Owner 由组件绑定的 `CCRegistry` 注入，业务不能伪造。
3. 调用返回 `Future<R>`；`R` 可以是 `void`，此时仍保留完成、异常、超时和取消语义。
4. 未注册 Handler 抛出 `CCResolutionError`，不会降级到 Service、Route 或 Event。
5. 显式 timeout 与父调用 Deadline 取更早者；取消沿嵌套调用向下传播。
6. 嵌套调用共享 `traceId` 并创建子 Span；Trace 记录可信 `targetComponentId`。
7. Runtime dispose 会取消未完成调用；Command 不拥有 Runtime、Session 或 Route Scope。
8. Runtime 不自动重试有副作用操作，也不记录 Command 参数或返回对象。

## 5. API 示例

```dart
final class CreateOrder implements CCCommand<String> {
  const CreateOrder(this.amount);

  final int amount;
}

final class RefreshCatalog implements CCCommand<void> {
  const RefreshCatalog();
}

registry.registerCommand<CreateOrder, String>((command, context) async {
  context.cancellation.throwIfCancelled();
  return createOrder(command.amount);
});

final orderId = await CCRouter.command(
  const CreateOrder(100),
  timeout: const Duration(seconds: 5),
);
await CCRouter.command(const RefreshCatalog());
```

Command 类型、字段和结果应位于调用方可依赖的契约 Package；Handler 留在实现组件中。

## 6. 生成器问题与决策

Runtime 已能正确执行 Command，但现有手写方式仍存在以下生成期缺口：

- Handler 必须在 `CCComponentContribution` 中重复注册；
- Runtime Trace 主要依赖 `runtimeType`，缺少跨重命名稳定的 Command ID；
- Workspace 无法验证 Contract Owner、唯一 Handler 和消费组件依赖；
- 顶层页面或 UI 直接调用 `CCRouter.command` 时通常没有可信的 caller component；
- Catalog、`ccrouter find` 和未来 DevTools 无法定位 Contract、Handler 与生成入口。

不采用“扫描依赖中的所有 `CCCommand` 并全部生成”方案。该方案无法证明真实消费关系，会生成
未使用 API，并使增量构建和组件依赖图失真。采用显式 Contract、显式 Handler、显式消费依赖，
由生成器完成注册、调用入口、metadata 和静态校验。

Command 数据类、构造函数和 Handler 业务逻辑继续手写。生成器不是消息 Schema DSL，也不应从
字段或函数体猜测业务语义。

## 7. 推荐声明模型

跨组件 Contracts Package 声明稳定 Command，并显式指定 Owner：

```dart
@CCCommandContract(
  componentId: orderComponentId,
  id: 'order.submit',
  description: '提交订单并返回支付单号。',
)
final class SubmitOrderCommand implements CCCommand<String> {
  const SubmitOrderCommand(this.orderId);

  final int orderId;
}
```

仅在实现 Package 内使用的 Command 可以省略 `componentId`；生成器从该 Package 唯一的
`CCComponent` 推导 Owner。它需要跨组件后再保持 ID 不变迁移到 contracts Package：

```dart
@CCCommandContract(
  id: 'order.refresh_cache',
  description: '刷新订单组件缓存并等待完成。',
)
final class RefreshOrderCacheCommand implements CCCommand<void> {
  const RefreshOrderCacheCommand();
}
```

Owner 实现 Package 声明顶层 Handler，Command 类型与结果类型从函数签名推导：

```dart
@CCCommandHandler()
Future<String> handleSubmitOrder(
  SubmitOrderCommand command,
  CCInvocationContext context,
) async {
  context.cancellation.throwIfCancelled();
  return 'receipt:${command.orderId}';
}
```

消费组件只声明实际使用的跨组件 Command：

```dart
const paymentComponent = CCComponent(
  id: paymentComponentId,
  version: '1.0.0',
  dependencies: [orderComponentId],
  commandDependencies: [
    CCCommandDependency<SubmitOrderCommand>(alias: 'submitOrder'),
  ],
);
```

生成消费组件专属、强类型调用入口：

```dart
final receipt = await DemoPaymentCommands.submitOrder(
  const SubmitOrderCommand(42),
  timeout: const Duration(seconds: 10),
);
```

Owner 组件也为自己拥有的所有注解 Command 自动生成内部调用入口，不要求自依赖声明：

```dart
await DemoOrderCommands.refreshOrderCache(
  const RefreshOrderCacheCommand(),
);
```

已注解 Command 在组件 Package 内必须使用生成 Client，以携带经过生成期验证的 caller component
和稳定 Command ID。Workspace Validator 拒绝组件源码对已注解 Command 直接调用
`CCRouter.command`；裸入口只保留给未注解内部能力、Host Composition Root、兼容迁移和测试。
这是可诊断的架构约束而不是安全沙箱，Runtime 仍保留类型、Handler 和调用边界校验。

## 8. 生成物与边界

```text
lib/src/ccrouter_generated/
├── command/...command.g.dart
├── component/...command_api.g.dart
└── metadata/...command.json
```

- `command.g.dart` 只包含 package-internal Handler registration bridge；
- `command_api.g.dart` 生成 Owner 内部入口以及消费组件显式声明的跨组件入口；
- `command.json` 记录 Contract、Owner、结果类型、Handler、Consumer 和源码位置；
- Command Contract 本身由开发者编写，不生成 `.command.contract.g.dart`；
- 没有 Command 声明时不创建对应文件或空目录；
- 生成 SPI 只从 `ccrouter_generated.dart` 暴露，业务 barrel 不公开注册控制器。

## 9. 生成期校验

1. Contract 必须是公开、具体、非泛型类，并且只实现一个 `CCCommand<R>`。
2. 实现 Package 可以省略 `componentId` 并从唯一 `CCComponent` 推导；contracts Package 必须
   显式声明 Owner。
3. `R` 必须明确；允许 `void`，禁止 `dynamic`、Flutter、private 和 callback 类型。
4. Command 实例字段必须为 `final` 且不能有 setter；字段与 `R` 必须形成公共 Pure Dart 类型
   闭包。生成器只保证浅层不可变，集合和嵌套对象仍由开发者负责不在调用期间修改。
5. Command ID 全局唯一并符合稳定 ID 语法，description 保持有界。
6. Handler 必须是公开、顶层、非泛型函数。
7. Handler 参数只允许 `(Command)` 或 `(Command, CCInvocationContext)`。
8. Handler 同步/Future 返回必须与 `R` 类型兼容；`CCCommand<void>` 不能静默丢弃业务结果。
9. Host 依赖闭包中每个被消费的 Contract 必须有且只有一个 Handler。
10. Handler 所在组件必须与 Contract Owner 相同。
11. Consumer 必须把 Owner 放入 required `dependencies`，optional dependency 不能满足必需调用。
12. Client alias 必须是无冲突的 public lower-camel Dart 标识符。
13. 跨 Package Contract 必须通过公共 barrel 暴露，不能导入其他 Package 的 `src`。
14. 组件源码不得对已注解 Command 使用裸 `CCRouter.command`；Host 与未注解内部 Command 除外。

## 10. Runtime 与诊断调整

- `_RegisteredCommandHandler` 增加生成的稳定 `commandId`，Runtime 仍按 Dart Type 进行类型安全分派；
- Trace、错误与 Catalog 优先使用稳定 ID，不记录 Command 字段、返回对象或异常消息；
- 增加仅生成代码可见的 `CCRouterGeneratedCommandBinding`，负责注册和携带可信 caller identity；
- Owner 内部 Client 与跨组件 Consumer Client 使用同一 Binding；Host 裸调用保留 root caller 语义；
- timeout、父 Deadline、协作取消、嵌套 Trace 和 Runtime shutdown 语义保持不变；
- 手写 `CCComponentContribution` 继续作为复杂 Handler 和回退路径，不强制一次性迁移；
- 生成器不引入运行时反射、全仓递归扫描或新的 Command 生命周期资源。

## 11. 实施与回归顺序

1. 新增 `CCCommandContract`、`CCCommandHandler` 和 `CCCommandDependency` 声明模型。
2. 实现 Contract/Handler 解析、Pure Dart 类型边界和签名校验。
3. 生成 Handler registration bridge，并接入私有组件 Registrar。
4. 生成 Owner 内部与显式 Consumer 的组件专属 Command Client 和可信调用 Binding。
5. 扩展 metadata schema、Workspace Validator、Package/Host Catalog 和 `ccrouter find`。
6. Demo 把现有 typed、`void`、timeout、cancel 和 Handler error 迁移到 Owner Client，并增加真实
   跨组件调用、可信 caller/target 与裸调用门禁用例。
7. 回归 Generator 增量/清理/无输出、Runtime 并发与 shutdown、Analyzer、生成物一致性和内存释放。
8. 实现完成后再同步 README 与 Integration Skill；完成前继续标记为不支持。

## 12. 已完成实施项

- [x] 保留 `CCCommand<R>`，支持类型化结果和 `void`。
- [x] 删除行为相同但无法保证纯读取的 Query 能力链。
- [x] 删除不具备优先级、短路和来源策略的旧 Action 原型。
- [x] Command Handler 保留可信组件 Owner，并写入 Trace。
- [x] 覆盖重复注册、缺失 Handler、timeout、取消、嵌套调用和 Runtime dispose。
- [x] 保持诊断缓存有界，不记录参数与返回对象。
- [x] 生成 `CCCommandContract`、顶层 `CCCommandHandler` 注册桥与稳定 Command ID。
- [x] 为 Owner 和显式 `CCCommandDependency<T>` Consumer 生成强类型组件 Client。
- [x] 校验 Payload 不可变性、Handler 签名/结果、Owner、唯一 Handler 和组件依赖。
- [x] 接入 Package/Host metadata、Capability Catalog、源码定位和私有 Registrar。
- [x] Demo 覆盖组件内 typed/void/timeout/cancel/error 与跨组件 Contract 调用。

## 13. 明确不纳入本轮

幂等键、受控重试和 Command Middleware 必须由真实支付、订单或 Native Bridge 场景驱动。
引入前需要先冻结重复请求语义、错误分类、可取消边界和脱敏 Trace，不在 1.x 预先开放占位 API。
远程 Command、持久化队列、多 Handler 仲裁、优先级和短路属于独立能力，不得混入基础生成器。
