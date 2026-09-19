# CCRouter 独立纯契约文件设计

## 背景

当前生成器把 `Arguments`、`Intent`、`Definition`、Codec 和页面 `build` 工厂
放在同一个 `.route.g.dart` library part 中。这样可以访问私有页面构造器，
但组件消费者为了获得类型安全的 Intent，仍然需要导入页面 library。公共 barrel
虽然可以用 `show` 裁剪页面符号，但它不是编译层面的纯契约边界。

纯契约文件的目标是让跨组件调用只依赖稳定的路由契约，不依赖目标页面实现、
Flutter Widget 或页面所在 library。它不改变 Runtime 的注册所有权，也不把页面
构造器暴露给业务代码。

## 目标与非目标

目标：

- 为每个 `exported` 路由生成独立的 Pure Dart 契约 library。
- 契约包含稳定 Route ID、Arguments、Intent、Definition 和 Codec。
- 契约只依赖 `ccrouter_contracts`，不依赖 Flutter、页面类或 GoRouter。
- 组件 Registrar 继续由 owner 组件控制，业务代码不能通过契约直接注册路由。
- 组件内部路由仍只生成 library-private part，不生成可导出的纯契约。
- 保持现有 `CCRouter.navigator` 和 `Future<R?>` 结果类型不变。

非目标：

- 不把页面构造器或 `Route.build` 放入纯契约 library。
- 不生成 GoRoute、Navigator、Widget 或 Adapter 对象。
- 不允许纯契约绕过 `visibleTo`、拦截器或 Runtime 生命周期。

## 文件布局

组件源文件仍保留页面专用 part：

```text
lib/
├── order_route_contracts.dart
├── src/order_detail_page.dart
├── src/ccrouter_generated/order_detail_page.route.g.dart
└── src/ccrouter_generated/order_detail_page.route.contract.g.dart
```

`order_route_contracts.dart` 是组件作者维护的公共 barrel，只导出
`*.route.contract.g.dart` 中的 exported 契约，并使用 `show` 明确列出
Route 和 Arguments 类型。页面专用 `.g.dart` 只保留页面构造和 owner 注册 glue，
不从公共 barrel 导出。

## API 归属

| 声明 | 纯契约 | 页面 glue | 原因 |
| --- | --- | --- | --- |
| `XxxRouteArguments` | 是 | 否 | 跨组件参数类型 |
| `XxxRoute.intent` | 是 | 否 | 业务导航入口 |
| `XxxRoute.definition` | 是 | 否 | Runtime 注册所需的中立定义 |
| `XxxRoute.register` | 否 | 是 | 仅 owner Registrar 调用 |
| `XxxRoute.build` | 否 | 是 | 需要访问页面构造器 |
| Codec 实现 | 是 | 否 | 只依赖纯参数类型和 contracts |
| 页面构造器 | 否 | 否 | 页面实现属于组件内部 |

纯契约中的导航入口只创建 `CCRouteIntent<R>`；实际调用仍必须经过
`CCRouter.navigator`。`register` 不进入业务导出的契约，避免消费者获得组件
注册能力。

## 生成与兼容策略

1. 首个实现阶段保留当前 `.route.g.dart` 输出，新增纯契约文件和显式 opt-in
   barrel，避免一次生成升级破坏已有组件。
2. 组件启用纯契约后，生成器检查 page library 是否导入契约文件，并检查 owner
   glue 与契约使用同一个 Route ID、Codec 和 Definition。
3. 纯契约稳定后，下一主版本再把默认输出切换为“纯契约 + 页面 glue”，并移除
   page part 中重复的业务 API。
4. `CCRouteWorkspaceValidator` 检查 exported 路由的纯契约 barrel 是否只导出
   `Route` 与 `Arguments`，不导出 glue 或页面类。

这种分阶段策略避免同一个 Route ID 出现两套不兼容的 Definition，也保留现有
demo 和组件的增量迁移路径。

## 验证要求

- Pure Dart 契约包可以在没有 Flutter SDK 的环境下 `dart analyze` 和 `dart test`。
- 导入纯契约的消费者不能解析页面 Widget 或 `BuildContext`。
- Intent 的 `routeId`、结果泛型、Codec 编解码和主 Pattern 与页面 glue 完全一致。
- 内部路由不生成纯契约，跨组件 `visibleTo` 和依赖检查语义不变。
- barrel 缺少 `show`、导出 glue 或契约与页面 Route ID 不一致时，构建失败。
- 生成文件布局迁移期间必须保持现有生成测试和 Runtime 回归通过。
