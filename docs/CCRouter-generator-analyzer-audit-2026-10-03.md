# 生成器与 Analyzer 复审（2026-10-03）

审查基线：`c2c169c`。初次审查只复现问题；后续经授权逐项修复，状态见文末。上一轮 F01–F18 的修复状态
保持不变；本轮发现是新增边界，不能用既有测试通过推断这些边界也已正确。

## 1. 已确认问题

### G01 / P1：Service Proxy 回调遮蔽业务参数

位置：`packages/ccrouter_generator/lib/src/service_proxy_generator.dart`，
`_emitServiceProxyMember` 的固定 `(service, _)` 回调。

合法契约 `String echo(String service)` 被生成为：

```dart
String echo(String service) =>
    CCRouterGeneratedServiceBinding.invokeSync<AuditService, String>(
      methodId: 'echo',
      callerComponentId: 'consumer',
      call: (service, _) => service.echo(service),
    );
```

最后一个 `service` 绑定到了回调中的 Service 实例。真实 Builder 复现了此输出；独立分析
该转发形式得到 `argument_type_not_assignable`。若业务参数是 `Object`，还可能在可编译
情况下传错对象。不能要求业务避开框架内部变量名。

建议生成器按方法参数、泛型和导入符号分配不冲突的局部变量名；同时检查桥接类型名称
和导入前缀是否被遮蔽。增加编译与真实转发断言，不只比较输出字符串。

### G02 / P1：集合默认值丢失实际类型，空 Set 变为 Map

位置：`packages/ccrouter_generator/lib/src/service_proxy_generator.dart`，
`_renderServiceConstant`。Route 的 `_StandaloneRouteImportPlan._renderConstant` 也有同类
无类型集合输出，应一并检查；本轮直接复现的是 Service Proxy。

```dart
String inspect({
  Object set = const <int>{},
  Object list = const <String>[],
  Object map = const <String, int>{},
});
```

实际生成默认值依次为 `const {}`、`const []`、`const {}`。对生成库进行解析并读取常量后，
类型依次是 `Map<dynamic, dynamic>`、`List<dynamic>`、`Map<dynamic, dynamic>`。语义已变化，
而生成本身成功。此前集合测试使用窄类型参数，上下文类型推导掩盖了此问题。

建议保留常量实际集合类型，递归收集默认值所需的类型和枚举导入；补宽类型、空集合、
嵌套集合、可空类型和私有/不可导出元素类型的拒绝测试。无法保持等价时明确拒绝生成。

### G03 / P1：Host DevTools 描述未转义 Dart 插值

位置：`packages/ccrouter_generator/bin/ccrouter_generator.dart`，
`_emitGeneratedDevToolsCatalog` 的 `description: jsonEncode(description)`。

合法描述 `r'Price in $currency'` 生成 `description: "Price in $currency"`。
本轮在临时复制的生成器中调用未修改的 emitter，使用真实 Package metadata 并替换描述，
确认了该输出。Dart 会将其解释为插值；没有 `currency` 声明时宿主编译失败。`${...}` 也
不能直接作为 JSON 字符串复制到 Dart。此路径在 Host 装配 DevTools Catalog 时触发。

建议统一 Dart 字符串字面量编码，JSON 输出继续使用 JSON 编码。扫描所有生成 Dart 的
描述、URI、名称及默认值边界；增加包含 `$`、`${}`、反斜线、换行的生成后编译测试。

### G04 / P2：依赖 preflight 把 Package 当作 Dart Library 作用域

位置：`packages/ccrouter_generator/lib/src/component_dependency_preflight.dart`，
`_componentIds` 与 `_resolveComponentId`。

复现：Contracts 导出 `ownerId = CCComponentId('owner')`；消费组件正确导入并将 `ownerId`
放入 `dependencies`。同一消费 Package 的另一个未被导入的文件声明
`ownerId = CCComponentId('unrelated')`。preflight 优先选用 Package 级同名常量，错误地报
`consumer missing owner`。Dart 的库作用域不会引入该未导入声明。

本轮直接调用 preflight，复现错误拒绝。它发生在 Builder 前，会阻止原本合法的生成；
后续权威校验不能修复这个提前返回。

建议采用精确 Library URI 和实际 import/export 可见性证明。短期可保守收窄预检：只使用
当前库可证明的声明，对跨库歧义交给 Builder，不扩大扫描或靠名称猜测。增加同包不同库
重名、re-export、show/hide、条件导入及本地遮蔽测试。

### G05 / P1：自定义输出目录绕过 `--check` 差异检测和恢复

位置：`packages/ccrouter_generator/bin/ccrouter_generator.dart`，
`_GeneratedArtifactsSnapshot.capture`、`_readManagedGeneratedFiles` 与
`_isManagedGeneratedArtifact`。

复现命令：

```sh
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate demo --check \
  --output-dir build/ccrouter-audit2-output.80VHKJ --profile
```

目标目录事前为空。命令退出 0，报告 `output-delta.files=0` 和生成物已是最新，但目录下
留下了新生成的 `cc_routes.json`、`cc_catalog.md`。快照跳过 build 子树；对于其它不在
`ccrouter_generated` 下的自定义目录，文件名筛选也不纳入这两个产物。CLI 目前只验证
`--check` 输出目录位于 build root 内，没有要求它处于快照覆盖范围。

建议显式把本轮目标文件加入快照及成功/失败恢复，不扩大到同目录所有用户文件；若不能
做到，应在任何写入前拒绝不支持的目录。补自定义 docs/build 目录、已有文件、首次创建、
失败回滚和目录外拒绝测试。当前测试只覆盖名为 `ccrouter_generated` 的子目录，未覆盖
普通自定义目录。复现产物留在上述忽略的 build 目录，没有删除用户文件。

### A01 / P2：Analyzer 对业务自定义同名注解误报

位置：`packages/ccrouter_analyzer_plugin/lib/src/source_analyzer.dart`，
`_generatedOutputExpectations`、`_singleFileRuleDiagnostics` 和注解参数规则。

```dart
class CCInitTask { const CCInitTask(); }
@CCInitTask()
void run() {}
```

该独立业务库没有 CCRouter 注解；真实 Analyzer 解析没有 Dart 错误。将 resolved unit
交给插件规则仍得到 `ccrouter_generated_output_missing` 和
`ccrouter_annotation_arguments_conflict`。原因是多条规则仍仅比较终端名称，缺失生成物
规则还直接使用重新解析的未解析 AST。

建议所有规则和 Quick Fix 共用框架声明身份校验；已解析时按真实声明 URI 判断，解析
缺失时只对可证明的框架导入执行保守语法规则。补业务同名类型、前缀、重导出、typedef、
不完整缓冲区测试，防止提示和 Quick Fix 不一致。

## 2. 额外需验证的并发边界

`_GenerationFastPath.write` 和 Build Plan 写入会在输入变化时跳过本地基线，但
`_CCPortableGenerationState.write` 在聚合后重新采集当前输入。需用可控制的阶段屏障测试
验证：编辑器恰在 Builder 完成后保存文件时，是否可能给旧输出签上新输入的 Portable State。
本轮没有完成确定性并发复现，**不将其计入已确认缺陷**，也不声称发生过生产错误。
建议后续将“生成前后输入一致”纳入成功发布状态的证明，输入变化时明确重试或失败。

## 3. 方案与推荐顺序

| 方案 | 收益 | 代价与限制 |
| --- | --- | --- |
| 文档要求避开特殊参数名/字符串/宽类型 | 无框架改动 | 业务需记忆隐式限制，不能解决准确性问题，不推荐 |
| 对已发现边界分别补丁 | 快速止血 | 易遗漏 Route/Host/Proxy 共享问题，必须补全生成后验证 |
| 最小公共编码与命名规则，加精确语义证明 | 行为统一，不新增业务 API | 需跨 emitter 回归，推荐分批实施 |

推荐先修 G05 的只读检查边界和 G01–G03 的错误代码/数据语义，再修 G04/A01 的误拒绝与误报；每项先增加
失败测试，修复后检查缓存/无缓存等价、生成库编译、真实 Analysis Server 刷新和全量回归。
在这些正确性缺口关闭前，不进入 P6 传播收窄和语义摘要优化。

## 4. 验证边界

现有用例和新增反例分别记录；失败反例是审查证据，不得与既有回归的通过数相抵消。
临时复现仅操作 `/tmp` 或测试夹具，不修改生产实现和用户业务源码；没有升级依赖、修改
Demo Analyzer pin、推送提交或改变缓存策略。

本轮验证结果：

- Generator 全量：321 项通过，1 项需显式联网的安装测试默认跳过。
- Analyzer 独立包全量：83 项通过，包含真实 Analysis Server 回归。
- 框架 `packages/ccrouter_test/test`：414 项通过；上述独立用例合计 818 项。
- Workspace `fvm dart analyze`：无问题。它只分析当前已生成样本，不能证明所有合法输入
  都能生成可编译代码。
- 默认输出目录的缓存和 `--no-cache --check --profile`：均通过，零生成物差异；覆盖
  6 个组件、33 条路由、11 个生成 Package。
- 六项新增问题分别有 Builder 常量解析、编译检查、preflight、resolved Analyzer、实际
  emitter 或 CLI 文件结果证据。临时反例保存在 `/tmp/ccrouter_audit2_*`，执行日志为
  `/tmp/ccrouter-audit2-*.log`；它们不是已经纳入正式套件的回归用例。
- 本轮没有重跑设备 UI、多平台构建、远端 Analyzer pin、长期 RSS/Heap 或规模性能采样；
  不据此宣称这些门禁已满足，也没有将前次性能数据算成本轮测试结果。

核心价值复核：G01/G02 违反类型及转发语义，G03 破坏合法输入生成，G05 违反可预测与
可恢复，G04/A01 增加误拒绝/误提示。继续以最小内部修复处理，不能将这些问题转换成
业务配置或要求接入方记忆特殊限制。普通生成和既有测试稳定，但当前不能给出“无缺陷”结论。

## 5. 修复进度

- G05：已修复。快照显式收录自定义目录四个当前/旧 Catalog 文件；首次创建、已有内容、
  旧文件迁移、未知用户文件以及中途写入失败恢复均加入真实 CLI 回归。
  两项新增测试修复前失败、修复后通过；默认生成命令与失败原子性 15 项回归通过，
  改动文件 analyze、缓存/无缓存检查通过。生成器代码变化由正式生成更新 Portable State。
- G01：已修复生成回调 receiver、SPI 与类型导入前缀的名称遮蔽。新增用例实际编译并执行
  同步、异步、同名框架符号及同名泛型的方法转发；修复前编译失败，修复后通过。
- G02：已修复 Route/Proxy 集合常量类型丢失与默认值专属类型漏导入。Object 下空 Set、
  List、Map、嵌套 nullable 枚举集合与 dynamic 空列表均覆盖；不可公开导入的私有默认类型
  在生成期明确拒绝。Route/Service 原套件及新边界共 122 项通过，Workspace analyze、
  缓存/无缓存检查通过。
- G03：已修复 Host 聚合器的 Dart literal 编码，所有 JSON-compatible metadata 写入 Dart
  时统一转义插值符号，JSON 元数据仍保留原始文本。新增真实生成后编译执行 Catalog 的回归，
  覆盖 `$currency`、`${literal}`、引号、反斜杠、换行和中文；修复前编译失败。
- G04：预检索引改为 Library URI，解析直接/相对 import、export 与 show/hide；局部声明
  优先且同 Package 未导入声明不参与匹配。未知/条件命名空间与 part 保守交由 Builder。
  不扩大文件扫描范围、不创建 Analyzer Session；现有已读文件保留必要的命名空间边。
  Demo Network 的 Owner 解析涉及未索引 Dio import，预检不再宣称提前证明该 Owner，最终
  Builder 校验不变。新增两个原始误拒绝反例及 namespace 边界回归。
- A01：待修复。
