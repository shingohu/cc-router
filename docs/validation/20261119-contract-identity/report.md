# Contract 身份与 Dependency alias 一致性（2026-11-19，本地）

基线为 `acb9b04ba8968a7615afd9ea569cc0474829c58f`（tag `0.3.0`），
本轮在 `codex/contract-identity-consistency` 顺序处理三项已确认的问题。
当前仅完成本地实现与验证，未提交、推送、合并或创建 tag。

## 问题与方案取舍

| 问题 | 根因 | 采用的方案及兼容影响 |
| --- | --- | --- |
| Service Key 相等性不对称 | `other is CCServiceKey<T>` 接受协变子类型，但 hash 包含精确的 T | 在原比较中要求相同 runtimeType；同类型同名的值语义保留，跨泛型 Key 不再相等 |
| Service/Command 重复 Contract 注解被静默取首 | 本地扫描和导入读取使用 first-match 注解结果 | 在六个私有读取入口要求恰好一个对应注解；有歧义的声明直接生成失败 |
| Dependency alias 的 IDE 诊断缺失 | Core 单文件检查只遍历注解，UI 另有依赖扫描 | 新增私有 part 检查 Service/Command 依赖字面量，复用现有名称规则与构造器身份校验 |

应用层绕过不能修复 Key 的集合语义或 Generator 的歧义读取；新增 Core API、
开关或 alias 配置也没有必要。选择原值类型的最小修复、现有生成入口的校验和可选 IDE
工具补齐，不扩展业务 Facade。三项可分别回退对应改动。

实现顺序为失败回归、Key 修复、Contract 读取入口收口、alias 诊断、关联文档与验证。
重复注解覆盖本地声明、导入的 Command Handler/Service 实现，以及消费组件 Dependency
metadata，避免只修复声明端。

## 边界与复查

- `CCServiceToken` 按稳定 ID 判等有独立语义，不随 Key 改动。
- Key 不拥有实例，新增检查仅处理编译期模型或当前 AST；无新增缓存、订阅或生命周期资源。
  Runtime 的 Scope、销毁、取消、并发、fallback、业务权限和数据记录行为不变。
- Service/Command Dependency 使用 `ccrouter_alias_invalid`；UI 保留
  `ccrouter_ui_alias_invalid`，不将 Core 诊断纳入 UI code。
- IDE 只检查真实框架构造器、直接 list literal 及字符串字面量；支持 prefix 和 typedef。
  同名函数、外部同名 Component、计算型 alias、间接集合和 spread/条件集合保守暂缓。
  最终完整校验仍由 Generator 执行。
- 新增 Generator 跨文件公共 helper 在复查中移除，改为现有私有入口内校验；
  Plugin 新文件通过 `part of` 保持私有，不新增公共导出或依赖。
- 第二轮检查了所有 first-match 契约读取和业务 barrel、对称性/hash、生成错误入口、
  诊断定位以及真实编辑器 overlay 的出现/清除。当前没有已确认的遗留问题。
- alias 测试夹具曾漏填 Service Owner 和泛型上界，已修正。归档的 alias RED 使用
  合法 Dart 夹具并暂时禁用新增扫描，六项均因缺失目标诊断失败；最终代码恢复扫描。

## 验证

使用仓库 FVM SDK（Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`）。
下列命令从根目录运行，Plugin 两项除外，均以隔离 Package 为工作目录。

| 验证 | 命令或范围 | 结果与证据 |
| --- | --- | --- |
| Key RED/GREEN | `fvm flutter test --no-pub packages/ccrouter_test/test/service_key_test.dart` | [旧行为失败](key-red.log)，[修复后 2 项通过](key-green.log) |
| 重复注解 RED | Service/Command Generator 新回归 | [两项失败](duplicate-red.log)，证明原行为静默取首 |
| 最终重复注解回归 | 三个 Generator 文件，筛选 `Contracts reject duplicate declarations\|component metadata rejects duplicate` | [4 项通过](duplicate-final.log)，覆盖六个生产读取入口 |
| alias RED | Plugin `test/ui_analysis_test.dart --name 'dependency literal alias'` | [六项因诊断缺失失败](alias-red.log) |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1722 项通过摘要](framework-summary.log) |
| Generator 相关回归 | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/command_generator_test.dart packages/ccrouter_test/generator_test/service_generator_test.dart packages/ccrouter_test/generator_test/metadata_builder_test.dart --reporter expanded` | [57 项通过](generator-tests.log)；随后最终私有入口实现另跑上面的 4 项 |
| Plugin 全量 | 隔离目录 `fvm dart test --reporter expanded` | [229 项通过](plugin-tests.log) |
| 随后补充的 Plugin 边界与 LSP | 隔离目录 `fvm dart test test/source_analyzer_test.dart test/analysis_server_integration_test.dart --name 'parser-only dependency aliases\|real LSP reports and clears (Service\|Command) alias' --reporter expanded` | [3 项通过](alias-integration.log)，含两个真实 LSP overlay 修复 |
| 静态分析 | 根目录和隔离 Plugin 各运行 `fvm dart analyze` | [根目录](root-analyze.log)、[Plugin](plugin-analyze.log)均无问题 |
| Demo | `fvm dart analyze`；`fvm flutter test --no-pub` | [分析通过](demo-analyze.log)、[118 项通过摘要](demo-tests-summary.log) |
| Demo 完整生成路径 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [通过](demo-check.log)：6 components、34 routes、11 Packages，生成物一致 |

框架与 Demo 测试仅归档末 12 条非空日志，完整原始日志保留在本机 `/tmp`；其余证据为完整输出。
证据仅对 ANSI、换行、行尾空白和本机 home 路径做机械规范化，不改变测试结果。
本轮未重跑整个 Generator 目录，也未进行实体设备或独立发行安装认证。

## 文档与发布状态

根 README（中英文）、Contracts/Generator/Plugin README 和 CHANGELOG、Contract DartDoc、
integration Skill、implementation patterns 与 IDE 指南已同步。
文档链接、敏感信息与 diff 空白检查的最终记录见 [archive-checks.log](archive-checks.log)。

本轮未修改 Demo Plugin pin。新增诊断须在获得提交推送授权后，先发布 Plugin 实现提交，
再以远端可解析的完整 SHA 独立同步 Demo bootstrap 并完成 pin-check、doctor 和真实 IDE
验证。上述本地 Plugin/LSP 测试不代表 Demo 已加载本地新实现。
