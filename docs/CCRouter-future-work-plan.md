# CCRouter 后续工作与触发条件

本文只维护未完成事项与立项条件，不复制已经完成的实施清单、历史测试数量或发布阻塞表。当前能力以[文档索引](README.md)与专项规范为准，证据见[验证索引](validation/README.md)；发布结论只看[Release Readiness](CCRouter-release-readiness.md)，当前仍不可正式发布。合并前计划保留于[归档](archive/20261024-consolidation/CCRouter-future-work-plan.md)。

## 1. 近期验证与开发工具

| 待办 | 启动条件与边界 | 规范/执行入口 |
| --- | --- | --- |
| 发布候选兼容样本、干净消费者与分发验证 | 进入 RC/正式发布流程；保留上一版本 Index、指纹和迁移样本，不从当前版本号推断已发布 | [Contract 兼容](CCRouter-contract-compatibility.md)、[Release Readiness](CCRouter-release-readiness.md) |
| 平台与长期性能/内存趋势 | 按候选源码与真实业务场景采样；自动化、构建 smoke 和单次实窗不替代设备矩阵 | [验证索引](validation/README.md)、[SDK 兼容](CCRouter-sdk-compatibility.md) |
| Flutter/Dart SDK 升级 | 尚未选择或升级目标；独立执行 U0–U6 的解析、工具身份、最小迁移、平台与分发验证 | [SDK 升级计划](CCRouter-sdk-upgrade-plan.md) |
| build_runner P6 传播与摘要优化 | 正确性前置、输入一致性屏障和测量先行；Shadow Closure 已删除，传播收窄及 P6-2/3 尚未实施；完整证明与净收益通过前无新默认 skip | [优化计划](CCRouter-build-runner-optimization-plan.md#12-p6生成状态摘要与依赖失效粒度优化) |
| Host 聚合输入摘要优化 | 只有真实工程聚合超过总耗时 20% 才继续；不能以 mtime/size 替代内容摘要；减少状态变更与缩短耗时分别验收 | [性能报告](CCRouter-generator-performance-report.md) |
| Analyzer 独立多根冷启动、完整 IDE/SDK/Hosted 矩阵 | 共享 Workspace 回归不关闭 legacy PluginManager 多实例边界，也不承诺监听分析根外依赖；Hosted 下载必须等待实际发布 | [IDE 与 CLI 规范](CCRouter-ide-analysis-server.md) |
| Contract scaffold/promotion/migration、alias migration | 真实接入证明重复成本；先定义安全迁移、Owner 与生成物一致性，不能靠跨包导入内部实现规避 | [注解校验](CCRouter-annotation-validation.md) |
| 官方 Extension 直接打开本地 IDE | 已有只读源码位置和复制 URI；需真实工具协议及多 IDE 验证后扩展 | [DevTools](CCRouter-devtools.md) |

UI 已有 enum/受限 DTO、生成、查找和本地首次接入技术闭环。未参与实现者的接入可用性、API 最终冻结、正式分发及长期性能仍需补证据；不将实施者自测当作新人研究。UI DevTools Catalog 尚未实现，是否新增取决于真实诊断需求。

## 2. 按业务需求触发的能力扩展

| 候选能力 | 触发与必须先解决的问题 |
| --- | --- |
| Service Proxy 高级类型 | 真实生产需求触发泛型 Contract、Stream、callback、继承或 Route Scope 方法代理；每项先定义 Owner、取消、释放、并发与版本兼容；现有受限泛型方法不等于通用支持 |
| 环境 Provider 选择 | 先使用 Composition Root、Service Key 和 Test Override；确有多个应用共同需求才引入 dev/test/staging/production 抽象 |
| Navigator 1.0 Backend | 真实渐进接入受阻时立项；先明确 root Outlet、readiness handshake、混合栈与结果通道 |
| 外部 Router Backend/attach | 原生 Managed 已使用 Navigator 2.0；这里指接入明确的外部 RouterDelegate/Pages 模型，不提供“万能 attach” |
| 原子组合栈、任意位置 replace | 已支持精确 Entry close；新增组合操作须有稳定身份、原子提交、失败回滚和结果/Scope 语义，不能把连续 push/pop 包装为事务 |
| 原生多窗口/多 Flutter View | 真实 macOS/Windows/iPadOS 应用触发；现有 MultiHost 聚合不等于 Window 创建、激活、关闭与 View 生命周期桥 |
| 完整 Route Restoration | 先由应用采集恢复需求；再设计版本化快照、契约校验、重新解析、部分恢复与安全降级；不在 Runtime 预置需求诊断队列 |
| 动态组件治理 | 先覆盖依赖级联、Handler/订阅清理、活跃 Route 协调、未完成调用取消与能力原子切换，再讨论 activate/deactivate/install/uninstall |
| Workspace/Feature Scope | 真实共享生命周期触发，不开放任意字符串层级 Scope |
| Action Pipeline | 只有动态来源需本地白名单、多候选处理器或真实仲裁缺陷才立项；先约束来源、优先级、短路、取消、超时、白名单与报告 |
| Host-owned Route Mount | [旧 Proposal](CCRouter-host-owned-route-mount-design.md)含历史 GoRouter 语境，须基于 Managed 与已有局部 Outlet 重新评估；不是现行 API |
| UI sealed union/集合/动态 Slot | 真实异构动作或多贡献者场景触发；不能用 Object/Map/函数 Props 绕过 schema；每项先定义兼容、实例身份与资源所有权 |
| Event Runtime Contract Registry | 仅在 generated SPI 需要成为严格防伪边界时评估；正常 Client、Workspace 校验和 publisher identity 已覆盖常规场景 |

[Action Pipeline 方案](CCRouter-action-pipeline-plan.md)仅作候选设计。新能力不能因为外部框架有同名功能就进入默认 API。

## 3. 保持应用职责的事项

布局 metrics、breakpoints、折痕解释与 pane 选择属于应用；Host 只投递已决定的 Outlet 可见性。产品 Analytics、Consent、供应商 HTTP/Crash/存储 Adapter、账号与环境切换策略放在应用或 `demo/modules/*`。恢复需求采集也由应用拥有。

不做默认 Widget 文本/Key 猜测、随机业务 ID、全局万能 Route 表、反射分派或任意 Map Contract。多个独立 Pub build root 不合并为一个 watch；嵌套 Host 各自持有 session/lock，跨 root 编排需真实样本证明。不为收尾新增单独 `ccrouter help`。

## 4. Framework Package 准入

新增 `packages/*` 前须同时证明：

1. 多个应用能复用，而非单一 Demo、产品或供应商策略。
2. 契约 provider-neutral，不内置业务事件、账号、上传、存储或环境切换。
3. Owner、生命周期、失败、隐私、性能与兼容语义能形成稳定契约。
4. Composition Root、`demo/modules/*` 或现有更窄 SPI 无法满足。
5. 依赖可选，不向未使用能力的应用传递供应商 SDK。
6. 有独立测试、回归矩阵与长期维护责任。

不满足时留在应用侧试验，形成多个应用共性后再评估晋升。

## 5. 执行顺序

先确认真实场景、版本与触发条件，列明候选取舍；再定义 Owner、生命周期、失败/取消和隐私边界，选择最小可回退路径。更新专项规范和接入指南后实现，按风险运行适用的 Pure Dart、Flutter、Generator 与平台回归，最后做生成一致性和文档检查。

当前发布阻塞不在本页重复打勾；回到 Release Readiness 逐项关闭。计划文字本身不授权升级 SDK、发布 Package、修改远端或更新 Demo pin。
