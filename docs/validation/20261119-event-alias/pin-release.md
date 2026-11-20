# Event alias 两阶段推送与 Demo pin（2026-11-19）

这是[提交前验证报告](report.md)的后续来源记录，不改写其 RED、整套失败或复跑数字。
用户明确授权本轮提交、推送和 tag，选择 Git tag `0.3.0`，指向当前开发分支的最终提交；
本次不包含合并到 main。Package 版本与 Hosted 发布状态没有随 Git tag 改动。

## 两阶段来源

第一阶段源码提交 `ec9da8538b27ef17efcf44aeefc9bbad2fbef845` 已先推送至
`origin/codex/unify-contract-validation`。随后才在独立提交中修改 Demo bootstrap manifest
和 lockfile，固定到这个完整远端 SHA。没有使用未推送 SHA、分支或自引用 commit。

隔离 bootstrap 的 `fvm dart pub get` 成功，逐字节复核 lockfile 只有 Plugin ref 改变；
`analyzer: 8.4.0` 与 `analyzer_plugin: 0.13.10` 均未升级。
[status](pin-release-status.log)和 [pin-check](pin-release-check.log)确认身份一致、
远端可解析以及 Plugin 生产代码没有 pin 后漂移。

Git 原生支持版本 tag，但现行 bootstrap 工具只接受完整 SHA；本轮未夹带 tag 解析、
锁定 SHA 一致性与移动检测的维护策略改动。当前真实 pin 仍以
[manifest](../../../demo/tools/ccrouter_analyzer_plugin_host/tools/analyzer_plugin/pubspec.yaml)
和 [lockfile](../../../demo/tools/ccrouter_analyzer_plugin_host/tools/analyzer_plugin/pubspec.lock)为准。

## 缓存、加载与编辑诊断

[初次 doctor](pin-release-doctor-before.log)通过依赖、分析和 loader 编译，同时保留了
旧 PluginManager cache 的 stale advisory。确认没有 SDK Analysis Server 进程后，将
完整旧缓存条目移动到独立可恢复备份，没有删除缓存或只移走其子目录。
新真实 Demo Server 重建后，[最终 doctor](pin-release-doctor-current.log)确认缓存 current。

真实 LSP 验证使用实际 Demo 根、其 bootstrap、默认 PluginManager 缓存和 SDK 官方
Analysis Server，不替换成本地 Plugin loader。只通过未保存 overlay 给第一个 Event
Contract 注入 `alias: 'toString'`：收到 `ccrouter_alias_invalid`，恢复原文后诊断清除。
正常退出后重新启动 Server，再次完成同样往返。两次 PID 不同，磁盘源文件保持原样。
缓存 manifest 与活动 bootstrap 一致，解析路径指向远端第一阶段 SHA。
见[输出](pin-release-lsp.log)、[结构化结果](pin-release-lsp.json)和
[脱敏后的执行探针快照](pin-release-lsp.py)。快照需替换本机路径后才能复现，不是通用 CLI。

[最终 Host freshness](pin-release-generation.log)命中内容一致 fast path 并通过；
没有重复执行第一阶段功能套件。真实 LSP 通过不代表现有 GUI IDE 会话已重启或加载新版。
本轮仍没有真机、长期内存、性能或 Hosted 发布认证。

本补充随 pin 同步提交保存；`0.3.0` tag 由 Git refs 标识最终提交，不在文档中构造自引用 SHA。
日志只机械规范化 home 路径与行尾显示空白，原件保留在任务临时目录。
