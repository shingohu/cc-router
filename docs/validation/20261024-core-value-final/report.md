# 核心价值收口回归（2026-10-24）

本轮行为、类型/组件边界与生命周期回归未发现新增退化，所执行测试 suite 均通过。
但发布门禁并未全绿：历史验收文件仍含本机路径；既有真机问题也仍未关闭。
这不是全平台、全部性能指标均优于重构前的证明。

后续[遗留项收口](../20261024-closure/report.md)记录 Demo 修复、历史证据路径归一化和
华为受控复测；下文敏感信息门禁失败及待办保持本轮执行时的事实。

## 范围与判定

源码基线为 `7d9b51211ddae3e55349c64773ec7d4e2675e391` 加本工作树的绑定导航 API、
Demo 和文档改动。本轮审查与验证不修改框架实现、不升级依赖、不更新 Plugin pin。
生产源码差异摘要：对 `packages/ccrouter/lib`、`packages/ccrouter_core/lib`、`demo/lib`、
`demo/modules/navigation_lab/lib` 执行 `git diff -- <上述目录> | shasum -a 256`，结果为
`e3e032a4196227481aad77817b031a91d5e78f19bd0e85ad75e9c760e0fd3790`。

环境：macOS arm64、Flutter `3.41.10-ohos-1.0.0`（`62357a93d6`）、Dart `3.11.5`。
这是主机源码、Dart/Widget、工具和有界压力回归；不代表远端 CI、标准 Flutter SDK、
macOS 实窗或 Android/iOS 真机手势重新验收。

仅跑新增测试无法覆盖生成与组件边界；重做全平台验收则不能替代这些边界测试。
本轮采用源码/API/所有权审查、框架全量、隔离 Plugin、Generator/CLI 全量、各真实 Host
新鲜度、Demo/模块和有界压力的分层验证。

## 13 条核心价值

| 核心价值 | 核查内容与判定边界 |
| --- | --- |
| 智能 | 声明、生成 Intent/Client、Host Assembly 与静态 Owner 校验继续承担装配，不依赖焦点猜测调用者，也不通过运行时反射发现业务。Generator 和实际 Host 产物分别验证。 |
| 简单易用 | `navigatorOf(context)` 返回原 `CCNavigator`，一次绑定后复用；旧全局和 per-call Context 用法保留。首次接入、README、Skill 与路由规范明确三种入口选择；未做新人可用性研究。 |
| 功能强大 | 原有 typed Route、Service、Command、Event、InitTask、Shell、父链、Deep Link、精确 close、重验证和返回桥继续回归。不会把完整 restoration、原生多窗口或任意外部 Router attach 写成已支持。 |
| 可扩展性 | Contracts/Core 保持 Pure Dart；Flutter Managed 与 Core/Host SPI 分层。便捷入口复用既有分发管线，不新增 Generator 协议或业务 Adapter 控制。内存 Adapter 与 Managed 均有测试，但不是第二个生产 UI Backend 认证。 |
| 可测试 | 框架测试集中在 `ccrouter_test/test`；Plugin 独立运行，真实 Analysis Server/LSP 与 Widget 测试分开。主 Demo 不替代独立 Order Example Host。 |
| 最小公开 API | 业务仅新增获取现有接口的入口；`CCNavigationHostLifetime` 被业务 barrel 隐藏。真实 Analyzer 正负向探针验证业务不可获取 Runtime 生命周期和 Host/Adapter SPI。 |
| 编译校验与类型安全 | typed 参数/结果、生成 Proxy、Contract Owner/版本/fingerprint、公开导出与跨组件依赖均有回归。已知目的地仍用生成 Intent；外部 URI 仍通过受控 ingress。 |
| 非侵入式 | 新 API 可选，原调用无需迁移；局部 Managed Outlet 和普通 Flutter 弹层边界保留。应用埋点、存储与布局仍由业务拥有，不因调用新入口而引入这些依赖。 |
| 可降级回退 | 可改回原 `CCRouter.navigator` + `context:` 调用，不更改 Intent 或 Contract。自定义 Backend 不支持精确能力时显式拒绝；不把失败 close 降级为 Pop 误删别页。 |
| 明确生命周期 | 绑定对象不保存 Context/Navigator/Runtime，不安装监听或 Timer，无须 dispose；原 Host 注销/Runtime 关闭后永久失效。页面退出不是 Host 注销。全量包含 GC、取消、异步结果、Scope 释放和 shutdown 边界。 |
| 可观测与溯源 | 保持脱敏、有界历史与单在途 Sink；DevTools 只读。另做四种容量的背压断言。运行时诊断边界与仓库历史验收日志的本机路径问题分开判定。 |
| 并发安全 | 多 Host/Outlet、显式 placement、焦点变化、同名 Host 换代、redirect/defer/resume、跨 error Zone、共享 readiness、重复返回和晚到结果均进入回归；业务对象不通过全局焦点重绑定。 |
| 性能和稳定 | 执行 Runtime/Service 扩展、100 并发导航、有界长运行和 1 万次额外循环。状态回收断言通过不等于零泄漏；无配对旧架构基线，不宣称耗时或 RSS 优于重构前。 |

## 执行记录

所有命令从仓库根执行，另有说明的除外。测试数量按 suite 分列，不将专项或 Monkey 步数
重复计入，也不将 benchmark 操作次数算作测试项。

| 检查 | 本轮结果 | 证据 |
| --- | --- | --- |
| `fvm flutter test packages/ccrouter_test/test --no-pub --reporter expanded` | 1,411 项通过 | [框架](framework.log) |
| `fvm flutter test --no-pub --reporter expanded`，cwd `demo/` | 113 项通过，含 feature matrix、3 seed × 120 步语义 Monkey、重复/取消 iOS 侧滑 | [Demo](demo.log) |
| `fvm flutter test --no-pub demo/modules/kv_storage/test demo/modules/payment/test demo/modules/navigation_lab/test --reporter expanded` | 9 项通过 | [组件模块](demo-modules.log) |
| `fvm flutter test --no-pub test --reporter expanded`，cwd `demo/modules/order/example/` | 1 项通过，打开生成 Route 并返回结果 | [独立 Example](example.log) |
| `fvm dart test tool/test --reporter expanded` | 51 项通过，含隔离 Skill/真实 API 示例 | [工具](tools.log) |
| `fvm dart test --concurrency=1 --reporter expanded`，cwd `packages/ccrouter_analyzer_plugin/` | 191 项通过，含真实 LSP/Analysis Server | [Plugin](plugin.log) |
| `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test --reporter expanded` | 668 项通过、1 项跳过，耗时 33 分 24 秒 | [Generator/CLI](generator.log) |
| `fvm dart analyze`，根目录及隔离 Plugin 目录分别执行 | 均 No issues found | [根分析](analyze.log)、[Plugin 分析](plugin-analyze.log) |
| `fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test --reporter expanded` | 41 项通过 | [应用埋点](analytics.log) |
| `fvm flutter test --no-pub demo/modules/analytics_flutter/test --reporter expanded` | 18 项通过 | [应用 Flutter 观察](analytics-flutter.log) |
| `fvm flutter test --no-pub packages/ccrouter_devtools/test packages/ccrouter_devtools_protocol/test --reporter expanded` | 12 项通过 | [DevTools](devtools.log) |
| `fvm dart tool/skill_bundle_check.dart` | 隔离双 Skill 分发包与真实 CLI 命令检查通过 | [Skill](skill-bundle.log) |
| `fvm dart tool/documentation_check.dart` | 最终报告/索引补齐后，178 份 Markdown 检查通过 | [文档](documentation.log) |
| `fvm dart tool/release_sensitivity_check.dart` | **失败**，45,392 处本机路径，147 个既有 tracked files | [分类汇总](sensitivity-summary.log) |
| `fvm dart run ccrouter_generator:ccrouter generate demo --no-cache --check` | 6 组件、34 Route、11 Packages 一致 | [主 Host 生成](generation-demo.log) |
| `fvm dart run ccrouter_generator:ccrouter generate demo/modules/order/example --no-cache --check` | 2 组件、2 Route、3 Packages 一致 | [独立 Host 生成](generation-example.log) |
| `fvm dart format --output=none --set-exit-if-changed <本次 13 个 Dart 文件>` | 0 changed | [格式](format.log) |
| `git diff --check` | 通过；生产源码差异摘要与开始时相同 | 最终命令输出 |

Generator 唯一跳过项是 `analyzer_installation_smoke_test.dart` 的远端 Git 安装/升级/
doctor/uninstall，需要显式 `CCROUTER_ANALYZER_NETWORK_SMOKE=1`。本轮未开启；
隔离 Plugin 的本地真实 Server/LSP 测试仍全部执行，不能相互替代。
生成器测试结束后的生产源码差异摘要与开始时一致，没有遗留临时源码改动。

本次 14 项 scoped navigator 专项已计入框架总数，不另行叠加。主 Demo feature matrix
与语义 Monkey 已计入 113 项，不按动作步数扩充测试数。日志保存时仅将工作树和用户
主目录路径归一化为 `<workspace>` / `<home>`，结果与计数保留原样。

本轮只新增/更新验证报告和文档状态，没有为追求全绿放宽断言、改动框架生产代码或更新
依赖。框架与 Plugin 的静态分析分别执行；未修改 Plugin，不变更 Demo bootstrap pin，
也没有声称用户活跃 IDE 已重新加载插件。

## 压力、性能与内存口径

- [默认性能套件](performance.json)包含 10/100/1000 Route、10/100/1000 Service、
  10 轮 × 100 并发导航，以及每 100 次重建 Runtime 的 1,000 次循环。
  并发场景结束保留预期的 1 个根 Entry，pending 为 0；完整 shutdown 通过。
- [额外 10,000 次循环](long-run-10000.log)每 1,000 次重建 Runtime；每次 Pop 后
  active Entry、backend Entry 和 pending navigation 均为空，最终 dispose 断言通过。
  单进程 RSS 起点约 197.3 MiB、终点约 269.7 MiB；未强制 GC，也没有原生分配保留分析。
  不能将空状态或 GC 专项通过等同于整个进程内存没有增长。
- [诊断容量](diagnostic-capacity.log)分别设置历史容量 0、64、128、1000，每组执行
  2,000 个 Command 并挂起 Sink。unfinished write 峰值均为 1；等待队列分别不超过
  64、64、128、1000，超量丢弃计数正常，shutdown 后释放测试 Sink。
- 这些进程在 Generator suite 仍运行时执行，存在主机竞争；耗时和 RSS 只保存快照，
  不作为跨提交性能比较或固定阈值门禁。默认性能套件未启用 `--full` Generator scaling。
  benchmark JSON 的 revision 是 HEAD，必须与本报告的未提交差异摘要一起解释。

## 未关闭项与建议顺序

### 本轮确认：交付敏感信息门禁失败

当前扫描的 45,392 处命中全部属于 `macOS absolute home path`，覆盖 147 个既有文件，
与本轮开始时已修改的 tracked files 无交集。扫描不回显值；这不证明做过完整 Secret
Scanner，也不证明未追踪文件或 Git 历史没有其它内容。当前问题来自历史验收记录保留
了主机路径，不能解释为 CCRouter Runtime 向业务诊断泄漏 payload。

建议另做日志/报告统一脱敏与证据保存流程，再运行同一门禁；不放宽 scanner，不删除旧
失败事实，也不把本轮所有行为测试通过写成“可正式发布”。本轮仅给新增保存日志做路径
归一化，既有历史证据保持原样。发布阻塞仍按[发布清单](../../CCRouter-release-readiness.md)。

### 既有真机待办不被源码回归关闭

[华为 30 分钟 Monkey](../20261024-huawei-monkey-30m/report.md)已记录的 Cupertino
正文默认样式、详情页 GoRouter 遗留文案，以及 Native/Graphics 内存增长、约 1.16 秒
build 长帧仍待修复或定位。本轮没有修改这些问题，也没有重做其真机对照。

推荐先处理可直接复现的 Demo 样式与文案，内存/长帧在无系统录屏、温控恢复后做受控
同引擎对照，再按 retaining path 定位。系统手势、macOS 实窗与 Hosted/发布归档验收
各自有独立完成条件，不从本轮自动化结果推断已经完成。
