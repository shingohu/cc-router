# CCRouter 与组件化框架能力对比

## 文档状态

- 版本：v0.1
- 状态：调研记录，不代表新增 API 或实施承诺
- 最近对齐：2026-10-07
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

当前主要欠缺的是正式发布与迁移治理、IDE 自动改写、少数高级 Proxy 形态和长期生产观测，
而不是 Host 最小接入、官方 DevTools Extension 或继续堆叠更多基础路由操作。

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
| IDE 路由定位 | ARouter 有插件 | 一般 | 无 | 生成 API | 生成 API + `ccrouter find`，另有可选 Analysis Server 边界诊断 |
| Watch 增量生成 | 生态支持 | 部分支持 | 不适用 | 支持 | Host-only `generate --watch=auto --machine`，并提供 `watch status/follow`；最终门禁仍是 `--no-cache --check` |
| DevTools | 部分 | 部分 | 注册查看 | 部分 | 嵌入式面板、官方只读 Extension、Catalog/Runtime 联动、依赖与调用链已支持；不直接控制 Runtime 或绑定本地 IDE |
| 原生多窗口 | 平台相关 | 平台相关 | 无 | 后端相关 | Host 隔离已具备，原生桥接暂缓 |
| 状态恢复 | 平台/后端相关 | 后端相关 | 无 | 部分 | 只记录恢复机会，完整恢复暂缓 |

## 当前真实缺口

### 1. Host 最小接入已完成

新项目可以直接使用 `CCGoRouterApp`，由它装配 managed GoRouter、Root Observer、
Adapter、Host 和 `MaterialApp.router`：

```dart
runApp(const CCGoRouterApp());
```

应用必须先显式调用 `CCRouterHost.initialize(hostAssembly: ...)`；`CCGoRouterApp` 始终只负责
Host，并自动使用初始化时安装的同一份 Catalog。已有 GoRouter 工程继续使用
`CCGoRouterBackend.attach`；复杂 Shell、多 Outlet 或
自定义 Router 构造可使用一次性 `backendFactory`，只有完全自定义 Widget 树才直接使用
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
  registry.registerInitTask(...);
}
```

Contribution 会自动并入组件的生成 Registrar，因此新增 Route 或简单 Service 不再手工修改
Registrar。Shell、策略和复杂 Service 仍是低频且语义各异的能力。Command、Event 和 InitTask
已经分别实现显式 Contract、Handler/Subscription、Owner Client、稳定 ID、metadata、Catalog、
Workspace 校验和自动 Registrar bridge。

继续显式声明低频复杂能力是有意选择，不是自动装配遗漏。Service 方法 Proxy 通过消费组件的
结构化依赖声明生成；Command、Event 和 InitTask 也保持各自语义，不合并成万能注册注解。

**状态：已完成当前批准的生成闭环；高级方法形态和动态能力仍按生产需求评估。**

### 3. Generator 和 IDE 工具链仍有自动化缺口

当前已有：

- `generate`；
- `--check`；
- `--no-cache`；
- `--profile`；
- Host-only `--watch=auto --machine` 与 `watch status/follow`；
- `find`；
- `clean`；
- 按 Host/Package 角色执行的 package-local generation；
- `portable prepare/publish` 显式分发状态生命周期；
- `create component` / `create page` / `create service` / `create command` /
  `create event` / `create init-task` 非覆盖式脚手架；
- Package/Host Catalog；
- watch/one-shot Generator 结构化诊断到 Analyzer Plugin 的 fail-open bridge。

仍缺少：

- Contract Promotion/Migration 和 alias 迁移自动化；
- IDE 内直接打开本地源码、自动改 import 和 rename/alias migration Quick Fix；
- 跨文件自动重构，以及超出当前结构化 Generator snapshot 和确定性单文件规则的 IDE 诊断。

静态 Catalog 与 Runtime 快照联动、只读组件依赖/反向依赖、源码 URI 和单次能力调用链已由
嵌入式面板与官方 DevTools Extension 实现。Extension 不绑定任意本地 IDE，不能把 source URI
展示误写成跨 IDE 自动跳转。

当前 watch 通过稳定协调锁、逐轮输入栅栏、结构化状态、失败恢复和最终 one-shot 参考门禁限制
常驻进程风险。后续重点是持续测量大型项目 P95/RSS、真实 IDE 时序和异常恢复，不把当前 Demo
数据外推为所有工程收益；具体数字以带日期的生成器性能报告为准。

**状态：watch 与结构化诊断桥接已完成；自动改写和迁移仍属后续开发体验能力。**

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

### 5. Component/Contract 版本兼容核心门禁已完成

五类 Contract 已具备独立 SemVer、规范化 shape fingerprint、Owner/消费者范围，以及生成、
Host 聚合和 Runtime 三层校验。错误可以区分缺失、Owner 不匹配、版本范围不满足、指纹变化、
重复实现和陈旧生成物。

仍未完成的是正式 Hosted 发布、release candidate 兼容样本的持续维护，以及 Contract
Promotion/Migration CLI；它们属于发布工作流，不应再写成 Runtime 兼容检查缺失。

**状态：核心兼容门禁已完成；发布与迁移工具待完成。**

### 6. 缺少环境实现选择模型

Injectable 等 DI 工具通常支持 dev、test、staging、production 环境实现。CCRouter 当前可以用 `CCServiceKey<T>` 选择多个实现，并通过 `CCRouterTestHost` 做测试替换，但没有独立的 Environment 抽象。

短期继续使用 Composition Root 显式选择、Service Key 和测试 Override。只有多个真实组件重复出现环境分支时，再考虑生成期环境校验。

**优先级：中低。**

### 7. DevTools 可视化边界

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

`ccrouter_devtools` 已提供可嵌入的统一只读面板；`devtools/ccrouter_extension` 已通过版本化
Snapshot 协议展示 Overview、Catalog、Component Graph 和 Call Graph。两者均不提供导航、
重试、销毁或组件激活控制。源码 URI 可展示/复制，嵌入式面板可由 Host 提供 `onOpenSource`；
官方 Extension 到任意本地 IDE 的直接绑定仍未实现。

**状态：官方只读 Extension 和关系视图已完成；IDE 直接打开源码仍是工具链缺口。**

## 有意延期，不应视为当前遗漏

以下能力已明确放入 2.0 或等待真实生产触发：

1. Navigator 1.0 Backend；
2. 其他通用 Navigator 2.0 / 自定义 Backend；
3. Native macOS、Windows、iPadOS 多窗口桥接；
4. 完整 Route Restoration；
5. 原子组合栈操作和精确 Entry 操作；
6. 动态组件激活、停用和卸载；
7. Action Pipeline；
8. Service Proxy 当前明确拒绝的通用 generic Contract、Stream、callback、继承和高级 Route Scope 形态；
9. CLI Contract Promotion/Migration 和 alias 迁移工具。

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

1. 完成正式 Hosted 发布、release candidate 兼容样本和迁移说明；
2. 持续验证 `ccrouter find`、Catalog 和 DevTools 对五类能力的源码定位；
3. 持续性能、RSS/Heap、真实设备和长时间运行回归；
4. 保持 README、Integration Skill 与生成器文档同步。

### 架构 2.0

1. Navigator 1.0 Backend；
2. Native 多窗口桥接；
3. Route Restoration；
4. IDE 自动改写/迁移 Quick Fix；Generator Watch、基础 Analysis Server 边界诊断与官方
   只读 DevTools Extension 已落地；
5. 分层 Scope；
6. 动态组件治理；
7. Action Pipeline；
8. Service Proxy 高级方法形态；
9. CLI Contract Promotion 和迁移工具；六类基础 scaffold 已落地。

## 最终判断

CCRouter 当前最明显的缺口不是基础路由 Runtime，而是：

1. `ccrouter find`、嵌入式面板和官方 Extension 已形成只读定位/诊断闭环，深度 IDE 跳转和
   自动迁移仍待完善；
2. Contract 版本核心门禁已完成，环境实现选择和正式发布迁移流程尚未系统化；
3. 复杂 Service 与未注解迁移能力仍依赖显式 Contribution，高级自动生成等待生产阈值；
4. 原生多窗口、状态恢复和动态组件属于明确的 2.0 范围。

后续应优先处理版本治理和可发现性，而不是继续增加重复的导航快捷 API，或复制其他框架的
全局注册模型。
