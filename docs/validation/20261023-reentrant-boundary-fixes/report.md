# 同步重入与异步交接边界修复

日期：2026-10-23。分支 `codex/managed-navigation-runtime`，HEAD `09cb21d`。
修改位于现有 Managed worktree；保留此前未提交改动，没有提交或推送。

## 结果

已修复[上轮审查](../20261023-reentrant-boundary-review/report.md)的三类问题，
并修复相邻生命周期组合中确认的变体。现有业务 API 签名不变；没有新增业务控制接口。
新增 27 项常规发现的回归，最终 Flutter/Demo 共 924 项通过。

## 根因及方案取舍

共同根因是只在操作开始时校验生命周期：readiness 的异步交接、Adapter 同步返回、
旧 Scope 关闭，以及注册/解绑回调，都可能使原 Owner 在下一次提交前失效。
仅观察 Future 错误或等 UI settle 后验证，无法证明业务未启动及事务身份正确。

| 方案 | 取舍 | 选择 |
| --- | --- | --- |
| 业务或 Demo 每次手工检查，禁止快速操作 | 无法覆盖生成 Proxy、共享 Scope 和自定义 Host SPI | 不采用 |
| 全局串行或禁止所有外部回调 | 改变独立 Host 并发，可能自等待，接入成本高 | 不采用 |
| 在交接点检查原生命周期，事务按 identity 清理 | 私有实现兼容修复；需验证晚到 Future 和回调重入 | 已实施 |

正确性修复不增加允许旧错误行为的业务开关；各子系统保留独立正常路径和对照测试，
便于审查及按实现文件回退，避免引入长期双实现。

## 实施内容

### Service 方法入口

`runtime_host.dart` 新增私有 `_ensureInvocationCanEnter`，在通用 invocation 开始
和 async Service readiness 返回后调用，检查 invocation cancellation、所属 Scope、
Runtime 及 deadline。没有 initializer 或已 ready 的 Service 也经过最终入口检查。
尚未进入的方法在 caller cancel、Session close、shutdown 后不会执行。

共享 singleton 初始化仍只执行一次，取消一个 caller 不影响另一个；已经进入的
应用代码仍采用协作取消。没有修改同步 Service 调用的签名或生成 Proxy。
原 component 测试的“在途取消”增加明确的 method-start Completer，避免测试把
“尚未开始就取消”与“已执行方法后取消”混为一谈，也避免完成前一次的 Completer。

### 导航提交

`navigation.dart` 将原 request cancellation 传到 `_dispatchRequest`，在 Adapter
同步调用返回后检查原 Host/Runtime/request lifetime。提交过程中如需移除旧页面，
`route_entry.dart` 在旧 Scope 清理后、添加新 Entry 前再次检查生命周期。
提交失败时关闭新 Entry 的 Scope，并为已经返回的 Adapter Future 安装无状态的
晚到结果/错误消费回调；取消不等待 Backend 工作结束。

这项检查覆盖 Push/Replace/Go/Reset/Open，不把已提交 Push 的正常 Pop 结果当成
过期请求。Backend 仍负责自己的原子变更、回滚及不可中断的应用工作。

### Host 注册、回滚与解绑

`multi_host.dart` 的注册中记录持有尚未提交的 Adapter；同 ID 初始化重入和聚合
初始化中的递归 initialize/register 被拒绝。参数/生命周期校验后，新且未被持有的
Adapter 转移所有权，后续冲突、初始化或绑定失败均释放该次接管的资源。
重用现有或注册中/退役中 Adapter 被拒绝，但不销毁其当前 Owner。

绑定后检查 record identity；catch 只移除自身仍持有的记录，不能删除回调建立的
替代注册。绑定回调移除旧注册后才返回的 listener remover 仍会被回收；注册中
aggregate.dispose 同时接管所有 pending records，disposer 不会执行两次。
绑定完成前不能激活该 Host 或用它替换当前 active Host。

相邻失败回归还确认并修复了：

- 初始化前 `registerHost` 原先会先绑定一次，aggregate.initialize 又绑定一次。
  现在初始化前只接管，正式初始化时绑定一次。
- 原先先调用外部 unsubscribe，再发布旧 detach。unsubscribe 回调重建同 ID Host
  并导航后，迟到 detach 会清掉新 Entry。现在先清除旧索引并完成旧 detach 投递，
  再调用外部 unsubscribe/dispose。投递期间保留退役记录的所有权并拒绝同 ID 注册；
  投递结束后的清理回调可建立新实例，后续旧清理不再做 Host 级 mutation。

## 失败证据与常规回归

原 review-only fixtures 已迁入：

- `packages/ccrouter_test/test/reentrant_lifecycle_regression_test.dart`
- `packages/ccrouter_test/test/cross_capability_cancellation_regression_test.dart`

它们均为正常 `_test.dart`，没有 skip 或隐藏发现规则。新增共 27 项，包含原先的
7 个失败复现和 2 个对照，以及扩展的注册所有权、初始化、绑定/解绑重入、五类
导航晚到错误、旧 Scope 清理中 detach/shutdown、已 ready Service 共享取消等组合。

失败日志与修复顺序：

- `baseline.log`：正式发现路径下 2 个对照通过、原 7 个复现失败。
- `expanded-boundaries.log`：首轮修复后 20 通过，旧 Scope 清理中的两个提交变体失败。
- `preinitialization-baseline.log`：初始化前注册产生两个 listener 的有效失败。
- `unsubscribe-baseline.log`：解绑回调中新建导航被旧 detach 清掉的有效失败。
- `focused-first.log`：首轮同时暴露原 component 在途取消 fixture 的重复 Complete；
  已用明确 start gate 修正该测试时序，不将其归为生产缺陷。

## 最终验证

| 检查 | 结果 |
| --- | --- |
| Flutter 框架、Demo、navigation_lab、analytics_flutter 全量 | 924 通过，`flutter.log` |
| Pure Dart Demo analytics、Firebase adapter、tool 测试 | 55 通过，`dart.log` |
| `fvm dart analyze` | No issues found，`analyze.log` |
| Demo `generate --check` | up to date，复用 active watch cycle 50，`generation.log` |
| `tool/documentation_check.dart` | 121 个纳入检查的 Markdown 通过，`documentation.log` |
| 修改文件 Dart format、`git diff --check` | 通过 |

全量命令：

```text
fvm flutter test --no-pub packages/ccrouter_test/test demo/test demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test tool/test --reporter expanded
fvm dart analyze
fvm dart run ccrouter_generator:ccrouter generate demo --check
fvm dart run tool/documentation_check.dart
```

## 生命周期、性能及接入边界

注册中/退役中 map 仅持有当前同步事务的记录，结束后删除，aggregate.dispose 全部清空；
没有新的历史 Host 容器、Timer、全局队列或长期业务数据。disposer 和 listener 计数
验证恰好一次清理；晚到 Future 消费回调不捕获 Runtime、Entry 或业务 payload。
注册的所有权检查只发生在 Host 管理路径，不增加每帧遍历；方法入口和导航提交检查
为常数成本。本轮没有提供新的性能基准或 heap GC 认证。

README、集成 Skill、实现/审查 reference 及相关 DartDoc 已同步。没有修改生成代码，
没有新增 Demo 按钮：既有 Service/Session/Host 示例继续使用相同 API；精确回调调度
和 SPI 故障注入由上述常规回归稳定验证，避免把人工慢速点击当作竞态验证。

本轮未重新进行 macOS 真实窗口、Android/iOS 真机、长时间 monkey 或内存验收；
全量 suite 含现有 semantic monkey 和手势回归，不能替代真实平台认证。
