# 类型化 UI Fragment 易用性与收敛审查

日期：2026-10-20。范围：静态 v1 的完整接入路径、三个代表场景、生成诊断及既有生命周期回归。
本次为仓库场景演练与代码审查，不是外部开发者可用性研究；未测量首次接入耗时、误配率或生产帧耗时。
历史[实施验收](CCRouter-ui-fragment-acceptance.md)中的测试结果仍只对应其注明的提交。

## 结论与根因

架构边界已明确：A 管布局、输入和操作决策，B 管局部业务 UI，Flutter State 管实例资源，
Host 管静态实现装配。公开消费调用简短，但不能据此认定完整接入简单或公开 API 已最终收敛。

主要成本来自多角色声明和严格的受限 schema。生成 Client 省去了运行时查询，却没有省去
contracts 导出、Pub 依赖、required Owner edge、UI dependency 和 Host 生成。原诊断还把
alias 非法、alias 重复及契约重复合为一条错误，增加了找出正确修正位置的难度。

v1 的 enum Action 无法携带动态业务数据。因此“B 私有加载列表，A 获取被选项 ID”是
明确的能力缺口，而非补一个示例或设置某个开关即可解决。现有推荐 Demo 只证明了无 payload
的选择通知；不能把它作为动态列表选择闭环的证据。

## 三个场景及复现证据

| 场景 | 期望与现状 | 分类 | 证据与边界 |
| --- | --- | --- | --- |
| A 展示 B 的固定订单摘要 | A 传 orderId，B 展示并发出 openDetails，A 用已知 ID 决策；已支持 | 已支持接入 | `demo/test/ui_fragment_demo_test.dart` 使用真实 Host、Renderer 和生成 Client；补充选择订单 1、Props 更新后选择订单 3 的断言，验证 A 使用最新输入 |
| B 私有加载推荐列表，选择后向 A 返回 selectedId | enum 只能表达动作种类，无法携带动态 ID；不支持 | 待设计的通用能力 | `ui_fragment_generator_test.dart` 用带 selectedId 的 const Action DTO 复现拒绝；不通过全局选择状态、Service getter 或 Event 绕行 |
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

Host 仍传一个生成 Assembly，无需手写 UI 注册或修改原 initialize 调用形态。
生成 Dart、metadata、fingerprint、Portable State 不计入手写成本，也不能手改。
同一 Fragment 的多实例只消费一个契约，依赖 alias 是方法名，实例由 Key 区分。

## 候选方案与本轮决策

| 方案 | 收益 | 代价、兼容与回退 | 决策 |
| --- | --- | --- | --- |
| 普通公共 Flutter Widget + 显式依赖/注入 | 成本低，可用普通数据型回调 | 没有 CCRouter UI 契约和装配校验；适合所有权与依赖方向已明确的普通组合 | 保留为轻量选项 |
| 保留 v1，补完整指南、场景证据和定位明确的诊断 | 减少试错，不扩大业务 API | 多角色声明成本仍存在；可独立回退诊断及文档变更 | 本轮实施 |
| 自动从 uiDependencies 推导 required Owner edge | 少写一项 | 改变显式组件图及既有校验约定，会影响更多能力的一致性 | 本轮不采用 |
| 扩展数据型 Action | 能覆盖动态列表选择 | 需要 schema、指纹、公共导出、兼容、生成和 Host 校验的完整设计 | 下一项独立能力设计，当前未实现 |
| 通用 Slot、动态实现替换或新 Fragment Scope | 更大扩展能力 | 增加调度、资源、装配与生命周期语义，当前三个场景均不需要 | 延期 |

## 本轮实现与故障修正

- Builder 的缺失 Owner 提示包含 consumer、Owner、契约及 `CCComponent.dependencies` 修正位置；
  明确 `optionalDependencies` 不满足消费要求。同 Owner 的误用指向普通局部 Widget。
- 拆分 `invalidAlias`、`duplicateAlias` 和 `duplicateDependency`。重复契约提示只声明一次，
  多次调用并使用不同 Key；没有增加新业务 API，也没有放宽原有拒绝条件。
- 无效 `versionRange` 包含 consumer、契约、实际范围及基于当前 Contract 版本的示例。
- 非法 Action 类型说明 enum 边界与动态 payload 缺口，避免开发者误以为 DTO 回调已经支持。
- Workspace 的 missing Owner / missing Renderer 提示包含消费方和 Host 修复路径。
- 接入指南补齐四个角色的步骤、完整最小代码和错误修正表；README 与 Integration Skill 同步。

没有新增长期资源或所有权。运行时仍由 B State 取消请求、释放 Controller/Timer，A 在账号变更时
显式清除旧账号状态或重建子树；active 不自动暂停工作、不表示像素可见性或权限。
运行时诊断仍不记录 Props 或 Action payload。本轮错误消息只使用 authored 静态声明信息。

回退仅需还原这次诊断和指南改动并按正常流程重新生成；旧契约、客户端签名和运行时语义不变。

## 数据型 Action 的后续设计边界（提案，未实现）

先用“推荐项选择”和“设备项选择”两个场景评估一个普通不可变 DTO Action 是否足够。
候选是保留 enum，并允许单个 final/const DTO 携带最小 selectedId；复用受限 Pure Dart DTO
约束，继续排除 Flutter 类型、callback、Stream 和动态对象图。该候选尚不能用于现有注解。

与 sealed union 相比，单 DTO 的新增类型规则较少，但多个动作若靠 kind 加可空字段区分，
容易产生无效组合；不能把 enum-plus-nullable-fields 包装成通用动作协议。如果两个场景需要
多个异构 payload，应重新比较封闭 union 的收益和生成成本，不先发布宽泛 Object/Map Action。

扩展必须满足以下门槛再进入实现：

1. 新 Action 形状纳入 schema、公开类型导出、SemVer 与 fingerprint，保留既有 enum 契约语义。
2. 明确旧生成器的拒绝行为和是否需要提升 UI schema，不能静默接受新声明。
3. A 接收实例局部的类型化数据；同步 callback 错误遵循 Flutter，不自动转 Event、重试或持久化。
4. 延续当前 mount、active 和 generation 的 Action 防护；多实例、Props 更新、账号切换、
   卸载及 shutdown 后的旧 Action 不得污染新实例；请求竞态仍由 B 管理。
5. 验证错误类型、公共导出、兼容漂移、真实跨 Package 选择、隐藏及销毁后的延迟回调。
6. 不保存 payload 到全局 catalog/诊断；对比 enum 和 DTO 调用成本后再决定发布范围。

## 验证记录

修改前：新增的 10 项诊断断言全部失败，分别复现缺失上下文、合并式错误及 payload 边界说明缺失。
它们证明的是诊断缺口；数据型 Action 被拒绝是当前既定边界，不是本次修复的运行时缺陷。

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
仅 9 个 Portable State 文件有生成差异：工具、解析闭包与 content fingerprint 更新，
Demo State 另包含测试源码变化对应的 authored fingerprint。与 HEAD 对比，全部 State 的
`metadataFingerprint` 和 `managedOutputFingerprint` 不变；生成 Dart、Package metadata
和 Catalog 没有字节差异。未手工修改生成文件。

本轮没有运行生成器全部 CLI/watch 用例、平台构建/真机矩阵、真实账号 Session 或长期内存压力测试；
本次主机回归和静态接入成本分析不替代这些验收。

## 收敛完成条件与剩余范围

当前可以确认：既有两个受支持场景有仓库回归，第三个场景被明确拒绝，接入成本和修正路径已公开。
这不等于已经完成可用性研究、支持所有业务 UI，或 API 已最终冻结。

后续应由未参与实现的接入者按照指南完成首个摘要，再完成多实例及保活账号场景，记录遇到的
漏配和错误修复步骤；动态选项回传则必须等数据型 Action 通过上述门槛。UI 专属脚手架、
find --usage、DevTools Catalog、完整 schema 的编辑时校验、真实平台矩阵及长期内存/性能验证仍是剩余范围。


## UI Analyzer 检测补充

新增 UI 声明身份、alias/重复依赖、明显非法范围、普通 enum Action、Renderer 签名和
Host/Generated SPI 边界检查。UI Owner 复用 required edge 检查，仅在公共常量已导入且
列表可安全编辑时提供 Quick Fix。UI metadata 新增可移植源码引用；Host 错误通过现有
结构化快照进入 IDE。未知类型、旧 metadata 和不可安全编辑的集合延迟到 Generator，
不增加第二套 Props schema 或自动 import/角色修复。

本轮验证包括：UI Generator 专项 41 项，加上真实 metadata 源码引用回归 1 项、结构化 UI
校验回归 10 项；Workspace/依赖预检/one-shot 快照 68 项；框架串行全量 565 项；
Demo 全量 61 项；根与独立 Plugin 静态分析；portable prepare/publish；缓存与无缓存
`generate demo --check`。首次并发框架运行有一项 WeakReference GC 断言未通过，串行全量
通过，未修改 Runtime 或降低断言。实际移除 Demo Renderer 注解时，Host 生成发布带消费
声明位置的 `ccrouter_ui_missing_implementation`；恢复后成功生成清空快照。真实 LSP
验证 UI alias 诊断随 editor overlay 出现／清除，以及 UI Host 结构化错误桥接／过期清除。
