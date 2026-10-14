# CCRouter Host-owned Route Mount 设计与实施计划

## 文档状态

- 版本：v0.1
- 日期：2026-10-13
- 状态：Proposal 已确认，尚未实现
- 分类：新的通用框架能力（生产场景分类 E）
- 适用范围：Contract-first Route、单 Host、Shell/StatefulShell/Outlet、GoRouter Backend
- 当前公开能力：不包含 Host-owned Route Mount；现有静态 `CCRoutePlacement` 行为保持不变

本文定义后续实施 Host-owned Route Mount 的边界、API 草案、兼容策略和验收门禁。
文中的类型与示例均为设计目标，不代表当前代码已经提供对应 API。当前 Route、Shell、
Outlet 和 Host 语义继续以
[路由子系统设计](CCRouter-route-design.md)、
[路由契约设计](CCRouter-route-contract-design.md)和
[混合路由设计](CCRouter-hybrid-routing-design.md)为准。

## 1. 生产场景与问题分类

### 1.1 场景

组件 B 提供一个可复用的完整页面。某个应用需要把该页面作为组件 A 的固定 Tab 内容，
并要求：

- A 不导入或构造 B 的页面 Widget；
- B 页面仍是 CCRouter Managed Route；
- B 保留 typed Intent、参数、结果、Interceptor、PopGuard、Trace 和 Route Scope；
- Tab 切换保留独立 Navigator 历史和 Widget State；
- Deep Link 可以定位 B 页面并激活对应 Tab；
- B 在其他 Host 中仍可被放在不同 Shell/Outlet，或作为独立页面使用。

### 1.2 当前能力映射

现有 `CCRoutePlacement`、`CCShellDefinition`、`CCGoRouterShellBinding` 和
`StatefulShellRoute` 已能表达固定 Shell/Outlet。问题在于 placement 由 Route Contract
静态声明，并进入 Route shape fingerprint。若 B 直接声明 A 的 `shellId` 和
`navigatorOutlet`，会形成以下错误依赖方向：

```text
A component ---- consumes ----> B Route Contract
B Route Contract ---- knows ----> A Shell / Outlet
```

当 A 同时需要调用 B 的 typed Intent 时，这个关系容易变成 Package 循环依赖。即使通过共享
常量 Package 消除编译循环，B 仍被某个具体 Host 拓扑绑定，无法保持可复用性。

### 1.3 分类

该问题不是页面 Widget 注入需求，也不是现有 Shell/Outlet 的实现缺陷。它是 Route 业务契约与
Host 导航拓扑缺少独立组合层，分类为新的通用框架能力。

## 2. 目标与非目标

### 2.1 目标

- 让 Route Owner 声明“该 Route 必须由 Host 分配 Outlet”，但不引用具体 Shell。
- 让 Host 在 Runtime 初始化前把 Route 挂载到一个确定的 Shell/Outlet。
- Runtime、Flutter Catalog 和 Backend 使用同一个 effective placement。
- 保持现有 fixed Route 的源码、生成物、shape fingerprint 和运行行为不变。
- 配置错误在初始化或 Adapter attach 前 fail closed，不回退到 root Outlet。
- Mount 配置不可变，生命周期与 `CCHostAssembly` 一致。
- 保持业务调用方式不变：调用方仍只使用 generated Intent 和
  `CCRouter.navigator`。

### 2.2 v1 非目标

- 不向 A 暴露 B 的 Widget、WidgetBuilder、Navigator 或 Adapter 对象。
- 不支持运行时添加、删除、移动或重新排序 Route Mount。
- 不支持动态组件 activate/deactivate/install/uninstall。
- 不允许 Host 覆盖 Route ID、Pattern、参数、返回类型、Presentation、Deep Link、
  Interceptor 或 PopGuard。
- 不允许覆盖 `parentRouteId`；跨 Route 父子树组合另行设计。
- 不允许覆盖 `hostId`；v1 只支持单 Host 下的 Shell/Outlet 组合。
- 不自动生成 Tab UI、标签、图标、排序、权限或业务可见性规则。
- 不让生成器推断 GoRouter Shell 树；Host 仍显式拥有 Backend 拓扑。
- 不支持页面局部 UI Fragment；局部内容继续使用普通 Flutter 组合或 Service 数据契约。

## 3. 设计原则

### 3.1 新增路径，不改写旧语义

现有 Route 默认保持 `fixed`。只有 Route Owner 显式声明 `hostAssigned`，Host 才能为它提供
Mount。禁止 Host 移动 fixed Route，避免应用升级框架后出现静默导航变化。

### 3.2 声明与部署分离

Route Contract 继续拥有业务语义：地址、参数、结果、Presentation 和策略。Host Mount 只拥有
部署语义：目标 Shell 和 Navigator Outlet。

### 3.3 单一 effective topology

Mount 不能只修改 Flutter Catalog 或只修改 Runtime。`CCHostAssembly` 必须在初始化前产生一个
不可变的 effective topology snapshot，并让 Runtime Route Registry 与 Host Route Catalog
共同消费该快照。

```text
Route Contract/Definition       Host Route Mount
           |                           |
           +-----------+---------------+
                       |
              CCHostAssembly resolve
                       |
             effective topology snapshot
                    /         \
          Runtime Registry   Flutter Catalog
                    \         /
                 Navigation Backend
```

### 3.4 Fail closed

缺失、重复或非法 Mount 不能静默退回 `root`。如果 effective placement 无法被唯一证明，
Runtime 不得进入 ready 状态，Backend 不得执行导航。

## 4. API 草案

### 4.1 Route Mount Policy

在 `ccrouter_contracts` 增加组件作者 API：

```dart
enum CCRouteMountPolicy {
  fixed,
  hostAssigned,
}
```

`@CCRouteContract` 增加默认值为 `fixed` 的字段：

```dart
@CCRouteContract<void>(
  componentId: componentBId,
  id: 'component_b.main',
  pattern: CCPathPattern('/component-b'),
  mountPolicy: CCRouteMountPolicy.hostAssigned,
)
abstract class ComponentBMainRouteContract {
  const ComponentBMainRouteContract();
}
```

v1 只允许 Contract-first Route 使用 `hostAssigned`。页面级内部 `@CCRoute` 保持 fixed，避免
Host 依赖组件内部 Route ID，后续只有出现独立生产场景才扩展。

生成器规则：

- `fixed` Route 保留现有 `CCRoutePlacement` 规则；
- `hostAssigned` Route 的 authored placement 必须是默认 root；
- `hostAssigned` 与显式 `hostId`、`parentRouteId`、`shellId` 或 named Outlet 同时出现时构建失败；
- `CCRouteImplementation` 继承 Contract policy，不能覆盖；
- generated `CCRouteDefinition` 和 `CCNavigationRoute` 携带 policy，业务 Intent 不暴露 Mount。

### 4.2 Host Route Mount

在 `ccrouter_host.dart` 增加 Host/Adapter SPI：

```dart
final class CCHostRouteMount {
  const CCHostRouteMount({
    required this.routeId,
    required this.shellId,
    required this.navigatorOutlet,
  });

  final String routeId;
  final String shellId;
  final String navigatorOutlet;
}
```

`CCHostAssembly` 提供返回新快照的 Host-only 配置入口：

```dart
final hostAssembly = ccrouterGeneratedHostAssembly.withRouteMounts(
  const [
    CCHostRouteMount(
      routeId: ComponentBMainRoute.id,
      shellId: 'component_a.tabs',
      navigatorOutlet: 'component_a.tabs.b',
    ),
  ],
);

CCRouterHost.initialize(hostAssembly: hostAssembly);
```

该方法不修改原 Assembly，不修改 generated Package Bundle，也不允许 Runtime ready 后变更。
Feature Package 不得导入 `ccrouter_host.dart` 或创建 Mount。

v1 使用显式 Dart Host 配置，不扩展 `ccrouter.yaml`。原因是当前 Shell Definition 可以来自
`CCComponentContribution`，生成器无法仅凭 YAML 完整证明 Shell/Outlet。后续只有在 Shell 也
具备稳定生成元数据时，才评估 YAML 或 CLI scaffold。

### 4.3 Assembly 内部快照

`CCHostAssembly` 需要保留：

- authored Route Catalog；
- 规范化并按 Route ID 排序的 Mount 表；
- 应用 Mount 后的 effective Route Catalog；
- 一个只覆盖拓扑稳定 ID 的 `topologyFingerprint`。

`CCRouterHost.initialize` 必须把同一份 Mount 表传给 Runtime，并把同一 Assembly 的 effective
Catalog 保存到 Host Binding。禁止 Runtime 和 Catalog 分别重复解释 Host 配置。

## 5. Placement 解析与优先级

### 5.1 Fixed Route

现有行为完全保留：

1. Route 声明显式 placement 时，声明值生效；
2. Route 使用默认 root 且调用方传入 `BuildContext` 时，可以使用现有 call-site Outlet；
3. 没有 Context 时使用默认 Host/root 行为。

Host Mount 不得匹配 fixed Route。

### 5.2 Host-assigned Route

解析顺序固定为：

1. 根据 `routeId` 读取唯一 Host Mount；
2. 生成 effective `CCRoutePlacement`；
3. 忽略业务调用点的 Outlet Context，防止同一 Route 被临时重定向到其他 Tab；
4. Interceptor redirect 或 Failure Policy 跳转按目标 Route 自己的 policy 重新解析；
5. defer/resume 保留原 effective Host/Outlet，不在恢复时重新选择拓扑。

由于 v1 不允许覆盖 `hostId` 和 `parentRouteId`，effective placement 为：

```dart
CCRoutePlacement(
  hostId: 'default',
  shellId: mount.shellId,
  navigatorOutlet: mount.navigatorOutlet,
)
```

## 6. 初始化与数据流

### 6.1 Assembly 阶段

`withRouteMounts` 执行不依赖 Runtime 的确定性校验：

- Route ID 格式合法；
- Route 存在于 Catalog；
- Route policy 是 `hostAssigned`；
- 一个 Route 只出现一次；
- Shell/Outlet ID 格式合法；
- 每个 `hostAssigned` Route 恰好存在一个 Mount；
- 原 Assembly 尚未应用另一组 Mount。

此阶段尚不能证明 Shell/Outlet 存在，因为 Shell 可以由组件 Registrar 在 Runtime 配置阶段
注册。

### 6.2 Runtime 配置阶段

Runtime Route Registry 接收不可变 Mount 表。所有组件完成注册后、Adapter capability 校验前：

1. 对 fixed Route 使用 authored placement；
2. 对 host-assigned Route 查找 Mount 并生成 effective placement；
3. 使用现有 Shell Registry 校验 Shell 和 Outlet；
4. 缓存 `routeId -> effective placement`；
5. parent cycle 校验只处理 fixed Route；v1 Mount 不产生 parent；
6. Adapter-facing `CCNavigationRoute` 从缓存读取 effective placement。

Route Definition 保留 authored placement 和 policy，不被克隆或修改。`_PreparedRoute`、
`CCNavigationRequest`、Route Entry、并发键、Aspect、诊断和生命周期统一使用 effective
placement。

### 6.3 Host Catalog 阶段

Assembly 为每个 host-assigned destination 复制 adapter-neutral `CCNavigationRoute` 元数据并
替换为 effective placement；页面 builder 保持同一个引用。fixed destination 不复制、不变化。

Host Binding 只能暴露 effective Catalog。Backend 不得读取 authored Catalog 后自行叠加 Mount。

### 6.4 GoRouter Backend 阶段

Host 继续显式创建 `ShellRoute` 或 `StatefulShellRoute`、Navigator Key、Outlet Observer 和
`CCGoRouterShellBinding`。Mount 不负责绘制 Tab，也不推断 branch 顺序。

GoRouter 组装使用 effective Catalog：

- mounted Route 仍需要 `CCGoRouterRouteOverride(includeInRootRoutes: false)`；
- Host 把生成的 GoRoute 放入 Mount 指定的 branch；
- Adapter 初始化时比较 Route effective placement、Shell Binding 和 Outlet Key；
- Route 未物理挂入对应 branch 时必须报配置错误，不能同时保留 root Route。

第一阶段可以复用 Demo 现有的 Catalog destination mount helper；若实现中出现重复 glue，再将其
收敛为 `ccrouter_go_router` Host helper。不得为减少几行 Host 代码而提前引入通用 Router DSL。

## 7. Contract 与生成兼容性

### 7.1 Existing fixed Route

现有 fixed Route 的 fingerprint 输入必须逐字节保持不变。生成器不得因为增加默认
`mountPolicy: fixed` 就向旧 fingerprint payload 写入新字段。

现有注解源码不需要修改，旧 Host 不需要调用 `withRouteMounts`，生成后的 Route Definition、
Catalog 和 Runtime 行为不变。

### 7.2 New host-assigned Route

只有 `hostAssigned` 才向 shape fingerprint 增加非默认 policy。具体 Host 的 `shellId` 和
`navigatorOutlet` 不属于 Route Contract fingerprint；它们进入 Host topology fingerprint。

把已有 public Route 从 fixed 改为 hostAssigned 会改变部署语义和 Contract shape，必须升级
Route Contract 版本。0.x 阶段消费者继续使用精确版本和 fingerprint 校验。

### 7.3 Generated package identity

Route policy 属于 Package generated content，进入 Package `contentFingerprint`。手写 Host Mount
发生在 Package Bundle 合并之后，不改写依赖 Package identity；Assembly 单独计算 topology
fingerprint，用于诊断、测试和 stale Host 对比。

Portable Generation State 在 v1 不缓存手写 Mount。未来若 Mount 进入生成配置，必须同时加入
portable source/content 摘要，不能复用忽略 topology 的旧缓存。

## 8. 错误语义与诊断

增加稳定的 Host Route Mount 配置错误类型。错误至少区分：

| Code | 阶段 | 语义 |
| --- | --- | --- |
| `invalidIdentity` | Assembly | Route、Shell 或 Outlet ID 非法 |
| `unknownRoute` | Assembly | Catalog 中不存在目标 Route |
| `routeNotHostAssigned` | Assembly | Host 尝试移动 fixed Route |
| `duplicateMount` | Assembly | 同一 Route 被挂载多次 |
| `missingMount` | Assembly/Runtime | host-assigned Route 没有 Mount |
| `declaredPlacementConflict` | Generation/Runtime | host-assigned Route 同时声明静态 placement |
| `unknownShell` | Runtime | Mount 指向未注册 Shell |
| `unknownOutlet` | Runtime | Shell 不包含目标 Outlet |
| `backendBindingMismatch` | Adapter | 物理 GoRouter branch 与 effective placement 不一致 |
| `unsupportedMultiHost` | Adapter | v1 Mount 被用于 Multi-host Backend |

错误必须包含稳定 Route/Shell/Outlet ID，不包含 URI 参数、Extra、Widget、Navigator、异常原文或
业务返回值。

初始化诊断可记录：

- Mount 数量；
- topology fingerprint；
- Route ID、Shell ID、Outlet ID；
- 校验阶段和稳定失败码。

DevTools 后续应显示 declared policy、effective placement 和 `source: hostMount`，但保持只读，
不能提供 remount 控件。

## 9. 生命周期、并发与导航语义

### 9.1 Owner 与生命周期

| 对象 | Owner | 生命周期 |
| --- | --- | --- |
| Route Contract/Implementation | 组件 B | Package/Runtime 注册 |
| Shell Definition 和视觉容器 | 组件 A 或 Composition Component；视觉树由 Host 装配 | Runtime/Host |
| `CCHostRouteMount` | Host Composition Root | Assembly snapshot |
| effective topology | Runtime 与 Host Binding 共同消费的不可变快照 | Runtime |
| Route Entry/Route Scope | Runtime | mounted Entry 永久移除时结束 |

Mount 不持有 BuildContext、Widget、Navigator、Controller、Listener、Timer 或 Subscription，
因此没有独立 dispose。Tab 切换只改变 PageShow/PageHide；StatefulShell 保留的 B Entry 和
Route Scope 不因 PageHide 被销毁。

### 9.2 并发

effective placement 必须在创建 navigation concurrency key 之前解析。两个不同 Outlet 中的请求
不能因 declared root placement 被错误合并。Mount 表初始化后不可变，因此不需要锁或运行时
更新协议。

### 9.3 Deep Link、Redirect 和 Deferred Navigation

- Internal URI 与受信任 Deep Link 先按现有 Pattern/Policy 匹配 Route，再应用该 Route 的 Mount；
- Deep Link 到 mounted Route 时由 Backend 激活目标 StatefulShell branch；
- Redirect 目标使用目标 Route 的 Mount，不能继承来源 Route 的 Outlet；
- call-site Context 不覆盖 host-assigned Mount；
- Deferred Navigation 保存 effective placement，并在恢复时验证 Route/arguments，但不重新选择
  Shell/Outlet；
- Runtime shutdown 继续取消 pending navigation，Mount 不延长任何 Future 生命周期。

### 9.4 Pop 与结果

mounted Route 的 Pop、maybePop、PopGuard 和 typed result 语义不变，只是 active pop target 使用
effective Outlet。Foreign Popup 或其他 Outlet 的 Top Route 不得关闭 B 的 Route Entry。

## 10. Multi-host 边界

v1 明确拒绝 `CCGoRouterMultiHostBackend` 使用 host-assigned Route。原因是当前默认 `hostId`
会被 Multi-host Adapter 解释为 active Host，而不同 Host 未必拥有相同 Shell/Outlet。静默复制
Mount 到所有 Host 会破坏隔离。

后续只有满足以下条件才设计 Host-aware Mount：

- Mount 显式声明稳定 `hostId`；
- Host Assembly 能验证目标 Host 拓扑；
- Deep Link 和 active Host 切换规则明确；
- Host 卸载、pending navigation 和 Route Scope 不发生隐式迁移；
- 同一 Route 是否允许多个 Host 实例具有确定的 Route Entry identity 语义。

在此之前，多 Host 页面继续使用现有 fixed placement。

## 11. 候选方案对比

| 方案 | 收益 | 缺点/风险 | 结论 |
| --- | --- | --- | --- |
| A 直接导入 B Widget | 成本低 | 破坏组件边界和 Managed Route 语义 | 拒绝 |
| B 静态声明 A Shell | 使用现有能力 | B 反向依赖 A，无法跨 Host 复用 | 仅固定应用可用 |
| Host 任意覆盖所有 placement | API 表面简单 | breaking change，容易静默搬迁 Route | 拒绝 |
| 显式 `hostAssigned` + Host Mount | 依赖方向正确、可校验、可回滚 | 需要贯通 Generator/Core/Host/Backend | 推荐 |
| 动态 UI Contribution Registry | 支持插件式 Tab | 排序、恢复、权限、生命周期和 Widget 泄漏复杂 | 暂缓 |

## 12. 实施阶段

### P0：边界测试和基线

- [ ] 建立 A Shell Component、B Contract/Implementation Component 的最小 fixture；
- [ ] 记录当前静态 placement 导致 B 依赖 A topology 的复现；
- [ ] 固化现有 fixed Route generated output 和 fingerprint golden；
- [ ] 固化现有 Context Outlet、Deep Link、defer/resume、StatefulShell 生命周期回归。

### P1：Contract 与 Generator

- [ ] 增加 `CCRouteMountPolicy`，默认 fixed；
- [ ] 仅允许 `@CCRouteContract` 声明 hostAssigned；
- [ ] 为 `CCRouteDefinition`、`CCNavigationRoute` 和 metadata 增加 policy；
- [ ] 保证 fixed Route fingerprint 和既有 generated fixture 不变；
- [ ] 增加 annotation、workspace metadata 和 stale output 校验；
- [ ] 更新生成文档，但不把 Host Mount 标记为已支持。

### P2：Host Assembly 与 Runtime

- [ ] 增加 `CCHostRouteMount` 和 immutable `withRouteMounts`；
- [ ] 增加 topology normalization、fingerprint 和 Assembly 前置校验；
- [ ] Runtime Route Registry 接收 Mount 表并缓存 effective placement；
- [ ] Runtime/Catalog 共用同一解析结果；
- [ ] 增加稳定错误码和脱敏初始化诊断；
- [ ] 验证 Context、Redirect、Failure Policy、defer/resume 和 concurrency precedence。

### P3：GoRouter Backend

- [ ] 让 managed/attach Backend 只消费 effective Catalog；
- [ ] 校验 RouteOverride、ShellBinding、Outlet Key 和物理 branch 一致；
- [ ] Deep Link 激活正确 branch；
- [ ] 明确拒绝 v1 Multi-host Mount；
- [ ] 仅在重复明显且边界稳定时增加 Host mount helper。

### P4：跨组件 Demo 与生命周期验证

- [ ] 在 `demo/modules/` 建立独立 A/B 组件场景；
- [ ] A 不导入 B 实现 Package，B 不依赖 A Shell Contract；
- [ ] Host 同时装配 A Shell 与 B Route Mount；
- [ ] 覆盖 Tab 状态保留、B 内部 push/pop、Back、PopGuard、typed result 和 Deep Link；
- [ ] 验证 PageHide 不 dispose Route Service，Entry 移除和 shutdown 正确清理；
- [ ] 保留现有静态 Shell Demo 作为并行对照和回滚路径。

### P5：文档、工具与发布门禁

- [ ] 更新根 README 当前能力、Host/Shell/Outlet 和示例；
- [ ] 更新 integration Skill 及 implementation/review references；
- [ ] 更新 Route Design、Contract Design、Annotation Validation 和 Demo 文档；
- [ ] 根据公开行为决定 Catalog/DevTools/Analyzer 的只读诊断；
- [ ] 执行 release sensitivity 和文档一致性检查；
- [ ] 实现、验证和文档同一变更完成后，才把本文件状态改为“已实现”。

## 13. 测试矩阵

### 13.1 Generator

- fixed Route 旧 fixture 输出和 fingerprint 完全不变；
- hostAssigned policy 正确进入 Definition、Catalog metadata 和 fingerprint；
- hostAssigned + 显式 placement 构建失败；
- `@CCRoute` 使用 hostAssigned 构建失败；
- Contract/Implementation policy 不一致或 stale output 被拒绝。

### 13.2 Assembly 与 Runtime

- 空 Mount 表对只含 fixed Route 的 Host 零行为变化；
- unknown、duplicate、missing、fixed Route Mount 分别返回稳定错误码；
- unknown Shell/Outlet 在 Runtime ready 前失败；
- typed Intent、URI open、Deep Link、redirect 和 recovery 使用 effective placement；
- call-site Context 不能覆盖 hostAssigned Mount；
- pending resume 保留原 Host/Outlet；
- navigation concurrency key 使用 effective Outlet；
- Adapter capability 检查能识别新增的 nested placement。

### 13.3 GoRouter 与 Flutter

- B 页面首次进入时激活目标 Tab；
- A -> B -> A -> B 后各分支 Navigator 栈和 Widget State 保留；
- B 分支内的详情 push/pop 不进入 A 分支；
- system back、predictive back、Cupertino gesture 和 PopScope 保持现有语义；
- PageShow/PageHide 只反映 active Outlet；
- Route Scope 只在 B Entry 永久移除后 dispose；
- Foreign Dialog/Overlay 不误关闭 B Entry；
- 物理 branch 与 Mount 不一致时初始化失败；
- Multi-host 使用 hostAssigned 时显式失败。

### 13.4 回归命令

实现阶段至少执行：

```text
dart format packages/*/lib
dart analyze
fvm flutter test packages/ccrouter_test/test
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test
fvm flutter analyze demo
fvm flutter test demo/test
fvm dart run ccrouter_generator:ccrouter generate demo --check
fvm dart run tool/documentation_check.dart
fvm dart run tool/release_sensitivity_check.dart
```

Analyzer Plugin 若未修改 production behavior，不需要更新 Demo bootstrap pin；若新增对应
diagnostic 或 Quick Fix，则必须遵循独立 Plugin 提交、推送、远端 SHA pin 和真实 IDE 验证流程。

## 14. 性能、内存与隐私

- Assembly/Runtime 初始化增加 O(Route + Mount) 的 Map 构建与校验；
- 导航热路径只进行 `routeId -> effective placement` 的 O(1) 读取；
- 不在每次 build 或 frame 中计算 topology；
- Mount 和 effective placement 都是小型不可变值，不持有 Widget 树或生命周期资源；
- topology diagnostic 只包含稳定 ID 和计数，不记录完整 URI、参数、Extra、Token 或业务对象；
- 性能基线应比较空 Mount Host、固定 placement Host 和 hostAssigned Host 的初始化时间，
  不把单次本机结果当作发布承诺。

## 15. 灰度、回滚与提交拆分

### 15.1 灰度

- 能力默认关闭：没有 hostAssigned Route 和 `withRouteMounts` 时不进入新路径；
- Demo 保留原静态 placement 场景，与新跨组件场景并存；
- 生产应用先迁移一个无复杂返回值的固定 Tab，再扩大范围；
- 首轮不迁移 root、登录、支付或跨 Host 关键入口。

### 15.2 回滚

- fixed Route 旧路径始终保留；
- Host 可移除 `withRouteMounts` 并恢复对应 Route 的静态 placement；
- 不涉及持久化 Schema、数据迁移或远程协议；
- 不允许运行中的 Runtime 从 hostAssigned 回滚为 fixed，回滚通过重新构建并重启应用完成。

### 15.3 建议提交顺序

1. 设计文档与失败 fixture；
2. Contract/Generator policy 与兼容 golden；
3. Assembly/Core effective topology；
4. GoRouter Backend 校验；
5. A/B Demo 与生命周期回归；
6. README、Skill、设计状态和 release gate 更新。

各提交应可独立分析和测试。生产接入与框架修改不得混入同一提交，也不得通过导入 `src` 或
修改 Pub cache 提前使用未完成能力。

## 16. 完成标准

只有同时满足以下条件，Host-owned Route Mount 才能从 Proposal 改为已支持：

- 现有 fixed Route generated golden 和 Contract fingerprint 无变化；
- Runtime 与 Catalog 对每个 Route 得到完全一致的 effective placement；
- A/B 组件之间不存在页面实现依赖或反向 Shell 依赖；
- 成功、配置失败、Deep Link、Back、生命周期、并发和 shutdown 均有自动化覆盖；
- GoRouter 物理 branch 与 Mount 不一致时 fail closed；
- Multi-host 限制有明确错误而不是静默降级；
- Demo、README、Integration Skill、API DartDoc 和设计状态与实现一致；
- 生产接入可移除，框架改动可独立回退。

