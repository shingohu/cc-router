# Managed 返回与平台入口修复验证

日期：2026-10-23。分支：`codex/managed-navigation-runtime`。

本轮落实[交叉场景审查](../20261023-cross-scenario-review/report.md)的四类修复，
保留原审查及失败证据，不修改历史结论。没有提交或推送工作区。

## 根因与方案选择

共同问题是操作、逻辑 Entry 和渲染容器的生命周期没有完全分离：等待中的请求可以覆盖
别人的结果或提交，外层容器仍渲染时子 Scope 已结束，页内历史又被误判成离开页面。

| 方案 | 收益 | 成本与问题 |
| --- | --- | --- |
| 应用页面防抖、强制焦点、延迟 dispose | 局部改动小 | 无法修正后端回执、平台提交和真实 Route 所有权，不采用 |
| 全局导航串行队列或新业务 API | 能统一排队 | 会改变独立 Host/Outlet 和普通 Push 的语义，重复返回还可能弹出下一页，不采用 |
| 现有 Runtime/Managed 内精确关联、Host 入口取消、渲染退出投影 | 保持业务调用，修正明确的框架缺陷 | 需覆盖并发、取消和卸载交叉路径，本轮采用 |
| 复制 Flutter Navigator.maybePop 实现 | 可插入自定义检查 | 易偏离 Flutter/OHOS 行为与未来 SDK，不采用 |

实施顺序为失败基线 → 结果与回执归属 → 平台取消传播 → Shell 渲染寿命 →
LocalHistory Guard → 中断/重入/GC 边界 → 全量回归及接入文档。

## 已修复

1. 同一个实际 Route 只保留一个未完成的 `maybePop`；重复调用被消费，不排队弹下一页。
   普通页面结果来自真实 `Route.popped`，移除回执由实际 `didPop` 与操作 Zone 关联。
   Shell 回执使用提交时实际选中的 child identity；不同 Outlet 互不串行。
   push/close/其它 Pop 不得被等待中的请求领取回执。renderer 退场和 shutdown 结束框架
   等待，即使应用 `willPop` 不返回；晚到值和错误被消费，Dart 应用工作本身仍由应用负责。
2. 每个 Delegate 拥有自己的 location cancellation token，新 location 先取消旧等待，
   即便新 URI 等于当前 URI。取消贯穿 Interceptor、redirect、Failure Policy、defer/resume，
   Adapter 提交前再次检查；superseded 不进入 Failure Policy 恢复。
   不改变普通业务 Push 并发，不取消其它 Host 的请求。
3. 原生 Shell Pop 保存实际已渲染的分支 Pages 和选中 Outlet，子 Scope 跟随外层 Route
   的退出寿命；结果只返回给选中分支，其它分支得到 null。退场中重入会退休旧投影，保留
   tombstone 到外层结束，避免旧容器重新读取 live Store、争用 Navigator Key。
   renderer 代次检查防止旧 detach 清理新 owner；完成、卸载和 shutdown 都解绑并清空持有。
4. Host-only `CCNavigationPopTarget.handlesPopInternally` 表示 LocalHistory 页内消费，
   Core 和原生返回跳过 Managed 离页 Guard。Flutter 本地 gate 仍然有效；等待中历史被
   移除时，真正离页仍需检查实际目标 Guard。MultiHost 转发该字段。

业务 `CCRouter.navigator` 调用签名不变。Host-only `openRouteInformation` 增加可选取消
参数；业务 barrel 不开放 Runtime/Host SPI。README 中英文、集成 Skill、implementation
patterns 与 review checklist 已同步。没有修改生成器声明或手改生成物。

## 回归与所有权证据

修复前首批正式回归 **7 项全部失败**，见 `baseline.log`。补充异步测试时使用真正阻塞的
Flutter `willPop` gate，确保 push/unmount 确实发生在等待期间，不依赖微任务偶然顺序。
另两项新失败基线证明，未完成的 willPop 原先会阻塞框架返回直至用户 Future 完成。

新增正式文件：
`packages/ccrouter_test/test/managed_operation_ownership_regression_test.dart`。
其 **29 项通过**，覆盖：

- 并发同页、独立 Outlet、等待中的 pop/push/close/unmount；
- never-completing willPop 下的卸载/shutdown；
- native/managed LocalHistory、历史等待中移除；
- native/managed Shell 退出中间帧、真实 result、分支 Scope、选中 child 回执；
- 退出中 push/reenter/unmount/shutdown，以及 Adapter 仍活跃时旧 Route 的 weak-reference GC；
- 初始链接与新链接、相同当前 URI、晚到 redirect、Failure Policy recovery、defer/resume；
- 取消 listener 抛错、MultiHost 入口隔离、shutdown 与晚到策略错误。

本轮没有发现新增所有权对象存在已证明的残留引用：Pages 在完成或退休时清空；render
completion callback、token listeners 和 timer 在终态解绑；`_pendingPops` 在卸载/销毁后
结束等待并移除。Scope disposal 与 weak-reference GC 均有专项证据。这不等于完成了
所有平台的长期 heap/性能认证。

最终验证：

| 检查 | 结果 |
| --- | --- |
| Framework + Demo + navigation_lab + analytics_flutter | **775 passed**，`flutter-tests.log` |
| analytics + analytics_firebase + tool Dart tests | **55 passed**，`dart-tests.log` |
| 根 Workspace `fvm dart analyze` | **No issues found**，`analysis.log` |
| `generate demo --no-cache --check` | **生成物最新**，`generation.log` |
| 改动 Dart 文件 format、`git diff --check` | 通过 |
| 文档检查 | 通过 |
| 最终源码 `flutter build macos --debug --no-pub` | 通过，`macos-build.log` |

框架测试执行路径为 `packages/ccrouter_test/test`。本轮不涉及 Analyzer Plugin，未运行
隔离 Plugin suite 或变更 Demo pin；生成器生产代码未变化，未重复其完整专项矩阵。

## macOS 与平台边界

macOS Demo 已成功构建并启动，CUA 能读取 `ccrouter_demo` 窗口及完整首页截图：
首页显示 6 Components、1 Route Entry、1 Backend Entry，未见黑屏或 Flutter 运行异常。
首次 run 与 generation check 并发导致 watch-lock 冲突；等待 generation 完成后重跑，
watch ready 和 macOS build 成功。该冲突没有被报告成框架功能失败。

尝试进入“展示”：Accessibility 点击未改变页面，坐标点击报
`Computer Use server error -10005: noWindowsAvailable`；键盘 Tab 也未改变焦点。
因此本轮只确认构建、启动和首页，**没有完成真实窗口的 Shell/多 Host/自适应交互验收**，
不把自动化测试冒充点击通过。相关交叉场景由上述 Widget 回归覆盖。

设备清单显示 Android NE2211、Android/iOS simulator 和 OHOS 设备；本轮没有执行新一轮
Android/iOS 真机返回手势或性能/内存验收。之前的手工记录仍是历史证据。

## 补充 macOS 真实窗口验收（本日后续）

用户将窗口移回可捕获的显示器后，CUA 恢复操作。本段补充后续结果，保留上面的首次
阻塞记录。先对运行中的 `lib/main.dart` Hot Restart，再用真实按钮验收；之后正常退出
应用，执行 `fvm flutter run -d macos -t lib/multi_host_demo.dart --no-pub` 切换入口。
两次运行均使用本工作树源码，没有修改生产代码或生成物。

| 场景 | 实际窗口结果 |
| --- | --- |
| 普通 Shell | Feed → Detail #7 → Feed；Root 透明海报覆盖、关闭后恢复 Feed；切 Settings 后退出 Shell，首页为 1 Entry |
| 透明页视觉 | 截图确认海报、暗色遮罩、底层 Feed 和底栏均可见，未出现黑屏 |
| Stateful Shell | Home Detail #42 → Activity 计数增加至 2 → Profile → Activity 仍为 2 → Home 仍在 Detail #42 |
| 跨 Shell | 从 Workspace Detail Push 普通 Shell，再返回恢复原 Detail；返回 Home 后退出到 Lab，无多退一层 |
| LocalHistory | 打开 Scaffold BottomSheet，通过返回箭头关闭；Lab 保留，Entry 仍为 1 |
| PopGuard | 未保存时“尝试返回”和“模拟系统返回”均保留表单；保存后正常退出，首页为 1 Entry |
| 策略失败 | Cancel 显示 CCRouteCancelledError；Timeout 显示 CCNavigationInterceptorTimeoutError；均不进入新页 |
| Defer 取消 | Pending 从 0 → 1 → 0，显示 CCRouteCancelledError，页面继续可操作 |
| covered close | Level 1 打开 Level 2 后按 identity 定时关闭 Level 1；Level 2 保留、Entry 列表减少一项；关闭 Level 2 直接回 Lab，显示 exact:1 |
| Typed result | Detail #42 参数显示正确，确认后调用方显示 detail:42:confirmed，首页为 1 Entry |
| 多 Host 隔离 | 右侧内容进入 Level 1，左侧仍为首页；左侧建立 Level 101 后，右侧 Push 到 Level 2 并返回 Level 1，左侧保持 Level 101 |
| 双 Outlet 定向 | 列表选择 Item 3，右详情同步；详情按钮 Push Level 3 到 adaptive.detail，左列表仍可见；返回恢复 Item 3 |
| 布局与历史 | 551 宽 compact 下 Item 4 详情位于 adaptive.list，Push Level 4；拉宽到 1001 后，左侧 Level 4 保留、右侧显示 Item 4；左侧 Pop 后缩回 compact，恢复 Item 4 详情，再返回列表 |
| 模拟 hinge | expanded 下在详情栈存在时开关可用；551 宽 compact 下启用后 Active Outlet 为 list + detail，Item 4 保留；关闭后回到单栏列表 |

窗口缩放期间还观察到 `host.primary` 保持不变。最终 Multi Host Demo 保留运行，停在
compact 单栏列表。上述交互中 Flutter attach/run 控制台未输出新的 Flutter exception。
个别 CUA AX 点击没有改变画面，改用最新截图定位后验证；中途捕获发生 -3812、
noWindowsAvailable，重新关联并置前后恢复。这些工具失败没有记作功能通过或框架缺陷。

本补充关闭了四类修复关联的 macOS Shell、多 Host、自适应交互缺口。它是有界的
真实场景回归，**不是本日全部按钮遍历、monkey 压测、heap/帧性能认证**，也没有新增
移动真机手势结论。Scope 仅释放一次和异步并发归属仍以专项自动化证据为准，不能仅凭
窗口画面推断。

## 仍需完成的验收

在移动真机复验侧滑取消/提交和预测返回，特别观察是否一次手势只移除一次、结果一致、
Scope 仅释放一次；全量按钮遍历和长期性能/内存认证也不在本次补充的覆盖声明内。
这些是平台验收边界，不影响上述已通过的正式自动化修复结论。
