# Managed 工具链两阶段推送与 Demo Plugin pin（2026-10-24）

这是[本地工具链修复报告](report.md)的发布补充，不改写其修复前失败记录或回归数字。

## 提交与来源

第一阶段源码提交 `c066213027573f7c6dfe4900680d8c6ffb2df83f` 已推送至
`origin/codex/managed-navigation-runtime`，包含此前 Managed 重构、边界修复、工具链与文档收口。
随后才在独立提交中更新 Demo 的手工 bootstrap manifest 和 lockfile，使用上述完整远端 SHA。
没有升级隔离的 `analyzer: 8.4.0` 或 `analyzer_plugin: 0.13.10`。

Bootstrap 内执行 `CCROUTER_PUB_HOOK_DISABLE=1 fvm dart pub get` 成功，仅改变 Plugin Git 来源。
`ccrouter analyzer pin-check demo` 通过：manifest/lock/resolved-ref 一致、远端 ref 可解析、
Plugin 生产代码无 pin 后漂移。见[pin-check 原始输出](pin-release-check.log)。

## 加载与诊断验证

`ccrouter analyzer doctor demo` 通过锁定依赖解析、bootstrap 分析与 loader 编译。
它同时指出全局旧 IDE Plugin 缓存 stale；该 advisory 保留，未停止用户 IDE、移动或删除全局缓存。
见[doctor 原始输出](pin-release-doctor.log)。

真实 Language Server 验证使用当前 SDK 官方 JIT Analysis Server、实际 Demo 根与其已更新的
bootstrap；缓存单独置于临时目录，未替换为本地 Plugin 源码，也未修改 Demo 源文件。
对 `demo/lib/main.dart` 发送未保存 overlay，追加一条仅用于诊断的 Route：非法 Host ID、
自引用 parent、重复 policy。实际收到三个新诊断后，在 overlay 中修复并确认全部消失，
随后恢复原文并以 documentSymbol 请求确认探针已移除，磁盘源码保持原样。
见[真实 LSP 输出](pin-release-lsp.log)。

该新 Server 会话证明 Demo bootstrap 能从远端 pin 加载新版并完成编辑诊断往返。
它不等于现有 Android Studio 会话已重启或已清除其旧缓存；该现有 IDE 会话仍需按 doctor
提示自行重启/处理缓存，不能把临时 Server 的结果宣称为现有 IDE 会话验证。

第二阶段还复核静态分析、Demo 生成 freshness 和文档链接；未重复第一阶段已完成的重型回归。
