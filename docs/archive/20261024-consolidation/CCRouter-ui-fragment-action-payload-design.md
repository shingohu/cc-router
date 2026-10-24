> 归档日期：2026-10-24。原路径：`docs/CCRouter-ui-fragment-action-payload-design.md`。
> 此文件保存文档合并前的设计/实施快照；相对链接已重定位，正文中的旧 API、阶段状态与测试数字不代表当前能力。
> 现行入口与合并映射见[归档索引](README.md)。

# UI Fragment 类型化 Action payload 设计与验证

状态：最小 DTO Action 路径已实现，仍为待发布、未冻结能力。保留原 enum 路径，
新增受限单 DTO 输出，不增加 Runtime 公共 API；sealed union 继续延期。
实现与仓库验证记录见文末，生产接入和新人可用性实测不在已验证范围内。
当前操作步骤以[UI 接入指南](../../../skills/ccrouter-integration-development/references/ui-fragments.md)为准；
[独立首次接入验证](../../validation/ui-fragment-adoption-20261020/README.md)提供后续本地技术闭环、
复现源码与手工成本，区别于正式分发、真实业务和未参与实现者的接入验收。

## 问题与场景

1. 推荐项选择：A 传 category；B 私有请求并展示推荐列表；点击后 A 必须收到实际 selectedId，
   再决定是否打开详情。ID 不在 A 的原始 Props 中，enum 通知无法表达结果。
2. 设备项选择：A 传筛选条件；B 负责发现与展示设备；点击后 A 收到 deviceId，决定后续流程。
   扫描与连接资源仍属于 B State 或其有明确所有权的 Service。

这两个场景属于通用的实例局部输出能力。全局选择状态、Service getter 和广播 Event 会使
输出归属、并发实例和请求时序变得不明确，不能作为等价替代。
若只需展示复用，普通公共 Widget + 类型化 callback 仍是成本最低的选项。

## 候选与推荐范围

| 方案 | 收益 | 代价与决定 |
| --- | --- | --- |
| 保持 enum，使用普通 Widget | 无框架改动，支持普通数据型 callback | 缺少 Fragment 契约版本和静态实现装配；继续支持这种选型 |
| 允许单个不可变 DTO Action | 两个单一选择结果可直接表达；复用 Props schema 校验 | 新增兼容和生成规则；本轮实现此范围 |
| sealed union Action | 多种动作携带不同 payload，可避免非法字段组合 | 类型闭包、穷尽性、指纹和代码生成成本更高；以真实异构动作需求触发 |
| Object、Map 或任意 callback | 表面上通用 | 丢失静态契约与兼容证明，不采用 |

本轮范围：保留 enum；新增 public final class、const 生成构造器和 public final 存储字段的
单 DTO Action。示意结果是 `RecommendationSelected(selectedId: ...)`，而不是多个动作共享
`kind + nullable fields`。Generator 与 Plugin 均识别该受限类型。
根 Action 只允许普通 enum 或受限不可变 DTO；scalar 不能直接作为 Action。
DTO 字段仅接受受限 Pure Dart scalar、普通 enum 和嵌套 DTO，继续排除 Flutter 对象、Object/dynamic、
函数、Future/Stream、泛型集合及带行为成员的类型。对多种异构输出先评估 union，
不把单 DTO 宣称为已解决全部 Action 建模。

## 契约、版本与发布

- 业务仍通过自身生成 Client 的 `onAction` 收到精确类型；不新增字符串 dispatcher、全局
  payload store、Event 桥接或业务可访问的 Host/Registry。
- enum-only 契约保留 UI schema 1 及原指纹算法和生成签名，作为兼容对照。
- DTO Action 使用 UI schema 2；涉及该形状的 Contract、Renderer 和 consumer metadata
  都带匹配版本。混合文档应声明其所需最高 UI schema；旧 Generator 必须明确拒绝。
  DTO Package Index 升至 schema 4：真实旧 schema 3 读取器会直接接受 Index 3 的 metadata，
  因此仅改变内部 UI 版本不能保证只读查询拒绝新能力。旧读取器已验证明确拒绝 Index 4。
- Action 字段类型、nullable、构造参数/default、嵌套类型与公共导出纳入 shape fingerprint。
  指纹记录形状，不包含运行时业务值。enum 改为 DTO 是破坏性契约变更，需要 major SemVer，
  更新消费范围并重生成 A/B/Host；不会自动把原 enum 解释成 DTO。
- Generator、Analyzer、运行时 UI 包和分发来源必须按验证过的组合发布；不静默升级 SDK
  或 analyzer 约束。新 Plugin 行为仍走独立提交、远程 SHA、Demo pin 两阶段流程。

## 所有权、时序与失败

- B 创建不可变 Action 值；A 的实例局部同步 callback 接收值并决定业务操作。
  Action 不持有 Context、State、资源所有权或释放句柄，不需要框架 dispose。
- 保持 mount、active、Runtime generation 防护。隐藏时停止分发；卸载、shutdown 或
  旧 generation 的 callback 不得影响新挂载。恢复后不重放期间丢弃的 Action。
- 保持现有“调用最新 callback”语义。Props 更新本身不代表旧请求结果仍有效；B 根据
  请求相关 Props 和 revision 取消工作或丢弃旧结果。A 若有异步决策，也需检查当前账号/实例。
- Session 变化由应用清理私有数据、失效请求或更换子树 Key；不在 payload 中隐式引入
  框架 Session、Fragment Scope 或导航结果 Future。
- callback 抛错遵循现有 Flutter 错误处理，不吞错、不重试、不转 Event。
  加载失败、空列表、取消、超时与重试仍由 B 的业务 UI 和请求所有者处理。
- catalog、诊断、Trace 不保存 payload、selectedId、Context 或 callback。热路径直接传递
  类型化值，无 JSON 编解码；跨进程、持久化及 Deep Link 不在范围内。

## 验收边界与仓库记录

- 跨 Package fixture 覆盖 `selectedId` 和 `deviceId`；字段类型/default 进入 fingerprint，
  非 final、非 const、Object、集合、行为成员等类型被拒绝。嵌套类型继续走同一 schema 和公共导出校验。
- enum-only metadata 与生成 Client 对照修改前 Builder；Demo 的 `order.summary` 完整记录
  在规范化 JSON 后不变，保持原 UI schema、签名和 fingerprint。
- DTO Contract/Renderer/consumer 都标记 UI schema 2；混合文档采用最高版本。测试覆盖
  文档降级、record 版本混用、旧范围与新 major 不匹配、Index 4 roundtrip 和误标旧 Index。
- Demo A 使用真实生成 Client 收到 B 私有加载的 `recommendation-7301`；两实例返回各自 ID，
  快速 Props 更新丢弃旧结果，隐藏禁用选择，卸载取消 Timer 并释放 controller。
- 运行时 DTO 回归覆盖最新 callback、实例隔离、隐藏/恢复、账号 Key 重建、卸载、shutdown
  与重建；Action 仍直接经过原泛型分发闭包，无序列化、全局 payload 表或新资源所有权。
- Plugin 接受受限 DTO，拒绝确定的非法形状；完整构造器、default、公共导出与 Host 闭包仍由
  Generator 校验。UI schema 2 Owner metadata 继续提供 required-edge 检查及现有 Quick Fix。

首轮仓库验证结果（2026-10-20；后续 review 修复复验见下）：

| 验证 | 结果 |
| --- | --- |
| 根目录、隔离 Plugin analyze | 均无问题 |
| Framework 全量 | 566 项通过，包含 13 项 UI 专项 |
| Generator UI/Package/Workspace/工具回归 | 65 + 78 项通过 |
| Plugin 全量及新增 DTO LSP | 172 项全量通过；新增 1 项另跑通过 |
| Demo 真实 Host UI | 3 项通过 |
| 修改前 Builder 对照 | enum metadata/Client 字节相同；旧 Builder 拒绝 DTO，2 项通过 |
| 实际旧 Index reader | 明确拒绝 DTO Index schema 4 |
| Demo Portable | 9 Package 就绪；缓存及无缓存 `generate --check` 通过 |
| 文档、Skill bundle、release sensitivity | 通过 |

后续 review 修复收紧根 Action 校验，并补全脚手架 Consumer 的 UI import。
新增回归覆盖 5 种 scalar 在 metadata/Dart 两种生成路径被拒绝、DTO scalar 字段继续可用，
并从脚手架打印步骤构造 Consumer，验证真实 Builder 生成 UI requirement。
UI Generator、脚手架及查询回归共 76 项全部通过。
本次修改文件的 analyze、文档/Skill 检查和 Demo 无缓存 `generate --check` 通过。
随后修复 Demo 测试的跨包生成文件 import：把双实例组合移至导航组件的
`test/support/recommendation_pair_fixture.dart`，Host 测试通过测试 fixture 使用真实装配。
生成 UI Client 仍只在所属组件内导入，未扩大业务导出、屏蔽诊断或新增反向 Package 依赖。
全仓 analyze 恢复通过；Demo 全部 7 个测试文件共 62 项通过（UI 专项 3 项，其余 59 项）。

以下 Plugin SHA 与 IDE 状态为该次验证快照，当前 pin 以 Demo 实际 bootstrap manifest/lock 为准。
Plugin 实现已独立提交并推送：`51c5b3892928337e7c7728fa9dd6845ac2f93b2e`；
Demo pin/lock 在后续独立提交 `c06a124` 更新。`analyzer pin-check demo` 确认远程 SHA
可解析、生产源码无 drift；doctor 的锁定依赖、bootstrap analyze 与临时 loader 编译通过。
另启动使用实际 Demo bootstrap 的全新 Analysis Server，通过 unsaved overlay 验证非法 DTO
诊断出现、修为 final DTO 后清除；未落盘测试文件。现有 Android Studio 窗口未重启，
doctor 的旧 legacy cache 提示仍存在，不能据此声称用户当前 IDE 会话已更新；未移动或清理缓存。

本轮不以 API 冻结为验收结论。sealed union、设备发现 SDK/真实设备矩阵、生产数据隐私验收、
完整 enum/DTO 分配与性能基准以及未参与实现的新接入者计时均未完成，不宣称已经验证。
UI 脚手架继续默认生成 enum；无需新增占位开关，确需输出私有加载 ID 时再改为 DTO。
后续 Plugin 生产变更继续遵守独立提交、远程完整 SHA 与单独 Demo pin/lock 的两阶段流程；
本地 fixture 测试不能替代实际 bootstrap 的验证。

Host 可按应用构建配置选择普通 Widget 或 DTO Fragment 路径对比。回退时恢复旧契约、消费范围
并重生成 A/B/Host；不能将 enum 生成物和 DTO 契约混用。首次接入工具减少模板成本，
仍需完成 contracts、B、A、Host 的显式依赖与所有权声明。
