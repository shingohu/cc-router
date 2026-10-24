# Session 解析准入与跨 Zone Resume 修复

2026-10-23；分支 `codex/managed-navigation-runtime`；工作树
`/Users/shingo/.codex/worktrees/managed-navigation-runtime/cc-router`。

已修复 [上一轮审查](../20261023-session-resume-review/report.md) 的两项缺陷。
外部 API 签名保持不变，没有新增公开类型、业务参数、运行开关或依赖。
生产修改限于 Core Service 解析、Pending Resume 及 Facade DartDoc；保留工作树已有修改，
未提交、推送、删除或回退任何用户成果。

## 根因与方案

| 问题 | 根因 | 修复 |
| --- | --- | --- |
| 旧 Session 的方法/initializer 恢复后可同步取得新账号 Service | 同步解析只检查当前目标 Scope active，忽略原 Invocation cancellation/deadline 和 construction owner 生命周期 | 私有 `_ensureServiceResolutionCanEnter` 在 cache/factory 访问前与资源交付前统一校验 |
| 不同 error Zone 的 Resume 在取消或策略失败时挂起 | 恢复流程完成原 Completer 后，直接返回原调用者的 error Future | 原 Completer 独立完成，恢复调用在自己的 Zone 直接返回结果或以原 stack 抛错 |

业务逐处检查 token 可以临时规避，但不能保证缓存/批量/Key 等所有入口一致；新增业务
Session 参数或限制 Zone 会增加迁移成本。本次采用私有校验和本地返回，不增加 Adapter、
全局队列或每调用者 Zone 缓存，也不改写共享 singleton 初始化的执行所有权。

### Service 所有权

`packages/ccrouter_core/lib/src/runtime_host.dart` 的 `_resolve` 统一覆盖同步
single、optional、batch、Key 和 newInstance 路径。准入校验使用当前 Runtime 的父
Invocation 与 construction owner，避免旧账号调用重新进入可变的当前 Session。
factory 可同步取消调用者，因此交付前再次校验；成功创建的资源仍归原目标 Scope，
不会因调用者取消而泄漏或被提前销毁。测试确认活着的 App-owned 资源可供新调用使用，
最终只释放一次。

共享 singleton initializer 使用 Scope 的 context，不绑定首个等待者。单个等待者取消或
超时不阻止 initializer 继续解析合法依赖，也不会启动第二次初始化。新账号的独立调用
照常工作。上述校验不撤销业务已经持有的对象引用，也不能强制停止已进入的任意 Dart 工作。

### Resume 终态与恢复策略

`packages/ccrouter_core/lib/src/navigation_pending.dart` 的恢复流程保持原导航 ID、
placement、类型校验、defer Timer 和 cancellation remover 清理路径。
恢复结果在本地 return/throw，原导航的 Completer 仍在自己的 Zone 传播结果；失败对象
与 stack 保持一致，不再把原 error Future 返回给不同 error Zone。

原导航流水线仍负责 Failure Policy 与失败记录。它可以恢复成功，而 Resume 调用仍收到
本次重放的错误。两个 Future 应分别处理，完成先后顺序没有保证；读取原导航的失败记录
应等待原 Future，不能以 Resume 完成为替代条件。既有 pending-resume attribution 测试
已改为等待两个 Future，继续检查 `pendingResume/interceptorFailed`，未删除诊断断言。
新测试同时确认 Failure Policy 只运行一次、取消路径的 terminal Aspect 不重复。

## 默认回归

新增 97 项常规回归，默认 Flutter suite 从 1043 项增加至 1140 项：

- `session_resume_lifecycle_regression_test.dart`：18 项，直接复用原审查 fixture，
  覆盖 initializer/普通方法、切账号/未切账号、同步 single/batch 与异步对照，
  以及同/不同 error Zone 的 Resume 成功、取消和策略抛错。
- `service_resolution_admission_test.dart`：65 项，其中 60 项交叉 Session close、
  caller cancel、timeout 与 single/optional/batch/Key/optional Key、singleton/
  newInstance、未构造/预热资源；4 项验证 App/Session singleton 在首等待者取消或
  超时后继续解析；1 项验证 factory 取消后的交付 fence 与 App 资源所有权。
- `pending_resume_zones_test.dart`：14 项，覆盖三个 error Zone 的重复 defer 后成功、
  显式取消、pending timeout、Session close、shutdown；恢复中策略等待的 Host
  detach/re-register、shutdown、策略 timeout 及晚到错误；原 error/stack；一次
  Failure Policy recovery；Push/Replace 的正确和错误类型结果。

保留原显式 probe 文件和修复前失败日志；新 wrapper 已使其进入默认发现，不再依赖
维护者记得单独运行 repro。测试中 Framework 共享结果与应用自行返回的外来 error
Future 分开验证，后者仍受 Dart 自身 error Zone 规则约束。

## 验证结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 最终框架、Demo、导航组件和 Flutter analytics suite | 1140 通过 | [flutter-final.log](flutter-final.log) |
| 应用 analytics 与工具 Dart suite | 55 通过 | [dart.log](dart.log) |
| 最终 Workspace analyze | No issues found | [analyze-final.log](analyze-final.log) |
| Demo generation --check | 通过，复用 active watch cycle 83 的精确当前证据 | [generation.log](generation.log) |
| 文档检查 | 所选 121 个 Markdown 通过 | [documentation.log](documentation.log) |
| 修改文件 format / git diff --check | 通过 | 最后检查无格式变化、diff 检查退出码 0 |

首次全量 [flutter.log](flutter.log) 为 1138 通过、2 项失败，不计作通过：

1. 既有诊断测试的 100ms 真实 deadline 在 Command handler 进入前耗尽，导致原本要
   验证的 timeout listener 尚未注册，晚到 fixture 错误也没有等待者。改用显式
   handler-start gate 和 Flutter 虚拟时间：一分钟 deadline 由 `tester.pump` 推进，
   不消耗一分钟真实时间，不放宽生产 timeout，也不删除清理/Trace/诊断断言。
   该测试文件 9 项独立通过，随后最终全量通过。
2. 既有 Resume 测试只等待恢复 Future 就读取原流水线失败记录。解除跨 Zone Future
   依赖后，两者完成时序独立；按各自职责明确等待原导航和 Resume，再保留原失败
   attribution 断言。该项单独通过，随后最终全量通过。

修复后的 1140 项全量是在上述测试修正后重新完整执行，并非把第一次失败项单独重跑
就视作全量通过。本轮未改 Generator 生产实现或生成契约，未跑全套 Generator Builder。
独立 Analyzer Plugin 未修改，不涉及 pin 更新。

## 文档与边界

同步更新 README.md/README.en.md、集成 Skill、implementation-patterns、
review-checklist 以及 Service/Resume 的 Facade/Core DartDoc。文档检查器的 121 文件
是其选择范围，不表示全部 untracked 验证报告都被自动扫描。

未新增 Demo 按钮：既有 Session、Service 和 defer/resume 展示场景足够；本轮缺陷是
跨账号/Zone 的确定性交叉边界，使用受控 gate、独立 Zone 和默认测试更易复核。
未手工编辑生成物，未停止有效 watch 或启动竞争生成器；普通 `generate --check` 的
watch 复用不等同于 `--no-cache --check` 冷路径检查。

本轮没有新增 macOS 真实窗口、Android/iOS 真机手势或进程内存/性能验收。已有 Widget
suite 包含多 Host/Outlet、精确 close、Shell/foreign Popup、重复与取消 iOS swipe、
shutdown 与 swipe 交错回归；不据此扩大为全部平台认证。生产修复未增加 Timer、订阅、
可销毁资源或长期缓存；没有本轮额外 GC 或长期压力性能结论。

## 可复核命令

```sh
fvm flutter test --no-pub packages/ccrouter_test/test demo/test \
  demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test \
  tool/test --reporter expanded
fvm dart analyze
fvm dart run ccrouter_generator:ccrouter generate demo --check
fvm dart run tool/documentation_check.dart
```
