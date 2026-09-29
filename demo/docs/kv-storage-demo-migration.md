# KV Storage Demo 用例改造方案

> 文档归属：Demo / 应用层。本文描述 `demo/modules/kv_storage` 的示例架构，不定义 CCRouter
> 框架公开能力，也不表示框架负责持久化、账号、API 环境或设备身份。

## 状态

- 状态：Scoped Facade 已在 Demo 落地；Session/Environment/Device 的真实 Host 绑定和持久化
  Backend 仍按真实业务场景实施。
- 当前 Demo：`demo/modules/kv_storage` 同时提供显式 `DemoStorageNamespace` 底层 API、
  `DemoStorageContextProvider` 和 `DemoScopedStorage`，Backend 仍为内存实现。
- 本轮不把持久化存储实现加入 Workspace，也不把 Demo 上下文误当成认证或环境真源。
- 目标：业务调用方不需要在每次读写时手动拼接账号、环境或设备 namespace，同时保持
  生命周期、数据隔离、Backend 替换和安全边界可诊断。

## 1. 当前 Demo 与问题

当前底层 Client 的调用形式是：

```dart
await client.setJson(
  DemoStorageNamespace.user('demo-account'),
  'profile.preferences',
  {'theme': 'dark'},
);
```

这种形式适合 Backend 实现、迁移和测试，但不应成为生产业务的主要调用方式。业务代码如果
每次自行传入 `userId`、`environmentId` 或 `deviceId`，会产生以下风险：

- 同一组件不同调用点使用了不一致的账号或环境 ID；
- 登出或账号切换后，旧账号 Store 被继续持有；
- Network 和 Storage 各自维护当前 API 环境，发生漂移；
- 全局、游客、用户、设备数据混用；
- 业务误以为 namespace 本身提供加密或授权；
- 迁移、清理、诊断和并发行为无法集中控制。

Namespace、当前上下文和物理存储位置是三个不同维度，不能由一个字符串同时表达。

## 2. 目标架构

```text
Auth / CCRouter Session
  └── currentAccountId / guest state

Environment Service
  └── currentEnvironmentId

Device Service
  └── deviceId / hardware identity

Storage Context Provider
  └── logical namespace resolution

Scoped Storage Facade
  └── typed primitive / JSON operations

Backend Placement Policy
  └── standard / secure / database / memory

Concrete Storage Backend
  └── file / database / platform secure storage / test fake
```

Storage 只消费账号、环境和设备上下文，不拥有认证状态、API 环境切换或设备身份。
Network 与 Storage 应共享 Environment Service 的当前环境来源，不能分别维护一份可变环境 ID。

## 3. 目标业务 API

保留底层显式 namespace Client：

```dart
CCStorageClient.setJson(namespace, key, value);
```

已新增面向业务的 Scoped Storage Facade：

```dart
final storage = CCRouter.service<DemoKeyValueStorageService>();

await storage.global.setBool('privacy.accepted', true);

await storage.currentUser.setJson(
  'profile.preferences',
  {'theme': 'dark'},
);

await storage.currentEnvironment.setString('feature.apiMode', 'v2');

await storage.hardware.setJson(
  'display.configuration',
  {'scale': 1.0},
);
```

建议的业务访问面：

| Facade | 来源 | 无可用上下文时的行为 |
| --- | --- | --- |
| `global` | Application/Runtime | 始终可用 |
| `guest` | 匿名 Session | 始终可用；登录后不自动等同于用户 Store |
| `currentUser` | CCRouter Session / Auth | 未登录时返回不可用或稳定错误 |
| `currentEnvironment` | Environment Service | 始终有一个已校验环境 |
| `hardware` | Device Service | 设备身份未就绪时返回 readiness 错误 |

`currentUser`、`currentEnvironment` 和 `hardware` 只能在操作时解析最新上下文。业务不应把
这些 Scoped Store 跨登录、登出、账号切换或设备切换长期缓存。

## 4. 生命周期语义

### 登录

```text
登录成功
  -> CCRouter.openSession(accountId)
  -> Storage Context Provider 发布 currentUser
  -> 后续用户读写使用新账号 namespace
```

游客数据是否迁移到用户数据必须由应用显式选择，不能由 Storage 自动合并。迁移必须有：

- 明确的 Key 白名单；
- 幂等策略；
- 失败和回滚语义；
- 诊断事件；
- 测试覆盖。

### 登出与账号切换

```text
登出 / Token 失效
  -> 关闭当前 CCRouter Session
  -> 销毁 Session Scope 的用户 Storage
  -> currentUser 失效
  -> 业务回到 guest 或未登录状态
```

账号切换必须先完整关闭旧 Session，再打开新 Session。不能复用旧账号的用户 Store，也不能
只修改一个全局 `currentAccountId`。

### API 环境切换

环境切换由 Environment Service 原子更新。Network 使用它选择 Base URL，Storage 使用它
选择环境 namespace。环境切换不应清理用户数据，也不应把开发环境数据读到生产环境。

### 设备变化

设备 ID 或 Flutter View 身份变化时，新的硬件 namespace 只影响硬件配置；不能影响账号
Session，也不能自动复制旧设备配置，除非业务声明迁移规则。

## 5. Backend Placement Policy

Namespace 负责逻辑隔离，Placement 负责物理 Backend 与安全策略。两者不能硬编码为一一映射。

```dart
enum CCStoragePlacement {
  standard,
  secure,
  database,
  memory,
}
```

建议默认策略：

| 数据示例 | 逻辑 namespace | 推荐 Placement | 说明 |
| --- | --- | --- | --- |
| 隐私协议同意状态 | global | standard | 不包含凭证 |
| 用户偏好 | currentUser | standard/database | 按敏感度和规模选择 |
| Refresh Token | currentUser | secure | 不允许使用普通 KV |
| API 环境配置 | currentEnvironment | standard | 只保存已校验配置 |
| 硬件显示配置 | hardware | standard/database | 设备本地数据 |
| 临时请求缓存 | 任意 | memory/database | 必须有 TTL/容量策略 |

Namespace 不是加密边界、授权边界或密钥管理方案。Token、密钥和其他凭证应由独立的
Credential/Secure Storage Service 管理；诊断日志不得记录原始值。

## 6. Package 与 Contract 边界

不把 KV Storage、User、API Config 和 Device 全部聚合到一个万能 `base_contracts` 包。

推荐边界：

```text
base_contracts
  ├── CCAccountId
  ├── CCEnvironmentId
  └── CCDeviceId 等少量稳定值对象

storage_contracts
  └── Storage Service Contract

auth_contracts
  └── Account / Auth Session Contract

environment_contracts
  └── API Environment Contract

device_contracts
  └── Device Identity / Hardware Contract
```

在 Demo 阶段，`demo_kv_storage` 可以同时提供 Storage Contract 和实现。真实出现跨组件消费
后，再拆出 Pure Dart `storage_contracts` Package。实现 Package、Backend、生成 Registrar 和
Metadata 不进入 contracts Package。

## 7. 实施顺序

1. 保留现有 `CCStorageClient` 和显式 namespace API，作为 Backend SPI、迁移和测试底层。
2. 增加受控的 `CCStorageContextProvider`，只读取 Auth/Session、Environment、Device 的
   当前快照，不保存业务对象或凭证。
3. 增加 `CCScopedStorage` 和 Storage Facade，隐藏常规业务调用中的 namespace 参数。
4. 将 `currentUser` 绑定到 CCRouter Session；验证登录、登出、账号切换和并发调用。
5. 将 `currentEnvironment` 绑定到 Environment Service，并让 Network/Storage 共享同一来源。
6. 增加 Backend Placement Policy 和至少一个持久化/安全 Backend 适配实验，不把依赖加入 Core。
7. 增加游客迁移、环境隔离、设备切换、敏感数据拒绝普通 Backend 的测试。
8. 当跨组件真实消费者出现时，再拆分 `storage_contracts`，并由生成器校验 Owner、依赖和公开
   Barrel；不要先创建空的万能 `base_contracts`。

## 8. 验收与回归

- 相同 Key 在 global、guest、不同 user、不同 environment、不同 hardware namespace 中互不覆盖；
- 登录后不会继续读写旧账号 Store；
- 登出后 `currentUser` 明确失败或不可用；
- 环境切换只影响环境数据和 Network Base URL，不污染用户数据；
- 游客到用户迁移只处理白名单，重复执行不产生重复副作用；
- JSON 读写保持深拷贝和类型校验；
- Secure 数据不会落入 standard Backend；
- Backend、Context Provider 和 Facade 都能用 Fake 在 Pure Dart 测试中运行；
- Session、Runtime、Backend dispose 顺序明确且幂等；
- 诊断只记录 namespace kind、稳定 ID 和操作结果，不记录原始值、Token 或完整 Key 内容。

本轮已完成第 1-3 步以及 Facade 的 Pure Dart/Flutter 包测试。第 4-8 步仍需真实业务确认后
单独实施，尤其是 Session/Environment/Device Contract、游客迁移、持久化/安全 Backend 和
`storage_contracts` 拆包；不自动扩张万能 `base_contracts`。
