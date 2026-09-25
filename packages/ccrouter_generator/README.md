# CCRouter 路由生成器

组件的开发工具，不属于运行时依赖。页面库使用业务门面（非前缀导入）：

```dart
// lib/src/detail_page.dart
import 'package:ccrouter/ccrouter.dart';
import 'ccrouter_generated/component/order_component.route_api.g.dart';

const orderComponent = CCComponentDescriptor(
  id: 'order',
  version: '1.0.0',
);

@CCComponent(orderComponent)
final class OrderComponentRegistrar implements CCComponentRegistrar {
  const OrderComponentRegistrar();

  @override
  void register(CCRegistry registry) {
    orderGeneratedRoutes.register(registry);
  }
}

@CCRoute<String>(
  component: orderComponent,
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
  component: orderComponent,
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

Registrar 文件还需要声明生成的 Manifest Part：

```dart
part 'ccrouter_generated/component/order_component_registrar.component.g.dart';
```

声明 `@CCRouteContract` 的 Package 需要直接依赖 `ccrouter_contracts`，公共 barrel 只导出
生成的契约 library。同 Package Contract-first 可用于渐进迁移；独立 contracts Package
用于稳定的跨组件边界：

```yaml
dependencies:
  ccrouter: ^0.1.0
  ccrouter_contracts: ^0.1.0
```

```dart
export 'src/ccrouter_generated/contract/detail_page.route.contract.g.dart'
    show DetailPageRoute, DetailPageRouteArguments;
```

组件的 `dev_dependencies` 添加 `ccrouter_generator`，workspace 根目录添加
`build_runner`。本仓库在根目录执行：

```sh
fvm flutter pub get
fvm dart run ccrouter_generator:ccrouter generate demo
```

该命令自动寻找包或 Dart workspace 根目录，先调用现有 build_runner，再执行 metadata 校验、
组件索引、Host Catalog 和文档聚合。非 workspace 包也使用同一命令，不需要自行拼接两步流程。
新增或修改注解页面后再次运行相同命令；源码无需添加 `part` 或手动更新 Registrar。
首次生成前 IDE 不会提供尚不存在的 Route API 符号；生成完成后可使用 IDE 自动导入
本组件的 `src/ccrouter_generated/component/<component>.route_api.g.dart`。
页面重命名、移动或删除也使用相同命令清理旧生成物，并可用 `--check` 验证产物同步。
CI 使用只读门禁：

```sh
fvm dart run ccrouter_generator:ccrouter generate demo --check
```

`--check` 在生成前后只比较 CCRouter 管理的产物；发现新增、删除或内容变化时恢复原文件并返回
非零退出码，不依赖 Git，也不会把业务源码或其它工具的改动算作陈旧生成物。旧的
`ccrouter_generator aggregate` metadata-only 入口仅为脚本兼容保留，新项目不应使用。

如果需要在重新生成前清理当前 Host 运行时依赖闭包中的 CCRouter 生成物，使用：

```sh
fvm dart run ccrouter_generator:ccrouter clean demo
```

`clean` 只删除框架标记且位于可写 Package 的 `lib/src/ccrouter_generated/` 下的受管源码输出；
会保留业务源码、手写同名文件、只读依赖、`.dart_tool/build` 缓存和平台构建产物。清理后可
再次执行 `generate` 完整恢复。它不是通用的 `clean` 或 `flutter clean`，不会删除 Package
之外的文件。

查找已生成路由的组件、契约和页面源码位置时使用只读命令：

```sh
fvm dart run ccrouter_generator:ccrouter find order.detail demo
fvm dart run ccrouter_generator:ccrouter find '/order/:orderId' demo
```

`find` 读取指定 Host 的 Pub 运行时依赖闭包内已发布的 Package Index，不启动
build_runner，也不修改生成物。查询是大小写敏感的精确 Route ID 或声明的 Pattern 文本；
`/order/42` 这类带实际参数的 URL 不等同于 `/order/:orderId`，不会由查找命令执行路由解析。
从 Host Package 目录执行时可省略最后的 `demo` 参数。契约与页面分处不同 Package 时会合并
显示源码位置；无匹配、Index 缺失或损坏、依赖 Index 版本混用时返回非零状态。改动源码后先运行 `generate`，
必要时使用 `generate --check` 验证 Index 未过期；`find` 不扫描源文件来猜测未生成的声明。

大型工程可以观察分阶段耗时和缓存命中率，或强制走无缓存参考路径：

```sh
fvm dart run ccrouter_generator:ccrouter generate demo --profile
fvm dart run ccrouter_generator:ccrouter generate demo --no-cache
```

默认缓存只复用内容 SHA-256 完全一致的 metadata 解析结果；损坏、Schema/版本不兼容时自动
丢弃并全量解析。`--no-cache` 与默认增量路径必须生成逐字节一致的受管产物。并发执行会通过
`.dart_tool/ccrouter/v1/generation.lock` 串行化，文件内容未变化时不改写，变化时使用同目录临时
文件提交。workspace 模式仍复用 build_runner 的增量图，但通过 `asset:` build filter 只构建
Host 依赖闭包内、明确可写且声明 `ccrouter_generator` 的 Package，并排除
`lib/**/ccrouter_generated/**` 二次输入。

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
- `<registrar>.component.g.dart`：在 Registrar 同一 library 中生成
  `CCComponentManifest`，可以实例化 private Registrar，业务代码无需导出实现类。
- `<component-id>.routes.g.dart`：组件路由注册索引和后端中立的
  `CCFlutterRouteCatalog`。
- `lib/src/ccrouter_generated/metadata/ccrouter_package.json`：发布级 Package Index，包含 Schema、Package
  身份、内容指纹、直接生成依赖、规范化 metadata 和版本化 Capability Source Catalog；
  Git/path/pub 依赖均从此单文件读取。
- `<package>_ccrouter.g.dart`：Host-only `CCGeneratedPackageBundle`。只 import 本 Package 的
  Manifest/Catalog 与直接 Pub 依赖的 Bundle，不加入组件业务 barrel，也不跨过 Dart 直接依赖
  边界。纯 contracts Package 只生成 JSON Index，不生成 Flutter Runtime Bundle。
- 宿主 `lib/src/ccrouter_generated/host/ccrouter_host.routes.g.dart`：从宿主自己的 Bundle 解析传递
  Package 图，Diamond 依赖去重后生成 Manifest 与 Catalog。新增无路由的 Service 组件也会
  进入 Manifest 列表；普通路由或组件增删不再要求宿主逐项维护初始化列表。
- `lib/src/ccrouter_generated/metadata/cc_catalog.md`：仅在 Package 存在 Capability 时生成，按 Component 和 Capability ID 展示
  Route 的契约声明、页面实现及相关生成物。源码位置统一记录为可移植的
  `package:name/path.dart:line:column`，不把开发机绝对路径写入生成物。组件 Package
  生成局部视图，Host 生成完整依赖闭包的全局视图；Contract-first Route 会同时显示
  contracts Package 的 schema 与实现 Package 的 Page。

`ccrouter_package.json` 是 Capability Source Catalog 的机器事实来源，`cc_catalog.md` 只由
它和同轮 metadata 派生，不维护第二套手工索引。当前只生成已具备静态声明链路的 Route；
Service、Command、Action 和 Event 将在各自生成器落地后接入同一 Catalog Schema，现阶段不会
通过扫描 Registrar 源码猜测注册关系。只读 `ccrouter find` 和未来 DevTools 应消费版本化 Catalog 与
Runtime 快照，而不是解析 Markdown 或直接绑定 Builder 的原始 JSON。

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

组件路由注册索引由统一 `generate` 命令自动生成到
`lib/src/ccrouter_generated/component/<component-id>.routes.g.dart`。组件 Registrar 只需调用
一次生成的 `...GeneratedRoutes.register(registry)`；新增页面不会再修改 Registrar。
索引按源文件和 route ID 稳定排序，并通过页面生成文件中的 package-internal
registration bridge 完成注册，因此组件内部路由仍不会成为公共契约。索引文件禁止手工编辑，
生成器会删除带 CCRouter 生成标记、但已无对应组件的孤立聚合索引；手写同名文件不会被删除。
CI 应使用 `generate --check` 阻止陈旧生成物合入。

Catalog 只包含 Flutter 页面工厂和 `CCNavigationRoute`，不包含 `GoRoute`。GoRouter
宿主使用 `CCGoRouterAssembler` 同源生成 `routes` 与 `bindings`；以后接入 Navigator
1.0、其他 Navigator 2.0 实现或自定义后端时，可以复用同一 Catalog，仅替换
Assembler/Adapter。Shell、嵌套路由、完整 Regex 兼容入口等后端特有结构必须由宿主
提供显式 Override，不能被自动扁平化。

路由契约/注册 bridge 使用 `.route.g.dart`，Flutter 页面构造 bridge 使用
`.route_binding.g.dart`，独立契约使用 `.route.contract.g.dart`，均写入
`lib/src/ccrouter_generated/`；后续 Service 生成器预留 `.service.g.dart` 后缀，本版本尚不
生成 Service 代码。组件与路由的逐源码 JSON 仅存在于
`.dart_tool/build/generated/<package>/lib/src/ccrouter_generated/metadata/`，是可丢弃的 Builder 到 CLI
中间数据，不属于源码或发布物；不再生成逐源码 Markdown。开发者只阅读 Package/Host 的
`cc_catalog.md`，外部工具消费 `ccrouter_package.json` 或 Host `cc_routes.json`。

`@CCRoute` 在独立生成 library 中生成 Package 内部使用的 `_DetailPageRoute` 及参数类型，
页面 library 不需要声明生成 `part`；组件唯一 Route API 提供 IDE 可发现的调用入口。
`@CCRouteContract` 始终生成公开的独立纯契约；schema 与实现位于同一 Package 时聚合为
`package` exposure，位于独立 contracts Package 时聚合为 `external` exposure。契约 Package
必须通过 barrel 的 `show` 显式导出生成 library，消费者必须声明直接 Pub 依赖。框架不再
维护额外的契约模式、可见性枚举或调用方 allowlist。

独立契约只允许 Dart Core 类型和页面通过显式 public package import 引入的 Pure Dart
类型。页面本地类型、private 类型、`package:*/src/`、Flutter、`dart:ui` 和 GoRouter
类型会在生成阶段失败；复杂默认值暂时只支持 primitive 或 enum 常量。

内部路由需要升级时保持原 `routeId` 和参数 wire name，把路由元数据移动到
`@CCRouteContract` schema，再将页面注解替换为 `@CCRouteImplementation`。实现 Package
可以临时 re-export 新契约兼容旧 import；新消费者必须直接依赖 contracts Package。

组件身份和注册实现建议放在 `lib/src/` 的独立文件中：

```text
src/order_component.dart
src/order_component_registrar.dart
```

组件业务 barrel 只导出明确公开的路由契约，不导出 Manifest、Registrar 实现或
descriptor 细节；生成的 `<package>_ccrouter.g.dart` 是唯一 Host 装配入口。

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
`.dart_tool/build/generated/<package>/lib/src/ccrouter_generated/metadata/**/*.component.json` 和
`*.route.json`，不会回退扫描源码树；外部只读 Package 只读取发布的单一 Package Index，
Host 不会写入 path/Git/pub 依赖或 Pub cache。

嵌套依赖通过分层 Bundle 连接：Host 只 import 直接依赖，直接依赖再 import 自己的直接依赖。
同 Package ID 的版本或指纹不一致、外部 Package 缺少/损坏/Schema 不兼容的 Index、嵌套
Runtime Package 的中间 Package 未直接依赖 `ccrouter` 或未发布 forwarding Bundle，都会在生成
阶段失败，不通过非法传递 import 兜底。除框架自身 Package 外，任何直接依赖 `ccrouter` 或
`ccrouter_contracts` 的 Package 都必须发布 Index；没有注解时生成空 Index。该规则不依赖外部
Package 的 `devDependencies` 是否被 Pub 保留，因此不会把“漏生成”误判成“未参与”。

聚合校验组件/路由 ID、路由所有者、
required dependency 缺失、自依赖、依赖环、契约 exposure 与声明形态是否一致、external
实现所有权、静态 Pattern 冲突，以及
所有非 internal 路由是否由公共 barrel 使用 `show` 同时导出 Route 和 Arguments 契约；
不存在的 optional dependency 被忽略，存在时参与与 Runtime 一致的确定性拓扑排序；
它会在 Host 的 `lib/src/ccrouter_generated/metadata/` 下生成机器可读的 `cc_routes.json` 和合并路由定义、
源码位置、生成物位置的人类可读 `cc_catalog.md`。本仓库的扫描根目录是 `demo`，因此输出位于
`demo/lib/src/ccrouter_generated/metadata/`。也可以通过 `--output-dir <directory>` 指定其他
输出目录；校验失败时返回非零退出码。
