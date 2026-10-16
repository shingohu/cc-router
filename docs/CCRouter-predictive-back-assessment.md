# CCRouter 完整接入 Android 预测返回评估

评估日期：2026-10-15。状态：方案评估，未实施自动桥接，未变更生产代码、Manifest 或 targetSdk。

输入为 LiberLive 的 `docs/ccrouter_predictive_back_assessment.md`，其中的实施步骤作为评估材料，不作为本次执行指令。
源码核查起点为 `304aab269a3b1a5d1f2ed4e8fe132430918272f6`；评估期间仓库新增文档提交
`cd03e48f75585c91c6118ddb9d11421f3f8b7b1f`。本报告涉及的框架生产文件相对输入文档的
`4fb092897a589d7f3fb96d0a8069c0127a4a8e22` 无变更。
实际工具链为 Flutter `3.41.10-ohos-1.0.0`、Dart `3.11.5`，由 FVM 的
`ohos/oh-3.41.9-release` SDK 提供，GoRouter 为 `17.5.0`。

## 1. 问题分析与结论

**具备接入基础，推荐在 Flutter Route 与 GoRouter Adapter 边界补齐可选自动桥；当前不能宣称完整支持，也不能将所有页面都有交互动画作为正确的完整性标准。**

应分别定义以下验收层次：

| 层次 | 当前状态 | 完整接入的要求 |
|---|---|---|
| 普通页交互动画 | 已有 Flutter 能力 | 系统实际派发事件、Material Route、兼容转场、允许退出；取消和提交均正确 |
| CCRouter 阶段观察 | 有手动桥，无系统自动接线 | 自动关联 start/update/cancel/commit 与准确 Route 身份，终态最多一次 |
| 业务返回安全 | 已有 Guard、PopScope、Scope reconciliation | 拒绝、局部历史、弹窗、typed result 不被绕过；覆盖手势中状态变化 |
| 多 Host/Outlet 与自定义路由 | 有身份/拓扑基础 | 明确哪些路径支持阶段观察，哪些保留系统 fallback，不能用一个布尔能力概括全部 |
| Android 系统返回 | 本轮未验收 | embedding、系统版本、有效 Manifest、IME、返回桌面、跨 Activity 分别验证 |

“受保护页面安全降级”可以属于完整集成；“受保护页面也始终交互预览”是另一项更大的能力。
异步退出确认、WebView 历史和教程结果等业务语义不应被框架统一改写。

## 2. 对输入文档的核对与补充

### 2.1 核心结论成立

- `packages/ccrouter/lib/src/flutter_route_factory.dart` 的默认 Material 分支直接构造 `MaterialPageRoute`；显式自定义转场使用 `PageRouteBuilder`，不能自动等同于默认预测动画。
- `packages/ccrouter_go_router/lib/src/predictive_back_bridge.dart` 仅提供手动报告方法。开关创建桥，不安装真实平台事件转发。
- `packages/ccrouter_go_router/lib/src/adapter.dart` 为 Guard 页面安装保守的 `canPop=false` PopEntry，拒绝交互启动；提交后 fallback 按 `system` 判断，再检查局部 PopScope/Form。
- Core 按 backendEntryId 清理具体 RouteEntry。预测桥不得再次调用业务 pop；取消不能关闭 Scope、完成返回值或触发正式 PageShow/PageHide。
- 普通弹窗、局部历史、根路由与业务页面属于不同返回目标，不能通过“删掉当前 managed 栈顶”统一处理。

### 2.2 公开 Route 扩展点在当前 SDK 可用，进度方向需要转换

当前 SDK 的 `PredictiveBackPageTransitionsBuilder` 内部检测器调用 Route 的公开方法：

`handleStartBackGesture`、`handleUpdateBackGestureProgress`、`handleCancelBackGesture`、`handleCommitBackGesture`。

继承 MaterialPageRoute 并委托 `super` 的隔离探针已经通过，保留了 Flutter 动画、取消恢复及一次结果完成。
这使 Route 观察方案具备实证基础，但尚未证明 CCRouter 自动装配、全部 Outlet 或自定义 Page 的接线。

特别注意：Route 接收到的是动画剩余值 `1 - platformProgress`。探针中平台进度 `0.4` 对应 Route 值
`0.6`，上报 CCRouter 的手势进度时必须转换，不能直接转发。

### 2.3 动态 canPop 是需要单独解决的边界

当前 SDK 在启动时通过 `popGestureEnabled` 检查 `popDisposition`，实际提交进入
`TransitionRoute._handleDragEnd`，直接调用 `navigator.pop()`，不重新执行 `maybePop` 的检查。

新增探针复现：启动时 canPop=true，手势中改为 false，确认 popDisposition 已为 doNotPop，随后提交仍移除页面，
`onPopInvokedWithResult` 收到 didPop=true。

因此，“初始拒绝有效”与“手势中变为拒绝也有效”不能混为一谈。这是当前 SDK 的可复现行为，
不应误报为已经证实的 CCRouter 缺陷。完整接入必须明确策略：

- 第一阶段保留 Guard 页面非交互 fallback。
- 对自动接线的受管理交互 Route，建议把中途失去退出资格列为取消条件；在提交前核查准确 Route、
  当前状态和 popDisposition，必要时结束为取消并恢复动画。
- 中途失效是否通知业务一次拒绝回调、是否允许业务弹确认框，需要明确契约与回归，不能把动画取消直接当作业务返回。
- 在这项策略实现和验证前，只能承诺沿用 Flutter 的行为，不能承诺动态门禁全过程生效。

### 2.4 接线不等于 Core 已有完整阶段诊断

`packages/ccrouter_core/lib/src/navigation_backend.dart` 的 `_recordPredictiveBackEvent` 当前忽略所有非 committed 事件。
因此，自动桥会补齐 Adapter 事件源，但不会自动形成业务观察 API 或 Runtime 的全阶段诊断。
若产品需要阶段诊断，还需最小化地接入既有诊断系统；update 不逐帧持久化或上传。

当前 `CCPredictiveBackEvent` 在开始/进度/取消时没有 gestureId、hostId、outlet、backendEntryId。
多 Host 聚合直接转发该事件，消费者无法仅凭事件可靠区分来源。
内部必须绑定这些身份；若确实要求聚合后的阶段观察，再评估兼容性增加最小只读元数据，避免提前扩张业务 API。

### 2.5 应用自建 GoRouter 不能承诺无改动自动覆盖

框架 assembler 的默认页面经 `ccGoRouterPage` → `CCFlutterPage` → factory，适合集中接线。
但 attached GoRouter、显式 override、自定义 pageBuilder 或普通 GoRoute.builder 可以绕过这一构造路径。
需要支持表与显式 Host 接入方式；foreign Route 保留现有返回路径。不能把开关开启等同于所有路由都已自动覆盖。

### 2.6 Observer 与预测桥要共享一次提交事实

Route 的 commit 回调表示提交请求；准确 Route 的实际移除才是 committed outcome。
应先关联手势与具体 backend pop，再让既有 reconciliation 完成清理，并只发布一次预测终态。
现有身份清理是可复用基础，但不应把两个独立提交入口的幂等性当作全部语义保证：
生命周期原因、诊断来源与事件顺序也必须一致，晚到的桥报告不能事后“修正”已发送的离页事件。

## 3. 候选方案与取舍

| 方案 | 收益 | 成本及限制 | 结论 |
|---|---|---|---|
| 仅沿用 Flutter | 改动少，普通页可获得交互体验 | 不具备 CCRouter 自动阶段/来源能力 | 适用于只要求普通页体验的应用 |
| 应用 Host 手工转发 | 可做局部验证 | 重复平台适配；容易吞返回、错归属或双退 | 不作为长期框架方案 |
| 可选 Route + Adapter 自动桥 | 复用 Flutter 动画、现有身份和 Core 清理；便于回退 | 中等工作量；需覆盖动态门禁、并发及不同构造路径 | 推荐 |
| Core 新增可观察的 Guard 预判协议 | 有机会让 Guard allow 页面也参与预测 | 较高成本；同步 evaluate 本身没有状态失效通知，不能当作持续有效的授权 | 有真实需求后独立设计 |
| 暂缓并明确能力限制 | 保持现有行为 | 自动阶段能力仍缺失 | 发布约束下可选，不能表述为已经完整支持 |

不建议注册一个无条件接受 start 的 WidgetsBindingObserver：当前 SDK 会把接受者加入后续接收集合，
集合非空就不会走默认 handlePopRoute fallback。只做观察也可能改变 Guard、Dialog、自定义转场的返回行为。
同样不建议替换全局 flutter/backgesture handler、复制 Flutter 转场或增加第二套原生 pop 转发。

## 4. 推荐实施计划

1. **确定支持合同。** 第一阶段范围为框架默认 Material Route 的阶段自动观察、可靠取消/提交、准确 Scope/result 清理，
   Guard、foreign Route、自定义转场保持有声明的 fallback。明确动态门禁的取消策略。
2. **补隔离回归。** 将公开 hooks 探针转成框架夹具；补默认 assembler、attached/override、动态 PopScope、多个 Outlet、
   手势中 push/replace/remove、Host detach/dispose、连续独立手势。框架夹具不依赖 LiberLive 业务代码。
3. **实现可选接线。** Flutter factory 提供后端中立的最小 Host SPI，GoRouter Adapter 拥有上下文与身份映射；
   Flutter 保持动画和实际 pop 的执行者。Feature 不导入 Host SPI，不新增业务 Contract。
4. **实现内部状态机。** idle → tracking → cancelled 或 commitPending → confirmed；失效上下文单独终止。
   绑定 Route/backendEntryId/hostId/outlet/gesture generation。终态幂等，旧回调不作用于新栈顶，不使用时间防抖吞掉下一次正常手势。
   Host 关闭、Route 移除、取消及初始化失败释放监听与引用。监听异常不影响实际导航。
5. **整合提交与诊断。** Observer 确认准确移除后上报一次 outcome；复用 Core reconciliation，覆盖 Observer 与 bridge 的不同到达顺序。
   cancel 不触发正式生命周期、typed result 或资源释放。阶段诊断按需要接入，保持隐私字段边界和有界队列。
6. **保持兼容并交付 Demo。** 当前开关已有手动转发职责，自动模式须显式区分，避免升级后旧 Host 手动转发与新接线重复。
   最小模式/API 在探针通过后决定。更新 DartDoc、README、集成 Skill/相关 reference 与 Demo；不先发布占位 API。
7. **先框架、后应用、再平台验收。** LiberLive 先验证普通详情/设置等页面；WebView 历史、教程结果、登录步骤、退出确认逐组件优化。
   系统预测启用、自动桥、业务优化分别回退；回退桥不补 pop。targetSdk 升级作为独立变更。

主要改动域是 Flutter Route factory、GoRouter Page/assembler/Adapter/bridge/observer 和框架测试。
若增加阶段元数据或诊断，会涉及 contracts/Core 的最小兼容增量；无需预先重写路由 Core、生成器或业务 typed Intent。
共享 factory 改动需要回归 iOS/OHOS 等目标，不能因需求来自 Android 而省略。

粗估第一阶段框架实现、回归、Demo 与文档为 **6–10 人日**，设备/平台验收另计 **3–5 人日**。
这是按现有基础做的规划估算，动态策略及 attached/custom Page 范围会改变成本；
若再要求 Guard 页面全面交互预览或所有业务特殊页面同等体验，应独立立项估算。

## 5. 验收与本轮证据

本轮在仓库根目录以 `fvm flutter test --no-pub <隔离文件> --reporter expanded` 执行两组测试：

- 输入文档的 6 个预测返回用例：6/6 通过。桥关闭/开启普通页、Guard allow/deny、局部 PopScope 拒绝、foreign Dialog。
- 新增 SDK Route 探针：2/2 通过。公开 hooks 保留取消/提交/进度；中途 canPop=false 仍提交退出的行为得到复现。

新增探针以文本保存于 [validation/ccrouter_predictive_back_route_hooks_20261015.dart.txt](validation/ccrouter_predictive_back_route_hooks_20261015.dart.txt)，
便于复制为临时 Dart 测试文件后从本仓库根目录运行，不自动进入正式回归集。

验收重点包括：取消无副作用；提交只退准确目标；typed Future 与资源清理各一次；旧手势不操作新路由；
动态门禁策略有效；Dialog/BottomSheet/LocalHistory/IME 优先级正确；多 Outlet 归属明确；Host 关闭后无残留回调。

框架实施后运行 `fvm flutter test packages/ccrouter_test/test`，并完成相应 analyze、Demo 测试、
真实 Host 的 generation check 和受影响平台构建。
Android 13 验证离散返回，14/15/16 按实际系统配置、effective Manifest、embedding 和 target 验证预测分发；
覆盖左右边缘、取消重试、连续返回、三键、平台视图、返回桌面和第三方 Activity。

**本轮未执行自动接线实现、完整框架回归、平台构建或真机预测返回验收。8 个隔离用例通过不能替代这些验收，
也不能证明既有双退问题由预测返回导致。**
