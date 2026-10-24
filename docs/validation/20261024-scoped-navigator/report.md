# Host / Outlet 绑定导航 API 与实现后审查

日期：2026-10-24。源码基线：`7d9b51211ddae3e55349c64773ec7d4e2675e391` 加本次工作区改动。
本记录是源码、Widget 和 GC 验证，不是新的 macOS 实窗、Android/iOS 真机手势或性能验收。

## 问题与方案

多 Host / 多 Outlet 使用全局导航时，没有足够信息推断调用位置；焦点只能作为默认返回目标，
无法正确表达“右侧发起请求、等待期间点击左侧、请求完成后仍在右侧打开”的归属。
现有 `context:` 能表达此行为，但重复调用需要重复解析。

比较应用内包装、焦点推断、修改全局默认行为与新增可选入口后，采用
`CCRouter.navigatorOf(context) → CCNavigator`：复用既有业务接口、类型结果、策略和分发管线，
不改变全局调用语义，也不新增 Generator 或 Adapter 导航协议。旧调用可以直接用于对照和回退。

## 实现契约

- 在目标 Navigator 内部的 Context 获取一次；适合 build、didChangeDependencies 或交互回调。
- 保存 Host / Outlet 标识、无反向所有权的 Runtime identity 和原 Host 注册的只读弱租约。
  不保存 Context、Route、Navigator、Runtime；不安装 Timer 或监听，无须 dispose。
- 同名 Host 注销重建和 Runtime 重启不能复活旧对象；所有旧调用同步抛出
  `CCRouteCancelledError`，`code == 'host_detached'`。
- 单独退出页面、隐藏或卸载 Outlet Renderer 不等于注销 Host。这不是页面级任务取消器；
  组件移到其他 Host / Outlet 后重新获取对象。
- 默认 placement 使用绑定目标，路由显式 placement 继续优先。Pop 仍返回绑定区域，
  不自动追随最后一次 Push 的显式目标；close 仍按精确 handle 操作。
- 如仍传 per-call Context，必须解析到同一 Host / Outlet；不同目标报
  `CCNavigationOutletResolutionError`，不静默重绑定。
- Core 的只读 `CCNavigationHostLifetime` 属于框架内部集成 SPI，由业务 barrel 隐藏，
  并有真实 Dart Analyzer 的负向导出边界测试。

## 扩展审查发现与修复

发现已有的 Host 标识歧义：真实 Host ID 为 `default` 时，具体调用目标再次被解析为
“使用 active Host”。修复前专项输出包含：

```text
Expected: 'default'
  Actual: 'host.secondary'
```

该场景还会在第三个 Host 的初始路由期间误操作已挂载的另一个 Router，出现
`setState() or markNeedsBuild() called during build`。

修复将具体调用位置与路由声明的默认哨兵区分：传入的 call-site Host 是具体地址，
一次导航保存其默认 Host，后续解析沿用该快照。新增回归同时在调用前和异步 Interceptor
等待期间切换 active Host，确认真实 `default` Host 的归属和返回结果保持不变。
未传位置的全局调用仍使用 active Host；显式目的路由的拓扑规则不变。

最终 review 核查了全部导航方法、注册换代、Runtime 身份、返回所有权、公开导出边界与
内存引用链，未发现本次改动尚未解决的阻塞问题或高置信度生命周期泄漏。

## 回归证据

| 检查 | 结果 | 原始日志 |
| --- | --- | --- |
| `fvm flutter test packages/ccrouter_test/test --no-pub --reporter expanded`，仓库根目录 | 1,411 项通过 | [框架](framework.log) |
| `fvm flutter test --no-pub --reporter expanded`，`demo/` | 113 项通过 | [Demo](demo.log) |
| `fvm dart analyze`，仓库根目录 | No issues found | [分析](analyze.log) |
| `fvm dart run ccrouter_generator:ccrouter generate demo --no-cache --check` | 6 组件、34 路由、11 Packages 一致 | [生成](generation.log) |
| `dart format --output=none --set-exit-if-changed`，本次 12 个 Dart 文件 | 0 changed | 最终命令输出 |
| `git diff --check` | 通过 | 最终命令输出 |

框架总数已包含新增的 14 项 scoped navigator 专项，不能再叠加专项数字。
额外在原 Shell 回归中覆盖绑定后的 push/pop/result/Route Service 释放；公开 API 负向测试确认
业务入口不可访问生命周期租约，正向测试确认 `navigatorOf` 返回 `CCNavigator`。

专项覆盖：双 Host × 左右 Outlet、异步等待与焦点切换、所有导航方法、typed result、
显式目的 placement、错误 Context、同名 Host 替换、旧对象各方法拒绝、Runtime 重启、
defer/resume、根级 Popup 优先、LocalHistory 和 PopGuard。

GC 使用 `leak_tracker.forceGC`，保留导航对象的同时分别确认已退出页面 Context，
以及已结束的 Runtime、Adapter、Navigator 可回收；另有活跃注册下继续导航的正向对照。
测试只在获取对象时进入独立 Runtime overlay，避免把 Flutter 自己的 frame callback Zone
保留误计为导航对象保留。

Demo 将自适应详情区、类型安全详情 Push 和结果返回迁移到可选入口。
新增真实 Demo Widget 按钮回调验证：保持列表区域焦点、不注入 Pointer，详情页面仍进入
`host.primary / adaptive.detail` 并可返回。原双 Host 的语义回调隔离回归同时通过。

## 文档与边界

README、集成 Skill、实现范式、review checklist、DartDoc 和两个 Package Changelog 已同步。
Generator / Analyzer Plugin 的语法和协议无需变化，本轮未修改 Plugin，也未变更 Demo pin。
无设备长期性能数据，不能据此扩展结论到长期零泄漏或所有真机手势。
