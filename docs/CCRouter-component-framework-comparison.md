# CCRouter 与组件化框架能力对比

## 文档状态

- 版本：v0.1
- 状态：调研记录，不代表新增 API 或实施承诺
- 最近对齐：2026-09-27
- 对比对象：ARouter、TheRouter、Flutter Modular、GetIt、AutoRoute

本文用于回答“CCRouter 相比其他组件化框架还缺少什么能力”，并区分：

1. CCRouter 已经具备的能力；
2. 当前真正的工程缺口；
3. 有意延后的 2.0 能力；
4. 不应为了对齐其他框架而引入的能力。

参考资料：

- [ARouter](https://github.com/alibaba/ARouter)
- [TheRouter](https://github.com/HuolalaTech/hll-wp-therouter)
- [Flutter Modular](https://github.com/Flutterando/modular)
- [GetIt](https://github.com/fluttercommunity/get_it)
- [AutoRoute](https://github.com/Milad-Akarie/auto_route_library)

## 总体结论

CCRouter 的核心 Runtime 能力并不落后。相较常见方案，CCRouter 在以下方面更完整：

- Route Contract 与组件所有权分离；
- 跨组件 Pure Dart 契约；
- 类型安全参数和返回值；
- RouteEntry 与 Route Scope 精确生命周期；
- Foreign Route、Popup、Overlay 混合导航隔离；
- Deep Link Host allowlist 与 Route policy 双重校验；
- Interceptor、PopGuard、Aspect 的职责分离；
- 有界诊断、Trace、Failure 和 Capability Fallback；
- App/Session/Route Service 生命周期；
- Command、Event、InitTask 的语义分层；
- 并发、取消、超时和销毁边界。

当前主要欠缺的是跨能力源码定位、IDE/可视化工具和长期发布治理，而不是 Host
最小接入或继续堆叠更多基础路由操作。

## 能力对比

| 能力 | ARouter / TheRouter | Flutter Modular | GetIt | AutoRoute | CCRouter 当前状态 |
| --- | --- | --- | --- | --- | --- |
| 注解路由生成 | 强 | 中 | 无 | 强 | 已支持，组件级生成 |
| 多模块路由 | 强 | 强 | 无 | 中 | 已支持，按组件与 Contract 聚合 |
| 类型安全参数 | 中 | 中 | 无 | 强 | 已支持，Arguments/Intent/Codec |
| 类型安全返回值 | 有限 | 支持 | 无 | 支持 | 已支持 |
| 路由 Guard | Interceptor | Guard | 无 | Guard | 全局/路由 Interceptor + PopGuard |
| Deep Link | 支持 | 支持 | 无 | 支持 | 支持并增加来源与 allowlist |
| 嵌套路由/Shell | 部分 | 强 | 无 | 强 | Shell、StatefulShell、多 Outlet |
| Service/DI | Service/Provider | Module DI | 强 | 通常外接 | App/Session/Route Scope |
| 异步 Service Ready | 部分 | 部分 | 支持 | 外接 | 支持 single-flight 与取消 |
| 事件广播 | 事件/Action | 外接 | 外接 | 外接 | 类型化 Event |
| 启动任务 DAG | 通常较弱 | Module 初始化 | 异步依赖 | 外接 | InitTask + Gate + failure policy |
| 动态模块治理 | 部分方案支持 | Module 生命周期 | Scope/unregister | 无统一语义 | 1.x 不支持，2.0 候选 |
| IDE 路由定位 | ARouter 有插件 | 一般 | 无 | 生成 API | 有 `ccrouter find`，无 IDE 插件 |
| Watch 增量生成 | 生态支持 | 部分支持 | 不适用 | 支持 | 1.x 不提供 `watch` |
| DevTools | 部分 | 部分 | 注册查看 | 部分 | 有诊断数据，无可视化面板 |
| 原生多窗口 | 平台相关 | 平台相关 | 无 | 后端相关 | Host 隔离已具备，原生桥接暂缓 |
| 状态恢复 | 平台/后端相关 | 后端相关 | 无 | 部分 | 只记录恢复机会，完整恢复暂缓 |

## 当前真实缺口

### 1. Host 最小接入已完成

新项目可以直接使用 `CCGoRouterApp`，由它装配 managed GoRouter、Root Observer、
Adapter、Host 和 `MaterialApp.router`：

```dart
runApp(
  CCGoRouterApp(
    catalog: ccrouterGeneratedRouteCatalog,
    components: ccrouterGeneratedComponentManifests,
  ),
);
```

需要全局拦截器、Deep Link Policy、Aspect、Telemetry 或诊断配置时，应用先显式调用
`CCRouter.initialize`，再让 `CCGoRouterApp` 只负责 Host。已有 GoRouter 工程继续使用
`CCGoRouterBackend.attach`；复杂 Shell、多 Outlet、自定义 Override 或完整 Widget 树可使用
`CCRouterApp.managed`。这些显式路径是渐进式集成边界，不是新项目必须复制的样板代码。

因此 Host 最小接入已经闭环。后续新增 Backend 应复用同一个 `CCRouterAppBackend` 边界，
不再为每种后端复制业务初始化模型。

**状态：已完成。**

### 2. 简单 Service 已自动生成，低频能力保持显式 Contribution

零参数同步构造的简单 Service 使用 `@CCService`，生成器会推导内部 ID 或唯一直接
`@CCServiceContract`，并生成 Provider registration、私有 Registrar、Manifest 和 Catalog
metadata。复杂构造、依赖注入和 async initializer 仍使用显式 Provider：

```dart
@CCComponentContribution(id: 'orders.capabilities')
void registerOrderCapabilities(CCRegistry registry) {
  registry.registerService(...);
  registry.registerCommand(...);
  registry.registerEventSubscriber(...);
  registry.registerInitializationTask(...);
}
```

Contribution 会自动并入组件的生成 Registrar，因此新增 Route 或简单 Service 不再手工修改
Registrar。Shell、策略和复杂 Service 仍是低频且语义各异的能力。Command、Event 和 InitTask
已分别确认稳定 ID、可信 Owner 与静态关系图缺口，各自独立生成方案已记录，但尚未实现。

继续显式声明这些能力是有意选择，不是 Route/Service 自动装配遗漏。Service 方法 Proxy 已通过
消费组件的结构化依赖声明独立实现；Command 将采用显式 Contract、Handler 与消费依赖；Event
将采用显式 Contract、静态 Subscription 和 Owner 自动 Publication；InitTask 将采用显式 Task
Contract、顶层 Handler 和类型化依赖。不同语义不能重新合并成一个万能注册注解。

**优先级：Command、Event、InitTask 均已有独立方案，按未来计划顺序实施。**

### 3. Generator 和 IDE 工具链不如成熟路由框架

当前已有：

- `generate`；
- `--check`；
- `--no-cache`；
- `--profile`；
- `find`；
- `clean`；
- Package/Host Catalog。

仍缺少：

- `ccrouter watch`；
- IDE 内的路由到源码跳转插件；
- IDE 内的组件依赖和 Contract 图；
- 生成失败后的 IDE 状态提示；
- Catalog 的可视化浏览。

建议先继续强化 `find` 和 Catalog，再根据真实项目的生成 P95 决定是否实现 `watch`。当前 Demo 的稳定空改动约为数秒，尚不足以证明常驻 Watch 进程值得承担锁、资源和失败恢复成本。

**优先级：中，主要归入 2.0 开发体验。**

### 4. Service Scope 不是通用层级 Scope

GetIt 支持用户创建层级 Scope、Scope shadowing、unregister 和按 Scope 清理；Flutter Modular 也支持 Module DI 与 Page Scope。

CCRouter 当前固定为：

```text
App -> Session -> RouteEntry
```

这使生命周期容易诊断，但不能表达临时业务流程、Workspace、Tab 或 Feature Scope。当前不建议直接开放任意字符串 Scope，因为会重新引入动态组件和资源所有权不可追踪的问题。

如果真实业务出现稳定的：

```text
App -> Session -> Workspace -> Route
```

再设计有限的受控 Scope，而不是直接复制通用 Service Locator 的全部能力。

**优先级：低，2.0 候选。**

### 5. Component/Contract 版本兼容检查不完整

`CCComponent.version` 当前主要用于身份、Catalog、诊断和生成元数据。Pub 依赖可以解决 Package 版本，但目前还没有完整表达：

- Contract 允许的版本范围；
- Route Contract 兼容性；
- Service Contract 兼容性；
- 能力废弃和迁移；
- 跨组件接口升级失败原因。

正式发布前应考虑在生成阶段增加 Contract compatibility check，而不是等 Runtime 运行后才发现组件协议不兼容。

**优先级：中，适合正式发布前设计。**

### 6. 缺少环境实现选择模型

Injectable 等 DI 工具通常支持 dev、test、staging、production 环境实现。CCRouter 当前可以用 `CCServiceKey<T>` 选择多个实现，并通过 `CCRouterTestHost` 做测试替换，但没有独立的 Environment 抽象。

短期继续使用 Composition Root 显式选择、Service Key 和测试 Override。只有多个真实组件重复出现环境分支时，再考虑生成期环境校验。

**优先级：中低。**

### 7. 缺少 DevTools 可视化

CCRouter 已有足够的只读数据基础：

- Component Manifest；
- Package/Host Catalog；
- Route Entry Snapshot；
- Backend Entry；
- Navigation Aspect；
- Trace；
- Failure；
- Service Invocation；
- InitTask Snapshot。

但尚未提供统一 DevTools 面板。未来可以展示 Component Graph、Route Graph、Active Entries、Service Scope、Navigation Timeline、Failure/Fallback 和 InitTask DAG。

**优先级：中，2.0 开发体验任务。**

## 有意延期，不应视为当前遗漏

以下能力已明确放入 2.0 或等待真实生产触发：

1. Navigator 1.0 Backend；
2. 其他通用 Navigator 2.0 / 自定义 Backend；
3. Native macOS、Windows、iPadOS 多窗口桥接；
4. 完整 Route Restoration；
5. 原子组合栈操作和精确 Entry 操作；
6. 动态组件激活、停用和卸载；
7. Action Pipeline；
8. Command、Event、InitTask 自动声明生成，以及 Service Proxy 当前不支持的方法形态；
9. CLI 组件模板、契约提升和迁移工具；
10. Generator Watch 和 DevTools。

这些能力不是“缺少基础实现”，而是当前版本为了保持 API 表面积、生命周期和降级语义可控而主动不公开。

## 不建议为了对齐其他框架而引入

### 全局 Routes 表

全局路由表对小项目方便，但会削弱组件所有权、跨包可见性和增量生成。继续使用组件级 Route API、独立 Contract Package 和 Host Catalog。

### 任意代码注入

把 Dart 代码或方法名字符串放入注解会绕过 Analyzer、破坏重构和安全边界。继续使用结构化常量、Codec 和明确 SPI。

### 通用动态 Action Bus

普通业务操作使用 `CCCommand<R>`，事实通知使用 `CCEvent`，长期能力使用 Service。只有真实出现多 Handler 仲裁、优先级、短路和动态来源后，才启动 Action Pipeline 评审。

### 任意通用 Scope

通用 Scope 的灵活性会增加生命周期和资源泄漏风险。当前固定 App/Session/Route 更符合可诊断和稳定性要求。

## 推荐实施顺序

### 近期

1. Component/Contract 版本兼容校验设计；
2. 持续验证 `ccrouter find` 和 Catalog 对 Route、Service、Command、Event 与 InitTask 的源码定位；
3. 持续性能、RSS/Heap 和长时间运行回归；
4. 保持 README、Integration Skill 与生成器文档同步。

### 架构 2.0

1. Navigator 1.0 Backend；
2. Native 多窗口桥接；
3. Route Restoration；
4. DevTools；
5. Generator Watch 和 IDE 插件；
6. 分层 Scope；
7. 动态组件治理；
8. Action Pipeline；
9. Service Proxy 高级方法形态；
10. CLI 模板和迁移工具。

## 最终判断

CCRouter 当前最明显的缺口不是基础路由 Runtime，而是：

1. `ccrouter find` 已形成多能力只读定位闭环，但 IDE 和 DevTools 生态还不成熟；
2. Contract 版本兼容和环境实现选择尚未系统化；
3. 复杂 Service 与未注解迁移能力仍依赖显式 Contribution，高级自动生成等待生产阈值；
4. 原生多窗口、状态恢复和动态组件属于明确的 2.0 范围。

后续应优先处理版本治理和可发现性，而不是继续增加重复的导航快捷 API，或复制其他框架的
全局注册模型。
