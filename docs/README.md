# CCRouter 文档索引与能力状态

## 状态说明

- 最近全量对齐：2026-10-07。
- 当前实现事实依次以生产代码、自动化测试、生成物和本文状态矩阵为准。
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
- GoRouter managed/attach Host、Shell、StatefulShell、多 Outlet 和调用级 Context 定位。
- 类型安全 Route、Service、Command、Event、InitTask Contract 及其生成、聚合、源码索引和
  Workspace 校验。
- Route Interceptor、Redirect、Defer、PopGuard、Aspect、页面生命周期、Deep Link policy、
  混合导航台账和 Route Scope。
- App/Session/Route Service Scope、`singleton`/`newInstance`、lazy readiness、消费组件专属
  Service Proxy，以及当前受限泛型方法矩阵。
- 五类 Contract SemVer、shape fingerprint、Owner/消费者范围，以及生成、Host 聚合和 Runtime
  三层兼容门禁。
- `ccrouter generate/find/clean`、Host generation watch、`watch status/follow`、角色化
  package-local generation、显式 Portable State prepare/publish、Pub Hook、六类非覆盖式脚手架、
  增量缓存和 `--no-cache --check` 全量参考门禁。
- Analysis Server 的跨 Package 生成物导入、确定性同源能力生成物缺失、required InitTask 声明
  诊断，以及基于精确 resolution 身份的 watch/one-shot Generator 结构化诊断桥接。
- 嵌入式只读 DevTools、版本化 Snapshot/Trace Edge 协议和官方 DevTools Extension；Catalog、
  Runtime、组件依赖和单次能力调用链可以关联展示。
- Provider-neutral Analytics、显式点击/滚动/曝光采集、Consent、黑名单和节流；Firebase callback
  Adapter 作为应用层 Demo 提供。
- Demo KV Storage Scoped Facade、Host-owned Context Provider 和可替换内存 Backend。

### 部分实现

- DevTools 源码定位：已展示/复制 source URI，嵌入式面板支持 Host `onOpenSource` callback；官方
  Extension 不直接绑定任意本地 IDE。
- Component Graph：已支持只读搜索、聚焦、依赖和反向依赖；不是可编辑的通用图形建模工具。
- 自动埋点：只支持显式稳定 Target；不自动猜测任意 Widget 文本、Key 或业务事件 ID。
- Analyzer Plugin：当前提供跨 Package 生成物导入、Route/Service/Command/Event/InitTask
  确定性同源生成物缺失、required InitTask Contract/timeout、Handler 形态与明显签名、互斥参数、
  字面量 ID/alias/Gate ID 和正 timeout 等低误报单文件诊断；不生成代码、不自动改写 import，
  也没有 rename/alias migration Quick Fix。已支持互斥参数安全删除，以及由生成 metadata 唯一
  证明、公共 import 已暴露 Owner 常量时的 Service/Command required dependency 实时诊断和
  直接 List Quick Fix；复杂集合和 import 插入仍不自动处理。CLI 已提供 Host-only 的只读
  `analyzer status/doctor` 和 maintainer `pin-check`；legacy 安装/升级/卸载仍保留为可回退管理
  路径，Hosted 发布后优先普通 `dev_dependency`，完整 Hosted/IDE/SDK 矩阵仍待外部验收。
- 零 Subscriber Event：正常生成 Client、Workspace Validator 和 Runtime publisher identity 已覆盖；
  generated SPI 被手工伪造时没有独立 Event Contract Runtime Registry。该 Registry 仅在 generated
  SPI 需要成为严格防伪边界时再实现。
- 多平台与内存验证：已有构建 smoke、资源释放回归和统一基准入口；真实设备矩阵、长期生产
  RSS/Heap 趋势和原生多窗口仍需持续验证。
- KV Storage Demo：Scoped Facade 已落地；真实持久化/Secure Backend、生产 Session、API 环境、
  Device Contract 和游客迁移策略仍由业务 Composition Root 实施。

### 明确未实现或延期

- Navigator 1.0 Backend、通用 Navigator 2.0/自定义 Router Backend。
- 原子组合栈和精确 Entry 操作。
- macOS、Windows、iPadOS 原生多窗口/多 Flutter View 平台桥接。
- 完整 Route Restoration。
- 动态组件 activate/deactivate/install/uninstall。
- 受控 Workspace/Feature Scope 和 Action Pipeline。
- Contract Scaffold/Promotion/Migration、alias migration CLI/Quick Fix。
- Service Proxy 的通用 generic Contract、Stream、callback、继承和高级 Route Scope 代理。
- 全局 Widget 自动识别，以及 ThinkingData、OpenTelemetry、HTTP/Crash Analytics Adapter。
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

## 文档目录

### 总体与治理

- [v0.1 架构设计](CCRouter-v0.1-architecture.md)
- [组件化框架能力对比与缺口记录](CCRouter-component-framework-comparison.md)
- [核心价值与开发约定回归](CCRouter-core-principles-audit.md)
- [2026-10-03 全框架审查与修复顺序](CCRouter-framework-audit-2026-10-03.md)
- [2026-10-03 生成器与 Analyzer 复审](CCRouter-generator-analyzer-audit-2026-10-03.md)
- [后续任务与实施计划](CCRouter-future-work-plan.md)
- [最终 API 收口复审清单](CCRouter-final-api-review.md)
- [正式发布前能力设计与实施计划](CCRouter-pre-release-capability-plan.md)
- [正式发布准备与门禁](CCRouter-release-readiness.md)
- [生产项目场景驱动演进流程](CCRouter-production-adoption-workflow.md)
- [SDK 兼容性验证](CCRouter-sdk-compatibility.md)
- [Flutter / Dart SDK 升级同步计划](CCRouter-sdk-upgrade-plan.md)

### 路由

- [路由子系统设计](CCRouter-route-design.md)
- [路由契约文件设计](CCRouter-route-contract-design.md)
- [混合路由改造设计](CCRouter-hybrid-routing-design.md)
- [Host-owned Route Mount 设计与实施计划](CCRouter-host-owned-route-mount-design.md)
- [路由完成计划](CCRouter-route-completion-plan.md)
- [路由专项问题分析](CCRouter-route-follow-up-analysis.md)
- [Navigator Backend 可行性](CCRouter-navigator-backend-feasibility.md)
- [Cupertino Pop 手势设计](CCRouter-cupertino-pop-gesture-design.md)

### 能力与生成器

- [类型化 UI Fragment 设计与实施计划](CCRouter-ui-fragment-design.md)
- [类型化 UI Fragment 实施验收与核心价值回归](CCRouter-ui-fragment-acceptance.md)
- [Service 生命周期设计](CCRouter-service-lifecycle-design.md)
- [Service Proxy 生成设计](CCRouter-service-proxy-generation-design.md)
- [Service 实施计划](CCRouter-service-completion-plan.md)
- [Command 设计与实施计划](CCRouter-command-design.md)
- [Event 设计与实施计划](CCRouter-event-design.md)
- [初始化任务设计与实施计划](CCRouter-initialization-task-design.md)
- [Action Pipeline 候选计划](CCRouter-action-pipeline-plan.md)
- [注解路由生成器对比与借鉴记录](CCRouter-annotation-generator-comparison.md)
- [注解与字段校验](CCRouter-annotation-validation.md)
- [生成器性能报告](CCRouter-generator-performance-report.md)
- [build_runner 与团队构建正确性优先优化计划](CCRouter-build-runner-optimization-plan.md)
- [Generator / Analyzer 优化收敛验收](CCRouter-generator-analyzer-convergence-acceptance.md)
- [CLI Pub Hook](CCRouter-cli-pub-hook.md)

### 工具与诊断

- [DevTools 只读可视化](CCRouter-devtools.md)
- [DevTools Host 自动装配计划](CCRouter-devtools-host-integration-plan.md)
- [IDE / Analysis Server 集成](CCRouter-ide-analysis-server.md)
- [Analyzer Plugin CLI 自动装配计划](CCRouter-analyzer-cli-plan.md)
- [Analytics 与自动采集](CCRouter-analytics-and-auto-track-design.md)

## 文档职责

| 文档类型 | 用途 | 是否代表当前公开能力 |
| --- | --- | --- |
| 根 `README.md`、本索引、Integration/CLI Skill | 开发者接入和当前事实 | 是，但仍以代码、测试和生成门禁为最终依据 |
| Route/Service/Command/Event/InitTask 等专项设计 | 当前稳定语义、边界和取舍 | 仅未标为 Proposal/延期的部分 |
| `*-completion-plan`、审计和性能报告 | 某次实施或验证快照 | 否，测试数量和环境不会自动延续 |
| `*-plan`、Backend 可行性、Action Pipeline | 候选方案和触发条件 | 否，不得据此调用不存在的 API |
| v0.1 架构、框架对比、外部方案比较 | 历史基线和决策依据 | 否，冲突时以本索引及专项当前契约为准 |
| Release Readiness | 发布阻塞项、执行顺序和完成定义 | 是，且是唯一发布执行清单 |

文档提交应运行：

```bash
fvm dart run tool/documentation_check.dart
fvm dart run tool/release_sensitivity_check.dart
```

应用层示例的设计与验证文档放在 `demo/docs/`，不作为框架公开契约；例如
[KV Storage Demo 改造](../demo/docs/kv-storage-demo-migration.md)。

生成器输出的应用 Catalog 不属于手写设计文档。当前 Demo 聚合结果位于
`demo/lib/src/ccrouter_generated/metadata/cc_routes.json` 和
`demo/lib/src/ccrouter_generated/metadata/cc_catalog.md`。
