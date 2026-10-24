# 来源隔离与异步 Host 归属修复

日期：2026-10-23。分支：`codex/managed-navigation-runtime`。
本轮落实[上一轮审查](../20261023-partition-origin-review/report.md)的 3 类缺陷，
保留原有失败证据及工作区其它改动。没有提交或推送。

## 根因与方案

请求去重没有纳入 trusted origin；redirect/recovery 又在等待后重新解析 active Host；
MultiHost 子后端完成 Pop 后，聚合器用后来 active 的 Host/Outlet 覆盖了真实回执。
共同问题是请求等价性和一次异步操作的归属未贯穿所有路径。

| 方案 | 收益 | 代价 / 结论 |
| --- | --- | --- |
| 应用禁用 singleFlight、强制传 context、等待时禁止切焦点 | 应用改动较小 | 无法兑现既有 context-free 和独立导航能力，不作为最终修复 |
| 全局队列或新业务 API | 可压制部分交叉顺序 | 改变独立 Host/Outlet 的并发和 Push 生命周期，未采用 |
| 现有 Runtime 内隔离 origin、固定默认 Host、保留子回执 | 保持业务调用，修正准入和归属 | 需验证显式 Host 和结构化 placement，本轮采用 |

实施顺序为正式失败回归 → 来源 key → 操作 placement → Pop 回执 → 串联/销毁边界 →
文档 → 全量回归与 macOS 双 Host 交互。

## 已修复的行为

1. `singleFlight` / `rejectDuplicate` 的等价 key 包含精确 `CCNavigationOrigin`。
   internal、platform、notification、QR 互不共享或互相抑制 Interceptor。同来源的
   共享结果/错误、重复拒绝和终态重试保持原行为；Extra 仍独立执行。产品归因 source
   不作为 trusted origin，不新增授权状态或用户身份缓存。
2. Runtime 在操作开始时快照调用点或 active Host，初始目标显式声明 Host 时以它为准。
   后续默认目标使用这份固定 placement，包括 redirect、Failure Policy recovery、
   defer/resume、多次跳转和显式 Host 中间跳转。显式目标仍可选择另一 Host，默认目标
   继续使用原操作的归属；Parent/Shell/Outlet、Path/Query、Extra 和原 result 契约保留。
   初始 URI 解析失败时也保留 invocation Host。目标 Host 注销后失败，不改投其它 Host。
3. MultiHost 在 Pop 前捕获 Host 和 fallback Outlet；异步完成、同步 callback 改焦点、
   注销或 shutdown 不再重写回执。优先保留子后端实际 Outlet，scoped Pop 从 named
   Outlet 关闭 root Popup 时报告 root。真实 Route/result/removal identity 仍由原生
   Managed 负责；LocalHistory-only 处理不变成 Managed Entry removal。

业务 `CCRouter.navigator` 签名、Host SPI 签名和 barrel exports 未新增或改变。
没有给旧缺陷增加可切回的业务开关；它们是现有内部路径的兼容修正，可独立审查/回退。
没有新增 Timer、Stream、Listener、全局队列或持久资源，也没有保存 Context、Flutter
Route、账号身份或额外业务 payload。默认 placement 副本仅属于现有 pending 请求生命周期。

README 中英文、Concurrency DartDoc、Integration Skill、implementation patterns 与
review checklist 已同步；Skill 要求将这些行为作为框架不变量验证，未引入业务 workaround。
未手改生成物。

## 正式回归

新增：`packages/ccrouter_test/test/managed_navigation_partition_regression_test.dart`。
先转入原始 9 项探针，修复前 **5 passed / 4 failed**，见 `baseline.log`。最初 4 项失败
分别为来源策略未执行、redirect 错 Host、recovery 错 Host、Pop 回执错 Host，均为
真实行为断言失败。不是编译、依赖或 fixture 装配失败。

最终扩展为 **82 项通过**，使用真实 Runtime、Managed MultiHost、Flutter Router、
Navigator、Route 和 DialogRoute；不以 mock 返回值替代导航效果。

| 组合 | 覆盖与断言 |
| --- | --- |
| 四种精确 origin × 两种去重策略 | 所有不同 origin 的有序组合各自运行策略；同来源错误共享/重复拒绝与 gate 清理后重试 |
| 原始正反对照 | allow 与 singleFlight；无 context Proceed/redirect/recovery；传 context redirect；defer/resume redirect |
| Go / Reset / Push / Replace / Open-Push / 外部 Open-Go | 各自经 Interceptor 或 Failure Policy，目标使用 Intent 或 URI；焦点切换后仍保持 Host、Shell、named Outlet 和 parent；typed result 仍回原调用 |
| 声明式 parent | Go/Reset/Open-Go 重建祖先；Push/Replace 不制造祖先；外部叶子允许 Deep Link，结构祖先仍可禁止外部入口 |
| 显式 Host | 目标显式 Host 生效；初始显式 Host 决定默认 fallback；显式中间跳转后继续 redirect/recovery/defer 不重新读焦点 |
| 解析失败 | 未匹配 URI 的 recovery 使用 invocation Host 快照 |
| Host 注销 / Runtime shutdown | 等待中的 redirect/recovery 不改投其它 Host；Back 在业务 willPop 未结束时完成框架等待；晚到错误被消费 |
| Pop 与 Popup | 默认 Back 等待中切焦点；scoped 同步/异步 Pop 从 named Outlet 关闭真实 root Dialog；Host/Outlet/result/foreign ownership 一致 |
| LocalHistory | onRemove 同步切换 active Host，回执仍属于原 Host、无 Managed removal，之后真实 Pop result 正确 |

测试扩展期间校正了两个 fixture 条件：外部 redirect 的目标叶子必须允许 Deep Link；
注销/shutdown 结束未完成 Push 的既有契约为 `CCNavigationAdapterError`，需要在销毁前
安装错误处理。它们没有被误报为额外框架缺陷。串联测试在策略外断言收集到的元数据，
避免测试框架断言干扰被测决策 Zone。

## 最终检查

| 检查 | 结果 / 证据 |
| --- | --- |
| 专项 `fvm flutter test --no-pub packages/ccrouter_test/test/managed_navigation_partition_regression_test.dart --reporter expanded --timeout 30s` | **82 passed**，`matrix.log` |
| Framework + Demo + navigation_lab + analytics_flutter | **857 passed**，`flutter-tests.log` |
| analytics + analytics_firebase + tool Dart tests | **55 passed**，`dart-tests.log` |
| 根 Workspace `fvm dart analyze` | **No issues found**，`analysis.log` |
| `fvm dart run ccrouter_generator:ccrouter generate demo --check` | **生成物最新**，`generation.log`；复用 active Host watch cycle 14 的精确证据 |
| 文档检查、改动 Dart 文件 format、`git diff --check` | 通过 |

完整 Flutter 命令：

```sh
fvm flutter test --no-pub packages/ccrouter_test/test demo/test demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded
```

没有运行不存在的 `packages/ccrouter/test`。本轮不修改 Generator 或隔离 Analyzer Plugin，
未重复它们的全部专项矩阵，也未修改 Plugin pin。因 Demo watch 正在运行，采用正常
`generate demo --check` 的精确证据复用，不冒充执行了 `--no-cache --check`。

## macOS 真实窗口

对本工作树现有 `lib/multi_host_demo.dart` 运行执行 Hot Restart，Flutter 报告
`Restarted application in 1,715ms`，再通过 CUA 操作真实窗口。放大窗口显示左右两个 Host。

| 操作 | 观察结果 |
| --- | --- |
| 右侧 Host 入口 Go Level 202，再 Push Level 203 | 右侧进入正确页面，左侧仍为 Lab 首页 |
| 左侧 Host 入口 Go Level 101 | 左侧为 101，右侧 203 保留，截图确认没有串跳 |
| 右侧 AppBar Back | 只回到 202，显示 `push 完成 · result=null` |
| 左右交替各 Push 一次 | 左侧进入 102，右侧进入 203 |
| 右侧“Pop 并返回结果” | 右侧回 202，显示 `stack:203:done` |
| 左侧 AppBar Back | 左侧只回 101；最终截图为左 101、右 202，右侧 typed result 保留 |

交互后 Flutter run 控制台没有新的异常输出，Demo 保留运行。一次 CUA zoom 使用了
过期索引而失败；刷新完整 AX 后按实际 action 成功。一次坐标缩放判断不匹配未触发按钮，
随后按当前截图坐标成功；工具尝试不记作通过。

此段是本次修复相关的双 Host 交互验证，没有把窗口点击当作精确并发竞态复现：来源
策略及等待中切焦点的核心证据仍来自上述确定性异步测试。

## 生命周期与验收边界

没有发现本次修复新增的高置信度 not-disposed / not-GCed 问题。去重 key 在成功/失败
终态沿用已有 clear；Pop continuation 只捕获小型归属值，不在完成后访问当前聚合器状态；
无新增订阅或定时资源。注销/shutdown 晚到值/错误的专项测试及既有生命周期回归通过。

本轮没有完成新的 Android/iOS 真机侧滑/预测返回验收，也没有新增长期 heap、帧率、
内存压力或全按钮 monkey 认证。已有全量 suite 包含原来的语义 monkey 与手势取消/
提交/销毁回归；不能将其说成重新完成了所有平台真实手势测试。三类已复现缺陷已修复，
有限回归不等于保证再无其它问题。
