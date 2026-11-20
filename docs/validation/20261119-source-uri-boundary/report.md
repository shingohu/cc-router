# 源码 URI 与 generated API 边界循环复审（2026-11-19，本地）

承接[命名空间与 Catalog 循环复审](../20261119-namespace-catalog-loop/report.md)，继续用户
授权的“复现 → 最小修复 → 回归 → 再审查”。保留此前所有未提交改动；不提交、推送、合并、
打 tag 或改 Demo Plugin pin。

## 问题、取舍与范围

本轮审查源码 import/export 的 generated 内部 API 边界，而不是扩大业务 API。
仅用目录名原文筛选、将 metadata 的便携 URI 规则套到源码，都会漏掉 Dart 真正能够解析的
同一目标。只修 CLI 会留下 IDE 漏检；新建公共 URI/文件系统解析层会扩大 API 和依赖。
因此在原有两个私有入口修复，并补齐现有 Plugin session 的调用条件：复用 SDK/path/native
文件语义，不新增公共解析 helper、依赖、Analysis Server session 或长生命周期缓存。

改动覆盖三个生产 Dart 文件、四个测试文件及九个指导文档。Generator 的根路径只在单次
校验内复用；导入目标解析后检查已有 Package 边界。目录扫描仍不跟随 source symlink，
本轮的符号链接测试针对 import target，不宣称支持扫描任意链接目录。

## 第一轮：file URI 与字符串转义绕过

[Generator 两项失败复现](generator-red.log) 确认 file URI 被按不支持的 scheme 跳过，
目录名使用 Dart `\u` / `\x` 字符串转义时又被文本预筛选跳过。
[Plugin 失败复现](plugin-red.log) 中，真实 semantic 对照先确认 file import 无 Dart ERROR，
再确认缺少应有的边界诊断；已支持的 escaped Package import 作为正例对照保留。

现在 CLI 只按不可转义的 import/export 关键字做预筛选，由 AST 读取真正的 URI；不会从
注释或普通字符串猜测 import。file、relative、Package URI 都经过其目标路径判定。
同 Package、公开文件、生成胶水代码的既有允许路径继续覆盖。

## 第二轮：原生路径别名造成误报和漏检

[CLI 反例](alias-generator-red.log) 确认一个名字不含 generated 的普通相对导入，可通过
symlink 指向外部 Package 的 generated 文件而漏检。[IDE 反例](alias-plugin-red.log) 则
确认 own Package 的不同原生路径别名会被当成跨 Package；其中的 localhost 真实语义对照
也证明了 SDK 直接 `toFilePath` 与 Analyzer 所用原生转换并不等价。

原生目标和 generated 根现在解析已有 symlink；不存在/不可读的路径按既有保守词法路径
处理。Generator 对本次解析图预先计算根映射，避免每条 URI 重复解析所有根。没有新增
文件句柄、timer、subscription 或持久缓存，File API 的同步调用不转移资源所有权。

## 第三轮：按实际 Dart 语义区分源码与 metadata

[源码拼写试探](source-forms-red.log) 中七项确认实际漏检：POSIX file authority、file query、
file 编码分隔符、Package query、Package absolute path、Package authority、Package 编码
分隔符。它们都先通过真实 Analyzer 的“无 Dart ERROR”检查，再因缺少框架诊断失败。
最初矩阵对两项 fragment 的假设不成立：真实 Dart 报 URI 不存在，因此它们调整为负例；
不将这两项当成框架缺陷。

改为使用现有 path 原生 URI 转换，与当前 Analyzer 的目标文件语义一致；不人为假定
只有 localhost 有效。Package 源码按 Pub 根/已解析 Library 匹配目标，query 和被 Dart
接受的非规范拼写不再绕过边界。fragment、非法 UTF-8 与 NUL 的负例继续覆盖。
metadata 的源码位置保持严格便携 Package URI，这两种输入的用途和失败语义不同。

## 第四轮：Package 别名和真实 Plugin 调用入口

[CLI Package 别名反例](package-alias-generator-red.log) 与
[真实 semantic 反例](package-alias-plugin-red.log) 证明，只检查 Package URI 的目录片段
还会漏掉指向 generated 文件的公开别名。CLI 使用实际目标/根路径；IDE 复用已有 SDK
context 的 UriConverter，将每个 Package URI 映射为实际路径。明确的跨 Package generated
URI 仍直接检查，不因物理别名放过逻辑上的私有路径。条件分支各自转换，不把选中的
Library 当成其他分支的目标。仅直接提供 resolved unit 的内部调用也保留已有元素路径证据。

继续追到实际调用者，[真实 Plugin 会话反例](live-alias-red.log) 又确认：不含 CC 类型名、
只有 import/export 的文件，会被旧启发式跳过 semantic 请求。[同一会话回归](live-alias-green.log)
用于确认真实入口覆盖。直接扩大完整类型解析的范围会增加工作；最终选用现有 UriConverter，
让裸 import 和条件分支通过路径映射完成检查，保留原有类型解析启发式，不创建另一张图。
新增无 resolved unit 的 converter 对照及两种条件分支位置对照，避免只在直接调用时生效。
SDK context 由 Server 所有，converter 在 source freshness fence 之后借用并同步使用，不
进入字段或跨 await 保留；映射缺失/失效时不以陈旧元素补猜。既有 context 替换清理指针，
按 lifecycle reference 复核未发现新增高置信度泄漏，不将该静态结论当成独立 heap 测量。

## 最后复审

复查两个私有入口与真实调用者、SDK URI 接受/拒绝对照、query/fragment 分工、字符串转义、
own/foreign symlink、Package 别名、条件分支和无长生命周期缓存的所有权。未再确认本轮
这些路径中新的可复现缺陷，不将其扩大为全仓或全部平台不存在优化空间的保证。

## 验证

使用项目配套 Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`。隔离 Plugin 的 analyzer 仍为
原有依赖版本，未升级约束或 lockfile。初次根 Generator 测试因前轮已知 SDK 版本缓存缺失
而未进入测试，运行配套 `flutter --version --machine` 后重跑；该次 Pub 失败不算 RED。

最终源码指纹见 [source-manifest.json](source-manifest.json)，记录累计 81 个变更文件，并标明
本轮 16 个文件。Generator 本轮运行相关单测与真实 CLI 集成，没有重复上一轮整个
Generator 目录；不把历史整目录计数当成本轮结果。最终 Plugin 是 converter 方案下的重新
全量结果；先前扩大类型解析条件的 331 项结果不冒充最终实现结果。

| 检查 | 命令或范围 | 结果 |
| --- | --- | --- |
| 隔离 Plugin 全量 | Plugin 目录 `dart test --reporter expanded` | [332 项通过](plugin-final.log)，比上轮新增 17 项，含真实 Server/LSP 和裸 import 会话 |
| 隔离 Plugin analyze | Plugin 目录 `dart analyze` | [通过](plugin-analyze.log) |
| Generator 相关回归 | 根目录 `dart test --concurrency=1 packages/ccrouter_test/generator_test/internal_api_boundary_validator_test.dart packages/ccrouter_test/generator_test/component_dependency_preflight_test.dart packages/ccrouter_test/generator_test/route_api_boundary_test.dart --reporter expanded` | [27 项通过](generator-final.log) |
| 真实 CLI | 根目录 `dart test --concurrency=1 packages/ccrouter_test/generator_test/internal_api_boundary_command_test.dart --reporter expanded` | [一项通过](cli-final.log)，标准/file/query/转义/symlink 五种输入均拒绝，tracked 生成物逐字节不变 |
| Converter 专项 | Plugin 目录的实际会话和无 resolved unit 回归 | [两项通过](converter-green.log)；最终全量另覆盖条件 URI 的位置和 span 对照 |
| 框架全量 | 根目录 `fvm flutter test --no-pub packages/ccrouter_test/test` | [1767 项通过摘要](framework-summary.log) |
| Demo | Demo 目录 `fvm flutter test --no-pub` 与 `dart analyze` | [118 项通过摘要](demo-tests-summary.log)、[分析通过](demo-analyze.log) |
| 根 analyze | 根目录 `dart analyze` | [最终通过](root-analyze-final.log) |
| Demo 完整生成 | 配套 SDK `dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check` | [输出一致](demo-reference.log)：6 components、34 routes、11 Packages |
| Demo 普通生成 | 同入口 `generate demo --check` | [输出一致](demo-normal.log) |
| 格式/文档/敏感信息/还原/指纹 | 最终归档门禁 | [archive-checks.log](archive-checks.log) |

表中 `dart` 为项目配套 SDK 的 `bin/cache/dart-sdk/bin/dart`，根测试/CLI 显式设置该 SDK 的
`FLUTTER_ROOT`。纯 Framework/Flutter 代码在框架和 Demo 回归后未修改；最终 Plugin 的
converter 路径另外跑完全量。没有手改生成物，pubspec/lockfile 未变。

证据只机械规范化 ANSI、换行、行尾空白、home 路径及可能的原始 NUL；框架/Demo 归档末
12 条非空输出，其余保存完整输出，原始日志留在本机 `/tmp`。未将中间编译错误或错误的
fragment 测试预期计为通过或产品缺陷。

第一次根 analyze 与 Plugin 测试并行时，报告 Plugin
`DisposedAnalysisContextResult`，exit 4，见 [初次日志](root-analyze-initial.log)。单独重跑后
[通过](root-analyze-standalone.log)。当时 Demo 仍使用旧 bootstrap SHA，本地当前 Plugin 的
真实 Server 回归另外验证；本轮未确认该次上下文失效的具体触发点，也不声称 Demo 当前 IDE
已加载新版。

## 限制与后续发布

本轮未运行 Windows 原生环境、浏览器或实体设备；POSIX symlink fixture 在 Windows 默认
跳过。未执行远程 Analyzer 安装 smoke 或 SDK 版本缓存缺失的外部根因治理。
Demo 的 manifest/lockfile 仍共同指向 `ec9da8538b27ef17efcf44aeefc9bbad2fbef845`。
Plugin 的后续分发须遵守独立远端实现提交、Demo 完整 SHA pin 同步、pin-check、doctor、
Server 重启和真实 IDE 验证流程；本轮没有执行这些发布动作。

后续排查见[Host/UI SPI Library 身份循环复审](../20261119-spi-library-proof/report.md)。
