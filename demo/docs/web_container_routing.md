# 共享 WebView 容器路由

## 目标与边界

Demo 使用一个 `demo_web` 组件承载业务网页，但不会把任意 HTTP URL 直接注册为
CCRouter 路由。Web 容器仍然遵守组件契约、Deep Link Policy、来源追踪和诊断隐私边界。

实现拆成两个 Package：

- `modules/web_contracts` 是 Pure Dart 公共契约，调用方不依赖 Flutter Widget 或
  `webview_flutter`。
- `modules/web` 实现页面并持有 WebView engine。替换成其他 WebView 插件时，不需要修改
  调用方和生成的 typed Intent。

## 两类契约

### 公开 Web 路由

`demo_web.public` 的 canonical path 是 `/web`，允许 Platform Deep Link。目标 URL 使用
`DemoPublicWebTarget` 和自定义 Query Codec 编码：

```dart
await CCRouter.navigator.push<void>(
  DemoPublicWebRoute.intent(
    target: DemoPublicWebTarget(
      Uri.parse('https://docs.flutter.dev/ui/navigation'),
    ),
  ),
);
```

它适合公开、可分享、可恢复的 HTTPS 页面。示例只接受 `docs.flutter.dev` 和
`example.com`，并拒绝 HTTP、userinfo、非默认显式端口和未授权 Host。页面内后续跳转也
继续执行同一 allowlist，而不是只校验初始地址。

Query 中只能放公开 URL。Token、Cookie、认证 Header、一次性签名 URL 或其他隐私数据
不能使用这个契约，因为 URI 可能进入浏览器历史、系统日志、埋点或截图。

### 私密 Web 路由

`demo_web.private` 的 path 是 `/web/private`，默认禁止 Platform Deep Link。URL、Header
和 JavaScript policy 使用 `CCExtraParam` 在当前进程内传递：

```dart
await CCRouter.navigator.push<void>(
  DemoPrivateWebRoute.intent(
    request: DemoPrivateWebRequest(
      uri: Uri.parse('https://example.com/private'),
      headers: const {'X-Demo-Session': 'runtime-only'},
    ),
  ),
);
```

它的 normalized URI 始终是 `/web/private`，不会包含目标 URL 或 Header。Demo UI 只可
显示 Header 名称，不能显示 Header 值。私密页面内导航限制在初始 Host；生产项目通常还
应接入统一 Cookie、证书校验、下载和外部浏览器策略。

`WebViewController.loadRequest(headers:)` 只用于初始请求，不能假设 Header 会在重定向和
后续页面中持续注入。需要长期认证时应使用受控 Cookie/会话桥接，并明确登出清理和多账号
隔离，不能把 Token 拼进 URL 作为替代。

## 标准 HTTPS 外部链接

平台收到标准网页地址后，Host 的 `DemoPlatformDeepLinkBridge` 先调用
`demoMapExternalWebUri`：

```text
https://docs.flutter.dev/ui/navigation?source=ccrouter
                         │ allowlist mapper
                         ▼
/web?url=https%3A%2F%2Fdocs.flutter.dev%2Fui%2Fnavigation%3Fsource%3Dccrouter
                         │ CCDeepLinkIngress.fromPlatform
                         ▼
demo_web.public (origin=externalPlatform, source=platform.web_link)
```

未命中 allowlist 的 URL 不会被 WebView 抢占，会继续进入普通 CCRouter Deep Link 解析，
由现有 Failure Policy 或宿主外部浏览器策略处理。平台接入日志只记录 scheme、host 和错误
类型，不记录完整原始 URL。

不能声明 `https?://.*` catch-all 路由。这样做会抢占其他组件的 Universal Link，也容易
形成开放重定向和钓鱼入口；正则能匹配不代表这个边界是安全的。

## 手动验证

运行 macOS Demo：

```sh
cd /Users/shingo/develop/LiberLive/cc-router/demo
fvm flutter run -d macos
```

进入“导航”页：

1. “打开公开 Web 容器”验证 typed Query 和真实 WebView。
2. “打开私密 Web 容器”验证 Extra，诊断中的 URI 应保持 `/web/private`。
3. “模拟外部 HTTPS Web Link”验证 Host allowlist 映射，RouteEntry origin 应为
   `externalPlatform`，Aspect source 应为 `platform.web_link`。

外部 Ingress 按 CCRouter 既有约定使用 location replacement，避免保留无关的应用内栈；
因此外部 Web Link 可能成为新的 root，此时页面不显示框架返回按钮，由系统返回或窗口
生命周期处理。应用内 typed Push 保留上一页，并显示通过 `CCRouter.navigator` 执行的返回
按钮。

真实 macOS/iOS Universal Link 还需要应用 entitlement、域名 Associated Domains 和服务端
AASA 文件。当前 Demo 没有控制 `docs.flutter.dev` 的域名配置，因此执行
`open 'https://docs.flutter.dev/...'` 会打开默认浏览器，而不是本应用。这不是 CCRouter
解析失败，而是操作系统没有建立域名与应用的可信关联。自定义 `ccrouter://` Scheme 的完整
系统验证继续参考 [外部 Deep Link 验证](external_deep_link.md)。

Widget Test 没有注册 native WebView platform 时，页面会显示安全 fallback，以便继续验证
路由参数、隐私边界和生命周期；macOS 真机运行用于验证实际网页渲染。
