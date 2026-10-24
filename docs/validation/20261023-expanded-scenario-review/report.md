# 扩大场景范围审查：Host 换代、资源接管与异常清理

日期：2026-10-23。分支：`codex/managed-navigation-runtime`，HEAD：`09cb21d`。

本轮审查当前工作树，包括此前所有未提交修复。没有修改框架生产代码、Demo、生成物
或正式回归测试，没有提交、推送。新增内容仅为本目录的诊断探针、执行日志和报告。
遵循框架开发 Skill 的 API 隔离、生产场景分类及内存/生命周期证据要求，以及集成开发
Skill 的 Host/组件边界。探针中低层 Runtime 仅用于隔离测试；Session 问题另经公开
`CCRouter` 业务 Facade 复现。

## 结论

发现 **3 类生产代码问题**，新增探针共 **18 项：9 通过、9 失败**。另发现一处既有
回归测试对真实时钟启动时序的依赖。不能将本轮结论表述为“全部稳定”或“重构后各方面
均优于旧后端”。

正式 Flutter 全量第一次为 **856 通过、1 失败**；失败项单独重跑通过，第二次全量
**857 项通过**。Dart 专项 **55 项通过**，Workspace analyze 无问题。正式套件通过
与新探针失败同时存在，说明原有测试没有覆盖这些边界。

本轮不将全部问题归因于上一轮修复：Scope 的相关代码无工作树差异，HEAD 也包含
相同的资源接管顺序、timeout 取消调用及按 Host 字符串查找 Adapter 的逻辑。没有在
历史 GoRouter checkout 重跑探针，不能据此判断整个架构迁移前后的缺陷数量。

## P1：同 ID Host 重建后，旧操作会进入新实例，并污染新请求的并发准入

主要位置：

- `packages/ccrouter_core/lib/src/navigation_backend.dart:310`：detach 仅清理已存在的
  Entry、backend ledger 和 sequence，未终止该 Host 的策略等待、defer 或并发 gate。
- `packages/ccrouter/lib/src/multi_host.dart:787`：提交时只用 `request.hostId` 重新查找
  当前 Adapter，没有捕获或验证具体注册实例。
- `packages/ccrouter_core/lib/src/navigation_concurrency.dart:25`、
  `packages/ccrouter_core/lib/src/navigation.dart:468`：未完成请求按逻辑 Host ID 匹配，
  不区分注销前后的生命周期。

触发条件是使用公开 Host Composition API `unregisterHost`，随后用相同 ID
`registerHost` 新 Adapter；并非普通切焦点。探针先在真实 Managed MultiHost 中
阻塞策略，再注销 primary、创建全新 `CCManagedRouterBackend`、注册并挂载其
`MaterialApp.router`。新旧 Backend、Navigator keys 都是不同实例。

实际结果：

| 旧工作/新请求 | 实际行为 | 应保持的不变量 |
| --- | --- | --- |
| 旧 Interceptor 返回 Proceed | 新 primary 从 `/` 进入 `/detail/A` | 旧实例结束，未提交操作应失败/取消 |
| 旧 Interceptor redirect | 新 primary 进入 `/detail/B` | 晚到决策不得变更新实例 |
| 旧 Failure Policy recovery | 新 primary 进入 `/detail/B` | recovery 属于原操作的生命周期 |
| 旧 deferred request resume | 新 primary 进入 A，原调用成功 | 已结束实例的 continuation 不得复活 |
| 新 primary 相同 URI，singleFlight | 新请求的策略不执行，最终共享旧请求的取消错误 | 新实例应独立准入 |
| 新 primary 相同 URI，rejectDuplicate | 新请求的策略不执行，报 duplicate | 旧实例的 gate 不应阻塞新实例 |

singleFlight 和 rejectDuplicate 的新请求均只有第一次旧策略检查（`calls=1`），新
Backend 保持 `/`；对照中同一活实例两次请求正确共享/拒绝，单纯切焦点保持原 Host，
注销且不重注册时则正常失败。这不是上一轮“active Host 改投”的重复复现，而是
**逻辑地址相同、资源实例已换代**的 ABA 边界。

本例未证明跨账号数据泄露，也未证明已提交页面迁移；影响是旧策略和 continuation
越过 Host 实例终止边界，覆盖新窗口/导航区域，及新请求被旧 gate 错误共享或拒绝。
本轮使用 `go` 和默认 root placement，不将未测试的全部 Stack 操作宣称为已复现。

建议由 Runtime/Host 内部维护实例代际或等价的不可复用绑定：等待前捕获归属，detach
终止该代在途及 pending 工作、清理该代 gate，提交和 resume 验证该代仍有效。取消
错误应为终态，不能由 Failure Policy 又恢复进同 ID 新实例。仅在 gate key 加 epoch
不足以阻止旧请求提交；仅在提交时检查也不足以解决新请求共享旧 gate。默认/显式
Host 与跨 Host redirect 的绑定规则需要一起定义，不能退化为全局锁或隐式迁移。

## P2：Session 在 factory 内重入关闭时，返回的 Service 漏掉 dispose

位置：`packages/ccrouter_core/lib/src/scope.dart:179`、`:191`。

组件注册 Session-scoped Provider。factory 构造一个 `CCDisposable` 实例，随后同步
触发 `CCRouter.closeSession()`（例如构造过程中通知认证状态变化导致注销），再返回
实例。公开 `CCRouter.service<T>()` 按预期抛 `CCScopeClosedError`；等待 Session
关闭并最终 `CCRouterHost.shutdown()` 后，该实例的 `dispose` 调用次数仍为 **0**。
使用测试 Runtime 的隔离路径也得到相同结果。

根因是 `own(create())` 先执行用户 factory。Scope 在 `create` 内已经关闭，`own`
的 `_ensureActive` 随后抛错，已构造对象既未入 disposal 集合，也没有拒绝接管时的
补偿清理。Runtime 后续 shutdown 无法再找到它。

这是已证明的 **not-disposed**，保留的 owner/resource 为 factory 成功返回的
`CCDisposable` Service 及其可能拥有的资源；没有做 heap 保留证明，不报告
`not-GCed`。正常 Session 关闭、正常 App shutdown 的对照均 dispose 一次。
App factory 内发起 Runtime dispose 的对照也在等待 shutdown 后 dispose 一次：
Runtime 的 teardown 阶段不同，不能把该路径也误报为同一种遗漏。

建议让“构造成功 → 接管或补偿销毁”成为异常安全的完整流程。关闭与正在构造的
实例交接必须协调；异步 dispose 应被有界地等待并纳入 Owner 清理，保留原始 Scope
关闭错误，同时隔离清理异常。不要仅在 `own` 抛错后发一个无人等待的 dispose，也
不要让 factory 等待拥有它的 shutdown 而形成自等待。补充 singleton/newInstance、
依赖构造、同步/异步及抛错 dispose 的回归后再给出完整生命周期保证。

## P2：timeout 时取消监听器抛错会替换原始超时错误

位置：`packages/ccrouter_core/lib/src/runtime_host.dart:2593`。

Command handler 注册 cancellation listener，listener 在通知时抛 `StateError`；
handler 自身仍等待 Future。调用配置 5ms timeout。

实际 listener 收到一次通知，trace 为 `timedOut`，但调用方收到
**`StateError('cleanup listener')`**，而非 `CCInvocationTimeoutError`。handler
晚到错误已被探针完成并消费，不存在靠未处理异步异常制造失败的情况。取消 listener
不抛错的同配置对照正确收到 `CCInvocationTimeoutError`。

`CCCancellationToken.cancel` 的明确契约是通知所有监听器后抛首个错误；Runtime
在处理 timeout 的 catch 内直接调用它，抛出的清理异常打断 `rethrow`，覆盖原始业务
调用错误。由此依赖 timeout 类型的重试/降级可能失效，且调用结果与 trace 不一致。
同一 helper 也被其它异步能力复用，但本轮动态复现仅为 Command，不声称对每类
生成代理、Event 都单独做了此探针。

建议 Runtime 在此隔离 cancellation 通知异常，通过已有的安全诊断边界记录，同时
保留原 timeout 及其 stack。不要改变 Token 对显式调用 `cancel()` 的公开错误契约，
也不要把 cancellation/listener 抛错推给业务层统一吞掉。回归应核对原错误、trace、
所有 listener 都被通知、nested context 和晚到错误处理。

## 回归质量观察：共享 Service readiness 测试依赖 10ms 启动窗口

位置：`packages/ccrouter_test/test/runtime_test.dart:414`、`:417`。

本轮第一次全量回归中，该测试超时断言已通过，但读取
`late initializerContext` 时出现 `LateInitializationError`。该变量仅在 initializer
进入后赋值；调用在真正进入 initializer 前就耗尽 deadline 是合法分支。单项重跑
和第二次完整回归均通过，原始失败日志完整保留，不能用后续绿灯抹去首次失败。

代码证据及日志支持“测试缺少 initializer 已启动的同步点”，不据此另报 Service
readiness 的生产缺陷。建议先启动一个 owner waiter，等待 initializer 的明确 gate，
再发起有短 timeout 的第二个 waiter，核对第二个 timeout 不取消共享 initializer，
完成 gate 后等待 owner 成功；另以独立测试覆盖“超时发生在工作启动前”。这比把
10ms 调大更能表达要验证的契约。

## 验证矩阵与范围

| 范围 | 本轮动作 / 结果 |
| --- | --- |
| Host unregister → 同 ID register | 新建真实 Managed/Navigator 探针，Proceed/redirect/recovery/defer 和两种并发策略均复现问题 |
| 焦点切换、注销不重建、同代共享/拒绝 | 新增正向对照通过 |
| Session/App 构造与终止交叉 | 公开 Facade + 低层隔离探针；Session 重入有资源遗漏，其它上述对照通过 |
| Command timeout、throwing cancellation listener、late error | 新增确定性等待探针，throwing 路径复现错误替换 |
| 混合 Navigator、LocalHistory、Shell、parent、exact close、手势重入、Route Scope、适配布局 | 读取相关实现和既有 ownership/lifecycle 回归，完整重跑正式套件；本轮没有对这些维度新增所有交叉排列 |
| Command/Event/Service/InitTask、UI Fragment 边界 | 检查共享调用/Scope 实现及现有相关测试，正式全量覆盖；没有确认其它新生产缺陷，不能等价于每种失败组合均已新增探针 |

实际执行：

```sh
fvm flutter test --no-pub packages/ccrouter_test/test demo/test demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded
fvm flutter test --no-pub packages/ccrouter_test/test/runtime_test.dart --plain-name 'caller timeout does not poison shared Service readiness' --reporter expanded
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test tool/test --reporter expanded
fvm dart analyze
```

| 执行 | 结果 | 日志 |
| --- | --- | --- |
| Flutter 全量第一次 | 856 passed / 1 failed，readiness fixture 时序问题 | `ccrouter-expanded-review-flutter-tests.log` |
| readiness 单项重跑 | 1 passed | `ccrouter-expanded-review-readiness-retry.log` |
| Flutter 全量第二次 | 857 passed | `ccrouter-expanded-review-flutter-retry.log` |
| Dart 专项 | 55 passed | `ccrouter-expanded-review-dart-tests.log` |
| Workspace analyze | No issues found | `ccrouter-expanded-review-analysis.log` |
| 文档检查 | 121 个受检 Markdown 通过 | `ccrouter-expanded-review-docs.log` |
| 新增 review probe | 9 passed / 9 failed，三个生产问题类别 | `ccrouter-expanded-review-probe.log` |

探针快照为 `probe.dart.txt`，不加入正式 test gate，以免把已知预期失败混入日常套件。
使用当前工作树的绝对 fixture import；换 checkout 后需要调整。

```sh
cp docs/validation/20261023-expanded-scenario-review/probe.dart.txt /tmp/ccrouter_expanded_review_probe_test.dart
fvm flutter test --no-pub /tmp/ccrouter_expanded_review_probe_test.dart --reporter expanded --timeout 30s
```

9 项失败对应 Host 的 6 条路径、Session 的公开/隔离 2 条路径、timeout 1 条路径。
factory 里的 Runtime shutdown 仅作与 Session 关闭不同阶段的对照，不作为业务接入示范。

没有修改生成声明、Plugin 或生成器，未额外执行其专项 suite、pin-check 或生成流程。
没有新增实际计时器/订阅等框架资源。未执行新的 macOS 按钮遍历、Android/iOS 真机
手势、长时间 monkey、heap 或性能采样；已有结果不能冒充本轮验证。

## Demo 缺口与候选方案

当前固定双 Host Demo 覆盖的是两个存活 Host 的导航隔离与适配布局，不能覆盖
Host 销毁后复用同 ID 的生命周期。`CCManagedMultiHostBackend` 的 factory/Backend
列表为固定装配；其公开 adapter 的动态注册属于 Host Composition API。不要把业务
组件直接调用 register/unregister 当作推荐接入模式。

本轮没有改变支持能力或推荐接入方式，故未为报告修改 README/Integration Skill，
也未把已知失败路径包装成能正常工作的 Demo。新增的确定性探针已经足够复现本轮
三个问题；交互样例应随框架修复建立通过基线。

| 方案 | 收益 | 代价 / 结论 |
| --- | --- | --- |
| 应用永久使用唯一 Host ID、禁用并发共享、禁止 factory 间接触发注销 | 可临时减少触发机会 | 隐藏生命周期缺口，不能替代框架清理和错误保证 |
| Demo 单独清理旧工作，或全局锁住全部导航 | 可使演示看似正常 | 掩盖 Runtime 缺陷，破坏独立 Host 并发，不推荐 |
| 内部统一实例归属、资源交接和清理错误隔离 | 无需扩大业务 API，修复所有调用方共享的根因 | 需要跨路径生命周期回归，推荐 |
| 新增万能 Host/业务 API 抽象 | 能暴露更多控制 | 本次场景已有契约可表达，成本与边界风险无必要 |

推荐顺序：

1. 将本轮探针转为正式 contract regression，先固定失败基线；同时去掉 readiness
   fixture 对工作启动时间的假定。
2. 优先修复 Host 实例代际：一并覆盖策略等待、Failure Policy、pending replay、gate
   清理及 late completion，不能只给某个 API 加一次判断。
3. 修复 Scope 构造交接和异步资源回收，保证所有成功返回资源都有清理归属。
4. 隔离 timeout 的 cancellation 通知失败，保持原错误及诊断一致性。
5. 在 Demo Host 层补“辅助 Host 关闭/重开 + 延迟策略完成/取消”的可观察样例，并用
   实际 Flutter 窗口验证旧页面不会进入新实例；factory 重入清理和 timeout 错误语义
   继续由确定性测试主验，无需增加诱导业务代码在 factory 注销的按钮。
6. 按行为变化同步 README、Integration Skill、有关 reference 与 DartDoc，执行全量
   回归，再进行适用的真实窗口/手势验收。

## 为什么审查仍能发现新问题

这轮证据表明，测试此前验证了“Host 地址固定”，未验证“地址相同但实例已终止”；
验证了“Scope 关闭后拒绝解析”，未覆盖“构造已开始、接管尚未完成时关闭”；验证了
“timeout 取消工作”，未覆盖“取消清理本身抛错”。测试自身还有“已超时就意味着
initializer 已启动”的时序假定。

应按不变量补齐终止边界、资源移交边界与异常清理边界，而非只增加顺序点击或断言
数量。每次修复至少配“成功 / 未启动即失败 / 等待中结束 / 完成时换代 / 清理抛错 / 晚到
信号”中的相关交叉，并明确活实例与新实例的正反对照。有限的 review 和回归不能
证明永远没有其它问题；本报告保留具体覆盖与未验证范围，避免再次给出无依据的
整体稳定结论。
