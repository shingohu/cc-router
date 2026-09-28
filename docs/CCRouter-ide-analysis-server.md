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

插件 Package 位于 `packages/ccrouter_analyzer_plugin`，当前因为官方
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

## 后续评估

当前不承诺 IDE 内专用 Route-to-source 导航、Component Graph 面板或官方 DevTools Extension。
可嵌入的只读诊断面板已由 `ccrouter_devtools` 提供；IDE 深度跳转和官方 Extension 可复用
Package Catalog 的 source location metadata，在真实项目验证导航误报率和索引规模后再单独立项。
