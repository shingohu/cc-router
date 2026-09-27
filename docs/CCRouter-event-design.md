# CCRouter Event 设计与实施计划

## 1. 状态与结论

- 状态：Runtime 与生成器能力已完成
- 稳定契约：`CCEvent`、`CCRegistry.registerEvent`、`CCRouter.event`
- 已实现：Event Contract、静态 Subscription、Owner 自动 Publication Client、metadata、Catalog 和 Workspace 校验
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

## 8. 生成器问题与决策

Runtime 已具备正确的多 Subscriber 语义，但现有手写方式仍存在以下生成期缺口：

- Event 类型没有跨重命名稳定的 Event ID，发布 Trace 主要依赖 `runtimeType`；
- Subscriber ID、类型和 Registrar 代码重复手写；
- Workspace 无法生成 Event、Publisher、Subscriber 的静态关系图；
- 构建期不能发现重复 Subscriber ID、非法函数签名和组件依赖错误；
- 根业务调用 `CCRouter.event` 时通常没有可信 publisher component；
- Catalog、`ccrouter find` 和未来 DevTools 无法定位发布方与订阅方。

不采用全量扫描 Package 依赖、为所有 `CCEvent` 生成 API 的方案。该方式无法证明谁有权发布，
也会生成未使用能力。采用显式 Event Contract、显式静态 Subscription、Owner 显式 Publication，
由生成器完成注册、发布入口、metadata 和静态校验。

Event 数据类和 Subscriber 业务逻辑继续手写。生成器不从字段、函数体或命名猜测业务事件。

## 9. 推荐声明模型

跨组件 Contracts Package 声明由一个领域组件拥有的事实：

```dart
@CCEventContract(
  componentId: orderComponentId,
  id: 'order.created',
  description: '订单已经创建。',
)
final class OrderCreatedEvent implements CCEvent {
  const OrderCreatedEvent(this.orderId);

  final String orderId;
}
```

仅在实现 Package 内传播的 Event 可以省略 `componentId`，由生成器从唯一 `CCComponent` 推导
Owner；需要跨组件后再保持稳定 Event ID 迁移到 contracts Package。

Subscriber 实现 Package 声明静态订阅函数：

```dart
@CCEventSubscription(id: 'analytics.order-created')
Future<void> trackOrderCreated(
  OrderCreatedEvent event,
  CCInvocationContext context,
) async {
  await analytics.track(event.orderId);
}
```

同一组件对某个 Event 只有一个 Subscriber 时可以省略 ID，生成器使用
`<subscriberComponentId>.<eventId>` 作为稳定默认值；同一组件存在多个 Subscriber 时必须为
所有相关 Subscription 显式设置 ID，避免发现顺序改变默认身份。

Event Contract 已经声明唯一 Owner，因此不再在 `CCComponent` 中重复维护 publication 列表。
生成器自动为当前组件拥有的全部 Event Contract 生成发布入口：

```dart
await DemoOrderEvents.publishOrderCreated(
  const OrderCreatedEvent('42'),
  timeout: const Duration(seconds: 3),
);
```

不增加 `eventDependencies` 或 `eventPublications`。Subscription 本身已经是订阅组件的结构化
消费声明，Contract Owner 足以证明发布权，避免新增 Event 时修改中心 Component 文件。

## 10. 所有权与依赖规则

1. 默认只有 `CCEventContract.componentId` 对应的 Owner 获得生成 Publication Client。
2. Subscriber 可以为零或多个，不拥有 Event，也不能影响发布者业务成功。
3. Subscriber 组件应把 Owner 放入 required 或 optional dependencies；机会型监听可以使用
   optional dependency，Owner 不存在时只是不产生 Event。
4. 如果未来出现多个合法 Publisher，必须基于真实场景设计显式授权；本轮不开放任意组件发布。
5. Workspace Validator 拒绝组件源码对已注解 Event 直接调用 `CCRouter.event`；裸入口只用于
   未注解内部 Event、Host Composition Root、兼容迁移和测试。这是架构门禁而不是安全沙箱。

## 11. 生成物与 API 隔离

```text
lib/src/ccrouter_generated/
├── event/...event.g.dart
├── component/...event_api.g.dart
└── metadata/...event.json
```

- `event.g.dart` 只包含静态 Subscriber registration bridge；
- `event_api.g.dart` 包含当前组件拥有的类型安全 Publication API；
- `event.json` 记录 Contract、Owner、Publisher、Subscriber、ID 和源码位置；
- Event 数据类由开发者编写，不生成 `.event.contract.g.dart`；
- 没有 Event 能力时不创建对应文件或空目录；
- 注册与发布 Binding 只从 `ccrouter_generated.dart` 暴露，不进入业务 barrel。

## 12. 生成期校验

1. Event 必须是公开、具体、非泛型类，并且实现 `CCEvent`。
2. 实现 Package 可以省略 `componentId` 并从唯一 `CCComponent` 推导；contracts Package 必须
   显式声明 Owner。
3. Event ID 全局唯一、Owner 明确、description 有界。
4. Payload 实例字段必须为 `final` 且不能有 setter；生成器只能保证浅层不可变，嵌套值仍由
   开发者保证不会被并发 Subscriber 修改。
5. Payload 禁止 Flutter、private、callback、Stream 等不适合作为公共事实契约的类型。
6. Subscription 必须是公开、顶层、非泛型函数。
7. Subscription 参数只允许 `(Event)` 或 `(Event, CCInvocationContext)`。
8. 返回只允许 `void`、`Future<void>` 或兼容的 `FutureOr<void>`，不能产生业务结果。
9. Subscriber ID 在一个 Runtime 范围全局唯一；同组件同 Event 多 Subscriber 时全部必须显式
   设置 ID，重复 ID 在生成期失败。
10. Publication Client 只能生成在 Contract Owner 组件，同一 Event 不重复声明 publication。
11. Subscriber 可以为零，零订阅者不是生成错误。
12. 跨 Package Contract 必须通过公共 barrel 暴露，不能导入其他 Package 的 `src`。
13. 组件源码不得对已注解 Event 使用裸 `CCRouter.event`；Host 与未注解内部 Event 除外。

## 13. Runtime 与诊断调整

- Runtime 增加稳定 Event ID，同时继续按 Dart Type 做类型安全分派；
- 增加仅生成代码可见的 `CCRouterGeneratedEventBinding`，负责 Descriptor、Subscription 注册和
  携带可信 publisher identity；
- 发布 Span 使用稳定 Event ID，Subscriber 子 Span 记录 Subscriber ID 和可信组件 Owner；
- Event Payload、异常消息和业务对象不得进入 retained Trace 或应用诊断 Sink；
- 现有并发启动顺序、失败隔离、零订阅者、timeout、取消和 shutdown 语义保持不变；
- 动态 subscribe/unsubscribe、页面生命周期订阅和反射扫描仍不进入 Runtime。

## 14. 已完成实施项

1. [x] 新增 `CCEventContract` 和 `CCEventSubscription` 声明模型，不增加重复 Publication 声明。
2. [x] 实现 Contract、Payload、Subscription 签名和公共 Pure Dart 边界校验。
3. [x] 生成 Subscriber registration bridge，并接入组件 Registrar。
4. [x] 从 Contract Owner 自动生成 Publication Client 和可信 Event Binding。
5. [x] 扩展 Runtime 稳定 Event ID、metadata schema、Workspace Validator、Catalog 和 `ccrouter find`。
6. [x] Demo 迁移多 Subscriber、零 Subscriber、失败隔离和 timeout，并覆盖默认/显式 ID。
7. [x] 增加 Generator、Workspace、Runtime Binding 和 Demo 回归。
8. [x] 同步 README 与 Integration Skill 使用方式。

## 15. 明确不纳入本轮

Sticky、历史重放、持久化、跨进程广播、动态订阅、Subscriber 优先级和线程调度不属于静态
组件 Event。需要可靠送达或事务一致性时必须使用专门的持久化消息基础设施，不能把基础 Event
生成器扩展成全局 EventBus。
