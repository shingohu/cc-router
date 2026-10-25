# macOS 外部 Deep Link 验证

## 两种验证方式

Demo 提供两个不同层级的入口：

1. 导航页的“模拟外部 Deep Link”直接调用 `CCDeepLinkIngress.fromPlatform`。它不依赖
   操作系统，但会使用 `externalPlatform` origin，执行 Deep Link Policy、参数 Codec、
   Interceptor、Aspect 和诊断链路。
2. macOS URL Scheme 验证从系统 `open` 命令开始，经 `app_links` 进入宿主，再调用
   `CCDeepLinkIngress.fromPlatform`。它验证完整的平台接入链路。

仅给 `CCRouter.navigator.open` 传入 `CCNavigationSource.deepLink` 不会把请求变成外部入口；
Source 只用于来源归因，是否外部由受控 Ingress 设置的 `CCNavigationOrigin` 决定。

外部来源和栈行为相互独立。三个 `CCDeepLinkIngress` 入口默认使用
`CCDeepLinkOpenMode.push`，因此运行中打开链接会覆盖到当前页面上方，返回时仍可回到固定
Root 或主 Tab。需要按 URI 重建当前 Managed Host 的声明式 Shell/Outlet location 时，宿主可以显式
选择：

```dart
await CCDeepLinkIngress.fromPlatform(
  uri,
  mode: CCDeepLinkOpenMode.go,
);
```

`go` 会替换当前 Host 的 Managed location；它不改变 Origin，也不会绕过 Host Authority
白名单、Route Deep Link Policy、参数 Codec 或拦截器。Demo 的平台桥保持默认 `push`，用于
验证固定首页不会被外部链接清除。

三个入口直接返回只读 acceptance receipt。Demo 平台桥记录本次 receipt 的实际 Route、
Navigation 和 Entry ID，不通过最新栈猜测目标。Host 如需关联分享业务 ID，可保存
`receipt.navigationId` / `routeEntryId` 的映射；singleFlight 跟随者拥有独立的
`navigationId`，但共享 producer 的 `entryNavigationId` 和 Entry。redirect／fallback 后
`routeId` 为最终目标。receipt 只表示接收成功，不保证可见或业务成功；defer 等待 resume，
拒绝与取消仍抛错。映射清理及先到观察事件的有界暂存由 Host 负责。

Demo 平台桥与导航实验室通过 `async/await + try/catch` 处理入口错误，无需迁移。
升级其它 Host 时，若旧 `catchError` 以 void/null 返回来消化错误，应先接
`.then<void>((_) {})` 转换；只声明 `Future<void>` 变量或转发函数不会转换底层 Future，
拒绝、取消时仍可能新增抛出 `ArgumentError`。需要 receipt 时使用 `try/catch`。

跨 Shell 或分支并不自动要求 `go`。原生 Managed 的 cross-Shell `push` 保留原 Shell 的分支栈
与 Widget State，可在目标退出后返回；Host Tab 选择本身仍是分支激活策略，不自动新增 Push
历史。需要保留访问前历史时用 `push`，需要用链接重建当前 Host location 时用 `go`，不要再
沿用已移除 GoRouter Backend 的历史限制。跨 Shell 返回入口见导航实验室 Workspace 详情。

Demo 在 `CCRouterHost.initialize` 中配置 `demoDeepLinkIngressPolicy`：只接受
`ccrouter://lab/...`、`https://ccrouter.example/...`，并允许经过 Host mapper
验证后生成的绝对 Path。框架默认策略是 `denyAll`，所以新增生产域名或自定义 Scheme
时必须由宿主显式添加精确的 `CCDeepLinkAuthorityRule`，仅新增 `CCUriPattern` 不会放行。

## 运行中唤醒

先启动 Demo，并保持终端中的 `flutter run` 继续运行：

```sh
cd <repository-root>/demo
fvm flutter run -d macos
```

另开一个终端执行：

```sh
open 'ccrouter://lab/detail/88?title=macOS%20External%20Deep%20Link&tags=terminal&tags=app-links'
```

应用应在当前页面上方 Push ID 为 `88` 的详情页，并显示两个 tags；返回后应回到此前页面。
再打开“诊断”页，可看到：

```text
Platform Deep Link received · scheme=ccrouter · host=lab
Aspect ... · demo_navigation_lab.detail · source=platform.app_link
Platform Deep Link dispatch complete · route=demo_navigation_lab.detail · navigation=... · entry=...
```

RouteEntry 的 origin 应为 `externalPlatform`。完整 URI 和 Query 值不会写入平台接入日志。

## 冷启动

先构建并至少运行一次应用，让 Launch Services 注册 `ccrouter` Scheme：

```sh
cd <repository-root>/demo
fvm flutter build macos --debug
open build/macos/Build/Products/Debug/ccrouter_demo.app
```

关闭应用后执行同一个 Deep Link 命令：

```sh
open 'ccrouter://lab/detail/89?title=Cold%20Start%20Deep%20Link&tags=cold-start'
```

宿主会在首帧前接收 URI，但会等到 `CCRouterApp.managed` 完成 Backend attach 后再串行
分发，因此不应出现“Adapter 尚未初始化”的错误。

如果 macOS 仍把 Scheme 指向旧构建，可显式刷新注册：

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$PWD/build/macos/Build/Products/Debug/ccrouter_demo.app"
```

然后重新执行 `open 'ccrouter://…'`。

## 路由约束

外部链接必须先命中 Host 的 Scheme/Host/Port 白名单，然后只能进入声明了
`deepLink: CCDeepLinkPolicy.enabled` 的路由。当前可测试地址：

```text
ccrouter://lab/detail/:id
https://ccrouter.example/lab/detail/:id
/workspace/home/:item
```

自定义 Scheme 可直接通过上述 macOS 命令验证。HTTPS Universal Link 还需要域名上的
Associated Domains 文件和 macOS entitlement，本 Demo 目前没有伪造这部分生产配置。
允许的标准 HTTPS 网页地址如何映射到共享 WebView，以及为何不能使用 catch-all 路由，见
[共享 WebView 容器路由](web_container_routing.md)。
