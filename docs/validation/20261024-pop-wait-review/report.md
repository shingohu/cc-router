# Pop 等待生命周期与初始栈身份审查

日期：2026-10-24。工作树：
`<home>/.codex/worktrees/managed-navigation-runtime/cc-router`，
分支 `codex/managed-navigation-runtime`，基于 HEAD
`09cb21d78381bbdeab431cf6bca279f909827db1` 及此前未提交成果。

本轮仅审查、编写复现探针和执行验证。未修改生产代码、公开 API 或 Demo，
未提交、推送、清理已有改动，也未修改用户的主工作树。

## 发现 1：P2，退役后仍等待自定义 Adapter 的 Pop / close

位置：`packages/ccrouter_core/lib/src/navigation.dart:83`、`:95`、`:101`、`:329`。

Core 直接等待 `maybePopOutcomeAt`、`maybePopOutcome`、旧 Boolean `maybePop`
和 `closeNavigation` 返回的 Future。这些等待没有绑定 Runtime / Host / 原 Entry
结束信号。上轮增加的 registration fence 在等待之后执行，只能阻止迟到回执
修改状态，不能结束等待或释放等待帧。

触发条件是自定义 Adapter 等待尚未结束的外部 Future，例如异步表单确认、
第三方导航桥回执。先结束 Runtime、移除 Host，或者让正在 close 的 Entry 被
同 Host 的 Go 替换，调用都仍处于等待状态。Adapter 的 dispose 已执行一次、
backend listeners 已清空、Runtime active Entries 已清空，仍不能结束该调用。

泄漏类型为 **not-GCed**：外部 gate Future 的 continuation 保留 Core async 等待帧，
帧继续保留 Runtime 和调用者 Zone；`closeRoute` 还保留原 `_RouteEntryRecord`
及其 arguments。若外部 Future 永不结束，这些对象会无限期存活。Pop 探针中原页面
参数已释放，不将其错误列为 Pop 的保留对象。

证据：
`packages/ccrouter_test/test/review_repros/pop_wait_lifecycle/repro.dart`，共 36 项。

- Legacy / Coordinator / scoped Coordinator / targeted close，覆盖 Runtime.dispose
  和 Host detach；targeted close 另外覆盖同 Host Go 替换原 Entry。
- 每条路径交叉底层已完成 / 仍挂起、成功 / 失败，18 个已完成对照通过，18 个挂起
  变体失败：边界之后仍未 settled，三轮强制 GC 后 Runtime / caller Zone 仍在；
  close 的原页面参数也仍在。
- 测试在记录 Host / Entry 结束时的 settlement 后，关闭剩余 Runtime，再测 Runtime
  GC。因此不宣称 Host detach 时仍存活的 Runtime 本身就应该被 GC。
- 释放外部 gate 后，所有变体完成且上述对象都可以 GC。迟到错误也有消费者，未出现
  uncaught error。确认的是取消缺口及延迟保留，不是 Adapter 未调用 dispose。
- 探针状态和完成通知在父 Zone 创建，不保留从 caller Zone 返回的 Future 来测该
  Zone 的 GC。初版夹具恰好保留了这个 Future，导致正常对照也失败；该无效版本的
  输出保存在 `prototype-invalid-fixture.log`，不计入产品发现。

原生 Managed 的 pending willPop 在 renderer teardown / Runtime shutdown 时结束，
现有默认测试仍通过。因此本发现针对 Core 接入外部 Adapter 的等待边界，不能表述为
“所有原生返回都挂起”或“侧滑出现新回退两次”。

## 发现 2：P2，初始栈尚未有 Runtime 导航时缺少 registration fence

位置：`packages/ccrouter_core/lib/src/navigation.dart:120`–`:122`。

`_popRegistrationForTarget` 只读取 `_navigationHostRegistrations`；目前 token
由普通导航 `_bindNavigationHost` 创建。可选 Snapshot SPI 导入的初始栈不保证已经
有过 Runtime 导航，因此合法的 initial backend stack 可以没有 registration token。

复现：导入 right Host 的 managed initial snapshot → 发起挂起 Pop → detach right →
注册同名 right 并导航新页面 → 旧 Pop 返回 managed ownership。
聚合 identity namespace 正确保留旧 registration 的 Entry ID，新页面不会被误删；
但 Core 捕获的 registration 为 null，旧回执进入 `_recordUncorrelatedManagedPop`，
把新 right 错误加入 `desynchronizedBackendHosts`。

这属于退役回执污染 replacement 的诊断状态，**不是已证实的跨 Host 误删或内存泄漏**。
不需要假设任意嵌套聚合受支持：使用普通两 Host、公开 Snapshot / Pop SPI 即可复现。

证据：
`packages/ccrouter_test/test/review_repros/pop_wait_lifecycle/initial_stack.dart`，共 8 项。

- prior Runtime navigation 有 / 无 × 普通 / scoped Pop × diagnostic capacity 0 / 4。
- 4 个已有 Runtime 导航的对照通过；4 个只导入 initial stack 的变体失败。
- 每项先断言 replacement 未失同步，再释放旧 Pop；之后新 Entry identity 保持不变，
  失败仅为失同步标记错误出现。与是否保留 removed-entry 诊断历史无关。

## 根因、方案取舍与建议

这两处暴露的是两种不同的不完整边界：**异步结果隔离不等于等待生命周期结束**；
**有导航记录不等于有 Host registration**。上轮测试启动过 Runtime 导航才发起 Pop，
并在断言前主动释放底层 gate；所以覆盖了旧回执身份，却没有覆盖本轮的两个边界。
这些证据不能证明架构整体劣于 main，也不能用既有 suite 全绿证明所有 SPI 组合完整。

| 候选方案 | 收益 | 成本 / 缺点 |
| --- | --- | --- |
| 只要求每个 Adapter.dispose 完成所有等待 | Core 改动小 | 取消语义分散，原 Entry 单独结束也无法仅靠 Adapter.dispose 覆盖；不能统一第三方桥接行为 |
| 给每处 await 增加 Future.any 或更多事后检查 | 表面调用可提前返回 | 不保证底层 Future listener 释放等待者 Zone；继续存在 GC 保留和漏掉某条等待路径的风险 |
| Core 统一管理外部导航等待，registration 独立于导航历史 | 在固定内部边界覆盖取消、迟到结果及资源释放；业务入口不变 | 需要明确各操作取消结果，并验证跨 error Zone、同步重入和原生已有语义 |

推荐第三项。下一轮修复顺序：

1. 为每次 admitted Pop 固定目标 Host 和具体 registration；即使只有初始栈也建立
   生命周期身份，detach 取消后不能因同名重建而复用。同步 business Pop 同步审计。
2. 用可注销、无 Runtime / Entry 捕获的内部完成桥接管理外部等待。绑定 App 和具体
   Host；targeted close 另外绑定原 Entry。owner 结束时只终结框架等待，不擅自
   取消独立的应用任务，也不等待 UI frame。
3. 外部迟到成功 / 失败只由无 owner 引用的消费者处理，不能二次终结、改写新 Host
   状态或形成 uncaught error。取消结果保持现有原生返回语义；先确定 `maybePop`
   与 `close` 的各自契约，不将统一 `handled: false` 当作未经评估的默认答案。
4. 将本轮两份 failing probe 纳入默认回归，再补取消后仍不结束的业务 Future、
   独立 error Zone、同步 teardown 重入、live owner 和同名 replacement 对照。
5. 同步受影响 DartDoc、README 和 integration guidance，再跑框架 / Demo / 分析 / Host
   generation。无需在业务 API 添加开关；内部等待桥接可独立审查和回退。

本轮没有新增可演示的业务能力缺口，因此不补业务 Demo 按钮。以自定义 Adapter 和
初始栈夹具复现更准确，不把内部 SPI 故障转成推荐应用模式。

## 验证结果

| 检查 | 本轮结果 | 证据 |
| --- | --- | --- |
| 两份新增边界探针 | **44 项：22 对照通过、22 失败归属于上述 2 个根因** | [boundaries.log](boundaries.log) |
| 默认框架 + Demo + navigation_lab + analytics Flutter + payment + kv_storage + order example | **1441 项通过** | [flutter.log](flutter.log) |
| analytics / analytics_firebase / tool Dart suites | **55 项通过** | [dart.log](dart.log) |
| 根静态分析 | 无问题 | [analyze.log](analyze.log) |
| 最终新增探针分析 | 无问题 | [probe-analyze.log](probe-analyze.log) |
| Demo generate --check | 通过，内容校验 fast path；未重跑完整 Builder | [generation.log](generation.log) |
| 文档检查 | 121 个 Markdown 通过 | [documentation.log](documentation.log) |
| 格式 / git diff --check | 两份新增 Dart 格式通过、diff 检查通过 | 命令结果 |

默认 suite 通过不包含新 failing probe：两份文件刻意不使用 `_test.dart` 后缀，
用于 review 时显式执行；修复后应转成默认回归，不能仅依靠默认 suite 宣称这两处已修复。

实际默认 Flutter 命令：

```sh
fvm flutter test packages/ccrouter_test/test demo/test demo/modules/navigation_lab/test demo/modules/analytics_flutter/test demo/modules/payment/test demo/modules/kv_storage/test demo/modules/order/example/test --reporter expanded
```

初跑将 order example 错写成不存在的 `examples/order_component/test`，1440 项实际测试通过
但 invocation 失败，保存为 `flutter-invalid-path.log`；纠正路径后完整重跑 1441 项通过，
以上表格只使用纠正后的结果。未把错误路径加载失败当成产品失败。

新增探针命令：

```sh
fvm flutter test packages/ccrouter_test/test/review_repros/pop_wait_lifecycle/repro.dart packages/ccrouter_test/test/review_repros/pop_wait_lifecycle/initial_stack.dart --reporter expanded
```

本轮现有测试还覆盖原生 pending willPop 结束、iOS 重复 / 取消侧滑、Shell 与 foreign
popup、父栈重建、多 Host / Outlet、共享 readiness DAG / 独立根环路 / timeout 解边、
Session 更替和先前的 waiter GC 回归。未重新进行 macOS 真实窗口或 Android / iOS
真机手势验收；没有重跑 Generator 全量 suite 或 isolated Analyzer Plugin suite。
这些范围无生产修改，本轮结果不替代真机验收或所有外部 Adapter 的兼容性证明。
