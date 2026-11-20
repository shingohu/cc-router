# 三轮复查（2026-11-19）

范围：`codex/contract-identity-consistency` 上全部未提交改动，包含两个新增 Dart 文件、
测试、公开 DartDoc、README、接入 Skill 和验证说明。本轮没有修改生产代码或测试代码，
没有提交、推送或更新 Demo Plugin pin。按普通组件声明规模和编辑器逐文件增量分析评估，
没有将本轮检查当作大型项目性能认证。

## 第一轮：值语义与生成调用链

沿 `CCServiceKey` 的 Facade、生成绑定、Core Provider 注册及查找追踪：Key 判等要求
精确类型和名称；Runtime 仍通过 Service 类型分组及 `key.name` 查找，不会因 Key 判等
修复改变实例选择。稳定 ID Token 有独立语义，没有被改成 Key 的比较方式。

核对全部 Service/Command `firstAnnotationOfExact` 和 `annotationsOfExact` 用法：
本地契约声明、导入 Handler/实现、Service Proxy 和组件 Dependency metadata 均经过
新增的唯一性校验。Raw Command 调用检查仅判断有无注解并拒绝绕过 Client，不读取
或选择契约身份，无须另加重复计数。SourceGen 按原注解逐项 yield，不会将重复的
同值注解去重。检查仍保留原 Owner、ID、泛型和命名验证。

结论：没有确认的正确性或入口遗漏问题。

## 第二轮：IDE 误报与 API 边界

检查新私有 part 的调用方、canonical constructor proof、命名规则和诊断定位；没有
新增业务 API、依赖、缓存或可释放资源。Generator 与隔离 Plugin 的有效名称规则一致。

通过临时探针复用现有 resolved fixture，对 Service/Command 各运行 11 个用例：
raw/triple/相邻字符串、插值字符串、有效名称、null、Component typedef、公开 barrel
加 prefix、变量集合、spread 和条件集合。合计 [22 个边界用例通过](review-alias-boundaries.log)，
核对 Dart 本身没有诊断、alias 诊断存在性以及完整字面量定位。
同名函数和外部同名 Component 由已纳入 Plugin 全量的回归覆盖。
临时探针最初因脚本引号及 barrel 夹具位置错误未执行完成，校正探针后才取得上述通过结果；
这些是探针构造问题，不作为生产代码问题或通过证据。

结论：在已验证边界内未发现误报、崩溃或诊断定位错误。

## 第三轮：类型边界、回归与文档

临时 Key 探针覆盖 Object、可空类型、dynamic、void、Never、Null、typedef、集合泛型和
函数类型，两种名称共 30 个值；全部 [900 组比较通过](review-key-boundaries.log)，
并核对相等值 hash 和 Set 身份数量。

复跑最终版本，而非合并不同阶段的计数：

- 隔离 Plugin `fvm dart test --reporter expanded`：[232 项通过](review-plugin-full.log)，
  包括三个 family 的真实 LSP alias 出现/清除及既有 watcher/Quick Fix 回归。
- 根目录 `fvm dart test --concurrency=1`，目标为 Command、Service、metadata 三个 Generator
  测试文件：[57 项通过](review-generator.log)。
- `fvm flutter test --no-pub packages/ccrouter_test/test/service_key_test.dart`：
  [2 项通过](review-key.log)。
- 根目录及隔离 Plugin 各执行 `fvm dart analyze`：
  [根目录](review-root-analyze.log)、[Plugin](review-plugin-analyze.log)均无问题。

检查公开参数、错误语义、诊断代码、保守暂缓规则及发布状态是否与 README、Skill、
references 和 CHANGELOG 一致；没有把本地 Plugin 通过描述成 Demo pin 已更新。
原有框架全量、Demo 测试和完整生成检查仍见 [实现验证报告](report.md)，本轮没有重复执行。
本轮归档后的文档、敏感信息和 diff 检查见 [review-checks.log](review-checks.log)。

结论：三轮均未发现确认需要修复的问题，可以进入提交前准备。
未重跑整个 Generator 目录、实体设备和独立发行安装认证；Demo Plugin pin 仍需在实现
提交远端后按既定两阶段流程单独同步。临时边界探针不增加仓库测试用例计数。
