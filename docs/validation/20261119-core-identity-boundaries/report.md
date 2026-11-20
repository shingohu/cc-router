# Core Contract 最终身份门禁（2026-11-19，本地）

后续 Host 合并快照保留多条消费范围约束的修复，见
[Host 合并记录](../20261119-host-contract-merge/report.md)。本页保留身份门禁阶段的历史证据。

继续此前授权的“修复 → review → 再修复”循环。此次核对五类 Core ContractBundle
在 Generator、Workspace、Host 与 Runtime 的身份边界，前轮见
[UI 边界收口](../20261119-ui-identity-boundaries/report.md)。保留此前未提交修改；
没有提交、推送、合并、打 tag 或同步 Demo pin。最新文件指纹见
[source-manifest.json](source-manifest.json)。

## 第一轮：匹配不代表身份有效

共享 `CCContractBundleDescriptor.validate` 已校验版本与已安装 fingerprint，但没有
校验 descriptor/requirement 的 ID 和 Owner 语法。空 ID、`Bad ID`、129 字符 ID 或
大写 Owner 只要两侧一致，就能通过最终门禁，[修复前复现](before-fix-proof.log) 为零问题。
这些输入已被对应 Generator 拒绝，最终 Host/Runtime 却缺少同一保护。

新增 21 项回归：五类 Contract 分别覆盖已安装身份、消费者身份、消费者 fingerprint、
合法长度/大小写能力 ID，以及真实 Host/Runtime 启动前拒绝。旧实现 16 项失败、5 项合法
边界通过，见 [RED](red.log)。

修复在原共享 validate 中进行，使用私有规则检查能力 ID 最长 128 字符、Owner 最长
128 字符且满足 lowercase component 语法。合法能力 ID 保留大写 segment，例如
`owner.MyService`。匹配但损坏的身份按来源 Package 报 `staleGeneratedOutput`，而非
把匹配结果误当作兼容证明；损坏的消费者身份不会被误分类为普通 missing Contract。

规则没有新增业务 API、配置开关或第三方依赖；与其在 Host/Runtime 两端分别打补丁，
沿用共享 Contracts 门禁可覆盖两个实际调用方。没有修改 Runtime 的 Service、消息注册
或 Scope API，只拒绝先前误接受的非法生成 descriptor/requirement。

## 第二轮：区分损坏 fingerprint 与真实形状变化

消费者 `requiredShapeFingerprint: 'bad'` 原先只会被报告为 fingerprintChanged，掩盖
生成 metadata 自身已损坏的事实。Core 新回归覆盖了该问题；Workspace 独立对照也先
复现失败，见 [fingerprint RED](fingerprint-red.log)。

现两条路径都要求完整 lowercase SHA-256。格式损坏归为 `staleGeneratedOutput`，
两个不同但合法的 SHA-256 仍为 `fingerprintChanged`。Core 复用同一个私有 fingerprint
规则校验已安装和消费者字段，保留版本/Owner/缺失/重复声明的既有错误门禁。

## 第三轮：复查与兼容边界

复查共享 validate 的 Host/Runtime 调用、已安装身份损坏后的诊断、消费者格式检查与
版本解析顺序、相同/不同 fingerprint，以及 Workspace 既有 source/metadata ID 校验。
[原始用例复跑](after-fix-proof.log) 现在对每组匹配但损坏的 descriptor 和 requirement
分别报告两条 stale 来源错误。此前 Owner 版本和合法消费者范围的归因修复继续由回归覆盖。

合法 128 字符 ID/Owner、合法能力 ID 的大写 segment、正确生成数据与正常消费仍通过。
只收紧非法输入，不扩展发布版本或自动迁移；旧手写/陈旧 bundle 如使用非法身份或非
SHA-256 shape 标签，需修正并重新生成。最终未再确认本轮身份门禁范围内的新问题。

新增规则为无状态值检查，不创建订阅、计时器或生命周期资源；在 Host/Runtime 启动前
失败，不安装部分状态。生产新增 helper 和正则均为库私有，没有增加业务导出。
已同步中英文根 README、Contracts/Generator README/CHANGELOG、兼容规范、integration
Skill/reference、CLI Skill 和 descriptor/requirement DartDoc。

## 最终验证

使用项目 FVM SDK（Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`）。

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1764 项通过摘要](framework-summary.log)，含新增 21 项 |
| Generator 相关 | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/contract_validation_test.dart packages/ccrouter_test/generator_test/workspace_validator_test.dart --reporter expanded` | [64 项通过](generator-final.log)，含新增 Workspace fingerprint 对照 |
| 根目录分析 | `fvm dart analyze` | [通过](root-analyze.log) |
| Demo | Demo 目录 analyze、`fvm flutter test --no-pub` | [分析通过](demo-analyze.log)、[118 项通过摘要](demo-tests-summary.log) |
| 完整生成 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [生成物一致](demo-reference.log)：6 components、34 routes、11 Packages |
| 普通生成 | 同命令 `generate demo --check` | [同样一致](demo-normal.log) |
| 格式 | 四个本轮 Dart 文件只读检查 | [无变更](format.log) |
| 文档/敏感信息/空白/源文件指纹 | 最终归档检查 | [archive-checks.log](archive-checks.log) |

框架和 Demo 测试只归档末 12 条非空输出，完整原始日志保留在本机 `/tmp`；其余为完整
输出。机械规范化只处理 ANSI、换行、行尾空白和 home 路径，不改变结果。
本轮未修改 Plugin 生产源码、未重跑其全量，未运行整个 Generator 目录、浏览器/实体
设备或独立发行安装。Demo Plugin pin 仍保持旧值，等待后续获授权的远端实现提交和
独立 bootstrap 同步；本地测试不能证明 Demo 已加载新 Plugin。
