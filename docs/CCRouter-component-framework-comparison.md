# CCRouter 与组件化框架能力对比

## 文档状态

- 版本：v0.1
- 状态：调研记录，不代表新增 API 或实施承诺
- 评估日期：2026-09-24
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

当前主要欠缺的是 Host 接入体验、代码生成生态、可视化工具和长期发布治理，而不是继续堆叠更多基础路由操作。

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

### 1. Host 启动和路由装配仍有样板代码

Flutter Modular 将 Module、DI 和 Route 放在一个模块定义中；AutoRoute 通过 Router Config 聚合；而 CCRouter 当前 Host 仍需要显式创建：

- `CCNavigationHost`；
- Navigator keys；
- Observer；
- Shell binding；
- Route override；
- `CCGoRouterBackend.managed`；
- `MaterialApp.router`。

这不影响 Runtime 正确性，但会降低新项目接入效率，属于当前最重要的开发体验缺口。

后续可以提供默认 Host 装配入口，例如：

```dart
final backend = CCRouterGoRouterApp.create(
  catalog: ccrouterGeneratedRouteCatalog,
  components: ccrouterGeneratedComponentManifests,
);
```

前提是 Shell、StatefulShell、多个 Outlet 和自定义 Override 仍然显式可控，不能依赖路径前缀或隐式启发式猜测。

**优先级：高，建议 1.x 后续优先处理。**

### 2. Service、Command、Event、InitTask 仍需手动 Registrar 注册

当前路由已经自动生成，但以下能力仍需手动注册：

```dart
registry.registerService(...);
registry.registerCommand(...);
registry.registerEvent(...);
registry.registerInitializationTask(...);
registry.registerRouteInterceptor(...);
```

与 ARouter 的 Service/Interceptor 自动注册、Flutter Modular 的 Module DI 相比，样板代码更多，也无法自动生成完整的消息 Catalog。

但当前生产样本不足以冻结新的注解和 metadata 协议。继续手动注册是有意选择，不是实现遗漏。达到既定生产阈值后，再统一设计 Service、Command、Event 和 InitTask 生成器。

**优先级：中，暂不立即实现。**

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

`CCComponentDescriptor.version` 当前主要用于身份、Catalog、诊断和生成元数据。Pub 依赖可以解决 Package 版本，但目前还没有完整表达：

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
8. Service、Command、Event、InitTask 自动注解生成；
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

1. Host 最小接入优化，减少新项目的 Backend/Shell/Observer 样板；
2. Component/Contract 版本兼容校验设计；
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
9. Service/Message 自动生成；
10. CLI 模板和迁移工具。

## 最终判断

CCRouter 当前最明显的缺口不是基础路由 Runtime，而是：

1. Host 接入仍有样板代码；
2. Service/消息注册尚未自动生成；
3. Generator、IDE 和 DevTools 生态还不成熟；
4. Contract 版本兼容和环境实现选择尚未系统化；
5. 原生多窗口、状态恢复和动态组件属于明确的 2.0 范围。

后续应优先处理 Host 最小接入体验，而不是继续增加重复的导航快捷 API或复制其他框架的全局注册模型。
