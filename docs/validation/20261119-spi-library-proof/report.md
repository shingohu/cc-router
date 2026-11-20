# Host/UI SPI Library 身份循环复审（2026-11-19，本地）

承接[源码 URI 边界复审](../20261119-source-uri-boundary/report.md)，继续按用户授权执行
“复现 → 最小修复 → 回归 → 再审查”。保留此前未提交改动，不提交、推送、合并、打 tag，
不改 Demo Plugin bootstrap pin。

## 问题、方案与边界

本轮审查 Host lifecycle 和 UI SPI 的身份及可见性判定。只比较 URI 原文会漏掉指向同一
配置文件的别名；把所有 Framework 类型比较都放宽为物理文件比较，又可能混淆不同 Dart
Library 的类型兼容性。因此只在这两个访问边界复用现有 SDK UriConverter 和原生路径证明，
保持 Contract/Renderer 的 Dart 类型兼容规则不变。

来源证明在 SourceAnalyzer 当前调用内构造，缓存只活到同步检查结束，通过既有内部检查
入口传给两个 visitor；没有新增公共 helper、业务 barrel、依赖、全局缓存或另一张分析图。
当前 SDK 配置中的 canonical URI 和 actual URI 都要映射到同一文件；同名或同后缀不足以
证明身份。未知映射暂缓，不扫描其他 Workspace 源码猜测。

## 第一轮：Host 引用漏检与 hide 误报

[Host 失败复现](host-red.log) 的九项对照中确认四项缺陷：symlink facade 别名漏检、typedef
静态调用漏检、NamedType 漏检，以及 `hide CCRouterHost` 被当成实际使用。file/query URI
加实际类型引用的四项原本已通过，保留为对照；不把它们计为新缺陷。

[另外三项反例](host-directive-red.log) 确认不含类型引用的 file/query/conditional export
会漏掉 Host 入口。修复用 SDK 当前来源证明识别这些入口；引用 visitor 同时覆盖 NamedType
和 typedef 的目标 InterfaceType。专门断言 `Root.shutdown` 的引用位置，避免只靠 typedef
定义处的一条诊断假装已覆盖使用点。

## 第二轮：同一遗漏也影响 UI SPI

[UI 七项对照](ui-red.log) 中六项失败：file/query 的 Host/Generated barrel、定义文件别名
和 transitive hide 的误报；外部同名声明对照原本通过。修复共用当前调用的来源证明，
仍按已有类型名称集合与 Host/Package 角色决定哪些 SPI 被禁止。

后续将外部复制文件对照加强为相同的 `src/facade.dart` / `src/ui_fragment.dart` 后缀，
验证不会按文件名或后缀误认。额外对照 Host 可用 UI Host API、Host/组件均不得手写
Generated SPI，以及同一实现库中的正常业务 UI 类型继续允许。

## 第三轮：真实 Plugin 入口没有触发 UI 类型检查

[真实 Plugin 会话反例](ui-session-red.log) 确认：只有 UI 类型引用、没有 Component 声明的
文件，被旧类型解析启发式跳过。补齐 `CCUI` 触发条件后，同一 SDK session 的回归通过。
这只对需要 UI 语义的源码请求已有 session，不将全部普通 import 升级为完整类型分析。

[最终会话专项](ui-session-final.log) 还把同一文件切换成独立 UI Renderer：Owner ID 从
其他文件导入，当前文件没有 `CCComponent` 字样；错误 Renderer 返回/参数签名能被诊断，
前一状态的 SPI 诊断同时清除。这个对照验证实际入口与 unsaved overlay，而不仅是直接
给 SourceAnalyzer 注入一个已经解析好的 AST。

## 第四轮：修复 hide 时发现的 show 回归

修复过程中一度跳过所有 show/hide 名字，后续复审用[失败对照](show-red.log) 捕获了
transitive show 漏检。该回归属于本轮实施中发现的问题，不作为原有仓库缺陷计数。
最终只排除 hide 与最终不可见的 show 名字，所有 show/hide 按交集计算；实际暴露的
show 名字仍按 SDK 声明身份检查。含 show-then-hide、多个不相交 show 的对照均保留。

## 最后复审与生命周期

复查直接调用者、SDK URI 映射缺失路径、同名文件反例、组件/Host/测试/生成物分工、
NamedType/typedef 的位置、show/hide 最终可见性和 UI 入口触发条件，未再确认本轮这些
路径中新的可复现缺陷。这不是全仓或所有平台不存在其他优化空间的保证。

按 framework lifecycle reference 检查来源证明的保留路径：visitor 只在 `unit.accept` 的
同步调用中持有 callback；当前调用的 URI/path cache 和借用 converter 不进入诊断结果、
字段或跨 await 保留。SDK context 仍由 Server 所有并沿既有路径清理，没有新增 timer、
subscription、controller 或自建 AnalysisContext。未发现新增高置信度泄漏；这不是 heap
或真实设备内存测量。

## 验证

使用项目配套 Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`，Dart 命令直接使用配套 SDK，
Plugin 所有命令在隔离目录执行；未升级 analyzer/analyzer_plugin 约束或 lockfile。

最终源码指纹见 [source-manifest.json](source-manifest.json)：累计 84 个变更文件，标明本轮
13 个文件。只改 Plugin 生产代码，Runtime/Generator 生产代码未动；不重复或引用历史
Runtime/Generator 整套结果作为本轮测试。

| 检查 | 命令或范围 | 结果 |
| --- | --- | --- |
| 隔离 Plugin 全量 | Plugin 目录 `dart test --reporter expanded` | [358 项通过](plugin-final.log)，较上轮新增 26 项，含真实 Server/LSP 和 UI 会话 |
| 隔离 analyze | Plugin 目录 `dart analyze` | [通过](plugin-analyze.log) |
| 定向回归 | `dart test test/semantic_analysis_test.dart test/ui_analysis_test.dart test/source_analyzer_test.dart --reporter expanded` | [256 项通过](targeted-confirmed.log)；随后追加的引用位置与 Renderer 会话对照在最终全量覆盖 |
| typedef/实际会话专项 | SDK alias 位置与 typed UI 会话 | [三项通过](alias-final.log) |
| 独立 UI 会话最终专项 | 不含 Component 的 SPI 类型与 Renderer 两种 overlay 状态 | [一项通过](ui-session-final.log) |
| 根 analyze | 根目录 `dart analyze` | [通过](root-analyze.log) |
| Demo analyze | Demo 目录 `dart analyze` | [通过](demo-analyze.log) |
| Demo 完整生成 | `dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [一致](demo-reference.log)：6 components、34 routes、11 Packages |
| Demo 普通生成 | 同入口 `generate demo --check` | [一致](demo-normal.log) |
| 文档/格式/敏感信息/指纹/还原 | 最终归档门禁 | [archive-checks.log](archive-checks.log) |

最终验证结果：Plugin 全量 [358 项通过](plugin-final.log)，定向复审 [256 项通过](targeted-confirmed.log)，
框架全量 [1767 项通过](framework-summary.log)，Demo [118 项通过](demo-tests-summary.log)；
根目录、Plugin、Demo analyze 均通过，Demo `--no-cache --check` 与普通 `--check` 均保持
`6 components / 34 routes / 11 Packages` 一致。源文件指纹累计 84 个，本轮 13 个；Demo
Git 状态和依赖文件差异为空。

`dart` 为项目配套 SDK 的 `bin/cache/dart-sdk/bin/dart`；根 CLI 显式设置该 SDK 的
`FLUTTER_ROOT`。Demo 生成物只由 CLI 检查，没有手改。各源码/文档指纹验证前轮内容保留，
Demo Git 状态和 pubspec/lockfile 差异为空。证据只规范化 ANSI、换行、行尾空白和 home
路径，不改断言结果；原始日志保留在本机 `/tmp`。

## 限制与分发

未知或尚未获得 SDK 语义证明的别名继续保守暂缓。未运行 Windows 原生环境、浏览器、
真机、远程 Analyzer 安装 smoke 或独立 heap/leak 测量。Demo 现有 bootstrap 仍使用旧
SHA，本地当前 Plugin 的会话/Server 测试不证明 Demo IDE 已加载新版。

后续分发须按仓库两阶段流程，先提交并推送实现，再单独同步 Demo 完整远端 SHA、执行
pin-check/doctor、重启 Server 并验证真实 Demo IDE；本轮未进行这些发布动作。
