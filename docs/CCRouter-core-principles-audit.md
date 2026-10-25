# CCRouter 核心价值与开发约定回归

本文按日期保留审查快照；其中旧 `CCGoRouterApp`、attach 和第二 Backend 待验证等结论
只代表当时架构。GoRouter 兼容包已退役，当前能力见[状态矩阵](README.md)，最新源码回归、
平台证据与尚未重验范围见[验证索引](validation/README.md)，不从历史“满足”项推断当前全面通过。

2026-10-23 边界收口：Core 不再接收访客/应用 Session 身份，不保留恢复需求队列或布局策略。
下文 Telemetry Context、Restoration Listener/Source 等条目是历史实现；当前身份快照与校验
归应用观察桥，框架仍校验稳定的导航 Source 标识。布局由应用决定，再通过 Host SPI 同步可见 Outlet。

## 2026-10-24 核心价值收口回归

当前原生 Managed 与绑定导航入口的 13 条核心价值逐项判断、源码身份、实际命令和原始
结果统一见[本轮回归报告](validation/20261024-core-value-final/report.md)。本轮分别运行
框架、Generator/CLI、独立 Plugin、Demo/独立 Example、工具、DevTools、应用侧示例和
有界压力检查；历史 GoRouter 结论和真机认证不自动延续。

行为验证与发布就绪分开判定：当前 tracked files 的敏感信息检查发现历史验收文件仍含
本机路径，门禁未通过；华为真机报告中的 Demo 样式、文案、Native/Graphics 内存增长和
长帧待办也不由源码测试关闭。后续按报告建议顺序处理，不把自动化通过写成全平台无缺陷。

后续执行情况见[遗留项收口](validation/20261024-closure/report.md)：Demo 问题和当前验收材料
路径门禁已修复；真机受控复测与原始 Monkey 分开记录，以上保留当轮事实。
后续[Native 分配归因](validation/20261024-native-attribution/report.md)已补齐匹配符号与
完整采样，并在不初始化 CCRouter 的纯 Flutter 字体样例复现主要增长；底层持有/淘汰
路径和原长帧仍未关闭，不能据此宣称框架所有资源均无泄漏。

## 2026-10-20 审查项修复

下节保留 `672d057` 的修复前审查快照及首次验证结果；R01–R03 已在本次工作区修复，
原生成器全量超时记录仍保留，不改写为通过。

根因是框架包的“无需业务索引”规则只用于缺失校验，生成与查询仍读取遗留索引；同时，
主 Demo 的 freshness 门禁没有覆盖独立 Example Host，CLI Skill 的 schema 说明也未同步 DTO。
仅刷新现有产物成本较低，但不能解决旧索引重新出现时的身份漂移；删除遗留文件同样不能
保护旧安装。采用统一框架依赖扫描规则，保持非框架业务 Package 的 fail-closed 校验。

1. R02：生成聚合和 `find` 复用内部框架包分类，跳过框架依赖的业务索引。既有文件保留
   时也不参与身份计算，writable/read-only 路径一致；未放宽其他可选包的验证，未增加业务 API。
2. R01：通过 CLI 重生成主 Demo 和独立 Order Example 的 Host Bundle/Package Index，
   并用 `portable prepare demo` 刷新显式 opt-in Package 的 Portable State。
   CI 在 Demo 测试前分别检查两个 Host 的无缓存 freshness，并补独立 Example Widget 测试。
3. R03：CLI Skill 明确 enum 的 UI schema 1 / Index 3、DTO 的 UI schema 2 / Index 4、
   混合文档最高版本与非 UI Index 2；README、Integration Skill 和生成指导同步身份及多 Host 规则。

新增的生成与查询回归在修复前均失败，修复后通过。生成回归覆盖遗留索引损坏与缺失、
writable 与 read-only、缓存与参考路径；已有 clean 回归增加重建前后 Demo 产物逐字节
一致断言，查询回归也要求不修改索引。业务依赖缺失、混合身份和 Portable State 的既有
负向回归继续执行。代码和生成物可作为一个改动整体回退，没有改变 Runtime 或 Contract shape。

修复验证：相关 Generator/CLI 六个测试文件 **73 项通过**，含 clean parity、
Host aggregation、Package workspace、Route/UI find，以及独立 Git/归档消费；仓库工具
14 项、主 Demo 62 项、独立 Example 1 项均通过。根静态分析、文档和发布敏感信息检查通过；
两个 Host 的缓存与 `--no-cache --check` 均通过，Example 的 `order.detail` 查询和主 Demo 的
`order.summary --usage demo_navigation_lab_component` 查询通过。`portable publish` 仅做本地验证，
主 Demo 的 9 个、Example 闭包的 2 个 opt-in Package 状态均有效，未执行发布。
命令与产物 SHA 见[修复验证记录](validation/core-value-remediation-20261020.json)。

未重复执行修复前约 52 分钟的 Generator 全量，也未把前一轮框架、Plugin 和性能结果计入
本次修复测试数量。修复前全量的单项超时与网络 smoke 跳过仍保留在原证据中。

本次验证仍使用 macOS 上的 OHOS Flutter SDK；没有执行远端 CI、平台构建、用户 IDE
重启或 Plugin pin 更新。修复不改变 Analyzer Plugin production code。

## 2026-10-20 最近提交审查与核心价值回归

审查对象为 `672d057`，范围为 `ee83979..672d057` 的最近 10 个提交，包含
Event deadline、诊断背压与启动回滚、导航历史释放，以及 UI Fragment DTO Action、
Analyzer 身份校验和 Demo pin。开始时工作区干净。本轮仅新增审查证据和文档，
没有修改框架、Demo、生成物或 Plugin pin。

### 审查发现

**R01 / P2：独立 Order Example Host 的生成身份未随依赖同步。**
[Example Package Index](../demo/modules/order/example/lib/src/ccrouter_generated/metadata/ccrouter_package.json)
仍引用旧的 `demo_order` 和 `demo_order_contracts` contentFingerprint。
`ee83979` 基线中的两个引用均匹配；`1e35b42` 更新依赖产物后变为不匹配，`672d057`
再次升级 DTO/schema 时仍未刷新这个独立 Host。主 Demo 的 `generate demo --check`
只验证其依赖闭包，不涵盖这个子目录里的独立 Host。

实测 `generate demo/modules/order/example --no-cache --check` 退出 1，列出 Example 的
Host Bundle 与 Package Index 陈旧；`find order.detail demo/modules/order/example` 同样退出 1，
明确报告 Example 引用了不同的 `demo_order` identity。Example Widget 测试 1 项通过，
说明此处已确认的是生成新鲜度与工具身份校验回归，不能直接推断页面运行失败。

最小修复是从生成器运行 `generate demo/modules/order/example`，提交其更新的 Host Bundle
和 Package Index；不要手改 fingerprint。把两个真实 CCRouter Host 的 `--check` 都纳入
维护回归。这个问题不证明 Runtime 算法失效，但当前已提交 Example 未满足生成新鲜度和
Package 身份约定，不能由主 Demo 门禁通过推断整个 Workspace 均已同步。

**R02 / P2：UI 框架包归类后，遗留空索引仍影响生成身份。**
`672d057` 在 [Package Workspace](../packages/ccrouter_generator/lib/src/package_workspace.dart)
将 `ccrouter_ui` 归为不发布业务 metadata 的框架包，但仍提交其旧空 Package Index，
主 Demo、Order 和 Navigation Lab 产物也仍记录该索引的 fingerprint。
全量测试执行 clean 后，这个不再生成的旧索引被移除，依赖包 identity 随之变化。

为排除测试残留，本轮把其余所有产物恢复为 HEAD 原始字节，仅保留测试清理后的旧索引缺失
状态：主 Demo `generate demo --no-cache --check` 退出 1，报告 6 个文件陈旧、只发现
11 个生成 Package；随后从 HEAD 恢复该空索引，不改源码或其他产物，同一命令退出 0，
发现 12 个生成 Package。说明当前可复现产物取决于已不再发布的遗留文件，破坏 clean 与
现有工作区生成一致性。没有据此证明 Runtime 执行异常或发布安装必然失败。

推荐统一框架包身份规则：生成依赖扫描一致忽略该遗留框架索引，或在迁移时通过 CLI 清理旧
产物并重生成两个 Host、刷新 Portable State；两种方案都需补 clean-generation parity
回归。不要手改依赖 fingerprint，也不要将“忽略所有可选包索引”作为通用修复。
本轮已恢复旧文件及所有测试改动，仅保留证据。

**R03 / P3：CLI Skill 遗留 enum-only 的 schema 规则。**
[CLI Skill 的 Generated Output Rules](../skills/ccrouter-cli-development/SKILL.md)
仍将 UI Package Index 一律写为 schema 3、源 metadata 的 UI 版本一律写为 1。
`672d057` 已加入 DTO Action，其真实产物为 UI schema 2 / Package Index 4；
同文前面的 DTO 支持说明和 Generator README 已采用新规则。维护者或接入 Agent 按旧段落
判断生成物时，会将合法 DTO 产物误判为不符合约定。应明确区分 enum 的 1/3 与 DTO 的 2/4，
并说明混合 metadata 文档取最高 UI 版本、非 UI Index 仍为 2。生产实现已有覆盖，
无需修改 schema 或增加 Runtime API；本轮按审查范围记录，未改写该接入 Skill。

### 问题分析与审查结论

发现两处生成身份/交付回归与一处文档漂移；所查框架 Runtime/Core 实现未发现新的高置信度
算法缺陷，也没有证明新的 `not-disposed` 或 `not-GCed` 问题。结论仅覆盖本节范围和已执行测试，不构成全部平台、生产流量或任意
Sink/Backend 的无缺陷证明。生成器全量首次存在一项 30 秒超时，详见验证表，不能称为
“全部门禁首次通过”。

近期改动对应三个具体问题，而非无场景扩展 Core：

- Event 子调用的 Timer 毫秒截断可能早于共享 deadline；现向上取整，并保留结束时的
  deadline 复核，避免把整体超时误记为孤立 Subscriber 失败。
- 有界诊断队列原先不能限制未完成 Sink Future，导航历史原先可能延长 Route 生命周期。
  新投递 Owner 限制单个在途写入，关闭释放队列/Sink；历史快照只保留值。启动回滚使用
  成功完成、携带错误数据的共享 Future，使跨 error Zone 的 shutdown 可以加入清理。
- B 私有加载选项后向 A 回传 selectedId，需要携带数据的 Action。受限不可变 DTO 沿
  既有可选 UI 包扩展，未向 Core 引入 Widget、动态注册或新的调度能力。schema 与
  Package Index 升级保留旧 enum 路径；Demo Contract 正确升 major 并同步消费范围。

Analyzer 的 declaration library 身份、typedef/part、真实构造调用证明和跨包刷新已复核；
它仍是可选诊断工具，不能替代生成校验。Demo pin-check 证明当前完整 SHA、lock 和远端
身份一致且无 Plugin production drift；本轮没有重启用户 IDE，不能宣称其活跃实例已加载。

### 13 条约定回归

“保持”表示所查实现及测试未发现新增退化；有条件项保留其未验证边界。

| # | 核心价值 | 本轮判断与证据 |
| --- | --- | --- |
| 1 | 智能 | 机制保持、产物一致性有缺口（R01、R02）：声明、生成 Client、Host Assembly 和静态 Owner 索引承担胶水；不依赖运行时反射猜测 |
| 2 | 简单易用 | 有条件：scaffold/find 减少模板和查找成本，首次 UI 接入仍需协调 Contract、A/B、Host；未测新人耗时和误配率 |
| 3 | 功能强大 | 保持明确范围：typed Route/Service/Command/Event/InitTask 回归，UI 支持单 DTO 与受限 sealed union 输出；不包含集合、动态 Slot 或完整 Restoration |
| 4 | 可扩展性 | 保持分层：Contracts/Core 仍为 Pure Dart，UI 与 GoRouter 独立；尚无第二个生产 Backend 验证 |
| 5 | 可测试 | 分层保持，独立 Host freshness 与 clean parity 门禁有遗漏（R01、R02）：框架、Demo、生成器、独立 Plugin 和真实 Server/LSP 分层；不把 UI process-default Runtime 说成 TestHost overlay 隔离 |
| 6 | 最小公开 API | 保持：业务 Facade 不导出 Host 生命周期、Runtime 和 Adapter SPI；UI 业务、generated、Host barrel 分离，API 反向编译探针通过 |
| 7 | 编译校验与类型安全 | 校验保持，产物未完全满足当前身份（R01、R02）：DTO UI schema 2 / Index 4 与 enum schema 1 / Index 3 区分；shape、Owner、版本和 public exports 继续 fail-closed |
| 8 | 非侵入式 | 保持：UI 按需启用，沿用 Flutter Key/State；普通 Widget 和局部弹层不要求框架化 |
| 9 | 可降级回退 | 保持边界：旧 enum 路径保留；缺 Renderer 或混合 schema 显式失败。DTO → enum 需迁移消费点和重生成，不能当作热开关 |
| 10 | 明确生命周期 | 保持所测路径：单在途 Sink、构造失败 deferred cleanup、Host rollback、Route/Controller 弱引用回收及 UI 卸载/旧回调失效通过 |
| 11 | 可观测与溯源 | 保持：有界值快照与无 payload 计数，UI find 和结构化 IDE 诊断已存在；UI DevTools Catalog 仍未实现 |
| 12 | 并发安全 | 保持所测路径：共享 deadline、嵌套较短 timeout、跨 error Zone 清理加入、重复 shutdown 与旧 UI generation 终态受保护 |
| 13 | 性能和稳定 | 有界行为通过，生成一致性有缺口（R02），性能趋势未定：补跑 Runtime/Service、并发、长运行、Analytics、诊断和导航历史基准；不由单次 RSS 或主机耗时推断生产性能 |

主要复核入口为 [调用与 deadline](../packages/ccrouter_core/lib/src/runtime_host.dart)、
[诊断投递 Owner](../packages/ccrouter_core/lib/src/diagnostic_delivery.dart)、
[Host 清理](../packages/ccrouter/lib/src/host_lifecycle.dart)、
旧导航历史（历史路径 `packages/ccrouter_go_router/lib/src/adapter.dart`，现已退役）、
[UI schema 生成](../packages/ccrouter_generator/lib/src/ui_fragment_generator.dart)、
[UI Analyzer](../packages/ccrouter_analyzer_plugin/lib/src/ui_fragment_analysis.dart) 和
[Demo Renderer](../demo/modules/order/lib/src/order_fragment_renderers.dart)。

### 候选方案、取舍与推荐顺序

| 方案 | 收益 | 成本与判断 |
| --- | --- | --- |
| 继续扩展通用 Action/动态 UI/Core 调度 | 增加能力组合 | 增加 schema、生命周期和工具维护面；目前没有新的必要性证据，不推荐本轮推进 |
| 回退到 enum-only 或放松 Owner/shape 校验 | 可减少部分规则 | 丢失私有加载结果回传能力或削弱组件边界；不推荐 |
| 保持受限 DTO 与可选路径，先巩固验证和接入 | 满足真实 selectedId 场景，保留 Core 边界和旧 enum 对照 | 仍需承担四角色声明和工具维护；推荐 |

1. 先统一 R02 的框架包索引身份，验证 clean 与现有工作区的生成结果一致，再通过生成器
   刷新 R01 的独立 Example Host，执行两个 Host freshness、Widget 和 Portable State 回归，
   同步 R03 的 CLI schema 说明。保持现有 Runtime/API 分层；保留生成器首次超时与单项复跑结果，若继续复现再定位
   冷启动/资源竞争或时限设置，不以重复运行掩盖问题，也不直接放宽功能断言。
2. 下一次接入继续从一个真实消费者的“契约 → 生成 → 调用 → 失败/取消 → 释放”闭环出发，
   记录手工步骤和误配点，再决定是否调整工具；不以新增抽象代替接入问题定位。
3. 面向 RC 再补标准 Flutter SDK、目标真机和发布归档/Hosted 安装升级验证；API 冻结、
   License、发布集合等仍遵循[唯一发布清单](CCRouter-release-readiness.md)。

### 本轮验证与边界

环境为 macOS、Flutter `3.41.10-ohos-1.0.0`（`62357a93d6`）、Dart `3.11.5`。
这是 OHOS Flutter SDK 在 macOS 主机上的验证，没有执行平台构建或真机测试。
命令、结果和性能快照见[机器可读记录](validation/core-value-regression-20261020.json)。

| 验证 | 本轮结果 |
| --- | --- |
| Framework `fvm flutter test packages/ccrouter_test/test` | 566 项通过 |
| 主 Demo `fvm flutter test test` | 62 项通过 |
| 独立 Analyzer Plugin `fvm dart test` | 173 项通过，含真实 Analysis Server/LSP |
| Generator `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test` | 642 项通过、1 项跳过、1 项失败；耗时 52 分 23 秒 |
| Generator 超时单项复跑 | `route_contracts resolves transitive cross-package inputs and constants` 以 2 分钟上限复跑，11 秒通过；原全量仍记失败，首次超时原因未证实 |
| Workspace / 独立 Plugin `fvm dart analyze` | 均无问题 |
| 主 Demo 参考生成 / 缓存检查 | 原始 HEAD 产物状态下均通过，6 组件、34 Route、12 生成 Package |
| UI 遗留索引对照 | 缺失旧索引时主 Demo freshness 失败；恢复旧索引即通过，确认 R02 |
| Order Example | freshness 与 find 各退出 1，复现 R01；Widget 测试 1 项通过 |
| Analyzer `pin-check demo` | 完整 SHA、manifest/lock/远端一致，无 production drift；不代表用户 IDE 已加载 |
| 文档校验 | 119 个 Markdown 通过 |
| 性能与生命周期基准 | 默认 5 个回归程序、诊断投递、导航历史基准均完成；适用边界见下文 |

补充边界探针验证“DTO Action 内的 enum 默认值从 first 改为 second”会改变 fingerprint，
1 项通过；探针放在临时目录，未增加框架测试或改写生产源码。

Runtime 长运行完成 1000 轮，RSS 从约 197.6 MiB 到 229.4 MiB（增加约 31.8 MiB）。
该脚本没有强制 GC 或对象 retaining path 证据，且本机存在其他开发进程；不能据此报告
内存泄漏，也不能据此宣称长期 RSS 稳定。弱引用释放测试只证明其特定资源的回收路径。
Analytics 5000 次事件压力中队列峰值为 64，关闭后 pending 为 0；10 × 100 并发导航后
保留 1 个根 Entry，pending 为 0。导航历史的同进程旧实现参考与快照实现覆盖容量
0/2/1000/10000；小容量存在分配开销取舍，大容量写入避免线性移位。这不是 UI 帧率测试。
诊断 off/sync/Future 三种模式均完成每轮 10000 次 Command，启用投递的模式未丢事件；
未与旧提交作完整应用 A/B，不给出整体性能提升比例。

本轮没有复跑独立 Hosted/发布归档消费者，没有做业务真实认证、全平台构建、长期 Heap/RSS
或用户当前 IDE live 验证；Analyzer 网络安装/升级 smoke 默认跳过，未额外开启；已有历史证据不累计为本轮结果。


## 2026-10-19 增量回归

审查基线：`283b00b37ed71c13acea9d22691b6988d75fb60b`。本节记录该基线与本轮局部修正，
后文保留历史审查，不将旧测试数量和平台结果累计为本轮证据。

### 问题分析与结论

CCRouter 的核心价值是：**组件通过类型安全契约协作，由生成工具承担装配胶水，由明确的
Owner 和生命周期保证调用、取消与释放的一致性。** Route、Service、Command、Event、
InitTask 和可选 UI Fragment 应按场景选择，不应成为每个普通方法或 Widget 的必经层。

本次静态复核聚焦业务/Host/generated API 边界、Core 依赖、UI generation、预测返回
opt-in 与终态、Event deadline，以及 watch 初始化失败清理；结合框架全量和 Demo 测试
检查既有约定。没有在这些复核路径发现新的高置信度框架缺陷或 `not-disposed` /
`not-GCed` 问题；这不是对全部生产源码、插件或平台组合的无缺陷证明。

主要风险来自接入认知和证据分散：根 README 已同时承载最小接入、大量高级规则与工具维护，
本报告原主体仍是 9 月快照。功能隔离仍在，但“已有实现”不能直接推出“新团队容易接入”。
可替换 Backend 目前也主要由契约隔离与 GoRouter 实现支撑，尚无第二个生产 Backend 的验证。

本轮发现并修正 Demo 入口未使用的 `dart:io` import；首次根分析因此退出 2，修正后无问题。
发布候选清单遗漏已存在的可选 `ccrouter_ui`，本轮补入可选集合；不替 Owner 冻结发布集合。
本报告新增当前证据入口，保留历史结论及其适用时间。

### 候选方案与取舍

| 方案 | 收益 | 代价与判断 |
| --- | --- | --- |
| 继续按能力清单扩张 Core | 快速增加覆盖面 | 扩大 API、生命周期和测试组合；缺少真实消费者时不采用 |
| 立即合并或删除现有能力 | 表面减少 Package/API 数量 | 破坏已有契约与可选接入，迁移和回归成本高；本轮证据不支持 |
| 保持边界，按生产场景收敛接入与质量证据 | 保留可回退实现，把成本用于真实接入 | 需要干净消费者和长期验证；推荐，当前仅做局部修正与证据更新 |

### 13 条约定逐项复核

“保持”表示本次所查实现与已执行测试未发现该约定的新增退化，不表示穷尽证明。

| # | 核心价值 | 本次判断 | 实现依据与适用边界 |
| --- | --- | --- | --- |
| 1 | 智能 | 保持 | 仍以声明、生成 Client 和原子 Host Assembly 装配；UI 复用生成入口，不靠运行时反射猜测依赖 |
| 2 | 简单易用 | 有条件保持 | 默认 Host 仍使用一个 Assembly；UI、高级 Host、预测返回按需接入。后续已补本地独立消费者闭环和首次接入指南，团队可用性与发布来源仍待验证 |
| 3 | 功能强大 | 保持范围 | 六类能力各有场景；普通 API 优先规则仍在。动态组件、完整 Restoration、原生多窗口不计入已实现能力 |
| 4 | 可扩展性 | 保持隔离 | Core/Contracts 无 Flutter、dart:ui、GoRouter 或 UI 包 import/export；第二个生产 Backend 的可行性仍待实际验证 |
| 5 | 可测试 | 保持 | 框架、Demo 与生成器边界测试分层，后续另补真实 App 14 项及独立消费者 4 项。UI 仍只支持 process-default Runtime，不声明 TestHost Zone overlay 隔离 |
| 6 | 最小公开 API | 保持分层 | `ccrouter.dart` 隐藏 Runtime、Scope、生命周期与 Adapter SPI；UI business/generated/Host 独立 barrel；Dart 正反向编译探针纳入框架测试 |
| 7 | 编译器校验与类型安全 | 保持 | UI DTO/enum/default fingerprint 和跨组件依赖由 Generator 校验；Runtime 继续复核 generated caller/Owner。可选 Plugin 不取代生成门禁 |
| 8 | 非侵入式 | 保持 | UI 沿用 Flutter State/Key；预测返回默认 false，关闭时不创建 bridge/fallback history；普通 Widget、局部弹层仍可用原生 API |
| 9 | 可降级回退 | 保持 | 预测返回不满足条件时保留 Flutter fallback；required UI 装配错误显式失败。移除 UI 消费需要迁移消费点并重新生成，不冒充运行时热开关 |
| 10 | 明确生命周期 | 保持所测路径 | UI detach 使 generation 失效并清空活动工厂表；旧 Action 不跨 Runtime；手势提交仍受原 Owner 约束；watch 异常需先停 child 再释放锁 |
| 11 | 可观测可诊断可溯源 | 保持范围 | UI 诊断最多 128 条且无 Props/Action；预测返回 fallback 沿用有界容量；UI 专属 find/DevTools/IDE 仍未实现，本轮未重新验收这些工具 |
| 12 | 并发安全 | 保持所测路径 | Event 共享 deadline 失败不转成 Subscriber 噪声；更短嵌套 timeout 保持隔离。旧 UI 回调和失效手势均有终态保护 |
| 13 | 性能和稳定 | 有界状态通过，趋势待验 | 资源释放与诊断容量回归通过；不将本次测试耗时当性能基准，也不将实例归零当长期 Heap/RSS 证明 |

主要源码与回归入口：

- [业务 barrel](../packages/ccrouter/lib/ccrouter.dart)、[API 隔离测试](../packages/ccrouter_test/test/api_surface_test.dart)。
- [UI generation 与 State](../packages/ccrouter_ui/lib/src/ui_fragment.dart)、[UI 生命周期测试](../packages/ccrouter_test/test/ui_fragment_test.dart)。
- [Flutter 手势终态](../packages/ccrouter/lib/src/flutter_predictive_back.dart)、旧 Adapter bridge（历史路径 `packages/ccrouter_go_router/lib/src/predictive_back_bridge.dart`，现已退役）、[预测返回测试](../packages/ccrouter_test/test/predictive_back_test.dart)。
- [调用 deadline](../packages/ccrouter_core/lib/src/runtime_host.dart)、[Runtime 回归](../packages/ccrouter_test/test/runtime_test.dart)。
- [watch 清理](../packages/ccrouter_generator/bin/src/generation_watch.dart)、[watch 故障测试](../packages/ccrouter_test/generator_test/generation_watch_test.dart)、[资源释放回归](../packages/ccrouter_test/test/resource_lifecycle_regression_test.dart)。

### 本轮验证

环境：macOS，FVM 实际解析到 Flutter `3.41.10-ohos-1.0.0`（revision `62357a93d6`），
Dart `3.11.5`。这是 OHOS SDK 在 macOS 上的测试，不是 OHOS 真机执行或标准 Flutter SDK 复验。

- `fvm flutter test --concurrency=1 --reporter expanded packages/ccrouter_test/test`：491 项通过。
- `cd demo && fvm flutter test --concurrency=1 --reporter expanded test`：61 项通过。
- `fvm dart analyze`：首次为上述 unused import 警告，修正后退出 0，`No issues found!`。

- Generator 专项：UI schema/fingerprint、Workspace Validator、内部 API 边界、Route API 边界、
  required Owner 依赖预检共 102 项通过，退出 0。实际命令：

  ```sh
  fvm dart test --concurrency=1 --reporter expanded \
    packages/ccrouter_test/generator_test/ui_fragment_generator_test.dart \
    packages/ccrouter_test/generator_test/workspace_validator_test.dart \
    packages/ccrouter_test/generator_test/internal_api_boundary_validator_test.dart \
    packages/ccrouter_test/generator_test/route_api_boundary_test.dart \
    packages/ccrouter_test/generator_test/component_dependency_preflight_test.dart
  ```

- watch 初始化终态：启动期间停止、首次快照失败两项通过，退出 0；验证 child 清理和锁释放。
  实际命令：

  ```sh
  fvm dart test --concurrency=1 --reporter expanded \
    packages/ccrouter_test/generator_test/generation_watch_test.dart \
    --name 'watch stops during child session startup before reading signals|initial snapshot failure stops the child before releasing ownership'
  ```

- `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --check`：通过。
- `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check`：
  通过，Builder 写出 0 个输出，校验 6 个组件、34 条 Route、12 个生成 Package。
  最终 Git diff 不含生成物变更。

本轮不重复全量 Generator/Analyzer Plugin、IDE live、平台构建和真机矩阵，也不执行
Portable State 发布、Pub 发布、Git 提交/推送或 Plugin pin 变更。既有专项记录仍只代表各自基线。

### 推荐后续顺序

1. 保持现有 API 分层与可选路径；新需求先依照[生产场景评估流程](CCRouter-production-adoption-workflow.md)
   判定为应用职责、接入缺口、实现缺陷或通用能力，避免用新增抽象代替问题定位。
2. 选择一个实际消费者完成“契约 → 生成 → 导航/调用 → 失败与释放”的最小闭环；从干净依赖环境
   验证，不以 Monorepo 内通过替代对外接入成功。
3. 根据首次接入暴露的障碍再拆分入门与维护指南；分别衡量业务声明、Host 装配和工具维护成本，
   不直接删除高级能力来追求表面简单。
4. 按[唯一发布清单](CCRouter-release-readiness.md)处理 License、分发、版本与消费者门禁；
   真实平台和长期 Heap/RSS 采样持续进行，满足对应证据后再提升承诺。

## 2026-10-19 按推荐顺序执行：消费者与指南

用户选择 `liberlive-flutter` 为第一阶段真实消费者。完整范围、可复现通用源码及退出码见
[消费者验证记录](validation/consumer-adoption-20261019/README.md)。应用私有源码和认证数据
未进入框架归档；上游仅保留通用合成场景。

### 场景、取舍与责任

选用已有登录 Route：Consumer 使用公开 typed Contract，Account 组件实现页面，App 的生成
Assembly 装配。AccountRuntime 拥有 SignInGate/会话，页面与组件处理迟到认证响应；
App Composition Root 最终负责 CCRouter Runtime。外部入口失败由应用 coordinator 映射。

现有 API 足以表达场景，归类为 **A 已支持接入**；指南入口与旧包名/Skill 漂移归类为
**C 文档缺口**。真实认证策略和迟到状态提交仍属 **D 应用职责**。没有证据要求修改 Core。

| 方案 | 收益与成本 | 执行选择 |
| --- | --- | --- |
| 在真实 App 重写接入 | 可重新设计，但会打扰进行中的业务工作，迁移成本高 | 当前已有充分调用链，先验证既有实现 |
| 只运行原 Monorepo Demo | 快速，但不能证明独立依赖解析与消费 | 复用前一轮证据，并补独立工程 |
| 真实 App 既有测试 + 独立源码快照消费者 | 保留业务行为，区分真实场景与环境耦合；仍需单独验证正式分发 | 本轮采用 |

### 实际结果

| 验证 | 结果与证明范围 |
| --- | --- |
| App 登录 Route 与外部入口专项 | 14 项通过，覆盖成功返回、取消重开、覆盖后恢复、AccountRuntime 结束门禁、迟到认证响应及外部入口失败；测试使用内存/测试后端 |
| App `generate app --check` | 通过；前后 985 个相关源码与依赖输入摘要一致 |
| 新消费者首次 `flutter pub get --offline` | 独立 Pub 解析成功，已安装 Hook 自动生成 2 组件、1 Route、3 生成 Package；不借用框架 `.dart_tool` |
| 独立消费者依赖身份 | 五个框架包全部来自独立复制品，Pub Workspace 为消费者自身；复制品仅移除框架 pubspec 的 Workspace membership，原源码不变 |
| 独立消费者 Widget 测试 | 4 项通过：typed result、取消重开、业务失败保留页、shutdown 完成 pending result 并释放 Route Service/Timer |
| 独立消费者分析与生成 | `fvm dart analyze`、缓存/无缓存 `generate . --check` 均通过 |
| 独立标准 Analyzer 反向探针 | 预期退出 3，拒绝 String → int 参数及从业务 barrel 使用 `CCRouterHost`，不依赖 Plugin |

App 测试通过其既有 `with_ohos_build_lock.py --cwd app` 入口执行；应用业务源码、依赖和平台
配置保持原输入。标准 Flutter SDK、真机、真实认证后端和长期 Heap/RSS 均不属于本次验证。
这里的独立消费者使用本地框架快照及本机下载缓存，不称为 Hosted 或正式发布归档验收。

### 接入指导收敛

根 README 与两个 Skill 的入口现在优先指向[首次接入指南](../skills/ccrouter-integration-development/references/first-integration.md)：
先完成最窄 Route 和 Owner 终态，再按需查 watch、Analyzer、DevTools 等维护流程。
该指南随两个完整 Skill 目录分发，不依赖框架仓库文档才能阅读。
其中两个 Dart 片段已经用独立消费者的真实生成 API 编译验证，标准 Analyzer 退出 0。

真实消费者已同步两个完整 Skill 目录，并修正其接入清单中的旧 `ccrouter_auto_track` 名称为
`demo_analytics_flutter`。消费者 README/接入基线注明本地来源和测试边界。
本轮应用侧修改仅为上述开发者指导，不改变运行时依赖或业务行为。

第一阶段在当前本地开发来源下完成，第二阶段的首次接入入口与文档同步完成。
第三阶段沿用[发布执行清单](CCRouter-release-readiness.md)：License、正式来源、发布 Package
集合、首发 SemVer 仍需 Owner 决策；发布归档/Hosted 的安装与升级 smoke 仍开放。
没有把本次结果改写成可正式发布，也未执行发布、Git 提交/推送或 Plugin pin 变更。

---

以下为历史审查与既有增量入口。

2026-10-15 类型化 UI Fragment 的增量实施与 13 项核心价值回归见
[专项验收快照](archive/20261024-consolidation/CCRouter-ui-fragment-acceptance.md)。下述历史测试数量不代表该增量的结果。

> 本文主体保留 2026-09-30 的审查快照。后续 2026-10-03 全框架审查发现的 F01–F18
> 已修复；最新逐项结论、修复后核心价值与未覆盖范围见[全框架审查](CCRouter-framework-audit-2026-10-03.md#15-修复后核心价值与收尾边界2026-10-03)。
> 下文“没有本轮未解决 P0/P1”仅代表历史审查，不能作为当前无缺陷结论。

## 2026-10-19 Workspace 聚合根 Pub Hook 状态核对

结论：Host 识别缺陷已由 `d01e8a1`（2026-10-01）修复，AGENTS.md 的开放状态没有同步。
当前 Hook 使用共享的 `CCProjectRoleResolver`，先按当前 Package 的直接依赖确定参与身份，
再根据 `.metadata` / `ccrouter.yaml` 区分 Host 与 package-local。完整解析图中出现框架包
不会使无直接依赖的 Workspace 聚合根成为 Host。

本次只修正 AGENTS.md 状态与 Hook 文档中的旧提示文本，没有修改生产实现或生成物。
验证环境沿用本报告的 OHOS Flutter / Dart SDK：

- `project_role_test.dart`：8 项通过，包含共享 Generator/Analyzer 角色矩阵与 Host override。
- `pub_hook_test.dart` / `generation_command_test.dart` 定向回归：5 项通过，覆盖 Hook 聚合根
  跳过、无框架项目跳过、临时 SDK wrapper 的 Pub 退出码、run/build preflight 和聚合根
  `generate` 跳过；临时夹具不会安装到真实 SDK。
- 仓库根 `ccrouter pub-hook run --project-root . --pub-command get`：退出 0，输出聚合根
  跳过提示，未进入生成。此命令直接验证 Hook，不执行原始 `flutter pub get`。
- `ccrouter generate demo --check`：退出 0，fast path，生成物一致。

聚合根 Pub 成功仍不能替代真实 Host 生成检查；显式 Hook bypass 保留为依赖解析工具，
不再以“Host 识别缺陷仍开放”为使用理由。

## 1. 审查结论

- 审查日期：2026-09-30
- 审查范围：路由 Runtime、业务 Facade、Host/Adapter SPI、GoRouter Adapter、生成器、
  Service、Command、Event、初始化任务、Demo、测试与诊断模型。
- 自动化基线：`dart analyze packages` 与 Demo Analyze 通过；`ccrouter_test` 354 项、Demo 36 项、
  Generator 249 项测试通过；Demo 生成物缓存与 `--no-cache` 两种 `--check` 均通过。根 Workspace
  Analyze 当前被 Analyzer Plugin Git bootstrap 的外部凭据获取失败阻断，不属于 Dart 诊断；此前
  macOS、iOS Simulator、Android、Web 和 OHOS 构建 smoke 结果未在本轮重复执行。
- 总体结论：当前实现满足 13 条约定在当前静态组件范围内的实现门槛，没有本轮审计发现且
  未解决的 P0/P1 实现缺陷；正式 Hosted 发布、迁移文档和长期生产观测仍未完成。本轮实际发现
  并修复了 InitTask 重叠 Gate 丢失新就绪任务、Generated SPI 只信任
  生成期身份、Adapter attach 失败状态残留，以及 Runtime/Multi-Host 清理被单点异常中断的问题；
  这些修复均已有回归测试，不能只归类为文档调整。
  Route、Service、Command、Event 和 InitTask 已形成边界明确的最小闭环。生成物职责、API 隔离、
  生命周期、取消与诊断已完成本轮收口；Service Contract 自动绑定、Provider 最小注解与消费组件
  方法级 Proxy 与 Command/Event/InitTask 注解生成已实现；Action Pipeline、动态
  组件治理、Restoration、真实平台多窗口和长期 RSS/Heap 趋势仍是明确后续项，不能因已有设计
  文档而视为已经实现。
  Host 初始化现已收敛为一个必填 `CCHostAssembly`：生成 Host、手写 Host 和测试使用同一原子
  快照，旧的 `components/contractBundle/hostAssembly` nullable 参数组合已删除。

本审查只记录事实和后续门槛，不因为某项容易实现就扩展公开 API。

## 2. 逐项对齐结果

| # | 约定 | 状态 | 当前证据与缺口 |
| --- | --- | --- | --- |
| 1 | 智能 | 基本满足 | 顶层 Component、Route/Codec、简单 Service Provider、Command/Event/InitTask Handler、私有 Registrar/Manifest、Host Catalog/文档均由单一 `ccrouter generate` 编排生成；稳定 Host barrel 只导出原子 `CCHostAssembly`，Manifest、Contract、Catalog 与可选 Tool Integration 不再拆分传递。Runtime 自动校验组件与最终注册边界，`--check` 提供不依赖 Git 的只读陈旧门禁。复杂 Service 与未注解迁移能力使用显式 Contribution，没有用反射或函数体扫描冒充自动化。 |
| 2 | 简单易用 | 基本满足 | 宿主使用 `CCRouterHost.initialize(hostAssembly: ...)`、按需 `runInitTasks`、`CCGoRouterApp()` 即可启动；默认 managed App 自动读取初始化时安装的 Catalog，不再重复传参。手写 Host 使用 `CCHostAssembly.fromComponents`，不再理解 nullable 参数互斥规则。业务统一通过 `CCRouter.navigator/service/command/event`。Route Service 仅在需要精确页面 Scope 时增加 `BuildContext`，高级 Shell、Multi Host、Trace 和 Gate 保持渐进可选。 |
| 3 | 功能强大 | 基本满足 | 已覆盖类型安全导航、Deep Link、拦截、生命周期、混合路由、诊断、多种 Presentation、App/Session/Route Service、一次性 Command、事实 Event 和启动 DAG，没有万能 Map 或混合消息接口。Action Pipeline、可靠持久消息和动态组件明确不属于 1.x。 |
| 4 | 可扩展性 | 基本满足 | Core 使用中立 Route Definition 与强类型能力契约；Catalog、Assembler、Adapter、Service Provider、Handler 和 Gate 均通过明确边界扩展。新导航后端复用同一 Catalog，跨组件 Service 通过注解稳定 ID 和自动绑定渐进提升，不访问 Runtime 私有表。 |
| 5 | 可测试 | 基本满足 | Pure Dart Runtime 覆盖 Scope、readiness、Command/Event、InitTask DAG、取消/超时/失败；Flutter Adapter、生成器和 Demo 均有回归。`ccrouter_test` 提供 Test Host/Service Override，并具备 Generator、Route Runtime、Service 和并发回收非门禁基准。长期平台内存趋势仍需持续积累。 |
| 6 | 最小公开 API | 基本满足 | Runtime、Scope、Memory Adapter、Host binding 以及控制 SPI 均从业务 barrel 隐藏；Registrar 只拿到注册面 `CCRegistry`。`CCRouterHost.initialize` 只接受一个必填 Host Assembly，稳定生成入口也只导出该值；Catalog 自动解析仅存在于 Host Binding，没有增加 `CCRouter.routeCatalog` 业务 getter。Query/旧 Action/ActionReport 已删除，通信只保留 Service、Command、Event 与 InitTask；Action Pipeline 等未成熟能力没有提前公开。 |
| 7 | 编译器校验与类型安全 | 基本满足 | Route 参数、Codec、ID、Pattern、Contract exposure、页面实现、barrel、组件图、Service、Command、Event 与 InitTask 所有权和冲突已有生成期校验；缺少 Host Assembly 或继续传递旧 `components` 参数会由标准 Dart Analyzer 直接拒绝，不依赖可选 Analyzer Plugin。InitTask metadata 会形成完整跨 Package DAG。Runtime 会根据实际安装的 Manifest 再次校验 Generated Service/Command/Event 的组件身份和依赖边，陈旧生成物或手工调用 generated bridge 不能伪造调用归属。 |
| 8 | 非侵入式 | 满足 | 不要求页面基类或 Mixin，不保存全局 `BuildContext`；可继续使用应用自己的 `MaterialApp.router`/`GoRouter`；attached Adapter 不销毁应用 Router。 |
| 9 | 可降级回退 | 基本满足 | 无法可靠降级的组合栈事务与精确 Entry 操作已从公开链删除。Service optional lookup 只吞“未注册”，不吞工厂/生命周期错误；Event Subscriber 失败按契约隔离；InitTask required/optional 失败以脱敏结果返回，只有 Host 显式选择严格模式才抛错。 |
| 10 | 明确生命周期 | 基本满足 | Runtime、Session、RouteEntry、Service Scope、Adapter、Backend 和 InitTask Owner/销毁顺序明确；App/Session/Route Service 自动持有与逆序释放，shutdown 取消并等待活动调用和 DAG。Runtime 与 Multi-Host 在 remover、PopGuard、Adapter 或 Scope 清理失败时仍继续释放其余资源并返回首个错误，Adapter attach/Host 注册失败会回滚部分绑定。1.x 组件集合只在初始化确定，不提供不完整的 activate/deactivate。 |
| 11 | 可观测可诊断可溯源 | 基本满足 | Navigation、Service、Command、Event Subscriber 和 InitTask 均记录稳定 ID、可信 Owner、Trace 父子关系、状态和耗时；历史与 Subscriber error 有界，错误只保留类型和安全摘要。URI、Extra、消息字段、Service 参数/返回值和异常消息不进入 retained diagnostics。 |
| 12 | 并发安全 | 基本满足 | 导航策略、Service singleton readiness、InitTask Gate drain 都有 single-flight；重叠 Gate 在活动 drain 期间会触发下一轮 DAG readiness 检查，直到没有新就绪任务，避免任务永久停留在 `pending`。Event Subscriber 并发但按稳定 ID 启动；timeout、caller/Scope/shutdown cancellation 和异步依赖环均有测试。共享状态由 Runtime/Scope 单 Owner 修改，回调重入受控。 |
| 13 | 性能和稳定 | 基本满足 | 热路径无反射；路由和 Workspace 候选使用索引，诊断队列有界。Service 同步 Provider 不增加异步切换，Singleton/readiness 缓存按 Scope 有界，Event/InitTask 仅在显式调用时调度。生成器使用精确依赖闭包、内容指纹、write-if-changed、并发锁和全量回退；缓存/无缓存逐字节一致，`ccrouter find` 只读取 Host 依赖闭包 Index。已有 Route、Service、并发与资源回收基线，长期内存趋势仍需版本间持续采样。 |

## 3. P1 问题

### 已完成：并发 Observation、Extra 与回调重入

- `rejectDuplicate` 为被拒请求产生独立 Navigation ID 和 `found/lost/after`，随后释放
  Observation；
- `singleFlight` 共享第一个 Future，但跟随调用保留独立 Navigation ID、Lifecycle 和 `after`
  终态，不创建第二个 RouteEntry；
- 携带 Extra 的请求不参与自动去重，避免比较、哈希或合并任意业务对象；
- Interceptor、Failure Policy、PopGuard、Telemetry Provider、Aspect 和所有 Runtime 路由 Listener
  统一进入 Runtime Zone；回调内同步调用及其派生异步任务发起导航均抛出
  `CCNavigationReentrancyError`；
- 专项测试覆盖拒绝、共享、Extra 独立执行、Interceptor 重入和 Listener 重入。

### 已完成：P1-1 Retained diagnostics 数据边界

- `CCPendingNavigation` 和 `CCRouteEntrySnapshot` 只暴露 `CCRouteAddressSummary`；
- Visibility 与 RouteEntry lifecycle 自动复用同一安全 Entry 快照；
- Adapter 原始 `CCNavigationBackendEvent` 只在回调调用栈中完成 identity 与 lifecycle 协调，进入
  Runtime history 和业务 Listener 前转换为 `CCNavigationBackendDiagnosticEvent`；
- Runtime backend ledger 不再保存 `location`，只保存 `CCRouteAddressSummary`，业务通过
  `CCBackendEntrySnapshot` 观察；
- 摘要仅包含 canonical `routePattern` 和 Path/Query/Fragment presence；Pattern 可以包含声明期
  Path 占位符名称，但不包含 Path 值、动态 Query 名和值、完整 URI 或第三方 RouteSettings
  location；
- Pending resume、Route 匹配和 Adapter 调度仍使用 Runtime 私有 request/record 中的 operational URI，
  不因脱敏改变导航语义；
- 专项测试覆盖带 Path 用户标识、Query Token、Fragment 和外部 backend location 的输入。

### 已完成：P1-2 Observer 有界异步分发

- Aspect、Navigation/Failure、RouteEntry/Visibility、Backend 和 Restoration Listener 统一进入
  Runtime 私有 FIFO 队列，在下一轮 event loop 分发；决策型 Interceptor/Policy/Guard 保持同步或
  显式 await；
- 队列容量复用 `navigationDiagnosticCapacity` 且最少为 64 个事件批次，避免低历史容量让常规
  导航频繁触发 backpressure；
- overflow 优先移除最旧非终态批次；全终态队列拒绝新非终态，只有新终态才同步释放最旧终态；
- Navigation `completed/failed`、Failure、RouteEntry `removed/disposed`、Aspect
  `lost/after/removed/disposed`、Backend `pop/remove/hostDetached` 不静默丢失；
- Listener 在 drain 前取消订阅会跳过排队回调；Runtime dispose 取消 Timer、flush 队列并清理
  Listener 和闭包，覆盖 `not-disposed` 与 `not-GCed` 风险；
- 专项测试覆盖异步边界、FIFO、取消订阅、两类 overflow、终态保护、dispose flush 和异步重入拒绝。

## 4. P2 问题

### 已完成：P2-1 业务 barrel 与 Host/Adapter SPI 隔离

- `package:ccrouter/ccrouter.dart` 使用完整 `hide` 清单隔离 Adapter、Request、Route、Capability、
  Backend Event/Snapshot、Pop Coordinator、Predictive Back 和 Restoration Source 等 Host SPI；
- `package:ccrouter/ccrouter_host.dart` 使用对应 `show` 清单提供 Host/Adapter 实现入口；
- 页面生成 glue 只返回组件已有的 `CCRouteDefinition`，由
  `CCFlutterRouteDestination.fromDefinition` 在 Host catalog 边界生成 `CCNavigationRoute`，页面
  library 不需要也不能额外导入 Host SPI；
- API surface 快照测试同时锁定业务隐藏集合、Host 导出集合和主要 SPI 类型可解析性。

### 已完成：P2-2 前置失败和能力降级诊断

- Route resolution、参数准备、拦截和 Adapter 失败无论是否安装 Failure Policy，都会进入有界
  `CCNavigationFailureEvent`；事件只记录 navigation ID、operation、route ID hint、origin、stage、
  error type、recovery depth 和是否恢复；
- request 创建前无法可靠得到 Pattern、Placement、Owner 和 Host，因此不伪造 Lifecycle/Aspect
  request；Failure Event 是该阶段的权威终态 envelope；
- Observer 能力不足但可以保持语义时，独立记录
  `CCNavigationCapabilityFallbackEvent`，区分 backend visibility 的 Runtime commit 回退和
  managed removal 的 Host/Outlet partition-local reconciliation；
- capability fallback 只在实际采用回退时记录，包含稳定 Route/Host/Outlet 与枚举，不包含 URI、
  Arguments、Extra、Widget、Navigator 或 backend Route；
- 两类事件都使用有界 history；Listener 通过 Runtime FIFO 队列异步分发，capability fallback 作为
  非终态诊断可在队列压力下丢弃，failure 终态保持 backpressure 语义。

### 已完成：P2-3 Workspace Validator 组件依赖图校验

- required dependency 缺失、自依赖和 required/optional 混合依赖环在 Workspace 聚合阶段失败；
- 不存在的 optional dependency 保持允许，存在时作为普通依赖边参与排序和环检测；
- 聚合组件列表复用 Runtime 的确定性语义：组件 ID 与依赖 ID 均稳定排序，依赖先于消费者；
- Generator 专项测试覆盖缺失、自依赖、混合环、optional 缺失和确定性拓扑顺序，避免构建期与
  Runtime 初始化对同一合法依赖图产生不同装配顺序。

### 已完成：P2-4 统一生成入口与陈旧门禁

- `ccrouter generate` 自动发现 standalone Package 或 Dart workspace，先复用 build_runner，
  再执行 metadata 校验、组件索引、Host Catalog 和文档聚合；
- `generate --check` 只快照 CCRouter 管理的输出，发现 added/removed/modified 后恢复原现场并
  返回非零，不依赖 Git 状态，也不覆盖业务源码；
- 普通生成清理由框架标记但不再有 owner 的 `.component.g.dart`/`_ccrouter.g.dart` 聚合物，
  且只清理解析图中明确可写的 Package；同名手写文件和外部 path/Git/pub Package 保持不动；
- 没有生成能力的 Package 不创建 `ccrouter_generated`；最后一个受管产物删除后只清理真正为空
  的目录，存在未知文件时完整保留；
- 旧 metadata-only aggregate 路径仅保留兼容，不再作为标准开发流程；
- 从 Host `package_graph.json` 只沿正式 dependencies 计算闭包，通过 `package_config.json` 定位
  workspace/path/Git/pub Package，排除无关 workspace roots 和 devDependencies；
- 每个参与 Package 发布单一 `ccrouter_package.json`，Runtime Package 额外发布只 import 直接依赖
  的 `CCGeneratedPackageBundle`；Host 不直接 import 传递 Package，Diamond 依赖按版本与内容指纹
  去重；
- 默认缓存只复用 metadata 字节 SHA-256 完全一致的解析结果，损坏或 Schema/版本不兼容时全量
  回退；`--no-cache --check` 已作为逐字节等价参考路径，`--profile` 输出阶段耗时与命中率；
- workspace build_runner 使用 `asset:` filter 限制到 Host 闭包内可写的生成器 Package，并排除
  `ccrouter_generated` 目录作为二次 Builder 输入；外部 Package 只消费发布 Index；
- 两个生成进程通过版本化文件锁串行化，write-if-changed 使用同目录临时文件提交。正式规模
  benchmark 仍归 P2-6，不能用缓存掩盖全量路径错误。

### 已完成：P2-5 Telemetry/source 稳定标识校验

- `CCNavigationSource.id` 使用最大 64 字符的稳定分段标识语法，拒绝空白、URL 和凭证式字符；
- 匿名 Visitor/App Session ID 使用独立的有界 opaque 语法，允许 UUID 风格的数字开头；
- 非法来源和 Telemetry Context 安全降级为无 attribution 导航，并记录不包含原值的有界诊断；
- Framework DartDoc 和回归测试明确禁止账号、完整 URI、Token、设备 ID 与业务 Payload。

### 已完成首批基线：P2-6 性能与稳定性基准

仓库已提供非门禁式 Generator、Runtime、Service scaling 和并发回收 benchmark，覆盖 Workspace
校验、Runtime 初始化、动态 URI 解析、Service 装配/查询/调用/readiness、并发 Push/Pop 和销毁。
动态 URI resolution 仍会遍历候选 Route/Pattern；生成器使用精确闭包、单 Package Index、内容缓存
和 Pattern 候选索引。基准只用于同机版本对比，不能把一次本机结果视为跨机器性能承诺。

生成器聚合已增加非门禁式基准脚本：

```sh
fvm dart run packages/ccrouter_test/benchmark/generator_scaling.dart
fvm dart run packages/ccrouter_test/benchmark/runtime_scaling.dart
fvm dart run packages/ccrouter_test/benchmark/runtime_concurrency.dart
fvm dart run packages/ccrouter_test/benchmark/service_scaling.dart
```

2026-09-27 在修复 benchmark 入口和 caller fixture 后重新执行当前本机 Dart JIT 基线：

- Generator 5000 Route 固定路径校验：`54.419ms`；
- Runtime 1000 Route 初始化 P50/P95：`455/527us`，动态 URI 打开：`424/3773us`，
  dispose：`39/55us`；
- 10 轮、每轮 100 个并发 Push/Pop：`cycleUsP50=3574`、`cycleUsP95=9208`，结束时
  `finalActiveEntries=1`、`finalPendingNavigations=0`、`finalAdapterEntries=1`；
- Service 1000 Provider 初始化 P50/P95：`3304/3627us`，`invokeServiceSync`：`4/13us`，
  dispose：`147/442us`，每轮实例计数均归零。

这些结果没有形成跨机器硬阈值。Runtime 动态打开 P95 相比 P50 波动明显，后续版本应在同机、同
SDK 和相同预热条件下比较趋势；不能仅凭单次样本认定回归，也不能通过减少生命周期或诊断工作
换取更低数字。持续 Push/Pop 后的台账恢复和 Service 实例归零只证明可观测状态有界，不替代真实
RSS/Heap 趋势；后者仍需在目标平台和生产应用中持续采样。Generator 测试与 Demo Analyzer 必须
串行执行，避免 Analyzer 短暂读取 Generator 测试创建的临时探针而产生假诊断。

### 已完成：P2-7 生成物最终审计

- 页面源码保持零 `part`、零生成文件 import；组件唯一 Route API 聚合内部 Intent factory，业务侧
  通过单一 generated API 获得 IDE 补全和自动导包；
- 单源码 Route、Route Binding、组件 Route Catalog、Package Bundle/Index、Host Catalog 和文档
  各自只有一个职责，没有重复声明公开 Intent 或重复构造 Runtime Route Definition；
- 组件业务 barrel 不再导出 Host-only intent；Host 装配入口集中在独立 host barrel，业务依赖不会
  意外获得 Host SPI；
- 非 nullable 且具有编译期空 List/Set 默认值的 Query 参数将空集合编码为缺失 key，解码恢复默认值；
  required、nullable 和非空默认集合继续严格拒绝无法无损表达的空集合；
- 默认缓存与 `--no-cache --check` 均验证 4 个组件、31 条路由和 8 个生成 Package，输出无差异；
  测试同时覆盖缓存损坏全量回退、并发生成锁、write-if-changed 和 stale cleanup。

### 已完成：P2-8 资源生命周期回归

- Runtime 连续 250 次 Push/Pop 后 Route Entry、Backend Entry 和 Pending Navigation 均为空，诊断
  history 保持容量上限；
- Host、Navigator Observer 和页面生命周期对象通过 leak tracker 回归；
- 自定义页面转场不再在 builder 中创建需要手动 dispose 的 `CurvedAnimation`，改用无独立所有权的
  `CurveTween` 链，并覆盖 Fade、Scale、右侧滑入和底部滑入的重复创建/销毁测试；
- 本轮发现并修复 Adapter attach、动态 Host 注册、初始多 Host 装配、Host 注销和 Runtime shutdown
  的失败路径：一个 listener remover、PopGuard 解绑或 Adapter 抛错不再跳过其余 owned resource；
  原始失败或首个 cleanup failure 仍返回调用方；
- 本轮基于 `not-disposed` 与 `not-GCed` 证据标准复查后，没有剩余高置信的框架自有资源泄漏。
  第三方 Adapter 的 remover 若抛错且其实现仍强引用 callback，框架无法替它解除引用；这是 Adapter
  SPI 的实现责任，框架会清除自身引用并继续释放其它资源。

本轮新增的私有 Runtime Resolver 只保存默认 Runtime 引用和 Zone-local overlay，不创建 Timer、
Listener、Stream、Overlay 或 Controller；Resolver 不拥有 Runtime，也不负责销毁，因此没有新增
可疑释放路径。嵌套 Test Host overlay 恢复测试和全量资源回归均通过。

### 已完成：P2-9 Service、Command、Event 与初始化任务闭环

- Service 生命周期与创建策略正交：App/Session/Route Scope 分别拥有 `singleton`/`newInstance` 实例，
  `CCDisposable` 由 Scope 逆序释放；Route Service 只通过 Managed Page 的精确绑定解析，不猜当前页；
- Lazy Service readiness 由显式异步 API 启动，Singleton 在当前 Scope single-flight，`newInstance` 每次
  初始化；同步解析不会偷跑 I/O，失败、timeout、caller cancellation 和 Scope cancellation 保持
  不同标准错误；
- 跨组件 Service 的稳定 Contract ID 与 Type lookup 共享 Provider/实例；Key 支持确定性多实现，
  optional lookup 只把真正缺失转为 null；测试替换留在 `ccrouter_test`；
- `@CCServiceContract` 生成内部 Token/metadata，`@CCService` 从唯一直接 Contract 自动生成简单
  Provider registration，Package 唯一 `CCComponent` 自动生成私有 Registrar/Manifest；复杂构造
  与 readiness 继续使用 `@CCComponentContribution`，不在 Annotation 中注入任意执行代码；
- Service/Command Contract alias 已作为全部消费者的默认 Client 成员名进入 metadata 和 shape
  fingerprint，Dependency alias 可局部覆盖；alias migration CLI/Analyzer Quick Fix 尚未实现；
- `CCCommand<R>` 是唯一的一对一操作消息，支持 `R` 与 `void`、单 Handler、timeout、取消、嵌套
  Trace 和 Runtime shutdown；读取能力保持在 Service，不再保留重复的 Query/Action 表面；
- `CCEvent` 只表达已经发生的事实；静态 Subscriber 并发执行且按 ID 稳定启动，一个 Subscriber
  失败只进入有界脱敏诊断，零订阅者成功，发布 deadline/cancellation 仍会终止整体操作；
- InitTask 在同步 `initialize()` 校验 ID、依赖和 DAG，Host 显式打开 Gate；同层并发、重叠触发
  single-flight；活动 drain 中打开的新 Gate 会继续 drain 到稳定状态。每任务 exactly-once，
  required/optional/skip、显式严格模式、timeout 和 shutdown 等待已有回归；
- Demo 通过真实 Runtime 覆盖 Command typed/void/timeout/cancel/error、Event 多订阅/隔离/零订阅/
  timeout、InitTask Gate/失败依赖，以及 Service 全部 Scope、创建策略、readiness、多实现、optional
  lookup 和自动销毁；
- Action Pipeline 等待动态预埋操作链的真实业务样本；Service 方法 Proxy 已采用显式消费依赖，
  只为真实跨组件 Contract 生成组件专属 Client；Command 已形成 Contract、唯一 Handler、显式
  消费依赖、组件专属 Client 和 metadata 已实现；Event Contract、静态 Subscription、Owner
  自动 Publication Client、metadata 和 Catalog 已实现；InitTask 的 Task Contract、顶层 Handler、
  类型化依赖、自动注册、DAG/Catalog 和 Workspace 校验也已实现。

Generated Service/Command/Event 的 Package exposure、Owner 和消费依赖先由 Generator/Workspace
Validator 校验，Runtime 再对实际安装组件图做二次校验。Event 的零 Subscriber 语义仍是成功
no-op；由于此时 Runtime 没有 Subscriber 可反推出 Contract Owner，它只能证明 Publisher 身份已
安装，无法独立证明手工 generated SPI 提供的 Publisher 就是 Contract Owner。正常业务 API 和
生成代码路径已阻止该调用方式；若未来要把 generated SPI 提升为独立防伪边界，需要新增 Event
Contract Runtime Registry，而不是改变零订阅者语义。

## 5. 已确认符合且应保持的边界

- 默认 Runtime 由应用组合根通过 `CCRouterHost` 创建和关闭，业务 `CCRouter` 不暴露生命周期控制，也不构造 Runtime/Scope。
- Registrar 只接收受限 `CCRegistry`，组件不获得 Runtime。
- 生成 Route Intent 和结果类型是业务导航主入口；动态 URI 是明确的兼容入口。
- GoRouter managed/attach 所有权不同，attach 不销毁应用 Router。
- 外部 Popup、Overlay 和 LocalHistory 不会按位置误删 Managed RouteEntry。
- Adapter 不支持某项语义时在变更栈前失败，不做不等价模拟。
- `CCNavigationFailureAttempt` 区分原始请求、拦截器重定向、Failure Policy 恢复和 pending
  resume；Failure Policy 不再通过模糊的 stage 或异常文本猜测来源。
- `ccrouter clean` 只删除可写 Package 中带 CCRouter 标记的生成源码，用户文件、只读依赖和
  build_runner 缓存均保留；清理后可由 `generate` 完整恢复。
- Managed Cupertino Route 安装 PopGuard 时禁用交互侧滑，保证手势不能绕过 Guard；Foreign
  Popup/LocalHistory 仍只影响自身，不会关闭底层 Managed Route Scope。
- Route/Session/Adapter pending Future 在 Pop、Reset、Go 和 shutdown 路径都有终止行为。
- Trace、Lifecycle、Failure、Aspect 和 Backend 历史均有容量边界，subscriber error 有界。
- 页面生命周期不要求业务继承基类；Mixin 和 Listener 均为可选。
- contracts Package 可以保持 Pure Dart，页面实现和后端依赖不进入跨组件契约。
- 读取和长期能力使用 Service；唯一执行者的一次性操作使用 Command；已发生事实通知使用 Event；
  Runtime 一次性启动依赖使用 InitTask，不以万能消息类型互相替代。
- `CCRouterHost.initialize()` 保持同步原子装配；异步启动工作必须通过显式
  `runInitTasks(gate: ...)` 等待，Service readiness 不隐藏在全局启动中。
- 组件集合在初始化时一次确定。1.x 不提供不完整的动态 activate/deactivate，也不允许业务销毁
  Runtime、Scope、Adapter 或 Service 实例。
- 简单 Service 使用生成注册，跨组件 Service 使用显式消费声明生成方法 Proxy；复杂 Service 和
  未注解迁移能力使用显式 Contribution，InitTask 使用专用 Contract/Handler 生成。当前 Proxy
  不支持的方法形态只有在真实
  所有权与取消语义明确后才扩展。

## 6. 本轮修复与残余风险

本轮核心价值回归不是“全部满足”的形式化勾选，实际收敛了四类问题：

1. **并发确定性**：重叠 InitTask Gate 过去可能复用一个即将完成的 Future，却不再检查新 Gate
   解锁的任务；现在共享 drain 会运行到 DAG quiescent。
2. **纵深类型安全**：Generated Service/Command/Event 过去主要依赖生成期身份；现在 Runtime 会
   拒绝未安装组件、Contract/Handler 不一致和缺失依赖边，再进入业务执行与 Trace。
3. **失败原子性**：Adapter attach 或 Host 注册中途失败过去可能留下 listener、ledger 或已插入
   Host；现在会回滚框架侧状态，并保持 Adapter 所有权契约。
4. **生命周期稳定性**：单个 cleanup 回调过去可能中断后续 Adapter、Scope 或 Host 释放；现在采用
   best-effort 全量清理并保留首个异常。
5. **Host 装配原子性**：Facade 过去以多个 nullable 参数表达生成与手写两种装配模式；现在统一
   接受一个必填 `CCHostAssembly`，手写工厂在 Runtime 可见前完成组件拓扑、Contract 与 Tool
   Integration 校验，稳定 Host barrel 不再并列暴露可混用的 Manifest/Catalog 顶层变量。

仍需明确保留以下边界，不能在 1.x 审计中误报为已完成：

- 长期 RSS/Heap 趋势、真实平台多窗口和不同 SDK/Adapter 版本性能仍需生产接入持续采样；当前
  benchmark 只证明有界状态和同机基线。
- 零 Subscriber Event 的 Contract Owner 独立 Runtime 证明需要额外 Registry；当前由生成期校验、
  Package 边界和实际安装 Publisher 校验共同保证正常集成路径。
- Action Pipeline、动态组件、Restoration、Navigator 1/2 新 Backend 和真实平台多窗口仍属于后续
  设计或 2.0 工作，不应为满足“功能强大”而提前扩张公开 API。

## 7. 本轮最终门禁

- `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test`：249 项通过；
- `fvm flutter test --concurrency=1 packages/ccrouter_test/test`：354 项通过；
- `fvm flutter test --concurrency=1 demo/test`：36 项通过；
- `fvm dart test --concurrency=1 packages/ccrouter_devtools_protocol/test`：4 项通过；
- `fvm flutter test --concurrency=1 packages/ccrouter_devtools/test`：7 项通过；
- `dart analyze && dart test`（`packages/ccrouter_analyzer_plugin`）：无问题，8 项通过；
- `fvm flutter analyze devtools/ccrouter_extension`：无问题；
- `fvm dart analyze packages` 与 Demo `fvm flutter analyze`：无问题；根 Workspace Analyze 因
  Analyzer Plugin Git bootstrap 无法读取外部 GitHub 凭据而在插件安装阶段失败，本轮没有将其
  误记为 Dart 代码失败或通过；
- `fvm dart run ccrouter_generator:ccrouter generate demo --check --profile` 与
  `--no-cache --check --profile`：生成物一致，缓存和无缓存路径均通过；
- `ccrouter find` 已验证 Route ID/Pattern 与 InitTask 稳定 ID，查询只读且受 Host 依赖闭包约束；
- `fvm flutter build macos --debug`、`ios --simulator --no-codesign`、`apk --debug`、`web` 和
  `hap --debug`：均成功；这些是当前 SDK/主机的构建 smoke，不等价于真实设备手势、原生多窗口
  或长期 RSS/Heap 无泄漏证明；
- Runtime/Service/Command/Event/InitTask 混合性能回归、Analytics 队列压力和资源释放回归通过；
  1x/10x/20x/30x 生成基准已覆盖冷/热路径，长期 RSS 仅作为同机趋势保存；
- `git diff --check`：通过。

后续扩展 Service Proxy 方法矩阵、Action Pipeline、动态组件、Android Predictive Back、
Restoration、真实平台多窗口或新 Adapter 时，必须补对应构建期、生命周期、并发、性能和平台
回归；它们不属于本轮已经实现的能力。
