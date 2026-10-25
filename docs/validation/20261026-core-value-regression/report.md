# 核心价值回归审查（2026-10-26）

**结论：在本轮源码、API、自动化和有界压力范围内，13 条核心价值保持其约定边界。**
未发现新的高置信 Runtime 算法、组件隔离或资源所有权缺陷；修正两处文档/证据漂移。
易用性、兼容容量和性能稳定有条件，发布与真机门禁不因这些通过而关闭。

## 基线、问题与处理方案

基线 `bbb4a4163dfcacb1fa2597eea99511c7af7cb619`，工作位于独立
`codex/sealed-action-unions` worktree。开始时干净，原 main 不修改。
本轮没有改动框架、Plugin、生成物、依赖或 Demo pin；对 177 个生产 Dart 文件冻结
[摘要](production-source-sha256.json)，结束后核对。环境为 macOS arm64、OHOS Flutter
3.41.10-ohos-1.0.0 / Dart 3.11.5，不代表标准 Flutter、远端 CI 或原生平台复验。

### CV01 / P3：CLI Skill 的生成规则落后于实际 schema

Integration Skill、README、实现与生成物已有 union 的 UI schema 3 / Index 5，
CLI Skill 的 scaffold/Generated Output Rules 仍只列 enum/DTO 的 1/3、2/4。
这会使独立分发的 Skill bundle 对合法新产物给出不完整判断。

仅刷新测试证据不能解决接入规则漂移；修改实现则没有必要。采用最小文档修复：补齐
三种 schema/Index、迁移 SemVer、终态 DTO、工作量限制、版本一致性与重复注解规则。
修复后再次运行隔离双 Skill bundle 与真实 CLI help 检查。

### CV02 / P3：历史能力快照被回写

`docs/CCRouter-core-principles-audit.md` 的 2026-10-20 表格被近期改动写成“支持 sealed”。
该日只有 enum/单 DTO，这违反文档自身“按日期保留快照”的口径。对照本任务之前的
`cd776d9726a50c9011375dadb6d69d89d2a95c98` 恢复原行，并添加独立的本日期审查入口。
不改写旧失败、旧数字、旧平台判断；当前 union 能力在本报告和当前规范中维护。

## 13 条核心价值

| # | 价值 | 本轮判断与证据 |
| --- | --- | --- |
| 1 | 智能 | 保持：声明、生成 Client/Intent、Host Assembly、Owner 与形状索引承担装配。两个实际 Host 的 uncached freshness、UI/Route find 与 Portable 就绪检查通过；没有运行时反射发现业务或依靠焦点猜测来源。 |
| 2 | 简单易用 | 有条件保持：scaffold/find 与真实 Skill 示例测试通过，修复 CV01。UI 首次接入仍涉及 Contract、Owner、Consumer、Host；本轮没有新人耗时、误配率或人工体验研究。 |
| 3 | 功能强大 | 范围明确：五类旧能力、Managed 多 Host/Outlet、typed result、Deep Link、guard、targeted close 与 UI enum/DTO/sealed 联合进入回归。集合、动态 Slot、任意 Router attach、完整 Restoration 不宣称已支持。 |
| 4 | 可扩展性 | 保持：Contracts/Core 无 Flutter 依赖，UI 为可选 Flutter 层；新类型检查仅在工具/可选 UI，不把业务 Share、导航异步完成、Session 或布局注入 Core。没有第二生产 UI Backend 的认证结论。 |
| 5 | 可测试 | 保持：本轮运行框架、工具、组件、Analytics、Demo 与独立 Example；相同源码 Generator/Plugin 全量证据单列复用。框架集中测试根、Plugin 独立 analyzer 图与实际 LSP 分开，不混计次数。 |
| 6 | 最小公开 API | 保持：1 正向/12 反向真实 Analyzer 探针通过。业务可用 navigator 与 RenderInput；Runtime/Host/Scope、UI 注册/生成 SPI 不暴露，业务 facade 无 initialize/shutdown。Registrar 仍只取得 CCRegistry。 |
| 7 | 编译校验与类型安全 | 保持：明确 SDK Object 身份、终态 DTO、闭合变体、default/fingerprint、公开导出、版本及 Owner 证明。内部 API 反向分析/跨包边界 3 项通过；版本错标与陈旧快照仍 fail-closed。 |
| 8 | 非侵入式 | 有条件保持：普通 Widget 和旧 enum/DTO 路径继续存在，正常旧指纹与生成签名不变，Core/facade 生产代码相对功能前基线无差异。但旧超复杂 DTO 新增容量限制，不能说任意历史模型无条件兼容。 |
| 9 | 可降级回退 | 保持可审查回退：实现集中于独立分支，旧 enum/DTO 与新 union 可并行对照。回退需恢复声明/工具组合并重生成 A/B/Host，不能将 Index 5 改标为旧版，也不是 Renderer 热切换。 |
| 10 | 明确生命周期 | 保持所测边界：完整串行框架含取消、GC、Scope/Host 清理、shutdown、旧 Action 撤销。变更快照先撤销旧 sink，恢复不复活旧回调。类型缓存按次创建，没有新全局 Runtime/Widget/Context 所有权。 |
| 11 | 可观测与溯源 | 保持：四种诊断容量下峰值在途 Sink 始终为 1，队列有界，释放后 inFlight 清零；DevTools 只读，日志敏感信息与链接检查通过。UI DevTools Catalog 仍未实现。CV02 修复保证历史证据不回写。 |
| 12 | 并发安全 | 保持所测路径：完整框架覆盖多 Host、相同身份换代、跨 error Zone、异步清理屏障；额外 10 轮 × 100 并发导航后 pending=0，保留预期根 Entry。Generator 共享 writer/锁与输入屏障的同源全量证据有效。 |
| 13 | 性能与稳定 | 有界行为通过、趋势未定：运行 10/100/1000 Route/Service、1,000 循环默认套件和额外 10,000 循环。旧 DTO/常量 16,384 访问/256 层、union 512/32、IDE 超预算退让均明确；单次耗时与 RSS 不构成改善、零泄漏或长期趋势证明。 |

## 本轮新执行的验证

数量按 suite 分列，API 探针和压力操作不是测试项；不将专项或操作次数累加为唯一测试总数。
所有根 Dart 命令使用相同 FVM SDK 和根已解析 package_config，避开定制 SDK 的隐式 Pub
重解析问题；Plugin 分析从独立 Package 目录执行。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 框架完整串行回归 | 1646 项通过 | [框架](framework.log) |
| 仓库工具 | 52 项通过 | [工具](tools.log) |
| Route/public/internal API 边界 | 3 项通过 | [生成 API 边界](api.log) |
| 业务 facade 正反向真实分析 | 1 正向、12 反向通过 | [探针](facade-probe.log) |
| KV/Payment/Navigation Lab/Analytics Flutter | 27 项通过 | [Flutter 模块](modules-flutter.log) |
| Analytics / Firebase mapping | 41 项通过 | [应用逻辑](analytics.log) |
| Demo | 117 项通过 | [Demo](demo.log) |
| 独立 Order Example | 1 项通过 | [Example](example-test.log) |
| DevTools/协议 | 24 项通过 | [DevTools](devtools.log) |
| 根及独立 Plugin 静态分析 | 均 No issues found | [根](analyze.log)、[Plugin](plugin-analyze.log) |
| Demo uncached freshness | 6 组件、34 Route、11 Packages 一致 | [Demo 生成](generation-demo.log) |
| 独立 Example uncached freshness | 2 组件、2 Route、3 Packages 一致 | [Example 生成](generation-example.log) |
| UI usage 与独立 Route find | 正确 public imports、Owner edge、Client/alias；查询未改产物 | [UI](find-ui.log)、[Route](find-example.log) |
| Portable publish 本地校验 | 9 Package 就绪，未对外发布 | [Portable](portable-demo.log) |
| Plugin pin-check | 当前完整 SHA、lock/remote 一致，无 production drift | [pin](pin-check.log) |
| 隔离 Skill bundle / CLI help | 修复前后检查均通过；该检查验证结构/命令，不会自动发现 schema 文案遗漏 | [修复前](skill-before.log)、[修复后](skill-after.log) |
| 文档/敏感信息/差异检查 | 186 份 Markdown、敏感信息及差异检查通过 | [文档](documentation.log)、[敏感信息](sensitivity.log) |

## 复用的相同源码全量证据

前一轮 [扩大审查报告](../20261026-ui-action-review/report.md)已完成并提交：

- Generator/CLI **721 项通过、1 项默认远端安装 smoke 跳过**。
- 独立 Plugin **212 项通过**，包括真实 Analysis Server/LSP、part-only 和 metadata 失效。
- 实际 Demo 根及固定 Git pin 的新 JIT Server 已完成未保存诊断/修复往返。

本轮核对该报告所列全部生产摘要与当前源码一致，且没有修改任何生产 Dart 文件，故复用
这些证据，不重复耗时约 36 分钟的 Generator 全量，也不把它们冒充本轮新执行。
新 pin-check 只证明来源身份，不等于现有 GUI IDE 已重启。可复核的 pin 仍由 manifest/lock
决定，本轮没有为了跟随 HEAD 而改 pin。

## 压力、内存与观测口径

[默认性能套件](performance.json)使用仓库原始 orchestrator，以独立 child process 运行
Route/Service 扩展、100 并发和 1,000 循环，未启用 `--full` Generator scaling。
每个场景正常 dispose，所有状态断言通过。并发末尾保留预期根 Entry 1、pending 0。

[额外 10,000 循环](long-run.log)每 1,000 次重建 Runtime，每次 pop 后 active Entry、
backend Entry、pending 均为空，最终清理断言通过。RSS 约 **199.70 → 265.94 MiB**，
增量 66.23 MiB；未强制 GC、没有配对旧版或原生 retaining-path 采样。这不是确定泄漏或
零泄漏结论，也不与其他日期机器负载下的数字作优劣比较。

[诊断容量](diagnostic-capacity.log)分别为 0/64/128/1000，每组 2,000 Command；
峰值在途写入都是 1，队列上限 64/64/128/1000，超额丢弃计数正常，关闭后释放挂起 Sink。
压力在完整框架测试结束后串行执行，未与 GC 套件争用，但仍不是性能趋势门禁。

## 未关闭范围

- 易用性人工研究、Hosted/发布归档及升级、标准 Flutter/远端 CI、原生窗口/真机手势没有
  新验证。源码通过不能覆盖这些独立条件。
- [发布准备](../../CCRouter-release-readiness.md)中的 License、历史签名治理、发布集合、
  SemVer/API 冻结及 Hosted 分发等 Owner 决策仍未关闭；保持 publish_to: none。
- 历史 Native/Graphics 增长及长帧边界按原真机证据维护，本轮不关闭，也不重复解释为 UI
  sealed Action 或 Runtime 已证明的泄漏。
- 新旧普通 DTO 的容量收紧与同库继承漏检修复已披露；没有“所有任意模型无条件兼容”的承诺。

本轮仅修正文档和保存回归证据。日志机械规范化本机路径、换行和行末空白，结果保持。
