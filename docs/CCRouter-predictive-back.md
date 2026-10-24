# CCRouter 返回协调与平台手势

状态：2026-10-23，原生 Managed 是当前内置 Backend。GoRouter 兼容包、attach 和旧 Demo 入口
已移除；历史验收不等于对当前所有设备重新验收。

本文合并系统/业务返回、iOS Cupertino PopGuard 与 Android 预测返回的现行规则。
原独立手势设计、评估和专项分析保留于[合并归档](archive/20261024-consolidation/README.md)。

## 问题与方案选择

Flutter 负责平台转场和唯一一次 Pop，CCRouter 负责精确 Entry 身份、Guard、typed result
与 Route Scope。让两者分别退栈会造成偶发连续退出两层；因此 bridge 只观察与协调，
绝不在 Flutter 已提交的手势后补一次业务 Pop。

| 方案 | 收益 | 限制 |
| --- | --- | --- |
| Flutter 默认行为 | 最少接线、保留系统动画 | 没有 CCRouter 手势阶段诊断 |
| Host 可选自动桥（采用） | 复用 Flutter 动画和 backend-neutral Entry 协调器 | 必须按 Route、Theme、平台明确限定支持范围 |
| 业务页手工转发 | 可作局部平台实验 | 容易重复提交、错绑实例，不推荐作为默认接入 |

## Managed 接入

Host 使用 `CCManagedRouterApp(enablePredictiveBack: true)`，或将相同配置传给
`CCManagedRouterBackend`。自定义 backendFactory 必须转发开关。
Android 的有效 application 还须配置
`android:enableOnBackInvokedCallback="true"`；框架不替应用更改 Manifest 或 targetSdk。

默认 false 不创建 CCRouter gesture observer 或阶段状态机，也不会禁用 Flutter 自身的
预测动画。true 时，Managed 默认 opaque Android Material Page 自动接线，支持原生
`PredictiveBackPageTransitionsBuilder` 和
`PredictiveBackFullscreenPageTransitionsBuilder`。自定义 Route 可通过
`CCFlutterRouteFactory` 的 `predictiveBackHandler` 接线，需独立验证其转场。
自动接线后禁止再手工报告同一序列。

Host-only `CCPredictiveBackCoordinator`、handler 与桥类型从 `ccrouter_host.dart` 导出；
业务页面只使用业务 Facade，不持有这些 SPI。开启与回退通过重建 Backend 生效。
`adapter.predictiveBackFallbacks` 最多保留 100 条脱敏记录；关闭时为空。
通用历史使用 Runtime 的 `recentBackendNavigationEvents`，旧 GoRouter Adapter 的
`lifecycleEventCapacity/lifecycleEvents` 已移除。

## 身份、提交与清理

1. start 捕获具体 Route、backendEntryId 和 Outlet，按当前 Theme、平台、可见性及门禁判断。
   update 仅观察动画进度，不完成结果、释放 Scope 或产生正式 PageHide。
2. cancel 恢复 Flutter 动画且只报告一次取消。开始或取消不自动触发业务确认 UI。
3. commit 前重查原实例、当前 Route、LocalHistory、PopScope/Form 与 Outlet 身份。
   Flutter 执行唯一一次 Pop；Navigator Observer 确认同一 Entry 移除后才报告 committed。
4. 重复终态、迟到提交、push/replace/go/reset、弹窗覆盖、Outlet 切换、Theme 改变或
   Adapter dispose 不能结束另一页的 result/Scope，也不能猜测当前栈顶再 Pop。
5. 祖先 Navigator 弹窗覆盖时，子页拒绝新手势。预览中发生覆盖会永久使原序列失效，
   即使弹窗先关闭也不恢复原提交。相关 Outlet 必须保留框架 Observer。
6. Adapter dispose 清空 Route、listener、Runtime evaluator 与 Backend callback。
   平台尚欠终态时，只保留无导航能力的终态消费 observer，收到终态或新 start 后移除，
   平台丢失终态时最多保留 30 秒；Timer 不保留已结束 Host。
7. 自定义 Host 保留的 Route 在原 handler 退役后仍先拒绝旧提交；下一次新 start 可取消
   残余预览并恢复 Flutter 行为。读取 eligibility 不改变进行中手势所有权。
8. Theme 在预览期间切到不支持的平台或转场时，Route 用 Flutter 原取消 hook 恢复动画和
   Navigator 手势状态。恢复原 Theme 不使旧预览再次有效。监听器失败不跳过清理。

## Android 与 iOS 边界

### 同步 Guard 与本地返回规则

`CCPopGuard` 是同步、只读、backend-neutral 的退出决策；异常 fail closed，不能等待 I/O、
显示 UI 或重入导航。Guard 读取实际退出 Route 的 Host/Outlet/backend identity，不按全局焦点
猜测。AppBar、系统返回、业务 maybePop、侧滑和预测返回共用精确目标与结果协调。

LocalHistory-only Back 不退出底层 Managed 页面，绕过其 leave Guard，保留 Entry/Scope。
Foreign Popup 的返回由其真实 Navigator 所有者处理。框架 Guard 放行仍须服从本地
PopScope/Form；不能仅靠 Observer 在移除后补 veto，也不能在 Flutter 提交后再执行一次 Pop。

### Android 预测返回

Android Guard、Modal、透明页面、LocalHistory、自定义转场及不支持的 Theme 使用 fallback；
不能据此承诺所有路径都有预测阶段事件。局部 PopScope/Form 仍可拒绝系统返回与 maybePop，
框架 Guard 允许不等于覆盖局部拒绝。确认 UI 属于页面，确认后显式 Pop。

### iOS Cupertino 返回

iOS 默认 opaque Managed 页面在交互开始前同步评估 Guard：拒绝时页面不移动，允许时
保留 Flutter 跟手转场，取消保持精确 Entry，提交只退出一层。临时门禁在取消、拒绝启动、
Route 移除和 Backend dispose 时关闭。自定义转场仍使用保守 fallback。
iOS 侧滑不是 Android 预测返回开关的同义词，必须分别验收。

框架使用 Route 级 `PopEntry` gate，只为 `hasPopGuard` 的精确受保护 Route 安装。无 Guard
页面保留 Flutter 默认手势。eligibility 查询放行后，gate 仍绑定同一 Route；未真正开始、取消、
提交、Route 卸载、Guard unbind 或 Backend dispose 时都必须复位/释放。自定义转场、Modal、
身份未关联或正在结构切换等不能可靠处理的情形采用保守 fallback，不改变页面展示类型。

系统返回的临时放行与最终 `popDisposition` 检查保持同步，避免跨 await 被另一返回请求借用。
已完成 legacy willPop 判断的路径不再二次调用同一异步判断；目标改变即放弃旧提交。

### 页面拥有的异步确认

页面使用 Flutter `PopScope` / `Form` 或显式离开按钮拥有确认 UI。合并重复请求；确认取消时
保持 Entry、Scope 与结果不变。确认后检查 mounted、更新业务允许退出状态，再用页面 Context
调用 `CCRouter.navigator.pop`；原同步 Guard 仍有效，确认不是绕过其它 Guard 的凭据。
框架没有公开 UI 协调器或 resume-token API。

iOS 的 `canPop: false` 可禁用边缘侧滑而完全没有拒绝回调，不能承诺滑动时自动弹框。
需要提供显式保存/离开入口，允许后再恢复交互。页面不必为了框架 Guard 重复接线，业务确认
UI 则继续由业务页面管理。

MultiHost 仍通过当前活动 Host 选择无 Context 的系统返回；同时可见页面使用 Context
定位到具体 Host/Outlet。原生平台多窗口的全局手势仲裁不在本实现范围内。
第三方 WebView、IME、返回桌面与自定义预测转场需要应用单独验收。

普通 Pop 先完成逻辑 Entry/result，Route Scope 保留到退出渲染结束；renderer 卸载与逻辑移除
不同，shutdown 不等待下一帧。生命周期细则统一见[Service 生命周期](CCRouter-service-lifecycle-design.md)。

## Demo 与验证

在 demo/ 中运行：

```sh
fvm flutter run -t lib/main.dart
fvm flutter run -t lib/main_predictive_back.dart
# 旧 Managed 名称保留为同一路径的别名
fvm flutter run -t lib/main_managed_predictive_back.dart
fvm flutter test test/predictive_back_demo_test.dart
```

普通入口默认关闭；开启入口使用相同页面和原生 Managed Backend。
使用 Push + typed result 验证取消仍在、提交一次；策略页验证未保存拒绝与保存后允许；
Shell/StatefulShell 验证 Outlet、分支切换与迟到提交。
Demo Android Manifest 已显式启用系统回调，但复制 Dart 入口不替代目标 Host 的合并检查。

- 框架专项覆盖动画进度、取消/提交、重复终态、导航打断、Theme 改变、祖先弹窗、
  本地门禁、退役 handler、跨 Host 迟到消息、资源释放；见
  [框架回归](../packages/ccrouter_test/test/predictive_back_test.dart)。
- Demo 场景覆盖真实业务页面与结果、Scope；见
  [Demo 回归](../demo/test/predictive_back_demo_test.dart)。
- 历史三星 Android 16 验证见
  [设备记录](validation/android_predictive_back_samsung_20261015.md)。
- Managed Android/iOS 真机验收与限制见
  [平台记录](validation/managed_navigation_platform_acceptance_20261022.md)。
- 本轮删除与 macOS 验证以
  [退役记录](validation/go_router_retirement_20261023.md)为准。

Widget 回归与 macOS 不替代手机跟手观感；历史设备通过也不扩大到 Android 全版本、
全部 OEM 或 iOS 全版本。此前 OHOS HAP 构建被外部 embedding 的 AutoFill API 与本机 SDK
不匹配阻断，该限制未在此次删除中修复。

返回回归还须交叉覆盖 Guard/local gate 的允许与拒绝、重复请求、取消/晚到提交、弹窗与
LocalHistory、跨 Host 焦点、Shell 切换、Route 移除、renderer 重挂与 shutdown，断言实际页面、
typed result 和 Scope 只结束一次。最新源码与历史设备结果分别从[验证索引](validation/README.md)查阅。

## 回退

先对普通页面启用，逐项验收结果、Scope 和曝光时机。需要回退自动桥时设为 false 并重建
Backend，同时撤掉自定义 Route 的 handler 接线；不要在桥内额外执行 Pop。
GoRouter 已退役，源码可从 Git 历史恢复，但不再作为当前运行时开关维护。
