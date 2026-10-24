# Managed 重构功能对齐审查（2026-10-22）

## 结论与范围

初审确认 6 类行为在当前 GoRouter 兼容路径通过、Managed 路径失败，另发现 1 类 Managed
exact-close 契约缺陷。随后已按建议顺序修复 F1–F7，并将失败探针迁入正式默认回归。
下文保留原始发现及失败证据，当前修复结果见文末；不能据自动化通过宣称所有平台、性能和
内存都已优于旧架构。跨不同 Shell 的 push 返回在初审时两条路径共同失败；后续全量审查已修复
Managed 路径，最新能力矩阵和实窗证据见[全量审查记录](managed_full_review_20261022.md)。

源码比较基线为原生 Managed 引入前的 `9af16ed`，审查对象是
`codex/managed-navigation-runtime` 的当前提交与全部未提交生产改动。行为 A/B 使用当前
保留的 GoRouter Demo 和 Managed Demo；没有把重构前提交完整部署到真机，也没有将两条
当前路径共同失败的场景直接判为重构引入。

最初审查只添加探针与记录；后续修复修改 Managed/Core 和 Host SPI，保留业务调用 API 与
GoRouter A/B 入口，不修改冻结的 GoRouter 生产实现。未提交或推送 Git。

## 确认问题（按优先级）

### F1 · P1 · exact close 会撤掉仍有覆盖页面的 Shell

- 位置：`packages/ccrouter/lib/src/managed_router.dart:1093`。
- 复现：Go 到 Workspace Home；从 Home 的 Context 打开 `/lab/stack/101`；捕获的 Home
  handle 执行 close。close 返回 `closed`，Stack 101 仍在 `activeRouteEntries`，但界面上消失。
- 原因：通用目标通过 Context 只取得 Host/Outlet，没有显式 Shell ID。`_removeEntry`
  只按剩余请求的 `placement.shellId` 判定 Shell 是否还有页面，忽略它的 Outlet 内仍有
  活跃 Entry，因此清掉 Shell anchor。
- 影响：违反“只移除指定 identity、覆盖页面保留”的核心价值；留下活跃但不可达的页面。
- 建议：根据结构化 Shell/Outlet 所有权决定容器存活，不能只检查页面声明是否携带 Shell ID。
  回归同时断言 covering Page 可见、Entry identity、结果通道和 Scope 均保持。
- 分类：Managed 新能力契约缺陷；未声称旧 GoRouter 支持这一 exact-close 场景。

### F2 · P1 · 冷启动子路由没有父页面返回链

- 位置：`packages/ccrouter/lib/src/managed_router.dart:1039`。
- 复现：以 `/workspace/home/42` 作为初始地址；Managed 展示详情，但该 Outlet 的
  `canPop(context: ...)` 为 false，无法返回 Workspace Home。GoRouter 同场景通过。
- 原因：`parentRouteId` 虽被保存在 request 中，建栈时只加入叶子 Entry，未解析/建立父链。
- 影响：Demo 声明的可 Deep Link 嵌套详情失去原有返回路径；go、browser route-information
  等同类入口也需要按同一个父链规则验证。
- 建议：定义并执行经过验证的父链建栈计划，明确父页面参数、policy、结果与 Scope 所有权；
  对确实无法重建的祖先给出明确配置诊断，不能静默建立残缺栈。

### F3 · P1 · 默认便捷接入忽略平台启动地址

- 位置：`packages/ccrouter/lib/src/managed_router.dart:181`。
- 复现：平台 `defaultRouteName` 为 `/workspace/home/42`，采用默认 Demo/Host 配置启动；
  GoRouter 进入详情，Managed 进入 `/`。
- 原因：Managed 将默认的非 null `initialLocation = '/'` 无条件优先于平台地址；只有显式
  传 null 才读取平台地址，便捷 App 和 Demo factory 又默认使用 `/`。
- 影响：沿用旧默认配置迁移后，平台启动链接被吞掉；Web 首次地址同样依赖这个入口。
- 建议：区分启动 fallback 与强制覆盖平台地址，保证默认迁移语义；采用平台地址时必须保持
  external origin 与 ingress policy，不能为对齐而将外部地址标成 trusted。

### F4 · P1 · foreign Dialog 被底下页面的 PopGuard 拦住

- 位置：`packages/ccrouter/lib/src/managed_router.dart:812`、`:2240`。
- 复现：打开未保存的 guarded 页面；通过 Flutter `showDialog` 显示普通弹窗；调用
  `CCRouter.navigator.maybePopOutcome()`。GoRouter 关闭弹窗；Managed 返回
  `guardDeniedCode = demo_unsaved_form`，弹窗仍在。
- 同源证据：普通未 guarded 页面被 foreign Dialog 覆盖后，GoRouter Runtime Entry 变 hidden，
  Managed 仍是 visible。
- 原因：观察器只向 Flutter PageLifecycle bridge 报 top，没有向 Runtime 发布 foreign
  ownership/top 变化；`activePopTarget` 遇到非 managed top 又回退到底下 managed Entry。
- 影响：破坏既有弹窗返回语义，并使 Runtime visibility/Aspect/诊断与实际界面不一致。
- 建议：补全 live foreign route 的身份、top、push/pop/remove 观察，guard 针对真实将被移除的
  Route；保留 payload-free 历史和 live Route 的清理边界。

### F5 · P2 · 直接切换 Shell 分支没有同步 Runtime 可见性

- 位置：`packages/ccrouter/lib/src/managed_router.dart:1129`。
- 复现：进入 Workspace Home 详情，再直接调用 `go(demoWorkspaceActivityIntent())`。
  两条路径都展示 Activity；GoRouter 将保留的 Home detail 标成 hidden，Managed 仍标 visible。
- 原因：Store 改了 active/visible Outlet，但 `_notifyStateListeners` 只更新 Flutter bridge；
  该事务没有把分区切换事件同步给 Runtime。通过 Demo Tab 按钮调用 `activateOutlet` 则会
  单独发事件，因而掩盖直接业务导航路径的问题。
- 影响：PageLifecycle 与 Runtime/Navigation Aspect 形成两套状态，停留时长及曝光观察不可靠。
- 建议：每次结构状态提交都从同一个可见性计划发布 Runtime 与 Flutter 观察，覆盖直接
  go/push/open、Tab 切换及 root 覆盖/揭示路径，不依赖额外 UI 激活调用。

### F6 · P2 · 切回已保留分支时 URL 仍指向别的分支

- 位置：`packages/ccrouter/lib/src/managed_router.dart:448`。
- 复现：Home 详情 → Activity → Home；Managed 屏幕显示 Home 详情，但
  `routerDelegate.currentConfiguration.uri.path` 仍为 `/workspace/activity`。
  GoRouter 对比返回 Home 分支地址。
- 原因：`_currentUri` 使用整个列表最后一次插入的请求，忽略当前 Shell branch/root overlay。
- 影响：URL 与当前分支不一致，复制链接、刷新和后续浏览器导航可能进入错误页面。
- 建议：按明确的 location owner 投影当前地址，与焦点回退目标和实际可见层级区分；不要
  简单改成“最后获取焦点的 Outlet”来解决全部场景。
- 比较标准没有要求 GoRouter 把 imperative push 写入 URL；仅要求地址属于实际选中的分支。

### F7 · P2 · mounted Shell 在 shutdown 中重建抛异常

- 位置：`packages/ccrouter/lib/src/managed_router.dart:1621`、`:1915`。
- 复现：保留 mounted 的 Workspace Shell，await `CCRouterHost.shutdown()` 后 pump。
  GoRouter 无异常；Managed 抛 `Null check operator used on a null value`。
- 原因：Adapter 先清空 `_shells`，再通知仍 mounted 的 Shell surface；后者 build 强制读取
  已被清掉的 Shell metadata，退出动画期间仍可能发生此重建。
- 影响：正常 Host 清理不能保持无异常；影响重启和错误诊断。
- 建议：协调 teardown 通知和渲染所有权，让退休中的 surface 可以安全完成 unmount；不要
  通过吞掉 FlutterError 掩盖结构状态被提前释放的问题。

## 功能矩阵与证据边界

| 能力 | 当前审查结果 | 证据/限制 |
| --- | --- | --- |
| typed Intent、参数/Codec/Extra/result | 既有回归通过 | Framework 及两 Backend Demo matrix；未证明所有业务 DTO |
| push/replace/go/reset、exact identity close | F1 修复，正式回归通过 | 覆盖页 identity/result/Scope 保留，种子 Scope once-only |
| Alias、Regex、约束匹配 | 既有回归通过 | Managed 使用 Runtime 解析的 `pathParameters`，没有重新匹配 primary |
| nested parent/Deep Link 返回链 | F2 修复，正式回归通过 | 参数、策略、取消与独立 Scope；不含完整恢复 |
| 平台启动位置、Web 初始入口 | F3 修复，正式回归通过 | external origin/deny/显式覆盖；Web 真浏览器尚未验收 |
| 运行中 external ingress/权限校验 | 既有回归通过 | Deep Link/Facade/Demo tests；不抵消启动地址缺陷 |
| Interceptor/redirect/defer/resume/Failure Policy | 既有回归通过 | Core + shared Demo matrix；重定向 placement fence 已有测试 |
| PopGuard、PopScope、LocalHistory | F4 修复，正式回归通过 | 新增 nested Context/非 active Host popup owner；既有平台 fixture 仍有 GoRouter |
| Dialog/BottomSheet/透明页/自定义转场 | shared Demo matrix 通过 | 渲染、普通关闭不是全部 ownership 组合 |
| Shell branch 保留及本地 Widget State | F5 修复，正式回归通过 | Tab 与直接业务导航 visibility 一致 |
| Shell 当前地址与浏览器投影 | F6 修复，正式回归通过 | 包括独立 pane URL；非真实浏览器 History e2e |
| MultiHost/context 隔离 | 既有回归通过 | 左右页、语义激活绕过焦点、精确 close/revalidation |
| adaptive 宽窄/hinge 布局 | 初审只证明本地视图；后续已迁移 Managed Outlet | 全量审查完成真实宽窄切换、Managed覆盖页保留和返回；本地选中项由Demo拥有 |
| Route Scope/Service/Session 清理 | F7 修复，正式回归通过 | mounted Shell/popup/进行中侧滑 shutdown；未做 heap 实测 |
| iOS 单次侧滑与取消 | 补充 Widget 探针通过 | 两 Backend 各连续 8 轮提交只移除一层；取消保持 Entry identity |
| Android Predictive Back | 既有自动化回归通过 | Managed duplicate terminal/结果与 Scope 清理覆盖；未重做本轮真机手势 |
| Command/Event/InitTask/组件依赖 | 既有回归通过，生产实现无重构差异 | Runtime shutdown 顺序是本次相关共享边界 |
| UI Fragment/诊断/Analytics/DevTools | 基础回归通过 | F4/F5 可影响页面可见性下游；不能因此宣称 Analytics 全面对齐 |
| API 分层/Host SPI 隔离 | 自动 API surface 与 analyze 通过 | 旧 Adapter revalidation replace 需要 receipt，正常导航仍兼容 |
| Generator/Portable/Hook | 本轮无生产差异 | 复用上一轮 645 通过、1 网络 smoke 跳过的证据；没有重复执行 |
| Analyzer Plugin | 独立目录 analyze、173 项测试通过 | 不等于 Demo IDE 加载了新 Plugin，本轮没有改 Pin |
| 完整状态恢复/Navigator 1 Backend | 原来就未承诺完整支持 | 不计作本次新增退化，也不能宣称已补齐 |
| 内存/性能优于旧架构 | 尚不能证明 | 本轮无同设备、同负载 A/B benchmark 或 heap 实测 |

附加场景的初审结果：跨两个不同 Shell 的 push 后 maybePop 返回原 Shell，两条 Backend
路径均失败；未计入已确认重构退化。后续全量审查已在 Managed 保留多 Shell anchor并正确返回，
Widget回归与macOS实窗验证通过；GoRouter冻结生产实现未改，不机械复制其失败行为。

## 初审执行结果（修复前）

- `fvm flutter test --no-pub packages/ccrouter_test/test --reporter expanded`：659 通过。
- `fvm flutter test --no-pub demo/test --reporter expanded`：77 通过。
- `fvm dart test -r expanded`（工作目录 `packages/ccrouter_analyzer_plugin/`）：173 通过。
- root 与 isolated Plugin `fvm dart analyze`：通过。
- 补充探针 `fvm flutter test --no-pub demo/test/review_managed_parity_probe.dart
  --reporter expanded`：23 项中 13 通过、10 失败。
  其中 7 个 A/B 场景是 GoRouter 通过而 Managed 失败（foreign 两个断言归为 F4）；1 个
  Managed-only close 场景失败（F1）；另外 2 个失败来自两条路径共同失败的跨 Shell 场景。
- close 的活跃 Entry 保留/页面消失已通过独立 focused run 再次确认。

当时探针故意不使用 `_test.dart` 后缀，作为显式执行的失败复现。现已迁入
`demo/test/managed_parity_regression_test.dart`，默认 suite 自动执行确认缺陷的回归；
跨不同 Shell 的两 Backend 共同失败场景独立保留在本报告的待定项，不计入修复通过数量。
日志位于 `/tmp/ccrouter-parity-review-{framework,demo,plugin,probe,close}.log`。

## 方案取舍与建议顺序

1. 只改 Demo 焦点/按钮或在 probe 中改期望，成本低，但会把缺陷转移到调用者，不能达到
   迁移条件。不采用。
2. 直接恢复旧 GoRouter 为唯一实现，短期减少部分差异，但重新引入旧 close 的 match-tree
   限制，且无法满足长期去 GoRouter 的目标。不建议作为架构方案。
3. 推荐保留当前 A/B 入口，在 Managed 内补齐结构状态契约；无需先扩张业务公共 API。
   成本高于逐项 UI 补丁，但能统一修复返回路径、容器存活、location 与 visibility 投影。

具体顺序：

1. 先修 F1/F2：明确父链与 Shell/Outlet 所有权，exact removal 不得让其它 Entry 丢失渲染。
2. 修 F3：确定平台地址/Host fallback 的兼容规则，并保留外部 ingress 安全边界。
3. 合并处理 F4/F5/F6：由同一结构状态提交派生真实 top owner、活动分支、Runtime visibility
   和 location；保留 foreign Route 的独立生命周期。
4. 修 F7：增加 mounted Shell/分支/Popup/手势进行中的 shutdown 组合，保证 teardown 无异常。
5. 将本轮失败探针纳入正式矩阵，同一行为在两 Backend 下验证；对明确增强/受限能力分别
   断言成功或明确拒绝，不机械复制旧缺陷。
6. 矩阵通过后再验收真实 macOS 窗口、iOS 连续取消/提交及 Android Predictive Back；性能和
   内存以同设备同场景 A/B 单独证明。在这些证据齐全前，不宣称“全面更优”。

## 修复实现与验证（2026-10-22）

1. F1：按实际 Shell Outlet 所有权决定容器存活及分支是否已有 Entry。Context 产生的通用
   覆盖页不需要伪造 Shell 声明；关闭种子只释放其 Scope，覆盖页结果继续等待。
2. F2：新增可选 Host SPI `CCNavigationParentStackAdapter`，Runtime 在 declarative
   Go/Reset/Open-Go（含启动和浏览器入口）预先重建并校验祖先 Codec/Path/Query，运行祖先到
   目标的策略后一次提交。取消、缺参数、需要 Extra 不改原栈；redirect 丢弃旧计划，defer
   重跑原叶子。祖先各自拥有 Entry/Scope；保留的叶子不持有祖先计划和参数。
   普通 push/replace 保留原栈，不自动生成祖先。GoRouter 不加入新 SPI。
3. F3：`initialLocation` 改为可信 fallback，平台非根地址默认优先，且保持 external origin。
   Host 可显式 `overridePlatformDefaultLocation: true`。Demo 自定义 Factory 透传配置。
4. F4：Navigator 观察器发布 live foreign identity/top/remove，不创建 Managed Scope。
   `CCNavigationPopTarget.owner` 和可选 `CCNavigationScopedPopTargetSource` 支持事件尚未投递、
   nested Context、非 active Host 的真实所有权；旧 Adapter 不实现时保持原回退规则。
   不把旧 Backend 的结构占位 Entry 当成 popup，也不把 Flutter Route 或参数留入历史。
5. F5/F6：同一结构状态派生 Flutter/Runtime 活动 Outlet，top 由 Navigator 实际确认；
   location 按当前 Shell 分支/root overlay/独立 pane 的导航状态投影，不跟随指针焦点。
   Predictive Back 使用同一个真实 Back 分区；root 覆盖页刚被移除、焦点尚未恢复时，也能
   立即识别已揭示的 Shell Outlet。新增断言先证明旧焦点回调仍误指 root，再修正桥的投影。
6. F7：退出中的 mounted Shell 在 Store retired 后安全结束渲染，不再读取已清空 metadata。
   popup 和进行中的 iOS edge swipe shutdown 均有正式回归，不吞 FlutterError。

验证记录：

- Framework：`fvm flutter test --no-pub packages/ccrouter_test/test --reporter expanded`，672 通过。
- Demo：`fvm flutter test --no-pub demo/test --reporter expanded`，108 通过，含 shared feature
  matrix、31 项正式 parity regression、现有 semantic monkey。
- Generator 路由与 API 边界专项：`route_generator_test.dart`、`route_api_boundary_test.dart`，89 通过。
- root 和 Demo 的 `fvm dart analyze` 均通过；Host `generate demo --no-cache --check` 通过，
  校验 11 个 generated Packages、6 个 Components、34 个 Routes。生成物未手改。
- API surface 负向编译验证隔离两个新增 Host SPI；本轮没有修改 Analyzer Plugin 生产代码，
  没有更新 Demo Plugin Pin，也不把上一轮 173 项 Plugin 结果写成本轮重新执行。
- `git diff --check` 与误删检查通过。日志位于 `/tmp/ccrouter-parity-fix-*.log`。

此前反复 review 发现问题的主要原因是回归场景覆盖不足：基础 happy path 通过，不能证明
Runtime Entry、真实 Route、Shell 容器、Scope、visibility 和 URL 在组合场景中一致。
此次将这些跨层约束落实为默认运行的测试，并保留失败前的 A/B 证据；不能用测试数量证明
完整性，也不能继续用默认 suite 之外的临时探针作为最终质量门槛。

以上为F1–F7修复阶段证据。后续已完成macOS默认/多Host真实窗口、跨Shell返回修复、
Adaptive Managed迁移和缺失Demo入口补充，最新Framework673项、Demo123项通过，见
[全量审查与macOS验收](managed_full_review_20261022.md)。Android/iOS真机手势、Web history e2e
及同设备性能/heap A/B仍未在本轮重复，不据此宣称所有功能全面对齐或整体优于旧架构。
