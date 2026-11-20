# 0.4.0 Git snapshot 收口（2026-11-20）

按用户授权的顺序执行：累计 diff review、冻结验收、提交推送实现、独立同步 Demo Plugin
完整远端 SHA、pin-check/doctor/真实 IDE 验证、合并 main、创建 0.4.0 tag、清理已合并分支。
用户明确选择 tag `0.4.0`。Package 版本与 `publish_to: none` 保持现状；本次是 Git snapshot，
不表示 Hosted 发布、稳定 API 承诺或新的真机验收。

## 累计改动审查

基线 `acb9b04ba8968a7615afd9ea569cc0474829c58f`（原 `main` / `0.3.0`）。
审查包含 tracked diff 与新增源码/夹具，不只检查最后一轮：

- Contracts：Service Key 精确泛型相等/hash、SemVer prerelease/range 边界、输入身份与
  fingerprint 最终校验及错误归因。
- Host/UI：完整 requirement 去重与多消费者约束保留、UI descriptor/range 错误脱敏。
- Generator：重复声明拒绝、null/default 参数语义、nullable 缺席声明、消费快照发射与
  InitTask 补全、Catalog Library 身份与 URI 校验、preflight 命名空间和内部 API 边界。
- Plugin：当前声明身份、Owner cache/source/Library 失效、parser-only 保守证明、同名与
  typedef、Quick Fix 与诊断共享参数语义、原生/Package URI、Host/UI SPI 与最终 show/hide。
- 测试/文档：真实 Server/LSP 和 CLI 调用者、跨 Package/part 对照、根中英文及 Package
  README/CHANGELOG、双 Skill 和相关 references。

按现有 Host/业务/内部 API 分层核对调用者与导出，无新增业务公共 parser/helper。
来源证明只在当前调用内持有 borrowed SDK converter 和 cache，没有新增 Analysis graph、
timer 或 subscription。现有 source freshness fence 和 context 清理路径继续保留。
review 未确认新的必须修复的生产缺陷；发布前清理了多轮追加留下的重复空行，并补充根
0.4.0 Git snapshot 变更说明。没有把格式统一扩大为新抽象或额外功能。

历史失败复现与修复轨迹仍保留在各轮 validation 报告；它们说明历史检查范围，不替代本次
冻结验收。[上一轮 SPI 身份报告](../20261119-spi-library-proof/report.md)为最近的实现记录。

## 冻结验收

配套 Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`。隔离 Plugin 从其 Package 目录运行，
Generator 与 framework 从根目录运行；完整 Generator 运行过程中会暂时修改并还原 Demo。
最终 analyze 和 Host 生成检查在该套件结束后执行。SDK 版本缓存用官方
`flutter --version --machine` 初始化，根 Dart/CLI 显式设置配套 `FLUTTER_ROOT`。

| 验收 | 命令或范围 | 结果 |
| --- | --- | --- |
| Plugin | 隔离目录 `dart test --concurrency=1 --reporter expanded` | [358 项通过](plugin.log) |
| Generator 整目录 | 根目录 `dart test --concurrency=1 packages/ccrouter_test/generator_test --reporter expanded` | [主跑 818 通过、42 失败、1 默认跳过](generator.log)；42 项经下方整文件补验通过，共覆盖 860 个实际执行用例 |
| 环境补验 | `pub_hook_test.dart` 与 `route_find_command_test.dart` 整文件 | [38 项通过](pubhook-recovered.log)、[12 项通过](routefind-recovered.log)，[逐项名称核对 42/42](recovery-check.log) |
| 框架 | `flutter test --no-pub --enable-vmservice packages/ccrouter_test/test` | [1767 项通过摘要](framework-summary.log) |
| Demo | Demo 目录 `flutter test --no-pub` | [118 项通过摘要](demo-summary.log) |
| 仓库工具 | `dart test tool/test --reporter expanded` | [52 项通过](tools.log)，含隔离 Skill bundle |
| 应用 analytics | Dart analytics/Firebase 与 Flutter analytics | [41 项通过](analytics.log)、[18 项通过摘要](analytics-flutter-summary.log) |
| 独立 Example | Order Example 目录 `flutter test --no-pub test` | [一项通过摘要](example-tests-summary.log) |
| 分析 | 根、隔离 Plugin、Demo 各 `dart analyze` | [根](root-analyze.log)、[Plugin](plugin-analyze.log)、[Demo](demo-analyze.log)通过 |
| Host 生成门禁 | `generate demo --no-cache --check`、`generate demo --check`、`generate demo/modules/order/example --no-cache --check` | [Demo 参考](generation-demo.log)、[普通路径](generation-normal.log)、[独立 Example](generation-example.log)均一致 |
| 格式 | 全部 64 个变更 Dart 文件只读 format | 0 变更 |

Generator 的首次失败均出现在实际配套 Flutter SDK 版本缓存缺失后，Dart Pub 重新解析
Workspace 报 Flutter SDK 不可用。运行官方 `flutter --version --machine` 恢复元数据后，
受影响的两个整文件重新执行并通过。保留原始失败，不把首次运行重写成单次全绿；不把
这个已知外部环境问题冒充框架代码缺陷或已完成外部根因治理。

全部 source/docs 在冻结后保持一致。CLI 结束后 Demo tracked/untracked 状态为空，
pubspec/lockfile 未变。[source-manifest.json](source-manifest.json)记录第一阶段累计变更
的 SHA-256；[archive-checks.log](archive-checks.log)保存文档/敏感信息/空白/还原门禁。
证据只机械规范化 ANSI、换行、行尾空白、home 路径和原始 NUL，不改变断言结果。
Flutter 测试归档末 12 条非空输出，其他日志完整保留；原始日志留在本机 `/tmp`。

## 实现与 Demo pin 的两阶段提交

先验证和推送实现，再用 remotely resolvable full SHA 修改 Demo 的 inner bootstrap manifest
及 lockfile。该 pin 更新必须在独立提交中，不能指向编辑自身 ref 的提交；不使用 branch 或
floating tag，不升级隔离 analyzer/analyzer_plugin 版本。

此处的 `status`/`pin-check` 只证明静态与远端身份，`doctor` 另外证明临时 loader；真实 IDE
重启及诊断验证单独记录，不将 CLI 成功写成 IDE 已加载。

## 验收与发布状态

执行中；最终提交、pin、合并、tag 和分支状态由完成后的实际结果填入。

## 未覆盖范围

本次不运行 Windows 原生、浏览器或实体设备、Hosted 发布、完整历史凭据治理及设备内存
采样。该 Git tag 不解除 [Hosted 发布阻塞项](../../CCRouter-release-readiness.md)。
