# CCRouter DevTools Host 自动装配计划

## 1. 状态与目标

- 状态：已实现，持续多平台 smoke 与性能回归作为发布门禁。
- 优先级：P1，DevTools 开发体验和 Host 样板收敛。
- Owner：Host 与生成器；`ccrouter` 只管理中立生命周期，`ccrouter_devtools` 负责具体 VM
  Service Extension。
- 目标：Host 不再手写 DevTools 注册函数、静态 Catalog 和清理调用，同时保持 DevTools 可选、
  Release 强制关闭、失败不影响应用。

当前有效接入是 Host 直接依赖 `ccrouter_devtools`，由生成器写入静态 Catalog 和 Tool
Integration，再通过 `CCRouterHost.initialize(hostAssembly: ...)` 驱动注册与清理。手工
`CCDevToolsServiceExtension.register()` 只保留给测试和不使用生成 Assembly 的特殊 Host。

## 2. 当前问题

改造前 Demo 把手写 `demoDevToolsCatalog` 和 `registerDemoDevToolsExtension()` 放在
`demo_navigation_lab` 业务组件中，再由 `main.dart` 主动调用。它存在以下问题：

1. VM Service Extension 是应用 Host/Isolate 级开发工具，不属于业务组件。
2. 组件、能力、依赖关系和源码位置已经存在于生成 metadata/Catalog，手写副本容易漂移。
3. Host 必须记住注册和清理，生命周期不完整。
4. 一个简单的 `CCRouterHost.initialize(enableDevTools: true)` 无法提供静态 Catalog，也会迫使
   `ccrouter` 反向依赖当前已经依赖它的 `ccrouter_devtools`，形成循环依赖。
5. 一个 Runtime 可以管理多个 Navigation Host/Outlet；任意 `CCRouterApp.dispose` 都不能代表
   isolate 级 DevTools endpoint 应被清理。

因此需要消除 Host 样板，但不能把具体 DevTools 包直接塞入业务 Facade。

## 3. 方案比较

### 3.1 `CCRouterHost.initialize(enableDevTools: true)`

不采用。调用简单，但会污染业务 API、破坏可选包依赖方向，且无法独立携带生成 Catalog、失败
策略和清理逻辑。布尔值也不能证明 Host 是否直接安装了 DevTools Package。

### 3.2 永久保留 Host 手工 bootstrap

仅保留为测试和非生成 Host Assembly 的兼容入口。边界清晰，但不能作为生成式 Host 的推荐接入。

### 3.3 生成式 Host Tool Integration

采用。Core 定义窄的 Host-only 生命周期 SPI，`ccrouter_devtools` 提供具体实现，生成器从 Host
Catalog 生成静态快照并写入 Host Assembly。`CCRouterHost.initialize/shutdown` 只驱动中立
Integration，不依赖 DevTools 协议或 UI。

## 4. 启用与生成规则

`ccrouter_devtools` 必须是 Host Package 的直接依赖。这个声明同时表达安装和 opt-in：

```yaml
dependencies:
  ccrouter_devtools: ^0.1.0
```

生成器不得因为组件的传递依赖中出现 `ccrouter_devtools` 就自动启用，也不得把该依赖自动加入
Host。没有直接依赖时：

- 不生成 DevTools Host Integration；
- 不生成 DevTools 协议静态快照；
- 不向 `CCRouterHost.initialize` 注入任何调试工具；
- 普通生成、构建和 Runtime 行为保持不变。

存在直接依赖时，生成器从已验证的 Host Catalog 和 Package metadata 生成：

- Component ID、版本和依赖关系；
- Route、Service、Command、Event、InitTask 的稳定 ID、Owner 和类型；
- 可移植的 `package:` 源码位置；
- 可确定的静态调用与依赖关系；
- 基于规范化内容的 Catalog fingerprint。

生成器不得猜测运行时调用、动态目标或缺失的源码关系。无法证明的关系保持缺失，由 DevTools
显示为 unresolved，不能通过字符串启发式补全。

## 5. Host Assembly 与生命周期 SPI

在 `ccrouter_host.dart` 暴露窄的 Host-only Integration SPI；它不是业务 API，不从
`package:ccrouter/ccrouter.dart` 导出。接口只允许同步启动和停止可选工具，不暴露 Runtime、
Registry、Scope、Navigator 或 Adapter。

已实现结构：

```dart
abstract interface class CCHostToolIntegration {
  String get id;
  void onRuntimeReady();
  void onRuntimeStopping();
}
```

生成的 `CCHostAssembly` 携带只读 Integration 列表，Host 初始化已收敛为：

```dart
CCRouterHost.initialize(
  hostAssembly: ccrouterGeneratedHostAssembly,
  deepLinkIngressPolicy: appDeepLinkPolicy,
  // 其余真正属于应用的策略。
);
```

`hostAssembly` 提供组件、Contract Bundle 和 Host Tool Integration；路由 Backend 继续消费同一
Assembly 的 Route Catalog。`components/contractBundle` 继续作为手写 Host 和底层测试入口；
生成式 Host 必须与 `hostAssembly` 二选一，不能混用。

具体依赖方向保持为：

```text
ccrouter_devtools -> ccrouter Host SPI
generated Host assembly -> ccrouter_devtools integration
ccrouter -X-> ccrouter_devtools
```

## 6. Build Mode 与显式开关

生成 Integration 的有效条件建议为：

```dart
!kReleaseMode &&
const bool.fromEnvironment(
  'CCROUTER_DEVTOOLS',
  defaultValue: kDebugMode,
)
```

语义如下：

| Build mode | 默认 | 可否显式开启 |
| --- | --- | --- |
| Debug | 开启 | 可用 `CCROUTER_DEVTOOLS=false` 关闭 |
| Profile | 关闭 | 可用 `CCROUTER_DEVTOOLS=true` 开启 |
| Release | 强制关闭 | 不允许通过 `dart-define` 覆盖 |

`CCDevToolsServiceExtension.register()` 自身还应增加 `kReleaseMode` 防御，使错误的手工调用在
Release 中也不会注册 endpoint。开关控制的是 VM Service 注册与快照交付，不承诺 Pub 依赖从
Release 依赖图中消失。若产品要求 Release 产物完全不解析或编译 `ccrouter_devtools`，必须使用
独立 Debug entrypoint、Flavor 或调试集成 Package；Flutter Pub 依赖不能按 build mode 条件化。

## 7. 启动、清理与失败语义

启动顺序：

1. Runtime 完成组件和 Contract 校验。
2. 默认 Runtime 安装到 Facade Resolver。
3. 已启用的 Host Tool Integration 执行 `onRuntimeReady()`。
4. DevTools 注册或更新现有 isolate endpoint，并绑定生成 Catalog 和只读 Provider。

清理顺序：

1. `CCRouterHost.shutdown()` 取得默认 Runtime 后，立即调用 Integration 的
   `onRuntimeStopping()`。
2. DevTools 调用 `CCDevToolsServiceExtension.clear()`，后续请求返回 uninitialized 快照。
3. Runtime 和导航 Backend 按原顺序释放。

清理跟随默认 Runtime，而不是任意 Navigation Host、Outlet、页面或组件。VM Service API 无法
注销 endpoint；重新初始化时复用已注册 handler 并更新 Provider/Catalog。

DevTools 是可选观察工具。注册、快照转换和清理异常必须被隔离并产生脱敏诊断，不能导致
`CCRouterHost.initialize`、导航、业务调用或 `shutdown` 失败。Integration 不得同步发起导航、解析
Service、执行 Command 或修改 Runtime 状态。

## 8. Demo 迁移结果

当前已经：

1. 删除 `demo_navigation_lab` 中的 `demoDevToolsCatalog` 和
   `registerDemoDevToolsExtension()`。
2. 将 `ccrouter_devtools` 的 Extension 所有权移到 Demo Host；业务组件不负责 isolate 工具注册。
3. `demo/lib/main.dart` 删除显式注册调用。
4. Host 生成物包含静态快照和 Integration，不能包含手写日期、源码行号或关系副本。
5. 嵌入式 DevTools 面板如果继续作为 Demo 功能展示，应由 Host debug route/注入边界提供，不能
   迫使普通业务组件依赖 Host 调试工具。

## 9. 实施结果

1. 已生成 Host DevTools 静态 Catalog，并删除 Demo 手写能力、关系和源码位置副本。
2. 已增加 Host-only `CCHostToolIntegration`，生命周期同步、短时且异常隔离。
3. 已扩展 `CCHostAssembly`，并校验空或重复 Integration ID。
4. 已由 `CCRouterHost.initialize/shutdown` 驱动 Integration，且生成式 Host 使用单一
   `hostAssembly` 参数。
5. 已移除 Demo 手工 bootstrap 和业务组件的 Extension 所有权。
6. 已增加 Runtime、Generator 与 DevTools focused 测试；多平台 smoke 继续作为发布门禁。

## 10. 验收与回归

至少覆盖：

- Host 未依赖 `ccrouter_devtools` 时零生成、零注册；
- 只有传递依赖时不启用；
- Debug 默认启用和显式关闭；
- Profile 默认关闭和显式开启；
- Release 即使 define 为 true 也不注册；
- Catalog 与 Host metadata 的组件、五类能力、关系、源码位置和 fingerprint 一致；
- 注册失败不影响 Runtime 初始化；
- `shutdown` 开始后 endpoint 返回 uninitialized；
- shutdown 后重新 initialize 可更新 Provider/Catalog，且不重复注册 endpoint；
- 多 Navigation Host/Outlet 的销毁不会错误清空 isolate endpoint；
- Test Runtime Overlay 不自动接管生产 DevTools endpoint；
- 缓存/无缓存生成结果一致，且未显著增加无 DevTools Host 的生成耗时；
- Demo、macOS、iOS、Android、Web 和官方 DevTools Extension smoke 通过。
