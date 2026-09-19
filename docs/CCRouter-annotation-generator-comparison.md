# 注解路由生成器对比与借鉴记录

## 文档状态

- 版本：v0.1 Draft
- 参考对象：[ff_annotation_route](https://github.com/fluttercandies/ff_annotation_route)
- 参考范围：上游 `master` 的 README、示例说明和公开生成模型
- 评估日期：2026-09-19
- 结论：借鉴工程能力，不直接复制其全局路由表和动态扩展模型

本文档记录 `ff_annotation_route` 对 CCRouter 注解生成器、路由生命周期和多后端设计的参考价值。核心路由契约仍以 [路由子系统设计](CCRouter-route-design.md) 为准。

## 1. 总体判断

`ff_annotation_route` 更偏向“注解扫描、生成全局路由映射和适配多种导航框架”；CCRouter 的目标是“组件拥有路由契约、生成类型安全 API，并由 Runtime 统一处理生命周期、可见性、拦截和诊断”。

两者的边界不同，因此不应直接引入全局 `Routes` 类、任意代码注入或动态全局转换器。可以吸收它在生命周期事件、Stateful Shell 示例、复杂 Query 参数和 Monorepo 工具体验方面的做法。

## 2. 值得借鉴的能力

### 2.1 页面和弹窗生命周期

`ff_annotation_route` 提供以下生命周期事件：

```text
onPageShow
onPageHide
onForeground
onBackground
onRouteShow
onRouteHide
```

这些事件覆盖页面曝光、页面被覆盖、App 前后台、Dialog/BottomSheet 显示隐藏等场景。

CCRouter 当前已经有 `RouteEntry` 生命周期和 `CCNavigationAspect` 的 `before`、`found`、`arrival`、`lost`、`after` 阶段，但还需要补充：

- App/Window 前后台事件；
- Route 显示、隐藏和焦点变化；
- Shell 分支切换导致的页面失焦；
- 多 Window 的独立生命周期。

建议增加 Adapter 上报的中立事件模型，例如：

```text
CCHostLifecycleEvent
CCRouteVisibilityEvent
CCWindowVisibilityEvent
```

不建议把 Widget Mixin 作为 Core 生命周期模型。Mixin 可以作为 Flutter 层的便利接入，但不能替代 Runtime 的 RouteEntry 和 Adapter 事件。

### 2.2 StatefulShell 和嵌套路由

其示例展示了：

- 多 Navigator；
- Tab 内嵌套 Router；
- `ChildBackButtonDispatcher`；
- `StatefulShellRoute` 状态保持；
- Shell 分支间的返回处理。

CCRouter 已有 `CCRoutePlacement`、`shellId`、`navigatorOutlet`、`CCGoRouterShellBinding` 和 Stateful Shell 能力声明。后续应重点补充真实 Demo 和回归测试，验证系统返回、Tab 切换、Shell 内 Pop 以及 Foreign Popup 不会错误关闭其他 Outlet 的 Route Scope。

### 2.3 复杂 Query 参数

其 `FFConvert.convert` 支持将 Web Query 转换为集合或自定义 Model。这个方向对筛选条件、分页参数和分享链接有实际价值。

CCRouter 当前主要支持 `String`、`int`、`double`、`bool`、enum、可空值和 `Extra`。后续可以增加显式 Query Codec：

```dart
CCRouteQueryCodec<OrderFilter>
```

或在参数注解中声明受约束的 Codec。Codec 必须是显式、可测试、可生成的，不能引入一个运行时动态的全局转换器。

### 2.4 Monorepo 生成工具体验

其生成器支持多 Package 扫描、排除包、分组和排序。CCRouter 已经有组件级 `ccrouter_generated/metadata/**/*.component.json`、路由级 `ccrouter_generated/metadata/**/*.route.json`、workspace 聚合校验和应用级 `cc_routes.json` / `cc_routes.md`，并且额外校验组件所有权、`visibleTo` 和依赖边界。

已参考其“生成统一 Route Settings 列表、宿主批量转换”的思路，但没有照搬动态参数
Map 或组件直接依赖 GoRouter。CCRouter 生成 `CCFlutterRouteCatalog`，由宿主生成器跨组件
聚合，再交给具体后端 Assembler。当前 `CCGoRouterAssembler` 同源产生 `GoRoute` 与
Binding；Navigator 1.0 或其他 Navigator 2.0 后端可以复用 Catalog。Shell、嵌套 Outlet
和完整 Regex 入口使用显式 Override，避免根据 path 前缀猜测结构。

后续可以改进 CLI：

- 指定扫描目录；
- 排除 Package；
- 按组件或业务域分组；
- 稳定排序；
- 可选输出目录；
- 增量或缓存扫描。
- 提供可选的 Route Scaffold 子命令，创建页面模板并写入正确的生成 `part` 路径，随后
  调用标准 `build_runner` 和组件路由索引生成流程。它不作为另一套生成语义，也不自动
  修改公共 barrel 或 GoRouter 路由树，以免把开发便利性变成隐式 API 暴露或宿主侵入。

### 2.5 路由元数据扩展

其 `exts` 可以表达分组、排序和其他文档字段。CCRouter 可以吸收这个需求，但不应直接增加 `Map<String, dynamic>` 作为核心契约。

优先考虑结构化元数据，例如：

```dart
CCRouteMetadata(
  group: 'orders',
  order: 10,
  tags: {'business': 'order'},
)
```

未被 Runtime 使用的元数据也可以只保留在生成器和文档层。

## 3. 不直接采用的做法

### 3.1 全局 `Routes` 常量类

全局路由常量对小项目较方便，但会削弱 CCRouter 的组件隔离：

- 所有路由都会出现在一个全局符号表中；
- 组件内部路由更容易被外部发现；
- `visibleTo` 难以成为真实的编译期边界；
- 组件依赖会变成隐式关系；
- 大型生成文件会增加冲突和增量构建成本。

CCRouter 应继续按组件生成 `Route`、`Arguments` 和 Registrar 契约。

### 3.2 `codes` 任意代码注入

将 Dart 代码以字符串放进注解会导致：

- 生成器无法理解和校验代码；
- 重构时容易产生隐式错误；
- 业务依赖可能绕过组件边界；
- 代码审查和静态分析变得困难。

CCRouter 应继续使用结构化常量、显式 Codec 和受控扩展点。

### 3.3 Fast Mode / Non-Fast Mode 双语义

快速模式和完整模式可以改善大型项目的生成速度，但也会产生两套导入推断和构造分析规则，导致本地与 CI 结果不一致。

CCRouter 更适合保持单一生成语义，后续通过 Analyzer 缓存、文件级增量缓存和 Package 图缓存优化性能。

### 3.4 依赖扩展方法触发拦截器

如果拦截器依赖 `pushNamedWithInterceptor` 之类的扩展方法，业务仍可以绕过扩展直接调用原始 Navigator，导致策略失效。

CCRouter 应继续要求业务统一通过 `CCRouter.navigator`，让拦截、Aspect、诊断和返回值都经过同一条管线。

## 4. 能力对比

| 能力 | `ff_annotation_route` | CCRouter 当前方向 |
| --- | --- | --- |
| 注解参数辅助 | 支持 | 生成强类型 Arguments/Intent |
| 多 Path / URI | 支持部分 | 多 Pattern、主 Pattern 和别名分离 |
| 路由可见性 | 主要依赖生成文件和包扫描 | Component Owner、`visibleTo`、barrel 校验 |
| 路由生命周期 | Widget Mixin + Observer | Runtime RouteEntry + Aspect + Adapter 事件 |
| App 前后台 | 有生命周期回调 | 需要补 Host/Window Lifecycle Bridge |
| 全局/路由拦截器 | 支持 | 已支持，并统一经过 CCRouter |
| GoRouter | 支持 | 独立 GoRouter Adapter |
| Stateful Shell | 有示例 | 已有 Shell Binding，需要加强回归 |
| 复杂 Query | 动态转换器 | 当前标量 Codec，后续增加显式 Codec |
| 全局 Routes 表 | 支持 | 不采用 |
| 任意代码注入 | 支持 | 不采用 |
| 应用路由文档 | 支持 | `cc_routes.json` / `cc_routes.md` |

## 5. 后续优先级

### P0

1. 增加 Host/Window 前后台生命周期事件。
2. 增加 Route 显示、隐藏和焦点变化事件。
3. 完善 StatefulShell、嵌套路由和多 Outlet 回归测试。
4. 将产品埋点名称与稳定 `routeId` 分离，例如增加结构化 `CCRouteTelemetry`。

### P1

1. 支持集合 Query 和自定义类型 Query Codec。
2. 增强复杂构造器、继承参数和类型导入分析。
3. 增加生成器的排除包、分组、排序和缓存能力。
4. 路由文档按组件、业务分组、Shell 和 Outlet 输出不同视图。

### P2

1. 生成器性能优化，但保持唯一的生成语义。
2. 提供 IDE 或 CI 友好的路由目录查询接口。
3. 增加更多 GoRouter、Navigator 2.0 和多 Window 示例。

## 6. 结论

`ff_annotation_route` 最值得借鉴的是生命周期事件设计、复杂 Query Codec、StatefulShell/嵌套路由示例和 Monorepo 工具体验。

不建议引入全局 Routes 表、任意代码注入、动态全局转换器或依赖扩展方法触发拦截器。

CCRouter 应保持组件所有权、编译期可见性、类型安全 Intent、RouteEntry 生命周期和统一导航入口这些核心边界，在此基础上吸收成熟的工程体验。
