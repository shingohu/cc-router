# Host Contract requirement 合并保留完整约束（2026-11-19，本地）

后续 CLI 上游保留 consumer snapshot 的修复，见
[Package 快照记录](../20261119-package-contract-snapshots/report.md)。本页保留 Host 合并阶段的历史证据。

继续用户此前授权的“审查 → 复现 → 修复 → review”循环。本轮聚焦 Host 合并快照，
前轮见 [Core 最终身份门禁](../20261119-core-identity-boundaries/report.md)。保留此前
未提交修改；未提交、推送、合并、打 tag 或更新 Demo pin。最新文件指纹见
[source-manifest.json](source-manifest.json)。

## 问题与复现

`_mergeContractBundles` 用 consumerPackage/kind/Contract ID/Owner 四项去重，没有
包括 range 和 fingerprint。一个消费者对同一 Contract 记录 `^1.0.0` 与 `<1.5.0`，
已安装 `1.1.0` 时两项都是合法约束；合并后却只留下第一项。反转顺序会改变保留下来的
range，因此合并快照丢失了原始约束。两种顺序都由 [失败回归](red.log) 确认 2 项变成 1 项。

原 Host 在合并前仍会校验全部原始输入，本问题不是同一次装配跳过初始兼容检查；影响的是
公开合并快照的完整性，以及后续读取或再校验时对原约束的准确表达。

## 最小修复

去重 key 加入 requirement 的 range 和 fingerprint，仅完整字段一致才合并。
保留不同文本范围，不在框架中自动计算/重写交集；实际约束仍由共享范围校验逐项执行。
完全重复项继续去重，既有 Package diamond、Contract descriptor、组件排序等算法不变。

新增三个回归：两个独立范围的正序、逆序，以及内容相同的两个独立 requirement 对象。
除了核对快照数量，还对 `1.1.0`、`1.8.0`、`0.9.0` 分别比较合并前后的兼容错误类别集合，
确认有效约束不丢失；完整重复项的诊断数量可去重，但兼容判定保持。

与其拒绝两个合法且当前都满足的范围，或引入范围交集表示，保留完整 requirement 值的
修复更小，也保持已有 range API。无新增业务 API、开关、依赖、缓存或生命周期资源。

## 两轮复查

第一轮追踪 `_resolve` 的预校验 → 合并 → Assembly 快照，以及 Runtime/Host 对 snapshot
的再校验路径，确认修复不将非法 requirement 延后、也不绕过已存在的门禁。
第二轮核对 requirement 所有字段、重复字段相等性、顺序、Package diamond 和合法版本
范围；同一 Contract 上不兼容的 fingerprint 仍会在合并前失败。最终未再确认本轮合并路径
中需要修复的新问题，不将无实际错误的统一写法升级为重构。

更新了框架包 README/CHANGELOG、Assembly DartDoc、根 README（中英文）、兼容规范、
Contracts README、integration Skill/reference 与 CLI Skill。引用图与 resource ownership
未改变，不创建或安装额外 Runtime 对象。

## 最终验证

使用项目 FVM SDK（Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`）。

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| Host bundle 专项 | `fvm flutter test --no-pub packages/ccrouter_test/test/generated_package_bundle_test.dart` | [14 项通过](bundle-tests.log)，含新增三项 |
| 框架全量 | `fvm flutter test --no-pub packages/ccrouter_test/test` | [1767 项通过摘要](framework-summary.log) |
| 根目录分析 | `fvm dart analyze` | [通过](root-analyze.log) |
| Demo | Demo 目录 analyze、`fvm flutter test --no-pub` | [分析通过](demo-analyze.log)、[118 项通过摘要](demo-tests-summary.log) |
| 完整生成 | `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [生成物一致](demo-reference.log)：6 components、34 routes、11 Packages |
| 普通生成 | 同命令 `generate demo --check` | [同样一致](demo-normal.log) |
| 格式 | 两个本轮 Dart 文件只读检查 | [无变更](format.log) |
| 文档/敏感信息/空白/源文件指纹 | 最终归档检查 | [archive-checks.log](archive-checks.log) |

初次临时探针使用 standalone Dart 导入 Flutter Host，因 `dart:ui` 不可用未执行；它不是
产品失败证据。真正的 RED/GREEN 使用仓库 Flutter 测试入口。框架与 Demo 日志仅归档末
12 条非空输出，完整原始日志保留于本机 `/tmp`；其余为完整输出。机械规范化仅处理 ANSI、
换行、行尾空白与 home 路径，不改变结果。

本轮未修改 Generator 或 Plugin 生产代码，未重跑两者全量；未进行浏览器/实体设备或独立
发行安装验证。Demo Plugin pin 仍保持旧值，后续需获授权的远端实现提交和独立 bootstrap
同步；上述本地验证不证明 Demo 已加载新 Plugin。
