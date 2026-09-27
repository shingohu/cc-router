# CCRouter Service Proxy 自动生成设计

## 1. 状态与目标

- 状态：1.x 已实现
- 使用者：存在真实跨组件 Service 调用的组件作者
- 目标：消除手写 Proxy 中的 Token、method ID、caller component ID、参数转发和同步/异步
  Invocation 样板，同时保留编译期类型检查、精确依赖、Scope 生命周期和方法级诊断。
- 非目标：运行时反射、远程 RPC、动态 `Map` 分派、Service EventBus、任意方法 AOP 或组件安全沙箱。

普通组件内部 Service 继续使用 `CCRouter.service<T>()`。只有公开 Contract 被另一个组件调用时，
消费组件才声明 `CCServiceDependency<T>` 并获得组件专属 Client。

## 2. 声明与生成

Contract Package 保持 Pure Dart：

```dart
@CCServiceContract(
  componentId: orderComponentId,
  id: 'order.summary',
  description: '提供跨组件订单摘要。',
)
abstract interface class OrderSummaryService {
  String summaryFor(int orderId);
  Future<String> loadSummary(int orderId);
  int get invocationCount;
}
```

消费组件同时声明粗粒度组件依赖和精确 Service 依赖：

```dart
const paymentComponent = CCComponent(
  id: paymentComponentId,
  version: '1.0.0',
  dependencies: [orderComponentId],
  serviceDependencies: [
    CCServiceDependency<OrderSummaryService>(),
  ],
);
```

`dependencies` 保证 Provider Owner 必须安装并参与组件拓扑；`serviceDependencies` 只授权并生成
精确消费能力。`optionalDependencies` 不能满足必需方法调用。生成器不会扫描全部 Pub 依赖来
猜测消费关系。

生成结果位于组件内部：

```text
lib/src/ccrouter_generated/component/<component-source>.service_api.g.dart
```

业务通过生成 Client 调用：

```dart
final text = DemoPaymentServices.orderSummary.summaryFor(orderId);
final loaded = await DemoPaymentServices.orderSummary.loadSummary(orderId);
```

Proxy 是无状态 `const` Client Stub，不拥有、缓存或销毁 Provider。每次调用都从当前 Runtime 和
Scope 解析实例，因此静态 Client 可以跨 Session 使用，而旧 Session 实例仍会按原 Scope 关闭。

## 3. Key 与命名

默认成员名由 Contract 类型去掉 `Service` 后转为 lower camel。多 Key 或名称冲突时显式声明：

```dart
CCServiceDependency<PaymentService>(
  key: CCServiceKey<PaymentService>('wechat'),
  alias: 'wechatPayment',
)
```

生成器校验 Contract ID、Owner、Key、alias、重复 `(Contract, Key)` 和成员名冲突。业务不传 Token、
字符串 Key、caller identity 或 method ID。

## 4. 方法支持矩阵

首版支持：

- public 普通实例方法与 getter；
- 同步 `R`、同步 `void`、`Future<R>`、`Future<void>`；
- 非泛型 Contract 上的方法级泛型，包括公共 Pure Dart bound、nullable 结果、多个相互引用的
  类型参数和显式类型实参转发；
- required/optional positional 与 named 参数；
- primitive、enum、集合、record 和公开 Pure Dart DTO；
- primitive、enum、List、Set、Map 的 const 默认值；
- `CCServiceKey<T>` 多实现。

首版生成失败：

- 泛型 Contract、Contract 继承或 mixin；
- setter、operator；
- `Stream<T>`、`FutureOr<T>`、callback/function 参数；
- private、Flutter、`dart:ui`、GoRouter 或未从公共 barrel 暴露的 `package:*/src/` 类型；
- Route-scoped 跨组件 Proxy。

不支持项必须定位到声明并中止生成，不能退化为 dynamic、反射或运行时字符串分派。

泛型方法只保留同一 Dart isolate 内的静态类型关系。Proxy 必须同时复刻方法类型参数声明并在
实现调用点显式传递全部类型实参，避免 `T create<T>()` 这类零参数方法丢失推断上下文。类型参数
和 bound 不进入 Trace，且该能力不表示支持远程 RPC、跨 isolate 序列化或任意运行时类型。

## 5. 运行时语义

- 同步成员使用 `invokeServiceSync`，不会启动或等待 async initializer；Provider 未 Ready 时抛出
  `CCServiceNotReadyError`。
- Future 成员使用 `invokeService`，等待 lazy readiness，并接受 Owner Scope cancellation。
- App、Session 和 Runtime shutdown 的所有权与原 Provider 完全一致；Proxy 没有 dispose。
- 参数、返回值和异常文本不进入 Trace；只记录 Contract ID、Key、method ID、生成 caller、Provider
  owner、Scope、耗时、状态和 error type。
- Session 关闭会取消其中未完成调用。新 Session 中同一个静态 Client 会解析新实例，不保留旧实例。
- `newInstance` 仍按每次解析创建，实例销毁继续归父 Scope 所有，Proxy 不引入额外生命周期。

“调用方可信”表示 caller ID 由本组件生成代码固定并可用于架构诊断，不表示 Dart Package 形成
安全沙箱。业务 Facade 不开放 caller ID；CI 的 Analyzer 与生成内部 API 边界规则负责阻止普通
源码绕过生成入口。

## 6. 生成与校验链

1. Service Contract Builder 校验 Contract 和成员签名，输出 Token 与方法 metadata。
2. Component Builder 读取显式 `serviceDependencies`，校验 Owner 位于 required dependencies。
3. Service Proxy Builder 复用组件源码中的公共 barrel import，生成组件专属 Client。
4. Workspace Validator 再次校验 Contract、Owner、Key、member 和重复依赖，防止陈旧 metadata。
5. Package Index 和 Capability Catalog 记录 Contract 方法与消费方 `serviceClient` 生成物。
6. `generate --check`、Analyzer 和端到端 Test Host 回归共同阻止陈旧或不可编译生成物。

## 7. 性能与回退

生成器只处理显式消费项，不扫描依赖 Package 的全部 Service。没有声明时不写
`*.service_api.g.dart`。Proxy 每次调用增加一次受控 Provider 解析和 Trace；普通本地 Service 不走
此路径。若 Proxy 生成出现兼容问题，消费方可以临时退回 `CCRouter.service<T>()`，Provider、Scope
和 Contract 注册无需迁移，但会失去生成 caller identity 和方法级 Trace。
