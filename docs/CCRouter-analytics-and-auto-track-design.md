# CCRouter Analytics 与 Auto Track 设计

> 文档状态：架构 1.x 当前契约。Provider-neutral 分发、显式 Target、Consent、黑名单与节流、
> 有界属性和可选 Sink 超时已实现；全局 Widget 猜测和供应商上传 Adapter 不属于当前框架承诺。

## 1. 结论

CCRouter 自动观测框架拥有的导航和生命周期；应用负责业务事件语义、隐私同意、身份管理和最终供应商配置。任意 Widget 点击、滑动和曝光不能依赖框架猜测。

分层如下：

```text
ccrouter_core                 Route、Trace、Failure、Diagnostic
ccrouter_analytics            统一分析事件、脱敏属性、有界 Sink
ccrouter_analytics_flutter           可选的显式 UI 目标和有限自动采集
应用层 Adapter                Firebase、ThinkingData、本地记录或 HTTP 上传
应用层                         业务事件、Consent、身份和网络/Crash 接入
```

## 2. 已有能力

`CCNavigationAspect` 已提供 `found`、`arrival`、`show`、`hide`、`removed`、`disposed`、`lost` 和 `after`。它可以生成页面进入、页面离开、来源、重定向、失败和停留时长等框架级事件。

`CCDiagnosticSink` 负责框架诊断，不是产品分析事件存储。诊断默认只保留稳定 ID、状态、阶段、耗时和错误类型，不保留参数、Token、完整 URI、Widget 或业务返回值。

## 3. 分析事件边界

`CCAnalyticsEvent` 与 `CCDiagnosticEvent` 分离。

框架自动生成：

- `page_view`
- `page_leave`
- navigation requested/found/arrival/failed
- redirect、interceptor、PopGuard 和 fallback
- Route Scope、Service、Command、Event、InitTask 生命周期

业务显式生成：

- 商品点击
- 点赞
- 确认订单
- 支付提交
- 搜索完成

自动 UI 采集只允许作为默认关闭的可选能力，不能通过 Widget 文本、随机 Key 或完整 Widget 树推断业务事件。

## 4. Page View 语义

对于 CCRouter managed Route：

- `arrival`：首次进入页面，生成一次 `page_view`；
- `show`：被覆盖的页面再次成为当前页面，可生成一次新的 `page_view`；
- `hide`：页面不再是当前 Route，生成一次 `page_leave`；
- `removed/disposed`：用于生命周期和资源诊断，不重复生成 `page_leave`。

Dialog、Modal Bottom Sheet 和透明页面保留其 Route 类型。Foreign Popup、Overlay、LocalHistoryEntry 和未绑定 Navigator 不自动转换成 CCRouter 页面分析事件。

## 5. Click、Scroll 和 Exposure

首选显式稳定目标：

```dart
final target = CCAnalyticsTarget(
  tracker: tracker,
  eventId: 'order.detail.confirm',
);

FilledButton(
  onPressed: () => target.run(submitOrder),
  child: const Text('确认订单'),
)
```

滑动只记录 `scroll_start`、`scroll_end`、方向、距离区间、时长区间和业务目标 ID，不记录每一帧 PointerMove 或完整轨迹。

曝光需要显式目标、可见比例阈值、最小停留时长和去重策略。长列表只记录曝光区间或稳定 Item ID，不记录文本内容。

`CCAnalyticsExposureTarget` 订阅实际祖先 ScrollPosition，按帧合并测量；可见比例是目标
全局矩形与 View、祖先 paint clip 的交集，支持嵌套滚动和最近 ScrollPosition 替换。
它不是逐像素检测，不能推断任意 Overlay 遮挡、透明度或无通知的自定义布局动画。
Target detach/dispose 会移除滚动/策略监听并取消 Timer；后帧回调只弱引用 State。

Consent 拒绝、后台和 detach 不积累 dwell；grant/resume 后重新计满时长，不回放历史。
`once` 表示同一 Target 状态生命周期内至多接受一次，不是 Sink 写入承诺。
已接受的 Target 不因 revoke/grant 重放；采样、黑名单和节流拒绝只
结束当前周期的一次尝试，新的可见周期或策略变化可重新测量，不逐帧重试提高采样概率。

跨 Pure Dart Dispatcher 和可选 Flutter Target 使用窄的 `addPolicyListener` 只读观察接口：
同步通知、不传事件 payload、异常隔离、禁止回调重入修改策略；注册不立即回调，消费者
读取当前 `policy/isClosed`。调用方持有 remover 并在解绑时调用，close 通知终态后清空
监听；通知中 close 时，尚未通知的观察者在该轮读取终态。无需应用手工重建曝光 Widget。

## 6. 安全与性能

- 属性必须是 String、num、bool 或有限的 String/num 列表；列表在属性创建时复制为不可变
  快照，拒绝嵌套集合和任意对象，调用方和 Sink 均不能修改已验证值；
- 每个 String 最多 256 个字符，每个列表最多 32 项，每个事件最多 64 个属性，属性值的
  保守总大小最多 4096 个字符；数值必须是有限值。超限在创建属性或属性集合时同步抛出，
  不进入业务回调之后的异步路径；黑名单最多 256 个 ID，节流状态最多保留 1024 个 ID，
  超出时按最旧状态淘汰；
- 禁止 Token、Cookie、完整 URI、Widget、Exception、业务对象和未脱敏账号信息；
- 分析事件使用有界异步队列；队列满时允许丢弃非关键旧事件；首个 Sink 也在后续事件循环
  启动，分发前先建立单次调度状态，Sink 重入入队不会启动并行 drain；
- Sink 异常不能影响导航、Service、Command、Event 或页面构建；
- 同意前后必须可以切换事件策略；`CCAnalyticsEventDispatcher` 在入队前执行
  Consent、启用和采样判断。撤销同意或禁用时清理待发送队列，并使当前事件剩余 Sink 的
  投递失效；立即重新授权也不能恢复旧事件。每个 Sink 启动前检查授权代次，不重复采样。
  已经开始的外部 Sink 写入无法撤回，网络取消和供应商缓存清理由应用 Adapter 负责；
- Composition Root 等待 `close()`，包括尚未启动的调度与在途写入；关闭后不接收新事件，
  等待期间仍允许撤销授权以取消尚未开始的投递。Sink 不得在自己的 `write` 中等待
  同一 Dispatcher 的 `close()`，以免形成自身等待。异步调度不是 Isolate 隔离，应用 Sink
  仍须避免耗时同步工作；
- 默认不设置 Sink 超时，因此 `close()` 继续等待应用 Sink 完成。配置
  `sinkWriteTimeout` 后，单次写入超过期限的 Sink 会被隔离并跳过后续事件，关闭等待有界；
  Dart Future 本身不可撤销，底层写入可能在超时后继续运行，因此应用仍需在 Sink 内实现取消。
- 监听器、ScrollController、Timer 和 StreamSubscription 必须在 Host/页面销毁时释放；
- 分析事件和框架错误诊断都必须支持分类开关和采样。

## 7. 第三方 Adapter

Firebase Adapter 属于应用层。当前 `demo/modules/analytics_firebase` 演示将已脱敏事件映射到
Firebase 风格的 `logEvent` callback；生产应用可按自身命名规则把页面事件映射到
`logScreenView` 或 `logEvent`。

ThinkingData Adapter 映射到 `track`，用户身份通过 `identify/login` 管理。App Start、App End、Install 和 Crash 等供应商自动事件由 Adapter 或应用错误入口负责，不由 Core 伪造。

Core 不依赖 Firebase、ThinkingData、Sentry 或 Crashlytics。

## 8. 实施计划

### P0：事件契约和分发基础

- [x] 新增 `ccrouter_analytics`；
- [x] 增加事件类型、稳定 ID 和安全属性校验；
- [x] 增加有界异步 Sink Dispatcher；
- [x] 隔离 Sink 异常和队列压力；
- [x] 增加属性/黑名单/节流状态上限、有限数值校验和可选 Sink 超时隔离；

### P1：Route 自动分析

- [x] 将 managed Route `arrival/show/hide` 桥接为 Page View/Leave；
- [x] 保留 navigationId、routeId、componentId、Host、Outlet 和匿名 Telemetry Context；
- [x] 增加 Pure Dart 契约、FIFO、容量、异常隔离和桥接测试；

### P2：显式 UI 事件

- [x] 增加不改变 Flutter 手势语义的 Click Target 和基础 Tracker API；
- [x] 增加基础显式 Scroll、Exposure 和 Custom 事件入口；
- [x] 增加 Scroll Target 和聚合策略；
- [x] 增加曝光 API、可见比例、最小停留时间和去重；
- [x] 增加 Widget、生命周期和内存释放测试；

### P3：可选 Auto Track

- [x] 独立 `ccrouter_analytics_flutter` Flutter 包；
- [x] 默认关闭，只识别显式 Target；不基于 Widget 文本、随机 Key 或全局手势猜测；
- [x] 黑名单和通用节流；平台能力矩阵仍需随真实设备回归持续补齐；采样已由
  `CCAnalyticsPolicy` 提供；
- [x] 不改变手势竞技和第三方 Overlay 行为；

### P4：应用层供应商 Adapter 示例

- [x] 应用层 Firebase Adapter 示例（通过注入 `logEvent` callback，不让框架依赖供应商 SDK）；
- [ ] 应用层 ThinkingData Adapter 示例；
- [ ] 应用层 OpenTelemetry/日志 Adapter 示例；
- [x] 增加 provider-neutral Consent 开关和有界采样策略；
- [ ] 应用层用户身份、批量上传、离线缓存和重试参考实现；

### P5：应用层 HTTP、Crash 接入与全链路回归

- [ ] 应用网络层 Adapter；
- [ ] Flutter、PlatformDispatcher 和原生 Crash 桥接；
- [ ] current Route、Host、Outlet、Trace 关联；
- [x] 增加独立分析分发基准：入队 P50/P95、接受/丢弃数、峰值队列深度、关闭后残留队列和 RSS 趋势；
- [x] Demo 接入 Route Analytics、显式点击、滑动、曝光、失败与 Foreign Popup 场景；
- [x] Demo 增加 Analytics Consent deny/grant/revoke 和 Foreign Popup 不误归因断言。

## 9. 当前状态

P0、P1、P2 显式 UI 能力、P3 的独立包基础和 Consent/采样基础已实现，Demo 已接入页面、
点击、滑动、曝光、失败与 Foreign Popup 场景。Analytics Consent 的 deny/grant/revoke 演示和
Foreign Popup 不误归因断言已闭环；应用层 Firebase 映射示例、黑名单和通用节流已提供，ThinkingData、
通用 Widget 自动猜测、HTTP/Crash Adapter 尚未实现。

Dispatcher 的稳定性边界已经收口：属性值、属性数量、黑名单和节流状态均有界；
`sinkWriteTimeout` 是应用按需开启的慢 Sink 隔离开关，超时 Sink 会被跳过并通过
`timedOutSinkWriteCount`/`quarantinedSinkCount` 提供无 payload 健康信号。默认不启用超时，
保持已有 `close()` 等待语义。

正式发布前的实施顺序、平台能力矩阵、全局 Widget 识别的实验边界、Firebase Adapter、性能/RSS/Heap
基线，以及 Demo 的 Consent deny/grant/revoke 和 Foreign Popup 不误归因断言，统一见
[`CCRouter-pre-release-capability-plan.md`](CCRouter-pre-release-capability-plan.md)。本专项文档
仍是 Analytics API 和隐私边界的详细契约；总计划不把“全局自动识别”提升为默认承诺。

### 9.1 当前平台边界

| 平台 | Dispatcher/Consent/应用层映射 | Exposure/Scroll AutoTrack | 说明 |
| --- | --- | --- | --- |
| Android | 支持 | Flutter Widget 测试覆盖 | 原生生命周期和 Crash 仍由应用 Adapter 接入 |
| iOS/iPadOS | 支持 | Flutter Widget 测试覆盖 | 不读取原生控件文本或无授权设备标识 |
| macOS/Windows | 支持 | Flutter Widget 测试覆盖 | 多窗口归因依赖 Host/Outlet 上下文 |
| Web | 支持 | 需应用确认浏览器隐私策略 | 不默认采集 URL 全文或浏览器指纹 |
| OHOS | Pure Dart 层支持 | 需 OHOS 真机回归 | 当前 FVM OHOS SDK 不能替代桌面 Flutter 测试矩阵 |

平台矩阵中的 `required` 表示协议和显式 Target 在该平台必须保持一致；`verify` 表示需要目标设备
执行 smoke，不能据此推导“全局 Widget 自动识别”已支持。分析 Dispatcher 的 Pure Dart 指标和
Consent/黑名单策略可在所有 Dart 平台复用，RSS 结果只允许同 SDK、同平台进程内比较。

## 10. 低配置智能采集方案

### 10.1 问题分析

当前事件契约、Route 生命周期桥接、Consent、采样、有界队列、Scroll 和 Exposure 已经具备，
Scope 已提供上下文继承，但 UI 使用仍有两类需要显式声明的配置：

- Click 需要先创建 `CCAnalyticsTarget`，Scroll/Exposure 还要分别包 Widget；
- 本地记录和上传虽然可以实现 `CCAnalyticsSink`，但缺少应用层参考组合。

“在应用或页面外只包一个 Widget，就准确采集所有操作”不能作为生产承诺。Flutter 的原始
Pointer 只能说明发生了按下、抬起或移动，不能证明某个业务 callback 最终执行；Gesture Arena、
禁用按钮、拖动、长按、键盘/遥控器操作、Semantics action 和第三方 Overlay 都可能让原始 Pointer
与业务动作不一致。通过遍历 Element 树读取 Text、Key 或 Widget 类型生成事件 ID，还会造成隐私
泄漏、重构后数据漂移和大页面扫描抖动。

### 10.2 参考实现结论

- [`auto_track_plugin`](https://github.com/epoll-j/auto_track_plugin) 通过统一配置、
  `NavigatorObserver`、全局 `PointerRouter`、Element 树扫描和 Key/Text 推断降低接入成本，并内置
  HTTP、上传和 Crash；其 README 明确主要在 Android/iOS 验证。可借鉴统一开关、过滤、采样和
  callback Sink，但不能复制随机 Key、文本采集、全树扫描、`HttpOverrides.global` 或供应商上传。
- [Firebase Analytics Observer](https://github.com/firebase/flutterfire/blob/main/packages/firebase_analytics/firebase_analytics/lib/observer.dart)
  只根据 `NavigatorObserver`、Route filter 和 name extractor 自动记录 screen view，不尝试推断
  任意 Widget 点击。这说明页面自动化与业务行为自动化应分开设计。
- [ThinkingData Flutter SDK](https://github.com/ThinkingDataAnalytics/flutter-sdk/tree/master/lib/autotrack)
  同样使用全局 Pointer、Element/RenderObject 遍历和可选 Element Key。稳定 Key 的思路可参考，
  但读取控件文本、依赖 Widget 树形状和每次点击扫描页面不适合作为 CCRouter 默认实现。

### 10.3 候选方案

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| 全局 Pointer + Element 树猜测 | 接入代码最少，可快速看到大量事件 | 误报、隐私和性能风险高，无法证明业务动作执行，跨平台不稳定 | 仅可用于 Debug 实验，不进 Release 默认 |
| 保持所有 Target 显式传 Tracker | 语义准确、可测试、没有全局扫描 | 页面和组件样板代码较多 | 保留为精确兜底，不作为唯一入口 |
| Scope + 稳定 Target 元数据 + Debug Recorder | 自动补齐上下文，业务只声明稳定 ID；可把模糊轨迹与产品埋点隔离 | 仍不能零标注推断业务语义，需要新增少量 Flutter Scope | 推荐 |

### 10.4 推荐的三档模式

1. `frameworkOnly`：生产默认。自动记录 CCRouter managed Route 的 PV/Leave、来源、Host/Outlet
   和耗时，不采集任意 Widget 内容。
2. `annotated`：生产推荐。页面只安装一个 Scope；带稳定 Target 元数据的点击、滚动和曝光才生成
   产品事件。未标注控件不上传，不从 Text、Key、runtimeType 或坐标生成业务 ID。
3. `debugRecorder`：Debug/Profile 或受控灰度。页面 Scope 记录有界的 pointer/scroll/route 操作
   轨迹，用于复现问题；默认只写本地环形缓冲，不作为 PV/UV 或业务转化数据，也不默认上传。

三档可以逐级增加信息，但不能把 `debugRecorder` 事件伪装成 `annotated` 产品事件。

### 10.5 建议结构

```text
CCAnalyticsEventDispatcher（现有）
  ├── Consent / Sampling / Rules（现有基础）
  └── CCNavigationAnalyticsBridge（现有）

CCAnalyticsScope（已实现，应用根或页面一层 Widget）
  ├── Inherited Dispatcher/Context
  ├── 本地 enabled 开关
  └── 显式 Target / Scroll / Exposure

应用拥有的 Sink
  ├── Firebase / ThinkingData Adapter
  ├── 有界本地 JSONL/数据库环形缓冲
  └── HTTP Batch Uploader
```

`CCAnalyticsScope` 只持有应用拥有的 Dispatcher 和不可变上下文，不持有页面业务对象，也不负责
Dispatcher 的关闭。根 Scope 注入 Dispatcher，页面或 Feature Scope 可只提供增量 Context；
`CCAnalyticsScope.trackerOf(context)` 返回值对象 Tracker，`maybeTrackerOf` 允许可选接入。
当前 Scope 不读取 RouteEntry，也不依赖 CCRouter 内部 API；managed 页面可以由 Host 在页面边界
显式传入稳定 route/Host/Outlet 字段。无法证明精确上下文时应省略字段，不能从完整 URL、Widget
文本或 `ModalRoute.settings.arguments` 猜测，也不能把 Foreign Popup 自动归因到下层页面。

### 10.6 API 草案

下面只用于确认开发体验，不代表公开 API 已确定：

```dart
final dispatcher = CCAnalyticsEventDispatcher(
  sinks: [appLocalSink, appUploadSink],
);

runApp(
  CCAnalyticsScope(
    dispatcher: dispatcher,
    context: const CCAnalyticsContext(componentId: 'order'),
    child: const CCGoRouterApp(),
  ),
);
```

业务 Target 不再传递 Tracker，只声明稳定事件 ID：

```dart
Builder(
  builder: (context) {
    final tracker = CCAnalyticsScope.trackerOf(
      context,
      analyticsContext: const CCAnalyticsContext(routeId: 'order.detail'),
    );
    final target = CCAnalyticsTarget(
      tracker: tracker,
      eventId: 'order.detail.confirm',
    );
    return FilledButton(
      onPressed: () => target.run(submitOrder),
      child: const Text('确认订单'),
    );
  },
)
```

该包装表示“用户对已标注目标完成一次可识别的 activation”。如果必须证明业务动作实际执行、成功
或失败，仍使用 callback 入口记录 `attempt/success/failure`，不能依赖 Pointer 自动判断。对于多个
嵌套 Scrollable，页面级自动聚合只记录总体验；需要区分列表时仍声明稳定 scroll target ID。

### 10.7 自动采集边界

| 场景 | 自动化级别 | 说明 |
| --- | --- | --- |
| managed Route PV/Leave | 全自动 | 复用 Aspect/RouteEntry，不读取页面内容 |
| Foreign Route/Popup | 不自动归因 | 未桥接时不得归到当前 managed Route |
| 标注 Target 点击 | 自动补上下文 | eventId 必须稳定且显式 |
| 未标注 Widget 点击 | Debug 可记录 | 只记录安全结构摘要，不作为产品事件 |
| 页面主 Scroll | Scope 可聚合 | start/end、方向、距离和时长分桶，不记录逐帧轨迹 |
| 多列表/嵌套 Scroll | 需要 Target ID | 避免把多个滚动源混在一起 |
| Exposure | 显式 Target | 需要阈值、停留时间和去重语义，不能扫描全树 |
| 文本输入、剪贴板、密码、Token | 永不自动采集 | 黑名单也不能替代数据最小化 |
| 键盘、遥控器、Semantics action | 精确入口或后续适配 | 不能只依赖 Pointer |

### 10.8 本地记录与上传

框架继续只定义 provider-neutral `CCAnalyticsSink` 和有界调度，不提供业务存储或上传后端。
Demo/应用层可以提供两类参考 Sink：

- 本地 Sink：有界容量、TTL、版本化 schema、原子追加、脱敏后落盘；Consent deny/revoke 时立即
  停止写入并按应用政策清理，默认只在 Debug/Profile 保存操作轨迹；
- 上传 Sink：批量、指数退避和 jitter、网络约束、幂等 event ID、Session 隔离；Base URL、Header、
  登录态和 API 环境由应用 Network/Session Service 提供，不能复制到框架全局状态。

Firebase、ThinkingData、本地数据库和 HTTP 实现都放在应用或 `demo/modules/*`。只有多个真实应用
证明存在稳定、供应商中立的公共契约后，才按 Framework Package 准入门禁重新评估。

### 10.9 实施顺序与验收

1. [x] 增加 Scope 的可行性实现，不替换现有 `CCAnalyticsTarget`；用 enabled 开关
   与现有显式路径 A/B 对照。
2. 打通只读 RouteEntry 上下文，验证多 Host、Shell/Outlet、Dialog 和 Foreign Popup 不误归因。
3. 增加只识别稳定元数据的 Target，验证 disabled、Gesture Arena、拖动、长按、键盘和 Semantics。
4. 增加页面级 Scroll 聚合；Exposure 继续使用现有显式 Target，不做全树轮询。
5. 在 Demo 增加应用层本地环形 Sink 和 Fake Upload Sink，验证 Consent、断网、重试、队列压力和
   App 重启；不把实现迁入 `packages/*`。
6. 最后才增加 `debugRecorder`，并以 Release 默认关闭、本地有界、不可上传为默认安全值。

进入实现前必须建立基线：每次 pointer 处理耗时、每帧额外 build/layout 次数、长列表滚动 P95、
事件误报/漏报率、队列峰值、RSS/Heap 增长和 Scope dispose 后残留对象。任何自动化路径如果不能
证明不会改变手势结果、页面生命周期或业务 callback，都必须降级到显式 Target。
