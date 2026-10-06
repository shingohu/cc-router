# CCRouter Analyzer Plugin CLI 自动装配计划

## 1. 状态与目标

- 状态：`status/doctor/install/upgrade/uninstall` 已实现；Hosted 发布后真实安装和完整 IDE/SDK 矩阵仍待验收。
- 优先级：P1，正式发布前的开发体验能力。
- Owner：`ccrouter_generator` CLI；`ccrouter_analyzer_plugin` 继续只负责确定性诊断。
- 目标：用显式、幂等、可诊断和可回滚的命令装配 Host Analysis Server bootstrap，减少
  Analyzer 版本、Git ref、loader 和 `analysis_options.yaml` 的手工配置错误。

本计划不改变 Analyzer Plugin 的职责。插件不运行生成器、不修改业务源文件、不代替
`ccrouter generate --check`，安装失败也不能影响应用构建和运行。

## 2. 当前固定 ref 决策

Demo bootstrap 的当前 Git ref 只在活动 manifest
`demo/tools/ccrouter_analyzer_plugin_host/tools/analyzer_plugin/pubspec.yaml` 与其 lockfile 中维护；
两者的 `ref`/`resolved-ref` 必须一致。普通文档不复制当前值，避免文档与实际 bootstrap
形成第三份状态。该固定 commit 已存在于远端，并通过对应阶段的独立 Plugin 测试、生成物检查
和 loader smoke；后续仍不为了追随仓库 HEAD 而更新 ref。

Git ref 只能更新到已推送、已评审并通过 Plugin Package 测试和 loader smoke 的完整 commit
SHA。禁止使用分支名 `main`、未推送的本地 SHA 或浮动 tag。Hosted Package 发布后，默认在
Host 的普通 `dev_dependencies` 中声明 Hosted 版本；Git bootstrap 只作为发布前或指定版本验证方式。

## 3. 候选方案

### 3.1 只保留手工文档

优点是没有 CLI 维护成本。缺点是开发者需要同时维护 bootstrap、Analyzer 兼容版本、Git ref、
loader 和 Host 配置，容易产生只能在部分 IDE 或机器复现的问题。

### 3.2 在生成或 Pub Hook 中隐式安装

不采用。Analyzer Plugin 是 Host 的可选开发工具，不是生成和构建的必要依赖。隐式安装会修改
IDE 配置，并把可选工具故障混入 Pub、生成或运行链路，也无法正确表达多 Host Workspace 的
选择。

### 3.3 显式 Analyzer 命令组

采用。显式命令保持 Host Owner 边界，允许预检、诊断、升级和完整回滚，不改变普通生成流程。

## 4. 命令状态

已实现：

```text
ccrouter analyzer status [host-root]
ccrouter analyzer doctor [host-root]
ccrouter analyzer pin-check [host-root]
```

写入型命令也已实现；以下三个命令都支持 `--dry-run`：

```text
ccrouter analyzer install [host-root] [--source hosted|git] [--version <range>]
                          [--url <git-url> --ref <full-commit-sha>] [--git-path <package-path>]
ccrouter analyzer upgrade [host-root] [--version <range> | --ref <full-commit-sha>]
ccrouter analyzer uninstall [host-root]
```

### `install`

- 只面向明确的 Host Package，不把 Workspace 聚合根或组件 Package 猜成 Host。
- 检测当前 Dart 3.10+、Host SDK constraint；loader 固定 Analyzer 8.4.0 / analyzer_plugin 0.13.10，实际解析、分析、编译验证兼容性，不承诺任意 SDK。
- 默认来源为 Hosted，但必须显式 `--version`；仓库版本号不能证明包已发布。Git 必须同时提供远端 HTTPS/SSH URL 和完整 commit SHA，通过临时 bare fetch 验证远端可获取，拒绝本地路径和浮动引用。
- 创建隔离的 `tools/ccrouter_analyzer_host/tools/analyzer_plugin` bootstrap，不把 Plugin Analyzer 依赖混入应用或 Generator
  Workspace。
- 以 YAML 结构叶和 ownership 记录更新 `analysis_options.yaml`，保留无关规则、注释及祖先规则继承；发现未知的同名配置或其它插件冲突时停止并
  给出差异，不覆盖用户内容。
- 生成前提供 dry-run 摘要；重复执行相同配置不得改写文件或 lockfile。

### `status`

- 已实现，只读取指定 Host 与最近的 enclosing Workspace Package config。
- 输出 Host、bootstrap 路径、Plugin 来源、Hosted 版本或 Git ref、Analyzer 版本、lockfile
  状态以及 `analysis_options.yaml` 是否启用。
- 区分 `notInstalled`、`healthy`、`stale`、`incompatible`、`modified` 和 `incomplete`，不把
  Plugin 状态错误描述成应用构建错误。

### `doctor`

- 已实现；所有工具检查在 bootstrap 临时副本中执行，不改写活动 bootstrap 的 `.dart_tool`、
  manifest 或 lockfile。
- 先执行 `status`，再验证依赖解析、loader `dart analyze` 和
  `dart compile exe bin/plugin.dart`。
- 不启动常驻 Analysis Server，不运行生成器，不修改配置。
- 检查当前 bootstrap 对应的 legacy 缓存 manifest 和入口，区分 cache artifact
  `absent/current/stale`；stale 保持 advisory，不按 Package 同名误报其他 Host 的缓存。
- cache 异常时以 POSIX `ps` 或 Windows CIM 做只读、保守的进程匹配，报告 PID、PPID、elapsed
  和 command。候选匹配不是所有权证明，CLI 不自动 kill、move 或 delete。
- 分别输出 source pin、cache artifact、temporary loader smoke、Analysis Server restart 与 live IDE
  verification；loader compile 或 `dart analyze` 不能证明运行中的 IDE 已加载插件。
- 给出完整 hash entry 的精确 source/backup 路径；开发者必须先从 IDE 停止 Server、确认进程
  退出，再手工备份整个条目并重启。禁止只移动 `analyzer_plugin` 子目录或清空无关 cache。

### `pin-check`

- 供 maintainer/release 手动运行，不接入所有 Plugin PR 的默认硬门禁。
- 只接受健康的 Git bootstrap；校验完整 40 位 SHA、manifest/lock/`resolved-ref` 一致，并在
  临时 bare repository 中精确 fetch 该 SHA，拒绝本地 Git URL 和越界 package path。
- 在当前维护仓库中比较 pinned SHA 与工作树的 `packages/ccrouter_analyzer_plugin/lib`。存在
  生产变化时报告 `pending` 及文件列表但返回成功：先验证并推送 Plugin，再在独立提交中 bump
  manifest/lock；bump 后重新运行应报告 `none`。
- 不修改 Host、活动 bootstrap、lockfile、Git index、全局 cache 或 IDE 进程。

### `upgrade`

- 只在开发者显式给出目标 Hosted 版本或远端 commit SHA 时更新。
- 不自动跟随 `main`，不把本地 HEAD 当作 Git ref，不自动跨 Analyzer 兼容区间。
- 更新前对现有安装运行 `doctor`，新版本先在临时目录通过依赖解析和 doctor，再写入 Host 并执行 Pub；失败时恢复受管配置和已记录的 Pub 解析文件。
- 相同来源/版本且静态状态健康时直接幂等返回，不重新解析或修改 lockfile；改变来源类型需显式卸载后安装。

### `uninstall`

- 只移除 ownership 记录且摘要仍匹配的四个 bootstrap 文件、记录文件、Host dev_dependency 和 `analysis_options.yaml` 受管叶。
- 保留未知文件、用户 Analyzer 配置和非 CCRouter Plugin。
- 可先执行 `--dry-run`；部分内容被用户修改时拒绝删除，并给出手工处理范围。现有手工 bootstrap 不自动采用或迁移。

### Hosted 迁移与弃用冻结（2026-10-05）

`ccrouter analyzer install` 与 `upgrade` 进入 legacy maintenance-only 状态：实现保留可回滚
能力，不再增加新的来源、IDE 或 SDK 管理特性，执行时会明确输出弃用提示。`status`、`doctor`
和 `uninstall` 保留，用于诊断和撤销已有隔离 bootstrap；`doctor` 对私有
`.dartServer/.plugin_manager` 只给 advisory，不把跨 SDK 的缓存目录当作权威门禁。普通 Hosted
依赖的推荐迁移方式是直接编辑 Host：

```yaml
dev_dependencies:
  ccrouter_analyzer_plugin: ^0.1.0
```

再在 `analysis_options.yaml` 启用插件并执行普通 `dart analyze`/IDE 重启。仓库保留
`demo/tools/ccrouter_analyzer_plugin_host/tools/analyzer_plugin/pubspec.hosted.yaml` 作为发布后
替换模板；在 Hosted 版本真正可解析前，Demo 继续使用固定 Git SHA，不执行隐式切换。

## 5. 所有权、失败与回滚

- CLI 拥有固定 bootstrap 路径及 `.ccrouter-analyzer.json` 记录的配置叶，不拥有 Host 的其它 IDE 配置。
- Plugin 是开发期可选能力；任何安装、加载和版本故障都不得改变生成物、Runtime 或业务结果。
- 文件写入采用临时文件和原子替换；多文件操作保留本次备份，全部验证成功后才完成提交。
- `--dry-run` 不启动子进程、不写文件；实际操作在 Pub owner 下使用非阻塞文件锁，多 Host 共用 Workspace 时串行修改。
- 只安装明确的 Flutter 应用：直接依赖 ccrouter/flutter，且有 app `.metadata` 或 `lib/main.dart` 顶层 main。Workspace 聚合根及普通组件不接受安装。
- 多 Host Workspace 必须逐 Host 装配；命令不扫描并批量修改所有 Package。
- 执行后提示重启 Dart Analysis Server 或 IDE，但 CLI 不主动终止 IDE 进程。

提交 Host 的 pubspec/options、四个 bootstrap 文件、ownership 记录和 Pub lockfile；不要提交
`.dart_tool`。Host Pub 使用当前 Dart 所属 Flutter SDK，并禁用 Pub Hook，不运行生成器。
事务记录位于 Pub owner 的 `.dart_tool/ccrouter/analyzer/transactions/`，保存原始字节；普通
失败恢复本次受管配置及 Host/Workspace 的 lockfile、package_config、package_graph、Flutter
plugins dependency 文件。不会回滚全局 Pub cache 或其它平台缓存。并发用户改动、无法读取的
Pub 结果或进程中断保留恢复记录，后续写命令拒绝继续；核对记录中的明确路径后恢复，不能清空
缓存来绕过。未知文件保留。子进程输出有界，单阶段三分钟超时并结束子进程。

## 6. AI Skill 接入规则

新 Host 可使用显式写入命令；已手工装配的 Demo 继续使用手工指南，CLI 不自动接管。
已经装配的 Host 应优先运行 `status` 和 `doctor`；maintainer/release 处理 Git pin 时再运行
`pin-check`，并遵守：

1. 先运行 `status` 和 `doctor`，再判断是否需要 `install` 或 `upgrade`。
2. 未经明确请求不升级版本或 ref，不使用 Git `main`。
3. 不覆盖已有 Analyzer Plugin、未知 bootstrap 或用户 `analysis_options.yaml` 内容。
4. 不提交本地绝对 path 或临时 `pubspec_overrides.yaml`。
5. 安装失败时保留普通 Dart Analyzer 和 `ccrouter generate --check` 门禁。
6. 报告实际 Host、来源、固定版本/ref、验证结果、重启提示和回滚命令。

## 7. 实施顺序与验收

1. [x] 抽取 Host/bootstrap 状态探测，只读实现 `status`。
2. [x] 实现无写入的 `doctor` 和兼容矩阵诊断。
3. [x] 实现 Hosted `install/uninstall`，覆盖幂等、冲突和回滚测试；真实 Hosted 下载待发布后验收。
4. [x] 增加固定 Git commit 安装，并拒绝 branch、短 SHA、本地来源和非法组合；远端获取失败不写 Host。
5. [x] 实现显式 `upgrade` 与失败恢复。
6. [x] 更新 CLI help、根 README、IDE 文档和 Integration/CLI Skill。
7. [~] 临时 Host 真实 Git/Pub/loader 验证与既有独立 Server 测试分别验收；完整 VS Code、Android Studio、SDK/OS 矩阵仍未完成。
8. [x] Hosted 普通 `dev_dependency` 迁移模板、legacy install/upgrade 弃用提示和
   `.plugin_manager` 非权威语义已落地；Hosted 发布与干净消费者验证仍是外部前置条件。
9. [x] 增加手动 `pin-check`、legacy cache 进程诊断，以及 source/cache/live 分层状态；不把
   这些诊断接入普通 PR 硬门禁或 IDE 控制链路。

第 7 项已有独立进程自动化基础：Legacy/LSP 协议、overlay、修复应用、五类生成物磁盘
变化和 Workspace Owner metadata/Contract 刷新已覆盖。它使用本地源码和临时缓存，不
替代安装命令的真实 bootstrap/Pub/AOT/固定 ref 验收，也不表示两个 IDE 的完整矩阵通过。
SDK 独立多根冷启动边界见 [IDE 文档](CCRouter-ide-analysis-server.md)。

验收至少覆盖：重复安装、已有 Plugin 配置、多 Host、聚合根误判、Hosted/Git 两种来源、Analyzer
不兼容、离线依赖失败、loader 编译失败、用户修改受管文件、卸载恢复和 Plugin 不可用时的业务
构建回退。

### 2026-10-03 实际验收边界

- macOS / Dart 3.11.5：临时 Flutter Host 的真实 SSH Git 安装、重复安装、升级、doctor、卸载
  全链路通过，约 88 秒。使用远端 `97c72da…` → `a275d1d…`，未修改 Demo 或推送任何 ref。
- HTTPS GitHub 连接在本机失败；SSH 验证通过不代表 HTTPS 网络正常。可选测试由
  `CCROUTER_ANALYZER_NETWORK_SMOKE=1` 开启，`CCROUTER_ANALYZER_GIT_URL` 可选择远端协议；
  默认回归跳过网络测试，避免要求每个开发者都有 Git 凭据。
- 安装事务测试覆盖模拟 Hosted、真实 YAML/文件操作、继承规则、来源冲突、共享锁、SDK、
  幂等、失败恢复、并发编辑、无法读取的 Pub 结果和中断 journal；不把模拟 Hosted 当成真实发布验收。
- 安装事务专项 36 项通过；Generator 全量 321 项通过（默认跳过的网络测试另行通过）。
  Workspace analyze、缓存/无缓存生成检查、文档与 Skill 分发检查均通过。
- 实际 loader 固定 Analyzer 8.4.0 / analyzer_plugin 0.13.10。Windows/Linux、其它 SDK、
  新版插件机制和两个 IDE 的完整矩阵尚未验证，仍按独立兼容任务推进。
