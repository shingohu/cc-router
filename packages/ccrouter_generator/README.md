# CCRouter 路由生成器

组件的开发工具，不属于运行时依赖。页面库使用业务门面（非前缀导入）：

```dart
// lib/src/detail_page.dart
import 'package:ccrouter/ccrouter.dart';
part 'ccrouter_generated/detail_page.route.g.dart';

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

part 'ccrouter_generated/order_detail_page.route.g.dart';

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
part 'ccrouter_generated/order_component_registrar.component.g.dart';
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
export 'src/ccrouter_generated/detail_page.route.contract.g.dart'
    show DetailPageRoute, DetailPageRouteArguments;
```

组件的 `dev_dependencies` 添加 `ccrouter_generator`，workspace 根目录添加
`build_runner`。本仓库在根目录执行：

```sh
fvm flutter pub get
fvm dart run build_runner build --workspace
fvm dart run ccrouter_generator:ccrouter_generator demo \
  --generate-component-registrars
```

非 workspace 包在自己的目录执行 `dart run build_runner build`。

生成结果：

- `@CCRoute` 的 `<page>.route.g.dart`：页面同库的私有 Arguments、Intent、Definition、
  Codec，以及注册、描述和构造 glue。
- `@CCRouteContract` 的 `<schema>.route.contract.g.dart`：生成公开 Pure Dart Arguments、
  Intent、Definition 和私有 Codec；不包含页面、Registrar、Flutter 或路由后端类型。
- `@CCRouteImplementation` 的 `<page>.route.g.dart`：只生成 owner 注册、描述和页面构造
  glue，不重复生成业务契约。
- 公开 `DetailRoute.intent(...)` 只构造 `CCRouteIntent<String>`，仍通过
  `CCRouter.navigator.push<String>(...)` 导航。
- `<registrar>.component.g.dart`：在 Registrar 同一 library 中生成
  `CCComponentManifest`，可以实例化 private Registrar，业务代码无需导出实现类。
- `<component-id>.routes.g.dart`：组件路由注册索引和后端中立的
  `CCFlutterRouteCatalog`。
- `<package>_ccrouter.g.dart`：只向应用组合根暴露 Manifest 与 Catalog 的窄 Host
  integration library，不加入组件业务 barrel。
- 宿主 `lib/ccrouter_generated/ccrouter_host.routes.g.dart`：合并所有扫描到的组件
  Manifest 与 Catalog。新增无路由的 Service 组件也会进入 Manifest 列表；普通路由或
  组件增删不再要求宿主逐项维护初始化列表。

组件路由注册索引由 `--generate-component-registrars` 自动生成到
`lib/src/ccrouter_generated/<component-id>.routes.g.dart`。组件 Registrar 只需调用
一次生成的 `...GeneratedRoutes.register(registry)`；新增页面不会再修改 Registrar。
索引按源文件和 route ID 稳定排序，并通过页面生成文件中的 package-internal
registration bridge 完成注册，因此组件内部路由仍不会成为公共契约。索引文件禁止手工编辑，
CI 应在生成后检查工作区无未提交差异。

Catalog 只包含 Flutter 页面工厂和 `CCNavigationRoute`，不包含 `GoRoute`。GoRouter
宿主使用 `CCGoRouterAssembler` 同源生成 `routes` 与 `bindings`；以后接入 Navigator
1.0、其他 Navigator 2.0 实现或自定义后端时，可以复用同一 Catalog，仅替换
Assembler/Adapter。Shell、嵌套路由、完整 Regex 兼容入口等后端特有结构必须由宿主
提供显式 Override，不能被自动扁平化。

页面 glue 使用 `.route.g.dart`，独立契约使用 `.route.contract.g.dart`，均写入
`lib/src/ccrouter_generated/`；后续 Service 生成器预留 `.service.g.dart` 后缀，
本版本尚不生成 Service 代码。组件元数据使用 `.component.json` 和 `.component.md`，
路由元数据使用 `.route.json` 和 `.route.md`，统一写入包根目录的
`ccrouter_generated/metadata/`，并保留输入文件相对 `lib/` 的目录层级。

`@CCRoute` 始终在页面 library 中生成 `_DetailPageRoute` 及私有参数类型。
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
- Query 显式注解，可指定 URI key；支持 String、int、double、bool、enum
  及可空值、构造器默认值。bool 只接受 `true/false`，double 拒绝非有限值。
- 标量 Query 重复、缺失必需值、非法类型会抛出 `CCRouteParameterError`；
  消息包含路由和参数名称，不包含原始参数内容。
- 最多一个显式 Extra，保持对象身份；启用 Deep Link 时不能要求必需 Extra。
- 可选且未注解的 Flutter `key` 不进入契约；其他未映射参数构建失败。
- 单地址路由使用 `pattern`，生成器自动补齐 primary；多地址路由使用 `patterns`。
  两者不能同时设置。多值只有一个可逆 Pattern 时自动补齐 primary，存在多个可逆
  Pattern 时必须显式指定一个 primary。别名必须捕获相同的 Path 参数；支持 Path、
  URI、Regex Pattern 以及 Presentation、Placement、拦截器 ID 元数据。
- 组件生成物不生成 GoRoute、不选择路由后端；宿主生成物只聚合中立 Catalog。

集合 Query、自定义字段 Codec 以及具名/Factory 页面构造器留到后续阶段。聚合校验同时
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

第二条命令聚合全部 `ccrouter_generated/metadata/**/*.component.json` 和
`ccrouter_generated/metadata/**/*.route.json`，校验组件/路由 ID、路由所有者、
契约 exposure 与声明形态是否一致、external 实现所有权、静态 Pattern 冲突，以及
所有非 internal 路由是否由公共 barrel 使用 `show` 同时导出 Route 和 Arguments 契约；
它会在扫描根目录的 `ccrouter_generated/metadata/` 下生成 `cc_routes.json` 和
`cc_routes.md`。本仓库的扫描根目录是 `demo`，因此输出位于
`demo/ccrouter_generated/metadata/`。也可以通过 `--output-dir <directory>` 指定其他
输出目录；校验失败时返回非零退出码。
