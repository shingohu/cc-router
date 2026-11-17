# Flutter 3.47.9 适配完整性评估

日期：2026-11-17。源码：`699c81ae6a0e0080f0f00475bfa0673aad0867ff`。
SDK：官方 Flutter 3.47.9 / Dart 3.13.7，Framework `c197ca5199`、Engine `89c39edfdf`、
DevTools 2.60.0。本轮评估不修改生产源码，不发布 Plugin 或修改本机 SDK Hook。

**后续修复更新：** 用户批准实施后，Web 修复、Chrome CI、原生配置迁移与新 Plugin pin
均已落地，现场 IDE 验收仍受阻。以下保留原提交的评估事实；最新结果见文末
[修复落地与复验](#修复落地与复验)。

## 结论与实际阻断

**尚未完全适配。标准 SDK 下核心 VM 回归与四个平台的编译已通过，但发现 Web JavaScript
路径的 Runtime 初始化阻断；IDE 分发、原生工程迁移及 OHOS 仍未闭环。**

Web 阻断位于 `packages/ccrouter_core/lib/src/runtime_host.dart:269`：

```dart
Random.secure().nextInt(1 << 32)
```

JavaScript 的整数位移在这里得到 0，Runtime 构造即抛出
`RangeError: max must be in range 0 < max ≤ 2^32, was 0`。Chrome 中三个既有 Managed
测试全部在 `CCRouterHost.initialize` 失败，尚未进入导航断言。`git blame` 表明该行来自
历史基线；本轮证明它在目标 SDK 下仍然阻断 Web，不将其归因为本次升级新增。

只在临时副本将上限换成 `0x100000000`，同样三个 Chrome 测试 **3 项通过**，VM 对照
**3 项通过**；随后还原临时生产源码。该字面量保留 32 位随机范围，不新增依赖或公开 API。
这是已验证的最小候选修复，尚未应用到当前分支；3 项 GREEN 不代表整个 Web 套件通过。

- [原始 Chrome 失败](chrome-package-navigation.log) / [临时补充错误报告器取得的异常栈](chrome-error-details.log)
- [候选补丁](web-runtime-candidate.patch) / [Chrome GREEN](chrome-candidate.log) / [VM 对照](vm-candidate.log)

首次从 Workspace 聚合根运行 Chrome 测试产生测试 URI 的 file-not-found，属于无效的测试
入口证据，见 [root 调用日志](chrome-navigation.log)。随后从 `packages/ccrouter_test/` 执行
`flutter test --no-pub --platform chrome test/managed_router_backend_test.dart --name 'activateExisting|deliverToExisting'`
完成上述 RED/GREEN。常规 VM 框架全量仍按仓库规范从根目录运行。

## 当前证据矩阵

| 层面 | 结果 | 证据边界 |
| --- | --- | --- |
| SDK、Pub、Generator | 干净副本 root / Demo / Extension Pub 成功 | 使用同一 SDK，显式禁用 Hook；Pub 成功不代替 Host 生成 |
| 核心 VM / Demo 回归 | 同源码最近验证 Framework 1718、Demo 全目录 188 项通过 | [合入主分支记录](../20261117-generator-plugin-followup/report.md#合入主分支后的组合验证)，不是本轮新跑 |
| Generator / Plugin 回归 | 同源码最近 Generator 209 + Portable 1、Plugin 215、工具 53 项通过 | 当前提交 Generator 全目录未重跑；不拿合入主分支前的 725 项替代 |
| DevTools 协议与面板 | 本轮 7 + 17 项通过 | 独立 Package 测试补齐了框架主套件以外的范围 |
| DevTools Extension | Release Web、官方 build_and_copy、validate 成功 | 实际出现 validation successful；未验证 DevTools 2.60 连接中的 UI |
| Demo Web / 独立 Example Web | 两个 Release JS 构建成功 | 构建成功不等于 Runtime 启动成功；上面的 Chrome RED 是实际阻断 |
| Android | Debug、Release APK 构建成功 | Release 使用 Demo 既有 debug signing 配置；不是生产签名或真机验收 |
| iOS | Simulator Debug、设备目标 Release 编译成功 | Release 显式 no-codesign；未安装到真机 |
| macOS | Debug、Release 编译成功 | 未进行原生应用交互验收 |
| Runtime 长循环 | 10000 次循环完成，账本清理断言通过 | RSS 仅趋势记录，无同条件 A/B，不宣称性能提升或全场景无泄漏 |
| Demo Plugin | status、doctor、pin-check 均完成 | doctor 验证的是旧 ref 的临时 loader，不是本地新修复或当前 IDE |
| 实际 SDK Pub Hook | status 返回 1，未安装 | 可选集成尚未验收，不据此判定 Hook 源码不兼容 |
| OHOS / Windows / Linux | 未验证 | 旧 OHOS SDK 的 meta 1.17.0 与工具链冲突；标准 Flutter 3.47.9 不等于 OHOS Fork |

全部本轮命令和退出码见 [results.json](results.json)，SDK 修订、产物 SHA-256 和自动迁移
文件见 [manifest.json](manifest.json)。构建产物保留在仓库外临时副本，未加入 Git。

## 工程与分发缺口

1. Flutter 3.47.9 stable 默认启用 Swift Package Manager。本次 Apple 构建自动改变 6 份
   Xcode project/scheme/Pod lock；Android 构建另在 gradle.properties 自动增加
   `android.builtInKotlin=false` 和 `android.newDsl=false`。当前仓库仍为原配置，成功构建
   对应“干净提交起点经 SDK 自动迁移后的临时副本”，不是原生工程文件完全未变。
   [7 份迁移候选差异](native-migrations.patch)可单独审查，尚未应用。自定义 Podfile 还会提示
   CocoaPods 与 SPM 并存，需明确保留或完成迁移；这次编译没有因此失败。
   补丁保留零上下文差异；从评估基线复现时使用 `git apply --unidiff-zero`。
2. Android 的 AGP 8.11.1 / Kotlin 2.2.20 当前构建成功，但 Flutter 提示后续需升级到
   AGP 9.0.1 / Kotlin 2.3.20。属于维护事项，不能仅为消除 warning 直接跨大版本升级；
   需另核对 Gradle、JDK 与插件兼容矩阵。本轮未跳过依赖校验或接受新的 Android 许可证。
3. Demo Plugin ref 仍为 `f0bd3c2af3c3f6282f503e7182a41779beeb19f5`。远端 ref 可解析，
   manifest/lock/resolved-ref 一致，但 pin-check 明确报告两个 Plugin 生产文件 pending。
   新 UI 语义解析修复尚未随 Demo pin 交付；doctor 的 loader smoke 不能代替 IDE 加载证明。
4. 真机手势返回、PopGuard、Deep Link、WebView、可访问性和自适应重挂载的原生体验，
   Hot Reload/Restart 与实际 SDK Hook、DevTools 活连接、真实 Actions 均未验收。
   本轮 Web 构建的 Wasm dry run 不等于 Wasm 运行或浏览器全量回归。

## 方案取舍与建议顺序

| 方案 | 收益 | 限制与成本 |
| --- | --- | --- |
| 先完成标准 3.47.9 的确定性阻断与工程基线 | 可最小化修复范围，保持当前 SDK 和依赖组合 | 不能提前承诺完整 IDE、设备或 OHOS 支持 |
| 同时升级 AGP/Kotlin、Plugin 平台及所有 Fork | 覆盖面更广 | 增加变量，难以区分框架缺陷与平台迁移，成本更高 |

推荐第一种方案，并按以下顺序收口：

1. 应用 Web 随机上限最小修复，保留可持续执行的 Chrome 回归，再扩大 Web 场景验证。
2. 单独审查、提交原生工程 7 份迁移差异，重复相应构建，再做设备交互验收。
3. 按两阶段流程先推送已验证 Plugin 提交，再另一个提交更新 Demo 完整 SHA 与 lock；
   pin-check、doctor、重启 Analysis Server 后验证真实 diagnostic / Quick Fix。
4. 按实际需要验收 3.47.9 SDK 的可选 Pub Hook；补跑当前提交 Generator 全量、真实 CI 和
   DevTools 活连接。OHOS 使用可解析新工具链的独立 Fork，再建立其平台矩阵。

本轮留下评估报告、失败与候选修复证据，未将临时修复或原生自动迁移写入生产分支。

## 修复落地与复验

用户批准上述建议后，应用跨 JavaScript 的 `0x100000000` 随机上限，保留原有 32 位安全
随机范围；新增只使用公开 Host/Facade 的初始化、关闭、重启回归。新测试在修复前的
Chrome 实测失败；修复后与三个既有 Managed 导航用例共 **4 项通过**。
Quality 增加独立 Chrome Job，从测试 Package 执行相同回归，VM 全量继续从根目录执行。

本次新执行结果：Framework **1719 项**、Demo 全目录 **188 项**、工具 **53 项**、
生成命令/Portable 分发/Workspace 校验 **54 项**，全部通过。没有重新运行整个 Generator
目录；54 项覆盖状态身份、缓存失效、Git/归档分发与严格拒绝边界。
全部夹具还原后再次 prepare，9 个 publish 入口、Demo 和独立 Example 的 no-cache check
均通过。当前源码与 9 份状态见 [fix-manifest.json](fix-manifest.json)。

已将 7 份 SDK 自动迁移的原生工程文件应用到当前分支。在隔离副本同步实际修复和迁移后，
Demo Web、macOS、iOS（未签名）和 Android 的 Release 构建再次全部通过；前后逐字节核对
7 份配置文件，额外漂移均为 0。保留自定义 Podfile，不将 CocoaPods 清理或 AGP/Kotlin
大版本升级混入这次修复。原生设备交互仍是独立验收项。

Plugin 两阶段发布已先将已审查提交 `699c81ae6a0e0080f0f00475bfa0673aad0867ff` 推送到
远端功能分支，再更新 Demo 手工 bootstrap 的 manifest/lock 到该完整 SHA。CLI upgrade
dry-run 按设计拒绝接管手工 bootstrap，后续直接更新 manifest 并由 Pub 重解 lock；
不新增 CLI 安装、不升级 Analyzer 8.4.0 / analyzer_plugin 0.13.10。

- pin-check：远端可解析、manifest/lock/resolved-ref 一致、生产漂移 **0**。
- doctor：新 pin 在临时副本的依赖、分析、loader 编译通过；现有私有缓存仍提示 stale。
- 与新 pin 生产源码一致的真实 LSP UI-only 诊断专项 **1 项通过**。
- 现场 IDE：尝试用 Android Studio 打开当前 worktree Demo，打开后 UI 查询持续超时；
  重新选择窗口和取消操作后仍无法读取界面。没有完成 Analysis Server 重启或取得真实
  IDE diagnostic / Quick Fix，因此不宣称当前 IDE 已加载新 pin。未强制终止其他项目的
  IDE/Analysis Server，未移动无法确认所有权的全局缓存。

对应证据：

- [新增回归 RED](fix-red.log) / [Chrome GREEN](fix-chrome.log) / [全量与工具摘要](fix-suite-summary.log)
- [Portable 扩大回归](fix-portable.log) / [最终生成验收](fix-generation-summary.log)
- [Web](fix-build-web.log)、[macOS](fix-build-macos.log)、[iOS](fix-build-ios.log)、[Android](fix-build-android.log) Release 复验
- [新 pin 的 Pub](pin-pub.log)、[pin-check](pin-check.log)、[doctor](pin-doctor.log)、[真实 LSP](pin-lsp.log)
- [本次命令与退出码](fix-results.json)

Web 初始化阻断已修复，原生工程基线已冻结，Plugin 配置/loader 更新完成。当前剩余边界为
IDE 现场验收、真机交互、可选 SDK Hook、真实 CI、Generator 全目录与 OHOS 等独立平台。

本地提交分别为 Web 修复 `e2c48f7d` 与原生迁移 `8be9aeda`；Demo bootstrap 与本记录
作为后续独立提交。先前 Plugin 提交 `699c81ae` 已推送，本轮新增修复提交留待整体审查。
最终分层分析、191 份文档与敏感信息检查见 [fix-final-gates.log](fix-final-gates.log)。
