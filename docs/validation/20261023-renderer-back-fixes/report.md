# Managed Renderer 与原生 Back 修复验收

日期：2026-10-23。工作区分支：`codex/managed-navigation-runtime`。
本轮保留已有迁移改动，没有提交、推送或修改生成源码。

## 问题与方案选择

前轮审查的四类问题均已修复。共同根因是逻辑 Entry、实际 Navigator 渲染实例、
平台返回回调被当成了同一个生命周期或同一个焦点目标。

应用层强制切焦点、永久 Offstage 或延迟关闭 Scope 改动小，但不能修复框架记录分裂；
重新设计整个 Backend 的风险与成本过高。本轮选择在现有 Managed 架构内补齐精确
原生 Guard SPI 与真实 Renderer 生命周期，保留业务导航 API 和逻辑 Stack 所有权。

| 问题 | 修复及关键不变量 |
| --- | --- |
| 原生 Pop / iOS 提交提前释放 Route Scope | observer 丢失 Route 关联前建立幂等退出信号；结果及 active Entry 先结束，退场正文/Scope 保留到实际渲染结束；shutdown 不等下一帧 |
| 非焦点 Outlet / 非活动 Host 的原生 Guard 错选页面 | 新增 Host-only 可选 scoped Guard binding，传实际 Host/Outlet/backend identity；AppBar 语义返回、iOS eligibility、predictive policy 不切换全局焦点 |
| Outlet 卸载遗留 foreign、Guard、渲染关联与 lifecycle top | root、named、Shell 统一 Renderer ownership；真正卸载时退休旧记录，保留 Managed identity、Scope 和待返回结果；旧 generation 不能清新 renderer |
| 折叠隐藏焦点后 Back 错落 root | 无有效焦点/选中分支时，选择唯一可见且已挂载的 Outlet；多个候选不靠列表顺序猜；根 foreign 覆盖优先 |

实施中补齐两个同源边界：

- 复用 RouterConfig 重挂载时，不再重放已完成的 initial Go；相同当前地址保留原 Entry，
  后续真正不同的地址仍经过正常 ingress。
- 同帧左右换位属于 Flutter reparent，而非 Navigator dispose。使用私有稳定 Renderer Key
  让 observer/gates 与实际 Navigator 一起迁移；存活 Popup 不能从 foreign ledger 消失。
  此用例先复现 foreign 从 1 变 0，再验证修复。

新 SPI 保留旧一参数 Guard binding。MultiHost 为当前/动态子 Host 转发精确 target；
legacy 单 Navigator 子 Adapter 固定到自身 Host。初始化拒绝、动态 unregister、
解绑及 shutdown 均清理回调。清理同时失败时保留第一个异常，并继续释放其他资源。
业务 barrel 隐藏新 SPI，Host barrel 显式导出，API 编译隔离测试通过。

## 回归证据

正式失败基线：迁入 19 项交叉场景后，13 passed / 6 failed，失败对应前轮四类缺陷。
修复及扩展后新增 32 项正式回归：26 项跨生命周期、5 项 binding、1 项 Demo。

- [跨生命周期回归](../../../packages/ccrouter_test/test/managed_cross_lifecycle_regression_test.dart)
- [Guard binding 回归](../../../packages/ccrouter_test/test/scoped_pop_guard_binding_test.dart)
- [Demo 自适应 Renderer 回归](../../../demo/test/adaptive_renderer_lifecycle_test.dart)

覆盖 native/business/system/iOS gesture 的退场中间帧、结果、一次 Scope dispose，
Pop 后再次 Pop/Push/Replace/Go/Reset/Close/Popup，原生 Pop 后无下一帧 shutdown，
非焦点面板与非活动 Host 的原生 Guard，root/named/Shell 重挂载，
反复卸载时的待返回结果、Route Service、handle，旧 Route 的强制 GC，
同帧 reparent、foreign popup ledger、折叠 Back 和 Demo close 后底面恢复。

最终全量命令：

```sh
fvm flutter test --no-pub packages/ccrouter_test/test demo/test demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test tool/test --reporter expanded
fvm dart analyze
fvm dart run ccrouter_generator:ccrouter generate demo --no-cache --check
fvm dart run tool/documentation_check.dart
git diff --check
```

| 检查 | 本轮结果 |
| --- | --- |
| Framework + Demo + navigation_lab + analytics_flutter | 746 passed |
| analytics + Firebase + tool | 55 passed |
| Workspace analyzer | No issues found |
| Demo Host 无缓存生成物检查 | up to date |
| 文档链接/索引检查 | passed |
| diff whitespace 检查 | passed |

已有连续 iOS swipe / cancel / double-pop、Android predictive bridge、parent plan、
interceptor/defer/recovery、revalidation、typed result、exact close、Shell retained
state、Service/Command/Event/InitTask 和 semantic monkey 均包含在上述全量套件中。
本轮没有 Generator 或 Analyzer Plugin 生产修改，未重跑耗时完整 Generator 测试矩阵。

原始本机日志：

- `/tmp/ccrouter-lifecycle-fix-baseline.log`
- `/tmp/ccrouter-lifecycle-reparent-baseline.log`
- `/tmp/ccrouter-lifecycle-unbind-baseline.log`
- `/tmp/ccrouter-lifecycle-fix-focused.log`
- `/tmp/ccrouter-lifecycle-fix-binding.log`
- `/tmp/ccrouter-lifecycle-fix-full.log`
- `/tmp/ccrouter-lifecycle-fix-dart.log`
- `/tmp/ccrouter-lifecycle-fix-analyze.log`
- `/tmp/ccrouter-lifecycle-fix-generate.log`
- `/tmp/ccrouter-lifecycle-fix-docs.log`

## 内存与所有权

已修复的具体 `not-GCed` 链为 Adapter → Outlet observer → foreignEntries/topRoute →
已销毁 Route。Renderer retirement 清理 live Routes、foreign ledger、PopEntry/pending
registration、弱渲染关联和 PageLifecycle top。退场信号也在 renderer dispose 结束，
不依赖 Flutter 在整体 Navigator 销毁时为每条 Route 补发 didPop/didRemove。
退出回调在完成/取消后不再持有 Runtime；重复完成幂等。

强制 GC 回归在 Adapter 和逻辑 Entry 仍存活时确认旧 Managed Route 与 foreign Popup
均可回收，同时新 renderer 保留原 Scope/handle。该证据不代表长期 RSS、峰值内存或所有
第三方业务资源均无泄漏。

## macOS 实际窗口

通过 `fvm flutter run --no-pub -d macos -t lib/multi_host_demo.dart` 构建并运行。
首轮使用原生窗口自动化和实际 UI 完成：

1. compact 列表选择 Item 3，展开到 1920 × 914，右侧为 `adaptive.detail`。
2. 右侧打开 Level 3，缩窄卸载右侧 Navigator，再展开，Level 3 恢复。
3. 点击“Pop 并返回结果”，确认显示 `Detail View · adaptive.detail`，无空白覆盖。
4. 再打开 Level 3，点击“覆盖后精确关闭本页”，覆盖页 Level 4 保留；
   Managed Entries 从两个 stack 恢复到一个 stack。覆盖页 Pop 后回到底面。

上述真实操作后又补齐同帧 reparent 与解绑异常优先级。最终代码再次成功构建，
并完成 Hot Reload；最后一轮原生窗口点击未生效，坐标操作返回
`noWindowsAvailable`。因此不将最终重跑的窗口交互记录为通过，也不将首轮窗口验证
扩大为全部功能/全部按钮验收。两个自启动 Demo 实例及其 Flutter run/watch 已结束。
本机运行日志保存在：
`/tmp/ccrouter-lifecycle-fix-macos.log`、`/tmp/ccrouter-lifecycle-fix-macos-final.log`。

带本地 Popup 的折叠/展开/精确 close 组合在 Demo Widget 回归中通过；
该组合没有完整的最终 macOS 窗口重跑记录。

## 后续设备验收边界

本轮没有复验三星 Android 或 iOS 真机手势，也没有做新的长期性能/RSS 采样。
真实设备需继续核对：Guard deny/allow、跟手、取消、提交、连续手势仅退一层，
以及手势提交中途转后台/旋转/销毁 renderer。Widget 手势和 bridge 测试不能替代 OS 验收。

本轮通过 framework/integration Skill 的 ownership 和 API-isolation 规则，
同步了 README、中英文接入说明、集成 Skill、实施模式与 review checklist。
改动保留现有业务签名；回滚时应将 scoped binding、Renderer/exit 修复及其回归作为一组处理，
不能仅移除清理逻辑或让应用再次通过焦点时序补偿。
