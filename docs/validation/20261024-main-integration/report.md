# main 与 Managed 分支整合验证

日期：2026-10-24。仅在 `codex/managed-navigation-runtime` 合入 `origin/main`，
不回退或推送 main，不移动 `0.1.0` 标签。

## 输入与冲突决策

- 整合前分支：`b01d1d3b32341c148a8b34adc97c2e6238739037`。
- main：`12a6b0fb9746195dfeeb2e8583bfeb9565700836`，也是 `0.1.0` 的 peeled commit。
- 共同祖先：`9af16ed488e5545e3ed419b41d1126f6f8df590c`。
- main 独有一个提交，Managed 分支独有十五个提交；实际 merge 出现 23 个冲突路径。

不能整批忽略 main 的最后一次提交：其中确实存在当前分支遗漏的 Route Service 隔离保护。
本次保留两边历史，以 Managed 为导航实现，逐项吸收仍适用的修复。

| main 改动 | 整合结果 |
| --- | --- |
| exact Entry handle、四种 close outcome、可选 Adapter SPI | 保留 Managed 已有实现及 Entry/Host/Runtime 结束时的等待收敛、Host Zone 与迟到回执保护 |
| 目标 Guard、结果类型先验、单次结果与 Scope 清理 | 保留现有实现；main 的十个 Core 用例完整保留，通过内部 Runtime bridge 获取测试句柄 |
| Route Service 的 Runtime generation 隔离 | 合入统一校验，覆盖四个同步/异步、可选/必需查询；不提前结束合法退出动画 Scope |
| 快照仅供诊断，不能成为导航控制入口 | 去掉快照中的 handle；业务仅通过所属页面 Context 捕获。内部身份读取 Extension 从业务 barrel 隐藏 |
| GoRouter Adapter 与 targeted-close match-tree 实现 | 保持既有删除；排除 Git 推测的错误文件迁移，不恢复 GoRouter 包或依赖 |
| README、Skill 与设计文档 | 保留 Managed 当前能力矩阵和已归档的历史说明，补入隔离与只读边界 |

同时排除了自动合并产生的重复 `close` 声明/实现。Demo Revalidation 用
sanitized `routeEntryId` 对照已捕获的目标，而不是从观察快照获取控制句柄；需要实际 close
的集成测试从所属页面 Context 捕获，Core 测试才使用底层身份桥接。

## 问题复现与闭环

[Route Service RED](route-service-red.log)：外来 Runtime payload 复用当前 Navigation ID，
四个查询均错误返回了当前资源，预期四个 Scope 错误却实际为零。恢复统一 generation
校验后，该用例及 shutdown/reinitialize 后仍挂载页面的四个查询全部通过。

[API 边界 RED](api-boundary-red.log)：业务 barrel 未隐藏内部 Extension，且快照仍有
可执行关闭的 handle。加入真实 Analyzer probe 后两项失败；最终完整回归已通过。

迁移中的首次静态分析还发现 Demo Revalidation 仍读取 `entry.handle`，已改为 ID 比较。
[独立 Example 首次命令](generate-example-invocation-failed.log)在进入生成器前被
`dart run` 隐式 Pub 解析阻断：Flutter Workspace 中 `webview_flutter` 需要 Flutter SDK。
显式绑定现有 Package Config 后生成检查通过；该失败不记作生成器执行失败或成功验证。

## 最终验证

环境：macOS；FVM Flutter `3.41.10-ohos-1.0.0` / Dart `3.11.5`。
命令从仓库根执行，特别标明的 cwd 除外。所有测试串行执行各自的用例。

| 检查 | 结果与证据 |
| --- | --- |
| `fvm dart analyze` | 无问题，[日志](analyze.log) |
| Demo cwd：`fvm dart analyze` | 无问题，[日志](demo-analyze.log) |
| `fvm flutter test --no-pub --concurrency=1 --reporter expanded packages/ccrouter_test/test packages/ccrouter_devtools/test packages/ccrouter_devtools_protocol/test` | 1,447 项通过，[日志](framework.log) |
| Demo cwd：`fvm flutter test --no-pub --concurrency=1 --reporter expanded` | 114 项通过，包含固定 seed Monkey、Shell、exact close、Revalidation 与 iOS 手势 Widget 回归，[日志](demo.log) |
| `fvm dart test --concurrency=1 tool/test` | 52 项通过，[日志](tools.log) |
| Generator 的 `route_api_boundary_test.dart` 与 `internal_api_boundary_validator_test.dart` | 3 项通过，[日志](generator-api.log) |
| `fvm dart run ccrouter_generator:ccrouter generate demo --no-cache --check` | 6 组件、34 路由、11 Packages 一致，[日志](generate-demo.log) |
| `fvm dart --packages=.dart_tool/package_config.json packages/ccrouter_generator/bin/ccrouter.dart generate demo/modules/order/example --no-cache --check` | 2 组件、2 路由、3 Packages 一致，[日志](generate-example.log) |
| 独立 Example cwd：`fvm flutter test --no-pub --concurrency=1 --reporter expanded` | 1 项通过，[日志](example-test.log) |
| 文档、隔离 Skill bundle、敏感信息与源码 diff whitespace 检查 | 通过；日志中的原始错误输出空白不作为源码格式检查对象 |

整合期间另有 [58 项专项验证](focused.log)，包含 targeted close、Route Service、API
surface、parent stack 与 scoped navigator。其用例包含于最终完整框架 suite，不重复加总。
源码冻结后完成最终 suite 和实际 Host 检查；没有手工修改生成文件。

## 边界

本次不是平台实窗/真机验收，没有重跑 macOS 手工点击、Android/iOS 真机手势、长期
性能或原生 heap 测量；历史设备证据不自动升级为本次验收。本次没有新增 Timer、订阅、
外部依赖或业务导航参数；generation 校验为已有页面绑定上的身份读取，不据此声称零开销。

未重跑 Generator 全量与隔离 Analyzer Plugin suite；此次未修改二者生产代码或 Demo Plugin
pin。以前 Generator 全量的失败/单项复验仍见原[诊断报告](../20261024-diagnostics/report.md)，
不能把它改记为全量通过。远端 Quality 仅在 PR 或 push main 触发，本地通过不代表远端 CI
已通过。正式分发仍遵守[发布门禁](../../CCRouter-release-readiness.md)。
