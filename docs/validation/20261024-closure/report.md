# 遗留项收口（2026-10-24）

后续[Native 分配归因](../20261024-native-attribution/report.md)已找到并验证匹配的引擎符号，
补充全程采样与纯 Flutter 对照；本报告保留当轮诊断进度与原始未关闭项。

本轮承接[核心价值回归](../20261024-core-value-final/report.md)与
[华为 Monkey](../20261024-huawei-monkey-30m/report.md)的遗留项。
源码基线为 `7d9b51211ddae3e55349c64773ec7d4e2675e391` 加当前工作树；未改动框架实现，
未升级 Plugin 或修改 pin。本轮修复 Demo 和证据流程，性能仍有开放项。
生产差异摘要（与上轮相同四个生产目录的 `git diff | shasum -a 256`）：
`2caea8aea93309a7d8d9cfe362183024b3fcc666759d313215ddd391c9bc2677`。

## 已修复与根因

- MaterialApp 中显式 Cupertino Route 仅选择转场。Demo 的 CupertinoPageScaffold 正文
  没有文本样式，落到 Flutter 错误默认值。修复前新增 320×568 Widget 回归观察到字号
  **48**，预期 **17**；同时发现首页标题向右溢出 **66 px**。正文补 Cupertino
  DefaultTextStyle，标题采用 Flexible/ellipsis 后同一回归通过。
- 详情页删除 GoRouterState 遗留说明，改为生成 Codec 与类型安全构造参数。
- Profile 构建发现缺 CupertinoIcons 字体资源；在 Demo 组件补 cupertino_icons 依赖，
  实际解析 1.0.9。重新构建确认 CupertinoIcons.ttf 进入资源并完成 tree-shaking。
- 原敏感信息门禁命中的 147 个 tracked 文件和 3 个未追踪验收文件完成机械路径归一化。
  原件先备份到仓库外临时目录 `ccrouter-evidence-originals-RRYYks`，本轮保留，不提交。
  历史失败、测试数字、时间、错误位置行号与指标均未改写。工具默认只检查，`--write`
  先备份再归一化；包含未追踪证据、保留 CRLF、跳过二进制且不修改验收目录外文件。
  独立门禁保留原规则，另提供 `--include-untracked` 用于提交前扫描。
  4 份旧 Flutter 日志的 whitespace comparator 测试名嵌有 CR；路径替换后触发
  `git diff --check`，将这些行的 CR 显示为文字 `\r`，保留 LF、行号和原件，不删除测试信息。

## 验证

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Demo 全量 Widget，`demo/` 执行 `fvm flutter test --no-pub --reporter expanded` | 114 项通过，包含新增小屏/Cupertino 样式回归 | [日志](demo.log) |
| 仓库工具，根目录 `fvm dart test tool/test --reporter expanded` | 52 项通过，包含未追踪证据扫描，及真实 Skill 示例编译 | [日志](tools.log) |
| 可逆脱敏工具，`node --test tool/test/sanitize_validation_evidence_test.mjs` | 1 项通过；验证原件、未追踪文件、CRLF、二进制、幂等和符号链接越界拒绝 | [日志](evidence-tool-test.log) |
| 根目录 `fvm dart analyze` | 无问题 | [日志](analyze.log) |
| Demo `generate demo --no-cache --check` | 6 组件、34 Route、11 Packages 一致 | [日志](generation.log) |
| Android arm64 Profile 构建 | 成功，CupertinoIcons 字体资源已打包；真机使用同一 APK SHA-256 | [构建日志](profile-build.log)、[设备配置](controlled-config.json) |
| 隔离双 Skill 与真实 CLI 命令检查 | 通过 | [日志](skill-check.log) |

初次生成检查发现源位置/指纹相关的 8 个 managed 文件过期；通过正式生成更新后，上述
无缓存检查通过。未手改 generated 文件。命令复用短暂退出的 watch 时曾 fail-closed，
待确认 watch inactive 后重跑成功；不记作首次全绿。
本轮没有重跑框架、Generator 和独立 Plugin 全量；其上轮结果仍按原报告的源码范围解释。
本轮框架实现与 Plugin production 均未修改。所有最终门禁结果另见本报告末尾。

## 华为受控复测口径

使用同一华为 OCE-AN10，Android 12 / API 31。Profile APK 显式启用
`CCROUTER_DEVTOOLS=true` 只读端点，启动 extra `enable-dart-profiling=true`。
首轮准备遗漏 Profile 的 DevTools opt-in，端点返回 Method not found；未执行导航负载，
保留在事件文件中。修正后 CPU probe 有真实 samples，Timeline 使用 Dart/Embedder/GC。

通过 UI 真实按钮分别执行 120 次 typed-detail 和 120 次 Cupertino 打开/返回；每次断言
Managed Entry 增加一个、返回后根 Entry identity 不变，每 20 次记录 PID/isolate、Activity、
自然/GC 后 Dart heap、PSS、CPU 和温控，结束后同引擎空闲 30/60 秒再次记录。
存在任何进程/isolate/根 Entry 变化则停止并判为无效对照；不重启来制造内存回落。
本轮每个检查点显式 GC，且启用 profiler/Timeline/DevTools，不能与旧 Monkey 直接比较耗时或 PSS。
Android 12 不覆盖 Predictive Back，固定场景也不等于全功能 Monkey 或原生 heap retaining path。

## 真机结果与未关闭项

固定场景：北京时间 **16:08:07—16:15:01**，两个场景共 **240** 次打开/系统返回，
每次 Entry 增减与根 identity 检查通过。PID 18579、main isolate、ActivityRecord 始终一致。
共 **13,960** 帧，build P95 **3.146ms**、最大 **77.392ms**；raster P95 **7.226ms**、
最大 **28.700ms**。正文及返回图标的真机截图见 [Cupertino](cupertino-opened.png)，
文案见[详情页](typed-detail-opened.png)。

随后启动**独立**随机诊断轮，未将新引擎基线的回落计为前一轮释放证明。其 PID 22808、
main isolate、VM-service isolate、ActivityRecord 在该轮内始终一致。
北京时间 **16:18:40—16:23:41**，计时目标 300 秒，记录的 301.123 秒包括末次采样；
throttle 200ms、seed 20261024、至少 4,800 个周期事件，未观察到 crash、ANR、OOM、
Flutter 未处理异常。为保持同一引擎，关闭 app-switch/syskeys，参数见
[配置](random5m/controlled-config.json)与[Monkey 参数](random5m/monkey-args.json)。
不能将其视为原 30 分钟相同负载的重放。温控从 1 升至 2，仍是测量限制。

| 指标 | 固定场景 | 随机场景 |
| --- | --- | --- |
| PSS 基线 → 导航结束 → 同引擎空闲 60s | 148.03 → 192.17 → 199.02 MiB | 131.24 → 248.04 → 251.16 MiB |
| GC 后 main heap 基线 → 空闲 60s | 12.62 → 13.43 MiB | 12.62 → 16.38 MiB |
| native heap PSS 基线 → 空闲 60s | 82.09 → 97.67 MiB | 66.85 → 156.63 MiB |
| 导航结束保留页面数 | 1 | 2（随机负载结束时的实际栈） |

完整逐点数字、帧与 110ms 栈分析见[机器汇总](analysis.json)，原始采样在
[固定](samples/)和[随机](random5m/samples/)目录。没有以正常页面栈替代进程内存验收。

### 长帧：有了新证据，原 1.16 秒问题仍未复现

随机轮 **7,432** 帧，build P95 **4.763ms**、最大 **110.235ms**，仅 1 帧超过 100ms；
raster P95 **8.347ms**、最大 **29.527ms**。
该帧已捕获 [Timeline](random5m/samples/slow-4692-timeline.json) **399** 事件及
[CPU profile](random5m/samples/slow-4692-cpu.json) **109** 个样本。
Timeline 中 root LAYOUT **93.790ms**、BUILD **8.853ms**；CPU 可见 Flutter
Viewport/SliverList/Flex 布局，raster 有 **14.275ms** 字形图集创建。
这只能定位本次 110ms 窗口的活动，不能据此解释原 1162.584ms 长帧或归因给 CCRouter。

### 内存：增长再次出现，尚未证明框架泄漏或完成修复

- 随机末点 GC 后 `CCScope=3`、`_RouteEntryRecord=2`、Managed content State=2、
  NavigatorState=1，与两个活页面相符；保留的 RouteEntrySnapshot=670 属于有界诊断快照。
  此类数量只能排除本次明显的逐页对象堆积，不能证明所有 retaining path 都清洁。
- VM-service isolate heap 约 2～4 MiB，external 约 29～32 MiB；主 isolate 单独的
  heap 数字不能代表整个进程。smaps 显示 libc_malloc、匿名页、profiler 和 Timeline
  均占用内存，不能把全部增长自动解释为 Dart 页面或 VM-service。
- 已用 Perfetto heapprofd 尝试 native 分配栈：初次 8KiB 采样触发 buffer overrun/client
  error，见[原始诊断](native-first-analysis.log)。该 trace 提前截断，**不用于趋势结论**。
  后续 256KiB、90 秒低开销捕获未报告 overrun/client error，见
  [分析](native-low-overhead-analysis.log)和[trace](native-low-overhead.perfetto-trace)。
  仅观察到该短窗口约 4MiB 新保留分配，栈含 libflutter.so 原生偏移；它既不覆盖增长
  全程，也缺匹配引擎符号，不能据此定位未释放的 CCRouter Owner。
- 随机与空闲轮结束后，针对同一进程发送 `am send-trim-memory dev.ccrouter.demo RUNNING_CRITICAL`。
  [前](random5m/memory-before-trim.txt)/[后](random5m/memory-after-trim.txt)的 native malloc
  已分配量从 171,087KiB 降至 134,170KiB，约 **36.05MiB** 被释放；PSS 只回落约
  3.37MiB，native heap free 增加。说明部分分配可响应内存压力，但不证明剩余增长是
  缓存，也不证明原生分配器将已释放页归还操作系统。未清理数据、重启或强制修改引擎。

后续应以匹配当前 OHOS Flutter SDK 的引擎符号，取得覆盖实际增长窗口且无丢失的
native 分配/释放栈，再区分引擎缓存、分配器保留和真实未释放对象。保持本问题开放；
当前没有足够证据支持修改 CCRouter Core，也不能声称“无泄漏”或性能全面优于旧架构。
macOS 实窗、iOS/Android 系统手势与 Hosted 发布验收未在本轮重做。

## 最终门禁

原 tracked 敏感信息门禁和新增 `--include-untracked` 扫描均通过；路径归一化检查为 0，
Markdown 179 文件通过，6 个本轮 Dart 文件格式为 0 changed，`git diff --check` 通过。
新增证据中的 5 个含路径文件另先备份到仓库外 `ccrouter-evidence-originals-G17sbd` 后归一化。
两份原件目录均保留，未清理历史、删除证据、提交或推送。
