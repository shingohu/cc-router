# CCRouter Android 预测返回自动桥

状态：2026-10-15，已实现可选自动接线；平台验收范围见下文。

## 问题与方案选择

Flutter 已负责默认 Material 页面预测动画和实际返回。原 CCRouter bridge 需要 Host
手工报告阶段，不能仅凭 `supportsPredictiveBack` 判断页面已自动接线。

| 方案 | 收益 | 成本与限制 |
| --- | --- | --- |
| 直接沿用 Flutter | 最小改动，保留原生返回体验 | 没有 CCRouter 自动阶段观察 |
| 可选 Route / Adapter 自动桥（本次采用） | 复用 Flutter 动画、现有 Entry 身份和清理协议 | 中等成本；只覆盖明确支持的 Route / Theme |
| 应用 Host 手工转发 | 可做局部平台试验 | 容易重复提交、绑定错误 Route，应用维护成本高 |
| 新 Core Guard 预判协议 | 可进一步探索 Guard 页交互动画 | 需要独立的策略失效和异步确认设计，本次暂缓 |

不修改业务 Contract、生成器生产代码、Android targetSdk 或 Manifest。业务页面无需
导入 Host SPI，也不应为了获得动画而放宽 `PopScope.canPop`。

## 开关与支持范围

`CCGoRouterApp`、`CCGoRouterBackend.managed/attach` 的 `enablePredictiveBack`
默认仍为 `false`。

- **false**：沿用原 `MaterialPageRoute` / `CupertinoPageRoute` / 自定义 Route
  构造，不创建 CCRouter bridge、手势 observer 或阶段状态机。Flutter 自身预测动画
  仍可能存在；此开关不负责禁用 Flutter 或 Android 的预测返回。
- **true + managed 默认 Page**：默认 opaque Android Material 页面自动接线。
  支持 Flutter 原生 `PredictiveBackPageTransitionsBuilder` 和
  `PredictiveBackFullscreenPageTransitionsBuilder`。
- **true + attach / override / Shell 自定义 Page**：Host 显式传
  `predictiveBackHandler: adapter.predictiveBackBridge` 给 `ccGoRouterPage` 或
  `CCFlutterRouteFactory.createPage`。Demo 的 Shell / StatefulShell 提供实际示例。
- Cupertino、iOS/OHOS、模态页、透明页、自定义转场和非预测 Theme 保留原路由路径。
  未接线的 Page 不会被自动改写，不承诺阶段事件。
- 框架 PopGuard、局部 `PopScope` / `Form`、`LocalHistoryEntry`、foreign Popup
  保留自己的门禁与返回消费路径。Guard 页继续非交互 fallback；fallback 不保证报告
  `predictiveBack` 来源或自动桥阶段。

Host 接线类型 `CCFlutterPredictiveBackHandler` 从 `ccrouter_host.dart` 导入，
不从业务 `ccrouter.dart` 导出。自定义 Backend factory 需要传递配置开关。
开启和回退通过重新创建 Host / Backend 生效，不支持原地切换已有 Route 的 handler。

自动桥拒绝 start 时，Host 可读取 `adapter.predictiveBackFallbacks`。原因是稳定枚举，覆盖
button event、无已接线路由、Route 不可用、Theme 不支持、Route 非 current、本地门禁、
非活动 Outlet 和未知 managed Entry。历史与 `lifecycleEventCapacity` 共用容量，每次 start
最多记录一条，不记录 update；字段仅包含 reason、Host、Outlet 和 timestamp，不包含 URI、
arguments、Extra、Widget、BuildContext 或业务结果。关闭开关时 getter 返回空列表，Adapter
不分配该历史。

## 身份、提交与生命周期

1. 私有 Material Route 子类通过公开的 Flutter gesture hooks 报告阶段，始终调用
   Flutter 原有动画实现。平台 progress 为 `1 - routeProgress`。
2. start 捕获具体 Flutter Route、backendEntryId 和 Outlet。update 只观察进度，
   不导航、不完成 typed result、不释放 Scope、不将预览视为正式 show/hide。
3. cancel 只恢复动画并报告一次取消。commit 前重查原 Route 是否仍为当前页、
   `popDisposition`、LocalHistory、Adapter 和 Outlet 身份；策略中途关闭则取消。
   不在手势 start 或取消时自动触发业务确认回调。
4. Flutter 执行唯一一次 Pop；Navigator Observer 确认相同 managed Entry 实际移除后，
   bridge 才报告 committed。Core 对已清理的具体 Entry 幂等处理，不能猜测或再退栈顶。
5. push、replace、go、reset、Popup 覆盖、Outlet 切换和 Adapter dispose 使旧手势失效。
   取消上下文可保留到原 Route 终止，以拒绝迟到 commit；Route dispose 释放其引用。
6. 开启路径检查祖先 Navigator 的当前 Route。根 / 祖先弹窗已覆盖嵌套页面时，底下页面
   不接受新手势，返回交由弹窗 fallback。手势中观察到祖先覆盖则使旧预览永久失效，
   弹窗先关闭也不恢复该次提交；相关祖先 Outlet 必须保留导航 Observer。
7. attach 模式允许应用 Router 在 Adapter 销毁后存续。handler 的 `isActive` 变为 false，
   旧手势仍拒绝 commit；Route 在下次新手势开始时解除旧 handler，恢复 Flutter 返回行为。
   该判断不重建 Route，也不让已失效的旧序列再次生效。
8. Adapter 构造将 Navigator Observer listener、RouterDelegate listener 和 binding observer
   作为一个事务注册；任一步失败会逆序清理。自定义 handler 的 `isActive` 抛错时，Route
   解除故障 handler 并恢复 Flutter 返回，Host 观察故障不会阻断动画或 Pop。
9. start 按当前 `Theme.platform` 校验实际转场，不能仅凭 Android builder 的配置接受手势。
   预览期间切换到非 Android 平台或非预测转场时，Route 在 rebuild 后通过 Flutter 原有取消
   hook 恢复动画并结束 Navigator 手势状态，即使旧 detector 已被销毁。取消不完成结果或
   Scope；bridge 继续消费旧终态，恢复预测 Theme 也不恢复旧预览，新手势按当前 Theme 处理。
   延迟取消绑定原手势序号，Route 已销毁或新手势已开始时不再操作。

仅 Route hook 不能处理所有迟到平台消息：Route 在手势中被替换后，Flutter detector
可能已移除，迟到 commit 会进入普通返回 fallback。因此开启时增加一个 Adapter 拥有的
`WidgetsBindingObserver`，仅对当前、可交互、身份明确且使用受支持原生预测 Theme 的
Route 接受 start，使该次手势持续被消费。它不驱动动画或导航；Guard、foreign、
自定义 Theme 和三键返回不由它接管。关闭时不注册该 observer。

每个 Adapter 拥有 bridge、Route 注册集合和监听器；Adapter dispose 立即清空
Route / 手势 / listener / Runtime evaluator / Adapter 引用。若平台仍欠一次手势终态，
只保留无导航能力的终态消费观察，避免旧 Host 的 commit 误退新 Host；收到 commit、
cancel 或下一次 start 后移除，平台丢失终态时最多保留 30 秒并清理 Timer。移除在
microtask 执行，避免修改 Flutter 正在遍历的 observer 列表。超过该清理窗口的异常迟到
平台消息仍由 Flutter fallback 处理。此窗口不拦截下一次正常手势。
监听器失败隔离，不阻断 Flutter 清理。自动接线页面禁止再手工转发同一序列。

本次支持现有单活动 Host / Outlet 路由选择；多个同时可见、独立导航 Host 的系统返回
全局仲裁不属于本实现。第三方自定义预测转场应独立评估，不能仅继承原生 builder 就
宣称兼容。

## Demo 与回归

在 `demo/` 中使用两个入口对比：

```sh
fvm flutter run -t lib/main.dart
fvm flutter run -t lib/main_predictive_back.dart
fvm flutter test test/predictive_back_demo_test.dart
```

普通入口保持 false；开启入口共享同一套初始化、页面与 Backend。导航页的
`Push + typed result` 可验证取消后保留原页、提交后仅退出一层；诊断事件显示
`Predictive back · started/cancelled/committed`，不逐帧记录 update。
自动桥降级原因可从 `backend.adapter.predictiveBackFallbacks` 读取。
策略页验证未保存表单拒绝和保存后 fallback。Shell / StatefulShell 验证具体 Outlet
及分支切换后的迟到提交。

本次自动化验证：

- 框架完整 Flutter suite：475 项通过，其中预测返回专项 43 项。
- Demo 完整 suite：58 项通过，其中新增预测专项 12 项。
- 生成器完整执行：523 项通过、28 项失败、1 项远程网络冒烟按默认配置跳过。
  失败来自 worktree 的 `.git` 文件定位和嵌套 Dart Pub 缺少 Flutter SDK 上下文；修复
  三处测试夹具的 worktree 定位后，设置 `FLUTTER_ROOT` 指向实际 FVM SDK，重跑失败
  所在两个文件，37 项全部通过。未修改生成器生产逻辑。
- 覆盖 false 原生 Route 类型、动画、typed result、资源释放；true 取消、进度、提交、
  重复终态、连续手势、动态门禁、手势中导航、LocalHistory、Popup、Adapter dispose、
  attach 显式接线、左右边缘、三键 fallback、iOS/OHOS 路由族，以及 Host 重建后的
  迟到提交、取消、连续新手势和丢失终态后的观察清理。
- 根 Dart analyze、Demo Flutter analyze 通过；Android 开启入口 debug APK、
  iOS debug 无签名构建通过。

Review 修复新增 10 个边界回归：修复前 false 对照通过、其余 9 个失败；修复后全部通过。
覆盖 attached Router 销毁 Adapter 后的新手势、旧 commit/cancel 后恢复，以及两种 Shell
的祖先弹窗在开始前、过程中、提交前已关闭三种时序。此轮未重新执行真机手势验证，
以下设备记录对应 review 修复前版本。

本轮再新增 4 个核心边界回归：Adapter 构造失败时原子回滚注册、`not-GCed` 泄漏追踪确认
无 binding observer 保留链、自定义 handler 活性读取抛错时释放并恢复 Flutter fallback，以及
降级原因按 `lifecycleEventCapacity` 保持有界；同时在现有 false、非预测 Theme、三键和 attach
未接线用例中验证空历史或精确 reason。

Theme 边界修复新增 6 项回归：修复前关闭开关的对照通过，其余 5 项失败；修复后全部通过。
覆盖页面创建后的平台 Theme 切换、手势中的平台/转场切换、动画和 Navigator 手势状态恢复、
commit/cancel 与重复终态、预测 Theme 在旧 commit 前恢复，以及后续独立手势。取消不改变
typed result、Route Scope 或正式页面生命周期。此轮框架 475 项、Demo 58 项、根和 Demo
analyze、`ccrouter generate demo --check` 均通过；未重新执行平台构建或真机验证。

Android 16 三星 SM-S911U1（手势导航，Demo targetSdk 36）补充完成真机 Android
触摸输入注入验证：开启时左右缘取消、提交、重新进页后的独立手势、入场未稳定时的
普通 fallback，以及 Guard 未保存拒绝 / 保存后放行；关闭时取消保留页面、提交仅退
一层且没有 CCRouter 阶段事件。取消无正式 Hide / result 完成 / dispose，提交对应
副作用各一次。此轮未改变系统手势设置、targetSdk 或 Manifest，结束后恢复开启版本。
见 [设备验证记录](validation/android_predictive_back_samsung_20261015.md) 与结构化证据。

真机输入注入经过 Android 手势识别与 Flutter embedding，未直接注入 Flutter back
channel；仍不代表人工动画观感、IME、WebView、返回桌面或 Android 13/14/15/16
完整平台矩阵已经验收。

OHOS 构建未通过：外部 Flutter embedding 的 `OhosAutoFillHelper.ets` 与本机 SDK
AutoFill API 不匹配（`AutoFillType`、`ViewData`、`requestAutoFill` 等）。本次不升级
SDK、不改平台代码；OHOS Route 类型回归通过不能替代 HAP 构建或设备验收。

## 灰度与回退

先对普通默认页面启用，业务原有 gate、WebView 历史、教程返回结果等维持自身约束；
按真实页面逐项验证 typed result、Route Scope 和曝光时机。回退将开关恢复为 false 并
重建 Backend，移除自定义 Page 的自动 handler 接线。系统预测启用配置和业务页面
交互优化分别验收、分别回退，不在 bridge 内额外执行 Pop。
