# UI 身份与 metadata 边界收口（2026-11-19，本地）

后续五类 Core ContractBundle 最终身份门禁检查，见
[Core 身份记录](../20261119-core-identity-boundaries/report.md)。本页保留 UI 阶段的历史证据。

在此前“修复 → review → 再修复”授权范围内，继续核对 Host、Workspace 和 Generator 的
UI 声明输入。上一轮 [兼容错误修复](../20261119-compatibility-errors/report.md) 已保留在
当前工作区，本轮没有重复修改那些已完成的修复，也未提交、推送、合并、打 tag 或改 Demo pin。
最新改动文件指纹见 [source-manifest.json](source-manifest.json)。

## 第一轮：Host 与 Generator 的身份规则不一致

Generator 已限制 UI 能力 ID 与 Owner 最长 128 字符，Owner 使用 lowercase component
语法；Host descriptor validator 却只使用能力 ID 的正则，遗漏长度并允许大写 Owner。
手写或陈旧 SPI 可通过 Host 装配，即使相同输入在源码生成时会被拒绝。

先新增 128/129 对照：[长度 RED](host-length-red.log) 中两个合法 128 字符样本通过、
两个 129 字符样本错误地通过装配而使回归失败。[Owner RED](host-owner-red.log) 复现
`Orders` / `orders.Team` 被接受。修复沿用已有 Host descriptor validator，补齐长度与
lowercase Owner 规则；能力 ID 的既有大小写 segment 语义保持。

最终五项 Host 回归核对合法上界、非法上界、Owner 语法及 Runtime 未初始化。无新增
公开 API、配置、依赖或生命周期资源；错误仍为 `staleGeneratedOutput`，发生在 UI 绑定创建前。

## 第二轮：一致的 metadata 也可能同时损坏

Workspace 原来主要比较 schema/version/fingerprint 快照是否相等，却不证明字段自身有效。
Contract/Renderer/Requirement 三份都填 `shapeFingerprint: 'shape'` 或相同坏版本时，CLI
可能通过，直到 Host 才失败。package-local 检查还会漏过无效 requirement range。

[Workspace RED](workspace-red.log) 覆盖匹配但损坏的 Owner、ID、类型、版本和 fingerprint，
以及 package-local 范围。新增第一轮 19 个用例中 17 个失败，说明仅快照一致不足以证明有效。
现对三种 record 分别验证字段类型、身份长度/语法、共享 SemVer 及 lowercase SHA-256，
并在 Package/Host 两种模式都解析消费者范围。保留已有来源位置和 stable diagnostic code。

复用原有共享 SemVer，身份语法与 Generator/Host 保持一致。验证局限于当前 metadata 快照；
没有新增 Analyzer session、磁盘扫描或业务 payload 读取。原正例中简化的 `'shape'` /
`'payload-shape'` 夹具改为合法 SHA-256；不同 shape 的负例使用另一个合法 fingerprint，
继续单独验证兼容性错误，而不是依赖无效输入。

## 第三轮：避免重复故障，确认合法边界

加强字段检查后又发现：无效 requirement range 会在第一遍和 Host 比较阶段各报一次。
[单源错误 RED](range-cascade-red.log) 复现两条而非一条诊断。现把本次调用中已解析范围
保存在局部 map，Host 仅对有效 descriptor 和范围执行兼容比较，损坏字段由其来源检查负责。
不是长期缓存，无生命周期或失效策略；一次校验结束即可释放。

另外补齐 Workspace 的两个 128 字符合法上界正例。最终复查生成入口、三类 record、
Package/Host 区别、Owner grammar、typed error 和 Host 安装时机，未再确认本范围内的新问题。
未把未影响结果的 Host 合并或 helper 写法当作新优化。

## 最终验证

使用项目 FVM SDK（Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`）。

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1743 项通过摘要](framework-summary.log) |
| UI Generator/Workspace/Index | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/ui_fragment_generator_test.dart packages/ccrouter_test/generator_test/ui_fragment_workspace_test.dart packages/ccrouter_test/generator_test/ui_schema_index_review_test.dart --reporter expanded` | [115 项通过](generator-final.log) |
| Workspace 单独复核 | `fvm dart test packages/ccrouter_test/generator_test/ui_fragment_workspace_test.dart --reporter expanded` | [39 项通过](workspace-final.log)，包括新增 22 项 |
| 根目录分析 | `fvm dart analyze` | [通过](root-analyze.log) |
| Demo | Demo 目录 analyze、`fvm flutter test --no-pub` | [分析通过](demo-analyze.log)、[118 项通过摘要](demo-tests-summary.log) |
| 完整生成 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [生成物一致](demo-reference.log)：6 components、34 routes、11 Packages |
| 普通生成 | 同命令 `generate demo --check` | [fast path 命中且一致](demo-normal.log) |
| 格式 | 五个本轮 Dart 文件只读检查 | [无变更](format.log) |
| 文档/敏感信息/空白/源文件指纹 | 最终归档检查 | [archive-checks.log](archive-checks.log) |

框架与 Demo 测试仅归档末 12 条非空输出，完整原始日志保留于本机 `/tmp`；其余证据是
完整输出。机械规范化只处理 ANSI、换行、行尾空白与 home 路径，不改变结果。
先前未完成字段修复的测试尝试及夹具失败不算最终通过；115 项记录是在最终代码和夹具下重跑。

已同步根 README（中英文）、Generator/UI README 和 CHANGELOG、Contracts README、UI 设计
规范、integration Skill/reference、CLI Skill 与 descriptor DartDoc。本轮未修改 Plugin
生产代码，未重跑其全量；未运行整个 Generator 目录、浏览器/实体设备或独立发行安装。
Demo Plugin pin 保持原值，待后续获授权的远端实现提交和独立 bootstrap 同步。
