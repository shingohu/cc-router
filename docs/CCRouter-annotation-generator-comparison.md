# 注解路由生成器对比与借鉴记录

## 文档状态

- 版本：v0.2
- 状态：已与当前实现对齐；本文只记录外部方案比较和仍可借鉴的工程能力
- 参考对象：[ff_annotation_route](https://github.com/fluttercandies/ff_annotation_route)
- 参考范围：上游 `master` 的 README、示例说明和公开生成模型
- 评估日期：2026-09-19
- 结论：借鉴工程能力，不直接复制其全局路由表和动态扩展模型

本文档记录 `ff_annotation_route` 对 CCRouter 注解生成器、路由生命周期和多后端设计的参考价值，不作为实现完成状态清单。核心路由契约以[路由子系统设计](CCRouter-route-design.md)为准，已完成能力以[路由完成计划](CCRouter-route-completion-plan.md)为准。

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

CCRouter 当前已经有 `RouteEntry` 生命周期、Flutter App 前后台转发和
`CCNavigationAspect` 的 `found`、`arrival`、`lost`、`after` 只读观察阶段；跳转前的
继续、取消和重定向决策由 Global/Route Interceptor 提供。Flutter
业务层另外提供共享同一 Host 台账的 `CCPageLifecycleMixin` 和
`CCPageLifecycleListener`，二者均支持：

- `onPageShow` / `onPageHide`：只表示 `PageRoute` 是否为所属活动 Outlet 的当前主
  Route，不表示像素是否仍然可见；
- `onForeground` / `onBackground`：只在当前页面经历后续 App 前后台转换时触发；
- Foreign `PageRoute` / `PopupRoute` 可以覆盖和恢复 Managed 页面，但不能移除其
  RouteEntry；`OverlayEntry` 等非 Navigator 浮层不改变页面生命周期。

GoRouter 集成通过 `CCGoRouterNavigationObserver.didChangeTop` 上报确认后的当前 Route；
Stateful Shell 和多 Pane Host 通过 Host SPI 上报活动 Outlet 集合。当前底层中立事件模型
已经包括：

```text
AppLifecycleState
CCRouteVisibilityEvent
```

当前不伪造 Window 或 Display 生命周期。逻辑导航状态通过稳定的 `hostId`、Host
Registry 和活动 Outlet 集合隔离；未来原生 Window 事件由独立平台桥接提供。

Mixin 和 Listener 都只是 Flutter 业务层的便利接入，不能替代 Runtime 的 RouteEntry、
Adapter 事件或最终移除埋点。页面创建和销毁继续使用 Flutter `initState` / `dispose`；
页面最终退出统计使用 Navigation Aspect 或 RouteEntry removed/disposed 事件，不增加
含义不可靠的 `onPageDispose`。

### 2.2 StatefulShell 和嵌套路由

其示例展示了：

- 多 Navigator；
- Tab 内嵌套 Router；
- `ChildBackButtonDispatcher`；
- `StatefulShellRoute` 状态保持；
- Shell 分支间的返回处理。

CCRouter 已有 `CCRoutePlacement`、`shellId`、`navigatorOutlet`、
`CCGoRouterShellBinding` 和 Stateful Shell 能力声明。系统返回、Tab 切换、Shell 内 Pop、
Foreign Popup 隔离和多 Outlet Route Scope 已有专项回归；后续增加真实业务 Demo 只用于
改善集成体验，不再是 Runtime 正确性的阻塞项。

### 2.3 复杂 Query 参数

其 `FFConvert.convert` 支持将 Web Query 转换为集合或自定义 Model。这个方向对筛选条件、分页参数和分享链接有实际价值。

CCRouter 当前支持 `String`、`int`、`double`、`bool`、enum、可空值、`List<T>`、
`Set<T>`、`Extra`，并已支持显式 Query Codec：

```dart
CCRouteQueryCodec<OrderFilter>
```

Codec 通过参数注解显式声明，必须可测试、可生成，且其类型和构造器在生成期校验；不会
引入运行时动态的全局转换器。

### 2.4 Monorepo 生成工具体验

其生成器支持多 Package 扫描、排除包、分组和排序。CCRouter 已经有组件级 `ccrouter_generated/**/*.component.json`、路由级 `ccrouter_generated/**/*.route.json`、workspace 聚合校验和应用级 `cc_routes.json` / `cc_routes.md`，并且额外校验组件所有权、契约 exposure 和实现边界。

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

如果未来有真实需求，应优先考虑结构化元数据。以下只是 Proposal 示例，当前不存在
`CCRouteMetadata` API：

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
- 手写消费者 allowlist 难以成为真实的编译期边界；
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
| 路由可见性 | 主要依赖生成文件和包扫描 | 契约形态、Package 依赖、barrel 校验 |
| 路由生命周期 | Widget Mixin + Observer | Runtime 状态源 + 可选 Mixin/Listener + Adapter `didChangeTop` |
| App 前后台 | 有生命周期回调 | 已有 Flutter App 生命周期回调和多 Host 隔离；原生 Window 生命周期待平台桥接 |
| 全局/路由拦截器 | 支持 | 已支持，并统一经过 CCRouter |
| GoRouter | 支持 | 独立 GoRouter Adapter |
| Stateful Shell | 有示例 | 已有 Shell Binding、分支观察和专项回归 |
| 复杂 Query | 动态转换器 | 标量、集合和显式 `CCRouteQueryCodec<T>` |
| 全局 Routes 表 | 支持 | 不采用 |
| 任意代码注入 | 支持 | 不采用 |
| 应用路由文档 | 支持 | `cc_routes.json` / `cc_routes.md` |

## 5. 剩余可借鉴项

以下是工程体验增强，不代表当前路由闭环缺失：

1. 为 CLI 增加扫描目录、排除 Package、稳定分组、缓存和 Route Scaffold 支持。
2. 为应用路由文档增加按组件或业务域组织的可选视图。
3. 增加更多 GoRouter、Navigator 2.0、多 Host 和 Stateful Shell 集成示例；原生多
   Window 示例等待 Flutter 平台能力稳定后补充。
4. 优化生成器和 Workspace 聚合性能，但保持唯一生成语义。
5. 提供 IDE 或 CI 友好的只读路由目录查询接口。
6. 如确有产品需求，再设计独立于稳定 `routeId` 的结构化产品埋点名称；该能力目前只是
   Proposal，不属于已公开 API。

## 6. 结论

`ff_annotation_route` 最值得借鉴的是生命周期事件设计、复杂 Query Codec、StatefulShell/嵌套路由示例和 Monorepo 工具体验。

不建议引入全局 Routes 表、任意代码注入、动态全局转换器或依赖扩展方法触发拦截器。

CCRouter 应保持组件所有权、编译期可见性、类型安全 Intent、RouteEntry 生命周期和统一导航入口这些核心边界，在此基础上吸收成熟的工程体验。
