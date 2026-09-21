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

## 逐规则回归映射

测试入口：[G：Route Generator](../packages/ccrouter_test/generator_test/route_generator_test.dart)、
[W：Workspace Validator](../packages/ccrouter_test/generator_test/workspace_validator_test.dart)、
[R：手写 Definition/Runtime](../packages/ccrouter_test/test/component_test.dart)、
[N：导航策略](../packages/ccrouter_test/test/navigation_test.dart)。没有足够静态事实的阶段会在表中
标明责任边界，不能理解为跳过最终验证。

| 不变量 | Generator 测试 G | Workspace 测试 W | Runtime/手写测试 R、N |
| --- | --- | --- | --- |
| Component ID、Version、依赖合法性 | `builder rejects invalid component ID/version/dependencies`、`accepts complete SemVer` | `rejects invalid persisted identifiers and SemVer`、`rejects missing/self/cyclic dependencies` | R `runtime validates component identity, SemVer, and dependencies` |
| Route ID、Route Owner、重复注册 | `builder rejects invalid route ID/duplicate ID` | `rejects unknown route owners`、`rejects duplicate routes` | R `runtime rejects invalid handwritten route identities and policies`、`route registration rejects missing primary and duplicate patterns` |
| 单值/多值 Pattern、唯一可逆 Primary | `builder rejects missing/single+plural/regex-only/duplicate primaries` | 复用生成元数据，不推断 Primary | R `route registration rejects missing primary and duplicate patterns` |
| Path/URI/Regex 语法与重复 Pattern | `builder rejects bad regex`、路径与 URI 元数据测试 | `rejects equal-specificity overlapping path patterns`、`rejects identical regex patterns` | R `route registration rejects malformed URI and regex patterns`、`route registration rejects missing primary and duplicate patterns` |
| Regex 长度/Capture 与 Constraint 语法/长度 | `builder rejects oversized regex/too many regex captures/bad constraint/oversized constraint` | 仅校验可静态证明的 Pattern 冲突 | R `runtime bounds handwritten route regular expressions`、`runtime applies generator expression bounds to handwritten routes` |
| Path 参数、Query 类型/Codec、Extra 边界 | `builder rejects unmapped/missing/nullable path`、`unsupported query object/codec mismatch/duplicate query keys`、`required external Extra/multiple Extras` | 不重建源码类型；验证 Contract 实现关系 | R `route registration rejects malformed URI and regex patterns`；手写 Codec 的业务正确性在 decode/encode 边界校验，不能静态推断 |
| Interceptor/PopGuard ID 与重复引用 | `builder rejects invalid/duplicate interceptor ID`、`duplicate Pop guard ID` | `rejects invalid persisted identifiers and SemVer` | R `runtime rejects invalid handwritten route identities and policies`；N `rejects route definitions with unknown interceptors`、`rejects route interceptors owned by another component` |
| Host/Shell/Outlet ID 与 Placement | `builder rejects invalid placement ID` | `rejects invalid persisted identifiers and SemVer`、`rejects parent placement mismatches` | R `runtime rejects invalid Shell and Outlet identities`、`runtime rejects missing, cyclic, and mismatched route parents` |
| Parent 存在、自引用、环、依赖可见性 | `builder rejects self parent` | `rejects missing, self-referencing, and cyclic route parents`、`requires cross-component parents to be visible dependencies` | R `runtime rejects missing, cyclic, and mismatched route parents` |
| Contract exposure、实现与公共导出 | `contract builder emits a standalone Pure Dart contract`、`page builder rejects a Contract-first constructor mismatch` | `rejects missing, duplicate, and unknown public implementations`、`requires public contracts to export the generated library` | Runtime 验证注册后的 Route ID/Owner；静态 Barrel/export 由 Workspace 负责 |
| Description 大小和安全序列化 | `builder rejects oversized description`、`metadata builder emits documented ownership and parameters` | 只消费已序列化的元数据 | 不影响运行时路由语义，无手写 Definition 字段 |

动态策略注册、Host 绑定、Adapter 能力不能由 Generator 从注解推断；Runtime 初始化/绑定时拒绝
缺失或不一致的关系。路径表达式的复杂重叠也不能可靠静态判定，Workspace 只拦截可证明冲突，
Runtime 保留注册及解析边界校验。后续增加字段时，必须同步指定失败阶段、正/负例和对应测试入口，
不能只在生成器中新增校验。

## 内部生成 API 边界

组件级 `XxxRoutes` 仅供所属 Package 使用，生成类标记 `@internal`。Workspace 与 Demo
将 `invalid_use_of_internal_member` 提升为 Analyzer error。`ccrouter generate` 和 `--check`
额外解析 Host 运行时依赖闭包中可写 Package 的手写 `lib/**/*.dart` import/export 指令，禁止引用
另一 Package 的 `src/ccrouter_generated`；条件导入与跨 Package 相对路径同样检查。自动生成的
Host/Binding 胶水可以跨 Package 连接内部 Bundle，公开 Contract/Host barrel 可以正常使用。
规则不扫描无关 Package、第三方只读依赖或测试源码，也不通过字符串搜索解释注释和普通字符串。
这是一条构建门禁，不是 Dart 编译器级私有权限；CI 应执行 `ccrouter generate --check`
和 `dart analyze`，并要求每个消费方使用相同的 Analyzer error 配置。

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
