# 应用侧埋点与 CCRouter 导航观察边界

更新日期：2026-10-23。

产品埋点由应用实现。CCRouter 保留导航、Scope、组件调用的生命周期事实和框架诊断；
不定义产品事件模型、PV/UV、停留口径、Consent、采样、发送队列、滚动/曝光或上传协议。

## 分层与迁移

原 `packages/ccrouter_analytics`、`packages/ccrouter_analytics_flutter` 已迁到
`demo/modules/analytics`、`demo/modules/analytics_flutter`。
新包名为 `demo_analytics`、`demo_analytics_flutter`，类型使用 `AppAnalytics…`、
`AppNavigationAnalyticsBridge`。没有旧包名或旧类型的兼容导出，避免继续被误认为框架 API。
它们保留 `publish_to: none`，不在框架发布集合内。

| Owner | 职责 |
| --- | --- |
| CCRouter | `CCNavigationAspect`、页面生命周期、稳定的 Route/Host/Outlet 关联、框架诊断 |
| 应用埋点基础设施 | 产品事件和字段、身份、Consent、PV/停留口径、采样/节流、有界分发、上传/持久化/重试 |
| 应用 UI | 显式点击目标、滚动聚合、曝光阈值与去重 |
| 应用 Host | 桥接导航观察、前后台状态和资源释放，装配供应商 SDK |

普通窄接口或注入 callback 已能满足的场景不必注册成 CCRouter Service。
只有需要 Scope、异步 readiness 或生成依赖校验时才引入 Service/Contract。

## 框架提供事实，应用定义统计口径

`CCNavigationAspect` 提供 found/arrival/show/hide/removed/disposed/lost/after。
Arrival/Show/Hide 描述 managed 导航状态，不直接等于 PV 或像素曝光。
应用可注册自己的观察器，并保持它只观察、失败隔离、不重入导航。
`CCDiagnosticSink` 用于排查框架执行，不是产品事件存储、审计日志或上传重放来源。

Demo 的 `AppNavigationAnalyticsBridge` 选择将 Arrival/Show 解释为新的访问，
Hide 解释为离开，Removed/Disposed 只清理未结束访问。这是示例口径，不是框架承诺。
Host 转发 onForeground/onBackground 计算前台停留；Foreign Popup 不创建产品访问。
Core 不再持有访客或应用 Session ID。应用桥注入 `identityProvider`，在首个异步 Found
交付时（必要时 Arrival/Show fallback）捕获身份，保持到实例退出；不承诺调用瞬间身份。
Consent/账号变化前显式 resetTracking；dispose 清空快照、Provider 并阻止旧观察重新填充。
其他产品可以采用不同规则而不修改 CCRouter。

## 可运行参考

- [demo_analytics](../demo/modules/analytics/README.md)：Pure Dart 事件、属性校验、策略、
  Tracker、显式 Target、有界异步 Dispatcher，以及使用公开导航契约的桥。
- [demo_analytics_flutter](../demo/modules/analytics_flutter/README.md)：应用侧 Scope、
  显式滚动与曝光 Widget；没有平台目录或原生 SDK。
- [demo_analytics_firebase](../demo/modules/analytics_firebase/README.md)：callback 映射，
  不强制依赖 Firebase SDK。
- [Demo 配置](../demo/modules/navigation_lab/lib/src/lab_configuration.dart) 与
  [Host 生命周期](../demo/lib/main.dart)：使用上述应用侧实现，不让框架反向依赖 Demo。

应用可以对接已有埋点服务，无需依赖这三个 Demo 包。示例包之间是普通 Dart API 依赖，
不增加框架公共 API，也不生成假的 Route 或 Service。

## 示例的隐私、投递与生命周期语义

示例迁移保持既有规则：默认未授权；撤销授权清空待投递事件并阻止当前事件进入后续 Sink，
立即重新授权也不会恢复旧事件。已经开始的供应商写入需由应用取消。
属性只允许有界不可变原语，禁止凭据、完整 URI、参数、Extra、Widget、异常和业务结果。

Dispatcher 在后续事件循环启动 Sink，队列满时丢弃最旧的非关键事件。
Owner 在退出时 await close；不能从自身 Sink.write 等待 close。
可选写入超时隔离慢 Sink，Dart Future 不可强制取消，SDK/网络连接仍归应用管理。
分发异步不代表离开 UI isolate；Sink 不应做耗时同步计算。

Bridge.dispose 清理访问状态；应用或 Scope 的 Widget 不得关闭借入的 Dispatcher。
曝光 Widget 取消 dwell Timer、解除祖先滚动/策略监听和 WidgetsBindingObserver；
授权恢复、回前台或重新挂载后重新计时。once 表示已接受入队，不保证供应商上传成功。
几何曝光只考虑 View/祖先裁剪，不保证识别任意 Overlay、透明度或广告曝光。

## 验证与迁移影响

原埋点的四个测试文件移到应用包内：事件/分发及回归属于 analytics/test；
Flutter/曝光回归属于 analytics_flutter/test。benchmark 移到
`demo/modules/analytics/benchmark/analytics_dispatcher.dart`。
框架 `ccrouter_test` 删除对埋点包的依赖，框架导航和诊断测试继续保留。
测试数量因归属调整而改变，不能把测试迁出解读为删除了行为覆盖。

从根目录执行：

```sh
fvm dart test demo/modules/analytics/test
fvm flutter test demo/modules/analytics_flutter/test
fvm dart test demo/modules/analytics_firebase/test
fvm flutter test packages/ccrouter_test/test
fvm flutter test demo/test demo/modules/navigation_lab/test
fvm dart analyze
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check
```

后续边界收口已将身份快照从 Runtime 迁到应用桥，快照时刻改为首次观察交付；
这是明确的应用统计语义，不能再声明为导航调用瞬间。单次 benchmark 或回收测试不能
证明长期生产无泄漏或跨平台性能更优；发布前的实际 SDK、平台、隐私和产品口径仍归应用验收。

2026-10-23 实际回归、构建与边界记录见
[迁移验证](validation/20261023-application-analytics/README.md)。
