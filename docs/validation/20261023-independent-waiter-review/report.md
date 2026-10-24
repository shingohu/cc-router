# 独立等待者与跨 Host 身份边界审查

2026-10-23；工作树 `managed-navigation-runtime/cc-router`；分支
`codex/managed-navigation-runtime`；HEAD
`09cb21d78381bbdeab431cf6bca279f909827db1`，叠加此前未提交成果。

本轮为审查与复现，未修改框架生产代码，未提交或推送，也未修改用户的主工作树。
按 framework-development Skill 检查身份、生命周期及内存所有权；按 integration
Skill 判断是否需要增加业务 Demo。确认 **1 个 P1、2 个 P2**，不应据默认 suite
通过就宣布已经稳定。

## P1：MultiHost 子 Adapter 的本地 Entry ID 碰撞导致跨 Host 清理

生产位置：

- `packages/ccrouter/lib/src/multi_host.dart:987`：转发 child backendEntryId 原值；
  同一桥接只对 operation ID 做 registration namespace。
- `packages/ccrouter_core/lib/src/navigation_backend.dart:386`、`:409`：ledger 仅用
  backendEntryId 作全局 key，后到的另一个 Host Entry 覆盖前者。
- `packages/ccrouter_core/lib/src/navigation.dart:123`：消费 managed Pop receipt 时
  按该 key 找 RouteEntry，未校验 receipt 的 Host/Outlet。

复现：两个独立、自定义子 Adapter 各只推入一个 managed 页面，正确提供不同 Host、
navigationId 和同一类 root Outlet，但各自本地 Entry ID 都是 `entry-1`。返回左侧：

- 左侧后端栈变空，右侧后端栈仍有一个页面。
- Runtime 的 active RouteEntry 却全被清空。
- 两个 Route Service 的 dispose 次数是 `[1, 1]`，预期为 `[1, 0]`。
- 改为不同 backendEntryId 的对照通过。

原因是右侧 push 覆盖 ledger 后，左侧 Pop receipt 错误关联右侧 Scope；随后左侧原始
navigation Future 完成，又正常移除左侧。公开契约仅说明 ID 由 Adapter 分配并保持稳定，
未要求独立子 Adapter 在所有 Host 间协调全局 ID；`CCPopOutcome.hostId` / Outlet 的
DartDoc 还明确承诺用于精确分区校验。

影响限定：**自定义或兼容子 Adapter 的本地 ID 碰撞**。原生 Managed 使用实例区分的
ID，本轮没有复现两个原生 Managed Host 互相误删。另一组 right foreign push/pop 与
left managed Entry 同 ID 的对照也通过，不能将本发现泛化成任何 foreign event 都会
直接销毁 Scope。

分类为错误销毁（Scope 生命周期/分区隔离违约），不是内存泄漏。

## P2：取消或超时的独立 waiter 保留调用者 Zone

生产位置：`packages/ccrouter_core/lib/src/scope.dart:80`，root waiter 直接等待共享
readiness Future；`shared_result.dart:48` 在每个 caller Zone 中建立 await。
`runtime_host.dart:2303` 的内部 readiness 等待不会随外层 invocation 的取消一起脱离。

复现刻意排除“首个调用者合法创建 singleton”带来的 Zone 继承：

1. 首个调用在 Host/test Zone 启动 App singleton initializer，initializer 仅返回外部
   gate Future，不捕获请求对象，且只启动一次。
2. 再建立三个各自带独立 payload 的第二批 caller Zone，加入同一未完成初始化。
3. 分别显式 cancel 或 timeout，外部调用正确结束，helper frame 返回。
4. WeakReference + 三轮 forceGC 后，三个已结束 caller 的 payload 仍全部存活。
5. 共享 initializer 完成后，三个 payload 全部回收；先初始化完成再调用的对照也通过。

这是 **not-GCed**：共享任务仍合理存活，但 Future listener/await 的 caller Zone 继续
保留已经结束的独立请求数据。若共享初始化长期等待网络/平台资源，重复取消会累积保留
对象；不是只在强制 shutdown 时才可见的问题。

上一轮修复“实际 initializer owner 结束”并未覆盖“singleton owner 仍有效，某个 waiter
独立结束”。不能通过取消共享 initializer、清空 lineage 或仅增加外层 Future.any 来
解决，前两者破坏其他调用者语义，后者不能保证解除原 Future listener 的 Zone 保留。

## P2：MultiHost 预测返回转发缺少逐 observer 异常隔离

生产位置：`packages/ccrouter/lib/src/multi_host.dart:925`—`:926`。

子 source 将 aggregate bridge 当作一个 listener。aggregate 遍历自己的 observer 时，
第一个抛异常会中断循环；即使 native coordinator 在外层吞掉 bridge 异常，后面的
observer 仍然收不到任何 phase。

复现发出四种 phase，正常对照收到全部四个；先注册一个抛错 observer 后，后注册
observer 收到 `[]`。单 Host/native source 的逐 observer 隔离夹具不变。

这与同文件 `_publishBackendEvent`、native coordinator `_emit` 的隔离策略不一致。
若 Host observer 注册早于 Runtime，后者可能漏掉 committed 的协调事件；实际原生
页面仍可能通过普通 backend event 或 navigation result 完成清理，本轮不据此声称
已复现手机手势失败或双重返回。

## 候选方案与建议顺序

| 方案 | 收益 | 限制/成本 |
| --- | --- | --- |
| 只要求每个 child 生成全局唯一 ID | 实现成本低，可临时约束自定义 Adapter | 把聚合责任转给 child；无法保护已有兼容实现，Pop 仍缺少分区防御 |
| MultiHost 按 child registration 编码 Entry identity | 复用现有 operation namespace 所有权，保留 child 本地协议 | 必须覆盖 event、snapshot、previous ID、Pop receipt、target、guard、predictive outcome 的完整双向转换 |
| Core ledger 改用复合身份 | 在 Core 统一表达 Host/Outlet/Entry 分区 | 改动遍及关联/可见性/快照消费者；还要处理同名 Host 重新注册的旧事件 |
| readiness 增加可注销的 per-waiter relay | 保留共享初始化，释放取消 caller 的 Zone | 必须保留跨 error Zone 的原始错误/stack 和 late error 消费语义 |
| MultiHost fan-out 逐 observer try/catch | 与 native/backend observer 一致，改动小 | 同时回归注销重入、旧 registration 晚到事件，不可降低现有 fence |

推荐：

1. 先修跨 Host 身份：在聚合边界按 registration 编码并完整转换 Entry identity，Core
   对已知 Host/Outlet 的 Pop receipt 再做防御校验。仅加 Host 比较而丢弃 receipt 会
   隐藏 ledger 覆盖，不能作为完整修复。保持业务导航 API 不变。
2. 将 shared readiness 的独立 waiter 改为可取消订阅；分别验证显式取消、deadline、
   Session/Route owner 结束、活跃 singleton、迟到成功/失败、不同 error Zone。
3. 统一预测返回 observer 的逐个异常隔离，保留原 generation fence。
4. 修复时将当前失败探针和对应边界提升为默认回归，再重跑完整 suite。每项私有修复
   可独立审查/回退；不为这些内部正确性修复引入业务开关或另一套路由架构。

以上为待实施建议，本轮未宣称已修复。

## 扩大场景的验证结果

新增三个显式探针文件位于
`packages/ccrouter_test/test/review_repros/shared_waiter_lifetime/`。为保留未修复问题的
复现证据，使用显式路径执行，未命名为 `_test.dart`，默认 suite 不会发现它们。

| 范围 | 结果 | 证据 |
| --- | --- | --- |
| 独立 waiter：cancel/timeout × pending/completed | 2 通过，2 失败；pending 各保留三个 payload | [probes.log](probes.log) |
| child Entry ID：managed/foreign × collision/control | 3 通过，1 失败；managed collision 跨 Host 清理 | [probes.log](probes.log) |
| predictive observer throw/control | 1 通过，1 失败 | [probes.log](probes.log) |
| interceptor/failure policy/revalidation/diagnostics × pending/completed × success/error | 16 全通过；Runtime 与 route payload GC、shutdown、late error 对照 | [probes.log](probes.log) |
| 新探针合计 | **22 通过、4 失败，对应三个缺陷** | [probes.log](probes.log) |
| 框架、Demo、navigation_lab、analytics Flutter、payment、kv_storage、order example 默认 Flutter suite | **1390 通过**；不包含上述显式探针 | [flutter.log](flutter.log) |
| analytics、analytics_firebase、tool 的 Dart suite | **55 通过** | [dart.log](dart.log) |
| 工作树静态分析 | 无问题 | [analyze.log](analyze.log) |
| Demo generation --check | 复用 active watch cycle 115，通过，未启动竞争生成 | [generation.log](generation.log) |
| 文档检查 | 通过 | [documentation.log](documentation.log) |
| git diff --check | 通过 | [diff-check.log](diff-check.log) |

最终有效复现命令：

```sh
fvm flutter test --no-pub \
  packages/ccrouter_test/test/review_repros/shared_waiter_lifetime/repro.dart \
  packages/ccrouter_test/test/review_repros/shared_waiter_lifetime/host_identity.dart \
  packages/ccrouter_test/test/review_repros/shared_waiter_lifetime/navigation_retention.dart \
  --reporter expanded
```

初次扩展夹具曾包含无效的 `Future<void?>`、`FutureOr<void>` 空 return，随后记录断言
曾错误地用包含 List 的 record 做 identity 比较；这些探针编译/断言问题已修正，不能
算作产品失败。最终统一日志 `probes.log` 使用合法类型、深比较 Map 和通过的正常
对照，仅采用该日志的 26 项统计。

## 为什么仍发现问题，以及本轮边界

现有回归此前主要证明了实际 owner 结束、operation ID 去重、单 source observer
隔离。本轮分别验证独立 waiter 结束、Entry ID 聚合和 aggregate observer 隔离，
揭示同一规则在相邻层没有完整落实。默认测试数量不是这些规则跨层成立的证明。

后续应按“所有权主体 × 终态 × 入口/聚合层 × 同步/迟到回调”维护边界矩阵，复用
Adapter 合约测试，而非仅为每次发现补单个正常页面用例。新断言需覆盖 Host 后端栈、
Runtime ledger、RouteEntry、Service 清理次数四者一致性，以及取消后的实际 GC。

没有添加新业务 Demo：本轮发现是内部等待注销、Host SPI 身份转换与异常隔离，已有
多 Host 与 Service 场景能够表达业务能力。将 ID 冲突或永挂 initializer 包装为推荐
业务示例不能提高覆盖质量；确定性探针更适合这些边界。

未进行新的 macOS 实窗、Android/iOS 手势或长期性能/内存 soak；GC 探针不等于这些
平台验收。本轮未对 main 运行新的同场景比较，不能把三个新发现归因于旧 main 或
Managed 重构。上一轮 main 比较的结论仍仅限其当时覆盖的缺陷。
