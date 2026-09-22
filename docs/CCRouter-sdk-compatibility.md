# CCRouter SDK 兼容性验证

## 文档状态

- 版本：v0.1
- 状态：持续验证记录，不是对所有 Flutter 平台和版本的永久承诺
- 范围：Dart/Flutter SDK、GoRouter 适配器、Generator 和 Demo 路由回归

## 当前约束

核心 Package 的最低 Dart 约束统一为 Dart 3.10.0；Demo 仍按自身依赖使用更高版本：

| Package | SDK 下限 |
| --- | --- |
| `ccrouter_core`、`ccrouter_contracts`、`ccrouter_generator`、`ccrouter` | Dart `^3.10.0` |
| `ccrouter_go_router` | Dart `^3.10.0` |
| `ccrouter_test` | Dart `^3.10.0` |
| `demo` | Dart `^3.11.5` |

因此仓库当前可回归的最低完整 Demo 基线仍是 Dart 3.11.5；整个 Workspace 不再宣称支持
Dart 3.9。

## 本机 SDK 矩阵

截至 2026-09-22，本机 FVM 缓存包含：

| FVM 标识 | Flutter | Dart | 类型 |
| --- | --- | --- | --- |
| `ohos/oh-3.41.9-release` | `3.41.10-ohos-1.0.0` | `3.11.5` | 当前项目默认 OHOS SDK |
| `3.41.9` | `3.41.9` | `3.11.5` | 标准 Flutter，最低完整 Demo 基线 |
| `3.44.9` | `3.44.9` | `3.12.2` | 标准 Flutter |
| `3.47.2` | `3.47.2` | `3.13.2` | 标准 Flutter |

版本信息使用以下命令确认：

```sh
fvm list
fvm --version
fvm spawn 3.41.9 --version
fvm spawn 3.44.9 --version
fvm spawn 3.47.2 --version
fvm flutter --version
```

## 验证命令

当前默认项目 SDK 为 OHOS Flutter：

```sh
fvm dart analyze
fvm dart test packages/ccrouter_test/generator_test
fvm flutter test packages/ccrouter_test/test
fvm flutter test demo/test
fvm dart run ccrouter_generator:ccrouter generate demo --check
```

标准 Flutter SDK 使用指定版本执行同一组不依赖 OHOS 平台的测试：

```sh
fvm spawn 3.41.9 test packages/ccrouter_test/test
fvm spawn 3.44.9 test packages/ccrouter_test/test
fvm spawn 3.47.2 test packages/ccrouter_test/test
```

切换 SDK 后必须先在同一版本执行一次 `pub get`，再运行测试；不能并行运行多个版本，
也不能复用另一个版本生成的 `.dart_tool/package_config.json` 或 `build/unit_test_assets`：

```sh
fvm spawn 3.41.9 pub get
fvm spawn 3.41.9 test packages/ccrouter_test/test --no-pub
```

这些文件包含 Flutter SDK 的实际路径和测试 shader 资产，跨版本复用会产生误导性的
`DisplayCornerRadii`、`HitTestRequest` 或 `ink_sparkle.frag` 错误。

`demo` 的 macOS 构建和真实平台运行不属于 OHOS SDK 与标准 Flutter SDK 的同一项验证；
应分别使用目标 SDK 的平台工具执行，不能用一个平台通过替代另一个平台。

## 已验证范围

- Core / Contracts 的纯 Dart 路由解析、拦截、并发和生命周期测试不依赖 Flutter UI。
- Flutter 测试覆盖 GoRouter Adapter、Page/Route Factory、Host/Outlet、Dialog/BottomSheet、
  Shell、StatefulShell、系统返回和资源销毁。
- Generator 测试覆盖 Analyzer、build_runner、Package Index、Catalog、源码定位和生成物校验。
- GoRouter 当前锁定 `17.5.0`，升级版本需要重新执行 Adapter、Demo 和生成物回归，不能只更新
  `pubspec.yaml`。

本轮本机验证结果：

| SDK | 验证结果 |
| --- | --- |
| OHOS `3.41.10-ohos-1.0.0` | 默认完整回归通过：Workspace analyze、Generator 130 项、Flutter 测试 244 项、Demo 22 项、生成 `--check` |
| 标准 `3.41.9` | 执行独立 `pub get` 后，`ccrouter_test` Flutter 测试 244 项通过 |
| 标准 `3.44.9` | 独立临时工作区执行 `pub get` 后，`ccrouter_test` Flutter 测试 244 项通过 |
| 标准 `3.47.2` | 独立临时工作区执行 `pub get` 后，`ccrouter_test` Flutter 测试 244 项通过 |

此前在同一工作区并行切换 SDK 时出现的 `ink_sparkle.frag` 失败发生在 Flutter Material
shader 资源加载，不是 CCRouter 断言失败；隔离每个 SDK 的 `.dart_tool` 和 `build` 后，
3.44.9 与 3.47.2 均通过完整 244 项测试。兼容性回归必须遵守独立构建缓存和串行执行规则。

## 不应过度宣称的范围

- OHOS Flutter Fork 与标准 Flutter 的平台实现不同；标准 Flutter 通过不代表 OHOS 平台窗口、
  Deep Link 或系统返回行为完全一致。
- 当前没有把 macOS、Windows、iPadOS 原生多窗口生命周期纳入兼容承诺。
- 当前没有用真实 RSS/Heap 数值证明长期无内存增长；资源释放以生命周期测试、活动 Entry、
  pending navigation 和 Adapter 栈清空为确定性证据，长期 RSS 需要在目标应用和平台单独采样。
- FVM 缓存中的版本可用于本机回归，但发布兼容范围仍由各 Package `environment.sdk`、依赖
  约束和实际测试结果共同决定。

## 维护规则

1. 修改 Core、Contracts、Generator、GoRouter Adapter 或生成器输出协议后，至少重跑默认 OHOS
   SDK 的完整命令集。
2. 修改 Flutter Page、Adapter、生命周期或 Demo Host 后，补跑标准 Flutter 3.41.9 的
   `ccrouter_test` Flutter 测试；若涉及平台插件或平台目录，再执行对应平台构建。
3. 升级 Dart、Flutter 或 GoRouter 后，记录版本、命令和失败阶段；不能只记录“能编译”。
4. 新增 API 的性能变化先运行两个现有 scaling benchmark 和并发回收 benchmark，再决定是否
   调整实现或门禁阈值。
