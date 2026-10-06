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
