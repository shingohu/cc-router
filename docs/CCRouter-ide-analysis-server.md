# CCRouter IDE / Analysis Server 集成

> 文档状态：当前接入契约与已知限制。Plugin 提供低误报单文件诊断和 Metadata 驱动的
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

除 Owner 规则外，这些诊断只处理单文件和当前 Package 的可确定信息。Owner 规则从最近的
`.dart_tool/package_config.json` 获取精确 Package 根，只读取各 Package 固定位置的
`ccrouter_package.json` 及 metadata 指向的 Contract 源文件；不会递归扫描仓库、运行 Generator
或根据类型名猜 Owner。索引按 Pub 图有界缓存，并在 Package config、metadata 或相关 Contract
源码变化时失效。Command/Event/InitTask Contract 本身只进入 metadata，Component API 聚合依赖
Package Catalog，插件不会为它们虚构同源输出。完整依赖闭包、Pattern 冲突、参数 Codec、聚合
入口和生成物指纹仍由 `ccrouter generate --check` 权威校验。

Owner Quick Fix 只在以下条件同时满足时提供：

1. Contract Owner 在 metadata 中唯一；
2. `CCComponent.dependencies` 缺失，或为没有 spread/条件元素的直接 List literal；
3. 当前文件已有公共 import，并且递归 export 校验能证明该 import 暴露的
   `CCComponentId` 常量值与 Owner 完全一致；
4. 当前 required 列表尚未包含该 Owner。

插件始终保留“只补当前 Owner”的修复；如果同一个 `CCComponent` 的全部缺失 Owner 都满足上述
条件，还会提供一次补齐全部可证明 Owner 的修复，并按 Component ID 稳定排序。只要其中一个
Owner 缺少可证明的公共常量，就不提供批量修复，避免形成部分自动、部分手工的隐式结果。

复杂变量、spread、条件集合、歧义 Owner、缺失或被 `show/hide` 排除的常量只保留 Generator
门禁；插件不会自动插 import，也不会把 `optionalDependencies` 当作 required 能力依赖。

## 接入步骤

当前接入仍为手工 bootstrap。CLI 已提供只读的 Host 状态和健康检查：

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer status demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer doctor demo
```

`status` 区分 `notInstalled`、`incomplete`、`stale`、`incompatible`、`modified` 和
`healthy`，并输出实际 bootstrap、来源、固定 Git ref/Hosted 版本及 Analyzer 版本；它只证明
静态配置一致，不证明 Git 凭据可用或 Analysis Server 已成功加载插件。
`doctor` 只在静态状态健康时，在临时副本中校验 lockfile、执行 bootstrap analyze 和 loader
compile；不修改 Host、活动 bootstrap manifest 或 lockfile，也不运行 Generator。Git 凭据或
SSH Key 不可用时会明确说明 IDE 诊断尚不可用；`doctor` 通过后，bootstrap/ref 变化仍需重启
Dart Analysis Server。若 `~/.dartServer/.plugin_manager` 中同名 bootstrap 副本与当前 manifest
不一致，`doctor` 会只读失败并列出准确目录；停止 Analysis Server、只移走该缓存目录并重启，
不能清空整个 Pub cache 或其它插件缓存。

计划中的 `install/upgrade/uninstall` 尚未实现，不能写入当前接入脚本或 CI。完整边界见
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

`dart analyze` 不运行 legacy Analysis Server Plugin，因此它只适合验证 Dart 自带规则，不能用来
证明 CCRouter IDE 诊断已经加载。实时闭环应使用 Android Studio、IntelliJ、VS Code 或真实
Language Server 协议测试；跨文件与生成物最终正确性继续由 `ccrouter generate --check` 保证。

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
Analyzer 10 混在一个依赖图里。bootstrap 当前使用远端 `main` 上固定的 commit
`c9495775b5da61ba8c63c7597939e3350bb08c0f`，可由 Analysis Server
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

当前固定 ref `c9495775b5da61ba8c63c7597939e3350bb08c0f` 已包含 2026-09-30 完成的规则、单个/批量
Owner Quick Fix、未保存 overlay 诊断、性能缓存和只读 CLI 健康检查，无需仅为追随本地 HEAD 而更新。只有 Plugin
生产代码真实变化、隔离测试通过并
推送远端后，才更新为对应的完整 commit SHA；禁止使用 `main` 或尚未推送的本地 SHA。

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

这些剩余项不改变 Analyzer Plugin 的“不生成、无后台改写、显式安全 Quick Fix”边界。
DevTools 当前实现与协议见 [`CCRouter-devtools.md`](CCRouter-devtools.md)，发布门槛见
[`CCRouter-pre-release-capability-plan.md`](CCRouter-pre-release-capability-plan.md)。
