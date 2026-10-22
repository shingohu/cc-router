# Managed Navigation 平台验收记录

日期：2026-10-22。代码身份：`85b6137` 加当前
`codex/managed-navigation-runtime` PopGuard 修复。对象为原生 Managed Backend、
`CCManagedMultiHostBackend` 和 backend-neutral Predictive Back coordinator；该记录不覆盖
业务应用，也不替代发布候选版本的最终验收。

## 环境

| 平台 | 环境 | 用途 |
| --- | --- | --- |
| macOS | macOS 26.6.1，Debug App | MultiHost 真实窗口 |
| Android | OnePlus NE2211，Android 16 / API 36，1080 x 2412，targetSdk 36 | Managed Back、Guard、monkey、内存 |
| Android | Samsung SM-S911U1，Android 16 / API 36，1080 x 2340，targetSdk 36 | Managed / GoRouter Predictive Back 真手势 |
| iOS | iOS 26.5 Simulator | Managed build 与基础栈 smoke |

Flutter 为 `3.41.10-ohos-1.0.0` / Dart 3.11.5。当前没有可用 iOS 真机。

## macOS MultiHost

入口：

```sh
fvm flutter run -d macos -t lib/multi_host_demo.dart --debug
```

真实窗口中已完成右侧 Host 点击链：激活 `host.secondary`、进入右侧“导航”、执行右侧
`Push + typed result`。右侧显示“类型安全详情 / ID 42”，左侧仍停留“运行总览”，顶部保持
`host.secondary · active`，未复现“点击右边却跳到左边”。

后续重启时窗口继续正确渲染双 Managed Host，但本机 CUA 坐标输入服务对该 Flutter 窗口返回
`noWindowsAvailable`，AX 只暴露根容器。因此本轮没有把左右详情分别返回、自适应布局点击和
真实窗口 monkey 记为通过；这些场景的 Widget 回归仍由 `multi_host_demo_test.dart` 覆盖。

结论：多 Host 核心隔离真实点击通过，完整 macOS 窗口矩阵部分完成。

## Android Managed

入口：

```sh
fvm flutter run -d <device> -t lib/main_managed_predictive_back.dart --debug
```

首次运行发现 Demo 没有把 `enablePredictiveBack` 传给 Managed factory，且有效 Manifest 没有
启用 `android:enableOnBackInvokedCallback`。修复后 APK 的合并 Manifest 已确认该属性为 true，
targetSdk 为 36。

设备的 Oplus WindowManager 仍报告 `predictive settings is disabled`，手势日志为
`animationCallback is null` 并回落到 `onBackPressed`。标准
`enable_back_animation=1` 没有解除 OEM 限制，shell 也无权设置
`persist.wm.debug.predictive_back_always_enforce`。因此该设备没有完成真实 Predictive Back
`started/cancelled/committed` 阶段验收，不能把普通边缘返回冒充预测返回。

在系统 fallback 路径完成：

- typed detail 长边缘滑动只退一层，Route Entries 回到 1；
- PopGuard 未保存时相同手势被拒绝，页面保留；
- 切换为已保存后相同手势只退一层，Route Entries 回到 1；
- 结束后已将临时 `enable_back_animation` 从 1 恢复为原值 0。

### Monkey 与内存

对 `dev.ccrouter.demo` 连续运行两轮相同 seed、每轮 1000 events：

```sh
adb shell monkey -p dev.ccrouter.demo --throttle 20 \
  --pct-syskeys 0 --pct-appswitch 0 --pct-anyevent 0 \
  -s 20261022 1000
```

两轮均注入 1000 events，进程保持存活，没有 crash、ANR、Flutter 未处理异常或 OOM。
Monkey 的 device flip 事件因 `/dev/input/event0` 权限被拒绝三次，其余事件继续执行。

内存检查点：

| 检查点 | Total PSS | Native Heap PSS | Java Heap PSS |
| --- | ---: | ---: | ---: |
| 冷启动及手工场景后 | 266394 KB | 53496 KB | 11024 KB |
| 第一轮后，foreground trim | 307052 KB | 80688 KB | 10220 KB |
| 第二轮后，background COMPLETE trim | 312837 KB | 79496 KB | 10488 KB |

第二轮没有继续出现首轮约 40 MB 的线性增长，Native Heap 反而下降约 1.2 MB；这支持
“未发现短时线性泄漏”，不证明长期零泄漏。随机遍历后的 warm cache 比冷启动高约 46 MB，
仍需 release/profile 模式的长时循环和 heap snapshot 才能形成性能预算。

`gfxinfo` 累计 54 frames 中 3 个 deadline jank（5.56%），P50 8 ms、P90 61 ms；样本混入
Debug 启动和 UI 自动化，不可作为 release 性能结论。

## Android Samsung Predictive Back

设备：Samsung SM-S911U1，Android 16 / API 36，三键/手势配置中的
`navigation_mode=2`。验收时临时把 `enable_back_animation` 从原值 0 设为 1；全部验收结束后
已恢复为 0。通过设备侧真实 `MotionEvent` 边缘手势注入验证，系统日志均明确报告
`mIsAnimationCallback=true`、`dispatchOnBackStarted`，取消路径为
`onBackNavigationDone triggerBack=false`，提交路径为 `dispatchOnBackInvoked` 和
`triggerBack=true`。

### Managed Backend

入口：

```sh
fvm flutter run -d R3CW402QMBJ \
  -t lib/main_managed_predictive_back.dart --debug --no-pub
```

- 普通 typed detail 左缘取消后仍显示 `ID 42`，Demo 记录
  `Predictive back · started`、`cancelled`，没有完成结果或释放 Route Scope；
- 右缘提交后只移除 detail，记录 `started`、`committed` 和一次 `Detail dispose`，回到
  Managed 首页基线 `1 Route Entries`；
- `dirtyForm=true` 的 PopGuard 页面提交系统手势后保留页面，只记录
  `PopGuard · system · deny`，没有新增 predictive phase；
- 切换为已保存后再次提交，只记录一次 `PopGuard · system · allow`，只退一层并回到
  `1 Route Entries`。

真机在这里发现并复现了一个 Framework 缺陷：Managed Adapter 原先没有像 GoRouter
Adapter 一样为 guarded Route 注册关闭的 Flutter `PopEntry`，Android 手势会直接 Pop，绕过
Runtime PopGuard。修复在 Managed Adapter 内增加 Route-scoped gate；Runtime 批准的业务 Pop
临时打开 gate，system fallback 同步求值后只重试同一当前 Route。Route unmount、Adapter
unbind/dispose 会注销 `PopEntry` 并释放其 `ValueNotifier`，延迟注册也受 dispose 状态隔离。

### GoRouter Compatibility Backend

入口：

```sh
fvm flutter run -d R3CW402QMBJ \
  -t lib/main_predictive_back.dart --debug --no-pub
```

同样完成普通 detail cancel/commit 和 PopGuard deny/allow。普通页记录完整
`started/cancelled/committed`；guarded 页面只记录 `PopGuard · system · deny/allow`，没有新增
predictive phase。提交均只移除一层且 Scope 只释放一次。GoRouter 声明式首页不是 Runtime
push Entry，因此返回后的既有 Demo 基线为 `0 Route Entries`；Managed 首页由 Runtime 管理，
基线为 1。这是两种接入模型的既有差异，不是返回行为分叉。

## iOS Simulator

```sh
fvm flutter build ios --simulator --debug \
  -t lib/main_managed_predictive_back.dart
```

构建成功，并安装到 iOS 26.5 Simulator。真实 Simulator UI 中完成：首页渲染、进入“导航”、
Push typed detail、显示 `ID 42`、确认返回；状态回到 1 Route Entry，并显示
`detail:42:confirmed`。

Simulator 不能验证 iOS 真机边缘侧滑、交互动画、内存压力和多窗口生命周期。这些仍是发布 gate。

## 结论与 Gate

- backend-neutral feature matrix、生命周期测试和三平台 build/smoke 证据支持继续原生 Managed
  迁移与 A/B 对比。
- Samsung 真机已关闭 Android 单窗口 Managed / GoRouter Predictive Back 核心 gate；IME、
  PlatformView、原生多窗口和回到桌面动画仍需独立平台场景验证。
- Android NE2211 的 OEM predictive callback 仍不可用；macOS 完整真实窗口矩阵、iOS 真机
  侧滑仍未完成。
- `ccrouter_go_router` 继续保留兼容状态，不标记 deprecated；完成上述 gate 后再评估弃用。
