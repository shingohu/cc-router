# 华为 Android 真机 30 分钟 Monkey（2026-10-24）

已在华为真机完成连续 30 分钟原生 Monkey。未观察到进程退出、crash、ANR、OOM 或 Flutter
未处理异常；发现明确的 Demo Cupertino 正文样式问题、遗留文案，以及待定位的长帧与
Native/Graphics 内存增长。性能数据包含系统录屏和温控负载，内存验收仍有待定位项。

后续修复与受控复测见[遗留项收口](../20261024-closure/report.md)。本报告保留原始结果；
路径文本后经统一归一化，原件已备份，测试事实和指标未改写。

## 最终结果

北京时间 **12:28:28.966—12:58:29.017**；截止计时为 **1800.016 秒**。
之后约 67 秒用于退出页面、Activity 重建、空闲/GC 采样与记录清理，不计入 Monkey 时长。

| 项目 | 结果与口径 |
| --- | --- |
| 事件 | 最后一个 Monkey 周期计数至少 26600；日志含 26693 条 Touch/Key/Switch 发送记录、8442 次 200ms throttle |
| 进程 | PID 24424 从基线到结束保持不变；计时内有一次正常 Activity/isolate 重建 |
| 错误 | Monkey、选定 logcat、应用 crash buffer、应用 exit-info 均未发现本轮 crash/ANR/OOM；Flutter 未处理异常记录为 0 |
| 内存采样 | 1 个基线、60 个计时点、2 个后置点；每点有原始内存分项 |
| PSS | 基线 **111.36 MiB**；第 30 分钟及采样峰值 **348.13 MiB**；重建后 30 秒 **135.38 MiB**，重建/GC 后末点 **139.87 MiB** |
| Dart 堆 | 计时内 55 个独立样本，**13.87～24.19 MiB**；新 isolate 的末次 GC 后 **12.58 MiB** |
| CPU | 55 个 1 秒窗口样本，均值 **17.1%**、P95 **60%**、峰值 **66%**，100% 为一个核心；这是稀疏采样均值 |
| 温度 | 电池温度 **35～40°C**；初始 Thermal Status 1，后续至少达到 3 |
| Flutter 帧 | 以接收时间限定计时窗口，**30772 帧**；截止时录制器累计计数 30773，边界批量投递产生 1 帧差异 |
| build | P50 **1.139ms** / P95 **3.704ms** / P99 **12.936ms** / 最大 **1162.584ms** |
| raster | P50 **5.118ms** / P95 **11.711ms** / P99 **15.663ms** / 最大 **77.580ms** |
| 超预算帧 | build 或 raster 超过 16.667ms：**386 / 30772，1.25%**；超过 33.333ms：**55，0.18%** |

超预算是 Flutter 单阶段阈值统计，不是系统端到端丢帧率。计时前后不重启进程、不清理应用数据；
后置 Back 操作结束了原 Activity/isolate 并新建引擎，因此最后的内存回落不能作为同一 Runtime
中 Route 资源释放干净的证明。新引擎的 Native Heap PSS 约 36 MiB，显著低于计时末约
168 MiB；大部分增长可随引擎重建回收，同引擎长期导航的保留问题仍需进一步区分。

系统录屏开始前的 13893 帧：build P95 **3.532ms**，raster P95 **9.882ms**；
开始后的 16879 帧：build P95 **3.908ms**，raster P95 **12.391ms**。
场景和温控同时发生变化，这个分段描述不构成录屏导致差异的因果证明。
原生 gfxinfo 另报告 924 帧、5 个 deadline jank（0.54%）；Flutter SurfaceView 的取样范围不同，
该数值仅作[辅助证据](gfxinfo-after.txt)，不代替 Flutter.Frame 统计。

## 设备、源码和方法

- 设备：HUAWEI OCE-AN10，Android 12 / API 31，arm64-v8a，1080 × 2376，density 480。
  当时显示模式为约 60Hz；设备支持 90Hz，本轮没有更改显示设置。
- 应用：`dev.ccrouter.demo` 0.1.0，minSdk 24 / targetSdk 36，Flutter Profile APK。
- 源码：`7d9b51211ddae3e55349c64773ec7d4e2675e391`；APK SHA-256 与全部参数见
  [run-config.json](run-config.json)，包信息见[package.txt](package.txt)。
- 构建：从 `demo/` 执行
  `fvm flutter build apk --profile --target-platform android-arm64 --no-pub`，生成检查通过，
  Profile 构建成功后定向安装到华为设备。其它连接设备未参与。
- seed `20261024`，throttle 200ms；touch 45%、motion 20%、pinchzoom 5%、major navigation
  20%、directional navigation 5%、app switch 5%。权限、任意事件、设备 flip、syskey 均为 0。
  仅允许 Demo 包启动；触摸仍可能到达系统状态栏。完整命令见[monkey-command.txt](monkey-command.txt)。
- 计时采用主机单调时钟，计划 1800 秒；命令设足够大的事件上限，由截止计时终止本次 Monkey。
  throttle 是 Monkey 插入的等待，不等于每秒固定 5 个底层 MotionEvent；手势可含多个事件。
- 保留 crash/ANR/native crash 记录并继续压力运行；最终结合进程、退出原因和日志判定，
  不以 `--ignore-crashes` 后进程存活代替错误检查。
- 每 30 秒记录 PSS/RSS、内存分项、PID、前台 Activity、电池温度和 gfxinfo；另每约 31.5 秒
  获取 Dart `getMemoryUsage` 与两次 `top` 中第二个 1 秒窗口。CPU 100% 表示一个核心。
- 通过现有 VM Extension stream 采集 `Flutter.Frame` build/raster/total span，无业务代码插桩。
  统计使用实际采到的帧，空闲时不强制刷新；Flutter 帧预算按 60Hz 的 16.667ms 比较。

原始驱动见[run.mjs](run.mjs)、[堆/CPU 补充采样](heap-sampler.mjs)、
[长帧捕获](slow-frames.mjs)和[统计脚本](analyze.mjs)。运行中的首版驱动从 `getIsolate` 读取
内存字段，但该 RPC 实际不提供该字段，因此从第 87 秒起用补充采样器读取 `getMemoryUsage`。
首版缺失数据保留，未补造前 87 秒的连续 Dart 堆数据；驱动源码已更正供后续复用。

## 已发现问题与定位边界

### P2：显式 Cupertino 示例正文样式异常

第 10 分钟[截图](screenshots/020-monkey.png)中，正文呈现巨大红字、黄色下划线。
源码入口为 `demo/modules/navigation_lab/lib/src/presentation_pages.dart:46`：页面只返回
`CupertinoPageScaffold`，正文没有为 MaterialApp 宿主设置 Cupertino 默认文字样式。
该情况可在没有 Flutter 未处理异常日志时出现。

建议在 Demo 的 Cupertino 页面正文提供 `DefaultTextStyle`，取
`CupertinoTheme.of(context).textTheme.textStyle`，并补 MaterialApp + 显式 Cupertino Route
的样式/小屏回归。先修应用页面，不为这一示例改变全局路由主题契约。本轮只记录，未修改应用。

### P2 待定位：Native/Graphics 与总 PSS 在后半程增长

冷启动 GC 后基线 PSS 为 114033 KiB（111.36 MiB）。第 10 分钟为 182600 KiB，
第 15 分钟为 205578 KiB，第 20 分钟为 284815 KiB。Dart 堆在自然 GC 下反复回落，
这不能单独解释 Native/Graphics 的增长，也不能据此证明其无异常保留。

约第 14 分 33 秒设备启动系统录屏，证据见[系统记录](screen-recording-midrun.txt)及
[第 15 分钟截图](screenshots/030-monkey.png)。录屏来源未确认，不能直接归因于 Monkey
或用户操作。本轮保留现场继续计时，未停止用户系统服务；性能统计按录屏前后分段。
设备 USB 供电且开始时已有 Thermal Status 1，后续出现更高温控等级；后台系统负载也会影响结果。

不能从 PSS 曲线直接认定 CCRouter 存在 `not-disposed` / `not-GCed` 泄漏。
建议下一步关闭系统录屏并待温控恢复后，以相同 seed 重做对照；若 Native/Graphics 的增长
仍能复现，再以同一引擎、同一目的页反复打开/返回的受控循环和原生分配/保留工具定位。
随机遍历不同功能引入缓存预热，不能直接等同于重复同一路径的泄漏复现。当前保留为内存验收待定位项。

### P2 性能观察：早期单帧 build 超过 1 秒

第 53 秒左右，Flutter 第 1154 帧 build 为 1162.584ms，raster 为 10.860ms，
total span 为 1175.083ms。原始帧见[flutter-frames.ndjson](flutter-frames.ndjson)。
同时段系统进程也报告 Choreographer 跳帧，尚未证明二者的因果关系。

尝试读取既有 profiler ring，但 CPU profiler 未启用，返回 `Feature is disabled`；
旧帧的 Timeline 只剩线程元数据。见[捕获记录](slow-frame-capture.ndjson)和
[Timeline 输出](slow-frame-1154-timeline.json)。缺少具体调用栈，保留待归因，不猜测为路由计算缺陷。

### P3：Managed Demo 仍有 GoRouter 遗留文案

第 5 分钟[截图](screenshots/010-monkey.png)的详情页正文仍写“页面不读取 GoRouterState”。
来源为 `demo/modules/navigation_lab/lib/src/detail_page.dart:97`。建议改为介绍生成 Codec
与 typed arguments 的当前语义，避免对已删除 Backend 产生歧义。

## 生命周期与验证限制

约第 10 分 39 秒旧 Activity 正常结束，随后由 Monkey 再次启动；进程 PID 保持 24424，
Dart isolate 换代。`events.ndjson` 保留 isolate exit，`metrics.ndjson` 与补充堆数据保留 isolate ID。
因此连续 30 分钟覆盖包含 Activity 重建，内存趋势必须按 isolate 分段，不能以重建后的回落
证明同一 Runtime 中的 Route/Scope 释放情况。

Android 12 未覆盖 Android 13+ Predictive Back。随机原生事件与定时截图也不能证明 Demo
所有按钮、每条路由不变量或侧滑只退一层；既有 Widget feature matrix 仍需独立保留。
本次关闭 syskeys 后不再随机发送 Back 键，major navigation 主要是 Menu/DPAD_CENTER；
近期片段曾停留静态 Cupertino 页面，截图和帧数都能看出覆盖变稀。后续语义 Monkey 应加入
页面感知的返回与场景恢复，避免把底层事件条数解释为有效业务操作次数。
本轮缺少 GoRouter 配对基线、Release 构建、Native allocation retaining path 与 90Hz 验收，
不据此宣布新架构性能优于旧架构或零泄漏。

## 原始证据

- [录制器事件](events.ndjson)、[录制器输出](recorder.log)。
- [Monkey 日志](monkey.log)、[平台/Flutter 日志](logcat.log)。
- [PSS/RSS 与进程采样](metrics.ndjson)、[Dart 堆与 CPU](dart-memory-cpu.ndjson)。
- [帧数据](flutter-frames.ndjson)、[汇总统计](summary.json)。
- [应用崩溃缓冲区](crash-buffer-app.log)、[应用退出原因](exit-info.txt)。
- [计时末内存](meminfo-after.txt)、[结束环境](environment-after.txt)、
  [新 isolate 的 GC 后内存](cooldown-dart-after-gc.json)、[最终截图](screenshots/cooldown-final.png)。
- 每个采样点的原始 meminfo/cpu/top/gfxinfo/Activity/温度在 `samples/`，截图在 `screenshots/`。
