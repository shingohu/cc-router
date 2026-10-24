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

可选类型化 UI Fragment 也使用现有 `generate` 和 `portable prepare/publish`，不需要额外命令。
契约包通过 `ccrouter_ui_contracts.dart` 声明 Contract，Renderer 和消费组件直接依赖
`ccrouter_ui`；消费者在 `uiDependencies` 声明 Contract、版本范围与 alias，并把 Owner 保留在
required `dependencies`。Generator 校验 DTO、普通 enum、有效默认值指纹和静态 Renderer
装配，生成消费者专属 `<componentId>.ui.api.g.dart`。消费方不得导入 Owner Renderer 或
`ui/*.ui.g.dart` SPI。实际消费 UI 的 Host 直接依赖 `ccrouter_ui`，启动仍传一个完整 Assembly。
UI source metadata 使用 schema 5；enum Action 保留 `uiSchemaVersion: 1` / Index schema 3，
受限 DTO Action 使用 UI schema 2 / Index schema 4，混合文档取最高版本；
未声明 UI 的 Package 保持原 schema。必须配套使用匹配版本的 Generator、Contracts、CCRouter
和 UI Package。`create ui-fragment ... --dry-run` 可预览契约、公共入口及可选 Renderer；
UI `find --usage` 从索引中的完整 schema 公共导出和实际 alias 输出接入步骤，旧索引需重生成。
脚手架默认 enum Action，动态选择 ID 可显式改为受限 DTO；根 scalar Action 不支持。
参与生成的 contracts、Owner、Consumer 各包需声明自己的 `ccrouter_generator` dev dependency，
Host 同时需要 `build_runner`。生成后核对组件/UI 数量，Host 依赖不能代替成员包声明。
`ccrouter_ui` 是框架依赖，无需业务 Package Index 或 Portable State；生成与 `find`
忽略框架依赖的遗留索引，外部分发业务组件仍需自己的有效索引与状态。
Analyzer 已有保守 UI 诊断和 required Owner Quick Fix；UI DevTools Catalog 仍未实现。详见
[UI Fragment 接入指南](../../skills/ccrouter-integration-development/references/ui-fragments.md)。
[独立 enum/DTO 验证](../../docs/validation/ui-fragment-adoption-20261020/README.md)记录本地闭环与
复现源码；该结果不代表公开 API 冻结、正式分发或真实平台验收完成。

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
    show DetailPageRoute;
```

`<package>.contracts.api.g.dart` 只聚合公开 Route Consumer 的生成类型，隐藏逐源码
`.route.contract.g.dart` 路径。authored Service、Command、Event 和 InitTask 契约仍由公共 barrel
显式导出；生成器不会替 Package 决定这些 API。每层转发都必须保留完整 `show`，最终到达
`lib/` 顶层 public library。`clean` 后的下一轮 `generate` 会为显式引用的缺失稳定入口创建受管
placeholder，Builder 完成后立即替换为正式 exports。

组件的 `dev_dependencies` 添加 `ccrouter_generator`，workspace 根目录添加
`build_runner`。本仓库在根目录执行：

```sh
# 创建一个新的组件 Package；不会覆盖已有文件
fvm dart run --verbosity=error ccrouter_generator:ccrouter create component demo_inventory demo/modules

# 可选：同时创建默认作为 CCRouter Host 的 Flutter example app
fvm dart run --verbosity=error ccrouter_generator:ccrouter create component demo_inventory demo/modules --with-example

# 在组件中创建一个内部 Route 页面；不会自动创建跨组件 Contract
fvm dart run --verbosity=error ccrouter_generator:ccrouter create page InventoryPage demo/modules/demo_inventory

# 创建组件内部能力模板；不会修改 Host 或生成目录
fvm dart run --verbosity=error ccrouter_generator:ccrouter create service OrderSummary demo/modules/demo_inventory
fvm dart run --verbosity=error ccrouter_generator:ccrouter create command ReserveOrder demo/modules/demo_inventory
fvm dart run --verbosity=error ccrouter_generator:ccrouter create event OrderPaid demo/modules/demo_inventory
fvm dart run --verbosity=error ccrouter_generator:ccrouter create event OrderPaid demo/modules/demo_inventory --with-subscriber
fvm dart run --verbosity=error ccrouter_generator:ccrouter create init-task WarmCache demo/modules/demo_inventory
fvm dart run --verbosity=error ccrouter_generator:ccrouter create init-task WarmCache demo/modules/demo_inventory --with-contract

CCROUTER_PUB_HOOK_DISABLE=1 fvm flutter pub get
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo
```

这里禁用 Hook 的 Pub 命令仅用于本仓库 Workspace 聚合根的依赖解析；Host 生成仍显式选择
`demo`。在外部应用中，应从实际 Host 运行 Pub 与生成检查。

Analyzer 是可选的 Host 开发工具，独立于生成流程：

```sh
ccrouter analyzer status <host-root>
ccrouter analyzer doctor <host-root>
ccrouter analyzer pin-check <host-root>
ccrouter analyzer install <host-root> --version <published-version> --dry-run
ccrouter analyzer install <host-root> --source git --url <remote-url> --ref <full-commit-sha>
ccrouter analyzer upgrade <host-root> --ref <full-commit-sha>
ccrouter analyzer uninstall <host-root> --dry-run
```

写入命令支持 `--dry-run`，只管理 CLI 创建的隔离 bootstrap 和 Host 配置叶，先验证候选
loader 再运行禁用 Hook 的 Host Pub。现有手工装配不自动接管，未知文件保留；普通失败恢复
记录的配置/解析文件，并发冲突或中断保留恢复日志。Hosted 需显式指定已发布版本，Git 需远端
完整 SHA。完成后重启 Analysis Server，并验证实际 IDE 诊断；不隐式挂入 generate 或 Pub Hook。
`install`/`upgrade` 目前是 legacy maintenance-only 路径，会输出弃用提示；Hosted 发布后优先
在 Host 的普通 `dev_dependencies` 中声明插件。`status`/`doctor`/`uninstall` 仍用于既有隔离
bootstrap 的诊断与回退，私有 `.plugin_manager` 只提供 advisory，不是跨 SDK 权威门禁。
`pin-check` 只供 maintainer/release 手动验证 Git manifest/lock/`resolved-ref`、远端完整 SHA
和 pin 之后的 Plugin `lib` 变化；发现 pending 生产变化不会失败，以保留先推 Plugin、再独立
bump pin 的两阶段流程。`doctor` 把 source、cache、temporary loader smoke、restart 与 live IDE
verification 分开报告；cache 异常时只列出相关进程候选和手工备份路径，不自动 kill 或清理。
完整说明见 [Analyzer CLI 指南](../../docs/CCRouter-analyzer-cli-plan.md)。

如果希望在当前 Flutter SDK 的 `flutter pub` 或 `dart pub`
`get/upgrade/downgrade/add/remove` 成功后自动生成，可以显式安装可回滚的 hook：

```sh
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook install
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook status
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook uninstall
```

Hook 按 SDK 版本独立安装，不修改 Flutter snapshot；macOS/Linux 同时包装 Flutter SDK 的
inner Dart executable，Windows 包装 `bin/dart.bat`，但无法拦截 IDE 直接执行的 `dart.exe`。
非 CCRouter 项目以及没有直接声明
`ccrouter` 的 Workspace 聚合根会跳过，不会猜测成员 Host。wrapper 只按已知 global option
arity 定位真实 top-level command 和 Pub subcommand；参数值中
出现 `pub`、`run`、`build` 或 `get` 不会触发 Hook，未知 global option 则安全交还原 CLI。
完整退出码语义、FVM 版本切换和禁用方式见
[`docs/CCRouter-cli-pub-hook.md`](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-cli-pub-hook.md)。
普通 `flutter build` preflight 在 active watch 下会验证并复用精确 cycle 后继续平台构建，
成功摘要保留 `reused active watch cycle`。DevEco/Hvigor 直构建绕过 Flutter wrapper；OHOS
Host 需要在 Flutter Hvigor `FlutterTask` 前调用同一 `pub-hook run --pub-command build`，参考
仓库 `demo/ohos/ccrouter-preflight.js` 与 `hvigorfile.ts`。
`--verbosity=error` 只压低 Dart/Pub 在 CLI 启动前的依赖解析和 executable 构建噪声，
不会隐藏 CCRouter 自己的进度、诊断或失败。

`create component <package-name> [parent-directory] [--with-example]` 会生成
`pubspec.yaml`、`project_type: package` metadata、Package barrel 和
`lib/src/<package>_component.dart`；Descriptor 不会从根 barrel 导出。可选 example 由当前
Flutter SDK 的 app template 生成，直接依赖组件与 CCRouter 工具，`project_type: app` 默认是
Host。入口已安装生成的 Assembly 和 `CCManagedRouterApp`，Example 自己声明 `/` 首页。
组件和 Example 均有可证明来源的 `build_runner` 和同 SDK 的 Flutter 测试依赖。
Workspace 需要按 `Next steps` 同时登记组件和 example。独立组件还会启用 Portable State：
先在组件目录 Pub get、`ccrouter portable prepare .`，再在 Example Pub get、`ccrouter generate .`。
组件变更后重新 prepare；Example 不会写入其只读父组件。独立解析的工具链不一致时先对齐
依赖版本，不能绕过 Portable 校验。
Example 从组件 staging manifest 重算依赖，不在 Flutter 创建后重新读取上游工具版本。
SDK 范围和看似数字、布尔值或 alias 的 Git ref 会按解析后的实际类型决定是否引用，保留字符串身份。
`create page <PageName> [component-directory]` 会生成
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
命名约束时都会失败并返回非零。Component 会在同一父目录中完整 staging，Flutter example
创建失败不会发布部分 Package，成功后才原子 rename。它们不修改已有 Host 依赖、不创建 generated 文件，也不替代后续
的 `pub get` 和 `generate`。创建成功后会输出 `Next steps`：Component 会提示 Workspace 与
消费者依赖装配，其它模板会提示先完善源码再为实际 Host 生成；提示本身不会修改工程。

该命令先解析 requested Package 与 Pub resolution root，再按 `.metadata`、`ccrouter.yaml` 和
直接 CCRouter 依赖选择角色。app-role Host 为其可写 dependency closure 运行 Builder、跨
Package 校验、Host assembly 和 Host Catalog；其它 Flutter/Pure Dart 参与 Package 只更新
自身 Builder/API/Bundle/Package index/catalog，不执行 Host 完整性校验，也不写入 sibling
Package。无直接 CCRouter 依赖的 Workspace aggregator 会跳过。package-local 暂不支持
`--output-dir` 或 watch，Host CI 仍使用最终 `--no-cache --check` 权威门禁。
非 workspace 包也使用同一命令，不需要自行拼接两步流程。
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
之外的文件。扫描遇到嵌套 `pubspec.yaml` 即停止，组件内独立运行的 `example/` Host 由自己的
generate/clean 管理，父组件或其它 Host 不会删除、覆盖或计入它的生成物。保留的 build cache
有效时，`generate` 会先从 Builder metadata 临时恢复 authored
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

普通生成默认只额外输出最终总耗时。大型工程在耗时异常时可以显式观察分阶段耗时和缓存
命中率，或强制走无缓存参考路径：

```sh
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --profile
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --watch=auto --machine
fvm dart run --verbosity=error ccrouter_generator:ccrouter watch status demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter watch follow demo
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

Tool fingerprint 使用显式 execution-kernel ownership：生成器 `lib/`、主生成入口、Build
Plan、Portable State 和 `build.yaml` 会影响身份；Analyzer bootstrap、scaffold 模板和
Pub hook 属于 CLI integration，不会使生成 tool identity 变化。新增会影响生成结果的模块时，
必须在 `bin/src/execution_kernel.dart` 中加入边界并增加 identity 回归，而不是扩大整个 `bin/`
目录扫描。

fast path miss 时，Profile 还会输出本轮 `build-targets`，以及逐 Package 的
`dirty-packages` 原因：`host`、`cache-missing`、`metadata`、`output`、
`dependency-index` 或 `propagated-from:<package>`。dirty set 在 build_runner 完成后计算，
用于决定 Package API、Bundle 和 capability catalog 是否可以复用；它不是 build_runner 的
输入目标列表。依赖图变化后，即使 dirty Package 很少，Workspace Analyzer 仍可能占据主要耗时。

`--profile` 还会输出 `CCRouter profile trace=<json>`，其中 schema `1` 使用单调时钟记录
锁等待、Workspace/Build Plan/fingerprint、Portable State、preflight、快照、build_runner
子进程、聚合/校验/写入、`--check` 恢复和本地状态提交等阶段的 `startUs`、`durationUs`、
`status` 与有界计数。最新报告会原子写到
`.dart_tool/ccrouter/v1/profiles/<host-identity>/latest.json`，不包含绝对路径、源码或业务值，
也不参与生成决策。Profile 模式同时向 build_runner 传入官方 `--verbose-durations`，用于查看
各 Builder phase 的 analyzing/resolving/tracking/building/reading/writing 明细；该上游文本不是
CCRouter JSON schema 的一部分。未传 `--profile` 时不会创建或更新报告。

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

样本包含五类能力与公共依赖，逐次变更注释、DartDoc、位置、实现、常量、描述、dependency/public
barrel、Package dependency edge 和声明删除；每次比较全部受管文件并执行 `--no-cache --check`。
单次样本不能作为真实项目 P95 或提速结论。
Profile 的 `aggregation-input-fingerprint` span 会在 `attributes.fingerprint` 中报告 Builder
metadata、Package Index identity 与 Host graph 的聚合输入摘要。它不允许跳过 Builder；Builder
成功后，只有该摘要、Tool identity 和全部 aggregation-owned output bytes 同时匹配上次成功的
本地证明，才跳过重复的 aggregation rendering/writes。Workspace Validator、Package graph/index
构造和前后 input barrier 始终执行。状态位于 `.dart_tool/ccrouter/v1/aggregation_reuse/`，缺失、
损坏、输出篡改、metadata cache 损坏或 identity 变化均 fail closed；损坏 cache 由完整路径重建。
`CCROUTER_DISABLE_AGGREGATION_REUSE=1` 恢复完整 aggregation，`--no-cache` 固定报告
`miss/no-cache-reference`。矩阵同时要求 optimized 与
`--no-cache --check` reference 得到相同 fingerprint 和逐字节产物；被 Builder 消费但不被
aggregation 消费的默认常量允许只改变 Builder Dart，Package dependency edge 即使没有当前
产物差异也必须改变 fingerprint。

本地持续开发可用 `--watch=auto` 保持当前 build root 的 build_runner AOT entrypoint 和
Analyzer graph。每次 Builder 成功后先验证 exact-content fast path；未命中时仍走完整
CCRouter 校验、聚合、快照与原子提交；
同一 resolved build root 的不同 Host 共享一个 Builder owner 和活动 Host target union，但保留
各自的 aggregation、Validator、原子发布、lease、状态、diagnostics 与 Host-scoped
`inputRevision`。`status.json.pid` 表示本 Host watch，`builderOwnerPid` 表示共享 Builder owner；
owner 退出后 subscriber 可接管。同一 Host 不允许同时启动两份 watch，以免竞争同一状态文件。
Hook 管理的同 Host 并行 `flutter run` 不属于两份 watch：每个 run 维护独立 heartbeat lease，
通过 watch PID 绑定的 acknowledgement 接入一个 Host watch；任一 run 退出只释放自身 lease，
最后一个有效 lease 消失后 watch 才停止。并发候选若未取得 registration，不会覆盖 active
status，而是等待接入或在旧 watch 退出后重新竞选。
设置 `CCROUTER_DISABLE_MULTI_HOST_WATCH=1` 可恢复旧的单 watch ownership 语义做 A/B。
watch 停止或 session restart 时，build_runner child 依次获得 10 秒 SIGINT、5 秒 SIGTERM 和
5 秒 SIGKILL 回收窗口；每一阶段都有上限，卡住的 child 不会让 generation lock 永久不释放。
`--machine` 将 stdout 限定为 schema `1` NDJSON，普通 build_runner 日志走 stderr。
默认事件保留 Builder 与聚合最终耗时；只有显式追加 `--profile` 时，
build_runner 才启用 `--verbose-durations`，且 `aggregationSucceeded.profile` 才携带完整 cycle
trace。默认 `build` 是 CCRouter 观测的端到端耗时，精细的 `build_runner` 上游耗时仅在 Profile
模式可用。性能 benchmark 和 AI 慢任务诊断应显式使用该参数，不根据调用者身份隐式开启。
`buildSucceeded.buildRunner` 和 Builder 阶段失败事件中的同名字段使用结构化
`formatVersion: 2`。默认是 `available: false, reason: profile-disabled`，不会把未采集数据表示成
零 counters；外层事件仍保留 CCRouter 实测耗时。`--profile` 下是 `available: true`，包含 Builder
报告的总耗时、写入数以及每个 phase 的耗时、inputs、skipped、not-triggered、
invalidated/executed input、new/same/no-op output
和达到上游阈值的 activity 耗时。该统计仅解析 build_runner 正式 console 输出，不访问 private
Asset Graph；未知终态格式以有界 `unparsedFinalLines` 保留且不影响生成成败。
`CCROUTER_LEGACY_UNPROFILED_BUILD_RUNNER_REPORT=1` 可恢复旧空 counters 做 A/B。
设置 `CCROUTER_DISABLE_BUILD_WATCH=1` 可回退为一次 one-shot。watch 不替代最终的
`--no-cache --check`；它在 lease 内持有 root generation lock，应先停止再运行最终门禁。
同 root 的普通 `generate` 与 `generate --check` 会等待并复用 active watch 的精确 Pub resolution、
authored input 与 managed output 完成证据，不会并发启动第二个 writer；失败、退出、证据不匹配或
五分钟超时仍 fail-closed。`--no-cache`、`--profile`、自定义输出、portable prepare 与 `clean`
继续快速失败。`CCROUTER_DISABLE_ONE_SHOT_WATCH_REUSE=1` 可恢复旧 reject-only 路径做 A/B。
已有 one-shot 正在执行或等待时，新的 watch 同样会快速失败，调用方可在命令完成后重试启动 watch。
共享只覆盖单个 resolved build root，不合并嵌套 Package Host 的独立 Pub root。subscriber
退出不会为了收缩 target union 重启当前 child；Pub resolution 中真实的 target 删除仍会重启。
Hook 的 `watch ready`/`watch reused` 提示写入 stdout，与 preflight 成功信息保持一致；真正失败
仍写 stderr，避免 IDE 将正常启动渲染成红色错误。detached coordinator 独立持有重定向后的
watch 输出，不依赖任一 Flutter run supervisor 的存活。
Windows 的原 Flutter Tool 由 Dart supervisor 继承终端运行。supervisor 在进程存活期间刷新
自己的版本化 lease heartbeat，并在正常或可处理的异常退出时删除该 lease；强制终止时 watch
会使该 heartbeat 过期，全部 Host lease 消失后自行停止。`CCROUTER_DISABLE_WINDOWS_RUN_SUPERVISOR=1` 仅用于恢复旧 batch
生命周期做 A/B。
Hook 对 `flutter run --machine` 增加只代理 stdin 的 reload gate。它等待 watch 的
`completedInputRevision` 覆盖保存时的 `inputRevision` 且状态稳定，再把
`app.restart` 转发给原 Flutter Tool；失败返回标准 daemon error 和有界 Generator
diagnostics。topology 变化设置 `hotRestartRequired`，Hot Reload 被拒绝，显式 Hot
Restart 得到 daemon 成功响应后才解除当前 run session 的栅栏。普通交互式终端 `r`
不经过该 machine gate；使用前先通过 `watch follow` 确认本轮聚合成功。
交互式 `flutter run` 会在启动 Flutter Tool 前明确打印这一限制，避免把已启动 watch
误认为终端 `r/R` 同样受到 generation gate 保护。
`CCROUTER_DISABLE_HOT_RELOAD_GATE=1` 只回退这一协调层。
watch 会原子发布 `.dart_tool/ccrouter/v1/watch/status.json`；`watch status <host>` 读取一次
当前状态，`watch follow <host>` 持续输出简洁状态变化。Hook 启动的完整 build_runner 日志仍在
`.dart_tool/ccrouter/v1/watch/flutter-run.log`，不会污染 Flutter Tool 的 machine stdout。
同一 Host 执行成功的 `flutter pub` 或 `dart pub` `get/upgrade/downgrade/add/remove` 时，
post-pub Hook 会以
当前 Pub 解析文件为栅栏等待活动 watch，而不是并发启动 one-shot。成功复用对应
`aggregationSucceeded`；失败则返回非零并输出该轮有界 diagnostics。状态不可用、watch 退出
或 5 分钟超时均 fail-closed，且不会把另一个 Host 的状态当作完成证据。
非 Host 的 Flutter component 与 Pure Dart contracts Package 由同一 Hook 触发
package-local generation，只更新 requested Package 的 artifacts，不执行 Host 聚合或跨 Package
校验。若同 build root 的 Host watch 活跃，成功 cycle 会发布 Package 级 Pub resolution、authored
input 和 managed output 指纹；Hook 重新计算并完全匹配后复用，不再要求停止 watch。旧版状态、
target 缺失、指纹不匹配或失败仍 fail-closed。`CCROUTER_DISABLE_PACKAGE_WATCH_REUSE=1` 可恢复
原有拒绝行为做 A/B。无直接 `ccrouter`/`ccrouter_contracts` 依赖的 Workspace aggregator 继续跳过。
状态发布失败只警告并停止后续状态写入，不影响生成锁、Builder、Validator、快照恢复、原子发布
或最终 `--no-cache --check`。watch 异常退出且未写入 `stopped` 时，只读命令会根据已释放的
owner lock 将遗留 `active` 记录显示为 `stale`，但不会改写历史状态文件。
Builder 成功后的 cycle 会跳过已无决策价值的普通 fast-path inspection 和 Build Plan 推导，
但不跳过 input barrier、preflight、Validator、聚合、快照或状态写入。设置
`CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION=1` 可恢复旧 cycle planning 路径做 A/B 对照。
cycle 默认直接复用 watch 进程内的 generation kernel，不再为每轮启动 generator 子进程；
machine 事件通过 `aggregationSucceeded.cycleMode=inProcess` 明确该路径。设置
`CCROUTER_DISABLE_WATCH_IN_PROCESS_CYCLE=1` 可恢复 `subprocessReference`，用于逐字节和耗时
A/B；该开关不允许跳过快照、Validator、原子提交或最终 `--no-cache --check`。
成功 cycle 的 fast-path manifest 与本机 Build Plan state 复用一次 exact-content planning
snapshot，并继续分别原子写入。设置 `CCROUTER_DISABLE_SHARED_PLANNING_SNAPSHOT=1` 可恢复
两个状态各自扫描的 reference 路径，用于逐字节和耗时 A/B；它不削弱任何输入屏障或最终门禁。
one-shot 与 watch 默认还复用最终 input barrier、profile/check output delta 或 metadata-cache
persist 已读取的 exact bytes，形成只供本轮 planning 派生的 unified epoch evidence。设置
`CCROUTER_DISABLE_UNIFIED_EPOCH_SNAPSHOT=1` 可恢复独立 planning recapture；入口 rollback snapshot、
Builder/aggregation barrier 和 restore 时的独立重扫均不受影响。
one-shot build_runner 还会从入口 snapshot 派生 build root 内 non-target output protection；root 外
read-only Package 继续独立捕获。`CCROUTER_DISABLE_SHARED_BUILD_PROTECTION_SNAPSHOT=1` 恢复二次
filesystem scan，Profile 的 protection span 以 `evidenceMode=shared/recaptured` 区分。Builder 后
restore 仍重新扫描并逐字节比较，build filters 不是正确性证明。
aggregation reuse 直接复用 cycle 入口 artifact snapshot 和上述 cycle-end planning snapshot
中的 bytes，不额外扫描生成目录；命中时也不重写 metadata cache，未来 miss 只会更保守地重算。
watch 的 after-aggregation barrier 返回它刚完成的 exact-content input snapshot，cycle-end
planning state 直接复用该证据；aggregation reuse 命中时还复用入口 snapshot 中已验证未变的
aggregation-owned bytes，但始终重新读取当前 Builder-owned outputs。Profile 的
`planning-snapshot-capture.attributes.evidenceMode` 为 `input-and-aggregation-output`、`input` 或
`recaptured`。设置 `CCROUTER_DISABLE_WATCH_EVIDENCE_REUSE=1` 可恢复完整 recapture 做 A/B；
该开关不改变 barrier、Validator、原子写入、失败恢复或最终 `--no-cache --check`。
watch 的 `output-delta-scan` 已经读取本轮 Builder 和 aggregation 完成后的 current managed-output
bytes，因此 planning state 直接消费同一份 exact-content evidence，Profile 报告
`input-and-current-output`。`CCROUTER_DISABLE_WATCH_OUTPUT_EVIDENCE_REUSE=1` 只关闭 current-output
复用并退回上一层 evidence；`CCROUTER_DISABLE_WATCH_EVIDENCE_REUSE=1` 仍关闭全部 evidence reuse。

生成主路径不会计算文件闭包 shadow，也不会为此扫描 Workspace Dart 文件。历史 shadow
采样保留在性能报告中，仅作为 benchmark/tooling 研究数据；它不参与 Build Plan、Tool
fingerprint、Builder 跳过条件或任何正确性判断。完整内容摘要、输入一致性屏障和
`--no-cache --check` 仍是唯一的生成正确性参考。

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
`lib/src/ccrouter_generated/metadata/ccrouter_generation_state.json` 只有在 Package 通过
`ccrouter.yaml` 的 `generation: { portable: true }` 显式声明后，才由
`ccrouter portable prepare <project-root>` 按 Host closure 或 requested Package 的角色写作用域，
作为可提交受管产物写入；它只包含内容 identity，不包含
绝对路径、用户名、mtime、inode 或 `.dart_tool`，也不能替代 CI 权威门禁。普通 `generate` 不再
写入 Portable State；writable 未声明 Package 回退完整 Builder，已声明的只读 Package 缺失或
失配则 fail closed。`ccrouter portable publish` 只做本地 readiness check。

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
  使用的稳定 Route Consumer 入口，只转发公开 Route 类型；Arguments、Definition 和 Codec
  保留在 generated Owner SPI，不替代 authored Contract
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
Managed Route Scope。原生 Managed 默认 opaque iOS 页面会在侧滑开始前同步评估 Guard：
拒绝时不启动动画，允许时保留 Flutter 跟手转场；取消和提交分别保持与结束精确实例。
自定义转场保留保守 fallback，不应由业务页面自行补一套拦截逻辑。

组件 Registrar 由统一 `generate` 命令自动生成到
`lib/src/ccrouter_generated/component/<component-id>.component.g.dart`。它按稳定 ID 和源文件顺序
装配 Route、Service 与 Contribution；新增页面或简单 Service 不再修改手写 Registrar。
组件内部 bridge 仍不是公共契约。生成器会删除已无来源的受管聚合文件；手写或未知文件不会
被删除。Package 没有任何生成能力时不创建 `ccrouter_generated`，最后一个受管产物移除后只
清理真正为空的目录。CI 应使用 `generate --check` 阻止陈旧生成物合入。

Catalog 只包含 Flutter 页面工厂和 `CCNavigationRoute`，不包含 `GoRoute`。原生 Managed
Host 将 Catalog 投影为 Navigator.pages；自定义 Backend 可通过 Host SPI 复用同一 Catalog。
原生 Managed 的 Shell/Outlet 由 Host 显式装配，声明的 parentRouteId 由 Runtime 解析为
祖先链；自定义后端仍须自行提供对应拓扑能力，不能自动扁平化。

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
所有非 internal 路由是否由公共 barrel 使用 `show` 导出 generated Route Consumer；
不存在的 optional dependency 被忽略，存在时参与与 Runtime 一致的确定性拓扑排序；
它会在 Host 的 `lib/src/ccrouter_generated/metadata/` 下生成机器可读的 `cc_routes.json` 和合并路由定义、
源码位置、生成物位置的人类可读 `cc_catalog.md`。本仓库的扫描根目录是 `demo`，因此输出位于
`demo/lib/src/ccrouter_generated/metadata/`。也可以通过 `--output-dir <directory>` 指定其他
输出目录；校验失败时返回非零退出码。
