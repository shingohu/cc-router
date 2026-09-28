# CCRouter Pub Hook

## 目的

`ccrouter pub-hook` 为当前 Flutter SDK 安装一个可回滚的 `flutter` wrapper。
当 `flutter pub get`、`upgrade`、`downgrade`、`add` 或 `remove` 成功后，wrapper
会检查当前项目的 `.dart_tool/package_config.json`：只有同时解析到 `ccrouter`
和 `ccrouter_generator` 时，才运行一次：

```bash
dart run ccrouter_generator:ccrouter generate <project-root> --profile
```

因此普通 Flutter 项目不会触发生成，也不会因为没有 CCRouter 依赖而报错。

## 安装

从项目或 Workspace 根目录执行：

```bash
fvm dart run ccrouter_generator:ccrouter pub-hook install
```

默认按 `FLUTTER_ROOT`、当前目录向上的 `.fvm/flutter_sdk`、PATH 中的 `flutter`
顺序解析。也可以明确指定一个 SDK：

```bash
fvm dart run ccrouter_generator:ccrouter pub-hook install \
  --sdk /Users/shingo/fvm/versions/3.41.9
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
fvm dart run ccrouter_generator:ccrouter pub-hook status
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
fvm dart run ccrouter_generator:ccrouter pub-hook uninstall
```

卸载会恢复原始入口。若发现 marker、wrapper 或备份文件不完整，命令会拒绝删除
入口并报告错误，避免破坏 SDK。

## 执行语义

1. 先完整执行原始 `flutter pub`。
2. 原始命令失败时，直接返回原始退出码，不运行生成器。
3. 原始命令成功后，wrapper 查找 `--directory`/`-C` 指定的项目并向上定位
   `pubspec.yaml`。
4. 没有 resolved Package config，或没有同时解析 `ccrouter` 与
   `ccrouter_generator` 时，打印跳过原因并返回成功。
5. 生成器失败时打印生成日志和最终耗时，并返回非零，使 CI 能发现生成物过期或
   元数据错误。

## `run` / `build` 前置生成

当前 wrapper 还覆盖 `flutter run` 和 `flutter build`。它会在调用原始 Flutter
入口前执行一次生成：

1. POSIX/Windows wrapper 会在全局 Flutter 参数之后定位 `pub`、`run` 或 `build` 命令；
   因此 `flutter --no-color run` 不会绕过 Hook。
2. `run`/`build` 使用当前目录（以及兼容的 `--directory`/`-C`）向上定位项目，只有
   同时解析 `ccrouter` 和 `ccrouter_generator` 的 resolved Package config 才运行生成。
3. 生成器使用自身的内容 fingerprint fast path；没有变化时只做有界校验，不重复运行完整
   Builder。并发调用仍由生成锁串行化。
4. 预生成失败会阻止原始 `flutter run/build`，避免启动或 Release 构建消费陈旧生成物。
5. 没有 Package config、普通 Flutter 项目或还未完成首次 `pub get` 时安全跳过；后续
   `flutter pub get` 成功后会执行一次正常的 post-pub 生成。

这不是对 Flutter Tool 内部隐式 `pub get` 的监听：wrapper 无法可靠观察内部 Dart 调用，
也不会修改 `shared.sh`、Dart snapshot 或 Flutter Tool 源码。`run/build` 的前置生成只保证
调用 Flutter 前当前已有依赖解析和生成物是最新的。

可以临时禁用 hook，但仍保留原始 `flutter` 行为：

```bash
CCROUTER_PUB_HOOK_DISABLE=1 flutter pub get
```

## 边界

- 覆盖 `flutter pub`、`flutter run` 和 `flutter build`，但不覆盖直接执行的 `dart pub`，
  也不监听 Flutter Tool 内部隐式 `pub get`。
- 当前不提供常驻 `watch` 进程；每次成功的依赖操作最多触发一次生成。
- Flutter SDK 升级或 FVM 版本切换可能替换 `bin/flutter`，切换后应重新执行
  `status`，必要时对新 SDK 执行 `install`。
- Hook 会让 Flutter SDK Git 工作树包含受管 wrapper 和备份文件；执行 Flutter
  升级前应先 `uninstall`，升级后再对新 SDK 安装。不要把这些备份文件提交到
  Flutter SDK 仓库。
- Hook 不修改 `pubspec.yaml`、锁文件或生成物恢复策略；所有生成校验仍由
  `ccrouter generate` 负责。
- 安装是显式操作，不应在项目初始化、CI 或普通 `pub get` 中隐式修改 SDK。

## 验证

安装后在 CCRouter 项目执行：

```bash
flutter pub get
```

控制台应看到 `CCRouter pub hook started`、生成阶段日志以及
`CCRouter pub hook finished: ... elapsed=...ms`。随后可以用：

```bash
fvm dart run ccrouter_generator:ccrouter generate <host-root> --check
```

执行 `flutter run` 或 `flutter build macos` 时，若项目已经完成依赖解析，控制台会先输出
同一套生成日志；生成失败时 Flutter 命令不会继续执行。`ccrouter pub-hook status` 会额外
显示 `run/build preflight: enabled`。升级 SDK 或使用新的 FVM 版本后，如果状态显示
`missing`，先卸载旧 wrapper 再重新安装，避免旧入口继续绕过前置生成。

确认 hook 产生的结果已经通过只读一致性检查。
