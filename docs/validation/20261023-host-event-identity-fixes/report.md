# Host 注册事件身份与 Demo 首页修复

日期：2026-10-23。分支：`codex/managed-navigation-runtime`，HEAD `09cb21d`。
本轮修改在现有工作树内完成，未提交、推送；保留此前已有改动。

## 问题分析

修复对象来自[真实窗口失败报告](../20261023-macos-host-lifecycle-acceptance/report.md)：

- P1：Managed 用逻辑 Host ID 与重置的事件计数构造操作 ID，MultiHost 也会在同 ID
  重注册时重复自己的 detach ID。Runtime 的正确去重因此拒绝合法事件，Host 注销
  未抵达异步工作取消机制，可能让旧策略覆盖新页面。
- P2：生命周期 Demo 禁止初始路由，却显示“新实例首页”，造成空白与文案不一致。

前一轮回归只验证一次换代、或使用不同事件序列，没有覆盖同一 Runtime 下重复相同
事件顺序，以及退出后重新进入。UI 状态和首次成功不足以证明后续注销、Scope 清理
及新 Entry 身份仍正确。本轮把这些组合固定为自动回归并核对只读 Runtime 快照。

## 方案权衡与实施

| 方案 | 收益与代价 | 结论 |
| --- | --- | --- |
| Demo 每轮换 Host ID 或重启 Runtime | 实现简单，但规避同 ID 生命周期契约 | 不采用 |
| Runtime 取消去重或让所有 detach 直通 | 改动少，但重复或旧通知可能终止新实例 | 不采用 |
| 仅给 Managed 加实例 ID | 解决原生子事件，无法覆盖自定义子 Adapter 和聚合层事件 | 不完整 |
| Adapter 实例身份 + MultiHost 注册命名空间 + 旧回调拦截 | 私有实现兼容修复，保留去重，增加常数大小标识 | 已实施 |

已完成顺序：

1. 补充并执行失败回归，保留 `baseline.log`；Managed 专项测试修正了未等待微任务
   的测试夹具，原身份算法的有效失败证据另存 `managed-baseline-corrected.log`。
2. Managed 所有 backend operation ID 统一使用实例独立命名空间。
3. MultiHost 每个注册记录拥有独立命名空间与事件序列；子事件保留同代重复 ID 的
   一致映射，缺失 ID 仍为 null；自身 outlets/detach 事件使用同一个注册生命周期。
4. 转发 backend/predictive 回调前核对当前注册记录，拒绝退役注册排队中的通知。
5. 辅助 Demo 保留初始路由初始化，通过现有 Host-scoped startup 加载可信 `/`，
   设置 `overridePlatformDefaultLocation: true`，不重复消费平台启动链接。
6. 更新 README、集成 Skill 与实现/审查参考；执行专项、全量及真实窗口回归。

业务 API 与 Host SPI 的公开签名均未增加或改变；未改 Runtime 去重或异步取消契约。
事件身份是进程内实现细节，不是持久化或跨进程协议。

## 生命周期、内存与边界

序列直接属于注册记录，注销后不保留历史 Host map；静态/实例计数器只保存数值，
不保存 Backend、Widget、Route、参数或业务结果。原 listener remover、子 Adapter
dispose 及失败清理路径保留。没有新增 Timer、全局锁或异步等待资源。
诊断容量 0 与 2 下，各连续五次注册的 Route Service 均恰好释放一次，另一 Host
Entry 保持不变；自定义 Adapter 排队的旧 backend/predictive 回调不再传播。
这些是生命周期回归证据，本轮未执行 heap 保留链或长时间性能/内存认证。

## 自动回归

| 命令 | 本轮结果 |
| --- | --- |
| `fvm flutter test --no-pub packages/ccrouter_test/test/multi_host_test.dart packages/ccrouter_test/test/managed_host_incarnation_regression_test.dart demo/test/host_lifecycle_lab_test.dart --reporter expanded` | 67 通过，`focused.log` |
| `fvm flutter test --no-pub packages/ccrouter_test/test demo/test demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded` | 897 通过，`flutter.log` |
| `fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test tool/test --reporter expanded` | 55 通过，`dart.log` |
| `fvm dart analyze` | No issues found，`analyze.log` |
| `fvm dart run ccrouter_generator:ccrouter generate demo --check` | up to date，复用 active watch cycle 32，`generation.log` |
| `fvm dart run tool/documentation_check.dart` | 通过，`documentation.log` |
| `git diff --check` | 通过 |

专项包括：Managed 同 ID 实例事件不冲突、自定义 Adapter ID 跨注册隔离及同代去重、
退役注册晚到通知、多轮注销与 Scope 恰好释放、Demo 两次进入各三轮重开后旧请求
保持取消、902 页面身份不变、退出无残留、每次挂载/重开都有真实首页。
全量包含现有 semantic monkey、Pop/close、手势及跨生命周期自动回归。

## macOS 真实窗口验收

沿用 `lib/multi_host_demo.dart` 的 Flutter run 会话，热重启到本轮实现。
真实操作均通过 CUA；诊断只读调用 `ext.ccrouter.snapshot`，没有用 VM evaluate 导航。

| 实际操作 | 结果 |
| --- | --- |
| 初次进入及每次重开辅助 Host | 真实渲染 CCRouter Lab 首页，不再空白 |
| 连续三轮延迟导航 → 重开 → 新实例 901 → Push 902 → 放行旧决策 | 页面保持 902，旧请求取消；第 3 代截图明确显示第 2 代 `host_detached` |
| 第 4 代再次等待策略时切出 | 辅助 Host 活动 RouteEntry 清空，primary/secondary 各保留一项 |
| 同 Runtime 重新进入，再延迟 → 重开 → 901 → 902 → 放行 | 页面仍为 902，Entry 身份完全不变 |
| 902 执行 Pop 并返回结果 | 只回到 901，结果为 `stack:902:done` |
| 901 覆盖后按 identity 精确关闭 | 901 移除，覆盖页 902 仍在；再退出场景无辅助活动残留 |
| 右侧 header 导航，再左侧 header 导航 | 最终右 202、左 101，各自独立 |
| 自适应 detail Outlet 打开栈页并返回 | 回到 Item 1，双 Host 页面保留 |
| separating hinge 开/关，再回双 Host | 布局状态正常，最终左 101、右 202 |
| 运行控制台 | 本轮热重启及操作后读取未出现新增 Flutter exception |

快照证据：

- `macos-round1-before.json`：首轮 902 状态采样。
- `macos-round2-before.json` / `macos-round2-after.json`：四个 RouteEntry 的
  id、Host 和 traceId 前后完全相同；辅助页仍为 entry-8/entry-9。
- `macos-after-first-exit.json`：仅 primary entry-1、secondary entry-2。
- `macos-reentry-before.json` / `macos-reentry-after.json`：重新进入后四个
  RouteEntry 身份仍完全相同，辅助为 entry-15/entry-16。
- `macos-after-reentry-exit.json`：辅助 Host 无 RouteEntry、无 active Backend
  Entry；保留的 removed Backend 记录属于有界诊断历史。

本轮两项已知问题修复且上述验收通过。真实窗口范围是本次修复链路及双 Host/自适应
对照，不声称重新遍历默认 Demo 的全部按钮、重新验收 Android/iOS 真机手势，或完成
长时间 monkey、性能与内存认证。macOS 窗口及 Flutter run 会话保留。
