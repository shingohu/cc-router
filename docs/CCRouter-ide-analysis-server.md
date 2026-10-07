# CCRouter IDE / Analysis Server 集成

> 文档状态：当前接入契约与已知限制。Plugin 提供单文件诊断、按需类型解析和 Metadata 驱动的
> Service/Command Owner 检查，Generator/Workspace Validator 仍是跨 Package 正确性的最终门禁。

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
| `ccrouter_cross_package_generated_import` | error | 阻止业务 Package 直接导入另一个 Package 的 `src/ccrouter_generated` |
| `ccrouter_generated_output_missing` | warning | 标记 Route/Binding、Route/Service Contract、Service、Command Handler、Event Subscription 或 InitTask 的确定性同源输出缺失 |
| `ccrouter_required_init_task_contract_missing` | error | required InitTask 必须使用稳定的 `CCInitTaskContract` |
| `ccrouter_required_init_task_timeout_missing` | error | 异步 required InitTask 必须声明 timeout |
| `ccrouter_handler_declaration_invalid` | error | Handler 必须是 public、top-level、non-generic 函数 |
| `ccrouter_handler_signature_invalid` | error | 标记明显不支持的 Handler 参数数量或 void 返回形态 |
| `ccrouter_annotation_arguments_conflict` | error | 标记 Route `pattern/patterns` 或 InitTask `contract/id` 冲突 |
| `ccrouter_identifier_invalid` | error | 校验可确定的字面量 Route/Service/Command/Event/InitTask/Gate ID |
| `ccrouter_alias_invalid` | error | 校验可确定的 Service/Command Client alias |
| `ccrouter_timeout_invalid` | error | 拒绝可确定的零值或负值 InitTask timeout |
| `ccrouter_component_owner_dependency_missing` | error | Service/Command Contract Owner 未进入消费组件 required `dependencies` |
| `ccrouter_host_component_owner_missing` | error | active watch 已证明 Host closure 缺少能力声明的 Owner；同一根因的级联错误折叠显示 |
| `ccrouter_pub_resolution_stale` | warning | 保存的 Host dependencies 与 resolved Pub graph 不一致；先运行 Pub get，期间暂停 Owner 推断 |
| `ccrouter_service_disposable_missing` | warning | 注解 Service 已有兼容的实例 `dispose()`，却未实现 Scope 识别的 `CCDisposable` |
| `ccrouter_service_owned_resource` | warning | 注解 Service 的私有 final 字段直接持有自建可释放资源，但 Service 没有接入 Scope 释放 |

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

## 接入步骤

当前接入仍为手工 bootstrap。CLI 已提供只读的 Host 状态和健康检查：

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer status demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer doctor demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer pin-check demo
```

`status` 区分 `notInstalled`、`incomplete`、`stale`、`incompatible`、`modified` 和
`healthy`，并输出实际 bootstrap、来源、固定 Git ref/Hosted 版本及 Analyzer 版本；它只证明
静态配置一致，不证明 Git 凭据可用或 Analysis Server 已成功加载插件。
`doctor` 只在静态状态健康时，在临时副本中校验 lockfile、执行 bootstrap analyze 和 loader
compile；不修改 Host、活动 bootstrap manifest 或 lockfile，也不运行 Generator。Git 凭据或
SSH Key 不可用时会明确说明 IDE 诊断尚不可用。输出分别标记 source pin、cache artifact、
temporary loader smoke、Analysis Server restart 和 live IDE verification；bootstrap analyze 或
loader compile 不能升级为 live success。对当前 bootstrap 路径及其真实路径对应的 legacy
plugin-manager 条目，`doctor` 会比较 manifest 和 `bin/plugin.dart`，报告
`absent/current/stale`，不按同名 Package 猜测其它 Host 的缓存所有权。该检查适配 Dart 3.11
的路径 MD5 缓存键；它不是生成物内容证明，SDK 改变缓存布局后仍需真实加载验收。

`pin-check` 只供 maintainer/release 手动运行。它复用静态 identity 检查，在临时 bare Git
repository 中验证完整 SHA 可从 manifest 声明的远端精确 fetch，并报告该 pin 到当前工作树的
`packages/ccrouter_analyzer_plugin/lib` 生产变化。`pending` 是两阶段流程中第一阶段提交/推送后
的预期状态，不导致命令失败，也不应成为所有 Plugin PR 的默认门禁；pin bump 后应重新运行并
得到 `none`。命令不修改 Host、lockfile、Git index 或全局 cache。

发现问题时，doctor 会尽可能报告候选进程的 PID、PPID、elapsed、command 以及每个 cache
entry 的精确 source/backup 路径。候选命令匹配不是所有权证明，CLI 不自动 kill、move 或
delete。先从 IDE 停止 Analysis Server，确认相关进程退出，再将 doctor 列出的**整个哈希条目
目录**手工移到 `~/.dartServer/.plugin_manager` 外备份，之后重启并运行 doctor。不能只移走条目中的
`analyzer_plugin` 子目录：Dart 3.11 会复用仍存在的父目录，随后因 `bin/plugin.dart` 缺失
而启动失败。不能清空整个 Pub cache 或其它插件缓存。

`install/upgrade/uninstall` 已提供显式 Host 自动装配及 `--dry-run`，其中 install/upgrade
进入 legacy maintenance-only 状态并会提示弃用。Hosted 必须指定已发布版本，Git 必须指定远端 URL
和完整 SHA；候选 loader 验证成功后才写 Host。Hosted 发布后优先使用普通 `dev_dependency`：

```yaml
dev_dependencies:
  ccrouter_analyzer_plugin: ^0.1.0
```

已有手工 bootstrap
不自动接管，Demo 保持原配置；CLI 成功也不代表正在运行的 IDE 已重新加载。完整边界见
[`CCRouter-analyzer-cli-plan.md`](CCRouter-analyzer-cli-plan.md)。Analyzer 装配不会挂入
`generate`、Pub Hook 或组件脚手架隐式执行。

插件规则 Package 位于 `packages/ccrouter_analyzer_plugin`，当前因为官方
`analyzer_plugin` 版本与生成器的 Analyzer 版本约束不同，未加入主 Dart Workspace；这避免
为了 IDE 工具降级生成器和全仓 Analyzer。正式接入前应发布到 Hosted（推荐），再在宿主
Package 中作为 `dev_dependency` 引入：

```yaml
dev_dependencies:
  ccrouter_analyzer_plugin: ^0.1.0
```

然后在宿主 Package 的 `analysis_options.yaml` 启用：

```yaml
analyzer:
  plugins:
    - ccrouter_analyzer_plugin
```

Android Studio、IntelliJ 和 VS Code 使用同一个 Dart Analysis Server 配置；启用后重启
Analysis Server 或 IDE。插件会在编辑 `.dart` 文件时发送标准 `analysis.errors` 诊断，并读取
当前未保存的 overlay；删除 required Owner 等问题不需要等到保存或运行 Generator 后才出现。
Plugin 初始化只分析开发者编写的 Dart 源码，跳过平台/build 产物和 CCRouter 生成库。

`dart analyze` 不能证明 CCRouter Plugin 已加载到当前 IDE 会话。Dart 3.11.5 在分析范围命中
Host 的 `analysis_options.yaml` 与 bootstrap 时会初始化 Plugin manager，可能报告 Plugin
诊断，也可能暴露 Server/Plugin 启动或兼容性失败；它不能再被视为“只运行 Dart 内置规则”。
该行为取决于 SDK、分析范围和 bootstrap 状态。实时闭环仍应使用 Android Studio、IntelliJ、
VS Code 或真实 Language Server 协议测试；跨文件与生成物最终正确性继续由
`ccrouter generate --check` 保证。

当前仓库尚未发布 Package 时，可先在插件 Package 本身验证：

```bash
cd packages/ccrouter_analyzer_plugin
dart pub get
dart analyze
dart test

cd tools/analyzer_plugin
dart pub get
dart analyze
```

工具包的 `pubspec_overrides.yaml` 只用于本地加载器编译验证，不应复制到发布物中。

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

本轮修复原始磁盘路径被 Analyzer import 依赖图过滤的问题，并将精确
`ccrouter_package.json` 加入插件关注路径。重新装配分析根时释放 Context 引用和旧索引。
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

watch diagnostics bridge 与 canonical Host identity 修复已推送，并进入 Demo 固定的远端
commit。当前值以 Demo bootstrap manifest/lock 为准；两者必须保持一致。运行 doctor 后仍需
重启 IDE，不能仅凭依赖解析或本地插件测试声称正在运行的 IDE 已升级。

## Demo 接入

`demo/analysis_options.yaml` 已启用 `ccrouter_demo_analyzer_plugin`。这是一个只属于 Demo
Host 的 bootstrap Package，位置为：

```text
demo/tools/ccrouter_analyzer_plugin_host/
└── tools/analyzer_plugin/
    ├── pubspec.yaml
    └── bin/plugin.dart
```

Demo 的 `pubspec.yaml` 只依赖这个不带 Analyzer 约束的 Host Package；真正的规则 Package
在 bootstrap 的独立依赖环境中解析。这样不会把 Analyzer 8.4.0 与 Workspace 生成器的
Analyzer 10 混在一个依赖图里。bootstrap 当前使用远端 `main` 上固定的完整 commit；其
source of truth 是活动 `pubspec.yaml` 与 `pubspec.lock` 的 `resolved-ref`，可由 Analysis Server
复制到临时目录并正常启动。bootstrap 目录同时保留 `pubspec.hosted.yaml` 作为发布后的
Hosted fallback；发布到 Hosted 后只能二选一替换活动 manifest，不能在同一个 bootstrap
Package 同时声明 Git 和 Hosted 两个来源。

Loader smoke 使用 `dart analyze` 和 `dart compile exe bin/plugin.dart`，只验证依赖解析和
Analysis Server entrypoint 可加载，不会启动常驻 Analysis Server。插件启动失败或版本不兼容
时，应关闭该 bootstrap，继续使用 Dart Analyzer 和 `ccrouter generate --check`；这不会改变
应用构建或生成器门禁。

通常优先用 `ccrouter analyzer doctor demo` 执行相同 smoke；直接进入 bootstrap 目录的命令
保留为 CLI 不可用时的排障回退。

修改 `packages/ccrouter_analyzer_plugin` 后，在尚未推送并固定到远端的本地工作区，不能直接
用 Git bootstrap 验证新代码。可在 bootstrap 的临时本地验证环境中使用绝对 path override
验证，验证完成后恢复固定 Git ref；绝对 path 不得提交。Git ref 更新前必须先运行插件
Package 的 analyze/test 和 loader smoke。

当前固定 ref 已包含 2026-10-03 完成的
F14/F15 类型与 Owner 修复、Service 生命周期诊断，以及既有的单个/批量 Owner Quick Fix、
未保存 overlay 诊断、性能缓存、structured watch diagnostics bridge、canonical Host identity
和只读 CLI 健康检查。无需仅为追随本地 HEAD 而更新。只有 Plugin 生产代码真实变化、隔离测试
通过并推送远端后，才更新为对应的完整 commit SHA；禁止使用 `main` 或尚未推送的本地 SHA。

该同步是强制的两阶段流程，不能把“之后再更新 Demo”留作隐含约定：第一阶段独立提交并验证
Plugin，推送后确保完整 SHA 可被 bootstrap 的 Git URL 解析；第二阶段用另一个提交执行
`ccrouter analyzer upgrade demo --ref <full-sha>`，提交 manifest 与 lockfile，再运行
`ccrouter analyzer doctor demo`。随后重启 Dart Analysis Server，并用真实 diagnostic 或 Quick Fix
确认 IDE 已加载新版本。一个提交不能让依赖 ref 指向它自身，也不能使用浮动 tag。纯测试、注释
和不改变行为的重构不要求更新 ref。除非新 Plugin 改动同时改变 SDK 兼容区间，否则不要顺带升级
隔离 bootstrap 的 `analyzer`/`analyzer_plugin` 版本。

2026-10-03 的 F14/F15、Service 生命周期诊断等旧修复，以及后续 watch diagnostics bridge 与
canonical identity 改动，均已完成各自的插件测试并推送远端；Demo bootstrap 当前值只在
活动 manifest/lock 中维护。任何 ref 更新都不等于正在运行的 IDE 已重新加载，仍需重启 Dart
Analysis Server 后验证新增规则。

2026-10-03 已完成本机 Android Studio 的实际验收：关闭工程停止 Analysis Server，备份
指定旧缓存条目后重开；临时 `@CCService` 的既有 `dispose()` 触发
`ccrouter_service_disposable_missing`，IDE Quick Fix 补入 `implements CCDisposable` 后
该警告消失，普通 Dart 的 `@override` 提示继续正常工作。临时文件已移出工程。
这证明本机当前 SDK/IDE 的此条链路，不代表 VS Code、全部诊断或完整文件监听矩阵均已验收。

Demo 运行时还接入了 `ccrouter_devtools`：进入 Navigation Lab 的“诊断”分区，点击
“打开 CCRouter DevTools”，即可查看只读 Overview、Components、Entries、Timeline、
Failures 和 InitTask DAG。该入口使用应用自己的本地 BottomSheet，不会把 DevTools 变成
CCRouter 管理页面，也不会增加 Runtime 控制 API。

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
[`CCRouter-pre-release-capability-plan.md`](CCRouter-pre-release-capability-plan.md)。
