# UI Action 扩大审查与修复循环（2026-10-26）

基线为 `4b12cf1eb4ebacdd73545b23e36fd276fd1833f3`，继续使用
`codex/sealed-action-unions` worktree。范围包括 UI Generator、Props/Action 数据闭包、
默认值与公开导出、Package Index、Host 校验、Action 生命周期、Plugin/Quick Fix、
Portable State、Demo 与接入文档。原 main 不参与修改。

## 审查轮次与已确认问题

功能缺陷先建立失败测试，再做最小修复；容量保护用边界用例验证。缓存构建复杂度的
问题由静态推导发现，并用子类型/工作预算回归复核，未冒充独立性能基准。最终源码冻结
后重跑完整套件。下列复现保留 RED/GREEN，没有移除或放宽原有断言。

### 第一轮：数据、身份与展开成本

1. **同库 DTO 子类逃逸（P1）**：final 仍允许同库继承，子类可覆盖 final 字段的 getter
   或添加未建模状态。原 Props、schema 2 DTO 和 schema 3 嵌套 DTO 都漏检。
   现在所有普通 DTO 都是实际叶子；同库/part 的子类和 implements 边也拒绝。
2. **同名 Object 绕过（P2）**：旧路径按显示名称判断直接 Object 继承，合法 Dart 中的
   自定义 Object 可让隐藏继承数据绕过检查。改为 SDK 元素身份，与 union/Plugin 一致。
3. **默认字符串误判公共类型（P2）**：常量中名为 type 的普通字段若包含 package URI，
   通用遍历会把字符串当成 Phantom 类型，污染公开导出证明。公共类型现在只来自声明
   schema；默认值本身仍完整纳入原指纹，合法 enum/DTO baseline 不变。
4. **重复图阻塞同步诊断（P1）**：24 层共享 DTO 图的旧 Plugin 校验单次耗时约 3.29 秒。
   增加跨分支的工作预算和按次 subtype 索引，超预算交由 Generator 判断。
   Generator 对旧 DTO/常量展开新增明确保护，避免少量共享类型产生指数工作量。

### 第二轮：版本和 metadata 一致性

5. **Index 接受错标 UI 版本（P2）**：外层 document 与记录版本不一致或未知版本仍能
   编码/读取，削弱升级拒绝。现在编码和读取都校验记录最高版本、文档版本、源 schema
   与 Package Index 一致性，错误包含 Package 定位。
6. **浮点版本被当作整数（P2）**：Dart 的数值相等使 4.0/1.0 通过整数版本比较。
   Index、UI document/record/source 版本现在显式检查整数类型。

### 第三轮：Runtime 与修复自身的复审

7. **过期 schema 后旧 Action 仍可交付（P1）**：同一 capability 更新为不匹配快照时，
   Widget build 虽报 staleGeneratedOutput，外部旧 sink 却已更新为新消费 callback。
   现在 consumer、capability、schema fingerprint、Contract version 或 range 更新时，
   在 rebuild 验证前撤销旧 sink；恢复有效快照只创建新 sink，旧 callback 永不复活。
   Widget 回归分别覆盖 shape/version/range 三条路径，普通 Props/callback 更新保持原行为。
8. **Runtime 与 Generator 的版本快照不一致（P2）**：Runtime attach 原来只检查范围与
   fingerprint，能接受 Generator 会拒绝的过期 Contract version。现在精确版本检查与
   Generator 对齐，错误发生在 Runtime 初始化前。
9. **新 subtype 缓存的平方构建成本**：复审发现逐项 List.contains 去重仍有平方复杂度。
   改为每个候选的父集合去重，库扫描线性构建，Generator 另做确定性排序。
10. **错误 metadata 仍产生 Owner Quick Fix（P2）**：Plugin 独立读取 metadata 时仍接受
    浮点或不匹配 UI 版本。现在仅在版本证据一致时使用 UI Owner 事实，错误数据保守
    退让；其他 capability families 的处理不变。测试覆盖已有缓存失效后的退让。

### 第四轮：修复后交叉复审

重新检查闭包索引生命周期、缓存失效、字段/参数/default 遍历、公开类型来源、SDK
身份、版本门禁、部分失败与恢复、Host 初始化顺序、normal callback 更新和资源释放。
新增真实 LSP part-only 测试验证“加入子类报错 → 未保存移除子类清错 → 再加入重新报错”。
该轮缓存/资源交叉测试通过后，继续追加了下面的来源一致性审查。

### 第五轮：声明来源与陈旧事实

11. **重复 Contract 被静默取首个（P2）**：同一 marker 重复框架 UI Contract 注解，或同一函数重复 Renderer 注解时，
    source_gen 的 firstAnnotationOfExact 只返回第一条，另一个 capability 被静默忽略。
    Generator 对两种声明都要求恰好一个，失败测试覆盖了该取首行为。
12. **源码 Owner 与 metadata 漂移（P2）**：源码 Owner 已改变，但版本格式正确的旧
    metadata 仍能对正确的新依赖报告缺少旧 Owner。resolveType 现在核对当前 resolved
    marker 的真实框架注解及 Owner；缺失/重复/不匹配时退让，不利用陈旧事实发出修复。
    Service/Command 行为保持，UI 类型别名和正常 Owner 的旧回归继续验证。

发现这两项后停止了上一轮完整运行（未作为成功验收），修复并重新冻结后再执行最终套件。
第六轮对最终修复重新检查并完整回归，未再发现可确认的未修复问题。
最终结论以最后一轮结果为准，不代表任意输入或整仓库的无缺陷证明。

## 兼容性和容量取舍

- 不引入新的 wire schema 版本，也不改变正常旧 enum/DTO 的 shape 指纹或生成签名。
- 同库 DTO 继承/实现及伪 Object 原本不符合“无继承、纯数据”约束，修复其漏检。
- **新增可观察限制**：旧 DTO 类型与常量共用 16,384 展开访问 / 256 层保护；union 类型图
  保持 512 节点 / 32 层，常量单独受 16,384 / 256 保护。超复杂旧图现在明确拒绝。
  这是容量收紧，已同步 README、Skill、API 文档和接入指南；不是宣称所有曾尝试展开的
  极大模型仍被支持。对这类图应收窄契约或拆开实际业务数据边界。
- 选择工作预算而非改造旧指纹 wire 形式，避免给正常消费者强加 schema 迁移。
- Runtime 只补快照与撤销守卫，不新增 Scope、异步任务、业务 Session 或资源所有权。
- 类型事实缓存仅存在于一次 Contract/annotation 校验；无全局 Analyzer/Widget/Context
  保留。没有发现高置信 not-disposed/not-GCed 问题；源码检查不等于独立长期 heap 证明。

## 验证

最终冻结后的 Generator 完整套件 **721 项通过，1 项默认跳过**，见 generator-full.log。
跳过项为需显式 opt-in 的远端安装 smoke；本轮另行完成当前 Git pin 的远端检查、doctor
和真实 Demo Server 诊断往返。生产源码在完整运行前后摘要一致。已完成结果：

- 失败复现包括默认值、DTO 子类/part、伪 Object、重复图、错标/浮点版本、Owner 事实、
  Runtime version 和 stale callback。日志按轮次分别保留。
- 框架完整串行回归 1646 项通过，包含独立的 shape/version/range 撤销及恢复测试。
- Plugin 完整套件 212 项通过，包含新增真实 LSP part-only 失效回归。
- Demo 117 项、独立 Example 1 项、DevTools/协议 24 项通过。
- 完整套件结束后，Demo/Example 的 `generate --no-cache --check`、9 个 Package 的
  Portable State 就绪检查、真实成员 Pub Hook 和根静态分析再次通过。
- 正常旧 enum/DTO 的两个 baseline 指纹和 40 层旧 DTO 对照保持通过。

Generator 使用相同 FVM Dart、根 package_config 和解析出的 test 1.30.0 runner：

```sh
fvm dart --packages=.dart_tool/package_config.json <resolved-test-package>/bin/test.dart \
  --concurrency=1 packages/ccrouter_test/generator_test
```

这避免定制 OHOS SDK 的 Dart 命令隐式重新解析 Flutter-only 依赖；未切换测试根或 SDK，
最终整套不设置 Pub Hook bypass，也不并行执行其他真实 Workspace 生成。

## Plugin 两阶段来源与当前 IDE 边界

生产 Plugin 修复先单独提交并推送 `f0bd3c2af3c3f6282f503e7182a41779beeb19f5`，
再在后续独立提交更新 Demo bootstrap manifest/lock；完整运行核实生产代码无 pin 后漂移。
`pin-check` 验证远端可解析、三份身份一致、生产源码无漂移；doctor 的临时 loader 通过。
固定 Git 包的独立 Server 和实际 Demo 根的临时官方 JIT Server 均完成诊断往返。

全局旧 IDE cache 的 stale advisory 保留，未停止用户 IDE、移动或删除全局缓存。
新的临时 Server 通过不等于现有 GUI IDE 会话已重启。没有新增真机或长期性能验证。

日志只机械规范化本机路径、换行与行末空白，结果和堆栈内容保留。
