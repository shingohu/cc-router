# Demo Firebase Analytics Adapter

`demo_analytics_firebase` 是应用层示例，不属于 CCRouter 框架 Package。

它演示如何把 `demo_analytics` 输出的、已经过属性校验和 Consent 策略处理的
`AppAnalyticsEvent` 映射为 Firebase 风格的 `logEvent` callback。示例刻意不直接依赖
`firebase_analytics`，以便测试映射和失败隔离；真实应用应在 Composition Root 注入自己的
Firebase SDK 调用。

以下职责仍归应用所有：

- Firebase 初始化与平台配置；
- Consent、用户身份和账号切换；
- 业务事件命名与参数治理；
- 离线缓存、批量、重试和上传；
- Crashlytics 及其它供应商能力。

如果应用更换为 ThinkingData、HTTP 或本地存储，只需提供另一种 `AppAnalyticsSink`，无需修改
CCRouter Core。
