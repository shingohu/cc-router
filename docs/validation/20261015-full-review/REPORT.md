# CCRouter 完整审查与回归报告（2026-10-15）

结论：**暂不建议直接放行 main 的 Watch 可靠性，也不建议直接合并 predictive-back 分支。** 本轮确认 main/共用代码 1 项 P1，predictive-back 新代码 1 项 P1、1 项 P2；其余失败中已区分 SDK 不兼容、测试运行环境及负载超时。原工作区的生产代码、测试和用户文档均未由本次审查修改，候选修正只在隔离副本验证。

## 1. 审查对象与边界

| 对象 | 冻结状态 | 范围 |
| --- | --- | --- |
| main | `7cdf3820ff6aed8260d26d1d2c62736809f9a789`，与审查开始时 origin/main 一致 | 近期提交 `0649797^..main`：239 文件、12,428 行新增、953 行删除；重点框架与 Generator 行为，图标等二进制资源通过平台构建校验 |
| predictive-back | 开始时 HEAD 为 `cd03e48f75585c91c6118ddb9d11421f3f8b7b1f` 加未提交修改；审查期间提交为 `1f7ce27a42b565cf25ad750618a82e68864cb8ee` | 已逐文件校验：新提交内容与测试快照完全相同。相对共同祖先 34 文件、3,192 行新增、49 行删除 |
| combined | main 加 predictive 改动的临时合并副本 | 保留 main 的 3 处等价测试 fixture；分阶段加入 SDK 兼容候选、手势候选修正，并分别记录结果 |

实际未合入分支只有 `codex/predictive-back`，当前有 1 个独有提交。它缺少 main 的 UI Fragment 三个提交；`codex/typed-ui-fragment`、`codex/host-lifecycle-boundary` 已合入，不重复当成待合分支。

本轮遵循 framework、integration、CLI 三项仓库 Skill，并按 memory/lifecycle reference 检查资源所有权及异常终止。重点包括 Host/business API 隔离、UI Fragment Props/Key/Session/unmount、Route family、predictive start/cancel/commit、Scope/result 完成、Generator 原子性/缓存/并发/Watch/Hook，以及 Analyzer 真实服务器及 Demo pin。

主线原有未跟踪文件保留：

- `docs/CCRouter-predictive-back-assessment.md`
- `docs/validation/ccrouter_predictive_back_route_hooks_20261015.dart.txt`

## 2. 确认的问题

### F1 · P1 · main 与 predictive 共用：首次快照异常会遗留 build_runner 子进程

- 位置：`packages/ccrouter_generator/bin/src/generation_watch.dart:782–784`；真正的 session `try/finally` 到约 900 行才开始。
- 触发：Watch 已创建 build_runner、监听器、订阅和 Timer 后，首次 `_GeneratedArtifactsSnapshot.capture` 读取生成文件发生 IO 异常。
- 根因：首次快照在清理保护区外。异常直接穿透 session；外层 owner 释放生成锁/lease，但没有对 `activeProcess` 做退出兜底。
- 影响：CLI 退出后 build_runner 仍可存活、写入生成文件；新的 generation 可以取得已经释放的锁，破坏单一写入者约束。生命周期分类：**not-disposed（拥有的子进程）**。
- 复现：在隔离 main 启动真实 `generate demo --watch=auto --machine`，收到 `watchStarted` 后将一个生成文件设为不可读。CLI 以 255 退出并发布 `stopped`；`ps` 捕获 build_runner PID 80522、PPID 1、PGID 80451 仍存活。复现脚本在 finally 恢复权限并清理其自行启动的进程组。
- 证据：[异常日志](evidence/watch-snapshot-probe.log)、[退出及孤儿进程快照](evidence/watch-snapshot-probe.json)、[原始复现脚本](evidence/watch_probe.py)。
- 归因：该 try/finally 边界早于本轮近期改动，属于本次在 main 发现的既有缺陷；近期 startup cancellation 修复没有覆盖 IO 失败路径。

建议将资源取得后的所有异步初始化纳入统一清理边界，先 bounded shutdown 子进程、取消监听/Timer/订阅，再释放生成锁；必要时 owner 对 activeProcess 增加兜底。初始化失败应发布 failed。补充真实 snapshot IO 失败回归，断言父子进程都退出且下次 generation 不与残留写入者竞争。本轮未修改或验证这一生产修复。

### F2 · P1 · predictive：OHOS 专有枚举使标准 Flutter CI 编译失败

- 位置：`packages/ccrouter_test/test/predictive_back_test.dart:800`。
- 当前代码直接引用 `TargetPlatform.ohos`；CI 固定的标准 Flutter 3.41.9 没有该枚举值。
- 标准 SDK 下根 analyze exit 3；框架套件 432 项通过、1 个测试文件加载失败，predictive 专项无法加载。
- OHOS SDK 下 analyze 通过、475 项框架测试通过。这只能说明 OHOS 构建成立，不能覆盖标准 SDK CI。

建议保留 iOS 固定值，通过 `TargetPlatform.values.where((value) => value.name == 'ohos')` 条件加入 OHOS，不升级 SDK、不删掉 OHOS 覆盖。候选 [SDK 兼容补丁](predictive-sdk-compatibility.patch) 已在 combined 验证，标准框架全量 486 项通过。证据：[标准分析](evidence/predictive-analyze.log)、[标准框架](evidence/predictive-framework.log)、[OHOS 框架](evidence/predictive-ohos-framework.log)。

### F3 · P2 · predictive：只读能力探测解除旧手势提交保护，迟到 commit 错误 Pop

- 位置：`packages/ccrouter/lib/src/flutter_predictive_back.dart:83–97`，尤其 91 行 `_handler = null`；commit 路径约 197 行。
- 触发：attached Router 的 managed 页面开始预测手势 → Adapter dispose → Host 读取 `route.popGestureEnabled` → 旧手势的迟到 `commitBackGesture` 到达。
- 根因：getter 调用 `_activeHandler`，发现 handler inactive 就清空；commit 又将 handler 为 null 解释为可采用 Flutter 默认 Pop。处于进行中的旧手势因此绕过应拒绝 commit 的旧 handler。
- 影响：原本要求取消的旧手势弹出仍存活的 attached Router 页面，错误改变页面和结果生命周期。已有“dispose 后迟到 commit”测试缺少中间 getter 读取。
- 新回归实测修正前 `keptPage == false`，修正后为 true。证据：[失败日志](evidence/combined-predictive-probe.log)、[修正后 43 项专项](evidence/combined-predictive-probe-fixed.log)。

候选最小修正为 tracking 期间保留旧 handler 到该手势终止；下一次正常探测再恢复 Flutter 所有权。提供 [候选生产补丁](predictive-handler-candidate.patch) 与 [新增回归补丁](predictive-regression-test.patch)。combined 加入候选后，原 predictive 专项及新增用例合计 43 项通过，框架全量再跑 486 项通过。另在 predictive 独立副本直接应用交付的 3 个补丁，标准 analyze 通过，框架全量 475 项通过（包含新增回归）；该数量不含 main 尚未合入的 UI Fragment 测试。同一 predictive 副本撤回 handler 修正后，新增用例再次失败；恢复修正后再次通过，排除了 UI Fragment 合并的影响。证据：[原行为复现](evidence/build-predictive-candidate-regression-unfixed.log)、[恢复修正后](evidence/build-predictive-candidate-regression-restored.log)。原分支尚未应用。

## 3. 回归矩阵

所有计数来自日志；不同快照与 SDK 的数量差异不代表漏跑。Demo 命令包含模块/example 的测试，不能只按 host 的 test 目录计数。

| 检查 | main 原状态 | predictive 原状态 | combined 临时状态 |
| --- | --- | --- | --- |
| 标准 Flutter/Dart analyze | 通过 | F2：undefined_enum_constant | 加 SDK 兼容修正后通过 |
| 框架全量 | 440 通过 | 432 通过、1 文件加载失败 | SDK 兼容后 486 通过；再加 F3 候选后重新跑 486 通过 |
| Demo + modules/examples | 59 通过 | 69 通过 | SDK 兼容状态 71 通过 |
| DevTools | 8 通过 | 8 通过 | 未重复 |
| DevTools protocol | 4 通过 | 4 通过 | 未重复 |
| tools / Skill bundle | 14 通过 | 14 通过 | 未重复 |
| 独立 Analyzer Plugin analyze | 通过 | 通过 | 未重复 |
| 独立 Analyzer Plugin tests | 133 通过，含 Legacy/LSP 真实 Server | Plugin 所有文件与 main 字节一致，共用此结果 | 未重复 |
| Generator 全量 | 首轮 579 通过 / 7 失败 / 1 跳过；失败用例复验通过 | 首轮 542 通过 / 9 失败 / 1 跳过；失败用例复验通过 | 未再跑完整 Generator |
| cached generate --check | 通过 | 通过 | 未重复 |
| --no-cache --check | 通过 | 通过 | 通过：6 components / 34 routes / 12 Packages |
| release sensitivity | 通过 | 通过 | 未重复 |
| documentation gate | 纯提交 107 Markdown 通过；当前目录见下述未跟踪文档 | 新 predictive 文档缺 docs/README 索引 | 未重复 |
| OHOS SDK analyze / 框架 | 未单独重复 | analyze 通过，475 项通过 | 未在 OHOS 上跑候选补丁 |

### Generator 首轮失败与复验

完整运行保留原始 exit code，不将复验通过包装为“首次全量全绿”。

| 首轮 | 通过 | 失败 | 跳过 | exit code | 耗时 |
| --- | --- | --- | --- | --- | --- |
| main | 579 | 7 | 1 | 1 | 42.7 分钟 |
| predictive | 542 | 9 | 1 | 1 | 40.2 分钟 |

两套各有 6 项 Hook 相关失败：1 项 Watch preflight，以及 Pub Hook 的 5 项 wrapper/preflight 用例。清除全局禁用变量后，Watch 单项通过，Pub Hook 整个文件 36 项通过。此外，在 predictive 自身的快照中对首轮全部 9 个失败用例按原时间限制重新运行，9 项全部通过（53.46 秒），并在其后再次执行 uncached generate --check。

另外 main 有 1 项、predictive 有 3 项 30 秒超时，4 项已单独复验通过。完整套件跳过的是默认关闭的远程 Git 安装 smoke；本轮另外显式启用该 smoke，并通过 SSH 完成真实安装/升级/doctor/卸载。

证据：[predictive 9 项逐一复验](evidence/predictive-generator-failed-cases-recheck.log)、[main 全量](evidence/main-generator.log)、[predictive 全量](evidence/predictive-generator.log)、[Watch preflight 复验](evidence/build-main-watch-preflight-recheck.log)、[Pub Hook 36 项复验](evidence/build-main-pub-hook-enabled-recheck.log)。

本轮 runner 为根依赖解析设置的 `CCROUTER_PUB_HOOK_DISABLE=1` 被错误地沿用到全量测试，导致依赖启用 Hook 的用例不执行 Hook。这是**审查运行环境污染**，不算产品缺陷。后续复验显式 `env -u CCROUTER_PUB_HOOK_DISABLE`；仓库 CI 仅在 pub get 那一步禁用 Hook，配置本身没有这个问题。

初轮出现的 4 个 30 秒超时用例都来自相同的 `builder_dependency_scope_test.dart`：

1. main：InitTask transitive inputs/constants。
2. predictive：Route DartDoc metadata。
3. predictive：Service Proxy imported generic bounds/typedef targets。
4. predictive：Route Codec imported supertype arguments。

它们在平台编译并发期间超时，去掉平台构建负载后按原 30 秒限制单独重跑，4 项全部通过；证据：[复验日志](evidence/build-main-generator-timeout-recheck.log)。不能据此宣称已证明所有 CI 时序无波动。

### 文档 gate 的区别

- main 已提交状态通过 107 个 Markdown 检查。当前工作目录失败仅因用户原有未跟踪 `docs/CCRouter-predictive-back-assessment.md` 不在 `docs/README.md` 索引，不应归因于 main commit。
- predictive 新增的 `docs/CCRouter-predictive-back.md` 同样漏索引；合入前应补齐。
- 分支已更新 README、integration Skill 和相关 reference，主要对外说明路径存在；本文不把设计文档或历史设备记录当成本轮执行结果。

## 4. 平台构建与 Analyzer 链路

| 状态 | 目标 | 结果 |
| --- | --- | --- |
| main | Web debug | 成功 |
| main | Android APK debug | 成功 |
| main | macOS debug | 成功 |
| predictive 原状态 | Android APK debug，`lib/main_predictive_back.dart` | 成功 |
| predictive 原状态 | iOS debug，`lib/main_predictive_back.dart`，不签名 | 成功 |
| predictive 原状态 / OHOS SDK | OHOS 默认入口，未签名 HAP | 成功，35 tasks |

标准 SDK：Flutter 3.41.9 / Dart 3.11.5，与 CI 对齐。OHOS SDK：Flutter 3.41.10-ohos-1.0.0 / Dart 3.11.5。两套 SDK 使用独立副本解析依赖，未混用 package_config。

OHOS 初次 devecocli 自动选择旧 `DevEco-Studio-26-previous.app`，ohpm Node 被 SIGKILL；指定已存在的 `/Applications/DevEco-Studio.app` 后成功，未升级或替换用户 SDK。此结果是构建验证，不是 Android 预测手势设备验收。Hvigor preflight 在去掉 FLUTTER_ROOT 的独立副本中也成功，未发现此前怀疑的环境变量依赖问题。

Analyzer Demo 当前 pin 为 `5c69a72b769389d076d6f538e6964a0dafe88c27`：

- status healthy；pin-check 验证 manifest/lock/resolved-ref 一致、远端可解析、production drift 为 none。
- doctor 的依赖、bootstrap 分析、loader smoke 通过。
- 真实远程 Git install → upgrade → doctor → uninstall smoke 通过（隔离临时 Host，使用项目现有 SSH remote）。
- 首次默认 HTTPS smoke 因私有仓库无 HTTPS 非交互凭证失败；改用已可访问的 SSH remote 后通过，属于 transport 环境差异。
- 本轮没有重启用户 IDE，也不声称观察到了其当前 IDE 进程已加载插件；真实 Legacy/LSP 行为由隔离 Server 测试覆盖。

## 5. 合并预演、资源回收与剩余边界

main 与 predictive 的临时整合出现 3 个 fixture 文本冲突：

- `component_dependency_preflight_test.dart`
- `generation_atomicity_test.dart`
- `pub_hook_test.dart`

均为 repository root 识别兼容 `.git` 文件/目录的等价实现，保留 main；未发现业务代码文本冲突。main 的 UI Fragment 与 predictive 在临时整合后，analyze、框架、Demo、uncached generation 通过。以上通过依赖 F2 候选修正；F3 候选另有明确的修正后专项/全量证据，不能直接套用于未修正原分支。

运行非 full 的 `performance_regression.dart` 作为容量和回收检查：

- 10/100/1000 Routes、Service Providers 场景完成。
- 10 × 100 并发导航完成，最终 pending 为 0，保留预期根 entry。
- 1,000 lifecycle cycles 完成，结束时清理断言通过。
- analytics 5,000 事件、capacity 64，队列峰值 64，close 后 pending 为 0；超容量采用预期丢弃策略。

这些检查与其他任务并行，未做同条件基线比较，**不提供性能提升/退化结论，也不证明长期零泄漏**。F1 有明确未销毁子进程证据，其余未发现可确认的 not-GCed 保留链。

本轮未执行实机/模拟器手势交互、动画观感、IME/WebView 场景、多 Android 系统版本矩阵、Linux/Windows 构建、签名发布构建和长时间 heap/leak-tracker 检查。已有分支 Samsung 设备验收文件仅作为历史参考，没有冒充本轮设备验证。

## 6. 方案比较与推荐实施顺序

| 方案 | 优点 | 代价与风险 |
| --- | --- | --- |
| 直接合并 | 最快 | F2 会使标准 CI 失败；F1/F3 保留真实生命周期错误，不推荐 |
| 三项局部修复、保留现有 opt-in、分步合并 | 修改面小，可逐项验证和回退；候选 F2/F3 已有证据 | 仍需实现 F1、补文档索引、提交后跑 CI 与设备验收；推荐 |
| 重做 Watch/预测手势架构或统一改 OHOS SDK | 可以重新设计所有权 | 成本和回归面远大于已定位问题；SDK 切换不能修复 F1/F3，不建议为本轮问题采用 |

推荐步骤：

1. main 独立修 F1：先加入故障注入回归，再统一清理边界；验证孤儿进程消失、锁释放顺序及 Watch shutdown/restart。
2. predictive 独立修 F2，并在标准 SDK 与 OHOS SDK 各跑分析和框架测试。
3. predictive 修 F3，加入 getter-interleaving 回归；补充取消、Host 替换、重启手势、超时和 attached Router 的语义检查，保留默认关闭开关。
4. 补 predictive 文档索引；确定原 main assessment 文档是否进入版本管理并相应维护索引。
5. 把最新 main 整合进分支，保留 main 的等价 fixture；重新执行所有 required CI gates。生产代码修复应按 framework Skill 同步相关生命周期文档。
6. 执行 Android 真机预测返回/取消、Guard/PopScope、foreign overlay、IME/WebView 场景后再放行合并。

本次交付到审查与验证为止：未自动应用修复、提交、推送、合并或发布。候选补丁用于下一步实现审阅，不包含尚未完成的 F1 修复。

## 7. 证据索引与重现约定

2026-10-16 归档脱敏：本目录的 JSON、日志、复现脚本及两个日志压缩包统一使用
`<USER_HOME>`、`<TEMP_DIR>` 代替本机用户目录和临时目录前缀，压缩包不保留本机属主信息。
命令参数、退出码、耗时、失败与复验结果均保留；这些仍是历史验证记录，不表示重新执行。
源码文件的历史 SHA-256 保持不变；`source-integrity.json` 同时记录脱敏前后的 manifest 摘要，
其中 `baseline_manifest_sha256` 对应当前压缩包内脱敏后的 `source-manifest.json`。
复现前需将路径占位符替换为本地 SDK、工作副本及临时目录。

- [命令与退出码汇总](checks.json)：保留每条命令、cwd、exit code、耗时及原始日志路径。
- [完整脱敏日志压缩包](full-logs.tar.gz)：包含初次失败和复验，不只保留成功结果。
- [源码一致性校验](source-integrity.json)：两原工作区的既有文件逐一 SHA-256 比对；worktree 的提交发生在审查期间，文件内容与冻结快照一致。
- [F1 复现](evidence/watch_probe.py)：保存本轮复现脚本，已替换本机路径；还原时需把 root 指向包含 watch-probe 隔离副本的临时目录。只应在独立副本运行，脚本会短暂修改一个生成文件权限。
- F2/F3 补丁按顺序应用于 predictive 分支：SDK compatibility → handler candidate → regression test。补丁未应用到用户原工作区。
- 标准验证使用绝对 SDK 路径，避免全局 FVM 默认 OHOS 造成结果误读；根 pub get 才设置禁用 Hook，Hook 功能测试清除该变量。
- 框架测试路径固定为 `packages/ccrouter_test/test`；Plugin 测试 cwd 固定为 `packages/ccrouter_analyzer_plugin`。

