# CCRouter 路由完成计划

## 文档状态

- 版本：v0.2
- 状态：路由功能闭环与 Observer 有界异步分发已完成；完整 Route Restoration 明确暂缓
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
- [ ] 接入原生 macOS、Windows、iPadOS Window/Flutter View 的创建、激活、关闭和恢复生命周期。

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
- [ ] 定义版本化、Adapter 中立的 Route Restoration Snapshot（数据证明有需求后再启动）；
- [ ] 实现重新解析、安全校验、契约升级和部分恢复（非当前版本阻塞项）。

完整状态恢复暂不进入生产 API。后续只有在恢复机会率、受影响 Route 分布、多窗口恢复占比等
Telemetry 数据证明收益后才重新立项；届时必须采用路由显式 opt-in，且不能持久化 Widget、
BuildContext、Flutter Route、Scope、Extra 或返回 Completer。

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

#### P2-1 生成物收敛（已审计，待执行）

当前生成链同时保存源码级 JSON/Markdown、Package Index、Package/Host Capability Source
Catalog 和 Host Route Catalog。同一份路由事实存在多种派生表示；当前体积不是风险，但文件数量、
Git 噪声和后续 Capability 扩展会随源码文件数线性增长。收敛必须保持“单一机器事实来源”，且
不能以减少文件为由破坏 Dart library privacy、Package 发布边界或增量生成正确性。

第一阶段进行低风险清理：

- [ ] 停止生成逐源码 `*.route.md` 和 `*.component.md`；这些文件不参与编译、校验或 Host 聚合，
  开发者视图由 Package/Host Catalog 覆盖；
- [ ] Capability Catalog 没有记录时不生成空的 Package 文档，并在能力从空变为非空或反向变化时
  正确创建、删除陈旧文件；
- [ ] 将 Host 的 `cc_routes.md` 与 `cc_sources.md` 合并为统一的人类可读
  `cc_catalog.md`，同时包含契约、源码位置和生成物位置；Package 也使用局部
  `cc_catalog.md`，为后续 Route、Service、Action 和 DevTools 共用同一视图；
- [ ] 保留 Host `cc_routes.json` 作为 CI、跨端工具和自动校验使用的机器路由目录，不以 Markdown
  替代结构化契约；
- [ ] 补齐生成、`--check`、空 Catalog、陈旧文件清理和全量回归测试。

第二阶段独立迁移 Builder 中间数据：

- [ ] 将逐源码 `*.route.json` 和 `*.component.json` 从源码树迁入 `.dart_tool/ccrouter/` 或等价的
  Build Cache；它们只作为 Builder 到 CLI 的中间输入，不作为 Package 发布物；
- [ ] 每个 Package 仅发布 `lib/ccrouter_generated/ccrouter_package.json` 机器 Index，Host 只通过
  已解析依赖闭包读取 Package Index；
- [ ] 迁移时同步处理 `build_to`、增量失效、缓存回退、并发锁、原子写入、外部只读 Package、
  `--check` 快照和旧路径清理，禁止采用“生成后删除中间文件”导致每次全量重建；
- [ ] 评估 Package Index 中由 `metadata` 可确定推导的 `capabilityCatalog` 是否继续持久化；如果
  删除或统一 Schema，必须保留版本兼容、指纹校验和 DevTools 的稳定读取边界。

以下 Dart 生成物职责不同，默认保留，不以文件数量为目标强行合并：

- `*.route.g.dart`：与页面源码共享 library privacy，并承载参数 Codec 和页面构建桥接；
- `*.route.contract.g.dart`：跨组件 Pure Dart 类型安全契约；
- `*.component.g.dart`：访问私有 Registrar 并生成 Runtime Manifest；
- `<component>.routes.g.dart`：独立 import 页面库，供 Registrar 和 Package Bundle 共同消费；
- `<package>_ccrouter.g.dart`：发布跨 Package 运行时 Bundle 和直接依赖图；
- `ccrouter_host.routes.g.dart`：向 Host 提供隔离 Package Bundle SPI 的窄门面。

本节只记录审计结论，不表示上述收敛已经实现。实施时先完成第一阶段并验证生成性能与输出稳定性，
再单独迁移中间 JSON，避免把文档清理、Schema 变更和 Build Cache 改造混入同一变更。

#### P2-2 注解字段合法性校验（已审计，待执行）

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

需要补齐以下静态规则：

- [ ] 为 Route、Component、Interceptor、Pop Guard、Host、Shell 和 Outlet 分别定义稳定的 ID
  语法；Route ID 不能继续只检查非空和空白，所有 ID 的前后空白、非法字符和重复值必须在生成期
  给出指向注解声明的错误；
- [ ] Generator 校验 `interceptors`、`popGuards` 内的空值、格式和重复项；Workspace 在未来具备
  对应注册元数据后校验存在性与 Owner，在此之前仍由 Runtime 初始化校验动态注册关系；
- [ ] Workspace 校验 `parentRouteId` 存在、自引用、依赖可见性和 Parent 环，并校验可静态确定的
  Host、Shell、Outlet 结构兼容性；动态 Host 和 Adapter Binding 仍在初始化阶段校验；
- [ ] 明确 Component Version 使用完整 SemVer 2.0，或将当前近似格式命名为 CCRouter Version
  Format，避免错误宣称完整 SemVer；
- [ ] 对 `CCRegexPattern` 和参数 Constraint 保持语法硬校验，并增加长度、Capture 数量等确定性
  上限；无法可靠判断的灾难性回溯只做明确诊断或文档提示，不使用高误报启发式规则阻断构建；
- [ ] 对 Description 和源码注释保持自由文本语义，只做安全转义、确定性换行和必要的生成物大小
  保护，不限制业务语言、Markdown 或 Unicode；
- [ ] 为每条 Generator 规则增加失败测试，为每条跨 Package 规则增加 Workspace 测试，并为手写
  `CCRouteDefinition` 增加对应 Runtime 防线测试，防止三层语义漂移。

校验失败时机必须稳定：静态字段由 Generator/Workspace 直接阻断生成；动态注册关系在
`CCRouter.initialize()` 阶段以稳定的 Registration Error 失败；外部 URI 的实际参数值由生成的
Codec 在解析边界返回标准 `CCRouteParameterError`。不得把本可在构建期发现的错误延迟到首次
页面跳转，也不得为了提前失败而让 Generator 猜测运行时 Host 或 Adapter 状态。

本节只记录校验目标，尚未表示 Route ID、Placement、Parent、Pop Guard 去重或 Regex 上限已经
实现。实施前应先形成字段规则表和兼容性清单，确认现有 Demo 与已发布契约不会因语法收紧而静默
改变含义。

#### P2-3 页面零 Part 与可发现 Route API（方案已确认，待执行）

当前内部路由通过页面侧 `part 'ccrouter_generated/xxx.route.g.dart';` 与生成代码共享 Dart
library，以获得真正的 library privacy，并访问页面构造器、私有类型和默认表达式。但该声明需要
开发者根据源码相对路径手工维护，新增、移动页面时容易遗漏，错误通常延迟到 Component Route
Index，违背自动配置和低成本接入原则。

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
不能虚构符号，因此后续 CLI 应提供快速单次生成，并评估 `ccrouter watch`，但不能通过自动修改
业务源码插入 `part` 或 import 来模拟智能化。

独立 Library 无法访问另一个 Library 的私有声明，迁移时必须显式校验以下规则：

- [ ] 被 `@CCRoute` 标记的 Page 类及未命名构造器必须能被生成 Library 访问；Page 的 State、
  字段和其他实现仍可保持私有；
- [ ] Route 参数、结果类型、Extra 类型、Query Codec 和默认值必须可由生成 Library 稳定引用或
  重建；复用 Contract Generator 的确定性 Import Plan 和常量渲染，禁止复制未经解析的源码表达式；
- [ ] Package-internal 生成 API 使用 `@internal`、`implementation_imports`、Barrel Validator 和
  API Surface Test 共同阻止跨 Package 误用；公开跨组件能力必须提升为 `CCRouteContract`；
- [ ] Component Route API 是内部 Route Intent 的唯一声明位置，逐源码中间生成物不得再次暴露
  同名 public Route API，保证 IDE 只有一个规范 import；
- [ ] Component Route Index 只负责 Runtime 注册和 Flutter Destination Catalog，不成为业务
  导航入口，也不把 `ccrouter_host.dart` 泄漏给组件业务代码；
- [ ] 先以可回退的 `standalone` 生成模式迁移 Demo 和测试，对比生成结果、导航行为、API surface
  和生成性能，验证后设为默认，再删除旧 `part` 模式及陈旧 Part 文件；
- [ ] 覆盖多 Route 单源码、源码子目录、私有 Page、私有参数类型、枚举/集合默认值、Extra、
  Contract-first Implementation、重命名/移动源码、自动导包唯一性和陈旧输出清理测试。

该方案接受一个明确权衡：内部 Route API 从 Dart library-private 变为受 Analyzer 和 Package
边界保护的 package-internal。收益是页面零样板、无需计算生成路径、IDE 可发现且组件内只有一个
稳定入口；跨组件能力仍保持独立 Contract Package 和编译期类型安全。若实现无法满足唯一导包、
公共 barrel 隔离或默认值确定性，不得直接替换现有 Part 模式。

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
