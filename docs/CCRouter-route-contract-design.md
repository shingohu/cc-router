# CCRouter 路由契约与按需升级设计

## 文档状态

- 版本：v0.2
- 状态：统一 Contract-first 公开契约已实现并与当前生成器对齐

本文只定义路由契约的 Package 边界和 Promotion 规则。路由整体语义以
[路由子系统设计](CCRouter-route-design.md)为准，完成状态以
[路由完成计划](CCRouter-route-completion-plan.md)为准。

## 背景

生成器把内部路由的 `Arguments`、`Intent`、`Definition` 和 Codec 放在独立的
Package-internal `.route.g.dart` library，把页面构造放在独立 `.route_binding.g.dart`。
页面不声明 generated `part`，Page 类及其未命名构造器必须可由 Binding library 访问；
组件外没有公共 barrel 就不能获得内部 Route API。路由需要公开时改用 Contract-first schema，
避免通过导出页面 library 形成不完整的契约边界。

纯契约文件的目标是让跨组件调用只依赖稳定的路由契约，不依赖目标页面实现、
Flutter Widget 或页面所在 library。同一个 Contract-first 形态既支持组件 Package 内的
公开契约，也支持独立 Pure Dart contracts Package。页面注册所有权仍属于实现
组件，业务调用只能创建 Intent 并通过 `CCRouter.navigator` 导航。

## 目标与非目标

目标：

- 为每个 Contract-first 路由生成独立的 Pure Dart 契约 library。
- 契约 library 包含稳定 Route Consumer，以及供 generated owner glue 使用的 Arguments、
  Definition 和 Codec；业务 barrel 只导出 Route Consumer。
- 契约依赖 `ccrouter_contracts`，并可依赖页面显式导入的公开 Pure Dart 业务契约；
  不依赖 Flutter、`dart:ui`、页面类或 GoRouter。
- 组件 Registrar 继续由 owner 组件控制，业务代码不能通过契约直接注册路由。
- 组件内部路由只生成 Package-internal Route API/Definition 和页面 Binding，不生成可导出的纯契约。
- 保持现有 `CCRouter.navigator` 和 `Future<R?>` 结果类型不变。
- 支持内部路由在出现真实跨组件消费者后保持 Route ID 和调用语义完成 Promotion。

非目标：

- 不把页面构造器或 `Route.build` 放入纯契约 library。
- 不生成 GoRoute、Navigator、Widget 或 Adapter 对象。
- 不允许纯契约绕过 Package 依赖、拦截器或 Runtime 生命周期。

## 两种声明形态

| 声明形态 | 使用场景 | 聚合后的 Exposure |
| --- | --- | --- |
| 页面上的 `@CCRoute` | 组件内部页面 | `internal` |
| `@CCRouteContract` + `@CCRouteImplementation` | 同包公开或跨组件入口 | 同包为 `package`，跨包为 `external` |

不要因为未来可能复用就提前拆出所有契约。只有出现真实的同包公开或跨组件消费者时，
才把内部能力 Promotion 为 Contract-first；独立发布、双向依赖风险或动态组件边界出现时，
再将 schema 放入独立 contracts Package。

## 文件布局

### 同包 Contract-first 契约

页面与 schema 都不声明 generated `part`：

```text
lib/
├── order_route_contracts.dart
├── src/order_detail_route_contract.dart
├── src/order_detail_page.dart
├── src/ccrouter_generated/order_package.contracts.api.g.dart
├── src/ccrouter_generated/contract/order_detail_route_contract.route.contract.g.dart
└── src/ccrouter_generated/binding/order_detail_page.route_binding.g.dart
```

`order_route_contracts.dart` 是组件作者维护的公共 barrel，只导出
稳定 `<package>.contracts.api.g.dart` 中的公开 Route Consumer，并使用 `show` 明确列出 Route
类型。稳定入口由生成器聚合逐源码 `*.route.contract.g.dart`，后者不再成为 authored barrel 的
固定路径。页面专用 `.route_binding.g.dart` 只保留页面构造和 owner 注册 glue，
不从公共 barrel 导出。

### 独立 contracts Package

```text
demo_order_contracts/
├── lib/demo_order_contracts.dart
├── lib/demo_order_contracts_owner.dart
├── lib/src/order_detail_route_contract.dart
├── lib/src/ccrouter_generated/demo_order_contracts.contracts.api.g.dart
└── lib/src/ccrouter_generated/contract/order_detail_route_contract.route.contract.g.dart

demo_order/
├── lib/src/order_detail_page.dart
└── lib/src/ccrouter_generated/binding/order_detail_page.route_binding.g.dart
```

业务调用方只导入 `demo_order_contracts.dart`。实现组件导入 owner integration library，
用 `@CCRouteImplementation(OrderDetailRouteContract)` 绑定页面。contracts Package 只依赖
`ccrouter_contracts`，不能依赖 Flutter、实现组件或具体导航后端。

业务与 owner barrel 都应转发同一个稳定 `<package>.contracts.api.g.dart`，但分别用 `show`
控制实际公开符号。该 generated barrel 只包含 Route Consumer；Arguments、Definition 和 Codec
属于 generated Owner SPI；authored Service、
Command、Event 与 InitTask Contract 继续从其源文件显式导出。生成器校验转发链最终到达
`lib/` 顶层 public library，`lib/src` 中间 barrel 本身不构成公开 API。`clean` 或首次生成时，
CLI 会在 Builder 前为 authored barrel 的显式引用创建受管 placeholder，并在聚合阶段覆盖，
避免 public barrel 与待生成文件形成首次构建循环。

## API 归属

| 声明 | 纯契约 | 页面 glue | 原因 |
| --- | --- | --- | --- |
| `XxxRouteArguments` | Owner SPI | 否 | Intent 和 Codec 的内部传输类型 |
| `XxxRoute.intent` | 是 | 否 | 业务导航入口 |
| `XxxRouteContractBinding.definition` | Owner SPI | 否 | Runtime 注册所需的中立定义 |
| `XxxRoute.register` | 否 | 是 | 仅 owner Registrar 调用 |
| `XxxRoute.build` | 否 | 是 | 需要访问页面构造器 |
| Codec 实现 | Owner SPI | 否 | 只依赖纯参数类型和 contracts |
| 页面构造器 | 否 | 否 | 页面实现属于组件内部 |

纯契约中的导航入口只创建 `CCRouteIntent<R>`；实际调用仍必须经过
`CCRouter.navigator`。`register` 不进入业务导出的契约，避免消费者获得组件
注册能力。

## Contract-first 生成

contracts Package 以抽象 schema 作为公共契约的唯一来源：

```dart
@CCRouteContract<String>(
  componentId: demoOrderComponentId,
  id: 'order.detail',
  pattern: CCPathPattern('/orders/:orderId'),
)
abstract class OrderDetailRouteContract {
  const OrderDetailRouteContract({required this.orderId});
  final int orderId;
}
```

实现 Package 只绑定页面：

```dart
@CCRouteImplementation(OrderDetailRouteContract)
final class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({required this.orderId, super.key});
  final int orderId;
}
```

生成器校验参数名称、顺序、named/positional 形式、类型和可空性。Workspace 聚合按
`routeId` 合并契约元数据与实现元数据，并拒绝缺失实现、重复实现、owner 不一致或
页面声明和公开实现同时注册。

## 生成与兼容策略

1. 页面上的 `@CCRoute` 固定生成 Package-internal Route API/Definition，不提供公开开关。
2. 公开契约统一使用 `@CCRouteContract`；同 Package 放置用于渐进迁移，独立 contracts
   Package 用于稳定跨组件边界。
3. 契约生成发生在 schema 所在 Package 内；
   `build_runner` 不跨 Package 写文件。
4. workspace barrel 校验要求所有公开路由从生成 contract library 使用 `show`
   导出 `Route`；Arguments、Definition、Codec 和页面 glue 不属于 Consumer barrel。

这种声明分离避免同一个 Route ID 出现两套不兼容的 Definition；生成器不再提供
与注解形态重复的契约生成开关。

## Contract Promotion

内部路由升级为跨组件契约时：

1. 创建 `@CCRouteContract` schema；同包迁移可先放在实现 Package，跨组件使用则放在
   owner 的 contracts Package。
2. 保持原 `routeId`、Pattern、参数 wire name、返回类型和拦截策略不变。
3. 页面从 `@CCRoute` 改为 `@CCRouteImplementation`，不复制路由元数据。
4. 消费者只依赖契约所在 Package，并从其公共 barrel 导入生成契约。
5. 原实现 Package 可临时 re-export 新契约，给旧调用方提供迁移窗口。
6. 聚合器确保同一时刻只有一个 Definition 和一个页面实现。

2.0 可评估提供 CLI `promote route` 脚手架、依赖修改和 dry-run，但标准生成与校验不能
依赖 CLI。手动建立 contracts Package 后仍必须能用 `build_runner` 完成全部生成。

## 验证要求

- 生成契约 library 的 import graph 不包含 Flutter、页面或导航后端类型，并能在独立
  contracts Package 中通过 Dart Analyzer。
- 导入纯契约的消费者不能解析页面 Widget 或 `BuildContext`。
- Intent 的 `routeId`、结果泛型、Codec 编解码和主 Pattern 与页面 glue 完全一致。
- 内部路由不生成纯契约；跨组件访问由公共 barrel、Pub 直接依赖和 Analyzer 共同约束。
- barrel 缺少 `show`、任一转发层丢失必需符号、导出 glue 或契约与页面 Route ID 不一致时，
  构建失败。
- 生成文件布局迁移期间必须保持现有生成测试和 Runtime 回归通过。

当前生成器还会拒绝源文件本地类型、private 类型、`package:*/src/` 导入和
Flutter/GoRouter 类型进入独立契约。Result 或 Extra 使用自定义对象时，应将对象移动到
contracts Package 的公开 Pure Dart model library，并由 schema 通过公开入口显式导入。

## 非路由附录：Service Promotion 已迁移

本节原先记录的 Service Promotion Proposal 已完成，不再作为架构 2.0 候选。当前实现支持
`@CCServiceContract`、稳定 ID、自动绑定、生成 Token、消费组件专属 Proxy 和 Contract 版本
兼容门禁；生成 Token 仍只属于 Generator、低层 Component SPI 和测试，不进入业务 Facade。

Service 的当前语义和剩余限制以
[Service 生命周期设计](CCRouter-service-lifecycle-design.md) 与
[Service Proxy 生成设计](CCRouter-service-proxy-generation-design.md) 为准。本路由契约文档不再
重复维护 Service 状态。
