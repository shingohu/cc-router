# build_runner 2.16.1 工具链升级与验证

2026-11-17 的 Plugin 语义触发修复与跨版本契约测试单列在
[后续验证记录](20261117-generator-plugin-followup/report.md)；以下数字保留原 SDK 升级轮次语境。

日期：2026-11-05（目标 SDK 复验）；基线：`b07d9313ba48c2a2b7ed1378116c58d6c2e9d9f8`。
分支：`codex/build-runner-2161`。本轮只在独立 worktree 和临时夹具实施；未合并、推送、
发布或修改共享 SDK / Pub 包内容。目标 SDK 已固定为官方 upstream Flutter 3.47.9；候选实现与下述验证已完成。
严格全仓分析仍有 3 条 warning，旧 OHOS SDK 的依赖解析不兼容仍是分发限制，不能将本分支标记为全平台发布完成。

## 1. 原始问题与报告来源

原分析报告见 [build_runner_incremental_20261104.md](build_runner_incremental_20261104.md)。
用户提供的原路径位于另一个 worktree；实施时该目录已经清空，同名文件及可访问 Git snapshot
均未找到。本分支按前一轮实际读取的完整文本恢复该报告，不将本轮新结论写进原诊断记录，
也不宣称已校验与已消失文件的字节哈希。

原报告以 stock 最小工程证明：保留 build_runner 2.15.1 的旧图，同时合入新增输入和预生成
输出，可能将输出误分为 source，导致空值异常。上游 [#5079](https://github.com/dart-lang/build/issues/5079)
的案例是循环等待；共同根因是分类错误，不是相同异常堆栈。
[2.16.1 changelog](https://pub.dev/packages/build_runner/versions/2.16.1/changelog)
明确修复该问题。2.15.2/2.15.3 不包含这项修复。

原报告说 Dart 3.11.5 满足 Analyzer SDK 条件，这一点成立，但不足以判断整个 Flutter 图能解析：
本轮实际 Pub 证明还有 Flutter 的 `meta` pin 冲突，见下一节。

## 2. 依赖与 SDK 决策

| 项目 | 基线 | 本分支解析值 / 约束 |
| --- | --- | --- |
| build_runner | 2.15.1 / ^2.10.0 | 2.16.1，Workspace 精确锁定 |
| analyzer（Generator） | 10.0.1 / ^10.0.0 | 13.3.0 / ^13.3.0 |
| build | 4.0.7 / ^4.0.0 | 4.0.11 / ^4.0.9 |
| dart_style | 3.1.7 / ^3.1.7 | 3.1.14 / ^3.1.14 |
| source_gen | 4.2.4 | 4.2.4，保持原约束 |
| build_config | 1.3.3 | 1.3.3 |
| build_test | 3.5.16 | 3.5.20，与 runner 2.16.1 配套 |
| meta | 1.17.0 | 1.19.0，标准 SDK 允许的正常解析 |
| 根与 Demo FVM | 默认/显式旧 OHOS SDK | 官方 Flutter 3.47.9 / Dart 3.13.7 |
| Generator / 根 SDK 声明 | ^3.10.0 | ^3.11.0 |
| Runtime / Contracts / 独立 IDE Plugin | 原约束 | 不提高其 SDK / Analyzer 约束 |

SDK 核验：

- OHOS `oh-3.41.9-release` 实际 Flutter `3.41.10-ohos-1.0.0` / Dart 3.11.5，
  Flutter 固定 `meta 1.17.0`；实际 Pub 解算失败。
- 已安装标准 Flutter 3.44.9 固定 `meta 1.18.0`，仍低于 Analyzer 的 `^1.18.3`。
- 官方 Flutter 3.47.9 的 Flutter 依赖允许 `meta ^1.18.3`，本分支在该 SDK 上解析成功。
  Framework revision：`d3b14c876900e553bc736ca19295fc09e3853e8e`；
  engine：`89c39edfdfae2949f6806e4a315c0c08522238b7`；Dart 3.13.7。

选择 2.16.1 而非 2.17.1：后者要求 build 5 / build_config 1.4 / Analyzer >=14.3，
与当前 CCRouter 和 FlutterGen 5.15.0 的 build 4 图不兼容。保持 build 4 能限制迁移范围。
也不通过生产 dependency_overrides 强压 Analyzer/meta，不改共享 Pub 包和 SDK 源码。

**OHOS 发布边界：** 本分支不能用旧 OHOS SDK 解析，目录和旧 Runtime 对照测试存在不等于
新 Generator 支持 OHOS。需要具备兼容 meta 依赖的 OHOS SDK 并重新验证；本分支不能直接
作为原生产 OHOS 工程的可用升级包。回退应回退整组 manifest/lock/SDK/生成物，不混用缓存。

## 3. 实现与回归发现

### Analyzer、Builder 与常量

- 将 NamedExpression 迁移到 NamedArgument，ArgumentList 迁移到 NodeList<Argument>。
- Command/Event 静态类型检查读取 argumentExpression，保留禁止绕过生成 Client 的校验。
- ExtensionType 名称改用 namePart；FunctionType 判断替代已弃用的参数子结构访问。
- Dart 3.13 将 Duration 常量 backing field 改为 inMicroseconds；InitTask 同时兼容旧
  `_duration` 与新字段，继续拒绝未知、零或负值，不将读不到常量解释为无 timeout。
- build_test 3.5.16 虽允许解析 runner 2.16.1，但实际使用私有 API 导致编译错误；
  改为上游与 2.16.1 对应的 3.5.20，不使用 overrides。

### watch、输出保护与诊断

2.16 默认修复磁盘上修改的生成物。当 CCRouter 恢复非目标 Package 产物时，这会导致
repair/delete/restore 持续循环。新增 idle watch 回归在修复前失败（静置期间轮次 6 → 8），
修复后通过。watch 使用上游公开 `--keep-modified-outputs` 保持旧策略；one-shot 保持新版
默认修复行为，#5079 分类修复仍然有效。

启动时先完成回滚基线再创建子进程；结束时先有界停止子进程，再恢复非目标产物。
启动失败也恢复最后完整基线。若特定文件不可读，保留该文件和原始失败诊断，恢复其他受管
输出，不据此返回成功。无法确认子进程已退出时不与它竞争恢复写入。
非目标恢复在读字节前排除目标作用域，避免目标文件的权限故障阻止其他 Package 恢复。
新增/补强测试比较非目标字节、失败后全局产物集合及子进程退出。

Profile 兼容上游新增的 `fixed` counter：可选 `fixedOutputs` 字段保留在 schema 2 的
phase/totals 中，独立于 outputs/sameOutputs，计入 executedInputs。不影响生成或缓存决定。
未知计数继续保留为原始诊断，不能吞掉失败。

### Flutter SDK 适配

标准 Flutter 3.47 会在 NavigatorObserver.didPop 之前调用 onDidRemovePage。原回调过早
按 null 移除 Entry，导致 11 项既有 typed Pop / renderer remount 测试失败。
现在两个入口复用 Route.popped 的真实结果，并用现有 pending 标记避免重复处理。
旧 SDK 回调顺序同样有效，不扩大业务 API。

每个 Managed Navigator 添加独立 Semantics container，避免同帧跨父节点重挂载后继续使用
旧的合并语义几何关系。保留可访问性内容；既有 Demo 折叠/展开、双 Pane 测试保留全部断言。
该边界属于 renderer，不重建业务 Entry/Scope，也不持有额外长期资源。

### 独立脚手架与测试隔离

标准 SDK 的 app 模板预置 lockfile 使用 meta 1.18.3，而父组件首次解析到 1.19.0；
Portable State 正确拒绝该 toolMismatch。真实独立消费测试按已有文档在 Example 执行
`flutter pub upgrade --offline` 对齐工具解算，再生成和运行；没有放宽校验。
新的非目标产物测试在 teardown 恢复其夹具，避免 Package-local 生成的测试 Index 泄漏到
之后验证“Host 不生成无关 Package Index”的测试。

## 4. 可复现命令与验证记录

不含 CCRouter 的 stock A/B（所有状态在独立临时目录）：

```sh
python3 docs/validation/20261104-build-runner-upgrade/incremental_probe.py \
  --dart /absolute/path/to/selected/flutter/bin/cache/dart-sdk/bin/dart
```

官方 Flutter 3.47.9 / Dart 3.13.7 下，2.15.1 首次构建为 0、增量为 255（空值断言 / _writeBuildOutput）；
2.16.1 首次、相同增量、重复构建均为 0。此前 3.47.2 / Dart 3.13.2 的 A/B 结果相同。脚本保留对应临时目录和日志供核查。

当前推荐的仓库门禁（从仓库根目录使用选定 SDK 执行，不能拿根 Pub 成功替代 Host 生成）：

```sh
CCROUTER_PUB_HOOK_DISABLE=1 fvm flutter pub get
fvm dart analyze packages
fvm dart analyze tool
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test
fvm flutter test --no-pub packages/ccrouter_test/test
fvm flutter test --no-pub demo/test
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --no-cache --check
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo/modules/order/example --no-cache --check
```

独立 Plugin 的分析和测试另从其 Package 目录执行：

```sh
(
  cd packages/ccrouter_analyzer_plugin &&
    fvm dart analyze &&
    fvm dart test --concurrency=1
)
```

根目录的 `fvm dart analyze` 会进入 Demo legacy Plugin bootstrap，不是聚合门禁。
本报告下文及原始日志保留其实际失败结果；更新当前推荐命令不将历史失败改记为成功。

- 3.47.2 首轮发现 Builder、Duration 和 watch 问题后重新跑 Generator 全量为 **722 通过、
  3 失败、1 跳过**；三项分别为启动快照恢复、脚手架独立解算、非目标测试 Index 残留。
  三项均已修复，并在最终 worktree 复验通过；没有将这次全量运行改称“一次全绿”。
  远端安装 smoke 仍按既有开关跳过，不将 fixture/本地 smoke 冒充远端发布验证。
- 官方 3.47.9 最终 worktree：Generator **725 项通过、1 项跳过、0 项失败**；框架 **1650 项通过**，
  Demo **117 项通过**；包含 Pop 与 Semantics 修复。完整 3.47.9 日志见证据目录的 `upstream-3479-*`。
  首次标准 SDK 运行的 11 项 Pop 失败和 2 项 Semantics 失败保留为 RED 证据，不删断言。
- watch 扩大运行中曾与隔离副本的试验源码写入重叠，2 项触发输入一致性/产物差异断言，
  该次运行为 27 通过、2 失败。源码固定后，启动恢复、idle、mid-cycle 和文件增删改四项
  串行复验全部通过；最终 worktree 的启动恢复和 idle 两项再次通过。
- 最终 worktree：脚手架真实独立消费 1 项、回滚/自定义输出/profile counter 9 项、
  Host 不生成无关 Package Index 的隔离测试 1 项，全部通过。
- 最终 worktree：普通 cached check、Demo no-cache check、独立 Example no-cache check 均通过。
  显式 portable prepare 重生成 **9 份**已选择 portable 的 Demo/组件状态。
  后续 Review 发现工作区仍有旧指纹，且该次记录未验证 Package-local publish；
  此项不能证明最终状态已可分发。重新 prepare 与逐入口 publish 的修复验收见
  [后续记录](20261117-generator-plugin-followup/report.md#再次-review静态分析portable-state-与证据脱敏)。
- 旧 OHOS SDK + 旧依赖图：最终 Runtime（含 Pop/Semantics 修复）框架全量 1650 项、
  Demo 全量 117 项通过。此前 Pop 专项 162 项也通过。这不是新 Generator 依赖在旧
  OHOS SDK 解析成功的证据。
- 冷副本不带 .dart_tool：Pub、Demo 与独立 Example 正式生成及两条 no-cache check 通过。
  最后将源码对齐至最终 worktree，重新生成 portable 状态；全部 **109 个** Demo/模块/Example
  受管文件逐字节一致（含 Portable State），差异为 0。
- 独立副本加入与生产工程同版本 FlutterGen 5.15.0：正常 Pub 解算、Workspace 全量构建、
  新增资源后的增量构建、CCRouter 正式生成、no-cache check、再次 Workspace 构建均通过；
  资源 API 在 CCRouter 生成前后和重复构建之间字节一致。没有迁移原生产工程依赖或缓存。
- Profile fixed counter RED/GREEN：新增用例修复前失败，修复后 6 项通过。
- 官方 3.47.9 下 Generator 单包 analyze 无问题，Plugin 在独立目录执行 pub get 后 analyze 无问题、
  212 项测试通过。全仓严格 analyze 退出 2：legacy Plugin 弃用 warning，
  以及未改动 Core/navigation.dart 两处 unawaited_return_in_try_block warning；没有把它写成
  静态分析全绿。首次还遇到插件 bootstrap 的 SSH publickey 拉取失败；只为复验进程设置
  Git HTTPS insteadOf 后，该错误消失，没有改 pin、全局 Git 配置或清插件缓存。
  后续局部记录 Core 两处异步错误归属并豁免该 lint，CI 的 `fvm dart analyze packages`
  已通过；不将原来失败的全仓命令改记为成功。
- 独立 Analyzer Plugin 在自己的 Package 工作目录使用新标准 SDK：Pub、analyze 成功，
  212 项测试通过，包含真实 Legacy/LSP Server、诊断和 Quick Fix。未改版本或远端 pin，
  这些测试不证明桌面 IDE 当前会话已重启加载。
- Pure Dart 最低消费者另用 Dart 3.11.5：独立 Pub、Service Contract 生成、no-cache check
  和 analyze 全部成功。它没有 Flutter SDK 依赖，不受 Flutter meta pin 影响；不代表
  Flutter Host / Runtime 的全部最低版本矩阵已完成。
- 生命周期检查覆盖 startup failure、watch stop/ownership、Renderer remount、Scope、旧回调
  与 GC 既有回归；尚未做原生 heap / 长时间 RSS / 真机手势性能测试。

[证据目录](20261104-build-runner-upgrade/)保留全量 Generator 的原失败记录、最终门禁
结果、关键 RED/GREEN、stock A/B、109 文件 SHA-256 对照和生产源码指纹。
完整本机日志另位于 `/tmp/ccrouter-build-runner-2161-validation/`。不提交构建缓存、SDK、
Pub cache、临时 fixture 或生产应用数据。日志中的部分绝对前缀替换为 `<worktree>` / `<pub-cache>`。

## 5. 完成与分发边界

本轮不改独立 Analyzer Plugin 8.4.0 / analyzer_plugin 0.13.10 和 Demo 的远端 Plugin pin；
因此没有触发 Plugin 两阶段推送及 pin 更新流程。IDE 的旧插件弃用提示与本次 Generator
Analyzer 13 是不同依赖图。

需要以当前工具链重新生成和分发 Portable State，再更新消费者。源码只合入依赖修改并不能
证明外部组件分发已完成。尚未验证原生产 Host、原生 Android/iOS/macOS/Web/OHOS 安装构建、
DevTools Extension Web 构建、Flutter 最低 SDK 独立消费者、Windows/Linux 或桌面 IDE 当前会话。
这些边界不由 Widget/Generator 测试替代；本分支不自动合并或推送。
