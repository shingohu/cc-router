# GoRouter 退役与原生 Managed 回归

日期：2026-10-23。分支：`codex/managed-navigation-runtime`。
本记录承接 2026-10-22 全量审查；仅下列实际执行结果代表此次退役验证。

## 原因与方案

双 Backend 长期维护两套身份、拓扑和生命周期逻辑，使 close 与声明式页面树存在额外同步成本。
保留冻结兼容包可短期回滚，但会继续占用测试和接入心智；直接移除需要一次 Host 迁移，
业务 Contract、Intent、导航调用和 Scope 语义可以保留。本次采用用户确认的正式退役：
原生 Managed Stack 为唯一内置导航状态，Flutter RouterDelegate/Navigator.pages 负责渲染。

## 变更与迁移

- 删除 `packages/ccrouter_go_router`、GoRouter Pub 依赖及旧兼容 Demo 入口。
- Host 改用 `CCManagedRouterApp`；定制 MaterialApp 使用 `CCManagedRouterBackend` +
  `CCRouterApp.managed` + `MaterialApp.router(routerConfig: backend.routerConfig)`。
- 不再提供外部 GoRouter attach；渐进改造使用局部 Managed Outlet，外层应用负责返回交接。
- Foreign/opaque UI 诊断桥迁到 Host-only `adapter.foreignRouteBridge`；自动观察的普通
  foreign Route 不重复报告。桥只发诊断，不导航、不创建 Entry/Scope。
- 通用历史迁到 Runtime 有界脱敏快照；predictive fallback 单独固定最多 100 条。
- 旧兼容源码可从 Git 历史恢复；不再提供双 Backend 运行时切换。

## 测试迁移映射

| 旧覆盖 | 原生 Managed 覆盖与处理 |
| --- | --- |
| Adapter 操作与能力 | `adapter_test` + `managed_router_backend_test`；移除 match tree/attach 专属断言 |
| Catalog/别名/Regex/presentation | `catalog_assembler_test`，真实 Managed 渲染 |
| Facade 与混合 Flutter 导航 | `integration_test`，保留 Popup、LocalHistory、foreign Page、Form/PopScope、直接 Pop 结果 |
| 配置透传/factory once | 新 `managed_app_configuration_test`；删除旧 GoRouter 配置测试 |
| 有界历史/Route 回收 | `navigation_history_test`、`navigation_history_lifecycle_test`，容量交叉与 WeakReference/GC |
| Observer 与页面生命周期 | `navigation_observer_test`、`page_lifecycle_test`，使用中立测试观察桥 |
| 精确 close 与 Route Service | `targeted_close_test`、`route_service_test`；声明式从旧 unsupported 迁为成功能力 |
| Predictive Back | `predictive_back_test`，Managed 实例与独立 Navigator handler 退役边界 |
| 资源与 API 隔离 | `resource_lifecycle_regression_test`、`api_surface_test`，桥销毁后不可保留 Adapter |
| Demo 双跑 matrix | 保留真实业务场景并只跑 Managed；不把双 Backend 重复执行数当成独立能力 |

测试总数变化包含 GoRouter 专属配置/内部结构退役和重复 Backend 参数化收敛，不能仅用数量
判断覆盖增减。Generator 中 GoRouter 类型拒绝字符串和历史包识别仍保留为边界防御，
不代表依赖或兼容 Backend 仍存在。

## 迁移发现并修复

1. Foreign Route 复制 Managed Page key/settings：以私有 Page 类型、Adapter owner 和
   实际渲染 Route identity 交叉确认，不能冒领 Entry。
2. close 最后一个 root/Shell Entry 撤掉覆盖 Popup：短期保留无业务 child/arguments/Scope
   的空结构边界；Popup 结束后释放。业务 Scope/result 立即且只结束一次。
3. 直接 Flutter Navigator.pop(result) 先被 Page 回调用 null 完成：等待原 Route.popped，
   精确关联外部 Pop，并隔离 Adapter 已销毁和重复通知。
4. 局部 PopScope 拒绝错误归因 foreign removal：保持 owner.none，不结束原 Entry。
5. 自定义 Host 的 placement 仍为 default：事件填入实际 Host，保留 Shell/parent/Outlet。
6. 外部长期持有已销毁诊断桥：清空所有回调与句柄，WeakReference/GC 回归确认可回收 Adapter。

## 验证结果

- 框架 Flutter：633 项通过。
- Demo Flutter：104 项通过。
- Generator：645 项通过、1 项跳过。跳过项需显式开启
  `CCROUTER_ANALYZER_NETWORK_SMOKE=1` 的远程网络 Smoke，不算本轮通过。
- navigation_lab、analytics_firebase、payment、kv_storage 与 DevTools：合计 18 项通过。
- Workspace `fvm dart analyze`：No issues found。
- Pub 重新解析确认 `go_router 17.5.0` 退出依赖图。
- Demo 真实 Host `generate`、`generate demo --no-cache --check` 均通过；
  Generator 全量测试结束后再次 freshness check 通过。
- 独立 Host `demo/modules/order/example --no-cache --check` 通过。
- 文档检查：121 份 tracked Markdown 通过；`git diff --check` 通过。
- macOS 默认入口与 `lib/multi_host_demo.dart` 均 Debug 构建成功。
- Runtime history benchmark：1 项通过，覆盖容量 0/2/1000/10000。

测试日志、截图与动作快照归档于
[本轮证据目录](20261023-go-router-retirement/)。检查命令为
`fvm flutter test packages/ccrouter_test/test`、`fvm flutter test demo/test`、
`fvm dart analyze`，Generator 日志保留完整逐项结果。未提交、未推送本轮变更。

## macOS 真实窗口验收

默认入口实际点击并核对了以下场景：

- typed result、Path alias、scheme、模拟外部 Deep Link、full URL；
  Push/Replace、覆盖后 exact close、Revalidation keep/replace/close/reset。
- Shell 子页、root 透明页、StatefulShell 跨分支详情保留与返回；
  fade、scale、Cupertino、底部滑入与透明页面。
- Managed Dialog 确认/取消、BottomSheet 选择；foreign Page/Dialog/BottomSheet、
  Overlay、LocalHistory BottomSheet。
- Interceptor proceed/cancel/redirect、defer resume/cancel、timeout、Failure Policy；
  Guard dirty 拒绝退出、保存后只退一层；Managed/foreign 覆盖下 Hide/Show。
- 订单 Contract/result、跨组件 Service、Session；Command 的 typed/void、跨组件、
  timeout/cancel/error；Event 多订阅/零订阅/timeout；Privacy/Timeout InitTask Gate。
- Service 的 App/Session/Route/NewInstance/lazy/multiple/optional 与 Session 释放；
  KV String/Bool 保存读取、Fragment Tab/Props/账号/错误切换、DevTools 八个只读 Tab。

网络页 GET/POST 只完成按钮点击，未核对 HTTP 完成，不能记为远程请求成功。
固定 Seed `20261023` 的随机开关测试完成 24 轮，最后 48 条动作组成 24 对开关操作，
每轮关闭后的 AX 快照均包含 `CCRouter Lab` 与 `1 Route Entries`。
本轮未见黑屏或错误 Widget；这不是长期稳定性或全平台手势证明。

多 Host 入口另外验证：

1. 右侧 typed Push 显示 ID 42，左侧总览不变；确认返回 `detail:42:confirmed`。
2. 实际鼠标点击左侧 Push，仅左侧显示详情，右侧导航首页不变；返回后为两个首页。
3. 自适应列表选 Item 3，Detail Outlet 内 Level 3 → Level 4 → Pop，精确回到 Level 3，
   结果为 `stack:4:done`。
4. expanded/compact、hinge 开关切换保持 Host identity；compact 无 hinge 时仅显示 List，
   再展开恢复原 Level 3 Entry，Pop 回 Item 3 基础页。页面局部瞬时提示会重建，
   本结果只证明导航 Entry 保留，不承诺所有 Widget 局部状态自动保留。

窗口自动化中途曾返回 `noWindowsAvailable`；用户确认解锁后，将窗口移到可用显示器恢复。
没有证据将该工具中断判为框架卡死。MultiHost AX 树仅暴露一个导航子树，切换左侧 active
后仍可能引用右侧控件；最终归属检查使用真实坐标点击和截图交叉确认。
`08-primary-push.jpg` 是 AX 误选右侧控件的过程截图，不能作为左侧成功证据；
以 `09-primary-coordinate-push.jpg` 及 `multihost-observations.json` 为准。
`13-adaptive-compact-stack-preserved.jpg` 显示的是详情隐藏，恢复证据在 14、16。
完整动作日志包含尝试和中断，不能将其 221 条记录全部算作成功断言。

MultiHost 进程采集日志未报告 Flutter 异常；默认入口后半段经 `open` 启动，
没有完整 stdout，默认入口结论限定为实际窗口观察。

## 平台与性能边界

本次不将历史 Android/iOS 真机通过冒充当前版本复验；手机跟手、取消与提交仍按平台验收。
历史证据见 [平台记录](managed_navigation_platform_acceptance_20261022.md) 与
[上轮全量审查](managed_full_review_20261022.md)。OHOS embedding/SDK AutoFill 构建限制仍在。
Runtime history benchmark 已切换为中立 Runtime 路径，不能与旧 Observer/Adapter 路径
直接比较并声称加速。每组预热 6000、测量 1000 次 push/pop 和 500 次 snapshot；
容量 0/2/1000/10000 的 wall µs/pushPop 分别为 32.668/46.212/34.162/26.895，
snapshot 分别为 0.078/10.408/6.638/41.396 µs。测试使用 Memory Backend + Runtime，
不包含 Flutter 帧或 allocation/heap；构建负载也会影响单次结果。
资源回收测试覆盖 WeakReference/GC 与桥回调释放，但 RSS 或一次 GC 不能证明长期生产不存在泄漏。
