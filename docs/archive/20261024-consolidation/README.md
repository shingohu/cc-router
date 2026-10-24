# 2026-10-24 文档合并归档

本目录保存合并前的 18 份完整快照。正文只机械重定位相对链接，未更新旧 API、测试数量、设备环境或阶段完成状态；开头统一标记归档。使用当前能力请从[现行文档索引](../../README.md)进入。

合并减少独立维护入口；旧路径保留短指向页，避免历史链接失效。现行规范不从快照的勾选或历史“通过”推断发布准备完成。[Release Readiness](../../CCRouter-release-readiness.md)仍是唯一发布阻塞清单。

| 历史快照 | 现行维护入口 |
| --- | --- |
| [DevTools Host 自动装配](CCRouter-devtools-host-integration-plan.md) | [DevTools 与 Host 自动装配规范](../../CCRouter-devtools.md) |
| [Service 实施清单](CCRouter-service-completion-plan.md) | [Service 生命周期规范](../../CCRouter-service-lifecycle-design.md)、[Service Proxy 生成规范](../../CCRouter-service-proxy-generation-design.md) |
| [Cupertino Pop 手势](CCRouter-cupertino-pop-gesture-design.md) | [返回协调与平台手势规范](../../CCRouter-predictive-back.md) |
| [预测返回评估](CCRouter-predictive-back-assessment.md) | [返回协调与平台手势规范](../../CCRouter-predictive-back.md)、[验证证据索引](../../validation/README.md) |
| [路由专项分析](CCRouter-route-follow-up-analysis.md) | [Managed 路由与混合导航规范](../../CCRouter-route-design.md)、[返回协调与平台手势规范](../../CCRouter-predictive-back.md) |
| [类型化 UI Fragment 总设计](CCRouter-ui-fragment-design.md) | [现行规范](../../CCRouter-ui-fragment-design.md) |
| [UI Fragment Action payload](CCRouter-ui-fragment-action-payload-design.md) | [UI Fragment 规范：Action schema 与兼容](../../CCRouter-ui-fragment-design.md#action-schema-与兼容) |
| [UI Fragment 易用性审查](CCRouter-ui-fragment-usability-review.md) | [UI Fragment 规范](../../CCRouter-ui-fragment-design.md)、[独立首次接入技术验证](../../validation/ui-fragment-adoption-20261020/README.md) |
| [UI Fragment 实施验收](CCRouter-ui-fragment-acceptance.md) | [UI Fragment 规范](../../CCRouter-ui-fragment-design.md)、[验证证据索引](../../validation/README.md) |
| [Analyzer CLI 自动装配](CCRouter-analyzer-cli-plan.md) | [IDE / Analysis Server 与 CLI 规范](../../CCRouter-ide-analysis-server.md) |
| [路由总设计](CCRouter-route-design.md) | [现行规范](../../CCRouter-route-design.md) |
| [混合路由改造](CCRouter-hybrid-routing-design.md) | [Managed 路由与混合导航规范](../../CCRouter-route-design.md) |
| [路由完成计划](CCRouter-route-completion-plan.md) | [Managed 路由与混合导航规范](../../CCRouter-route-design.md)、[后续工作与触发条件](../../CCRouter-future-work-plan.md) |
| [正式发布前能力计划](CCRouter-pre-release-capability-plan.md) | [Contract 版本与兼容规范](../../CCRouter-contract-compatibility.md)、[后续工作与触发条件](../../CCRouter-future-work-plan.md)、[正式发布准备与门禁](../../CCRouter-release-readiness.md) |
| [后续任务与实施计划](CCRouter-future-work-plan.md) | [现行规范](../../CCRouter-future-work-plan.md) |
| [最终 API 阶段复审](CCRouter-final-api-review.md) | [当前能力与规范索引](../../README.md)、[正式发布准备与门禁](../../CCRouter-release-readiness.md) |
| [Navigator Backend 可行性](CCRouter-navigator-backend-feasibility.md) | [Managed 路由与混合导航规范](../../CCRouter-route-design.md)、[后续工作与触发条件](../../CCRouter-future-work-plan.md) |
| [IDE / Analysis Server 集成](CCRouter-ide-analysis-server.md) | [现行规范](../../CCRouter-ide-analysis-server.md) |

## 查阅规则

- 历史原因、旧实现、原验收数字：查快照；其中旧锚点继续保留。
- 当前 API、所有权、错误与能力边界：查映射中的现行规范和 Integration Skill。
- 源码回归与真实平台证据：查[验证索引](../../validation/README.md)，不把本次文档合并当作重跑。
- 未完成事项：查[后续工作](../../CCRouter-future-work-plan.md)；发布门禁只查 Release Readiness。
