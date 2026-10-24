# Zone 保留路径与清理屏障审查

修复进展与回归结果见 [Zone 保留路径修复报告](../20261023-zone-retention-fixes/report.md)。下文保留审查时的失败证据，不代表修复后的状态。

2026-10-23；工作树 `managed-navigation-runtime/cc-router`；分支
`codex/managed-navigation-runtime`，HEAD 基线 `09cb21d`。

本轮仅审查并新增确定性探针、正常对照和报告，没有修改生产实现、提交或推送。
保留此前工作树修改；未运行竞争生成器、停止 watch 或修改生成物。

## 已确认的问题

### P2：构造 Zone 使已销毁页面的参数不能回收

位置：`packages/ccrouter_core/lib/src/runtime_host.dart:31`，factory 注入点
`:2151`，initializer 注入点 `:2282`。

页面的 Route Service 在 factory/initializer 中注册一个普通 Future completion
callback。该回调不引用 Service、页面参数或 Runtime。页面 exact close 后，
RouteEntry 已从活动栈移除，Service 已销毁一次；然而参数仍不能 GC。

已验证的保留路径：

```text
未完成 Future 的 listener / 被保留的 Zone
  → construction Zone value
  → _ServiceConstructionOwner.routeEntry
  → _RouteEntryRecord.request
  → arguments
```

原因是 construction owner 强持有完整 RouteEntry，且 Scope close 不撤销该引用。
当前的 invocation ownership 只保存 token，并未覆盖这个较早存在的 construction
Zone。后台回调的 Zone 生命周期因此延长了页面 payload 的生命周期。

证据：普通方法 Zone 的参数 GC 对照通过；factory 和 initializer 的保留 Zone
均失败；两种场景改为普通未完成 Future、且 callback 不捕获业务对象，仍失败。
清除保留 Zone 或完成该 Future 后，同一 WeakReference 的 target 可以回收。
分类为 **not-GCed**，并非 Service 的 `dispose` 没有调用。

建议让 constructor owner 保留生命周期信号和必要身份，对 RouteEntry 使用不拥有其
生命周期的弱引用或可撤销引用。活跃/仍在退出渲染的 Entry 继续由 Runtime 强持有；
关闭后的回调仍须明确拒绝解析，不能为了释放引用而退回当前可见页面。

### P2：已完成方法的 Zone 强持有已 shutdown 的 Runtime

位置：`packages/ccrouter_core/lib/src/invocation_ownership.dart:5`、`:55`。

普通 App Service 方法启动一个未完成 Future 的回调后成功返回。方法的回调不捕获
Runtime，随后 Runtime 已完成 `dispose`，但仍无法 GC。Future 完成后才能回收。
在 invocation 外注册同样回调的正常对照可以立即回收 Runtime。

原因是 `_InvocationFrame.runtime` 为强引用。它用于判断当前 frame 属于哪个
Runtime，却同时让外部 Future 的 listener 通过 Zone 保留整个已结束 Runtime。
Scope、listener 已完成清理并不等于 Runtime 对象和其注册图已不可达。
分类为 **not-GCed**；本轮没有测量实际 heap 字节或认定所有 Service 都被保留。

建议以 Runtime 专属、不反向引用 Runtime 的身份 token 匹配 frame，或使用弱引用。
同时审查 construction owner 等相邻 Zone 值，避免只修一个强引用路径。
不要在方法返回时清空所有权信号，否则会重新打开上一轮已修复的旧 Session 调用漏洞。

### P2：重复 TestHost.dispose 提前返回并隐藏首次清理失败

位置：`packages/ccrouter_test/lib/src/test_host.dart:104`。

`dispose` 在第一次异步清理开始前就把 `_disposed` 设为 true。第二次调用因为
`if (_disposed) return` 立即成功返回，即使第一次还在等待资源销毁；第一次 Adapter
清理失败时，第二次调用也返回成功。两个确定性测试均复现。

这影响测试基础设施，而非证明应用的 `CCRouterHost.shutdown` 有相同问题。
在手工 cleanup 与 `addTearDown` 重叠时，后者无法作为真正完成资源清理的屏障，
测试可能提前结束，且不同调用者得到不一致的结果。

建议分离“已禁止使用”与“清理已完成”，所有调用者加入同一次清理并观察结果。
修复时同时覆盖跨 Dart error Zone 的失败交付；单纯共享 error Future 可能使另一
Zone 的等待挂起。不要直接从测试包导入 Core 私有实现来复用结果容器。

## 方案取舍与推荐顺序

| 方案 | 收益 | 代价或风险 |
| --- | --- | --- |
| 应用逐个避免 Future/Timer 或保证立刻结束 | 无框架变更 | 无法解除框架 Zone 中的强引用，且不适合合法的独立后台工作 |
| 方法/构造一返回就清空整个 Zone ownership | 看似快速释放 | 破坏原 Scope fence、nested dependency 校验和共享初始化语义，不采用 |
| 弱化身份引用，保留取消信号与 exact ownership | 内部兼容修复，不增加公开 API | 需覆盖活跃、退出渲染、关闭后重入及多 Runtime 隔离 |
| 只在 TestHost 删除 `_disposed` 检查 | 可让后续调用进入 Runtime.dispose | 还需确认错误 Zone 和重复失败结果，不能当完整修复 |
| 统一清理结果屏障，逐调用者恢复错误 | 等待与失败语义稳定 | 需验证同步重入、异步资源和跨 Zone，不扩大业务 API |

推荐：

1. 先补 TestHost cleanup barrier，确保后续回归的 teardown 真正等待清理；保留
   once-disposal、相同错误 identity，并增加不同 error Zone 的用例。
2. 一起修 invocation frame 与 construction owner 的强引用；保持上一轮原调用链
   token fence、依赖生命周期验证、singleton initializer 独立性。
3. 将本轮确认缺陷的探针转入默认 suite，扩展到 Route/App/Session、正常完成和取消、
   exact close、退出渲染、Host detach 和 shutdown，然后重跑完整回归。
4. 对长时间停留在后台的真实订阅，再做 macOS heap/进程采样；GC 单测不能替代该项。

这几项可作为独立内部修改回退，不需要新增业务 API 或兼容旧缺陷的公开开关。
具体生产修复尚未执行；改变可观察生命周期语义时再同步 README、Skill 与 reference。

## 实际执行的验证

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 完整 Flutter 回归：框架、Demo、导航/analytics、支付/存储、Order example | 1292 通过 | [flutter.log](flutter.log) |
| analytics / Firebase / tool Dart suite | 55 通过 | [dart.log](dart.log) |
| Workspace analyze | No issues found | [analyze.log](analyze.log) |
| 参数/Runtime GC 新探针 | 2 通过、5 失败 | [retention.log](retention.log) |
| TestHost 清理新探针 | 0 通过、2 失败 | [test-host.log](test-host.log) |
| Demo generation freshness | 复用有效 watch cycle 98；up to date | [generation.log](generation.log) |
| 文档检查 | 检查器选择的 121 份 Markdown 通过 | [documentation.log](documentation.log) |

完整 suite 的数量是本轮实际重跑结果，不是复制上一轮结论；其执行日志移入本目录。
新增未修复探针都使用非 `_test.dart` 文件名并显式执行，未加入默认 suite。因此默认
1292 通过与新增探针 7 失败并不矛盾，也不能据默认通过声称本轮没有发现问题。
GC 使用 `WeakReference` 与 `forceGC(fullGcCycles: 3)`，同时验证释放外部 callback
后 target 消失。测试来源目录：
`packages/ccrouter_test/test/review_repros/runtime_round_trip/`。

第一次 GC fixture 编译因 snapshot 的 nullable `handle` 未解包而失败，未执行测试；
已更正为 fixture 保证存在的 exact handle。上表均为后续有效运行结果。

### 探索性多 Runtime 结果，不列为已确认生产缺陷

`repro.dart` 的 24 项 A → B → A 探索用例：12 项不切账号对照通过，12 项切账号后
不满足“恢复 A 旧调用来源”的候选预期，见
[round-trip-exploratory.log](round-trip-exploratory.log)。
当前 frame 是单个 Runtime-qualified Zone 值，B 会覆盖 A。这个实现观察已经证实；
但独立 Runtime 的跨越不是业务 Facade 的多 Host 接入模型（多个 Host 共享一个
Runtime），B 的 factory/singleton initializer 还存在刻意独立于首等待者的所有权语义。
在明确该跨 Runtime 合同前，不把候选预期当成当前产品承诺，也不据此宣称 Demo
多 Host 发生串账号。源文件已标明其探索性质，不加入默认 suite。

## 覆盖缺口与 Demo 判断

之前侧重 Service 是否执行一次 dispose、成功返回后的调用准入与 Service target GC，
没有同时检查 construction Zone 中的 Route payload、结束 Runtime 本体，以及第二个
cleanup awaiter 的完成语义。这解释了为何数量很多的默认回归仍可能漏掉新边界。
后续应按“Owner × 终态 × 遗留 callback × 被保留对象 × 多个 awaiter”建模，
避免只为上一个失败入口增加相似用例。

本轮未增加 Demo UI：现有 Service、Session、页面生命周期和多 Host 场景已有入口；
发现的是内部 GC 保留路径和测试清理竞态，重复按钮不能展示或证明 GC/await 屏障。
应优先加入上述确定性回归，并按需增加 heap 验收脚本。

没有新增 macOS 真实窗口操作、Android/iOS 真机手势、长期 monkey、吞吐或进程内存
基准；未改独立 Analyzer Plugin / Generator 生产代码，未运行其专属完整测试。
没有证据声称所有方面已经优于旧架构。
