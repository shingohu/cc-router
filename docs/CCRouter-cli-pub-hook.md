# CCRouter Pub Hook

> 文档状态：当前已实现行为。Hook 是显式安装、可回滚的本地开发工具，不是 Flutter 官方
> 生命周期扩展点，也不是正式发布或 CI 的替代品。

## 目的

`ccrouter pub-hook` 为当前 Flutter SDK 安装一个可回滚的 `flutter` wrapper。
当 `flutter pub get`、`upgrade`、`downgrade`、`add` 或 `remove` 成功后，wrapper
会检查当前项目自己的 `pubspec.yaml` 和 `.dart_tool/package_config.json`：只有当前
Package 直接声明 `ccrouter`，并且解析图同时包含 `ccrouter` 与
`ccrouter_generator` 时，才运行一次：

```bash
dart run --verbosity=error ccrouter_generator:ccrouter generate <project-root>
```

因此普通 Flutter 项目和仅聚合成员的 Workspace 根不会触发生成，也不会因为没有
CCRouter Host 依赖而报错。

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

每一个 FVM 版本都是独立 SDK，必须分别安装。安装只改动该 SDK 的 `bin/flutter`
和 `bin/flutter.bat`，原文件会保存为：

```text
bin/flutter.ccrouter-original
bin/flutter.ccrouter-original.bat
bin/.ccrouter_pub_hook.json
```

不会修改 Flutter 的 `shared.sh`、Dart snapshot 或 Flutter 工具源码。

## 状态与卸载

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook status
```

`status` 会打印实际解析到的 SDK 绝对路径、marker、POSIX/Windows wrapper 与备份
文件路径，并校验 wrapper 内容是否仍然是 CCRouter wrapper。只有显示
`installed and verified` 时返回码才为 0；SDK 被升级覆盖或文件不完整时会显示
`not installed or inconsistent` 并返回非零。

例如：

```text
CCRouter pub hook SDK: /path/to/flutter-sdk
  marker: /path/to/flutter-sdk/bin/.ccrouter_pub_hook.json (valid)
  POSIX wrapper: /path/to/flutter-sdk/bin/flutter (verified)
  POSIX backup: /path/to/flutter-sdk/bin/flutter.ccrouter-original (present)
CCRouter pub hook result: installed and verified
```

卸载命令：

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook uninstall
```

卸载会恢复原始入口。若发现 marker、wrapper 或备份文件不完整，命令会拒绝删除
入口并报告错误，避免破坏 SDK。

## 执行语义

1. 先完整执行原始 `flutter pub`。
2. 原始命令失败时，直接返回原始退出码，不运行生成器。
3. 原始命令成功后，wrapper 查找 `--directory`/`-C` 指定的项目并向上定位
   `pubspec.yaml`。
4. 没有 resolved Package config、当前 Package 没有直接声明 `ccrouter`，或解析图没有
   同时包含 `ccrouter` 与 `ccrouter_generator` 时，打印跳过原因并返回成功。
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
6. 成功时只打印 fast-path、验证摘要和总耗时；生成器失败时打印最近
   200 行且最多 64 KiB 的有界日志并返回非零，使 CI 能发现生成物过期或元数据错误，
   同时避免长时间 Builder 输出造成控制台刷屏或内存无界增长。

所有推荐命令都给 `dart run` 传入 `--verbosity=error`。它只压低 Dart/Pub 在 CLI
启动前输出的重复依赖解析和 executable 构建信息，不会隐藏 CCRouter 的阶段、耗时、
跳过原因、标准错误或非零退出码。直接省略该参数仍可运行，但冷启动或依赖变化后可能
看到多次 `Resolving dependencies`。

Wrapper 会先完整执行原始 Pub 命令，但 `--help`、`-h`、`--dry-run` 和 `-n` 只保留原始
命令语义，不触发 CCRouter post-pub generation。真实依赖写操作使用调用 Package 作为
`requestedRoot`，使用 Pub Workspace reference 验证后的根作为 `resolutionRoot`；两者不能
通过向上找到任意 `package_config.json` 来混为一谈。

`CCROUTER_DISABLE_PUB_HOOK_WATCH_FAILURE_FENCE=1` 仅用于 A/B 或紧急回退：它关闭等待基线后的
terminal failure 快速栅栏，恢复旧的 fingerprint-only 失败判断与有界超时。该开关不放宽成功
条件，也不关闭 watch、generation lock、Validator、原子写入或最终 `--no-cache --check` 门禁。

## `run` / `build` 前置生成

当前 wrapper 还覆盖 `flutter run` 和 `flutter build`。两者都会在调用原始 Flutter
入口前执行一次生成；`run` 在成功后额外持有 watch lease：

1. POSIX/Windows wrapper 会在全局 Flutter 参数之后定位 `pub`、`run` 或 `build` 命令；
   因此 `flutter --no-color run` 不会绕过 Hook。
2. `run`/`build` 使用当前目录（以及兼容的 `--directory`/`-C`）向上定位项目，只有
   同时解析 `ccrouter` 和 `ccrouter_generator` 的 resolved Package config 才运行生成。
3. 生成器使用自身的内容 fingerprint fast path；没有变化时只做有界校验，不重复运行完整
   Builder。并发调用仍由生成锁串行化。
4. 预生成失败会阻止原始 `flutter run/build`，避免启动或 Release 构建消费陈旧生成物。
5. 没有 Package config、普通 Flutter 项目或还未完成首次 `pub get` 时安全跳过；后续
   `flutter pub get` 成功后会执行一次正常的 post-pub 生成。
6. `flutter run` 的 preflight 成功后，wrapper 在后台启动
   `generate <host> --watch=auto --machine`，日志写到
   `.dart_tool/ccrouter/v1/watch/flutter-run.log`；原始 Flutter 进程退出时删除 lease 并终止
   watch。wrapper 不把进程 fork 当作启动成功：它等待同一 lease 的 `sessionReady`，并确认
   build root owner lock 仍被持有，随后才启动原 Flutter Tool。Dart/AOT 入口 30 秒内没有
   匹配状态，或初始 Builder/aggregation 5 分钟内没有到达 `ready`，都会 fail-closed。
   `watch starting` 和 `watch ready` 写 stdout，真实失败与完整日志路径写 stderr。
   `flutter build` 不启动常驻进程。
7. IDE/AI 使用的 `flutter run --machine` 由一个窄 stdin gate 启动原 Flutter Tool。它不改写
   或缓冲 daemon stdout，仅透传解析与 Hot Restart 匹配的 response；它只延迟
   `app.restart`：watch 的 `completedInputRevision` 必须覆盖
   保存对应的 `inputRevision`，且成功状态经过短暂稳定窗口。Builder/Validator/aggregation
   失败会以标准 daemon error 返回有界诊断。Host topology 变化发布
   `hotRestartRequired: true`，普通 Hot Reload 会被拒绝，显式 Hot Restart 经 daemon
   `code=0` 确认后才解除当前 run session 的栅栏。

Hook 不默认采集详细 profile。遇到慢生成时，在独立终端显式运行 `generate <host> --profile`
定位阶段耗时；性能 benchmark 或 AI 诊断也应显式传入该参数。

后台 watch 会原子维护 `.dart_tool/ccrouter/v1/watch/status.json`。不需要把 watch NDJSON
混入 Flutter Tool 的 machine stdout；另开终端读取即可：

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter watch status <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter watch follow <host-root>
```

`status` 显示活动状态、PID、轮次和最近 Builder/聚合耗时；`follow` 只输出简洁状态变化，
完整诊断继续写入 `flutter-run.log`。状态文件是本地可观察性，不参与生成决策；写入失败仅警告，
不会阻断 direct watch 的生成锁、Builder、Validator、快照恢复或原子发布；但 Hook 无法取得
同一 lease 的 readiness proof 时会拒绝启动 Flutter。若 watch 被强制终止而来不及写入
`stopped`，只读命令会通过已释放的 owner lock 将遗留 `active` 记录显示为 `stale`；它不会
回写历史 `status.json`。

同一 resolved build root 的不同 Host 会共享一个 Builder owner，但每个 Hook 只读取自己 Host 的
lease/status/diagnostics 并等待自己的 aggregation。`status.json.pid` 是本 Host watch，
`builderOwnerPid` 可指向另一个 Host 的 owner 进程。owner 退出时活动 subscriber 会接管；同一
Host 的重复 watch 会 fail-fast，不会同时写同一状态文件。可用
`CCROUTER_DISABLE_MULTI_HOST_WATCH=1` 恢复旧的单 watch ownership 路径做 A/B。

Workspace Validator 失败还会原子发布同目录的 `diagnostics.json`。它与 `status.json` 分开写入，
最多保留 100 条结构诊断，并绑定 Host/build root、`sessionId`、`cycle`、`eventRevision` 和当前
resolution fingerprint。成功、新 cycle 或 session restart 会发布空 snapshot 清除旧错误。
Analyzer Plugin 只在两份文件身份完全一致且 `cycleResolutionState=matched` 时显示 authored Dart
诊断；Pub 解析暂时落后于 `pubspec.yaml` 时只提示先执行 Pub get，不推断缺失 Owner。
Analysis Server 通常不转发 `.dart_tool` 文件变化，插件使用 500ms 的有界 file-identity polling，
仅在输入变化时刷新受影响文件；它不运行 Generator 或创建独立 Analyzer graph。可用
`CCROUTER_DISABLE_ANALYZER_WATCH_BRIDGE=1` 关闭该 IDE bridge。diagnostics 写入或消费失败不会改变
Generator/Hook 的 fail-closed 结果，最终仍需 `--no-cache --check`。

watch 使用文件 stat 作为低成本唤醒信号，再以 exact-content fingerprint 确认 Pub resolution
变化；低频 exact scan 只作事件遗漏兜底，成功证据从不依赖 mtime。需要新 Analyzer graph 或
`--build-filter` 时发布 `sessionRestarting`，恢复当前 cycle 快照并在同一 lease 内启动新 child；
新 session 的 `aggregationSucceeded` 在 `ready` 前不能满足 Pub Hook。设置
`CCROUTER_DISABLE_WATCH_SESSION_RESTART=1` 后，这类变化会 fail closed，并提示停止 watch 后运行
one-shot，不会静默沿用旧 target 集合。

这不是对 Flutter Tool 内部隐式 `pub get` 的监听：wrapper 无法可靠观察内部 Dart 调用，
也不会修改 `shared.sh`、Dart snapshot 或 Flutter Tool 源码。`run/build` 的前置生成只保证
调用 Flutter 前当前已有依赖解析和生成物是最新的。

可以临时禁用 hook，但仍保留原始 `flutter` 行为：

```bash
CCROUTER_PUB_HOOK_DISABLE=1 flutter pub get
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

## 边界

- 覆盖 `flutter pub`、`flutter run` 和 `flutter build`，但不覆盖直接执行的 `dart pub`，
  也不监听 Flutter Tool 内部隐式 `pub get`。
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
