# CCRouter SDK 兼容性验证

## 文档状态

- 版本：v0.1
- 状态：持续验证记录，不是对所有 Flutter 平台和版本的永久承诺
- 范围：Dart/Flutter SDK、原生 Managed Backend、Generator 和 Demo 路由回归
- 2026-10-04 补充[Flutter / Dart 升级同步计划](CCRouter-sdk-upgrade-plan.md)：包含独立 Analyzer、
  工具身份/只读组件、Hook、DevTools 与最低消费者门禁；该计划不代表目标 SDK 已升级或通过。
- 最新源码回归与各日期的平台证据见[验证索引](validation/README.md)；下文 SDK 安装及较早
  smoke 记录不自动延续到当前源码，也不能替代最低 SDK 的独立消费者验证。

## 当前约束

Runtime/Contracts 保持 Dart 3.10.0 约束；Generator 工具链有独立的 SDK 与 Flutter pin 要求：

| Package | SDK 下限 |
| --- | --- |
| `ccrouter_core`、`ccrouter_contracts`、`ccrouter` | Dart `^3.10.0` |
| `ccrouter_generator`、Workspace 聚合根 | Dart `^3.11.0` |
| `ccrouter_test` | Dart `^3.10.0` |
| `demo` | Dart `^3.11.5` |

生成器升级到 Analyzer `^13.3.0`、`build ^4.0.9`、`dart_style ^3.1.14`，Host 使用
`build_runner 2.16.1`，Builder 测试配套 `build_test 3.5.20`。Analyzer 的 `meta ^1.18.3`
与旧 OHOS `oh-3.41.9-release` 的固定 `meta 1.17.0` 冲突；不能仅凭 Dart 3.11.5 已满足
SDK 条件就判定可解析。根与 Demo 的 FVM 现固定标准 Flutter `3.47.9 / Dart 3.13.7`。
Quality workflow 的全部 Flutter Job 与根 FVM pin 同步使用 3.47.9；新增 Chrome Job
从测试 Package 验证 Host 初始化、重启和既有 Entry 导航。Plugin Job
单独安装 Dart 3.13.7 并在隔离 Package 内解析、分析与测试，不合并 Analyzer 依赖图。
`tool/test/quality_workflow_test.dart` 检查所有 CI Flutter pin 与根 `.fvmrc` 一致。
旧 OHOS SDK 在本分支不支持；兼容 OHOS SDK、最低版本独立消费者和真实平台验证仍需单独完成。
下文较早的安装及 smoke 数字是历史证据；本轮范围见
[build_runner 升级记录](validation/build_runner_upgrade_20261104.md)。

2026-11-17 对提交 `699c81ae` 的[完整性评估](validation/20261117-flutter-3479-readiness/report.md)
补齐了四个平台的编译 smoke 和 DevTools 验证，并发现 Web Runtime 初始化阻断。
该问题现已用跨 JavaScript 的随机上限字面量修复，Chrome 初始化与导航回归通过；
原生工程迁移和 Plugin 分发进展见报告后续修复记录。设备交互、OHOS 等仍需独立验收。

## 本机 SDK 矩阵

下表保留截至 2026-09-22 的历史 SDK 安装记录，并另列当前分支的 3.47.9 目标：

| FVM 标识 | Flutter | Dart | 类型 |
| --- | --- | --- | --- |
| `ohos/oh-3.41.9-release` | `3.41.10-ohos-1.0.0` | `3.11.5` | 当前项目默认 OHOS SDK |
| `3.41.9` | `3.41.9` | `3.11.5` | 标准 Flutter，最低完整 Demo 基线 |
| `3.44.9` | `3.44.9` | `3.12.2` | 标准 Flutter |
| `3.47.9` | `3.47.9` | `3.13.7` | 官方 upstream，当前分支目标与验证 SDK |
| `3.47.2` | `3.47.2` | `3.13.2` | 标准 Flutter，历史验证 |

版本信息使用以下命令确认：

```sh
fvm list
fvm --version
fvm spawn 3.41.9 --version
fvm spawn 3.44.9 --version
fvm spawn 3.47.9 --version
fvm flutter --version
```

## 验证命令

本分支默认项目 SDK 为官方标准 Flutter 3.47.9；以下命令从仓库根目录执行：

```sh
fvm dart analyze packages
fvm dart analyze tool
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test
fvm flutter test packages/ccrouter_test/test
fvm flutter test demo/test
fvm dart run ccrouter_generator:ccrouter generate demo --check
```

仓库根是 Workspace 聚合根。根目录的 `fvm dart analyze` 会进入 Demo legacy Plugin
bootstrap，当前可因弃用 warning 返回退出码 2，不作为聚合门禁。独立 Plugin 的分析和测试
从其 Package 目录执行，与上面的根目录检查分开：

```sh
(
  cd packages/ccrouter_analyzer_plugin &&
    fvm dart analyze &&
    fvm dart test --concurrency=1
)
```

其他 SDK 应在隔离工作区先确认能解析本分支，再执行同一组不依赖 OHOS 平台的测试。
以下为指定 SDK 命令示例，不证明列出的旧 SDK 已兼容新工具链：

```sh
fvm spawn 3.41.9 test packages/ccrouter_test/test
fvm spawn 3.44.9 test packages/ccrouter_test/test
fvm spawn 3.47.9 test packages/ccrouter_test/test
```

切换 SDK 后必须先在同一版本执行一次 `pub get`，再运行测试；不能并行运行多个版本，
也不能复用另一个版本生成的 `.dart_tool/package_config.json` 或 `build/unit_test_assets`：

```sh
CCROUTER_PUB_HOOK_DISABLE=1 fvm spawn 3.41.9 pub get
fvm spawn 3.41.9 test packages/ccrouter_test/test --no-pub
```

这些文件包含 Flutter SDK 的实际路径和测试 shader 资产，跨版本复用会产生误导性的
`DisplayCornerRadii`、`HitTestRequest` 或 `ink_sparkle.frag` 错误。

Workspace 根是聚合 Package；根目录解析时禁用 Pub Hook，并单独对实际 Host 执行
`ccrouter generate demo --check`。优先为每个 SDK 使用独立工作区，不在当前工作区来回
覆盖 lock、`.dart_tool` 和平台产物。Generator 测试中存在真实 Demo 修改夹具，必须串行，
不能同时对同一个 Demo 执行生成或 Analyze。

`demo` 的 macOS 构建和真实平台运行不属于 OHOS SDK 与标准 Flutter SDK 的同一项验证；
应分别使用目标 SDK 的平台工具执行，不能用一个平台通过替代另一个平台。

## 已验证范围

- Core / Contracts 的纯 Dart 路由解析、拦截、并发和生命周期测试不依赖 Flutter UI。
- Flutter 测试覆盖原生 Managed Adapter、Page/Route Factory、Host/Outlet、Dialog/BottomSheet、
  Shell、StatefulShell、系统返回和资源销毁。
- Generator 测试覆盖 Analyzer、build_runner、Package Index、Catalog、源码定位和生成物校验。
- 2026-10-23 已移除 GoRouter 依赖；历史 SDK 结果只代表当时版本，当前回归见
  [退役记录](validation/go_router_retirement_20261023.md)。

2026-09-22 本机多 SDK 验证历史快照如下。表中的测试数量保留当次执行口径，用于证明这些
SDK 组合在当时通过，不代表当前测试套件总数：

| SDK | 验证结果 |
| --- | --- |
| OHOS `3.41.10-ohos-1.0.0` | 默认完整回归通过：Workspace analyze、Generator 130 项、Flutter 测试 244 项、Demo 22 项、生成 `--check` |
| 标准 `3.41.9` | 执行独立 `pub get` 后，`ccrouter_test` Flutter 测试 244 项通过 |
| 标准 `3.44.9` | 独立临时工作区执行 `pub get` 后，`ccrouter_test` Flutter 测试 244 项通过 |
| 标准 `3.47.2` | 历史独立临时工作区验证，非当前目标 SDK |

2026-11 工具链升级阶段的标准 3.47.9 记录为 Framework 1650 项、Demo 117 项与生成门禁
通过，见[升级记录](validation/build_runner_upgrade_20261104.md)。合入主分支后的同源码
回归为 Framework 1718 项、Demo 全目录 188 项，见[组合验证](validation/20261117-generator-plugin-followup/report.md#合入主分支后的组合验证)。
这些 VM/Widget 结果不覆盖本轮 Chrome 发现的 Web 初始化阻断，当前完整范围以
[2026-11-17 适配矩阵](validation/20261117-flutter-3479-readiness/report.md)为准。

此前在同一工作区并行切换 SDK 时出现的 `ink_sparkle.frag` 失败发生在 Flutter Material
shader 资源加载，不是 CCRouter 断言失败；隔离每个 SDK 的 `.dart_tool` 和 `build` 后，
当前分支 3.47.9 的框架与 Demo 回归已通过；历史 3.44.9/3.47.2 数字仅作对照。兼容性回归必须遵守独立构建缓存和串行执行规则。

2026-10-03 当前默认 OHOS SDK 已追加通过 Generator `272/272`、增量生成及
`--no-cache --check` 回归；该结果没有重新执行上述全部标准 Flutter SDK 组合，因此不覆盖或
伪装成新的多 SDK 矩阵。正式 RC 需要按本节命令重新建立同一提交上的完整兼容性快照。

2026-09-29 在当前 FVM OHOS SDK 的 macOS 主机上追加平台构建 smoke：

| Target | 命令 | 结果 |
| --- | --- | --- |
| macOS | `fvm flutter build macos --debug` | 通过，生成 Debug `.app` |
| iOS Simulator | `fvm flutter build ios --simulator --no-codesign` | 通过，生成 Simulator `.app` |
| Android | `fvm flutter build apk --debug` | 通过，生成 debug APK |
| Web | `fvm flutter build web` | 通过，Wasm dry-run 和 Web 构建通过 |
| OHOS | `fvm flutter build hap --debug` | 通过，生成 signed `.hap` |

这些是当前 SDK/主机的编译 smoke，不等同于真机手势、Deep Link、原生窗口或长期 RSS 结论；
真机和多窗口仍需按目标设备单独运行 Demo 手工/自动用例。

## 不应过度宣称的范围

- OHOS Flutter Fork 与标准 Flutter 的平台实现不同；标准 Flutter 通过不代表 OHOS 平台窗口、
  Deep Link 或系统返回行为完全一致。
- 当前没有把 macOS、Windows、iPadOS 原生多窗口生命周期纳入兼容承诺。
- 当前没有用真实 RSS/Heap 数值证明长期无内存增长；资源释放以生命周期测试、活动 Entry、
  pending navigation 和 Adapter 栈清空为确定性证据，长期 RSS 需要在目标应用和平台单独采样。
- FVM 缓存中的版本可用于本机回归，但发布兼容范围仍由各 Package `environment.sdk`、依赖
  约束和实际测试结果共同决定。

## 维护规则

1. 修改 Core、Contracts、Generator、Managed Adapter 或生成器输出协议后，至少重跑默认 OHOS
   SDK 的完整命令集。
2. 修改 Flutter Page、Adapter、生命周期或 Demo Host 后，补跑标准 Flutter 3.41.9 的
   `ccrouter_test` Flutter 测试；若涉及平台插件或平台目录，再执行对应平台构建。
3. 升级 Dart、Flutter 或 Backend 后，记录版本、命令和失败阶段；不能只记录“能编译”。
4. 新增 API 的性能变化先运行两个现有 scaling benchmark 和并发回收 benchmark，再决定是否
   调整实现或门禁阈值。
