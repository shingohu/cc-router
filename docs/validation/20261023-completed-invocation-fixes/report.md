# 调用链所有权与同步交付修复

2026-10-23；工作树 `managed-navigation-runtime/cc-router`；分支
`codex/managed-navigation-runtime`，当前 HEAD 基线 `09cb21d`。
落实[上一轮审查](../20261023-completed-invocation-review/report.md)的两项缺陷。
保留工作树此前的所有修改，没有提交、推送、删除或回退。

## 问题、取舍与最终实现

| 问题 | 其它方案及限制 | 本轮实现 |
| --- | --- | --- |
| 已返回 Session 方法的遗留回调可进入新账号，包括嵌套 App 调用 | 业务逐处检查容易遗漏；完成后永久保留 listener 会累计保留链；完成即取消会误伤活跃 Scope 的正常工作 | 私有 Invocation frame 保存原调用链的具体生命周期信号，成功返回后仍验证原 Owner |
| 根级同步查找在 factory shutdown 后仍交付资源 | 单查目标 Scope 不能识别 Runtime 已进入 shutdown；抛弃返回对象又会破坏资源接管 | factory 前后统一检查 Runtime 终态，已构造 disposable 继续由原 Scope 清理 |

生产改动集中在 `ccrouter_core`：新增私有 `invocation_ownership.dart`，通过同库
`part` 共享私有状态，不增加业务 API、Host SPI、配置、依赖或导出。Facade 仅更新
DartDoc，外部调用签名保持不变。可按本报告列出的内部改动和测试范围独立审查、回退，
不增加继续运行旧缺陷的开关。

### 调用来源跨成功返回继续有效

- `_InvocationFrame` 分离公开 Trace context 与私有 ownership。
  ownership 只保存去重后的 cancellation tokens，不保存 Scope、Service、参数、
  返回值或父 context，也不加入 Trace/诊断历史。
- 普通同步/异步 Invocation 继承整条来源链，不只看最内层 Scope ID。
  因此 Session → App、Route → App 的回调也不能在原 Scope 关闭后重新进入有效目标。
- `_ensureInvocationCanEnter` 在实际入场检查原所有权；同步解析在 factory/cache
  前和实例交付后复用这条校验。Command/Event 使用同一个 Invocation 边界。
- 新的 pending 子调用临时订阅继承的具体信号，因此即使父方法早已返回，原 Scope
  随后关闭仍会结束该子调用。原方法及子调用 finally 继续移除所有 listener，
  不用永久监听维持来源关系。
- 仍活跃 Scope 的后台回调正常工作；独立 Runtime 的 frame 不相互混用。
  已持有对象和已进入的任意 Dart 业务代码仍需协作式取消，框架不强制终止它们。

### 保持共享初始化与实例所有权

- factory frame 使用实际选中的 instance Scope，不继承短命等待者的所有权。
- singleton initializer 同样使用自身 Scope 的 frame。App 初始化可在其 Session
  首等待者结束后继续，首等待者取消/超时不影响其它调用者。
- `newInstance` initializer 同时保留实际 instance Scope 与调用者来源链。
- 普通后台回调关闭后进入仍可用的目标，以 `CCInvocationCancelledError` 拒绝；
  注册缺失、无可用 Scope、无效参数等仍遵循原入口的先行校验规则。

### 同步资源交付与关闭

- `_ensureServiceResolutionCanEnter` 无条件检查 Runtime disposed，覆盖没有父
  Invocation、没有 construction owner 的根级查找。
- factory 已成功返回的资源先由 Scope 接管；之后因 Runtime 关闭拒绝交付时，
  仍保持原清理顺序、一次销毁、关闭等待及清理错误传播。
- Session factory 同步关闭自身 Scope 的原 `CCScopeClosedError` 语义保持；
  App factory 重入 Runtime shutdown 的同步交付现明确返回取消。

没有新增生产 Timer、Completer、共享缓存或诊断历史；祖先信号只在子调用执行期间
临时监听，并沿用 finally 释放。每个 frame 增加不可变 token 集合；其成本随不同
祖先信号数增长。本轮没有吞吐/延迟基准或进程内存采样，
不据此宣称零开销或整体性能提高。

## 默认回归新增 127 项

1. `completed_invocation_regression_test.dart`：将审查的 74 项探针加入默认 suite。
   原 26 项失败全部通过；保留未切换账号、initializer 独立生命周期及代理等正常对照。
2. `invocation_ownership_test.dart`：53 项扩展边界。
   - Session/Route × 直接/嵌套 App × 可空/Key × singleton/newInstance × 缓存状态，
     共 32 项；原 Owner 结束后零额外构造，独立调用正常、资源清理一次。
   - 返回方法的新 pending App 子调用，共 8 项；分别覆盖已进入方法和 readiness
     阶段，并保留 Scope 不关闭的正常对照。共享初始化继续，已关闭来源不进入方法。
   - Command/Event 在 Session/Route 结束后的零 handler 入场，共 4 项。
   - 保留旧 Zone 的 Session/Route Service GC 回归，共 2 项；Runtime 仍存活、Zone
     仍被持有时，已关闭 Service 可回收，旧 Zone 新解析拒绝，独立解析成功。
   - App factory/initializer 独立性 2 项，singleton/newInstance initializer
     来源差异 2 项，shutdown notification 失败保留与资源清理 2 项，跨 Runtime 1 项。

GC 用例使用 `WeakReference` 与 `forceGC`。它证明这些具体保留路径中的资源可回收，
不替代进程 heap、长时间 monkey 或真机内存验收。

旧 `managed_host_incarnation_regression_test.dart` 的 App factory 重入用例原本只
验证资源清理，默认允许成功交付；现在同时断言交付取消，并保留原 once-disposal
断言。没有移除、跳过测试或降低资源清理要求。

## 最终验证

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| 相关专项，含旧 Service/Scope 回归 | 197 通过 | [focused-final.log](focused-final.log) |
| 框架、Demo、导航/analytics Flutter、支付、存储、Order Example | 1292 通过 | [flutter-final.log](flutter-final.log) |
| analytics / Firebase / tool Dart suite | 55 通过 | [dart.log](dart.log) |
| Workspace analyze | No issues found | [analyze-final.log](analyze-final.log) |
| Demo generation freshness | 复用有效 watch cycle 94 的精确证据，up to date | [generation.log](generation.log) |
| 文档检查 | 检查器选取的 121 份 Markdown 通过 | [documentation.log](documentation.log) |

最终 Flutter 数量为上一轮默认 1156 + 本轮新增 127 + 额外组件/Example 9。
专项结果与完整结果有重叠，不能叠加为独立覆盖数量。
新增/修改 Dart 文件格式检查与 `git diff --check` 通过。
文档检查的选择范围不等于所有 untracked 审查报告。

```sh
fvm flutter test --no-pub packages/ccrouter_test/test demo/test \
  demo/modules/navigation_lab/test demo/modules/analytics_flutter/test \
  demo/modules/payment/test demo/modules/kv_storage/test \
  demo/modules/order/example/test --reporter expanded
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test \
  tool/test --reporter expanded
fvm dart analyze
fvm dart run ccrouter_generator:ccrouter generate demo --check
fvm dart run tool/documentation_check.dart
git diff --check
```

### 迭代中失败的说明

- `ownership.log` 为新测试夹具的 void 返回类型编译错误，未执行测试。
- `ownership-final.log` 中 Route 夹具错误地从 Runtime 根注册 Route Service，
  21 项被正确拒绝；已改为组件 Registrar 注册，`ownership-registered.log` 的
  当时 49 项全通过。随后再增加 4 项 Command/Event，均包含最终 197/1292 结果。
- 首次完整 `flutter.log` 为 1291 通过、1 失败，对应上述旧 App factory 交付期望。
  已补取消断言并保留清理要求，完整重跑后为 1292 通过。首轮不报告为通过。

## 指导同步与边界

已更新 README 中英文、集成 Skill、implementation-patterns、review-checklist，
以及 Service Facade/Core DartDoc，明确成功返回后的来源约束、共享初始化独立性、
pending 子调用取消及根级同步交付规则。

Demo 已有 Session、Service 及 defer/resume 入口。本轮修复的是确定性时序边界，
没有新增公开能力或重复 Demo 按钮，也未手工修改生成物或启动竞争生成器。

重复 review 的缺口来自此前用“当前 token 是否取消”代表整个来源生命周期。
本轮将所有权校验与临时监听清理分开，并把成功返回、嵌套调用、pending 子调用、
共享初始化与资源可回收性一起纳入默认回归。

未新增 macOS 实窗、Android/iOS 真机手势、长期稳定性或性能验收。
未修改独立 Analyzer Plugin 或 Generator 生产实现；未运行其隔离/完整专项套件。
