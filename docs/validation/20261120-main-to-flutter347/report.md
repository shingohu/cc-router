# main 0.4.0 → Flutter 3.47.9 集成（2026-11-20）

按用户授权在独立 worktree 和 `codex/integrate-main-flutter-347` 上进行普通 merge，
保留双方历史，不 rebase 已发布分支。目标基线 `flutter-3.47.9@1cb8d9bc`，来源为
`main@ce2a251b`（Git tag `0.4.0`），共同基线 `ab20c157`，两边各有 8 个独有提交。

## 冲突处理与保留项

只读预演和实际合并均有 24 个冲突文件：9 份 Portable State、2 个 bootstrap pin 文件、
其余 13 个源码/测试/文档/CI 文件。逐个保留语义，不对所有文件统一选择 ours/theirs。

- 保留 Flutter 3.47.9 / Dart 3.13.7、Analyzer 13.3、build_runner 2.16.1 工具链、lockfile、
  原生工程迁移、Chrome CI、JS Runtime identity 和原生 Pop/Semantics 修复。
- 合入 main 的 Service Key、SemVer、Contract identity/requirement snapshots、nullable
  declarations、重复注解拒绝、Owner/Quick Fix、URI 与 Host/UI SPI 边界修复。
- InitTask 同时使用 Analyzer 13 的 NamedArgument/argumentExpression、main 的显式 null
  缺席规则和跨 SDK Duration backing-field 兼容；自动合并的 preflight 也逐项核对新 AST。
- Plugin 保留 3.47 的 annotation-table resolution trigger，并合入 main 的 borrowed
  UriConverter 和新的诊断/Quick Fix；Analyzer 8.4 / analyzer_plugin 0.13.10 继续隔离。
- 两边顶层新增测试分别完整保留。跨 Analyzer 的真实 metadata 测试改为 overlay-resolved
  unit 证明当前输入，以保留 main 新增的严格 Owner 规则；诊断、Quick Fix、修复后的重新
  分析及磁盘不变断言均保留。
- Portable State 仅暂存原分支副本作为 CLI 输入，最终由 3.47 工具链 portable prepare
  重建，不手工拼接 JSON 指纹。bootstrap 在第一阶段保留原 pin，合并实现推送后再单独更新。

README 中英文、Package guidance、integration/CLI Skills、IDE reference、CHANGELOG
和 validation index 保留两边适用内容。历史验证不自动延续为本次结果。

## 合并后验证

显式使用官方标准 Flutter 3.47.9 / Dart 3.13.7；根 Pub Hook 对聚合根禁用后解析，Plugin
从独立目录解析、分析、测试。静态分析首先确认新旧 AST 没有混用，再运行实际生成。

最初同时启动各套件时，InitTask 首个
Builder 用例在冷启动中超过默认 30 秒；该次超时保留为未通过，随后重试/全量结果另列，
不把超时改写成产品缺陷或成功。

完整 Generator 的两个新 watch 用例发现了测试前置条件问题：辅助函数生成
`ccrouter_test` Package 时，内部 Contract-first Route fixture 没有显式 public barrel，
在进入 watch 之前就被有效的导出校验拒绝。辅助函数现在只在当前测试期间创建窄化的
barrel，并用 teardown 移除它，同时保留原有受管产物 snapshot/还原。没有向稳定测试 API
永久导出 fixture，也没有放宽生产校验。两个用例重跑均通过，原始失败与修复后结果分开
归档。主跑其他用例继续执行；这两项由修复后的真实 watch 回归补齐。

最终结果如下；Generator 的全量原始失败记录保留，不能解释为一次全绿。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Generator 全量与修复后回归 | 原跑 861 通过、2 失败、1 默认跳过；修复后对应 2 项通过，共覆盖 863 项 | [全量](generator-full.log)、[重跑](watch-fixture-retry.log)、[对应核查](recovery-check.log) |
| 隔离 Plugin 全量 | 361 通过 | [Plugin](plugin-full.log) |
| Flutter 框架 | 1768 通过 | [摘要](framework-summary.log) |
| Demo | 118 通过 | [摘要](demo-summary.log) |
| Chrome Runtime identity / managed router | 4 通过 | [Chrome](chrome.log) |
| 工具 / Analytics Dart / Analytics Flutter / 独立 Example | 53 / 41 / 18 / 1 通过 | [工具](tools.log)、[Dart](analytics.log)、[Flutter](analytics-flutter-summary.log)、[Example](example-tests-summary.log) |
| 首轮定向 Builder / 参数 / preflight | 63 通过、1 冷启动超时；该项默认超时独立重试通过，全量也通过 | [原跑](targeted.log)、[重试](cold-retry.log) |
| 根 packages/tool、隔离 Plugin、Demo lib/test/modules 静态分析 | 均无问题 | [根](analyze-final.log)、[Plugin](plugin-analyze-final.log)、[Demo](demo-analyze.log) |
| Portable prepare / publish | 重建并校验 9 份状态，publish 为本地验证，无外部发布 | [prepare](prepare-final.log)、[publish](portable-publish.log) |
| Demo / Example 参考生成与 Demo 常规检查 | 均通过 | [Demo 参考](demo-reference.log)、[Example 参考](example-reference.log)、[Demo 常规](demo-normal.log) |

完整运行期间四份 Dart 文件由 3.47 formatter 规范化，无语义改动；watch fixture 修复后
重新验证两个失败用例、最终静态分析、Portable State 与参考生成。远端网络 analyzer
smoke 保持套件默认跳过。[源码清单](source-manifest.json)记录本阶段最终改动文件指纹。

## 分发与目标分支

先提交并推送合并实现，再用完整远端 SHA 独立更新 Demo bootstrap manifest 和 lockfile，
执行 pin-check、doctor、重启与诊断验证；最后合回 `flutter-3.47.9` 并推送。
main 与 `0.4.0` tag 不变，本任务不创建新 tag。

## 验证边界

本次覆盖标准 3.47 SDK 的框架/Demo/Chrome、Generator 和隔离 Plugin；不将前轮原生构建
或 OHOS canary 数字当成新验收。未验证 Android/iOS/macOS/OHOS 真机交互、重新签名构建、
Hosted 发布或设备内存采样。
