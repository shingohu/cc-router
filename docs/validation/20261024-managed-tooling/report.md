# Managed 工具链修复与接入回归（2026-10-24）

范围：`codex/managed-navigation-runtime` 的本地工作树，Generator 脚手架与隔离 Analyzer
Plugin；不修改 Runtime 导航契约，不升级 Analyzer 依赖，不代表新的平台或发布验收。

## 根因与方案

- Generator 已经使用 backend-neutral Route/Host metadata，不需要为 Managed 重写生成链。
  本轮保留 Builder、Validator、只读依赖和 Portable fingerprint 的权威边界。
- Analyzer 原来只检查 import/export 主 URI，条件分支可漏过 generated 内部引用检查。
  现在逐 URI 检查并定位实际字面量。
- placement 与 policy 的确定性配置错误只能等生成发现。现在对框架身份确定的直接字面量
  提前诊断；未知/计算表达式和全图拓扑继续由 Generator 判断，不增加推测式 Quick Fix。
- `--with-example` 原来只创建 Flutter 空模板并补依赖。现在提供生成 Assembly 的 Managed
  入口、Example 自有首页/组件描述、build_runner 与同 SDK 测试依赖，仍保留可选入口和原子发布。
- 真正的 Workspace 外验收发现：Example 对父组件的 `path: ..` 依赖是只读；父组件必须先
  prepare Portable State。两边独立解析还曾出现 `stack_trace` 1.12.2/1.12.1 导致 toolMismatch；
  同 SDK 测试依赖消除了该复现，未放松 fingerprint。其它独立 lockfile 仍需团队对齐工具链。

相比重写 Generator、共享不同版本 Analyzer AST 或绕过 Portable 校验，本方案只扩展现有
可选工具与脚手架，成本和迁移风险较低。业务 API 与已有工程保持不变；已有 Example 不自动重写。

## 验证范围

配置正反例由同一 JSON fixture 分别交给 Analyzer 8 与 Generator 10 验证；包含默认根、显式根、
合法拓扑、有序 policy、非法 Host/Outlet/Shell/parent、自引用和重复 policy。
真实 LSP 测试验证未保存配置修复后诊断清除。独立脚手架测试只复制框架源码与 Builder 配置，
不复制 Workspace Pub/build 状态；实际执行 Pub、父组件 Portable prepare、Example 生成、
分析、Managed 挂载、父组件动态 URI、typed 参数/结果、覆盖页面精确 close 与最终无缓存检查。

当前已完成：Flutter 框架 1397 项、Demo 181 项、隔离 Plugin 全套 191 项（含真实 Legacy/LSP
Server）、独立消费者闭环 1 项、共享 Generator 配置 11 项通过。根工作区与隔离 Plugin
静态分析均通过。为排除编译失败导致的假阳性，Contract
typedef 配置测试同时断言 Dart 语义无 error；修改断言 API 后定向复跑通过，Plugin 分析无问题。
Generator 首次全量扫描已结束：665 项通过、1 项跳过、1 项失败。唯一失败的脚手架用例已修复，
受影响的完整脚手架测试与独立消费者闭环复跑通过，具体如下；修复后没有重复执行整套约 40 分钟
的扫描，不能将首次全量报告为全部通过。跳过项为需要显式启用
`CCROUTER_ANALYZER_NETWORK_SMOKE=1` 的远端网络 smoke，本轮未启用。原始记录见
[框架](framework.log)、[Demo](demo.log)、[静态分析](analyze.log)、
[独立工程初跑](standalone.log)、[共享配置](shared-rules.log)、[Generator 全量初跑](generator.log)。

全量扫描中的 Example 来源继承用例复现了原有 YAML scalar 输出缺陷：`>=...` SDK 范围
未引用，Flutter 将其当作 block scalar 而拒绝读取。扩大复核还复现创建期间上游 manifest
变化可使组件与 Example 的 build_runner 来源不一致。[两项修复前失败](scaffold-review-red.log)
已保留。真实 Workspace 生成专项结束后，修复使用 YAML 解析 round trip 保留 scalar 类型，
并从 staged component manifest 重算 Example 工具依赖。全部 12 项脚手架测试与独立消费者
闭环重新运行，共 13 项通过，见[修复后完整脚手架/消费者回归](scaffold-final.log)。
全量日志保留首次失败，不以复跑结果覆盖原始证据。

主要命令从仓库根执行；Plugin 两项从其隔离目录执行：

```sh
fvm dart analyze
fvm flutter test packages/ccrouter_test/test --reporter expanded
fvm flutter test demo --reporter expanded
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test --reporter expanded
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/scaffold_command_test.dart packages/ccrouter_test/generator_test/managed_scaffold_integration_test.dart --reporter expanded
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --profile --check
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --profile --check
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo/modules/order/example --check
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo/modules/order/example --no-cache --check
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer pin-check demo
fvm dart test tool/test --reporter expanded
fvm dart run tool/documentation_check.dart
fvm dart run tool/skill_bundle_check.dart
fvm dart run tool/release_sensitivity_check.dart
# cwd: packages/ccrouter_analyzer_plugin
fvm dart analyze
fvm dart test --concurrency=1 --reporter expanded
```

仓库工具 51 项、文档链接、独立 Skill bundle/实际 CLI 帮助、两个修改 Skill 的
`quick_validate.py` 和发布敏感项检查通过。[仓库工具日志](tools.log)。

实际 Host 的生成 freshness 检查也均通过：Demo 的[缓存路径](demo-cached-check.log)与
[无缓存参考路径](demo-reference-check.log)，以及嵌套 Order Example 的
[缓存路径](order-example-cached-check.log)与[无缓存参考路径](order-example-reference-check.log)，
均无生成物差异。根工作区是聚合器，没有以根 Pub 成功替代这些 Host 检查。

## 性能基线

使用现有 `benchmark/analyzer_edit_scaling.dart`，本机 Dart 3.11.5；同时有其它开发/测试负载，
这是当前源码的 smoke 基线，没有与旧架构做配对 A/B，不据此声称加速。
该 fixture 主要是被动声明加一个能力，不代表数千个复杂 Route 的上限。

| 声明数 | parser + 规则平均，50 次 | resolved 规则 P50 / P95，20 次 | Server 解析 P50 / P95 |
| --- | --- | --- | --- |
| 100 | 1.047 ms | 0.827 / 1.482 ms | 6.817 / 8.593 ms |
| 1000 | 1.792 ms | 1.362 / 1.871 ms | 19.940 / 30.952 ms |
| 3000 | 4.424 ms | 2.097 / 5.379 ms | 48.090 / 52.089 ms |

见[原始性能输出](analyzer-edit-performance.log)。没有观察到足以支持新增缓存或改变 polling
默认策略的证据，因此本轮保留现有失效与正确性门禁，不以性能名义弱化验证。

另跑现有 [polling 基准](analyzer-poll-performance.log)：100 个 Package 的角色/解析 identity
稳态检查平均 3.134 ms，10000 条 exact path 的全量 fallback P50 为 35.346 ms；分片 P50 为
4.767 ms，但有更长的漏事件恢复延迟。该比较针对已有实现，不能当成本轮新增优化收益，
也没有据此开启默认关闭的分片选项。

Demo 生成缓存路径为 451 ms，无缓存参考路径为 2386 ms，output delta 均为 0；后者验证
6 个组件、34 条路由、11 个参与生成的 Package。无缓存指 Generator 参考路径，仍保留
build_runner 增量状态（其构建阶段 1173 ms），不属于冷构建，也不是与旧架构的配对性能比较。

## Plugin 发布边界

Demo bootstrap 当前仍固定远端完整 SHA
`51c5b3892928337e7c7728fa9dd6845ac2f93b2e`，没有指向本地未提交源码。
[pin-check](analyzer-pin-check.log) 已通过：manifest/lock/resolved-ref 一致，远端 ref 可解析，
本地生产代码变化按预期报告为 pending；这不表示 Demo 已加载本轮 Plugin。
本地真实 Server 测试不是 Demo IDE 已加载新版的证明。按 AGENTS 的两阶段流程，先提交、推送
Plugin，再单独更新 Demo bootstrap SHA/lock，执行 pin-check/doctor、重启 Analysis Server
并验证实际 IDE 诊断。该外部发布步骤不包含在本轮本地修复中。
