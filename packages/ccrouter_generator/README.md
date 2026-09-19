# CCRouter 路由生成器

组件的开发工具，不属于运行时依赖。页面库使用业务门面（非前缀导入）：

```dart
import 'package:ccrouter/ccrouter.dart';
part 'detail_page.ccroute.g.dart';

const orderComponent = CCComponentDescriptor(
  id: 'order',
  version: '1.0.0',
);

@CCComponent(orderComponent)
final class OrderComponentRegistrar implements CCComponentRegistrar {
  // Register generated routes through the restricted CCRegistry.
}

@CCRoute<String>(
  component: orderComponent,
  id: 'order.detail',
  pattern: CCPathPattern('/orders/:orderId'),
  visibility: CCRouteVisibility.exported,
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

组件的 `dev_dependencies` 添加 `ccrouter_generator`，workspace 根目录添加
`build_runner`。本仓库在根目录执行：

```sh
fvm flutter pub get
fvm dart run build_runner build --workspace
fvm dart run ccrouter_generator:ccrouter_generator demo
```

非 workspace 包在自己的目录执行 `dart run build_runner build`。

生成结果：

- `DetailPageRouteArguments`：不可变字段的参数对象。
- `DetailPageRoute.intent(...)`：只构造 `CCRouteIntent<String>`，通过
  `CCRouter.navigator.push<String>(...)` 导航。
- `DetailPageRoute.definition`：中立路由表定义和私有 Codec。
- `DetailPageRoute.register(registry)`：组件 Registrar 的注册入口。
- `DetailPageRoute.build(arguments)`：将解码参数注入页面构造器；Host 自己绑定后端。

默认 `component` 可见性在同一 library 中生成 `_DetailPageRoute` 及私有参数类型。
只有 `exported` 生成公开类型，组件仍需通过 barrel 的 `show` 显式导出。
私有页面仍可以通过 `part` 使用生成的内部契约。

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
- 不生成 GoRoute，不选择路由后端，不替宿主维护 Navigator。

集合 Query、自定义字段 Codec 以及具名/Factory 页面构造器、分离的纯契约文件留到后续
阶段。聚合校验同时检查同层、同具体度且能够静态证明的
Path/URI/Regex Pattern 冲突；约束表达式仅在可证明互斥时排除重叠，复杂正则歧义仍由
Runtime 注册兜底。

## 回归

构建工具测试在 Dart VM 下运行，全部测试仍归属于 `ccrouter_test` 包：

```sh
fvm dart test packages/ccrouter_test/generator_test
fvm flutter test packages/ccrouter_test/test demo/test
fvm flutter analyze packages demo
```

生成样例和测试 Fixture 的 `.ccroute.g.dart` 纳入版本管理，方便直接打开 demo；
修改声明后必须重新生成并做静态检查。

第二条命令聚合全部 `.ccroute.json`，校验组件/路由 ID、路由所有者、
`visibleTo` 目标、消费组件对路由所有者的显式依赖、静态 Pattern 冲突，以及
`exported` 路由是否由公共 barrel 使用 `show` 同时导出 Route 和 Arguments 契约；
它会在扫描根目录的 `docs/generated/` 下生成 `cc_routes.json` 和
`cc_routes.md`。本仓库的扫描根目录是 `demo`，因此输出位于
`demo/docs/generated/`。也可以通过 `--output-dir <directory>` 指定其他输出目录；校验失败时返回非零退出码。
