# CCRouter Service 实施计划

> 生命周期和创建策略的最终语义见 [CCRouter Service 生命周期设计](CCRouter-service-lifecycle-design.md)。

## 1. 文档状态

- 状态：Service 子系统实施清单，生命周期模型已重新收敛，Component Scope 已落地
- 范围：Service Provider、Token/Key、Scope、生命周期和跨组件契约
- 不包含：CLI 2.0、Service 代码生成器、动态组件交付和远程 RPC

本文只记录 Service 的实施边界和验收顺序。实际状态以本文件和测试为准，不能把架构设计中
尚未实现的能力当成公开 API。

## 2. 当前已实现

- App、Session、Component 三种已启用 Service Lifetime；实例按 Lifetime 懒创建并按
  `CCServiceCreationPolicy` 选择缓存或每次创建。
- Route Lifetime 已定义但在精确 RouteEntry 所有权协议完成前拒绝注册。
- `CCServiceToken<T>` 支持跨 Package 稳定契约身份。
- `CCServiceKey<T>` 支持同一契约的命名实现。
- `ccrouter_test` 提供 `CCServiceOverride<T>`，可在隔离 `CCRouterTestHost`
  中按类型、Token 和 Key 替换已注册 Provider；替身沿用原 Provider 的 Scope、创建策略和销毁边界。
- 未命名 Provider 自动作为默认实现；多个默认实现和重复 Key 在注册时失败。
- Provider Factory 接收 `CCInvocationContext`，可以读取当前 Scope 的取消和 Deadline 信息。
- `CCDisposable` 实例由 Scope 按逆创建顺序销毁，单项失败和超时不会阻塞其它实例。
- Session 关闭会拒绝新的 Session Service 解析，并释放 Session-owned 实例。
- 服务仍由组件 Registrar 手动注册；当前没有 Service 注解生成器或方法 Proxy。
- 静态 `CCRouter` Facade 的全局 Runtime Overlay 尚未实现，测试替身不得注入生产
  `CCRouter.initialize`；需要 Facade 语义的测试仍应使用独立 Test Host 的 Runtime。

## 3. 第一阶段：注册边界与确定性

第一阶段只强化不会改变调用模型的边界：

1. Token ID 和 Key 名称使用统一的稳定标识语法和长度上限。
2. 注册时拒绝非法 Contract/Key 值，并保留安全、可诊断的注册错误。
3. 保持 Type lookup、Token lookup、Key lookup 和已有 Scope 语义不变。
4. 增加非法值、重复值、默认选择和跨 Runtime 回归测试。

第一阶段已完成：除上述注册校验外，缺失 Provider、Token 类型不匹配、循环构造和未激活
Session Scope 均返回稳定的 Service 错误子类型；缺失命名实现会保留稳定 Key 诊断字段。

Component Scope 已通过独立的异步组件停用协议落地；Route Scope 仍需绑定 RouteEntry
最终移除。页面级对象不等同于 PageShow/PageHide；Factory 也不等同于调用结束销毁。

## 4. 后续实施顺序

### 4.1 Component Scope（已完成）

- Provider 保存 Runtime 注入的 owner component ID，组件代码不能伪造所有权。
- `deactivateComponent` 先停用路由和 Shell，再取消并异步关闭 Component Scope；新解析立即拒绝。
- Scope 按逆创建顺序释放 `CCDisposable`，重复停用和并发转换保持幂等、串行。
- `activateComponent` 不重开旧 Scope，而是创建唯一的新 Scope 后恢复路由和 Shell。
- App Service 不能依赖更窄 Scope；Session Service 不能捕获 Component Service。

### 4.2 Route Scope

- 将 Service 解析显式关联到具体 RouteEntry，而不是从 `BuildContext` 或全局栈猜测。
- Route 永久移除后关闭 Route Scope；Page hide、Popup、LocalHistory 和普通 rebuild 不触发关闭。
- 先补纯 Dart RouteEntry/Scope 测试，再接入 Flutter Adapter。
- 在关联和结果语义未确定前，继续拒绝 `CCServiceScope.route`。

### 4.3 Service 调用链

- 先定义 Service 方法调用的 Invocation/Trace 边界，再考虑生成 Proxy。
- Proxy 必须传播 cancellation、deadline、Scope 状态和标准错误；不得记录业务参数和返回对象。
- 普通本地 Service 可以不生成 Proxy，跨组件 Service 才按契约选择生成。

### 4.4 生成器与 CLI

- Service Registrar 先保持手动维护，避免为低频变化的能力增加生成冲突。
- 只有在跨 Package Service 契约数量和手动错误达到可量化阈值后，才设计 Service metadata、
  Proxy 和 Host 聚合生成。
- CLI 2.0 再考虑契约提升、Override、迁移和一键校验。

## 5. 验收门槛

- 所有 Provider 标识校验在注册阶段确定失败，不依赖解析顺序。
- App/Session/Singleton/Factory 的生命周期测试全部保持通过。
- Session close、Runtime dispose、Factory failure 和 disposal timeout 不产生实例残留。
- 同一 Token 的类型不匹配、重复默认实现和命名冲突均返回稳定错误。
- 不新增 BuildContext、反射、字符串方法调用或万能 Map 作为 Service 公开契约。
