# 共享执行、订阅身份与 UI/Contract 生命周期修复

2026-10-23；分支 `codex/managed-navigation-runtime`；基线 HEAD `09cb21d`。

已修复前两轮审查确认的问题，并补齐共享导航取消的 Aspect 终态。外部 API 签名保持不变；
新增实现均为私有类型/函数，不扩大业务 Facade 或 Host SPI。

## 问题、根因与修复

| 问题 | 根因 | 最终修复 |
| --- | --- | --- |
| InitTask 同步重入重复执行 sibling、drain 提前结束 | 调用任务后才发布运行状态 | 先建立并发布私有 `_InitTaskDrain`，再驱动 DAG；重入与重叠调用加入同一轮 |
| 不同 error Zone 的 shutdown 卡住、Service 不释放、Host 无法重启 | Core await 另一个 error Zone 创建的 error Future | 内部成功 Future 携带 outcome 数据；shutdown 只等待 settled，不在内部重抛任务取消 |
| Service readiness、导航 singleFlight 的共享失败无法到达其他 error Zone | 把执行共享实现为直接共享 error Future | 私有 `_SharedResult<T>` 保存 value/error/stack；在每个调用者自己的 Zone 恢复结果 |
| Fragment 卸载后保留 Action 仍保留 State/Props/消费方 callback owner | 转发闭包直接捕获 State | 使用可撤销的小型 Action sink；卸载或 identity 更新清空 callback，sink 不引用 State/Widget/Props |
| 观察者 re-add 收到旧事件、旧 remover 删除新订阅 | callback identity 与 registration identity 混为一谈 | 六类订阅增加 token；队列快照与 remover 均核对原 registration |
| 单比较器和 Tab/换行分隔范围失败 | 仅包含 ASCII 空格时才走 comparator 分支 | exact 和比较器统一 whitespace tokenize 后解析，caret/tilde 等原规则保持 |
| SemVer preRelease 可变 | 直接暴露 split 返回的可变 List | 保存不可变标识集合 |
| singleFlight 的共享取消观察被记为 failed | 共享结果的 catch 固定写 failed | 与原请求保持一致：CCRouteCancelledError 对应 cancelled，普通失败仍为 failed |

主要实现位置：

- `packages/ccrouter_core/lib/src/shared_result.dart`：只共享成功完成的 outcome Future，
  不增加 Timer，不缓存所有调用者的 Zone，不持有 Runtime/Scope。
- `initialization.dart`、`runtime_host.dart`：原 error Zone 中的重叠 Gate 调用保留同一
  Future identity；跨 error Zone 的调用各自恢复错误。shutdown 继续保持资源清理顺序。
- `scope.dart`、`navigation.dart`：initializer 与导航仍只执行一次；保持 readiness
  失败不隐式重试、取消单个调用不重启初始化、导航 gate 完成/失败后允许重试。
  Service 原有 CCServiceInitializationError 包装规则不变。
- `navigation_callback.dart` 及六类订阅入口：同时重复 add 同一函数仍去重，任一原
  remover 可取消它；取消后再次 add 才创建新 registration。静态 Aspect 的列表顺序
  和重复 callback 行为保持原样，未强行转换为 Map。
- `packages/ccrouter_ui/lib/src/ui_fragment.dart`：新 sink 保持 latest callback、active、
  capability identity、generation 的约束；仍不承担 Renderer 自己保存的 Props/input
  或异步任务的释放。
- `packages/ccrouter_contracts/lib/src/contract_compatibility.dart`：范围语法及不可变值
  使用同一实现供 Generator 和 Host 检查。

## 方案取舍

| 方案 | 收益与代价 | 选择 |
| --- | --- | --- |
| 业务增加 timeout、避免回调 re-add、约定只写 caret | 局部规避，但不能修复内部清理与订阅隔离 | 不作为框架方案 |
| 按 Zone 拆分执行、增加业务公开 API、全局清空观察队列 | 破坏 singleton/singleFlight 或订阅隔离，迁移成本高 | 未采用 |
| 私有 outcome、运行记录、注册 token、可撤销 Action sink | 保留调用方式，增加少量随生命周期释放的内部记录 | 已实施 |

修改保留在原独立 worktree，未提交或推送，未回退用户已有修改。没有增加保留已知缺陷的
生产开关；原始失败日志与修复后回归构成对照。需要回退时应只回退本轮有边界的修改，
不能 reset 整个包含历史工作的工作树。

## 验证

前两轮原有 46 项探针所表达的契约均已纳入默认测试发现，并补充 31 项相关边界，
共 77 项新增默认回归。原始 fixtures 保留，以 `*_regression_test.dart` 入口调用，
避免只保留不会自动执行的显式 repro。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 最后一轮 Flutter/Demo 全量回归 | 1043 通过，包含新 77 项 | [flutter-final.log](flutter-final.log) |
| 共享执行专项 | 22 通过 | [shared-execution.log](shared-execution.log) |
| 应用 analytics 与工具测试 | 55 通过 | [dart.log](dart.log) |
| Generator 本次影响路径 | 9 通过：Workspace 6、真实 Builder 3 | [generator-focused.log](generator-focused.log) |
| 原有 Service Builder 超时项单独复核 | 默认 timeout 下 1 通过，约 22 秒 | [generator-timeout-recheck.log](generator-timeout-recheck.log) |
| 最终 Workspace analyze | No issues found | [analyze-final.log](analyze-final.log) |
| Demo generation --check | 通过，复用 active watch cycle 70 的精确证据 | [generation-final.log](generation-final.log) |
| 文档检查 | 检查器选择的 121 个 Markdown 通过 | [documentation-final.log](documentation-final.log) |
| Dart format / git diff --check | 通过 | 格式检查 29 个文件、0 changes；diff check 退出码 0 |

77 项默认新增回归组成：

- 共享执行 22 项：Gate 同步重入与普通重叠、跨 error Zone readiness 成功/失败/晚加入、
  Core 和公共 Host shutdown、Host 重启、两个 error Zone 加入同一 Gate drain、
  原失败 identity/stack、singleFlight 成功/取消及两份 terminal observation。
- Fragment 3 项：不保留/保留 inert Action 的强制 GC 对照，以及同一 State 更新
  capability identity 后旧 Action 失效、新 Action 正常。既有 UI suite 继续覆盖
  callback 更新、hidden KeepAlive、DTO Action 和 generation 失效。
- 观察者 30 项：Lifecycle/Entry/Visibility/Failure/Backend/Capability 六类，
  分别覆盖取消、取消后 re-add、旧 remover 重复调用、重复 add 去重、独立订阅隔离。
- 版本边界 22 项：原语法对照、四种单比较器、whitespace、UI Host Assembly、
  非法表达式拒绝、prerelease 不可变及哈希集合/排序稳定。

共享执行默认回归的 hang watchdog 从审查探针的 200ms 放宽到 2 秒，避免把机器负载
当作功能失败；它不是框架性能 SLA。放宽后重新执行共享执行 22 项，不改变生产 timeout。

补核 Aspect 时，先增加取消 outcome 断言，修复前得到 2 个成功对照、2 个有效失败，
见 [navigation-outcome-before.log](navigation-outcome-before.log)；修复后 22 项共享
执行及最终 1043 项套件均通过。由此保证修复不止让 Future 结束，也维持正确的观察语义。

首轮广域 Generator 命令与 Flutter/Analyze/工具测试并行，原有 Service Token Builder
用例达到默认 30 秒 timeout；该次广域运行随后主动停止，不计为全量 Generator 通过，
保留 [generator.log](generator.log)。其他任务结束后，该原用例在不放宽 timeout、
不改测试断言的情况下单独通过；本次修改相关的 9 项 Generator 测试也通过。
这支持受影响路径已验证，但不能代替完整 Generator 套件认证，也不能仅凭单次重跑
断言首次超时必然只由 CPU/内存负载造成。

## 文档、Demo 与限制

已同步根 README、集成 Skill、implementation-patterns、ui-fragments 和 review-checklist，
以及相关框架 DartDoc。旧审查报告保留失败时证据，并增加指向本报告的状态更新。
文档检查器选择的 121 个 Markdown 不包含全部 untracked 报告，不扩大其覆盖结论。

未手工修改生成物。有效 Demo watch 已在运行，因此使用普通 `generate demo --check`
复用精确当前证据，没有启动竞争生成器或停止用户的 watch，也没有把它描述为
`--no-cache --check` 的冷路径验收。独立 Analyzer Plugin 未修改，不涉及 Demo pin 更新。

未增加 Demo 按钮：现有 UI Fragment、InitTask、Service 与并发导航已有展示场景，本轮
修复针对 GC、同步重入、error Zone 和订阅重建，确定性测试更适合证明这些行为。
正常套件仍包含多 Host/Outlet、close、Shell、foreign Popup、iOS 连续 swipe 只移除一次、
取消 swipe、shutdown 与 swipe 交错等既有场景。

本轮没有新增 macOS 真实窗口、Android/iOS 真机手势、进程级内存或性能认证。GC 测试
只证明指定保留链已解除，不能替代长期压力运行；内部 outcome 也不会改变 Dart 对任意
应用自行跨 error Zone 共享 error Future 的规则。

## 可复核命令

```sh
fvm flutter test --no-pub packages/ccrouter_test/test demo/test \
  demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded
fvm flutter test --no-pub packages/ccrouter_test/test/shared_execution_regression_test.dart \
  --reporter expanded
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test \
  tool/test --reporter expanded
fvm dart test --concurrency=1 \
  packages/ccrouter_test/generator_test/ui_fragment_workspace_test.dart \
  packages/ccrouter_test/generator_test/ui_fragment_generator_test.dart \
  --name 'valid UI workspace|documented comparator|single comparator' --reporter expanded
fvm dart test --concurrency=1 \
  packages/ccrouter_test/generator_test/service_generator_test.dart \
  --name 'contract builder emits a typed owner-only Token' --reporter expanded
fvm dart analyze
fvm dart run ccrouter_generator:ccrouter generate demo --check
fvm dart run tool/documentation_check.dart
```
