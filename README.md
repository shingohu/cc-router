# CCRouter

CCRouter 是一个面向 Flutter 大型应用的组件化运行时与类型安全路由框架。它把组件装配、路由契约、导航策略、生命周期、跨组件能力调用和诊断统一到稳定的 Core Contract，同时允许 Host 选择 GoRouter 或后续其他导航后端。

当前版本为 `0.1.0`，适合在本仓库 Workspace、Demo 和受控业务试点中验证。所有 Package 目前均为 `publish_to: none`，尚未发布到 pub.dev 或私有 Hosted；接入外部工程前需要先完成正式发布，或使用受控 Git 依赖。不要把本仓库的 Workspace 依赖写法直接复制到另一个仓库。

当前仓库**尚未达到正式发布条件**。License、历史凭据治理、Package 发布集合、Package 级
README/CHANGELOG、Hosted 分发和干净消费者回归等阻塞项见
[`docs/CCRouter-release-readiness.md`](docs/CCRouter-release-readiness.md)。不要仅根据某份设计
文档中的“已完成”将当前 commit 当作 `1.0.0` 稳定发布。

## 为什么使用 CCRouter

- **组件边界明确**：组件只通过 Manifest、Route Contract、Service Contract、Command 和 Event 协作，不依赖其他组件页面实现。
- **导航类型安全**：生成的 Intent 编译期约束参数与返回值，避免散落的字符串 Path 和 `Map<String, dynamic>`。
- **后端可替换**：业务只调用 `CCRouter.navigator`；GoRouter 由独立 Adapter Package 接入。
- **生命周期可控**：Runtime、Session、Route Entry、Service 与 Adapter 均有明确 Owner 和销毁顺序。
- **策略与观察分离**：Interceptor/PopGuard 负责决策，Aspect、Lifecycle 与诊断事件负责观察。
- **生成优先**：路由注册、Package Index、Host Catalog 和文档由统一命令生成，不使用运行时反射。
- **混合导航安全**：Foreign Route、Dialog、Popup、Overlay 不应误删 CCRouter 管理的 Route Scope。
- **可测试、可诊断**：Pure Dart Runtime 测试、Flutter Host 测试、有界 Trace 和稳定错误类型均有独立入口。

## Package 结构

| Package | 用途 | 业务是否直接依赖 |
| --- | --- | --- |
| `ccrouter_contracts` | Pure Dart Route、Service、Command、Event、错误与导航契约 | 仅独立 contracts Package |
| `ccrouter_analytics` | Provider-neutral 分析事件、脱敏属性、有界 Sink 与 Route PV/Leave 桥接 | 按需接入 |
| `ccrouter_analytics_flutter` | 显式点击、滚动和曝光采集 Target | 按需接入 |
| `ccrouter_core` | Runtime、Registry、Scope、调度和诊断实现 | 否 |
| `ccrouter` | Flutter 业务门面、`CCRouterApp`、页面生命周期 | 是 |
| `ccrouter_go_router` | 默认 GoRouter Backend、Assembler、Observer 与 Shell 接入 | 仅 Host |
| `ccrouter_generator` | 注解处理、Host 聚合、校验、查找与清理 CLI | 仅 dev dependency |
| `ccrouter_analyzer_plugin` | Analysis Server 实时边界与生成物诊断 | 仅 dev dependency，需显式启用 |
| `ccrouter_devtools` | 可嵌入的只读 Component/Route/Trace/Failure/InitTask 诊断面板 | 按需作为 Flutter dependency 接入 |
| `ccrouter_devtools_protocol` | Pure Dart、版本化的静态 Catalog/Runtime Snapshot/Trace Edge 协议 | 仅工具与 Host 适配层 |
| `devtools/ccrouter_extension` | 官方 Flutter/Dart DevTools 只读 Extension | 仅开发工具 |
| `ccrouter_test` | 面向集成者的测试 Host、Fake 与测试辅助能力 | 仅 test/dev dependency |
| `demo` | Android、iOS、macOS、Web、OHOS 平台 Host 和完整能力示例 | 示例 |
| `demo/modules/*` | 示例组件、独立 contracts Package 和应用层 Adapter 示例 | 示例 |

Firebase 等供应商 SDK 的初始化、Consent、身份和上传策略属于应用层。仓库中的
`demo/modules/analytics_firebase` 只演示如何把 provider-neutral 事件映射到应用拥有的
Firebase callback，不属于 CCRouter 框架 Package，也不构成框架对 Firebase 的依赖或兼容承诺。

业务与组件默认只导入：

```dart
import 'package:ccrouter/ccrouter.dart';
```

只有应用 Composition Root 可以导入 `ccrouter_go_router` 和 `package:ccrouter/ccrouter_host.dart`。业务代码不得导入 `ccrouter_core/src/*`、Adapter 或 Host SPI。

`CCRouterHost.initialize`、`CCRouterHost.shutdown` 和 `CCRouterHost.runInitTasks` 只从
`ccrouter_host.dart` 提供；装配类型 `CCHostAssembly` 也只属于 Host API。业务入口 `CCRouter`
不提供这三个方法，不保留旧入口或兼容转发。Session 的 `openSession/closeSession` 和只读
`initTasks` 仍属于业务 API。多个导航 Host 共享默认 Runtime，关闭某个导航 Host 不应关闭 Runtime。
可选 Analyzer Plugin 通过 `ccrouter_host_lifecycle_access` 拒绝组件导入／转导出生命周期入口，
并按框架声明身份检查经公共 barrel 使用的 `CCRouterHost`；Host 角色依据 `.metadata`、
`ccrouter.yaml` 和直接依赖判定。该诊断针对组件 Package 的 `lib/`，测试／工具及生成物除外；
同一个 Host Package 内无法自动区分装配文件与页面，仍需代码审查。Dart 导出边界独立于 Plugin 生效。

### IDE / Analysis Server 诊断

生成的 Route API 已经提供类型补全和自动导包。需要编辑时实时检查跨组件内部生成物引用、
同源 Route/Service/Command/Event/InitTask 生成物缺失和 required InitTask 声明时，可显式加入 `ccrouter_analyzer_plugin` 并在
`analysis_options.yaml` 中启用：

```yaml
analyzer:
  exclude:
    - tool/ccrouter_analyzer_host/tools/analyzer_plugin/**
  plugins:
    - ccrouter_analyzer_plugin
```

隔离 loader 不属于 Host 的应用依赖图。Host 的 `dart analyze` / `flutter analyze` 必须排除内层
`tools/analyzer_plugin/**` 源码；其依赖解析、analysis 与 loader compile 由
`ccrouter analyzer doctor <host-root>` 在隔离图中验证。Demo 的自定义目录使用对应的
`tools/ccrouter_analyzer_plugin_host/tools/analyzer_plugin/**` 路径。

插件只提供轻量诊断，不执行生成、不在后台修改源代码，也不替代 `ccrouter generate --check`。
它读取 Analysis Server 的当前 overlay，未保存的 `.dart` 编辑也会触发实时诊断；Plugin
初始化只扫描开发者编写的 Dart 源码，不遍历平台产物或 CCRouter 生成库。
当 `ccrouter generate` 或 `ccrouter clean` 新增、修改或删除同源生成物时，插件会重新检查
对应的声明源文件，避免生成成功后仍保留旧的“生成物缺失”提示。依赖跨文件 Catalog 的
Component API 聚合与 metadata-only Contract 继续由 `ccrouter generate --check` 校验，插件不做
不可靠的单文件猜测。
Plugin 使用与 Generator 一致的 `requestedRoot/resolutionRoot` 语义：Workspace member 只接受
有效 `workspace_ref.json` 或精确 membership，standalone 嵌套 Package 不继承父 Workspace graph。
保存的依赖与 resolved graph 不一致时，即使没有 active watch，IDE 也会按 Host、Flutter
package-local 或 Pure Dart package-local 提示对应的 `flutter pub get`/`dart pub get`；该提示只
暂停 Owner 推断，不执行 Pub 或生成。打开 Workspace 根目录时，Plugin 会从根 manifest 的
显式 member 列表建立有界索引，因此每个参与生成的 member 都会独立获得、清除该提示；
500ms polling 不递归扫描 Workspace。

插件还会在编辑期检查 Handler 的 public/top-level/non-generic 形态、显然不支持的参数数量和
void 返回形态、Route `pattern/patterns`、InitTask `contract/id`、字面量 ID/alias/Gate ID 与
可计算 timeout。它还从 Pub 已解析 Package 的精确 metadata 建立有界 Owner 索引，在
`serviceDependencies` 或 `commandDependencies` 缺少 required Owner 时实时报错。互斥参数可以
显式删除其中一个；Owner 唯一、公共 import 已暴露准确 `CCComponentId` 且 `dependencies` 是
直接 List 时，可以由开发者主动应用单 Owner Quick Fix；同一组件的全部缺失 Owner 都能被
唯一证明时，还会提供一次补齐全部 Owner 的 Quick Fix。插件不会创建 Contract、猜测标识符、
自动插入 import、改写复杂集合或运行 Generator。
涉及 Handler 类型、Owner 常量和 Service 继承时，插件按需复用 Analysis Server 的当前解析结果，
支持 `Future` 前缀、typedef、const alias 和导入遮蔽；无法证明的值暂缓判断，不按末尾名称猜测。
`@CCService` 已有兼容 `dispose()` 却未实现 `CCDisposable` 时会警告；接口已明确导入时可用
Quick Fix 补接口，保留原释放代码。直接自建并持有可释放资源却未接入 Scope 时提供所有权提示，
不生成空 `dispose()` 或自动释放借用资源。没有提示不代表已证明无泄漏，仍需生命周期测试。
当前仓库 Demo 已在 `demo/analysis_options.yaml` 启用它，并通过
`demo/tools/ccrouter_analyzer_plugin_host` 提供官方要求的 `tools/analyzer_plugin` bootstrap。
bootstrap 使用远端固定 Git commit 隔离 Analyzer 版本；Hosted 发布后优先在 Host 的普通
`dev_dependencies` 中声明 `ccrouter_analyzer_plugin`，可切换到同目录的
`pubspec.hosted.yaml` Hosted manifest。不能把本地 Workspace path 直接放进 bootstrap，因为
Analysis Server 会把 bootstrap 复制到临时目录。完整接入、固定 ref、Hosted fallback 和
Analyzer 版本边界见
[`docs/CCRouter-ide-analysis-server.md`](docs/CCRouter-ide-analysis-server.md)。

手工装配完成后可从 Workspace 根检查指定 Host；命令只读取配置，`doctor` 在临时副本中验证
锁定依赖、bootstrap 分析和 loader 编译，不运行 Generator，也不改写 Host 配置：

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer status demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer doctor demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer pin-check demo
```

`status` 的 `healthy` 只代表 manifest、lockfile、固定来源和版本静态一致，不能证明 Analysis
Server 已经加载插件；`doctor` 通过只证明当前凭据和临时副本中的隔离 bootstrap 可解析、分析
并编译。它会分别报告 source pin、legacy cache artifact、restart 和 live verification 状态，
不会把 loader compile 写成 IDE live success。`pin-check` 是 maintainer/release 手动检查：验证
Demo 活动 manifest/lock/`resolved-ref`、远端完整 SHA，并以 advisory 报告 pin 之后 Plugin
`lib` 是否有生产变化；它不接入普通 Plugin PR 硬门禁。

`doctor` 对当前 bootstrap 对应的 Analysis Server 缓存只给 advisory；私有 `.plugin_manager`
不是跨 SDK 权威门禁。发现 stale/incomplete 条目时，它会尽可能报告候选 PID、PPID、elapsed、
command 和精确备份路径，但不会自动 kill、移动或删除。先从 IDE 停止 Analysis Server，确认
相关进程退出，再把列出的完整 hash entry 手工移到 `.plugin_manager` 外；不能只移动其中的
`analyzer_plugin` 子目录，也不能清空无关 cache。重启后仍需用真实 diagnostic/Quick Fix 验证。

`dart analyze` 不能证明当前 IDE 会话已经加载 CCRouter Plugin。Dart 3.11.5 在分析范围命中
Host bootstrap 配置时会初始化 Plugin manager，可能报告 Plugin 诊断，也可能暴露 Server/Plugin
启动或兼容性失败；它不能再被视为“只运行 Dart 内置规则”。该行为受 SDK、分析范围和
bootstrap 状态影响，不能替代 Android Studio、IntelliJ、VS Code 或真实 Language Server
会话验证。最终跨文件正确性仍以 `ccrouter generate --check` 为准。
仓库提供独立 Server 进程回归：在 `packages/ccrouter_analyzer_plugin/` 执行
`fvm dart test test/analysis_server_integration_test.dart`。测试覆盖 Legacy/LSP 修复往返、
未保存编辑、五类生成物磁盘变化及 Workspace Owner 元数据刷新；不替代当前 IDE 的
bootstrap/ref 加载验证。具体 SDK 和多根工程边界见 IDE 文档。

已存在隔离 bootstrap 的 Host 可用显式装配命令（`install`/`upgrade` 为 legacy
maintenance-only，并会输出弃用提示；Hosted 发布后优先普通 `dev_dependency`，下列 Hosted
版本必须已发布，Git 则使用已评审的远端完整 SHA）：

```bash
ccrouter analyzer install <host-root> --version <published-version> --dry-run
ccrouter analyzer install <host-root> --source git --url <remote-url> --ref <full-commit-sha>
ccrouter analyzer upgrade <host-root> --ref <full-commit-sha>
ccrouter analyzer uninstall <host-root> --dry-run
```

三种写命令均支持 `--dry-run`；正式操作先验证隔离 loader，再更新 Host 并运行禁用 Hook 的
Pub。CLI 会自动把内层 loader 路径加入 Host `analyzer.exclude`，并在 ownership marker 中记录
该列表项是否由 CLI 新增；卸载只删除自己新增的项，预先存在的相同项、其它 excludes、规则、
注释与未知文件都保留。冲突或手工 bootstrap 不自动接管。`status`/`doctor` 会把缺少 loader
exclude 报告为未完成配置。新安装统一写入现有 Dart 工具目录
`tool/ccrouter_analyzer_host`；旧版 CLI 已管理的 `tools/ccrouter_analyzer_host` 仍可原地升级和卸载，
命令不会隐式搬移用户目录。失败恢复受管配置与记录的解析文件；进程中断或并发编辑
保留事务恢复记录并停止后续写入。写事务按 canonical Workspace Pub owner 串行化；lock 与
恢复记录位于 project-isolated `CCROUTER_HOME/coordination/v2`，不会被 `flutter clean` 删除。
`CCROUTER_USE_LEGACY_DART_TOOL_LOCKS=1` 可把它们临时切回 Pub owner 的 `.dart_tool` 做 A/B；
新旧模式检测到对方仍持锁时会 fail-fast。Demo 仍保持手工 bootstrap 和现有远端 pin。
Analyzer 装配不得隐式挂入 `generate`、Pub Hook 或组件脚手架。详见
[Analyzer CLI 指南](docs/CCRouter-analyzer-cli-plan.md)。

### DevTools 只读面板

Host 直接依赖 `ccrouter_devtools` 并重新生成后，Host Assembly 会自动携带静态 Catalog 和
DevTools Tool Integration。Debug 默认启用，Profile 需要显式
`CCROUTER_DEVTOOLS=true`，Release 强制关闭。页面侧只需在 Debug Drawer 或内部诊断路由嵌入：

```dart
import 'package:ccrouter_devtools/ccrouter_devtools.dart';

const diagnosticsPage = CCRouterDevToolsPanel();
```

面板只读展示静态 Catalog 与 Runtime 的联动、源码位置、可搜索/聚焦的 Component Graph、
Managed/Backend Entries、Trace Timeline、Failure/Fallback、InitTask DAG 和能力调用链。
源码位置默认以可复制的 `package:` URI 展示；Host 可以通过 `onOpenSource` 映射到自己的 IDE
或源码浏览器。它不会初始化 Runtime、导航、Pop、重试任务、销毁 Scope 或控制 Adapter；
未初始化时显示空状态。当前 Demo 的“实时诊断”分区会读取生成式 Host Catalog，并同时验证
嵌入式面板和官方 Extension 的静态/运行时关联行为；业务组件不手工注册或清理 Extension。
完整数据边界和接入方式见
[`docs/CCRouter-devtools.md`](docs/CCRouter-devtools.md)。

## 当前能力

| 能力 | 状态 | 说明 |
| --- | --- | --- |
| 启动期组件装配 | 已支持 | 依赖排序、重复 ID、缺失依赖和循环依赖校验 |
| 注解路由与类型安全 Intent | 已支持 | Path、URI、custom scheme、Regex、多 Pattern、Query、Extra、typed result |
| 页面展示 | 已支持 | 平台默认、Material、Cupertino、fade、scale、bottom-up、透明全屏 |
| Modal Route | 已支持 | Dialog、modal bottom sheet，可选择是否纳入 CCRouter 契约与生命周期 |
| 导航操作 | 已支持 | `push`、`replace`、`go`、`reset`、`open`、`pop`、`maybePop`、`canPop` |
| GoRouter Backend | 已支持 | 新工程 managed 模式和已有 GoRouter attach 模式 |
| Shell / StatefulShell / Outlet | 已支持 | 显式 Host 装配，支持多 Outlet 与调用级 Context 定位 |
| Deep Link | 已支持 | Platform、Notification、QR 入口，Host allowlist 与 Route policy 双重校验 |
| Interceptor / Redirect / Defer | 已支持 | 全局与路由级策略、超时、取消、Pending 恢复 |
| PopGuard | 已支持 | 业务 Pop、系统返回、Cupertino 手势和预测返回进入统一判断 |
| Aspect / Trace / Telemetry | 已支持 | 有界、脱敏、观察异常隔离 |
| Provider-neutral Analytics | 已支持 | Route PV/Leave、稳定事件契约、属性校验和有界异步 Sink；不绑定第三方 SDK |
| Widget 点击/滑动/曝光采集 | 部分支持 | `CCAnalyticsTarget`、`ccrouter_analytics_flutter` 提供显式点击、滚动聚合和曝光；全局 Widget 猜测仍不支持 |
| 页面生命周期 | 已支持 | `PageShow/PageHide` 与前后台，Mixin 和 Listener 两种形式 |
| Service | 已支持 | App/Session/Route Scope，singleton/newInstance，Key、稳定 Contract ID、lazy async readiness |
| Namespace-aware KV Storage Demo | 已支持（Demo） | 基本类型、JSON Map、全局/游客/用户/API 环境/硬件命名空间和可替换 Backend 抽象 |
| Command | 已支持 | 单 Handler、强类型结果、`void`、取消、超时与 Trace |
| Event | 已支持 | 零到多个订阅者、稳定顺序、失败隔离 |
| InitTask | 已支持 | 一次性 DAG、Gate、必需/可选失败策略 |
| 生成器增量缓存与门禁 | 已支持 | 内容校验 fast path、`--check`、`--no-cache`、`--profile`、并发锁、原子写入 |
| 生成索引和源码定位 | 已支持 | Package/Host Catalog、`ccrouter find` |
| DevTools 只读可视化 | 已支持 | 生成式 Host 自动装配、Catalog/Runtime 联动、源码定位、组件依赖聚焦、能力调用链、纯 Dart 协议和官方 Extension |
| Navigator 1.0 Backend | 暂不支持 | 2.0 阶段候选 |
| 通用 Navigator 2.0 Backend | 暂不支持 | 2.0 阶段候选 |
| 动态组件安装/卸载 | 暂不支持 | 当前组件集合在 `initialize` 时固定 |
| Action Pipeline | 暂不支持 | 等真实优先级、短路、白名单场景成熟后再设计 |
| 完整状态恢复 | 暂不支持 | 当前只记录脱敏的 restoration opportunity |
| Service 注解生成 | 已支持 | `@CCService` 自动绑定唯一直接 Contract，并生成简单 Provider registration |
| Command 注解生成 | 已支持 | Contract、Handler、Owner/Consumer Client、稳定 ID、metadata 与 Catalog 自动生成 |
| Event 注解生成 | 已支持 | Contract、静态 Subscription、Owner Publication Client、稳定 ID、metadata 与 Catalog 自动生成 |
| InitTask 注解生成 | 已支持 | Task Contract、Handler、类型化依赖、自动注册、DAG/Catalog 与 Workspace 校验 |

GoRouter 当前无法可靠提供原子 `pushAndRemoveUntil`、精确 `removeRoute/removeRouteBelow` 和 `replaceRouteBelow`。CCRouter 不公开语义不完整的替代方法，也不会把它们静默拆成多个普通操作。

## 环境要求

- Dart SDK `^3.10.0`
- Flutter SDK：本仓库默认使用 FVM 配置的 Flutter/OHOS Flutter SDK
- GoRouter `^17.5.0`

首次运行：

```bash
CCROUTER_PUB_HOOK_DISABLE=1 fvm flutter pub get
fvm dart analyze packages
fvm dart analyze tool
fvm flutter test packages/ccrouter_test/test
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test
fvm flutter test --no-pub demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check
```

仓库根目录是 Dart Workspace 聚合根，不是 CCRouter Host。根依赖解析必须禁用 Pub Hook，
静态分析应按 `packages` 与 `tool` 分层执行，再对 `demo/` 这个真实 Host 单独执行测试与生成
检查。根 `dart analyze` 会进入 Demo 的 legacy Plugin bootstrap，不是可靠的聚合门禁；不能把
Plugin 启动失败或根 Hook 的 Host 识别失败报告成 Pub 依赖解析失败。

运行 macOS Demo：

```bash
cd demo
fvm flutter run -d macos
```

## 最小接入

### 1. 声明组件

每个实现 Package 只定义一个顶层 `const CCComponent`。生成器会自动发现它，并生成
Registrar、Manifest、路由目录和简单 Service 注册：

```dart
import 'package:ccrouter/ccrouter.dart';

const orderComponentId = CCComponentId('order_component');

const orderComponent = CCComponent(
  id: orderComponentId,
  version: '1.0.0',
  dependencies: [accountComponentId],
);
```

不需要手写 Registrar。Shell、复杂 Service 或其它没有专用声明模型的扩展
可放进带 `@CCComponentContribution` 的顶层注册函数；生成器会把它并入同一个私有 Registrar。
组件定义、Contribution 和生成装配入口不要从业务 barrel 导出。组件间使用公开 contracts
Package 或明确的 public contract library。

### 2. 声明组件内路由

```dart
import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

import 'ccrouter_generated/order_component.api.g.dart';

@CCRoute<String>(
  id: 'order.detail',
  pattern: CCPathPattern('/orders/:orderId'),
  description: '订单详情，确认后返回订单编号。',
)
final class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({
    required this.orderId,
    @CCQueryParam() this.tab = 'summary',
    super.key,
  });

  final int orderId;
  final String tab;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('订单 #$orderId')),
    body: FilledButton(
      onPressed: () => CCRouter.navigator.pop(result: 'confirmed:$orderId'),
      child: const Text('确认'),
    ),
  );
}
```

页面源码**不需要**添加 `.route.g.dart` 的 `part`。执行生成后，IDE 可从组件唯一的
`<componentId>.api.g.dart` 自动补全路由、Service Proxy、Command 和 Event API。

业务源码应优先导入稳定的组件 API 入口：

```dart
import 'ccrouter_generated/order_component.api.g.dart';
```

该文件由生成器按 `componentId` 维护，只通过受控 `export/show` 暴露允许业务使用的类型安全
API，不导出 Registrar、Binding、Host、Manifest、Metadata 或 Route Registration Bridge。底层
`component/*_api.g.dart` 仍是生成器和 Host 胶水的实现文件，业务源码不应直接依赖；没有可导出
能力的组件不会生成空的 `.api.g.dart`。

单一地址使用 `pattern`；兼容旧 Path 或多入口时使用 `patterns`。两者不能同时设置。多值中只有一个可逆 Pattern 时会自动成为 primary；多个可逆 Pattern 必须显式指定唯一 primary；只有 Regex 且无法反向构造 URI 时生成失败。

### 3. 生成代码

从 Workspace 根目录执行：

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo
```

统一命令会运行所需的 build_runner、生成 Package 内路由代码、组件索引、Host Bundle、Catalog 和文档。生成文件位于各 Package 的 `lib/src/ccrouter_generated/`，禁止手工编辑。

### 4. 命名空间 KV Storage（Demo）

`demo/modules/kv_storage` 展示一个后端无关的 KV Storage Service。常规业务调用通过
`DemoScopedStorage` 从 Host 提供的上下文解析数据边界，不在每次读写时传入账号或环境 ID：

```dart
final storage = DemoScopedStorage(
  service: DemoNavigationLabServices.demoKeyValueStorage,
  contextProvider: contextProvider,
);

await storage.global.setBool('privacy.accepted', true);
await storage.currentUser.setJson('profile.preferences', {
  'theme': 'dark',
  'notifications': {'enabled': true},
});
```

底层 `DemoStorageNamespace` 和 `CCStorageClient` 仍保留给 Backend、迁移和测试使用。
支持 `String`、`int`、`double`、`bool` 和 JSON Object 的类型化读写。不同命名空间的
相同 Key 互不覆盖；JSON 在写入和读取时都会复制，避免调用方修改内部状态。
`CCStorageBackend` 是实现替换边界，Demo 默认使用内存 Backend，因此重启应用后数据会丢失。
生产环境应由应用 Composition Root 接入文件、数据库或 Secure Storage Backend，并根据数据
敏感度选择加密和清理策略；命名空间本身不是安全边界，也不会自动提供加密。
Scoped Facade、Session/Environment/Device 上下文绑定和 Backend Placement Policy 的设计与
边界见
[`demo/docs/kv-storage-demo-migration.md`](demo/docs/kv-storage-demo-migration.md)。该方案属于
Demo / 应用层，不是 CCRouter 框架的存储契约。

### 5. 初始化 Host

Host 使用生成的 Manifest 与 Catalog。新项目默认使用 managed GoRouter Backend：

Host 自己的公共 barrel 只需转发生成的
`src/ccrouter_generated/ccrouter_host.api.g.dart`；不要直接导出 `host/` 下的内部聚合文件或
手写 `show` 列表。稳定入口只导出完整的 Host Assembly；初始化后 managed Host 会通过
Host-only Binding 使用其中的 Catalog，避免重复传参或混用不同代生成物。

`CCRouterHost.initialize` 只接受一个必填 `CCHostAssembly`。已有工程需要手写装配时使用
`CCHostAssembly.fromComponents(components: ...)`，不要把 Component、Contract、Catalog
和 Tool Integration 拆成多组初始化参数。手写 Host 自己提供页面目录时，也必须通过
`fromComponents(routeCatalog: ...)` 放入同一个 Assembly；`CCGoRouterApp` 不提供覆盖入口。

```dart
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CCRouterHost.initialize(
    hostAssembly: ccrouterGeneratedHostAssembly,
  );
  await CCRouterHost.runInitTasks(gate: CCInitTaskGate.appStarted);
  runApp(const CCGoRouterApp());
}
```

上面的 `CCGoRouterApp` 会自动装配 managed GoRouter、Root Observer、Adapter、Host
和 `MaterialApp.router`，但不会初始化或关闭进程 Runtime。`CCRouterHost.initialize` 始终由
Composition Root 显式调用；全局拦截器、Deep Link 白名单、Aspect、Telemetry 等配置也放在
这里：

```dart
CCRouterHost.initialize(
  hostAssembly: ccrouterGeneratedHostAssembly,
  globalInterceptors: const [...],
);
final initResult = await CCRouterHost.runInitTasks(
  gate: CCInitTaskGate.appStarted,
);
// 仅无法降级的 Host 才显式选择 fail-fast：
// initResult.throwIfRequiredFailed();
runApp(const CCGoRouterApp());
```

`CCGoRouterApp` 直接提供 `MaterialApp.router` 的非路由配置，包括主题、高对比度主题、
国际化、`ScaffoldMessenger`、快捷键/Action、Restoration、滚动行为和调试开关。普通 Host
不需要为了设置 `locale` 再手写一层 `MaterialApp.router`：

```dart
runApp(
  CCGoRouterApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
  ),
);
```

`routerConfig`、`routerDelegate`、`routeInformationProvider`、
`routeInformationParser` 和 `backButtonDispatcher` 不对外透传；它们由
`CCGoRouterBackend` 唯一管理。需要 Shell、redirect、refresh 或自定义 Router 时使用
`backendFactory`，不要在应用 Widget 和 Backend 两处重复配置路由所有权。

复杂 Shell/Outlet 或自定义 Router 构造仍可复用同一个 Widget，通过一次性 Factory 消除
`StatefulWidget + late Backend + CCRouterApp.managed + MaterialApp.router` 样板：

```dart
runApp(
  CCGoRouterApp(
    backendFactory: (configuration) => createApplicationBackend(
      catalog: configuration.catalog,
      initialLocation: configuration.initialLocation,
    ),
  ),
);
```

默认 `CCGoRouterApp` 自动使用 `CCRouterHost.initialize` 安装的同一份 Catalog。只有直接使用
`CCGoRouterBackend.managed/attach` 的高级 Host 或渐进式接入才显式传递 Catalog；业务代码
不能通过 `CCRouter` 读取路由表。

同一个 Flutter View 确实需要多个独立 Router Host 时，使用
`CCGoRouterMultiHostBackend.managed` 聚合 Host Backend。它自动复用初始化时安装的同一份
Catalog，校验 Host ID，聚合 `CCMultiHostNavigationAdapter`，并在 Runtime shutdown 后统一
释放各 Router。应用仍然负责 Router surface 的布局和 active Host 选择：

```dart
final backend = CCGoRouterMultiHostBackend.managed(
  defaultHostId: 'workspace.primary',
  hostFactories: {
    'workspace.primary': (configuration) => createWorkspaceBackend(
      catalog: configuration.catalog,
      hostId: configuration.hostId,
    ),
    'workspace.secondary': (configuration) => createWorkspaceBackend(
      catalog: configuration.catalog,
      hostId: configuration.hostId,
    ),
  },
);
```

当多个 Host 同时可交互时，Composition Root 必须在 Pointer 或 Focus 进入某个 Router surface
时调用 `backend.adapter.activateHost(hostId)`，让无显式 Context 的 Pop、系统返回和默认 placement
导航始终落到当前交互 Host。不要让业务页面自行选择 Host；需要精确定位 Host/Outlet 的
`push`、`replace`、`go`、`reset` 或 `open` 仍应传入调用点 `BuildContext`。

这不是大屏分栏、Bottom Tab 或 Shell 的默认方案；这些场景通常使用一个 Host 下的多个
Outlet。聚合器也不代表平台 Window，不负责 macOS、Windows 或 iPadOS 原生窗口生命周期。

`CCRouterHost.initialize` 同步完成全局配置和启动组件注册；`CCGoRouterApp` 不会在卸载时隐式 shutdown Runtime。应用 Composition Root 结束默认 Runtime 时执行（包括使用生产装配入口的集成测试）：

```dart
await CCRouterHost.shutdown();
```

不要在页面 Pop、组件页面销毁、App 后台或 Session 关闭时 shutdown。Runtime 会先销毁它拥有的 Adapter，再释放 managed Backend 创建的 GoRouter；attach 模式不会销毁应用自己创建的 GoRouter。销毁、动态 Host 注销或 Host 初始化失败时采用 best-effort 结构化清理：某个 listener remover、PopGuard 解绑或子 Adapter 抛错不会跳过其它资源，调用方最终收到首个失败。

取消 Listener 抛错也不会截断其余通知和资源释放。Token 通知结束后重抛首个错误；Scope 将
取消错误与 Service dispose 错误一起留在内部清理记录中，继续逆序释放。Runtime 在早期
App 取消通知失败时继续完成全部清理，再向 shutdown 调用方报告失败。关闭操作在调用
Listener 之前建立门禁，重复调用只等待同一轮清理；即使回调同步重入，也不能提前 initialize。

这里的命名按所有权层级区分：`CCRouterHost.initialize()` 创建并原子初始化进程默认 Runtime，
`CCRouterHost.shutdown()` 由应用 Composition Root 停止该 Runtime；它们不是某个 Widget 或对象实例
的 `init/dispose`。Runtime、Adapter、Scope、Service 等具体实例仍由各自 Owner 调用内部
`dispose`。`CCRouterHost.runInitTasks(gate: ...)` 打开一个 `CCInitTaskGate` 并等待零到多个新就绪
任务，它不会再次初始化或替换 Runtime，也不会重试已完成或失败的任务。所有 `shutdown()`
调用都必须被 `await`，完成后才允许重新调用 `initialize()`。

已有 GoRouter 工程使用 `CCGoRouterBackend.attach`，把生成 bindings、Host 和已经安装到 Router 的 Observer 显式交给 CCRouter。只有需要完全自定义应用 Widget 树时才直接使用 `CCRouterApp.managed`。完整 Shell/Outlet 示例见 [`demo/lib/demo_router_backend.dart`](demo/lib/demo_router_backend.dart)。

### 分析事件与页面埋点

`ccrouter_analytics` 只提供不绑定供应商的事件契约和页面生命周期桥接。它会把 CCRouter 管理的 Route
`arrival/show/hide` 转换成 `page.view.*` 和 `page.leave.*`，并通过有界异步 Dispatcher 交给应用自己的
Firebase、ThinkingData、Sentry 或日志 Adapter。Sink 异常不会改变导航结果，队列满时会丢弃最旧的非关键分析事件。

需要减少页面重复传递上下文时，可选依赖 `ccrouter_analytics_flutter` 的
`CCAnalyticsScope`：根 Scope 注入应用拥有的 Dispatcher，页面 Scope 增量提供稳定的
`CCAnalyticsContext`，业务通过 `CCAnalyticsScope.trackerOf(context)` 获得值对象 Tracker。
Scope 不关闭 Dispatcher，也不扫描 Widget、Route 或 Foreign Popup；没有稳定上下文时应省略归因字段。
导航桥接器还为每次 managed Arrival/Show 生成有界 `visit_id`，在 Hide 时记录总停留和
前台停留毫秒数。Host 生命周期回调应调用 `onBackground/onForeground`，Host 销毁时调用
`bridge.dispose()`；它不会把 Foreign Popup 当作页面访问。

```dart
final analytics = CCAnalyticsEventDispatcher(
  sinks: [applicationAnalyticsSink],
);
final navigationAnalytics = CCNavigationAnalyticsBridge(
  dispatcher: analytics,
);

CCRouterHost.initialize(
  hostAssembly: ccrouterGeneratedHostAssembly,
  navigationAspects: [navigationAnalytics.createAspect()],
);

// 隐私授权完成后再开启分析；撤销授权会取消尚未开始的投递。
analytics.updatePolicy(
  CCAnalyticsPolicy(consentGranted: true, sampleRate: .25),
);
```

分析属性必须使用 `CCAnalyticsProperty` 声明，禁止放入 Token、完整 URI、Widget、异常对象或任意业务对象。
支持的 String/num 列表在属性创建时复制为不可变快照，调用方或某个 Sink 的修改不能污染其他 Sink。
每个字符串最多 256 个字符、列表最多 32 项、单个事件最多 64 个属性，属性值保守总大小最多 4096
字符，数值必须有限；黑名单和节流状态也有固定上限。超限会在构造阶段抛出 `ArgumentError`，便于尽早发现错误。
撤销 Consent 或禁用分析会清空队列，并阻止当前事件继续投递到尚未开始的 Sink；立即重新授权也不会恢复旧事件。
已经开始的 Sink 写入无法撤回，网络取消和供应商缓存清理由应用 Adapter 负责。

`dispatch` 只负责入队，首个 Sink 也在后续事件循环启动。Composition Root 结束时应等待
`analytics.close()`，它会停止接收并等待已接受的投递；不要在 Sink 自己的 `write` 中等待 `close()`，
否则形成自身等待。对不可靠的应用 Sink 可以配置 `sinkWriteTimeout`；超时后该 Sink 会被隔离，
`close()` 的等待有界，但 Dart Future 不可撤销，Sink 自身仍应支持取消。默认不配置超时，保持等待
写入完成的语义。异步分发不等于后台线程，Sink 仍应避免在 UI isolate 执行耗时同步计算。
任意 Button、列表项点击和滚动不由 Core 猜测；使用 `CCAnalyticsTarget` 包装现有回调，自动 UI 采集只能作为默认关闭的独立插件接入。
需要滚动会话或曝光时，按需依赖 `ccrouter_analytics_flutter`，显式包裹
`CCAnalyticsScrollable` 或 `CCAnalyticsExposureTarget`；曝光默认按可见比例、最小停留
时间和目标生命周期去重，不读取 Widget 文本，也不注册全局手势监听。
Target 自动监听祖先滚动与分析策略；可见比例取 View 和祖先裁剪区域的交集，不判断任意
Overlay 遮挡或像素透明度。Consent 拒绝、后台或暂时移出树会取消本次停留计时，恢复后
必须重新满足完整时长。`once` 只在 Dispatcher 接受事件后生效，不保证 Sink 已成功写入；
采样、黑名单或节流拒绝不会消耗一次额度，也不会逐帧重试。

分析 Dispatcher 还提供不含事件内容的压力指标：`acceptedEventCount`、`pendingEventCount`、
`peakQueueDepth`、`droppedEventCount`，以及慢 Sink 的 `timedOutSinkWriteCount`、
`quarantinedSinkCount`。`dispatcher.snapshot` 还提供按 Sink 索引的成功/失败/超时和累计耗时
快照。它们只用于性能/健康诊断，不是审计日志或事件回放接口；可用
`packages/ccrouter_test/benchmark/analytics_dispatcher.dart` 在同一 SDK 和平台下输出入队延迟、队列压力
与 RSS 趋势。

当前 Demo 的事件字段已经由原语校验、Context/Scope 和应用层 Adapter 覆盖；没有真实跨项目
消费者前，框架不额外引入强制事件 Schema 或分类采样规则。需要更严格字段时由业务 Contract
或 Adapter 校验，避免把产品字段表固化进框架。

```dart
final confirmTarget = CCAnalyticsTarget(
  tracker: tracker,
  eventId: 'order.detail.confirm',
);

FilledButton(
  onPressed: () => confirmTarget.run(submitOrder),
  child: const Text('确认订单'),
);
```

完整边界和分阶段计划见 [`docs/CCRouter-analytics-and-auto-track-design.md`](docs/CCRouter-analytics-and-auto-track-design.md)。

## 类型安全导航

业务导航统一经过 `CCRouter.navigator`：

```dart
final result = await CCRouter.navigator.push<String>(
  OrderComponentRoutes.detail(orderId: 42, tab: 'payment'),
  source: const CCNavigationSource.feature('checkout'),
);

await CCRouter.navigator.replace<void>(AccountRoutes.login());
await CCRouter.navigator.go<void>(HomeRoutes.home());
await CCRouter.navigator.reset<void>(HomeRoutes.home());

final handled = await CCRouter.navigator.maybePop();
CCRouter.navigator.pop(result: 'confirmed');
```

语义：

- `push`：在当前栈上新增 Entry，并在该 Entry 被移除时返回强类型结果。
- `replace`：替换当前 CCRouter 管理的 Entry。
- `go`：采用后端 declarative location 语义，与 GoRouter `go` 对齐；可能重建匹配栈。
- `reset`：明确把目标设置为新的根位置。
- `open`：匹配应用内部动态 URI，默认以 push 方式打开，不提供 typed Pop result。
- `maybePop`：尊重 PopGuard、Flutter `PopScope`、LocalHistory 与 foreign popup，返回后端是否处理。
- `pop`：业务主动返回；返回值必须与 Route 的结果类型一致，否则抛出标准导航错误且页面不会被错误移除。

禁止业务代码直接调用 `Navigator.push/pop`、`GoRouter.push/go` 或 Adapter 来操作 CCRouter 管理的页面。临时、局部且不需要组件契约的 Flutter Dialog/BottomSheet 可以继续使用原生 API；它们属于 foreign/overlay，不应改变 Managed Route Scope。

### BuildContext 与 Outlet

通常不传 `BuildContext`，行为与全局 Host 路由一致。只有同一路由需要按调用位置落入当前 Shell、Pane 或嵌套 Navigator 时才传：

```dart
await CCRouter.navigator.push<void>(
  DetailRoutes.detail(id: 1),
  context: context,
);
```

Context 只用于严格解析最近的 Host/Outlet，不会被全局保存。解析失败会报错，不会猜测另一个 Host 或 Outlet。

### 动态 URI

应用内部运行时地址使用：

```dart
await CCRouter.navigator.open(Uri.parse('/orders/42?tab=payment'));
await CCRouter.navigator.open(Uri.parse('myapp://order/42'));
await CCRouter.navigator.open(
  Uri.parse('https://example.com/web?url=https%3A%2F%2Fflutter.dev'),
);
```

匹配在 URI 结构层完成，Path segment 与 Query 按 Codec 解码；不要先对完整 URI 做字符串级 `decodeComponent`。需要传递标准网页 URL 时，把它作为 Query 参数或 typed argument，不要把未转义 URL 拼进另一个 Query。

### Path、URI 与参数

路由支持：

- 标准 Path：`/orders/:orderId`
- 完整 URL：`https://example.com/orders/:orderId`
- custom scheme：`myapp://order/:orderId`
- Regex：用于只匹配、不反向生成的兼容入口
- 多 Pattern 指向同一页面
- Path 参数自动转换
- `@CCQueryParam` 标量、enum、`List<T>`、`Set<T>` 与自定义 Codec
- `@CCExtraParam` 强类型进程内对象；生成的 binding 保留参数静态类型，并在 decode 边界校验对象类型

外部可分享数据应进入 Path/Query；Token、Controller、大对象和不可序列化状态不得放入 URL。`Extra` 只适合进程内短生命周期数据，不写入 URI、生成文档或诊断；错误类型会抛出不包含原始值的 `CCRouteParameterError`。不能依赖 `Extra` 做 Deep Link、状态恢复或跨进程传递。

## 跨组件 Route Contract

组件内路由默认保持内部。只有另一个组件确实需要调用时，才把契约提升到独立 Pure Dart contracts Package：

```dart
// order_contracts
@CCRouteContract<String>(
  componentId: orderComponentId,
  id: 'order.detail',
  pattern: CCPathPattern('/orders/:orderId'),
)
abstract class OrderDetailRouteContract {
  const OrderDetailRouteContract({
    required this.orderId,
    @CCQueryParam() this.tab = 'summary',
  });

  final int orderId;
  final String tab;
}
```

页面组件只绑定实现：

```dart
@CCRouteImplementation(OrderDetailRouteContract)
final class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({required this.orderId, this.tab = 'summary', super.key});
  // ...
}
```

消费者依赖 `order_contracts`，不依赖 `order` 页面 Package。保持原 route ID、wire name 和结果类型，可以把既有 `@CCRoute` 平滑提升为 `@CCRouteContract`。契约可见性由 Package 依赖和 barrel export 决定，不再额外维护 `visibility`、`visibleTo` 或 `contractMode`。

Contracts Package 的 authored public barrel 一次性转发生成器维护的稳定入口，不直接绑定
`contract/*.route.contract.g.dart` 的物理文件名：

```dart
export 'src/ccrouter_generated/order_contracts.contracts.api.g.dart'
    show OrderDetailRoute;
```

该稳定入口只聚合公开 Route Consumer 的生成类型；`RouteArguments`、Definition 和 Codec 属于
generated Owner SPI，不从业务 barrel 导出。authored Service、Command、Event 和 InitTask
契约仍由 public barrel 使用独立 `export/show` 明确暴露。`show` 是 Package 的公开 API 边界，
生成器会验证每一层转发都保留完整符号。执行 `clean` 后，下一次 `generate` 会在 Builder 前临时
补齐缺失入口并在同一轮替换为正式内容，开发者不需要创建空文件。

## 页面展示与动画

`CCRoute.presentation` 是后端中立描述。当前支持：

- 平台默认 PageRoute
- Material / Cupertino
- fade / scale / 从底部滑入
- 透明全屏 Page
- Dialog Route
- Modal Bottom Sheet Route

普通页面可以使用从底部滑入与透明背景，例如海报分享页。Dialog/BottomSheet 只有在需要跨组件类型安全契约、Interceptor、Trace、Route Scope 或统一返回值时才应建模为 CCRouter Route；单页面局部提示继续用 Flutter API，避免把所有 Overlay 都升级成全局路由。

## Deep Link

内部动态地址与外部不可信输入必须分开：

```dart
// 内部
await CCRouter.navigator.open(Uri.parse('/orders/42'));

// Universal Link / App Link / custom scheme
await CCDeepLinkIngress.fromPlatform(uri);

// 通知
await CCDeepLinkIngress.fromNotification(uri);

// 二维码
await CCDeepLinkIngress.fromQrCode(uri);
```

外部 URI 必须同时通过：

1. Host 的 `CCDeepLinkIngressPolicy` allowlist。
2. 目标 Route 的 `CCDeepLinkPolicy.enabled`。

默认 Host policy 为 `denyAll`，默认 Route policy 为 disabled。`CCNavigationSource.deepLink` 只记录来源，不能把内部请求伪装成受信任外部入口。

外部入口默认使用 push，保留固定首页或主 Tab 的返回路径；Host 可显式选择 `CCDeepLinkOpenMode.go` 来重建 declarative Shell location。选择栈行为不会绕过安全策略。

平台模拟和手工验证入口见 [`demo/README.md`](demo/README.md)。

## Interceptor、Defer 与失败恢复

Interceptor 是**导航前决策**，适合：

- 登录与账号状态
- 权限或合规同意
- 维护模式、强制升级、Feature Flag
- 安全风控
- redirect 到登录/说明页
- defer 原请求，外部条件满足后恢复

全局 Interceptor 在 `CCRouterHost.initialize` 注入；路由级 Interceptor 通过组件
`@CCComponentContribution` 注册，并由注解中的稳定 ID 引用。它们可以返回
proceed、cancel、redirect 或 defer。

不要在 Interceptor 中调用 `CCRouter.navigator` 或 Adapter，也不要用它做 PV/UV、页面到达回调或业务数据加载。异步 Interceptor 必须有明确超时和取消语义。
Runtime shutdown 会取消正在等待的 Interceptor 和 Failure Policy，以 `CCRouteCancelledError`
结束导航；不会再执行失败恢复或接受晚到的 proceed/redirect/defer。Interceptor 应观察
`context.cancellation` 主动停止业务工作，框架无法强制终止 Dart Future。

`CCNavigationDefer` 会把原请求保存为 Pending Navigation。登录、授权或设备解锁成功后由 Host 调用 `resumePendingNavigation`；放弃流程时调用 `cancelPendingNavigation`。Failure Policy 仅处理稳定的解析、Codec、Adapter 等失败，默认传播错误；它不应吞掉编程错误或把未知地址静默送往错误页面。
恢复会重新校验并执行拦截链：Typed 请求保留 arguments/Extra 对象，动态 URI 重新匹配和解码；
保留原具体 Host、调用级 Outlet、操作和返回类型，切换 active Host 不会把待恢复页面送往新 Host。
重定向目标显式声明的 Host/Outlet 仍优先；待恢复数据只在进程内保留，应配置超时或主动取消。

## PopGuard

PopGuard 用于页面离开前可同步判断的规则，例如内存中的未保存编辑状态、不可中断步骤或受控流程。它必须同步且快速。需要弹确认框、网络请求或异步保存时使用 Flutter `PopScope` 管理 UI，再在确认后调用 `CCRouter.navigator.pop`。不要从 Guard 内再次发起导航。

系统返回、普通 Pop、Cupertino 手势和 Android predictive back 都进入统一协调；foreign Popup 或 `LocalHistoryEntry` 消费返回时不会关闭底层 Managed Route Scope。

系统返回或 `maybePop` 中，框架 Guard 返回 allow 只表示通过框架策略，页面自身的
`PopScope(canPop: false)` / `Form(canPop: false)` 仍可拒绝退出。页面和结果 Future 会保持
存活，本地拒绝回调可负责确认 UI。确认后主动调用 `pop` 仍是显式返回操作。Cupertino 页面
无 Guard 时保留平台默认侧滑，有 Guard 时继续禁用侧滑，不会因本地保护修复而放宽。

## Aspect、Trace、Telemetry 与生命周期

`CCNavigationAspect` 只观察导航阶段，不做决策。它适合 PV/UV 与来源归因、route found/arrival/completion/failure 观察、耗时、跨 Host/Outlet 链路追踪和脱敏日志。Aspect 回调异常会被隔离；回调中不得同步重入导航。请求参数、完整 URI、Extra、Token 和业务返回对象不会进入默认诊断记录。

Runtime 还可以把 Command、Event、Service、InitTask、导航失败和后端降级统一投递到 Host 注入的 `CCDiagnosticSink`：

```dart
final class AppDiagnosticSink implements CCDiagnosticSink {
  const AppDiagnosticSink(this.logger);

  final AppLogger logger;

  @override
  void record(CCDiagnosticEvent event) {
    logger.write(
      category: event.category.name,
      level: event.level.name,
      operation: event.operation,
      status: event.status,
      traceId: event.traceId,
      target: event.target,
    );
  }
}

CCRouterHost.initialize(
  hostAssembly: ccrouterGeneratedHostAssembly,
  diagnostics: CCDiagnosticsConfig(
    sink: AppDiagnosticSink(appLogger),
    policies: const [
      CCDiagnosticCategoryPolicy(
        category: CCDiagnosticCategory.navigation,
        minimumLevel: CCDiagnosticLevel.info,
      ),
      CCDiagnosticCategoryPolicy(
        category: CCDiagnosticCategory.event,
        sampleRate: .25,
      ),
    ],
  ),
);
```

Sink 是异步、有界、观察型边界：Sink 抛错、缓慢或关闭都不会改变业务结果；高负载下允许丢弃非关键诊断，但 Runtime 的有限 Trace 历史仍独立保留。类别策略只控制外部 Sink，不会关闭 Runtime 的错误与生命周期状态。应用可以把 `CCDiagnosticEvent` 映射到现有 Logger、Sentry、Crashlytics 或 OpenTelemetry，但必须继续遵守脱敏边界：不要自行追加完整 URI、参数、Extra、Token、Widget、Navigator、异常原文或业务返回对象。

组件装配和 Runtime 启动同样通过 `initialization` category 投递：`componentGraph`
记录清单校验与依赖拓扑结果，`componentRegistration` 按实际依赖顺序记录每个 Registrar，
`runtimeInitialize` 记录 Runtime 配置校验与 Adapter/Backend 启动。每个 operation 都会产生
`started` 以及 `succeeded` 或 `failed` 状态；失败只携带稳定 component ID、
`failureStage` 和 `errorType`，不携带异常原文。需要观察完整开始阶段时，将
`defaultMinimumLevel` 或对应 category policy 设为 `CCDiagnosticLevel.debug`。

需要排查一次跨组件调用时，可用 `CCRouter.traceBundle(traceId)` 按稳定 `traceId` 聚合有限的 `CCTraceRecord`。它可能因有界容量而不完整，不能作为业务审计、事件总线或请求回放数据源。

页面需要当前 Route 与 App 前后台回调时，可以选择 Mixin：

```dart
final class DetailState extends State<DetailPage>
    with CCPageLifecycleMixin<DetailPage> {
  @override
  void onPageShow() {}

  @override
  void onPageHide() {}

  @override
  void onForeground() {}

  @override
  void onBackground() {}
}
```

或组合式 Listener：

```dart
CCPageLifecycleListener(
  onPageShow: () {},
  onPageHide: () {},
  child: const DetailBody(),
)
```

`PageShow/PageHide` 表示 PageRoute 是否为其 active Outlet 的当前主 Route，不代表物理像素是否仍可见。Widget 创建与销毁仍使用 Flutter `initState/dispose`。资源所有权不要交给曝光回调；页面实例资源应使用 Route Service。

## Host、Shell 与 Outlet

`CCNavigationHost` 是框架对一个独立 Flutter navigation tree / Flutter View 的映射，不等同于平台 Window：

- 手机横竖屏、桌面窗口缩放：通常仍是同一个 Host，只更新 metrics。
- 折叠屏展开或折痕变化：通常仍是一个 Host，调整布局和 Outlet。
- 大屏左列表右详情：一个 Host，两个 Outlet。
- Bottom Tab、`ShellRoute`、`StatefulShellRoute`：一个 Host，多个 Shell/Outlet。
- Dialog、BottomSheet、Popup：属于当前 Host 的 Route 或 Overlay，不是新 Window。

真实 macOS/Windows/iPadOS 多窗口可以映射为多个 Host，但当前只提供
`CCGoRouterMultiHostBackend` 聚合、底层隔离和接入能力，不宣称已经完成所有平台多窗口
生命周期集成。

Shell 与 nested route 是 Host 拓扑，生成器不会猜测。Host 使用 `CCGoRouterRouteOverride`、`CCGoRouterShellBinding` 和 Outlet Observer 显式装配，业务页面仍只使用 `CCRouter.navigator`。

## Service

Service 表达可重复调用、可能持有状态或资源的长期能力。选择最窄 Scope：

| Scope | 创建与销毁 | 适合场景 |
| --- | --- | --- |
| `app` | 首次解析到 Runtime shutdown | 配置、网络门面、全局缓存 |
| `session` | 登录 Session 内首次解析到 logout/account switch | 用户资料、账号缓存、鉴权能力 |
| `route` | 某个 Managed RouteEntry 内首次解析到 Entry 永久移除 | 页面 Controller、草稿、页面订阅 |

零参数同步构造的简单 Service 使用注解，由生成器自动注册：

```dart
@CCService(
  id: 'order.repository',
  scope: CCServiceScope.session,
)
final class OrderRepository {
  OrderRepository();
}
```

跨组件 Service 在 Pure Dart contracts Package 声明接口和 Owner：

```dart
const orderComponentId = CCComponentId('order_component');

@CCServiceContract(
  componentId: orderComponentId,
  id: 'order.summary',
  version: '0.1.0',
  description: 'Formats one order identity for cross-component display.',
)
abstract interface class OrderSummaryService {
  String summaryFor(int orderId);
}
```

contracts barrel 只导出接口。实现类直接实现唯一 Contract，生成器会自动绑定稳定 ID：

```dart
@CCService()
final class OrderSummaryServiceImpl implements OrderSummaryService {
  const OrderSummaryServiceImpl();

  @override
  String summaryFor(int orderId) => 'Order #$orderId';
}
```

消费组件显式声明它实际调用的跨组件 Contract：

```dart
const paymentComponent = CCComponent(
  id: paymentComponentId,
  version: '1.0.0',
  dependencies: [orderComponentId],
  serviceDependencies: [
    CCServiceDependency<OrderSummaryService>(),
  ],
);
```

若遗漏 `orderComponentId`，可选 Analyzer Plugin 会在编辑期依据已生成 Package metadata
报告 `ccrouter_component_owner_dependency_missing`。只有当前公共 barrel 已导出准确 Owner 常量，
且 `dependencies` 缺失或是无 spread/条件元素的直接 List 时，IDE 才提供安全 Quick Fix；同一
组件的全部缺失 Owner 都可唯一证明时可一次补齐，否则只修当前 Owner。最终正确性仍由
Generator/Workspace Validator 校验。

重新生成后，通过组件专属 Client 调用；不要手写 Token、method ID、caller ID 或 Proxy：

```dart
final summary = DemoPaymentServices.orderSummary.summaryFor(orderId);
final loaded = await DemoPaymentServices.orderSummary.loadSummary(orderId);
```

生成 Proxy 不持有 Service，每次方法调用都解析当前 Scope。同步方法保持同步且不会启动 async
initializer；`Future<T>` 方法会等待 readiness。生成器支持普通实例方法、getter、同步/Future
返回值、方法级泛型和常用参数形态。泛型方法的类型参数、公共 Pure Dart bound、nullable
结果和显式类型实参会完整保留；Contract 类本身仍必须非泛型。setter/operator、Stream、
FutureOr、callback、Flutter 类型、Contract 继承和未从公共 barrel 暴露的 `src` 类型会在生成期
失败。生成器会避开业务参数和泛型名称，为内部回调和导入分配不冲突的名字；业务无需回避
`service` 等名称。组件内部 Service 仍直接使用 `CCRouter.service<T>()`，不需要声明或生成 Proxy。
Route 与 Service Proxy 的集合默认值保留实际 List/Set/Map 类型及泛型参数，包括 `Object`
参数下的空集合和嵌套集合；默认值涉及的枚举和类型也必须能被生成库公开导入。
描述中的 `$`、引号和换行按普通文本保留；生成的 Host DevTools Catalog 不会将描述当作 Dart 插值。
依赖预检按实际 Library、import/export 与 show/hide 查找 Owner；同 Package 的未导入声明
不参与判断。条件导入、part 或不完整的外部命名空间交由 Builder 最终校验，不猜测 Owner。
Analyzer 的注解诊断和 Quick Fix 核对声明所属框架 Library；业务同名注解不会因名称相同被
识别为 CCRouter 注解。解析不完整且无法证明导入来源时，保守等待后续解析或生成校验。

Route、Service、Command、Event、InitTask Contract 都有独立的 Contract SemVer。生成器会同时
写入不包含源码路径和实现类名的 `shapeFingerprint`，消费者 metadata 和 Host Bundle 会携带
精确的版本范围与指纹。Workspace、Host 组装和 Runtime 会使用稳定的兼容错误码拒绝缺失
Contract、Owner 不匹配、版本范围不满足、指纹漂移、重复实现和陈旧生成物；不会在运行时
下载、协商或静默降级旧 Contract。当前 `0.x` 阶段仍不承诺跨版本自动兼容；修改公共形状时
应显式升级版本，破坏性变更使用新的 Contract ID。

生成的 Host Assembly 暴露只读 `contractBundle`。标准启动代码将它和组件 Manifest 一起交给
`CCRouterHost.initialize`，因此业务不需要手写版本字符串：

```dart
CCRouterHost.initialize(
  hostAssembly: ccrouterGeneratedHostAssembly,
);
```

生成器会先校验 Service Owner、Consumer 和 Package exposure；Runtime 还会根据本次实际安装的
Manifest 依赖图再次验证生成 Proxy 携带的 caller identity。旧生成物、手工调用 generated bridge、
缺失组件或未声明 required dependency 会抛出 `CCResolutionError`，不会以伪造归属进入 Trace。

需要构造参数、依赖注入、自定义 Factory 或 async initializer 时，使用
`@CCComponentContribution` 显式注册，不把复杂生命周期隐藏在注解里：

```dart
@CCComponentContribution(id: 'order.services')
void registerOrderServices(CCRegistry registry) {
  registry.registerService<OrderRepository>(
    CCServiceProvider(
      scope: CCServiceScope.session,
      factory: (_) => OrderRepositoryImpl(database),
      initializer: (service, context) => service.open(context.cancellation),
    ),
  );
}
```

复杂的跨组件 Provider 仍需稳定 Contract ID。此时只在实现组件专用的 owner barrel 中
导出生成 Token，并在 `CCServiceProvider(contractToken: ...)` 中使用；业务 contracts barrel 和
消费方不得导出、传递或构造 Token。简单 `@CCService` 不需要这一步。

解析：

```dart
final repository = CCRouter.service<OrderRepository>();
final optional = CCRouter.serviceOrNull<OptionalCapability>();
final readyService = await CCRouter.serviceAsync<RemoteConfigService>();
final controller = CCRouter.routeService<OrderDraftController>(context);
```

- 默认 `singleton` 是每个 Scope 一个懒实例。
- `newInstance` 每次解析创建新实例，但需要销毁的实例仍由 Scope 统一拥有；不要用它模拟手工 dispose 的临时对象。
- `initializer` 只用于实例无法在同步构造后立即工作的异步 readiness；调用方必须使用 `serviceAsync`。
- 同一 Singleton 的并发调用共享初始化；跨独立调用根的 A→B→A 等等待环也会报
  `CCCircularServiceDependencyError`。调用者超时/取消会撤销自己的等待关系，不破坏共享初始化；
  初始化本身失败在当前 Scope 内保持失败，不隐式重试。
- 多实现使用 `CCServiceKey<T>`；跨组件调用使用生成 Client。统一名称配置在
  `CCServiceContract.alias`，单个消费者或 Key 的覆盖配置在 `CCServiceDependency.alias`；组件内部
  解析仍使用 `CCRouter.service<T>()`。
- 实现 `CCDisposable` 的实例由 Scope 按逆构造顺序自动销毁，业务不得自行 dispose。
- `serviceOrNull` 只把“未注册”转换为 null，不吞掉创建策略、Scope 或初始化错误。

Session 由认证流程显式管理：

```dart
CCRouter.openSession(accountId: account.id);
await CCRouter.closeSession();
```

App 后台、页面切换和普通 Pop 都不会关闭 Session。退出登录、Token 失效、账号切换或强制下线才关闭。

## Command

Command 表达“由唯一 Owner 执行的一次性动作”，可返回强类型结果，也可使用 `void`。组件内 Contract 可省略 Owner，由 Package 的唯一 `CCComponent` 推导：

```dart
@CCCommandContract(
  id: 'order.submit',
  alias: 'submit',
  description: '提交订单并返回支付单号。',
)
final class SubmitOrderCommand implements CCCommand<String> {
  const SubmitOrderCommand(this.orderId);
  final int orderId;
}

@CCCommandHandler()
Future<String> handleSubmitOrder(
  SubmitOrderCommand command,
  CCInvocationContext context,
) async {
  if (context.cancellation.isCancelled) {
    throw const CCInvocationCancelledError();
  }
  return 'receipt:${command.orderId}';
}

final receipt = await OrderCommands.submitOrder(
  const SubmitOrderCommand(42),
  timeout: const Duration(seconds: 10),
);
```

跨组件 Command 在 contracts Package 中显式填写 `componentId`，消费组件把 Owner 放入 `dependencies`，并在 `commandDependencies` 中只声明实际调用的 Contract。生成器会产生消费组件专属 Client，业务不传 `commandId` 或 caller identity。复杂、迁移期或未注解的内部 Command 仍可通过 `CCComponentContribution` 手写注册并使用 `CCRouter.command`；已注解 Command 应统一走生成 Client。

Runtime 会再次确认生成 Client 的 caller 已安装、Command ID 与已注册 Handler 一致，并且 caller
对 Handler Owner 声明了 required dependency；校验失败会在 Handler 执行前抛出
`CCResolutionError`，且不会记录伪造的组件调用归属。

适合创建订单、提交支付、刷新远端数据等一对一操作。状态读取或多次方法调用使用 Service；“已经发生”的广播使用 Event。取消是协作式的，框架可以结束等待并发出 cancellation，但不能强制停止同步 Dart 代码或回滚已发生的副作用。

## Event

Event 表达已经发生的事实，Publisher 不依赖订阅者结果。组件内 Event 可以省略
`componentId`，由 Package 的唯一 `CCComponent` 推导 Owner：

```dart
@CCEventContract(
  id: 'order.paid',
  description: '订单支付已经完成。',
)
final class OrderPaidEvent implements CCEvent {
  const OrderPaidEvent(this.orderId);
  final String orderId;
}

@CCEventSubscription(id: 'analytics.order-paid')
Future<void> trackOrderPaid(
  OrderPaidEvent event,
  CCInvocationContext context,
) => analytics.track(event.orderId);

await OrderEvents.publishOrderPaid(
  const OrderPaidEvent('42'),
  timeout: const Duration(seconds: 3),
);
```

同一 Event 可以没有 Subscriber 或有多个 Subscriber。订阅按稳定 ID 确定启动顺序，单个 Subscriber 失败不会阻止其他 Subscriber；调用 Future 在本次分发完成后结束。同一组件只有一个对应 Subscriber 时可省略 `CCEventSubscription.id`，生成器使用 `<subscriberComponentId>.<eventId>`；存在多个时必须全部显式设置。跨组件 Contract 显式填写 `componentId`，订阅组件把 Owner 放入 required 或 optional dependencies。生成器只为 Owner 生成 Publication Client，不增加 `eventDependencies` 或任意发布权。

Runtime 会确认生成 Publication Client 声明的 Publisher 已安装，并逐一复核 Subscriber 对
Publisher Owner 的 required/optional dependency。缺失 Publisher、Event ID 不一致或 Subscriber
依赖缺失会在分发前以 `CCResolutionError` 失败；无 Subscriber 的合法 Event 仍是成功 no-op。

`CCEventSubscriberId<E>`、`CCEventSubscriber<E>` 和旧的 `registerEvent` 仅用于未注解迁移能力、底层注册和测试。已注解 Event 必须使用生成 Owner Client，不能调用裸 `CCRouter.event` 绕过稳定 Event ID 与 publisher identity。Subscriber 在 Runtime 生命周期内静态注册，不提供页面级动态 subscribe/unsubscribe、Sticky、历史重放或持久化；页面内状态同步继续使用状态管理或 Route Service。

## InitTask

InitTask 是 Runtime 生命周期内只执行一次的启动任务 DAG，适合 SDK 初始化、基础配置加载和具有明确依赖关系的启动工作：

```dart
const foundationInitTask = CCInitTaskContract(
  id: 'foundation.initialize',
  description: '准备 Analytics 依赖的基础设施。',
);

@CCInitTask(
  contract: foundationInitTask,
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.required,
  timeout: Duration(seconds: 3),
)
Future<void> initializeFoundation() async {}

@CCInitTask(
  id: 'analytics.initialize',
  dependsOn: [foundationInitTask],
  gate: CCInitTaskGate.privacyGranted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
  timeout: Duration(seconds: 3),
)
Future<void> initializeAnalytics(CCInvocationContext context) =>
    analytics.initialize(context.cancellation);
```

生成器自动把 Handler 注册到所属组件，并在 Workspace 阶段校验 Owner、Contract exposure、
缺失/重复依赖和完整 DAG。被其它任务依赖的任务必须声明 `CCInitTaskContract`；跨组件 Contract
放在公共 contracts Package，消费组件必须 required-depend on Owner。独立内部任务可以只填写
`id`，`contract` 与 `id` 不能同时设置。

Host 在 `CCRouterHost.initialize` 后调用 `CCRouterHost.runInitTasks(gate: ...)`。调用方必须显式选择 Gate；普通启动使用 `CCInitTaskGate.appStarted`，它不是 API 默认值。Runtime 仍保留重复 ID、缺失依赖、循环依赖以及 required 依赖 optional 的最终校验。并发打开 Gate 共享 single-flight drain；执行期间新打开 Gate 时，Runtime 会继续运行新就绪的 DAG 层直至稳定，不会遗留永久 `pending` 的任务。

`runInitTasks(gate: ...)` 返回 `CCInitTaskRunResult`。required 与 optional 业务失败都进入 Result、Snapshot、Trace 和 Diagnostics，仅依赖失败节点的分支会 `skipped`，无关分支和后续 Gate 仍可继续。默认不把业务失败作为未捕获异常抛给启动流程，因此现有“先 `await` InitTask、再 `runApp`”的顺序仍然支持；确实无法降级的 Host 可显式调用 `result.throwIfRequiredFailed()`。Runtime shutdown、取消和非法状态等框架错误仍直接抛出。`@CCInitTask` 同样要求显式 `gate`；CLI Scaffold 会生成 `gate: CCInitTaskGate.appStarted`，开发者可按真实条件修改。单个 Service 的异步准备应放在 `CCServiceProvider.initializer`，不要创建 InitTask 预热所有 Service。

## 生成器

常用命令：

```bash
# 创建组件 Package（第二个参数是父目录，默认当前目录）
fvm dart run --verbosity=error ccrouter_generator:ccrouter create component demo_inventory demo/modules

# 可选：同时用 Flutter 官方 app template 创建独立 example Host
fvm dart run --verbosity=error ccrouter_generator:ccrouter create component demo_inventory demo/modules --with-example

# 在已有组件中创建内部页面（第二个参数是组件根目录，默认当前目录）
fvm dart run --verbosity=error ccrouter_generator:ccrouter create page InventoryPage demo/modules/demo_inventory

# 在已有组件中创建能力模板（默认是组件内部能力）
fvm dart run --verbosity=error ccrouter_generator:ccrouter create service OrderSummary demo/modules/demo_order
fvm dart run --verbosity=error ccrouter_generator:ccrouter create command ReserveOrder demo/modules/demo_order
fvm dart run --verbosity=error ccrouter_generator:ccrouter create event OrderPaid demo/modules/demo_order
fvm dart run --verbosity=error ccrouter_generator:ccrouter create event OrderPaid demo/modules/demo_order --with-subscriber
fvm dart run --verbosity=error ccrouter_generator:ccrouter create init-task WarmCache demo/modules/demo_order
fvm dart run --verbosity=error ccrouter_generator:ccrouter create init-task WarmCache demo/modules/demo_order --with-contract

# 生成/增量更新
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo

# CI 只读一致性门禁；发现变化后恢复现场并返回非零
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --check

# 禁用 metadata 缓存，验证参考全量路径
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache

# 耗时过长时再输出阶段耗时、Builder 目标、缓存命中率和 dirty 传播原因
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --profile

# 本地/AI 开发：常驻 build_runner watch；stdout 为 NDJSON 事件
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --watch=auto --machine

# 人工确认 Hook/后台 watch 状态，或持续查看简洁状态变化
fvm dart run --verbosity=error ccrouter_generator:ccrouter watch status demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter watch follow demo

# Runtime/Service/Analytics/生成器性能与资源回收基准
fvm dart run packages/ccrouter_test/benchmark/performance_regression.dart
fvm dart run packages/ccrouter_test/benchmark/performance_regression.dart --full

# 按能力 ID 查找 Route/Service/Command/Event/InitTask，Route 也支持 Pattern
fvm dart run --verbosity=error ccrouter_generator:ccrouter find order.detail demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter find '/orders/:orderId' demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter find demo.startup.foundation demo

# 为已有消费组件输出只读接入建议
fvm dart run --verbosity=error ccrouter_generator:ccrouter find demo_order.summary demo --usage demo_payment_component

# 只清理 CCRouter 标记的生成源码
fvm dart run --verbosity=error ccrouter_generator:ccrouter clean demo

# 可选：给当前 Flutter SDK 安装可回滚的 Flutter/Dart Pub 成功后生成 hook
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook install
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook status
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook uninstall
```

这里的 `--verbosity=error` 是 `dart run` 的启动参数，只隐藏 Dart/Pub 冷启动时重复的依赖解析与
executable 构建信息；CCRouter 自己的阶段、耗时、跳过原因和错误仍会输出。

生成命令会把调用者选中的最近 Package 记为 `requestedRoot`，把实际拥有 Pub
`.dart_tool`、build_runner cache 和 generation lock 的 Package/Workspace 记为
`resolutionRoot`。声明 `resolution: workspace` 的成员优先使用 Pub 写入的
`.dart_tool/pub/workspace_ref.json` 并验证 Workspace membership；普通嵌套 Package 不会因为
物理目录位于 Workspace 下而被误判为成员。reference 缺失时才向上验证 Workspace，reference
损坏或过期则 fail-closed 并要求重新执行 Pub get。

`generate` 随后按 requested Package 的显式角色执行：直接依赖 `ccrouter` 的 Flutter
`project_type: app` 默认是 Host；`ccrouter.yaml` 的 `host.enabled` 可显式覆盖；其它直接依赖
`ccrouter` 或 `ccrouter_contracts` 的 Flutter/Pure Dart Package 走 package-local。Host 拥有其
可写 dependency closure 的 Package 生成、跨 Package 校验、Host assembly 和 Host catalog；
package-local 只运行并发布 requested Package 的 Builder、API、Bundle、Package index 与本地
catalog，不生成 Host facade，也不会用某个 Host 的完整性规则拒绝独立 Contracts Package。
没有直接参与 CCRouter 的 Workspace aggregator 会明确 skip。package-local 暂不接受 Host 专属
`--output-dir` 和 watch；最终 `--no-cache --check` 应在实际 Host 上执行。

### 生成入口一致性

手动 `generate`、Host watch 和 Pub Hook 共享同一个 generation kernel，但“结果一致”不表示
“执行过程或耗时相同”。在 requested root、resolution root 和输入 epoch 相同时，Host 路径使用
相同的 Builder 输出、Workspace Validator、聚合、输入屏障、快照恢复和原子写入语义：无活动
watch 的 Pub Hook 直接启动默认 `generate <requested-root>`；活动 watch 已覆盖当前请求时，Hook
等待与当前 Pub resolution 精确匹配的 `aggregationSucceeded`，不并发启动第二个 one-shot。
package-local Hook 也只有在 stable Builder session 发布的 requested Package Pub resolution、
authored input 和 managed output 指纹全部匹配时才复用，否则 fail closed。
`flutter build` preflight 走普通 `generate`，因此 active watch 存在时也会验证并复用同一份
精确证据，而不是因为 generation lock 被长期持有就拒绝 Android、iOS 或 `flutter build hap`；
成功摘要会保留 `reused active watch cycle` 以便确认该路径。

DevEco Studio/Hvigor 直接构建不会经过 Flutter wrapper。OHOS Host 应像 `demo/ohos` 一样把
`CCRouterPreflight` 注册为 Flutter Hvigor `FlutterTask` 的前置 task，并通过
`ohos/local.properties` 所解析 Flutter SDK 的 Dart 执行同一个
`pub-hook run --project-root <host> --pub-command build`。没有 watch 时它正常 one-shot 生成；
有 watch 时普通生成会等待并复用精确 cycle，只有真实生成/校验失败才阻止 Hvigor 编译。
不要在这个 task 中使用 `--no-cache`，该参考路径在 active watch 下仍按设计 fail-fast。

各入口的性能不能直接互换：watch 复用常驻 build_runner AOT entrypoint 和 Analyzer graph，并增加
in-process cycle/evidence reuse；普通 one-shot 可命中 fast path；`--no-cache --check` 则强制权威
参考路径。package-local 只拥有 requested Package 生成物，不执行 Host assembly 和跨 Package
完整性校验。Analyzer Plugin 更不是另一条生成路径，它只提供保守、fail-open 的编辑期诊断并消费
已验证的 Generator snapshot；最终正确性始终以实际 Host 的 `--no-cache --check` 为准。Generator
图算法、planning snapshot 和 Analyzer alias graph 默认启用；Analyzer tiered polling 仍仅通过
`CCROUTER_ENABLE_ANALYZER_TIERED_POLL=1` 供 maintainer A/B，修改 Analyzer 环境开关后必须重启
Analysis Server。完整入口矩阵和 A/B 结果见
[`docs/CCRouter-generator-performance-report.md`](docs/CCRouter-generator-performance-report.md)。

同一 Workspace 中未被本次 package-local 命令授予写权限的 sibling Package 只作为现有
Package index 输入，不会被写入或清理，也不会仅因本次只读而被误判成外部分发依赖。Hosted、
Git 或 Workspace 外 Path dependency 仍须提供可验证的预生成 index/Portable State。metadata
parse cache、Build Plan 和 aggregation state 继续只保存在 `resolutionRoot/.dart_tool`；一次
package-local 成功会合并自己的 cache entry，不会驱逐其它 Host/Package 的本地 entries。

`create component` 创建新的 Flutter library Package、`project_type: package` metadata、`lib/src` 下的
顶层 `CCComponent` Descriptor 和 Package barrel。`--with-example` 还会通过当前 Flutter SDK 的
官方 app template 创建 `example/`，显式依赖组件、`ccrouter` 与 `ccrouter_generator`；其
`project_type: app` 因而默认按独立 Host 生成与校验。Workspace 场景会提示同时登记组件和
example，非 Workspace 场景使用 `path: ..` 连接组件。
`create page` 只创建带 `@CCRoute` 的最小 Flutter Page；`create service`、`create command`、
`create event` 和 `create init-task` 分别创建真实注解的 Service/Command/Event/InitTask 起始模板。
内部 Service 默认是带稳定 ID 的 concrete `@CCService`，不会提前创建跨组件 Contract。Event
默认只声明已发生事实，只有 `--with-subscriber` 才增加同组件 Subscriber；独立内部 InitTask
默认直接使用 `id`，只有 `--with-contract` 才生成可被其它任务引用的 typed Contract。
这些能力模板默认属于当前组件，不会自动提升为跨组件 Contract，也不会修改 Host 依赖。
所有命令都会先检查全部目标文件，目标已存在或名称非法时返回非零并拒绝覆盖，不修改已有 Host
的 `pubspec.yaml`，也不写入生成目录。Component 与可选 example 会先在父目录的临时目录中
完整创建；Flutter template 或 manifest 配置失败时删除临时目录，只有全部成功后才通过同文件系统
rename 发布最终 Package，避免留下半成品。
创建成功后 CLI 会按模板类型输出确定性的 `Next steps`；它只提示需要补齐的源码、Workspace/
Host 依赖和生成命令，不会猜测 Host 或自动修改依赖。
Component 模板会优先继承目标目录最近 Package/Workspace 中明确声明的 `ccrouter`、
`ccrouter_generator` 依赖来源和 Dart SDK 约束，支持 Hosted、Git 和重算后的 Path 依赖；缺少
显式声明时才从 resolved Package identity 生成版本约束。无法证明任一框架依赖来源时，命令会
在写文件前失败，不回退到硬编码版本。
脚手架完成后仍需执行一次 `flutter pub get` 和 `ccrouter generate`，让 build_runner 生成 Registrar、
Route API 和 Package/Host metadata。跨组件 Route 不能直接由脚手架猜测，真实消费者出现后再
手动建立 contracts Package 和 Contract-first 声明。

普通 `generate` 会在持有生成锁后校验版本化 manifest。只有 authored Dart 源码、Pub graph、
生成器与 Dart SDK identity、外部 Package Index 及全部 CCRouter 受管输出的内容摘要完全一致时，
才跳过 build_runner 和聚合；任一缺失、损坏或变化都会自动回退完整生成。该路径不依赖 mtime
或文件大小。普通生成只额外输出最终总耗时；`--no-cache` 始终绕过 fast path，是生成正确性的
权威参考路径。需要诊断慢生成时再传 `--profile`，它会明确
报告 `fast-path=hit/miss`。miss 时还会输出 `build-targets` 和逐 Package 的
`dirty-packages` 原因；`dirty` 是 build_runner 完成后的聚合复用判断，不表示 Builder 只分析
这些 Package。

性能诊断还会输出 schema `1` 的 `CCRouter profile trace=<json>`，按单调时钟细分锁等待、
Workspace/指纹/Build Plan、preflight、快照、build_runner 子进程、Validator、聚合写入、
`--check` 恢复和 planning state 提交。最新 JSON 会原子写入
`.dart_tool/ccrouter/v1/profiles/<host-identity>/latest.json`；只包含阶段名、微秒耗时、状态和
有界计数，不包含绝对路径、源码或业务值，也不参与缓存和生成判断。Profile 模式会为
build_runner 启用官方 `--verbose-durations`，其 Builder phase 明细用于继续区分 Analyzer、
resolve、build、read/write 成本，但不属于 CCRouter trace schema。不带 `--profile` 不产生报告。
`aggregation-input-fingerprint` span 额外携带一个 SHA-256 `attributes.fingerprint`，覆盖 Builder
metadata、Package Index identity 与 Host graph 等聚合输入。它永远不能授权跳过 Builder；Builder
成功后，若该 identity、Tool identity 与入口 artifact snapshot 中全部 aggregation-owned bytes
同时匹配上次成功的本地证明，则可跳过重复的 aggregation rendering/writes。命中前仍执行只读
依赖校验、Package graph/index 构造、Workspace Validator 和前后 input barrier。状态缺失、损坏、
输出篡改、metadata cache 损坏或任一 identity 变化都会 fail closed；损坏 cache 会由该轮完整
路径重建。`CCROUTER_DISABLE_AGGREGATION_REUSE=1` 可恢复完整 aggregation 做 A/B，
`--no-cache --check` 始终强制权威参考路径。

`--watch=auto` 为一个 Host 解析单一 build root，并保持一套 `build_runner watch --workspace`
进程、AOT entrypoint 和 Analyzer graph。同一 resolved build root 下启动的不同 Host 会注册到
同一个 Builder owner；owner 以所有活动 Host dependency closure 的 target union 启动或扩容
build_runner，各 Host 仍分别执行聚合、Validator、原子发布，并维护自己的 lease、
`status.json`、diagnostics 与 `inputRevision`。状态中的 `pid` 是该 Host watch 进程，
`builderOwnerPid` 是共享 Builder owner，subscriber 场景下两者可以不同。owner 退出后，仍活动的
subscriber 会接管并重新到达 `ready`；同一 Host 的第二个 watch 会在写共享状态前快速失败。
这里的“第二个 watch”指手工或独立 CLI watch writer。Hook 管理的同一 Host 多个
`flutter run` 不会创建多个 writer：每个 run 持有独立 heartbeat lease，并通过当前 watch PID
绑定的 acknowledgement 接入同一个 Host watch；任一 run 退出只释放自己的 lease，最后一个
有效 lease 消失后 watch 才停止。并发启动时 registration 竞选失败的候选不会覆盖 active
`status.json`，而会等待接入或在旧 watch 正退出时重新竞选。
Flutter 子进程运行期间，supervisor 处理中断时先移除当前 run 的 lease，再将信号转发给
子进程；初始化 lease 的写入尚未完成时关闭它，也不会留下 heartbeat 定时器。
Watch 在新 child session 尚未到达 `ready` 时也可停止，不会因尚未读取内部信号队列而阻塞
清理和 generation lock 释放。
`CCROUTER_DISABLE_MULTI_HOST_WATCH=1` 可恢复一个 build root 只允许一个 watch 的旧语义做 A/B。
watch ownership、generation、aggregation、Host registration、Flutter-run lease、Analyzer CLI
写事务及最小 Host/Builder session authority 位于用户级
`CCROUTER_HOME`；macOS/Linux 默认是 `~/.ccrouter`，Windows 默认是
`%LOCALAPPDATA%\CCRouter`。每个 canonical build root 使用完整 SHA-256 项目目录，同一项目内再按
canonical Host SHA-256 隔离 registration，因此不同项目完全隔离、同一 build root 的多个 Host
共享 Builder 与 Analyzer operation lock，但不共享 Host 状态。锁文件只 unlock/close，不在
停止时删除，避免 unlink 后创建新 inode 导致双 owner。`.dart_tool` 继续保存 build_runner
graph、planning/cache、profile，并将
status/diagnostics 作为面向 IDE/Analyzer 的本地镜像；活动 watch 每秒检查并重建被删除的镜像。
Pub Hook 优先读取 stable session，因此 Host 本地 watch 状态被清理时不会误启 one-shot、卡满超时
或丢失 package-local 冲突诊断。`watch status` 也可在本地镜像缺失时读取 stable session，并显示
实际 coordination schema 和路径。
`CCROUTER_HOME` 不可写或不是目录时，CLI 会报告无法写入的目标路径并提示改到绝对可写目录，
不会输出内部 Dart 堆栈。
若启动时检测到仍持有 V1 `.dart_tool` owner lock 的旧 CLI/watch，新版会 fail-fast，要求停止旧进程
并重新安装 Pub Hook；不会尝试让两种协议静默并发。短期可设置
`CCROUTER_USE_LEGACY_DART_TOOL_LOCKS=1` 做 A/B；它也会把 Flutter-run lease 恢复到 Host
`.dart_tool`，并把 Analyzer operation lock/journal 恢复到 Pub owner `.dart_tool`，但不承诺
新旧进程互操作。
已安装的 Flutter wrapper 还会在真正的 top-level `flutter clean` 前检查该 build root：活动 watch
存在时直接阻止 clean，要求先停止 `flutter run/watch`，不会擅自终止开发会话。Help、未知全局
参数和业务参数中的 `clean` 不触发检查。`CCROUTER_DISABLE_FLUTTER_CLEAN_GUARD=1` 可单次绕过
做恢复或 A/B；`CCROUTER_PUB_HOOK_DISABLE=1` 仍可绕过整个 wrapper。两种 bypass 都不保证活动
watch 能跨越被删除的 Pub/build_runner 状态继续工作。
若 clean 通过未安装 wrapper、kill switch 或直接删除目录绕过 guard，watch 会对 build root 的
`package_config.json`、`package_graph.json` 和已建立的 build_runner Asset Graph 做 500ms
二次确认。持续缺失会发布 `invalidatedByClean`，有界停止 build_runner、保留最后完整生成物并
释放 stable locks；不会无限等待 `pub get` 或尝试在失效 Analyzer graph 上继续。重新执行 Pub get
后启动新的 watch。仅清理 Workspace member Host 自己的 `.dart_tool`、而共享 build root 状态仍
完整时，不会误判为 clean invalidation。
watch 在 lease 内持有 generation lock；每个成功 Builder
轮次后先执行 exact-content 一致性检查，未命中 fast path 时继续执行只读依赖校验、preflight、
输入屏障、快照恢复、Validator、聚合、原子写入和本地 planning state 提交。失败轮次不会发布
半成品。`--machine` 令 stdout 仅输出 schema `1` NDJSON 事件，适合
AI Agent 等待 `ready`、`aggregationSucceeded`、`failed` 和 `stopped`，build_runner 详情写入
stderr。默认事件保留 Builder 与聚合最终耗时；性能测试或慢任务诊断显式追加 `--profile` 后，
build_runner 才启用 `--verbose-durations`，且 `aggregationSucceeded.profile` 才包含完整 cycle
trace。默认 `build` 是 CCRouter 观测的端到端耗时，精细的 `build_runner` 上游耗时仅在 Profile
模式可用。`buildSucceeded.buildRunner` 使用结构化 `formatVersion: 2`：默认明确发布
`available: false, reason: profile-disabled`，不会把未采集的 Builder counters 伪装成零；仍保留
外层 CCRouter 实测耗时。`--profile` 下发布 `available: true`，并携带 Builder 报告的总耗时、
写入数以及每个 Builder phase
的 `durationMs`、`inputs`、`skipped`、`invalidatedInputs`、`executedInputs`、`outputs`、
`sameOutputs`、`noOp` 和达到 build_runner 报告阈值的 activity 耗时。它只解析上游正式
console 格式，不读取 private Asset Graph；无法识别的终态保留在有界 `unparsedFinalLines`，
不会改变生成结果。`CCROUTER_LEGACY_UNPROFILED_BUILD_RUNNER_REPORT=1` 可恢复旧的默认空 counters
做 A/B；`CCROUTER_DISABLE_BUILD_WATCH=1` 会执行一次 one-shot 后退出。watch 是开发加速路径，
CI 仍以 `generate <host> --no-cache --check` 为权威。一个活动 watch 会在 lease 生命周期内
持有该 root 的 generation lock；同 root 的普通 `generate` 与 `generate --check` 不会启动第二个
writer，而是等待并复用 active watch 对当前 Pub resolution、authored input 和 managed output 的
精确完成证据。watch 失败、退出、证据不匹配或五分钟超时仍 fail-closed。`--no-cache`、`--profile`、
自定义 `--output-dir`、portable prepare 与 `clean` 仍快速失败；设置
`CCROUTER_DISABLE_ONE_SHOT_WATCH_REUSE=1` 可恢复普通 one-shot 的旧 fail-fast 路径做 A/B。
反过来已有 one-shot 正在执行或排队时，新 watch 也会快速失败。先停止 watch 再执行最终
`--no-cache --check` 门禁。共享仅发生在同一个 resolved build root；嵌套且
拥有独立 Pub build root 的 Package Host 仍各自启动 watch，不做跨 root 合并。subscriber
离开时当前 child 可保留已加载的 target superset，避免无意义 restart；真实 Pub resolution
删除仍按精确 topology 重新启动 session。
watch 还监视 Host manifest 与 Pub resolution 的精确内容变化；普通版本/依赖边变化在当前
Builder target 集合仍可覆盖时发布 `resolutionStarted` 并直接执行完整聚合校验。Host closure
新增 Package、Builder target/`--build-filter` 集合变化，或 build_runner 因 resolution 更新自行
退出时，supervisor 会在同一 generation lock 和 lease 内发布 `sessionRestarting`、等待旧 child
完整退出并启动新 session。停止过程先给 build_runner 10 秒处理 SIGINT，再给 SIGTERM 5 秒；
仍未退出则发送 SIGKILL，并只再等待 5 秒，因此异常 child 不会无限持有 generation lock。
Pub Hook 只有在新 session 到达 `ready` 后才接受其
`aggregationSucceeded`。`CCROUTER_DISABLE_WATCH_SESSION_RESTART=1` 会让需要 restart 的变化
fail closed，并要求停止 watch 后运行 one-shot，供紧急回退和 A/B 使用。
后台 watch 会原子维护本地观察镜像
`.dart_tool/ccrouter/v1/watch/status.json`。`watch status <host>` 一次性显示活动状态、PID、
轮次和最近 Builder/聚合耗时；`watch follow <host>` 只打印简洁状态变化，完整 build_runner
输出继续保留在 `.dart_tool/ccrouter/v1/watch/flutter-run.log`，不会注入 Flutter Tool 的
`--machine` stdout。状态发布属于 fail-open 可观察性：写入失败只警告并停止更新状态文件，
不会改变 direct watch 的生成锁、Builder、Validator、原子发布或最终参考门禁；但 Hook 无法
取得 lease-bound readiness proof 时会拒绝启动 Flutter。若 watch 被强制终止而来不及
写入 `stopped`，只读命令会根据已释放的 owner lock 将遗留 `active` 记录显示为 `stale`，
但不会改写历史 `status.json`。
Pub Hook 启动 `flutter run` 时不会把后台进程已经 fork 当成 watch 可用：POSIX 与 Windows
wrapper 都把 stable lease heartbeat、readiness handshake、原 Flutter Tool 和退出清理交给
同一个 Dart supervisor，并由 detached coordinator 独立持有重定向后的 watch 输出。supervisor
先等待自己的 lease 成为新 watch 的主 lease，或收到当前 active watch 基于其 PID 的精确接入
acknowledgement，再确认 `sessionReady` 与 build root owner lock，随后才启动原 Flutter Tool。
同一 Host 的并行 run 因此共享一份 watch，生命周期延续到最后一个 run lease 释放。
Dart/AOT 入口 30 秒内未发布匹配状态、初始 Builder/aggregation 5 分钟内未到达 `ready`、
watch-lock 冲突、进程退出或结构化失败都会阻止 `flutter run`，并保留状态与日志路径。可用
`CCROUTER_DISABLE_WATCH_STARTUP_HANDSHAKE=1` 单独恢复旧的立即启动行为做 A/B；它不关闭
preflight、watch、generation lock 或 reload gate。
Hook 启动的 `flutter run --machine` 还会通过一个仅处理 stdin 的 reload gate 协调 IDE/AI
Hot Reload：watch 为 authored Dart/config 保存发布单调 `inputRevision`，成功 cycle 发布
`completedInputRevision`；只有状态稳定且相应 revision 已到达 `aggregationSucceeded` 后，
`app.restart` 才转发给原 Flutter Tool。生成失败会按 Flutter daemon 标准 error 返回并携带有界
诊断，不会让第一次 reload 消费旧生成物。Host topology 变化会发布
`hotRestartRequired: true`，普通 Hot Reload 被拒绝，须显式 Hot Restart；只有 daemon 确认
restart 成功后，当前 run session 才继续接受 reload。该 gate 不改写或缓冲 Flutter stdout，
仅透传解析与 Hot Restart 匹配的 daemon response；IDE/AI 关闭 machine stdin 时，gate 会同步
关闭原 Flutter Tool 的 stdin，使其按直接启动时相同的 EOF 生命周期退出。gate 不代理
普通交互式终端 `r`；后者仍应先通过 `watch follow` 确认成功。设置
`CCROUTER_DISABLE_HOT_RELOAD_GATE=1` 可只关闭 machine reload 协调，保留 preflight 和 watch。
交互式 `flutter run` 启动时会明确打印这一限制；该提示表示 watch 正常运行，但不应把普通
终端 `r/R` 误认为已经受 generation gate 保护。
Workspace Validator 失败时，watch 还会独立原子发布
`.dart_tool/ccrouter/v1/watch/diagnostics.json`。该文件只包含最多 100 条版本化结构诊断，并绑定
Host/build root、session、cycle、`eventRevision` 与 Pub resolution fingerprint；成功、新 cycle
或 session restart 会清空旧诊断。Analyzer Plugin 只消费与当前 `status.json` 完全匹配且
resolution 未在 cycle 中变化的失败证据，把同一缺失 Owner 引起的 Route/Service/Command/Event/
InitTask 级联折叠到 authored Dart 主位置。没有活动 watch 时，普通 Host generation 还会发布
`.dart_tool/ccrouter/v1/generation/diagnostics.json` 终态；Plugin 仅在其 Host/build root 和当前 Pub
resolution 逐字节 fingerprint 仍一致时消费，成功终态或任一输入变化都会清除旧错误。活动 watch
始终优先，不能回退并复活旧 one-shot 错误。`pubspec.yaml` 与 resolved Package graph 暂时不一致时，
IDE 使用当前未保存 overlay，并根据 `.metadata`、`ccrouter.yaml` 与直接依赖识别 Host/package-local，
提示相应的 Flutter 或 Dart Pub get，不猜测 Owner；恢复 overlay 后提示立即撤销，不要求保存、watch
active 或重启 Analysis Server。无效 YAML、非布尔 `host.enabled` 或缺少直接 `ccrouter` 依赖的 Host
声明会在 `ccrouter.yaml` 上发布 `ccrouter_project_configuration_invalid`，修复后立即清除。
Analysis Server 不可靠转发 `.dart_tool` 文件事件，因此插件每 500ms 比较 context root 和 Workspace
内各 Host 的 watch/one-shot snapshot；Package role/context 只在 authored identity 变化时重算，共享
Pub graph/config 每个 resolution root 只检查一次，不创建第二套 Analyzer graph。设置
`CCROUTER_DISABLE_ANALYZER_WATCH_BRIDGE=1` 可关闭整个 Generator diagnostics bridge。
框架维护者可在启动 Analysis Server 前设置
`CCROUTER_ENABLE_ANALYZER_TIERED_POLL=1` 做规模 A/B：文件事件与通过双文件校验的成功 generation
epoch 仍即时刷新，exact-path 丢事件兜底分为 10 个 500ms shard，最坏完整审计周期为 5 秒。
该实验开关默认关闭，不能作为业务项目的生成正确性保证。
诊断发布/消费均为 fail-open 可观察性，不改变生成成功与否；CI 仍以 `--no-cache --check` 为权威。
Builder 成功后的 watch cycle 会直接进入已完成 Builder 的聚合路径，避免重复执行普通 fast-path
inspection 与 Build Plan 推导，但仍保留 input fingerprint/barrier、preflight、快照、Validator、
聚合和状态写入。聚合 cycle 默认在 watch 进程内执行，避免再次启动 Dart、加载 generator AOT
entrypoint 和恢复 CLI library graph；`aggregationSucceeded.cycleMode` 为 `inProcess`。设置
`CCROUTER_DISABLE_WATCH_IN_PROCESS_CYCLE=1` 可恢复 subprocess reference（事件值为
`subprocessReference`）做逐字节与耗时 A/B；`CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION=1`
则只恢复旧 cycle planning 路径。两个 kill switch 均不关闭 watch，也不改变最终
`--no-cache --check` 的权威性。

源码 fingerprint、managed-output snapshot、Generator kernel fingerprint 和 dependency preflight
的批量文件读取共享每个 isolate 最多 4 个并发读取的预算；文件内容仍逐字节校验，结果保持确定顺序。
设置 `CCROUTER_DISABLE_PARALLEL_FILE_READS=1` 可回退串行读取做 A/B；活动 watch 需要重启后生效。
读取失败会先等待已启动的
读取结束，再进入失败/恢复流程；该开关不跳过 Builder、Validator 或任何 input barrier，也不缓存
跨 cycle 的文件内容。规模基准：
`fvm dart run packages/ccrouter_test/benchmark/generator_file_read_scaling.dart`；实际 Demo 交错 A/B
追加 `--demo`。文件读取基准的收益不能直接当作完整生成或 Analyzer 的收益。

单个 input snapshot 内进一步去重已经评估：当前 Demo 只有约 82.7KB 候选重复读取，真实 CLI
A/B 没有显示净收益，生产原型已撤回。局部研究清单与 benchmark 见
[性能报告 10.19](docs/CCRouter-generator-performance-report.md)；
该评估没有新增运行时开关，也不改变 watch、Pub Hook 或 Analyzer 行为。

流式 SHA-256 也已评估：它保持原有名称、排序、分隔符和完整文件字节，减少微基准中的
连续数组分配，但真实 Demo CLI 的耗时与峰值 RSS 没有一致净收益，因此生产原型同样撤回。
评估与验收边界见[性能报告 10.20](docs/CCRouter-generator-performance-report.md)；研究 benchmark：
`fvm dart run packages/ccrouter_test/benchmark/generator_digest_streaming.dart`。
该命令只运行局部 hash 对照，不启用生产优化，也不提供 CLI/watch A/B 开关。

成功 cycle 在发布本机 fast-path manifest 与 Build Plan state 前只捕获一次 exact-content
planning snapshot，并由两个状态文件复用；两者仍分别原子写入。设置
`CCROUTER_DISABLE_SHARED_PLANNING_SNAPSHOT=1` 可恢复各自独立扫描，用于逐字节和耗时 A/B；
该开关不改变 input barrier、Validator、artifact snapshot 或最终 `--no-cache --check`。
普通 one-shot 与 watch 还会把最终 input barrier、profile/check current-output scan 或
metadata-cache persist 已读取的 exact bytes 组合为 unified generation epoch，供 planning state
派生，避免在同一成功边界再次读盘。设置 `CCROUTER_DISABLE_UNIFIED_EPOCH_SNAPSHOT=1` 可恢复
完整 planning recapture；入口 artifact snapshot、Builder 前后 input barrier、restore 重扫和
逐字节比较仍保持独立，不能由 epoch evidence 替代。
同一个入口 snapshot 还会派生 build root 内 non-target Package 的 build_runner protection view，
避免在启动 Builder 前再次遍历相同 managed outputs；root 外 read-only Package 仍独立捕获和恢复。
设置 `CCROUTER_DISABLE_SHARED_BUILD_PROTECTION_SNAPSHOT=1` 可恢复完整二次扫描。
`build-runner-protection-snapshot.attributes.evidenceMode` 报告 `shared` 或 `recaptured`；两条路径
都在 Builder 后重新扫描当前文件并逐字节恢复，不能用 build filter 代替越界写保护。
同一入口 artifact snapshot 和 cycle-end planning snapshot 也分别提供 aggregation output proof，
不会为 reuse 额外扫描生成目录；证明只写入 `.dart_tool/ccrouter/v1/aggregation_reuse/`，不属于
Portable State 或可提交生成物。
watch 的最终 input barrier 会把刚验证的 exact-content snapshot 直接交给 planning state；当
aggregation reuse 命中时，planning capture 还会复用入口快照中已验证未变的
aggregation-owned bytes，同时重新读取当前 Builder-owned outputs。它不删除或合并 barrier。
`planning-snapshot-capture.attributes.evidenceMode` 还会报告
`input-and-current-output` 或 `input-and-persisted-output`；
`CCROUTER_DISABLE_WATCH_EVIDENCE_REUSE=1` 恢复 watch 完整 recapture，供逐字节和耗时 A/B。
watch 的 profile output-delta scan 还会把它刚读取的 current managed-output bytes 交给 planning
state，避免随后再次扫描相同输出；此路径报告 `input-and-current-output`。设置
`CCROUTER_DISABLE_WATCH_OUTPUT_EVIDENCE_REUSE=1` 只关闭本项并退回上述 aggregation/input evidence，
总开关仍关闭全部 watch evidence reuse。该复用发生在 Builder、aggregation 和最终 input barrier
成功之后，不会用 cycle 入口 bytes 代替本轮 Builder 输出。

`--profile` 的 `input-delta` 对比上次成功的本机 Build Plan：`authored` 是自身源码/配置变化，
`resolutionOnly` 是自身未变但解析身份变化，另列工具与 Host 图变化。它不证明具体依赖边或
生成语义；没有两侧源码摘要的 Package 单列 `authoredUnavailable`，不据此推断源码未变。
缺少可用基线、强制参考路径等情况报告 `unavailable`。`output-delta` 按 Dart、JSON
元数据、Markdown、Portable State 分别统计实际新增/删除/修改，`--check` 在恢复前统计。
状态文件变化不等于业务 API 变化，Dart 不变也不代表文档/定位不变。Package 名称最多显示
12 项，数量完整；不输出源码或业务值。不带 `--profile` 不做额外输出比较，缓存与生成决策不变。
输入归因与既有 Build Plan 一样只覆盖默认输出目录；自定义 `--output-dir` 不提供输入归因。
自定义 docs/build 输出目录的 Catalog 仍参与 `--check` 差异检测与恢复；同目录其它用户
文件不受影响，检查模式仍要求输出目录位于构建根目录内。

当前已完成 Build Plan 的 P1 诊断、P2“Host 依赖闭包删除组件”优化、P3 Portable
Generation State 的可信 Package 新增路径、P4 冷成本评估，以及 P5 3x/5x/10x 多组件个人与
团队拓扑回归。P4/P5 是正确性和性能验证阶段，不增加命令或公开 API；详细边界和样本见
[`docs/CCRouter-build-runner-optimization-plan.md`](docs/CCRouter-build-runner-optimization-plan.md)
与
[`docs/CCRouter-generator-performance-report.md`](docs/CCRouter-generator-performance-report.md)。
fast path miss 时，`--profile` 还会输出
`build-plan suggested=<unchanged|aggregateOnly|runBuilder> actual=<...> reasons=<...>`：
`suggested` 是根据 Tool、Package 和 Host 分层内容摘要得到的候选计划，`actual` 才是本轮
真实执行路径。只有 Package 集合发生纯删除、没有新增 Package，并且所有保留 Builder Package
的源码、解析身份、metadata 和受管输出都与上次成功状态完全一致时，`actual=aggregateOnly`
才会跳过 build_runner。纯新增 Package 也可以走该路径，但每个新增 Package 都必须携带
`lib/src/ccrouter_generated/metadata/ccrouter_generation_state.json`，且 CLI 重新计算的源码、
配置、解析依赖、metadata 和全部受管输出摘要必须逐项一致。生成仍会继续执行完整 Validator、
Host 聚合、旧产物清理和原子恢复。普通源码变化、缺少状态的本地新组件或任何无法证明的可写
状态仍为 `actual=runBuilder`；只读 Git/Pub/Workspace 外 Path Package 缺失或失配时明确失败，
Host 不会修改外部依赖。诊断基线保存在
`.dart_tool/ccrouter/v1/build_plans/`，可以随时删除；缺失、损坏或无法证明解析身份时会保守回退。
设置 `CCROUTER_DISABLE_AGGREGATE_ONLY=1` 可临时关闭该优化并恢复完整 Builder；
`--no-cache --profile` 会报告 `reasons=no-cache-reference` 并始终执行完整参考路径，
`--no-cache --check` 仍是 CI 权威门禁。Portable State 是可选的分发契约，而不是普通本地
生成的默认输出。Package 需要在 `ccrouter.yaml` 声明 `generation: { portable: true }`，然后
由作者显式运行 `ccrouter portable prepare <project-root>` 生成当前角色写作用域内声明为
portable 的状态，再用 `ccrouter portable publish <project-root>` 做发布前验证；普通
`ccrouter generate` 只维护
`.dart_tool` planning state。发布动作不会替代用户授权的 Pub/Git 发布，也不会连接外部系统。
只读消费端对已声明预生成 Package 的状态缺失或失配 fail closed，writable Package 则回退完整
Builder。

Portable State 按组件内容验证，不绑定该组件自身尚未产生的 Git commit 或归档哈希，也不要求
消费者安装作者的测试用 devDependencies；生成工具及实际运行依赖仍须匹配。只要依赖身份或
源码不同，就需要由作者重新生成并分发，Host 不会修改只读依赖。快速路径与完整验证共享外部
源码及解析依赖的内容证明，并重新读取全部外部受管输出；修改/删除生成文件或修改传递 Path
依赖的 DTO 都会使快速路径失效。注释目前仍属于源码摘要输入，尚未实施语义摘要优化。

fast path 未命中后，Generator 会先对 Host 依赖闭包执行保守的 Component Dependency
Preflight：仅当直接 List、Contract 与 Owner 都能唯一证明时，才在 build_runner 前按组件和
Owner 聚合报告缺失的 Service/Command required dependency；变量、spread、条件集合、歧义或
复杂表达式继续交给权威 Builder/Workspace Validator。进入正式生成后会先保存全部 CCRouter
受管生成源码的内容快照，Builder、聚合或校验失败都会恢复原生成物，避免失败运行留下可编译但
彼此不一致的半成品。

执行 `ccrouter clean` 后，如果 build cache 仍有效，下一次 `generate` 会在 build_runner 前
临时恢复源码已导入的 Route/Command/Event component API，避免 import graph 需要第二轮才能
收敛；当前轮仍会重新构建并完整校验最终生成物，bootstrap 失败不会保留半成品。
Package 的生成物 ownership 在遇到下一级 `pubspec.yaml` 时终止；因此组件目录中的独立
`example/` Host 不属于父组件的 clean、fingerprint 或 Builder 写入范围，必须由 example Host
自己的 generate/clean 管理。

`find` 会返回 Contract、实现与生成桥接的 Package URI 和源码坐标，只读取当前 Host 依赖闭包中
已有的 Package Index，不运行 Builder，也不扫描源码。增加
`--usage <consumer-component-id>` 时，会为一个已存在的消费组件报告已验证 public import、Pub/
Owner/能力依赖状态、稳定 Component API 和 typed 调用方式。该模式不会修改 `pubspec.yaml`、
`CCComponent`、import 或生成物；缺少 public exposure 时不会猜 barrel，也不会建议依赖实现 Package。
Service/Command 分别使用各自 dependency list，Event 使用 Subscription，InitTask 使用 `dependsOn`
DAG；不存在统一的万能依赖列表或 InitTask 业务 Client。源码或依赖声明变更后应先运行 `generate`。

`pub-hook` 是显式、按 Flutter SDK 版本安装的可回滚 wrapper；`status` 会打印实际 SDK
路径并校验 Flutter/Dart wrapper、备份和 marker，只有 `installed and verified` 才返回成功。
SDK 解析优先使用 `FLUTTER_ROOT` 和当前目录向上的 `.fvm/flutter_sdk`。它只在原始
`flutter pub` 或 `dart pub` 的 `get/upgrade/downgrade/add/remove` 成功后运行；`flutter run` 和
`flutter build` 会在调用原始 Flutter 入口前执行同一生成器作为 fail-closed preflight。当前
项目没有直接声明 `ccrouter`/`ccrouter_contracts`，或没有解析对应 Package 与
`ccrouter_generator` 时直接跳过。app-role Host 运行完整 Host generation；Flutter component 与
Pure Dart contracts Package 运行 package-local generation。因此 Workspace 聚合根不会被误判为
Host；Hook 不会猜测某个成员 Package 代替当前目录生成。
Hook 的 preflight、post-pub、supervisor 与 watch daemon 都显式使用刚由 Pub 成功写入的
`.dart_tool/package_config.json`；这些内部 `dart run` 不会再次触发 Dart-only dependency
resolution，因此含 Flutter SDK 依赖的 Host 也不会在 generator 入口前失败。
preflight 遇到 active watch 时由普通 `generate` 验证并复用精确 Host/Package cycle，成功后继续
原始平台构建；它不会仅因 watch 持有 generation lock 而拒绝构建。
wrapper 按已知 global option 的 arity 定位第一个真实 Flutter/Dart command，再只读取 `pub`
后的第一个真实 subcommand；option value、脚本参数或后续业务参数中的 `pub`/`run`/`build` 不会
误触发生成。无法判断 arity 的未知 global option 会安全跳过 Hook 并交给原 CLI；可用
`CCROUTER_PUB_HOOK_DISABLE=1` 做完整原路径对照。
在 macOS/Linux 上，安装器包装 Flutter SDK 的 inner Dart executable，因此 IDE 直接调用
`bin/cache/dart-sdk/bin/dart pub get` 也会触发 Hook；Windows 只包装 `bin/dart.bat`，IDE 若直接
执行 `cache/dart-sdk/bin/dart.exe` 则仍在边界之外，`status` 会明确显示该限制。它不监听
Flutter Tool 内部隐式 `pub get`。`flutter run` 在 preflight
成功后会持有一个后台 watch lease，原始 Flutter 进程退出时释放；`flutter build` 仍只执行
one-shot preflight。lease 位于 project/Host 隔离的 `CCROUTER_HOME` coordination 目录，不会因
`flutter clean` 删除 Host `.dart_tool` 而先于 clean invalidation 消失。同一 Host 的并行
`flutter run` 各自持有 lease，但复用一个 watch；任一 run 退出不会中断其它 run，最后一个
有效 lease 消失后 watch 才停止。wrapper 会先输出 `watch starting`，再以结构化状态、owner
lock 和 PID-bound lease acknowledgement 等待 `watch ready` 或 `watch reused`；只有后者成功
才启动 Flutter。正常提示都写入 stdout，避免 IDE
将正常状态渲染为红色错误；其中包含 PID、状态文件和完整日志路径。可用
`ccrouter watch status <host>` 或 `ccrouter watch follow <host>` 验证保存后的生成轮次。
POSIX 与 Windows wrapper 都用同一个 Dart supervisor 继承终端运行原 Flutter Tool，detached
coordinator 负责 watch 竞选与日志重定向，supervisor 持续刷新版本化 lease
heartbeat；正常退出、non-zero exit 和可处理的 Ctrl+C 都会释放 lease。即使 supervisor 被强制
终止、无法执行清理，watch 也会在 heartbeat 过期后停止，避免后台进程长期残留。可用
`CCROUTER_DISABLE_WINDOWS_RUN_SUPERVISOR=1` 临时恢复旧 batch 生命周期做 A/B；该回退不关闭
preflight、watch startup handshake 或 generation lock。
SDK 切换后 `status` 应显示 `run/build preflight: enabled`、`run watch: enabled`、
`watch startup handshake: enabled`、`run supervisor: enabled` 以及当前平台的
`dart pub post-hook: enabled`。旧 schema 4/5 安装需先 `uninstall` 再重新 `install`；schema 6
确保所有 Hook 内部 Dart 入口绑定已解析的 package config。
`run/build` 成功时控制台使用 `CCRouter preflight`，Pub 后生成使用
`CCRouter post-pub generation`；成功只保留 fast-path、验证摘要与最终总耗时，失败则输出最近
200 行且最多 64 KiB 的 Generator 日志。若 Builder 已成功而后续 Workspace Validator 失败，
默认输出会删除正常的 Builder progress/skipped 行，只保留 Builder 汇总、structured root cause、
修复建议以及 requested Host/Package 和 resolution root；`--profile` 额外保留 raw validation errors。
Builder 自身失败时仍输出完整有界 tail，不会因精简呈现隐藏未知错误。
当同一 Host 的 watch 已活动时，post-pub 不会再启动一个必然与 generation lock 冲突的
one-shot；它等待 Pub 解析变更之后的 `aggregationSucceeded`。该轮失败时仍返回非零并转发
watch 的有界 Generator diagnostics。watch 状态使用 `sessionId`、`cycle` 和单调
`eventRevision` 区分历史事件；若 Pub 在 cycle 中途改写 resolution，新的 terminal failure 会
立即报告该轮不能作为成功证明并要求新 cycle/session，不再等待 5 分钟。成功仍必须匹配当前
resolution exact-content fingerprint；若 topology 需要新 build_runner graph，Hook 会继续等待
新 session 的 `ready`，不会接受该 session 尚未 ready 时的中间聚合成功。设置
`CCROUTER_DISABLE_PUB_HOOK_WATCH_FAILURE_FENCE=1` 可临时恢复旧的严格 fingerprint-only
失败等待路径；状态不可用、watch 退出或最终超时仍 fail-closed。
同一 build root 中从 component/contracts Package 触发 Pub 时，package-local Hook 不会只凭
Host watch 的 target 名称放行。成功 aggregation 会在 stable Builder session 中原子发布每个
target 的 Pub resolution、authored input 与 managed output 精确指纹；Hook 重新计算当前 Package
字节并全部匹配后复用该 cycle。build/resolution 开始时旧证据即失效；target 缺失、旧版 watch、
指纹不匹配、失败、退出或超时仍 fail-closed，且不会启动冲突 one-shot。设置
`CCROUTER_DISABLE_PACKAGE_WATCH_REUSE=1` 可恢复原有拒绝路径做 A/B。stale、损坏或 build-root
不匹配的 `builder-status.json` 不会被信任。
SDK 切换或升级后需要重新检查 `pub-hook status`。详细语义见
[`docs/CCRouter-cli-pub-hook.md`](docs/CCRouter-cli-pub-hook.md)。

生成目录统一为：

```text
lib/src/ccrouter_generated/
├── ccrouter_host.api.g.dart # Host 稳定聚合入口，仅 Host Package 生成
├── <package>.contracts.api.g.dart # Contracts Package 的稳定 Route Contract 入口
├── binding/     # Flutter 页面构造 bridge
├── command/     # Command Handler registration bridge
├── component/   # 自动 Registrar、Manifest、组件 Route/Service API
├── contract/    # 独立 Pure Dart Route/Service Contract
├── event/       # Event Subscription registration bridge
├── host/        # Package Bundle 与 Host 内部装配胶水
├── init_task/   # InitTask registration bridge
├── metadata/    # Package Index、Host routes、可读 Catalog
├── route/       # 组件内部 Route contract/registration bridge
└── service/     # 简单 Service Provider registration bridge
```

并非每个 Package 都会生成全部子目录；Package Bundle 与 Host 聚合代码按 Package 角色写入 `host/`。

页面或简单 Service 新增后只需添加注解并重新执行 `generate`；不要手写生成文件、逐项修改
Registrar 或添加 generated `part`。没有任何生成能力的 Package 不创建
`lib/src/ccrouter_generated/`；清理最后一项能力后，CLI 会移除仅含受管文件的空目录，但保留
任何未知或手写文件。

详细生成规则见 [`packages/ccrouter_generator/README.md`](packages/ccrouter_generator/README.md)。
生成性能、混合能力压力模型和优化前后数据见
[`docs/CCRouter-generator-performance-report.md`](docs/CCRouter-generator-performance-report.md)；
Package Graph 变化后的正确性优先调度和团队构建加速方案见
[`docs/CCRouter-build-runner-optimization-plan.md`](docs/CCRouter-build-runner-optimization-plan.md)。

## 测试

框架使用者的测试能力统一放在 `ccrouter_test`，生产代码不要访问 Runtime 私有构造器。测试至少覆盖 Route Intent、Interceptor、PopGuard、Scope 销毁、Command 取消/超时、Event 失败隔离、InitTask DAG 和 Host/Outlet 混合导航。

完整回归：

```bash
fvm dart analyze
fvm flutter test packages/ccrouter_test/test
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test
fvm flutter test demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --check
```

## API 边界

业务和组件代码应遵守：

- 只通过 `CCRouter.navigator` 导航 CCRouter 管理的页面。
- 只通过生成的 Intent 调用静态已知路由；动态地址使用 `open`。
- 不访问 `CCRouterRuntime`、`CCScope`、Registry 内部表、Adapter Controller 或销毁入口。
- 不从业务代码导入 `ccrouter_host.dart`、`ccrouter_core/src/*` 或生成 binding/package/host 文件。
- 不把 Registrar、Manifest、页面实现或组件 private 类型当作跨组件契约。
- 不手工 dispose 框架拥有的 Service、Adapter 或 Route Scope。
- 不在 Interceptor、Aspect、Lifecycle callback 中同步递归导航。
- 不把完整 URI、Token、Extra、参数或返回对象写入日志和 Telemetry。

生成器与 Analyzer 会尽量把 Route ID、Pattern、Codec、参数、跨 Package import 和内部 API 误用提前到构建期，但 `src` 目录本身不是 Dart 的强私有边界；CI 必须保留 analyze 与 `generate --check`。

## AI 集成开发 Skill

仓库提供两套互补的 Skill：

- [`skills/ccrouter-integration-development/SKILL.md`](skills/ccrouter-integration-development/SKILL.md)：业务组件与 Host 集成。
- [`skills/ccrouter-cli-development/SKILL.md`](skills/ccrouter-cli-development/SKILL.md)：生成、查找、清理、脚手架、校验，以及尚未实现 CLI 命令时的受控 AI 辅助流程。

集成 Skill 会强制 Agent：

- 先判断应使用 Route、Service、Command、Event 还是 InitTask。
- 页面导航统一走 `CCRouter.navigator`。
- 正确区分 Interceptor、PopGuard、Aspect 和页面生命周期。
- 遵守 Host SPI、组件实现与 contracts Package 的依赖边界。
- 不虚构当前尚未实现的 Action Pipeline 或动态组件；Command/Event/InitTask 生成能力与 Service Proxy 只使用当前支持的显式声明和方法矩阵。
- 生成后执行 analyze、针对性测试与 `generate --check`。

CLI Skill 覆盖已经实现的 `generate`、`find`、`clean`、六类 `create` 脚手架、
`analyzer status/doctor/install/upgrade/uninstall` 和显式 `pub-hook` 管理。Contract
Scaffold/Promotion/Migration、alias 迁移和扩展生成失败诊断目前仍是 AI 辅助工作流，不是可直接
调用的 CLI 命令；五类 Contract 版本兼容核心门禁已经由生成器、Host 聚合和 Runtime 自动执行。
AI 辅助的迁移操作先说明影响和 dry-run；已有明确授权时继续实施，只有超出授权范围或仍有
关键选择时才询问，不反复确认已批准的修改。AI 开发可使用
`generate <host> --watch=auto --machine` 消费 NDJSON 状态；结束任务前仍运行
`generate <host> --no-cache --check`，不能把 watch 成功当作 CI 权威门禁。

将下面**两个完整目录作为一套安装包**，从同一框架版本复制或同步到集成工程的 `skills/` 下，
保留它们的相邻关系、`references/` 和 `agents/`，不要只复制单个 `SKILL.md`：

```text
skills/
├── ccrouter-integration-development/
│   ├── SKILL.md
│   ├── agents/
│   └── references/
└── ccrouter-cli-development/
    ├── SKILL.md
    └── agents/
```

必需的场景评估、能力选型、Analyzer 手工接入和 CLI 流程都在这套目录内；无需复制框架的
`docs/`、Demo 或生产源码。远端设计链接只是可选背景，离线不影响必需流程。SDK、API 或 CLI
版本不同时，以消费工程实际依赖和命令帮助为准，不因 Skill 示例自动升级依赖。
若客户端采用其他 Skill 搜索目录，将两个目录一起放入其同一个父目录。
然后在集成工程的 Agent 规则中加入：

```text
When implementing or reviewing Flutter features that use CCRouter, read and
follow skills/ccrouter-integration-development/SKILL.md.

When generating, validating, locating, cleaning, scaffolding, or planning a
Contract migration, also read and follow
skills/ccrouter-cli-development/SKILL.md.
```

支持显式 Skill 调用的客户端也可以直接使用：

```text
$ccrouter-integration-development 为订单组件新增详情页，并返回类型安全的确认结果。
$ccrouter-cli-development 检查并安全规划订单详情页的生成与跨组件 Contract 提升。
```

Skill 使用主文件和按需 reference，既适合日常编码，也可用于代码审查。框架公开 API、生命周期、错误语义、生成命令、支持状态或推荐 Demo 用法发生变化时，维护者必须同步审查本 README、Integration/CLI Skill 及其 references。

维护者在框架仓库执行 `fvm dart run tool/skill_bundle_check.dart`：它只复制这两个目录到临时
消费目录，检查必需引用不越界，并对照真实 CLI 帮助校验命令和参数。该检查不会执行文档中的
清理、Hook 安装或迁移命令，也不能替代关键示例的编译验证和 AI 实际使用评估。
关键示例与安装故障边界通过 `fvm dart test tool/test/skill_bundle_check_test.dart` 回归：
测试直接提取文档代码，使用实际依赖分析，并确认旧初始化参数和缺失方法实现会被拒绝。

## 进一步阅读

- [`CHANGELOG.md`](CHANGELOG.md)：当前未发布变更
- [`SECURITY.md`](SECURITY.md)：安全问题报告边界
- [`docs/README.md`](docs/README.md)：当前能力状态与全部文档职责索引
- [`docs/CCRouter-release-readiness.md`](docs/CCRouter-release-readiness.md)：正式发布阻塞项、门禁与发布顺序
- [`demo/README.md`](demo/README.md)：可交互能力清单和真机验证方式
- [`docs/CCRouter-v0.1-architecture.md`](docs/CCRouter-v0.1-architecture.md)：总体架构
- [`docs/CCRouter-route-design.md`](docs/CCRouter-route-design.md)：路由设计
- [`docs/CCRouter-component-framework-comparison.md`](docs/CCRouter-component-framework-comparison.md)：与其他组件化框架的能力对比和后续缺口
- [`docs/CCRouter-service-lifecycle-design.md`](docs/CCRouter-service-lifecycle-design.md)：Service 生命周期设计
- [`docs/CCRouter-service-proxy-generation-design.md`](docs/CCRouter-service-proxy-generation-design.md)：跨组件 Service Proxy 生成设计
- [`docs/CCRouter-command-design.md`](docs/CCRouter-command-design.md)：Command 设计
- [`docs/CCRouter-event-design.md`](docs/CCRouter-event-design.md)：Event 设计
- [`docs/CCRouter-initialization-task-design.md`](docs/CCRouter-initialization-task-design.md)：InitTask 设计
- [`docs/CCRouter-core-principles-audit.md`](docs/CCRouter-core-principles-audit.md)：核心价值回归
- [`docs/CCRouter-pre-release-capability-plan.md`](docs/CCRouter-pre-release-capability-plan.md)：正式发布前 Contract、DevTools、Analytics、脚手架与质量回归计划

设计文档用于解释约束与演进方向；实际可用 API 以当前 public barrel、生成器校验和 Demo 回归为准。
