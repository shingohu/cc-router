# 同步重入与异步交接边界审查

日期：2026-10-23。工作树：`managed-navigation-runtime/cc-router`；分支
`codex/managed-navigation-runtime`，HEAD `09cb21d`。
本轮只增加审查复现、对照测试与报告，没有修改框架、Demo 或生成代码，没有提交或推送。

## 结论与问题分析

确认三类新问题，由七个确定性用例复现。它们没有被现有 897 项 Flutter/Demo
回归覆盖；现有测试全部通过不能作为这些生命周期边界已正确的证明。

### P1：取消后仍启动尚未执行的 Service 方法，并可能返回成功

位置：`packages/ccrouter_core/lib/src/runtime_host.dart:1427`，尤其是
`await _resolveReady(...)` 之后直接 `call(resolved, context)` 的交接点。

复现：注册没有异步 initializer 的 promoted Service，发起一次 `invokeService`，
在同一同步调用栈紧接着取消 caller token、关闭 Session，或 shutdown Runtime。
三种情况均实际进入业务方法，进入时 `context.cancellation.isCancelled == true`，
并且本例最终返回 `1`，没有返回取消错误。

根因：即使 Service 已可用，`_resolveReady` 的 Future 仍引入异步交接。
方法恢复后未再次检查取消/所有权。外层 `Future.any` 也不能保证取消胜出：
本例业务方法同步返回，work 先被观察为成功。生成 Proxy 的
`call: (service, _) => service.method(...)` 不替 Runtime 执行这项检查。

影响：例如发起写入后立即退出账号，尚未开始的写入仍可执行；Runtime shutdown
后也可启动尚未执行的业务方法。这不同于已经开始的 Dart 工作需要自行协作取消。
本轮没有声称这些测试证明了真实网络或数据库副作用；计数器证明的是业务方法进入。

建议：在 readiness 返回到实际方法调用的最后边界检查 invocation cancellation、
所属 Scope 与 Runtime 状态；保留共享 singleton readiness，不用取消一个 caller
的方式终止所有 caller 的初始化。补充无 initializer、已完成/共享 initializer、
caller/Session/Route/Runtime 终止及同步返回/异步返回的交叉回归。

### P1：Adapter 同步回调结束 Host/Runtime 后，Runtime 仍提交 Entry

位置：`packages/ccrouter_core/lib/src/navigation.dart:980` 至 Entry 提交处。

复现：自定义 Adapter 的同步 `navigate` 接受 Go 时，Host 回调注销当前辅助 Host，
或调用当前 Runtime 的 dispose，然后返回已接受的 Future。
两种情况下调用结束后 `activeRouteEntries` 均仍有一项。
shutdown 变体等待 shutdown Future 完成后，Entry 依然存在。

根因：`action()` 可以同步调用外部代码，返回后没有再次验证原 Host 注册生命周期
及 Runtime 存活状态，就执行 `_commitRouteEntry`。
detach/shutdown 已经清理了当时的活动 Entries；后提交的 Entry 错过这轮清理。
shutdown 是 memoized 的，再次 dispose 不会补做这次迟到提交的清理。

影响：Runtime 出现没有对应活 Backend 的逻辑 Entry；shutdown 后仍保留 Entry
及其 Scope/请求引用。属于已证实的生命周期清理缺口；本轮没有进行 heap GC 认证。
触发条件是 Host/自定义 Adapter 的同步回调重入，不等同于普通点击必然触发。

建议：把同步 Adapter 调用也当成外部交接边界，在提交前核对原 operation 的
Runtime/Host registration/request lifetime；失败时关闭尚未提交的 Scope，消费
Adapter Future 的晚到成功或错误。不能用所有 Push 结果返回时统一拒绝的方式修复，
已提交页面的普通 Pop/Host 关闭结果仍须遵守原契约。

### P2：动态 Host 注册重入可覆盖注册或误删替代注册，遗失资源所有权

位置：`packages/ccrouter/lib/src/multi_host.dart:249`。

两个独立用例：

- 外层 aux Adapter 在 initialize 中再次注册同 ID 的内层 Adapter；内层注册成功后
  被外层 `_hosts[hostId] = record` 覆盖。最终 aggregate.dispose 后，内层
  Adapter 的 dispose 次数仍为 0，证明 `not-disposed`。
- 绑定回调先 unregister 当前 aux，再 register replacement，随后抛错。
  外层 catch 无条件 `_hosts.remove(hostId)`，误删 replacement；最终注册集合只剩
  primary，aggregate.dispose 也未释放 replacement。

根因：调用子 Adapter 前未保留注册中的身份；提交、回滚没有核对自己仍然拥有
这个 Host 地址。这不是此前事件 operation ID 冲突的重复问题。

建议：为同 ID 注册保留独立事务/注册中身份，拒绝冲突重入；在初始化、绑定后的
提交/回滚处核对 record identity。失败只回滚自身所有权，不能移除新注册。
继续保证成功接管的 Adapter 清理恰好一次，正常解绑其他 Host 不受影响。

## 方案权衡与推荐顺序

| 方案 | 收益与代价 | 判断 |
| --- | --- | --- |
| 业务/Demo 每次手工检查 token、禁止快速操作 | 可局部减轻，但生成 Proxy 和其他 Host 仍暴露缺口 | 不作为框架修复 |
| 所有操作全局串行化或禁止全部同步回调 | 容易引入自等待，牺牲独立 Host 并发，改变现有契约 | 不推荐 |
| 在交接点核对原生命周期，注册按 identity 提交/回滚 | 可在私有实现内修复，不新增业务 API；需要验证迟到 Future 清理 | 推荐 |

推荐先处理 Service 方法入口，再处理导航提交，最后处理 Host 注册事务。
每项先把对应失败用例纳入常规回归，再实现最小修复，随后验证相邻正常路径。
涉及可观察取消或生命周期语义时，同步检查 README、集成 Skill 和相关 reference。
本轮是 review 请求，生产修复尚未实施。

## 审查范围及排除项

| 维度 | 本轮证据与结论 |
| --- | --- |
| Service caller/Session/Runtime 终止发生在方法开始之前 | 3 个有效失败，归入第一项 |
| Adapter 同步 dispatch 中 Host detach/Runtime shutdown | 2 个有效失败，归入第二项 |
| register initialize/bind 的同 ID 重入与异常回滚 | 2 个有效失败，归入第三项 |
| 旧账号 readiness 晚到错误，新 Session 重新解析调用 | 新增对照通过，旧资源释放一次，新账号不被污染 |
| Event → Command → Service 嵌套取消、Trace、晚到错误、后续重试 | 新增对照通过，取消传到 3 层，新调用可成功 |
| Pop/close、旧 Host/Context、Shell/Outlet、parent stack、revalidation、手势 | 审查现有契约与专项覆盖，执行现有全量回归，本轮未确认其他新缺陷 |
| InitTask DAG/Gate、消息隔离、Scope construction/readiness | 静态抽查与现有全量回归，不等于穷举所有调度 |

排除的疑点包括：revalidation reset 失败后仍 supersede 同 Host 的低优先级决策
是明确契约；单纯从私有 cancel 调用不能推断 policy 异常未隔离；重复 composition
root mount 已有前置拒绝，尚无有效同 Backend 被误 dispose 复现。
Memory Adapter 的 Pop 调用返回也不能直接当作 Route Scope 已取消：扩展探针进入
方法时 cancellation 尚未发生，不能据此报告“取消后启动”的 Route 变体。

没有新增 Demo 按钮：现有能力页面已演示 Service/Session/Command/Event/InitTask；
本轮主要缺口是精确调度窗口和自定义 SPI 故障注入，自动化 fixture 更能稳定复现。
修复后可把“发起调用立即取消/关闭账号”的对照加入能力页，但不能用顺序点击
或隐藏异常使当前实现看似通过。

## 验证与复现

Review fixtures 位于 `packages/ccrouter_test/test/review_repros/20261023/`。
文件刻意不以 `_test.dart` 结尾，只有显式命令才会执行，避免把尚未修复的缺陷
伪装成已通过回归或破坏原默认测试发现。修复时须移入正常发现的回归文件。

后续修复已将上述 fixtures 迁入常规发现的 `reentrant_lifecycle_regression_test.dart`
和 `cross_capability_cancellation_regression_test.dart`，见
[修复与回归报告](../20261023-reentrant-boundary-fixes/report.md)。本表保留审查时的命令与失败证据。

| 命令 | 本轮结果 |
| --- | --- |
| `fvm flutter test --no-pub packages/ccrouter_test/test/review_repros/20261023/repro.dart --reporter expanded` | 7 个有效预期失败，见 `baseline.log` |
| `fvm flutter test --no-pub packages/ccrouter_test/test/review_repros/20261023/controls.dart --reporter expanded` | 2 通过，见 `controls.log` |
| `fvm flutter test --no-pub packages/ccrouter_test/test demo/test demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded` | 897 通过，见 `flutter.log` |
| `fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test tool/test --reporter expanded` | 55 通过，见 `dart.log` |
| `fvm dart analyze` | No issues found，见 `analyze.log` |
| `fvm dart run tool/documentation_check.dart` | 121 个纳入检查的 Markdown 通过，见 `documentation.log` |
| Dart format、`git diff --check` | 通过 |

本轮未改声明、组件图、生成输出或接入行为，无需重新生成。
没有新增 macOS 真实窗口、Android/iOS 真机、长时 monkey、性能或内存基准结果；
现有 suite 中的 semantic monkey 与手势回归不替代上述认证。

## 为什么连续 review 仍有新问题

此前覆盖较偏向“开始 → 等待 → 取消”以及每步 settle 后的导航序列；本轮击中的是
“已开始解析但业务尚未进入”“外部同步回调刚返回”“注册尚未提交/回滚”的窗口。
不同子系统各自检查生命周期，检查点并不一致。持续增加正常按钮点击不能覆盖它们。

建议后续把回归组织为状态与交接点矩阵：每个异步恢复、每个外部同步回调返回、
每次 identity 提交/回滚，都交叉 caller cancel、Scope close、Host detach/re-register、
Runtime shutdown、抛错与晚到完成；验证不只看 Future，还核对业务是否进入、
逻辑/Backend Entry 一致性、Scope 清理和 disposer 次数。
对不应重入的 SPI 应明确拒绝并回归，不应静默覆盖；对可重入路径则核对原身份。
这一方法能系统扩大覆盖，但不能诚实地承诺后续 review 永远不会再发现问题。
