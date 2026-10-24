# UI Fragment、观察者与 Contract 边界审查

状态更新：本报告保留审查时的失败证据；问题现已修复并纳入默认回归，见
[修复与验证报告](../20261023-shared-lifecycle-contract-fixes/report.md)。

2026-10-23；分支 `codex/managed-navigation-runtime`。
HEAD `09cb21d`；工作树 `managed-navigation-runtime/cc-router`。

本轮没有修改生产实现、Demo 或生成物；新增审查探针、常规 Deep Link 边界测试及报告。
没有提交或推送，也没有回退工作树中已有的修改。

## 结论与问题分析

确认三项 P2 缺陷及一项 P3 不可变性缺口。27 项显式探针中，11 项正常对照通过、
16 项期望契约失败。常规 Flutter/Demo 回归 966 项、Dart/工具测试 55 项全部通过；
这不意味着新增失败探针已通过，也不意味着上轮 P1 待修问题已经解决。

### P2：卸载后保留失效 Fragment Action，会连带保留 State、Props 和消费方 callback owner

位置：`packages/ccrouter_ui/lib/src/ui_fragment.dart:370`，以及 `dispose:388`。

触发条件：Renderer 或其异步工作只保留框架传入的 `input.onAction`，随后 Fragment
正常卸载。该 Action 已不能触发业务回调，但仍强引用 `_FragmentState`，后者通过
`widget` 保留 Props 和消费方 callback owner。`dispose` 只清除 `_generation`，
不能解除这条闭包引用链。

证据：`fragment_lifecycle/repro.dart` 用 WeakReference 观察三类对象。在 helper
完成 mount/unmount、释放局部强引用并执行四轮强制 GC 后，不保留 Action 的对照
三项均已回收；保留 inert Action 时三项均存活。卸载后的 Action 未调用业务回调，
所以这是 `not-GCed`，不是未执行 dispose，也不是卸载后继续执行 Action。

影响：长时间未结束的异步工作或外部回调表会把整组已卸载输入和消费方对象留住，
直到该 Action 被释放。本结论有明确保留条件，不表示所有正常卸载都会泄漏；也没有
以 Widget 测试代替真实设备的进程内存测量。

建议：Action 闭包只持有小型生命周期转发记录；State 在卸载时清除其中可达业务
callback 的引用。保留 latest callback、active、identity 和 generation 检查；
不得让旧 callback 重新指向新实例。B 仍需取消自己的工作，但框架自己的失效转发
闭包不应为此继续保留整个 State。

### P2：观察者取消后同函数重新订阅，会复活旧事件；旧 remover 还能移除新订阅

位置：

- `packages/ccrouter_core/lib/src/navigation_lifecycle.dart:25`；
- `packages/ccrouter_core/lib/src/route_entry.dart:90`；
- `packages/ccrouter_core/lib/src/route_visibility.dart:22`；
- `packages/ccrouter_core/lib/src/navigation_failure.dart:21`；
- 公共队列 `packages/ccrouter_core/lib/src/navigation_callback.dart:165`。

根因：集合和排队快照只有 callback identity，没有 registration identity。remover
按函数删除，投递时只检查集合是否还包含函数，无法区分旧订阅和新订阅。

证据：四类观察者各执行三种时序。单纯 remove、等待队列清空的四个对照通过；
remove 后立刻 re-add 同函数，新订阅收到旧事件，四个失败；旧订阅清空后 re-add，
再次调用旧 remover，新事件不再收到，四个失败。各 probe 均先验证触发事件后尚未
投递，排除了测试时序错误。导航 Listener 的 DartDoc 明确承诺取消 queued deliveries。

影响：订阅在前后台、Session 或页面生命周期切换时重建，可能把旧导航事件当成新
订阅收到的事件；重复 cleanup 又可能静默关闭新的订阅。未证明这会直接造成页面
重复 Pop，不应与历史“双返回”问题混为一谈。

建议：为每次有效订阅保存独立 registration/active identity，队列绑定当时的记录，
remover 幂等且只退休自己的注册。实现时明确同函数同时重复 add 的既有去重语义，
不能顺便改变它。Backend/Capability 观察者若使用同模式，也应纳入修复时的关联
审查；本轮实际复现范围仅是上述四类，不声称六类都已测试。

### P2：已声明支持的单比较器和非空格 whitespace 版本范围会被拒绝

位置：`packages/ccrouter_contracts/lib/src/contract_compatibility.dart:166`。

根因：只有表达式包含 ASCII 空格才进入 comparator parser；单个 `>=1.2.3` 等
表达式和 Tab 分隔的两个比较器被当作 exact SemVer，随后抛 FormatException。
这与文件中 whitespace-separated comparators 的声明及已实现的 `_parseComparator`
能力不一致。

证据：exact、`=exact`、caret、tilde、空格分隔 comparator 五个对照通过。
`>=1.2.3`、`>1.2.3`、`<=1.2.3`、`<1.2.3` 和 `>=1.2.3\t<2.0.0` 五个失败。
另通过合法 UI Host Assembly 验证：`^1.0.0` 成功、`>=1.0.0` 在 attach 阶段失败，
证明影响不限于直接调用 parser。未运行真实生成流程，不声称已经复现完整生成失败。

建议：保留 exact/caret/tilde 等规则，把比较器分支统一按 whitespace tokenize，单个
token 也走 comparator parser。覆盖边界相等、区间不匹配、Tab/换行和非法 token；
不通过删掉已支持语法的文档来掩盖缺陷。

### P3：CCSemVer 暴露可变 preRelease，违背不可变值的约定

位置：`packages/ccrouter_contracts/lib/src/contract_compatibility.dart:59`。

`split('.')` 返回可变 List，直接暴露为 `preRelease`。调用者可以对已解析的
`1.2.3-rc.1` 执行 `preRelease.clear()`，改变 isStable、比较、文本及 hashCode；
与文件声明的 immutable values 不一致。probe 中不可变断言确定失败。

建议：保存不可变副本。该问题需要调用者主动修改公开集合才触发，优先级低于上面
的生命周期和契约解析问题；本轮没有证明正常导航因此出错，也没有声称已实测哈希
集合查找失败。

## 方案取舍与推荐顺序

| 方案 | 收益与代价 | 判断 |
| --- | --- | --- |
| 应用中避免保留 Action、为每次订阅新建不同闭包、统一写 caret | 实施快，但框架缺陷仍在，各接入方重复承担约束 | 仅适合临时规避 |
| 加公开新 API、全局清空观察队列、禁止重新订阅 | 侵入接入层或破坏其他订阅的隔离，不必要地扩大兼容成本 | 不推荐 |
| 私有生命周期转发记录、registration identity、统一 parser 和不可变副本 | 保留外部 API；增加少量内部记录与针对性边界回归 | 推荐 |

建议按以下步骤修复；本轮为 review，只保留证据，没有执行这些生产变更：

1. 优先处理[上轮报告](../20261023-startup-zone-review/report.md)中尚未修复的 P1：
   InitTask 同步重入与跨 error Zone shutdown 卡住；其资源清理/启动正确性影响更高。
2. 修复 Fragment 引用释放与观察者 registration identity。把显式 probes 转入默认
   回归，继续覆盖 latest callback、旧 generation、重复 cleanup 和正常队列顺序。
3. 修复版本解析及 SemVer 不可变性，增加生成侧/Host 侧一致性的正反例。
4. 修复引起开发者可观察语义变化时，同步 README、集成 Skill 和相关 reference，
   再执行全量回归；不要求业务导入内部 Runtime/SPI。

## 为什么多轮审查仍能发现问题

本轮从导航堆栈扩大到 UI 嵌入、观察订阅和静态 Contract 值。以前的成功路径与
一次性取消覆盖，不能证明以下相互独立的性质：

- callback 已失效，不代表 callback 已解除对业务对象的引用；
- callback identity，不等于一次注册的 identity；
- 常见版本表达式通过，不代表声明支持的全部 token/whitespace 组合都通过；
- 字段 final，不代表字段引用的集合不可变。

后续应把“保留旧引用、取消后重建、重复 cleanup、身份更新、失败/取消、跨 Zone”
作为横向不变量矩阵应用到所有能力。继续只按按钮逐个 review，容易重复遗漏共同
机制。当前证据不足以宣称“已经没有问题”或“各方面优于旧架构”。这些生产位置中
被核查的 UI Fragment、版本解析、导航 Listener 文件相对 HEAD 无 diff，因此也不能
把本轮新发现等同于本次 Managed 重构新引入的回归。

## 验证结果与范围

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Fragment GC 探针 | 1 对照通过、1 契约失败 | [repros.log](repros.log) |
| 四类观察者注册探针 | 4 对照通过、8 契约失败 | [repros.log](repros.log) |
| 版本与 UI Assembly 探针 | 6 对照通过、7 契约失败 | [repros.log](repros.log) |
| 新 Deep Link 输入边界矩阵 | 42 通过 | [deep-link.log](deep-link.log) |
| Flutter/Demo 常规回归，含新 42 项 | 966 通过 | [flutter.log](flutter.log) |
| 应用 analytics 与工具测试 | 55 通过 | [dart.log](dart.log) |
| Workspace analyze | No issues found | [analyze.log](analyze.log) |
| 文档检查 | 检查器选择的 121 个 Markdown 通过 | [documentation.log](documentation.log) |
| 新增 Dart 文件格式、git diff --check | 通过 | 命令退出码 0 |

Deep Link 新矩阵覆盖 Platform/Notification/QR 三个来源、UTF-8、编码斜杠及双重
编码、加号、空格、编码分隔符、重复 query。拒绝路径覆盖冒名 host、后缀欺骗、
HTTP、userinfo、错误端口、相对路径及 network-path；验证拒绝前没有栈变更，拒绝
后仍能正常导航。network-path 当前为 CCRouteNotFoundError，其余拒绝样本为
CCDeepLinkIngressRejectedError。没有对 malformed UTF-8 作已确认缺陷声明。

常规回归仍包含已有多 Host/Outlet、目标 close、Shell、Session、revalidation、
Route Service、Command/Event、InitTask、Popup 和预测返回模拟；含重复 iOS swipe
只移除一个 Entry、取消 swipe 保留 identity、Shell swipe 中 shutdown 等已有用例。
它们是自动化模拟结果，本轮没有新增 macOS 真实窗口、iOS/Android 手势、进程
内存或性能验收；没有运行独立 Analyzer Plugin 或 Generator 专项测试。

没有新增 Demo 按钮：现有 Fragment Demo 已含输入更新、隐藏 Tab、账号切换、加载
失败与卸载。GC 可达性、同函数重新订阅、版本 token 是框架边界，确定性 probe 比
人工点击更适合验证；本轮没有缺失的业务展示场景。文档检查器不覆盖本次 untracked
报告，不能把 121 个 Markdown 通过扩大为全部未提交文档检查通过。

## 复现与回归命令

以下显式 probes 不以 `_test.dart` 结尾，避免把已知 review 失败混入常规发现；
非零结果表示期望契约尚未满足，不是修复成功。生产修复后应迁入默认回归。

```sh
fvm flutter test --no-pub \
  packages/ccrouter_test/test/review_repros/fragment_lifecycle/repro.dart \
  packages/ccrouter_test/test/review_repros/observer_registration/repro.dart \
  packages/ccrouter_test/test/review_repros/contract_version_boundaries/repro.dart \
  --reporter expanded
fvm flutter test --no-pub packages/ccrouter_test/test demo/test \
  demo/modules/navigation_lab/test demo/modules/analytics_flutter/test --reporter expanded
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test \
  tool/test --reporter expanded
fvm dart analyze
fvm dart run tool/documentation_check.dart
```
