# CCRouter 类型化 UI Fragment 规范

本文统一维护 UI Fragment 的契约、Action schema、生成装配、生命周期与兼容规则。它适用于跨组件局部 UI；普通共享 Widget 继续放在公共 Flutter Package，完整页面使用 Route。

首次接入按[UI 接入指南](../skills/ccrouter-integration-development/references/ui-fragments.md)操作。实施过程、早期取舍与当时的验证数字保留在[合并前快照](archive/20261024-consolidation/CCRouter-ui-fragment-design.md)和[归档索引](archive/20261024-consolidation/README.md)；当前证据统一由[验证索引](validation/README.md)导航。本文不表示 API 已冻结或正式发布门禁已关闭。

## 1. 目标与 v1 非目标

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

## 2. Package、API 与依赖分层

### 2.1 分层

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

独立 UI 入口是新增的显式 API 层，接入必须遵守 Integration Skill 的 import 白名单。
它不意味着业务可以导入 `src` 或 Host/Generated SPI。

### 2.2 应用依赖方向

```text
A implementation ----> B public contracts + generated UI Client
B implementation ----> B public contracts + ccrouter_ui Renderer API
Host assembly -------> A/B generated package bundles + UI Host SPI
ccrouter_ui ----------> stable CCRouter SPI
```

B 的 Renderer implementation 不从公开 Contract barrel 导出。Host 聚合器可以导入实现
贡献，A 的生成 Client 只能依赖公开契约和 `ccrouter_ui`。普通共享 UI Package 不受此装配
流程约束。

## 3. 契约与消费 API

以下展示当前已实现的声明形式；应用类型和 Owner 常量由实际 contracts Package 提供。

### 3.1 B 声明 UI Contract

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

Action 也可使用与 Props 相同约束的单一不可变 DTO，以返回 B 私有加载的
selectedId/deviceId。该路径采用 UI schema 2 / Package Index schema 4；enum-only 保持原格式。
enum 改 DTO 需要 major SemVer 与 A/B/Host 重生成，sealed union 继续不支持。完整约束与验证
见 [Action schema 与兼容](#action-schema-与兼容)。

Contract marker 必须公开且非泛型；Props 为 final class，只提供 const generative constructor，
不含继承、mixin、interface 或自定义方法；enum Action 和 DTO 中的 enum 均只能声明枚举值，
不允许自定义字段、getter/setter、方法、构造器、mixin 或 interface（含 static 成员）。
DTO 构造器参数只允许 `this.field`；每个字段必须在声明处提供常量初始值，或由每个构造器的
`this.field` 初始化。参数默认值与字段初始值均按有效常量值计入指纹，等值表达式保持相同指纹。
v1 拒绝初始化列表赋值和重定向构造器，避免未建模的构造表达式绕过默认值兼容校验。
Props 字段仅支持 scalar、普通 enum 与无环嵌套 DTO（可空字段可用），不可包含集合、Widget、
BuildContext、controller、Service 实例、Future、Stream 或 function。
根 Action 必须为普通 enum 或上述受限 DTO，scalar 只允许作为 DTO 字段类型。
输入以 UI 所需最小数据为准，不把完整业务对象图或账号凭证传入视图。

v1 每份 Props 必须有明确字段 schema，所有存储字段公开且 final。不得在原对象中
修改字段期待 UI 自动刷新。更新应传入新的 Props；B 显式比较影响数据请求的字段。
复杂对象、通用外部库类型、递归 schema 和 sealed Action 暂不开放。

### 3.2 A 声明消费依赖

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

### 3.3 B 实现 Renderer

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

### 3.4 A 构建 Fragment

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

## 4. 生成与 Host 静态装配

### 4.1 生成路径

1. 解析 Contract 的 Owner、ID、版本、Props/Action schema 与 Renderer 签名。
2. 生成契约描述与 shape fingerprint、消费依赖和消费组件专属 Client。
3. B 的独立 UI 生成库输出 Renderer contribution；A 输出 UI requirement。
4. Host 聚合所有 contribution/requirement，构建不可变 UI catalog 并执行兼容门禁。
5. Runtime 初始化与 Host UI binding 使用同一份验证快照，避免验证与实际渲染不一致。

UI 使用显式 opt-in `<componentId>.ui.api.g.dart`，保持现有
`<componentId>.api.g.dart` 的路径和 Pure Dart 使用者依赖不变。具体导出位置与命名
由当前生成器确定。Client 名为完整 component ID 的 PascalCase 加 `Fragments`。
无 UI 声明的 Package 不新增 UI import、输出文件或 UI fingerprint 输入。

首次接入可使用非覆盖式 `create ui-fragment ... --dry-run`，再按打印步骤补齐四角色声明。
contracts、A、B 各包需自己的 `ccrouter_generator` dev dependency，Host 还需 `build_runner`；
Host 的声明不能代替成员包。生成后用 `find <ui-id> <host-root> --usage <consumer-id>`
查询公共 import 和真实 Client alias，并核对组件/UI 数量，不能仅凭退出码认定接入完成。
`ccrouter_ui` 是框架依赖，不需要业务组件 Portable State；外部分发业务组件仍需验证该状态。
完整命令和配置见[接入指南](../skills/ccrouter-integration-development/references/ui-fragments.md)。

### 4.2 避免反向依赖

实施选择 UI Assembly wrapper：`CCUIHostAssembly.attach` 先校验独立 Renderer/requirement
列表，再通过 Host-only `CCHostAssembly.withLifecycleBindings` 保留原 Assembly 的全部输入，
附加一个 `CCHostLifecycleBinding`。原 `CCGeneratedPackageBundle` 不新增 UI payload。
Core 只负责通用 binding 的 attach、初始化失败回滚和 shutdown detach，不理解 UI 工厂。
`ccrouter_ui -> ccrouter` 单向依赖；业务 `CCRegistry` 权限不变。
Host 仍只把最终的一个 Assembly 交给 `CCRouterHost.initialize`。

### 4.3 装配不变量

- 契约 identity 由 Owner component ID 与 contract ID 确定，实例 Key 不参与契约身份。
- required 契约必须且只能有一个 Renderer；重复、缺失、Owner 不匹配均拒绝启动。
- A 的消费声明、B 的实现和 Host 装配必须使用同一 schema 与兼容结果。
- catalog 只保存工厂和描述，不保存实例 Widget、State、Context 或消费 callback。
- Host 不能在运行中更改映射；A/B 对比通过不同 Host Assembly 构建选择实现。
- 替换实现仍属于同一 Owner 的部署选择；不能注册两个实现后“取第一个”。

## 5. 生命周期、并发与资源归属

### 5.1 实例身份与更新

包装 Widget 与 B 的内部 Widget 保持稳定类型。相同位置、类型和 Key 下，Flutter 保留
State；Props/active/callback 更新通过正常 Widget 更新路径传入。
Key 改变或树移除时由 Flutter dispose 旧实例。没有 Key 时遵循 Flutter 的位置身份，
列表重排必须由 A 提供稳定业务 Key；框架不能猜测业务 identity。
两个 Fragment 实例必须拥有独立 State，不缓存 Widget 来复用状态。

包装层只保存当前实例所需引用；callback 更新后，动作分发读取最新 callback。
B 的异步请求必须使用请求 revision/token，防止旧 Props 的结果覆盖新 Props。
只检查 mounted 不足以解决同一 State 中的请求竞争。

### 5.2 active、隐藏与销毁

`active` 默认 true，表示宿主允许当前实例执行活动行为，不表示像素曝光、应用前台
或可见比例。A 在 Tab/Offstage/KeepAlive 场景中显式传递它；无法判断时不冒称自动检测。

`active: false` 时，包装层拒绝新 Action 分发；B 暂停轮询、动画或自动刷新等活动工作，
可以保留状态和已有缓存。是否取消已开始的数据请求由 B 按业务明确处理。
隐藏不会触发 dispose，恢复 active 不应无条件重建所有状态。
`deactivate` 可能只是 GlobalKey 移动，不作为终止生命周期。

### 5.3 Owner 与清理路径

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

### 5.4 Action、Session 与 Runtime 终止

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

### 5.5 Scope 与继承环境

Fragment 使用所在 Widget 树的 Theme、Locale、MediaQuery 和应用 Provider。
B 不依赖 A 的私有 Provider schema；必要输入进入 Props 或明确的公共契约。
Fragment 不建立额外 Scope。A 自己在确切 Route Context 内使用本地 Route Service
仍遵守现有规则；跨组件 Route-scoped Service Proxy 仍不因此获得支持。

## 6. 失败、诊断与可观测性

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
边界产生有界记录，不逐帧记录 build；业务性能与点击/曝光由应用自有系统显式采集，框架不提供产品 Analytics。

## 7. 兼容性与现有功能影响

可选模块可以隔离运行路径，但不是零改造。影响主要集中在契约注解、Package Bundle、
Host 聚合、生成器 metadata 和依赖校验；不需要修改导航 dispatch 或 Service 类型规则。

当前 `CCContractKind` 包含 Route、Service、Command、Event、InitTask 五类。
直接增加 UI enum value 会影响调用方 exhaustive switch。v1 采用独立 UI descriptor /
requirement family，复用 SemVer 算法，不直接向旧 enum 追加成员。
新 metadata 必须显式标识 UI schema 版本；旧工具遇到声明 UI 的新元数据应报告升级要求，
不能静默忽略后声称装配成功。

UI shape fingerprint 覆盖 identity、Props 字段/类型/必填与默认语义、Action enum 成员或
受限 DTO payload schema；不能只 hash 类型名。sealed Action 尚不支持，Renderer 内部布局不作为 shape。
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
不能声明任意版本的新旧工具可以混用。enum-only 保留 UI schema 1 / Package Index 3，
DTO 使用 UI schema 2 / Package Index 4；混合文档声明所需最高版本。
enum 改 DTO 需要 major Contract SemVer、消费范围更新和 A/B/Host 重生成；
配套来源与验证边界见[Action schema 与兼容](#action-schema-与兼容)。

## Action schema 与兼容

| 方案 | 收益 | 代价与决定 |
| --- | --- | --- |
| 保持 enum，使用普通 Widget | 无框架改动，支持普通数据型 callback | 缺少 Fragment 契约版本和静态实现装配；继续支持这种选型 |
| 允许单个不可变 DTO Action | 两个单一选择结果可直接表达；复用 Props schema 校验 | 新增兼容和生成规则；当前支持此范围 |
| sealed union Action | 多种动作携带不同 payload，可避免非法字段组合 | 类型闭包、穷尽性、指纹和代码生成成本更高；以真实异构动作需求触发 |
| Object、Map 或任意 callback | 表面上通用 | 丢失静态契约与兼容证明，不采用 |

当前范围：保留 enum；新增 public final class、const 生成构造器和 public final 存储字段的
单 DTO Action。示意结果是 `RecommendationSelected(selectedId: ...)`，而不是多个动作共享
`kind + nullable fields`。Generator 与 Plugin 均识别该受限类型。
根 Action 只允许普通 enum 或受限不可变 DTO；scalar 不能直接作为 Action。
DTO 字段仅接受受限 Pure Dart scalar、普通 enum 和嵌套 DTO，继续排除 Flutter 对象、Object/dynamic、
函数、Future/Stream、泛型集合及带行为成员的类型。对多种异构输出先评估 union，
不把单 DTO 宣称为已解决全部 Action 建模。

### 契约、版本与发布

- 业务仍通过自身生成 Client 的 `onAction` 收到精确类型；不新增字符串 dispatcher、全局
  payload store、Event 桥接或业务可访问的 Host/Registry。
- enum-only 契约保留 UI schema 1 及原指纹算法和生成签名，作为兼容对照。
- DTO Action 使用 UI schema 2；涉及该形状的 Contract、Renderer 和 consumer metadata
  都带匹配版本。混合文档应声明其所需最高 UI schema；旧 Generator 必须明确拒绝。
  DTO Package Index 升至 schema 4：真实旧 schema 3 读取器会直接接受 Index 3 的 metadata，
  因此仅改变内部 UI 版本不能保证只读查询拒绝新能力。旧读取器已验证明确拒绝 Index 4。
- Action 字段类型、nullable、构造参数/default、嵌套类型与公共导出纳入 shape fingerprint。
  指纹记录形状，不包含运行时业务值。enum 改为 DTO 是破坏性契约变更，需要 major SemVer，
  更新消费范围并重生成 A/B/Host；不会自动把原 enum 解释成 DTO。
- Generator、Analyzer、运行时 UI 包和分发来源必须按验证过的组合发布；不静默升级 SDK
  或 analyzer 约束。新 Plugin 行为仍走独立提交、远程 SHA、Demo pin 两阶段流程。

### 所有权、时序与失败

- B 创建不可变 Action 值；A 的实例局部同步 callback 接收值并决定业务操作。
  Action 不持有 Context、State、资源所有权或释放句柄，不需要框架 dispose。
- 保持 mount、active、Runtime generation 防护。隐藏时停止分发；卸载、shutdown 或
  旧 generation 的 callback 不得影响新挂载。恢复后不重放期间丢弃的 Action。
- 保持现有“调用最新 callback”语义。Props 更新本身不代表旧请求结果仍有效；B 根据
  请求相关 Props 和 revision 取消工作或丢弃旧结果。A 若有异步决策，也需检查当前账号/实例。
- Session 变化由应用清理私有数据、失效请求或更换子树 Key；不在 payload 中隐式引入
  框架 Session、Fragment Scope 或导航结果 Future。
- callback 抛错遵循现有 Flutter 错误处理，不吞错、不重试、不转 Event。
  加载失败、空列表、取消、超时与重试仍由 B 的业务 UI 和请求所有者处理。
- catalog、诊断、Trace 不保存 payload、selectedId、Context 或 callback。热路径直接传递
  类型化值，无 JSON 编解码；跨进程、持久化及 Deep Link 不在范围内。


## 验证与扩展边界

[独立首次接入技术验证](validation/ui-fragment-adoption-20261020/README.md)保留 enum/DTO 两条路径的复现源码、日志和条件化成本；它不等于未参与实现者的可用性研究。历史实施验收、易用性审查及 Action 增量记录统一保留在[归档索引](archive/20261024-consolidation/README.md)。

回归至少覆盖无 UI 组件兼容、required Owner/Renderer、指纹与旧 schema 拒绝、多实例/重排、Props 竞争、最新 callback、active、Runtime generation、卸载后晚到 Action 和引用释放。UI DevTools Catalog、集合、sealed Action、动态 Slot 与热替换尚未支持。新能力按[后续工作与触发条件](CCRouter-future-work-plan.md)评估；API 冻结、正式分发、平台矩阵与长期性能门禁只在[Release Readiness](CCRouter-release-readiness.md)维护。
