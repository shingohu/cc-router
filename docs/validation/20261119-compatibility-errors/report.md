# 兼容错误归因与 UI Host 错误边界（2026-11-19，本地）

后续 UI 身份及 metadata 字段边界核对见
[UI 边界收口](../20261119-ui-identity-boundaries/report.md)。本页保留错误归因阶段的历史证据。

继续此前授权的“排查 → 复现 → 修复 → review”循环。范围为共享契约校验、Workspace
Validator、Host 合并调用方及 UI Host 的版本输入错误语义。保留所有此前未提交修改，
未提交、推送、合并、打 tag 或改变 Demo pin。前轮见
[版本校验记录](../20261119-semver-consistency/report.md)，最终文件指纹见
[source-manifest.json](source-manifest.json)。

## 第一轮：错误归因

共享 `CCContractBundleDescriptor.validate` 把范围解析和已安装版本解析放在同一个 try
中，任一 FormatException 都被当作消费者范围损坏。Owner 版本为 `bad`、消费者范围
为合法 `1.0.0` 时同时出现 Owner 错误与假的消费者错误。Workspace Validator 有同一
结构，分别由 [Core RED](core-red.log)、[Workspace RED](workspace-red.log) 复现。

共享校验现在只解析一次已安装版本，并在本次验证的局部 map 中保留有效版本；Owner
解析错误仍按发布 Package 报出。消费者范围独立解析，只有两个值都有效才比较范围。
Workspace 使用同样的错误边界，已有安装版本错误不再触发假的消费者范围诊断。

五组对照分别覆盖 Owner 错、消费者错、双方错、合法但超范围和完全合法；要求错误数量、
归属与原有 code 一致。双方都损坏仍分别报告，不吞错误，也不把 Owner 问题转移给消费者。

## 第二轮：UI Host 的稳定错误类型

Owner descriptor、Consumer descriptor 或 requirement range 格式损坏时，UI Host 原先
直接泄漏包含原始输入的 `FormatException`，绕过其稳定的 `CCUIFragmentError`。
三种情况均在 [UI RED](ui-red.log) 中复现。

现将格式解析失败转换为 `CCUIFragmentError('staleGeneratedOutput', contractId)`，
只携带既有稳定身份。合法版本但范围不匹配仍为 `versionOutOfRange`，fingerprint、
精确版本快照、Owner 与缺少实现的原有检查顺序不变。不吞非格式异常。
回归同时核对异常类型、code、contractId、错误文本不包含无效输入，以及 Runtime 未初始化。

选择在现有错误边界收口，避免应用自行捕获底层解析异常或新增错误类/公开 API。
Core 版本 map 仅在一次校验内使用，结束即释放；UI 验证发生在 `_UIBinding` 构造前，
不安装部分 catalog，不改变初始化/销毁所有权，也不新增订阅或异步任务。

## 第三轮复查

核对共享 validate 在 Host/Runtime 的调用方、重复/缺失/Owner 不符的原有门禁、Workspace
相邻 FormatException 路径、UI 注册失败时机与错误对象字段。既有 fingerprint、版本精确
快照和预发布比较回归继续通过。最终未再确认本轮错误语义范围内的新问题；不把只存在
理论可能、没有错误结果的地方当作新功能或重构。

根 README（中英文）、Contracts/Generator/UI README 与 CHANGELOG、兼容规范、UI 设计
文档、integration Skill/reference、CLI Skill 及 DartDoc 已同步。未新增业务导出或依赖。

## 最终验证

使用项目 FVM SDK（Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`）。

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1738 项通过摘要](framework-summary.log)，含新增五项 Core 归因和三项 UI 错误回归 |
| Generator 相关 | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/contract_validation_test.dart packages/ccrouter_test/generator_test/workspace_validator_test.dart --reporter expanded` | [63 项通过](generator-final.log)，含五项 Workspace 对照 |
| 根目录分析 | `fvm dart analyze` | [通过](root-analyze.log) |
| Demo | Demo 目录 analyze、`fvm flutter test --no-pub` | [分析通过](demo-analyze.log)、[118 项通过摘要](demo-tests-summary.log) |
| 完整生成 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [生成物一致](demo-reference.log)：6 components、34 routes、11 Packages |
| 普通生成 | 同命令 `generate demo --check` | [同样一致](demo-normal.log) |
| 格式 | 六个本轮 Dart 文件只读检查 | [无变更](format.log) |
| 文档/敏感信息/空白/源文件指纹 | 最终归档检查 | [archive-checks.log](archive-checks.log) |

框架和 Demo 测试只归档末 12 条非空输出，完整原始日志仍在本机 `/tmp`；其余为完整输出。
证据仅机械规范化 ANSI、换行、行尾空白与 home 路径，不改变结果。
本轮未修改 Plugin 生产源码、未重跑其全量，也未运行整个 Generator 目录、浏览器/实体
设备或独立发行安装认证。Demo Plugin pin 仍待后续获授权的远端实现提交与独立同步。
