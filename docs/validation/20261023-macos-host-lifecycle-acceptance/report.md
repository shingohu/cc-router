# macOS Host 生命周期真实窗口验收

后续修复与通过记录见[Host 注册事件身份修复](../20261023-host-event-identity-fixes/report.md)。
下文保留修复前的失败证据。

日期：2026-10-23。工作树：`codex/managed-navigation-runtime`，HEAD `09cb21d`。
本轮只做真实窗口操作、只读诊断和报告，没有修改生产实现、Demo 或测试，未提交、推送。

## 结论

窗口点击通道已恢复，完成新增生命周期场景、双 Host 隔离、自适应 detail Outlet 的
真实操作。**验收不通过**：发现一个 P1 框架事件身份问题及一个 P2 Demo 初始空白问题。
先前自动回归通过的结论仍是当时命令结果，不能等同于多轮真实场景均符合契约。

## P1：事件 ID 跨 Host 注册实例复用，导致注销漏处理、旧请求覆盖新页面

真实操作顺序：

1. 生命周期场景第 1 代发起延迟导航，重开第 2 代。界面正确显示旧请求
   `host_detached`；新实例进入 Level 901，放行旧决策不改变页面。
2. 同一场景再做一轮，重开第 3 代。界面仍显示上一代 `host_detached`，新导航成功。
   在等待策略时切出到“Host 隔离”。此时全局 Route Entries 显示 3，Backend Entries
   为 2。通过只读 `ext.ccrouter.snapshot` 确认辅助 Host 仍有 navigation-6 的
   RouteEntry，而该辅助 Host 没有 active Backend Entry；不是单纯计数 Widget 未刷新。
3. 双 Host 分别进入右 Level 202、左 Level 101。切到自适应布局，detail Outlet
   Push/Pop，再切回生命周期场景，界面计代重新从 1 开始，但使用同一个 Runtime。
4. 再发起延迟导航、关闭并重开 Host。界面显示“辅助 Host 第 2 代”，旧请求仍是
   “第 1 代：等待策略”，没有按契约收到取消。
5. 新实例导航到 Level 901，点击 Push 下一层到 **Level 902**。
6. 点击“放行旧决策”。真实窗口从 **Level 902 被覆盖回 Level 901**，旧请求显示
   “第 1 代：已完成”。

只读快照进一步证实请求身份倒退：放行前，新页面属于 navigation-13 / entry-9；
放行后，当前页面属于更早的 navigation-11 / entry-10。新操作 navigation-12/13
不再是活动 RouteEntry。诊断不含 Path/Query、Extra 或业务对象。

归档快照：

- `before-late-decision.json`：新 Level 902 所属 navigation-13，另有上一轮遗留的
  navigation-6 / entry-4。
- `after-late-decision.json`：当前辅助 Host 页面变成旧 navigation-11；navigation-6
  的遗留 Entry 此时仍在。
- `after-exit.json`：最后一次切出触发了另一条可接受的注销事件，辅助 Host RouteEntry
  全部清除，只有 bounded removed Backend diagnostics。这个后续清除不否定前面的
  漏处理和页面覆盖，不把遗留描述为永久无法释放或已证明 heap 泄漏。

代码链路：

- `packages/ccrouter/lib/src/managed_router.dart:1619` 及同文件其它事件构造使用
  `managed-${host.id}-${++eventSequence}`，新 Backend 重新计数，Host ID 相同则操作
  ID 可以与上一实例相同。
- `packages/ccrouter/lib/src/multi_host.dart:892` 保留子事件原始操作 ID；
  `:343` 的注销 ID 使用 aggregate ID、逻辑 Host ID 和 Host sequence，而 `:349`
  在注销后删除 sequence。因此重复相同操作序列也会复用注销 ID。
- `packages/ccrouter_core/lib/src/navigation_backend.dart:363` 的有界全局去重先拒绝
  已处理的操作 ID，然后才进入 `hostDetached` 的生命周期处理。被误判为重复的注销
  不会调用 `_detachNavigationHost`，也不会清理 RouteEntries。

上一轮解决的是异步工作绑定具体注册 token；本轮缺口是生命周期通知在抵达该机制
之前被事件去重丢弃。不能据此移除去重或把所有注销绕过去重，否则重复/晚到事件可能
误终止新实例。

推荐修复顺序：

1. 先新增失败回归，固定同一 Runtime 下至少三代注册、重复同样的事件顺序，以及
   离开并重新进入场景；断言旧请求及时取消、不能覆盖新 Entry、卸载后无活动残留。
2. 为 Managed Backend 的操作 ID 增加不可复用的实例身份；为 MultiHost 每次注册的
   事件命名空间和自身注销事件增加不可复用身份，兼顾自定义子 Adapter 的重复 ID。
   保持同一注册内重复事件仍去重，拒绝已退役注册的晚到通知，使用 O(1) 标识而非
   无界保留历史 Host map。全部可在私有实现内完成，不需要业务 API 变更。
3. 加入同代重复通知、跨代晚到通知、诊断 capacity 为 0/较小值、exact Pop/close、
   Route Scope 恰好释放一次的对照，再跑全量和上述真实窗口序列。

这是框架缺陷。业务手动清队列、强制换 Host ID 或定期重启 Runtime 都不适合作为
推荐接入方案。

## P2：辅助 Host 初始区域空白，状态却称“新实例首页”

初次进入、重开和重新进入生命周期场景，控制区下方均是空白；首次业务导航后才
渲染 Level 901。`demo/lib/host_lifecycle_lab.dart:81` 显式关闭
`initializeFromRouteInformation`，又没有提交初始 Intent；`:94` 却固定显示“新实例首页”。

此路径的实际行为与禁用初始路由的配置一致，不据此报告框架无法渲染首页。缺陷属于
Demo 接入/文案和测试覆盖：现有 Demo 回归检查控制状态与后续 Level 901，没有断言
辅助 Host 的初始内容存在。

推荐让辅助 Host 通过现有 Host-scoped startup path 加载明确的可信初始首页，并保持
平台 Deep Link 只进入拥有它的 Host；补充首页真实渲染和仅属于辅助 Host 的 Entry
断言。若产品意图是空栈，则需要显式空态并准确命名，不能用“首页”掩盖空白。
不需要扩展 Core API。优先修复 P1，再修正这个 Demo 路径并重验。

## 本轮通过及范围

| 真实操作 | 结果 |
| --- | --- |
| 首轮及第二轮控制区的旧请求取消/新实例导航/放行旧决策 | 界面表现符合预期，但第二轮后清理核对发现上述 P1 |
| 右侧 header 导航 | 右 Level 202，左侧原页面保持 |
| 左侧 header 导航 | 左 Level 101，右 Level 202 保持 |
| 自适应 detail Outlet 打开栈页并 Pop 返回 | 回到 Item 1，未改变另一个 Host |
| 模拟 separating hinge 开/关 | 开关状态和双 Outlet 说明正确 |
| 离开/重新进入生命周期场景 | UI 状态重置，仍存在上述事件身份问题 |
| 控制台 | 本轮读取未出现新增 Flutter exception；P1 是无异常的状态错误 |

入口是运行中的 `lib/multi_host_demo.dart`，通过 CUA 点击真实 macOS 窗口。
只读诊断使用已注册的 `ext.ccrouter.snapshot`，没有调用 VM evaluate、执行隐藏导航或
通过测试代码代替真实点击。最后窗口回到双 Host，保留现有 Flutter run 会话。

本轮未重新运行 Flutter/Dart 全量套件，没有修改实现，不沿用旧测试数字充当本轮新
回归；也未声称遍历默认 Demo 全部按钮、重新验证移动端手势或完成长时间 monkey、
性能/内存认证。UI 截图与辅助功能变化可在本次操作记录中查看。
