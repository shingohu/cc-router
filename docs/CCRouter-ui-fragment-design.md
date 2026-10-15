# CCRouter 类型化 UI Fragment 设计与实施计划

## 文档状态

- 版本：v0.2（v1 实施记录）
- 日期：设计 2026-10-13，实施 2026-10-15
- 状态：静态 v1 已实施；平台实机、长期内存与性能基线仍需后续验证
- 分类：跨组件 UI 契约与静态装配属于新的通用框架能力；具体 UI 和业务状态仍由组件负责
- 适用范围：Flutter Widget 树内的跨组件局部 UI 组合
- 推荐方案：可选 `ccrouter_ui` 模块，采用 UI Contract + generated Client + Renderer 静态注册

本文保留设计依据与分阶段门禁，并按 v1 实现修正已冻结边界。当前公开能力以
[文档索引](README.md)、[接入指导](../skills/ccrouter-integration-development/references/ui-fragments.md)
和生产代码为准。实施选择 UI Assembly wrapper，未让 Core Bundle 承载 Widget factory。
实际 API、回归证据、核心价值和剩余边界见
[实施验收记录](CCRouter-ui-fragment-acceptance.md)。

## 1. 问题分析与能力边界

### 1.1 生产场景

A 的页面需要展示 B 提供的推荐列表、订单摘要或设备状态卡片。B 负责该 UI 的布局、
加载、刷新和局部交互，A 负责摆放位置、输入参数和收到动作后的页面级决策。
A 不应导入 B 的内部 Widget、页面或 Renderer，也不应复制 B 的展示逻辑。

当前 Service 可以提供数据，但不能表达“B 拥有并输出完整的局部 UI”。直接导入 B 的
Widget 虽然可运行，却使 A 依赖 B 的实现 Package，绕过 Contract、依赖校验和 Host 装配。
将 Widget 放入 Service 返回值则会污染业务服务契约，并绕过现有生成器类型约束。

缺失的是跨组件 UI 的类型化组合边界，不是 Flutter 缺少 Widget 组合能力。
仅共享颜色、按钮或无业务状态的布局时，普通公共 Flutter UI Package 已足够。
只有需要隐藏组件实现、校验消费依赖、由 Host 选择实现时，才使用本能力。

### 1.2 与现有能力的关系

| 场景 | 推荐机制 | 生命周期与职责 |
| --- | --- | --- |
| A 只需要 B 的数据，自行展示 | Service Contract | Service Scope 管理业务资源 |
| A 需要 B 的一块完整局部 UI | 本文 UI Fragment | Flutter Element/State 管理实例 |
| 多页面共享普通展示控件 | 公共 Flutter UI Package | 普通 Widget 组合 |
| B 的完整页面成为 A 的 Tab | Host-owned Route Mount | Managed Route、Outlet、Route Scope |
| 多组件给一个区域贡献卡片并排序 | 后续 Slot 扩展 | v1 不提供多贡献者装配 |

UI Fragment 不创建 RouteEntry、导航栈、Route Scope 或 Fragment Scope。它不自带
Deep Link、PopGuard、页面结果通道，也不冒充 Managed Route。完整页面组合继续使用
[Host-owned Route Mount](CCRouter-host-owned-route-mount-design.md)。

## 2. 候选方案与推荐

| 方案 | 收益 | 代价与风险 | 决策 |
| --- | --- | --- | --- |
| A 导入 B 的 Widget | 最少代码，直接利用 Flutter | 实现耦合，无法独立替换和校验 | 小应用可用，不作为框架方案 |
| 公共 UI Package + Service 数据 | 简单、现有能力即可支持 | A 接管 UI 编排，B 无法完整封装业务 UI | 保留为轻量选择 |
| Service 返回 Widget/Builder | 看似可复用现有代理 | 污染服务契约，混入 Context、回调和视图生命周期 | 拒绝 |
| 可选 UI Contract 与 Renderer | 类型安全、实现隔离、静态校验，可独立回退 | 增加生成、装配与生命周期边界 | 推荐 |
| Core 内置动态 Slot/插件管理器 | 可做排序、热替换和动态发现 | 复杂度高，扩大 Core，当前场景不需要 | 延期 |

推荐先实现单契约单实现的静态闭环。它提供可复用的业务 UI 边界，但不成为通用
状态管理框架或 Android FragmentManager 的 Flutter 版本。

## 3. 业界参考与取舍

| 参考 | 借鉴 | 不照搬的部分 |
| --- | --- | --- |
| [Backstage Extensions](https://backstage.io/docs/frontend-system/architecture/extensions/) | 明确的类型化输入/输出、factory 与应用装配 | 插件树、动态贡献和通用扩展系统不进入 v1 |
| [Compose API Guidelines](https://github.com/androidx/androidx/blob/androidx-main/compose/docs/compose-api-guidelines.md) | 显式输入、状态提升、清晰的实例身份 | 不要求 B 将全部业务状态提升到 A |
| [Android Fragment Lifecycle](https://developer.android.com/guide/fragments/lifecycle) | 视图资源与长期业务资源分离，视图结束后清理引用 | 不新增 FragmentManager、事务或原生 Fragment 生命周期 |
| [Flutter State Lifecycle](https://api.flutter.dev/flutter/widgets/State-class.html) | Element/State、Key、didUpdateWidget 和 dispose 是实例基础 | 不以路由事件或 Runtime shutdown 代替 State.dispose |

这些参考支持契约与实现分离、装配与渲染分离、显式资源归属。CCRouter 的实现必须遵守
Flutter 的实例和重建规则，不能把其他平台的容器模型直接迁移过来。

## 4. 目标与 v1 非目标

目标是让 A 通过生成的类型化 Client 构建普通 Widget，B 通过 Renderer 提供实现，
Host 在启动前完成确定性装配。配置错误应在生成或初始化阶段被拒绝。
未声明 UI 能力的旧组件和 Host 保持原生成路径与行为。

v1 范围：

- 同一契约只有一个有效 Renderer；一个 Renderer 可创建多个相互独立的 UI 实例。
- Props 和 Action 使用明确的 Pure Dart 类型；局部交互通过类型化 callback 返回 A。
- 静态 Host Assembly、版本范围与 shape fingerprint 校验。
- 复用 Flutter inherited 环境、State 生命周期与现有 App/Session Service。

v1 不提供动态 install/uninstall、运行时替换 Renderer、多贡献者 Slot、排序规则、
通用 UI 沙箱、自动曝光、状态恢复、跨进程或原生视图容器。Android/iOS/OHOS/Web
上的 Flutter Widget 可按平台验证；原生 Fragment/ViewController/ArkUI 挂载不在承诺内。
v1 不支持泛型 UI 契约、多个独立 Action 通道、集合、sealed Action 或任意函数型 Props。

## 5. Package、API 与依赖分层

### 5.1 分层

| 层 | 实现位置 | 可见内容与使用者 |
| --- | --- | --- |
| UI 契约声明 | `ccrouter_contracts` 独立 UI library | Pure Dart annotation、identity、Props/Action 描述与依赖声明 |
| 业务与 Renderer API | `ccrouter_ui.dart` | 生成 Client 所需 Widget 包装、Renderer 输入；A/B 使用 |
| Host SPI | `ccrouter_ui_host.dart` | UI catalog 与 Host 绑定；只由 Composition Root 使用 |
| Generated SPI | `ccrouter_ui_generated.dart` | 工厂描述、生成绑定、消费身份；只由生成代码使用 |
| 内部实现 | `ccrouter_ui` 私有 library | lookup、generation guard、实例包装与诊断 |

`ccrouter_ui` 可以依赖 CCRouter 的稳定 SPI；CCRouter 不反向依赖 `ccrouter_ui`。
Pure Dart 契约、兼容算法与元数据不引入 Flutter。不得把 Widget factory 塞进现有
Service Registry，也不得向业务暴露 Runtime、Host adapter 或通用 registry 查询。

独立 UI 入口是新增的显式 API 层，实施时需同步 Integration Skill 的 import 白名单。
它不意味着业务可以导入 `src` 或 Host/Generated SPI。

### 5.2 应用依赖方向

```text
A implementation ----> B public contracts + generated UI Client
B implementation ----> B public contracts + ccrouter_ui Renderer API
Host assembly -------> A/B generated package bundles + UI Host SPI
ccrouter_ui ----------> stable CCRouter SPI
```

B 的 Renderer implementation 不从公开 Contract barrel 导出。Host 聚合器可以导入实现
贡献，A 的生成 Client 只能依赖公开契约和 `ccrouter_ui`。普通共享 UI Package 不受此装配
流程约束。

## 6. 契约与消费 API

以下展示已冻结的声明形式；应用类型和 Owner 常量由实际 contracts Package 提供。

### 6.1 B 声明 UI Contract

```dart
@CCUIFragmentContract<OrderSummaryProps, OrderSummaryAction>(
  componentId: orderComponentId,
  id: 'order.summary',
  version: '1.0.0',
)
abstract final class OrderSummaryFragmentContract {}

final class OrderSummaryProps {
  const OrderSummaryProps({required this.orderId});
  final String orderId;
}

enum OrderSummaryAction { openDetails, retry }
```

Contract marker 必须公开且非泛型；Props 为 final class，只提供 const generative constructor，
不含继承、mixin、interface 或自定义方法；Action 和 DTO 中的 enum 均只能声明枚举值，
不允许自定义字段、getter/setter、方法、构造器、mixin 或 interface（含 static 成员）。
DTO 构造器参数只允许 `this.field`；每个字段必须在声明处提供常量初始值，或由每个构造器的
`this.field` 初始化。参数默认值与字段初始值均按有效常量值计入指纹，等值表达式保持相同指纹。
v1 拒绝初始化列表赋值和重定向构造器，避免未建模的构造表达式绕过默认值兼容校验。
Props 字段仅支持 scalar、普通 enum 与无环嵌套 DTO（可空字段可用），不可包含集合、Widget、
BuildContext、controller、Service 实例、Future、Stream 或 function。
输入以 UI 所需最小数据为准，不把完整业务对象图或账号凭证传入视图。

v1 每份 Props 必须有明确字段 schema，所有存储字段公开且 final。不得在原对象中
修改字段期待 UI 自动刷新。更新应传入新的 Props；B 显式比较影响数据请求的字段。
复杂对象、通用外部库类型、递归 schema 和 sealed Action 暂不开放。

### 6.2 A 声明消费依赖

```dart
const accountComponent = CCComponent(
  id: accountComponentId,
  version: '0.1.0',
  dependencies: [orderComponentId],
  uiDependencies: [
    CCUIFragmentDependency<OrderSummaryFragmentContract>(
      versionRange: '^1.0.0',
      alias: 'orderSummary',
    ),
  ],
);
```

`uiDependencies` 是可选新增字段，默认空。v1 已声明依赖为 required，必须有实现；
不提供返回 null 的 optional Client。组件图记录 A 消费 B 的 UI 契约，禁止手写 identity
或借其他组件的 Client 规避依赖声明。业务可见性判断仍由 A 决定。

### 6.3 B 实现 Renderer

```dart
@CCUIFragmentRenderer(OrderSummaryFragmentContract)
Widget buildOrderSummary(
  CCUIFragmentRenderInput<OrderSummaryProps, OrderSummaryAction> input,
) {
  return OrderSummaryCard(
    props: input.props,
    onAction: input.onAction,
    active: input.active,
  );
}
```

Renderer 是公开、同步、顶层函数，输入输出必须精确匹配生成器确认的类型。
它可能在每次 build 调用，应只构造 Widget，不在 factory 内注册监听、创建需要释放的
资源、执行 I/O 或触发导航。内部有状态 Widget 自行拥有 controller、请求和订阅。
Renderer 的 BuildContext 由返回 Widget 在自身 build 中获取，不存进 catalog。

B 可以在内部使用 Provider、Riverpod、Bloc 或普通 State；框架不强制状态管理库。
它继续通过 B 自己的 generated Service Client 调用 App/Session Service。

### 6.4 A 构建 Fragment

```dart
AFragments.orderSummary(
  key: ValueKey(orderId),
  props: OrderSummaryProps(orderId: orderId),
  active: isSelectedTab,
  onAction: (action) {
    if (action == OrderSummaryAction.openDetails) {
      // A 通过现有 generated Intent 和 navigator 决定后续导航。
    }
  },
)
```

Client 返回普通 Widget；A 决定 Padding、尺寸约束、滚动容器、排列和 Key。
B 声明布局前提，例如是否需要有界高度，避免把内部 ListView 嵌入无界容器。
v1 不生成 BuildContext 参数，不将实例挂到全局 registry。
`onAction` 是 UI 层的类型化 callback，不属于 Service Contract；现有 Service 对
callback、Stream 和 Flutter 类型的限制保持不变。

## 7. 生成与 Host 静态装配

### 7.1 生成路径

1. 解析 Contract 的 Owner、ID、版本、Props/Action schema 与 Renderer 签名。
2. 生成契约描述与 shape fingerprint、消费依赖和消费组件专属 Client。
3. B 的独立 UI 生成库输出 Renderer contribution；A 输出 UI requirement。
4. Host 聚合所有 contribution/requirement，构建不可变 UI catalog 并执行兼容门禁。
5. Runtime 初始化与 Host UI binding 使用同一份验证快照，避免验证与实际渲染不一致。

UI 使用显式 opt-in `<componentId>.ui.api.g.dart`，保持现有
`<componentId>.api.g.dart` 的路径和 Pure Dart 使用者依赖不变。具体导出位置与命名
已冻结。Client 名为完整 component ID 的 PascalCase 加 `Fragments`。
无 UI 声明的 Package 不新增 UI import、输出文件或 UI fingerprint 输入。

### 7.2 避免反向依赖

实施选择 UI Assembly wrapper：`CCUIHostAssembly.attach` 先校验独立 Renderer/requirement
列表，再通过 Host-only `CCHostAssembly.withLifecycleBindings` 保留原 Assembly 的全部输入，
附加一个 `CCHostLifecycleBinding`。原 `CCGeneratedPackageBundle` 不新增 UI payload。
Core 只负责通用 binding 的 attach、初始化失败回滚和 shutdown detach，不理解 UI 工厂。
`ccrouter_ui -> ccrouter` 单向依赖；业务 `CCRegistry` 权限不变。
Host 仍只把最终的一个 Assembly 交给 `CCRouterHost.initialize`。

### 7.3 装配不变量

- 契约 identity 由 Owner component ID 与 contract ID 确定，实例 Key 不参与契约身份。
- required 契约必须且只能有一个 Renderer；重复、缺失、Owner 不匹配均拒绝启动。
- A 的消费声明、B 的实现和 Host 装配必须使用同一 schema 与兼容结果。
- catalog 只保存工厂和描述，不保存实例 Widget、State、Context 或消费 callback。
- Host 不能在运行中更改映射；A/B 对比通过不同 Host Assembly 构建选择实现。
- 替换实现仍属于同一 Owner 的部署选择；不能注册两个实现后“取第一个”。

## 8. 生命周期、并发与资源归属

### 8.1 实例身份与更新

包装 Widget 与 B 的内部 Widget 保持稳定类型。相同位置、类型和 Key 下，Flutter 保留
State；Props/active/callback 更新通过正常 Widget 更新路径传入。
Key 改变或树移除时由 Flutter dispose 旧实例。没有 Key 时遵循 Flutter 的位置身份，
列表重排必须由 A 提供稳定业务 Key；框架不能猜测业务 identity。
两个 Fragment 实例必须拥有独立 State，不缓存 Widget 来复用状态。

包装层只保存当前实例所需引用；callback 更新后，动作分发读取最新 callback。
B 的异步请求必须使用请求 revision/token，防止旧 Props 的结果覆盖新 Props。
只检查 mounted 不足以解决同一 State 中的请求竞争。

### 8.2 active、隐藏与销毁

`active` 默认 true，表示宿主允许当前实例执行活动行为，不表示像素曝光、应用前台
或可见比例。A 在 Tab/Offstage/KeepAlive 场景中显式传递它；无法判断时不冒称自动检测。

`active: false` 时，包装层拒绝新 Action 分发；B 暂停轮询、动画或自动刷新等活动工作，
可以保留状态和已有缓存。是否取消已开始的数据请求由 B 按业务明确处理。
隐藏不会触发 dispose，恢复 active 不应无条件重建所有状态。
`deactivate` 可能只是 GlobalKey 移动，不作为终止生命周期。

### 8.3 Owner 与清理路径

| 资源 | Owner | 终止与清理 |
| --- | --- | --- |
| controller、Timer、局部订阅 | B 的 State | dispose；active 变化另按策略暂停 |
| A 的 Action callback 引用 | 包装 State | 更新时替换；dispose 后释放且禁止晚到分发 |
| 局部数据请求与缓存 | B 的 State | Props/Session 变化使旧结果失效；dispose 取消可取消请求 |
| 长期业务资源 | App/Session Service | 现有 Service Scope 关闭流程 |
| 工厂/契约与 UI binding | Host/Runtime binding | detach/shutdown 使绑定失效并清空持有引用 |

每条监听必须可追踪到 remove/cancel，每个 controller 必须有对应 dispose。
初始化失败、请求晚到和 callback 抛错都不能跳过清理。Dart Future 不保证可强制取消，
框架只保证失效结果不被接受；B 负责使用具体客户端的取消能力。

### 8.4 Action、Session 与 Runtime 终止

Action 分发要求实例仍 mounted、active 且 Runtime generation 未失效。
失效 Action 被丢弃并给出有界诊断，不重试、不转为全局 CCEvent。
当前 callback 抛错交由 Flutter 原事件错误路径处理，不吞掉或再次执行。
Action callback 的 Future 不作为 Fragment 事务或路由结果通道。

Session 切换时 B 必须清除旧账号展示状态、取消/失效旧请求并重新获取授权数据。
若 Host 以 Session identity 作为 Key，也可以明确重建实例，但框架不能猜测业务账号。
视图隐藏不是权限控制，所有业务调用仍由 Service 验证当前权限。

Host 应先卸载 UI 子树，再等待 Runtime shutdown。若 UI 尚挂载，binding 的 generation
必须失效，包装层拒绝后续 lookup/action，并在重新渲染时显示明确的 Runtime 不可用状态。
shutdown 不能直接调用 B 的 State.dispose；资源释放最终由实际 unmount 完成。
重新初始化后 Host 必须显式重挂 UI 子树（例如更新根 Key），旧 State 报
`runtimeGenerationMismatch`，不能静默迁入新 Runtime。旧 generation 的回调继续无效，
不能自动重放旧 Action 或复活已关闭的 Service。

### 8.5 Scope 与继承环境

Fragment 使用所在 Widget 树的 Theme、Locale、MediaQuery 和应用 Provider。
B 不依赖 A 的私有 Provider schema；必要输入进入 Props 或明确的公共契约。
Fragment 不建立额外 Scope。A 自己在确切 Route Context 内使用本地 Route Service
仍遵守现有规则；跨组件 Route-scoped Service Proxy 仍不因此获得支持。

## 9. 失败、诊断与可观测性

契约/装配错误 fail closed，不静默显示空 Widget，也不退回任意候选实现。
B 的业务加载错误由 B 展示 retry/empty/error UI；A 决定是否隐藏整个区域。
业务 fallback 不能掩盖 required 契约缺失。

| 错误类别 | 诊断语义 | 发现时机 |
| --- | --- | --- |
| 缺失或重复实现 | `missingImplementation` / `duplicateImplementation` | Host 聚合与初始化 |
| Owner/消费依赖错误 | `ownerMismatch` / `dependencyMissing` | 生成、Workspace 校验与初始化 |
| 版本或 shape 不兼容 | `versionOutOfRange` / `fingerprintChanged` | 生成、聚合与初始化 |
| 生成物过期或 Renderer 签名非法 | `staleGeneratedOutput` / `rendererSignatureMismatch` | 生成与检查 |
| 未绑定、已关闭或旧实例调用 | `runtimeUnavailable` / `runtimeGenerationMismatch` | mount、更新与 Action 分发 |

错误码属于独立 UI 诊断 family；Host 可读至多 128 条生命周期与 ignored Action 摘要，
没有逐帧日志或业务 payload。Renderer 同步 factory 抛错沿用 Flutter
build 错误报告；其后代的异步/布局/事件错误仍由各自错误路径处理。
不承诺一个通用 ErrorBoundary 可以捕获整棵 Flutter 子树的所有错误。

诊断只记录 component/contract identity、版本、generation 和错误码，不记录 Props、
Action payload、账号、Context、Widget 或 callback。只在绑定、mount/结束摘要及失败
边界产生有界记录，不逐帧记录 build；性能与点击/曝光仍使用既有显式 Analytics 能力。

## 10. 兼容性与现有功能影响

可选模块可以隔离运行路径，但不是零改造。影响主要集中在契约注解、Package Bundle、
Host 聚合、生成器 metadata 和依赖校验；不需要修改导航 dispatch 或 Service 类型规则。

当前 `CCContractKind` 包含 Route、Service、Command、Event、InitTask 五类。
直接增加 UI enum value 会影响调用方 exhaustive switch。v1 采用独立 UI descriptor /
requirement family，复用 SemVer 算法，不直接向旧 enum 追加成员。
新 metadata 必须显式标识 UI schema 版本；旧工具遇到声明 UI 的新元数据应报告升级要求，
不能静默忽略后声称装配成功。

UI shape fingerprint 覆盖 identity、Props 字段/类型/必填与默认语义、Action enum/sealed
成员及 payload schema；不能只 hash 类型名。Renderer 内部布局不作为 shape。
行为语义变化仍由 Owner 正确提升 SemVer，fingerprint 无法替代版本责任。

| 现有区域 | 兼容目标 | 必须验证 |
| --- | --- | --- |
| 无 UI 声明的组件 | 源码和生成行为保持 | 默认空字段、原文件路径、无新增 Flutter import |
| 五类旧 Contract | 既有描述与兼容行为保持 | baseline fingerprint 字节一致、原门禁测试 |
| Route/Shell/Outlet | 独立运行 | 路由回归，不增加隐式 RouteEntry/导航操作 |
| Service/Command/Event | 规则不放宽 | 非法 Flutter/function 类型仍被拒绝 |
| Host Assembly/启动失败 | 原子性保持 | UI 验证失败不留下部分 binding/registry |
| 工具与 DevTools | opt-in metadata 扩展 | 旧 fixture、版本拒绝与隐私回归 |

新增默认字段对普通调用可兼容，但生成 SPI、metadata 消费者和 Package 版本必须同步。
不能声明任意版本的新旧工具可以混用。具体最低版本和迁移说明在实现时形成。

## 11. 实施顺序与验证门禁（原计划，执行结果见验收记录）

### P0：冻结契约与基线

建立 A 消费 B 订单摘要的最小夹具，比较直接 Widget 方案与 UI 契约方案。
用编译夹具确认注解、DTO 白名单、Client 命名、导出路径与独立诊断 family。
冻结 Bundle capability bridge 或 UI Assembly wrapper 中的一种路径。
记录旧五类 fingerprint、无 UI 生成输出及启动/生成性能基线。

### P1：契约生成与静态校验

实现 Props/Action schema、依赖声明、Renderer 签名验证、Client 和 opt-in metadata。
覆盖非法类型、重复 identity、缺失依赖、Owner/版本错误与确定性生成测试。
验证旧生成 fixture 字节稳定，声明 UI 的 Package 对旧工具明确失败。

### P2：Host 装配与 UI binding

实现不可变 catalog、原子兼容验证和 Host/Runtime generation binding。
验证重复/缺失实现、失败回滚、shutdown/reinitialize、Host detach 与绑定隔离。
业务仅通过 generated Client；测试支持放在明确测试入口，不公开 Runtime 构造能力。

### P3：Widget 生命周期闭环

验证相同 Key 更新 Props 保留 State、Key 改变释放资源、多个实例状态隔离、callback 更新、
请求乱序与晚到结果、KeepAlive/隐藏/恢复、GlobalKey 移动、Session 切换和 Runtime 失效。
为实际拥有的资源增加释放计数或定向 leak tracking；未验证真实设备长期 Heap 时不宣称
已经证明无泄漏。对 idle 重建检查无重复 I/O、监听或全局实例缓存。

### P4：Demo 与接入指导

Demo 契约和组件放在 `demo/modules/`，平台目录保留在 Host。
至少演示订单摘要与推荐列表两个独立场景、列表中多实例、Tab KeepAlive 和业务 error UI。
完成后同步根 README、文档状态、Integration Skill 及相关 references、DartDoc；
对 Analyzer 的新诊断另按其独立验证与 Demo pin 流程实施，不冒称 IDE 已支持。

### P5：回归、试用与发布门禁

执行以下现有入口，并补齐新 UI 模块适用的 analyze/test 命令：

```bash
fvm flutter test packages/ccrouter_test/test
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test
fvm dart run tool/documentation_check.dart
fvm dart run tool/release_sensitivity_check.dart
```

从真实 Host `demo/` 执行生成检查和 Demo analyze/test；不要把仓库聚合根视作 Host。
依赖解析若必须在根执行，使用 `CCROUTER_PUB_HOOK_DISABLE=1 fvm flutter pub get`，
之后单独执行 `ccrouter generate demo --check`。
生成 fixture、测试数量、命令与平台 smoke 以实施时实际结果为准。

## 12. 灰度、回退与完成标准

优先独立提交契约/生成、装配、Widget 层和 Demo，维持无 UI 路径可单独验证。
生产首次接入只选一个局部区域，通过 Host 构建配置选择旧公共 Widget 路径或新 Fragment
路径，不能在运行中替换 catalog。比较资源释放、滚动/重建与交互表现，再扩大接入。
性能门槛以 P0 基线设定，不在没有测量时承诺固定启动或帧耗时。

回退应用接入时切回旧组合路径，并重新生成不含 UI 声明的 Assembly；回退框架版本前
必须同步恢复对应源码与生成物，不能仅降级运行库而保留新 UI metadata。
不引入持久化 schema 迁移或业务数据修改。

后续实施完成须同时满足：

- A 不导入 B 实现，B 可在不同 A/Host 中复用，单实例和多实例均经验证。
- 契约/依赖/版本/Renderer 错误有静态或初始化门禁，无静默 fallback。
- Flutter 生命周期、Session 与 Runtime generation 的清理和晚到保护有回归证据。
- 旧 Route、Service 及五类 Contract 的兼容目标和原子启动行为通过回归。
- 实际开发者指导、Demo、API 注释与能力状态同步，发布版本要求明确。

## 13. 后续扩展触发条件与代码依据

仅当多个生产区域都需要独立贡献者、排序、过滤和冲突规则时再设计 Slot。
动态注册与 Native UI 容器分别需要独立生命周期和平台协议，不从本方案推导为已支持。
Host-owned Route Mount 与 UI Fragment 可以独立实施，彼此不作为前置依赖。

实施复核入口：

- [Component 注解与依赖模型](../packages/ccrouter_contracts/lib/src/component.dart)
- [既有 Contract kind、SemVer 与兼容检查](../packages/ccrouter_contracts/lib/src/contract_compatibility.dart)
- [Package Bundle 与 Host Assembly](../packages/ccrouter/lib/src/generated_package_bundle.dart)
- [业务 API barrel](../packages/ccrouter/lib/ccrouter.dart)
- [Service Proxy 类型边界](CCRouter-service-proxy-generation-design.md)
- [生产场景演进流程](CCRouter-production-adoption-workflow.md)
- [框架开发与 API 隔离规则](../skills/ccrouter-framework-development/SKILL.md)
- [内存与生命周期审查](../skills/ccrouter-framework-development/references/memory-lifecycle-review.md)
