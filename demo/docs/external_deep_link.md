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

## 运行中唤醒

先启动 Demo，并保持终端中的 `flutter run` 继续运行：

```sh
cd /Users/shingo/develop/LiberLive/cc-router/demo
fvm flutter run -d macos
```

另开一个终端执行：

```sh
open 'ccrouter://lab/detail/88?title=macOS%20External%20Deep%20Link&tags=terminal&tags=app-links'
```

应用应切换到 ID 为 `88` 的详情页，并显示两个 tags。返回首页后打开“诊断”页，可看到：

```text
Platform Deep Link received · scheme=ccrouter · host=lab
Aspect ... · demo_navigation_lab.detail · source=platform.app_link
Platform Deep Link dispatch complete
```

RouteEntry 的 origin 应为 `externalPlatform`。完整 URI 和 Query 值不会写入平台接入日志。

## 冷启动

先构建并至少运行一次应用，让 Launch Services 注册 `ccrouter` Scheme：

```sh
cd /Users/shingo/develop/LiberLive/cc-router/demo
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
  -f /Users/shingo/develop/LiberLive/cc-router/demo/build/macos/Build/Products/Debug/ccrouter_demo.app
```

然后重新执行 `open 'ccrouter://…'`。

## 路由约束

外部链接只能进入声明了 `deepLink: CCDeepLinkPolicy.enabled` 的路由。当前可测试地址：

```text
ccrouter://lab/detail/:id
https://ccrouter.example/lab/detail/:id
/workspace/home/:item
```

自定义 Scheme 可直接通过上述 macOS 命令验证。HTTPS Universal Link 还需要域名上的
Associated Domains 文件和 macOS entitlement，本 Demo 目前没有伪造这部分生产配置。
允许的标准 HTTPS 网页地址如何映射到共享 WebView，以及为何不能使用 catch-all 路由，见
[共享 WebView 容器路由](web_container_routing.md)。
