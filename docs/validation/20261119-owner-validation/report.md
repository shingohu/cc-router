# 重复注解与 Owner 诊断收口（2026-11-19，本地）

后续独立三轮复查发现两个 Owner Quick Fix 待处理边界，见 [review.md](review.md)。
这两项随后已完成 [本地修复和验证](quickfix-fix.md)；下文保留本阶段的历史验证记录。

在 `codex/contract-identity-consistency` 的既有未提交修改上继续修复三项已确认问题。
前一阶段的实现与复查见 [Contract 身份验证](../20261119-contract-identity/report.md) 和
[前一阶段 review](../20261119-contract-identity/review.md)；它们的计数不替代本报告。
本轮没有提交、推送、合并、创建 tag 或更新 Demo Plugin pin。

## 问题、方案与实现

| 问题 | 根因与复现 | 修复位置及取舍 |
| --- | --- | --- |
| Route Contract / InitTask 重复注解静默取首 | 第二个 Route ID 消失；第二个任务的 Gate、failurePolicy 被忽略 | Route 放在 Contract 输出与 metadata 共用的 `_RouteModel.read`；InitTask 放在注册桥与 metadata 共用的 `_readInitTasks`，重复声明立即报错 |
| Service/Command Owner 诊断漏报或误报 | Dependency typedef 漏报；同名业务函数返回 Other 契约时仍按语法中的 Shared 报错 | 对 Component 与各 Dependency 统一使用现有 canonical constructor proof，解析后读取实际泛型类型，复用 UI 的既有路径 |
| 陈旧 Owner metadata 产生旧提示 | 当前注解移除、重复、换成同名业务注解或 Owner 变化后仍提示旧 Owner | 将 `resolveType` 的当前注解及 Owner 核对从 UI 扩展到 Service/Command；不匹配时暂缓诊断和依赖修复 |

不采用应用侧命名规避或手写依赖修复：它们不能消除生成歧义与错误的符号判断。
不新增 Core API、配置开关或独立校验框架；沿用现有私有入口和工具身份校验，
保留原有 Owner、ID、版本、签名、Gate 和失败策略校验。三项修改可分别回退。

合法单注解声明的生成 API 保持一致。Parser-only 检查现在也需要构造器来源证明；
未知或有歧义的导入暂缓到语义解析，避免仅凭 metadata 和同名符号猜测。
当前 Contract 注解与 metadata Owner 的比对用于 resolved 类型；完整生成仍是最终校验。

## 回归与复查

先用临时解析/生成用例复现三个问题，再新增四个生成入口的失败回归、两类 Contract 的
Owner 边界回归和两个真实 LSP 测试。生成重复声明的 [RED](duplicate-red.log) 与
[GREEN](duplicate-green.log) 均保留，四个入口分别执行。

测试夹具同步补齐了框架导入和有效 Contract 注解。缺少来源证明的 parser-only 正例改用
明确的导入边界；Demo 集成用真实解析后的内存 overlay，不修改 Demo 源文件。
新增同名函数夹具补齐 alias 参数，typedef 测试修正了源码替换目标；初次夹具问题不作为
生产错误证据。最终回归使用修正后的夹具。

三轮复查覆盖：

1. 追踪 Route 的独立 Contract、metadata 和页面绑定入口，以及 InitTask 的注册/metadata
   共用读取；确认唯一性校验不只作用于其中一个 Builder。
2. 核对构造器与 Contract 的声明身份、prefix/typedef、同名函数、源码注解及旧 metadata，
   以及 Parser-only 暂缓边界。解析后的类型用于 Owner 查找，错误语义不依赖写法。
3. 核对真实 LSP overlay、旧 watcher/Quick Fix、Demo 集成和指导文档。LSP 验证 Owner
   改变且 metadata 未更新时旧提示清除，恢复源码后提示重新出现。

本轮检查未发现已确认的遗留问题。生产修改不创建缓存、订阅、Timer 或 Runtime 资源；
测试创建的 AnalysisContextCollection 由测试清理。InitTask 修改只拒绝编译期歧义，
不改 Runtime Gate、取消、失败、并发或生命周期行为，也不记录业务数据。

## 最终验证

使用仓库 FVM SDK（Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`）。
Plugin 命令均从隔离 Package 目录运行，其余从仓库根或表中指定目录运行。

| 检查 | 命令或范围 | 结果 |
| --- | --- | --- |
| Plugin 全量 | 隔离目录 `fvm dart test --reporter expanded` | [247 项通过](plugin-final.log)，包含真实 LSP 与 watcher/Quick Fix |
| 生成重复注解与 InitTask | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/duplicate_declaration_test.dart packages/ccrouter_test/generator_test/init_task_generator_test.dart --reporter expanded` | [18 项通过](generator-init-task.log) |
| Route Contract 相关 | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/route_generator_test.dart --name 'contract\|Contract' --reporter expanded` | [16 项通过](generator-route.log) |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1722 项通过摘要](framework-summary.log) |
| 根目录 / Plugin 分析 | 各运行 `fvm dart analyze` | [根目录](root-analyze.log)、[Plugin](plugin-analyze.log)均无问题 |
| Demo | 在 Demo 运行 `fvm dart analyze`、`fvm flutter test --no-pub` | [分析通过](demo-analyze.log)、[118 项通过摘要](demo-tests-summary.log) |
| Demo 完整生成 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [通过](demo-check.log)：6 components、34 routes、11 Packages，生成物一致 |
| 格式 | 对全部 24 个改动 Dart 文件执行只读 format 检查 | [0 个格式变更](format.log) |
| 归档检查 | 文档链接、敏感信息、diff 与未跟踪文件空白 | [最终记录](archive-checks.log) |

框架与 Demo 测试只归档末 12 条非空日志，完整原始日志保留于本机 `/tmp`。
证据仅机械规范化 ANSI、换行、行尾空白和 home 路径；没有改写测试结果。
本轮未重跑整个 Generator 目录，也未进行实体设备或独立发行安装认证。

## 文档与发布边界

已同步中英文根 README、Contracts/Generator/Plugin README 和 CHANGELOG、Route/InitTask
DartDoc、integration Skill 及 implementation patterns / IDE references。
新增校验仍为内部实现，没有新增业务 Facade 或跨文件公共 helper。

Demo 的 Git bootstrap pin 保持原值。本轮本地 Plugin 测试通过不表示 Demo 已加载新实现；
仍需获得提交推送授权后，先使 Plugin 提交可从远端解析，再以完整 SHA 单独同步 bootstrap，
完成 pin-check、doctor、Analysis Server 重启与真实 IDE 验证。
