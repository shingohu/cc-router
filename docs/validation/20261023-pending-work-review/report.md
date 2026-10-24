# 挂起工作与 Host 聚合所有权审查

后续状态：本报告保留修复前的审查证据；三个 P2 已修复，原 27 项及扩展边界已纳入
默认回归。见 [修复、全量回归与本地 main 对比](../20261023-pending-work-fixes/report.md)。

2026-10-23；工作树 `managed-navigation-runtime/cc-router`；分支
`codex/managed-navigation-runtime`，HEAD 基线 `09cb21d`。

本轮为 review；新增独立探针与证据，不修改生产实现、提交或推送。
保留此前工作树修改，未停止已有 watch，未手工修改生成物。

## 已确认的发现

### P2：挂起 initializer 的内部等待在销毁后继续保留 Runtime／Route payload

位置：`packages/ccrouter_core/lib/src/scope.dart:37`、`:68`；
`packages/ccrouter_core/lib/src/runtime_host.dart:2284`、`:2314`。

可复现路径：Service initializer 仅返回测试从外部传入的 Future，不捕获 Runtime、
Scope、页面参数；初始化已经开始后 shutdown。调用者收到
`CCInvocationCancelledError`，Runtime.dispose 已完成，Service.dispose 执行一次。
此时保持外部 Future 未完成，Runtime 的 WeakReference 仍存活；Route 场景的页面参数
也仍存活。完成该 Future 后二者可以回收。App／Session／Route × singleton／
newInstance 六种组合均复现。相同组合先完成初始化、再 shutdown 的六种正常对照均通过。

这是 **not-GCed**，不是没有执行 dispose，也不是任意 Dart 工作无法被强行停止的问题。
上一轮消除了 Zone value 的直接强引用；这里保留的是框架 readiness 的挂起等待和
回调闭包路径。`_ServiceReadinessRecord.start` 在 token 取消时只 deactivate 和清除
依赖边，`_completion` 仍等到原始 initializer 返回才 settle；无 initializer owner 的
`waitFor` 直接等待该 completion。`_resolveReady` 等待及 initializer 包装又保留
Runtime／精确 RouteEntry 等框架上下文。这些对象不应仅因第三方 Future 不返回而
一直保留。

建议在实际拥有者终结时 settle readiness，同时把遗留 initializer continuation
限制为不拥有 Runtime／Scope／Entry 的小记录。二者需要一起检查，不能只让外层
Future 先取消，或清空调用链的生命周期 token。保留共享 singleton 不受单个 waiter
取消影响、新实例调用者归属、旧 Session fence、失败 identity/stack 和 late-error
消费语义。

### P2：挂起 Event Subscriber 在 Event 取消和 Runtime 销毁后仍保留 Runtime

位置：`packages/ccrouter_core/lib/src/runtime_host.dart:1736`、`:1741`。

Subscriber 只返回外部 gate Future；既不保存 InvocationContext，也不捕获 Runtime。
开始发布后 shutdown，Event 调用正常取消、Runtime 正常完成清理，但 Runtime 仍不可
GC。释放 subscriber Future 后 Runtime 可以 GC。legacy、typed subscriber 和
generated Event 调用三种入口均复现；各自先完成 Subscriber 再 shutdown 的对照通过。

同样的挂起条件下，Command、普通 App Service method、InitTask 的 Runtime GC 均通过，
因此不能泛化为所有异步业务工作都会保留 Runtime。

分类为 **not-GCed**。Event fan-out 的异步 map／嵌套 subscriber 包装位于访问
`_invoke`、`_recordSubscriberError` 等 Runtime 实例成员的闭包环境中。原始 Subscriber
Future 的 listener 保留这个框架 continuation；外层取消并不会销毁它。

建议把用户 Subscriber 的 await／late completion 包装移到不拥有 Runtime 的私有
执行记录或独立 helper，仅让仍在进行的框架 fan-out 持有 Runtime。不能通过取消
时不再消费失败，或简单增加 timeout 并启动新 Subscriber，掩盖该保留路径。
修复后需要继续验证 Subscriber 错误隔离、Event 总 deadline、嵌套调用 cancellation
lineage、generated identity 和 Trace 一致性。

### P2：MultiHost 构造器允许两个 Host 共同拥有一个 Adapter

位置：`packages/ccrouter/lib/src/multi_host.dart:56`。

动态 `registerHost` 会检查 Adapter identity，拒绝复用一个已拥有的实例；构造器
循环只验证 Host ID／可选 Host binding，直接为每一项创建所有权 record。
将同一个不实现可选 HostBinding 的自定义 Adapter 放在 left、right 两项中会被接受。
两个 record 各自宣称独占所有权，aggregate.dispose 对同一 Adapter 调用两次 dispose；
初始化也可能执行两次，detach 一项可能结束另一项仍使用的 Adapter。

探针确认重复配置被接受且清理次数为 2。独立子 Adapter 构造、单独 unregister 后最终
dispose，以及动态重复注册拒绝且不提前 dispose 的两个正常对照通过。
这是自定义／兼容 Adapter 的构造入口缺陷；不能据此宣称使用强制 HostBinding 的
两个原生 Managed Host 会共享同一个 Adapter。

建议先对全部初始 Adapter 做 identity 唯一性和 Host binding 校验，全部通过后再
创建 ownership record。拒绝输入不应销毁尚未接管的调用方 Adapter；不要用最终
dispose 去重代替唯一所有权校验，否则初始化、绑定和 detach 仍有冲突。

## 方案取舍与推荐顺序

| 方案 | 收益 | 代价／限制 |
| --- | --- | --- |
| 只要求业务取消第三方 Future | 可减少未完成工作 | 不解除框架闭包持有；Future 本身通常不能强行取消 |
| 只给等待增加 timeout／立即清空 ownership | 实现表面简单 | timeout 仍保留底层 listener；清空 ownership 会破坏旧调用链 fence |
| 私有执行记录与拥有者终态结算 | 不新增业务 API，修复框架保留路径 | 必须保持 singleton／新实例、跨 error Zone、late-error 和 Trace 语义 |
| 仅在 dispose 对重复 Adapter 去重 | 可减少重复清理 | 仍有重复初始化、绑定和 Host detach 冲突 |
| 构造前完整 identity 预检 | 与动态注册契约一致，拒绝前无所有权变更 | 需加入构造失败及正常自定义 Adapter 对照 |

推荐顺序：

1. 修 readiness 的 owner 取消结算和非拥有闭包，先把六组生命周期组合转成默认回归。
2. 修 Event Subscriber await 的 Runtime 捕获，覆盖三种入口与正常／取消／late error。
3. 补 MultiHost 构造器 identity 预检，验证失败不接管、成功只初始化／销毁一次。
4. 全量回归，并在更改实际错误／生命周期行为时同步 README、集成 Skill 和 reference。

以上可作为兼容的内部修复独立回退，不需要增加公开 API、永久监听或重新引入 GoRouter。

## 实际验证

| 检查 | 本轮结果 | 证据 |
| --- | --- | --- |
| 框架、Demo、导航、analytics Flutter、支付、存储、Order example 全量 | 1327 通过 | [flutter.log](flutter.log) |
| analytics／Firebase／tool Dart suite | 55 通过 | [dart.log](dart.log) |
| 扩展 ownership 探针 | 27 项：17 通过、10 失败，对应上述 3 个 P2 | [probes.log](probes.log) |
| Workspace analyze | No issues found | [analyze.log](analyze.log) |
| Demo generation freshness | 复用有效 watch cycle 108；up to date | [generation.log](generation.log) |
| 文档检查 | 检查器选择的 121 份 Markdown 通过 | [documentation.log](documentation.log) |
| 差异检查 | `git diff --check` 通过 | 当前工作树 |

探针源文件位于 `packages/ccrouter_test/test/review_repros/pending_work_retention/`，
没有使用 `_test.dart` 后缀，故默认全量 1327 通过不包含上述未修复探针。
所有 GC 测试都在工作已经开始后终结拥有者，使用 WeakReference + forceGC 三轮，
并在释放外部 gate 后重复 GC 校验。页面 payload 的 WeakReference 解引用在独立的
同步、禁止内联 helper 中执行，避免测试自身的 nullable 临时变量跨 await 强持有它。
最初 fixture 尝试从 Runtime 直接注册 Route Service 被正确拒绝，已改为组件 Registrar；
这是无效探针输入，不计入产品失败。表格是更正后的有效结果。

重新执行探针：

```sh
fvm flutter test --no-pub \
  packages/ccrouter_test/test/review_repros/pending_work_retention/repro.dart \
  packages/ccrouter_test/test/review_repros/pending_work_retention/message_retention.dart \
  packages/ccrouter_test/test/review_repros/pending_work_retention/multi_host_constructor.dart \
  --reporter expanded
```

## 场景范围、Demo 与剩余边界

这次复查了导航入口、RouteInformation 取消、MultiHost 构造／动态注册／detach、
revalidation 序列化、Session／Scope cleanup、Service readiness、Command／Event／
InitTask 及 Zone ownership。默认全量同时重跑已有 parent-stack、Shell／多 Outlet、
foreign popup、精确 close、预测返回、iOS 取消与退出渲染、Host remount 等测试。
不能将这些自动化结果写成新的真机或 macOS 实窗验收。

没有增加 Demo 页面：本轮确认的是框架挂起闭包保留及非法自定义 Host 配置，
正常 Demo 已有 Service 生命周期、Event／Command／InitTask、动态 Host 入口。
把永不返回的 Future 或无效重复 Adapter 包装成推荐 Demo 用法会误导接入；应先修复并
落实确定性回归。若后续需要教学示例，应使用可取消的业务操作和明确拥有者。

反复发现问题的具体原因是测试矩阵尚未完整覆盖：上一轮主要验证“方法已返回、Zone／
无关 Future 仍存在”，本轮补的是“框架已取消、业务 Future 仍未返回”。同时构造入口
未复用动态注册的唯一所有权检查。后续评审需交叉检查这两类挂起状态和所有接入入口，
而不是把默认 suite 通过或 dispose 一次视为内存／生命周期完整性的证明。

本轮未新增平台真机、macOS 实窗、长期 monkey、进程 heap／吞吐基准；未改或全量验证
独立 Analyzer Plugin／Generator 生产代码。A → B → A 多 Runtime 候选契约仍不在本轮
产品缺陷结论内。未发现新的已证实 P1，也不声称所有场景均无问题。
