# 生成 Client 名称与 Contract 版本校验收口（2026-11-18）

后续按用户要求追加的 Event alias 与多轮复审见[2026-11-19 报告](../20261119-event-alias/report.md)。
本文件记录此前的名称/版本校验阶段，保留各次失败与执行边界。

本轮基线为 `7f3d95754eefb978b0074380a19c5fb14c11a9c6`（Git tag `0.2.0`），
在 `codex/unify-contract-validation` 分支本地修改。本文不代表新 Git tag、远端 CI 或发布验证。
最终源码摘要由后续 Event alias 报告的 source-manifest.json 统一保存；未以未提交 SHA 更新 Demo bootstrap。

## 问题、方案与兼容边界

1. **名称校验漏检**：UI 生成 Client 拒绝 Object 成员名，Service/Command 却允许
   `hashCode`、`runtimeType`、`toString`、`noSuchMethod`。这些名称作为静态成员会与
   Object 的实例成员冲突，导致生成代码不能编译。
2. **版本校验分散**：Route、Service、Command、Event、InitTask、Component 和 Workspace
   各自维护 SemVer 正则，UI 使用 Runtime 的 `CCSemVer`。前者拒绝首尾空白，后者会隐式
   trim；同样的版本字符串因此在不同入口表现不同。

逐个 Builder 修补会继续保留重复规则；新增业务 API、配置开关或自动重命名也没有必要。
本轮复用现有能力，在最窄的工具与值类型边界修复：

- Generator 的公共成员名称校验统一拒绝上述 Object 成员；Contract alias、消费方 alias、
  类型推导结果、持久化 metadata 校验和 CLI 使用提示共享此规则。Command Owner Client
  的隐式方法名也校验；Owner 推导冲突必须设置 Contract alias，消费方覆盖不能替代它。
- 隔离 Plugin 内复用一份名称校验，Service/Command/UI Contract 的字面量 alias 与 UI
  的有效默认名检查使用相同保留名策略。Command Owner 省略 alias 时也检查类型推导名；
  计算型覆盖值继续保守退让。不同 Analyzer 依赖仍隔离，不引入 Generator 依赖。
- Generator 的重复 SemVer 正则删除，统一调用 Runtime `CCSemVer`，保留各入口的声明定位
  和错误说明。`CCSemVer.parse` 要求完整匹配，版本值不接受任何首尾空白。
- 范围表达式保留外围空白、比较器之间空白，以及 caret/tilde 后原有的空白处理。
- 本阶段最初未新增业务参数；随后用户要求补齐 Event alias，见上方 2026-11-19 报告。

既有合法声明的 API 参数和语义保持；命名原本会产生不可编译静态 Client 的输入提前失败。
版本值的隐式 trim 被移除，这是可观察的输入收紧：将 `' 1.0.0 '` 改为 `'1.0.0'`。
不能通过手改生成文件或放宽 metadata 绕过校验。接入规则已同步根 README、集成 Skill、
相关参考、包说明与 API DartDoc。

修改不创建或持有资源，不改变 Runtime/Scope/Service 生命周期。此处没有新增性能、内存
或真机认证结论。

## RED 与定向 GREEN

修复前分别执行新增回归，保留三个独立失败记录：

| 复现 | 修复前结果 | 记录 |
| --- | --- | --- |
| Generator 公共名称规则拒绝 Object 名称 | `hashCode` 返回 true，断言失败 | [alias-red.log](alias-red.log) |
| Contract 版本拒绝首尾空白 | `CCSemVer.parse` 返回规范化版本，断言失败 | [version-red.log](version-red.log) |
| Plugin Contract alias 拒绝 Object 名称 | 没有产生预期诊断，断言失败 | [plugin-red.log](plugin-red.log) |
| Command Owner 的隐式 `toString` 名称 | 未拒绝生成 metadata，断言失败 | [owner-red.log](owner-red.log) |

修复后已完成：

| 检查 | 结果 | 记录 |
| --- | --- | --- |
| 命名、共享版本规则、Workspace 校验 | 60 项通过 | [common-green.log](common-green.log) |
| Contract 兼容测试 | 5 项通过，含范围空白回归 | [contract-green.log](contract-green.log) |
| Service、Command、UI Builder 新边界用例 | 3 项通过 | [builder-green.log](builder-green.log) |
| Command Owner 隐式名称与 Contract alias 修复 | 1 项通过，内部同时检查拒绝与显式 alias 成功 | [owner-green.log](owner-green.log) |
| 补齐 Owner 检查后的 Workspace 套件 | 56 项通过，含外部 metadata 默认名 | [workspace-final.log](workspace-final.log) |
| Plugin source/UI 定向测试 | 112 项通过 | [plugin-focused.log](plugin-focused.log) |
| 框架完整套件 | 1720 项通过 | [framework-full.log](framework-full.log) |
| 隔离 Plugin 完整套件 | 214 项通过，含真实 Server 场景 | [plugin-full.log](plugin-full.log) |
| 根静态分析、隔离 Plugin 分析 | 无问题 | [root](root-analyze.log)、[Plugin](plugin-analyze.log) |

定向测试可能重叠，不能累加为独立覆盖数量。补齐 Command Owner 推导诊断后，
[隔离 Plugin 最终套件](plugin-final.log)为 215 项通过，其新增 RED 见
[plugin-owner-red.log](plugin-owner-red.log)。

[Generator 完整尝试](generator-completed-attempt.log)执行完毕：689 项通过、51 项失败、
1 项默认跳过。显式失败输出集中于 Dart Pub 的 Flutter SDK bootstrap；有些断言未打印
子进程 stderr，不能凭缺失输出推断其全部细节。保留[失败选择清单](generator-retry-manifest.json)，
未修改 Generator 测试断言，改用正常 FVM 测试入口逐项复跑这些失败用例，
[51 项全部通过](generator-failed-cases-retry.log)。这是分次验证，不改写为一次完整全绿。
Owner/metadata 路径补齐后的其它检查及最终 Host 结果参见后续 Event alias 报告。

## 执行位置与命令

Plugin 的分析与测试均从 `packages/ccrouter_analyzer_plugin/` 执行，不借用根 Workspace
的 Package config。框架测试路径为 `packages/ccrouter_test/test`；其余命令默认从仓库根执行。

```sh
fvm dart analyze
fvm flutter test --no-pub packages/ccrouter_test/test --reporter expanded
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test --reporter expanded
```

最终完整 Generator 的实际入口（使用根解析出的 test Package，并显式提供同一 FVM SDK）：

```sh
FLUTTER_ROOT="<paired-Flutter-SDK>" fvm dart --packages=.dart_tool/package_config.json \
  "<resolved-test-Package>/bin/test.dart" --concurrency=1 \
  packages/ccrouter_test/generator_test --reporter expanded
```

隔离 Plugin：

```sh
fvm dart analyze
fvm dart test --concurrency=1 --reporter expanded
```

定向 Builder 命令：

```sh
fvm dart test --concurrency=1 \
  packages/ccrouter_test/generator_test/service_generator_test.dart \
  packages/ccrouter_test/generator_test/command_generator_test.dart \
  packages/ccrouter_test/generator_test/ui_fragment_generator_test.dart \
  --name 'Object member|UI versions reject whitespace' --reporter expanded
```

## 生成检查的并发边界

完整 Generator 中的 watch 测试会在真实 Demo 上临时修改与恢复文件；不能同时执行独立
的真实 Host 生成作为验收。本轮中途曾重叠执行一次 `generate demo`，该次仅命中 fast path，
没有写入产物，见 [overlapping-generation.log](overlapping-generation.log)。它不计为独立
Host 验收。后续 Host 检查复用现有 `real-workspace.lock` 的 POSIX 排他记录锁，
与测试库的真实 Workspace 修改串行；最终还在失败用例复跑及临时探针恢复后重新检查。

首轮完整 Generator 运行遇到一条已安装 Flutter wrapper 的 preflight 用例失败，子进程
在 Dart Pub bootstrap 阶段报告 `webview_flutter` 需要 Flutter SDK。随后复审发现 Owner
Command 默认名路径需要补齐，首轮在该修改前被中断，不能作为最终完整套件验收，见
[首轮保留记录](generator-first-interrupted.log)。该 preflight 用例在没有修改 Hook 代码的
情况下独立复跑通过，见 [hook-recheck.log](hook-recheck.log)。

最终 Generator 运行使用根 Package config 解析出的 test 入口并显式提供配对 Flutter
SDK 环境。它的 reload gate 子进程也出现了同类 Dart Pub bootstrap 错误；相同源码用
正常 FVM 测试入口复跑该文件，19 项通过，见 [reload-recheck.log](reload-recheck.log)。
保留整次运行的失败与后续复跑边界，不把分次通过改写成一次完整全绿。

## Demo Plugin pin 与未覆盖范围

本轮修改 Plugin 生产诊断，但用户仅授权本地修改，没有授权本轮提交、推送或打 tag。
因此 Demo manifest/lock 保留基线的远端 pin，待源码评审并获授权推送后，按仓库要求在
独立后续提交中同步。不能将本地 Plugin 测试通过宣称为 Demo IDE 已加载这些新规则。

本轮没有 GUI IDE、真机、长期 heap、性能基准或发布安装矩阵验证。已有历史验证不覆盖
这些本地未提交改动。归档日志保留原件，只机械规范化本机 home 路径与行尾显示空白，
不改写诊断、结果、测试数量或失败事实。
