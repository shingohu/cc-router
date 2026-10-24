# 已结束调用、同步交付与多次 Resume 扩展审查

> 状态更新：两项缺陷均已修复并进入默认回归，见
> [调用链所有权与同步交付修复报告](../20261023-completed-invocation-fixes/report.md)。
> 以下保留修复前审查及原始失败证据。

2026-10-23；工作树 `managed-navigation-runtime/cc-router`；分支
`codex/managed-navigation-runtime`。本轮只新增测试和审查记录，未修改生产实现、
公开 API、Demo 代码或生成物，未提交或推送。
前轮 Session/Resume 修复仍保留且通过回归；以下是不同终态组合的新增发现。

## 审查发现

### P1：成功返回的 Session 方法留下的回调仍可进入新账号

- 位置：`packages/ccrouter_core/lib/src/runtime_host.dart:2667` 和 `2514`
  的调用清理，及同文件 `2170` 的解析准入。
- 触发：Session A 的普通同步/异步 Service 方法启动一个等待 gate 的后台 Future，
  方法自身成功返回；随后关闭 A、开启 B，再释放后台 gate。回调在原 Invocation
  Zone 内恢复，重新通过框架获取 Service。
- 实际：`service`、`serviceAsync`、`services`、同步代理、异步代理全部进入 B。
  代理探针已执行目标方法并读得 `new`；直接解析探针得到 B 的资源对象。
  未发生切换时全部正常；initializer 的同类回调在切换后全部正确拒绝。
- 扩展：A 的方法先调用 App Service，再由 App Service 留下回调，结果相同。
  此时最内层 context 的 Scope 属于 App，单查该 Scope 是否活着不足以阻止跨代。
- 根因：`_invoke` / `_invokeSync` 成功后移除父 Invocation、具体 Scope 的取消连接，
  但遗留后台工作的 Zone 仍带着该 context。之后 Session 关闭时它的 token 不再
  变为 cancelled。普通方法不像 initializer 那样保留 construction owner；
  `_ensureServiceResolutionCanEnter` 因此放行，Session 解析选择当前的 B。
- 影响：旧账号操作的遗留回调可调用新账号 Service，造成账号间操作归属错误。
  这里证实了资源取得和代理方法执行，不声称已经发生真实业务数据泄漏。
- 分类：框架新调用准入的生命周期缺陷。业务后台任务的停止、网络请求取消仍是协作式；
  本问题不要求框架强停任意 Dart 代码，也不涉及撤销业务已持有的引用。
- 最小修复方向：用私有、轻量、绑定具体生命周期代际的记录保护 Invocation 继承链，
  成功返回后仍能在新框架入口识别旧 Owner 已关闭。保留正常移除 listener 的行为，
  不通过长期保存所有 listener 或整个 Scope/Service 对象图解决。
  singleton initializer 应继续独立于首个等待者，不能被后者的结束误杀。

50 项组合：4 类普通/嵌套方法 × 5 类查找在切账号后共 20 项有效失败；
其余 30 项正常对照通过。所有探针都先确认原方法已成功结束，再关闭 Session。
新账号独立调用正常，所有构造的 disposable 均只销毁一次。

### P2：根级同步查找在 factory 触发 shutdown 后仍交付资源

- 位置：`packages/ccrouter_core/lib/src/runtime_host.dart:2170–2175`，
  交付后调用点在 `2160`。
- 触发：在任何 Invocation/构造 Owner 之外调用根级同步 `service`、`serviceOrNull`
  或 `services`；对应 factory 同步调用 `runtime.dispose()` 后返回实例。
- 实际：Runtime 已标为 disposed，查找仍成功返回对象；shutdown 随后将对象销毁。
  singleton / newInstance 均发生。异步解析和同步/异步代理的对照正确拒绝。
- 根因：入口的 `_ensureInitialized` 发生在 factory 前。交付后的 helper 仅在
  parent 或 construction owner 存在时检查终态；两者皆无的根级调用漏过 Runtime
  自身 disposed/initialized 状态。shutdown 到达 Scope close 前的异步间隙使
  Scope 此时仍可能 active。
- 影响：调用者收到 shutdown 已开始、即将清理的资源；调用成功不能再代表交付时
  Runtime 仍可用。测试确认资源仍被清理一次，因此不是已证实的 not-disposed 泄漏。
- 最小修复方向：同步交付前无条件检查 Runtime 本身仍接受解析，保持已成功构造的
  disposable 由原 Scope 接管清理；不改变反向销毁、共享关闭和错误传播规则。

24 项组合：3 类根级同步查找 × 2 类 creation policy 的 shutdown 情况共 6 项有效
失败；其余 18 项正常或正确拒绝的对照通过。认证/应用关闭仍推荐放在 factory 外，
但该建议不能代替框架已承诺的重入交付保护。

## 方案比较与建议顺序

| 方案 | 收益 | 代价与限制 |
| --- | --- | --- |
| 业务每个后台任务自行检查账号/token，禁止 factory 内关闭 | 可临时降低触发率 | 分散重复防护，遗漏一个入口即可跨代；不能形成框架统一准入 |
| 让成功调用永久保留取消 listener，或成功后立即取消所有 context | 实现看似直接 | 前者累计监听与保留链；后者误伤仍在同一活跃 Scope 的合法工作 |
| 私有 Invocation 所有权代际记录 + 根级交付终态检查 | 不改变外部 API；覆盖同步/异步及嵌套调用 | 必须覆盖父链与 initializer 独立生命周期，推荐 |

建议先修 P1，再修 P2，按以下步骤推进：

1. 将本轮确定性探针作为失败基线，设计私有所有权记录；不扩大业务 Facade 或 Host SPI。
2. 同时覆盖方法成功/仍 pending、直接/嵌套 App 调用、同步/异步/代理、Session
   切换/Route 结束/Runtime 关闭，以及缓存、Key、newInstance 等入口。
3. 验证同一活跃 Scope 内的后台回调仍可正常调用；共享 singleton initializer
   不受首个等待者取消影响；关闭后零新资源构造、零新业务方法进入。
4. 补根级交付的 Runtime fence，保持晚构造资源清理一次、清理失败不跳过其它资源。
5. 修复后把失败探针加入默认回归，同步 README、集成 Skill 和相关生命周期说明，
   再跑全量；不得只补本次失败行的局部条件。

这是修复建议，本轮 review 未实施生产修复。

## 扩大的正常覆盖

新增 `pending_resume_repeated_failure_test.dart`，16 项已加入默认 suite：

- 相同/不同 error Zone × 1/3 次 defer × 拒绝/抛错 × 传播/Failure Policy 恢复。
- 每个 Resume 调用保留 replay 自身的失败及错误对象；原调用可以独立恢复成功。
- Failure Policy 仅执行一次，失败归因仍为 pendingResume，pending 完全释放。
- 随后的独立导航正常，不继承错误或触发第二次恢复。

这些组合全部通过，没有将它们误报成新缺陷。额外运行了支付生成代理、存储模块和
Order 独立 Host Example，覆盖真实生成 Client 的同步/异步/getter/泛型和账号切换。

## 验证证据

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| 框架及 Demo 默认 Flutter suite，新增 16 项后 | 1156 通过 | [flutter-final.log](flutter-final.log) |
| 支付代理、存储模块、Order 独立 Example | 9 通过 | [component-examples.log](component-examples.log) |
| analytics / Firebase / tool Dart suite | 55 通过 | [dart.log](dart.log) |
| 新增显式缺陷探针 | 74 项：48 通过、26 有效失败，归为上述 2 类缺陷 | [repro-final.log](repro-final.log) |
| 多次 Resume 专项，亦包含于默认 suite | 16 通过 | [repeated-resume.log](repeated-resume.log) |
| Workspace analyze | No issues found | [analyze-final.log](analyze-final.log) |
| Demo generation freshness | 复用有效 watch cycle 86 的精确证据，up to date | [generation.log](generation.log) |
| 文档检查 | 检查器选取的 121 份 Markdown 通过 | [documentation.log](documentation.log) |

新增 3 份 Dart 测试文件格式检查为 0 改动，`git diff --check` 通过。
文档检查的选择范围不等于工作树所有 untracked 审查报告。

默认全量通过不等于上述缺陷已经修复。显式失败探针位于
`packages/ccrouter_test/test/review_repros/completed_invocation/repro.dart`，
使用非 `_test.dart` 入口保留审查证据，修复前不混入默认通过结果。
2 秒 timeout 只是挂起探测上限，不是性能 SLA。

初次 42 项探针日志为 `repro.log`。扩展时的 `repro-fixture-draft.log` 中另有
4 项代理成功对照误把字符串返回值与实例比较；已纠正测试期望，生产代码未改。
只有最终 `repro-final.log` 用于 74 项最终结论，不把这 4 项夹具错误算作框架缺陷。

```sh
fvm flutter test --no-pub \
  packages/ccrouter_test/test/review_repros/completed_invocation/repro.dart \
  --reporter expanded
fvm flutter test --no-pub packages/ccrouter_test/test demo/test \
  demo/modules/navigation_lab/test demo/modules/analytics_flutter/test \
  --reporter expanded
fvm flutter test --no-pub demo/modules/payment/test \
  demo/modules/kv_storage/test demo/modules/order/example/test --reporter expanded
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test \
  tool/test --reporter expanded
fvm dart analyze
fvm dart run ccrouter_generator:ccrouter generate demo --check
```

## 为什么本轮仍发现问题，以及 Demo 取舍

上轮覆盖的是“调用尚在进行时被取消后的延续”，本轮增加了“调用已成功结束才关闭
Scope”及“Session → App 嵌套调用后的延续”。取消 listener 的清理本身正确，
但过去把 listener 存在等同于所有权仍可验证，没有独立覆盖完成后的 Zone 继承。
根级同步查找又没有父 context，局部修复不能自然覆盖它。
需要围绕统一所有权不变量补组合矩阵，而非以回归数量代替覆盖模型。

Demo 已有运行总览 Session 开关、能力页 Session Service 与 close，以及 defer/resume
入口；本轮没有新增需展示的公开能力。新增风险依赖精确时序和已结束调用的 Zone，
确定性测试更适合，故未增加重复按钮或把已知错误展示成支持能力。

未发现高置信度 not-disposed / not-GCed 泄漏；这不构成进程内存认证。
未执行新的 macOS 真实窗口、Android/iOS 真机手势或长期性能验收。
未修改独立 Analyzer Plugin，也未运行其隔离 suite 或全套 Generator suite。
