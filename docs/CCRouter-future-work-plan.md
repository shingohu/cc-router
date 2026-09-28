# CCRouter 后续任务与实施计划

## 1. 文档状态

- 状态：后续任务总清单，仅记录，不代表当前立即实施。
- 当前版本：1.x，重点是兼容性、性能、稳定性和生成物正确性维护。
- 架构 2.0：只有达到本文列出的真实需求、性能或平台触发条件后才立项。
- 优先级：P0 最高；P1 为 1.x 后续或正式发布前；P2 为架构 2.0 候选。

本文是各专项设计文档的索引，不替代具体契约。实施时必须先更新对应设计文档、补测试，
再修改代码；每个完成项单独回归并提交。

生产项目中发现的新场景、缺陷和能力候选，先按
[生产项目场景驱动演进流程](CCRouter-production-adoption-workflow.md) 分类和验证，再决定进入
当前版本修复、正式发布前计划或架构 2.0 候选。

## 2. 当前已完成

- [x] GoRouter Host 最小接入 `CCGoRouterApp`，保留 `attach` 和 `CCRouterApp.managed`。
- [x] Demo 稳定 ID 集中管理：InitTask、Gate、Event、Policy、导航来源和 Host ID。
- [x] GoRouter Page、Dialog、BottomSheet、Shell、StatefulShell、Outlet 和混合路由基础闭环。
- [x] Runtime、Session、RouteEntry、Service、Command、Event、InitTask 生命周期基础闭环。
- [x] Interceptor、Redirect、Defer、PopGuard、Aspect、Trace、Telemetry 和失败回退基础闭环。
- [x] 生成器增量缓存、Workspace/Package 聚合、Catalog、源码查找和生成物门禁基础闭环。
- [x] CLI Component/内部 Page 非覆盖式脚手架；脚手架不修改 Host 依赖或生成物。
- [x] 顶层 `const CCComponent`、自动 Registrar/Manifest、Route 与简单 Service 自动装配，
  以及 Service Contract 自动绑定、稳定 ID/Provider metadata 最小生成闭环。
- [x] Command/Event Contract、Handler/Subscription、Owner Client、稳定 ID、metadata、Catalog
  与 Workspace 校验生成闭环。
- [x] InitTask Contract、Handler、类型化依赖、自动 Registrar bridge、DAG/Catalog、源码定位
  与 Workspace 校验生成闭环。

## 3. P0：恢复开发后的第一批任务

### 3.1 稳定 ID 与 Contract 边界

- [x] 完成 InitTask/Contract 生成边界：不扫描 Registrar/Contribution 猜测关系，采用显式
  Task Contract、Handler 注解和类型化依赖引用。
- [x] Demo 已用公共 contracts Package 验证真实跨组件 Task Contract 和 required Owner dependency。
- [x] 框架提供通用的 `appStarted` 与 `privacyGranted` Gate；业务组件直接使用框架常量，避免重复定义。
- [x] 跨组件 Task Contract 必须归属公共 contracts Package，并由 public barrel exposure 测试门禁。

### 3.2 生成器校验收敛

- [x] 评估生成器是否能可靠发现手写 InitTask 的 ID、Gate 和依赖；结论是不能可靠发现，
  因此已批准显式声明方案，不增加启发式扫描，也不静默声称已覆盖。
- [x] 确认 Route/InitTask Contract、组件依赖、公共 Barrel 和跨包内部 API 的生成期校验边界；
  Runtime 继续保留对手写与陈旧生成物的最终校验。
- [x] InitTask 生成错误与 metadata 提供 Package、组件、任务 ID、依赖和可移植来源位置。
- [x] 2026-09-27 已在本轮 Component/Service 生成改动后执行全量生成物回归；后续每次
  Generator 改动仍必须重复该门禁，不能只验证 Demo 编译。

### 3.3 质量回归

- [x] 2026-09-24 完成本轮全量回归：`dart analyze`、`ccrouter_test` 302 项、Generator 131 项、
  Demo 30 项、缓存/无缓存 `generate --check`、Runtime/Generator/Service 基准、macOS Debug
  构建和资源释放审查均通过；长期平台 RSS/Heap 趋势仍属于持续观测。
- [x] 2026-09-27 完成 Component/Service 生成架构回归：`dart analyze`、
  `ccrouter_test` 324 项、Generator 177 项、Demo 31 项以及缓存/无缓存
  `generate --check` 均通过；4 个组件、31 条路由和 8 个生成 Package 输出一致。
- [x] 2026-09-27 完成 Command/Event/InitTask 生成闭环回归：`dart analyze`、
  `ccrouter_test` 329 项、Generator 216 项、Demo 31 项、缓存/无缓存 `generate --check`、
  InitTask clean/rebuild 和能力级 `ccrouter find` 均通过。
- [ ] 持续执行 `dart analyze`、框架测试、生成器测试、Demo 测试和 `generate --check`。
- [x] 2026-09-28 修复 public barrel 校验的重复 Package 扫描，引入精确内容 fast path 和
  Route/Service/Command/Event/InitTask 混合压力基准；30× 的 1650 项能力 Validator 为 38ms，
  无变化 wall 为 0.81-0.85s。完整数据见
  [生成器性能报告](CCRouter-generator-performance-report.md)。
- [ ] per-Package dirty set 仅在真实项目 Host 聚合超过总耗时 20% 时重新评估；实施前必须
  设计 per-Package output fingerprint，不能因跳过未变 Package 而漏掉受管输出篡改。
- [ ] 维护冷启动、初始化、路由解析、导航延迟、并发导航、Runtime dispose 的同机趋势。
- [ ] 继续做 macOS、iOS 真机/模拟器和 OHOS 运行回归；平台 SDK 变更只做兼容性修复。
- [ ] 继续检查 Adapter、Observer、Route Scope、Overlay、Timer 和 Stream 的释放路径。
- [x] 2026-09-27 核对架构、路由、契约、生成器、分析事件与后续计划文档，纠正已实现能力、
  旧生成路径、旧 API 名称和当前测试数量；历史回归基准保留其原始口径。
- [x] 保留 `CCRouterRuntime.forTesting` 与 Zone-local Test Runtime Overlay，并提取私有 Runtime
  Resolver 统一选择 default/overlay Runtime；Resolver 不拥有、不销毁 Runtime，未改变公开 API。

## 4. P1：正式发布前或真实规模触发后

### 4.1 Contract 与版本兼容

- [ ] 设计 Contract 版本范围、Route Contract 兼容性和 Service Contract 兼容性。
- [ ] 生成阶段报告升级、废弃、缺失和不兼容原因；Runtime 只做边界保护。
- [ ] 评估环境实现选择模型；短期继续使用 Composition Root、Service Key 和 Test Override。

### 4.2 初始化任务生成（已完成）

- [x] 设计显式 `CCInitTaskContract`、`@CCInitTask`、类型化依赖和现有
  `CCInitializationGate` 复用模型；不生成业务调用 Client。
- [x] 生成 Handler registration bridge、依赖索引、Package/Host metadata 和可读 DAG 文档。
- [x] 实现 Task/Owner/Gate/Handler/Contract exposure/依赖图校验，并保留 Runtime 最终校验。

### 4.3 Service Proxy 与 Command/Event 生成

- [x] Service Contract Token、简单 Provider registration、自动 Registrar 和 Catalog metadata
  已实现；复杂构造/readiness 继续通过 Contribution 显式注册。
- [x] Service 方法级自动 Proxy 使用消费组件显式 `CCServiceDependency<T>`，生成组件专属
  Client、稳定 caller/method identity 和方法 metadata；不扫描依赖生成未使用能力。
- [ ] 根据生产需求扩展当前明确拒绝的泛型 Contract、Stream、callback、继承或 Route Scope 方法代理；
  每一项必须先冻结所有权、取消和兼容语义。
- [x] 按 `CCRouter-command-design.md` 已批准方案实现 Command Contract、Handler registration、
  显式消费依赖、组件专属 Client、metadata、Catalog 和 Workspace 校验；不扫描并生成未使用 Command。
- [x] 按 `CCRouter-event-design.md` 已批准方案实现 Event Contract、静态 Subscription、Owner
  自动 Publication Client、metadata、Catalog 和 Workspace 校验；不引入重复 publication 声明
  或动态 EventBus 语义。
- [x] Contract 通过公共业务 barrel 暴露；Proxy 留在消费组件内部生成目录，跨 Package 不导出
  生成实现文件。

### 4.4 开发体验与诊断

- [x] 扩展 `ccrouter find` 和 Catalog 源码定位，覆盖 Route、Service、Command、Event、InitTask。
- [x] 增加 `ccrouter create component` 和 `ccrouter create page` 模板命令；跨组件 Contract 提升仍需显式设计。
- [x] 完成可嵌入 DevTools 只读视图：Component Graph、Route/Backend Entry、Trace、
  Failure/Fallback 和 InitTask DAG；官方 DevTools Extension 仍作为后续可选工具评估，见
  `docs/CCRouter-devtools.md`。
- [x] 2026-09-28 完成最小 IDE / Analysis Server 集成：独立
  `ccrouter_analyzer_plugin` 提供跨 Package 生成物导入和缺失 Route 生成物诊断；生成的 Dart
  API、`ccrouter find`、Catalog 与 `generate --check` 仍分别承担补全、源码定位和最终门禁。
  插件不执行生成、不替代 Workspace Validator。详见
  [IDE / Analysis Server 集成](CCRouter-ide-analysis-server.md)。

## 5. P2：架构 2.0 候选

### 5.1 导航后端与组合栈

- [ ] Navigator 1.0 Backend：先完成 root Outlet、readiness handshake、混合栈和结果通道设计。
- [ ] 通用 Navigator 2.0/自定义 Router Backend：只适配明确的 RouterDelegate/Pages 模型，
  不承诺“万能 Navigator 2.0 Adapter”。
- [ ] 原子组合栈操作：重新评估 `pushAndRemoveUntil`、`removeRoute`、`removeRouteBelow`、
  `replaceRouteBelow` 等能力；必须具备稳定 Entry ID、原子提交、失败回滚和返回值语义。

### 5.2 平台窗口与状态

- [ ] macOS、Windows、iPadOS 原生多窗口和 Flutter View 到 `CCNavigationHost` 的映射。
- [ ] 多 Window Host 的创建、激活、关闭、注销和替换 Host 生命周期。
- [ ] 完整 Route Restoration：版本化 Snapshot、重新解析、契约校验、部分恢复和安全降级。
- [ ] 仅在 restoration opportunity 数据证明收益后，才进入公开恢复 API。

### 5.3 组件与 Scope 治理

- [ ] 动态组件 `activateComponent` / `deactivateComponent` / 卸载协议。
- [ ] 依赖级联、Handler/订阅/诊断清理、活跃 Route 协调、未完成调用取消和原子能力切换。
- [ ] 受控 Workspace/Feature Scope；不直接开放任意字符串层级 Scope。

### 5.4 Action Pipeline

- [ ] 只有出现动态来源触发本地白名单能力、多个候选处理器或真实仲裁缺陷后立项。
- [ ] 设计 Action ID、来源策略、优先级、短路、取消、超时、白名单和执行报告。
- [ ] Host Ingress 先把 H5/远程输入转换为类型安全 Action，禁止脚本、类名和任意 Map。

## 6. 明确暂不做

- [ ] 不实现 `ccrouter watch`；当前采用显式生成命令，后续仍只评估单次生成性能。
- [ ] 不增加单独的 `ccrouter help` 作为 1.x 收尾能力。
- [ ] 不在 1.x 增加动态组件激活、停用或卸载 API。
- [ ] 不在 1.x 增加完整状态恢复 API，只保留脱敏 restoration opportunity 诊断。
- [ ] 不为了对齐其他框架增加全局万能 Route 表、反射分派或任意 Map Contract。
- [ ] 不在核心 `ccrouter` 中直接依赖 GoRouter；GoRouter 最小入口保持在独立 Adapter Package。

## 7. 执行规则

1. 每个任务开始前先确认所属版本、触发条件、Owner、生命周期和失败语义。
2. 先更新对应设计文档，再实现最小闭环；不把候选 API 提前加入公开 Barrel。
3. 每项完成后必须有 Pure Dart/Flutter/生成器测试中适用的回归覆盖。
4. 通过 Analyze、相关测试、生成检查和 `git diff --check` 后再单独提交。
5. 新增公开 API 必须说明场景、所有权、生命周期、错误、诊断边界和更窄替代方案。
