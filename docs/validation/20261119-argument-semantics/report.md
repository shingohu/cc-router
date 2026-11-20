# 参数有效值与声明来源：继续修复—审查循环（2026-11-19）

后续契约版本顺序与范围边界审查见 [版本校验记录](../20261119-semver-consistency/report.md)。
本页保留参数语义阶段的验证证据。

继续用户此前授权的循环，在既有未提交修改上审查 IDE、Quick Fix、源码生成与 metadata
对相同声明的语义。前一轮见 [声明校验收口](../20261119-declaration-loop/report.md)。
本轮没有提交、推送、合并、打 tag 或改 Demo pin。最终源文件指纹见
[source-manifest.json](source-manifest.json)。

## 第一轮：合法默认值被误报

Generator 已接受 Route 的 `pattern: null`、`patterns: []` 和可解析 null 常量，IDE 却仅因
两个参数出现在源码里就报冲突，并提供删除修复。InitTask 的 `contract`/`id` 也将
可空引用直接当作有值，导致真实 null 常量误报及无效删除建议。

先加入共享 fixture，记录 [IDE RED](plugin-red.log) 与 [Generator RED](generator-red.log)。
最终 fixture 位于 `packages/ccrouter_test/fixtures/annotation_argument_cases.json`，共
14 组 Route、Route Contract 和 InitTask 输入，同时核对 Generator 源码/metadata、
IDE resolved/parser-only 诊断、Quick Fix 数量以及应用修复后的诊断。

修复后只按实际生效值判断：

- Route：非空 `pattern` 和非空 `patterns` 同时存在才冲突，null/空列表是 inactive 默认值。
- InitTask：恰好一个非空身份；显式/可解析 null 不算身份。两项都没有值仍报错，但无删除
  修复；未解析且无法证明可空引用的值时暂缓诊断与编辑。
- Quick Fix 实现移为 `source_analyzer.dart` 的私有 part，与诊断共用同一规则。
  原 `quick_fixes.dart` 通过显式导出保留两个原有类的导入入口；无新增公开规则 API。

相较于只在 IDE 放宽判断或复制第二套规则，共用私有实现能让修复和诊断同时遵循相同
语义。调用方显式选择原有类型，内部 API 隔离保持；没有新增配置开关或依赖。

## 第二轮：空声明与生成入口差异

共享回归还揭示了两个实际问题：

1. 值为 null 的可空 InitTask Contract 常量被扫描成任务身份。相同缺口也存在于 Component
   metadata 和 Service Proxy，见 [nullable RED](nullable-red.log)。现在这些 const null
   值表示没有声明；非 null 实例及非法/非 const 声明继续走原校验。
2. InitTask metadata 原有 top-level const 引用语法校验，但源码 Generator 未调用它。
   源码路径现在也执行同一检查。`contract: null` 作为省略可用，非空 Contract/dependsOn
   仍须常量引用，内联构造继续拒绝；相关回归包含于最终 Generator 记录。

Nullable Service Proxy fixture 补为明确的公共 contracts import，避免把违反公开导入规则的
夹具失败误算成产品问题。补齐后严格重新执行验证。

## 第三轮：标准类型的同名误判

已用合法 Dart 复现业务 `Duration.zero` 实际是一秒 SDK Duration，却被按名字判成零超时，
见 [Duration RED](duration-red.log)。现在 timeout 字面量/zero 先证明 SDK Duration 声明
来源；支持解析后的 prefix/typedef，业务同名 class/extension/holder 与模糊导入暂缓判断。
没有依赖 SDK 私有字段来做 IDE 求值，也没有执行业务代码。

相邻 Gate 构造器 reader 同样改用已有框架身份证明，修复 resolved typedef 的漏检，见
[Gate RED](gate-red.log)。普通 SDK 零值、负值校验与 Generator 正时长判断保留。
最后复查当前参数读取入口、空值边界、原有引用限制、namespace 与 Quick Fix 稳定入口，
未再确认本轮范围内的遗留问题；未把审查扩大为全 Runtime、平台或数值算法审计。

## 最终证据

使用仓库 FVM SDK（Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`）。Plugin 在隔离目录运行。

| 检查 | 命令或范围 | 结果 |
| --- | --- | --- |
| Generator 最终相关回归 | 根目录 `fvm dart test --concurrency=1`，目标为 annotation_argument_consistency、nullable_declaration、init_task_generator、service_generator、metadata_builder 五个测试文件 | [91 项通过](generator-final.log) |
| Plugin 全量 | 隔离目录 `fvm dart test --reporter expanded` | [275 项通过](plugin-full.log)，含真实 Analysis Server / LSP |
| 后续 namespace 边界复查 | 隔离目录 `fvm dart test test/ui_analysis_test.dart test/source_analyzer_test.dart --reporter expanded` | [161 项通过](plugin-postreview.log)，包括业务同名 extension 的 parser-only 保护 |
| 共享矩阵 IDE 专项 | `test/ui_analysis_test.dart --name 'IDE argument semantics'` | [14 项通过](matrix-ide.log)，修复后再次解析，无新增 Dart 错误 |
| Nullable LSP overlay | `test/analysis_server_integration_test.dart --name 'nullable InitTask identity'` | [通过](live-lsp.log)：null → 有值产生冲突 → null 清除 |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1722 项通过摘要](framework-summary.log) |
| 分析 | 根目录、Plugin 各执行 `fvm dart analyze` | [根目录](root-analyze.log)、[Plugin](plugin-analyze.log)通过 |
| Demo | Demo 目录 analyze、`fvm flutter test --no-pub` | [分析通过](demo-analyze.log)、[118 项通过摘要](demo-tests-summary.log) |
| 完整生成 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [生成物一致](demo-reference.log) |
| 普通生成 | 同命令 `generate demo --check` | [同样一致](demo-normal.log)，不声称必然命中快速缓存 |
| 格式 | 全部 38 个改动 Dart 文件只读检查 | [0 个变更](format.log) |
| 文档/敏感信息/空白/指纹 | 最终归档检查 | [archive-checks.log](archive-checks.log) |

验证过程保留环境边界：初次重型测试冷启动触及默认 30 秒而未执行到业务断言，新测试
设置两分钟上限后 [该例单独复跑通过](cold-retry.log)，随后五文件完整 91 项通过。
另一次 Dart test 自动 Pub 解析遇 Flutter SDK 入口问题，未执行测试；使用
`CCROUTER_PUB_HOOK_DISABLE=1 fvm flutter pub get` 正确恢复依赖解析，
[摘要](pub-resolution-summary.log) 保留，依赖约束及 lockfile 无差异，再重跑原测试命令。
没有把这两类环境结果当作产品断言失败，也没有放宽产品校验。

框架和 Demo 测试只归档末 12 条非空日志；完整原始输出保留于本机 `/tmp`。证据仅机械
规范化 ANSI、换行、行尾空白和 home 路径。本轮未重跑整个 Generator 目录、实体设备或
独立发行安装。DartDoc、根 README、包 README/CHANGELOG、integration/CLI Skill 与相关
references 已同步。

修改不增加持久状态、缓存、订阅或资源 Owner，不改变 Runtime Gate/取消/销毁语义。
Demo bootstrap pin 仍保持旧值；后续需在提交推送授权后用远端完整 SHA 分阶段同步，
并执行 pin-check、doctor、Analysis Server 重启与真实 IDE 验证。
