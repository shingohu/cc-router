# Generator / Plugin 升级后的语义补齐

日期：2026-11-17。分支：`codex/build-runner-2161`。本轮建立在此前尚未提交的工具链升级上，
只补 Plugin 语义选择与跨版本边界测试；不升级 Plugin 的 Analyzer，不改生成语义或协议 schema。

## 问题与根因

Plugin `_resolvedCurrentUnit` 在调用当前 Analysis Server session 前，用字符串标记筛选文件。
原列表包含 `CCComponent` 等前缀，但没有 UI 标记。UI Contract 的 Owner 如果在同文件用
`CCComponentId(...)` 构造，会偶然触发解析；改为从别的文件导入常量后，只含
`CCUIFragmentContract` 的文件就退回 parser-only，Action 类型规则无法取得语义信息。

上次评估将 `CCRouteContract`、`CCServiceContract` 等也列为缺失触发并不准确：
原实现使用 `source.contains`，已有 `CCRoute` / `CCService` 前缀会覆盖它们。
本轮先用真实 LSP 的 UI-only 文件复现，再修复实际缺口。

## 方案、取舍与实现

- 只给旧列表加 UI 字符串：改动最少，但注解身份表和触发条件仍可能漂移。
- 复用已有 `CCRouterResolvedSymbols` 的身份表，再保留 Host/Component/Command 和 UI SPI
  类型标记：推荐；只改变是否请求当前 session，结果仍由原有规范库 URI/类型证明验证。
- 把 Plugin 升到 Analyzer 13 或合并两张依赖图：不能解决触发筛选根因，且增加 loader/Server
  迁移成本，本轮不做。

新增内部 `mayNeedResolution`，两个现有调用入口（诊断、Quick Fix）继续共用
`_resolvedCurrentUnit`；不新增 resolver、AST 缓存、轮询、依赖、业务公开 API 或开关。
词法触发不是框架身份证明：同名外部符号仍由现有语义规则排除；类型不可用、源码已变更时
沿用原有保守回退。完全改名且文件中没有任何已知标记的 alias-only 情况保持原来的回退边界，
本轮不宣称覆盖任意别名。没有性能基准，不宣称编辑速度提升。

## 测试步骤与证据

所有 Plugin 命令从 `packages/ccrouter_analyzer_plugin/` 执行，使用官方 Flutter 3.47.9 /
Dart 3.13.7；Generator 为 Analyzer 13.3.0，Plugin 仍为 Analyzer 8.4.0 /
analyzer_plugin 0.13.10。真实 Server 使用临时缓存和本地 Plugin 源码。

1. **RED：** 新增真实 LSP 用例，UI 文件只用 `@ui.CCUIFragmentContract` 和导入的 Owner。
   开放 Action 类型应报 `ccrouter_ui_action_invalid`；原实现等到 60 秒仍没有对应诊断。
   现有大量 UI 测试内联 `CCComponentId`，不能代替这个边界。
2. **GREEN：** 修复触发后，诊断出现在注解的第 5 行、第 1 列（LSP 为 line 4 / character 0）。
   未保存地将 `class Action` 改为 `final class Action` 后诊断清除，磁盘源码未改。
3. **选择边界：** 保留裸 `CCCommand<T>` 和 UI SPI 类型的解析选择；普通 Dart 源码不触发。
4. **跨版本契约：** 新增测试先读两张 package_config 的实际 Analyzer manifest，证明 13.x / 8.4.0
   隔离。随后通过根 package_config 启动 Generator 的 `generate demo --no-cache --check`，
   证明磁盘 metadata 与当前生产器逐字节一致，而非手写一个 JSON 冒充生产器输出。
   Plugin 读取真实 schema 5 / UI schema 3 索引，核对 UI Owner、声明库 URI、Service Owner
   诊断范围、Quick Fix 和应用后的诊断清除。输入变化只在内存中；最后验证磁盘源码保持原样。
   此命令只属于维护者集成测试，Plugin 生产运行路径仍不调用生成器。

执行命令：

```sh
fvm dart analyze
fvm dart test
```

最终分析无问题，完整 Plugin **215 项通过、0 项失败**，包含真实 Legacy/LSP、overlay、
磁盘刷新、Quick Fix 与跨版本生产器参考检查。此前第一次完整 Plugin 运行为 214 项通过；
补充裸 Command 选择边界后，以 215 项运行验证最终源码。另行执行 Host 的
`generate demo --no-cache --check` 成功（6 个组件、34 条路由、11 个生成 Package）。

- [LSP 修复前](lsp-red.log) / [LSP 修复后](lsp-green.log)
- [最终独立分析](analyze.log) / [最终完整 Plugin 测试](plugin-full.log)
- [真实跨版本 metadata/Quick Fix](cross-analyzer.log) / [Host 参考检查](host-check.log)
- [源码指纹](source-fingerprints.json) 用于关联这次验证的生产改动和测试。

本轮没有重跑 Flutter Runtime/Demo Widget 全量或 50 分钟的 Generator 全量：未修改这些生产
路径；跨版本测试实际执行 Host 的参考检查。此前 SDK 升级数字保留在原升级报告，不算本轮新执行。

## 发布与回退边界

本次改动会影响 Plugin 诊断，适用仓库 AGENTS.md 的两阶段 pin 流程：
“first commit, verify, and push the Plugin change; then use its remotely resolvable full commit SHA
in a separate Demo bootstrap update”。本轮只形成可审查本地改动，没有提交、推送或更新 Demo
bootstrap；现有 manifest/lock 的远端 ref 仍为 `f0bd3c2af3c3f6282f503e7182a41779beeb19f5`。
因此不宣称 Demo IDE 已使用本地修复。发布后还需单独更新 manifest/lock、pin-check、doctor、
重启 Analysis Server 并验证真实 IDE diagnostic/Quick Fix。

回退仅需还原本轮 Plugin 解析选择、对应测试与指导，不改变 Analyzer 约束或生成协议。
旧 SDK/生成物的分发约束仍按上一轮升级报告处理，不由本次 Plugin 测试替代。

## 后续 Review：CI SDK pin 修复

Review 发现 Quality workflow 的六个 Flutter Job 仍固定 3.41.9，忽略根 FVM 的 3.47.9。
3.41.9 的 Flutter 固定 meta 1.17.0，与 Generator Analyzer 13.3 的 meta ^1.18.3 冲突。
本地临时最小包确认同一 pin 冲突会在 Pub 阶段失败；没有把模拟解算称为真实 Actions 运行。

已将六个 Job 统一为 Flutter 3.47.9，Plugin Job 单独安装的 Dart 同步为配套 3.13.7。
独立 Plugin Package 的 Analyzer 8.4.0 / analyzer_plugin 0.13.10 约束与解析边界保持不变，
不再让跨版本生产器集成测试混用更早的 CI Dart 工具链。

新增测试逐一检查 workflow 中的 Flutter pin 与根 `.fvmrc` 一致，而非把目标版本再写死一份：
[修复前失败](ci-pin-red.log)、[修复后通过](ci-pin-green.log)。本轮额外验证：

- Ruby 标准 YAML parser 成功解析 workflow，并确认六个 Flutter action 都为 3.47.9。
- 官方 Flutter 3.47.9 下根 Pub 解析成功（显式禁用 Pub Hook，不冒充 Host 生成）。
- [workflow 测试文件分析](ci-workflow-analyze.log)无问题。
- [仓库工具测试全量](ci-tool-tests.log) **53 项通过**，包含 workflow guard、文档检查器及 Skill bundle 测试。
- `git diff --check` 通过。

本轮未重新跑 Runtime、Generator 或 Plugin 全量，未修改这些生产路径；此前同一 SDK 的
结果仍按各自轮次保留。没有触发真实 GitHub Actions、提交、推送或更新 Demo Plugin pin。
严格全仓分析的既有 warning 与其他尚未验证的 CI 步骤不由这些本地检查自动闭环。

## 再次 Review：静态分析、Portable State 与证据脱敏

本节记录用户授权的三项修复，前文各轮测试数字与失败事实保持原义。

1. CI 的实际命令 `fvm dart analyze packages` 会被 Core 两处
   `unawaited_return_in_try_block` 阻断。没有机械添加 `await`：dispatch 与 defer 的
   异步终态已有各自错误规范化和观测路径，交回外层 catch 会改变错误归属。
   仅在这两处记录原因并局部豁免，保留现有控制流与终态观测语义。
2. Demo 的 9 份 Portable State 仍含旧工具指纹；重新 prepare 后又发现 Host 校验成功、
   单个组件或 contracts Package 校验仍报 `toolMismatch`。根因是 Package-local 写入范围
   将只读本地 Framework 依赖排除出 authored identity，导致同一 Workspace 的工具身份不同。
   修复仅补充已有的本地 Workspace 成员判定，不放宽工具、源码、解算或产物校验。
   新测试真实执行 Host prepare，再分别从 Host、Order 和 Order Contracts 执行 publish；
   修复前在 Order 失败，修复后通过。先前“已重生成 9 份”的记录没有覆盖这些 publish
   入口，不能作为状态已可分发的验收结论；以下最终验收补齐此缺口。
3. 三份新增日志含 11 处本机 home 路径。使用仓库已有
   `tool/sanitize_validation_evidence.mjs --write` 规范化路径，保留测试输出和历史失败；
   原件备份留在仓库外临时目录，未将备份路径或原始 home 写入证据。

本次 Core 修复后重新运行 Framework **1650 项**、Demo **117 项**与仓库工具 **53 项**，
均通过。它们在随后 Portable 身份修复之前执行，Portable 改动另用 Generator 回归验证；
未将先前 Generator 全量 725 项或 Plugin 全量 215 项算作本次新运行。

Portable 身份修复后的扩大回归为 **54 项通过、0 项失败**（37 项生成命令、2 项真实
Git/归档分发、15 项 Workspace/Index 校验），串行运行以避免真实 Workspace 夹具竞争：

```sh
fvm dart test --concurrency=1 \
  packages/ccrouter_test/generator_test/generation_command_test.dart \
  packages/ccrouter_test/generator_test/portable_distribution_test.dart \
  packages/ccrouter_test/generator_test/package_workspace_test.dart
```

覆盖同一 Workspace 的 Host/Package 身份一致性、缓存和无缓存字节一致性、工具源码变化
失效、prepare 修复状态、依赖变化回退、只读状态缺失拒绝，以及独立分发中的源码与解算
变化拒绝。生产修复只是两行条件/原因说明，没有新增协议、依赖或对外 API。

- [Package-local 修复前](fix-portable-local-red.log) / [修复后](fix-portable-local-green.log)
- [扩大回归完整日志](fix-portable-regression.log)
- [CI packages 分析](fix-packages-analyze.log) / [Runtime、Demo、工具命令与结果摘录](fix-runtime-tools-summary.log)

所有会还原夹具的测试结束后，再次执行 `portable prepare demo`，随后从 Demo Host 和
kv_storage、navigation_lab、network、order、order_contracts、payment、web、web_contracts
八个 Package 分别执行 `portable publish`，**9 个入口全部成功**。最终 Demo 和独立 Order
Example 的 `generate --no-cache --check` 均成功；这次不依赖缓存命中证明状态可用。
9 份状态的工具指纹统一为 `493510bf744e3fea11308cd4bfedff721579b5a66edb570a51f880fbb22afda1`。
该指纹绑定当前源码，后续 Generator 或工具链再次变化仍须重新 prepare。

最终 `analyze packages`、`analyze tool`、文档检查、证据脱敏 dry-run、包含未跟踪文件的
敏感信息检查和 `git diff --check` 均通过。文档检查覆盖 190 份 Markdown；脱敏 dry-run
待规范化文件为 0。对应证据：

- [最终 prepare、9 个 publish 和两个 no-cache check](fix-portable-final.log) / [命令退出码](fix-portable-final-results.json)
- [本次生产源码与 9 份状态指纹](fix-source-and-states.json)
- [最终仓库门禁](fix-final-gates.log)

仍未执行提交、推送、真实 GitHub Actions 或原生/OHOS 构建；未重跑 Plugin 全量或修改
Demo Plugin pin，IDE 当前会话仍不由本次 Generator 修复验证替代。

## 合入主分支后的组合验证

按用户要求，将 `main` / `origin/main` 的 `ab20c1570fa153f658c5310744228930ae19b9d5`
快进合入 `codex/build-runner-2161`，再恢复原工作区的未提交修改与报告。合入前已保存
148 份修改/未跟踪文件的本地备份，并保留可恢复 stash；120 个不涉及主分支冲突或
生成产物更新的文件恢复后逐字节一致。没有创建新提交、推送或改写主分支。

生产代码自动合并，保留主分支的 Service Stream、多个 typed Extra、已有 Entry 导航交接
与 UI Fragment 复用，同时保留本分支的 Analyzer 13、watch、原生 Pop 和 Semantics 修复。
冲突为 9 份 Portable State 和首次接入文档：状态由生成器重新生成；文档保留主分支
新增的最低版本认证/历史验证边界，SDK 与 CI 说明按本分支 3.47.9 / Dart 3.13.7 对齐。

合并后的本次新执行结果：

- Framework 全量 **1718 项通过**。
- `flutter test --no-pub demo` 全目录 **188 项通过**，包含模块与 Example。
- Route、Service、UI Fragment 三个 Generator 测试文件 **209 项通过**；新增 Stream
  代理、多 Extra、UI 更新策略及拒绝边界均保留。没有重跑 Generator 全目录。
- Host prepare 后从本地 Package 验证 Portable State 的专项 **1 项通过**。
- Plugin 在独立 Package 目录分析成功，完整 **215 项通过**，含真实 Legacy/LSP 与
  Analyzer 13 metadata / Analyzer 8.4 Quick Fix；独立依赖版本及 Demo pin 保持不变。
- 仓库工具 **53 项通过**；packages/tool 分层分析、文档和敏感信息检查通过。

上述测试结束后再次 prepare，并验证 9 个 publish 入口与 Demo、Order Example 的
`--no-cache --check`。本节对应当前组合源码，前文所有测试数字和旧工具指纹仍是各自
轮次的历史证据；当前命令结果与状态身份见：

- [合并后命令与退出码](merge-main-results.json)
- [测试与最终生成检查摘录](merge-main-summary.log)
- [当前生产源码与 Portable State 指纹](merge-main-source-and-states.json)

仍未验证真实 GitHub Actions、原生/OHOS 构建或 IDE 当前会话；本地备份不代表发布完成。
