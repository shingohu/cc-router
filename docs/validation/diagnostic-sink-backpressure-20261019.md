# Diagnostic Sink 背压修复与验证（2026-10-19）

完成快照：当前交付包含 Core Sink 有界串行投递、构造失败清理、Host 启动回滚和普通
shutdown 的跨 error Zone 等待修复。接入规则见根 README 的
[Runtime 生命周期](../../README.md#runtime-生命周期)及
[诊断与容量](../../README.md#aspecttracetelemetry-与生命周期)。
下文按阶段保留失败回归和性能证据；最新验证数字统一见[最终检查](#最终检查)。
Core 性能数据不覆盖后续 Host 生命周期修改，业务真机堆与帧耗时尚未验收。

## 问题与方案取舍

属于框架有界投递承诺的缺陷。原路径是 Runtime 队列 → `sink.record` →
`unawaited(result.catchError(...))`：事件一交付就脱离容量约束，异步写入没有上限。
2000 个 Command、每 10 次让出事件循环且不完成 Sink Future 时，四档容量的
未完成写入都达到 2000。这里只确认未完成工作的无界保留，不声称每个应用 Sink
都存在永久泄漏；实际网络资源仍由 Host 所有的 Sink 管理。

| 候选方案 | 收益 | 代价与结论 |
| --- | --- | --- |
| 只让应用或可选 Sink 包装器限流 | Core 无改动 | 现有默认有界承诺仍不成立，且所有 Host 都需自行补洞；不采用 |
| 写入超时后继续投递 | 表面上投递继续 | Dart Future 不可取消，旧写入仍存活，会重复产生无界工作；不采用 |
| 等待 Sink 后再结束业务调用 | 不丢诊断 | 慢日志反压导航、Command 等业务；不采用 |
| Core 独立私有投递器，单个在途写入及有界等待 | 明确上限、FIFO、错误隔离，不阻塞业务 | 慢 Sink 会更多丢弃等待诊断；采用并提供计数与独立容量 |

本报告覆盖 Diagnostic Sink 及其失败终止所需的 Host 生命周期修复，不修改 Analytics、
Observer 队列、Backend 去重窗口，也不统一降低历史默认容量。无需业务特例、额外
Adapter 或第三方依赖。导航历史回收另见[容量评估](navigation-history-capacity-20261019.md)。

## 实现与所有权

- `_DiagnosticDelivery` 是 Runtime 私有的投递所有者，按 FIFO 从 Queue 取事件，
  最多一个未完成 `record` Future。等待队列满时丢最旧事件，包括 error 级别；
  不引入无限重试、超时替换写入、网络任务或业务等待。
- 新增可选 Host 配置 `CCDiagnosticsConfig.queueCapacity`，仅接受正整数；
  null 继续使用原来的 `max(64, navigationDiagnosticCapacity)`，保留现有容量行为。
  这是等待条数上限，另有最多一个在途写入，不是字节上限。
- 新增业务只读值 `CCDiagnosticDeliverySnapshot` 与
  `CCRouter.diagnosticDeliverySnapshot`；只含容量、当前等待/在途、队列峰值、
  成功/失败/丢弃数和关闭状态，不暴露事件、闭包或 Runtime。
- 同步与异步 Sink 共用有限批次预算，不复制额外的 pending List；预算仅在 Timer
  批次入口或空闲关闭的最后尝试中设置为当时的队列长度。Future 成功或失败都消耗
  同一预算，耗尽后才通过 Timer 继续，避免重入形成无限 microtask 链；同批内不为
  每个事件增加 Timer。
- Timer 创建、Sink 调用、Future 回调注册和关闭最终投递均使用 Runtime 创建时的
  Host Zone，保留 Host 上下文，避免继承嵌套 invocation Zone 中的 Runtime 引用。
  直接切到 `Zone.root` 会丢失 Host 日志/测试上下文；fork 并遮蔽 Zone value 仍持有
  parent Zone，不能断开保留链；因此采用捕获创建 Zone 的私有实现。
- 关闭停止接收并取消 Timer。空闲槽位进行最后一次尽力投递，以保留同步 Sink 的
  Host 停止日志；遇到未完成 Future 就停止，清空剩余等待事件并断开 Sink 引用。
  已忙碌时直接清空余量，不等待在途写入，也不关闭外部 Sink。
- 晚到完成或失败只更新投递器计数，不恢复投递。Future 的回调持有私有投递器及
  Host 上下文，不继承后续调用的 invocation Zone。Host 负责 Sink 的网络取消、自有缓存与最终 flush。
  同一 Sink 被多个 Runtime 使用或反复重建 Runtime 时，Host 仍须管理整体并发。
- 不增加自动超时；永不完成的 Future 占住一个槽位，业务继续，队列持续按上限淘汰。
  失败可释放槽位，失败本身不会递归写入同一 Sink。
- 回退可单独撤回本次 Sink 修改；容量试验只需恢复 `queueCapacity: null`。
  不提供恢复无界写入的生产开关；性能基线放在临时独立 Core 副本中比较。

## 回归与生命周期验证

先在旧实现增加失败回归：4 档容量的在途限制测试与异步失败恢复测试全部失败；
旧实现交付了 2000 条而不是单条在途写入。修复后共 25 项专项用例覆盖：

1. 容量 0、64、128、1000：2000 次 Command 完成，不等待 Sink；在途始终最多 1。
2. 异步失败释放槽位；溢出后精确匹配保留事件的 invocationId 顺序及丢弃数。
3. 显式容量 2 独立于导航历史容量 1000；首次交付前也严格淘汰最旧事件。
4. 同步 throw、同步完成 Future、重入产生诊断、Sink 内关闭，不会死锁或停摆。
5. 关闭时同步日志仍投递；空闲关闭最多启动一个异步写入，其余释放。
6. 关闭后晚到错误被吸收，不开始新写入；重复 dispose 不重复投递。
7. 顶层调用、嵌套 Command、包含 Runtime 引用的另一个 Zone 发起空闲关闭三条路径：
   Sink Future 未完成且 Sink/Future 保持存活，已关闭 Runtime 的 WeakReference 在
   `forceGC(fullGcCycles: 3)` 后为空。嵌套用例的 Future 在测试外层 Zone 预先创建，
   排除 Sink 自身创建 Future 时的 Zone 引用干扰。
8. 无效显式容量在组件安装前拒绝，快照独立且不暴露 payload。
9. 同步成功/抛错、SynchronousFuture、Future.value、Future.error 五种模式，各用
   1/3 条初始事件重入生成共 128 条：普通 Timer 分别在第 1/3 次写入后运行，全部
   FIFO 与成功/失败计数精确匹配，无丢弃；同时验证 Host Zone marker 保留。

Review 曾发现首轮修复的两处缺口：嵌套 invocation Zone 经 Timer/then 保留已关闭
Runtime；异步完成重置预算导致重入 microtask 饥饿。新增 12 条用例先在 review 前
实现运行，均失败（原有 13 条通过）：两个 WeakReference 不为空，四个 Future 成功/
失败用例的普通 Timer 直到 128 次写入后才运行，其余模式继承了 caller Zone。
修正后全部通过。原失败恢复用例显式等待下一批 Timer，FIFO、数量和关闭断言不变。
仅靠顶层 GC 用例不能证明嵌套调用的 Zone 引用已释放，此次已补齐该验证范围。

首次全量回归曾捕获 `hostToolStop` 同步日志丢失；增加关闭时的空闲尽力投递后，
原有断言保持不变并通过，不通过修改既有测试掩盖兼容问题。

### 构造失败的投递器清理

再次 review 发现构造终止缺口：`_installComponents` 或 `_applyServiceOverrides`
抛错后没有返回可供调用方 dispose 的 Runtime，但已排队的投递器仍会启动。未完成的
Sink Future 经完成回调持有投递器，投递器继续持有 Sink 和剩余诊断。独立 GC 探针
确认当前实现的 Sink 在 `forceGC(fullGcCycles: 3)` 后存活，最初 Core 基线可以回收；
释放 Future 后当前实现也能回收，证明是具体的 `not-GCed` 保留链。

直接丢弃队列会丢掉全部初始化失败日志；在构造 catch 中同步 flush 会改变既有异步
调用边界。因此在构造异常路径调用私有 `closeDeferred`：立即停止接受，取消原 Timer，
在 Host Zone 安排一次最终投递和清理。同步 Sink 的既有失败日志仍按 FIFO 交付；
遇到首个未完成 Future 就丢弃余量并断开 Sink，不等待异步写入，也不 dispose Host
所有的 Sink。调度失败直接释放数据，不掩盖原始构造异常。最后清理使用 finally；
正常投递批次和每条事件不增加状态判断、Timer、Future 或回调。

新增 `diagnostic_construction_failure_test.dart` 的 19 项回归：

- 清单校验、Registrar、Service Override 三种失败各覆盖晚到 success/error：
  6 条 GC 用例在修复前全部失败，其余首批 9 条兼容用例通过。修复后在 Future 仍
  未完成时 Sink 即可回收，晚到完成不会继续等待队列。
- 三种失败分别覆盖同步成功、同步 throw、SynchronousFuture：全部保留原来延后
  一轮的诊断顺序与 Host Zone；Registrar 错误保持相同实例和原始 StackTrace。
- 三种失败分别模拟最终 Timer 调度被拒绝：原始构造错误不变，Sink 可回收。
- 未配置 Sink 时不创建清理 Timer。

构造失败修复阶段，与背压和原诊断测试合计 52 项专项用例通过。此处只终止未返回实例的构造失败投递；
外部 Sink 的在途 I/O 仍归 Host 管理，失败诊断也受尽力投递语义约束。

### Host 初始化失败的 Runtime 回滚

后续 review 使用真实 `CCRouterHost.initialize` 入口发现另一个所有权缺口：构造成功后，
InitTask 缺失依赖等配置错误会使 `Runtime.initialize()` 抛错。Host 原来只撤销绑定，
没有 dispose 这个尚未发布的 Runtime；调用方也无法通过 Facade 或 shutdown 取得它。
未完成的 Sink Future 经投递器继续保留 Sink，构成可复现的 `not-GCed`。

应用补救拿不到该实例；可选 Adapter 无法覆盖尚未绑定 Backend 的失败；在 Core 自动
dispose 又会改变直接持有 Runtime 的调用方所有权。因此只在 Host 的失败路径补齐
回滚，不新增公开 API 或改变 Core 初始化语义。正常启动仅增加局部所有权引用的赋值；
启动回滚相关的门禁和异步清理只在已创建 Runtime 的启动失败时分配；普通 shutdown
使用下节的共享清理门禁。

Host 在任何 detach 或 Runtime 取消回调前建立 shutdown 门禁，并自动 dispose 未发布
Runtime。原始启动错误和 StackTrace 同步重抛；`shutdown()` 可加入回滚，期间新
初始化被拒绝，清理完成后可重试。绑定逆序撤销，其中一项抛错仍继续释放其余绑定和
Runtime。加入的 shutdown 可观察结构性清理错误；无加入者时错误也被处理，不产生
额外未处理异常。构造或更早的 attach 失败仍保留立即重试行为。外部 Sink 不由框架
关闭；失败诊断继续遵循尽力投递规则，不承诺全部交付。

Host 回滚初版新增 `host_initialization_failure_test.dart` 的 10 项回归。修复前 7 项失败、3 项通过；
修复后全部通过，覆盖：

- pending Future 保持存活时，Sink 的 WeakReference 在 3 轮 full GC 后为空；
  晚到成功和错误均不恢复等待队列，两种结果各一例。
- detach 内重入 shutdown 会等待清理，逆序 detach、回滚期间初始化拒绝、完成后
  重启、重复 shutdown 均正确；未发布 Runtime 不启动 Host Tool 回调。
- detach 抛错不会替代原始配置校验错误及其栈，仍完成 Runtime 诊断释放；加入的
  shutdown 返回原始清理错误及其栈；无加入者时不产生未处理异常，门禁自动解除。
- 同步成功、同步抛错、SynchronousFuture 三种 Sink 保留尽力投递的启动失败诊断，
  清理后不再投递；构造异常的实例/栈与立即重试、低层 Runtime 自主 dispose 均保持。

### 跨 error Zone 的清理等待

进一步 review 发现：共享门禁原来直接以错误完成。在 `runZonedGuarded` 内启动失败、
detach 抛错时，父或另一个 error Zone 调用 `shutdown()` 会永远等待，同时启动 Zone
收到重复的未捕获错误。同 Zone 的内部 onError 不能让 Dart 跨 error Zone 传播失败。
普通 shutdown 的并发加入也使用相同机制，存在同样缺陷。

限制 Host 只能在同一 Zone 使用会破坏合法的组合根/错误监控接入；切换到根 Zone 会
丢失调用方上下文，也不能解决把失败 Future 跨 error Zone 传递的根本约束。采用私有
结果桥接：共享门禁只成功完成，以可空私有 record 保存原始错误及 StackTrace；清理
错误在发生的 Zone 中被捕获，各 `shutdown()` 调用再在自己的 Zone 重抛。正常停止
和启动回滚共用这一机制，绑定、Runtime、Backend 的释放顺序和错误优先级不变。
门禁的解除回调在任何可重入用户回调前注册，确保任一等待者返回时已允许重新初始化。
无等待者的启动回滚不会产生未处理错误，清理本身仍只执行一次。

新增 6 项回归先在修复前运行：4 项因永久等待而超时、2 项成功清理兼容用例通过。
修复后覆盖启动回滚与普通 shutdown 两条路径，分别验证：

- 成功/失败时，发起者、父 Zone、另一个 guarded error Zone 三方并发等待均结束；
  错误实例及栈保持一致，各方完成于自己的 Zone，无额外 uncaught error，detach 仅一次。
- detach 回调跨 error Zone 重入 shutdown 不提前完成，也不允许同步重入初始化；
  加入者处理清理错误后即可初始化新 Host，即使发起 shutdown 的调用尚在恢复执行。

原 10 项启动失败用例及已有取消/绑定清理用例继续保持。新机制仅在每轮 Host 清理及
每位加入者处增加固定数量的 Future/回调，并在失败时创建错误 record；正常启动和每条
Command/Sink 投递没有新增工作。不用 Core 微基准推断这次 Host 修改的成本，也不宣称真机
零开销。直接把 `shutdown()` 返回的可能失败 Future 跨 error Zone 转交仍受 Dart
规则约束；各方应在自己的 Zone 调用并处理该 Future 后传递结果。

修复后的原容量探针：

| 原容量配置 | 等待上限 | 峰值未完成写入 | 等待事件 | 已丢弃事件 |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 64 | 1 | 64 | 1935 |
| 64 | 64 | 1 | 64 | 1935 |
| 128 | 128 | 1 | 128 | 1871 |
| 1000 | 1000 | 1 | 1000 | 999 |

各行均为 2000 次 Command、0 个已完成 Sink 写入。关闭后等待数为 0，丢弃数为
1999；最后释放测试 Sink Future，在途数回到 0。历史容量不改变业务执行数量。

## 性能验证与边界

使用 `packages/ccrouter_test/benchmark/diagnostic_delivery.dart` 对同一工作负载
比较修改前 Core 与当前 Core。基线来自修改前 Git 版本的 Core 文件，位于临时目录；
通过单独的 package config 把两份 Core 编译进同一个 AOT 可执行文件，不替换工作区
文件，不给生产路径增加旧实现开关。两侧使用同一份 Contracts 和相同的动态 Runtime
调用路径；单进程交替每 64 次 Command 的小批次，并反转每批顺序，减少调度和 CPU
频率变化造成的偏差。同步 Sink、立即完成的异步 Sink、无 Sink 分别执行；每样本
10000 次 Command，预热两轮后每种配置记录 49 轮，并校验有 Sink 时全部事件交付。
命令耗时排除让出时间，完整投递耗时包含让出时间与 Sink 完成回调。记录 wall time
及 POSIX mutator thread CPU time；线程 CPU 不含其他线程与 GC 暂停，不能解释为帧时间。
保留原始样本，不设置机器相关 CI 阈值。

独立进程以及按长批次交替的早期实验存在明显波动（无 Sink 对照也曾相差约 10%），
均保留在 JSON 中，不把那些样本当成性能收益。最终采用相邻小批次的同进程对照。
可复现脚本为 `packages/ccrouter_test/benchmark/compare_diagnostic_delivery.py`，
`--reference` 使用下方 JSON 中记录的完整基线 SHA，`--output` 写到临时结果文件。
脚本读取 Git 基线源码和现有 Workspace package config，保留临时编译文件供检查。

性能数据与最终检查结果在下方记录。这里的主机微基准不代表手机帧时间，也不证明
真实网络 Sink 的吞吐不变。串行写入的服务速率受 Sink 延迟限制，持续过载时更多
丢弃是保持有界的明确代价；生产通过计数、采样与 Sink 实际能力调优，不能靠加大队列
解决持续吞吐不足。异步分发仍在调用 isolate，耗时同步 Logger 需要 Host 处理。

### 最终同进程 A/B 结果

| Sink 模式 | Command CPU：旧 → 新（µs/条） | 完整投递 CPU：旧 → 新（µs/条） | 完整投递 wall：旧 → 新（µs/条） |
| --- | ---: | ---: | ---: |
| 无 Sink | 1.702 → 1.696 | 1.780 → 1.774 | 1.854 → 1.892 |
| 同步 Sink | 1.634 → 1.656 | 1.756 → 1.766 | 1.871 → 1.879 |
| 立即完成 Future | 1.737 → 1.736 | 1.942 → 1.966 | 2.078 → 2.058 |

Core 构造失败清理阶段的最终复测，与最初无背压 Core 基线相比，Future 完整投递 CPU
增加约 0.025 µs/条（1.3%），wall 中位数约 −1.0%；不能将该路径表述为确定的
零开销。同步和无 Sink 的完整投递 CPU 分别约 +0.6%/−0.3%。此前 Future CPU
曾测得 +2.8%，保存在 `earlierExperiments.beforeConstructionFailureFix`；更早的
主结果保存在 `earlierExperiments.sameProcessBeforeReviewFix`，不删除或挑选样本。

Zone/批次修复阶段为区分该修复与原背压改造，用当时相同的 Core，仅把
`diagnostic_delivery.dart` 恢复到 review 前源码，执行同进程 AOT 对照（历史阶段证据）：

| Sink 模式 | 完整投递 CPU：review 前 → 后（µs/条） | 完整投递 wall：review 前 → 后（µs/条） |
| --- | ---: | ---: |
| 无 Sink | 1.438 → 1.416 | 1.460 → 1.458 |
| 同步 Sink | 1.473 → 1.462 | 1.490 → 1.489 |
| 立即完成 Future | 1.577 → 1.573 | 1.597 → 1.602 |

该阶段直接对照中，两个 review 修复没有表现出明显新增开销；Future wall 约 +0.3%，
CPU 约 −0.3%，同步完整投递 CPU 约 −0.7%。不同轮次绝对耗时差异明显，只能比较
各自同进程配对，不能跨表推导加速。`reviewFixComparison` 保存全部样本、review 前
投递器源码及前后源码 SHA-256。此表对应上一轮的源码状态，不声称当前构造清理已
包含在该历史阶段对照中。

构造失败清理阶段另用当时的 Core，仅把 `runtime_host.dart` 与 `diagnostic_delivery.dart` 恢复到
构造失败修复前，执行同进程 AOT 对照：

| Sink 模式 | 完整投递 CPU：修复前 → 后（µs/条） | 完整投递 wall：修复前 → 后（µs/条） |
| --- | ---: | ---: |
| 无 Sink | 1.857 → 1.859 | 1.977 → 2.006 |
| 同步 Sink | 1.851 → 1.871 | 2.016 → 2.039 |
| 立即完成 Future | 1.923 → 1.959 | 2.074 → 2.122 |

该阶段 Future 完整投递 CPU 中位数约 +1.8%（0.035 µs/条），wall 约 +2.3%；同步
CPU 约 +1.1%，无 Sink 约 +0.1%。按同轮配对计算的完整投递 CPU 差异中位数分别
约 +0.2%/−0.0%/+0.8%，说明中位数比值并不能代替配对样本判断。该阶段未出现明显
量级回退，但这些结果不能证明严格的零开销，也不能跨轮推导加速。正常事件投递
本身没有新增分支、Timer 或 Future，构造成功只有异常保护，终止清理只在失败时启动。

`constructionFailureFixComparison` 保存该阶段全部样本，以及修复前两个文件的完整源码
和前后 SHA-256。复制当前 Core 的 `lib/` 并用所存源码替换这两个文件，即可重建
临时基线；用 runner 的 `--reference-core <临时 Core 目录>` 替代 `--reference`
复现，不会切换或覆盖工作区源码。

正常 Sink 的全部事件均交付；慢/永久阻塞 Sink 的过载丢弃是明确行为变化。原业务
设备帧耗时仍需接入后验证，不能从主机基准推导“真机绝无回退”。

完整当前及早期原始样本、基线 SHA、容量探针见
[机器可读验证结果](diagnostic-sink-backpressure-20261019.json)。复现命令：

```sh
python3 packages/ccrouter_test/benchmark/compare_diagnostic_delivery.py \
  --reference BASELINE_COMMIT --output /tmp/ccrouter-sink-comparison.json
```

其中 `BASELINE_COMMIT` 为 JSON 的 `referenceCommit`，本次为 `283b00b37ed71c13acea9d22691b6988d75fb60b`。

## 最终检查

以下为实现修复与最后一次 review 的执行快照；本次文档收口的检查单独记录。

- `fvm flutter test --no-pub --concurrency=1 packages/ccrouter_test/test --reporter expanded`：565 项通过。
- 在 `demo/` 执行 `fvm flutter test --no-pub --reporter expanded`：61 项通过。
- `fvm dart analyze`、在 `demo/` 执行 `fvm flutter analyze --no-pub`：均无问题。
- Host 实现修复时，生产文件与新增测试的 format 校验：通过。
- `git diff --check`：通过。

诊断与 Host 专项共 68 项，组成是背压 25、原诊断 8、构造失败 19、Host 回滚与跨 Zone 16
（初版 10 + 跨 Zone 6）。最后一次 review 同时复跑取消与 UI 绑定清理，6 个仓库测试文件
合计 88 项通过；这些都是 565 项全量套件的子集，不能累加为新的全量数字。

另外 2 个临时 review 探针通过：旧 shutdown 不清除新一轮门禁；Runtime 取消异常会在异步
Service 释放完成后通知跨 Zone 等待者。它们未纳入仓库持久测试套件，也不计入 565 项。
JSON 的 `validation.reviewClosure` 保存其源码、SHA-256 和复现命令，以及 88 项 review 的文件列表。

Host 回滚初版的首次默认并发全量运行 558 项通过、1 项失败：既有
`caller timeout does not poison shared Service readiness` 用例的 10ms 超时在 initializer
执行前发生，随后测试读取尚未赋值的 `initializerContext`，报 LateInitializationError。
同一用例单独复跑通过；保持该用例不变，当时完整套件串行复跑 559 项全部通过。
后续加入跨 Zone 的 6 项用例，最终完整串行运行 565 项通过。
记录此次时序波动，不把首次运行报告为成功，也不通过扩大超时掩盖结果。

文档收口检查：`fvm dart run tool/documentation_check.dart`（112 份已跟踪 Markdown）与
`fvm dart run tool/release_sensitivity_check.dart` 均通过。另对本次 5 份 Markdown 的
115 个本地链接补查，覆盖尚未跟踪的验证报告；JSON 测试总数、实现源码 SHA-256 和
归档探针 SHA-256 均匹配，`git diff --check` 通过。本次仅调整文档及验证记录，未重跑
框架/Demo 套件，也未把前轮测试结果记作本次重新执行。

本次不涉及生成器或 Analyzer Plugin 生产代码，没有修改 Demo Pin、生成产物或运行期
全局默认容量。根 README、集成 Skill、接入参考与 API 注释已同步交付语义。
未提交或推送；保留工作区内其他任务的既有修改。原业务设备尚未验收。
