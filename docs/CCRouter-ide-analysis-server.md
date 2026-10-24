# CCRouter IDE / Analysis Server 集成

> 文档状态：当前接入契约与已知限制。Plugin 提供单文件诊断、按需类型解析和 Metadata 驱动的
> Service/Command/UI Owner 检查，Generator/Workspace Validator 仍是跨 Package 正确性的最终门禁。

## Host 生命周期边界

`CCRouterHost.initialize/shutdown/runInitTasks` 与 `CCHostAssembly` 只从
`ccrouter_host.dart` 导出，业务 `CCRouter` 不保留旧方法。Plugin 的
`ccrouter_host_lifecycle_access` 错误检查非 Host 组件 Package 的 `lib/`：直接导入／转导出、
条件分支以及解析身份明确的公共 barrel 引用均受约束。遵守 show/hide；Adapter 基础设施应只
导入需要的 SPI。测试／工具、生成物和同名外部类不误报；无法证明角色或转导出身份时暂缓。
Host 判定复用 `.metadata`、`ccrouter.yaml` 和直接依赖，已保存角色变动会刷新诊断。
同一个 Host Package 内的装配代码与业务页面仍需审查，Plugin 不提供安全隔离或自动角色修复。

## UI Fragment 检测

当前 UI 的编辑时诊断包括 `ccrouter_ui_alias_invalid`、`ccrouter_ui_alias_duplicate`、
`ccrouter_ui_dependency_duplicate`、`ccrouter_ui_version_range_invalid`、
`ccrouter_ui_action_invalid`、`ccrouter_ui_renderer_invalid` 和 `ccrouter_ui_spi_access`。
使用框架声明身份，支持 prefix 和公共转导出；无法证明的类型和不完整输入暂缓。范围检查仅
拒绝明显不支持的字面量，Props 完整 schema 和最终 Host 闭包仍由 Generator 验证。
Action 接受普通 enum 或受限不可变 DTO；根 scalar、可变类型及确定的行为/循环 schema 被拒绝，
scalar 仅可作为 DTO 字段。DTO 使用 UI schema 2 / Package Index 4，需配套 Generator 和 Plugin。
完整约束与迁移步骤见[UI 接入指南](../skills/ccrouter-integration-development/references/ui-fragments.md)。

UI Owner 使用 `ccrouter_component_owner_dependency_missing`。Quick Fix 仅补已导入的唯一
公共 Owner 常量，要求 required 列表缺省或可直接编辑；不猜 import，不改 spread/计算集合。
旧 metadata 缺 marker declaration 时暂缓 Owner 检查，重新生成后可用。组件不得引用 UI
Host SPI，手写代码不得引用 Generated SPI；测试和生成物豁免。Host Package 内业务边界仍需审查。

Host 聚合产生有稳定 code 和可移植位置的 UI 诊断：缺 Renderer、重复 Contract/Renderer、
Owner 错位、依赖缺失、版本越界、指纹变化和陈旧生成物，经现有 watch/Host one-shot 快照
通道进入 IDE。快照身份和过期清除规则不变；无源码位置的旧 metadata 只在 CLI 报错。
插件不会运行生成器、自动重写 Renderer/Action 或证明 Flutter 资源释放。

## 目标与边界

CCRouter 的 IDE 支持分成四层：

1. 生成的 Dart Route API 和公共 Contract barrel 负责补全、类型检查和自动导包。
2. `ccrouter find` 与 Package Catalog 负责能力到源码位置的确定性查找。
3. `ccrouter_analyzer_plugin` 负责编辑过程中的轻量实时诊断。
4. `ccrouter generate --check` 负责最终生成物、依赖闭包和 metadata 门禁。

Analysis Server Plugin 不运行 `build_runner`，不在后台修改业务源文件，不替代
Generator/Workspace Validator，也不读取 Runtime 或隐式全局状态。只有开发者主动选择 Quick
Fix 时才会提交一个有界源码编辑。插件不可用时，项目仍可通过普通 Dart Analyzer 和 CLI 门禁
工作；缺少实时提示不会改变构建语义。

## 当前提供的诊断

| Code | 默认级别 | 作用 |
| --- | --- | --- |
| `ccrouter_cross_package_generated_import` | error | 检查 import/export 的每个条件 URI，阻止业务 Package 引用另一个 Package 的 `src/ccrouter_generated` |
| `ccrouter_route_placement_invalid` | error | 检查直接声明的 Host/Outlet/Shell/parent 稳定 ID |
| `ccrouter_route_parent_self` | error | 拒绝直接字面量的父路由自引用 |
| `ccrouter_route_policy_invalid` | error | 拒绝直接列表字面量中的非法 Interceptor/PopGuard ID |
| `ccrouter_route_policy_duplicate` | error | 拒绝直接列表字面量中重复的 policy ID |
| `ccrouter_generated_output_missing` | warning | 标记 Route/Binding、Route/Service Contract、Service、Command Handler、Event Subscription 或 InitTask 的确定性同源输出缺失 |
| `ccrouter_required_init_task_contract_missing` | error | required InitTask 必须使用稳定的 `CCInitTaskContract` |
| `ccrouter_required_init_task_timeout_missing` | error | 异步 required InitTask 必须声明 timeout |
| `ccrouter_handler_declaration_invalid` | error | Handler 必须是 public、top-level、non-generic 函数 |
| `ccrouter_handler_signature_invalid` | error | 标记明显不支持的 Handler 参数数量或 void 返回形态 |
| `ccrouter_annotation_arguments_conflict` | error | 标记 Route `pattern/patterns` 或 InitTask `contract/id` 冲突 |
| `ccrouter_identifier_invalid` | error | 校验可确定的字面量 Route/Service/Command/Event/InitTask/Gate ID |
| `ccrouter_alias_invalid` | error | 校验可确定的 Service/Command Client alias |
| `ccrouter_timeout_invalid` | error | 拒绝可确定的零值或负值 InitTask timeout |
| `ccrouter_component_owner_dependency_missing` | error | Service/Command/UI Contract Owner 未进入消费组件 required `dependencies` |
| `ccrouter_host_component_owner_missing` | error | active watch 已证明 Host closure 缺少能力声明的 Owner；同一根因的级联错误折叠显示 |
| `ccrouter_pub_resolution_stale` | warning | 保存的 Host dependencies 与 resolved Pub graph 不一致；先运行 Pub get，期间暂停 Owner 推断 |
| `ccrouter_service_disposable_missing` | warning | 注解 Service 已有兼容的实例 `dispose()`，却未实现 Scope 识别的 `CCDisposable` |
| `ccrouter_service_owned_resource` | warning | 注解 Service 的私有 final 字段直接持有自建可释放资源，但 Service 没有接入 Scope 释放 |

Route 配置诊断适用于能证明框架身份的 `CCRoute` 和 `CCRouteContract`；placement 也需证明
`CCRoutePlacement` 构造器身份。计算常量、未知表达式、跨文件父链与完整 Host 拓扑继续交给
Generator/Validator。插件不猜测注册关系，也不为这些错误自动发明 ID 或提供拓扑修改。

### Generated-src 诊断重复调研（2026-10-06）

`ccrouter_cross_package_generated_import` 与 Dart `implementation_imports` 在一个受限场景中会
重叠：外部 Package 使用 `package:owner/src/ccrouter_generated/...` URI，且当前文件的有效
Analysis Options 启用了 `implementation_imports`。如果该 import 尚未使用，Dart 还可能同时
报告 `unused_import`；后者只描述使用状态，并不证明或替代 CCRouter 的组件/API 边界。

本轮不删除、降级或按配置静态关闭 CCRouter 规则，原因如下：

- CCRouter 规则还覆盖跨 Package 的 relative import；不能假设通用 lint 对这类路径具有相同
  覆盖。
- 消费者可以不启用 `implementation_imports`，也可以通过 error severity、file/line ignore
  屏蔽单条通用诊断。只读取 lint 开关会在这些情况下丢失边界诊断。
- Legacy Plugin 通过独立 `analysis.errors` notification 发布 CCRouter 结果。当前 source
  analyzer 不消费同一 overlay 上 Analysis Server 最终保留的 core diagnostics；按异步到达顺序
  猜测会产生闪烁或漏报。
- `unused_import` 不能作为降噪证明：一旦 import 开始使用，该诊断会消失，而跨 Package
  generated-src 边界仍然存在。

后续只有同时满足以下条件才实施降噪：从当前 Analysis Server session 的同一 source/overlay
revision 取得最终有效 diagnostics；仅当同一 import URI offset 已存在未被 ignore 的
`implementation_imports` 时抑制 CCRouter 重复项；relative import、lint 未启用、severity
ignore、inline/file ignore、解析失败时继续保留 CCRouter 规则。必须为 Legacy/LSP 各覆盖
lint enabled/disabled、used/unused import、两类 ignore、relative import 与 unsaved overlay。
该变更属于 Plugin 生产诊断行为变化，仍须先独立提交、验证并推送 Plugin，再在另一个提交中
更新 Demo 远端 pin；不能在禁止推送或无法远端解析新 SHA 的工作中提前修改规则。

基础语法规则继续处理单文件可确定信息；Handler、Component、Service 相关源文件按需复用
Analysis Server 已有 Session 的 resolved unit，解析 `dart:async` 前缀、typedef、继承和常量值。
不另建分析引擎，不缓存 resolved AST，不自行递归扫描 Workspace。无法取得当前 resolved unit
时退回保守语法检查；其它表达式存在 Dart 错误时仍保留已证明的声明身份。未知类型/依赖值
不武断报错，Service 规则不在纯语法回退路径运行。
异步解析结果必须与当前 overlay 内容完全一致；源码已变化的诊断和 Quick Fix 请求直接丢弃。
Event/InitTask 的 void-like 类型与 Generator 对齐，包括现有支持的 `Future<void>?`；这不扩大
Service dispose Quick Fix 的签名范围。

注解规则、生成物缺失提示与参数 Quick Fix 共享框架声明身份校验。优先核对 resolved
annotation 的声明 Library；业务同名类不会触发 CCRouter 诊断。其它表达式的 Dart 错误
不会抹掉已经证明的注解身份。无法解析时仅使用无本地遮蔽、无歧义的明确框架导入，
否则等待语义解析或最终生成校验；不凭注解末端名称提供诊断或修改建议。

Owner 索引从最近的
`.dart_tool/package_config.json` 获取精确 Package 根，只读取各 Package 固定位置的
`ccrouter_package.json` 及 metadata 指向的 Contract 源文件；不会递归扫描仓库、运行 Generator
或根据类型名猜 Owner。索引按 Pub 图有界缓存，并在 Package config、metadata 或相关 Contract
源码变化时失效。Command/Event/InitTask Contract 本身只进入 metadata，Component API 聚合依赖
Package Catalog，插件不会为它们虚构同源输出。完整依赖闭包、Pattern 冲突、参数 Codec、聚合
入口和生成物指纹仍由 `ccrouter generate --check` 权威校验。

active watch 会把 Workspace Validator 的有界结构诊断原子写入
`.dart_tool/ccrouter/v1/watch/diagnostics.json`。Plugin 不解析日志，只在该 snapshot 与
`status.json` 的 Host/build root、session、cycle、event revision、resolution fingerprint 全部
匹配，且 cycle resolution 未变化时消费；成功、新 cycle/session 会清空旧错误。缺失 Owner
使用 metadata 的 `package:` 坐标定位 authored Dart，同一根因的能力级 fallout 作为 related
locations，不在编辑器重复报错。

无活动 watch 时，Host one-shot generation 会原子发布
`.dart_tool/ccrouter/v1/generation/diagnostics.json`。Plugin 重新计算 Host manifest、build manifest、
lock、Package config 与 Package graph 的逐字节 fingerprint；仅匹配时接受失败终态，成功终态或任一
输入变化都会清除旧诊断。活动 watch 是唯一优先权威，其 building/success/failed 状态均不会回退到
旧 one-shot snapshot。

Analysis Server 不可靠转发 `.dart_tool` 变化，因此 Plugin 每 500ms 比较 context root 及 Workspace
显式嵌套 Host 的 watch/one-shot snapshot、Host manifest 和 resolved graph file identity，变化时才
读取并刷新相关文件，不建立第二套 Analyzer graph。`pubspec.yaml` drift 检查读取当前 Analysis
Server overlay，注释或恢复依赖不必先保存即可出现或撤销提示。Timer 在 context replacement、
plugin shutdown 和 channel close 时取消。`CCROUTER_DISABLE_ANALYZER_WATCH_BRIDGE=1` 可关闭整个
Generator diagnostics bridge；结构诊断读写失败保持 fail-open，不改变 Generator/Pub Hook 的失败
结果，也不替代 `--no-cache --check`。

同文件 Component ID alias graph 优化默认开启；
`CCROUTER_DISABLE_ANALYZER_COMPONENT_ALIAS_GRAPH=1` 只用于恢复重复 declaration scan 做 differential
A/B。它与 tiered polling 是两项独立优化：前者不改变诊断刷新周期，后者默认关闭并以更长的
missed-event 最坏延迟换取较小的单 tick filesystem scan。所有 Analyzer 开关都由长生命周期的
Analysis Server Plugin 进程读取；修改环境变量后必须完整重启 Analysis Server，且 IDE 不一定继承
终端临时环境。无论是否启用这些优化，Plugin 都只是 advisory observer，不与手动生成、watch 或
Pub Hook 构成第二套权威生成结果。

Owner Quick Fix 只在以下条件同时满足时提供：

1. Contract Owner 在 metadata 中唯一；
2. `CCComponent.dependencies` 缺失，或为没有 spread/条件元素的直接 List literal；
3. 当前文件已有明确引用，解析后的 declaring library、import prefix 和常量值与 Owner
   完全一致；同名导入或本地遮蔽不能充当证明；
4. 当前 required 列表尚未包含该 Owner。

插件始终保留“只补当前 Owner”的修复；如果同一个 `CCComponent` 的全部缺失 Owner 都满足上述
条件，还会提供一次补齐全部可证明 Owner 的修复，并按 Component ID 稳定排序。只要其中一个
Owner 缺少可证明的公共常量，就不提供批量修复，避免形成部分自动、部分手工的隐式结果。

复杂变量、spread、条件集合、歧义 Owner、缺失或被 `show/hide` 排除的常量只保留 Generator
门禁；插件不会自动插 import，也不会把 `optionalDependencies` 当作 required 能力依赖。

### Service 生命周期提示与修复

范围限定为解析成功的具体、非泛型 `@CCService` 类。继承链已经实现框架 `CCDisposable`
时不提示；同名的外部接口不能冒充框架身份。

- 已有可调用、无参、非泛型实例 `dispose()`，返回 `void`、非 nullable `Future<void>` 或
  `FutureOr<void>`，但未实现框架接口：提示未接入 Scope。当前 import 唯一暴露正确接口时，
  Quick Fix 仅补 `implements CCDisposable`（或追加到现有接口列表），保留方法体和注释。
  不自动加 import，不承诺原方法已经正确释放所有资源。
- 私有 final 实例字段在声明、构造初始化列表或构造体中直接创建已知可释放资源：提供所有权
  警告，不生成释放方法。支持 generative `CCDisposable` 对象及明确的 SDK/Flutter 常见资源；
  不维护 Dio 等应用供应商类型清单。
- 构造注入、共享引用、任意 factory、辅助方法内分配、注册 Contribution 和复杂数据流不属于
  自动所有权证明。没有警告不表示没有泄漏，Scope 关闭/重入/失败仍应有测试。

这两条是 IDE 开发反馈，不新增 Runtime/Generator 必需接口，也不要求无资源的 Service
编写空释放方法。


## Host 接入与验证

Plugin 是可选 Host 开发工具，不运行 Generator，不后台改写源码。其 Analyzer 依赖图必须与应用和 Generator Workspace 隔离；当前仓库尚未完成 Hosted 发布，不能把下面的版本号当作可下载证据。

已装配 Host 先检查：

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer status demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer doctor demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer pin-check demo
```

手工 bootstrap 的完整目录、manifest、loader 和 analysis_options 配置见[独立接入指南](../skills/ccrouter-integration-development/references/ide-analysis-server.md#manual-host-bootstrap)。Host 必须排除内层 `tools/analyzer_plugin/**` 源码，由隔离图验证 loader。Demo 保持手工装配，不由 CLI 自动接管。

Hosted 发布后优先在 Host 的普通 `dev_dependencies` 中声明已发布的 Plugin 版本，再启用 `analyzer.plugins` 并重启 Analysis Server；当前 Git bootstrap 只使用远端可解析的完整 SHA。安装和运行范围仍受验证过的 SDK/IDE 组合约束。

### CLI 命令与证明边界

已实现：

```text
ccrouter analyzer status [host-root]
ccrouter analyzer doctor [host-root]
ccrouter analyzer pin-check [host-root]
```

写入型命令也已实现；以下三个命令都支持 `--dry-run`：

```text
ccrouter analyzer install [host-root] [--source hosted|git] [--version <range>]
                          [--url <git-url> --ref <full-commit-sha>] [--git-path <package-path>]
ccrouter analyzer upgrade [host-root] [--version <range> | --ref <full-commit-sha>]
ccrouter analyzer uninstall [host-root]
```

#### `install`

- 只面向明确的 Host Package，不把 Workspace 聚合根或组件 Package 猜成 Host。
- 检测当前 Dart 3.10+、Host SDK constraint；loader 固定 Analyzer 8.4.0 / analyzer_plugin 0.13.10，实际解析、分析、编译验证兼容性，不承诺任意 SDK。
- 默认来源为 Hosted，但必须显式 `--version`；仓库版本号不能证明包已发布。Git 必须同时提供远端 HTTPS/SSH URL 和完整 commit SHA，通过临时 bare fetch 验证远端可获取，拒绝本地路径和浮动引用。
- 创建隔离的 `tool/ccrouter_analyzer_host/tools/analyzer_plugin` bootstrap，不把 Plugin Analyzer 依赖混入应用或 Generator
  Workspace。
- 以 YAML 结构叶和 ownership 记录更新 `analysis_options.yaml`，自动添加隔离 loader 的
  `analyzer.exclude`；只认领 CLI 新增的列表项，保留预先存在的相同项、其它规则、注释及祖先
  规则继承。发现未知的同名配置或其它插件冲突时停止并给出差异，不覆盖用户内容。
- 生成前提供 dry-run 摘要；重复执行相同配置不得改写文件或 lockfile。

#### `status`

- 已实现，只读取指定 Host 与最近的 enclosing Workspace Package config。
- 输出 Host、bootstrap 路径、Plugin 来源、Hosted 版本或 Git ref、Analyzer 版本、lockfile
  状态，以及 `analysis_options.yaml` 是否启用 Plugin 并排除其隔离 loader 源码。
- 区分 `notInstalled`、`healthy`、`stale`、`incompatible`、`modified` 和 `incomplete`，不把
  Plugin 状态错误描述成应用构建错误。

#### `doctor`

- 已实现；所有工具检查在 bootstrap 临时副本中执行，不改写活动 bootstrap 的 `.dart_tool`、
  manifest 或 lockfile。
- 先执行 `status`，再验证依赖解析、loader `dart analyze` 和
  `dart compile exe bin/plugin.dart`。
- 不启动常驻 Analysis Server，不运行生成器，不修改配置。
- 检查当前 bootstrap 对应的 legacy 缓存 manifest 和入口，区分 cache artifact
  `absent/current/stale`；stale 保持 advisory，不按 Package 同名误报其他 Host 的缓存。
- cache 异常时以 POSIX `ps` 或 Windows CIM 做只读、保守的进程匹配，报告 PID、PPID、elapsed
  和 command。候选匹配不是所有权证明，CLI 不自动 kill、move 或 delete。
- 分别输出 source pin、cache artifact、temporary loader smoke、Analysis Server restart 与 live IDE
  verification；loader compile 或 `dart analyze` 不能证明运行中的 IDE 已加载插件。
- 给出完整 hash entry 的精确 source/backup 路径；开发者必须先从 IDE 停止 Server、确认进程
  退出，再手工备份整个条目并重启。禁止只移动 `analyzer_plugin` 子目录或清空无关 cache。

#### `pin-check`

- 供 maintainer/release 手动运行，不接入所有 Plugin PR 的默认硬门禁。
- 只接受健康的 Git bootstrap；校验完整 40 位 SHA、manifest/lock/`resolved-ref` 一致，并在
  临时 bare repository 中精确 fetch 该 SHA，拒绝本地 Git URL 和越界 package path。
- 在当前维护仓库中比较 pinned SHA 与工作树的 `packages/ccrouter_analyzer_plugin/lib`。存在
  生产变化时报告 `pending` 及文件列表但返回成功：先验证并推送 Plugin，再在独立提交中 bump
  manifest/lock；bump 后重新运行应报告 `none`。
- 不修改 Host、活动 bootstrap、lockfile、Git index、全局 cache 或 IDE 进程。

#### `upgrade`

- 只在开发者显式给出目标 Hosted 版本或远端 commit SHA 时更新。
- 不自动跟随 `main`，不把本地 HEAD 当作 Git ref，不自动跨 Analyzer 兼容区间。
- 更新前对现有安装运行 `doctor`，新版本先在临时目录通过依赖解析和 doctor，再写入 Host 并执行 Pub；失败时恢复受管配置和已记录的 Pub 解析文件。
- 相同来源/版本且静态状态健康时直接幂等返回，不重新解析或修改 lockfile；改变来源类型需显式卸载后安装。

#### `uninstall`

- 只移除 ownership 记录且摘要仍匹配的四个 bootstrap 文件、记录文件、Host dev_dependency、
  `analysis_options.yaml` 受管叶和 CLI 自己添加的 loader exclude；预先存在的相同 exclude 不删除。
- 保留未知文件、用户 Analyzer 配置和非 CCRouter Plugin。
- 可先执行 `--dry-run`；部分内容被用户修改时拒绝删除，并给出手工处理范围。现有手工 bootstrap 不自动采用或迁移。

#### Hosted 迁移与弃用冻结（2026-10-05）

`ccrouter analyzer install` 与 `upgrade` 进入 legacy maintenance-only 状态：实现保留可回滚
能力，不再增加新的来源、IDE 或 SDK 管理特性，执行时会明确输出弃用提示。`status`、`doctor`
和 `uninstall` 保留，用于诊断和撤销已有隔离 bootstrap；`doctor` 对私有
`.dartServer/.plugin_manager` 只给 advisory，不把跨 SDK 的缓存目录当作权威门禁。普通 Hosted
依赖的推荐迁移方式是直接编辑 Host：

```yaml
dev_dependencies:
  ccrouter_analyzer_plugin: ^0.1.0
```

再在 `analysis_options.yaml` 启用插件并执行普通 `dart analyze`/IDE 重启。仓库保留
`demo/tools/ccrouter_analyzer_plugin_host/tools/analyzer_plugin/pubspec.hosted.yaml` 作为发布后
替换模板；在 Hosted 版本真正可解析前，Demo 继续使用固定 Git SHA，不执行隐式切换。

### 所有权、失败与回滚

- CLI 拥有固定 bootstrap 路径及 `.ccrouter-analyzer.json` 记录的配置叶；loader exclude 采用
  列表项级 ownership，只有 CLI 新增时才拥有，不拥有 Host 的其它 IDE 配置。
- Plugin 是开发期可选能力；任何安装、加载和版本故障都不得改变生成物、Runtime 或业务结果。
- 文件写入采用临时文件和原子替换；多文件操作保留本次备份，全部验证成功后才完成提交。
- `--dry-run` 不启动子进程、不写文件；实际操作在 Pub owner 下使用非阻塞文件锁，多 Host 共用 Workspace 时串行修改。
- 只安装明确的 Flutter Host：Package 必须直接依赖 `ccrouter`，并由 `.metadata` 的
  `project_type: app` 或 `ccrouter.yaml` 的 `host.enabled: true` 证明 Host 角色；
  `host.enabled: false` 可显式降级。`lib/main.dart` 不是 Host 证据，Workspace 聚合根及普通组件
  不接受安装。
- 多 Host Workspace 必须逐 Host 装配；命令不扫描并批量修改所有 Package。
- 执行后提示重启 Dart Analysis Server 或 IDE，但 CLI 不主动终止 IDE 进程。

提交 Host 的 pubspec/options、四个 bootstrap 文件、ownership 记录和 Pub lockfile；不要提交
`.dart_tool`。Host Pub 使用当前 Dart 所属 Flutter SDK，并禁用 Pub Hook，不运行生成器。
事务记录位于 canonical Pub owner 对应的 project-isolated
`CCROUTER_HOME/coordination/v2/.../analyzer/transactions/`，保存原始字节；operation lock 与其
同级，因此 `flutter clean` 不会解除活动写事务或删除恢复证据。普通
失败恢复本次受管配置及 Host/Workspace 的 lockfile、package_config、package_graph、Flutter
plugins dependency 文件。不会回滚全局 Pub cache 或其它平台缓存。并发用户改动、无法读取的
Pub 结果或进程中断保留恢复记录，后续写命令拒绝继续；核对记录中的明确路径后恢复，不能清空
缓存来绕过。未知文件保留。子进程输出有界，单阶段三分钟超时并结束子进程。


### Demo pin 的两阶段流程

当前 SHA 只由 Demo 活动 bootstrap manifest 与 lockfile 维护，不在文档复制第三份值。Plugin 生产行为变化时先完成独立 Package 的分析、测试、提交和推送；随后以远端可解析的完整 SHA，在独立变更中更新 Demo manifest/lock。

运行 `ccrouter analyzer pin-check demo` 验证来源与生产 drift，再运行 `doctor demo`、重启 Dart Analysis Server，并以真实诊断或 Quick Fix 证明 live 加载。第一阶段的 `pending` 是预期状态，不是普通 Plugin PR 的失败门禁；测试、注释和行为不变的重构不要求 bump。不得把修改 pin 的提交本身、未推送 SHA、分支或浮动 tag 作为 pin。

未经用户明确要求，不升级版本或 ref，不接管手工 bootstrap；工具故障仍保留普通 Analyzer 与 `generate --check`。报告中分别说明静态状态、临时 loader、真实 IDE 加载，不合并为一个“通过”。

### 真实 Server 自动回归

在插件 Package 执行 `fvm dart test test/analysis_server_integration_test.dart`。
它启动当前 SDK 的官方 JIT `analysis_server.dart.snapshot`，使用独立临时 Host、缓存和
本地源码 loader，通过 Legacy/LSP 协议验收，不直接调用 Plugin 充当端到端测试。

- 未保存 overlay、移除 overlay 恢复磁盘内容、连续编辑最终结果。
- `edit.getFixes` 和 LSP `codeAction` 的真实修复内容、应用后重新分析。
- Route/Service/Command/Event/InitTask 生成文件新增、修改、重命名、删除与重建。
  LSP 会去重相同诊断，因此内容修改无告警变化时不要求收到重复通知。
- Dart Workspace 内跨 Package 的 Owner metadata 增删/修改与 Contract 源码变更。
- Server/Plugin 错误或退出视为失败；超时与退出均清理进程、订阅和临时目录。

插件将精确
`ccrouter_package.json` 加入关注路径；重新装配分析根时释放 Context 引用和旧索引。
磁盘 fixture 验证监听效果，不等于在这些 fixture 上执行过 `clean/generate`。
生成物正确性仍由独立的真实 CLI 回归保证。

规模诊断可在启动 Server 前设置 `CCROUTER_ENABLE_ANALYZER_TIERED_POLL=1`。该实验模式保留文件
事件和 validated generation epoch 的即时刷新，只把 exact-path 丢事件兜底分为 10 个 500ms
shard；所有 shard 的 affected source 并集必须与一次 full scan 完全一致。它默认关闭，最坏
fallback 刷新时间为 5 秒，不能用来替代最终生成检查。

当前验证基于 Dart 3.11.5，不宣称覆盖所有 IDE/SDK。无 manifest 的临时 loader 绕过 Pub 与
用户插件缓存；AOT loader 编译、发布 bootstrap 复制、固定 Git ref 和 IDE UI 另行验证。
独立多根 Package 同时冷启动时，当前 SDK 的 legacy PluginManager 可能并发启动同一路径
插件的多个 isolate，分别只持有部分 Context，造成跨根通知遗漏；本测试覆盖共享 Dart
Workspace，不把这一 SDK 边界标记为已解决。分析根外的依赖文件也没有自动监听承诺。

### Field-formal 参数注解的 IDE 跳转限制

截至 2026-10-04，在 Android Studio 2026.1.4、Dart Plugin 509.0.0 与 OHOS Flutter 内置
Dart 3.11.5 的组合中，光标位于 field-formal parameter 上的 `@CCQueryParam()` 或
`@CCExtraParam()` 时，普通 Go to Declaration（macOS `Cmd+B`）会提示
`Cannot find declaration to go to`。命名参数、位置参数和 required/optional 形态都会触发，
例如：

```dart
const DetailPage({
  @CCQueryParam() this.tab = 'summary',
  @CCExtraParam() this.snapshot,
});
```

这是当前 Dart Analysis Server/IDE 导航链的上游限制，不是 CCRouter 注解声明、barrel export、
Generator 或 `ccrouter_analyzer_plugin` 的解析错误：

1. 对同一源码位置直接请求 legacy `analysis.getNavigation`，可以正确返回
   `route_annotation.dart` 中的注解声明；LSP `textDocument/definition` 也返回相同目标。
2. 订阅整文件 `analysis.navigation` 时，通知包含类级 `CCRoute`，却遗漏 field-formal
   parameter metadata 中的 `CCQueryParam`/`CCExtraParam`。
3. 当前 navigation collector 的 `visitFieldFormalParameter` 路径处理字段、类型、类型参数和
   函数参数，但没有继续遍历该参数的 `metadata`。Android Studio 当前 `Cmd+B` 消费这份整文件
   navigation 数据，因此没有可跳转目标。
4. 临时移除 Demo 的 CCRouter Analyzer Plugin 配置、重启 Analysis Server，以及禁用第三方
   Translation Plugin 后分别复验，结果不变。清理 CCRouter 生成物或 IDE 缓存不会补回缺失的
   Server navigation region。

当前无侵入 workaround 是使用 Go to Type Declaration（macOS `Cmd+Shift+B`）；已在上述环境
对 `CCQueryParam` 完成真实 IDE 跳转验证，且两个注解的 LSP definition 请求均能解析到声明。
不要仅为 IDE 跳转把 field-formal parameter 批量改写为
普通参数加 initializer，这会制造无业务收益的源码 churn，且注解原有生成、类型检查和运行时
语义均正常。

Dart Plugin 509.0.0 只有在启用 Experimental LSP Features 且项目 Dart SDK 不低于
`3.14.0-65.0.dev` 时，才允许普通 Go to Definition 走 LSP navigation。Flutter/OHOS 项目使用
Flutter 分发版内置的 Dart SDK，不能通过单独替换系统 Dart 安全升级。后续升级整个 SDK 后，
必须同时复验整文件 `analysis.navigation`、LSP definition 和真实 IDE `Cmd+B`；达到版本门槛
本身不是上游缺陷已经修复的证明。

该问题归类为 Developer Experience gap。它不影响 `dart analyze`、CCRouter 生成、
`generate --check` 或 Runtime 路由参数语义，也不应通过修改 CCRouter public API、放宽生成器
校验或清理全局缓存规避。

## 诊断与生成的协作顺序

编辑带 CCRouter 能力注解的源码时，先保存源代码并继续完成业务修改；插件提示是开发反馈，生成物
缺失不会由插件自动补写。准备运行、提交或切换 Package 依赖时执行：

```bash
fvm dart run ccrouter_generator:ccrouter generate demo
fvm dart run ccrouter_generator:ccrouter generate demo --check
```

若插件显示跨 Package 内部生成物导入，应改为 Owner 的公开 Contract 或 Host barrel；不能用
`// ignore` 绕过，因为 Generator 的跨包边界校验仍会拒绝它。

## 版本与失败策略

- 插件使用独立的 Analyzer/`analyzer_plugin` 兼容矩阵；升级 Dart SDK 或 Analyzer 时先运行
  插件 Package 的 analyze/test，再在 Android Studio 和 VS Code 各重启一次 Analysis Server。
- 插件启动失败、版本不兼容或诊断异常时，Analysis Server 应隔离该插件；业务分析继续由 Dart
  Analyzer 提供，最终正确性由 `generate --check` 保证。
- 插件不提供后台自动修复、自动插入 import、自动生成和运行时导航。当前 Quick Fix 只允许
  开发者显式选择删除 Route `pattern/patterns`、InitTask `contract/id` 中的一个冲突参数，或把
  Metadata 唯一证明且已经由公共 import 暴露的一个或全部 Owner 常量加入直接 required
  dependency List。
  另可为符合上述条件的 Service 补 `CCDisposable` 接口，但不生成资源清理逻辑。
  注释可能被覆盖、集合包含 spread/条件元素、Owner/import 不唯一时不提供；插件不会创建
  Contract、猜 alias/ID/timeout、改 pubspec 或运行生成。

## 已完成与剩余边界

官方只读 DevTools Extension、Component Graph、Catalog/Runtime 联动和单次能力 Call Graph
已经交付。静态 Catalog 携带 source location，嵌入式面板支持 Host `onOpenSource` callback；
官方 Extension 当前展示并复制 source URI，但不直接绑定 VS Code、Android Studio 或任意本地
IDE。因此：

- “找到 Route/Service/Command/Event/InitTask 的源码位置”已完成；
- “只读查看组件依赖、反向依赖和调用链”已完成；
- “从官方 Extension 直接调用本地 IDE 打开文件”未完成；
- 自动生成、自动 import、rename/alias migration Quick Fix 仍未实现；已提供互斥参数删除和受限
  Service/Command required Owner 补齐。
  已有 Service dispose 接入 Scope 的受限 Quick Fix 也已提供；复杂资源释放仍需人工设计。

这些剩余项不改变 Analyzer Plugin 的“不生成、无后台改写、显式安全 Quick Fix”边界。
DevTools 当前实现与协议见 [`CCRouter-devtools.md`](CCRouter-devtools.md)，发布门槛见
[Release Readiness](CCRouter-release-readiness.md)。


## 文档职责

本规范统一维护诊断、CLI 装配、失败与 pin 规则。[CLI 原计划](archive/20261024-consolidation/CCRouter-analyzer-cli-plan.md)与[合并前 IDE 文档](archive/20261024-consolidation/CCRouter-ide-analysis-server.md)保存阶段验收、配置演进与当时证据；不代表本轮重跑。当前验证从[验证索引](validation/README.md)查阅，待补矩阵由[后续工作](CCRouter-future-work-plan.md)维护。
