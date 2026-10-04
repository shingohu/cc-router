# CCRouter Flutter / Dart SDK 升级同步计划

## 1. 状态与目标

- 日期：2026-10-04。
- 状态：已核对当前约束及代码边界；**实施待确认，尚未选择目标 SDK、升级依赖或修改生产实现**。
- 范围：框架适配、生成正确性、IDE 插件、CLI/Hook、DevTools、平台验证及文档同步。
- 本文管理升级工作；[SDK 兼容性验证](CCRouter-sdk-compatibility.md) 保存实际运行矩阵；
  [正式发布门禁](CCRouter-release-readiness.md) 仍是唯一发布清单。

Flutter 升级、提高 Package 最低 Dart/Flutter 版本、升级第三方依赖是三个不同决定。
Flutter 应使用它自带的 Dart；Pure Dart 包可以另测独立 Dart SDK，但不能以它替换 Flutter
内部 Dart 后宣称 Flutter 兼容。框架不自动要求所有用户跟随维护者的开发 SDK 升级。

## 2. 当前基线与风险

以下为本次源码/lockfile 核对；默认 SDK 额外执行了 `fvm flutter --version --machine`。
没有查询官方最新发布版本，也没有重新执行历史表中所有标准 Flutter SDK。

| 层 | 声明约束 / 当前解析值 | 升级时的含义 |
| --- | --- | --- |
| 当前本机默认 | OHOS Flutter `3.41.10-ohos-1.0.0`，Dart `3.11.5`，DevTools `2.54.1` | 仅表示本次运行环境，不是框架最低支持版本 |
| 框架 Package、独立插件、Extension | Dart `^3.10.0` | 声明允许不等于该下限已在当前提交完整验证；需独立最低版本消费者 |
| Demo | Dart `^3.11.5` | 整个 Workspace 不能用来证明 Dart 3.10 下限 |
| GoRouter Adapter | `go_router: ^17.5.0`，lock 为 `17.5.0` | 依赖本身要求 Dart `^3.10.0`、Flutter `>=3.38.0`；这不是 CCRouter 所有功能在 Flutter 3.38 已验证的承诺 |
| Generator | `analyzer: ^10.0.0` → `10.0.1`；`build: ^4.0.0` → `4.0.7`；`source_gen: ^4.0.0` → `4.2.4`；`dart_style: ^3.1.7` → `3.1.7` | AST/Element API、常量求值、语法支持、格式输出需要组合验证 |
| Workspace 构建工具 | `build_runner: ^2.10.0` → `2.15.1`；`build_test 3.5.16`；`meta 1.17.0` | Flutter SDK 的依赖 pin 会限制可解析组合，不能只看各包最新版 |
| IDE 插件及 loader | `analyzer 8.4.0`、`analyzer_plugin 0.13.10` | 独立依赖图，不在 Workspace 内；与 Generator Analyzer 无须同版本 |
| DevTools Extension | `devtools_extensions` / `devtools_app_shared` 均为 `^0.4.0`，lock 为 `0.4.0` | 应与实际 DevTools 宿主验证；Web 构建按 Extension 文档使用标准 Flutter |

根目录没有提交 `.fvmrc`；Demo 的 `.fvm/fvm_config.json` 声明 OHOS SDK。不能只看配置文本
判断实际执行路径，根目录 FVM 默认、Demo、IDE 和全局 CLI 可能使用不同 SDK。

已知历史约束：build_runner 优化计划记录过候选 `2.16.1` 的 Analyzer/meta 组合与当前 Flutter
pin 冲突。该记录不是永久版本结论；目标 SDK 确定后重新解析，不为解决冲突直接加入
`dependency_overrides` 强行覆盖 Flutter 固定依赖。

### 2.1 需要重点验证的生成状态边界

当前本地快速路径包含 `Platform.version` 和 Dart executable 路径；Portable State 的工具摘要
包含 Dart 数字版本、生成器源码和工具解析身份。`verifyReadOnly` 对不匹配的 Git/Pub 组件
明确拒绝，不写依赖缓存。因此：

- Dart 版本变化，即使业务契约未改，也可能触发只读外部组件的 `toolMismatch`。执行
  `--no-cache` 不能绕过这项校验。需先用目标组合重新生成并分发组件，Host 再更新依赖。
- 标准 Flutter 与 Fork 可能携带相同 Dart 版本。现有 portable SDK 来源字段不能直接证明
  Flutter framework、SDK Library 或 engine 的所有变化都已覆盖。需设计“同 Dart、不同 Flutter
  内容/修订”的反例，检查本地快速路径、Build Plan 和跨 clone Portable State，而非只测路径变化。
- 以上是待验收边界，不是本次已复现的缓存漏洞。若反例成立，再按实际语义输入补齐确定性
  身份或安全失效路径；不把本机绝对路径、mtime、时间戳写入可移植状态。
- Runtime/Contract SemVer、生成证明 schema、生成器版本各有职责。SDK 升级不能自动等同于
  Contract major 升级；也不能为保持旧 state 有效而删掉 SDK 身份。

正式承诺多个 SDK 消费同一份 Git/Pub 生成物前，必须证明这种分发组合成立。若现有严格
策略导致无法同时支持，应明确兼容工具链及重生成/分发要求；跨工具链证明或多份产物协议
需要单独评审，不能在升级中临时放宽校验。

## 3. 方案与推荐

| 方案 | 优点 | 风险 / 成本 |
| --- | --- | --- |
| 仅切换 Flutter，保留依赖锁 | 最小变量，容易归因 | 可能无法解析，或编译通过但运行/IDE/生成语义发生变化 |
| Flutter、GoRouter、Analyzer、build_runner 全部升到最新 | 一次获得新版能力 | 变更面大、冲突难定位、难以回滚，不推荐 |
| SDK 兼容验证与工具链升级分阶段 | 能定位问题、保留旧组合参考、按收益决定依赖升级 | 需要独立工作区和多阶段回归，推荐 |

默认先验证新 SDK 与现有依赖；必须调整的依赖作为最小兼容组合升级。可选的性能升级
放在兼容修复之后，独立提交。不能为了 build_runner 提速顺带扩大 Runtime 或公开 API。
当前 SDK 正常且目标版本没有明确收益时，先完成下面的证明/回归准备，不为追版本而升级。

## 4. 框架层同步检查与可能修改

每行“可能修改”由目标组合的实际失败或已确认 API 变化触发，不要求每次升级都改代码。

| 领域 | 每次必须核对 | 必要时修改的位置与验收 |
| --- | --- | --- |
| Package 版本边界 | 所有 `environment.sdk`，Flutter 面向包的有效最低 Flutter 约束，实际 transitive 下限，最低消费者能否解析/运行 | `packages/*/pubspec.yaml`、根/独立插件 lock；证据确认后才补充 `environment.flutter` 或提高下限，不仅统一文本 |
| Generator / Builder | 五类能力的 15 个入口；AST/Element/Fragment、注解身份、常量/default/typedef/bound、Codec、`part`/导出/条件分支、语言版本和格式结果 | `packages/ccrouter_generator/lib`、`build.yaml` 及专项测试；新语法无法证明时不能静默生成错误结果 |
| 生成缓存与分发 | SDK/tool identity、热命中、失效、旧产物删除、失败恢复、只读 Git/Pub、团队 clone | `bin/src/build_plan.dart`、`portable_generation_state.dart`、CLI 快速路径；必要的证明变更应版本化，保留完整参考路径 |
| Analyzer 插件 | SDK Server 协议、AST API、新语法、声明身份、overlay/磁盘刷新、诊断清除、Quick Fix 坐标、多个分析根和进程退出 | `packages/ccrouter_analyzer_plugin` 及独立测试；普通 Analyzer 和 `generate --check` 仍是插件不可用时的门禁，不静默屏蔽错误 |
| 插件 bootstrap / CLI | 插件自身、loader、CLI 模板、Demo bootstrap 是否匹配；全局 CLI snapshot 是否可在目标 SDK 重建 | 插件和 `tools/analyzer_plugin` pubspec、`bin/src/analyzer_installation.dart`、Demo `tools`；固定来源安装 smoke 后才能更新 Demo ref，不使用浮动 main |
| Flutter Route/Host | Page/Route Factory、默认平台动画、Cupertino 返回、PopScope/Guard、系统返回、typed result、生命周期、Foreign Popup、Host/Outlet 隔离 | `ccrouter/lib/src/flutter_route_factory.dart`、生命周期/Host 与 `ccrouter_go_router/lib/src`；重点防止“能编译但侧滑或返回保护失效” |
| GoRouter | 当前版本是否支持目标 Flutter、匹配/重定向/refresh、Shell/StatefulShell、observer 与 pop/replace 行为 | 按真实 breaking change 调整 Adapter/Assembler；不假定 GoRouter major 必须随 Flutter major/minor 同步 |
| App 封装 | `MaterialApp.router` 属性、locale/theme/快捷键等转发、Router ownership 和 dispose 顺序 | `ccrouter_go_router/lib/src/app.dart`；只补真实接入需求，不盲目复制新 SDK 所有参数 |
| Analytics / DevTools | 手势/滚动监听、Consent、Foreign Popup 归因、VM Service、Extension 宿主协议及 Web 构建 | 框架保持 provider-neutral；Firebase、Network、KV Storage 的插件升级归 Demo/应用，不迁入框架 |
| SDK Pub Hook | wrapper 参数解析、pub 成功后生成、run/build 前置、release/`--machine`、退出码、耗时、非 Host 跳过、递归防护 | `bin/src/pub_hook.dart` 及临时 SDK 夹具；不得为了升级修改 Flutter 内部 tool snapshot |
| 生命周期与性能 | pending Future、取消/超时、Scope/Host/Sink/Server 清理、RSS/Heap、冷/热生成及 UI 导航延迟 | 同机同输入 A/B；Flutter/Analyzer 自身缓存增长与框架对象残留分别归因，不能吞错或弱化校验换速度 |

Pub Hook 的 `status` 当前检查 marker、wrapper 与备份存在等结构，不等于验证备份内容与新
SDK 修订完全匹配。优先使用新 SDK 目录做验证；如必须原地升级，应在旧 SDK 完整时先按
既有工具卸载 Hook，再升级。升级后若状态不一致，停止自动覆盖/恢复，核对目标 SDK 与原始
入口，不能把旧 `flutter.ccrouter-original` 恢复到新 SDK。SDK 外部写入由明确安装/卸载操作承担。

## 5. 实施顺序与完成条件

每项独立完成、测试、审查和提交，再进入下一项；具体升级目标确认前不执行切换。

1. **U0：冻结版本矩阵与兼容承诺。** 记录当前提交、目标标准 Flutter 完整版本/revision、
   配套 Dart、DevTools、是否升级 OHOS Fork、保留的最低版本、平台范围及升级收益。
   SDK “已安装”“能解析”“已回归”分开记录；不从历史测试继承当前提交的通过结论。
2. **U1：隔离解析与工具身份验证。** 为旧/新 SDK 准备独立 clone/checkout 和构建缓存，先
   保留 lock 尝试解析，记录 solver 不得不改变的依赖。复现同 Dart 不同 Flutter、Dart 升级、
   路径变化但内容相同、只读 Git/Pub 和跨 clone 场景。与 P6 的生成前后输入一致性测试衔接。
   发现准确性缺陷先修；未证明安全前不做传播收窄。
3. **U2：Generator 工具链最小迁移。** 必要时调整 Analyzer/build/source_gen/dart_style/build_runner
   的可解析组合，修复真实 API/语义变化；跑五类全量 Generator 测试和冷/热生成对照。
   新旧 SDK 产物允许有经过解释的格式/SDK state 差异；同一目标工具链的冷热产物必须一致。
4. **U3：独立 Analyzer 与装配迁移。** 插件和 loader/CLI 模板同步，跑独立 analyze/test，包含
   Legacy/LSP 真 Server、Quick Fix、watcher、独立多根冷启动及退出清理。通过固定来源安装、
   upgrade/失败恢复后，再安排 Demo 远端 ref；没有发布/推送授权时停留在本地可审查结果。
5. **U4：Flutter/GoRouter 与可选工具验证。** 保留旧 GoRouter 优先测试，再按需升级；补必要
   Adapter/Host 修复。验证 Hook 临时夹具与实际选定 SDK；标准 Flutter 构建 DevTools Extension，
   确认协议、连接/断连及重新初始化行为。不以 OHOS SDK 结果代替标准 Flutter 或反之。
6. **U5：最低消费者、平台与性能门禁。** 最低 SDK 的独立消费者覆盖所承诺的 Runtime、
   Generator、插件能力；Demo 用自身要求的 SDK。跑 Android/iOS/macOS/Web/OHOS 中实际承诺
   的平台，iOS 真机侧滑与 Guard 单独验收；Windows/Linux 若未测明确列出。重测混合能力
   3x/5x/10x、个人/团队变更、P50/P95、RSS/Heap、长运行和关闭资源计数。
7. **U6：约束、分发与文档收口。** 基于以上证据调整最低约束和 SDK pin，正式生成并提交全部
   受影响产物；按依赖 DAG 先重生成/分发组件再迁移 Host。更新兼容矩阵、README/CHANGELOG、
   Integration/CLI Skill、安装模板、Demo 与发布门禁。若只是内部修复且接入不变，不做无关
   API/文档改名。最终用干净消费者复验；CI 变更不在本计划默认执行范围内。

U1–U5 的测试补充或修复不是本轮已完成项。本次只完成 U0 所需的当前基线盘点，目标选择仍待确认。

## 6. 执行与证据约定

在已确认实际 FVM 指向目标 SDK 的隔离工作区中执行。使用系统 FVM；需要访问 SDK 缓存时
在沙盒外运行。不同 SDK 不共用 `.dart_tool`、构建产物或插件分析缓存，性能采样串行进行。

```sh
fvm flutter --version --machine
# Workspace 根仅解析依赖，不把聚合根当成 Host 触发生成。
CCROUTER_PUB_HOOK_DISABLE=1 fvm flutter pub get
fvm dart analyze
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test
fvm flutter test packages/ccrouter_test/test
fvm flutter test demo/test
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --check
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check
```

SDK 改变导致受管状态需更新时，`--check` 报差异是预期的审查信号；在隔离工作区执行正式
`generate demo`，审查语义与状态差异，随后再次检查。**不手改生成物，不清理用户工作区来制造通过。**
`--no-cache` 绕过 CCRouter 缓存，但保留 build_runner 的 Asset Graph；还必须在全新临时
工作区执行冷生成，比较同一目标组合下文件集合、每个字节、错误及失败恢复。

独立插件从 `packages/ccrouter_analyzer_plugin/` 运行目标 Dart 的 `pub get`、`analyze`、`test`；
根 `dart analyze` 排除了它，不能冒充插件验证。DevTools Web 构建/校验按
[Extension README](../devtools/ccrouter_extension/README.md) 执行；平台构建从 `demo/` 执行。
Pure Dart 最低版本检查应在脱离 Demo Workspace 的消费者中完成；必要的锁调整只提交各项目
应受版本管理的 lock，不提交全局 Pub/Analysis Server/Flutter 缓存。

每次升级保存：旧/新 SDK revision 与 Dart、lock 差异、各测试结果、生成语义差异说明、只读
依赖重生成要求、平台/IDE 未覆盖项、性能和资源基线、失败阶段及回退方式。性能比较使用
同机同输入，区分 Pub、CLI 启动、Builder、聚合、分析和首次缓存成本；不把测试耗时当生成耗时。

## 7. 回退与完成定义

- 开发验证失败：保留日志和隔离工作区，继续使用旧 SDK/lock/生成物组合；通过普通提交
  回退已合并的兼容改动，不重置用户文件，不覆盖只读依赖缓存。
- SDK/生成物/插件/Hook 回退作为组合处理；只切回 SDK 而继续使用新 `.dart_tool` 或新工具
  产物不算完成回退。已发布 Package 不覆盖旧版本，按发布流程修订。
- 新旧承诺组合的验证均通过，真实行为没有静默降级，生成和插件安装路径可复现，依赖
  分发方案明确，文档只列有证据的支持范围，才可标记升级完成。
- P6 传播收窄与 SDK 升级分开比较；每次升级若 Generator/Analyzer/build_runner 读取语义变化，
  [P6 读取范围证据](CCRouter-build-runner-optimization-plan.md#127-五类-builder-读取范围证据与-p6-决策2026-10-04)
  必须重新验证，不能继承旧工具链的证明。
