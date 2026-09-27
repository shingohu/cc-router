# macOS Monkey 验证记录

## 结论

macOS 没有 Android `adb shell monkey` 的直接等价物。Android Monkey 依赖
Activity/Window 输入注入，不能覆盖 Flutter macOS 应用；本 Demo 采用两层互补方案：

1. 固定 seed 的 Flutter Semantic Monkey，随机操作语义控件并持续校验 CCRouter 状态不变量。
2. 真实 macOS Accessibility Monkey，在实际窗口中执行点击、返回、开关、滚动和窗口缩放，
   再从 Flutter 运行日志检查渲染异常与未处理错误。

随机测试用于扩大组合覆盖，不替代 Route、PopGuard、Interceptor、生命周期和结果类型的
确定性单元测试。

## 验证环境

- 日期：2026-09-28
- 系统：macOS 26.6.1，arm64
- Flutter：3.41.10-ohos-1.0.0
- Dart：3.11.5
- Backend：`CCGoRouterBackend.managed`，`go_router 17.5.0`
- 应用：`demo/build/macos/Build/Products/Debug/ccrouter_demo.app`

## Semantic Monkey

测试位于 `demo/test/monkey_test.dart`。它使用固定 seed `20260928`、`13377574` 和
`314159`，每组执行 120 步，随机选择：

- 当前可命中的 `ListTile`、Button、Switch、IconButton、BackButton 和 CloseButton；
- 六个主功能 Tab；
- Router 级系统返回；
- 主滚动区域滚动；
- 720x620、960x720、1280x900 和 1540x960 四档窗口尺寸。

每一步都检查：

- Managed Route Entry ID 和 Backend Entry ID 不重复；
- active Route Entry 不处于 removed/disposed 状态；
- Entry 的 Host/Outlet 身份完整；
- Flutter 没有未处理异常。

用例结束后卸载 Widget，并由应用所有者显式调用 `CCRouter.shutdown()`，确认 Runtime 已终止。
这也验证 Deferred Navigation 的定时器能由 Runtime shutdown 统一取消。

另有两个 DPR 2、980x700 物理像素的定向用例，验证 PopGuard 和 Failure fallback 在约
490x350 logical pixels 下仍可滚动和操作。

运行：

```sh
fvm flutter test demo/test/monkey_test.dart
```

本轮结果：5 个用例全部通过，其中随机路径共 360 步。

## 真实 macOS Monkey

真实应用使用固定 seed 执行两轮有效的 60 步 Accessibility 操作。覆盖包括 Typed Push、
Service Contract、Interceptor Proceed/Cancel/Redirect、Failure fallback、Fade Page、
Managed Dialog、生命周期与诊断 Tab、PopGuard 拒绝/保存/退出、普通返回和滚动。

最终状态感知轮次明确验证：

- PopGuard 在未保存时拒绝返回，保存后可以退出；
- Interceptor Cancel 返回标准失败且不创建页面；
- Redirect 目标可到达并正常返回；
- 随机操作没有 Accessibility action error；
- Flutter 日志没有新增未处理异常、重复 GlobalKey、`setState after dispose` 或失效
  `BuildContext` 错误。

测试器必须使用完整 Accessibility tree 并按页面语义节点精确识别状态。增量 AX diff 或
仅按包含文本判断页面，会导致错误的覆盖统计；这些 preliminary run 不计入有效步数。

## 已发现并修复

1. PopGuard 页面在约 490x350 logical pixels 下底部溢出 33px。
2. Failure fallback 页面在相同尺寸下底部溢出 45px。
3. Demo 的部分 fire-and-forget Push 只使用 `unawaited` 或直接丢弃 Future。随机测试在页面
   未返回时关闭 Runtime，会正确收到 `CCNavigationAdapterError`，但应用未消费该错误，形成
   未处理异步异常。

两处都属于 Demo UI 自适应缺陷，不是 Route Scope、PopGuard 或 Failure Policy 的框架错误。
页面已改为 `SafeArea + LayoutBuilder + SingleChildScrollView`，同时保留大窗口居中布局；
对应 DPR 2 定向测试已加入回归。第三项属于应用异步所有权问题；Demo 现通过统一的
`observeDemoOperation` 消费结果，并把失败类型写入现有应用日志。Core 继续在 shutdown 时以
明确错误结束 pending result，不改为静默成功。

## 框架层判断

本轮没有确认新的 CCRouter Core 缺陷。Route Entry identity、Backend ownership、PopGuard、
Interceptor、Deferred Timer 和 Runtime shutdown 在随机组合下保持一致。

后续可在 `ccrouter_test` 增加测试专用 matcher，统一断言 Entry identity、Host/Outlet 完整性、
终止状态残留和 shutdown 清理。当前不应把 UI Monkey、窗口缩放或 Accessibility 驱动加入
Core，也不应仅为本 Demo 新增公开诊断 API；这些能力属于应用测试层，待多个生产项目出现
相同需求后再收敛公共测试工具。

## 未覆盖边界

- 本轮 CUA 对应用前后台切换不稳定，没有把该项计入自动化结果；既有手工验证仍记录在
  `route_validation.md`。
- 未覆盖 macOS 原生多 Window、多 Flutter Engine 或 Host 跨 Window 迁移。
- 未覆盖 Android Predictive Back、iOS 交互式侧滑进度和平台中断恢复。
- 随机测试不能证明所有 typed result、重定向链和并发时序；这些继续由专项测试负责。
