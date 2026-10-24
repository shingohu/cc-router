# Host 换代、资源接管与超时语义修复

日期：2026-10-23。分支：`codex/managed-navigation-runtime`，基于 HEAD `09cb21d`
的当前工作树。保留此前所有未提交修改，没有提交、推送或删除历史证据。

## 问题与方案取舍

本轮落实上一轮 expanded-scenario-review 的三类生产缺陷及一个测试时序问题。
正式回归修复前基线为 18 项中 9 通过、9 失败，原始日志保留于本目录。

| 问题 | 可选方案及代价 | 本轮采用 |
| --- | --- | --- |
| 同 ID Host 重建后旧导航复活、旧并发 gate 污染新实例 | 业务手动取消容易遗漏；Adapter 提交前检查无法释放策略等待和旧 gate；全局锁影响无关 Host | Runtime 私有操作生命周期绑定具体 Host 注册，detach 终止旧操作并同步释放准入 |
| factory 内重入关闭 Scope，返回对象漏清理 | fire-and-forget 补偿不能等待异步清理；拒绝重入会改变关闭契约 | 已准入同步构造先完成资源交接，Scope close 等待交接后执行原有有界清理 |
| cancellation listener 抛错覆盖 timeout | 改 Token 契约影响显式调用者；业务吞错无法修复错误类型 | Runtime 隔离通知异常，脱敏诊断并保留原 timeout |
| readiness 测试依赖 10ms 启动窗口 | 调大 timeout 仍依赖机器速度 | 用 owner waiter 和 initializer started gate 确定启动时序 |

没有新增业务 API、Host SPI 签名、依赖或导出。实现集中在 Runtime/Scope 内部，
便于按改动范围回退；不使用全局串行化，也不新增配置开关让旧缺陷继续作为支持路径。
新增可观察语义：Host detach 后，尚未提交的归属导航以
`CCRouteCancelledError('host_detached')` 终止，取消不能由 Failure Policy 恢复进新实例。
已提交页面的结果仍沿用 Backend 原有 detach 完成逻辑。

## 实现及生命周期

- 每个原始导航在 Runtime 专属 Zone 中拥有一个私有 operation lifetime，保存访问过的
  Host 注册 token。逻辑 ID 可复用，token 不复用；显式目标 Host 优先于无关 active Host。
  redirect 访问过的任一 Host 注销，整个旧操作终止。defer/resume 恢复原归属，不能复活。
- 并发 key 包含注册 token identity，保持同代 singleFlight/rejectDuplicate 行为；
  operation 取消同步清除旧 gate，旧 Future 晚到完成时以 identity 校验保护新 gate。
- 策略等待订阅 operation cancellation，取消时通知 cooperative interceptor token，
  框架不再等待旧用户 Future。其晚到结果/错误被消费，不提交新页面；任意 Dart 用户任务
  本身不能被强制终止，仍由创建者管理资源。
- operation finally 移除 Host listeners 并清空捕获；pending 在 resume、cancel、timeout、
  shutdown 时移除相关 listeners 和 timer。Host detach 移除注册，Runtime shutdown
  清空注册 map。没有新增生产 Timer。
- Scope 使用同步构造 reservation 和 drained completer，成功返回的 disposable 即使
  lookup 因关闭失败，仍进入逆序清理；异步清理被等待，同对象只清理一次，异常隔离。
  factory 抛错同样释放 reservation，不让 close 悬挂。
- timeout 通知失败只记录异常类型和关联 invocation/scope ID，不记录私有异常 message；
  Token 显式 cancel 的“通知全部 listener 后抛首错”契约保持原样。

本轮未发现上述新增 listener、pending 或构造 reservation 有遗漏终止出口。此结论来自
所有权检查与生命周期测试，不是 heap 或长期内存认证。

## Demo 与开发者指导

新增 `demo/lib/host_lifecycle_lab.dart`，通过 MultiHost Demo 的“Host 生命周期”入口：

1. 发起延迟导航，旧实例停在手动策略 gate。
2. 关闭并以相同 ID 重开辅助 Host，旧调用收到 `host_detached`。
3. 新实例独立导航到 Level 901。
4. 放行旧决策，新页面与 Entry identity 保持不变。

Host 注册/注销只在 Demo Composition Root 操作，业务导航仍使用公开 Facade。
离开场景释放 gate、注销辅助 Host、dispose Backend。重建时资源清理先完成，再等待
旧 Widget 的 endOfFrame 卸载后挂载同 ID CCRouterApp，避免重复 lifecycle bridge。
资源释放本身不依赖 UI frame。

已更新 README 中英文、Demo README、integration Skill、implementation-patterns、
review-checklist 及相关 DartDoc，说明注销的取消语义与 Scope 构造资源接管行为。

## 回归结果

新增正式回归 34 项：Host 换代 27 项、Scope 构造 5 项、timeout 诊断 1 项、Demo 1 项。
覆盖 Proceed/redirect/recovery/defer、同代和跨代并发、跨 Host redirect 后无 pump 立即
retry、Go/Reset/Push/Replace/Open/notification、公开 Facade Session 清理及晚到错误。

| 检查 | 最终结果 | 日志 |
| --- | --- | --- |
| 修复前正式探针基线 | 9 passed / 9 failed | `ccrouter-incarnation-fix-baseline.log` |
| 扩展专项（不含 diagnostics） | 33 passed | `ccrouter-incarnation-fix-expanded.log` |
| 新 Demo 单项 | 1 passed | `ccrouter-incarnation-demo-focused.log` |
| Flutter 全量 | 891 passed | `ccrouter-incarnation-fix-full-final.log` |
| Dart 专项 | 55 passed | `ccrouter-incarnation-fix-dart.log` |
| Workspace analyze | No issues found | `ccrouter-incarnation-fix-analysis.log` |
| Demo 生成物检查 | up to date，复用 active Host watch cycle 27 的精确证据 | `ccrouter-incarnation-fix-generation.log` |
| 文档检查 | 121 个受检 Markdown 通过 | `ccrouter-incarnation-fix-docs.log` |
| diff 格式检查 | `git diff --check` 通过 | 命令退出码 0 |

实际最终命令：

```sh
fvm flutter test --no-pub packages/ccrouter_test/test demo/test demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test tool/test --reporter expanded
fvm dart analyze
fvm dart run ccrouter_generator:ccrouter generate demo --check
fvm dart run tool/documentation_check.dart
git diff --check
```

本轮首次全量为 875 passed / 1 failed，暴露新 Demo 在旧 Widget 尚未卸载时挂载同 ID
Host。已修正为上述 frame 交接，专项和最终全量均通过。首次失败日志保留在
`ccrouter-incarnation-fix-full-first.log`，不以最终通过抹去迭代记录。

## macOS 真实窗口验证及边界

后续状态：窗口点击通道恢复后完成了真实操作，并发现重复生命周期下的事件 ID 复用
缺陷和辅助 Host 初始空白，验收不通过。详见
[macOS 后续验收报告](../20261023-macos-host-lifecycle-acceptance/report.md)。
以下保留本次修复收尾时的窗口阻塞记录，不代表后续验收结论。

运行入口为 `lib/multi_host_demo.dart`，成功热重启，窗口显示三个入口，双 Host 首页
正常，能够读取 Flutter 辅助功能按钮，控制台在最后一次读取时无新增输出或异常。

真实点击仍受工具阻塞：多次坐标点击返回 Computer Use server error
`-10005: noWindowsAvailable`；重新连接、Raise、辅助功能点击和键盘尝试后，页面未
切到“Host 生命周期”。因此本轮新增场景的 **macOS 真实按钮验收未完成**，不能把
Widget 回归等同真实窗口通过。无需为此修改框架或操作系统权限。

未在本轮新增执行 Android/iOS 真机手势、长时间 monkey、性能采样或 heap 检查，
也未在历史 GoRouter checkout 重跑这组测试。没有据此声称所有场景穷尽、零缺陷，或
重构在所有方面均优于旧后端。
