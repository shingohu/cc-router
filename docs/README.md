# CCRouter 文档索引与能力状态

## 状态说明

- 2026-10-24 文档合并：DevTools/Service/返回手势/UI/Analyzer/Managed 路由的重复规则已归并，未完成工作与发布门禁分开维护。18 份合并前快照与映射见[归档索引](archive/20261024-consolidation/README.md)，旧路径仅保留导航页。

- 2026-10-24 文档收口：统一 Managed-only、Route Scope 退出渲染期、业务异步返回确认及
  Deep Link push/go 语义。当前源码与历史平台证据分列于[验证索引](validation/README.md)。
  最近源码回归为[外部导航等待与所有权修复](validation/20261024-backend-wait-fixes/report.md)：
  Flutter 1537 项、Dart 55 项、Generator API 隔离专项 4 项通过；不是全平台重新验收。

- 2026-10-23 产品埋点移到应用侧 `demo_analytics` / `demo_analytics_flutter`，公开类型
  使用 `AppAnalytics…`，测试与 benchmark 一并迁移。框架只提供导航观察和诊断，详见
  [应用侧埋点边界](CCRouter-analytics-and-auto-track-design.md)。

- 2026-10-23 已移除 GoRouter 兼容包和依赖，当前 Host 使用原生 Managed；见
  [退役与回归记录](validation/go_router_retirement_20261023.md)。精确 close 支持声明式、
  覆盖页和 retained branch，并保留覆盖 foreign Popup。历史 GoRouter 报告仅作历史证据。
  此项不扩大真实平台、浏览器历史或原生多窗口验收结论。
- 精确实例语义见[精确 RouteEntry 关闭](CCRouter-targeted-close-design.md)，已打开页面的
  策略失效处理见[路由重验证](CCRouter-route-revalidation-design.md)。

- 2026-10-20 的[最近提交审查与核心价值回归](CCRouter-core-principles-audit.md)复核最近 10 个提交与
  13 条约定；两处生成身份问题和一处 CLI 文档漂移已修复，附修复前后验证及性能边界；
  生成器首次全量有一项超时，单项复跑通过，不记作首次全绿。

- 较早全量文档对齐记录：2026-10-07。
- 较早增量对齐记录：2026-10-16，覆盖 Host-only 生命周期、类型化 UI Fragment、默认路由族、
  Android 预测返回自动桥与丢失终态恢复、watch 初始化失败清理；不表示重新执行全平台验收。
- UI 专项文档收口：2026-10-20，统一 enum/受限 DTO、接入工具、独立技术验证及历史记录；
  不表示公开 API 已冻结，也不扩大正式发布或平台验收结论。
- 2026-10-19 的[核心价值增量回归](CCRouter-core-principles-audit.md)补充 13 条约定的当前证据、
  Demo 静态分析修正、真实消费者与独立本地源码快照的最小闭环，并提供首次接入入口；
  历史全量、平台和 IDE 结论不自动延续，本地快照验证不关闭 Hosted/发布归档门禁。
- 2026-10-19 的[导航历史与容量评估](validation/navigation-history-capacity-20261019.md)和
  [Sink 背压及 Host 清理验证](validation/diagnostic-sink-backpressure-20261019.md)记录 Route
  回收、单在途有界投递、启动回滚与跨 error Zone 关闭等待；主机验证不替代业务真机验收。
- 当前实现事实依次以生产代码、自动化测试、生成物和本文状态矩阵为准。
- 2026-10-20 的[UI Fragment 易用性与收敛审查](archive/20261024-consolidation/CCRouter-ui-fragment-usability-review.md)
  记录场景、接入工具及 enum/受限 DTO Action 的演进；
  [独立首次接入技术验证](validation/ui-fragment-adoption-20261020/README.md)补充完整闭环、
  外部 UI runtime 包识别修正和手工编辑点，未宣称完成新人可用性研究或 API 冻结。
- 专项设计文档用于解释语义和历史决策；其中的 Proposal、阶段计划和旧基准不能单独证明能力已实现。
- 性能数字、测试数量和平台验证结果只代表文档注明日期的快照，不自动代表后续提交。
- Package 当前仍是开发期 `0.1.0`；文档中的“架构 1.x”表示当前静态组件架构代际，不表示
  已经发布 `1.0.0`。
- 正式发布是否具备条件只看[正式发布准备与门禁](CCRouter-release-readiness.md)，不从某份专项
  设计的完成勾选推断。
- 2026-10-03 的[全框架审查](CCRouter-framework-audit-2026-10-03.md) 原 F01–F18 已修复；
  后续[生成器与 Analyzer 复审](CCRouter-generator-analyzer-audit-2026-10-03.md) 确认的
  G01–G05/A01 六项问题也已逐项修复并独立提交，验证与剩余边界见该报告。
  以下“已实现”表示能力存在，不表示所有组合边界已验证无误。

## 当前状态矩阵

### 已实现

- 可选类型化 UI Fragment：Pure Dart DTO/enum 契约、消费 Client、Renderer 静态装配、
  Host generation 校验与 Flutter State 生命周期；集合、sealed Action 和动态 Slot 未支持。
- 原生 Managed Host、Shell、StatefulShell、多 Outlet、MultiHost 和调用级 Context 定位。
  渐进接入使用局部 Managed Outlet；不再提供 GoRouter attach。
- 默认 Page/Dialog 路由族按最近 MaterialApp/CupertinoApp 宿主选择，显式类型优先；Material
  路由仍随主题平台适配。Android 预测返回可选自动桥默认关闭，支持普通 Material 页面与
  显式接线的自定义 Page；Guard、模态和不支持的 Theme 保留 fallback，平台验收见
  [专项说明](CCRouter-predictive-back.md)。
- 默认 Runtime 初始化、关闭和 InitTask Gate 控制仅由 Composition Root 通过 `CCRouterHost`
  调用；业务 `CCRouter` 保留 Session 操作与只读任务诊断，单个导航 Host 卸载不关闭 Runtime。
  启动失败自动回收未发布 Runtime；回滚与正常关闭均支持不同 error Zone 的调用方加入清理。
- 类型安全 Route、Service、Command、Event、InitTask Contract 及其生成、聚合、源码索引和
  Workspace 校验。
- Route Interceptor、Redirect、Defer、PopGuard、Aspect、页面生命周期、Deep Link policy、
  混合导航台账和 Route Scope。
- App/Session/Route Service Scope、`singleton`/`newInstance`、lazy readiness、消费组件专属
  Service Proxy，以及当前受限泛型方法矩阵。
- 五类 Contract SemVer、shape fingerprint、Owner/消费者范围，以及生成、Host 聚合和 Runtime
  三层兼容门禁。
- `ccrouter generate/find/clean`、Host generation watch、`watch status/follow`、角色化
  package-local generation、显式 Portable State prepare/publish、Pub Hook、七类非覆盖式脚手架、
  增量缓存和 `--no-cache --check` 全量参考门禁。
- Analysis Server 的跨 Package 生成物导入、确定性同源能力生成物缺失、required InitTask 声明
  诊断，以及基于精确 resolution 身份的 watch/one-shot Generator 结构化诊断桥接。
- 嵌入式只读 DevTools、版本化 Snapshot/Trace Edge 协议和官方 DevTools Extension；Catalog、
  Runtime、组件依赖和单次能力调用链可以关联展示。
- Diagnostic Sink 每 Runtime 单在途写入与独立有界等待队列、只读压力计数，以及不保留
  Flutter Route 的 Runtime 历史快照；容量与主机验证边界见上面的 2026-10-19 专项报告。

### 应用侧示例（不属于框架能力）

- `demo_analytics`、`demo_analytics_flutter` 提供产品事件、显式点击/滚动/曝光、Consent、
  黑名单、节流与有界分发参考；`demo_analytics_firebase` 提供 callback 映射。
  应用可接入自己的埋点系统，不需要依赖这些 Demo 包。
- 上述应用埋点仅支持显式稳定 Target，不自动猜测 Widget 文本、Key 或事件 ID。
- Demo KV Storage Scoped Facade、Host-owned Context Provider 和可替换内存 Backend；业务
  persistence、Secure Storage 与迁移策略由应用负责，不是框架内建存储能力。

### 部分实现

- DevTools 源码定位：已展示/复制 source URI，嵌入式面板支持 Host `onOpenSource` callback；官方
  Extension 不直接绑定任意本地 IDE。
- Component Graph：已支持只读搜索、聚焦、依赖和反向依赖；不是可编辑的通用图形建模工具。
- Analyzer Plugin：当前提供跨 Package 生成物导入、Route/Service/Command/Event/InitTask
  确定性同源生成物缺失、required InitTask Contract/timeout、Handler 形态与明显签名、互斥参数、
  字面量 ID/alias/Gate ID 和正 timeout 等低误报单文件诊断；不生成代码、不自动改写 import，
  也没有 rename/alias migration Quick Fix。已支持互斥参数安全删除，以及由生成 metadata 唯一
  证明、公共 import 已暴露 Owner 常量时的 Service/Command required dependency 实时诊断和
  直接 List Quick Fix；复杂集合和 import 插入仍不自动处理。CLI 已提供 Host-only 的只读
  `analyzer status/doctor` 和 maintainer `pin-check`；显式 `install/upgrade/uninstall` 支持
  `--dry-run` 与受管 bootstrap。插件依赖图保持隔离，Hosted 发布后使用对应 bootstrap 模板；
  完整 Hosted/IDE/SDK 矩阵仍待外部验收。
- UI Fragment 工具链：已支持生成、兼容校验、Portable State、`create ui-fragment --dry-run`、
  UI `find --usage` 和保守 Analyzer 诊断/Owner Quick Fix；UI DevTools Catalog 尚未实现。
  [UI Fragment 规范](CCRouter-ui-fragment-design.md#action-schema-与兼容)统一维护 Action schema 与兼容边界。
- 零 Subscriber Event：正常生成 Client、Workspace Validator 和 Runtime publisher identity 已覆盖；
  generated SPI 被手工伪造时没有独立 Event Contract Runtime Registry。该 Registry 仅在 generated
  SPI 需要成为严格防伪边界时再实现。
- 多平台与内存验证：已有构建 smoke、资源释放回归和统一基准入口；真实设备矩阵、长期生产
  RSS/Heap 趋势和原生多窗口仍需持续验证。
- KV Storage Demo：Scoped Facade 已落地；真实持久化/Secure Backend、生产 Session、API 环境、
  Device Contract 和游客迁移策略仍由业务 Composition Root 实施。

### 明确未实现或延期

- Navigator 1.0 Backend、接管任意已有 Router 的通用 attach；原生 Managed 已使用 Navigator 2.0。
- 原子组合栈与任意位置 replace；精确 Entry close 已实现。
- macOS、Windows、iPadOS 原生多窗口/多 Flutter View 平台桥接。
- 完整 Route Restoration。
- 动态组件 activate/deactivate/install/uninstall。
- 受控 Workspace/Feature Scope 和 Action Pipeline。
- Contract Scaffold/Promotion/Migration、alias migration CLI/Quick Fix。
- Service Proxy 的通用 generic Contract、Stream、callback、继承和高级 Route Scope 代理。
- 全局 Widget 自动识别，以及供应商产品埋点/HTTP/Crash Adapter：由应用选择实现，不列为框架待补齐能力。
- 正式 Hosted 发布、release candidate 兼容样本和迁移发布流程。
- 独立的 dev/test/staging/production Provider 选择抽象。

## 本轮纠正的历史误标

- Command、Event、InitTask 生成曾被标为“尚未实现”，现已完成。
- 官方 DevTools Extension、Catalog/Runtime 联动、组件依赖和调用链曾被标为未来计划，现已完成
  只读闭环；仅“Extension 直接打开本地 IDE”仍未实现。
- Contract 版本兼容曾被标为不完整，现已完成核心生成/聚合/Runtime 门禁。
- CLI 曾只记录 Component/Page；Service/Command/Event/InitTask scaffold 已实现。
- Generator Watch 曾被列为 2.0 候选；当前已提供 Host-only `generate --watch=auto --machine`、
  `watch status/follow`、Pub Hook 协调和 Flutter machine reload gate。
- Capability Catalog 曾写成只包含 Route；当前已覆盖 Route、Service、Command、Event、InitTask。
- Demo KV Storage 曾把 Scoped Facade 写成后续计划；该 Facade 已完成。

## 现行规范与执行入口

### 总体与治理

- [后续工作与触发条件](CCRouter-future-work-plan.md)：只维护未完成工作。
- [正式发布准备与门禁](CCRouter-release-readiness.md)：唯一发布阻塞清单。
- [Contract 版本与兼容规范](CCRouter-contract-compatibility.md)：版本、shape、Owner 和三层校验。
- [生产项目场景驱动演进流程](CCRouter-production-adoption-workflow.md)
- [SDK 兼容性验证](CCRouter-sdk-compatibility.md)
- [Flutter / Dart SDK 升级同步计划](CCRouter-sdk-upgrade-plan.md)
- [验证证据统一索引](validation/README.md)：源码回归、平台记录与历史证据。

### 路由

- [Managed 路由架构与混合导航规范](CCRouter-route-design.md)
- [路由契约文件设计](CCRouter-route-contract-design.md)
- [精确 RouteEntry 关闭](CCRouter-targeted-close-design.md)
- [已打开页面的路由重验证](CCRouter-route-revalidation-design.md)
- [返回协调与平台手势](CCRouter-predictive-back.md)：系统/业务返回、iOS 与 Android。

### 能力与生成器

- [类型化 UI Fragment 规范](CCRouter-ui-fragment-design.md)：契约、Action、装配与生命周期。
- [类型化 UI Fragment 接入指南](../skills/ccrouter-integration-development/references/ui-fragments.md)
- [Service 生命周期规范](CCRouter-service-lifecycle-design.md)
- [Service Proxy 生成规范](CCRouter-service-proxy-generation-design.md)
- [Command 设计与实施边界](CCRouter-command-design.md)
- [Event 设计与实施边界](CCRouter-event-design.md)
- [初始化任务设计与实施边界](CCRouter-initialization-task-design.md)
- [注解与字段校验](CCRouter-annotation-validation.md)
- [build_runner 与团队构建正确性优先优化计划](CCRouter-build-runner-optimization-plan.md)
- [CLI Pub Hook](CCRouter-cli-pub-hook.md)

### 工具与诊断

- [DevTools 只读面板、Host 装配与协议](CCRouter-devtools.md)
- [IDE / Analysis Server 与 Analyzer CLI](CCRouter-ide-analysis-server.md)
- [应用侧 Analytics 边界](CCRouter-analytics-and-auto-track-design.md)：不属于框架能力。

## 历史基线、审计与独立 Proposal

- [2026-10-24 合并归档与现行映射](archive/20261024-consolidation/README.md)
- [v0.1 架构基线](CCRouter-v0.1-architecture.md)
- [组件化框架对比与缺口记录](CCRouter-component-framework-comparison.md)
- [核心价值与开发约定回归](CCRouter-core-principles-audit.md)
- [2026-10-03 全框架审查](CCRouter-framework-audit-2026-10-03.md)
- [2026-10-03 生成器与 Analyzer 复审](CCRouter-generator-analyzer-audit-2026-10-03.md)
- [注解路由生成器对比](CCRouter-annotation-generator-comparison.md)
- [生成器性能报告](CCRouter-generator-performance-report.md)
- [Generator / Analyzer 优化收敛验收](CCRouter-generator-analyzer-convergence-acceptance.md)
- [Host-owned Route Mount Proposal](CCRouter-host-owned-route-mount-design.md)：需基于 Managed 重新评估。
- [Action Pipeline Proposal](CCRouter-action-pipeline-plan.md)：达到需求触发条件后再立项。

<details>
<summary>旧路径兼容入口（不再独立维护正文）</summary>

- [DevTools Host 自动装配](CCRouter-devtools-host-integration-plan.md)
- [Service 实施清单](CCRouter-service-completion-plan.md)
- [Cupertino Pop 手势](CCRouter-cupertino-pop-gesture-design.md)
- [预测返回评估](CCRouter-predictive-back-assessment.md)
- [路由专项分析](CCRouter-route-follow-up-analysis.md)
- [UI Fragment Action payload](CCRouter-ui-fragment-action-payload-design.md)
- [UI Fragment 易用性审查](CCRouter-ui-fragment-usability-review.md)
- [UI Fragment 实施验收](CCRouter-ui-fragment-acceptance.md)
- [Analyzer CLI 自动装配](CCRouter-analyzer-cli-plan.md)
- [混合路由改造](CCRouter-hybrid-routing-design.md)
- [路由完成计划](CCRouter-route-completion-plan.md)
- [正式发布前能力计划](CCRouter-pre-release-capability-plan.md)
- [最终 API 阶段复审](CCRouter-final-api-review.md)
- [Navigator Backend 可行性](CCRouter-navigator-backend-feasibility.md)

</details>

## 文档职责

| 文档类型 | 用途与维护规则 |
| --- | --- |
| 根 README、Integration/CLI Skill、现行专项规范 | 当前接入、API 边界和稳定语义；最终以源码、生成物与相应回归为准 |
| 后续工作 | 未完成项、需求触发条件与准入；不维护完成历史或发布阻塞副本 |
| Release Readiness | 唯一发布阻塞项、顺序与完成定义 |
| Proposal / 优化计划 | 候选设计和触发条件；不能据此调用尚不存在的 API |
| archive、审计、性能报告、validation | 注明日期/源码/环境的历史证据；不自动延续测试与设备结论 |
| 旧路径导航页 | 保留路径并引导现行规范/原文；不追加新规则 |

修改某条规则时更新对应现行规范与受影响的接入指南，历史快照只修复导航，不回写当前 API 或测试数量。文档提交应运行：

```bash
fvm dart run tool/documentation_check.dart
fvm dart run tool/skill_bundle_check.dart
fvm dart run tool/release_sensitivity_check.dart
```

应用层示例文档放在 `demo/docs/`，例如[KV Storage Demo 改造](../demo/docs/kv-storage-demo-migration.md)；它们不作为框架公开契约。
