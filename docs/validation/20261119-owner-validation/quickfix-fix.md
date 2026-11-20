# Owner Quick Fix 两项修复（2026-11-19，本地）

后续的持续修复—review 循环及最新统一验证见 [循环收口记录](../20261119-declaration-loop/report.md)。

本轮修复 [独立 review](review.md) 的 P2 / P3 两项问题，继续保留当前分支此前修改。
生产改动仅涉及隔离 Analyzer Plugin；没有提交、推送、合并、创建 tag 或更新 Demo pin。

## 根因与选择

1. 原 self-consumption 保护只覆盖 UI，Service/Command 会建议添加自身 Owner，从而生成
   被 Generator 拒绝的依赖环。将保护统一到三种 family，并复用 `_containsOwner` 对
   组件身份进行取值核对，覆盖字面量、本地 const、可证明的导入 const 和 resolved 类型。
   不为此引入另一套常量求值逻辑；未知值仍按既有保守规则处理。
2. Owner 诊断已用 canonical constructor proof，Quick Fix 的 parser-only 分支却仍用旧
   语法匹配，导致隐式 `cc.CCComponent(...)` 有诊断却无修复。Quick Fix 改为始终复用
   `CCRouterResolvedSymbols.constructorArguments`，删除无其它调用方的旧私有解析器。

手写 prefix 特例会继续保留两套识别逻辑；复用现有 helper 同时保留来源证明、模糊导入
暂缓和 synthetic 右括号防护，改动更小。无新增公共 API、配置开关、依赖或缓存。
两个修改均局限于已有私有校验/编辑路径，可独立回退。

自身 Contract 应移除跨组件 Dependency：Service 使用内部 lookup，Command 使用
Owner Client，UI 组合内部 Widget。非法配置的最终生成校验仍由 Generator 负责。
已证明的自身 Owner 不会收到“补 Owner”的误导性诊断或修复，普通外部 Owner 的诊断与
修复保留；这不代表自身消费配置已成为受支持的生成输入。

## 先失败，再修复

- 原始五项对照回归中，无 prefix 和显式 const 两项通过；隐式 prefix 与 Service/Command
  自身 Owner 三项失败，见 [RED](quickfix-red.log)。
- 进一步检查导入 const 后补两项 parser-only 自身 Owner 回归，均因导入 Owner 未被保护
  而失败，见 [第二组 RED](quickfix-parser-self-red.log)。最终复用原有取值证明修复它。
- 最终 [七项专项通过](quickfix-green.log)。测试不仅检查修复存在性，也对 prefix 修复
  应用后的源码重跑诊断；自身 Owner 同时覆盖字面量、本地/导入常量，并保留外部 Owner 正例。

原始 review 临时用例也重新执行：[parser-only 三种写法](quickfix-parser-proof.log) 均为
一个诊断、一个修复；[Service/Command 自身 Owner](quickfix-self-proof.log) 均为零个
补依赖诊断和空修复列表。临时用例不计入仓库测试数量。

## 验证与复查

从隔离 Plugin 目录执行：

- `fvm dart test --reporter expanded`：[254 项全部通过](quickfix-plugin-full.log)，包括
  既有真实 LSP、watcher、Owner metadata 和 Quick Fix 协议回归。
- `fvm dart test test/ui_analysis_test.dart test/quick_fixes_test.dart --name 'self Owner|parser-only Component|parser-only .* cannot add' --reporter expanded`：七项专项通过。
- `fvm dart analyze`：[Plugin 分析通过](quickfix-plugin-analyze.log)。

根目录 `fvm dart analyze` 同样 [通过](quickfix-root-analyze.log)；本轮四个 Dart 文件
[format 检查无变更](quickfix-format.log)。文档、敏感信息、diff 和未跟踪文件空白检查见
[最终记录](quickfix-checks.log)。

复查了诊断与 Quick Fix 共用的 `findMissing`、身份证明调用方、Owner 常量可见性、
隐式/显式 const，以及正常外部依赖；没有保留仅供其中一条路径使用的构造器解析器。
没有新增资源 Owner、异步任务或持久状态，不改变 Runtime、Generator 或消息分发语义。

已同步中英文根 README、Plugin README/CHANGELOG、DartDoc、接入 Skill 与相关
implementation patterns / IDE 指南。review 中两项发现已完成本轮闭环。

本轮未重复 Flutter、Generator 或 Demo 全量；它们的上轮结果保留在实现报告，不能计为
本轮重新执行。未进行实体设备或发行安装认证。Demo bootstrap pin 未变，后续仍需在实现
提交推送后用远端完整 SHA 单独同步，并完成 pin-check、doctor 和真实 IDE 验证。
