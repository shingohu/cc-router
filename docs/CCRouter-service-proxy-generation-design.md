# CCRouter Service Proxy 自动生成设计

## 1. 状态与目标

本文统一维护跨组件 Service 声明、生成与方法支持矩阵；Provider 注册、readiness、Scope 和
释放规则见[Service 生命周期规范](CCRouter-service-lifecycle-design.md)。原 Service 实施清单已
吸收到这两份规范，历史执行记录见[合并归档](archive/20261024-consolidation/README.md)。

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

生成成员名按以下确定顺序解析：

1. 消费组件的 `CCServiceDependency.alias`；
2. `CCServiceContract.alias`；
3. Contract 类型去掉末尾 `Service` 后，仅将首字母转为小写。

默认推导不做 acronym 猜测：`HTTPService` 会稳定得到 `hTTP`，需要领域名称时在 Contract
声明 `alias: 'http'`。这避免生成器升级时因分词规则变化而修改业务 API。Contract alias 适合让
全部消费者获得同一个名称；Dependency alias 只用于多 Key、消费组件词汇差异或名称冲突：

```dart
CCServiceDependency<PaymentService>(
  key: CCServiceKey<PaymentService>('wechat'),
  alias: 'wechatPayment',
)
```

生成器校验 Contract ID、Owner、Key、alias、重复 `(Contract, Key)` 和成员名冲突。业务不传 Token、
字符串 Key、caller identity 或 method ID。alias 必须是非关键字 public lower-camel Dart 标识符，
并进入 Contract metadata 与 shape fingerprint；修改 Contract alias 是生成 Client 的 source
compatibility 变更，必须按 Contract SemVer 处理并重新生成消费者。

本轮不生成全局 `Network.client` 命名空间 Facade。它会产生跨 Package 导入冲突，并容易隐藏
消费组件专属 caller identity。稳定入口继续采用 `<Component>Services.<member>`，例如
`DemoNavigationLabServices.network`；若生产项目证明两层命名空间有明确收益，再评估组件局部
`<Component>Api.network.client`，不能退化为全局共享 Proxy。

## 4. 方法支持矩阵

首版支持：

- public 普通实例方法与 getter；
- 同步 `R`、同步 `void`、`Future<R>`、`Future<void>`，以及方法直接返回非空 `Stream<T>`；
- 非泛型 Contract 上的方法级泛型，包括公共 Pure Dart bound、nullable 结果、多个相互引用的
  类型参数和显式类型实参转发；
- required/optional positional 与 named 参数；
- primitive、enum、集合、record 和公开 Pure Dart DTO；
- primitive、enum、List、Set、Map 的 const 默认值；
- `CCServiceKey<T>` 多实现。

首版生成失败：

- 泛型 Contract、Contract 继承或 mixin；
- setter、operator；
- Stream getter、可空/嵌套/自定义 Stream、多个取消 token 参数、`FutureOr<T>`、callback/function 参数；
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

### Stream 生命周期（Issue #7）

分类：通用框架能力。业务侧多个 Future 会丢失自然的增量交付和统一订阅语义；仅在生成器放开
检查不能维持 invocation，Adapter 也不能代替 Core 的 Scope 清理。采用独立 Stream SPI 路径，
不改同步/Future 行为；如需回退，回退此路径并恢复生成期诊断。

- 调用时固定 Owner Scope、继承的 consumer lineage 与最早 deadline，首次 listen 才 readiness、
  方法执行和上游订阅；一个返回流只允许一次 listen，源可为 single-subscription 或 broadcast。
- 未订阅调用在原 Scope 弱登记；流被丢弃时可回收，Owner/consumer 关闭释放启动闭包和调用 Zone，
  后续 listen 报取消但不进入方法、不创建 Trace。登记与活动订阅 barrier 分开，Scope 不强持有懒调用。
- 首次方法入场异步，后续源/resume 事件可同步交付，但回调不重叠；私有订阅拥有可清空 FIFO，
  不把 payload 交给不可清理的 Controller/Transformer 队列。中断清空值、业务错误和 Zone，pause
  同时传给上游。无积压的源完成可提交结果；有积压时保留原 Owner/deadline 隔离。
- 显式 cancel 保留取消发起方 error Zone 并注入 invocation 身份；自动 Scope/token/deadline 取消
  使用源 invocation Zone。协作信号和源 cancel 在同一选定 Zone 执行，以 `_SharedResult` 数据
  加入 Host 等待。外部裸 Future 仍需遵守 Dart 原生 producer error Zone 约束。
- handler 更新、asFuture、嵌套 pause/resumeSignal 保持 Dart 语义；cancelOnError 等待源清理后读取
  最新错误 handler，再次显式 cancel 可抑制待交付错误。清理失败独立发出 `serviceStreamCleanup`
  脱敏诊断，只记录 errorType/稳定 ID，不被主取消错误或 barrier 移除遮蔽。
- 至多一个框架 CCCancellationToken 参数；Proxy 转发与 Scope/Runtime 关联的 context token。
  Widget 不会被猜测为 consumer Scope，UI 必须显式取消 token/subscription。
- 原始数据顺序、error/stack、done、pause/resume 与 cancelOnError 遵循 Dart Stream。源错误默认
  非终止；显式 cancel 的 Future 等待源清理并传播原始清理错误。
- Scope/token/shutdown 在同步终止边界屏蔽迟到和积压事件，取消 context，等待源 cancel 后发出
  CCInvocationCancelledError 再 done；整个流存续期受 deadline 约束，超时为 CCInvocationTimeoutError。
  暂停不暂停 deadline，暂停的消费者恢复后才能看到终止事件。
- Scope 通过私有 cleanup barrier 在 Service dispose 前 join 流清理，继承现有逐资源 timeout 和
  disposalErrors。consumer lineage 仅保存 Scope 弱引用；终止移除监听/timer/barrier/Provider 引用。
  不合作的源可能超过清理界限，框架不承诺强制终止任意 Dart/网络操作。
- 自然结束或取消清理完成只产生一次方法 Trace，自然结束前出现源错误记 failed，取消记 cancelled，超时记 timedOut；
  不记录参数、快照、错误文本。并发调用独立，共享 Service 仍由 Provider Scope 拥有。
- HTTP、账号代次、业务 fallback 和重试由实现负责；有限请求没有自动重放、缓存或隐式空流降级。
  单个调用的开销为一套私有订阅、可清空事件队列、取消监听和可选 deadline timer。

验证入口：`service_stream_test.dart`、Service Generator 测试，以及 payment 的真实生成 Proxy 测试。
Demo 总览使用订单摘要展示首份/后续快照，重试和 dispose 取消旧请求；该能力不放宽 UI schema。

## 6. 生成与校验链

1. Service Contract Builder 校验 Contract 和成员签名，输出 Token 与方法 metadata。
2. Component Builder 读取显式 `serviceDependencies`，校验 Owner 位于 required dependencies。
3. Service Proxy Builder 复用组件源码中的公共 barrel import，生成组件专属 Client。
4. Workspace Validator 再次校验 Contract、Owner、Key、member 和重复依赖，防止陈旧 metadata。
5. Package Index 和 Capability Catalog 记录 Contract 方法与消费方 `serviceClient` 生成物。
6. `generate --check`、Analyzer 和端到端 Test Host 回归共同阻止陈旧或不可编译生成物。

## 7. 性能与回退

生成器只处理显式消费项，不扫描依赖 Package 的全部 Service。没有声明时不写
`*.service_api.g.dart`，删除最后一个声明时清理陈旧受管输出。Provider/Contract metadata 的增删改
必须使缓存失效，缓存与 `--no-cache` 输出逐字节一致；冷生成不依赖先生成 Token 再运行第二次。
Proxy 每次调用增加一次受控 Provider 解析和 Trace；普通本地 Service 不走此路径。
跨组件消费不应通过手写 Proxy 或直接 service lookup 绕开生成依赖边界；遇到生成不兼容时应
保留失败证据并修复/回退对应工具链，不能把丢失 caller identity 的调用包装成等价推荐路径。
