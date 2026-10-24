# 全量能力审查与 macOS 实窗验收（2026-10-22）

## 结论与审查范围

本轮完成当前公开能力清单、Managed/Core 导航一致性、Host API 隔离、生命周期所有权、
Demo 覆盖和工具链回归审查。补齐缺失的交互场景，并用编译后的 macOS Debug App 实际点击、
输入、滚动、隐藏/恢复应用及拖动窗口验证。默认入口与多 Host 入口分别构建、运行。
工作分支为 `codex/managed-navigation-runtime`，未 commit/push。

本轮修复了多 Shell 保留/返回、Root Context 返回绕过选中子页 Guard、不合法 Shell Outlet
拓扑未提前拒绝等问题；将 Adaptive Demo 从手写 Navigator 迁到真正 Managed Outlet。
此前 F1–F7 修复保留，原始失败与对照见
[功能对齐审查](managed_functional_parity_review_20261022.md)。

已验证的具体场景满足预期；这不能推出所有设备、完整浏览器 history、性能和内存均优于旧版。
当前没有新增已确认而未修复的框架缺陷；未覆盖的平台和测量边界见文末。

## 原因、方案与实施

根因是原先把 Shell 简化为单一活动容器，且部分 Demo 只证明局部 Flutter 视图切换，未证明
Managed Entry、真实 Route、Scope、选中分区和 Guard 在组合操作中一致。仅看首页按钮或
happy path 的通过结果，无法发现覆盖页面、跨 Shell、Root Context 和窗口缩放的问题。

| 候选方案 | 收益 | 代价与结论 |
| --- | --- | --- |
| 只补 Demo 焦点/手写 Navigator | 改动少 | 掩盖结构问题，不能验证真实 Managed 所有权；不采用 |
| 扩张业务 API 或恢复 GoRouter 为默认 | 暂时减少部分差异 | 增加迁移成本，保留旧 close 限制；不采用 |
| 在 Managed 结构层修复，保留兼容对照 | 业务导航 API 稳定，可分别比较 | 需要组合回归；本轮采用 |

执行顺序：先增加失败/边界回归，修正结构所有权与返回目标，再补交互入口；最后运行全套
自动化、生成物校验和 macOS 实窗验证。GoRouter 生产实现保持冻结，仅调整 Demo Host 的
Regex alias 装配，使同一功能矩阵可运行。

### 本轮核心修改

1. 每个 Shell 保留自己的 anchor，跨 Shell push 不卸载原 Shell；返回恢复原分支、详情和
   Widget State。Root Go 清理所有 Shell 分区。同一 Shell ID 是一个保留容器，不创建同名
   Navigator 的无限副本。
2. exhausted 子 Outlet 可以返回外层 Shell；结构 Shell 的结果与 Scope 归属选中子页，
   Flutter 后续 pages diff 不重复清理。Root Context 的 PopGuard 同样解析实际选中子页。
   `root Context cannot bypass the selected Shell guard` 在修复前得到空拒绝码，修复后正确拒绝。
3. Shell 必须独占命名 Outlet，不能声明 `root`，也不能与另一 Shell 共享同一 Outlet。
   初始化抛 `CCNavigationAdapterError`，避免挂载后重复 Key 或返回递归。
   `Managed Shells reject root and shared Outlet ownership before mount` 覆盖两种配置。
4. Host-only `CCManagedOutlet.baseBuilder` 提供本地基础视图，且不创建 Managed Entry、
   result channel 或 Route Scope。真正的 Managed 页面在同一 Outlet Navigator 上 Push/Pop。
   Adaptive Demo 删除手写 Navigator，列表/详情仍由应用状态拥有。
5. Shell Demo 不再在 build 中无条件查询全局 Facade 的 `canPop`，避免低层独立装配未初始化
   时出错；返回动作在点击时执行。新增按钮所在页使用可滚动布局。
6. 补 Demo：Regex alias、外部访问内部路由拒绝、Pending 取消、覆盖下精确 close、
   Revalidation keep/close/replace/reset、Workspace 详情跨 Shell push/返回、Adaptive
   当前 Outlet 的 typed push/result。定时 close 的 Timer 由页面 State 取消并释放。

修复前失败日志保存在证据目录的 `root-guard-before.log`、`shell-contract-before.log`、
`shell-return-before.log`、`shell-close-before.log` 和 `adaptive-before.log`；
修复后对应用例已进入默认 suite，不依赖单独执行的临时探针。

## 能力 → Demo → 验证矩阵

下表的“实窗”指本轮 macOS 编译 App；“自动化”不等于真机。CLI、配置错误和 IDE 能力用
真实 CLI/Server fixture 验证，不添加没有业务意义的 UI 按钮。表中测试路径相对仓库根目录。

| 当前能力 | Demo/可复现入口 | 自动化证据 | 本轮 macOS 结果与边界 |
| --- | --- | --- | --- |
| 启动装配、组件依赖、Contract 兼容 | 默认启动、总览/能力实验室/DevTools Components | `component_test`、`contract_compatibility_test`、`catalog_assembler_test` | 6 Components 正常启动；错误拓扑走测试，不让默认 App 故意启动失败 |
| Typed Intent、Path/Query/List/Extra/result | 导航：typed result、Typed Extra；订单公开 Contract | `generated_route_test`、`query_codec_generator_test`、Demo shared matrix | ID42 参数和结果正确；Extra owner/revision 可见；订单结果 confirmed:100 |
| Alias、Regex、scheme、full URL | 导航：Path alias、Regex alias、custom scheme、full URL | 两 Backend shared matrix（12 项） | 分别解析 ID43/46/44/45；Regex 为本轮新增入口 |
| 外部 Deep Link、mapper、双层拒绝 | 导航：外部 Push/Go、HTTPS Web、拒绝内部路由 | `deep_link_test`、shared matrix | Push ID46、Go ID47；内部 stack 外部访问拒绝且当前页保留 |
| 启动地址、嵌套父链 | `initialLocation`/平台入口，Workspace Home detail | `managed_parent_stack_test`、Demo parity | 实窗覆盖 Workspace 内部详情返回；平台冷启动来源和父链失败组合由自动化证明 |
| push/replace/go/reset/pop/maybePop | 导航：栈操作工作台 | `navigation_test`、`managed_router_backend_test`、Demo matrix | Push/Replace/Go/Reset/typed Pop 均可操作并返回首页 |
| 结果类型失败 | 栈页“故意返回错误类型” | `targeted_close_core_test`、Demo matrix | 展示 `CCRouteResultTypeError`，清理后首页单 Entry |
| identity close、独立结果/Scope | 栈页“覆盖后精确关闭本页” | `targeted_close_test`、`targeted_close_core_test`、`managed_capability_scenarios_test` | 覆盖 Level2 仍在；2 秒后 Pop 直接回首页，原页结果 exact:1 |
| Active Route Revalidation | 栈页四种 Revalidation；全局阻止 Detail | `route_revalidation_test`、`multi_host_test`、6 项 Demo capability scenarios | keep 保留、close 返回、replace 到900、reset 单首页；均实际点击 |
| Interceptor、redirect、defer、取消/超时 | 策略页全部策略入口 | `navigation_test`、`cancellation_cleanup_test`、Demo matrix | Proceed/Cancel/Redirect；Pending 恢复/取消后0；timeout 为预期错误 |
| Failure Policy | 策略：不存在路由→兜底 | Core 与 Demo matrix/parity | 展示兜底页并可返回 |
| PopGuard、LocalHistory | 未保存表单；展示页 LocalHistory | `managed_router_backend_test`、`managed_router_outlet_test`、Demo parity | 未保存拒绝，保存后返回；LocalHistory 返回仅关本地 sheet |
| iOS 侧滑、取消/重复终止 | 同一详情/栈页；现有真机入口 | Demo parity 两 Backend 连续8轮提交、取消 identity、shutdown；`predictive_back_test` | macOS 不能证明 iOS 手势跟手，本轮未重复 iOS 真机 |
| Android Predictive Back | `lib/main_predictive_back.dart` | `predictive_back_test`、`predictive_back_demo_test` | 本轮未重做 Android 真机，不把桌面点击当系统预测手势 |
| 平台默认/显式动画、透明页 | 展示：Fade、Scale、Cupertino、Bottom-up、透明全屏 | `flutter_route_factory_test`、Demo shared matrix | 各页打开和返回通过 |
| Managed Dialog/BottomSheet | 展示：Managed Modal | Demo shared matrix、Framework modal tests | Dialog 确认/取消、BottomSheet 按钮结果通过 |
| foreign Route/Popup/Overlay | 展示：Navigator.push、Dialog、BottomSheet、Overlay | `navigation_observer_test`、Demo parity | 普通页面和弹层正常返回；Overlay 显示/移除不增加 Managed Entry |
| Shell 与分支状态保留 | 导航：ShellRoute/StatefulShellRoute；Workspace 跨 Shell | `managed_router_outlet_test`、Demo parity（37 项） | Feed/Settings、root覆盖、三分支、Activity计数1；跨 Shell返回原 detail42且计数仍1 |
| Host/Context 隔离 | `lib/multi_host_demo.dart` 的 Host隔离 | `multi_host_test`、Demo multiHost（7 项） | 左101不变，右 typed42、202→203→202只影响右；切换展示模式后独立栈保留 |
| Adaptive、命名 Outlet、Display Feature | multiHost入口→自适应布局→本地详情→打开栈页 | `adaptive_layout_test`、Demo multiHost | 真拖窗口542×793 compact→1202×793 expanded；Managed Level3保留并能Pop，Item3保留；Host ID不变；hinge切换通过 |
| PageShow/Hide、前后台、Aspect | 生命周期页和诊断 | `page_lifecycle_test`、`route_visibility_test`、Demo parity | Managed/普通Dialog覆盖序列可见；真实隐藏应用 onBackground、Raise恢复 onForeground |
| App/Session/Route Service、Key、lazy readiness | 能力实验室 Service、首页 Session/Proxy | `route_service_test`、`runtime_test`、`resource_lifecycle_regression_test`、模块 Proxy tests | singleton same=true、newInstance false；lazy notready→ready；primary/backup、optional missing；Session开关 |
| Command/void/cancel/timeout/Handler error | 能力实验室 Command | `generated_command_binding_test`、`runtime_test` | typed/void/跨组件/timeout/caller cancellation/Handler error 均实际点击 |
| Event 零/多订阅、异常隔离、timeout | 能力实验室 Event | `generated_event_binding_test`、`runtime_test` | 多订阅者其中失败不阻塞其它、零订阅和timeout均展示实际结果 |
| InitTask DAG/Gate/optional failure | 能力实验室 InitTask、Privacy Gate | `runtime_test`、`host_initialization_failure_test` | appStarted；Privacy Gate成功；optional timeout Gate失败为预期结果 |
| UI Fragment、Props、Action、Key、State | 展示→类型化UI Fragment | `ui_fragment_test`、`demo/test/ui_fragment_demo_test`、Generator UI tests | 两实例、Props更新、账号Key、error/retry；输入 review-note，切Tab后保留；截图核对非空白 |
| Diagnostics/Trace/Telemetry/容量与隔离 | 实时诊断、能力实验室，Host Sink配置 | `diagnostics_test`、`diagnostic_*test`、`navigation_history*test` | 单active首页、route disposed、foreign owner；容量/慢Sink/脱敏通过自动化，未强加生产日志开关 |
| Analytics PV/Leave、click/scroll/exposure、Consent | 策略 Consent/健康/Foreign归因；总览曝光；导航点击 | `analytics_test`、`analytics_flutter_test`、`exposure_regression_test`、`analytics_dispatcher_regression_test` | 默认accepted0；grant后弹窗/滚动/typed导航accepted7、pending0；revoke后再导航仍7；foreign归因isolated。各事件精确属性/阈值以自动化为准 |
| DevTools Panel/Protocol/Extension | 诊断→DevTools；官方Extension为独立工具 | DevTools+Protocol 12项、Generator/Plugin tests | 面板8个Tab和refresh均实际打开；不声称本轮打开外部官方Extension |
| KV Storage（Demo应用能力） | 总览→KV Storage实验页 | 模块 `storage_client_test`、`scoped_storage_test`、Service Proxy | String/Int42/Double3.14/Bool/JSON读回；invalid提示；global/guest切换。remove/clear隔离由自动化验证，本轮未点删除/清空 |
| Network/Dio/Web（Demo应用能力） | 总览 Network；导航/展示 Web入口 | `network_lifecycle_test`、Demo matrix | GET/POST200、Header redacted、环境选择；public/private Web加载和reload。staging请求最终响应及网页内部back/forward未计为通过 |
| Generator/cache/check/find/Portable/Hook/CLI | `ccrouter generate demo --no-cache --check`；生成Catalog/Contract与CLI fixtures | Generator有效645通过、1外部网络smoke跳过 | 实际校验11 Packages、6 Components、34 Routes；属于构建场景，不伪造App按钮 |
| Analyzer/Quick Fix/metadata invalidation/API边界 | 隔离Plugin Server fixtures，Demo现有bootstrap | Plugin173项、API surface负向编译、root/Demo analyze | 本轮未改Plugin生产实现/Pin；Server fixture不等于用户IDE加载新Plugin |

当前声明不支持的动态组件安装/卸载、Action Pipeline、完整状态恢复、通用 Navigator 1 Backend，
不通过添加假 Demo 宣称实现。GoRouter 是 deprecated 冻结兼容路径；本轮没有修其跨 Shell 返回。

## 自动化执行记录

| 检查 | 实际结果 | 运行日志 |
| --- | --- | --- |
| Framework `fvm flutter test --no-pub packages/ccrouter_test/test --reporter expanded` | 673通过 | `framework.log` |
| Demo `fvm flutter test --no-pub test --reporter expanded`（cwd demo） | 123通过，含37项parity、12项双Backend matrix | `demo.log` |
| Demo模块：KV Storage、navigation_lab、payment、analytics_firebase | 10通过 | `modules.log` |
| DevTools/Protocol | 12通过 | `devtools.log` |
| Generator完整suite（concurrency=1） | 首轮644通过、1跳过、1失败；稳定输入后唯一失败项复跑通过 | `generator-suite.log`、`generator-watch-stable.log` |
| 隔离Analyzer Plugin analyze/tests | analyze通过、173通过 | `plugin-analyze.log`、`plugin-tests.log` |
| root与Demo analyze | 均无问题 | `analyze.log`、`demo-analyze.log` |
| Host generate no-cache check | 生成物最新 | `generate-check.log` |
| macOS 默认与multiHost Debug build | 均成功 | `main-build.log`、`multi-host-build.log` |

日志相对 [证据目录](20261022-managed-full-review/)。Generator 全套最初执行期间源码也在编辑，
watch optimized/reference 对比捕获到 authored fingerprints 改变；第一次复跑又与恢复测试生成
副作用冲突。停止修改输入后，该项复跑成功（inProcess799ms/reference3210ms），有效覆盖共645项。
不将其写成“全套一次全绿”。跳过的是显式 opt-in 的远程 Git/Pub Analyzer 网络 smoke。
这两个时长只是该 fixture 的单次记录，不代表导航性能或生产构建基准。

## 实窗证据与稳定性

- [操作记录](20261022-managed-full-review/macos-ui-actions.json)：405条动作/状态记录，包含
  早期build、`FINAL BUILD START`后的默认最终build、多Host和最后默认入口复核。
  并非405个互不重复的功能或独立测试。
- [真实混合Monkey](20261022-managed-full-review/macos-monkey.json)：固定seed20261022，
  16轮 typed Push/result、Fade/Scale返回与Cancel混合；每轮最终首页且单Entry。
  最多4次有界settling观察；初始试跑的一次动画中间状态不计为正式失败或泄漏。
- 截图：[右侧跳转](20261022-managed-full-review/multi-host-right-detail.jpg)、
  [两栈](20261022-managed-full-review/multi-host-stacks.jpg)、
  [compact Managed页](20261022-managed-full-review/adaptive-compact-managed.jpg)、
  [expanded仍保留Managed页](20261022-managed-full-review/adaptive-expanded-retained-stack.jpg)、
  [UI Fragment](20261022-managed-full-review/ui-fragment.jpg)、
  [生命周期](20261022-managed-full-review/lifecycle.jpg)、
  [DevTools](20261022-managed-full-review/devtools.jpg)、
  [Analytics撤回后计数](20261022-managed-full-review/analytics-revoked.jpg)、
  [最终默认首页](20261022-managed-full-review/final-managed-home.jpg)。
- 默认和multiHost运行日志未发现Flutter未捕获Exception、assertion或overflow。
  typed result mismatch、外部拒绝、策略取消/timeout等是被捕获并展示的预期失败路径。
- 最终保留默认Managed App窗口，首页1 Route Entry、1 Backend Entry，Consent已撤回。

## 生命周期与残余验证边界

静态所有权检查和正式回归覆盖精确Scope释放、跨Shell保留、foreign live Route映射清理、
Pending取消、Timer取消、Host/Runtime shutdown、mounted Shell/popup和进行中侧滑退出。
本轮没有确认新的 `not-disposed` / `not-GCed` 泄漏；这不等于heap已经无泄漏。

尚未在本轮重新执行：Android/iOS真机手势、Web浏览器back/forward/reload e2e、OHOS真实窗口、
macOS原生多Window/多Engine、长时浸泡、heap保留路径和同设备同负载的旧/新架构性能A/B。
已有Widget手势、16轮桌面Monkey和结果/Scope断言不能替代这些验收。
因此本轮结论是上述能力矩阵及具体缺陷修复有证据，不能宣称所有平台和各项指标全面优于旧架构。
