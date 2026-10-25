# Managed 装配、生命周期与健康诊断循环审查

日期：2026-10-25。源码基线：`fcace7f` 加本次提交的工作区改动。
范围为框架源码、Widget/生命周期自动化、Demo 和 DevTools；没有新增真实设备、
原生 heap 或长期性能验收。本报告不替代发布门禁。

## 实现与边界

普通应用使用 `CCRouterHost.initialize` 和 `CCManagedRouterApp`；显式 Backend、
`CCRouterApp.managed`、Catalog/Assembly 和 MultiHost 仍为高级 Host／测试装配入口。
内部协调实现保持私有，业务门面新增的健康摘要仅提供不可变标量。

本次工作区累计修复 managed/direct HostBinding 资源接管、拒绝清理身份预留、部分挂载回滚、
初始化销毁／重入、Route Scope 关闭屏障、批量清理、跨 error Zone 汇合和 MultiHost 注册身份。
初始快照先导入，再 FIFO 重放读取期间报告；Entry 版本是判旧下界而非完整事件水位，
operation 去重与 sequence 连续性独立。直接 Navigator Pop 的兼容回收不变，不能执行异步离开策略。

最后的循环审查采用内部修复，保留现有导航调用和可选 Host 能力；不通过新业务抽象或删除缓存
规避问题。全部新缺陷先补回归取得红灯，再修复，并继续检查相邻交叉路径。

| 已复现的问题 | 修复与回归 |
| --- | --- |
| Adapter getter 重入直接 HostBinding 后，外层 managed 拒绝误销毁新 Owner 的 Adapter | 只采样一次 getter，返回后检查最新所有权，后续释放使用同一捕获身份；断言原 Owner 存活及最终只释放一次 |
| 活动 RouteEntry 或 Backend ledger 变更后，外部 release/capabilities 回调仍读旧健康缓存 | 在外部回调前使缓存失效；回调内比较真实活动集合与摘要，稳定状态仍复用快照 |
| Binding.detach 首错被后续 Runtime／Adapter／Backend 错误覆盖 | 完成清理后交付首个结构性错误；8 种成功／失败组合、独立堆栈、两个 error Zone、清理最多一次 |
| 终态观察背压重入后队列达到 65/64，且多监听器收到逆序事件 | 先预留传入批次槽位，再通过回调游标和已接纳交付队列保持逐监听器 FIFO；覆盖正常 drain、unsubscribe、throw 和 shutdown |

红灯见[第一轮](round1-red.log)、[第一轮补充](round1-more-red.log)、
[背压容量](backpressure-red.log)、[多监听器顺序](fanout-red.log)。
两个“退出监听与 Service 清理连续失败”对照原本通过：Scope 收集业务 Service disposal 错误，
没有证实该处首错覆盖，因此未为这一疑点修改生产逻辑。
最后一轮在上述范围内未发现新的可复现缺陷，不将有限自动化视为穷尽所有执行序列的证明。

## 健康摘要含义

- `trackedNavigationHostCount` 是按需捕获且未 detach 的 Host 生命周期数，不是 Adapter 注册数。
- `inFlightNavigationCount` 是 `singleFlight/rejectDuplicate` 并发 gate 数；默认 `allow` 可以为 0。
- `observerQueueDepth` 仅统计等待批次，排除当前交付；容量为 `max(64, navigationDiagnosticCapacity)`。
- 关闭历史保留仍保留观察交付。结构变更在外部回调前失效缓存，稳定时复用快照。
- 无关联 Backend 事件包括 Foreign/opaque 转换，不是直接 Navigator.pop 次数；计数不证明泄漏。
- 协议 v1 的 `diagnosticHealth.runtimeHealth` 可选，旧 Producer 缺失仍为 null；
  Host 键输出 `trackedNavigationHosts`，兼容原 `registeredHosts` 输入但不改变含义。

## 最终回归

| 命令／工作目录 | 结果 | 日志 |
| --- | --- | --- |
| 根目录 `fvm flutter test --no-pub packages/ccrouter_test/test` | 1599 项通过 | [框架](framework.log) |
| `demo/` 中 `fvm flutter test --no-pub` | 114 项通过 | [Demo](demo.log) |
| 根目录 `fvm flutter test --no-pub packages/ccrouter_devtools/test packages/ccrouter_devtools_protocol/test` | 24 项通过 | [DevTools／协议](devtools.log) |
| 根目录 `fvm dart analyze` | 无问题 | [根分析](analyze.log) |
| `demo/` 中 `fvm flutter analyze --no-pub` | 无问题 | [Demo 分析](demo-analyze.log) |

最后循环新增 20 项回归已包含在 1599 中，不与专项数字重复累加。此前工作区修复的测试也包含在总数中。
首次并行全量运行为 1594 通过、1 失败，原始[失败日志](framework-first.log)保留：
旧 Service 测试使用真实 10ms 截止时间，负载较高时在业务回调进入之前到期，随后读取空列表。
测试改为 Flutter 虚拟时钟，先完成 readiness 再明确推进截止时间；未放宽超时或取消断言。

提交前同步 README 中英文、路由／DevTools 指引、集成 Skill 与 references、Package README／
Changelog 和 API DartDoc。补齐文档示例／链接检查、路径脱敏、敏感信息门禁和 diff 检查，
结果见[文档检查](documentation.log)。归档日志仅归一化本机路径和行尾空白，保留失败事实和结果；
原始副本保留在仓库外。Generator、隔离 Analyzer Plugin 生产逻辑未改，
本轮未重跑它们的全量套件、未变更 Demo Plugin pin。
