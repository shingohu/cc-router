# Managed 导航生命周期与可见性修复

日期：2026-10-23。分支：`codex/managed-navigation-runtime`。
修改保留在原 worktree，未提交、未推送；保留此前导航重构与职责迁移。

## 根因与方案取舍

本轮处理上一轮 review 复现的三个问题：

1. **普通 Pop 退场正文提前消失（P1）**：正文将 Store Entry 缺失直接视为渲染结束。
   Flutter 的反向动画仍在进行，Entry 和 Route Scope 却已释放。仅保留旧 Widget 也不够：
   页面订阅 `ModalRoute` 后，退出状态会触发重建，重新解析已关闭的 Route Service 就会报错。
2. **MultiHost 布局可见性被后续导航覆盖（P1）**：聚合层只向生命周期桥和事件报告布局，
   没有同步子 Managed Store；子 Store 的旧集合随后覆盖 Host 的选择。
3. **foreign Route 非 Pop 终态遗留空锚点（P2）**：只有 `didPop` 回收锚点，
   `removeRoute` 和 `replace` 缺少同一清理，下一次 push 后可能返回过期空页。

修复前独立探针的有效结果为 **1 项通过、3 项失败**：原生 Flutter 对照保留退场正文，
Managed 中间帧丢失正文；可见集合未到达子 Store；remove 后再 push 遗留两张 Page。
见 [原始复现日志](probe-before.log)。探针随后迁入仓库正式测试并扩充边界。

应用层在各页面补丁会重复生命周期逻辑；冻结已释放 Service 或渲染截图会隐藏资源错误，
并增加转场开销。仅将 Runtime Entry 延迟移除又会让已退出页面继续出现在 active 栈。
本轮选择两个可选、Host-only、backend-neutral SPI，保持业务导航签名不变：

- `CCNavigationRouteExitBinding`：逻辑 Entry/结果结束与渲染退出分离。Runtime 只保留
  精确退出页的 Route Scope，用可取消订阅等待 Flutter `TransitionRoute.completed`；
  退出页不参与 active Entries、导航选择与 revalidation。
- `CCNavigationOutletVisibilityBinding`：聚合层向所属 Adapter 传递布局选择，由子 Store
  负责有效可见性发布。未实现该 SPI 的 Adapter 保留生命周期/事件转发兼容路径。

两个 SPI 仅从 `ccrouter_host.dart` 暴露，业务 barrel 隐藏它们；API 编译探针覆盖边界。
回退应按本轮文件差异恢复，不能 reset 整个含既有修改的 worktree。

## 生命周期与状态收敛

- 普通 Pop 仍及时完成 typed result、移除 active Entry；正文及 Route Service 保留到
  Flutter 退场结束，防止中间帧空白以及 `ModalRoute` 依赖重建时 Scope 不可用。
  Service 的 dispose 时点相应延后到渲染结束，业务不得利用退场期启动新的工作。
- 精确 close 不等待动画；同步 `onDidRemovePage` 路径也不建立退场等待。foreign Popup
  所需空锚点清除业务正文、Extra 和 Scope，不延长业务资源生命周期。
- Runtime shutdown 在等待 Scope closure 前取消退出订阅，不依赖下一帧；Widget unmount、
  动画完成与 shutdown 都只清理一次。Flutter Future 只保留可脱离的信号对象；Adapter
  dispose 清空其 callback 和订阅，避免未完成的 Route Future 保留 Runtime/业务数据。
- Host 显式可见集合保持权威，push、焦点和 Shell 选择不会自行展开隐藏 Outlet。
  根级覆盖层只遮蔽选择。补测发现的根 Popup PageHide 不同步，以及 split Shell 切换
  短暂产生多余 hide/show，也统一为同一个有效可见集合。
- foreign Pop/Remove/Replace 统一收敛锚点；Replace 先登记新 Route，再判断锚点能否移除，
  避免替换 Popup 时提前拆除基座。根级及本地 foreign Route 都结束后才回收 Shell 锚点。

README、中英文接入说明、集成 Skill、实现模式、审查清单和资源清理规则同步这些语义。
框架没有重新引入 GoRouter、应用布局策略或埋点实现。

## 回归覆盖

- 普通页与 Guard 页的 iOS 风格中间反向帧：正文、结果、active Entries、同一 Service
  实例和一次 dispose；既有 Android predictive-back 与 iOS 提交/取消/重复手势回归。
- 退出动画中 shutdown 或直接 unmount：无需更多动画帧，Scope 关闭一次。
- 唯一 Managed 根页精确 close 后 foreign Popup 的 Pop/Remove/Replace；多个 Popup
  中间移除不提前回收；替换后 Popup 保持；后续 push 只有一张 Page 且不能返回空锚点。
- 最后一个 Shell Entry 同时被本地、根级 Popup 覆盖：close 不消费 Popup，正文清空，
  Scope 释放一次，最后一个 Popup remove 后新根页没有过期 Shell 锚点。
- 真实 Managed MultiHost：调用方列表变更、非法集合、未知 Outlet、另一 Host 隔离、
  隐藏后 Context 导航、根 Popup 遮蔽/恢复、PageShow/PageHide、结果与 Scope identity。
- 显式 split Shell 集合跨分支选择保持不变，不产生多余的 Runtime didHide。

## 验证

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Framework + Demo + navigation_lab + analytics_flutter | 714 项通过，包含本轮新增的 9 项测试及强化场景、semantic monkey | [Flutter](flutter-tests.log) |
| 应用 analytics + Firebase + tool/test | 55 项通过 | [Dart](dart-tests.log) |
| Managed/Outlet/MultiHost/API 专项 | 69 项通过，已包含于完整 Flutter 计数 | [专项](focused-tests.log) |
| Workspace analyze | No issues found | [Analyze](analyze.log) |
| Demo generate --check | 6 components、34 routes、11 generated Packages，通过 | [生成检查](generate-check.log) |
| Demo generate --no-cache --check | 通过 | [无缓存检查](generate-reference-check.log) |
| macOS Demo Debug 构建 | 通过 | [构建](macos-build.log) |
| Markdown 与 release sensitivity | 通过 | [文档](documentation.log)、[敏感信息](release-sensitivity.log) |

正式测试位置：

- `packages/ccrouter_test/test/managed_router_backend_test.dart`
- `packages/ccrouter_test/test/managed_router_outlet_test.dart`
- `packages/ccrouter_test/test/api_surface_test.dart`

未修改 Generator 或 Analyzer Plugin 生产实现，因此不重复上轮完整 Generator 的
645 项通过 / 1 项配置跳过，也不改 Demo Plugin pin。生成物通过 CLI 校验，没有手改。

本轮证据是自动化测试与 macOS 构建，**没有重做真实窗口操作、Android/iOS 真机手势或
长期 RSS/性能测量**。生命周期与既有资源回归未发现新增的高置信泄漏，但不据此声称
生产长期无泄漏，或所有平台表现已完成真实设备验收。
