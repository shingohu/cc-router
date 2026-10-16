# 三星 Android 16 预测返回 Demo 验证

日期：2026-10-15。设备：SM-S911U1，Android 16 / API 36，1080×2340，手势导航
`navigation_mode=2`。对象仅为 `dev.ccrouter.demo` debug APK，Demo 实际 targetSdk 36。
本次没有修改系统手势设置、SDK / Manifest，也没有操作 LiberLive 业务页面。

## 方法与证据

开启版本从 `lib/main_predictive_back.dart` 构建；关闭版本从 `lib/main.dart` 构建。
分别安装并重新启动同一个 Demo。完成 A/B 后已重新安装、启动开启版本。

使用 shell `app_process` 注入完整 touchscreen MotionEvent 序列，保持同一 downTime、
逐帧移动与真实事件时间；从屏幕边缘滑出，再收回取消或继续向内提交。事件经过 Android
系统手势识别、embedding 和 Flutter Navigator，没有向 `flutter/backgesture` 直接发消息。
验证同时读取 UI hierarchy 和现有 Demo 日志。日志通过 VM Service `getObject` 只读获取，
不暂停进程、不执行表达式、不写运行时状态；每次读取后断开，端口转发已移除。

- [结构化检查点与 APK SHA-256](android_predictive_back_samsung_20261015.json)
- [触摸输入辅助源码](CCRouterGestureProbe.java.txt)
- [Demo 日志只读辅助源码](CCRouterDemoVmProbe.dart.txt)

JSON 每个检查点的事件按 Demo 的顺序排列，即最新事件在前。证据只保留 Demo 事件、
设备型号及构建身份，不保存设备序列号、VM Service 认证地址、业务参数或其他 App 日志。

## 结果

| 场景 | 结果 |
| --- | --- |
| true，左缘滑出再收回 | `started → cancelled`，仍显示 ID 42，无正式 Hide、结果完成或 dispose |
| true，同页右缘取消 | 再次 `started → cancelled`，页面仍保留 |
| true，两次取消后右缘提交 | 一次 `started → committed`，回导航页；Hide、结果完成、dispose 各一次 |
| true，重新进页并等待入场稳定后左缘提交 | 新序列正常接收；一次 committed，仅退一层，Route Entries 回到 0 |
| true，进页后立即返回 | 入场未稳定时走普通 fallback，无自动阶段；仅退出该详情，结果与 dispose 各一次 |
| Guard，未保存时左缘提交 | `PopGuard · system · deny`，Guard 页仍保留，无自动阶段 |
| Guard，保存后右缘提交 | `PopGuard · system · allow`，仅退出 Guard 页，无自动阶段 |
| false，左缘取消 | Flutter 原有取消保留 ID 42，无 CCRouter 阶段、Hide、结果完成或 dispose |
| false，随后右缘提交 | 回导航页且 Route Entries 为 0；无 CCRouter 阶段，Hide、结果完成、dispose 各一次 |

最初使用多个独立 `adb input motionevent` 命令尝试取消，系统实际判定为提交；该尝试
未计入取消通过。上表取消使用辅助程序的连续时间戳输入序列，确认实际产生 cancelled。

## 重现

从 `demo/` 构建相应入口并安装到选定设备；每次 A/B 重新启动进程：

```sh
fvm flutter build apk --debug --no-pub -t lib/main_predictive_back.dart
fvm flutter build apk --debug --no-pub -t lib/main.dart
```

将辅助 Java 文本复制为 `/tmp/CCRouterGestureProbe.java`，用本机 Android SDK 的
`android.jar` 编译，再用 build-tools `d8` 转成 `classes.dex`，推送到设备测试临时目录。
在 Demo 前台、详情页入场稳定后执行以下命令；将 `$DEVICE` 替换为本次选定设备：

```sh
adb -s "$DEVICE" shell CLASSPATH=/data/local/tmp/ccrouter-gesture-probe.dex app_process /system/bin CCRouterGestureProbe left cancel
adb -s "$DEVICE" shell CLASSPATH=/data/local/tmp/ccrouter-gesture-probe.dex app_process /system/bin CCRouterGestureProbe right cancel
adb -s "$DEVICE" shell CLASSPATH=/data/local/tmp/ccrouter-gesture-probe.dex app_process /system/bin CCRouterGestureProbe right commit
```

该输入夹具的坐标针对本次 1080×2340 设备，不是通用设备测试框架。也可人工执行相同
动作，通过 Demo“诊断”的阶段与生命周期事件核对。

## 限制

这是单台 Android 16 真机的系统输入链路冒烟，没有人工确认整段动画观感。未覆盖
Android 13/14/15、三键导航、IME、foreign Popup、WebView / 平台视图、原生 Activity、
返回桌面，以及多个独立可见 Host 的系统返回仲裁。嵌套 Outlet、手势中导航、Host 重建、
重复终态等自动化结果见主文档，不冒充本次设备验收。

Demo targetSdk 36 不代表 LiberLive 已升级 targetSdk 或完成业务页面迁移。OHOS 外部
embedding / SDK 的 AutoFill 构建失败仍未解决，此次 Android 验证不改变该限制。
