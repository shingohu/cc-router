# build_runner 2.16.1 验证证据

最终目标 SDK 为官方 Flutter 3.47.9 / Dart 3.13.7；主报告见 [升级记录](../build_runner_upgrade_20261104.md)。源码基线与最终改动文件的 SHA-256
见 [source-fingerprints.json](source-fingerprints.json)。没有将旧失败或中断运行改称成功。

- [stock A/B](stock-comparison.json)：同一 Dart 3.13.2 下的 2.15.1 与 2.16.1；
  `stock-*.log` 是首次、增量及重复构建输出，重现脚本为 [incremental_probe.py](incremental_probe.py)。
- [Generator 全量原始记录](generator-full.log)：722 通过、3 失败、1 跳过；
  修复后见 `final-watch-startup.log`、`final-scaffold.log`、`final-isolation.log` 和
  [watch 扩大复验](watch-targeted-final.log)。未额外声称最终代码再次单轮全量无失败。
- [最终门禁](final-results.json)：各命令真实退出码；严格全仓 analyze 的 2 是 3 条 warning，
  不是通过。使用本次进程 HTTPS 映射后的实际诊断见 [分析日志](final-analyze-https.log)。
- [回滚与 profile](final-rollback.log)：9 项通过，包含失败恢复、自定义输出及 fixed counter。
- `framework-summary.log` / `demo-summary.log`：最终 worktree 的 1650 / 117 项全量摘要。
- `plugin-summary.log`：独立 Package 的 212 项（含真实 Server）摘要，不代表桌面 IDE 已重启。
- `ohos-runtime-summary.log` / `ohos-demo-summary.log`：仅 Runtime 修复配旧依赖、旧 SDK 的
  1650 / 117 项对照；不能用于宣称新 Generator 兼容旧 OHOS SDK。
- [冷/热对照](cold-hot-comparison.json)：109 个文件 SHA-256 一致，含 Portable State。
- [最低 Pure Dart 消费者](minimum-results.json)：Dart 3.11.5 的 Pub、生成、check、分析通过。
- [FlutterGen 5.15.0 共图](fluttergen-results.json)：独立临时副本的全量、资源增量、CCRouter
  生成、check 和重复构建通过。没有修改生产应用。

部分日志保留本机临时路径；源代码位置不依赖这些路径。构建缓存、临时工程和 SDK 不在证据目录中。

- `upstream-3479-*`：官方 3.47.9 最终门禁，725 项 Generator、1650 项 Framework、117 项 Demo 和 212 项 Plugin 测试；stock A/B 同 SDK 也在该目录保存。
