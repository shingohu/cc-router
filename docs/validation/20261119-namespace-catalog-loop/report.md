# 命名空间与 Catalog 边界循环复审（2026-11-19，本地）

承接[上一轮导出与 URI 证明](../20261119-export-uri-proof/report.md)，按用户授权继续
“排查 → 失败复现 → 最小修复 → 回归 → 再审查”。保留此前全部未提交修改，不执行提交、
推送、合并、tag 或 Demo Plugin pin 同步。

## 范围与取舍

审查 Owner Quick Fix、parser-only Contract 识别、Catalog 源码/实现/生成物 URI、UI 诊断
位置和 CLI generated 内部导入边界；不将格式统一扩展成新的业务 API 或通用解析层。

仅改测试/文档不能避免实际错误编辑与解码异常；新建公共 URI/命名空间抽象会扩大 API，且
各入口的失败语义不同。因此沿已有私有证明修复：同一库内复用符号导出证明，Catalog 内
复用私有 URI 校验；IDE 缺证据时暂缓，显式损坏的 Catalog 报 FormatException，源码 URI
错误继续交给 Builder。没有增加外部依赖、Runtime/Scope 行为、subscription 或长生命周期缓存。

## 第一轮：条件 import 和 part 不能证明符号不存在

[六项对照](owner-red.log) 中五项先失败：条件 import 的默认分支为空时，另一分支的同名
Owner 被漏算；同一问题也影响复用 prefix；导入或转导出的 `part` 声明、Consumer 自身的
`part` 声明也被漏算。隐藏目标符号的条件 import 正例保持可用。

修复在现有 Owner 引用路径中完成：相关条件 import 视为未知；parser-only 主库、导出库
含 `part` / `part of` 时暂缓，不对不完整命名空间生成编辑。resolved 路径仍使用 SDK 元素。

[语义反例](semantic-red.log) 进一步证明旧实现实际提供了 Quick Fix。最终测试验证原始源码
无 Dart ERROR，而加入错误 Owner 引用后出现 ERROR。条件分支的后半段显式选取 alternate
URI，避免依赖 Analyzer 的默认平台变量；这不是 Web/设备平台运行结果。

## 第二轮：统一各入口的 URI 读取边界

[Catalog 失败复现](catalog-red.log) 覆盖不完整 URI、authority、absolute path、query、
fragment、路径逃逸、编码分隔符、非法 UTF-8、NUL 和空路径段；源码与生成物不能只检查
`package:` 前缀。合法 `%23` / `%25` 源码/生成物保留原身份，旧 metadata 的原始文件名
通过 SDK pathSegments 编码一次，不把字面 `#` / `%FF` 当成 URI 语法。

[另外两条入口的失败复现](boundaries-red.log) 确认：UI 诊断会接受非法位置，CLI 内部
API 边界检查会在非法 UTF-8 解码时抛异常。分别补齐局部校验和窄异常边界；UI 不发布
不可信位置，源码错误保留给 Builder。新增 UI 合法编码位置对照。

复审发现 CLI 文本预筛选会漏掉编码后的 `ccrouter_generated` 目录名。预筛选现在保留含
`%` 的源码进入 AST/URI 判定；普通字符串、注释、同 Package 和生成胶水代码仍按已有规则
处理。真实 import/export 与 conditional URI 检查继续覆盖，不从文本猜测 import。

## 第三轮：Package 加同名类型不足以证明 Contract 身份

[四项对照](contract-red.log) 先复现本地类型遮蔽、hide 后由其他 Package 提供的类型、
条件导入及条件竞争分支的错误 Owner 诊断。导入提示按目标符号应用 show/hide，并暂缓
相关条件/deferred namespace；本地同名声明交给 semantic resolution。

[Library 对照](library-red.log) 再确认同 Package 的普通同名类型通过直接 import、prefix
或 re-export 都会被误认成已有 Contract。已有 `resolve` 的内部调用补充源码上下文，
带精确 Library metadata 的记录必须沿实际 import/export 匹配定义来源；复用并扩展现有
私有符号导出证明，没有公开新的解析 helper。缺失或不完整证据暂缓。

[最终五项对照](library-green.log) 保留普通及 prefixed 的正确 re-export，并拒绝三种
错误 Library。手工构造且不带 Library 的旧内部 index fixture 仍使用原有 Package 提示；
生产 cache 根据 metadata 的声明位置补齐精确 Library，真实 resolved 类型继续验证当前注解。

## 最后一轮复审

检查直接调用者、条件 import/export、show/hide、local/prefix 阴影、导出环的 visited fence、
part 的 parser/semantic 分工、metadata 与实际 Library 关系、所有本轮解码入口和正例保留。
未再确认本轮相关路径中新的可复现问题；这不代表全仓或所有平台不存在其它优化空间。

本轮五个生产 Dart 文件、六个测试文件，及根中英文 README、两个 Package README/
CHANGELOG、integration/CLI Skill 和 IDE reference 同步更新。没有手改生成物。

## 验证

使用项目 FVM 管理的 SDK：Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`。Plugin 命令在隔离
`packages/ccrouter_analyzer_plugin/` 下执行。源码指纹见
[source-manifest.json](source-manifest.json)：记录累计 80 个变更文件，并标明本轮 20 个文件。

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| Plugin 全量 | 隔离目录 `fvm dart test --reporter expanded` | [315 项通过](plugin-final.log)，比上轮新增 17 项，含真实 Server/LSP |
| Generator 整目录 | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test --reporter expanded` | [主跑 837 通过、19 失败、1 跳过](generator-full.log)；19 项全部对应下方环境恢复后的成功补验，[逐项核对](recovery-check.log)。共验证 856 个实际执行用例，不将首次运行表述为单次全绿 |
| Generator 定向 | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/package_workspace_test.dart packages/ccrouter_test/generator_test/ui_fragment_workspace_test.dart packages/ccrouter_test/generator_test/internal_api_boundary_validator_test.dart --reporter expanded` | [全部通过](generator-green.log)；后续新增合法编码位置对照由整目录覆盖 |
| Library 最终对照 | 隔离目录 `fvm dart test test/semantic_analysis_test.dart --name 'parsed Contract identity' --reporter expanded` | [五项通过](library-green.log) |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1767 项通过摘要](framework-summary.log) |
| Demo | Demo 目录 `fvm flutter test --no-pub`、`fvm dart analyze` | [118 项通过摘要](demo-tests-summary.log)、[分析通过](demo-analyze.log) |
| 分析 | 根目录和隔离 Plugin 各运行 `fvm dart analyze` | [根目录](root-analyze.log)、[Plugin](plugin-analyze.log)通过 |
| 环境恢复后的 watch 对照 | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/generation_watch_test.dart --name 'installed flutter build preflight reuses an active watch\|concurrent Flutter runs reuse one Host watch until the last lease exits' --reporter expanded` | [两项通过](build-wrapper-final.log) |
| Pub Hook 整文件 | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/pub_hook_test.dart --reporter expanded` | [38 项通过](pub-hook-final.log) |
| sealed UI 独立分发补验 | 配套 SDK 直接执行 `dart test --concurrency=1 packages/ccrouter_test/generator_test/portable_distribution_test.dart --name 'prebuilt sealed UI Package survives independent Git and archive consumption' --reporter expanded`，显式设置该 SDK 的 `FLUTTER_ROOT` | [一项通过](portable-final.log) |
| 最终完整生成 | 配套 SDK 直接执行 `dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check`，显式设置该 SDK 的 `FLUTTER_ROOT` | [输出一致](demo-final-reference.log)，6 components、34 routes、11 Packages |
| 最终普通生成 | 同一直接入口执行 `generate demo --check` | [输出一致](demo-final-normal.log) |
| 格式/文档/敏感信息/指纹/还原 | 最终归档检查 | [archive-checks.log](archive-checks.log) |

中间跨越源码编辑窗口的 Plugin 全量运行
曾让新 Analysis Server 子进程读到暂时不匹配的接口；该次运行作废，不计成功，以冻结源码后
重新执行的全量日志为准。Generator 整目录会暂时修改并恢复 Demo，因此最后生成门禁安排
在它结束之后，不用中途的 Demo 检查冒充最终还原证明。

Generator 整目录首次运行额外暴露了 SDK 环境前置条件：实际配套 Flutter SDK 缺少
`bin/cache/flutter.version.json` 等版本元数据，Dart Pub 重新解析 Workspace 时报告
`webview_flutter` 需要 Flutter SDK。临时 SDK fixture 的 launcher 已正确绑定实际配套 SDK，
无需修改 Hook 产品行为。标准命令 `fvm flutter --version --machine` 补齐元数据后，原先失败的
build preflight 和 shared lease 两项直接重跑通过；Pub Hook 整文件也单独复跑。
首次整目录结果与环境恢复后的日志分别保留，不把原始失败运行重写成全绿。
标准 SDK 版本输出见 [sdk-version.json](sdk-version.json)。
后续 sealed UI 独立分发测试再遇同类 Pub 错误，检查时实际 SDK 版本缓存再次缺失。用同一
SDK 的 `bin/flutter --version --machine` 补齐元数据，并由其
`bin/cache/dart-sdk/bin/dart` 直接启动补验后通过；未修改 FVM 配置、SDK 版本或 Hook 产品
逻辑，也不据此认定缓存缺失的外部原因已修复。
最后的普通生成也曾通过 FVM 入口再次遇到相同的 Pub 失败，见
[独立失败记录](demo-normal-fvm-error.log)。最终补齐 SDK 元数据后，使用同一配套 SDK
直接入口连续完成 `--no-cache --check` 和普通 `--check`，两个 exit code 均为 0。
完整生成后版本缓存仍存在；不把入口的可用规避方式表述为外部问题的根因修复。
整目录结束后，核对本轮之前的全部源文件与冻结指纹，除 20 个预期改动外无新增差异；
Demo 的 Git 状态为空，pubspec/lockfile 没有改动。最后的两种生成检查在测试全部结束后执行。

日志仅机械规范化 ANSI、换行、行尾空白、home 路径及可能的原始 NUL，不修改断言结果。
框架/Demo 测试归档末 12 条非空输出，其余保存完整输出；原始日志保留于本机 `/tmp`。

## 限制

未执行浏览器、实体设备或需显式 opt-in 的真实远程 Analyzer 安装 smoke test。
本地独立 Git/归档 Package 消费由分发测试覆盖。Demo bootstrap pin 保持旧远端 SHA；本地 Plugin
回归和真实测试 Server 不证明 Demo 当前 IDE 已加载新版。仍需另行授权的远端实现提交及
独立 pin 同步、pin-check、doctor、重启 Server 和真实 Demo IDE 验证。

后续排查见[源码 URI 与 generated API 边界复审](../20261119-source-uri-boundary/report.md)。
