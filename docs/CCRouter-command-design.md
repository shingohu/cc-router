# CCRouter Command 设计与实施计划

## 1. 状态与结论

- 状态：1.x 已采用的基础组件通信能力
- 稳定契约：`CCCommand<R>`、`CCRegistry.registerCommand`、`CCRouter.command`
- 当前不做：Command 注解与自动生成、重试、幂等去重、持久化队列、远程 Command

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

## 6. 生成器决策

当前手写 Command 定义和一条 Registrar 注册代码成本低，且没有足够生产样本证明注解能减少
复杂度。1.x 不增加 Command 注解、metadata 或代理。只有出现多个生产 Package 重复注册、
跨包契约漂移或确切的文档生成需求时，才与 Service 生成一起重新评估。

## 7. 已完成实施项

- [x] 保留 `CCCommand<R>`，支持类型化结果和 `void`。
- [x] 删除行为相同但无法保证纯读取的 Query 能力链。
- [x] 删除不具备优先级、短路和来源策略的旧 Action 原型。
- [x] Command Handler 保留可信组件 Owner，并写入 Trace。
- [x] 覆盖重复注册、缺失 Handler、timeout、取消、嵌套调用和 Runtime dispose。
- [x] 保持诊断缓存有界，不记录参数与返回对象。

## 8. 后续候选

幂等键、受控重试和 Command Middleware 必须由真实支付、订单或 Native Bridge 场景驱动。
引入前需要先冻结重复请求语义、错误分类、可取消边界和脱敏 Trace，不在 1.x 预先开放占位 API。
