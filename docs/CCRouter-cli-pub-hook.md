# CCRouter Pub Hook

> 文档状态：当前已实现行为。Hook 是显式安装、可回滚的本地开发工具，不是 Flutter 官方
> 生命周期扩展点，也不是正式发布或 CI 的替代品。

## 目的

`ccrouter pub-hook` 为当前 Flutter SDK 安装一组可回滚的 Flutter/Dart wrapper。
当 `flutter pub` 或 `dart pub` 的 `get`、`upgrade`、`downgrade`、`add` 或 `remove`
成功后，wrapper
会检查当前项目自己的 `pubspec.yaml` 和 `.dart_tool/package_config.json`：只有当前
Package 直接声明 `ccrouter` 或 `ccrouter_contracts`，并且解析图包含对应 runtime/contracts
Package 与 `ccrouter_generator` 时，才运行一次：

```bash
dart run --verbosity=error ccrouter_generator:ccrouter generate <project-root>
```

app-role Host 执行 Host generation、聚合和跨 Package 校验；Flutter component 与 Pure Dart
contracts Package 执行 package-local generation。普通项目和仅聚合成员的 Workspace 根不会
触发生成，Hook 也不会猜测其中某个成员 Host。

## 安装

从项目或 Workspace 根目录执行：

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook install
```

默认按 `FLUTTER_ROOT`、当前目录向上的 `.fvm/flutter_sdk`、PATH 中的 `flutter`
顺序解析。也可以明确指定一个 SDK：

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook install \
  --sdk /path/to/flutter-sdk
```

每一个 FVM 版本都是独立 SDK，必须分别安装。安装会管理该 SDK 的 Flutter 入口，并在
macOS/Linux 包装 Flutter 实际使用的 inner Dart executable，在 Windows 包装 `bin/dart.bat`。
原文件会保存为：

```text
bin/flutter.ccrouter-original
bin/flutter.ccrouter-original.bat
bin/cache/dart-sdk/bin/dart.ccrouter-original # macOS/Linux
bin/dart.ccrouter-original.bat                 # Windows
bin/.ccrouter_pub_hook.json
```

不会修改 Flutter 的 `shared.sh`、Dart snapshot 或 Flutter 工具源码。
schema 4 只管理 Flutter wrapper；升级时先用当前 CLI 执行一次 `uninstall`，再执行 `install`，
不得直接覆盖旧 marker 或备份。

## 状态与卸载

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook status
```

`status` 会打印实际解析到的 SDK 绝对路径、marker、Flutter/Dart POSIX/Windows wrapper 与备份
文件路径，并校验 wrapper 内容是否仍然是 CCRouter wrapper。只有显示
`installed and verified` 时返回码才为 0；SDK 被升级覆盖或文件不完整时会显示
`not installed or inconsistent` 并返回非零。

例如：

```text
CCRouter pub hook SDK: /path/to/flutter-sdk
  marker: /path/to/flutter-sdk/bin/.ccrouter_pub_hook.json (valid)
  POSIX wrapper: /path/to/flutter-sdk/bin/flutter (verified)
  POSIX backup: /path/to/flutter-sdk/bin/flutter.ccrouter-original (present)
  Dart POSIX wrapper: /path/to/flutter-sdk/bin/cache/dart-sdk/bin/dart (verified)
  Dart POSIX backup: /path/to/flutter-sdk/bin/cache/dart-sdk/bin/dart.ccrouter-original (present)
CCRouter pub hook result: installed and verified
```

Windows 的 `status` 还会明确显示：`cache/dart-sdk/bin/dart.exe` 不受管理。该平台只有经
`bin/dart.bat` 启动的 `dart pub` 会触发 Hook；IDE 若绕过 batch 直接执行 `dart.exe`，必须改用
Flutter Pub、CLI generation，或在 IDE 中配置 batch 入口，不能把 `status` 的成功理解为已拦截
任意 direct executable。

卸载命令：

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook uninstall
```

卸载会恢复原始入口。若发现 marker、wrapper 或备份文件不完整，命令会拒绝删除
入口并报告错误，避免破坏 SDK。

## 执行语义

1. 先完整执行原始 `flutter pub` 或 `dart pub`。
2. 原始命令失败时，直接返回原始退出码，不运行生成器。
3. wrapper 按已知 global option 的 arity 定位第一个真实 top-level command，再读取 `pub`
   后的第一个真实 subcommand。option value、Dart script 参数或业务参数中的 `pub`、`run`、
   `build`、`get` 不参与命令判定；未知且无法确定 arity 的 global option 安全跳过 Hook 并交给
   原 CLI。原始 Pub 成功后，wrapper 使用 subcommand 前后官方支持的 `--directory`/`-C`
   指定项目并向上定位 `pubspec.yaml`。
4. 没有 resolved Package config、当前 Package 没有直接声明 `ccrouter`/
   `ccrouter_contracts`，或解析图没有对应 Package 与 `ccrouter_generator` 时，打印跳过原因
   并返回成功。Host 进入完整聚合和校验；其它参与 Package 只更新自身生成物。
5. 同一 Host 已有活动 watch 时，post-pub 不再并发启动 one-shot；它以当前 Pub 解析文件的
   exact-content fingerprint 为完成栅栏，等待 watch 的 `aggregationSucceeded`。watch 的
   Builder、Validator 或 aggregation 失败时，Hook 返回非零并输出该轮有界 diagnostics，
   因此不会用 generation lock 遮蔽真实错误。状态中的 `sessionId`、`cycle` 和单调
   `eventRevision` 用于排除等待前的历史失败；若 cycle 执行期间 resolution 发生变化，等待后
   出现的新 terminal failure 会立即报告该轮无法作为成功证明，并要求新 cycle/session。
   watch 对 resolution-only 变化执行明确的聚合 cycle；Host closure 新增 Package、生成 target
   集合变化，或 build_runner 因 resolution 更新自行退出时，会在同一 lock/lease 内轮换
   `sessionId` 并重建 child。Hook 必须等新 session 的 `ready`，成功仍严格匹配当前 resolution
   fingerprint，不能用快速失败逻辑放宽。
6. 同一 build root 中从 component/contracts Package 触发 Pub 时，Host watch 的 target 名称
   本身不是 requested Package 的完成栅栏。成功 watch cycle 会在 stable Builder session 中发布
   每个 target 的 Pub resolution、authored input 与 managed output 精确指纹；package-local Hook
   重新计算当前 Package 证据并在三者全部匹配时复用该 cycle，不再启动冲突 one-shot。target
   缺失、旧版/缺失 evidence、指纹变化、失败、退出或超时均 fail closed，并明确报告 owner Host、
   requested Package 和修复动作。`CCROUTER_DISABLE_PACKAGE_WATCH_REUSE=1` 可恢复原有 reject-only
   路径做 A/B；stale、损坏或 build-root identity 不匹配的状态不会被信任。
7. 成功时只打印 fast-path、验证摘要和总耗时；生成器失败时最多保留最近
   200 行、64 KiB。Builder 已成功而 Validator 失败时，默认去掉正常 progress/skipped 行，
   显示 Builder 汇总、structured root cause、修复建议及 requested/resolution root；`--profile`
   才附 raw validation errors。Builder 自身未成功时保留完整有界 tail，避免隐藏未知错误。

所有推荐命令都给 `dart run` 传入 `--verbosity=error`。它只压低 Dart/Pub 在 CLI
启动前输出的重复依赖解析和 executable 构建信息，不会隐藏 CCRouter 的阶段、耗时、
跳过原因、标准错误或非零退出码。直接省略该参数仍可运行，但冷启动或依赖变化后可能
看到多次 `Resolving dependencies`。

Wrapper 会先完整执行原始 Pub 命令，但 `--help`、`-h`、`--dry-run` 和 `-n` 只保留原始
命令语义，不触发 CCRouter post-pub generation。真实依赖写操作使用调用 Package 作为
`requestedRoot`，使用 Pub Workspace reference 验证后的根作为 `resolutionRoot`；两者不能
通过向上找到任意 `package_config.json` 来混为一谈。

Hook 与手动 CLI 共享生成结果语义，但不承诺相同的进程和耗时路径。无活动 watch 时，Hook
启动默认 `generate <requestedRoot>`；活动 watch 时，Hook 只等待上述 exact evidence。Host 与
package-local 继续遵守各自 scope，后者不执行 Host assembly 或跨 Package Host 校验。Analyzer
Plugin 只消费经身份校验的结构诊断，不参与 Hook 成败或生成物写入。性能比较必须分别记录
one-shot、watch cycle 和 Hook wait，不能把某一入口的 wall-time 百分比套用到其它入口。

`CCROUTER_DISABLE_PUB_HOOK_WATCH_FAILURE_FENCE=1` 仅用于 A/B 或紧急回退：它关闭等待基线后的
terminal failure 快速栅栏，恢复旧的 fingerprint-only 失败判断与有界超时。该开关不放宽成功
条件，也不关闭 watch、generation lock、Validator、原子写入或最终 `--no-cache --check` 门禁。

## `run` / `build` 前置生成

当前 wrapper 还覆盖 `flutter run` 和 `flutter build`。两者都会在调用原始 Flutter
入口前执行一次生成；`run` 在成功后额外持有 watch lease：

1. POSIX/Windows wrapper 会在全局 Flutter 参数之后定位 `pub`、`run` 或 `build` 命令；
   因此 `flutter --no-color run` 不会绕过 Hook，`-d run pub get` 中作为 device ID 的 `run`
   也不会被误判为 command。
2. `run`/`build` 使用当前目录（以及兼容的 `--directory`/`-C`）向上定位项目，只有
   同时解析 `ccrouter` 和 `ccrouter_generator` 的 resolved Package config 才运行生成。
3. 生成器使用自身的内容 fingerprint fast path；没有变化时只做有界校验，不重复运行完整
   Builder。并发调用仍由生成锁串行化。
4. 预生成失败会阻止原始 `flutter run/build`，避免启动或 Release 构建消费陈旧生成物。
   active watch 本身不是失败：普通 `generate` 会等待当前 Pub resolution、authored input 与
   managed output 的精确成功证据，命中后输出 `reused active watch cycle` 并继续原始构建。
5. 没有 Package config、普通 Flutter 项目或还未完成首次 `pub get` 时安全跳过；后续
   `flutter pub get` 成功后会执行一次正常的 post-pub 生成。
6. `flutter run` 的 preflight 成功后，POSIX 与 Windows wrapper 都把当前 run 生命周期交给
   Dart supervisor；detached coordinator 负责启动或接入
   `generate <host> --watch=auto --machine`，并把日志写到
   `.dart_tool/ccrouter/v1/watch/flutter-run.log`。每个 run 在 project/Host 隔离的
   `CCROUTER_HOME` coordination 目录持有独立 lease；同一 Host 的并行 run 通过当前 watch PID
   绑定的 acknowledgement 复用一个 watch。任一 Flutter 进程退出只删除自己的 lease，最后一个
   有效 lease 消失后 watch 才终止。registration 竞选失败的候选不覆盖 active status，而会等待
   接入，或在旧 watch 正退出时重新竞选。wrapper 不把进程 fork 当作启动成功：它等待自己的
   lease 成为主 lease 或被 active watch 精确接纳，并确认 `sessionReady` 与 build root owner
   lock，随后才启动原 Flutter Tool。Dart/AOT 入口 30 秒内没有匹配状态，或初始
   Builder/aggregation 5 分钟内没有到达 `ready`，都会 fail-closed。
   `watch starting`、`watch ready` 和 `watch reused` 写 stdout，真实失败与完整日志路径写 stderr。
   `flutter build` 不启动常驻进程。
   supervisor 继承终端启动原 Flutter Tool，并每秒刷新版本化
   lease heartbeat。正常退出、non-zero exit 和可处理的 Ctrl+C 会立即删除该 run 的 lease；若
   supervisor 被强制终止而无法运行清理，watch 会在 5 秒无 heartbeat 后删除 stale lease；只有
   Host 的全部 lease 都失效时才退出。
7. IDE/AI 使用的 `flutter run --machine` 由一个窄 stdin gate 启动原 Flutter Tool。它不改写
   或缓冲 daemon stdout，仅透传解析与 Hot Restart 匹配的 response；它只延迟
   `app.restart`：watch 的 `completedInputRevision` 必须覆盖
   保存对应的 `inputRevision`，且成功状态经过短暂稳定窗口。Builder/Validator/aggregation
   失败会以标准 daemon error 返回有界诊断。Host topology 变化发布
   `hotRestartRequired: true`，普通 Hot Reload 会被拒绝，显式 Hot Restart 经 daemon
   `code=0` 确认后才解除当前 run session 的栅栏。IDE/AI 关闭父 stdin 时，gate 同步关闭
   原 Flutter Tool stdin，保留直接启动时的 EOF 退出语义。

Hook 不默认采集详细 profile。遇到慢生成时，在独立终端显式运行 `generate <host> --profile`
定位阶段耗时；性能 benchmark 或 AI 诊断也应显式传入该参数。

## DevEco/Hvigor 直接构建

DevEco Studio 或 `devecocli build` 直接执行 Hvigor，不进入上述 Flutter wrapper。OHOS Host
必须把 CCRouter preflight 放在 Flutter Hvigor `FlutterTask` 之前，而不是仅检查“是否存在
watch”后放行。推荐 task 使用 `ohos/local.properties` 解析到的 Flutter SDK 内置 Dart 执行：

```text
dart run --verbosity=error ccrouter_generator:ccrouter pub-hook run \
  --project-root <host-root> --pub-command build
```

该公开入口与 Flutter build preflight 语义一致：watch 不活跃时运行普通 one-shot，watch 活跃
时由普通 `generate` 等待并复用精确 cycle；只有生成、校验、watch 失败或证据不可用时才阻止
Hvigor 后续编译。不要传 `--no-cache`、`--profile` 或自定义 output，这些路径不能由 watch
证据满足。仓库 Demo 的可执行参考位于 `demo/ohos/ccrouter-preflight.js` 和
`demo/ohos/hvigorfile.ts`。`CCROUTER_DISABLE_HVIGOR_PREFLIGHT=1` 只用于单次恢复或 A/B；绕过后
调用者负责在构建前完成 Host generation check。

后台 watch 的权威锁、Host registration、Flutter-run lease 与 Analyzer CLI 写事务位于用户级 `CCROUTER_HOME`：macOS/Linux 默认
`~/.ccrouter`，Windows 默认 `%LOCALAPPDATA%\CCRouter`。canonical build root 与 Host 分别使用
完整 SHA-256 做两级隔离，并保存最小 Host/Builder session authority；
`.dart_tool/ccrouter/v1/watch/status.json` 继续作为 Analyzer/IDE 本地观察镜像。活动 watch 会重建
被删除的镜像，Pub Hook 优先读取 stable session，因此本地状态清理不会再变成 5 分钟等待或泛化
generation-lock 错误。planning cache、Portable State 与 build_runner Asset Graph 仍只在项目内。
启动发现仍被旧进程持有的 V1 owner lock 时会 fail-fast，需停止旧 watch 并重新安装 Pub Hook；
`CCROUTER_USE_LEGACY_DART_TOOL_LOCKS=1` 只用于短期 A/B，并会把 lease 恢复到 Host
`.dart_tool`、把 Analyzer operation lock/journal 恢复到 Pub owner `.dart_tool`；不支持新旧协议
并发。Analyzer `install/upgrade/uninstall` 按 canonical Workspace Pub owner 共享一把 operation
lock，未能安全回滚时保留逐字节 transaction journal；因此 `flutter clean` 不会解除活动事务锁
或删除恢复证据。
Wrapper 会在真正的 top-level `flutter clean` 前执行只读 clean guard。同 build root 存在活动
watch 时，clean 会 fail-fast，并提示先停止 `flutter run/watch` 后重试；guard 不会主动杀进程。
`--help`、未知全局 option 或参数值中的 `clean` 不会误触发。仅在明确恢复或 A/B 时设置
`CCROUTER_DISABLE_FLUTTER_CLEAN_GUARD=1` 单次绕过；它不保证 watch 能跨越被删除的
package config 或 build_runner Asset Graph 继续运行。
若通过未安装 wrapper、kill switch 或直接文件操作绕过 guard，watch 会对 build root 的 Pub
config/graph 与已建立的 Asset Graph 做 500ms 二次确认。持续缺失发布
`invalidatedByClean`，有界停止 child 并释放锁；恢复 Pub 状态后需要启动新 watch。Workspace
member 只删除自己的 `.dart_tool` 而共享 build root 仍完整时不会触发该失效。
不需要把 watch NDJSON
混入 Flutter Tool 的 machine stdout；另开终端读取即可：

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter watch status <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter watch follow <host-root>
```

`status` 显示活动状态、PID、轮次、coordination schema/path 和最近 Builder/聚合耗时；`follow` 只输出简洁状态变化，
完整诊断继续写入 `flutter-run.log`。状态文件是本地可观察性，不参与生成决策；写入失败仅警告，
不会阻断 direct watch 的生成锁、Builder、Validator、快照恢复或原子发布；但 Hook 无法取得
主 lease 或当前 watch PID 精确接纳其 lease 的 readiness proof 时会拒绝启动 Flutter。若 watch 被强制终止而来不及写入
`stopped`，只读命令会通过已释放的 owner lock 将遗留 `active` 记录显示为 `stale`；它不会
回写历史 `status.json`。

同一 resolved build root 的不同 Host 会共享一个 Builder owner，但每个 Hook 只读取自己 Host 的
lease/status/diagnostics 并等待自己的 aggregation。`status.json.pid` 是本 Host watch，
`builderOwnerPid` 可指向另一个 Host 的 owner 进程。owner 退出时活动 subscriber 会接管；手工
启动的同一 Host 重复 watch 会 fail-fast，不会同时写同一状态文件，而 Hook 管理的并行
`flutter run` 通过多 lease 接入现有 watch。可用
`CCROUTER_DISABLE_MULTI_HOST_WATCH=1` 恢复旧的单 watch ownership 路径做 A/B。

Workspace Validator 失败还会原子发布同目录的 `diagnostics.json`。它与 `status.json` 分开写入，
最多保留 100 条结构诊断，并绑定 Host/build root、`sessionId`、`cycle`、`eventRevision` 和当前
resolution fingerprint。成功、新 cycle 或 session restart 会发布空 snapshot 清除旧错误。
Analyzer Plugin 只在两份文件身份完全一致且 `cycleResolutionState=matched` 时显示 authored Dart
诊断。无活动 watch 的 Host one-shot 会另行发布 `generation/diagnostics.json`；Plugin 仅消费与当前
Pub resolution fingerprint 一致的终态，活动 watch 始终覆盖它。Pub 解析暂时落后于当前
`pubspec.yaml` editor overlay 时只提示先执行 Pub get，不推断缺失 Owner，恢复 overlay 会立即清除
提示。Analysis Server 通常不转发 `.dart_tool` 文件变化，插件使用 500ms 的有界 file-identity
polling，覆盖 context root 和 Workspace 内显式 Host，仅在输入变化时刷新受影响文件；它不运行
Generator 或创建独立 Analyzer graph。可用 `CCROUTER_DISABLE_ANALYZER_WATCH_BRIDGE=1` 关闭整个
Generator diagnostics bridge。diagnostics 写入或消费失败不会改变 Generator/Hook 的 fail-closed
结果，最终仍需 `--no-cache --check`。

`CCROUTER_ENABLE_ANALYZER_TIERED_POLL=1` 仅供框架维护者做规模 A/B。开启后，正常文件事件和
已经通过 `status.json`/`diagnostics.json` 双文件身份与 resolution 校验的成功 generation epoch
仍即时失效；exact-path 丢事件兜底分为 10 个 500ms shard，最坏完整审计周期从 500ms 放宽到
5 秒。默认继续逐 tick 完整检查 exact paths，实验模式不改变 Generator 或
`--no-cache --check` 的权威性。

watch 使用文件 stat 作为低成本唤醒信号，再以 exact-content fingerprint 确认 Pub resolution
变化；低频 exact scan 只作事件遗漏兜底，成功证据从不依赖 mtime。需要新 Analyzer graph 或
`--build-filter` 时发布 `sessionRestarting`，恢复当前 cycle 快照并在同一 lease 内启动新 child；
新 session 的 `aggregationSucceeded` 在 `ready` 前不能满足 Pub Hook。设置
`CCROUTER_DISABLE_WATCH_SESSION_RESTART=1` 后，这类变化会 fail closed，并提示停止 watch 后运行
one-shot，不会静默沿用旧 target 集合。
首次快照或 session 初始化失败也会先停止 child 并清理已取得的资源，再释放锁。
终止失败保留 `failed` 状态且 `active=false`，同时停止状态镜像修复 Timer，不发布成功的 `stopped`。

旧 child 的停止过程是有界的：SIGINT 最多 10 秒、SIGTERM 最多 5 秒，最后 SIGKILL 最多等待
5 秒。正常 child 仍有机会完成清理，忽略退出信号的 child 不会无限阻塞 session restart 或
generation lock 释放。

这不是对 Flutter Tool 内部隐式 `pub get` 的监听：即使 direct `dart pub` 已覆盖，Flutter Tool
仍可能在自身进程或 snapshot 内完成依赖解析。wrapper 不会修改 `shared.sh`、Dart snapshot 或
Flutter Tool 源码。`run/build` 的前置生成只保证
调用 Flutter 前当前已有依赖解析和生成物是最新的。

可以临时禁用全部 Flutter/Dart wrapper Hook，但仍保留原始命令行为：

```bash
CCROUTER_PUB_HOOK_DISABLE=1 flutter pub get
CCROUTER_PUB_HOOK_DISABLE=1 dart pub get
```

只禁用 watch、但仍执行 Hook 的方式是：

```bash
CCROUTER_DISABLE_BUILD_WATCH=1 flutter run
```

只关闭 machine Hot Reload 栅栏、保留 preflight 与后台 watch：

```bash
CCROUTER_DISABLE_HOT_RELOAD_GATE=1 flutter run --machine
```

只关闭 watch 启动握手、恢复旧的“后台进程启动后立即运行 Flutter”路径用于 A/B：

```bash
CCROUTER_DISABLE_WATCH_STARTUP_HANDSHAKE=1 flutter run
```

该开关不关闭 preflight、watch、generation lock、Validator、原子写入或 machine reload gate。

只在 Windows 回退到原有 batch 直接运行与末尾清理路径：

```bat
set CCROUTER_DISABLE_WINDOWS_RUN_SUPERVISOR=1
flutter run
```

该回退保留 preflight、watch 与启动握手，但不再提供 heartbeat 失活回收保证。

## 边界

- 覆盖 `flutter pub`、`flutter run`、`flutter build` 和平台支持的 direct `dart pub`。POSIX
  包装 inner Dart executable；Windows 只覆盖 `bin/dart.bat`，不覆盖 IDE 直接执行
  `cache/dart-sdk/bin/dart.exe`。也不监听 Flutter Tool 内部隐式 `pub get`。
- `flutter run` 自动持有 Host watch；同一 resolved build root 的不同 Host 共享一个 Builder
  owner，各自保留聚合与 Hook completion fence。`flutter build` 和成功的依赖操作仍最多触发
  一次生成。嵌套且可独立运行、拥有自己 Pub root 的 Package Host 使用独立 watch。
- reload gate 只覆盖 Flutter daemon 的 `--machine` `app.restart`，也就是 IDE 和自动化主路径。
  普通终端交互式 `r` 不经过该 gate，因为 shell wrapper 无法在不破坏 TTY、设备选择与信号
  语义的情况下安全接管按键；该场景先用 `watch follow` 等待成功，或使用 IDE Hot Reload。
- Flutter SDK 升级或 FVM 版本切换可能替换 `bin/flutter`，切换后应重新执行
  `status`，必要时对新 SDK 执行 `install`。
- Hook 会让 Flutter SDK Git 工作树包含受管 wrapper 和备份文件；执行 Flutter
  升级前应先 `uninstall`，升级后再对新 SDK 安装。不要把这些备份文件提交到
  Flutter SDK 仓库。
- Hook 不修改 `pubspec.yaml`、锁文件或生成物恢复策略；所有生成校验仍由
  `ccrouter generate` 负责。
- Hook 与同 Host watch 并发时最多等待 5 分钟；状态损坏、watch 退出、失败或超时均 fail-closed。
  不同 Host 即使共享 build root，也不会互相冒认完成轮次。
- 安装是显式操作，不应在项目初始化、CI 或普通 `pub get` 中隐式修改 SDK。

### Workspace 聚合根

在 Workspace 聚合根显式执行 hooked `flutter pub get` 时，resolved Package config 可能同时
包含 `ccrouter` 与 `ccrouter_generator`。Hook 不能只凭完整解析图判断当前 Package 是 Host；
它还会验证当前 `pubspec.yaml` 是否直接声明 `ccrouter`。聚合根不满足该条件时会输出：

```text
CCRouter pub hook skipped: current Package does not directly depend on ccrouter
(Workspace aggregators are not Hosts).
```

跳过会保留原始 Pub 成功结果，也不会猜测某个 Workspace 成员作为 Host。真实 Host 或显式使用
CCRouter 的组件 Package 仍以自身目录为根触发生成；`flutter run/build` 应始终从实际 Flutter
Host 执行 fail-closed preflight。

## 验证

安装后在实际 CCRouter Host Package（本仓库为 `demo/`）执行：

```bash
cd demo
flutter pub get
```

控制台应看到 `CCRouter post-pub generation started`、精简的验证/耗时摘要以及
`CCRouter post-pub generation finished: elapsed=...ms`。随后可以用：

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <host-root> --check
```

执行 `flutter run` 或 `flutter build macos` 时，若项目已经完成依赖解析，控制台会输出
`CCRouter preflight started/finished`；生成失败时输出有界的最近 Generator 诊断且 Flutter
命令不会继续执行。`flutter run` 还会输出 watch 的状态文件与日志路径；保存源码后可用
`ccrouter watch follow <host-root>` 等待下一次成功状态。`ccrouter pub-hook status` 会额外显示
`run/build preflight: enabled`、`run watch: enabled` 和
`machine reload gate: enabled`。升级 SDK 或使用新的 FVM 版本后，如果状态显示
`missing`，先卸载旧 wrapper 再重新安装，避免旧入口继续绕过前置生成。

确认 hook 产生的结果已经通过只读一致性检查。
