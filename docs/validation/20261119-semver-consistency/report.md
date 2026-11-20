# 契约版本顺序与范围边界（2026-11-19，本地）

后续错误归因与 UI Host 格式错误边界修复，见
[兼容错误记录](../20261119-compatibility-errors/report.md)。本页保留版本比较阶段的历史证据。

继续既有授权的“审查 → 复现 → 修复 → 再审查”循环。此次聚焦契约版本比较、范围及
兼容错误语义；既有未提交修改保留，没有提交、推送、合并、打 tag 或同步 Demo pin。
前轮见 [参数语义记录](../20261119-argument-semantics/report.md)，最新文件指纹见
[source-manifest.json](source-manifest.json)。

## 两处已确认缺陷

1. `CCSemVer.compareTo` 用 `int.tryParse` 分类预发布标识，但 Dart int parser 同时接受符号
   和 radix-like 输入。`0x10` 与 `16`、`-0` 与 `0` 被判成同一版本，却保留不同字符串 hash；
   超出整数容量的纯数字标识还会退回字典序，导致长数字顺序错误。
2. caret/tilde 将某个 core 数字自增构造上界，在已接受的最大整数输入处溢出。例如
   `^9223372036854775807.0.0` 会拒绝自己的 minimum，minor/patch 上界有相同问题。

[原始复现](before-fix.log) 同时记录错误比较/equality/hash 和四类错误范围结果；新增
回归在旧实现中六项失败、一项普通边界通过，见 [RED](red.log)。随后加入普通范围对照网格，
最终新增八项测试纳入框架全量验证。

## 最小修复与取舍

只将 ASCII 十进制数字识别为 numeric prerelease；解析器已保证它没有前导零，故比较
位数后比较字典序即可保持数值顺序。相比拒绝已支持的长数字或增加 BigInt 转换，这种
方式保留字符串精度、无需依赖，也不会把合法非数字标签当作整数。build metadata 继续
不参与版本相等、顺序和 hash。

caret/tilde 改为比较 core 前缀与下一 stable core 的相对关系，不再构造自增版本。
相邻数字的差只在大小关系已证明后计算，非负 core 字段间不会发生减法溢出。
普通版本保留原有 `>=minimum <upper` 语义，包括 next-core prerelease 边界；未引入
Pub/npm 的额外预发布过滤策略。Core 字段仍为既有 Dart int，不扩展公共类型或版本语法。

修复位于共享 Pure Dart Contracts 实现，自动作用于 Generator、Host 和 Runtime 校验；
没有分别补三套逻辑、新公开 API、配置开关或可变缓存。范围 `.source` 的注释同时更正为
“原始 authored 文本”，实际保留字符串行为不变。

## 复查与回归

- 分类/值语义：覆盖纯数字、符号/十六进制样式标签、超长数字、数值与非数值优先级、
  双向顺序、相等、Set 和 build metadata 的 hash 不变性。
- 边界：四组最大整数范围均接受自身 minimum，保持合法后续版本，并拒绝超出 core
  前缀的版本。普通 caret/tilde 对照显式比较器，27 个 minimum × 2 类范围 × 192 个
  candidate，共 10,368 次对照全部通过。
- 实际门禁：`CCContractBundleDescriptor.validate` 现在正确区分 numeric/alphanumeric
  prerelease 的 exact 与 comparator 要求，确认影响实际兼容错误，而不只测试排序 helper。
- 检查所有共享解析器/范围调用方、私有构造器和异常处理。空范围表示 wildcard 是既有
  明文规范，未把它当作缺陷收紧。最终未再确认本轮版本校验范围内的新问题。

新增逻辑不拥有资源或生命周期，不涉及 Runtime 取消/销毁、Scope 选择、实例注册、
业务权限或数据记录。没有新增内存专项触发条件。

## 最终验证

使用项目 FVM SDK（Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`）。

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1730 项通过摘要](framework-summary.log)，包含新增八项和对照网格 |
| Generator 相关 | `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/contract_validation_test.dart packages/ccrouter_test/generator_test/workspace_validator_test.dart --reporter expanded` | [58 项通过](generator-tests.log) |
| 根目录分析 | `fvm dart analyze` | [无问题](root-analyze.log) |
| Demo | Demo 目录 analyze、`fvm flutter test --no-pub` | [分析通过](demo-analyze.log)、[118 项通过摘要](demo-tests-summary.log) |
| 完整生成 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [生成物一致](demo-reference.log) |
| 普通生成 | 同命令 `generate demo --check` | [同样一致](demo-normal.log)，不声称必然命中快速缓存 |
| 格式 | 两个本轮 Dart 文件只读检查 | [无变更](format.log) |
| 文档/敏感信息/空白/源文件指纹 | 最终归档检查 | [archive-checks.log](archive-checks.log) |

首个完整生成检查与注释格式化重叠，正确触发 [input-changed 保护](input-barrier.log)，
该轮输出被丢弃。冻结修改后重跑原命令通过；没有将失败轮计为成功或关闭输入屏障。
框架/Demo 测试仅归档末 12 条非空输出，完整原始日志保留在本机 `/tmp`；其余证据为
完整输出。机械规范化仅处理 ANSI、换行、行尾空白和 home 路径，不改变结果。

已同步 Contracts README/CHANGELOG、根 README（中英文）、兼容规范、integration Skill/
reference 和 CLI Skill。本轮没有修改 Plugin 生产实现，未重跑其全量；前轮 Plugin 验证
不能计为本轮。未运行整个 Generator 目录、浏览器/实体设备或独立发行安装认证。
Demo Plugin pin 仍待后续获授权的远端提交与独立 bootstrap 同步。
