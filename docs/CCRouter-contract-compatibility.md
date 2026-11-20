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

`CCSemVer` 解析严格的 `major.minor.patch[-pre][+build]`，版本值不接受首尾空白。
Route、Service、Command、Event、InitTask、UI Contract 与 Component 的 Generator 校验
复用同一解析器，Workspace/Host 对外部 metadata 保持同样的边界。范围表达式自身可有外围
空白，caret/tilde 后原有的空白处理也保留；这不允许已安装的版本值携带空白。

范围支持精确版本、`*`、caret、tilde，以及空白分隔的一组比较器；空表达式在当前解析器中也表示任意版本。它不支持任意布尔表达式，不采用 Pub 的完整范围语法。0.x 仍按解析器的 caret/tilde 规则处理，没有“只有 exact 才合法”的额外 Runtime 限制。


预发布标识只有纯十进制数字才按数值比较；`0x10`、`-0` 等属于非数字标识，不等于 `16`、`0`。
数字预发布标识按位数和字典序比较，不受机器整数位数限制；major/minor/patch 仍使用 Dart int。
caret/tilde 上界不通过整数自增构造，避免已接受的大版本值溢出。范围继续使用原有字面比较器
语义（包括下一 core 的 prerelease 边界），不额外引入 Pub/npm 的预发布过滤策略。


兼容错误按输入归因：Owner 的安装版本损坏只归到 Owner，合法消费者范围不会被追加“范围无效”。
若两侧输入都损坏则分别报告；合法但超出范围仍报 `versionOutOfRange`。
UI Host 对损坏的版本/范围统一抛出脱敏 `CCUIFragmentError('staleGeneratedOutput', id)`，
不会向调用方泄漏包含原始版本字符串的 `FormatException`；合法范围不匹配的错误码保持不变。


五类 Core ContractBundle 的最终门禁也核对已安装 descriptor 与消费者 requirement 的身份：
能力 ID 最长 128 字符，Owner 最长 128 字符且使用 lowercase component 规则。
即使两侧填写一致，空值、非法或超长身份仍报 `staleGeneratedOutput`；格式损坏的消费者
fingerprint 同样报生成物无效。合法但不同的 SHA-256 继续报 `fingerprintChanged`，
不会把损坏输入误当成真实公共形状变更。Host/Runtime 在启动前执行同一检查。


Host 合并 ContractBundle 时保留同一消费身份的所有不同范围约束；范围和 fingerprint 也纳入
完整 requirement 的去重条件。仅完整字段相同才去重，不按输入顺序选择一个范围，也不自动
计算或重写范围交集；合并快照的再校验结果应与原始约束一致。


CLI 输出 Package ContractBundle 时同样保留消费者 metadata 已有的范围和指纹快照；
只在旧 metadata 缺少字段时按既有规则补齐精确版本/指纹，不把已有范围重写为 Owner 当前版本。
InitTask 的依赖快照也遵守此规则；已有 Owner 与当前 Contract 不符时在 Workspace 提前报
`ownerMismatch`，不同范围不被按身份静默去重。源码 API 不新增 `versionRange` 参数。

消费者记录 requiredVersionRange 与 requiredShapeFingerprint。**版本处于范围内仍须精确匹配当前消费者记录的指纹**；minor 不能自动绕过 shape 变化。生成 Client 的具体范围来自当前生成声明，不手写 metadata 放宽检查。

公共形状变化后，Owner 应评估 SemVer、更新契约与消费者，并重新生成 Owner/Consumer/Host；行为语义变化即使指纹不变，也由 Owner 负责版本评审。框架不会仅根据 major/minor 自动证明源码或行为兼容。


IDE 的 Contract Owner 身份还包括定义它的 Library：同一 Package 中同名且同 Owner 的
Contract 不会互相覆盖；共享 named part 的不同 Library 也分别识别。Service/Command 的 part
metadata 保留原源码 `packageUri`/行列，并补充可选 `libraryUri`，catalog 往返不丢失该字段。
旧 metadata 仅缺该证据时可被一致的新记录补全；明确冲突、带 query/fragment 或非便携 URI
不会回退猜测，IDE 暂缓该 Owner 诊断/Quick Fix。旧 part metadata 需重新生成以补齐身份。

此处 Library 证据属于源码身份/定位 metadata，不改变业务 Contract shapeFingerprint。

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
