# 导出命名空间证明与 URI 解码边界（2026-11-19，本地）

继续既有“审查 → 复现 → 修复 → review”循环，范围为 parser-only Owner 证据、URI
解码和诊断位置，不扩展为全仓或所有外部配置的审计。前轮见
[Contract Library 身份](../20261119-contract-library-identity/report.md)。保留此前未提交
修改；未提交、推送、合并、打 tag 或更新 Demo pin。最终文件指纹见
[source-manifest.json](source-manifest.json)。

## 第一轮：不能把未知命名空间当成没有声明

先复现 [四项失败](owner-fix-red.log)：命名 extension 遮蔽 Owner 常量时仍给出错误编辑；
条件导出被跳过后被当作来源唯一；Package query URI 被忽略后缀继续读文件；带 query 的
相对 URI 转 file path 直接抛 UnsupportedError。

修复沿用原 private proof 路径：

- 本地阴影集合统一覆盖 named compilation members 和命名 extension；构造器证明的
  相同遗漏也先经 [失败回归](constructor-red.log) 确认，再补齐。
- 导出证明区分 true/false/null。条件、缺失、不可解析或无法定位的分支是 unknown，不能
  计为“不存在”来证明另一个绑定唯一。隐藏目标符号的条件导出仍允许已证明的引用。
- URI query/fragment/authority 先拒绝；解码或 file path 转换失败返回 unavailable 证据，
  不提供无效编辑。正例仍覆盖普通/prefix/const Component、单独 Owner 及批量修复。

一个独立 semantic 回归证明了命名 extension 原源码本身没有 Dart 诊断，而把该名字填进
dependencies 会产生 Dart 错误，因此这不是只靠 metadata fixture 推断编辑无效。
旧 parser-only fixture 的 Pub roots 补齐真实 Core Package 根路径，让正例证明完整的
导入命名空间，而不再依赖“找不到某导入就假定它不声明目标符号”。

## 第二轮：URI 错误在多条入口重复出现

沿异常栈检查得到以下独立复现，而非假设所有 URI parser 都一样：

- [absolute URI](absolute-uri-red.log) 与 [catalog 对照](catalog-absolute-red.log)：
  非标准 `package:/...` 被当作便携身份。
- [编码错误](encoding-red.log)：非法 UTF-8 路径会在 metadata Owner 索引、Package 前缀
  收集和相对 file path 解码处抛 FormatException；`Uri.tryParse` 不等于后续解码安全。
- [源码/诊断桥 RED](uri-entry-red.log)：通用源码扫描和已发布诊断位置也存在同一解码异常。
- [预检 RED](preflight-red.log)：无效 import/export URI 在命名空间解析中提前抛异常，
  没有交回真实 Builder 的源错误。
- [namespace RED](namespace-red.log)：格式错误的 Package URI 仍给 parser 提供了错误
  Package namespace，甚至产生 Owner 诊断或跨 Package generated-import 诊断。
- [NUL RED](nul-red.log) 与 [catalog RED](catalog-nul-red.log)：编码 NUL 形成了无效 Owner
  事实或被发布为含 NUL 的 IDE path。

现在各入口在自己的字符串/文件边界拒绝不便携或无法解码的位置。IDE 缺证据就暂缓，
Generator 对显式非法 Library 身份仍按 FormatException 拒绝；CLI 的 AST preflight 只
跳过不可信命名空间，真实 Builder 仍负责报源错误，跳过不表示声明合法。
诊断桥限定已配置 Package 的 lib 路径，不将逃逸或非法位置交给 IDE。

没有为此增加跨文件 public parser API；同一库内复用已有 private URI 证明，独立功能入口
使用 SDK URI 与局部窄异常边界。CLI `_LibraryScope` 的 import/export 复用一项私有解析，
不新增 Analyzer session、磁盘扫描或网络请求。

## 第三轮：负例之外也检查合法路径

新增编码文件名正例发现：诊断桥把已解码的 `#` / 字面 `%FF` 再当作 URI 语法处理，导致
合法位置丢失，见 [失败回归](encoded-filename-red.log)。最终按 pathSegments 构造相对 URI，
由 SDK 编码一次，真实文件名不被解释为 query/fragment/编码数据。
[最终两项专项](bridge-final.log) 同时验证合法保留与非法拒绝。

复查真实引用可见性、命名 extension、hidden conditional 正例、缺失/语法不完整分支、
循环出口 visited fence、所有本轮异常栈涉及的解码入口、Bridge source path 与 namespace
映射，未再确认本轮范围中的新问题。resolved 模式继续使用 SDK 的实际元素身份，不受
parser-only 更保守策略的影响。没有增加 Runtime、Scope 或注册行为，也没有更改轮询、
cache entry 所有权或新增 subscription；失效证据只沿既有流程清除/暂缓。

更新根 README（中英文）、Generator/Plugin README 和 CHANGELOG、Contracts README、
integration/CLI Skill、implementation/IDE references 与相关 DartDoc。

## 最终验证

使用项目 FVM SDK（Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`）。Plugin 命令从隔离目录运行。

| 检查 | 命令或范围 | 结果 |
| --- | --- | --- |
| Plugin 全量 | 隔离目录 `fvm dart test --reporter expanded` | [298 项通过](plugin-final.log)，含新增 16 项及既有真实 Server/LSP 回归 |
| Generator 相关 | 根目录 `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/package_workspace_test.dart packages/ccrouter_test/generator_test/component_dependency_preflight_test.dart packages/ccrouter_test/generator_test/package_contract_requirement_test.dart --reporter expanded` | [38 项通过](generator-final.log)，包含真实 CLI preflight 正例及 import/export 负例 |
| Bridge 最终专项 | `fvm dart test test/generator_diagnostics_bridge_test.dart --name 'valid encoded filename\|malformed or escaping published' --reporter expanded` | [两项通过](bridge-final.log) |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1767 项通过摘要](framework-summary.log) |
| 分析 | 根目录与隔离 Plugin 各执行 `fvm dart analyze` | [根目录](root-analyze.log)、[Plugin](plugin-analyze.log)通过 |
| Demo | Demo 目录 analyze、`fvm flutter test --no-pub` | [分析通过](demo-analyze.log)、[118 项通过摘要](demo-tests-summary.log) |
| 完整生成 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [生成物一致](demo-reference.log)：6 components、34 routes、11 Packages |
| 普通生成 | 同命令 `generate demo --check` | [同样一致](demo-normal.log) |
| 格式 | 十五个本轮 Dart 文件只读检查 | [无变更](format.log) |
| 文档/敏感信息/空白/源文件指纹 | 最终归档检查 | [archive-checks.log](archive-checks.log) |

中间未补齐全部解码入口以及使用错误编码构造方式的测试尝试没有计为成功；298 项全量
记录是在最终实现下重新执行。框架/Demo 测试只归档末 12 条非空输出，完整原始日志保留于
本机 `/tmp`；其余为完整输出。机械规范化只处理 ANSI、换行、行尾空白、home 路径，并将
可能的原始 NUL 显示为转义文本，不改变断言结果或原始日志。

本轮未执行整个 Generator 目录、浏览器/实体设备或独立发行安装。Demo Plugin pin 保持旧值；
本地 Plugin 测试通过不证明 Demo 已加载新代码，仍待获授权的远端实现提交与独立 bootstrap
同步、pin-check、doctor、Server 重启和真实 IDE 验证。

后续排查与修复见[命名空间和 Catalog 循环复审](../20261119-namespace-catalog-loop/report.md)。
