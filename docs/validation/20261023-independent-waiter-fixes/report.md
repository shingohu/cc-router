# 独立等待者、Host Entry 身份与预测返回转发修复

2026-10-23 开始，2026-10-24 验证；分支 `codex/managed-navigation-runtime`，工作树
`/Users/shingo/.codex/worktrees/managed-navigation-runtime/cc-router`。
基于 HEAD `09cb21d78381bbdeab431cf6bca279f909827db1` 及此前未提交成果。

已修复[上一轮审查](../20261023-independent-waiter-review/report.md)的三个缺陷：
跨 Host 本地 Entry ID 碰撞、独立 readiness waiter 结束后保留其 Zone、MultiHost
预测返回 observer 异常截断转发。未修改业务导航 API、未引入依赖或开关，未提交/推送，
未修改用户主工作树或清理此前成果。

## 根因与方案取舍

| 问题 | 未采用方案 | 本轮实施 |
| --- | --- | --- |
| 子 Adapter 本地 ID 被当成聚合全局 ID | 仅要求 child 自行协调全局唯一 ID；仅核对 Host 而保留被覆盖的 ledger | 聚合边界按 registration 编码 Entry identity，Core 对已知 Host/Outlet 再作防御校验 |
| 独立调用者取消后，内部 Future listener 仍保留 caller Zone | 取消共享 initializer；再包一层 Future.any；清空调用链 lineage | 可注销的 per-waiter relay，取消时从共享 producer 的等待集合中移除 |
| 一个 observer 抛错中断整个 aggregate callback | 依赖 child source 吞 aggregate 异常 | MultiHost 内逐 observer 隔离，与 native coordinator/backend events 一致 |

保留现有 Core ledger 结构和业务入口，在最窄的内部边界修复，不新增另一套导航实现。
每项改动可独立审查、回退；无需给业务添加错误行为切换开关。

## 实现与所有权

### MultiHost Entry identity

`multi_host_identity.dart` 是 `multi_host.dart` 的私有 part，集中转换：

- backend events 的 Entry ID 和 previous ID；operation 去重仍按原 registration 规则。
- initial snapshots。
- active/scoped Pop target 与 child 回调进入 Runtime 的 Guard target。
- 普通、maybePop、scoped Pop 回执。
- predictive phase 内的 Pop outcome；保留 phase、progress、timestamp、trigger 和 owner。

转换以 registration 为身份域，无历史 ID 映射表；同名 Host 重开得到不同身份域。
null/空 ID 不被补成有效身份，navigationId 和结果 Future 保持原样。
事件、快照、target 和 outcome 的 Host 使用聚合器已注册的归属。

异步 Pop 在 dispatch 时只捕获 Host、Outlet 和 namespace 字符串，不为编码而让挂起的
child Future 捕获整个 registration/Adapter。旧回执在同名 Host replacement 后仍使用
旧域。active target 查询也在进入 child getter 前固定 Host，防止同步重入切换焦点后
混合旧 Entry 与新 Host。

Core `_applyManagedPopOutcome` 在已知 ledger owner/Host/Outlet 不匹配时，记录
desynchronized Host 并保留 Scope，不按位置猜测移除。此防御不能替代聚合身份转换：
只有转换才能同时保存两个 child 的独立 ledger 和正确清理原页面。
Pop 发起时还捕获 Runtime 已有的 managed Host registration token，退役/关闭后不再
应用其回执。否则 namespace 虽然避免误删，新 Host 仍可能被旧回执错误标记失同步。
这个 fence 不依赖 removed-entry 诊断历史是否保留，也不改写回执的原返回信息。

### Shared readiness 独立订阅

`_SharedResult.wait(cancellation: ...)` 为可取消消费者建立独立的数据 relay，不在共享
Future 上注册该 caller Zone 的 listener。调用者取消、超时或原 Scope 结束时，同步
移除 relay，再在调用者自己的 error Zone 中恢复取消结果。共享 producer、其他活跃
消费者和后加入的消费者均保留原初始化和结果。

Service readiness 的 root 与 initializer dependency 等待都使用该路径。依赖边继续在
取消时同步解除，并在 finally 幂等清理，保留跨独立根的循环检测。producer 的实际
owner 结束仍按上一轮规则终结 readiness；没有清空 lineage 或削弱已结束调用的准入。

共享成功/失败先释放等待集合，再发布数据。失败对象及原始 stack 跨 error Zone 保留，
不向无消费者的共享 Future 发布 error；晚到错误仍有生产者侧消费者。无取消参数的
InitTask/singleFlight 等既有内部等待保持原有使用方式。

### Predictive observer

MultiHost 先将 phase 的 outcome 转换到聚合身份域，再逐 observer try/catch。一个 Host
observer 抛错不能隐藏 Runtime 的 committed 通知。原 registration 退役 fence、child
订阅解绑和 dispose 顺序保持有效；重复 committed 不会重复移除或标记正常页面失同步。

## 默认回归覆盖

新增 `packages/ccrouter_test/test/independent_waiter_host_identity_regression_test.dart`，
共 **51 项**，纳入默认框架 suite：

| 场景 | 数量 | 关键断言 |
| --- | --- | --- |
| 原三份 review 探针 | 26 | 原四个失败转绿；保留完成/无冲突/无异常以及 16 个导航 GC 对照 |
| cancel/timeout × 相同/独立 error Zone × 迟到成功/失败 | 8 | GC 在共享任务完成之前成立；其他 live/late caller 得到原对象与 stack，初始化只执行一次，无 uncaught error |
| Session/Route 原调用者结束 × 迟到成功/失败 | 4 | Runtime/App 初始化继续存活；调用者 Zone 和旧 Route payload GC；一次清理，新 Session 正常 |
| 全部身份 SPI 一致性 | 1 | 两 child 原始 ID 相同，聚合域不同；snapshot/event/previous/target/Guard/四种 Pop/predictive outcome 一致 |
| child target getter 同步切换焦点 | 3 | target/pop/maybePop 保留 dispatch Host 与 Entry identity |
| old pending Pop × 普通/scoped | 2 | 同名 Host replacement 后，旧回执不得冒用新 registration 的 ID |
| Core receipt Host/Outlet 不匹配 | 2 | 不销毁仍在后端栈中的 Route Scope，诊断可见 |
| 退役 Runtime Pop × 普通/scoped × history capacity 0/4 | 4 | 旧回执不误删新 Entry，也不把同名新 Host 标记失同步 |
| 抛错 observer 早于 Runtime 注册 | 1 | 在 navigation result 的微任务交接前，Runtime 已通过 predictive commit 完成精确协调；重复终态幂等 |

调整两个既有测试：聚合 ID 不再等于 raw child ID，Guard target 不再是同一个 raw
对象；仍校验 Host、Outlet、转换身份和动态解绑，而非删除测试或弱化所有权断言。

初跑 `initial.log` 中 151 通过/2 失败，失败即上述旧身份假设；改成聚合域断言后，
`focused.log` 的 79 项通过。新 Scope 夹具初版错误地从 Runtime 根注册 Route Service，
并遗漏 promoted token，导致四项 fixture 错误；已改为组件 Registrar 注册及稳定 token。
`boundaries-fixed.log` 的 44 项通过，随后补充三项同步焦点重入，最终默认 suite 包含全部
47 项。进一步在 Runtime 层补验旧 Pop 回执，发现四项错误失同步标记并加入 registration
fence；见修复前 `late-receipt-before-valid.log` 的四项失败与修复后
`boundaries-final.log` 的 **51 项通过**。首次 late-receipt 夹具的 void Future 类型推断
错误已改为显式 outcome 转换，不计作产品缺陷。

## 验证结果

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| 最终框架 + Demo + navigation_lab + analytics Flutter + payment + kv_storage + order example | **1441 全通过**，包含新 51 项 | [flutter-verified.log](flutter-verified.log) |
| analytics、analytics_firebase、tool Dart suite | **55 全通过** | [dart.log](dart.log) |
| Generator suite，单并发 | 652 通过、1 因并行源码修改触发输入屏障失败、1 跳过；失败项在稳定输入下单独重跑 1 通过 | [generator.log](generator.log)、[generator-recheck.log](generator-recheck.log) |
| 根静态分析 | 无问题 | [analyze-final.log](analyze-final.log) |
| Demo generate --check | 完整 suite 结束后再验证通过；完整 Builder 执行，6 个组件、34 条路由、11 个生成 Package 产物一致 | [generation-final.log](generation-final.log) |
| 文档检查 | 通过 | [documentation.log](documentation.log) |
| 格式检查、git diff --check | 9 个 Dart 文件均无需格式修改，diff 检查通过 | [format.log](format.log)、[diff-check.log](diff-check.log) |

全量 Flutter 首跑为 1434 项通过，补充同步重入后为 1437 项通过，补充 Runtime
退役回执后最终 **1441 项通过**；以最终代码的 `flutter-verified.log` 为准。

Generator 完整 suite 的运行期间仍有本轮源码修改，其 one-shot/watch evidence 用例
因输入在 before-aggregation 屏障期间改变而 fail closed，见 `generator.log`。
冻结源码后，单独重跑该项通过，见 `generator-recheck.log`。完整 suite 无其他失败；
不会将初跑描述为一次全绿，也未为绕过输入屏障而修改生成器或削弱断言。

已同步根 README 中英、contracts/内部 DartDoc、integration Skill 与实现/review 参考、
framework 内存审查参考。Host 诊断将 aggregate Entry ID 视为不透明标识，不能与 child
原始 ID 混用；业务 API 无需迁移。无新业务能力需要补 Demo，确定性框架回归承担这些
内部故障边界的覆盖。

本轮未新增 macOS 实窗、Android/iOS 真机手势或长期性能/内存 soak。GC、Flutter 平台
Widget 手势和 Demo monkey 回归属于自动化证据，不替代真实设备验收；也不据此声称
整个框架已无其他缺陷。未对 main 追加同场景对比。
