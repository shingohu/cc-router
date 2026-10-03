# CCRouter 全框架审查：正确性、开发体验与核心价值

## 状态与结论

- 日期：2026-10-03。
- 基线：`769587b`。审查开始时的 Path 指纹修复、拓扑基准与文档改动，结束时已包含在该提交中。
- 范围：Core/Contracts、Flutter Facade、GoRouter、五类能力生成器与 CLI、Analyzer、Analytics、
  DevTools、Demo 接入模式以及面向集成者的 Integration/CLI Skill。
- 状态：审查及 F01–F18 修复完成，验证记录见第 8–15 节。
  工具安装、真实 IDE/平台与长期观测的剩余边界见第 15 节。
- 审查结论：现有测试基线通过，但不能认定框架没有严重缺陷或生成器绝对准确。原确认
  5 项 P1、13 项 P2，其中 1 项 P2 属于 Demo；上述修复后本轮剩余 0 项已确认 P1/P2。
  这不表示正式发布门禁、所有候选优化或真实平台矩阵已完成。

P1 表示优先处理的业务结果、清理、授权或生成准确性风险；P2 表示特定合法输入或
组合场景下可复现的功能、工具或接入问题。没有发现并确认 P0，并不等于已证明不存在。
测试数量、耗时和 RSS 都只表示本轮执行结果；本轮没有重新进行真实设备矩阵或长时间 Heap 分析。

## 1. 验证范围与证据

| 检查 | 本轮结果 | 结论边界 |
| --- | --- | --- |
| Workspace `fvm dart analyze` | 通过，无问题 | 不执行 legacy Analysis Server Plugin |
| 独立 Analyzer Package analyze | 通过 | 与应用 Workspace 的 Analyzer 版本隔离 |
| 框架、Demo、Demo 模块、DevTools/Protocol 测试 | 418/418 通过 | 已存在的测试用例范围 |
| Generator 全量测试 | 272/272 通过 | 包括五类能力、缓存、原子恢复和 Workspace 校验 |
| 独立 Analyzer Plugin 测试 | 49/49 通过 | 单文件诊断、Quick Fix、Plugin 与缓存等现有用例 |
| Demo `generate --check --profile` | 通过，fast path，内部 351ms | 当前 Demo 输入和输出 |
| Demo `generate --no-cache --check --profile` | 通过，内部 3569ms | 与当前 Demo 受管输出一致；build_runner 1726ms |
| Runtime 1000 次 Push/Pop、每 100 次重建 | 通过；P50/P95 为 82/168us | 每轮 Entry、Pending、Backend 台账归零 |
| 新构造的边界复现 | 确认下列缺陷 | 临时脚本与隔离 Workspace 中验证，不作为已修复回归 |

完整 Flutter 测试命令：

```bash
CCROUTER_PUB_HOOK_DISABLE=1 fvm flutter test --no-pub \
  packages/ccrouter_test/test demo/test \
  demo/modules/kv_storage/test demo/modules/payment/test \
  demo/modules/navigation_lab/test demo/modules/analytics_firebase/test \
  packages/ccrouter_devtools/test packages/ccrouter_devtools_protocol/test \
  --reporter failures-only
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --check --profile
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check --profile
fvm dart run packages/ccrouter_test/benchmark/runtime_long_run.dart --cycles=1000
```

Analyzer 测试在 `packages/ccrouter_analyzer_plugin/` 内执行 `fvm dart test`。首次 Flutter
批量命令误传了不存在的 `demo/modules/network/test`，引起一项加载失败；去掉该路径后重跑，
最终为 418/418。该次命令错误不归类为框架测试失败。

长运行样本 RSS 从 202522624 增至 236273664 bytes，增加约 32.2 MiB。单次 JIT 进程的
短样本没有 GC 后存活对象与平台分配器证据，不能据此断言内存泄漏或长期内存稳定。
以下 F01 与 F18 则存在明确的资源创建到清理路径缺口。

## 2. P1 审查发现与修复状态

### F01：取消监听器异常中断整个 Runtime 清理

- 状态：已修复。Token 释放回调集合后逐项通知并重抛首个错误；Scope 记录错误后继续
  清理；Runtime 完成清理后返回早期 App 取消错误。Scope、Runtime 和 Facade 都在回调
  前建立关闭门禁，补上同步重入时重复关闭/提前 initialize 的同源缺口。
- 位置：[invocation.dart](../packages/ccrouter_contracts/lib/src/invocation.dart) 第 24 行、
  [runtime_host.dart](../packages/ccrouter_core/lib/src/runtime_host.dart) 第 1900 行、
  [scope.dart](../packages/ccrouter_core/lib/src/scope.dart) 第 140 行。
- 触发：Service 在 `context.cancellation.addListener` 注册抛异常的回调，随后 shutdown。
- 根因：Token 遍历 Listener 不隔离异常；Runtime 在清理入口直接调用 cancel，后面的清理
  根本没有开始；memoized dispose Future 会持续返回同一次失败。
- 实测：`service disposed: false`、`scope state: active`；重试后仍未释放。
- 影响：`not-disposed`；其余取消监听器、Service、Adapter、Route 等可能留存。
- 建议：逐 Listener 隔离异常并保证集合清空；Runtime/Scope 即使取消通知失败也继续释放，
  最终按统一安全诊断或首个错误策略收口。不能简单吞掉整个 shutdown 异常。
- 验收：App/Session/Route 三种 Scope、多个 Listener、取消回调重入、重复 shutdown、
  Service dispose 本身失败均不阻断其余清理。

### F02：框架 Guard 放行越过页面自己的 PopScope

- 状态：已修复。只临时打开具体 Route 的框架 Gate，同步检查完整 Flutter
  `popDisposition == pop` 后提交，再恢复仍存活的门闩；本地 PopScope/Form 仍可拒绝。
- 位置：[adapter.dart](../packages/ccrouter_go_router/lib/src/adapter.dart) 第 1297 行。
- 触发：Managed Page 配有返回 allow 的 CCRouter PopGuard，页面又有
  `PopScope(canPop: false)` 或等价 Form 退出保护，执行系统返回。
- 根因：`didPop == false` 后只检查框架 Guard，然后直接 `Navigator.pop`；它没有区分
  Flutter 的拒绝是否同时来自页面自己的 PopEntry。
- 实测：`router.routerDelegate.popRoute()` 后未保存编辑页面已被移除。
- 影响：页面本地退出限制失效，可能丢失未保存业务数据。
- 最终方案：在精确目标 Route 上临时放开框架自己的 gate，再同步复核其它 PopEntry，
  处理重入和 finally 恢复；不全局放开所有 Guard。没有二次调用异步 `maybePop`，因为
  初始返回已执行 legacy willPop，重复调用会增加业务回调次数和跨 await 的放行窗口。
- 验收：框架 allow/deny × 页面 allow/deny、Foreign Popup、结果回传、连续系统返回及手势
  用例。现有测试分别验证了两类 Guard，缺少组合测试。

### F03：Fast path 漏检外部 Path 源码，缓存与参考校验不等价

- 状态：已修复。快速路径与 Portable State 共用源码、解析依赖和工具的内容证明，额外
  读取全部外部受管输出；外部状态在 Builder 前检查，构建后再次检查。
- 位置：[ccrouter_generator.dart](../packages/ccrouter_generator/bin/ccrouter_generator.dart)
  第 2422 行。
- 触发：外部只读 Package 首次生成验证成功后，修改该 Package 的 authored source，保持
  Index、Bundle、Portable State 原样。外部 Path 在业务联调中可以合法地发生这种变化。
- 根因：快速输入摘要对只读 Package 仅读取上述几个文件，没有涵盖源码及其它受管输出；
  命中后提前返回，未执行 Portable State 的完整比对。
- 隔离 CLI 实测：普通 `--check --profile` 返回 0、`fast-path=hit`；同样输入的
  `--no-cache --check` 返回 1、`authoredInputMismatch`。
- 影响：Pub Hook 和普通检查可能放行组件旧生成物，违背“速度优化不牺牲准确性”。
- 建议：快速路径与完整路径共享验证输入集合，重新计算可变依赖及受管输出的内容摘要；
  无法证明时回退。当前 Build Plan/Portable State 的 Path 指纹修复未覆盖这一更早的入口。
- 验收：外部源码修改、生成文件修改/删除、依赖 DTO 变化，逐项比较 cached/reference
  的错误语义和输出；不能仅测试 state 文件本身被篡改。

### F04：Portable State 混入自身分发身份，阻断正常 Git/Pub 消费

- 状态：已修复。分发证明排除作者开发依赖闭包及内容已证明的 Package 传输身份；依赖
  版本、源码、语言配置和工具身份仍校验，本地 Build Plan 继续保留更严格的构建输入。
- 位置：[build_plan.dart](../packages/ccrouter_generator/bin/src/build_plan.dart) 第 766 行、
  [portable_generation_state.dart](../packages/ccrouter_generator/bin/src/portable_generation_state.dart)
  第 103 行。
- 触发：作者 Workspace 生成的同一份 Package，通过 Git/Pub 被另一个 Host 消费。
- 根因：包自身的 lock 来源、Git resolved-ref/archive identity、根包 devDependencies
  都进入 resolutionFingerprint。作者 Workspace 与消费者解析图的自身身份天然不同。
- 验证：保持包字节不变，调用真实验证器，只把自身 lock 身份从 Workspace 改为合法 Git
  身份，结果由 `valid` 变成 `resolutionMismatch`。本项是实际验证器的分发身份模拟，尚未
  执行真实远端 Pub 发布/下载；代码显示的自身身份冲突已成立。
- 影响：预生成内容正确仍被拒绝；Git commit 又包含 State，自身 commit 摘要存在循环问题，
  “再生成再提交”不能可靠解决。
- 建议：区分包内容证明、生成工具身份、依赖语义与消费者分发来源。保留必要工具/依赖校验，
  将包自身的传输身份移出生成内容证明；单独处理生产者 devDependencies。
- 验收：真正独立的 producer/consumer、本地 Git 提交、归档消费及 Host 缺少生产者 dev
  dependency。现有仅移动 rootUri 的测试不足以证明外部分发。

### F05：撤销 Consent 后仍启动下一个 Analytics Sink

- 状态：已修复。撤销/禁用递增投递代次并清空队列，每个 Sink 启动前复核授权和代次；
  立即重新授权不会恢复旧事件，已经开始的 write 仍不可撤回。
- 位置：[analytics.dart](../packages/ccrouter_analytics/lib/src/analytics.dart) 第 506、571 行。
- 触发：一个事件同时发往 A/B 两个 Sink；A 正在等待时撤销 Consent，然后 A 完成。
- 根因：撤销仅清空待处理队列，已取出的事件遍历 Sink 时不再校验策略。
- 实测：撤销后 B 的新 `write` 仍调用一次。B 在撤销时尚未开始，不属于无法撤回的在途写入。
- 建议：每次开始新的 Sink 投递前验证授权状态；使用策略代次处理 revoke 后立即 grant 的
  场景，防止旧授权下的事件借新授权继续发出。已经开始的网络写入仍由应用 Adapter 处理。
- 验收：多 Sink、阻塞 Sink、deny/grant/revoke、连续 revoke/grant、close 时授权变化。

## 3. 其余已确认问题

### F06（P2）：异步 Singleton 并发根调用相互等待，循环检测失效

- 状态：已修复。Scope Singleton readiness 节点记录活跃等待边，在回调前发布节点与
  Future；独立并发根的环也会失败。等待者取消/超时移除自己的边，不污染共享初始化。

[runtime_host.dart](../packages/ccrouter_core/lib/src/runtime_host.dart) 第 2147 行只检查当前
Zone 祖先链；[scope.dart](../packages/ccrouter_core/lib/src/scope.dart) 第 120 行直接共享已存在
的 readiness Future。两个独立请求先同时启动 A/B initializer，随后 A await B、B await A，
实测两个 Future 持续等待。现有单根 A→B→A 测试检测不到这种环。

建议在实际实例 Scope/Provider 身份上记录活跃等待边并检测环，终态移除边；补并发根、
跨 Scope、失败清理与超时测试。仅给调用者加 timeout 不会解除共享 readiness 的循环。

### F07（P2）：shutdown 没有取消正在等待的导航 Interceptor

- 状态：已修复。Interceptor 和 Failure Policy 等待关联 App 取消；结束等待、清除 Timer
  和监听，并在每次 await 衔接处检查关闭状态，阻止晚到 proceed/redirect/defer 和失败恢复。

[navigation.dart](../packages/ccrouter_core/lib/src/navigation.dart) 第 475、652 行使用独立
Token，并仅等待 Interceptor 本身或 timeout。它没有关联 Runtime 取消；shutdown 只取消
已经 Defer 的 continuation。

实测：shutdown 后 `context.cancellation.isCancelled == false`，原导航仍 pending；之后
手工释放 Interceptor，才以 Adapter 错误结束。若 Interceptor 永不结束，等待方无法收口。
建议导航从 admission 起纳入 Runtime 取消管理，取消及时完成公开 Future，每次 await 后
阻止晚到结果继续 dispatch；Dart 无法强制终止业务 Future，需分别定义合作取消与框架等待方。
补 proceed/redirect/defer 晚到、拦截超时和 shutdown 组合测试；Failure Policy 的同类边界
也应在修复阶段逐项验证。

### F08（P2）：Defer 恢复没有保留完整导航上下文

- 状态：已修复。Typed 请求重新 encode 校验并保留对象，动态 URI 重新匹配/decode；
  固定原具体 Host，保留调用级 Outlet、原操作与结果校验，并传递到恢复后的重定向及再次 Defer。

[navigation_pending.dart](../packages/ccrouter_core/lib/src/navigation_pending.dart) 第 152 行
恢复时先 `prepareUri`，没有传入调用级 placement 或 Extra；第 167 行使用声明默认 placement，
第 165 行稍后补回 Extra 已无法纠正此前的 decode。

已分别复现：

- `secondary/detail` 请求恢复后变成 `default/root`，进入错误 Host/Pane。
- typed Route 必填 Extra 恢复时报 `CCRouteParameterError`，没有打开页面；可选 Extra
  同样需要验证 arguments 与 request.extra 一致性。

建议明确 typed 与动态 URI continuation 的重建规则，在参数解码之前恢复应保留的数据，
继续复核权限与目标可用性。验收包括原对象身份、调用级定位、active Host 切换、redirect、
重复 Defer、超时和取消后的引用释放。

### F09（P2）：Service Proxy 默认字符串未转义 Dart 插值

- 状态：已修复。默认字符串在 JSON 转义后补上 Dart `$` 转义；List/Set/Map 递归使用
  同一规则，回归通过解析生成库并求值默认常量验证，不只匹配生成文本。
[service_proxy_generator.dart](../packages/ccrouter_generator/lib/src/service_proxy_generator.dart)
第 563 行直接用 `jsonEncode` 生成 Dart 字符串。真实 Builder 将合法
`String price({String unit = r'$currency'})` 生成为 `unit = "$currency"`，引用了不存在的
变量。建议使用共用的 Dart 字符串字面量编码器；覆盖 `$`、引号、反斜杠、换行和嵌套集合，
对生成结果做 Analyze/编译验证，而不只比对文字快照。

### F10（P2）：Analytics 属性仅浅层只读，可绕过值校验

- 状态：已修复。属性构造时复制并验证列表，向调用方及全部 Sink 暴露同一不可变快照。

[analytics.dart](../packages/ccrouter_analytics/lib/src/analytics.dart) 第 41、72 行保留调用方
List 引用，仅外层 Map.unmodifiable。实测先传合法 `['valid']`，再向原 List 加入 Map/Object，
已经验证的事件能读到这些非法对象；Sink 也可修改该 List，污染后续 Sink。

建议在值边界校验并复制受支持的 List，暴露不可变副本；不扩大为支持任意深层业务对象。
验收调用方修改、Sink 修改、排队期间修改、拒绝嵌套对象。

### F11（P2）：Analytics 首个 Sink 同步进入业务调用栈

- 状态：已修复。先建立单次调度状态，再通过事件循环分发；重入保持 FIFO，close 等待
  尚未启动的调度，最后一个 Sink 的完成监听器新增事件也不会滞留。

[analytics.dart](../packages/ccrouter_analytics/lib/src/analytics.dart) 第 564 行直接调用
async `_drain()`，其首个 `await` 之前已经执行 `sink.write`。实测 dispatch 返回前 Sink
计数已增加。耗时同步 Sink 会阻塞按钮/导航调用，重入发生时 drain 标识也尚未赋值。

建议先建立单次调度状态，再通过事件队列异步启动分发；保留有界 FIFO 和 close 的确定完成
语义。验收同步慢 Sink、重入 dispatch、立即 close、异常和队列溢出。

### F12（P2）：曝光 Target 收不到祖先 Scrollable 的滚动通知

状态：已修复，验证见第 12 节。下述为修复前证据。

[exposure_tracking.dart](../packages/ccrouter_analytics_flutter/lib/src/exposure_tracking.dart)
第 104 行把 NotificationListener 放在 Target 内，滚动通知沿祖先方向传播，不会进入位于
Scrollable 子树中的列表项 Listener。

实测 Target 起初位于屏幕外，随后滚入 `Rect(350,50,450,150)`，超过 dwell 时间仍为 0 事件。
建议订阅目标实际所属的 ScrollPosition/合适的上层 observer，处理依赖更新与解绑；验证真实
List/嵌套滚动、移出移入和销毁，而非仅手工派发通知或改变 child 高度。

### F13（P2）：Consent 拒绝时曝光仍被记为已经上报

状态：已修复，验证见第 12 节。下述为修复前证据。

同文件第 204 行忽略 `tracker.exposure` 的接受结果，总是置 `_hasReported = true`。
实测 deny 下 Target 可见，随后 grant 并重建同一 Target，仍为 0 事件。

建议区分“投递尝试”和“已接受事件”，在授权后的新有效测量周期重新判断；不回放授权前
的历史曝光。验收 deny→grant、revoke→grant、once、采样/节流拒绝与新的 dwell 周期。

### F14（P2）：Analyzer 对合法 Future 前缀/typedef 误报

状态：已修复，验证见第 13 节。下述为修复前证据。

[source_analyzer.dart](../packages/ccrouter_analyzer_plugin/lib/src/source_analyzer.dart) 第 617、
821 行使用源码字符串验证 Handler 返回类型。实测 `async.Future<void>` 和
`typedef Completion = Future<void>` 均被报 `ccrouter_handler_signature_invalid`，而
Generator 使用 resolved DartType，可以接受这些合法类型。

建议解析能唯一证明的 `dart:async` 前缀，对无法证明的 typedef 保守不报错或采用已解析类型。
使用相同的合法/非法输入矩阵校验 Analyzer 与 Generator 的一致性，避免提高配置噪音。

### F15（P2）：Analyzer Owner 判断丢失前缀，Quick Fix 未处理本地遮蔽

状态：已修复，验证见第 13 节。下述为修复前证据。

[component_dependency_analyzer.dart](../packages/ccrouter_analyzer_plugin/lib/src/component_dependency_analyzer.dart)
第 147 行只比末尾标识符。依赖 `right.SharedService` 却写 `wrong.ownerComponentId`，只要
末尾名字相同，即静默认为正确。实测 diagnostics 为空。

[contract_owner_index.dart](../packages/ccrouter_analyzer_plugin/lib/src/contract_owner_index.dart)
第 120–144 行证明 import 导出了正确常量，但没有排除同文件的同名错误常量。实测 Quick Fix
仍插入裸 `ownerComponentId`，实际绑定本地错误 Owner。Generator 最终会拒绝，IDE 却隐藏问题。

建议诊断与修复共用带 library/prefix/稳定值的符号证明；遇到歧义停止提供修复。补前缀同名、
本地遮蔽、多 import、const alias 和应用修复后的重新分析。

### F16（P2）：外部工程按 README 安装 Skill 后，必需引用断链

状态：已修复，验证见第 14 节。下述为修复前证据。

[README](../README.md) 第 1259 行只要求复制 integration Skill，但该 Skill 第 17、26 行
要求访问仓库 `docs` 和 sibling CLI Skill。即使复制两个 Skill，仍有 references 依赖框架
仓库外部的 `docs`；普通业务仓库未拥有这些文件。

建议把强制流程收进一个可独立安装的 Skill bundle；设计文档用稳定链接补充，安装说明列全
必要目录。用“复制到空白消费仓库后验证必需引用”验收，现有仓库内链接检查不能替代它。

### F17（P2）：Skill 仍有与当前能力冲突的指令

状态：已修复，验证见第 14 节。下述为修复前证据。

- [capability-decisions.md](../skills/ccrouter-integration-development/references/capability-decisions.md)
  第 42 行仍要求把 `contractBundle` 单独传给 initialize；当前只接收完整 Host Assembly。
- [CLI Skill](../skills/ccrouter-cli-development/SKILL.md) 第 58 行在列出 `analyzer status/doctor`
  后又禁止添加 `analyzer`，第 244 行仍将 DevTools Catalog 联动标为 future。

建议修正具体指导，并为文档示例/API/命令做可执行或结构化校验。上轮链接和状态收口不能
证明所有 reference 中的代码建议正确，本轮这些冲突仍应作为未修复任务。

### F18（P2，Demo）：Network Service 没有把 Dio 清理接入 Scope

状态：已修复，验证见第 12 节。下述为修复前证据。

[network_service.dart](../demo/modules/network/lib/src/network_service.dart) 第 43 行的
`DemoNetworkServiceImpl` 自建 `CCNetworkClient → Dio`，但未实现 CCDisposable，也未调用
client.dispose。Client 与 Backend 虽有 close 实现，Service 没有连通释放路径。

这是明确的 `not-disposed`，属于 Demo 所有权问题。框架只会释放已声明 CCDisposable 的对象。
建议 Service 实现并转发 dispose，采用可观察 Fake Backend 验证 shutdown 只关闭一次；
真实 HTTP Adapter 继续留在 Demo/应用层。现有 KV Service 已正确演示此模式。

## 4. 模板代码与开发体验：哪些值得继续简化

普通页面、Component、简单 Service、Command/Event/InitTask 已经具备有效的生成入口，
不建议再创建平行注册 API。主要重复信息集中在高级 Host 的 Shell 装配。

| 候选改进 | 当前重复/风险 | 推荐边界与成本 |
| --- | --- | --- |
| Catalog Route 挂载辅助 | 原 Demo `_route` 自行构建 Widget，另维护 binding/override，遗漏完整 Presentation | 已在 Demo 私有挂载对象中同源创建 route/binding，复用中立 Page Factory；不公开新 API |
| Outlet Key/Observer 配对 | 同一 Outlet 分散写 Key、Host map、Shell map、Observer list | 已用 Demo 私有对象配对复用；进入框架仍需真实第二个消费者证据 |
| Owner barrel 复用 | order/web 的 owner barrel 与 business barrel 重复 Route/Arguments 清单 | 已复用公共 barrel，仅补 Owner 标记；业务公开边界仍有显式 show |

Shell 树、分支顺序、导航策略、Provider 构造注入、Key、Scope、async initializer、InitTask
Gate/failurePolicy/timeout 都承载业务语义，应保留显式配置。组件 dependencies 与 capability
dependencies 分别表达组件关系和实际消费，可用可靠 Quick Fix 减少手工补写，不扫描源码
猜测并自动增加消费关系。

## 5. Analyzer 与 Skill 的改进顺序

以下保留改进顺序，已修复缺陷与可选后续增强分开记录：

1. F14/F15/F17 已修复，消除本轮复现的错误诊断、错误修复和错误接入指导。
2. 增加真正 Language Server 往返验证：unsaved overlay、生成文件 add/modify/remove、
   clean 后恢复、应用 codeAction 再分析。现有直调 Plugin 测试不能完整覆盖文件监听链路。
3. F15 已增加 resolved 声明 Library 与 namespace 证明，支持 re-export/alias；未知输入
   仍保守暂缓，后续只根据真实漏检扩展，不把缺少类型信息当成合法或非法证明。
4. 执行已有 Analyzer `install/upgrade/uninstall` 显式装配计划，维护固定来源、隔离版本、
   回滚和 doctor；保持可选，不让生成流程隐式改写 IDE 配置。
5. F16 已将对外 Skill 整理为两个相邻目录组成的完整安装包，按需读取参考资料。
   空白目录引用与关键示例验证已完成；进一步拆分长篇 implementation-patterns、真实 AI
   编码效果评估仍属于体验增强，不能以静态链接检查声称已验证 AI 行为。

暂不建议新增全局万能 Client、自动猜 Contract exposure、动态 Scope 或任意方法 Proxy，
这些不能直接解决本轮实际问题。

## 6. 核心价值逐项回归

下表保留原始审查时的判断；后续修复及验证范围见第 8–15 节，不据此把已修项再次列为待办。

| # | 核心价值 | 本轮判断 | 证据与待完成项 |
| --- | --- | --- | --- |
| 1 | 智能、可预测 | 部分满足 | 自动装配和稳定入口有效；F03/F04 削弱自动校验可预测性 |
| 2 | 简单易用 | 部分满足 | 普通接入较少样板；F14–F17 增加 IDE/AI 操作成本，Shell 仍有重复 |
| 3 | 功能覆盖真实场景 | 基础满足，组合缺口 | 五类能力齐备；F02/F08 表明组合流程仍会改变业务结果 |
| 4 | 可扩展性 | 基础满足 | Backend/Provider/Sink 边界清晰；外部分发 F04 必须修复 |
| 5 | 可测试 | 基础满足，矩阵需扩展 | 现有 739 项测试通过；新增交叉边界复现揭示用例缺口 |
| 6 | 最小公开 API | 基础满足 | Business/Host/Generated SPI 分离；改进优先复用现有入口 |
| 7 | 编译期校验与类型安全 | 未完全满足 | F03/F04/F09、F14/F15，生成和 IDE 证明范围需一致 |
| 8 | 非侵入式 | 基础满足，退出保护有缺陷 | 仍支持附着已有后端；F02 违反页面本地 PopScope 决策 |
| 9 | 安全降级回退 | 未完全满足 | F03 不同路径验收结果不同，F04 对合法分发误拒绝 |
| 10 | 明确生命周期 | 未完全满足 | F01/F07 和 Demo F18 存在具体清理/取消缺口 |
| 11 | 安全、有界、可溯源 | 未完全满足 | F05/F10/F11/F12/F13，授权、不可变与采集边界需补强 |
| 12 | 并发安全 | 未完全满足 | F06 readiness 等待环、F07 shutdown、F11 重入前状态建立 |
| 13 | 性能与稳定 | 有基准，正确性门槛未闭环 | 现有性能和回收基准有效；先修 F01–F05，继续同机趋势采样 |

739 = Flutter/框架/Demo 等 418 + Generator 272 + Analyzer 49。这个数不包含静态分析和
本轮预期失败的缺陷复现。不可把它解释为所有平台、所有输入或无内存泄漏证明。

## 7. 推荐实施顺序与完成定义

以下为原实施顺序；F01–F18 均已修复。第 7 项的 Demo 私有减负已完成，新增框架 helper 仍按
实际消费者收益决定；第 8 项执行范围与未覆盖平台见第 15–16 节。后续独立任务继续补失败
用例、修复和回归，按授权提交。

1. **生命周期与返回保护：F01、F02。** 验证异常隔离和多层 Pop 决策，避免资源遗漏与数据丢失。
2. **外部分发和生成准确性：F04、F03、F09。** 建立真实 producer/consumer 样本，再统一
   内容证明与默认常量编码；完整与缓存路径逐字节/错误语义一致后再测性能。
3. **Analytics 安全与分发：F05、F10、F11（已完成）。** 授权代次、不可变快照、异步调度
   同属 Dispatcher 投递边界，一批修复并逐项独立测试，保持应用 Sink 边界。
4. **Runtime 组合流程：F06、F07、F08（已完成）。** 补并发根依赖环、shutdown during interception、
   Defer+Host/Outlet/Extra 组合矩阵。
5. **采集和 Demo 生命周期：F12、F13、F18。** 用真实滚动 Widget 和 Fake Backend 验证。
6. **IDE 与 AI 接入准确性：F14–F17。** 先修规则、修复和安装可用性，再缩短按需指南。
7. **模板减负。** 先做 Demo 私有复用，确认第二个真实 Host 的收益后，再评估窄的 Host helper。
8. **统一验收。** 全量 analyze、测试、cached/reference、独立分发、真实 LSP、Skill 空白
   消费者演练和性能/资源回收回归；对生命周期/返回改动补 macOS/iOS 实机或模拟器测试，
   不以 Widget 测试替代平台结论。

实现方案以内部修复和既有 SPI 复用为首选；只改文档不能解决上述实现缺陷，批量增加新
公开 API 也不能替代边界测试。已延期的架构 2.0 能力继续保持原有触发条件。

## 8. F01/F02 修复验证（2026-10-03）

- 新增 14 项确定性回归：
  [cancellation_cleanup_test.dart](../packages/ccrouter_test/test/cancellation_cleanup_test.dart)
  8 项；[integration_test.dart](../packages/ccrouter_test/test/integration_test.dart) 2 项；
  [adapter_test.dart](../packages/ccrouter_test/test/adapter_test.dart) 4 项。
- 修复前取消清理用例复现后续通知丢失、Scope/Runtime 清理中断、关闭重入和 Facade
  提前初始化；PopScope/Form 两条用例复现页面被误移除。修复后均通过。
- 生命周期覆盖真实 App/Session/Route Service、逆序 dispose、取消与 dispose 同时出错、
  重复/重入关闭、首个错误原始 StackTrace、Session 重开、Route 结果和 disposed 事件。
- 返回保护覆盖框架 allow/deny 与本地拒绝、typed Future 保持/完成、Foreign 确认弹窗、
  legacy willPop 等待时目标变化及异常、StatefulShell 双 Outlet 隔离、并发返回只完成一次。
- 与第 1 节相同的框架/Flutter/Demo/模块/DevTools 测试命令通过 **432/432**，包含既有
  Cupertino 默认侧滑、有 Guard 禁用侧滑以及 leak-tracker 资源回收用例。
- Workspace `fvm dart analyze` 通过，无问题。
- Runtime 1000 次循环通过，P50/P95 为 83/162us，每周期 Entry/Pending/Backend 归零。
  RSS 样本增加约 32.4 MiB，仅为短 JIT 趋势观测，不作为长期 Heap 无泄漏证明。
- 完整生成检查首次发现本次框架源码变化导致 Portable State 过期；使用官方生成器更新
  11 份 `ccrouter_generation_state.json`。仅工具、依赖解析和合成摘要变化，业务生成源码、
  metadata 和 managed output 摘要不变；未手工编辑生成物。
- 刷新后的 `generate demo --no-cache --check --profile` 与缓存 `--check --profile` 均通过，
  内部耗时分别为 3606ms、312ms；这只验证当前 Demo，不解除 F03/F04 的外部依赖缺陷。
- 文档检查和 `git diff --check` 通过；新增审查报告的本地引用另行验证，无断链。
- README、Service 生命周期设计、Cupertino 返回设计与集成 Skill 已同步本次行为。

本轮没有新增公开 API，没有重新执行 Generator/Analyzer Plugin 的独立全量套件，也没有
重跑 macOS/iOS 真机手势或长期 Heap 测试；不将已有 Widget 测试解释为本轮真机验证。
第 8 节仅记录 F01/F02；后续 F03/F04/F09 的修复见下节，其余仍待修复。

## 9. F03/F04/F09 修复验证（2026-10-03）

- [portable_distribution_test.dart](../packages/ccrouter_test/generator_test/portable_distribution_test.dart)
  建立独立 producer/consumer，执行真实 Pub 解析、本地 Git 提交依赖和 Git archive 解包后的
  Path 消费。消费者解析图不包含 producer 的 devDependencies，且断言未安装作者专用的
  `test` Package；完整生成、缓存检查与
  `--no-cache --check` 均通过，producer/consumer 的 `dart analyze lib` 均无问题。
- 外部组件源码修改、Service 生成源码修改/删除、传递 Path DTO 修改分别比较缓存与完整
  路径，均以稳定的 `authoredInputMismatch`、`managedOutputMismatch` 或
  `resolutionMismatch` 拒绝。恢复原始内容后检查通过，外部原始生成物逐字节不变。
- 删除生成文件时发现 Builder 先行可能触发 build_runner 对只读依赖的清理异常，因此新增
  Builder 前置状态校验。聚合阶段保留二次校验，不把前置成功当作构建期间内容不变的证明。
- [service_generator_test.dart](../packages/ccrouter_test/generator_test/service_generator_test.dart)
  新增 `$name`、`${expression}`、引号、反斜线、换行、List、Set 和嵌套 Map 的默认值回归，
  解析生成 Dart 库并求值常量，确认内容不变。修复前常量无法求值；修复后通过。
- 分发样本只验证本地 Git 和源码归档，不宣称完成真实远端 Pub 发布/下载验证。测试复用
  已下载 Hosted 依赖，Git clone 和临时 Pub 数据放入测试自有临时目录。
- 这批修复不增加公开 API，不实施 P6 的语义摘要、注释过滤或公共依赖失效粒度优化。
  README、集成 Skill 和生成操作指南同步了实际校验边界。
- 生成器整套回归中的其余 **273 项通过**；新增分发夹具首次放在非规范目录而未生成目标
  Service 文件，改为 `lib/src` 并补上生产者/消费者 Dart 分析后，单独复跑通过。
  框架/Flutter/Demo/模块/DevTools **432/432 通过**，Workspace `fvm dart analyze` 无问题。
- 最终 Demo `generate --no-cache --check --profile` 通过，内部耗时 **3734ms**，其中
  build_runner **1778ms**；三次快速检查 **436/422/431ms**，均确认产物无需更新。
  相比第 8 节历史单次样本 3606/312ms，快速校验开销增加；这不是同轮 A/B 或 P95 结论。
  扩大外部验证范围是准确性修复，不以跳过校验追回这部分耗时。
- 官方生成器刷新 11 份 Portable State，仅工具、解析及合成摘要变化，业务 Dart、metadata
  和 managed-output 摘要未变。文档链接检查通过；Skill YAML 另行解析通过，系统 Python
  缺少 PyYAML，因此 skill-creator 的 Python 快检脚本未能运行，不计为已通过的检查。
- 核心价值复核：F03/F04 补齐内容证明与安全回退，F09 补齐类型安全默认值；保留只读依赖
  所有权，不增加业务 API，且有真实消费者和完整路径对照。F05–F08、F10–F18 仍待处理，
  本轮不重跑独立 Analyzer Plugin、真实设备或长时间 Heap，不宣称全框架问题已清零。
- 3x 五类能力拓扑复测通过：18 组件、90 Route，个人/团队增删的 277 份受管输出均与
  参考路径逐字节一致；可信新增和删除继续复用聚合路径。wall time 为稳定检查 0.842s、
  个人新增 6.472s、团队预生成新增 2.698s，详见[性能报告](CCRouter-generator-performance-report.md#66-f03f04f09-准确性修复后的-3x-回归)。

## 10. F05/F10/F11 修复验证（2026-10-03）

- 根因分别是授权仅在入队时检查、属性列表保留外部可变引用、async 函数在首个 await 前
  同步调用 Sink。仅由应用 Sink 补检查会重复策略且无法保证所有消费者；本次选用
  Dispatcher 内部修复，不增加公开 API，不改变应用供应商 Adapter 的所有权。
- [analytics_dispatcher_regression_test.dart](../packages/ccrouter_test/test/analytics_dispatcher_regression_test.dart)
  新增 **12 项**确定性回归，覆盖 revoke/re-grant、disable/re-enable、Sink 错误回调内撤销、
  调用方/Sink 修改列表、首个写入异步、重入 FIFO、重复/重入 close、末尾完成监听器入队
  以及首次写入前的队列溢出。先用失败用例复现，再修复；加上原有 Pure Dart 测试共
  **23/23 通过**。
- 第 1 节同一框架/Flutter/Demo/模块/DevTools 回归命令 **444/444 通过**。首次回归中曝光
  断言失败、滚动用例等待未推进的 Timer；改为显式推进 Widget 假时钟后通过，没有删除
  去重断言或回退异步分发。本次没有修复 F12/F13 的曝光采集逻辑。
- Workspace `fvm dart analyze` 无问题。README、Analytics 设计和集成 Skill 同步了
  不可变属性、授权代次、事件循环调度、Composition Root 等待 close 的语义，以及 Sink
  不得等待自己的 Dispatcher close 的限制。异步调度不是后台线程，耗时同步 Sink 仍会
  占用 UI isolate；已开始写入的取消由应用 Adapter 负责。
- 官方生成器刷新 **3 份** Portable State，业务 Dart、metadata 和 managed-output 摘要未变。
  完整参考 `generate demo --no-cache --check --profile` 通过，内部 **3473ms**，其中
  build_runner **1597ms**；缓存检查同样通过，内部 **495ms**。本次未修改 Generator/Analyzer，
  不重复它们的独立全量套件。91 份 Markdown 的文档检查、Skill YAML 解析和
  `git diff --check` 通过；Python Skill 快检仍因环境缺少 PyYAML 未运行。
- Analytics 5000 次连续入队、capacity=64：入队 P50/P95 **1/3us**、accepted=5000、
  dropped=4936、peak=64、close 后 pending=0。首个事件现在也先入队等待，因此一次
  不让出事件循环的突发只能保留最后 64 个；与旧同步首个 Sink 的 4935 丢弃数差 1 属于
  时序修正，不是容量越界。RSS 增加 **2850816 bytes**，仅作短 JIT 趋势，不证明长期无泄漏。
- 核心价值：修复授权与数据快照边界、避免业务调用栈同步进入 Sink，保持确定性 FIFO、
  有界队列和异常隔离；未新增业务配置或公共 API。当前剩余 **10 项 P2**：
  F06/F07/F08/F12/F13/F14/F15/F16/F17/F18。下一批为 Runtime 组合流程；本次未重跑真实
  平台和长期 Heap 回归，不宣称全框架审查问题已清零。

## 11. F06/F07/F08 修复验证（2026-10-03）

- 本轮采用内部 Runtime 修复，无新增业务 API。只在应用层加超时无法解除共享 Service
  等待环，也不能保证关闭后不分发导航；单纯保存 URI 无法还原 Typed Extra，因此不采用
  调用方 workaround 或让业务手工重建原请求的方案。
- [runtime_test.dart](../packages/ccrouter_test/test/runtime_test.dart) 新增 **6 项**：独立 A/B 根
  等待环、共享 DAG 与重叠等待、不同 Runtime 同类型 Provider、三节点带 Key 的 Session
  等待环及新 Session 重建、newInstance 递归、调用者超时移除等待边而保留共享初始化。
  修复前 A/B 用例以测试兜底 TimeoutException 失败；修复后以标准循环依赖错误及时结束。
- Scope 在调用 initializer 前发布 readiness Future 与等待边；等待关系有引用计数，
  单次等待完成/取消/超时移除其边，initializer 完成或 Scope 取消清空出边。
  newInstance 继续用实际 Runtime/Scope/Provider 身份的活跃祖先检测递归；没有增加全局
  Service 实例表或业务对象缓存。初始化失败保持当前 Scope 内稳定，不隐式重试。
- [navigation_test.dart](../packages/ccrouter_test/test/navigation_test.dart) 新增 **12 项**：
  关闭后晚到的 proceed/defer/redirect、Failure Policy 等待、取消监听器异常与晚到错误、
  拦截器内部关闭、required/optional Extra 身份、typed/dynamic 请求切换 active Host、
  恢复后重定向与再次 Defer、原请求/恢复请求共享返回类型校验。关闭和 Extra 用例先失败
  复现，再修复；假 Adapter 明确声明嵌套 Outlet 能力后验证 Host/Outlet 隔离。
- Interceptor/Failure Policy 等待关联 App cancellation，终态撤销监听并取消 Deadline Timer；
  await 之间也复核关闭状态。业务 Future 无法被强制中止，但其晚到结果不再进入下一个
  Interceptor、Adapter 或失败恢复。取消 Listener 抛错记录安全诊断，不掩盖导航取消。
- Typed resume 重新 encode 校验原 arguments，保留原 arguments/Extra 对象；dynamic
  resume 重新匹配/decode。原具体 Host 与调用级 placement 固定，重定向目标的显式
  placement 仍优先。返回校验、navigationId、操作与原结果通道跨再次 Defer 保持一致。
- Pure Dart Runtime/Navigation 合计 **149/149 通过**，第 1 节全量框架/Flutter/Demo/模块/
  DevTools 命令 **462/462 通过**，包含已有取消、超时、资源释放和 leak-tracker 用例。
  完整回归后补强关闭与错误同时发生时的取消优先级，再跑上述 149 项通过。
- Service 基准 10/100/1000 Provider 均通过实例回收断言。1000 Provider 样本的
  singleton lookup P50/P95 **5/5us**、newInstance readiness **17/36us**、dispose
  **226/858us**；只记录当前 SDK/JIT 样本，不与历史单次样本混作 A/B 加速结论。
- Runtime 1000 次 Push/Pop、每 100 次重建通过；每周期 Entry/Pending/Backend 归零，
  P50/P95 **46/95us**，RSS 增加 **33570816 bytes**，只作趋势观测，不证明长期 Heap 无泄漏。
- README、Route/Service 设计、任务清单与集成 Skill 同步边界。官方生成器刷新 **8 份**
  Portable State，仅依赖解析和合成摘要变化，业务 Dart、metadata 和 managed-output
  摘要保持不变；本轮未修改 Generator/Analyzer，不重跑独立完整套件。
- 最终 Workspace analyze 无问题；完整参考生成检查 **1819ms**（build_runner **824ms**）、
  缓存检查 **223ms** 均通过。91 份 Markdown 文档检查、Skill YAML 解析与
  `git diff --check` 通过。Skill Python 快检依赖的 PyYAML 仍缺失，不计为已执行。
- 核心价值：修复并发等待、生命周期取消、类型安全与多 Host 确定性，保留原 Owner/Scope
  和最小 API 边界，没有引入业务配置。当前剩余 **7 项 P2：F12–F18**，下一批为曝光采集
  与 Demo Network 释放。本轮未重跑 macOS/iOS 真机或长期 Heap，不宣称已完成所有平台验收。

## 12. F12/F13/F18 修复验证（2026-10-03）

- 先复现：真实祖先滚动后曝光仍为 0、Consent grant 无业务 rebuild 时仍为 0；
  generated Network Service 所在 App Scope 关闭后认证状态仍存活。
- 方案取舍：要求业务反复 rebuild 会增加模板代码且无法统一取消旧 dwell；全局扫描 Widget
  或轮询会增加采集与性能风险。本轮在可选 Flutter Target 内订阅祖先 ScrollPosition，按帧
  合并测量，使用 View 和祖先 paint clip 交集；Core 不承担 UI 几何检测。
- 跨 Pure Dart Dispatcher 与 Flutter Target 新增窄的 `addPolicyListener`，仅通知策略/关闭
  状态，无 payload、不改变投递结果。同步回调异常隔离、拒绝重入策略更新；detach 调 remover，
  close 清空监听。Timer、ScrollPosition Listener、Binding Observer 与 Target 生命周期对称，
  后帧回调使用弱引用，避免无后续帧时保留已销毁 State。
- `once` 只在 Dispatcher 接受事件后生效；deny/background/detach 不积累 dwell，grant/resume
  后重新计时。采样/黑名单/节流拒绝不占 lifetime once，也不逐帧重试；授权变更不回放已接受事件。
- [exposure_regression_test.dart](../packages/ccrouter_test/test/exposure_regression_test.dart)
  新增 **10 项**真实 Widget 回归：祖先滚动与 50% viewport 裁剪、嵌套同轴滚动、中途移出重置、
  最近 ScrollPosition 替换、GlobalKey 迁移、deny/grant、revoke/grant、过滤拒绝、后台重建和关闭。
  [analytics_dispatcher_regression_test.dart](../packages/ccrouter_test/test/analytics_dispatcher_regression_test.dart)
  新增 **3 项**策略观察边界：解绑/异常/重入策略更新、终态只通知一次、通知中关闭。
- Demo Network 保留生成器要求的无参 generative constructor；增加测试用 Backend 注入入口，
  实现 `CCDisposable` 并转发 Client → Dio 释放。释放 Future 在调用 Backend 前发布，重复/重入
  dispose 共享结果；认证字段和日志及时清理，关闭失败或晚到日志不能重新填充。
  不把 Dio、HTTP SPI 或业务网络策略上移到框架 Package。
- [network_lifecycle_test.dart](../demo/test/network_lifecycle_test.dart) 新增 **3 项**：通过 Host
  公开 Assembly 选取真实生成的 Manifest，验证 App Scope 释放，以及 Fake Backend 延迟关闭、
  重复/重入关闭、失败和晚到日志。Demo 显式声明 `ccrouter_test` 开发依赖，测试不绕过跨包生成
  文件边界，也不向组件业务 barrel 暴露 Registrar。
- 全量框架/Flutter/Demo/模块/DevTools **478/478 通过**；Pure Dart Analytics **26/26 通过**。
  最后补强 Backend 同步重入关闭后，Network 定向 **3/3 通过**。Workspace analyze 无问题。
- Analytics 5000 次事件、capacity 64 压力基准通过：入队 P50/P95 **0/1us**，峰值队列 **64**，
  丢弃 **4936**，关闭后待处理 **0**；RSS 增量 **2834432 bytes**。只作当前 SDK/JIT 样本，
  不据此宣称 UI 测量零开销、优化加速或长期 Heap 无泄漏。
- 官方生成器刷新源码位置、关联 Catalog/Bundle 指纹和 Portable State；Service API、Proxy
  与注册逻辑没有漂移。最终完整参考检查 **2158ms**（build_runner **1149ms**）、缓存检查
  **243ms** 均通过。91 份 Markdown 文档检查、Skill YAML 元数据解析和 `git diff --check`
  通过；Skill Python 快检的 PyYAML 依赖仍未安装，不计为已执行。
- 核心价值：减少应用手工 rebuild；明确接受与投递语义；隐私撤销不重放；观察者异常隔离；
  Scope 资源所有权完整；生成服务契约与业务调用无需改写。README、设计、Demo 与集成 Skill
  同步更新。剩余 **4 项 P2：F14/F15 Analyzer、F16/F17 Skill**。
- 几何检测不处理任意 Overlay 遮挡、opacity 或无通知的自定义布局动画；本轮未跑真机矩阵、
  长时间 Heap 或独立完整 Generator/Analyzer 套件，不把自动化通过视为这些范围已验收。

## 13. F14/F15 与 Service 生命周期诊断修复验证（2026-10-03）

- 根因与取舍：源码字符串不能证明 typedef、import prefix 或 Owner 常量身份；扫描整个
  Workspace 或另建解析会话会增加编辑成本。采用 Analysis Server 现有会话按需解析当前文件，
  诊断与 Quick Fix 共用类型、声明 Library 和常量值证明；不持有长期 resolved AST 缓存。
  解析失败、Dart ERROR 或无法证明的依赖表达式退回保守检查，Generator 仍是最终校验入口。
- F14：Event/InitTask Handler 接受真实 dart:async 的前缀及 typedef，拒绝同名应用类型和
  非法返回值；required InitTask 的异步 timeout 规则也识别别名。对照测试发现 Generator
  已支持 `Future<void>?`，因此 Analyzer 与该既有语义对齐，没有收紧 Generator。
- F15：按真实 Contract 声明来源匹配 Owner，支持前缀与 const alias；本地遮蔽、重复前缀、
  多 import 歧义和 deferred import 不提供未经证明的修复。未知计算依赖不当成缺失 Owner。
  await 解析后复核当前 overlay，过期结果不发布诊断或编辑。
- Service 新增两类 warning：已存在兼容实例 `dispose()` 但未实现 `CCDisposable`；直接创建
  自有可释放资源但没有接入 Scope。前者仅在已有无歧义 import 时提供补接口的 Quick Fix，
  保留原方法体和现有 implements；后者只提示所有权检查，不生成空 dispose 或猜测释放次序。
  dispose 签名限于 void、非 nullable Future<void>/FutureOr<void>，不套用 Handler 的宽松规则。
- 资源证明仅覆盖私有 final 实例字段的直接初始化、构造 initializer 和构造体赋值；排除借用
  注入、共享值、任意 factory、static 和其他实例赋值。辅助方法、复杂控制流、Dio 等第三方
  资源以及清理方法内部是否完整，不在当前静态规则保证范围内；不宣称可检测所有内存泄漏。
- 独立 Analyzer **78/78 通过**，独立 Package 与 Workspace analyze 均无问题。新增真实
  AnalysisContextCollection（加载真实 Contracts 源码）与 Plugin 会话回归，覆盖修复后重新
  分析、overlay 更新丢弃旧结果、继承 dispose/CCDisposable 和资源所有权误报边界。
- Generator Event 对照矩阵 **13/13 通过**；同批 InitTask/Service **45 项通过**。
  框架/Flutter/Demo/模块/DevTools 全量 **478/478 通过**。本地 bootstrap analyze 与 loader
  可执行文件编译通过。后续按用户授权提交并推送 `a275d1d`，Demo 固定 Git ref 已更新到该
  完整 SHA；IDE 需要重启 Analysis Server，新旧运行会话不能仅凭 manifest 推断。
  远端 bootstrap 临时副本的 `pub get --enforce-lockfile`、analyze 与 loader 编译均通过，
  确认解析到 Git 缓存中的该 SHA。Demo `analyzer status` 为 healthy；本机 `doctor` 检测到
  旧 Analysis Server plugin-manager 缓存而停止，未计为 doctor 通过。保留活动 IDE 状态，
  待停止 Analysis Server、移走对应旧缓存并重启后重跑 doctor。
- 编辑基准包含 100/1000/3000 被动类与 20 次语义编辑，每次必须命中正确的 Service 诊断。
  CCRouter 语义规则 P95 分别为 **338/995/3724us**；复用的 Analysis Server 解析 P95 分别为
  **5176/23538/35987us**。首次冷解析约 **875ms**，与规则成本分开记录。这只是当前 SDK/JIT
  样本，不能推导真实 IDE 全局 P95 或与旧版相比的加速比例。
- `generate demo --no-cache --check --profile` **2935ms**（build_runner **1908ms**），
  缓存 `--check --profile` **429ms**，均通过，业务生成物无变化。
- README、IDE 设计与 Integration Skill 同步说明诊断和修复边界。核心价值侧保持编译期
  类型证明、最小 API、低配置和明确资源所有权，不改变业务 Runtime 行为；新增 helper
  保留在插件内部。剩余 **2 项 P2：F16/F17 Skill 安装完整性与指导一致性**。
- 本轮未执行真机矩阵或长时间 Heap 分析。Skill Python 快检因缺少 PyYAML 无法运行，
  使用 YAML 元数据解析与仓库文档检查验证，不将替代检查描述为 Python 快检通过。

## 14. F16/F17 Skill 分发与指导修复验证（2026-10-03）

- 根因：仓库内 Markdown 链接可达不代表消费工程安装后可达；示例和文字指导没有随 API
  同步。独立复制测试先复现 **6 处越界引用**，不会从原框架仓库补找文件掩盖问题。
- 方案取舍：整份复制框架 docs 会放大安装包并混入计划能力；只把必需步骤换成远端链接
  又不能离线工作。保留 Integration/CLI 两个互补 Skill，明确同版本、完整、相邻安装，
  将生产场景评估和 Analyzer bootstrap 必需流程收进包内；远端设计文档仅作可选背景。
- 修正 Host 初始化只传原子 Assembly、已支持的 `analyzer status/doctor` 与未实现写入型
  命令的区分，以及已经完成的 DevTools Catalog/Runtime 联动；保留用户已有授权，不因
  Skill 重复要求批准同一项工作。消费工程只更新自己的说明，不被要求编辑框架缓存/文档。
- 修正 Service 示例遗漏泛型实现、跨组件调用误用直接 lookup、公开 DTO export，以及
  Route 页面示例遗漏 Widget build 和凭空假设导航 Facade 名称的问题。
- 新增 `tool/skill_bundle_check.dart`：只复制两个分发目录到临时消费目录，检查必需引用
  不越界，并调用真实 CLI `--help` 核对命令和命令级参数；不执行任何示例中的写入命令。
  `tool/test/skill_bundle_check_test.dart` **8/8 通过**，包括单独安装遗漏、外部存在但越界、
  缺失参考、可选远端链接、跨 Skill 链接、虚构命令/参数与真实 CLI 矩阵。
- 从 Markdown 提取 Host、普通 Route/Extra 页面和泛型 Service 示例，使用实际 Demo
  依赖执行 Dart analyze。故意恢复旧初始化参数、删除泛型实现时均被拒绝，证明校验没有
  静默跳过文件。它验证选定示例的编译语义，不宣称验证所有片段或 AI 的实际编码行为。
- 两个 Skill 的 YAML 元数据经 Ruby 解析通过；Python quick_validate 仍因 PyYAML 缺失未执行，
  没有擅自安装系统依赖。README 已同步完整安装结构、验证方式和版本边界。

## 15. 修复后核心价值与收尾边界（2026-10-03）

最终自动化收尾 **844 项通过**：框架/Flutter/Demo/模块/DevTools **478**、Generator
**280**、独立 Analyzer **78**、Skill 分发与示例 **8**。Workspace 和独立 Analyzer
Package analyze 均无问题；Demo 缓存与 `--no-cache --check` 均通过，6 个组件、33 条路由、
11 个生成 Package 的受管产物无变化。两种生成检查与其他测试并行运行，耗时不作为新的
性能基准。91 份已跟踪 Markdown 链接检查及包含新增参考文件的独立 Skill bundle 检查通过。

| # | 约定 | 修复后的证据与边界 |
| --- | --- | --- |
| 1 | 智能、可预测 | 生成分发与默认值证明统一；未知符号不猜测，显式报错或保守暂缓 |
| 2 | 简单易用 | 合法类型不误报、Owner/销毁 Quick Fix 可用，Skill 必需指导可独立分发；高级 Shell 配置仍由 Host 决定 |
| 3 | 真实场景能力 | 修复 PopScope、Defer/Host/Extra 和曝光组合行为，未新增万能接口或占位能力 |
| 4 | 可扩展性 | 保留 Backend/Provider/Sink 分层，修复 Git/Path 分发校验，不要求业务依赖内部实现 |
| 5 | 可测试 | 补失败复现、组合生命周期、真实 Plugin 会话、独立安装和可编译示例；真实 LSP 文件监听端到端仍需扩展 |
| 6 | 最小 API | Analyzer helper 保留内部；本批 Skill 检查位于维护工具，不增加业务 API |
| 7 | 编译期与类型安全 | Generator/Analyzer 对合法类型与 Owner 的证明对齐，Runtime 继续保留最终契约校验 |
| 8 | 非侵入式 | 页面本地 PopScope 决策有效，Skill/插件可选，插件不可用不改变应用导航或生成门禁 |
| 9 | 明确回退 | 完整和缓存生成路径共同校验内容；无法证明的 IDE 修复不提供自动编辑 |
| 10 | 生命周期 | 异常隔离、取消清理、Network 嵌套资源与曝光监听有回归；静态诊断不承诺发现全部泄漏 |
| 11 | 安全可观测 | Consent 代次、payload 不可变、接受/投递分离和有界队列已修复；应用仍拥有业务日志与同意策略 |
| 12 | 并发安全 | readiness 等待环、shutdown、异步回调及旧 overlay 结果均有确定性保护与回归 |
| 13 | 性能稳定 | 保留精确内容证明、现有压力与规模基准；本批没有改热路径或宣称新的速度提升，长期趋势仍须持续采样 |

本轮确认的 18 项缺陷已关闭，不等于框架绝对无缺陷。仍需分别处理：

- 本机 Demo Analysis Server 的旧 plugin-manager 缓存与 Service Quick Fix 已在后续本机验收
  中闭环，见第 16 节；不据此扩大为全部 IDE 或规则验收。
- 完整真实 LSP 文件监听/codeAction 往返、macOS/iOS 返回手势和真实平台矩阵、长期 Heap/RSS
  趋势；现有自动化不能替代这些结论。
- Demo 模板减负已完成，生成器 P6 本轮仅做收益/边界评估；Analyzer 写入型安装命令、正式
  发布门禁和框架级 Host helper 仍按独立计划和授权推进，不自动开始架构 2.0。

## 16. 本机 IDE 验收与 Demo 模板减负（2026-10-03）

本机 Android Studio 已实际显示 `ccrouter_service_disposable_missing`，应用 IDE Quick Fix 后
补入 `implements CCDisposable`，告警消失。远端规则仍固定 `a275d1d`，未为跟随 HEAD 更新。
临时验收文件已移出工作区；旧缓存移到 `/tmp/ccrouter-analyzer-cache-2830316-20261003`
备份，没有清空其它 IDE/插件/Pub 缓存。

验收暴露并修正 CLI 排障缺口：Dart 3.11 复用整个路径哈希条目，只移动其 `analyzer_plugin`
子目录会导致入口缺失，旧 doctor 又漏检此状态。doctor 现在只定位当前 bootstrap 的准确
缓存条目，比较 manifest/入口并拒绝残缺，提示备份整个条目，不按同名插件误判其它 Host。
规则 Package 没有改动，无需更新 Demo 的 Analyzer Git pin。

Demo 私有装配把每条 Shell Route 与 binding/override 同源创建，Presentation 交给现有
`CCFlutterRouteFactory`；Key/Observer 由同一对象配对，Shell 树、相对路径、分支策略和
自适应面板仍由 Host 显式拥有。order/web Owner barrel 复用业务 barrel，生成后的
`publicLibraries` 保留明确 `show` 的业务入口；没有把 Owner 标记暴露给业务。

本轮保留准确性与生命周期边界：不更改 Runtime、Adapter 所有权或业务 API，不伪造 root
placement 绕过 Assembler 校验，不给未挂载的 Adaptive Navigator 添加 GoRouter Observer。
新增 Shell 测试覆盖 Cupertino、透明页、Dialog、BottomSheet、Path/多值 Query/Extra、
Outlet 和返回结果；既有测试继续验证 managed Entry、分支保持、Foreign Popup 和多 Host。

验证结果：本轮 **110 项**专项/回归通过（Demo **46**，含 4 项新增 Presentation 与固定 seed
Monkey；Analyzer CLI **13**；Workspace Validator **51**）。Workspace analyze、修正后的
本机 doctor、缓存 `generate --check` 和 `--no-cache --check` 均通过；两种生成检查未产生
产物差异。92 份 Markdown 链接、独立 Skill bundle/实际命令和 Skill YAML 检查通过。
系统及内置 Python 均缺 PyYAML，`skill-creator` 通用验证脚本未能运行，已使用仓库分发检查
与 Ruby YAML 解析补充验证，未修改系统 Python 环境。没有把上一轮 844 项测试计入本轮数量。

P6 评估已纳入 build_runner 优化计划第 12.5 节。既有完整字节 SHA-256、失效传播和参考
路径保持不变，当前仍未实现 P6-1/2/3。完整跨 IDE 文件监听/codeAction 矩阵、平台手势和
长期 Heap/RSS 观测仍未在本轮完成。

## 17. 真实 Analysis Server 协议回归与监听修复（2026-10-03）

新增真实 Server 回归先复现：创建 Route 生成库后，源码仍保留 missing-output 告警。
根因是插件把原始磁盘事件交给 Analyzer 后，只使用其 Dart import 依赖图返回的 affected
paths；生成注册库没有被声明源码 import，因此确定性映射没有执行。另一个缺口是插件只
声明关注 Dart，Owner JSON metadata 变化没有进入失效链。

修复在插件内部保留原始输入，先收集确定的声明/消费源码，再按当前 Context 分发刷新；
关注路径只增加准确的 Package metadata 文件，不扫描任意 JSON。分析根替换前清理借用的
Context 和有界索引，不新增后台 watcher、Timer、业务 API 或 Runtime 行为。

新增 **5 项**端到端回归，使用 SDK 自带 JIT Analysis Server 的真实子进程，覆盖：

1. Legacy 未保存 overlay、移除恢复、Service Quick Fix 应用和快速连续编辑。
2. LSP diagnostics/codeAction/didChange/didClose 往返与修复后无 Dart ERROR。
3. Legacy 下五类能力生成文件新增、修改、重命名、删除和重建。
4. LSP 下相同磁盘矩阵；相同诊断被协议去重时，不强求重复通知。
5. 共享 Dart Workspace 的跨包 Owner metadata 增删/修改，以及 Contract 常量修改。

完整独立插件测试 **83/83 通过**，独立 Package analyze 无问题。Demo 缓存和无缓存
`generate --check` 均通过，受管生成物无变化；92 份 Markdown 与独立 Skill bundle/CLI
指导检查通过。没有重跑上一轮 844 项或真机矩阵，不把文件 fixture 写入等同于执行
`clean/generate`。本轮日志中的生成耗时包含并行检查影响，不作为性能提升证据。

剩余边界：

- 测试加载本地插件源码，不经过 Pub/远端 bootstrap；Demo 仍固定 `a275d1d`，本次修复需
  后续推送、更新完整 ref、doctor 验证和 IDE 重启才能进入该集成。
- Dart 3.11.5 独立多根工程同时冷启动可创建同插件的多个 isolate，分别持有部分根，导致
  跨根事件不能刷新另一实例。已记录为 SDK/集成边界；共享 Workspace 测试通过不代表
  独立多根冷启动已通过，不能通过读取未受管根或增加全仓库轮询掩盖它。
- JIT 测试 loader 不验证 AOT 包装和用户缓存复制；这些仍由 doctor/loader smoke 和真实
  IDE 验收负责。无 manifest 的测试 loader 不能作为应用装配模板。
- Analyzer 写入型 CLI 和 P6 失效归因仍未在本项实施，继续按独立任务推进。
