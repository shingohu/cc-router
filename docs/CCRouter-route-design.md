# CCRouter Managed 路由架构与混合导航规范

本文统一维护原生 Managed 的所有权、栈操作、Host/Outlet 与混合导航边界。当前实现不依赖 GoRouter，不提供 GoRouter attach；旧总设计和混合导航阶段方案保留于[归档索引](archive/20261024-consolidation/README.md)。首次接入按[接入指南](../skills/ccrouter-integration-development/references/first-integration.md)完成最小闭环；具体生成语法见[Route Contract](CCRouter-route-contract-design.md)和[注解校验](CCRouter-annotation-validation.md)。

## 1. 所有权与 API 分层

CCRouter 自有 Managed Stack 是导航事实来源，Flutter `RouterDelegate + Navigator.pages` 是渲染投影。Runtime 负责契约解析、策略、Entry identity、结果与 Scope；Managed Backend 负责 RouterConfig、各 Outlet 页面投影和 Flutter Route 的精确关联。业务不得修改后端页面列表或 Flutter 内部 match tree。

| 调用方 | 入口与职责 |
| --- | --- |
| 业务组件 | `ccrouter.dart`、自身生成 Client/Intent、公开 contracts；导航使用 `CCRouter.navigator` 或 `CCRouter.navigatorOf(context)` 返回的 `CCNavigator` |
| Composition Root | `ccrouter_host.dart`；Assembly、初始化/关闭、Backend、Shell、全局策略和外部 ingress |
| 自定义 Backend | Host-only Adapter SPI；明确声明可选能力，执行 Runtime 已校验请求 |
| 生成代码 | Generated SPI；业务不能手写身份或通过 SPI 绕过依赖 |

默认 Runtime 由应用 Composition Root 创建和关闭；导航 Host 的卸载不等于 Runtime shutdown。Session 的业务操作与 Runtime 生命周期分开。跨组件页面通过 Route Contract 协作，不导入目标页面实现。测试使用真实测试 Host/Backend，不为方便让业务访问 Core Runtime。

## 2. Host 接入与渐进迁移

新应用在初始化同一个 Assembly 后使用便捷入口：

```dart
import 'package:flutter/material.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'ccrouter_host.dart'; // 当前 Host 的稳定生成 barrel

void main() {
  CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
  runApp(const CCManagedRouterApp());
}
```

示例中的生成 barrel 路径以本工程输出为准。该 Widget 从初始化时的 Catalog 创建 Managed Backend，组合 `CCRouterApp.managed` 和 `MaterialApp.router`；不隐式初始化或关闭 Runtime。主题、国际化等非路由参数可以直接配置，路由配置由 Backend 唯一拥有。

复杂 Shell 使用一次性的 `backendFactory`；高级 Host 可直接组合 `CCManagedRouterBackend`、`CCRouterApp.managed` 与 `MaterialApp.router(routerConfig: backend.routerConfig)`。Catalog 必须来自同一 Assembly，不在业务门面开放覆盖。挂载后 Backend 构造输入不可原地替换；拓扑变化要明确重建其 Owner。

已有应用可以在局部功能区挂载 `CCManagedOutlet`，逐步迁移页面，保留外围 Navigator。Managed 页面始终经 CCRouter 操作；普通局部 Dialog/BottomSheet 可继续使用 Flutter API。当前没有接管任意外部 Router 的通用 attach，也没有 Navigator 1.0 Backend。

`initialLocation` 默认是可信 Host fallback `/`；平台非根启动地址优先，按外部入口校验。显式 `overridePlatformDefaultLocation: true` 才忽略平台启动链接；`initialLocation: null` 始终读取平台 URI 为外部输入。自定义 Factory 必须传递这两个字段。辅助 Host 的固定首页应显式强制 fallback，避免再次消费主 Host 的平台链接。

## 3. 路由身份、地址与参数

Route ID 是稳定能力身份，Pattern 是地址匹配/生成规则，RouteEntry 是一次实际打开的实例。同一 Route ID 可以有多个 Entry；不能用路由名、当前栈顶或相同 URI 代替实例 identity。

支持 Path、完整 URL、custom scheme、多 Pattern alias 和只匹配的 Regex。Path/Query 由对应 Codec 校验与转换，Query 支持标量、enum、集合及自定义 Codec，具体限制以注解规范为准。Regex 兼容入口不保证反向生成。typed Intent 的参数与 Pop 结果由生成 API 约束。

不要先对完整 URI 字符串做 decode，再匹配；Path segment 与 Query 在结构层处理。外部可分享字段放 Path/Query；`@CCExtraParam` 仅传进程内强类型对象，不用于 Deep Link、跨进程或恢复，不写入诊断。参数类型错误使用脱敏的标准错误，不输出原对象。

## 4. 导航操作

| 操作 | 栈与完成语义 |
| --- | --- |
| `push` | 新增 Entry；Future 等待该 Entry 的 typed Pop 结果 |
| `replace` | 替换当前 Managed Entry；等待替换页的结果，不是任意位置替换 |
| `go` | 按目标 location 重建声明式栈与父链；不提供 typed Pop 结果 |
| `reset` | 明确重设根位置，并按声明重建必要父链 |
| `open` | 动态 URI；默认 push，可选 Go；后端接受即完成，无 typed Pop 结果 |
| `maybePop` | 尊重框架 Guard、实际 Flutter Route/PopScope、LocalHistory 与 foreign Popup |
| `pop` | 业务显式返回；先校验结果类型，错误类型不移除页面 |
| `canPop` | 查询当前目标的可返回状态，不预先执行 Pop |
| `close` | 按 handle 精确关闭实例；独立结果状态与 Guard 规则见[精确关闭](CCRouter-targeted-close-design.md) |

`go/reset` 是声明式位置切换，不能当成“逐页执行 maybePop”。需要权限失效后逐页重校验，使用[路由重验证](CCRouter-route-revalidation-design.md)。不要用多个操作拼出并声称具有事务保证的 `pushAndRemoveUntil`；原子组合栈和任意位置 replace 尚未提供。

同一个实际 Route 同时只接受一项未完成的 Managed `maybePop`；重复请求被消费，不排队回退下一页，不覆盖结果。不同 Outlet 独立返回；等待中 push、close、卸载或 shutdown 不能把别的操作的移除归给旧请求。

## 5. Host、Outlet、Shell 与调用点定位

一个 Host 表示独立导航树，不等于原生 Window。大屏左右分栏、Bottom Tab、自适应布局通常用一个 Host 的多个 Outlet；确有独立 Router surface 时才使用 `CCManagedMultiHostBackend.managed`。

Composition Root 通过 `CCManagedShellBinding`、`CCManagedOutlet` 显式声明拓扑。每个命名 Outlet 只能归属一个 Shell，不能使用保留的 `root`；同一 Outlet 的 Navigator Key 只挂载一次。生成器不猜布局或 Tab。

业务 `push/replace/go/reset/open/pop/maybePop/canPop` 可传调用点 `context`。框架同步解析稳定 Host/Outlet ID，不保存 BuildContext；解析失败报错，不猜另一个 pane。目标显式声明的 Host/Placement 保持权威，Context 不把 Shell/parent 强制改成 root。

同一组件反复导航时，使用 `CCRouter.navigatorOf(context)` 获取绑定当前 Host/Outlet 的
`CCNavigator`，后续调用无需重复传 Context；所有操作仍经过同一 Runtime 管线。
在目标 Navigator 内的 build、didChangeDependencies 或交互回调中获取，不在 initState 获取。
对象不保存 Context、Navigator 或 Runtime，无须 dispose；组件移动到其他 Host/Outlet 后重新获取。
显式目的 placement 仍优先，`pop` 仍返回绑定区域，`close` 仍按 handle 精确定位。
若另传 per-call Context，必须解析到相同 Host/Outlet，否则同步抛出
`CCNavigationOutletResolutionError`，不会重新绑定。

绑定对象属于原 Host 注册轮次。Host 注销或 Runtime 关闭后，全部操作同步抛出
`CCRouteCancelledError`（`code == 'host_detached'`）；同名 Host 或 Runtime 重建不能复活旧对象。
页面退出或 Outlet renderer 卸载本身不会使其失效，它不代替页面异步任务取消。
具体用法与入口选择见 [README](../README.md#buildcontext-与-outlet)。

使用未绑定的 `CCRouter.navigator` 且不传 Context 时，使用调用开始时的 active Host fallback。Host 的 Pointer/Focus 接入可调用 `activateHost` 更新默认目标；一次操作已固定的归属不会因异步拦截、redirect、recovery、defer/resume 期间焦点改变而漂移。原 Host 退役则取消，不把旧请求转给同名 replacement。

同名 Host 重开属于新的注册轮次；聚合 backend Entry ID 是不透明身份，不能与子后端原始 ID 混用。聚合器不负责原生窗口创建、Flutter View 映射或平台关闭手势。动态注册、注销、shutdown 和异步等待的边界按[接入模式](../skills/ccrouter-integration-development/references/implementation-patterns.md#multiple-hosts-and-shells)执行。

Shell 支持保留分支与跨 Shell push。返回先处理当前选中 Outlet，再在允许时退出外层 Shell 揭示来路；同一 Shell 重入复用保留容器，不创建第二套 Outlet Navigator。分支激活更新 URL；独立 pane 焦点只改变默认 Back 目标。关闭被覆盖的种子 Entry 不撤掉仍被其他 Entry 使用的 Shell。

应用决定 breakpoints、折痕和可见 pane。在 Host 边界调用 `setActiveOutlets(hostId: ..., outlets: ...)` 同步可见性；它不激活 Host、不导航、不删除 Entry 或 Scope。输入必须非空、唯一、非空白，无效输入不改变状态。

独立 pane 的本地底层 UI 可用 `CCManagedOutlet(baseBuilder: ...)`；该 surface 没有 Managed Entry、结果或 Route Scope。从它的 Context push 仍进入同一 Outlet；需要 Route Service 的页面应声明为 Managed Route。

## 6. 父链重建与外部入口

Managed Go/Reset/Open-Go、启动和浏览器位置变化，按 `parentRouteId` 先构建祖先到叶子的完整计划。每个父页用自己的 Codec 从子页 Path/Query 重建参数，不复制 Extra；缺少必填数据、依赖无法重建的 Extra、取消或失败，均不改变原栈。

祖先策略先于目标执行；redirect 重新规划，defer/resume 重新验证。每个安装的祖先有独立 Entry 与 Scope，没有业务调用者等待其 Pop 结果。普通 push/replace 不自动补祖先。自定义 Backend 通过可选 `CCNavigationParentStackAdapter` 接受计划，必须在修改前拒绝不支持的事务。

外部入口只能进入显式允许 Deep Link 的目标；结构父页不因此变成公开入口，其策略仍收到原始 external origin。URI 的绝对/相对形式不决定信任。Host 负责平台、通知或扫码 ingress 与 allowlist；`CCNavigationSource` 只是脱敏归因，不能绕过 policy。

动态 `open` 的 push/go 是栈行为，与 origin 独立。运行中的通知或扫码通常 push，保留原 Tab 返回；需要重建层级时选 Go。每个 Host 的新平台/浏览器位置取消旧 ingress，包括新 URI 已等于当前位置；迟到结果/错误被消费，不影响其他 Host 或普通业务 push。

## 7. 策略、并发与回退

Interceptor 负责进入前 allow/cancel/redirect/defer；PopGuard 是同步退出决策；Aspect/Lifecycle 是观察；Failure Policy 决定特定失败如何恢复。观察回调不执行策略，框架回调中不通过重入导航替代返回决策。

Host 可配置并发策略：默认 allow；singleFlight 共享同类在途执行；rejectDuplicate 拒绝同类重复。identity 包含 origin、Host/Outlet、operation、Open mode、routeId、URI；携带 Extra 不去重。各调用者保留独立观察身份和 error Zone；共享失败不能丢失原错误/堆栈。

Host/Session/Runtime 或原调用 Owner 结束后，旧策略等待、Failure Policy、deferred continuation 与并发 gate 必须结束；晚到结果不能提交到 replacement。框架结束等待不代表能强制停止外部 Future，应用仍须按取消 token 清理请求。登录恢复等具体流程见[生产场景](../skills/ccrouter-integration-development/references/production-scenarios.md)。

返回协调、页面异步确认、iOS 跟手与 Android 自动桥统一见[返回协调与平台手势](CCRouter-predictive-back.md)。`close` 不使用当前栈顶替代目标；不支持时不能降级成 pop 关闭别页。精确关闭和策略失效批量处理分别保留独立规范。

## 8. Entry、渲染与 Scope 生命周期

初始 Managed 页面与后续页面一样拥有 Entry 和 Route Scope。普通 Pop 先结束逻辑 Entry 与结果，退出渲染和 Scope 保留到 Flutter 转场完成，避免动画中重建访问 Service 时黑屏；业务不得在退出期启动新工作。精确 close 和仅剩 foreign anchor 的路径按其语义及时释放资源。

Shell 外层退出时，已渲染分支与 Scope 保留到转场完成。途中重新进入同一 Shell，旧 renderer 交出 Outlet 渲染权，不能争用 Navigator Key 或清除新 generation。卸载与 shutdown 结束渲染等待，不依赖下一帧；可选退出 SPI 使用可解绑回调，不能永久用 Future 持有 Runtime。

Renderer 真正卸载会释放 Route 关联、PopEntry、foreign 记录与页面 top 观察，不关闭保留的 Managed Entries、Scopes 或业务结果。重挂使用新 renderer generation 投影当前 Stack，不重放完成的启动 Go；已 dispose 的 Widget State/foreign Popup 不会恢复。同帧移动与真正卸载区分，前者保留原 Navigator 与 native gate。

Scope-owned Service、共享 readiness 和清理在 Host 上下文运行，不保留首次调用者任意 Zone 值。资源归属、释放顺序和初始化失败回收见[Service 生命周期](CCRouter-service-lifecycle-design.md)。所有结果只完成一次；旧 backend callback 不得修改新 Entry。

## 9. Foreign Route 与非 Route UI

普通 Flutter Dialog、BottomSheet、Popup 和外部 Navigator Route 以 foreign identity 观察；返回优先处理真正顶层 Route，不让底页 Guard 拦截上方弹窗。它们不建立 Managed Scope，也不借用底页 Scope 拥有独立资源。

LocalHistory 由实际 Flutter Route 的返回流程协调；系统/业务 maybePop 只能移除一次。精确 close 则按目标身份执行，不消费覆盖 Popup 或 LocalHistory。关闭最后一个 Managed Entry 仍保留覆盖的 foreign Popup；空 anchor 在最后一个 Popup 真正离开后回收。

Host 的 `foreignRouteBridge` 用于报告无法由内置观察覆盖的第三方 Route。返回的不透明 handle 只用于诊断关联，push/replace/pop/remove 报告不执行导航、不创建 Scope、不完成业务结果。已被内置 Observer 覆盖的 Route 不双报；opaque 非 Route UI 显式报告，不按 Widget 文本猜测身份。

Route/Context/payload 只在必要的活动期关联，退出、替换、移除、卸载与 shutdown 后释放。历史诊断只留脱敏值，不保存 Flutter Route、Widget、Context、完整 URI 或业务参数。

## 10. 能力边界与验证入口

当前有 Managed Navigator 2.0、Shell/多 Outlet、MultiHost、typed result、精确 close、策略重验证和可选返回桥。自定义 Adapter 必须对不支持能力给明确结果，不可先部分改栈再失败。

未提供：Navigator 1.0 Backend、任意外部 Router attach、原子组合栈、任意位置 replace、原生多窗口桥、完整 restoration、动态组件治理。应用布局、恢复需求采集、产品埋点和供应商 SDK 由应用拥有，不进入框架待补齐清单。

现行能力与 Demo、自动化、真实平台的对应见[验证索引](validation/README.md)。自动化通过不等于 macOS/Android/iOS 所有手势和长期性能均重新验收；结论以每份报告日期、源码与环境为限。扩展触发见[后续工作](CCRouter-future-work-plan.md)，发布条件只看[Release Readiness](CCRouter-release-readiness.md)。
