# 导航历史回收修复与框架容量评估（2026-10-19）

后续状态：本文保留首次评估时的证据；其中异步 Diagnostic Sink 在途写入无界的问题，
已在后续[Sink 背压修复与验证](diagnostic-sink-backpressure-20261019.md)中处理。
原始探针 JSON 保留旧实现结果，当前探针另输出等待数和丢弃数。

## 结论和范围

本次定位为 GoRouter Adapter 的 `not-GCed` 缺陷：有界历史强引用 Flutter
Route，导致已 dispose 的 AnimationController 和 RouteSettings.arguments 继续存活。
修复将历史改为纯数据快照，保留原有容量、丢弃最旧记录的语义和同步 Observer 行为。
本地历史用镜像环形 List 消除满容量时的元素搬移，不改其他 Core 容器。
不改导航、Scope、结果通道、预测返回门禁或 Core 的运行队列。

审查范围为应用运行期的 Runtime、GoRouter Adapter、恢复需求桥、Analytics 和
DevTools 读取路径；不包含 Generator 文件缓存、Analyzer Plugin 索引和平台图像缓存。
记录条数上限不能直接换算成字节上限，也不能代替在目标设备上的堆分析。

## 缺陷证据及修复

原保留链：`Adapter._lifecycleEvents → 原始事件 → route / previousRoute → controller`。
默认 1000 条的列表在旧事件淘汰前始终强引用 Route，Adapter dispose 会清空列表，但
应用中的长寿命 Adapter 不应依赖整个 Host 退出才能释放已退出页面。

新增 `navigation_history_lifecycle_test.dart` 使用真实 Navigator 和 MaterialPageRoute，
分别执行五轮 pop、replace、remove。只保存 Route、AnimationController 和 arguments 的
WeakReference，在三轮已确认的 GC 后断言它们均为空。replace 每轮替换后再退出，共检查
10 个 Route/controller，其余路径各检查 5 个。Adapter、Router 和调用方历史快照在
断言时均保持存活，历史未达到 1000，不借助淘汰或 Host teardown 通过测试。

先在原实现运行：容量 0 的三组全部通过；容量 1000 的三组全部失败，失败输出明确显示
控制器为 `DISPOSED`。替换历史内容后六组全部通过。这同时验证了 GC 探针的有效性与修复因果。
最终另外加入容量 2 的三组，验证历史多次溢出后 Route、controller、arguments 也全部可回收。

`navigation_history_test.dart` 补充容量 0/1/2/3/1000 下的顺序、淘汰、只读快照独立性、
dispose 清空、原始 Route 回调和 Backend 事件投递，并覆盖奇数容量和多次环绕。
五种事件均保持原投递路径。

### Host SPI 迁移与所有权

- `adapter.lifecycleEvents` 的元素类型由 `CCGoRouterNavigationEvent` 改为
  `CCGoRouterNavigationEventSnapshot`，显式声明旧泛型或读取原始 Route 的 Host 代码需要迁移。
- `kind`、`hostId`、`outlet`、`location` 继续可读；历史中的
  `previousRoute?.settings.name` 改为 `previousLocation`。
- Observer 的 `onEvent` 和 `addListener` 仍收到同步原始事件，仅借用 Route。
  调用方自行保存原始事件仍会保留 Route，这不由 Adapter 的快照修复代管。
- 快照仅含 enum/String，不保留 Route、Widget、Context、controller、arguments 或 Extra。
  名称仍是 RouteSettings.name，可能包含实际路径和 Query，不是生产日志的脱敏协议。
- 容量 0 不创建历史快照，Observer、Backend 投递和导航协调继续工作。
  Adapter dispose 清空框架历史；调用方已取出的快照仍独立有效。

### 性能取舍

仅 Adapter 本地历史采用惰性镜像环形 List：未满时按原方式追加；首次溢出时复制一份
引用槽位，此后只覆盖最旧项的两个镜像槽位。满容量写入为 O(1)，读取用一次连续
`sublist` 复制和只读视图保持时间顺序，避免标准 Queue 的逐项复制开销。
两侧槽位指向同一个不可变快照，不复制 String 或快照对象。

代价明确：填满后逻辑槽位最多为 `2 × capacity`（原来为 N 个），保留的不同快照仍最多 N 个；
首次镜像创建为一次 O(N) 分配/复制，后续每个事件多构造一个轻量快照。
Dart List 的底层预留空间和对象布局另计；调用方每次取历史仍产生自己的 N 项独立副本。
容量 0 不分配镜像或快照。dispose 清空全部槽位并重置环形索引。
没有加入 Timer、额外监听、弱引用扫描或运行期兼容开关。
标准 Queue 和两段拼接的环形复制方案经测量有历史读取成本，因此不采用。

可复现基准：

```sh
fvm flutter test --no-pub packages/ccrouter_test/benchmark/navigation_history.dart --reporter expanded
```

同一进程、同一 SDK 内交替运行实际快照实现和仅用于基准的旧原始事件缓存参考。
双方走完整同步 Observer → Adapter → Backend listener 路径，各容量预热到满后测量，
7 轮、每轮 20000 条事件，并测量 500 次完整历史读取。两条固定 Route 在两侧均保持存活；
该基准只测时间，内存有效性由上面的真实 GC 测试证明。保留容量 0 作为无历史对照。
基准输出全部样本，不将某台机器的耗时作为 CI 阈值或真机帧率结论。
macOS/Linux 64-bit 还记录当前 mutator thread CPU time，以区分本机并行构建导致的调度等待。
该辅助值不包含其他 GC 线程和停顿，必须与 wall time 一起阅读，不能代替分配或端到端帧耗时。

最终测量及完整验证结果见本文末尾。

## 容量逐项评估

| 配置/容器 | 当前默认与实际边界 | 判断与建议 |
|---|---|---|
| `traceCapacity` | 1000；Trace 与 sanitized subscriber errors 各自最多 1000；0 关闭这两份历史 | 纯数据，默认适合排查，但不是总计 1000。Trace 为 Queue，错误为 List，错误风暴下 List 淘汰 O(N)。不因本缺陷直接降低默认；移动端可先试 256。 |
| `navigationDiagnosticCapacity` | 1000；导航 lifecycle、failure、capability fallback、visibility、Route Entry、Backend、restoration 七份历史各自计算；另允许最多 N 个 removed Backend ledger entries | 有界纯数据，未发现原始 Route 保留。1000 是宽松诊断窗口，不能当成总内存预算。移动端试验起点可为 128，需验证下述运行语义耦合。 |
| Observer 队列 | `max(64, navigationDiagnosticCapacity)` 个批次；非终态可淘汰，终态队列满时同步背压投递 | 64 的最小运行余量有现成边界测试。容量越小越可能丢非终态或把终态回调放回同步栈。不能当历史关闭开关，更不能统一改成 0。队列保存待投递闭包，属于临时投递所有权。 |
| Diagnostic Sink 待投递队列 | `max(64, navigationDiagnosticCapacity)`；无 Sink 不入队；满时丢最旧记录 | 与导航历史耦合不理想。只限制等待 handoff 的事件，**不限制已启动且未完成的 Sink Future**，无对应丢弃/并发计数。优先评估独立的 Sink 并发/背压配置；本次不改投递顺序或关闭协议。 |
| Backend 操作去重窗口 | `max(64, navigationDiagnosticCapacity)` 个 operation ID | 纯字符串，但窗口是正确性辅助状态。历史调小也会缩短乱序/重复操作的识别窗口。建议后续与历史容量解耦；保留现有 active-entry、sequence 与重复事件回归。 |
| Adapter `lifecycleEventCapacity` | 每 Adapter/Host 默认 1000；0 仅关闭本地历史；预测返回启用时另有同上限的 fallback history | 本次修复原始 Route 保留。纯快照后 1000 是可用排查窗口，不再放大为页面对象图，但位置字符串长度仍非字节预算。移动端本地排查试验可从 64 开始；镜像环形槽位最多 2N 个引用，快照仍 N 个；读取整份历史仍 O(N)，不宜盲目调大。 |
| 恢复需求 `pendingCapacity` | 64 个订阅前信号；正整数；takeInitialSignals 后清空；无订阅时再次暂存 | 信号发生率通常很低，64 合理且已有溢出/清空测试；不建议为罕见事件再增加配置复杂度。List 淘汰 O(64) 不构成当前高优先级优化目标。 |
| Analytics `capacity` | 256 个等待事件，另有当前投递事件；Queue 丢最旧并计数；close 等待排空 | 独立业务队列，默认可保留。用 peakQueueDepth、droppedEventCount、Sink 延迟选择容量，增加容量不能解决持续吞吐不足。默认无写超时，永久阻塞 Sink 可阻塞 close；需由接入方按语义设置现有 sinkWriteTimeout。 |
| Analytics payload limits | 每事件最多 64 属性、String 256 code units、List 32 项、总 value units 4096、黑名单 256 IDs | 数量和内容同时设限，明显优于仅有事件条数；4096 是逻辑单位而非精确 heap bytes，还不包含 Map/list/header 等开销。不建议放宽。 |
| Analytics `throttleCapacity` | 默认/硬上限 1024 个 event ID；可设 1..1024；未启用 throttle 时不填充 | 高基数时有界，但每次接受检查会扫描过期项，最坏 O(1024)。正常稳定 ID 场景可保留；高频产品事件应按真实 ID 基数选择更小值并测 CPU，不能用动态实例 ID 填满它。 |
| DevTools 快照读取 | 不新增持久历史，复制 Runtime 的各份列表；每次观察通知均可刷新整份快照 | 上限叠加会放大复制/重建开销。继续只在 Host debug/internal gate 打开；不能为此把 Core 活动状态截断。后续若有性能证据，再评估合并刷新或分页。 |

### 总预算与生命周期边界

只按历史容器的最大记录数估算，Runtime 为 `2 × traceCapacity + 8 × navigationDiagnosticCapacity`，
其中 8 包含七份历史与 removed Backend ledger。单 Host Adapter 再加 `lifecycleEventCapacity`，
启用预测返回时还可能再加一份 fallback。全默认单 Host 的这些历史容器合计可达 11000 条，
预测返回启用时可达 12000 条；这不是对象去重后的数量、启动预分配量或实际字节。
某些事件共享不可变值，也并非每种历史在每个业务流程都会填满。
镜像环形 List 额外持有 N 个引用槽位，不增加上面的不同历史记录数量。

上述估算不包含当前活动 Route/Backend/Scope、pending navigation、正在运行的回调、
观察/日志待投递队列、去重窗口、应用保留的快照和 Sink 自己的缓存。
活动结构数据必须随生命周期正确释放，不应按诊断容量随意淘汰。
历史关闭不会取消真实导航或合法存活资源。

原生应用的内存预算还取决于 String 大小、事件率、Host 数、Dart VM 对象布局和分配器；
不以一个推算 MB 值宣称所有设备安全。Adapter 名称没有额外长度限制，需要特别注意
应用自行提供的超长 RouteSettings.name，不能把大对象序列化到其中。
Trace、导航历史和 Adapter 容量只校验非负，没有统一硬上限；应用仍需为配置值负责。
排查窗口应按“该类每秒事件数 × 希望保留的秒数”估算，而不是把 1000 条理解为 1000 次页面访问。

### 推荐方案与后续顺序

1. 本次交付最小快照修复和 GC/行为回归，不同时修改默认数值。
2. 正常开发保留 1000 作为诊断/A-B 基线；生产应用可试 `trace=256 / navigation=128 /
   adapter=64`，它只是待设备验证的起点。若不需要 Adapter 本地历史可单独设 0。
3. 在相同目标设备和同一业务序列上记录堆、GC 后控制器数量、事件速率、诊断窗口、
   丢弃/背压和 Sink backlog；恢复原配置即可回退容量试验。
4. 优先另立修改，解耦“历史保留”“Observer 运行队列”“Sink 待投递/在途写入”和
   “去重窗口”。这涉及公开配置、失败和关闭语义，不能以内部改常量代替契约设计。
5. 对其余 List 淘汰、Backend removed-ledger 扫描、throttle 扫描和 DevTools 重建，仅在对应
   场景有性能证据后优化；同时检查写入、读取、额外分配与业务帧耗时。

## 验证记录

- `CCROUTER_PUB_HOOK_DISABLE=1 fvm flutter pub get` 成功：仅解析测试新增的直接
  `leak_tracker` 依赖，不把 Workspace 根目录当成 Host 做生成验证；锁定版本未变化。
- `fvm flutter test --no-pub packages/ccrouter_test/test --reporter expanded`：505 个通过。
  包含九组 GC 回收对照、五组历史边界，以及现有 Observer/Adapter、Runtime、预测返回等回归。
- 在 `demo/` 执行 `fvm flutter test --no-pub --reporter expanded`：61 个通过。
- `fvm dart analyze`：Workspace（包含 Demo）无问题；性能/容量探针最终文件另行 analyze 无问题。
- `fvm dart run packages/ccrouter_test/benchmark/diagnostic_capacity.dart`：容量
  0/64/128/1000 时，2000 次 Command 的 Trace 分别保留 0/64/128/1000 条；
  四种配置的未完成 Sink 写入均达到 2000。每十次 Command 允许一次队列排空，
  每次突发低于最小队列容量，排除了单次队列溢出的干扰。探针最后释放所有 Sink Future。
- 未修改注解、生成契约、Host 装配或 Analyzer Plugin，不涉及 Plugin pin 更新。
- 本次验证是框架通用 Flutter 回收与 Demo 行为回归；没有连接原业务设备重复 ViewModel/Rive
  的原始五次往返，也没有用调试机微基准宣称真机帧率完全不变。

### 最终性能 A/B

本地 Dart 3.11.1 / Flutter test，7 轮中位数。下表为 mutator thread CPU 微秒，
旧实现参考与实际快照实现交替运行，读取特意让缓冲区处于非零 head，避免只测对齐快路径。

| 容量 | 旧写入 / 事件 | 新写入 / 事件 | 旧完整读取 | 新完整读取 |
|---|---:|---:|---:|---:|
| 0 | 0.470 | 0.375 | 0.084 | 0.091 |
| 2 | 0.497 | 0.421 | 0.072 | 0.081 |
| 1000 | 3.793 | 0.479 | 2.980 | 2.201 |
| 10000 | 34.725 | 0.483 | 33.694 | 16.389 |

默认容量下，稳态写入 CPU 中位数下降约 87%，完整读取下降约 26%。
容量 0/2 的读取差值约 0.008–0.010 微秒，且单轮样本波动明显，不据此宣称微小值有提速或退化。
容量 1000 的 wall time 中位数为写入 12.802→0.876 微秒、读取 5.394→3.684 微秒。
忙碌主机的 wall time 有明显尖峰（包括容量 2），不能外推到真机导航/帧耗时。
首次溢出镜像分配不在稳态计时中；其 O(N) 一次性成本与额外引用槽位是已知取舍。

完整 wall/CPU 样本和 Sink 容量探针保存在
[机器可读结果](navigation-history-capacity-20261019.json)。
