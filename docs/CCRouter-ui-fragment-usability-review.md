# 类型化 UI Fragment 易用性与收敛审查

日期：2026-10-20。范围：静态 UI 的完整接入路径、enum/受限 DTO Action、接入工具和独立技术验证。
本次为代码审查、仓库场景演练与代理执行的独立工程验证；未测量新人接入耗时、误配率或生产帧耗时。
历史[实施验收](CCRouter-ui-fragment-acceptance.md)中的测试结果仍只对应其注明的提交。

## 当前结论与阅读入口

静态装配、enum/受限不可变 DTO Action、非覆盖式脚手架、UI `find --usage` 及保守 Analyzer
检测均已实现。独立 enum/DTO 接入技术流程已走通；四角色声明仍有手工成本，公开 API 未最终冻结。

| 目的 | 入口 |
| --- | --- |
| 按当前能力接入、修复配置错误 | [UI 接入指南](../skills/ccrouter-integration-development/references/ui-fragments.md) |
| 理解 DTO 类型、SemVer、schema 与回退 | [Action payload 设计与验证](CCRouter-ui-fragment-action-payload-design.md) |
| 复现独立工程、检查实际成本和日志 | [独立首次接入技术验证](validation/ui-fragment-adoption-20261020/README.md) |

后文验证记录按实施阶段保留，历史测试数量不累加，也不视为本次文档收口重新执行的结果。

## 结论与根因

架构边界已明确：A 管布局、输入和操作决策，B 管局部业务 UI，Flutter State 管实例资源，
Host 管静态实现装配。公开消费调用简短，但不能据此认定完整接入简单或公开 API 已最终收敛。

主要成本来自多角色声明和严格的受限 schema。生成 Client 省去了运行时查询，却没有省去
contracts 导出、Pub 依赖、required Owner edge、UI dependency 和 Host 生成。原诊断还把
alias 非法、alias 重复及契约重复合为一条错误，增加了找出正确修正位置的难度。

早期 enum-only 实现不能表达“B 私有加载列表，A 获取被选项 ID”；该缺口已通过受限 DTO
Action 补齐。当前推荐 Demo 和独立消费者均通过真实生成 Client 接收实际 selectedId。
这解决单一选择结果，尚不支持 sealed union 或多种异构 payload；不能由此推断任意 Action 建模均已支持。

## 三个场景及复现证据

| 场景 | 期望与现状 | 分类 | 证据与边界 |
| --- | --- | --- | --- |
| A 展示 B 的固定订单摘要 | A 传 orderId，B 展示并发出 openDetails，A 用已知 ID 决策；已支持 | 已支持接入 | `demo/test/ui_fragment_demo_test.dart` 使用真实 Host、Renderer 和生成 Client；补充选择订单 1、Props 更新后选择订单 3 的断言，验证 A 使用最新输入 |
| B 私有加载推荐列表，选择后向 A 返回 selectedId | 通过受限不可变 DTO Action 返回实际 ID；已支持 | 已实现通用能力 | 真实 Demo 与独立 DTO Widget 回归覆盖私有 ID、双实例、Props 竞态、隐藏和卸载；不通过全局选择状态、Service getter 或 Event 绕行 |
| Tab 保活、输入更新和账号重建 | 隐藏时 active=false，保留 State；更新 Props 保留备注；切换账号 Key 后重建；已支持 | 已支持接入及应用职责 | Demo 测试验证实例独立、Tab 恢复、快速更新、账号 Key 重建；框架 UI 测试覆盖隐藏时 Action、旧回调、reparent 和 shutdown/reinitialize。模拟账号不等于真实 Session 集成验收 |

第一个场景的 ID 由 A 预先知道；第二个场景的选项由 B 私有加载，A 不知道最终选中项。
不能让 A 捕获一个 category 或列表下标后声称等价支持第二个场景。

## 完整接入成本

以已有 Host 和 A/B 组件、复用一个 contracts Package 为前提，有以下九类 authored 编辑点。
工程已具备对应依赖时可以复用；这不是每次接入都必须新增九个文件的统计。

1. contracts 的 `pubspec.yaml`：直接依赖 `ccrouter_contracts`。
2. 契约源码：Owner ID、Props、Action 和 Fragment marker；复用已有 canonical Owner ID。
3. contracts 公共 barrel：显式导出 marker 及完整 schema 类型和 Owner ID。
4. B 的 `pubspec.yaml`：contracts 与 `ccrouter_ui` 直接依赖。
5. B 的 Renderer：顶层同步函数及普通 Widget/State。
6. A 的 `pubspec.yaml`：contracts 与 `ccrouter_ui` 直接依赖。
7. A 的组件定义：required Owner edge 和唯一 `uiDependencies`。
8. A 的页面：自身稳定 UI Client import、Props、Action、Key 和按需 active。
9. Host 的 `pubspec.yaml`：实际 A/B 实现闭包与直接 `ccrouter_ui` 依赖；执行 Host 生成。

contracts、A、B 还各需自己的 `ccrouter_generator` dev dependency；Host 同时需要
`ccrouter_generator` 和 `build_runner`。这属于前置工程配置，Host 依赖不能替代成员声明。
Host 仍传一个生成 Assembly，无需手写 UI 注册或修改原 initialize 调用形态。
生成 Dart、metadata、fingerprint、Portable State 不计入手写成本，也不能手改。
同一 Fragment 的多实例只消费一个契约，依赖 alias 是方法名，实例由 Key 区分。

这些是职责与编辑点，不是文件数量。独立样例在已有 Host/A/B/contracts、Owner 和生成器
开发依赖的前提下，脚手架创建 3 个文件，另手动写入或更新 7 个生产文件及 1 个测试文件。
其中包含可复用的 Widget 公开入口和 Host 展示设置；不能当作普遍最低成本或新人耗时。

## 候选方案与本轮决策

| 方案 | 收益 | 代价、兼容与回退 | 决策 |
| --- | --- | --- | --- |
| 普通公共 Flutter Widget + 显式依赖/注入 | 成本低，可用普通数据型回调 | 没有 CCRouter UI 契约和装配校验；适合所有权与依赖方向已明确的普通组合 | 保留为轻量选项 |
| 保留显式声明，补指南、脚手架、查询和诊断 | 减少模板编写与试错 | 多角色成本仍存在；工具变更可独立回退 | 已实施，不自动改写既有配置 |
| 自动从 uiDependencies 推导 required Owner edge | 少写一项 | 改变显式组件图及既有校验约定，会影响更多能力的一致性 | 本轮不采用 |
| 扩展单 DTO Action | 覆盖私有动态列表选择 | 增加 schema/指纹/兼容门禁；enum 改 DTO 需 major SemVer 与重生成 | 受限 DTO 已实施，sealed union 延期 |
| 通用 Slot、动态实现替换或新 Fragment Scope | 更大扩展能力 | 增加调度、资源、装配与生命周期语义，当前三个场景均不需要 | 延期 |

## 第一阶段：enum-only 诊断修正（历史记录）

本节与紧随其后的验证表记录早期诊断改动；当时的 enum-only 拒绝边界已被后续 DTO 增量扩展。

- Builder 的缺失 Owner 提示包含 consumer、Owner、契约及 `CCComponent.dependencies` 修正位置；
  明确 `optionalDependencies` 不满足消费要求。同 Owner 的误用指向普通局部 Widget。
- 拆分 `invalidAlias`、`duplicateAlias` 和 `duplicateDependency`。重复契约提示只声明一次，
  多次调用并使用不同 Key；没有增加新业务 API，也没有放宽原有拒绝条件。
- 无效 `versionRange` 包含 consumer、契约、实际范围及基于当前 Contract 版本的示例。
- 当时的非法 Action 提示说明 enum-only 边界；当前已接受受限 DTO，根 scalar 与非法 schema 继续拒绝。
- Workspace 的 missing Owner / missing Renderer 提示包含消费方和 Host 修复路径。
- 接入指南补齐四个角色的步骤、完整最小代码和错误修正表；README 与 Integration Skill 同步。

没有新增长期资源或所有权。运行时仍由 B State 取消请求、释放 Controller/Timer，A 在账号变更时
显式清除旧账号状态或重建子树；active 不自动暂停工作、不表示像素可见性或权限。
运行时诊断仍不记录 Props 或 Action payload。本轮错误消息只使用 authored 静态声明信息。

回退仅需还原这次诊断和指南改动并按正常流程重新生成；旧契约、客户端签名和运行时语义不变。

## 数据型 Action 的设计决策与当前边界

“推荐项选择”和“设备项选择”用于评估单一不可变 DTO 输出。当前已保留 enum，并允许单个
final/const DTO 携带最小 selectedId/deviceId；复用受限 Pure Dart DTO 约束，继续排除
Flutter 类型、callback、Stream、集合和动态对象图。scalar 只允许作为 DTO 字段，不能作为根 Action。

与 sealed union 相比，单 DTO 的新增类型规则较少，但多个动作若靠 kind 加可空字段区分，
容易产生无效组合；不能把 enum-plus-nullable-fields 包装成通用动作协议。如果两个场景需要
多个异构 payload，应重新比较封闭 union 的收益和生成成本，不先发布宽泛 Object/Map Action。

实现与回归按以下边界验收，具体证据见[DTO 记录](CCRouter-ui-fragment-action-payload-design.md)：

1. 新 Action 形状纳入 schema、公开类型导出、SemVer 与 fingerprint，保留既有 enum 契约语义。
2. DTO 使用 UI schema 2 / Package Index 4，旧读取器明确拒绝；enum-only 保留原格式与签名。
3. A 接收实例局部的类型化数据；同步 callback 错误遵循 Flutter，不自动转 Event、重试或持久化。
4. 延续当前 mount、active 和 generation 的 Action 防护；多实例、Props 更新、账号切换、
   卸载及 shutdown 后的旧 Action 不得污染新实例；请求竞态仍由 B 管理。
5. 验证错误类型、公共导出、兼容漂移、真实跨 Package 选择、隐藏及销毁后的延迟回调。
6. 不保存 payload 到全局 catalog/诊断；完整 enum/DTO 性能对比仍未完成，不据此宣布发布就绪。

## 第一阶段验证快照

修改前：新增的 10 项诊断断言全部失败，分别复现缺失上下文、合并式错误及 payload 边界说明缺失。
它们证明的是当时的诊断缺口；DTO Action 被拒绝是该阶段的既定边界，不是该次诊断修复的运行时缺陷。

修改后实际执行：

| 命令或检查 | 本轮结果 |
| --- | --- |
| 根 `fvm dart analyze` | 无问题 |
| `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/ui_fragment_generator_test.dart` | 40 项通过，含修改前失败的 10 项诊断断言 |
| `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/workspace_validator_test.dart packages/ccrouter_test/generator_test/component_dependency_preflight_test.dart` | 67 项通过 |
| `fvm flutter test packages/ccrouter_test/test` | 框架全量 565 项通过 |
| `cd demo` 后 `fvm flutter test --no-pub` | Demo 全量 61 项通过，含真实 UI 选择、Props 更新、保活及模拟账号重建 |
| `ccrouter portable prepare demo` / `ccrouter portable publish demo` | 9 个 Package 就绪；仅本地生成和就绪校验，不联系 Pub/Git 发布 |
| `ccrouter generate demo --check` | 缓存 fast path 通过 |
| `ccrouter generate demo --no-cache --check` | 通过，Builder 写出 0 个输出；校验 6 个组件、34 条 Route、12 个生成 Package |
| 文档链接、敏感信息、独立 Skill bundle 与 CLI 检查 | 通过；新审查文档的本地链接另行核验 |
| `git diff --check` | 通过 |

以上 `ccrouter` 使用 `fvm dart run --verbosity=error ccrouter_generator:ccrouter`。
当时仅 9 个 Portable State 文件有生成差异：工具、解析闭包与 content fingerprint 更新，
Demo State 另包含测试源码变化对应的 authored fingerprint。与当时 HEAD 对比，全部 State 的
`metadataFingerprint` 和 `managedOutputFingerprint` 不变；生成 Dart、Package metadata
和 Catalog 没有字节差异。未手工修改生成文件。

本轮没有运行生成器全部 CLI/watch 用例、平台构建/真机矩阵、真实账号 Session 或长期内存压力测试；
本次主机回归和静态接入成本分析不替代这些验收。

## 剩余验收与后续触发条件

当前三个代表场景已有仓库回归，enum/DTO 独立接入闭环也已验证。文档与技术闭环收口不等于
可用性研究完成、正式分发就绪或 API 最终冻结；不应仅为减少声明数量增加新抽象。

下一步优先由未参与实现者按指南完成首次接入、多实例及保活/账号场景，记录漏配、修正步骤与
理解成本，再决定是否调整 API。正式分发与升级、真实平台和长期内存/性能需分别验收。
UI DevTools Catalog、完整 schema 的编辑时校验仍未实现；sealed union、Slot 和动态实现替换
只在真实需求触发后独立设计，不作为当前接入的前置工作。

## 第二阶段：首次接入工具增量与历史验证

`create ui-fragment` 新增契约、显式公共 barrel 和可选 Renderer 模板，支持无写入
`--dry-run`。调用者指定已有 Owner 常量的源文件和符号，不复制 ID、不创建第二个 Owner。
工具拒绝覆盖及越过 symlink/nested Package 的目标；existing pubspec、组件定义和公共 barrel
只提供明确后续编辑步骤，不猜测 Hosted/Git/Path 来源。生成校验继续证明真正的 Owner 和 schema。

`find <ui-id> <host-root> --usage <consumer-id>` 从已验证 Package Index 输出 UI 源码位置、
完整 schema 的公共 import、直接 Pub 依赖、required Owner edge 和已声明 alias 的真实 Client。
UI Client 保留完整组件 ID，避免错用 Service/Command Client 的去后缀规则。
缺失依赖仅提供显式 placeholder；旧 metadata 无公共导出或 alias 时要求重生成。
该增量不扩展旧 DevTools Catalog 的 kind schema，不运行生成，也不修改被查询工程。

这降低模板编写和查找配置的成本，但没有消除四个角色的必要声明，也没有测得新人接入耗时。
工具不是 API 冻结依据。[Action payload 设计与验证](CCRouter-ui-fragment-action-payload-design.md)
记录随后已实现的 DTO 增量、DTO/union 权衡、兼容与生命周期验收。

以下为当时的工具验证快照，早于 DTO 实现：

- 新增工具测试共 13 项完成验证，包括真实 UI Builder、dry-run、覆盖拒绝、导出歧义和旧
  Service 索引隔离；新增隔离用例在最后一轮单独执行。Demo UI 专项 2 项通过。
- 相关五文件回归首轮 119 项中 116 通过、2 项 metadata 身份断言失败、1 项契约迁移触发
  默认 30 秒超时。保持断言，最终源码下重新启动进程，metadata 2 项复跑通过；迁移与
  Workspace 校验以 `--timeout 3m` 复跑 56 项通过。不是一次完整回归全绿。
- 最终根 `fvm dart analyze` 无问题；文档、独立 Skill bundle/CLI 命令面及敏感信息检查通过。
- Demo 脚手架 dry-run 无写入；真实 UI `find --usage` 确认公共 import、required edge 和
  `DemoNavigationLabComponentFragments.orderSummary`，没有猜测 Service/Command 命名规则。
- 正常 `portable prepare demo` 更新生成索引与 Portable State；`portable publish demo`
  校验 9 个 Package 就绪。缓存 `generate demo --check` 与无缓存
  `generate demo --no-cache --check` 均通过，后者 Builder 写出 0 个输出。
  未手工修改生成物；UI Client/Renderer 调用签名和 Contract shape fingerprint 不变。

最终 CLI smoke 显式绑定已有 Workspace Package config，使用
`fvm dart --packages=.dart_tool/package_config.json packages/ccrouter_generator/bin/ccrouter.dart`
作为本地可执行入口，避免 `dart run` 隐式触发无法解析 Flutter 依赖的 Dart-only Pub。
未执行真实新人接入计时或外部发布。

## 第三阶段：UI Analyzer 检测与历史验证

新增 UI 声明身份、alias/重复依赖、明显非法范围、普通 enum Action、Renderer 签名和
Host/Generated SPI 边界检查。UI Owner 复用 required edge 检查，仅在公共常量已导入且
列表可安全编辑时提供 Quick Fix。UI metadata 新增可移植源码引用；Host 错误通过现有
结构化快照进入 IDE。未知类型、旧 metadata 和不可安全编辑的集合延迟到 Generator，
不增加第二套 Props schema 或自动 import/角色修复。
后续 DTO 检测和实际 Demo bootstrap/LSP 证据见[Action payload 记录](CCRouter-ui-fragment-action-payload-design.md)。

本轮验证包括：UI Generator 专项 41 项，加上真实 metadata 源码引用回归 1 项、结构化 UI
校验回归 10 项；Workspace/依赖预检/one-shot 快照 68 项；框架串行全量 565 项；
Demo 全量 61 项；根与独立 Plugin 静态分析；portable prepare/publish；缓存与无缓存
`generate demo --check`。首次并发框架运行有一项 WeakReference GC 断言未通过，串行全量
通过，未修改 Runtime 或降低断言。实际移除 Demo Renderer 注解时，Host 生成发布带消费
声明位置的 `ccrouter_ui_missing_implementation`；恢复后成功生成清空快照。真实 LSP
验证 UI alias 诊断随 editor overlay 出现／清除，以及 UI Host 结构化错误桥接／过期清除。

## 第四阶段：DTO 增量与独立首次接入技术验证

后续[独立消费者验证](validation/ui-fragment-adoption-20261020/README.md)在新的 Pub Workspace 中
完成脚手架预览、创建、显式接线、生成、`find --usage`、enum 回传及受限 DTO 迁移。
新增 4 项 Widget 测试通过；漏配 Owner 会被拒绝，恢复后检查通过。
这也修复了 `ccrouter_ui` 被误判为需业务 Portable State 的框架包识别问题，并补齐各参与包的
生成器开发依赖提示。DTO 已实现的范围以[Action payload 设计](CCRouter-ui-fragment-action-payload-design.md)
和本轮记录为准，早期 enum-only 的拒绝行为属于历史阶段。

样例从已有 Host/A/B/contracts 起步，脚手架创建 3 个文件，仍手动写入或更新 7 个生产文件，
另有 1 个测试文件；其中包含可复用的样例 Widget 公开入口和 Host 展示设置，不是普遍最低成本。
当前已证明技术路径可走通；未参与实现者的首次操作、理解成本与平台/发布矩阵仍待验证。
