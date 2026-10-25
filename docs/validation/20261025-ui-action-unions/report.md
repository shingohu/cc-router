# UI Fragment sealed Action 与嵌套联合验证（2026-10-25 至 26）

本轮于北京时间 2026-10-25 启动，2026-10-26 完成。

对应 [Issue #2](https://github.com/shingohu/cc-router/issues/2)。源码基线为
`cd776d9726a50c9011375dadb6d69d89d2a95c98`；工作位于独立
`codex/sealed-action-unions` 分支。框架修改的内容摘要见
[source-sha256.json](source-sha256.json)。本记录不替代原有平台或发布门禁。

## 问题、方案与边界

原 Generator 和 Plugin 明确只接受 enum/受限 DTO；异构 Action 不能在保持各变体
字段约束的同时用单 DTO 表达。采用独立的 UI schema 3 路径，Package Index 5 让旧工具
明确拒绝；保留 enum schema 1 / Index 3、DTO schema 2 / Index 4 的算法和工作流。
Props 不开放 sealed，Runtime/Core/UI 的生产实现没有改动。

支持根 Action 和 DTO 载荷中的嵌套 sealed 联合、基类 public final 字段、const
`super.field` 转发及隐式 const super。每个根直接继承 Object，同库/part 中的变体是
无进一步子类型的 public final 数据叶子。拒绝开放/私有/泛型变体、implements、mixin、
字段覆盖、行为、资源、有环图、factory、重定向和显式 initializer/assert。
生成展开限制为 32 个数据层级、512 个节点。完整约束见
[UI 规范](../../CCRouter-ui-fragment-design.md#action-schema-与兼容)。

指纹包含完整排序变体集、继承字段、构造参数及转发、有效默认值和常量的具体类型。
不同变体携带相同字段值仍得到不同形状；声明顺序及在同库 part 间移动不改变形状。
新增/删除变体与破坏性嵌套形状变化按 major Contract 变更处理，重生成 A/B/Host。

现有同步、实例局部 sink 继续持有最新消费方回调；active、卸载、identity 和 Runtime
换代规则不变。Action 不引入序列化、全局队列、导航 Future 或业务 Session 所有权。
新 schema reader 只在 Builder 调用中使用 Resolver，不保留全局 Analyzer/业务对象。

上线/回退以类型选择和生成版本隔离：只有 Action 图包含业务 sealed 联合时才启用
schema 3；旧 enum/DTO 持续走原路径。Generator 拒绝非法或不匹配模型，没有动态 Map、
反射或静默降级。回退时恢复旧声明/工具组合并重生成 A/B/Host，不能把 Index 5 改标为旧版。
新增 Demo 能力与旧两个能力并行，不替换旧协议。无需新增 Core API 或 Runtime 开关。

编译期图限制用于约束生成成本，不构成启动或热路径性能提升的证明。运行时仍直接同步
调用消费 callback，没有新增队列、重试、任务取消或并发仲裁；B 的异步请求与 A 的设置
导航/账号清理仍由应用管理。生成错误定位模型，现有有界 ignored-action 诊断不记录载荷。

## 回归证据

- enum 与 DTO 的修改前指纹分别固定为
  `00ada274a3626f31de2b44ebd56e4818ede659e4fdc961fb69a146fb2bf88dca`、
  `d8ee3f0b589e35ebdecf41c5454de61383b9e53ab4284ce122896df1768e474e`。
  新路径的测试同时检查旧指纹不变与 40 层旧 DTO 继续可用。
- Generator 的 union 专项覆盖根/嵌套/跨包/part、精确生成类型、继承字段与默认值、
  变体身份、公开类型闭包、确定性、非法模型和图限制。
- 框架 Widget 测试覆盖五种动作/目标的原实例交付、两个实例隔离、最新 callback、
  inactive/resume、Key 重挂、卸载、shutdown 与旧 generation。
- Demo 新增 `order.panel`，与旧 enum/DTO 示例并存；真实生成 Host、Renderer、消费 Client
  和穷尽 switch 已由 Widget 测试验证。Demo 117 项通过，独立 Order Example 1 项通过。
- 框架完整串行套件 1642 项通过；DevTools/协议 24 项通过。
- Plugin 隔离套件 202 项通过，后补的旧深层 DTO 保守退让测试单独 1 项通过。
  analyzer 固定 8.4.0、analyzer_plugin 固定 0.13.10，没有升级约束。
- 原基线 Generator 实际读取 Index 5 时明确拒绝，见 old-reader.log。
- 独立 Git/源码归档分发测试验证 Index 5、Portable State、只读消费者、源码/依赖/输出
  篡改拒绝、part-only 继承字段变化，以及 `--check` 恢复和恢复源码后的确定性。
- 全量测试结束后，Demo 与独立 Example 的 `generate --no-cache --check` 再次通过；
  `portable publish demo` 检查 9 个 Package 的状态就绪，仅为本地验证，不对外发布。实际 Demo 目录中的
  `flutter pub get` 触发并完成 Pub Hook，根 Workspace 的 Pub 成功未冒充 Host 生成证据。

最终 Generator 完整套件 **701 项通过，1 项按默认配置跳过**，见 generator-final.log。
跳过项为 opt-in 的远端 install/upgrade/uninstall smoke；本轮另有实际远端 pin-check、doctor
和实际 Demo 根的新 Server 验证。完整运行前后修改过的 Generator 源码摘要一致。命令为：

```sh
fvm dart --packages=.dart_tool/package_config.json <resolved-test-package>/bin/test.dart \
  --concurrency=1 packages/ccrouter_test/generator_test
```

`<resolved-test-package>` 来自根 `.dart_tool/package_config.json` 中已解析的 `test`，
本轮为 test 1.30.0；它与 `fvm dart test` 使用相同 runner 和测试根，避免该定制 Flutter
SDK 下 Dart 命令隐式重新解析 Flutter-only 依赖。

## 发现的路径问题与验证过程纠正

新增独立 UI 分发夹具揭露了原公共 barrel 索引的路径比较问题：Pub 的 Package 根
带尾部 `/` 时，导出目标和类型来源的词法路径不一致，导致合法的显式 `show` 被误拒。
先加入 trailing-slash/dot-root 失败测试，再统一索引和目标的词法路径身份。没有放宽
显式导出、hide/conditional/namespace 或 Package 所有权规则。

框架首轮默认并发运行有一项既有 Route GC 断言失败：
`live Adapter releases old Routes after renderer remount`。该文件单独 26 项通过，随后完整
串行套件 1642 项通过。保留首次失败，不把一次 GC 断言失败直接归因于已证明的泄漏，
也不删除或放宽原断言。参见 framework-first.log 与 framework-serial.log。

第一轮 Generator 全量启动时，执行环境带全局 Pub Hook bypass，且另有手动 Demo
生成与真实 Workspace watch 测试并行。出现 watch 退出/Hook 输出错误，故中止这一轮，
不计为验收通过。最终一轮不设置 bypass，独占所有真实 Workspace 生成操作，生产源码
保持不变。参见 generator-interfered.log 与最终日志。

后续稳定环境全量回归又拦下一处真实兼容错误：SDK 的 `num` 本身是 sealed，最初的
新路径探测将含 num 字段的旧 DTO 误选成 schema 3（原测试明确要求 schema 2）。修复将
探测限定到 package 声明的类型，SDK 标量不会启用 schema 3；原有全标量测试复跑通过，
union/旧指纹/深层 DTO 专项 29 项通过，随后再次从头执行完整 Generator suite。
这轮红灯与修复后输出分别保存在 generator-before-scalar-fix.log、scalar-green.log 和
union-final.log；没有放宽原断言或将失败视为预期。

该 OHOS Flutter SDK 的普通 Dart 命令还可能因隐式 Pub 重新解析 Flutter-only 依赖而
失败。本轮先通过 Flutter 完成依赖解析，再用相同 FVM Dart、根 package_config 和解析
到的 test runner 入口执行 Generator suite；未更换 SDK、依赖或测试根，也未禁用 Hook。
无效 Pub/测试入口调用不计入成功测试。

## Plugin 两阶段来源与真实 Server

Plugin 第一阶段提交 `f3a0296acd666a2d9b14ef358261a393d3e2c113` 已推送到
`origin/codex/sealed-action-unions`。此后才在单独提交中更新 Demo bootstrap manifest 和
lockfile，指向该远端完整 SHA。`pin-check demo` 验证远端可解析、manifest/lock/resolved-ref
一致，且 Plugin 生产代码无 pin 后漂移。

`doctor demo` 完成锁定依赖、分析及临时 loader 编译，同时保留全局旧 IDE 缓存 stale 的
advisory。未关闭用户 IDE、移动或删除其全局缓存。

两层真实 Analysis Server 验证分别为：

1. 新 Server 从该 Git pin 的实际包配置加载 Plugin，验证未保存 part 修复后的诊断往返；
2. SDK 官方 JIT Server 使用实际 Demo 根、实际远端 bootstrap 和临时缓存，对 Demo
   `main.dart` 的未保存合成 union 探针先报告开放叶子，再接受 final/嵌套/super 字段修复，
   最后恢复原 overlay，并核实 Demo 磁盘源码未变。

最初对嵌套 contracts Package 文件的 Demo 探针未收到诊断，未计为通过；实际 Demo
验收使用 Host main.dart overlay，part 行为由隔离的真实 Server fixture 验证。

本记录区分新的临时 Demo Server 和用户现有 GUI IDE 会话。后者是否重启/处理旧缓存仍
待用户自行验证，不能把前述通过宣称为原 IDE 会话已加载新版。

## 未覆盖范围

本轮是 Dart/Flutter 源码、Generator/分发和真实 Language Server 自动化证据。没有新增
Android/iOS/OHOS 真机验证、人工首次接入研究、长期性能或发布到 Pub 的证明。

日志对本机路径、换行和行末空白作机械规范化，结果、失败和堆栈内容保留。
