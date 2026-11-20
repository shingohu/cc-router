# Contract 定义 Library 与源码定位收口（2026-11-19，本地）

后续导出证明、URI 解码及诊断定位边界修复，见
[导出/URI 记录](../20261119-export-uri-proof/report.md)。本页保留 Library 身份阶段的历史证据。

继续既有“排查 → 复现 → 修复 → review”循环，核对跨 Package 的声明身份和 IDE Owner
证据。前轮见 [Package 快照传递](../20261119-package-contract-snapshots/report.md)。
保留此前未提交修改；未提交、推送、合并、打 tag 或更新 Demo pin。最新文件指纹见
[source-manifest.json](source-manifest.json)。

## 第一轮：同名类型覆盖与 part 身份缺失

- Core Owner 暂存索引的 key 缺少 source/Library。同一 Package 两个不同 Library 中
  同名、同 Owner 的 Service/Command Contract 会被后一个覆盖；分别消费时一侧漏掉
  缺 Owner 诊断和修复。[两项失败回归](owner-collision-red.log) 已复现。
- Service/Command 的 part metadata 只有源码位置，缺少定义 Library；resolved 类型属于
  父 Library，Owner 索引却把 part 当作声明 Library。Builder [两项 RED](builder-red.log)
  证明 `libraryUri` 缺失；Plugin 的 [part/URI RED](part-uri-red.log) 同时复现合法 part
  身份无法证明，以及 query/fragment 源码 URI 被忽略后仍得到诊断。

修复保留原 `packageUri`、行列，仅在 Service/Command 来源是不同 part 文件时增加
`libraryUri`。正常由 Builder 产生的非 part source reference 不增加该字段。
索引 key 纳入 source 和定义 Library，Owner 解析按真实 Library URI 匹配类型，两个路径
都纳入既有文件身份失效检查。Core/UI 复用私有便携 Package URI reader，拒绝 query、
fragment、authority 与越界路径证据；不对明确无效 Library 回退猜测。

## 第二轮：catalog 与 UI 相邻路径

继续追踪 metadata → catalog → index，发现 `CCSourceReference` 序列化会丢掉未知的
`libraryUri`，只修 Builder/Plugin 无法闭环。增加内部 source reference 的可选字段，
JSON 往返保留它；源码定位仍是 part 及其真实行列。Source catalog 的
[两项 RED](catalog-red.log) 覆盖丢字段和明确 Library 冲突未被拒绝。

旧记录缺少 Library 字段可被来源位置一致的新记录补全，两个明确不同 Library 仍报
conflicting source facts。显式无效/跨 Package Library 不会被当作“字段缺失”。
普通旧记录输出格式保留，不新增业务 Facade 或导出路径；该字段不参与业务 shapeFingerprint。

UI 暂存索引也存在同类 key 缺 Library 的问题：两个 Library 通过同名 named library 共用
part，但各自声明不同 Contract ID 时仍会覆盖。合法 Dart fixture 的
[共享 part RED](ui-shared-part-red.log) 复现后，UI key 同样保留定义 Library。

## 第三轮：真实编辑器与兼容边界

Service/Command 的既有真实 LSP overlay 回归改为 part + 定义 Library 两文件场景：
修改 part 注解中的 Owner、恢复，再修改父 Library 中的 Owner 常量、恢复，消费者诊断
均按当前证据清除/重现。没有用单元测试推断真实 Server 会刷新。

复查 URI 到 Package lib 文件路径、Core/UI 同名和 shared-part key、catalog 往返/合并、
当前 annotation Owner 核对及源码定位，最后未再确认本轮路径中的新问题。
旧 part metadata 缺 defining-Library 证据时仍保守暂缓，必须重新生成；不靠 Package/类型名
推断它来自哪个 Library。CLI 是格式错误的最终门禁，IDE 对无效证据 fail-open 暂缓修复。

复用现有 catalog、Owner index 和文件身份缓存，不新增公共身份解析 API、配置开关、
Analyzer session 或长生命周期订阅。新增 helper 都是库私有；可选字段留在既有工具内部
metadata 模型。现有 cache entry/文件身份集合有原来的清理和替换路径，本轮没有新资源 Owner。
同步中英文根 README、Generator/Plugin README 和 CHANGELOG、Contracts README、兼容规范、
integration/CLI Skill 与 IDE/implementation references 和 DartDoc。

## 最终验证

使用项目 FVM SDK（Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`）。Plugin 命令从隔离目录运行。

| 检查 | 命令或范围 | 结果 |
| --- | --- | --- |
| Plugin 全量 | 隔离目录 `fvm dart test --reporter expanded` | [282 项通过](plugin-full.log)，包含七项新增索引边界与真实 part/Library LSP 刷新 |
| Generator 相关 | 根目录 `fvm dart test --concurrency=1`，目标为 core_contract_library_identity、package_workspace、service_generator、command_generator、contracts_layout 五个测试文件 | [74 项通过](generator-final.log) |
| catalog 最终复核 | `fvm dart test packages/ccrouter_test/generator_test/package_workspace_test.dart --name 'source references preserve\|source catalog enriches' --reporter expanded` | [两项通过](catalog-final.log)，验证最终实现的 legacy enrichment/显式冲突 |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1767 项通过摘要](framework-summary.log) |
| 分析 | 根目录、隔离 Plugin 各执行 `fvm dart analyze` | [根目录](root-analyze.log)、[Plugin](plugin-analyze.log)通过 |
| Demo | Demo 目录 analyze、`fvm flutter test --no-pub` | [分析通过](demo-analyze.log)、[118 项通过摘要](demo-tests-summary.log) |
| 完整生成 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [生成物一致](demo-reference.log)：6 components、34 routes、11 Packages |
| 普通生成 | 同命令 `generate demo --check` | [fast path 命中且一致](demo-normal.log) |
| 格式 | 八个本轮 Dart 文件只读检查 | [无变更](format.log) |
| 文档/敏感信息/空白/源文件指纹 | 最终归档检查 | [archive-checks.log](archive-checks.log) |

框架与 Demo 测试仅归档末 12 条非空输出，完整原始日志保留于本机 `/tmp`；其余为完整输出。
证据只机械规范化 ANSI、换行、行尾空白和 home 路径，不改变结果。
本轮未运行整个 Generator 目录、浏览器/实体设备或独立发行安装。Demo Plugin pin 保持旧值，
本地 LSP 测试通过不表示 Demo 已加载新 Plugin；后续仍须获授权的远端实现提交和独立
bootstrap 同步、pin-check、doctor、Server 重启与真实 IDE 验证。
