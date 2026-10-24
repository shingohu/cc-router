# Android Native 分配归因（2026-10-24）

承接[遗留项收口](../20261024-closure/report.md)。本轮仅增加验收工具与证据，
不修改框架或 Demo 的生产实现，不将 PSS 上涨直接认定为 CCRouter 泄漏。
源码为 `7d9b51211ddae3e55349c64773ec7d4e2675e391` 加此前未提交工作树。

## 已核实的符号来源

- 同一 Profile APK SHA-256：
  `a3416242f0d745158b39d7f8e24d5404ebf33e298d04b3d7bd2397748a414851`。
- SDK Engine revision：`42d3d75a56efe1a2e9902f52dc8006099c45d937`。
- APK 内剥离后的 arm64 `libflutter.so`、Gradle 缓存内同版本未剥离 ELF、
  已有 Perfetto mapping 的 GNU Build ID 均为：
  `029a0f63d413a17beda1b7c51096f6796a37607e`。
- 缓存 ELF 包含 `.symtab`、`.debug_info` 和 `.debug_line`，可直接解析 C++ 函数、
  inline 调用与源码行号。无需下载符号或重编引擎；不同剥离状态的文件 SHA 不要求相同。
- [离线符号化工具](symbolize.mjs)在 Build ID 不符时拒绝输出；本轮使用 NDK 28.2
  LLVM 与 Perfetto Trace Processor v58.2。不把符号文件作为仓库分发材料。

## 已有 trace 的新增结论

- 健康短 trace 的 85 个 Flutter frame 全部解析成功。该短窗口的约 **4 MiB**
  保留分配沿 `dart::TextBuffer::EnsureCapacity` → `JSONWriter` →
  `ClassTable::AllocationProfilePrintJSON` → `GetAllocationProfileImpl`，属于 VM
  响应采样工具 `getAllocationProfile` 请求的路径；不是页面 Owner 泄漏的证明。
  见[完整调用栈](existing/native-low-overhead.perfetto-trace.symbolized.json)。
- 已损坏随机 trace 的 738 个 Flutter frame 同样可解析，但仍有
  `heapprofd_buffer_overran=1`、`heapprofd_client_error=1`，且只有一个 dump。
  [符号化结果](existing/native-random.perfetto-trace.symbolized.json)只用于查看调用路径，
  不恢复丢失事件、不作为增长趋势证据。
- 不能用短窗口的 4 MiB 解释此前约 90 MiB native PSS 增长。

## 已完成的对照与采样范围

[设备脚本](run-device.mjs)使用华为 OCE-AN10 / Android 12 / arm64，显式指定设备，
每轮独立重启 Demo，随后轮内保持 PID/Activity；诊断轮另核对 main isolate。
重启仅建立独立对照基线，不作为上一进程释放内存的证据。

两轮均使用相同 APK、相同 native 采样参数与相同 Monkey 参数：seed 20261024、
throttle 200ms、5 分钟；禁用 app-switch/syskeys，返回可见首页后观察 60 秒。
相同 seed 不保证 Flutter 异步 UI 处于完全相同状态，不据此计算严格性能提升比例。

| 配置 | baseline | diagnostic |
| --- | --- | --- |
| CPU profiler 启动请求 | 关闭 | 开启 |
| VM Service 客户端 / Timeline / 帧流 | 不连接、不主动启用 | 连接、Dart/Embedder/GC、监听帧流 |
| CCRouter 快照轮询 | 无 | 每 30 秒 |
| getAllocationProfile / 主动 GC | 无 | 无 |
| DevTools endpoint 编译注册 | 保持开启 | 保持开启 |
| native heapprofd | 256 KiB 间隔、16 MiB shared memory、非阻塞 | 相同 |

本轮不是“编译移除 DevTools”的对照，也不是无 profiler 的帧基准；baseline 不订阅帧流。
native trace 在启动应用前建立，覆盖启动、负载、归位与空闲，结束后才拉取文件。
每个检查点保存 meminfo、smaps、CPU、温控与 Activity，避免全量类分配采样的观察者开销。
必须检查最终 trace 的丢失/错误、dump 时间与完整覆盖后，才能写入结论。

两轮的 APK SHA 均与上方一致。baseline 为北京时间 **16:48:46—16:55:16**，
PID 26821、Activity `7bfa0c0`；diagnostic 为 **16:56:22—17:02:53**，
PID 29732、Activity `d0700c8`，main isolate `isolates/1390570932008295`。
各轮的进程/Activity 始终不变；诊断轮 main isolate 也不变。正常导航允许根 Entry 被 Go
替换，不把根 identity 不变错误地当作随机负载成立条件。

第二轮首次启动因前轮 heapprofd 仍在退休而 fail-closed，未执行负载或重启应用，记录在
[失败事件](diagnostic/events.ndjson)。确认退出后重试到独立目录，未覆盖失败材料。

| 指标 | baseline | diagnostic |
| --- | --- | --- |
| 20s 基线 → 返回首页空闲 60s PSS | 97.02 → 250.32 MiB | 96.93 → 239.57 MiB |
| 同口径 native heap PSS | 30.13 → 133.07 MiB | 30.18 → 113.40 MiB |
| 同口径 native malloc 已分配 | 38.36 → 145.67 MiB | 39.08 → 124.54 MiB |
| 末点 malloc 空闲容量 | 7.66 MiB | 12.52 MiB |
| trace dump 数 / 已解析 Flutter frame 数 | 23 / 1,219，未解析 0 | 24 / 1,155，未解析 0 |
| 最终采样估计保留 malloc | 121.39 MiB | 93.89 MiB |
| 其中经过字体处理路径 | 91.50 MiB | 66.75 MiB |
| 其中经过 `ft_var_load_gvar` | 60.00 MiB | 41.50 MiB |
| crash / ANR / 未处理 Flutter 异常 | 未观察到 | 未观察到 |

字体与 gvar 两行有包含关系，不能相加。采样保留 malloc 包含启动阶段，PSS 则包括不同
类型的驻留页，二者不能一一相减或相互替代。各 trace 没有非零 data_loss/error；末次
allocation dump 的设备 BOOTTIME 覆盖到对应最后 idle meminfo 之后。完整趋势、调用链与
smaps 映射分别见[汇总](analysis.json)、[baseline](baseline/native.perfetto-trace.symbolized.json)、
[diagnostic](diagnostic-retry/native.perfetto-trace.symbolized.json)。

两轮至少均执行到 Monkey 第 4,800 个周期事件，throttle 200ms 不等于每秒五个底层
输入事件；触摸序列含多个事件。本轮禁用系统跳转，不能替代最早 30 分钟的负载范围。
温控状态全程为 1。诊断轮 7,883 帧：build P95 **4.327ms**、最大 **87.079ms**；
raster P95 **8.021ms**、最大 **28.329ms**，没有复现原 1.16s 长帧。

### 已能区分的开销与限制

- 两轮在约第 130 秒都初始化 Huawei WebView。其 APK 代码页、partition allocator 等
  有单独 smaps 增长，不能都算到 Flutter 页面或 CCRouter。网络行为和输入异步执行仍使
  两轮页面序列不同；第二轮最终的较低 PSS **不是**诊断开关改善内存的因果证据。
- 诊断轮 `[anon:dart-profiler]` PSS 从 84KiB 增至 12,640KiB；基线未连接客户端也有
  引擎默认 Timeline 页增长。因此“未主动启用 Timeline”不等于它的所有内部缓冲均不存在。
  该对照没有关闭编译注册的 DevTools endpoint，也没有关闭应用自己的有界诊断和日志。
- baseline 不采集 Dart 类分配表或 main isolate ID，以避免该采样本身产生的 JSON 开销。
  它的同 PID/Activity 不是对所有内部 isolate 生命周期的完整证明。诊断轮返回首页后
  快照只剩一个 home Entry；没有用正常栈数量替代 native 内存证明。
- heapprofd 是非阻塞采样，但并非零开销：两个随机轮累计 unwind CPU 时间分别约
  **228.21s / 247.52s**，是跨样本累计值。不能把本轮帧耗时解释为无采样的性能基准。
  malloc 采样也不覆盖所有直接 mmap、GPU、驱动与其它进程分配。

## 纯 Flutter 最小复现：不需要 CCRouter 也会增长

新增独立[字体复现入口](../../../demo/tool/native_font_probe.dart)，只导入 Flutter，
不初始化 Runtime、Backend、Managed Stack、DevTools、WebView 或业务日志。
它使用一个页面和有限的 72 种字体组合（4 个 family 选择 × 9 个 weight × 2 个 style），
以 400ms 间隔循环三轮，同一中文/英文内容重复渲染，随后停留，不执行任何导航。
计数标签用于确认进度；本轮不是与真实 Demo 完全同工作量的性能比较。

从 `demo/` 构建：

```sh
fvm flutter build apk --profile --no-pub --target-platform android-arm64 -t tool/native_font_probe.dart
```

初始曾放在根 `tool/fixtures`，专项分析报告其所在 Package 没有 Flutter 直接依赖；
迁到 Demo 的 `tool/` 后重新分析无问题、重建成功，见[最终构建](font-probe-build-final.log)。
首次构建日志保留，不把有 lint 提示的试探位置当作最终通过。复现 APK SHA-256：
`f43f9506046d4580f959fe970be62ec41373f9b6d92627a39c249938caa20194`。

[执行脚本](run-font-probe.mjs)显式检查原 Demo APK SHA 后保存还原路径；不连接 VM 客户端、
不启用 CPU profiler。PID **32533** 在样例、空闲和压力通知期间不变。北京时间
**17:03:47—17:06:49**，包含约 86 秒字体切换、完成后约 60 秒空闲，再发送一次
`am send-trim-memory dev.ccrouter.demo RUNNING_CRITICAL` 并观察 20 秒。
日志确认三轮与完成标记均到达，未观察到 crash/ANR/未处理 Flutter 异常。

| 时点 | PSS | native heap PSS | native malloc 已分配 |
| --- | --- | --- | --- |
| 渲染中文前，12s | 88.34 MiB | 30.32 MiB | 29.58 MiB |
| 35s | 136.12 MiB | 71.80 MiB | 80.02 MiB |
| 65s | 179.80 MiB | 115.31 MiB | 125.72 MiB |
| 100s，临近第三轮结束 | 224.46 MiB | 159.26 MiB | 169.99 MiB |
| 165s，空闲约 60s | 224.29 MiB | 159.61 MiB | 170.44 MiB |
| 压力通知前 | 224.55 MiB | 159.61 MiB | 170.35 MiB |
| 压力通知后 20s | 224.72 MiB | 159.64 MiB | 170.42 MiB |

该 trace 共 14 个有 allocation delta 的 dump，678 个 Flutter frame 全部解析，
无报告数据丢失或错误。末点估计保留 malloc **137.57 MiB**，其中 **123.75 MiB**
经过字体路径、**36.75 MiB** 经过 `ft_var_load_gvar`。三轮期间仍在增长；停止渲染后
趋于平稳，但压力通知未使这些采样保留分配明显下降。见
[完整符号化结果](font-probe/native.perfetto-trace.symbolized.json)与[事件](font-probe/events.ndjson)。

这证明主要字体增长可在没有 CCRouter 的情况下复现，**不证明**所有原 Demo 内存均来自
字体、不证明现象必然无限增长，也不等于框架所有生命周期均无泄漏。尚不能把它定义为
已验证可回收的普通预热缓存。没有以“页面栈正常”关闭问题，也没有用周期性 GC、强制
清缓存或替换业务字体掩盖曲线。

## 结论与剩余工作

“精确匹配 Engine 符号 + 覆盖增长全过程的无报告丢失采样 + 诊断开销对照 + 最小复现”
已补齐。主要新增证据指向 **当前华为系统字体与 Flutter/Skia/FreeType 的文本路径**，
没有足够依据修改 CCRouter Core 来处理这批分配。

下一步优先在同设备、同字体样例上比较官方 Flutter SDK，再沿 TypeFace/FontCollection/
Paragraph 的持有与淘汰路径追踪当前引擎；如能证明具体泄漏，修复对应引擎资源 Owner，
而非给导航增加清字体缓存的副作用。SDK 对照需要独立 APK/符号，不能拿新引擎的符号解析
本轮 APK。本轮没有升级 SDK、修改引擎、联系上游或宣称完成修复。
原 1.16s 长帧仍未复现，继续保持开放。未重做 iOS、macOS 或系统预测返回验收。

结束后已重新安装并启动原 Demo，未清应用数据；本地默认 `app-profile.apk` 也恢复到原 SHA。
临时保存的原 APK 与复现 APK 保留在仓库外，未删除；设备测试进程和捕获进程已结束。
此前生产四目录差异摘要仍是
`2caea8aea93309a7d8d9cfe362183024b3fcc666759d313215ddd391c9bc2677`，
本轮不修改框架实现、正常 Demo 页面或生成输出。

## 最终验证

- 根目录 `fvm dart analyze` 无问题，见[日志](analyze.log)；字体入口专项分析无问题，
  `dart format` 为 0 changed，最终 Profile 构建成功。
- 四个新增 Node 脚本语法检查通过，三个新 trace 与两个历史 trace 均经过实际离线解析；
  另以不同 Engine revision 的 ELF 验证 Build ID 不符时拒绝输出。
- Markdown 180 文件检查、tracked 与 `--include-untracked` 敏感信息门禁均通过，
  见[文档](documentation.log)、[tracked](sensitivity-tracked.log)、[全工作树](sensitivity.log)。
  本轮一份失败事件含本机路径，先备份到仓库外 `ccrouter-evidence-originals-zlbKXX`
  后归一化；复查为 0，原件保留。
- `git diff --check` 通过。未改框架生产代码，未重复运行此前的框架、Generator、
  独立 Plugin 或 Demo 全量 suite；不把历史测试数累加到本轮。
- 未提交或推送，发布 Native 内存/长帧项仍保持开放。
