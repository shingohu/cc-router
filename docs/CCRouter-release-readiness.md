# CCRouter 正式发布准备与门禁

## 1. 当前结论

- 状态：**尚不可发布到 pub.dev 或对外承诺 `1.0.0` 稳定性**。
- 当前 Package 版本：`0.1.0`，所有框架 Package 均保留 `publish_to: none`。
- 本文是唯一的发布执行清单；能力完成状态见 [文档索引](README.md)，未来能力见
  [后续任务与实施计划](CCRouter-future-work-plan.md)。
- 2026-09-29 已完成当前 Git tracked files 的首轮脱敏、Markdown 断链检查及 Android、
  iOS Simulator、macOS、OHOS 构建 smoke，但这不等于已经满足 Hosted 发布条件。

不能为了“看起来可发布”提前移除 `publish_to: none` 或批量升到 `1.0.0`。License、发布
Package 集合、版本承诺和 Hosted 目标必须由仓库 Owner 明确决定。

## 2. 发布阻塞项

| 级别 | 阻塞项 | 当前事实 | 完成条件 |
| --- | --- | --- | --- |
| P0 | 开源或商业 License | 仓库和各 Package 均没有 `LICENSE` | Owner 明确选择 License；每个发布归档包含有效 License |
| P0 | 历史凭据治理 | Git 历史曾提交 OHOS 签名密码和本机路径 | 轮换签名材料；决定并执行历史清理或形成接受记录 |
| P0 | 发布 Package 集合 | 当前尚未冻结哪些 Package 对外发布 | 明确必选、可选工具包和永不发布的 Demo/内部工具 |
| P0 | SemVer 基线 | 当前为开发期 `0.1.0` | 冻结 RC API；明确首发使用 `0.x` 还是 `1.0.0` |
| P0 | Pub 元数据 | 已补 `repository/homepage/issue_tracker`，仍保留 `publish_to: none` | 冻结版本后逐包开启目标 Hosted 并通过 dry-run |
| P0 | Package 文档 | 已有首发 README/CHANGELOG 骨架，内容尚未随 RC 冻结 | 每个发布 Package 具有面向其使用者的 README、CHANGELOG、LICENSE |
| P0 | Contract 迁移基线 | 核心兼容门禁已实现，但没有上一发布版归档样本 | 保存首个 RC Index；后续版本以该样本做兼容回归 |
| P0 | Analyzer 分发 | Demo 仍使用固定 Git commit bootstrap；无 GitHub 凭据环境可能在 Plugin fetch 阶段失败 | 发布 Hosted Plugin；保留固定 Git SHA 仅作发布前验证回退 |
| P0 | 干净消费者验证 | 2026-10-19 已通过独立本地源码快照的 Pub/生成/typed Route/释放闭环，见[证据](validation/consumer-adoption-20261019/README.md)；尚未验证发布归档/Hosted 和版本升级 | 从发布归档/Hosted 依赖创建最小 Flutter 工程并完成生成、运行和升级 smoke |
| P1 | 安全响应入口 | 已有基础 `SECURITY.md`，尚未形成稳定版响应承诺 | 发布前确认私密报告入口、支持版本和响应边界 |
| P1 | 长期质量趋势 | 首轮性能、RSS/Heap 和真机回归已做 | RC 再采样并保存结果；长期趋势不作为一次性发布任务冒充完成 |

首次执行 `fvm dart pub publish --dry-run` 确认缺少 `LICENSE`、Package README、CHANGELOG 和
`homepage/repository`。本轮已补齐后三类的首发骨架与元数据；License 仍需 Owner 做法律选择，
RC 文案和发布归档仍需再次 dry-run。这不是文档措辞问题，而是发布工具的真实门禁。

## 3. Package 发布边界

正式发布前应冻结以下三组，不允许发布过程中临时决定：

1. **基础依赖闭包**：`ccrouter_contracts`、`ccrouter_core`、`ccrouter`、
   `ccrouter_generator`。GoRouter 兼容包已移除，不在发布集合中。
2. **可选能力**：`ccrouter_ui`、
   `ccrouter_devtools_protocol`、`ccrouter_devtools`、`ccrouter_analyzer_plugin`、
   `ccrouter_test`。每个 Package 必须有独立使用场景和维护承诺，不能仅因已经存在就发布。
3. **不发布到 pub.dev**：Workspace 聚合 Package、`demo`、`demo/modules/*`、Demo Analyzer
   bootstrap，以及 `devtools/ccrouter_extension` 的应用壳。Extension 按 DevTools Extension
   分发流程处理，不伪装成普通业务依赖。

`demo_analytics`、`demo_analytics_flutter` 已迁到 `demo/modules/`，属于第三组的应用侧示例，
不属于框架 API、可选框架能力或发布集合。产品埋点由应用自行实现或接入既有平台。

Package 发布顺序按依赖 DAG 从叶子到门面执行。任何一个基础 Package dry-run 或 Hosted smoke
失败，后续 Package 不得继续发布。

## 4. 文档与安全门禁

这些仓库工具使用 Workspace 的开发依赖；干净 checkout 先在根目录执行
`CCROUTER_PUB_HOOK_DISABLE=1 fvm flutter pub get`，再运行下列检查。
这里只解析聚合根依赖，不代表任何成员 Host 已完成生成验证：

```bash
fvm dart run tool/documentation_check.dart
fvm dart run tool/skill_bundle_check.dart
fvm dart run tool/release_sensitivity_check.dart
```

`documentation_check.dart` 检查当前工作树中 Git 跟踪及尚未暂存、未被忽略的 Markdown
本地文件链接与图片。它与 Skill 分发检查共用 GFM 解析器，支持行内和引用式链接、平衡括号、
转义与 URL 编码，按 URL 规则剥离 query/fragment；跳过已删除文件及不会渲染为链接的代码、
注释和未使用引用定义。章节锚点、HTML 标签中的链接和远端可达性不在检查范围内。
诊断报告文件和解析后的目标，不推算解析器未提供的源码行号。它还要求
`docs/README.md` 和 `demo/README.md` 通过实际本地链接覆盖对应目录中的直接子文档，
正文提到文件名、图片或远端同名文件不能满足索引覆盖。
`skill_bundle_check.dart` 验证隔离的双 Skill 分发包引用与真实 CLI 帮助的一致性。
`release_sensitivity_check.dart` 检查当前 tracked files 中的常见凭据和本机绝对路径，
只报告位置和类别，不回显值。

这些脚本都不能替代 Git 历史 Secret Scanner。正式公开发布前还必须：

1. 使用发布平台 Secret Scanner 或经批准的 `gitleaks`/同类工具扫描完整历史；
2. 先轮换已经进入历史的凭据，再决定是否重写历史；
3. 检查 commit author/committer email 是否符合公开策略；
4. 检查发布归档，不只检查工作树；
5. 禁止把本地证书、Profile、KeyStore、`.env`、完整 URI、Token 或业务样本带入测试夹具。

历史重写、force-push、Tag 删除和已发布版本撤回都是破坏性操作，必须单独确认。

## 5. RC 回归门禁

至少执行：

```bash
fvm dart analyze packages
fvm dart analyze tool
fvm dart test tool/test
fvm flutter test packages/ccrouter_test/test
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test
fvm flutter test demo
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --check
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --check --no-cache
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo/modules/order/example --check --no-cache
```

Analyzer Plugin 不属于根 Dart Workspace，必须先从
`packages/ccrouter_analyzer_plugin/` 独立解析依赖，再在该目录执行：

```bash
fvm dart analyze
fvm dart test --concurrency=1
```

根目录的分析和测试不替代上述隔离包门禁。若同时交付 Demo，还须从根目录执行：

```bash
fvm dart test demo/modules/analytics/test demo/modules/analytics_firebase/test
fvm flutter test --no-pub demo/modules/analytics_flutter/test
```

并从 `demo/modules/order/example/` 执行 `fvm flutter test --no-pub test`。
父 Host 的生成与测试不能代替独立 Example Host 的检查。这些命令与
`.github/workflows/quality.yml` 的门禁配合使用；真机验收仍需另行完成。

随后执行 Generator 混合能力基准、Runtime 长运行/RSS，以及 Android、iOS Simulator、macOS、
Web、OHOS 构建 smoke。若同时交付 Demo，再独立执行应用侧 Analytics 队列压力；这不是框架
埋点能力或其上传可靠性承诺。真机矩阵必须注明设备、OS、Flutter SDK、时间和未覆盖项，
不能把 Simulator 结果写成真机结论。历史及最新证据按[验证索引](validation/README.md)查阅，
后续源码自动回归不能延续旧平台认证，也不自动关闭本文发布阻塞项。

每个待发布 Package 在移除 `publish_to: none` 后单独执行：

```bash
fvm dart pub publish --dry-run
```

dry-run 必须从 Package 根目录执行，并核对归档文件清单。不得在仓库 Workspace 根把 Pub Hook
误判结果当作 Package 依赖解析结果。

## 6. 文档冻结要求

RC 提交必须同时冻结：

- 根 `README.md` 的安装、最小接入、能力矩阵、限制和版本要求；
- 每个发布 Package 的 README、CHANGELOG、License 和 Pub metadata；
- `docs/README.md` 的当前状态矩阵；
- Contract 迁移说明、上一版本 Index/fingerprint 样本和兼容检查结果；
- Integration/CLI Skill 中的命令、API、生命周期和不支持能力；
- Demo 手动验证路径及实际完成的平台矩阵。

设计文档可以保留历史取舍，但必须在开头标明“当前契约、持续验证、完成快照、候选计划或
历史基线”。历史文档不能单独作为当前功能已实现的证据。

## 7. 发布与回滚顺序

1. Owner 确认 License、发布目标、Package 集合和首发 SemVer。
2. 创建 RC，生成并保存 Contract/Package Index 基线。
3. 完成全部文档、安全、生成、测试、性能和平台门禁。
4. 按依赖 DAG 发布 Package；每一步用干净消费者验证后再继续。
5. Hosted Analyzer/DevTools 分发完成后更新 Demo bootstrap 和接入文档。
6. 最后创建不可变 Tag 和 Release Notes，不让 Tag 指向未验证提交。

若发布中途失败，不覆盖已发布版本，也不复用同一版本号。修复后增加版本并重新跑完整门禁；
未发布 Package 保持 `publish_to: none`。Contract 发生破坏性变化时使用新 major 或新稳定 ID，
不能通过修改旧归档隐藏不兼容。

## 8. 完成定义

只有以下条件全部满足，才可以把仓库状态改为“可正式发布”：

- P0 阻塞项全部关闭并有可审查证据；
- 文档和敏感信息门禁通过，历史凭据已经轮换；
- 所有发布 Package dry-run 无 error，warning 有明确接受记录；
- RC 全量回归、无缓存生成检查和干净消费者 smoke 通过；
- 公开文档没有把候选、Demo 能力或持续观察项写成框架承诺；
- Release Notes、迁移说明、Tag、发布顺序和回滚负责人明确。
