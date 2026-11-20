# 声明与身份校验：修复—审查循环（2026-11-19，本地）

后续相同输入在 IDE/Generator 的默认值、可空声明与 SDK 类型边界修复，见
[参数语义循环记录](../20261119-argument-semantics/report.md)。本页保留该阶段历史证据。

按用户要求，在 `codex/contract-identity-consistency` 的既有未提交修改上持续执行
“修复 → review → 修复新发现 → 再 review”。范围为声明/契约身份、ID/Owner 取值、
IDE 诊断/Quick Fix 与 CLI 依赖预检；不是对全部 Runtime 或平台的无限审计。
本轮没有提交、推送、合并、创建 tag、修改 Demo bootstrap pin 或发送外部消息。
基线与最终文件指纹见 [source-manifest.json](source-manifest.json)。

## 第一轮：两个已确认问题

- `CCComponentId` 构造器 typedef 已被语义解析为框架类型，但取值最终仍按名称匹配，
  导致自身 Owner 被建议加入自身依赖。新增 [失败回归](id-alias-red.log)，改为 canonical
  constructor proof，再读取字面量/const 字符串引用；去掉 Component analyzer 的旧名称解析器。
- 带配置的实现注解仍可能静默取首。逐项遍历全部 `annotatedWith` 与相关读取入口后，
  在原有私有共享读取路径中补齐普通 Route、RouteImplementation、Service Provider、
  CommandHandler、EventSubscription、ComponentContribution 的唯一性校验。
  源码和 metadata 共用校验。新增 11 项最初失败，已有 4 项通过，见
  [声明 RED](declarations-red.log)；最终这 15 项均进入 Generator 最终通过记录。

UI Contract/Renderer、Route/Service/Command/Event Contract 与 InitTask 的既有唯一性
保护继续保留。每种声明角色只能在同一声明上出现一次，不把不同角色一概当作同一个注解。
合法单注解和独立声明的注册行为不变；重复的 ID、Scope、绑定和订阅配置不会按源码顺序选取。

## 第二轮：沿调用链修复新发现

1. 对未知消费组件 ID，原逻辑无法排除 self edge 仍建议补依赖。现在只有能证明消费组件
   与 Owner 不同时才继续补依赖检查。正常字面量、prefix/typedef 与可解析 const 字符串
   保留识别能力；计算型或不可证明的值暂缓，交由 Generator。Source fixture 中未定义的
   consumer ID 补为明确常量，避免测试依赖猜测。
2. Contract 的相邻字符串（如 `'hash' 'Code'`）原先漏过 IDE 规则。共享字面量 reader
   改用 `StringLiteral.stringValue`，验证拼接后的 ID/alias；插值/计算表达式保守暂缓。
   上面两项的 [失败回归](constant-red.log) 与最终全量结果均保留。
3. Parser-only exported Owner 常量原先按 `CCComponentId` 名称取值。已复现 prefix 常量
   没有修复、同名业务类型却得到修复，[两项 RED](owner-id-proof-red.log)。该 reader
   也改用已有身份 helper，明确框架来源；补齐相关 source fixture 的真实导入依据。
4. CLI preflight 会把业务同名 Component/Dependency/Contract/ID 当作框架声明，可能在
   Builder 前错误阻断生成。[四项 RED](preflight-red.log) 复现后，在既有 Library/import/
   export 索引中识别 canonical Core 声明；未知/条件命名空间继续暂缓，不新增 Analyzer
   session 或磁盘扫描。prefix 的缺失/已声明 Owner 两种正例同时覆盖。
5. CLI 不应把自身 Owner 错报成缺少依赖，见 [self RED](preflight-self-red.log)。现在将该
   无效消费交回 Builder 的声明错误，不建议制造自依赖；Generator 对 self edge 的拒绝保持。

选择复用现有 canonical proof、常量元素值和命名空间索引。单独增加写法特例会继续留下
多套匹配逻辑；放宽名称校验会造成误报。没有新增业务 API、配置开关或第三方依赖。

## 第三轮：复查与停止条件

复查全部注解扫描、共享读取者、跨文件导入、const 注解、消费组件自身/外部/未知 ID、
typedef/prefix、相邻字符串、同名业务类、Owner 常量可见性、预检到真实 Builder 的调用链，
以及生成错误与 SDK/analyzer 版本隔离。实际资源所有权与 Runtime 生命周期没有改动。
新辅助方法、namespace 表均留在既有内部实现中；无新增跨文件公开 helper 或持久状态。

最后一轮未再确认本范围内需要修复的遗留问题。停止本轮循环，不将缺少证据的写法差异
自动升级为新功能或重构。已同步根 README（中英文）、相关包 README/CHANGELOG、
DartDoc、integration Skill/references 和 CLI Skill；此前阶段的结果仍是历史结果。

## 最终验证

使用仓库 FVM SDK：Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`。

| 检查 | 命令或范围 | 结果 |
| --- | --- | --- |
| Plugin 全量 | 隔离目录 `fvm dart test --reporter expanded` | [257 项通过](plugin-final.log)，含真实 LSP、watcher、Quick Fix |
| Generator 六个相关文件 | 根目录 `fvm dart test --concurrency=1`，目标为 component_dependency_preflight、duplicate_declaration、command_generator、service_generator、event_generator、init_task_generator 六个测试文件 | [119 项通过](generator-final.log)，包含真实 CLI 无写入预检 |
| Route 相关 | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/route_generator_test.dart --name 'contract\|Contract\|binding\|contribution' --reporter expanded` | [26 项通过](route-final.log)，与上一行合计 145 项 |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1722 项通过摘要](framework-summary.log) |
| 根目录 / Plugin 分析 | 各目录 `fvm dart analyze` | [根目录](root-analyze.log)、[Plugin](plugin-analyze.log)通过 |
| Demo | 在 Demo 执行 analyze、`fvm flutter test --no-pub` | [分析通过](demo-analyze.log)、[118 项通过摘要](demo-tests-summary.log) |
| 完整参考路径 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [生成物一致](demo-reference-check.log)：6 components、34 routes、11 Packages |
| 允许缓存的普通路径 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --check` | [同样一致](demo-normal-check.log)；不以此声称命中了快速缓存 |
| 格式 | 对全部 31 个改动 Dart 文件只读检查 | [0 个格式变更](format.log) |
| 文档/敏感信息/空白 | 最终归档检查 | [archive-checks.log](archive-checks.log) |

框架和 Demo 测试仅归档末 12 条非空日志，完整原始输出保留在本机 `/tmp`。证据只机械
规范化 ANSI、换行、行尾空白与 home 路径。中间失败的夹具已补齐导入/消费组件身份；
不以修正夹具前的失败记录替代最后的全量通过。正常生成文件没有需要保留的差异。

本轮未重跑整个 Generator 目录、实体设备或独立 Git 安装认证。Demo pin 保持原值，
本地 Plugin 通过不证明 Demo 已加载新实现。后续只有获得提交推送授权，才能先发布实现
提交，再以远端可解析完整 SHA 单独同步 bootstrap 并执行 pin-check、doctor 和真实 IDE 验证。
