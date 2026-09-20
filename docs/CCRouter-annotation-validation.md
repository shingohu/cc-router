# CCRouter 注解字段与兼容性校验

本文定义 Route 生成链的稳定字段规则、失败阶段和 Runtime 兜底边界。目标是让能在构建期
确定的错误尽早失败，同时保证手写 `CCRouteDefinition` 不会绕过相同的不变量。

## 稳定标识

Route、Interceptor、Pop Guard、Host、Shell 和 Navigator Outlet 使用统一语法：

```text
^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$
```

最大长度为 128 个 ASCII 字符，首字符必须小写；后续字符大小写敏感。`.`、`_`、`-` 是分段符，
不能连续、开头或结尾。统一语法用于生成索引、日志、Trace 和跨 Package 聚合，不表示这些 ID
属于同一个命名空间。Route 保留 `orders.byId` 这类既有 camelCase ID 的兼容性。

Component ID 沿用更严格的 Package 风格，只允许小写字母、数字和上述分段符。

推荐 Route、Interceptor 和 Pop Guard ID 使用 Component ID 作为前缀，例如
`demo_order.detail`、`demo_order.auth`。这是可发现性约定，不作为硬性校验，因为已有手写 Route
可能使用短 ID。

## 字段规则

| 字段 | Generator | Workspace | Runtime |
| --- | --- | --- | --- |
| Component ID | 语法、长度、自依赖、重复依赖 | 外部 Index 二次校验、全局重复、依赖图 | 手写 Manifest 二次校验 |
| Component Version | 完整 SemVer 2.0 | 外部 Index 二次校验 | 手写 Manifest 二次校验 |
| Route ID | 语法、长度、同 Library 重复 | 全 Workspace 重复 | 手写 Definition 重复与语法 |
| Interceptor/Pop Guard | 语法、长度、Route 内重复 | 持久化元数据二次校验 | 注册、引用、Owner 和重复校验 |
| Host/Shell/Outlet | Placement 语法与长度 | 持久化元数据二次校验 | 手写 Placement、Shell、Host 校验 |
| Parent Route | 语法、自引用 | 存在性、依赖可见性、环和 Placement | 手写 Route 的存在性、环和 Placement |
| Regex Pattern | 语法、2048 字符、32 个具名 Capture | 仅比较可证明的冲突 | 手写 Pattern 使用相同上限 |
| 参数 Constraint | 语法、256 字符、Capture 对应关系 | 保留生成结果 | 手写 Pattern 使用相同上限 |
| Description | Unicode/Markdown 自由文本，最大 4096 字符 | 安全序列化 | 不参与 Runtime 行为 |

Interceptor 与 Pop Guard 列表保留声明顺序。重复项是构建错误，框架不会通过去重改变策略执行
次数。注册存在性与 Owner 关系仍在 Runtime 初始化时验证，因为当前生成元数据不包含完整策略
注册表。

## Parent Route

Parent 是结构关系，不从 Path 前缀推断。Parent 与 Child 必须指向同一个 Host、Shell 和
Navigator Outlet；否则后端无法把两者装入同一确定栈。

同组件 Parent 可以直接引用。跨组件 Parent 还必须满足：

- Child 所属组件通过 required 或当前存在的 optional dependency 可达 Parent 组件；
- Parent 是 `CCRouteContract` 形成的公开契约，而不是另一个组件的内部 Page Route；
- 依赖边和 Parent 边都不能形成环。

动态 Host 绑定和 Adapter 能力不属于注解事实，仍在 Runtime 初始化阶段校验。

## 正则表达式边界

生成器和 Runtime 只执行确定性校验：语法、长度与具名 Capture 数量。框架不使用启发式规则
推测 catastrophic backtracking，因为这会误伤合法表达式。复杂 Regex 应只用于不可逆的兼容
地址；常规路由优先使用 `CCPathPattern` 或 `CCUriPattern` 及局部参数 Constraint。

## 兼容性

本次规则兼容仓库现有 Component、Route、Host、Shell、Outlet 和策略 ID。以下过去可能通过的
输入现在会稳定失败：大写或带空白的 ID、连续分隔符、非 SemVer 版本、重复策略引用、自引用或
不可见 Parent，以及超过确定性上限的 Regex/Description。

这些变化属于配置错误前移，不提供静默规范化。框架不会 trim、改写大小写、自动删除重复项或
猜测 Parent，以免生成物、Runtime 和诊断系统观察到不同身份。
