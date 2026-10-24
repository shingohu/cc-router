# 诊断上下文、健康快照与 DevTools 修复（2026-10-24）

源码基线：`4af9846de8f0dfaba027c6193c0c08737b7a1a85` 加本轮工作树。
本轮修改 Contracts/Core/Facade、可选 DevTools、协议、官方 Extension 和 Demo 日志桥，
未修改 Analyzer Plugin production 或 Demo Plugin pin，未提交推送。

## 问题与方案

正常拦截器取消曾产生两条 navigation error；失败观察缺具体 Host/Outlet，Sink 丢失
reason/attempt/recoveryDepth；VM 协议缺 Failure/Fallback/Pending/InitTask 和投递健康。
原面板只订阅导航事件，非导航调用不刷新，且高频导航会反复复制完整历史。
容量关闭、历史轮转和外部 Sink 丢弃也无法区分。

仅在应用 Logger 补字段不能恢复 Core 已丢失的归属；新增全诊断 Core 订阅系统会扩大
生命周期和投递队列责任。因此采用只读轻量计数，加可选工具端订阅期间的低频检查。
没有新 Core Timer、业务导航参数或控制命令；已有导航调用保持原样。

## 已实现

- Failure Context / Pending 增加兼容的 optional Host/Outlet；跨 Host redirect、recovery 和
  pending replay 跟踪实际目标。未知 URI 目标不继承上一次 Route/Outlet；已知 typed Route
  的参数失败可读取声明 placement，不重跑 Codec。目标未解析时保留调用 Host 归属。
- Sink 增加固定 reason/attempt/recoveryDepth，正常导航取消为 warning，最终 status 为
  cancelled；生命周期 phase 仍为 failed。recovered 只表示选择恢复，不保证后续成功。
  取消级别按错误对象类型判断，不依赖发布混淆后的 runtimeType 字符串。
  不导出任意业务取消 code、异常原文、地址、参数或结果。
- `CCRouter.diagnosticSnapshot` 提供 Runtime identity/revision、七类事件历史的
  retained/capacity/omitted，以及独立 Sink 健康计数，不复制事件历史。
  omitted 是容量关闭或轮转造成的未保留，不包含采样和外部过滤；队列丢弃另计。
  订阅者错误和已移除 Backend ledger 不在这七类事件历史中。
- Provider 订阅时每 250ms 比较轻量 token，包含独立变化的 Sink 完成计数；发生变化才通知
  消费者读取完整快照。覆盖 Command、Service、InitTask、Pending、Runtime 重建；面板在
  TickerMode 关闭、Provider 替换或卸载时释放订阅，恢复时立即读取新快照。
- 协议 v1 添加 optional diagnostics/diagnosticHealth。旧 Producer 缺字段时保持 null，
  UI 显示未提供，不能解释成零失败；存在但格式错误的已知字段明确拒绝。
  Extension 新增手动刷新的 Diagnostics 页。嵌入面板补健康状态和完整失败归属，并修复小屏标题溢出。
- Demo 日志桥和只读页面保留新字段；复用已有取消、失败、能力实验室及诊断入口。
  README、Integration Skill 和对应 reference、包说明与 Changelog 同步。

## 验证记录

| 检查 | 本轮结果 |
| --- | --- |
| 框架 + DevTools + Protocol 首轮全量 | 1438 项通过；之后新增突发合并、失败展示及 Provider 替换共 3 项测试 |
| 后续并行全量 | 1437 项通过、2 项 GC 弱引用断言失败；保留失败，未记作全绿 |
| 两个 GC 文件串行复核 | 35 项通过；未更改原测试断言或增加重试来掩盖失败 |
| 最终串行框架 + DevTools + Protocol 全量 | 1441 项全部通过，用时 1 分 29 秒，包含最终取消分类与展示断言 |
| Provider 突发合并、启动/重建、任务、Sink 完成、移除 | 4 项通过；100 次 Command 在一个检查间隔内只通知一次 |
| Demo 最终全量 | 串行 114 项全部通过，包含加强的取消日志桥断言，用时约 53 秒 |
| Demo 无缓存生成检查 | 生成器集成测试结束后复核通过：6 组件、34 Route、11 Packages 最新 |
| 根目录静态分析 | 生成器结束并恢复现场后重新执行，无问题 |
| Demo 静态分析 | 最终复核无问题 |
| 官方 Extension | Flutter stable 3.44.9 隔离副本 Web release 构建成功，官方 validate 输出 successful |
| Skill | quick_validate、独立双 Skill 分发包及真实 CLI 指令检查通过 |
| 文档、格式与敏感信息 | 181 份 Markdown 链接检查通过；29 份变更 Dart 格式无需调整；证据脱敏后 include-untracked 敏感信息门禁通过 |
| Generator/CLI 全量 | 51 分 31 秒：667 项通过、1 项跳过、1 项指纹对照失败；未记作全绿 |
| Generator 指纹对照独立复验 | 最终源码冻结后 1 项通过，用时约 70 秒；期间未改源码或并发生成 |

框架命令从根目录执行：

```text
fvm flutter test --no-pub --reporter expanded packages/ccrouter_test/test packages/ccrouter_devtools/test packages/ccrouter_devtools_protocol/test
fvm flutter test --no-pub --concurrency=1 --reporter expanded packages/ccrouter_test/test packages/ccrouter_devtools/test packages/ccrouter_devtools_protocol/test
fvm flutter test --no-pub --concurrency=1 --reporter expanded packages/ccrouter_test/test/navigation_history_lifecycle_test.dart packages/ccrouter_test/test/managed_cross_lifecycle_regression_test.dart
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test
fvm dart test --concurrency=1 --reporter expanded packages/ccrouter_test/generator_test/generation_watch_test.dart --plain-name 'watch evidence reuse keeps current Builder-only output bytes'
```

## 检查边界与未归因项

生成器全量中的 watch 集成测试会临时修改真实 Demo 源码及生成物，并在 finally 恢复。
将其与根目录分析并行是本轮执行安排错误，分析读到了测试临时插入的 `_nextLevel` 方法，
不能记作产品静态分析失败。后续源码门禁改为等其结束后串行执行。

全套中的 `watch evidence reuse keeps current Builder-only output bytes` 对照期间，
执行者又修改了 DevTools 面板源码，导致两次取证的
`ccrouter_devtools.authoredInputFingerprint` 及传播指纹不同。比较输入已变化，
该次运行不能证明 Generator 产品缺陷，也不能记作通过。全套结束后，完成最终源码修改，
冻结源码单独复验该用例通过；原始失败和独立复验分别保留。
默认跳过的是需显式启用 `CCROUTER_ANALYZER_NETWORK_SMOKE=1` 的远端网络测试。

第二轮框架全量的两个失败分别为：
`replace releases Routes and controllers with live history capacity 0` 与
`live Adapter releases old Routes after renderer remount`。已观察到 Route disposed，
但弱引用在该次强制 GC 后仍非空。首轮全量及随后两个文件的 35 项串行运行通过；本轮
未发现新增高置信对象保留链，也不能仅凭重跑通过就将失败归因为系统负载。
最终完整框架回归改为串行执行，1441 项全部通过；保留前述失败作为 GC 稳定性跟进证据。

首次 Web 尝试虽然调用官方 SDK，但复用了 OHOS 工作区 package config，产生
OperatingSystem.ohos 编译错误，属于 SDK 混用。改用临时 Extension/Protocol 副本，
仅移除 workspace 解析要求、将 Protocol path 指向副本，并用同一官方 SDK 离线解析及构建。
未改动工作区 SDK/lockfile。隔离解析的 vm_service 为 15.4.0，工作区为 15.3.0；
devtools_extensions 和 devtools_app_shared 均为 0.4.0。这是官方 SDK 的工具构建验证，
不是工作区 lockfile 的等同构建认证。构建仍有 CupertinoIcons 字体提示，未作无警告声明。

本轮没有做 macOS 实窗、Android/iOS 手势或新的原生 heap、PSS、长期性能采样。
250ms 是刷新合并策略，不是实测性能提升比例。已有 Native 字体分配等平台开放项保持原结论。
新计数不保留业务对象；新增 Timer 由工具订阅所有者取消，隐藏、替换和卸载边界有回归。

## 原始证据

以下日志仅机械脱敏本机用户路径，保留实际断言、计数及失败结果；未将失败日志改写为通过。

- 框架：[首轮通过](framework-initial.log)、[后续并行两项失败](framework-prior-parallel.log)、
  [两个 GC 文件独立复核](gc-isolated.log)、[最终串行全量](framework-final-serial.log)。
- 生成器：[全套原始结果](generator-full.log)、[冻结源码后的指纹对照复验](generator-fingerprint-recheck.log)。
- Demo：[最终测试](demo-final.log)、[最终无缓存生成检查](generate-final.log)。
- 静态分析：[根目录](analyze-final.log)、[Demo](demo-analyze-final.log)。
- 官方 Extension：[隔离 Web 构建](extension-web-build.log)、[官方 validate](extension-validate.log)。
- 收口：[文档](documentation-final.log)、[Skill 分发](skill-bundle-final.log)、
  [Skill 结构](skill-schema-final.log)、[格式](format-final.log)、[敏感信息](sensitivity-final.log)。

## 性能审查后的内部优化

性能审查发现：固定七类健康记账在每条观察上执行字符串 Map 读写；无 Sink 时仍经过
投递策略并构造待丢弃事件；空闲面板每次检查都会新建健康 DTO。默认未订阅工具没有
轮询 Timer，但常驻记账不能描述为零成本。

关闭默认健康统计可消除部分成本，却会改变已约定的完整性语义并增加 Host 配置。
因此选择内部优化：七个固定整数计数、无 Sink 提前返回、未变化的不可变健康值复用。
未新增公开 API、开关、Timer、业务对象保留或 I/O。Framework Skill 的 API 隔离与
生命周期规则用于约束实现；本轮接入行为不变，不另增接入文档或 Demo 场景。

Runtime 缓存同时检查 observation revision 和 delivery 快照 identity；delivery getter
比较 queue/inFlight/peak/delivered/failed/dropped/closed 标量，未变化时复用 DTO。
比较发生在读取时，不向 enqueue/drain 热路径增加缓存失效工作。关闭后晚到的成功/失败
也会刷新。Scope 清理可能在 Sink 关闭后读取快照，因此清空导航历史时还会推进 revision。
缓存只保留标量 DTO，不反向引用 Runtime、Sink、Route、Context 或业务 payload。

新增 6 项测试覆盖七类历史在容量 1000/1/0 下的 lifetime/retained/omitted 一致性、
空闲复用、无 Sink Command、Runtime 身份隔离、Sink 排队/溢出/完成/关闭/晚到失败，
以及清理中读取快照。最初的 5 项缓存测试在优化前失败，见 [原始结果](cache-before.log)。
专项首轮 67 项通过、2 项失败，原因是新测试未过滤构造成功事件，容量 1 时提前发生
一次丢弃；修正夹具过滤条件后通过。扩展七类历史夹具曾误写 enum 值 `pushed`，
编译失败后改为现有 `push`。这些是本轮测试编写错误，未据此修改产品语义；
[专项首轮](optimized-focused-initial.log)、[编译错误](cache-authoring-error.log)、
[最终新增 6 项通过](cache-final.log)分别保留。

### 同机 AOT 对照

同进程同时加载两份 Core，共用当前 Contracts，相邻 64 操作批次交替顺序。
51 轮中剔除前 2 轮，49 轮实测；每轮 Command 10000 次，Open-Go 1000 次。
以下单位为线程 CPU 微秒/操作，变化为逐轮配对百分比的中位数，不能直接用两列
边际中位数相除代替。没有与测试或构建并行采样。

先保存未提交的优化前 Core，再与优化后对照（均为历史容量 0）：

| Command 场景 | 优化前 | 优化后 | 配对变化中位数 |
| --- | ---: | ---: | ---: |
| 无 Sink | 2.42823 | 2.37179 | -2.51% |
| 同步 Sink | 2.46380 | 2.41353 | -1.97% |
| Future Sink | 2.45801 | 2.41635 | -1.73% |

再使用原六场景探针，对比 HEAD `4af9846de8f0dfaba027c6193c0c08737b7a1a85` 与优化后：

| 场景 | HEAD | 优化后 | 配对变化中位数 |
| --- | ---: | ---: | ---: |
| 默认 Command，容量 1000，无 Sink | 2.67306 | 2.66795 | -0.68% |
| Command，容量 1000，同步 Sink | 2.68266 | 2.69991 | +0.53% |
| Command，容量 1000，Future Sink | 2.71713 | 2.70833 | +0.19% |
| Command，容量 0，无 Sink | 2.72421 | 2.71138 | -0.37% |
| Open-Go，容量 1000，无 Sink | 10.39338 | 10.08092 | -2.66% |
| Open-Go，容量 0，无 Sink | 9.67188 | 9.59688 | -1.56% |

优化后未再呈现此前六场景普遍 +0.93% 至 +3.19% 的方向；两个开启 Sink 的场景
仍有 +0.53% / +0.19% 的配对中位数，不能声称严格零回退或统计显著提升。
共同 Contracts、线程 CPU 和单机微基准均不等同于完整对象布局、GC、Flutter 帧延迟、
功耗或真机长期内存认证。空闲读取由测试证明复用同一不可变值，本轮没有用 heap profiler
测量分配字节数，也没有重跑 Android/iOS/macOS 实窗验收。

证据：[优化前与优化后原始样本](performance-preopt-vs-optimized.json)、
[HEAD 与优化后原始样本](performance-head-vs-optimized.json)、
[此前 HEAD 与优化前原始样本](performance-head-vs-preopt.json)、
[六场景探针](performance-extended.dart.txt)、[仅本轮优化差异](performance-optimization.patch)。
三场景探针复用 `packages/ccrouter_test/benchmark/compare_diagnostic_delivery.py`
的 `--reference-core`，未覆盖此前可执行文件或原始样本。

### 优化后回归

| 检查 | 结果 |
| --- | --- |
| 框架 + DevTools + Protocol，串行全量 | [1447 项通过](optimized-framework.log)，约 87 秒，包含新增 6 项边界测试 |
| Demo，串行全量 | [114 项通过](optimized-demo.log)，约 49 秒 |
| 根目录 / Demo 静态分析 | [根目录](optimized-analyze.log)、[Demo](optimized-demo-analyze.log)均无问题 |
| 真实 Host 无缓存生成检查 | [6 组件、34 Route、11 Packages 最新](optimized-generate.log) |
| 改动 Dart 格式 | [10 个文件无需调整](optimized-format.log) |
| 文档与证据敏感信息 | [181 份 Markdown 链接检查通过](optimized-documentation.log)；[include-untracked 门禁通过](optimized-sensitivity.log) |

本轮框架命令仍从根目录执行，Demo 测试和分析从 `demo/` 执行。
生成检查使用 `fvm dart run packages/ccrouter_generator/bin/ccrouter.dart generate demo --no-cache --check`，
保留 build_runner 增量状态，不冒充冷构建基准。
没有修改 Generator 或 Plugin production，不重复此前约 51 分钟的 Generator 全套，
也不把真实 Host 检查冒充该全套结果。最终变更审查未发现新的高置信生命周期泄漏，
也未新增生产轮询、历史遍历或公开契约变更；本轮未提交推送。
