# CCRouter Event 设计与实施计划

## 1. 状态与结论

- 状态：1.x 已采用的基础事实通知能力
- 稳定契约：`CCEvent`、`CCRegistry.registerEvent`、`CCRouter.event`
- 当前不做：Sticky、历史重放、持久化队列、跨进程广播、优先级、动态订阅

Event 表示一个事实已经发生。发布者不读取订阅者结果，也不能用订阅者是否存在决定业务
成功；需要一个明确组件完成工作时必须使用 `CCCommand<R>`。

## 2. 框架参考与取舍

- [MediatR](https://github.com/LuckyPennySoftware/MediatR) 将 Request/Response 与
  Notification 分开，Notification 可由多个 Handler 处理，并支持异步发布与取消。
- [Android Broadcast](https://developer.android.com/develop/background-work/background-tasks/broadcasts)
  用于系统或应用事实通知，但跨进程、安全、后台限制和投递时机超出 CCRouter 进程内组件协作范围。
- [greenrobot EventBus](https://github.com/greenrobot/EventBus) 提供动态注册、线程模式、
  优先级和 Sticky Event；动态页面注册/反注册容易引入生命周期遗漏和不可追踪全局通信。
- ARouter、Flutter Modular 没有把通用 EventBus 作为组件化基础路由能力，说明 Event 应保持
  可选且窄，而不是成为任意业务通信入口。

因此 CCRouter 只提供静态组件装配期订阅。它吸收 Notification 的类型化多订阅者语义，
不复制移动端全局 EventBus 的页面级动态订阅、线程调度、Sticky 和优先级。

## 3. 真实使用场景

适合 Event：

- `OrderCreated` 后，Analytics、Coupon 和消息组件分别更新自己的状态；
- 登录或退出已经完成后，多个组件清理各自缓存；
- 配置同步已经完成后，独立组件使本地只读缓存失效；
- 一个组件完成数据变更后，通知其他组件自行刷新，而发布者不依赖刷新结果。

不适合 Event：

- 创建订单、支付、请求权限等必须知道业务结果的操作，使用 Command；
- 获取当前用户、购物车或配置状态，使用 Service；
- 页面跳转，使用 Route；
- 应用启动依赖顺序，使用初始化任务；
- 不能丢失、必须重放或需要事务一致性的消息，使用持久化消息基础设施；
- 页面内短生命周期状态，使用现有状态管理或局部 `Listenable`/Stream。

## 4. 投递语义

1. Event 类型是类型安全路由键；每个订阅者 ID 在一个 Runtime 内全局唯一。
2. 订阅者由组件 Registrar 静态注册，生命周期等于 Runtime，不提供业务动态 unsubscribe。
3. 匹配订阅者按稳定 ID 确定启动顺序，随后并发执行；不保证完成顺序。
4. `CCRouter.event` 返回 `Future<void>`，等待当前匹配订阅者完成。
5. 零订阅者是成功 no-op，并产生发布 Trace；它不是配置错误。
6. 单个订阅者异常不会使发布失败，也不影响其他订阅者；错误只形成脱敏、有界诊断。
7. 整体 timeout、调用方 cancellation 和 Runtime shutdown 会终止发布 Future，并向订阅者
   Context 传播 cooperative cancellation。Dart 不能强制中断忽略 cancellation 的代码。
8. 每个订阅者拥有独立子 Span，记录稳定 Subscriber ID、可信组件 Owner、状态和耗时，
   不记录 Event 字段、异常消息或业务对象。
9. 从 Command 或 Service 调用链发布时，可信父组件身份作为 caller 传播；根业务调用不猜测来源。

## 5. API 示例

```dart
final class OrderCreated implements CCEvent {
  const OrderCreated(this.orderId);

  final String orderId;
}

registry.registerEvent<OrderCreated>('analytics.order-created', (
  event,
  context,
) async {
  await analytics.trackOrder(event.orderId);
});

await CCRouter.event(
  OrderCreated(orderId),
  timeout: const Duration(seconds: 3),
);
```

Event 契约应放在发布者和订阅者共同依赖的契约 Package。Subscriber 留在实现组件中。

## 6. 失败与一致性边界

Event 是 best-effort 进程内通知。发布成功只表示本次已安装订阅者完成或其失败已被隔离，不表示
跨组件事务提交。关键账务、支付确认、离线补偿和必须送达的 Analytics 不能依赖此 API。

发布者不应在 Event 后读取“处理数量”或根据 Subscriber 失败回滚自身业务；需要这种协作时，
应使用一个明确 Owner 的 Command/Service 编排，或等待有真实需求后设计 Action Pipeline。

## 7. 已完成实施项

- [x] 静态类型化订阅与全局稳定 Subscriber ID 校验。
- [x] 确定启动顺序和并发投递。
- [x] 零订阅者成功语义。
- [x] Subscriber 失败隔离和有界脱敏诊断。
- [x] 整体 timeout、cancellation 与 Runtime shutdown 传播。
- [x] 每个 Subscriber 的独立 Trace、可信 Owner 与嵌套 caller 关联。
- [x] Pure Dart 测试覆盖并发、失败、空订阅、重复 ID、超时和诊断。

## 8. 生成器决策

Event 类型与 Registrar 注册当前都很少变化，注解生成的收益不足以抵消公开 Annotation、metadata
和增量构建复杂度。1.x 保持手写注册；只有真实组件出现重复订阅样板、跨包契约漂移或 DevTools
静态索引需求时，再与 Service/Command 生成统一评估。
