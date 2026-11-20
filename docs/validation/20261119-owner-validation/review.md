# 独立三轮 review（2026-11-19）

下面两项发现已在后续本地修复中闭环，见 [修复与验证](quickfix-fix.md)。下文保留复查当时的发现与建议。

范围：当前分支全部未提交改动及关联调用链。使用 ponytail-review 和仓库框架开发规范，
按普通组件声明规模、编辑器逐文件增量分析评估。本轮不修改生产或测试代码，不提交推送。
原 [实现验证报告](report.md) 保留其执行时结果；本次独立复查发现下面两个待处理边界。

## 应修复：自身 Owner 不能生成自依赖修复（P2）

位置：`packages/ccrouter_analyzer_plugin/lib/src/component_dependency_analyzer.dart:112`。
当前只有 UI 在 Owner 等于消费组件 ID 时跳过补依赖建议；Service/Command 继续进入
普通 missing-owner 路径。这是关联代码中既有的缺口，本轮统一 Owner 校验尚未覆盖它。

具体用例：组件 ID 为 `orders`，`Shared` Contract 的 Owner 也是 `orders`，在
`serviceDependencies` 或 `commandDependencies` 中填写它。使用真实 resolved unit 和
可见的 `orderOwner` 常量时，两种 family 都出现一个 missing-owner 诊断，并提供把
`orderOwner` 加入 `dependencies` 的修复。[复现输出](review-self-owner.log)。

这会生成非法组件自依赖：Generator 的 `_ComponentModel.read` 明确拒绝 dependency 等于
组件自身 ID；Service Proxy 和 Command dependency 读取也分别拒绝消费自己的 Contract。
业务应去掉该跨组件依赖，使用组件内部 Service lookup 或 Owner Command Client。

最小修复：把现有 UI 的 self-consumption 修复保护推广到三种 family，至少禁止提供添加
自身 Owner 的 Quick Fix；为 Service/Command 各补一个“不生成自依赖编辑”的回归。
不处理时，自动修复会把原有配置错误变成另一条必然生成失败的配置。

## 建议修复：parser-only prefix 的诊断与 Quick Fix 不一致（P3）

位置：`packages/ccrouter_analyzer_plugin/lib/src/quick_fixes.dart:168`。
Owner analyzer 已统一调用 `CCRouterResolvedSymbols.constructorArguments`，但 Quick Fix 在
未解析时仍调用旧 `_constructorArguments`，只接受没有 target 的 MethodInvocation。

同一份已证明 Owner 常量可见的 parser-only 源码中：

| Component 写法 | 缺 Owner 诊断 | Quick Fix |
| --- | --- | --- |
| `CCComponent(...)` | 1 | 1 |
| `cc.CCComponent(...)` | 1 | 0 |
| `const cc.CCComponent(...)` | 1 | 1 |

[复现输出](review-parser-fixes.log)。Plugin 的 `handleEditGetFixes` 在 resolved unit
不可用时仍走 parser-only 分析，因此这是实际 fallback 路径，而不只是无调用方的 helper。
最终生成结果不受影响，但同义写法会失去本应可用的修复。

最小修复：Quick Fix 也始终复用同一个构造器身份 helper，删除仅此处调用的旧私有
`_constructorArguments`。增加隐式/显式 const prefix 对照回归；保留模糊导入暂缓规则。
这项修复可同时删除重复的构造器识别代码。

## 三轮覆盖与验证

1. 生成和值语义：核对 Route Contract 输出/metadata/绑定，以及 Service、Command、InitTask
   的全部契约读取入口；核对 Key 的 Facade、Core 类型分组与按名称查找路径。
   新临时生成探针对四个 Route/InitTask Builder 分别验证单个 const 注解正常生成、
   重复同一个 const 注解失败：[8 个边界用例通过](review-const-annotations.log)。
2. Owner 与 Quick Fix：追踪 canonical constructor proof、resolved type、当前注解与旧
   metadata、Owner 常量可见性、协议 fallback；得到上面两项已复现问题。
3. 回归和文档：复跑新增 Owner/Parser-only 专项
   `fvm dart test test/ui_analysis_test.dart test/source_analyzer_test.dart --name 'owner detection|owner facts defer|parser-only Owner' --reporter expanded`，
   [13 项通过](review-owner-regression.log)。检查根 README、Skill、IDE 指南和 CHANGELOG
   与实现边界；对历史全量 247 项通过记录不追加“没有剩余问题”的推断。

根目录与隔离 Plugin 的 `fvm dart analyze` 均通过：
[根目录](review-root-analyze.log)、[Plugin](review-plugin-analyze.log)。
归档后的文档、敏感信息及空白检查见 [review-checks.log](review-checks.log)。

结论：建议先修复自身 Owner 的无效编辑，并补齐 prefix Quick Fix 一致性后再进入提交准备。
本轮没有重复整个 Generator、框架、Demo 或 Plugin 全量，也没有实体设备或发行安装认证。
前一轮的完整验证及 Demo pin 未同步边界仍见实现报告。临时探针不计入仓库测试用例数。
