# CCRouter Analytics 与 Auto Track 设计

## 1. 结论

CCRouter 自动观测框架拥有的导航和生命周期；应用负责业务事件语义、隐私同意、身份管理和最终供应商配置。任意 Widget 点击、滑动和曝光不能依赖框架猜测。

分层如下：

```text
ccrouter_core                 Route、Trace、Failure、Diagnostic
ccrouter_analytics            统一分析事件、脱敏属性、有界 Sink
ccrouter_auto_track           可选的显式 UI 目标和有限自动采集
ccrouter_analytics_firebase   Firebase 映射
ccrouter_analytics_thinkingdata ThinkingData 映射
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

## 6. 安全与性能

- 属性必须是 String、num、bool 或有限的 String/num 列表；
- 禁止 Token、Cookie、完整 URI、Widget、Exception、业务对象和未脱敏账号信息；
- 分析事件使用有界异步队列；队列满时允许丢弃非关键旧事件；
- Sink 异常不能影响导航、Service、Command、Event 或页面构建；
- 同意前后必须可以切换事件策略；`CCAnalyticsEventDispatcher` 在入队前执行
  Consent、启用和采样判断，撤销同意时清理待发送队列；已经进入外部 Sink 的事件无法撤回，
  因此敏感供应商应在同意后再启用；
- 监听器、ScrollController、Timer 和 StreamSubscription 必须在 Host/页面销毁时释放；
- 分析事件和框架错误诊断都必须支持分类开关和采样。

## 7. 第三方 Adapter

Firebase Adapter 映射 `page_view` 到 `logScreenView`，业务行为映射到 `logEvent`，并在 Adapter 边界校验事件名和参数限制。

ThinkingData Adapter 映射到 `track`，用户身份通过 `identify/login` 管理。App Start、App End、Install 和 Crash 等供应商自动事件由 Adapter 或应用错误入口负责，不由 Core 伪造。

Core 不依赖 Firebase、ThinkingData、Sentry 或 Crashlytics。

## 8. 实施计划

### P0：事件契约和分发基础

- [x] 新增 `ccrouter_analytics`；
- [x] 增加事件类型、稳定 ID 和安全属性校验；
- [x] 增加有界异步 Sink Dispatcher；
- [x] 隔离 Sink 异常和队列压力；

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

- [x] 独立 `ccrouter_auto_track` Flutter 包；
- [x] 默认关闭，只识别显式 Target；不基于 Widget 文本、随机 Key 或全局手势猜测；
- [ ] 黑名单、通用节流和完整平台兼容矩阵；采样已由 `CCAnalyticsPolicy` 提供；
- [x] 不改变手势竞技和第三方 Overlay 行为；

### P4：供应商 Adapter

- [ ] Firebase Adapter；
- [ ] ThinkingData Adapter；
- [ ] OpenTelemetry/应用日志 Adapter；
- [x] 增加 provider-neutral Consent 开关和有界采样策略；
- [ ] 用户身份、批量上传、离线缓存和重试；

### P5：HTTP、Crash 和全链路回归

- [ ] 应用网络层 Adapter；
- [ ] Flutter、PlatformDispatcher 和原生 Crash 桥接；
- [ ] current Route、Host、Outlet、Trace 关联；
- [ ] 冷启动、导航延迟、队列压力、内存增长和销毁耗时基准；
- [ ] Demo 覆盖页面、点击、滑动、曝光、失败、Consent 和第三方 Popup。

## 9. 当前状态

P0、P1、P2 显式 UI 能力、P3 的独立包基础和 Consent/采样基础已实现。Firebase、ThinkingData、
通用 Widget 自动猜测、黑名单/通用节流、HTTP/Crash Adapter 尚未实现。
