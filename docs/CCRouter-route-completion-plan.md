# CCRouter 路由完成计划

## 文档状态

- 版本：v0.2
- 状态：路由 1.x 功能闭环与 Observer 有界异步分发已完成；新增候选能力统一进入 2.0 规划
- 职责：五份路由文档中的唯一实施状态清单，不替代路由语义、契约或混合路由设计

本文中的勾选项表示当前仓库已实现并具有对应回归覆盖。其他设计文档不再重复维护任务
完成状态；若描述与本清单冲突，应先核对当前代码和测试，再同步修正文档。

## 1. 范围

本文是路由子系统从当前实现到可冻结 API 的执行清单。范围包括路由 Contract、Runtime、
Flutter Facade、GoRouter Adapter、路由 Generator、Demo 路由接入、测试和路由设计文档。

以下内容不在本轮范围内：

- CI、发布流水线和远端自动化；
- Service、Command、Query、Event 等非路由能力扩展；
- 接管第三方 Overlay 或未提供观察信号的独立导航系统；
- 为不具备原子能力的后端伪造一致性保证。

## 2. 完成原则

1. 经过 CCRouter 的路由必须保持 RouteEntry、Scope、返回值和诊断一致。
2. Foreign Route 尽量观察；无法关联时隔离，禁止猜测修改 Managed Route。
3. Interceptor 只负责决策，Aspect 只负责观察，Lifecycle 只描述对应维度的状态。
4. 平台和后端差异由 Host/Adapter SPI 承担，业务 API 不暴露 Flutter Route 对象。
5. 每项先增加失败或边界测试，再实现并执行专项与全量回归。
6. 所有缓存、Listener、Timer、Continuation 和 Route 引用必须有明确释放路径。

## 3. 实施阶段

### P0-1 导航决策管线

- [x] 移除 `CCNavigationAspect.before` 的决策能力，Aspect 变为纯观察接口；
- [x] 保证 Global Interceptor 后接 Route Interceptor 的唯一确定顺序；
- [x] 修复 `CCNavigationDefer` 恢复组合导航时退化为普通 `navigate` 的问题；
- [x] 为 Interceptor 增加真实 Deadline/Timeout 和专用错误；
- [x] 校验路由级 Interceptor 的组件所有权；
- [x] 为并发拒绝和共享请求补齐独立 Navigation ID、Lifecycle 与 Aspect 终态；
- [x] 禁止对任意 Extra 对象做隐式去重，携带 Extra 的请求保持独立执行；
- [x] 统一 Interceptor、Policy、Guard、Aspect 和 Listener 的 Zone 重入保护；
- [x] 覆盖 Redirect、Cancel、Defer、超时、异常、Session/Runtime 清理和内存释放。

### P0-2 Pop 决策

- [x] 增加 Adapter 中立的 `CCPopGuard` 决策契约；
- [x] 统一业务 Pop、系统返回、手势返回和预测返回的 Guard 管线；
- [x] Guard 拒绝或交互手势取消时不得关闭 RouteEntry 和 Scope；
- [x] Foreign、Opaque 和 LocalHistoryEntry 消费返回时不得触发 Managed Guard 销毁语义。

### P0-3 失败与兜底

- [x] 增加默认拒绝的 Host Deep Link Scheme/Host/Port 白名单，并显式控制相对 Path；
- [x] 统一路由未找到、参数非法、Deep Link 拒绝、组件不可用和 Adapter 失败事件；
- [x] 增加 Host 级只读 Failure Policy，支持明确的兜底或重定向；
- [x] 兜底链保留 Origin、Source、Navigation ID，并限制循环；
- [x] 参数和 Extra 不进入不受控日志、Aspect 或持久化数据。

### P0-4 Backend Identity 与可见性

- [x] 用已确认的 Backend Entry identity 驱动 Runtime RouteEntry 显示状态；
- [x] 消除 Runtime commit 即假定真实到达的时序；
- [x] 关联 GoRouter root、Shell Observer，并通过 RouterDelegate 自动观察 StatefulShell 分支；
- [x] 覆盖 Foreign PageRoute、PopupRoute、独立 Navigator、事件重复和序列断层；
- [x] StatefulShell 切换只 Hide/Show，不销毁非活动分支 Scope。
- [x] 拆分 Go、Reset 与 Open-Go 生命周期：Go/Open-Go 按真实 backend diff 清理，Reset 才执行 Host 级重置；Observer 不完整时只降级到目标 Host/Outlet 分区。
- [x] Replace、Pop 和 Pop Guard 使用精确 Host/Outlet；Root Modal 覆盖 Shell branch 时按 `parentNavigatorKey` 选择 Root。
- [x] 移除 Managed Pop 缺少 Entry identity 时删除 Runtime 顶部的兼容猜测。

GoRouter 的 Observer 必须在应用构建 Router 时由 Host/Assembler 安装，Flutter 不支持在 Router
创建后安全注入 Observer。Adapter 对已安装的 Observer 自动完成 Backend identity 关联；如果
Observer 只覆盖部分 Managed Outlet，Adapter 会关闭延迟 Arrival，避免未覆盖页面永久停留在
`pushed`。StatefulShell 分支切换不依赖 Navigator top 变化，由 RouterDelegate 单独上报
`outletActivated`。

### P1-1 Host 与自适应布局

- [x] 增加 Runtime 多 Host Registry 和动态 Host Resolver；
- [x] 隔离 Host、Shell 和 Outlet 的栈、返回与诊断状态；
- [x] 将 Adaptive Layout 契约接入 Host/Outlet 调度；
- [x] 支持单 Pane、双 Pane 和折叠状态变化，并明确 Host 卸载时不隐式迁移 Live Route；
- [ ] 2.0 候选：接入原生 macOS、Windows、iPadOS Window/Flutter View 的创建、激活、关闭
  和恢复生命周期。

Host 卸载会关闭该 Host 的 RouteEntry 和 Scope，并安全完成 pending result；其他 Host 不受影响。
Live Route 的跨 Host 迁移存在 Widget、Scope、返回值和后端状态所有权问题，因此不做隐式迁移。
注销当前 active Host 必须原子指定已注册的 `replacementActiveHostId`，不能依赖注册顺序隐式
选取接替 Host。
未来如需迁移，只能通过显式新导航或单独设计的状态恢复流程重建。

### P1-2 可观测性

- [x] Aspect 事件补齐安全的 Host、Outlet、Owner、Referrer 和 Redirect Chain；
- [x] 区分首次 Arrival、恢复显示、Hide、Removed 和 Disposed；
- [x] 拆分 Resolve、Intercept、Dispatch、Arrival、Stay 和 Total 耗时；
- [x] 提供 Telemetry Context SPI，不暴露原始账号或任意业务对象；
- [x] 明确 PV 由 Arrival/Show 产生，UV 由外部分析层结合匿名访客身份聚合。
- [x] 拆分 operational address 与 retained diagnostic snapshot，所有业务历史使用不含参数值的
  `CCRouteAddressSummary`；
- [x] 将纯观察回调改为有界 FIFO 异步分发，并覆盖顺序、取消订阅、overflow、终态不可丢失和 Runtime dispose 清理语义。

Runtime 同步写入有界诊断历史，但在下一轮 event loop 才通知 Aspect 与普通 Listener。观察
队列容量复用 `navigationDiagnosticCapacity` 且最少为 64 个事件批次；overflow 优先丢弃
最旧非终态批次，若队列只含终态则丢弃新到达的非终态。新终态进入全终态满队列时，通过
显式 backpressure 交付最旧终态，因此 `completed/failed`、Failure、RouteEntry
`removed/disposed`、Aspect `lost/after/removed/disposed` 和 Backend
`pop/remove/hostDetached` 不会静默丢失。取消订阅会跳过尚未分发的回调；Runtime dispose
会取消 Timer、flush 队列并清除 Listener 与闭包引用。

### P1-3 路由状态恢复（暂缓，仅保留设计与需求观测）

- [x] 增加 `CCRouteRestorationOpportunityEvent`，记录平台重建或异常 Session 的恢复机会；
- [x] 事件固定标记 `unsupported`，不伪装已经执行恢复；
- [x] 只记录 Route ID、Host/Outlet 数量、版本指纹和匿名 Telemetry Context；
- [x] 禁止记录完整 URI、参数、账号、Arguments、Extra 或任意业务对象；
- [ ] 2.0 候选：定义版本化、Adapter 中立的 Route Restoration Snapshot（数据证明有需求后
  再启动）；
- [ ] 2.0 候选：实现重新解析、安全校验、契约升级和部分恢复（非 1.x 阻塞项）。

完整状态恢复暂不进入 1.x 生产 API。2.0 阶段只有在恢复机会率、受影响 Route 分布、
多窗口恢复占比等 Telemetry 数据证明收益后才启动实施；届时必须采用路由显式 opt-in，
且不能持久化 Widget、BuildContext、Flutter Route、Scope、Extra 或返回 Completer。

### P2 生成器与最终收口

- [x] 隔离业务 barrel 与 Host/Adapter SPI，并以 API surface 快照测试锁定 hide/show 集合；
- [x] 页面生成 glue 只返回 Route Definition，由 Host catalog 负责转换 Adapter-facing Route；
- [x] 无 Failure Policy 时仍记录 request 创建前失败，并独立记录实际 Adapter capability 回退；
- [x] Workspace 聚合前移校验 required 缺失、自依赖和依赖环，并按 Runtime 语义确定性排序；
- [x] 单一 `ccrouter generate` 编排 Package 生成与 Host 聚合，并提供只读陈旧产物门禁；
- [x] 从 Host 的 Pub 运行时依赖闭包精确发现 workspace/path/Git/pub 与传递 Package，排除无关
  workspace Package 和 dev dependency；
- [x] 生成发布级 Package Index 与 direct-dependency Bundle，支持 Diamond 去重、外部只读校验、
  内容指纹、原子单文件提交、并发锁、缓存失效全量回退及 `--no-cache/--profile`；
- [x] 支持显式集合 Query 和自定义 Query Codec；
- [x] 完善继承参数、复杂构造器和导入分析；
- [x] 路由文档增加组件、Shell、Outlet、来源和“当前不支持恢复”的能力视图；
- [x] 执行最终 API 暴露、重复字段和半实现能力扫描；
- [x] 执行 Listener、Timer、Pending Navigation、Route/Backend Entry 和 Scope 泄漏回归；
- [x] 完成全部路由专项、Generator 和 Workspace 回归。

#### P2-1 生成物收敛（已落地）

当前逐源码 JSON 仅作为 Build Cache 中的 Builder 中间数据；发布级 Package Index、Package/Host
Catalog 和 Host Route Catalog 保留各自的消费边界。收敛必须保持“单一机器事实来源”，且不能以
减少文件为由破坏 Package 发布边界或增量生成正确性。

第一阶段进行低风险清理：

- [x] 停止生成逐源码 `*.route.md` 和 `*.component.md`；这些文件不参与编译、校验或 Host 聚合，
  开发者视图由 Package/Host Catalog 覆盖；
- [x] Capability Catalog 没有记录时不生成空的 Package 文档，并在能力从空变为非空或反向变化时
  正确创建、删除陈旧文件；
- [x] 将 Host 的 `cc_routes.md` 与 `cc_sources.md` 合并为统一的人类可读
  `cc_catalog.md`，同时包含契约、源码位置和生成物位置；Package 也使用局部
  `cc_catalog.md`，为后续 Route、Service、Action 和 DevTools 共用同一视图；
- [x] 保留 Host `cc_routes.json` 作为 CI、跨端工具和自动校验使用的机器路由目录，不以 Markdown
  替代结构化契约；
- [x] 覆盖生成、`--check`、空 Catalog、陈旧文件清理和回归测试。

第二阶段独立迁移 Builder 中间数据：

- [x] 将逐源码 `*.route.json` 和 `*.component.json` 从源码树迁入 Build Cache；它们只作为 Builder
  到 CLI 的中间输入，不作为 Package 发布物；
- [x] 每个 Package 仅发布 `lib/src/ccrouter_generated/metadata/ccrouter_package.json` 机器 Index，Host 只通过
  已解析依赖闭包读取 Package Index；
- [x] 迁移时同步处理 `build_to`、增量失效、缓存回退、并发锁、原子写入、外部只读 Package、
  `--check` 快照和旧路径清理，禁止采用“生成后删除中间文件”导致每次全量重建；
- [x] 评估 Package Index 中由 `metadata` 可确定推导的 `capabilityCatalog` 是否继续持久化；当前
  保留它作为发布索引的稳定读取边界，不删除版本化字段。

以下 Dart 生成物职责不同，默认保留，不以文件数量为目标强行合并：

- `*.route.g.dart`：独立生成的 Package 内路由 Library，承载参数 Codec 和注册 bridge；
- `*.route_binding.g.dart`：独立的 Flutter 页面构建 bridge；
- `*.route.contract.g.dart`：跨组件 Pure Dart 类型安全契约；
- `*.component.g.dart`：访问私有 Registrar 并生成 Runtime Manifest；
- `<component>.routes.g.dart`：独立 import 页面库，供 Registrar 和 Package Bundle 共同消费；
- `<package>_ccrouter.g.dart`：发布跨 Package 运行时 Bundle 和直接依赖图；
- `ccrouter_host.routes.g.dart`：向 Host 提供隔离 Package Bundle SPI 的窄门面。

上述目录和数据边界已经迁移。生成器测试覆盖增量缓存、`--check`、空 Catalog、陈旧输出清理、
并发锁和无缓存逐字节一致性；后续新增 Capability 仍必须复用同一 Package Index 与 Catalog。
本轮以 `ccrouter generate demo --no-cache --profile` 执行全量元数据解析（缓存命中 0/11），再用
`--check --no-cache` 校验受控生成物稳定：7 个 Package、4 个组件、30 条路由；旧路径扫描无残留，
Git 工作区无新差异。没有物理删除生成目录；Builder 中间缓存仍由 build_runner 增量管理，
不把“无缓存聚合”误称为全新 Builder 冷构建。

#### P2-2 注解字段合法性校验（已落地，动态注册关系保留运行时校验）

生成器必须校验所有可在构建期确定的字段语义，但不能对 Description、URL、Query Key 等不同领域
的字符串套用同一条通用正则。最终采用分层校验：Dart Analyzer 保证类型和 const 合法性，单
Package Generator 校验局部结构，Workspace 校验跨源码与跨 Package 关系，Runtime 保留手写
Route 和动态 Host/Shell/Interceptor 配置的最后防线。

当前已具备以下生成期校验，后续修改不得退化：

- Component ID、版本基本格式、依赖 ID、重复依赖和自依赖；
- `pattern` / `patterns` 互斥、唯一可逆 Primary、重复 Pattern、Path/URI/Regex 语法、参数
  Capture 和 Constraint；
- Path、Query、Extra 参数来源、支持类型、Query Key 冲突、Codec 类型与构造器；
- Route Contract/Page 的类形态、构造器、结果类型和实现参数一致性；
- Workspace 内 Component/Route 唯一性、Owner、依赖缺失与环、Contract Implementation 和
  可静态证明的 Pattern 冲突。

以下规则按已验证范围标注；组合验收项的剩余部分继续保留：

- [x] Generator 对 Route、Component、Interceptor、Pop Guard、Host、Shell 和 Outlet ID
  使用稳定语法，并校验路由策略引用重复项；相关非法值具有 Generator 失败测试；
- [x] Interceptor/PopGuard 引用的存在性与 Owner 由 Runtime 初始化校验；缺少注册元数据时
  Workspace 不推测动态注册关系；
- [x] Workspace 校验 `parentRouteId` 存在、自引用、依赖可见性、Parent 环及可静态确定的
  Placement 兼容性；动态 Host 和 Adapter Binding 仍在初始化阶段校验；
- [x] Component Version 使用完整 SemVer 2.0，并由 Generator 拒绝不符合 SemVer 的值。
- [x] 对 `CCRegexPattern` 和参数 Constraint 保持语法硬校验，并增加长度、Capture 数量等确定性
  上限；无法可靠判断的灾难性回溯只做明确诊断或文档提示，不使用高误报启发式规则阻断构建；
- [x] 对 Description 和源码注释保持自由文本语义，只做安全转义、确定性换行和必要的生成物大小
  保护，不限制业务语言、Markdown 或 Unicode；
- [x] 建立 Generator、Workspace 与手写 `CCRouteDefinition` 的逐规则测试映射，明确动态校验
  与不适用边界，并补齐手写 Definition 的 Regex Capture/Constraint 上限负向回归；详见
  [注解字段与兼容性校验](CCRouter-annotation-validation.md#逐规则回归映射)。

校验失败时机必须稳定：静态字段由 Generator/Workspace 直接阻断生成；动态注册关系在
`CCRouter.initialize()` 阶段以稳定的 Registration Error 失败；外部 URI 的实际参数值由生成的
Codec 在解析边界返回标准 `CCRouteParameterError`。不得把本可在构建期发现的错误延迟到首次
页面跳转，也不得为了提前失败而让 Generator 猜测运行时 Host 或 Adapter 状态。

已核对的静态声明字段校验已经落地。Interceptor/PopGuard 的“引用是否已注册”以及动态 Host、Shell、
Outlet/Adapter 能力仍在 `CCRouter.initialize()` 或 Adapter 绑定阶段校验，因为生成器无法可靠
推断运行时装配顺序；这是有意保留的运行时边界。

#### P2-3 页面零 Part 与可发现 Route API（已落地）

当前内部路由由生成器写入独立 Library，页面不再声明逐页面 `part`。生成器从注解和构造器
元数据生成 package-internal bridge，再由组件级 Route API 和 Route Index 统一引用，避免
新增或移动页面时手工修改 Registrar。

最终采用独立生成 Library，页面只保留注解和页面声明，不再 import 或 `part` 任何路由生成物：

```dart
@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.detail',
  pattern: CCPathPattern('/lab/detail/:id'),
)
final class DemoDetailPage extends StatelessWidget {
  const DemoDetailPage({required this.id, super.key});

  final int id;
}
```

每个组件生成唯一的内部 Route API Library，Route API 的真实声明只存在于该文件，不通过多个
逐 Route 文件重复导出，避免 IDE 给出多个等价 import 候选：

```text
lib/src/ccrouter_generated/
└── component/
    ├── demo_navigation_lab_component.route_api.g.dart
    └── demo_navigation_lab_component.routes.g.dart
```

组件内部调用统一使用组件命名空间：

```dart
CCRouter.navigator.push(
  DemoNavigationLabRoutes.detail(id: 1),
);
```

跨组件公开契约继续使用独立 Route 类型：

```dart
CCRouter.navigator.push(
  OrderDetailRoute.intent(orderId: 1),
);
```

两种形式的边界固定为：

- `XxxRoutes.method(...)` 是当前组件的 Package-internal 路由集合，只生成在
  `lib/src/ccrouter_generated`，不从 Package 公共 barrel 导出；
- `XxxRoute.intent(...)` 是 `CCRouteContract` 生成的跨组件 Pure Dart 契约，只能由显式依赖的
  Contract Package 公共导出；
- Runtime 注册和 Flutter Catalog 继续由 `<component>.routes.g.dart` 消费，不要求业务导入
  Host/Adapter SPI。

IDE 可发现性属于方案验收条件：生成完成且 Workspace Analyzer 使用根目录 Package Config 时，
输入 `DemoNavigationLabRoutes` 必须能得到代码补全和唯一的自动导包动作。新注解尚未生成时 IDE
不能虚构符号，因此后续按实际耗时评估快速单次生成与 `ccrouter watch`，但不能通过自动修改
业务源码插入 `part` 或 import 来模拟智能化。

独立 Library 无法访问另一个 Library 的私有声明，迁移时必须显式校验以下规则：

- [x] 被 `@CCRoute` 标记的 Page 类及未命名构造器必须能被生成 Library 访问；Page 的 State、
  字段和其他实现仍可保持私有；
- [x] Route 参数、结果类型、Extra 类型、Query Codec 和默认值必须可由生成 Library 稳定引用或
  重建；复用 Contract Generator 的确定性 Import Plan 和常量渲染，禁止复制未经解析的源码表达式；
- [x] Package-internal 生成 Route API 使用 `@internal`，Analyzer 对跨 Package 使用报
  `invalid_use_of_internal_member`；`ccrouter generate --check` 还会拒绝依赖闭包内可写
  Package 的手写生产源码跨包导入/导出 `src/ccrouter_generated`，即使使用 Analyzer ignore
  也不会放行。自动生成的 Host/Binding 胶水合法互访不受影响，公开能力仍通过 Contract；
- [x] Component Route API 是内部 Route Intent 的唯一生成声明位置，逐源码中间生成物不重复
  暴露同名 Route API；
- [x] Component Route Index 只负责 Runtime 注册和 Flutter Destination Catalog，不成为业务
  导航入口，也不把 `ccrouter_host.dart` 泄漏给组件业务代码；
- [x] 独立 Library 已成为默认模式；Demo、生成器和导航回归通过，旧页面 Route Part 已清理；
- [x] IDE 组件内唯一来源 Library 的自动导包已通过 Android Studio 验收；临时源码重命名/
  移动后已复验生成结果及调用点导包。现有测试覆盖多 Route 单源码、源码子目录、私有声明拒绝、集合默认值、
  Extra 和 Contract-first Implementation。

该方案已经启用：内部 Route API 从页面级 `part` 迁移为独立生成 Library，并通过组件命名空间
和公共 Barrel 边界控制可发现性。`lib/src` 与 `implementation_imports` 不是语言级访问控制；
`@internal`、Analyzer error 和 Generator 边界校验建立了工程级保护，不改变 Dart 语言本身的
可导入性；后者仅覆盖参与当前 Host 依赖闭包的可写 Package 生产源码。
页面零样板、组件内稳定入口、默认值生成和 IDE 唯一自动导包已有回归。

#### P2-4 生成器与 API 边界审查（当前 1.x 范围已完成）

- [x] `package:ccrouter/ccrouter.dart` 不暴露 Runtime、Scope、Memory Adapter 或 Host/Adapter SPI。
- [x] Host/Adapter SPI 有独立 `ccrouter_host.dart` 与 `ccrouter_go_router.dart` 入口；当前 Demo
  通过稳定 Host Barrel 引用生成的 Host Catalog。
- [x] 组件 Route API、Route Index、Binding、Contract 和 Package Bundle 已按职责分目录；
  Demo 业务 Barrel 仅显式导出契约 Route，Owner Barrel 导出实现侧所需契约，Host Barrel 独立导出
  Host Catalog，未发现业务 Barrel 导出 Binding、Registrar 或 Package Bundle。
- [x] API Surface 测试锁定业务 Barrel 的 `hide/show` 集合；生成器测试覆盖目标路径、相对
  import、Package URI、旧元数据清理和 Host Bundle 首次创建。
- [x] 用独立 Package 探针验证跨 Package Route API 边界：直接导入 `src/` 的生成 API 在
  当前 Dart SDK 中可以编译，公共 Barrel 不导出该符号时会得到 `undefined_identifier`。
  这证明 `src/` 是约定和导出边界，不是 Dart 语言级 package-private；`implementation_imports`
  也不能当作强制封锁（当前 SDK 对该规则不产生预期诊断）。专项回归位于
  `packages/ccrouter_test/generator_test/route_api_boundary_test.dart`。
- [x] 在 Android Studio 中验证组件内部生成 Route API 的唯一自动导包：在
  `demo/modules/navigation_lab/lib/src/home_page.dart` 输入 `DemoNavigationLabRoutes` 时，
  只有一个 Route API 候选，来源为
  `package:demo_navigation_lab/src/ccrouter_generated/component/demo_navigation_lab_component.route_api.g.dart`。
  `DemoNavigationLabComponentGeneratedRoutes` 是 Runtime 注册索引，不是重复的业务 Route API。
  宿主 Package 仍不会得到该内部候选；临时页面增删改移验收见 6.1。
  Analysis Server 协议探针对未导入符号返回空候选，不能替代真实 IDE 验收。
- [x] 内部 API 边界增量回归：Generator 专项 124 项、API Surface 与组件注册 29 项通过；
  `ccrouter_generator/lib`、`bin`、`generator_test` 静态分析及 Demo analyze 均无问题。

### P3 应用集成入口

- [x] 分别生成 Runtime Manifest 集合和后端 Route Catalog，并通过 Catalog 的组件版本来源
  校验两者一致性；
- [x] 应用通过 `CCRouter.initialize(components: ...)` 原子初始化，并显式调用 `shutdown`；
- [x] `CCRouterApp.managed` 只绑定 Host 与 Backend，并在 Adapter 绑定完成前阻止业务子树
  挂载；
- [x] Adapter 注入由 `CCRouterApp.managed` 的私有协调器完成，不开放独立 Controller；
- [x] `CCGoRouterBackend.managed` 自动组装 Root Observer、GoRouter、Binding 和 Adapter；
- [x] `CCGoRouterBackend.attach` 保留已有 GoRouter 的应用所有权；
- [x] 默认 `CCRouterApp(child:)` 保持不拥有 Runtime 的兼容语义；
- [x] Flutter 门面支持可选调用级 `BuildContext` Outlet 解析：只匹配当前 Host 已注册的
  Navigator，解析失败不猜测 root，显式 Route Placement 优先；
- [x] 覆盖绑定成功、失败安全 UI、显式销毁顺序、Router 所有权和生成器聚合回归；
- [ ] 提供 Navigator 1.0 Backend，供无法迁移到 Router API 的已有项目渐进接入（延期至架构 2.0，
  不计入当前 1.x 实施范围）。

## 4. 回归要求

每个阶段至少执行：

```text
受影响 Package analyze
新增专项测试
packages/ccrouter_test/test 全量测试
packages/ccrouter_test/generator_test（涉及生成器时）
git diff --check
```

Demo 中与本轮无关的用户工作区改动不回退；如果其未完成代码阻止 Demo analyze，单独记录，
不以修改或删除用户代码作为绕过方式。

### 1.x 生成物边界全量回归（第 6 项）

- `fvm dart analyze`：Workspace 无问题；`packages/ccrouter_test/test`：244 项通过；
  `packages/ccrouter_test/generator_test`：124 项通过；`demo/test`：22 项通过。
- `fvm flutter run -d macos --no-pub` 构建并启动 Demo，实际查看首屏与导航页；
  点击类型安全 Push 和确认返回后，获得 `detail:42:confirmed`，Managed Route Entry 回到 0。
  启动日志报告窗口未自动置前，但窗口及页面实际可见，未观察到运行异常。
- 新增的跨 Package 生成 API 校验器只在 CLI 校验期间读取源码并解析 AST，不持有
  Listener、Timer、Overlay 或运行时 Route；测试创建的临时目录使用 teardown 清理。
  现有路由测试覆盖 Host、Scope、pending result 与销毁路径；本轮未执行长时间运行的
  堆快照或压力测试，因此不能据此宣称不存在任何长期内存增长。
- 无缓存全量聚合与 `--check --no-cache` 的产物一致性结果见 P2-1；macOS 手工操作
  只验证了首屏和类型安全 Push/Pop，其他 UI 路径依赖上述自动化测试，未逐页手工遍历。

## 5. 1.x 路由边界冻结（第 7 项）

当前版本的交付边界如下；本节只固定已验收能力与延期范围，不增加新的公开 API。

| 领域 | 1.x 已交付边界 | 不应推断为已支持 |
| --- | --- | --- |
| 应用导航 | `CCRouter` 统一导航、Runtime/RouteEntry 生命周期、GoRouter Backend、Host/Outlet、Shell 与 StatefulShell 接入 | Navigator 1.0 Backend 或原生 Window 创建与监听 |
| 组件路由 | 注解生成 Package/Host Catalog、内部 Route API、跨组件 Contract 与公共 Barrel；页面无需 `part` | 未生成符号的 IDE 补全，或跨 Package 任意导入内部 Route API |
| 生成校验 | Analyzer、Generator、Workspace 和 Runtime 分层校验；增量与无缓存聚合一致性已回归 | 动态注册关系全部可在编译时证明，或仅靠 `lib/src` 实现语言级隔离 |
| 诊断与恢复 | 有界观察事件、Route/Backend identity 和恢复机会事件（固定 `unsupported`） | Route Restoration Snapshot、页面自动恢复或长期内存压力测试结论 |

内部生成 API 的保护由公共 Barrel 不导出、`@internal` 的 Analyzer error，以及
`ccrouter generate` / `--check` 的 AST 门禁共同实现。Dart 仍允许显式导入其他
Package 的 `src`；CLI 门禁只扫描当前 Host 已解析依赖闭包中**可写 Package 的手写生产
`lib/**/*.dart`**，不覆盖只读第三方、无关 Package 和测试源码；自动生成的 Host/Binding
胶水可以合法互访。该边界是工程级约束，不是语言级访问控制。

Host 表示一组受框架管理的导航上下文；目前一个 Host 可有多个 Outlet，布局变化只更新
Metrics/Display Features，不自动产生原生窗口。未来每个 Flutter View 或原生 Window 可映射
一个 Root Host，但平台窗口生命周期桥接尚未实现。`CCRouterApp` 不强制接管已有应用的
`MaterialApp.router` 或应用拥有的 GoRouter。

下列能力统一归入 2.0 规划，不作为 1.x API 冻结的隐含验收条件。2.0 是最早评估和实施阶段，
不是无条件发布承诺；前置条件不成立时继续延期，不以填满功能清单为目标。

1. Navigator 1.0 Backend 留到架构 2.0；先以独立 Backend 复用 Route Definition 和
   `CCRouterAppBackend` SPI，验证 Pop/Observer/返回值与能力降级，不改业务导航入口。
2. 原生多窗口桥接在 2.0 等待平台稳定接入能力；先验证 Window/View 到 Root Host 的身份映射、
   激活、关闭和失效释放，不把同一窗口的旋转、折叠或多个 Outlet 当成新 Window。
3. 完整 Route Restoration 在 2.0 只有恢复机会 Telemetry 证明收益后才实施；此前保持
   `unsupported` 诊断，不提供伪恢复语义。
4. `ccrouter watch`、CLI 快速单次生成与 DevTools 可视化属于 2.0 开发体验候选；
   当前以显式生成、`--check` 和 Package/Host Catalog 为确定性基础。临时页面的源码
   重命名/移动与 IDE 导包已验收，但不外推至 IDE 重启或大型外部依赖工程。
5. 原子组合栈事务和精确 Route Entry 操作在 2.0 重新评估；分别以稳定身份、原子回滚和
   混合栈隔离为准，不能在 1.x 通过拼接已有操作模拟。

Service/Handler/Scope 的完整组件动态停用、Service 契约收敛、组件创建与契约提升 CLI
也归入架构 2.0 的**非路由工作流**，需要独立设计和验收，不是路由 2.0 的必选依赖。
与新增能力不同，文档状态纠偏、当前改动的测试/提交，以及内存和性能的持续采样仍属于
1.x 日常质量维护，不能因规划 2.0 而暂停。

后续扩展必须保留本轮测试门禁与可回退的 Backend/Generator 边界；涉及新公开能力时先补
失败边界和能力声明，再实施并分别执行 Generator、Runtime、Demo 与 Workspace 回归。

## 6. 生成体验验收

### 6.1 页面增删改移与 IDE（已验证）

在 Demo 的 `demo_navigation_lab` 内使用临时、无业务引用的页面，按顺序执行
新增、类名重命名、移动到 `lib/src/probe/`、删除；每一步运行
`fvm dart run ccrouter_generator:ccrouter generate demo --profile`。以下为本机单次观测，
不是跨机器性能基准：

| 操作 | 总耗时 | Builder | 结果 |
| --- | ---: | ---: | --- |
| 初始空改动 `--check` | 2060 ms | 1255 ms | 0 输出，缓存 11/11 |
| 新增 Route | 5458 ms | 4847 ms | 31 条路由，Route/Binding、组件 API、Host Catalog 均更新 |
| 重命名页面类 | 5807 ms | 5094 ms | ID 不变；生成类型与 Catalog 符号更新，无旧类引用 |
| 移动源码目录 | 4867 ms | 4359 ms | 新子目录生成物与源码定位正确，旧位置生成物消失 |
| 删除临时页面 | 7689 ms | 6794 ms | 回到 30 条路由，Route API、Host Catalog 与旧产物均清理 |
| 删除后稳定空改动 `--check` | 2275 ms | 1367 ms | 0 输出，缓存 11/11，工作区干净 |

在 Android Studio 的本仓库窗口，对组件内临时未导包调用点请求 Quick Fix：
`DemoNavigationLabRoutes` 的导入建议均指向同一个生成 Library，IDE 同时提供相对路径、
Package 路径和 `show` 变体。选择相对路径建议后，调用
`DemoNavigationLabRoutes.generationProbe()` 可解析。这里验收的是**唯一来源 Library**，
不是声称 IDE 只显示一条菜单项。生成前尚无符号，不能依赖 IDE 猜测新增 Route。

临时页面与 IDE 调用点均已清理；删除后的 `--check` 与 Workspace analyze 通过。
首次删除后的 Builder 有失效图重建，稳定的再次执行已回到 0 输出；不能把这两个测量
当作重复空改动的平均值。该验收不包含同时编辑多个组件、IDE 重启或大型外部依赖工程。
Generator 全套 124 项、Demo 22 项通过；受管生成物无残留或 Git 差异。

### 6.2 快速单次生成命令（本轮不新增）

现有 `generate demo` 已按 Host 依赖闭包构建，build_runner 对未变更输入跳过 Builder，
随后使用内容指纹缓存解析元数据。6.1 的稳定空改动约 2.1–2.3 秒；改动一个页面约
4.9–7.7 秒，主要耗在 build_runner 的 Analyzer 和失效图，Catalog 聚合约 0.1–0.2 秒。
样本为一台机器的单次测量，不能推断大型项目的 P95。

候选方案及取舍：

- 继续使用统一 `generate`：保证 Route、Binding、组件索引、Package Index 与 Host Catalog
  同步，是当前默认路径；一次小改动仍需等待数秒。
- 新增按源码文件过滤的快速命令：可能减少 Analyzer 工作，但必须构建所有受影响的 Builder
  输出并重新聚合 Host；单文件过滤若漏掉间接依赖，会留下可编译但未注册的 Route。
- 绕过 build_runner 直接生成单文件：速度可能更快，但会复制 Builder 语义、缓存和校验边界，
  不符合“生成快且不出错”的优先级。

1.x 不新增命令或公共参数。2.0 若目标业务仓库对至少 20 次页面增删改移的增量操作
测得 P95 超过 10 秒，先用
`--profile` 确认 Builder/解析/聚合瓶颈，再做可回退的独立快速路径，与统一命令逐字节
比对生成物、错误和清理结果；不能把只更新页面文件的命令命名为完整生成。

### 6.3 `ccrouter watch`（2.0 候选，具备监听基础）

本机 `build_runner watch --help` 确认支持 `--workspace` 与多个 `--build-filter`，
理论上可监听 6.1 的可写依赖闭包；稳定的构建完成事件接入仍须验证。
当前 CLI 是一次性事务：持有
`.dart_tool/ccrouter/v1/generation.lock`，等待 build_runner 退出，再解析 metadata、
校验、聚合、清理与发布 Catalog。简单地把 `build` 改成常驻 `watch` 会永远等不到聚合；
让常驻进程一直持锁也会阻塞手动 `generate` / `--check`。

2.0 若实际页面编辑频率或 P95 延迟证明有需求，应作为独立可选命令，不改变现有
`generate` 的行为，并按下列顺序实现与验收：

1. 用可靠的 Builder 完成信号触发聚合，不解析易变的终端输出；多次文件事件合并，
   每轮只处理最新确定完成的构建，不发布半轮生成物。
2. 逐轮获取生成锁，并串行执行解析、跨 Package 校验、旧产物清理及原子发布；
   与独立 `generate --check` 并发时不死锁、不覆盖对方的结果。
3. 失败时保留上一次完整产物并报告明确的 stale 状态；恢复成功后重新校验依赖闭包，
   包括 Package 增删、`pubspec.yaml`、Component ID 和路由冲突的变动。
4. Ctrl-C、终端关闭或构建进程异常退出时终止子进程、释放锁和 Listener；测试快速连续
   修改、重命名、删除、多组件并发，以及失败后修复的收敛结果。
5. 与一次性 `generate` 和 `--no-cache` 比较产物与错误；增加资源占用和导航开发循环的
   实测数据后，再决定是否提供默认启用或 IDE 集成。

当前 Demo 改一页约 5–8 秒、稳定空改动约 2 秒，尚不足以证明常驻监听的维护与资源成本
值得承担。1.x 不启动后台服务，也不扩展公开 API；大型项目的实际 P95 是 2.0 决策的依据。

### 6.4 路由源码定位命令（已落地）

`ccrouter find <route-id-or-declared-pattern> [host-root]` 只读取当前 Host 的 Pub 运行时
依赖闭包与已发布的 Package Index，使用同一 Capability Source Catalog 合并跨 Package
契约和实现位置，按精确 Route ID 或声明的 Pattern 文本返回组件、Package、源码坐标和别名。
不启动 Builder、不写入生成物、不扫描源码或猜测实际 URL 的动态参数；缺失或损坏的 Index
以及依赖指纹不一致的混合版本 Index 必须报错，不能静默回退到旧文档。生成前新增的
Route 不可发现；源码修改后的新鲜度仍由 `generate --check` 负责。CLI 专项测试覆盖
跨包合并、Path/URI 别名、Host 闭包、无结果、参数错误和 Index 失败。
