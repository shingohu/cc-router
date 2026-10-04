# CCRouter 组件能力生成器

组件的开发工具，不属于运行时依赖。每个实现 Package 声明一个顶层
`const CCComponent`，内部 Route 和简单 Service 自动归属该 Owner：

```dart
// lib/src/order_component.dart
import 'package:ccrouter/ccrouter.dart';

const orderComponentId = CCComponentId('order');

const orderComponent = CCComponent(
  id: orderComponentId,
  version: '1.0.0',
);
```

```dart
// lib/src/detail_page.dart
import 'package:ccrouter/ccrouter.dart';

@CCRoute<String>(
  id: 'order.detail',
  pattern: CCPathPattern('/orders/:orderId'),
)
final class DetailPage {
  const DetailPage({
    required this.orderId,
    @CCQueryParam() this.tab = 'summary',
  });
  final int orderId;
  final String tab;
}
```

稳定跨组件入口使用独立 contracts Package，而不是让消费者依赖页面组件。契约包声明：

```dart
@CCRouteContract<String>(
  componentId: orderComponentId,
  id: 'order.detail',
  pattern: CCPathPattern('/orders/:orderId'),
)
abstract class OrderDetailRouteContract {
  const OrderDetailRouteContract({required this.orderId});
  final int orderId;
}
```

实现组件绑定页面：

```dart
import 'package:order_contracts/order_contracts_owner.dart';

@CCRouteImplementation(OrderDetailRouteContract)
final class OrderDetailPage {
  const OrderDetailPage({required this.orderId});
  final int orderId;
}
```

contracts Package 只依赖 `ccrouter_contracts`，生成 `OrderDetailRoute.intent(...)`；页面
组件依赖 contracts Package 并生成 owner glue。Workspace 聚合器要求公开契约恰好
存在一个实现。普通内部页面继续使用 `@CCRoute`，无需提前拆包。

不再需要手写 Registrar 或 generated `part`。Command、Event 和 InitTask 已分别使用
Contract/Handler、Contract/Subscription 和 Task Contract/Handler 注解生成。Shell、策略、
自定义构造或异步初始化的复杂 Service 等没有窄声明模型的能力，继续使用顶层同步
Contribution：

```dart
@CCComponentContribution(id: 'order.capabilities')
void registerOrderCapabilities(CCRegistry registry) {
  // Only registrations. Do not run I/O or retain registry.
}
```

跨组件 Service 由消费组件精确声明，不扫描全部 Package 依赖：

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

生成的 `<component-source>.service_api.g.dart` 提供 `<Component>Services` 静态 Client，自动固定
Contract、Key、method ID 和 caller component ID。无消费声明时不生成该文件。当前接受普通
实例方法/getter、同步或 Future 返回、可公开导入的 Pure Dart 类型，以及非泛型 Contract 上的
受限方法级泛型；泛型 Contract、Stream、callback、继承等不支持项在生成期失败。
Proxy 的内部回调变量和导入前缀自动避开业务参数、方法和泛型名称，不要求业务使用保留名称列表。
Route/Proxy 默认集合保持常量的实际泛型类型，不能因参数声明为 Object 而丢失 Set/List/Map
语义。仅在默认值出现的枚举/集合类型同样参与导入与可见性校验。

`dependencies`、`serviceDependencies` 和 `commandDependencies` 目前必须显式维护。生成器会从
Contract 元数据解析 Owner 并校验三者一致，不会因为发现某个 Contracts Package 或 Pub 依赖而
静默修改组件源文件。稳定 Component API 聚合入口已经实现；Generator 会在 build_runner 前
对直接、唯一可证明的声明按组件批量输出缺失 Owner，Analyzer 也能对直接 const List 提供单个
或全部可证明 Owner 的显式 Quick Fix。变量、spread、条件集合和歧义输入仍由最终
Builder/Workspace Validator 校验。AST 预检按 Library 的直接/相对导入和可证明的 export 链查找，
不从 Package 级同名声明推断可见性；part、条件导入或外部命名空间不完整时不做早期拒绝。
`ccrouter find --usage` 可基于当前已生成 Index 为一个现有
消费组件输出只读接入建议，但不会编辑依赖或替代最终校验。

不同消费组件如需统一 Service/Command Client 成员名，可在 Contract 上设置 lower-camel
`alias`，消费组件仍可在 `CCServiceDependency<T>` 或 `CCCommandDependency<T>` 上覆盖。命名优先级
为 Dependency alias、Contract alias、类型名推导。默认推导只移除末尾 `Service`/`Command` 并
降低首字母，不猜测 acronym。Contract alias 属于生成 API shape，修改后必须按 Contract SemVer
处理并重新生成消费者。点号命名空间（如 `Network.client`）经评估暂不支持；继续使用组件专属
Client，避免全局 Proxy 绕过消费组件 caller identity。

声明 `@CCRouteContract` 的 Package 需要直接依赖 `ccrouter_contracts`，公共 barrel 只导出
生成的稳定 Contract 入口。同 Package Contract-first 可用于渐进迁移；独立 contracts Package
用于稳定的跨组件边界：

```yaml
dependencies:
  ccrouter: ^0.1.0
  ccrouter_contracts: ^0.1.0
```

```dart
export 'src/ccrouter_generated/order_contracts.contracts.api.g.dart'
    show DetailPageRoute, DetailPageRouteArguments;
```

`<package>.contracts.api.g.dart` 只聚合公开 Route Contract 的生成类型，隐藏逐源码
`.route.contract.g.dart` 路径。authored Service、Command、Event 和 InitTask 契约仍由公共 barrel
显式导出；生成器不会替 Package 决定这些 API。每层转发都必须保留完整 `show`，最终到达
`lib/` 顶层 public library。`clean` 后的下一轮 `generate` 会为显式引用的缺失稳定入口创建受管
placeholder，Builder 完成后立即替换为正式 exports。

组件的 `dev_dependencies` 添加 `ccrouter_generator`，workspace 根目录添加
`build_runner`。本仓库在根目录执行：

```sh
# 创建一个新的组件 Package；不会覆盖已有文件
fvm dart run --verbosity=error ccrouter_generator:ccrouter create component demo_inventory demo/modules

# 在组件中创建一个内部 Route 页面；不会自动创建跨组件 Contract
fvm dart run --verbosity=error ccrouter_generator:ccrouter create page InventoryPage demo/modules/demo_inventory

# 创建组件内部能力模板；不会修改 Host 或生成目录
fvm dart run --verbosity=error ccrouter_generator:ccrouter create service OrderSummary demo/modules/demo_inventory
fvm dart run --verbosity=error ccrouter_generator:ccrouter create command ReserveOrder demo/modules/demo_inventory
fvm dart run --verbosity=error ccrouter_generator:ccrouter create event OrderPaid demo/modules/demo_inventory
fvm dart run --verbosity=error ccrouter_generator:ccrouter create event OrderPaid demo/modules/demo_inventory --with-subscriber
fvm dart run --verbosity=error ccrouter_generator:ccrouter create init-task WarmCache demo/modules/demo_inventory
fvm dart run --verbosity=error ccrouter_generator:ccrouter create init-task WarmCache demo/modules/demo_inventory --with-contract

fvm flutter pub get
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo
```

Analyzer 是可选的 Host 开发工具，独立于生成流程：

```sh
ccrouter analyzer status <host-root>
ccrouter analyzer doctor <host-root>
ccrouter analyzer install <host-root> --version <published-version> --dry-run
ccrouter analyzer install <host-root> --source git --url <remote-url> --ref <full-commit-sha>
ccrouter analyzer upgrade <host-root> --ref <full-commit-sha>
ccrouter analyzer uninstall <host-root> --dry-run
```

写入命令支持 `--dry-run`，只管理 CLI 创建的隔离 bootstrap 和 Host 配置叶，先验证候选
loader 再运行禁用 Hook 的 Host Pub。现有手工装配不自动接管，未知文件保留；普通失败恢复
记录的配置/解析文件，并发冲突或中断保留恢复日志。Hosted 需显式指定已发布版本，Git 需远端
完整 SHA。完成后重启 Analysis Server，并验证实际 IDE 诊断；不隐式挂入 generate 或 Pub Hook。
完整说明见 [Analyzer CLI 指南](../../docs/CCRouter-analyzer-cli-plan.md)。

如果希望在当前 Flutter SDK 的 `flutter pub get/upgrade/downgrade/add/remove` 成功后
自动生成，可以显式安装可回滚的 hook：

```sh
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook install
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook status
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook uninstall
```

Hook 按 SDK 版本独立安装，不修改 Flutter snapshot；非 CCRouter 项目以及没有直接声明
`ccrouter` 的 Workspace 聚合根会跳过，不会猜测成员 Host。完整的
退出码语义、FVM 版本切换和禁用方式见
[`docs/CCRouter-cli-pub-hook.md`](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-cli-pub-hook.md)。
`--verbosity=error` 只压低 Dart/Pub 在 CLI 启动前的依赖解析和 executable 构建噪声，
不会隐藏 CCRouter 自己的进度、诊断或失败。

`create component <package-name> [parent-directory]` 会生成 `pubspec.yaml`、Package barrel
和 `lib/src/<package>_component.dart`；Descriptor 不会从根 barrel 导出。`create page <PageName> [component-directory]` 会生成
`lib/src/<page>_page.dart`、内部 `@CCRoute<void>`、稳定默认 Route ID 和 `/page` Path。
新 Component 的 manifest 优先继承目标目录最近 Package/Workspace 的 Dart SDK 约束及
`ccrouter`/`ccrouter_generator` Hosted、Git 或 Path 声明；Path 会相对新 Package 重新计算。
只有没有显式声明时才读取 resolved Package 版本，仍无法证明来源则在写入前失败。
`create service`、`create command`、`create event` 和 `create init-task` 会在现有组件的
`lib/src` 下生成最小起始文件。内部 Service 默认只生成带稳定 ID 的 concrete `@CCService`；
Command 生成 Contract 与 Handler；Event 默认只生成 Contract，`--with-subscriber` 才附带一个
本地 Subscriber；独立内部 InitTask 默认直接使用 `id`，`--with-contract` 才附带可复用的 typed
Task Contract。它们默认是组件内部能力；真实出现跨组件消费者后，仍需显式建立 Contracts
Package、Owner 和依赖声明。
所有脚手架命令都是非覆盖式的：任何目标文件已存在、目标组件目录已存在或名称不符合 Dart
命名约束时都会失败并返回非零。它们不修改 Host 依赖、不创建 generated 文件，也不替代后续
的 `pub get` 和 `generate`。创建成功后会输出 `Next steps`：Component 会提示 Workspace 与
消费者依赖装配，其它模板会提示先完善源码再为实际 Host 生成；提示本身不会修改工程。

该命令自动寻找包或 Dart workspace 根目录，先调用现有 build_runner，再执行 metadata 校验、
组件索引、Host Catalog 和文档聚合。非 workspace 包也使用同一命令，不需要自行拼接两步流程。
新增或修改注解页面后再次运行相同命令；源码无需添加 `part` 或手动更新 Registrar。
首次生成前 IDE 不会提供尚不存在的 Route API 符号；生成完成后可使用 IDE 自动导入
本组件稳定的 `src/ccrouter_generated/<componentId>.api.g.dart`。业务源码不直接导入其
`component/` 子目录中的 Route/Service/Command/Event 实现入口。
页面重命名、移动或删除也使用相同命令清理旧生成物，并可用 `--check` 验证产物同步。
CI 使用只读门禁：

```sh
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --check
```

`--check` 在生成前后只比较 CCRouter 管理的产物；发现新增、删除或内容变化时恢复原文件并返回
非零退出码，不依赖 Git，也不会把业务源码或其它工具的改动算作陈旧生成物。旧的
`ccrouter_generator aggregate` metadata-only 入口仅为脚本兼容保留，新项目不应使用。

自定义 `--output-dir` 的 Catalog 也参与比较及失败恢复，包括 docs/build 目录。只管理
`cc_routes.json`、`cc_catalog.md` 和待迁移的 `cc_routes.md`、`cc_sources.md`，不接管同目录
其它文件。`--check` 仍要求输出目录位于 Workspace/Package 构建根目录内。

如果需要在重新生成前清理当前 Host 运行时依赖闭包中的 CCRouter 生成物，使用：

```sh
fvm dart run --verbosity=error ccrouter_generator:ccrouter clean demo
```

`clean` 只删除框架标记且位于可写 Package 的 `lib/src/ccrouter_generated/` 下的受管源码输出；
会保留业务源码、手写同名文件、只读依赖、`.dart_tool/build` 缓存和平台构建产物。清理后可
再次执行 `generate` 完整恢复。它不是通用的 `clean` 或 `flutter clean`，不会删除 Package
之外的文件。保留的 build cache 有效时，`generate` 会先从 Builder metadata 临时恢复 authored
源码已导入但被清理的 Route/Command/Event component API，使 build_runner 在同一轮看到完整
import graph；该 bootstrap 不替代当前轮构建与最终校验，失败时会恢复生成前现场。

查找已生成路由的组件、契约和页面源码位置时使用只读命令：

```sh
fvm dart run --verbosity=error ccrouter_generator:ccrouter find order.detail demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter find '/order/:orderId' demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter find demo_order.summary demo --usage demo_payment_component
```

`find` 读取指定 Host 的 Pub 运行时依赖闭包内已发布的 Package Index，不启动
build_runner，也不修改生成物。查询是大小写敏感的精确 Route ID 或声明的 Pattern 文本；
`/order/42` 这类带实际参数的 URL 不等同于 `/order/:orderId`，不会由查找命令执行路由解析。
从 Host Package 目录执行时可省略最后的 `demo` 参数。契约与页面分处不同 Package 时会合并
显示源码位置；无匹配、Index 缺失或损坏、依赖 Index 版本混用时返回非零状态。改动源码后先运行 `generate`，
必要时使用 `generate --check` 验证 Index 未过期；`find` 不扫描源文件来猜测未生成的声明。

`--usage <consumer-component-id>` 要求消费组件已经存在于所选 Host 闭包。它从 Generator 已验证
并写入 Package Index 的 export chain 得到 public import，报告直接 Pub 依赖、Owner 组件依赖和
能力声明是否齐全，并给出稳定 Component API/typed call。它始终只读，不修改 `pubspec.yaml`、
组件源码、import 或生成物；旧 Index 或未公开 Contract 缺少可证明的 public library 时明确停止
跨组件建议，不猜测 conventional barrel。Route 不要求 Owner component edge；Service/Command
分别建议 `serviceDependencies`/`commandDependencies`；Event 建议 top-level Subscription 而不是
虚构 `eventDependencies`；InitTask 建议任务 `dependsOn`，不生成业务调用 Client。

大型工程可以观察分阶段耗时和缓存命中率，或强制走无缓存参考路径：

```sh
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --profile
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache
```

默认缓存只复用内容 SHA-256 完全一致的 metadata 解析结果；损坏、Schema/版本不兼容时自动
丢弃并全量解析。`--no-cache` 与默认增量路径必须生成逐字节一致的受管产物。并发执行会通过
`.dart_tool/ccrouter/v1/generation.lock` 串行化，文件内容未变化时不改写，变化时使用同目录临时
文件提交。workspace 模式仍复用 build_runner 的增量图，但通过 `asset:` build filter 只构建
Host 依赖闭包内、明确可写且声明 `ccrouter_generator` 的 Package，并排除
`lib/**/ccrouter_generated/**` 二次输入。

普通生成还维护 Host 专属的版本化 generation manifest。只有 authored Dart 源码、Package
配置与解析图、生成器源码、Dart SDK identity、外部 Package Index 和所有受管输出的精确内容
摘要全部一致时，CLI 才在获取锁后跳过 build_runner 与聚合。manifest 缺失、损坏或任一摘要
变化都会 fail closed 到完整流程；校验不依赖 mtime 或文件大小。`--no-cache` 永远不读取该
fast path，`--profile` 会输出 `fast-path=hit/miss`。性能回归与混合能力基准见
[`docs/CCRouter-generator-performance-report.md`](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-generator-performance-report.md)。

fast path miss 时，Profile 还会输出本轮 `build-targets`，以及逐 Package 的
`dirty-packages` 原因：`host`、`cache-missing`、`metadata`、`output`、
`dependency-index` 或 `propagated-from:<package>`。dirty set 在 build_runner 完成后计算，
用于决定 Package API、Bundle 和 capability catalog 是否可以复用；它不是 build_runner 的
输入目标列表。依赖图变化后，即使 dirty Package 很少，Workspace Analyzer 仍可能占据主要耗时。

P6 的只读归因新增 `input-delta` 和 `output-delta`。前者用已有 Build Plan 基线区分自身
authored 内容变化、解析环境变化及 `resolutionOnly`、工具/Host 图变化；后者统计本次成功
生成前后 Dart、JSON metadata、Markdown、Portable State 的精确文件差异，并按新增/删除/
修改分类。`--check` 恢复前报告，Builder/聚合失败不输出成功差异。两侧源码摘要缺失的
Package 单列 `authoredUnavailable`，不视作源码一致。输入基线不可用时明确标记
`unavailable`，不猜测；相同输入 fast path 则报告 unchanged 和零产物差异。最多输出每组
12 个 Package 名，不输出业务值或完整路径。额外输出比较耗时单列 `output-delta-scan`。
这些统计不证明语义一致，不改 schema、缓存命中或 Builder 跳过条件；不带 `--profile` 没有
额外比较。输入归因沿用 Build Plan 的默认输出目录范围；自定义 `--output-dir` 不提供
`input-delta`。采样命令：

```sh
fvm dart run packages/ccrouter_test/benchmark/generator_component_topology.dart --invalidation 1 3 5 10
```

样本包含五类能力与公共依赖，逐次变更注释、DartDoc、位置、实现、常量、描述和 barrel，
每次比较全部受管文件并执行 `--no-cache --check`。单次样本不能作为真实项目 P95 或提速结论。

失效路径的 Profile 还会输出 `shadow-closure`，这是只读的本地 Dart 文件闭包诊断，展示潜在
反向 Package/文件候选和 `fallback` Package。它不参与 Build Plan 或 Builder 跳过条件；条件
导入、缺失目标和生成目录等无法证明的输入会保守地落到 Package-wide fallback。该诊断用于
评估未来传播收窄的收益，不能替代完整内容摘要或 `--no-cache` 参考生成。

Build Plan 的 P1 诊断、P2 删除组件优化和 P3 Portable Package 新增路径会在 Profile 中输出：

```text
CCRouter profile build-plan suggested=aggregateOnly actual=aggregateOnly reasons=host-graph-changed
```

`suggested` 表示分层 Tool/Package/Host 状态计算出的候选路径，`actual` 表示本轮实际路径。
只有 Host 依赖闭包发生纯删除、没有新增 Package，并且所有保留 Builder Package 的源码、解析身份、
metadata 和受管输出完全一致时，`actual=aggregateOnly` 才跳过 build_runner；Validator、Host 聚合、
旧产物清理和失败恢复仍完整执行。普通 Host 源码变化会显示
`suggested=aggregateOnly actual=runBuilder reasons=non-builder-input-only,p2-scope-excluded`。
纯新增 Package 只有在每个新增项的 Portable Generation State 与当前源码、配置、解析依赖、
Package Index 和受管输出逐项一致时才允许 `aggregateOnly`。可写 Package 缺少或失配时回退完整
Builder；Git/Pub/Workspace 外 Path 等只读 Package 缺失或失配时明确失败，Host 不在依赖目录运行
Builder 或写文件。首次创建且尚未生成的本地组件仍执行 Builder。

本地基线位于 `.dart_tool/ccrouter/v1/build_plans/`，不属于受管生成物，也不应提交；删除、损坏、
Schema 不兼容或解析身份无法证明时都会 fail closed。设置
`CCROUTER_DISABLE_AGGREGATE_ONLY=1` 可立即关闭 aggregation-only。`--no-cache --profile` 固定报告
`suggested=runBuilder actual=runBuilder reasons=no-cache-reference`，用于逐字节参考回归；CI 继续使用
`--no-cache --check`。每个生成 Package 的
`lib/src/ccrouter_generated/metadata/ccrouter_generation_state.json` 是可提交受管产物，只包含内容
identity，不包含绝对路径、用户名、mtime、inode 或 `.dart_tool`；它不能替代 CI 权威门禁。

fast path 未命中时会先执行保守的 Component Dependency Preflight，只有直接 List、Contract
类型和 Owner 都唯一可证明时才提前失败；它不替代 Builder。所有正式 `generate` 都会在
build_runner 前保存 CCRouter 受管源码快照，Builder、聚合或最终校验失败时恢复原内容，避免
失败生成覆盖上一次可用产物。生成期间还会在 Builder/聚合边界和状态发布前重新比较完整输入
摘要；如果源码或解析环境在本轮发生变化，命令会恢复受管输出并失败，等待编辑稳定后重试。
这项屏障不使用 `mtime/size` 猜测，也不改变完整 Builder 回退语义。

生成结果：

- `@CCRoute` 的 `<page>.route.g.dart`：生成独立的 Package-private Arguments、Intent、
  Definition、Codec，以及注册和描述 bridge；页面源码不需要 `part`。
- `<page>.route_binding.g.dart`：隔离 Flutter Page 构造，只由组件 Route Catalog 引用；
  不进入 Route API 或业务 barrel。
- `@CCRouteContract` 的 `<schema>.route.contract.g.dart`：生成公开 Pure Dart Arguments、
  Intent、Definition 和私有 Codec；不包含页面、Registrar、Flutter 或路由后端类型。
- `@CCRouteImplementation` 的 `<page>.route.g.dart` 与
  `<page>.route_binding.g.dart`：分别生成 owner 注册/描述 bridge 和页面构造 bridge，
  不重复生成业务契约。
- 公开 `DetailRoute.intent(...)` 只构造 `CCRouteIntent<String>`，仍通过
  `CCRouter.navigator.push<String>(...)` 导航。
- `@CCServiceContract` 的 `<schema>.service.contract.g.dart`：生成供 Generator、低层
  Component SPI 和测试使用的强类型 `CCServiceToken<T>`；业务 contracts barrel 只需通过
  `show` 导出 authored Service 接口，不导出裸 Token。
- `@CCService` 的 `<implementation>.service.g.dart`：生成 Package-private
  `CCServiceProvider<T>` registration bridge。直接实现唯一 `@CCServiceContract` 时自动绑定；
  未实现 Contract 的内部 Service 必须声明 `id`。首版只接受 public concrete non-generic
  class 的 unnamed zero-argument generative constructor。
- `<component-source>.service_api.g.dart`：仅为 `serviceDependencies` 中显式声明的跨组件
  Contract 生成组件专属 typed Client/Proxy；同步方法保留同步签名，Future 方法进入异步
  readiness 与 Scope cancellation 边界。
- `lib/src/ccrouter_generated/<component-id>.api.g.dart`：组件业务源码使用的稳定聚合入口，
  通过受控 `export/show` 合并 Route、Service、Command 和 Event Client；没有可导出能力时不生成。
- `lib/src/ccrouter_generated/<package>.contracts.api.g.dart`：Contracts Package authored barrel
  使用的稳定 Route Contract 入口，只转发公开 Route/Arguments 类型，不替代 authored Contract
  的显式 public export。
- `<component-id>.component.g.dart`：自动生成私有 Registrar、Runtime Manifest 和后端中立的
  `CCFlutterRouteCatalog`，稳定装配 Route、Service 与 Contribution。
- `lib/src/ccrouter_generated/metadata/ccrouter_package.json`：发布级 Package Index，包含 Schema、Package
  身份、内容指纹、直接生成依赖、规范化 metadata 和版本化 Capability Source Catalog；
  Git/path/pub 依赖均从此单文件读取。
- `<package>_ccrouter.g.dart`：Host-only `CCGeneratedPackageBundle`。只 import 本 Package 的
  Manifest/Catalog 与直接 Pub 依赖的 Bundle，不加入组件业务 barrel，也不跨过 Dart 直接依赖
  边界。纯 contracts Package 只生成 JSON Index，不生成 Flutter Runtime Bundle。
- 宿主 `lib/src/ccrouter_generated/ccrouter_host.api.g.dart`：Host 公共 barrel 可稳定转发的窄
  API，只导出原子 Host Assembly；Manifest 和 Catalog 通过 Assembly 属性读取，不暴露
  Package Bundle 或装配胶水。
- 宿主内部 `lib/src/ccrouter_generated/host/ccrouter_host.routes.g.dart`：从宿主自己的 Bundle
  解析传递 Package 图，Diamond 依赖去重后生成 Manifest 与 Catalog。新增无路由的 Service
  组件也会进入 Manifest 列表；普通路由或组件增删不再要求宿主逐项维护初始化列表。
- `lib/src/ccrouter_generated/metadata/cc_catalog.md`：仅在 Package 存在 Capability 时生成，按 Component 和 Capability ID 展示
  Route、Service、Command、Event、InitTask 的契约声明、实现及相关生成物。源码位置统一记录为可移植的
  `package:name/path.dart:line:column`，不把开发机绝对路径写入生成物。组件 Package
  生成局部视图，Host 生成完整依赖闭包的全局视图；Contract-first Route 会同时显示
  contracts Package 的 schema 与实现 Package 的 Page。

`ccrouter_package.json` 是 Capability Source Catalog 的机器事实来源，`cc_catalog.md` 只由
它和同轮 metadata 派生，不维护第二套手工索引。当前 Route 与注解 Service 具备静态声明链路；
Command 使用显式 Contract、Handler 和消费依赖，Event 使用显式 Contract、静态 Subscription
和 Owner 自动 Publication，InitTask 使用显式 Task Contract、Handler 和类型化依赖；三者都
不通过扫描 Contribution 源码猜测注册关系。Action Pipeline 仍未实现。只读
`ccrouter find` 消费版本化 Catalog；DevTools 已通过版本化 Snapshot 协议和稳定 ID 关联静态
Catalog 与 Runtime 快照，不解析 Markdown 或 Builder 私有数据。

导航失败诊断中的 `CCNavigationFailureAttempt` 用于区分同一恢复链中的失败来源：原始请求
(`request`)、拦截器重定向 (`interceptorRedirect`)、Failure Policy 恢复
(`failureRecovery`) 和 Deferred Navigation 恢复 (`pendingResume`)。它只用于稳定诊断和
策略归因，不替代 `CCNavigationFailureStage`/`CCNavigationFailureReason`，也不携带 URI、Query、
Extra 或业务返回值。

Managed Route 的 PopGuard 会在业务 Pop、系统返回、Cupertino 手势和预测返回进入后端提交前
执行。Foreign Route、PopupRoute 和 `LocalHistoryEntry` 消费返回时不会关闭 CCRouter 的
Managed Route Scope。当前 Flutter/Cupertino 的保守语义是：只要 Managed Route 安装了 PopGuard，
交互式侧滑会被禁用，以防手势绕过 Guard；Guard 允许时恢复侧滑仍是后续 Flutter Route API
能力候选，不应由业务页面自行补一套拦截逻辑。

组件 Registrar 由统一 `generate` 命令自动生成到
`lib/src/ccrouter_generated/component/<component-id>.component.g.dart`。它按稳定 ID 和源文件顺序
装配 Route、Service 与 Contribution；新增页面或简单 Service 不再修改手写 Registrar。
组件内部 bridge 仍不是公共契约。生成器会删除已无来源的受管聚合文件；手写或未知文件不会
被删除。Package 没有任何生成能力时不创建 `ccrouter_generated`，最后一个受管产物移除后只
清理真正为空的目录。CI 应使用 `generate --check` 阻止陈旧生成物合入。

Catalog 只包含 Flutter 页面工厂和 `CCNavigationRoute`，不包含 `GoRoute`。GoRouter
宿主使用 `CCGoRouterAssembler` 同源生成 `routes` 与 `bindings`；以后接入 Navigator
1.0、其他 Navigator 2.0 实现或自定义后端时，可以复用同一 Catalog，仅替换
Assembler/Adapter。Shell、嵌套路由、完整 Regex 兼容入口等后端特有结构必须由宿主
提供显式 Override，不能被自动扁平化。

路由契约/注册 bridge 使用 `.route.g.dart`，Flutter 页面构造 bridge 使用
`.route_binding.g.dart`，独立路由契约使用 `.route.contract.g.dart`，Service Token 使用
`.service.contract.g.dart`，Provider registration 使用 `.service.g.dart`，均写入
`lib/src/ccrouter_generated/`。组件、路由与 Service 的逐源码 JSON 仅存在于
`.dart_tool/build/generated/<package>/lib/src/ccrouter_generated/metadata/`，是可丢弃的 Builder 到 CLI
中间数据，不属于源码或发布物；不再生成逐源码 Markdown。开发者只阅读 Package/Host 的
`cc_catalog.md`，外部工具消费 `ccrouter_package.json` 或 Host `cc_routes.json`。

`@CCRoute` 在独立生成 library 中生成 Package 内部使用的 `_DetailPageRoute` 及参数类型，
页面 library 不需要声明生成 `part`；组件唯一 Route API 提供 IDE 可发现的调用入口。
`@CCRouteContract` 始终生成公开的独立纯契约；schema 与实现位于同一 Package 时聚合为
`package` exposure，位于独立 contracts Package 时聚合为 `external` exposure。契约 Package
必须通过 public barrel 的 `show` 显式导出稳定 `<package>.contracts.api.g.dart`，消费者必须声明
直接 Pub 依赖。框架不再
维护额外的契约模式、可见性枚举或调用方 allowlist。

独立契约只允许 Dart Core 类型和页面通过显式 public package import 引入的 Pure Dart
类型。页面本地类型、private 类型、`package:*/src/`、Flutter、`dart:ui` 和 GoRouter
类型会在生成阶段失败；复杂默认值暂时只支持 primitive 或 enum 常量。

内部路由需要升级时保持原 `routeId` 和参数 wire name，把路由元数据移动到
`@CCRouteContract` schema，再将页面注解替换为 `@CCRouteImplementation`。实现 Package
可以临时 re-export 新契约兼容旧 import；新消费者必须直接依赖 contracts Package。

组件身份建议放在 `lib/src/` 的独立文件中；只有存在手写能力时才增加 Contribution 文件：

```text
src/order_component.dart
src/order_component_contribution.dart # optional
```

组件业务 barrel 只导出明确公开的业务契约，不导出 Component、Contribution、Manifest 或
Registrar；生成的 `<package>_ccrouter.g.dart` 是唯一 Host 装配入口。

## 首版约束

- 页面必须为非抽象、非泛型类，有未命名的 generative constructor。
- 必须显式指定结果类型；无结果使用 `CCRoute<void>`。
- Path 按构造参数名称自动推断，不可为空或带默认值。
- Query 显式注解，可指定 URI key；支持 String、int、double、bool、enum、由这些标量组成的
  `List<T>`/`Set<T>`，以及通过 `CCRouteQueryCodec<T>` 显式声明的复杂 shareable value。
  支持可空值和构造器默认值；bool 只接受 `true/false`，double 拒绝非有限值。
- Query 集合编码为 repeated key。List 保序，Set 去重并按 wire value 生成稳定顺序；生成的
  Arguments 和解码结果都会复制为不可变集合。空集合因无法与缺失 key 区分而被拒绝。
- 自定义 Query Codec 必须是 concrete、non-generic、无参 const 构造，并与参数非空类型精确
  匹配；Codec 异常和空编码结果统一转换为脱敏的 `CCRouteParameterError`。
- 标量 Query 重复、缺失必需值、非法类型会抛出 `CCRouteParameterError`；
  消息包含路由和参数名称，不包含原始参数内容。
- 最多一个显式 Extra，保持对象身份；生成的页面 binding 保留声明类型，并在 decode 边界
  校验运行时对象类型，类型不匹配时抛出脱敏的 `CCRouteParameterError`。启用 Deep Link 时
  不能要求必需 Extra。
- 可选且未注解的 Flutter `key` 不进入契约；其他未映射参数构建失败。
- 单地址路由使用 `pattern`，生成器自动补齐 primary；多地址路由使用 `patterns`。
  两者不能同时设置。多值只有一个可逆 Pattern 时自动补齐 primary，存在多个可逆
  Pattern 时必须显式指定一个 primary。别名必须捕获相同的 Path 参数；支持 Path、
  URI、Regex Pattern 以及 Presentation、Placement、拦截器 ID 元数据。
- 组件生成物不生成 GoRoute、不选择路由后端；宿主生成物只聚合中立 Catalog。
- 一个实现 Package 必须且只能声明一个 public top-level `const CCComponent`；contracts
  Package 可以声明多个 `CCComponentId`，但不声明 `CCComponent`。
- `@CCServiceContract` 只用于 public abstract non-generic interface，并显式声明
  `componentId` 和稳定 ID。`@CCService` 只自动绑定一个直接实现的 Contract；多个直接
  Contract、Contract 与 `id` 并存、或只通过间接继承获得 Contract 都会生成失败。带参构造、
  依赖注入、自定义 Factory 和 async initializer 继续使用 `@CCComponentContribution`。
- Service 注解生成内部 Token、Provider registration 和 Catalog metadata；消费组件的
  `serviceDependencies` 生成方法级 typed Proxy。普通本地 Service 仍按接口类型直接解析，
  只有显式跨组件消费进入 invocation method Trace。

具名/Factory 页面构造器留到后续阶段；未命名构造器的继承参数、required positional、
optional positional、named 参数、默认值和跨 Package import 已覆盖。聚合校验同时
检查同层、同具体度且能够静态证明的
Path/URI/Regex Pattern 冲突；约束表达式仅在可证明互斥时排除重叠，复杂正则歧义仍由
Runtime 注册兜底。

## 回归

构建工具测试在 Dart VM 下运行，全部测试仍归属于 `ccrouter_test` 包：

```sh
fvm dart test packages/ccrouter_test/generator_test
fvm flutter test packages/ccrouter_test/test demo/test
fvm flutter analyze packages demo
```

生成样例和测试 Fixture 的 `.route.g.dart` 纳入版本管理，方便直接打开 demo；
路由源码放在 `lib/src/` 时，生成文件会保留源码相对目录并写入
`lib/src/ccrouter_generated/`。修改声明后必须重新生成并做静态检查。

统一命令首先从 Host 对应的 `.dart_tool/package_graph.json` 沿正式 `dependencies` 计算运行时
闭包，再由 `.dart_tool/package_config.json` 精确定位 workspace/path/Git/pub Package。它不会
扫描无关 workspace Package，也不会纳入 `devDependencies`；缺少解析图时明确要求先执行 Pub
get，不回退为全仓扫描。本地可写 Package 只读取当前 workspace 对应的
`.dart_tool/build/generated/<package>/lib/src/ccrouter_generated/metadata/**/*.component.json`、
`*.route.json` 和 `*.service.json`，不会回退扫描源码树；外部只读 Package 只读取发布的单一 Package Index，
Host 不会写入 path/Git/pub 依赖或 Pub cache。

嵌套依赖通过分层 Bundle 连接：Host 只 import 直接依赖，直接依赖再 import 自己的直接依赖。
同 Package ID 的版本或指纹不一致、外部 Package 缺少/损坏/Schema 不兼容的 Index、嵌套
Runtime Package 的中间 Package 未直接依赖 `ccrouter` 或未发布 forwarding Bundle，都会在生成
阶段失败，不通过非法传递 import 兜底。除框架自身 Package 外，任何直接依赖 `ccrouter` 或
`ccrouter_contracts` 的 Package 都必须发布 Index；没有注解时生成空 Index。该规则不依赖外部
Package 的 `devDependencies` 是否被 Pub 保留，因此不会把“漏生成”误判成“未参与”。

聚合校验组件/路由/Service ID、Route 与 Service 所有者、Service Contract/Provider 冲突、
required dependency 缺失、自依赖、依赖环、契约 exposure 与声明形态是否一致、external
实现所有权、静态 Pattern 冲突，以及
所有非 internal 路由是否由公共 barrel 使用 `show` 同时导出 Route 和 Arguments 契约；
不存在的 optional dependency 被忽略，存在时参与与 Runtime 一致的确定性拓扑排序；
它会在 Host 的 `lib/src/ccrouter_generated/metadata/` 下生成机器可读的 `cc_routes.json` 和合并路由定义、
源码位置、生成物位置的人类可读 `cc_catalog.md`。本仓库的扫描根目录是 `demo`，因此输出位于
`demo/lib/src/ccrouter_generated/metadata/`。也可以通过 `--output-dir <directory>` 指定其他
输出目录；校验失败时返回非零退出码。
