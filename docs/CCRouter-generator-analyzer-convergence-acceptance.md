# Generator / Analyzer 优化收敛验收（2026-10-05）

本文记录本轮 1→6 收敛的仓库内验收边界。它不替代真实 Hosted 发布、干净消费者和跨 SDK/IDE
矩阵；网络、凭据或外部发布前置条件未满足时，结论保持 fail-closed。

## 已收敛契约

| 项目 | 当前行为 | 回退/保留门禁 |
| --- | --- | --- |
| private State body fingerprint / AST preflight | 未发现独立 private body fingerprint；已提交的 authored input proof 与组件 dependency preflight 保留 | 不删除 namespace、输入一致性和 Builder 校验 |
| P6 Shadow Closure | 从生产 CLI、Build Plan 和 profile 热路径移除；历史数据仅作 benchmark 资料 | 完整内容摘要与 `--no-cache --check` |
| Tool identity | `execution_kernel.dart` 显式拥有 Generator `lib/`、主入口、Build Plan、Portable State、`build.yaml` | Analyzer/scaffold/pub-hook 修改不失效；kernel 修改失效 |
| Portable State | `ccrouter.yaml` 的 `generation.portable: true` + `portable prepare` 才写入；`portable publish` 只验证 | writable 未声明回退 Builder；只读已声明包缺失/失配 fail-closed |
| Analyzer | Hosted 普通 `dev_dependency` 是发布后首选；install/upgrade legacy maintenance-only | status/doctor/uninstall 保留；maintainer `pin-check` 手动运行；`.plugin_manager` 仅 advisory，live IDE 独立验收 |

## 必保留验收入口

- `CCROUTER_DISABLE_AGGREGATE_ONLY=1` 强制完整 Builder。
- `generate --no-cache --check` 是权威参考路径。
- P2/P3 `aggregateOnly`、generation lock、受管输出快照恢复、输入一致性屏障和原子写入继续执行。
- 缓存/聚合路径与参考路径必须逐文件逐字节比较；不能用相同 fingerprint 字符串代替比较。

## 本机执行结果

通过：

```text
dart format（Generator/Analyzer/测试改动）
dart analyze packages/ccrouter_generator packages/ccrouter_test packages/ccrouter_analyzer_plugin
```

被环境阻断：

```text
dart test packages/ccrouter_test/generator_test/...
ccrouter generate demo --no-cache --check
ccrouter portable prepare demo
dart analyze demo
```

原因是本机无法访问 `pub.dev` advisory/Hosted 网络，且现有 Demo Analyzer legacy cache 需要向
`.pub-cache` 写入 `FETCH_HEAD`；这些失败没有修改受管输出或外部系统。测试代码仍覆盖：

- execution-kernel 与 CLI integration tool identity 回归；
- Portable opt-in、普通 generate 不写 Portable State；
- P2/P3 aggregate-only、kill switch、输入屏障和快照恢复；
- Analyzer stale `.plugin_manager` 仅 advisory；安装事务的原子/回滚/逐字节快照。
- Analyzer source/cache/live 分层状态、POSIX/Windows 候选进程报告与手工恢复边界；CLI 不控制 IDE 或清理全局 cache。

## 外部前置条件

1. 发布 `ccrouter_analyzer_plugin` Hosted 版本并提供正式版本号/凭据；此前 Demo 继续使用固定 Git SHA。
2. 在干净 Flutter Host 中验证普通 `dev_dependency`、Analysis Server reload、`status/doctor` 回退和 IDE 矩阵。
3. 在网络可用的真实 Host 执行 `portable prepare`、`portable publish`、缓存路径与 `--no-cache --check` 的逐字节 A/B。
4. 不执行 `pub publish`、远端 push 或任何外部状态修改，除非用户另行授权。

## 2026-10-06 Analyzer 状态收敛回归

本轮针对 Demo Git bootstrap 的三层状态割裂完成只读收敛，实际结果：

- `analyzer_command_test.dart` 21 项通过；`analyzer_installation_test.dart` 36 项通过。
- `analyzer_installation_smoke_test.dart` 的 1 项真实网络安装测试按设计跳过，未设置
  `CCROUTER_ANALYZER_NETWORK_SMOKE=1`；真实 Demo 的 `pin-check` 已另行完成远端精确 SHA fetch。
- `analyzer pin-check demo` 通过：manifest/lock/`resolved-ref` 一致，远端可解析，pinned SHA
  之后 Plugin `lib` 无生产变化。
- `analyzer doctor demo` 的 locked dependencies、bootstrap analysis、loader compile 通过；legacy
  cache artifact 为 `current`。该结果只证明临时 loader smoke 与 cache 文件一致，live IDE
  verification 仍为 `pending`，未由 CLI 重启或控制 Analysis Server。
- `fvm dart analyze` 全 Workspace 通过。
- Skill bundle 的 8 项检查中 7 项通过；命令/flag 不得虚构、链接和示例分析均通过。剩余 1 项
  是既有命令矩阵解析器把三条 `generate <host-root> --check/--no-cache` 示例误判为 unsupported，
  与本轮新增 `analyzer pin-check` 无关。

个人开发回归关注误操作成本：status/doctor/pin-check 不修改 Host、Git index 或全局 cache；doctor
只报告候选进程和精确手工恢复路径，不自动 kill/move/delete。团队协作回归关注两阶段发布窗口：
Plugin `lib` drift 只报告 `pending`，不阻断第一阶段 Plugin PR；推送并取得远端可解析 SHA 后，
再由独立 pin bump 收敛为 `none`。剩余平台风险是 Windows CIM 目前有自动化解析测试但没有真实
Windows/IDE 本机验收；live diagnostic/Quick Fix 仍必须由实际 IDE 会话确认。

## 2026-10-07 one-shot diagnostics 与真实 IDE 收尾

- Analyzer Plugin 全套 110 项通过，覆盖 watch/one-shot 优先级、fingerprint 失效、Workspace 嵌套
  Host polling，以及 Legacy/LSP `pubspec.yaml` 未保存 overlay 的提示出现与清除。
- Plugin 修复已推送为 `23ff0d2`；Demo bootstrap manifest、lock 与 `resolved-ref` 固定到完整 SHA
  `23ff0d24acf63c3cf9674ad1651a4a4446beb88c`，`analyzer pin-check` 确认远端可解析且无 production drift。
- 在没有活动 Analysis Server 后，将旧 cache 整体移动到
  `~/.dartServer/ccrouter-plugin-cache-backup/2830316c39d53daed22fb3806abbfdb7`，未删除内容；Android Studio
  启动后重建 `.plugin_manager` cache，Package config 和 lock 均指向当前固定 SHA，`analyzer doctor`
  报告 cache current、bootstrap analysis 与临时 loader smoke 通过。
- 真实 Android Studio 会话中，未保存地注释 Demo 的 `demo_order` 后出现
  `ccrouter_pub_resolution_stale`，恢复原 overlay 后具体诊断和编辑器高亮均清除；磁盘
  `demo/pubspec.yaml` 与 Git 工作区未被修改。
- Generator 完整单线程 suite 以
  `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test` 验收：497 项通过、1 项需显式
  开启网络的 smoke 按预期跳过，耗时约 20 分 54 秒。当前 Workspace analyze 和 Demo
  `--no-cache --check` 继续作为本轮最终门禁。
