# CCRouter Contract 版本与兼容规范

本文从旧发布前计划中提取当前兼容规则；旧设计与当时承诺见[合并前快照](archive/20261024-consolidation/CCRouter-pre-release-capability-plan.md)。本规范说明现有校验，不表示已具备自动历史版本 diff、废弃周期治理或正式发布能力。

## 1. 身份与四类版本

| 值 | 用途 | 不能替代 |
| --- | --- | --- |
| Package SemVer | Pub 分发与解析 | Contract 版本与 shape |
| Component version | 组件实现身份/诊断 | 契约兼容证明 |
| Metadata schema | 工具读写格式 | 业务 API 版本 |
| Contract SemVer | 跨 Package 公共 API 的版本声明 | Owner、指纹和消费范围 |

五类 Contract 使用稳定的 kind、id、Owner component ID、version 与 shapeFingerprint。`CCContractKind` 当前只有 route/service/command/event/initTask；UI 使用独立 descriptor/requirement family，参见[UI 规范](CCRouter-ui-fragment-design.md)。不能通过增加 enum 值假定旧 exhaustive switch 可兼容。

同一 Host 的同一能力身份不能同时由不同 Owner 或不兼容描述认领；不得依赖“先注册的获胜”。破坏性 API 若需要并行迁移，可使用新 Contract ID 和显式适配流程，不让 Runtime 猜测两个形状。

## 2. 版本范围与 shape 是独立门禁

`CCSemVer` 解析严格的 `major.minor.patch[-pre][+build]`。范围支持精确版本、`*`、caret、tilde，以及空白分隔的一组比较器；空表达式在当前解析器中也表示任意版本。它不支持任意布尔表达式，不采用 Pub 的完整范围语法。0.x 仍按解析器的 caret/tilde 规则处理，没有“只有 exact 才合法”的额外 Runtime 限制。

消费者记录 requiredVersionRange 与 requiredShapeFingerprint。**版本处于范围内仍须精确匹配当前消费者记录的指纹**；minor 不能自动绕过 shape 变化。生成 Client 的具体范围来自当前生成声明，不手写 metadata 放宽检查。

公共形状变化后，Owner 应评估 SemVer、更新契约与消费者，并重新生成 Owner/Consumer/Host；行为语义变化即使指纹不变，也由 Owner 负责版本评审。框架不会仅根据 major/minor 自动证明源码或行为兼容。

## 3. 规范化指纹

生成器根据各能力的规范化公共 schema 计算确定性 SHA-256；以各 Builder 的 shape 输入为准。公共字段类型、必填/可空/default、方法签名、Route 参数/结果/地址及声明语义等可能影响指纹；不能只 hash 类型名称。注释、源码定位和生成时间不能成为兼容证据。

UI 的 enum/受限 DTO、嵌套 schema、默认值与公开导出规则由 UI 规范单独定义。enum 改 DTO 是破坏性变更，需要 major、消费范围更新与重生成；metadata schema 升级也必须拒绝不支持的旧工具。

指纹是混装/陈旧形状检测值，不是安全签名、权限凭证，也不证明 SDK/ABI、行为或发布来源可信。可信分发与 lockfile 仍由应用和发布流程维护。

## 4. 三层校验与失败

| 层 | 当前职责 | 不能据此推断 |
| --- | --- | --- |
| 能力生成 | 解析类型/声明，生成 descriptor、消费 requirement 和指纹 | 自动对比所有历史发布版本并判断 major/minor 是否正确 |
| Workspace/Host 聚合 | 校验 metadata 完整性、Owner、范围、指纹和生成输入，拒绝不一致 Assembly | Validator 会重新解析所有源码重算 shape |
| Runtime | 用同一兼容值作最终边界检查，发现混装/陈旧输出时拒绝 | 动态下载、协商、自动降级或选择另一个 Owner |

Workspace Validator 的基础 metadata 检查是 presence/syntax 校验，shape 计算由 Builders 完成。发现陈旧或不兼容输出，应修正声明和依赖并重新生成，不能跳过错误或伪造指纹。

五类 Contract 的稳定错误码为 `missing`、`ownerMismatch`、`versionOutOfRange`、`fingerprintChanged`、`duplicateImplementation`、`staleGeneratedOutput`。UI 有独立错误 family，不混用其 `missingImplementation` 等名称。诊断仅记录必要 identity 与错误摘要，不记录完整参数和业务对象。

optional dependency 只能表达允许缺失，不能把已存在但不兼容的实现当作未安装后静默跳过。

## 5. 升级流程与验证

1. Owner 评审公共 schema 与行为变更，确定版本和是否需要新 ID。
2. 更新依赖声明、消费范围和公共 Contract；重新生成 Owner、Consumer 与 Host。
3. 运行 `ccrouter generate <host-root> --check`，再运行适用的 Contract/Generator/Runtime 和业务闭环回归。
4. 发布候选保存 Index、fingerprint、兼容/不兼容样本与迁移说明，按 [Release Readiness](CCRouter-release-readiness.md)完成干净消费者与分发验收。

当前不应宣称自动提供历史版本 shape diff、major/minor 分类、`deprecatedSince` 废弃周期或删除前全仓消费者清零证明。这些属于后续治理需求，须先设计和实现。旧计划中的要求可作为发布评审输入，不能作为现有 API 调用依据。源码与历史验证见[统一索引](validation/README.md)。
