# CCRouter Analyzer Plugin CLI 自动装配计划

## 1. 状态与目标

- 状态：部分实现；只读 `status/doctor` 已完成，写入型装配命令尚未实现。
- 优先级：P1，正式发布前的开发体验能力。
- Owner：`ccrouter_generator` CLI；`ccrouter_analyzer_plugin` 继续只负责确定性诊断。
- 目标：用显式、幂等、可诊断和可回滚的命令装配 Host Analysis Server bootstrap，减少
  Analyzer 版本、Git ref、loader 和 `analysis_options.yaml` 的手工配置错误。

本计划不改变 Analyzer Plugin 的职责。插件不运行生成器、不修改业务源文件、不代替
`ccrouter generate --check`，安装失败也不能影响应用构建和运行。

## 2. 当前固定 ref 决策

Demo bootstrap 当前固定到：

```yaml
ref: 97c72daae65d0dd01e1ecd5263c647d6b213f814
```

该 commit 已存在于远端，且从该 commit 到 2026-09-29 的本地工作区，Plugin 生产代码没有
变化，只有隔离测试增加。因此当前不为了追随仓库 HEAD 而更新 ref。

Git ref 只能更新到已推送、已评审并通过 Plugin Package 测试和 loader smoke 的完整 commit
SHA。禁止使用分支名 `main`、未推送的本地 SHA 或浮动 tag。Hosted Package 发布后，默认使用
Hosted 版本；Git bootstrap 只作为发布前或指定版本验证方式。

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
```

尚未实现，当前不能直接执行：

```text
ccrouter analyzer install [host-root] [--source hosted|git] [--version <range>]
                          [--url <git-url> --ref <full-commit-sha>]
ccrouter analyzer upgrade [host-root] [--version <range> | --ref <full-commit-sha>]
ccrouter analyzer uninstall [host-root]
```

### `install`

- 只面向明确的 Host Package，不把 Workspace 聚合根或组件 Package 猜成 Host。
- 检测 Dart/Flutter SDK、Analyzer 和 `analyzer_plugin` 兼容矩阵。
- 默认使用已发布 Hosted 版本；使用 Git 时必须同时提供 URL 和完整 commit SHA。
- 创建隔离的 `tools/analyzer_plugin` bootstrap，不把 Plugin Analyzer 依赖混入应用或 Generator
  Workspace。
- 以可识别的受管区块更新 `analysis_options.yaml`，发现未知的同名配置或其它插件冲突时停止并
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
- 输出重启 Analysis Server 的建议和普通 Dart Analyzer + `generate --check` 回退路径。

### `upgrade`

- 只在开发者显式给出目标 Hosted 版本或远端 commit SHA 时更新。
- 不自动跟随 `main`，不把本地 HEAD 当作 Git ref，不自动跨 Analyzer 兼容区间。
- 更新前后均运行 `doctor`；失败时恢复 CLI 本次修改的 manifest 和 lockfile。

### `uninstall`

- 只移除 CLI 标记的 bootstrap 文件和 `analysis_options.yaml` 受管区块。
- 保留未知文件、用户 Analyzer 配置和非 CCRouter Plugin。
- 删除前输出 dry-run；部分内容被用户修改时默认拒绝删除，并给出手工处理范围。

## 5. 所有权、失败与回滚

- CLI 拥有其创建并带有受管标记的 bootstrap 和配置区块，不拥有 Host 的其它 IDE 配置。
- Plugin 是开发期可选能力；任何安装、加载和版本故障都不得改变生成物、Runtime 或业务结果。
- 文件写入采用临时文件和原子替换；多文件操作保留本次备份，全部验证成功后才完成提交。
- 命令支持 `--dry-run` 的具体统一形式在实现前与现有 CLI 参数规范一起冻结。
- 多 Host Workspace 必须逐 Host 装配；命令不扫描并批量修改所有 Package。
- 执行后提示重启 Dart Analysis Server 或 IDE，但 CLI 不主动终止 IDE 进程。

## 6. AI Skill 接入规则

写入型命令实现前，AI 继续使用现有手工 bootstrap 指南，不得声称 CLI 可以自动安装、升级或
卸载。已经装配的 Host 应优先运行 `status` 和 `doctor`，手工 smoke 作为回退，并遵守：

1. 先运行 `status` 和 `doctor`，再判断是否需要 `install` 或 `upgrade`。
2. 未经明确请求不升级版本或 ref，不使用 Git `main`。
3. 不覆盖已有 Analyzer Plugin、未知 bootstrap 或用户 `analysis_options.yaml` 内容。
4. 不提交本地绝对 path 或临时 `pubspec_overrides.yaml`。
5. 安装失败时保留普通 Dart Analyzer 和 `ccrouter generate --check` 门禁。
6. 报告实际 Host、来源、固定版本/ref、验证结果、重启提示和回滚命令。

## 7. 实施顺序与验收

1. [x] 抽取 Host/bootstrap 状态探测，只读实现 `status`。
2. [x] 实现无写入的 `doctor` 和兼容矩阵诊断。
3. 实现 Hosted `install/uninstall`，覆盖幂等、冲突和回滚测试。
4. 增加固定 Git commit 安装，并拒绝 branch、短 SHA、本地未推送 SHA 和非法组合。
5. 实现显式 `upgrade` 与失败恢复。
6. 更新 CLI help、根 README、IDE 文档和 Integration/CLI Skill。
7. 在 Demo、临时 Host、VS Code 和 Android Studio 完成 Analysis Server smoke。

验收至少覆盖：重复安装、已有 Plugin 配置、多 Host、聚合根误判、Hosted/Git 两种来源、Analyzer
不兼容、离线依赖失败、loader 编译失败、用户修改受管文件、卸载恢复和 Plugin 不可用时的业务
构建回退。
