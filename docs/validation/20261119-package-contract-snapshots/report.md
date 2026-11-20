# Package Contract requirement 快照传递（2026-11-19，本地）

后续 Contract 定义 Library、part 源码定位及 Owner 索引收口，见
[Library 身份记录](../20261119-contract-library-identity/report.md)。本页保留快照传递阶段的历史证据。

继续既有“审查 → 复现 → 修复 → review”循环，追踪上一轮
[Host 合并约束修复](../20261119-host-contract-merge/report.md) 的 CLI 上游。
保留全部此前未提交修改；没有提交、推送、合并、打 tag 或更新 Demo pin。
最新文件指纹见 [source-manifest.json](source-manifest.json)。

## 第一轮：emitter 重新生成范围，丢失已有约束

`_emitPackageContractRequirements` 没有使用 consumer metadata 中的
`requiredVersionRange` / `requiredShapeFingerprint`，而是重新读取当前 Owner record。
去重 key 也只包含 kind/ID/Owner。输入 `^1.0.0` 和 `<1.5.0`、当前 Owner 为 `1.1.0`
时，只生成一项精确 `1.1.0`，见 [原始输出](before-fix-emission.log) 与 [失败回归](red.log)。

现优先使用已经记录的 consumer snapshot，仅沿用旧 metadata 缺字段时的既有默认补齐；
完整范围和 fingerprint 都纳入去重 key。Service、Command、Event、InitTask 使用同一条
emitter 逻辑，独立范围保留、完整重复值去重。未增加源码 `versionRange` 参数，也未将
合法范围自动改写成交集或当前版本；旧缺字段 metadata 的精确版本默认行为保留。

## 第二轮：InitTask 补齐流程覆盖持久快照

上游 `_annotateConsumerContractMetadata` 原先重新构造 InitTask `contractDependencies`，
即使已有 snapshot 也会丢掉旧范围/指纹。现按当前 `dependsOn` 找已有快照，保留所有匹配
值，并复用原 `_copyConsumerContractFields` 只补齐缺字段。没有现有快照时按原规则生成。
中间修复曾漏补旧 snapshot 缺字段，[失败用例](legacy-fill-red.log) 已先复现，再补齐回归。

保留旧 Owner 后还需要相应校验：Workspace 原先只根据实际 task graph 校验 Owner，
没有核对 snapshot 自身记录的 Owner。[Owner RED](owner-red.log) 复现旧 Owner 被接受。
现在 InitTask dependency snapshot 与当前 Contract Owner 不一致时提前报
`[contract:ownerMismatch]`；已有范围、指纹不被“修复”成新值，而由兼容门禁决定是否有效。

## 第三轮：回归与边界复查

回归覆盖四类消费者的 snapshot 传递、Service/Event/InitTask 的多个独立范围、完整重复值
去重，以及旧 Service/InitTask 缺字段补齐。InitTask 的合法值、旧 Owner、超出范围、有效
fingerprint 变化和无效 fingerprint 分别核对其原有诊断类型。

为不暴露私有 CLI API，纯 emitter 测试从实际 CLI 源文件的明确函数段取出原实现，连同
真实 metadata 补齐/读取 helper 编译为临时 Dart 程序，检查真实生成字段；不是另写一套
测试实现，也没有新增依赖。测试只证明该纯数据路径，完整 CLI 的正常工作区行为另外由
Host aggregation 和 Demo 两种真实生成检查覆盖。没有声称模拟数据本身是完整合法 Pub 图。

核对补齐 → Workspace validation → Package Bundle emission → Host merge 顺序，未知
Contract 仍由原有门禁拒绝；不在 emitter 中绕过验证。最后复查未再确认本轮快照传递路径
中的新问题。未扩展为任意源码迁移、版本协商或通用 metadata 重写框架。

生产实现继续使用既有私有 CLI 函数，只新增读取 snapshot 参数与字段分支。无新增公开
API、开关、依赖或持久状态，不改变 Runtime 生命周期/注册/权限。同步了根 README
（中英文）、Generator README/CHANGELOG、Contracts README、兼容规范、integration
Skill/reference 与 CLI Skill。

## 最终验证

使用项目 FVM SDK（Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`）。

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| Generator/CLI 相关 | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/package_contract_requirement_test.dart packages/ccrouter_test/generator_test/workspace_validator_test.dart packages/ccrouter_test/generator_test/host_aggregation_test.dart packages/ccrouter_test/generator_test/contract_validation_test.dart --reporter expanded` | [70 项通过](generator-final.log) |
| emitter 单独复核 | `fvm dart test packages/ccrouter_test/generator_test/package_contract_requirement_test.dart --reporter expanded` | [通过](emission-final.log) |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1767 项通过摘要](framework-summary.log) |
| 根目录分析 | `fvm dart analyze` | [通过](root-analyze.log) |
| Demo | Demo 目录 analyze、`fvm flutter test --no-pub` | [分析通过](demo-analyze.log)、[118 项通过摘要](demo-tests-summary.log) |
| 完整生成 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [生成物一致](demo-reference.log)：6 components、34 routes、11 Packages |
| 普通生成 | 同命令 `generate demo --check` | [fast path 命中且一致](demo-normal.log) |
| 格式 | 四个本轮 Dart 文件只读检查 | [无变更](format.log) |
| 文档/敏感信息/空白/源文件指纹 | 最终归档检查 | [archive-checks.log](archive-checks.log) |

框架/Demo 测试仅归档末 12 条非空输出，完整原始日志保留于本机 `/tmp`；其余为完整输出。
证据只机械规范化 ANSI、换行、行尾空白和 home 路径，不改变测试结果。
本轮未修改 Plugin 生产代码、未重跑其全量，未执行整个 Generator 目录、浏览器/实体设备
或独立发行安装认证。Demo Plugin pin 未变，后续仍需获授权的远端实现提交和独立 bootstrap
同步；本地验证不代表 Demo 已加载新 Plugin。
