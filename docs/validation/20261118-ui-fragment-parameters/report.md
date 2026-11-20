# UI Fragment 参数统一与 Demo Plugin pin 验证（2026-11-18）

本报告归档本轮已执行的验证，不代表重新执行全部测试或发布验收。当前接入方式以
[UI 接入指南](../../../skills/ccrouter-integration-development/references/ui-fragments.md)和
[UI Fragment 规范](../../CCRouter-ui-fragment-design.md)为准；旧报告保留其原始源码身份和结论。

## 源码身份与改动范围

- 基线：`6643a2bec4a2eac1b69e8180ece309e13517a8a5`。
- 第一阶段：`30204ef9a8dffcc595128915cca3cf66fe18da45`，统一 UI 声明参数、生成器、Plugin
  诊断、Demo 与开发者指导。第一阶段测试在提交前、相同生产源码上执行。
- 第二阶段：`9e96b695ec8f9a06c61eac6589dda51ce3eee18f`，仅更新 Demo bootstrap 的
  manifest 和 lockfile，将 Plugin 锁定到第一阶段已推送的完整 SHA；未升级隔离的
  `analyzer: 8.4.0` 或 `analyzer_plugin: 0.13.10`。
- 本次文档归档以第二阶段提交为源码基准，不修改功能代码、提交或推送。

归档时补录的 [SDK 身份](sdk-version.log)为 Dart `3.11.5` / `macos_arm64`。
本轮执行使用 FVM 的 `ohos/oh-3.41.9-release` SDK；这是执行来源记录，不是新增平台认证。

这些 SHA 记录本轮历史证据，不作为后续开发者复制的安装配置。当前 Plugin SHA 始终读取
[Demo bootstrap manifest](../../../demo/tools/ccrouter_analyzer_plugin_host/tools/analyzer_plugin/pubspec.yaml)
和 [lockfile](../../../demo/tools/ccrouter_analyzer_plugin_host/tools/analyzer_plugin/pubspec.lock)。

`CCUIFragmentContract` 新增可选 `alias`、`description`，`version` 默认 `0.1.0`。
`CCUIFragmentDependency` 仅接受可选 `alias`，移除公开的 `versionRange`。方法名依次取
Dependency alias、Contract alias、移除末尾 `FragmentContract` 后首字母小写的类型名。
Generator 自动记录精确 Contract 版本与结构指纹，Host 继续检查版本、指纹和陈旧产物。
同一消费者的一条依赖仍支持多处、多实例渲染，实例身份使用 Flutter Key。

这是旧依赖声明的源码破坏性变更：移除 `versionRange` 参数，并使用配套 Generator
重新生成实际 Host。Demo 的三个 UI 方法名保持原样；5 个发生变化的 Package Index 中，
UI Contract 的版本和结构指纹在改动前后相同，已由本轮只读结构化比较核实。

## 第一阶段自动化证据

下表为本轮保存的执行结果。Generator 的 139 项是六个相关测试文件，不能称为 Generator
完整套件；Plugin 专项包含在 Plugin 完整测试中，不能叠加为独立覆盖数量。

| 检查 | 结果 | 原始记录 |
| --- | --- | --- |
| 根 `fvm dart analyze` | 无问题 | [root-analyze.log](root-analyze.log) |
| Demo `fvm flutter analyze --no-pub` | 无问题 | [demo-analyze.log](demo-analyze.log) |
| 框架 `fvm flutter test packages/ccrouter_test/test --reporter expanded` | 1719 项通过 | [framework-tests.log](framework-tests.log) |
| Demo `fvm flutter test --no-pub --reporter expanded` | 118 项通过 | [demo-tests.log](demo-tests.log) |
| 隔离 Plugin `fvm dart test --reporter expanded` | 213 项通过，包含真实 Analysis Server/LSP 场景 | [plugin-full-tests.log](plugin-full-tests.log) |
| 隔离 Plugin `fvm dart test test/ui_analysis_test.dart --reporter expanded` | 57 项通过 | [plugin-ui-tests.log](plugin-ui-tests.log) |
| UI Generator 相关专项 | 139 项通过 | [generator-ui-tests.log](generator-ui-tests.log) |
| 实际 Host 生成 | 6 组件、34 路由、11 个生成 Package 校验通过 | [generate.log](generate.log) |
| Host `--no-cache --check` | 产物新鲜；Builder 使用已有增量状态 | [generate-no-cache-check.log](generate-no-cache-check.log) |
| Portable prepare / publish | 9 个显式启用 Portable 的 Package 就绪；没有执行 Pub 发布 | [prepare](portable-prepare.log)、[publish](portable-publish.log) |

除 Demo 命令从 `demo/` 执行、Plugin 命令从 `packages/ccrouter_analyzer_plugin/` 执行外，
其余命令均从仓库根执行。框架测试路径是 `packages/ccrouter_test/test`。

UI Generator 专项的完整命令：

```sh
fvm dart test --concurrency=1 \
  packages/ccrouter_test/generator_test/ui_fragment_generator_test.dart \
  packages/ccrouter_test/generator_test/generated_client_naming_test.dart \
  packages/ccrouter_test/generator_test/ui_fragment_tooling_test.dart \
  packages/ccrouter_test/generator_test/ui_fragment_find_command_test.dart \
  packages/ccrouter_test/generator_test/ui_fragment_workspace_test.dart \
  packages/ccrouter_test/generator_test/ui_action_union_test.dart \
  --reporter expanded
```

实际 Host 及 Portable 验证使用同一 FVM SDK 和根 Package config，通过源码入口执行：

```sh
fvm dart packages/ccrouter_generator/bin/ccrouter.dart generate demo
fvm dart packages/ccrouter_generator/bin/ccrouter.dart generate demo --no-cache --check
fvm dart packages/ccrouter_generator/bin/ccrouter.dart portable prepare demo
fvm dart packages/ccrouter_generator/bin/ccrouter.dart portable publish demo
```

覆盖包括默认参数、精确版本记录、alias 覆盖优先级、推导名冲突、重复依赖、跨 Package
Action、脚手架打印的声明和 `find --usage` 提示。源码分析和测试通过不构成真机、性能或
长期内存验证。

## 首次失败与证据边界

实现前新增的默认声明与 Contract alias 用例曾失败；独立 RED 原始日志未保存，不能把
本目录宣称为完整 RED/GREEN 档案。这里保存的是改动后的成功测试输出。

首次通过 `fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo` 启动时，
Dart 的自动 Pub 解析报告 Flutter SDK 依赖不可用，CLI 尚未执行生成；该失败也未保存独立
日志，不计为有效生成检查。随后改用上面的 FVM Dart 源码入口成功完成生成和 freshness
验证，没有切换 SDK、测试根或降低校验要求。

第一次 doctor 检出旧 PluginManager 缓存 stale，但锁定依赖解析、bootstrap 分析和 loader
编译通过。该原始 advisory 完整保存在
[doctor-before-cache-rebuild.log](doctor-before-cache-rebuild.log)，没有用后续成功结果覆盖它。

## 第二阶段来源、缓存与实时诊断

第一阶段提交先成为远端可解析对象，随后才在第二阶段提交中更新 Demo pin。
[初次 pin-check](pin-check-before.log)和[最终 pin-check](pin-check-final.log)均确认
manifest/lock/resolved-ref 一致、远端 SHA 可解析、Plugin 生产代码没有 pin 后漂移。
lockfile 的逐字节复核确认只改变了 Plugin Git ref，没有升级其他依赖。

doctor 指定的旧缓存完整条目为
`<home>/.dartServer/.plugin_manager/2830316c39d53daed22fb3806abbfdb7`。
确认当时没有运行中的 Dart Analysis Server 后，将整个条目移动到独立备份
`<home>/.dartServer/ccrouter-plugin-cache-backup/2830316c39d53daed22fb3806abbfdb7-ui-30204ef9`，
没有删除缓存或只移走其子目录。随后通过实际 Demo Server 重建，
[最终 doctor](doctor-current.log)确认缓存 current，锁定依赖、bootstrap 分析及 loader
编译通过。doctor 自身仍不能判断现有 GUI IDE 会话的加载状态。

实时验证使用 FVM SDK 的官方 JIT Analysis Server、实际 `demo/` 根、Demo 的真实
bootstrap 和默认 PluginManager 缓存，没有将 Plugin 依赖替换成本地源码或测试用 loader。
对实际 `navigation_lab_component.dart` 发出未保存的 LSP overlay：

1. 保留第一条 `OrderPanelFragmentContract` 依赖的默认 `orderPanel` 方法名。
2. 将 `OrderSummaryFragmentContract` 的消费 alias 临时设为 `orderPanel`。
3. 收到 `ccrouter_ui_alias_duplicate`；这同时验证显式 alias 与推导默认名的冲突诊断。
4. 在 overlay 恢复原文，确认该诊断清除，随后正常关闭 Server。
5. 启动新的 Server 进程并重复上述诊断/修复循环，确认重启后仍加载相同 Plugin。

最终检查缓存中的 bootstrap manifest 与当前文件逐字节一致，其 Package config 指向
远端 pin `30204ef9a8dffcc595128915cca3cf66fe18da45` 的 Git Package。
两个 Server 进程的 PID 不同；每轮结束均确认 Demo 磁盘源码保持原样。
见[实时 LSP 输出](live-lsp.log)、[结构化结果](live-lsp.json)和
[执行时探针源码快照](live-lsp.py)。探针快照中的本机路径已经机械脱敏，是可审查证据；
重新执行前需要按本机位置替换常量，不作为通用工具或新增测试入口。

第二阶段后的 [Host freshness 检查](generate-after-pin-check.log)通过，命中内容一致的
fast path；该次没有运行 Builder，也不代表一次新的完整 Generator 回归。

## 本轮没有验证的范围

- 已打开的 Android Studio 或其他 GUI 编辑器会话没有完成新 pin 的实际加载验证；
  真实 Demo LSP 的通过不能冒充 GUI 会话已重启。
- 没有重跑整个 Generator 测试目录、独立 Example、DevTools 或发布安装矩阵。
- 没有新增 Android/iOS/OHOS 真机、GUI 交互、长期 heap 或性能基准验证。
- 本次归档不重新执行前两阶段的功能测试，也不执行提交、推送或主分支合并。

## 证据保存

日志和探针从本任务的临时记录复制，原件保留；不混入其他场景的同前缀日志。
归档通过仓库 `sanitize_validation_evidence.mjs` 机械替换本机 home 路径；
`demo-analyze.log` 另移除一行 `Analyzing demo...` 进度提示的行尾空格，以通过暂存差异检查。
原件保留，不改写诊断、结果、测试数、时序或失败事实。完整验证数量以各日志末尾为准。
本报告通过[验证索引](../README.md)导航；现行 API 指导不复制历史 SHA。

本次本地收口执行仓库文档链接检查、证据路径规范化检查，以及包含未追踪文件的发布敏感
信息检查，结果见[归档检查记录](archive-checks.json)。这些检查不替代前两阶段的功能测试。
