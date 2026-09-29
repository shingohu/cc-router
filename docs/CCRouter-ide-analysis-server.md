# CCRouter IDE / Analysis Server 集成

## 目标与边界

CCRouter 的 IDE 支持分成四层：

1. 生成的 Dart Route API 和公共 Contract barrel 负责补全、类型检查和自动导包。
2. `ccrouter find` 与 Package Catalog 负责能力到源码位置的确定性查找。
3. `ccrouter_analyzer_plugin` 负责编辑过程中的轻量实时诊断。
4. `ccrouter generate --check` 负责最终生成物、依赖闭包和 metadata 门禁。

Analysis Server Plugin 不运行 `build_runner`，不修改业务源文件，不替代 Generator/Workspace
Validator，也不读取 Runtime 或隐式全局状态。插件不可用时，项目仍可通过普通 Dart Analyzer 和
CLI 门禁工作；缺少实时提示不会改变构建语义。

## 当前提供的诊断

| Code | 默认级别 | 作用 |
| --- | --- | --- |
| `ccrouter_cross_package_generated_import` | error | 阻止业务 Package 直接导入另一个 Package 的 `src/ccrouter_generated` |
| `ccrouter_generated_output_missing` | warning | 标记 `@CCRoute` 源文件对应的 Route 生成物尚未生成 |

诊断只处理单文件和当前 Package 的可确定信息。Contract Owner、依赖闭包、Pattern 冲突、
参数 Codec、生成物指纹等跨文件规则仍由 `ccrouter generate --check` 权威校验。

## 接入步骤

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
Analysis Server 或 IDE。插件会在编辑 `.dart` 文件时发送标准 `analysis.errors` 诊断。

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
`97c72daae65d0dd01e1ecd5263c647d6b213f814`，提交规则 Package 后可由 Analysis Server
复制到临时目录并正常启动。bootstrap 目录同时保留 `pubspec.hosted.yaml` 作为发布后的
Hosted fallback；发布到 Hosted 后只能二选一替换活动 manifest，不能在同一个 bootstrap
Package 同时声明 Git 和 Hosted 两个来源。

Loader smoke 使用 `dart analyze` 和 `dart compile exe bin/plugin.dart`，只验证依赖解析和
Analysis Server entrypoint 可加载，不会启动常驻 Analysis Server。插件启动失败或版本不兼容
时，应关闭该 bootstrap，继续使用 Dart Analyzer 和 `ccrouter generate --check`；这不会改变
应用构建或生成器门禁。

修改 `packages/ccrouter_analyzer_plugin` 后，在尚未推送并固定到远端的本地工作区，不能直接
用 Git bootstrap 验证新代码。可在 bootstrap 的临时本地验证环境中使用绝对 path override
验证，验证完成后恢复固定 Git ref；绝对 path 不得提交。Git ref 更新前必须先运行插件
Package 的 analyze/test 和 loader smoke。

Demo 运行时还接入了 `ccrouter_devtools`：进入 Navigation Lab 的“诊断”分区，点击
“打开 CCRouter DevTools”，即可查看只读 Overview、Components、Entries、Timeline、
Failures 和 InitTask DAG。该入口使用应用自己的本地 BottomSheet，不会把 DevTools 变成
CCRouter 管理页面，也不会增加 Runtime 控制 API。

## 诊断与生成的协作顺序

编辑带 `@CCRoute` 的页面时，先保存源代码并继续完成业务修改；插件提示是开发反馈，生成物
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
- 插件不提供自动修复、自动插入 import、自动生成和运行时导航。任何自动写入都必须由未来
  独立的 IDE/CLI 设计明确授权，不能隐藏在 Analysis Server isolate 中。

## 已完成与剩余边界

官方只读 DevTools Extension、Component Graph、Catalog/Runtime 联动和单次能力 Call Graph
已经交付。静态 Catalog 携带 source location，嵌入式面板支持 Host `onOpenSource` callback；
官方 Extension 当前展示并复制 source URI，但不直接绑定 VS Code、Android Studio 或任意本地
IDE。因此：

- “找到 Route/Service/Command/Event/InitTask 的源码位置”已完成；
- “只读查看组件依赖、反向依赖和调用链”已完成；
- “从官方 Extension 直接调用本地 IDE 打开文件”未完成；
- 自动生成、自动 import、rename/alias migration Quick Fix 仍未实现。

这些剩余项不改变 Analyzer Plugin 的“只诊断、不生成、不改写”边界。DevTools 当前实现与
协议见 [`CCRouter-devtools.md`](CCRouter-devtools.md)，发布门槛见
[`CCRouter-pre-release-capability-plan.md`](CCRouter-pre-release-capability-plan.md)。
