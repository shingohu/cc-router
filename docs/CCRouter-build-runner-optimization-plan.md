# CCRouter build_runner 与团队构建正确性优先优化计划

> 文档状态：既有实施阶段完成。P0、P1、P2 Host 纯删除路径、P3 Portable reuse、P4 冷成本
> 评估与 P5 多组件个人/团队拓扑回归已完成；更宽的 Host-only 跳过 Builder 未获准，保留为
> 指标触发项。P6 已完成只读归因、混合对照采样、Builder 读取范围核对和生成阶段输入一致性
> 屏障，见第 12 节。
> 后续审查发现的 F03/F04 缓存与分发校验缺陷已修复，验证见全框架审查第 9 节；
> P6 的语义摘要与依赖失效粒度优化仍未实施。2026-10-07 已完成 dirty/runtime/InitTask/Route
> 图算法、unified epoch、Builder protection snapshot 与 Analyzer alias graph 的正确性优先优化；
> 当前 Demo 组合交错 A/B 和放大规模结果统一记录在性能报告 10.16-10.17，不在本计划重复维护。
>
> 日期：2026-09-30；P1–P6 实现与评估更新：2026-10-07。
>
> 核心约束：任何生成器性能优化都不能以漏生成、接受陈旧生成物、降低校验强度或改变错误
> 语义为代价。无法证明等价时必须回退完整 `build_runner + validate + aggregate`。

## 1. 问题与决策

CCRouter 当前以 `source_gen/build_runner` 生成 Package 内的 Route、Service、Command、Event、
InitTask、Binding 和 metadata，再由 CLI 完成跨 Package 校验、Bundle、Host Assembly、Catalog
和旧产物清理。只要现有 fast path miss，CLI 就会启动一次 Workspace build_runner。

这个策略正确但过于保守：Host 增删组件依赖会改变 Pub Package Graph，即使剩余组件的注解源码、
Builder metadata 和生成物都没有变化，也会触发 build_runner Asset Graph 与 AOT entrypoint 重建。

本轮真实 Demo 测量如下。临时组件包含 Route、Service、Command、Event、InitTask 五类能力：

| 场景 | 命令总耗时 | Generator | build_runner | dirty |
| --- | ---: | ---: | ---: | ---: |
| 稳定无变化 `flutter pub get` | 3.06-4.76s | 0.30-0.33s | 跳过 | 0 |
| 修改已有组件依赖 | 9.34s | 8.30s | 6.99s | 4/17 |
| 新增一个全新 Workspace 组件 | 34.06s | 30.35s | 29.02s | 2/18 |
| 删除组件，样本一 | 33.52s | 29.68s | 28.40s | 1/17 |
| 删除组件，样本二 | 32.78s | 29.81s | 28.52s | 1/17 |

新增和删除 Package 时，build_runner AOT entrypoint 约 17.5MB，命令最大 RSS 接近 1GB；解析、
Workspace Validator 和聚合合计仍低于 0.5 秒。主要问题不是 CCRouter Validator，而是 Package
Graph 变化后启动了语义上可能不需要的 Workspace build_runner 冷路径。

新增组件后的 macOS debug build 为 15.92 秒，稳定重跑为 13.13 秒，删除组件后的 build 为
19.47 秒；三次 CCRouter preflight 均为 1.32-1.39 秒并命中 fast path。因此本计划优化 Pub
Graph 变化后的生成阶段，不把应用编译和链接时间错误归因给 CCRouter。

最终决策：

1. 保留 build_runner 作为 Package 内代码生成的权威实现，不在 1.x 复制一套 Analyzer 生成器。
2. 把“Builder 输入失效”和“Host 聚合输入失效”拆开，不再让所有 graph 变化统一触发 Builder。
3. 优先落地可证明安全的 graph-only aggregation；新建且没有可信生成物的 Package 继续运行
   build_runner。
4. 单机热路径与多人协作冷路径共用同一套可移植状态、失效规则和正确性门禁，不建立第二套
   团队缓存协议。
5. `--no-cache --check` 永久保留为权威参考路径和回退入口。

## 2. 不可破坏的正确性约束

优化实现必须同时满足以下条件：

- 不依据 mtime、文件大小、目录时间或终端日志判断新旧，只使用规范化身份与精确内容摘要。
- 不从源码字符串猜测是否存在注解；需要判断 Package 是否可复用时，覆盖全部受管 authored
  Dart 源码和 Builder 配置。
- 不跳过 Route/Contract/Owner/依赖、公共 barrel、Pattern 冲突、Codec 和 Host Assembly 校验。
- 不把上一次 metadata 当作当前事实；只有当前源码、解析环境、工具身份和受管输出都能精确证明
  一致时才可复用。
- 新增可写 Workspace Package 缺少状态、状态损坏、版本不兼容或生成物缺失时，一律运行
  build_runner。
- Git、Pub 和 Workspace 外 Path Package 属于只读依赖；它们缺少生成物或当前源码与已发布
  Generation State 不一致时必须明确失败，不能由 Host 修改依赖或继续消费内部自洽但陈旧的
  Index/Bundle。
- 删除和重命名必须执行旧产物清理；快速路径不能只增加文件而遗留失效 API。
- Builder、聚合或校验失败时恢复原受管生成物，不发布半轮结果。
- 并发生成继续由 Workspace generation lock 串行化，状态文件和生成物继续原子提交。
- Observer、Profile、缓存或优化分支异常不能把失败伪装成成功。
- 优化路径与完整路径必须生成逐字节一致的受管文件，并返回等价的稳定错误。

## 3. 输入状态拆分

当前 fast path 使用一个 Workspace 级总摘要。新的内部状态需要区分三层，不增加业务公开 API。

### 3.1 Tool State

影响所有 Builder 的全局状态：

- Generator 版本、源码与 Builder protocol/schema；
- `build.yaml` 和相关 Builder 配置；
- Dart SDK 版本与可执行文件 identity；
- metadata、Package Index、Bundle 和 generation state schema；
- 影响代码输出格式的 formatter 版本。

任一 Tool State 变化都进入完整 build_runner，不能走 aggregation-only。

### 3.2 Package Generation State

每个可写 Package 记录：

```text
packageName
packageRootIdentity
authoredInputFingerprint
resolutionFingerprint
builderConfigFingerprint
metadataFingerprint
managedOutputFingerprint
packageIndexFingerprint
directDependencyIndexFingerprints
generatorIdentity
schemaVersion
```

其中：

- `authoredInputFingerprint` 覆盖 `lib/**/*.dart`，排除受管生成目录，并覆盖 Package 自己的
  `pubspec.yaml`、`build.yaml`、`ccrouter.yaml`；
- `resolutionFingerprint` 是该 Package 实际解析依赖闭包的规范化切片，不直接复用整个 Workspace
  `package_config.json` 字节；依赖版本、root URI、language version 或可见类型来源变化都必须失效；
- Hosted 依赖可使用 lockfile 中的版本与内容身份，Git 依赖使用锁定 commit；可变 Path/Workspace
  依赖不能只记录路径，必须覆盖其生成相关源码和配置，或沿依赖图传播对应 Package 的 authored
  input 变化；无法建立稳定依赖内容身份时必须运行 Builder；
- `metadataFingerprint` 和 `managedOutputFingerprint` 对当前真实文件重新计算，不能只读取缓存值；
- `directDependencyIndexFingerprints` 保持现有反向依赖传播语义；
- 所有摘要使用稳定排序和完整内容 SHA-256。

状态只能在一次完整成功生成后写入。状态文件缺失、损坏或字段不完整等价于 cache miss。

### 3.3 Host Assembly State

Host 单独记录：

```text
hostPackage
resolvedComponentClosure
requiredAndOptionalEdges
externalPackageIndexFingerprints
contractBundleFingerprint
hostCatalogFingerprint
hostManagedOutputFingerprint
```

Host 依赖增删可能只改变这一层。Package 内 Builder 输入没有变化时，应重新执行完整跨 Package
校验、Bundle/Host Assembly/Catalog 生成和旧输出清理，而不是先启动 build_runner。

## 4. Build Plan

内部规划器输出以下三种确定性计划：

### 4.1 `unchanged`

适用条件：Tool、Package、Host 输入和所有受管输出完全一致。

行为：沿用现有 fast path，获取锁并验证摘要后直接返回。

### 4.2 `aggregateOnly`

仅在以下条件全部成立时使用：

- Tool State 完全一致；
- 所有保留 Package 的 authored input、解析环境、Builder 配置、metadata 和受管输出完全一致；
- 被删除 Package 已不在新 Host 闭包，且删除不会改变保留 Package 的解析环境；
- 新增只读 Pub/Git Package 提供兼容且内容校验通过的 Package Index 和 Runtime Bundle；
- 所有只读依赖的 authored input、Builder 配置、解析依赖切片、metadata、受管输出和 Package
  Index 均与其 Portable Generation State 一致；
- 新增可写 Package 提供由同一 Generator/schema 产生的可信 Package Generation State，并且对当前
  源码和输出重新计算后完全匹配；
- 没有 `clean` 后输出缺失、手工篡改、Contract shape 漂移或未知生成目录文件。

行为：跳过 build_runner，但仍完整执行 metadata 读取、Workspace Validator、Contract 校验、
dirty 传播、Package Bundle、Host Assembly、Catalog、文档、旧产物清理和原子提交。

典型收益场景：

- Host 删除一个组件依赖，剩余 Package 完全未变；
- Host 增加一个已经独立完成生成且状态可信的组件；
- Host 闭包只调整已有外部 Package Index。

### 4.3 `runBuilder`

以下任一条件成立即使用：

- 新建本地组件没有可信状态或缺少任何受管生成物；
- Route、Service、Command、Event、InitTask、Component 或 Contribution 源码变化；
- Package 自己的依赖解析环境变化并可能改变 Analyzer 类型解析；
- Tool State、Builder 配置或 SDK identity 变化；
- metadata、Package Index、Bundle 或源码生成物被删除、损坏或篡改；
- 状态无法解析、无法唯一归属或无法证明等价。

行为：保存受管输出快照，运行 build_runner，再执行当前完整校验与聚合流程。任何阶段失败均恢复
快照并返回非零状态。

## 5. 新增和删除组件的具体语义

### 5.1 新建本地组件

刚由 Scaffold 创建、尚未生成的组件必须运行 build_runner。没有生成状态时不能用源码扫描或
“目录看起来完整”推断结果。首次生成的 29 秒冷成本在当前 build_runner 架构下可接受为低频
结构操作，不能用陈旧 metadata 换取速度。

### 5.2 增加已有组件

如果组件已在自己的 Package 上完成权威生成，且当前源码、解析环境、Generator identity 和全部
受管输出与 Package Generation State 一致，可以只做 Host 聚合。任一字段不一致则回退 Builder。

### 5.3 删除组件

删除 Host 依赖时，若所有保留 Package 状态一致，可直接重算闭包并清除 Host 中失效的 Manifest、
Route、Contract、Bundle、Catalog 和源码位置。被删除 Package 不得继续出现在 Host 生成物中。

如果删除同时改变了某个保留 Package 的源码或解析依赖，则不能使用 aggregation-only。

### 5.4 修改组件内部依赖

修改 `CCComponent.dependencies`、Service/Command dependency 或 Contract 声明属于 authored source
变化，必须运行 Builder。只修改 Host `pubspec.yaml` 的依赖边不能与组件源码变化混为一类。

## 6. 实施阶段

### P0：诊断基线，已完成

- `--profile` 输出 `build-targets`；
- 输出逐 Package `dirty-packages` 和 `host/cache/metadata/output/dependency/propagated` 原因；
- 保留完整生成、无缓存参考路径和真实 Package 增删性能样本。

### P1：只计算计划，不跳过 Builder，已完成

实现 Tool/Package/Host 分层状态和 Build Plan，但所有 miss 仍运行 build_runner。Profile 同时输出
“建议计划”和“实际完整路径”，完成以下验证：

- 计划在相同输入上稳定；
- 每个被判为 `aggregateOnly` 的样本与完整路径逐字节一致；
- 计划无法证明时稳定选择 `runBuilder`；
- 状态读写不改变现有生成结果和错误。

P1 是必须阶段，不能直接进入跳过 Builder 的实现。

P1 阶段的验收行为（P2 删除优化启用前）：

- 每次 fast path miss 计算 Tool、Package、Host 分层 Build Plan，并通过 `--profile` 同时输出
  `suggested`、`actual` 和有界 `reasons`；
- `suggested=aggregateOnly` 仅用于收集等价性样本，`actual` 仍固定为 `runBuilder`；
- `--no-cache` 输出 `no-cache-reference` 并始终执行完整参考路径；
- 本地基线写入 `.dart_tool/ccrouter/v1/build_plans/`，只在完整生成成功且输入未变化后更新；
- 状态不保存绝对路径、用户名、`rootUri`、mtime 或 inode，缺失、损坏和读取/计算异常均
  fail closed 到 `runBuilder`；
- 当前状态与上一次基线都必须能证明 Tool/Package 解析身份；任一侧不可证明时不输出
  `aggregateOnly` 建议；
- 状态写入失败不改变本轮生成结果，仅使后续运行保守回退。

该 `.dart_tool` 文件是可丢弃的单机诊断状态，不是可提交 Portable Team State。P3 另行生成
`lib/src/ccrouter_generated/metadata/ccrouter_generation_state.json`；两者的所有权和提交规则
不能混用。

2026-10-03 在当前 Demo（8 个 Builder Package、6 个组件、33 条路由）回归中，三次
`--no-cache --check --profile` 总耗时为 1.592-1.668 秒，build_runner 为 0.745-0.783 秒；
稳定 fast path 总耗时为 0.158-0.192 秒。相较 P1 前约 1.5 秒的完整路径基线，诊断状态捕获没有
出现数量级退化，但该数据只用于 P1 观测，不能作为 P2 跳过 Builder 的收益声明。

### P2：开放精确删除路径，已完成

当前已默认启用范围最窄的 aggregation-only：

- Host 依赖闭包至少删除一个 Package，且没有新增任何 Package；
- 所有保留 Builder Package 的 authored input、解析身份、Builder metadata 和受管输出完全未变；
- Tool identity 和可移植解析身份完全未变；
- 仍执行正式 Workspace Validator、Host 聚合、旧产物清理和受管文件原子恢复。

普通 Host 源码变化跳过 Builder 仍未开放。它即使显示 `suggested=aggregateOnly`，`actual` 仍为
`runBuilder`，并附带 `p2-scope-excluded` 原因。可信 Package 纯新增与跨 Clone 状态由 P3 独立
证明，不扩大 P2 的删除判定。

如果可信状态在写入前无法证明，或优化状态本身损坏，则回退同一请求的完整 Builder，而不是要求
开发者清缓存。正式 Workspace Validator、Contract 或配置错误必须恢复快照并直接报告，不能通过
重跑 Builder 吞掉或改写错误。`CCROUTER_DISABLE_AGGREGATE_ONLY=1` 是 aggregation-only 的紧急回退开关；
`--no-cache` 始终强制完整路径，可作为权威对照，CI 保持 `--no-cache --check`。

2026-10-03 在当前 Demo 删除 `demo_payment` 的同一依赖闭包样本中：关闭优化的完整 Builder 路径
为 1.491 秒（build_runner 771ms），默认 `aggregateOnly` 为 904ms（build_runner 0ms），
`--no-cache --check` 参考路径为 1.656 秒（build_runner 772ms）。`aggregateOnly` 相对同轮完整
Builder 减少约 39% wall time，且随后参考路径确认受管生成物逐字节一致。该数据只说明当前样本收益；
Validator、依赖发现和 Host 聚合仍会完整执行，不能据此承诺固定倍数。

### P3：支持可信预生成组件，已完成

显式声明 `generation: { portable: true }` 的生成 Package 才通过
`ccrouter portable prepare` 写入可提交的
`lib/src/ccrouter_generated/metadata/ccrouter_generation_state.json`。状态只包含 schema、Generator、
Dart SDK、Package identity、authored input、解析依赖、metadata 与受管输出的内容摘要，不包含
绝对路径、用户名、时间戳、mtime、inode 或 `.dart_tool` 数据。

当 Host 依赖闭包纯新增 Package 时，CLI 会在当前机器重新计算上述全部摘要。所有新增 Package
均匹配时可选择 `aggregateOnly`；可写 Package 缺少或失配时安全回退 `runBuilder`。Git、Pub、
Workspace 外 Path 等只读业务 Package 必须携带有效状态，缺失、损坏或陈旧时明确失败，Host 不在
外部依赖目录运行 Builder 或修改文件。Package Index 可在 Builder metadata 不存在时作为已验证
metadata 输入，但仍须通过正式 Workspace Validator、Contract 校验和 Host 聚合。

普通本地 `generate` 不写 Portable State，只维护 `.dart_tool` planning state；`portable publish`
只验证状态而不执行外部发布。状态文件纳入 `clean`、`--check`、失败恢复和 fast-path 外部输入摘要。实现已覆盖无 Builder cache
的预生成 Package、只读外部 Package、缺失状态和篡改状态；`--no-cache --check` 继续作为逐字节
权威对照，不能因为状态来自其他机器而降低校验强度。真实 Git/Pub 发布归档及 macOS/Linux 的
Clone A/Clone B 矩阵属于持续发布门禁，不改变当前 fail-closed 语义。

2026-10-03 在当前 Demo（6 个组件、33 条路由）重新加入已生成 `demo_payment`，并移走其本机
Builder metadata 后，P3 `aggregateOnly` 为 1.091 秒（build_runner 0ms）；同轮
`--no-cache --check` 权威路径为 1.961 秒（build_runner 913ms），wall time 减少约 44%。随后
完整 Generator 272 项及两条生成门禁均通过。该结果是单机单次样本，不承诺固定比例，也不省略
Validator、依赖发现、Portable State 重算或 Host 聚合成本。

### P4：评估剩余冷成本，已完成

2026-10-03 使用三个不携带 `.dart_tool` 的 `/tmp` 干净副本完成隔离评估：

- 当前 Flutter `3.41.x` Workspace 锁定 `build_runner 2.15.1`。最新 `2.16.1` 要求
  `analyzer >=13.3.0`，后者要求 `meta ^1.18.3`，但 Flutter SDK 固定 `meta 1.17.0`，因此候选
  组合在依赖解析阶段即失败。不能为了未证明的性能收益联动升级 Flutter、Analyzer 和 Generator。
- 当前带 Host closure build filters 的干净冷生成总耗时 16.338 秒，build_runner 15.560 秒；
  其中 AOT 编译约 10 秒，Validator 14ms，aggregate/format/write 230ms。瓶颈不在 CCRouter 校验。
- 去掉 filters 的相同干净构建仍约 14 秒，但 CCRouter Builder 输入从 `38/48` 增至 `47/58`，
  额外执行 `build_test:test_bootstrap` 的 76 个 action，并写出 230 个输出；过滤路径只写 75 个。
  Filter 明确减少无关 action 和副作用，但不能消除共享 AOT 启动成本，现有实现应保留。
- 同一工作区 warm `--no-cache --check` 为 1.961 秒，稳定 fast path 为 0.172 秒。冷路径仍低于
  30 秒触发阈值；P3 路径的 aggregate/format/write 占比约 21%，但绝对值只有 230ms，且尚无
  生产 P95 证明继续拆分能获得正收益。

结论：1.x 不引入常驻 daemon/watch，不访问 build_runner 私有 Asset Graph，不维护第二套
Analyzer runner，也不为升级 build_runner 扩大 SDK 迁移面。后续只有达到第 9.7 节生产 P95 或
第 7 节触发条件时重新立项；自有 runner 继续属于架构 2.0 候选。

### P5：多组件个人/团队拓扑回归，已完成

2026-10-03 使用 18/30/60 个真实 Workspace 组件 Package 完成 3x/5x/10x 隔离回归。每个组件
包含 Route、Service、Command、Event、InitTask 五类真实生成输入。个人新建未生成组件稳定
选择 `runBuilder`；个人/团队删除和团队拉取可信预生成组件按已证明边界选择
`aggregateOnly`。每条路径随后运行 `--no-cache --check` 并逐文件逐字节比较，全部一致。

测试发现 Workspace 外 Path 工具依赖在 Portable State 与 Build Plan 间采用了不同 authored
fingerprint 覆盖范围，导致安全但多余的 `resolution-unproven` 回退。实现已将 Path Package
内容指纹收敛为同一内部入口；只持久化内容摘要，不持久化绝对路径。详细数据和命令见
[生成器性能报告](CCRouter-generator-performance-report.md#65-多组件个人与团队增删样本)。

## 7. 测试与回归矩阵

每种优化路径必须与 `generate --no-cache --check` 参考路径比较：

| 场景 | 预期计划 | 必须验证 |
| --- | --- | --- |
| 完全无变化 | `unchanged` | 零写入、输出摘要一致 |
| Host 删除组件 | `aggregateOnly` | Host 不残留 Route/Contract/Bundle/Catalog |
| Host 增加可信外部组件 | `aggregateOnly` | Owner、版本、shape、源码位置正确 |
| 新建无生成物组件 | `runBuilder` | 五类能力全部生成并注册 |
| 修改五类任一注解 | `runBuilder` | 对应输出和反向依赖更新 |
| 页面/声明删除、重命名、移动 | `runBuilder` | 旧输出完全清理 |
| Package 依赖版本变化 | `runBuilder` | Analyzer 解析与 Contract shape 重算 |
| Generator/SDK/build.yaml 变化 | `runBuilder` | 全局状态失效 |
| metadata、Index、Bundle 或源码输出篡改 | `runBuilder` | 不接受陈旧输出 |
| cache/state 损坏 | `runBuilder` | fail closed 并重新播种 |
| 外部 Git/Pub 源码更新但保留旧生成物 | 明确失败 | 即使 Dart 可编译也不接受旧 Route/Service 语义 |
| 外部 Git/Pub 缺少 Index、Bundle 或 Portable State | 明确失败 | Host 不写依赖、不猜测、不静默忽略 |
| Workspace 外 Path 依赖源码与状态不一致 | 明确失败 | 提示回到组件仓库重新生成 |
| 并发 generate/check/pub hook | 串行 | 不死锁、不发布半轮结果 |
| Builder/Validator/写盘失败 | 失败回退 | 原生成物逐字节恢复 |
| Clone A 生成、Clone B 首次校验 | 按可信状态规划 | 不依赖绝对路径、本机缓存或用户名 |
| 合并他人新增的已生成组件 | `aggregateOnly` 或安全回退 | 组件闭包、Owner、Contract 和 Host 输出完整 |
| 合并他人修改的组件源码 | `runBuilder` | 不接受随提交带来的陈旧状态或输出 |
| 切换到增删组件的分支 | 按精确差异规划 | stale 生成物清理且不误用上一分支状态 |

验收不仅比较最终文件，还要比较：

- 退出码和稳定错误类型；
- 组件与路由数量；
- Package Index、Contract Bundle 和 Host Assembly 顺序；
- stale 文件删除结果；
- 缓存命中、dirty 传播和 Build Plan 原因；
- 第二次执行是否收敛到 `unchanged`；
- macOS/Linux 及项目支持的 Flutter SDK 组合。

## 8. 性能门槛

性能数据只能在正确性门禁全部通过后用于决策。建议目标，不作为跨机器绝对承诺：

- 稳定无变化不回退当前 fast path；
- Host 删除组件不再触发约 28 秒 Workspace AOT 重建；
- aggregation-only 的主要耗时保持在 metadata/Validator/聚合与 CLI 启动范围；
- 新建无生成物组件允许继续运行完整 Builder；
- 优化不能增加常驻进程、后台 Listener 或无界缓存；
- 性能退化或状态异常时可通过 `--no-cache` 立即回到权威路径。

## 9. Team Build Acceleration

### 9.1 范围与边界

团队构建加速是本计划的独立工作流，不是另一套生成器方案。它解决以下多人协作场景：

- 新成员或 CI 在全新 clone 中首次执行生成；
- 拉取或合并其他开发者已经完成生成的组件；
- 在包含组件增删、依赖图变化的分支之间切换；
- Host 只调整已有组件依赖，但 Package 内注解源码没有变化；
- 本地没有 build_runner Asset Graph，仍需要判断已提交生成物是否可信。

团队加速不承诺共享 build_runner 的本机增量缓存，也不改变 Package 内代码生成仍由
build_runner 权威负责的边界。

### 9.2 可共享与禁止共享的状态

允许随代码提交并跨机器复用：

- 确定性的 CCRouter 受管生成物；
- Package Index、Runtime/Contract Bundle 和 Host Assembly；
- 不含本机信息的 Portable Package/Host Generation State；
- Generator protocol/schema、Builder 配置和解析依赖的稳定内容指纹。

不得作为团队加速协议提交或分发：

- `.dart_tool/build`、build_runner Asset Graph 和 AOT entrypoint；
- Pub、Flutter、Analyzer 或操作系统的本机缓存；
- 绝对路径、用户名、时间戳、inode、mtime 或仅在单机成立的路径 identity；
- 未经过当前源码、解析环境和输出重新校验的历史 metadata。

Portable State 只用于证明“当前输入与受管输出是否等价”，不能直接声明缓存命中。消费方必须
重新计算当前摘要；任一字段缺失、不匹配或无法解释时，可写 Workspace Package 自动选择
`runBuilder`，只读外部 Package 返回稳定错误。

### 9.3 External Package Artifact Integrity

Git、Pub 和 Workspace 外部的 Path 组件按只读 Package 消费。组件作者必须发布或提交完整的：

- CCRouter 受管 Dart 生成物；
- Package Index、Runtime/Contract Bundle 和 Capability Catalog；
- Portable Package Generation State。

Host 必须重新计算当前 Package 的生成相关源码、`pubspec.yaml`、`build.yaml`、`ccrouter.yaml`、
解析依赖切片和受管输出摘要，并与 Portable State 对照。只校验 Index 与 Bundle 彼此自洽不够：
源码新增 Route/Service 后继续携带一套完整的旧 Index/Bundle，可能仍通过 Dart 编译，却会按旧
契约运行，必须被识别为陈旧生成物并拒绝装配。

只读依赖验证遵循以下规则：

- 缺少 Index、必要 Bundle、Portable State 或受管输出时明确失败；
- 源码、配置、依赖、Generator identity、Schema 或任一输出指纹不一致时明确失败；
- 错误包含 Package 名称、依赖来源、锁定版本或 Git commit、失配类别和重新生成建议，不输出
  开发机敏感路径或源码内容；
- Host 不在 Pub Cache、Git checkout 或 Workspace 外 Path 中运行 Builder 或写入文件；
- 不把外部 Package 的失败降级为“跳过该组件”，也不继续使用上一轮 Host Assembly；
- Git 生产依赖应锁定 commit；分支或 tag 最终仍以 Pub lock 解析出的 commit 和当前内容校验；
- Pub Package 发布前必须确认受管生成物包含在发布归档内，不能只在作者工作区存在。

本地 Workspace 内的可写组件保持自动修复路径：CLI 可以运行 Builder 生成当前产物，随后由
`generate --no-cache --check` 和 CI 判断生成物是否已提交。外部消费者只验证，不代替组件作者
生成。

组件发布和 Git 合入门禁至少包含：

1. 在组件所属 Workspace 执行 `ccrouter generate --no-cache --check`；
2. 执行 Analyzer 和组件测试；
3. 对 Pub 包执行发布归档检查，确认 Index、Bundle、Portable State 和必要 Dart 生成物存在；
4. 在不携带作者 `.dart_tool/build` 的消费工作区完成一次只读验证。

### 9.4 单机热路径与团队冷路径

两类路径共用相同 Build Plan，但独立记录性能和正确性结果：

| 路径 | 典型场景 | 主要目标 |
| --- | --- | --- |
| 单机热路径 | 无变化、修改单个 Package、Host-only 调整 | 避免重复启动 Builder，保持低延迟 |
| 团队冷路径 | 新 clone、切分支、合并他人组件、CI checkout | 无本机缓存时复用可证明可信的结果 |

团队冷路径不能以“文件来自 Git”作为可信依据。Git 只负责传输文件，CCRouter 仍需验证源码、
依赖解析、Generator identity、Builder 配置、metadata、输出和反向依赖指纹。

### 9.5 Clone A / Clone B 验收协议

每个允许跳过 Builder 的团队场景必须通过以下双工作区测试：

1. Clone A 从干净 checkout 执行 `generate --no-cache`，提交所有确定性受管输出和 Portable
   Generation State。
2. Clone B 从同一提交开始，不复制 Clone A 的 `.dart_tool`、Pub Cache 或 Flutter Cache。
3. Clone B 重新解析依赖并计算 Build Plan，记录选择原因和输入摘要类别。
4. 若选择 `unchanged` 或 `aggregateOnly`，保存结果后再执行 `generate --no-cache --check`。
5. 两条路径必须在受管文件、删除集合、退出码、稳定错误和 Catalog/Bundle 顺序上完全一致。
6. 分别篡改源码、输出、metadata、状态、依赖版本和 Builder 配置，确认 Clone B 全部 fail closed
   到 `runBuilder`。

对于 Git/Pub/Workspace 外 Path 只读依赖，第 6 步不得回退到 `runBuilder`，而应返回稳定的外部
生成物陈旧错误；修复动作必须发生在组件所属仓库或发布流程中。

该协议应覆盖 macOS 和 Linux；Windows 在正式声明支持团队快速路径前加入同样的路径规范化和
逐字节等价测试。

### 9.6 团队协作实施阶段

团队能力沿用 P1-P3，不单独发明新的版本线：

- **P1 / Observe，已完成**：生成不含本机路径的本地 disposable planning state 和计划报告；
  当前状态位于 `.dart_tool`，不提交，也不用于 Clone 间复用。
- **P2 / Host graph，删除路径已完成**：已开放 Host 依赖闭包纯删除的 `aggregateOnly`；普通
  Host 源码变化仍不跳过 Builder。
- **P3 / Portable reuse，已完成**：可信纯新增 Package 可在重新验证 Portable State 后跳过
  Builder；只读外部 Package 已启用严格 Artifact Integrity 门禁。设置
  `CCROUTER_DISABLE_AGGREGATE_ONLY=1` 可统一关闭 P2/P3 优化。
- **CI / Authority**：不走优化分支，使用 `generate --no-cache --check` 作为最终合并门禁。

开发者不需要手工选择计划或维护缓存。CLI 和 Pub Hook 自动规划并在无法证明时回退；Profile
输出计划、原因、命中范围和耗时，便于定位某位开发者为什么进入了完整 Builder。

### 9.7 团队性能指标

除单机性能门槛外，持续记录以下团队体验指标：

- 全新 clone 首次校验的 P50/P95；
- 拉取一个已生成组件后的 P50/P95；
- Host 增加、删除组件后的 P50/P95；
- 在增删组件的两个分支之间往返切换的 P50/P95；
- `unchanged`、`aggregateOnly`、`runBuilder` 的选择比例和回退原因；
- Portable State 损坏、过期或不兼容时的安全回退成功率；
- 优化路径与 CI 权威路径的逐字节不一致次数，该值必须始终为零。

性能收益只有在最后一项持续为零时才成立。任何无法解释的不一致都应关闭相应优化 gate，保留
完整 Builder 路径，而不是扩大启发式判断。

## 10. 明确不采用的做法

- 根据文件时间或大小跳过生成；
- 只搜索包含 `@CCRoute` 等字符串的源码；
- Package Graph 变化后无条件信任旧 metadata；
- 为了速度跳过 Workspace Validator、Contract 校验或旧输出删除；
- 失败后吞异常并继续使用上一次 Host Assembly；
- 从 build_runner 私有 API 注入不稳定的 Asset Graph；
- 在 1.x 同时维护 build_runner 和自有 Generator 两套输出语义；
- 强制所有开发者运行 watch/daemon 才能保证生成正确。

## 11. 实施完成标准

只有同时满足以下条件，优化才可从 feature gate 转为默认行为：

1. 全部矩阵样本与无缓存参考路径逐字节一致；
2. 连续增删、失败恢复、并发和缓存损坏测试通过；
3. Generator、Workspace、Demo、Pub Hook 和平台 build 回归通过；
4. 实际项目样本证明结构变更耗时明显下降；
5. `--profile` 能解释每次计划和回退原因；
6. 文档明确哪些操作仍必须运行 build_runner；
7. `--no-cache` 回退路径保持可用且行为未弱化。

P2/P3 已满足其适用范围内的门禁并默认启用；所有无法证明等价的请求仍以完整 build_runner 路径
作为默认回退。P4 没有证明继续扩大 1.x 优化能够产生净收益，因此不新增运行时代码或公开开关。

## 12. P6：生成状态摘要与依赖失效粒度优化

记录日期：2026-10-03；2026-10-04 补充读取范围证据。只读失效归因与对照样本已实现；依赖传播收窄、分层语义摘要尚未实现。
摘要算法、缓存协议和跳过 Builder 的条件未改。本阶段沿用本计划，不另建团队缓存协议，不增加业务公开 API。

### 12.1 问题与目标

当前 Portable State 对非生成 `lib/**/*.dart` 和 Package 配置计算完整字节摘要，并把相关
Workspace/Path 依赖源码纳入依赖闭包。普通注释、格式或公共依赖内部实现变化，即使未改变
生成的业务 API，也可能引起多份 `ccrouter_generation_state.json` 更新。

目标分别衡量：

1. 减少没有生成语义变化时的受管状态更新、无关消费者失效和团队合并噪音。
2. 减少不必要的 Builder/聚合执行；不能把“JSON 变更少”直接当作“生成速度提高”。

不能统一忽略注释：Route 参数/字段的 DartDoc 会进入 metadata 文档；五类能力的源码行列
位置会进入 Catalog，新增普通注释也可能改变 DevTools 定位。公共依赖的常量、注解默认值、
类型别名、泛型边界和导出关系也会影响生成，不能只比较公开方法签名或版本号。

### 12.2 前置门禁与实施顺序

- [x] **P6-0：先修正确性。** 完成[全框架审查](CCRouter-framework-audit-2026-10-03.md) 的
  F04 合法分发身份误拒绝和 F03 外部依赖快速路径漏检，建立真实 producer/consumer 样本。
  快速路径与参考路径必须覆盖相同的当前输入和输出，不能在已知漏检上继续扩大复用。
  后续 G01–G05/A01 复审缺陷亦已逐项修复，见
  [复审修复记录](CCRouter-generator-analyzer-audit-2026-10-03.md#5-修复进度)。
  Portable State 的生成期间输入变更边界仍需确定性验证，不能作为已证明安全的复用前提。
- [~] **P6-1：收窄依赖失效传播。** 已完成前置的只读输入/产物归因、混合样本，以及五类能力
  15 个 Builder 入口的源码核对与读取反例（12.7）。生成期间输入一致性屏障已完成（12.8），
  但尚未收窄任何传播，也未建立完备的符号级证明。下一步只评估不影响 skip 决策的文件闭包原型。
  工具链、Builder 解析和聚合校验分别建模，不共享一个被过度收窄的依赖身份。
- [ ] **P6-2：分层处理源码、文档和定位变化。** 普通注释在不影响文档/定位时可保持生成
  状态不变；文档或行列变化应更新对应 metadata/Catalog，不迫使无关代码重新生成。
  只有能够用确定性规则复现完整 Builder 输出时，才允许局部更新路径。
- [ ] **P6-3：对照验证后决定默认启用。** 先保留可关闭的内部优化路径，完成正确性、性能
  和团队协作矩阵；没有净收益时保留现状，不为减少摘要差异引入第二套生成语义。

P6 不放宽既有“真实项目 Host 聚合占比持续超过 20% 才继续做摘要计算速度专项优化”的
触发条件。本节优先解决输入分类和失效传播；摘要计算本身的微优化仍按原指标门槛判断。

### 12.3 两层验证方案与取舍

推荐先用完整内容 SHA-256 发现变化，再对变化部分判断是否影响生成：

- **本地变更检测层**：继续读取当前文件内容，覆盖新增、删除、重命名、配置、依赖和输出。
  本地字节摘要可以保存在 `.dart_tool`；它用于发现变化，不代表已经证明生成语义一致。
- **可移植生成证明层**：评估分别记录代码生成语义、生成文档、源码定位和受管输出身份。
  消费端必须从当前源码和解析环境重新验证，不能只信任生产端提交的摘要或旧 metadata。
- 若希望普通注释变化后 Portable State 保持不变，其自摘要覆盖的 payload 就不能继续包含
  每次都变化的原始字节摘要。需要版本化调整状态协议，并用可复算的生成证明接替；不能
  简单删掉 `authoredInputFingerprint`，也不能把准确性证明退回仅本机缓存。
- 必须用 Dart 词法/语法及必要的解析信息判断，保留语言版本指令、被消费的 DartDoc、
  字符串/插值/常量、注解默认值、import/export、条件导入、part、类型与 Codec 相关语义。
  不使用正则删除注释，不以“没有改注解”为复用依据。
- Generator 与其实际执行的工具依赖仍需严格内容身份；公开 API 不变不能证明生成算法
  不变。若要缩小工具链影响范围，应先证明依赖读取边界或拆分依赖，不仅依赖版本号。
- 对新增 Dart 语法、歧义或不完整依赖证据，停止优化。可写 Package 回退完整生成；只读
  外部 Package 沿用严格校验，无法证明生成物有效时明确失败，不修改依赖目录。
- 状态 schema 或证明算法变化必须有明确版本；旧状态不能被误认为新证明。可写 Package
  重新生成，只读依赖按兼容规则明确要求更新；不静默降低验证强度。

完整字节摘要的优点是简单、保守，缺点是失效范围较大。语义分类能减少更新和传播，但会
增加解析耗时和规则维护成本；仅维护一份“生成相关字段白名单”容易漏掉传递依赖。因此
先优化可证明的小范围，不承诺所有公共依赖更新都能保持状态不变。

### 12.4 准确性与性能验收

样本必须同时包含 Route、Service、Command、Event、InitTask，而不是只测路由：

| 变化场景 | 必须验证的结果 |
| --- | --- |
| 普通注释/空白变化，生成文档及定位均未变 | 能证明时状态及输出不变；不支持的场景安全回退 |
| DartDoc、声明前增加行、声明重命名/移动 | 文档和源码定位及时更新，DevTools 不跳转到陈旧位置 |
| 公共依赖内部实现变化 | 仅在证明无生成影响时阻止无关消费者失效 |
| 常量、默认值、类型别名、泛型边界、导出、Codec 变化 | 更新所有实际受影响消费者，不遗漏跨包传递变化 |
| 工具实现、SDK、Builder 配置或证明算法变化 | 正确失效，不能用旧状态绕过 |
| 输出/metadata/状态缺失或篡改 | 检查失败或按可写边界重建，不接受内部自洽的旧输出 |
| Git/Pub/Path、嵌套依赖、独立 clone 和分支切换 | 同一内容证明可复算；合法分发不误拒，实际变化不漏检 |

每个场景都必须与完整参考路径比较所有受管文件的逐字节内容、状态、错误码、旧产物删除
和失败恢复行为。`--no-cache --check` 强制进入 build_runner 和完整 metadata 解析，绕过
CCRouter 的复用决策；它不清理 build_runner 自身的 Asset Graph，不能称为逐个 Builder 冷重建。
传播优化还需在隔离夹具中增加无 Asset Graph 的冷构建对照，防止两侧共享相同遗漏。
同一份漏判规则不能同时决定优化路径与参考路径是否跳过。新状态协议只允许有计划的格式变化，不允许优化开关
导致同一输入得到不同生成物。

同机记录 Demo 与五类能力混合的 3x/5x/10x 样本：冷/热 P50/P95、语义分类新增耗时、
Builder/聚合耗时、峰值 RSS、变化状态文件数、失效 Package 数、fallback 原因及团队 clone
首跑成本。先通过准确性矩阵，再判断是否有净性能收益；无变化热路径不得因全量语义分析
出现明显倒退。Profile 应说明此次变化影响代码、文档、定位还是工具链，不能输出业务值。

生成物、诊断错误和定位结果全部等价且性能收益可复现后，才考虑默认开启；发现任一
不一致立即关闭对应优化路径，保留参考路径继续工作。

### 12.5 本轮可行性与收益评估（2026-10-03，只评估）

结论：P6-1/2 有减少团队状态噪音和无关消费者失效的潜在收益，但目前没有足够证据安全
跳过 Builder；本轮不修改缓存 schema、摘要算法或 Build Plan 决策，也不声称已有提速。

代码核对：`_CCPortableGenerationContext.capture` 为每个相关 Package 计算 authored 内容身份；
`_GenerationResolutionPlanningContext` 把传递依赖的 authored/index 身份纳入解析环境；
`_CCPortablePackageGenerationState` 的自摘要又覆盖这些原始输入身份。因此仅把 AST 摘要
添加到 JSON，既不能使注释变更保持状态不变，也不能证明未被追踪的依赖不会影响输出。

本轮 Demo 实际样本：仅 order/web Owner barrel 改为复用业务 barrel，生成仍选择
`runBuilder`，8 个 Builder Package，耗时 **6981ms**、CLI 内部总计 **9221ms**，54 个 Builder
输出均为 same；聚合仍正确更新公开入口索引与反向依赖身份。该样本说明“Builder 输出相同”
不代表“所有聚合产物相同”。测量与 IDE 加载并行，只作为失效路径证据，不是 P50/P95 基准。

| 候选 | 收益与成本 | 下一步边界 |
| --- | --- | --- |
| 增加只读失效归因与对照样本 | 成本较低，可区分输入变化、实际输出变化和传播规模；本身不提速 | 先复用 Profile/现有混合样本，对普通注释、DartDoc、行列、常量与 barrel 分别采样 |
| 基于已解析依赖的传播收窄 | 中高成本；真实共享 contracts 较多时可能减少无关消费者重算 | 先证明五类 Builder 的读取集合，包含默认值、导出、Codec、泛型边界和解析环境；证据不全回退 |
| 代码/文档/位置的分层可移植证明 | 高成本；可能减少团队 Git diff，但需要版本化状态协议及消费端复算 | P6-1 的正确性与净收益明确后再做；不从旧 metadata 推断当前源码有效 |
| 摘要计算本身的微优化 | 当前缺少真实项目持续 P95 证据，维护成本暂不合理 | 保留原 20% 触发门槛，不用本次单次样本或合成占比直接启动 |

建议下一次获准实施时，先做不影响执行选择的归因采样，再增加可关闭的局部依赖证明原型；
通过第 12.4 节准确性、团队 clone 和性能矩阵后，才讨论分层状态协议和默认开启。普通注释
不能简单剥离，MD5/mtime/size 不能替代当前完整 SHA-256 内容校验。这里的生成内容证明与
Analysis Server 使用 MD5 定位其内部缓存目录是两个完全不同的用途。

### 12.6 只读失效归因落地

`generate --profile` 复用已有 Build Plan 基线输出 `input-delta`，包括自身 authored 输入变化、
解析身份变化、`resolutionOnly`、Package 增删和 Tool/Host 图变化。`resolutionOnly` 只表示
自身输入未变但解析身份变了，不证明某条具体依赖边是原因。每组完整计数，最多列出 12 个
Package 名；没有两侧源码摘要时单列 `authoredUnavailable`，不把空摘要视作源码一致。
不持久化新状态、不输出源码或业务值。参考路径或不可用基线报告 `unavailable`。

生成成功后，`output-delta` 按 Dart、JSON metadata、Markdown 和 Portable State 统计精确
新增/删除/修改数量。`--check` 在恢复前报告；Builder/聚合失败不报告成功产物差异。额外读取耗时单列
`output-delta-scan`。不带 Profile 不做额外比较；fast path 命中复用既有一致性结论报告零变化。
归因异常隔离，绝不成为 skip Builder、接受旧输出或放宽只读依赖校验的条件。

复用已有组件规模基准，新增 `--invalidation`：每个组件 5 个 Route 与各 1 个 Service、Command、
Event、InitTask；再加入共享的普通 Dart 依赖，提供被消费的默认值、描述常量和实现函数。
七种连续变更为尾部普通注释、等长度 DartDoc 修改、五类声明前加行、共享实现修改、默认值
修改、共享描述修改和等价 barrel 重排。每次把 Profile 总数与真实变更文件数比较，并执行
`--no-cache --check`、比较全部受管文件名和每个字节；大图额外检查名称截断不丢计数。

```sh
fvm dart run packages/ccrouter_test/benchmark/generator_component_topology.dart --invalidation 1 3 5 10
```

场景名称来自受控测试动作，不是词法/AST 自动判定。12.7 已补读取范围核对和反例，仍未建立可用于
跳过 Builder 的完备语义证明，不允许据此忽略注释、实现或公共依赖变化。
规模采样及测量边界见 [性能报告](CCRouter-generator-performance-report.md)。

### 12.7 五类 Builder 读取范围证据与 P6 决策（2026-10-04）

结论：可以继续评估保守的**文件闭包**；目前不能按“公开签名不变”“没有本地注解”或
“没有生成物变化”收窄传播。源码核对和受控反例证明了必须保留的读取边界，不是对所有
Dart 程序的完备语义证明。本轮仅新增测试和文档，没有修改生产 Builder、缓存协议或 Build Plan。

#### 入口与实际读取方式

以 [build.yaml](../packages/ccrouter_generator/build.yaml) 和
[Builder 工厂](../packages/ccrouter_generator/lib/builder.dart) 为准，五类能力并非只有五个 Builder：
Route 4 个、Service 4 个、Command/Event/InitTask 各 2 个，加上共享 Component metadata，合计 **15 个**。

9 个代码 Builder 使用 `source_gen.LibraryBuilder`，先 `resolver.isLibrary`，再
`resolver.libraryFor`；6 个 metadata Builder 直接调用相同 Resolver。当前这些实现没有
额外显式 `findAssets` 或 `readAsString` 扫描。这**不意味着只读当前文件**：LibraryElement、
ConstantReader、类型系统和 import namespace 会读取传递依赖中的声明、常量和源码信息。

当前锁定 `build_runner 2.15.1`、`build_test 3.5.16`、`source_gen 4.2.4`。上游
`BuildStepResolver.libraryFor → AnalysisDriverModel.updateDriver` 用 `transitive: true`
记录 Resolver entrypoint 并加载 Library cycle graph。`build_test.resolverEntrypointsTrackedFor`
记录的是入口，不是“只依赖这个文件”；`assetsRead` 是本次构建的物理读取，不是最小符号读取集。
`AssetDepsLoader` 对 `UriBasedDirective` 的主 URI 建边，不能把这个运行记录直接当作覆盖所有
条件分支、目标平台和缺失文件的长期可移植证明。SDK 的 `dart:` 依赖还必须由解析环境身份覆盖。

| 能力 / 入口 | 生成与校验实际消费的信息 | 主要实现 |
| --- | --- | --- |
| Route / routes、route_bindings、route_contracts、route_metadata | 注解及其常量链、Pattern/primary/presentation、构造参数类型/空值性/默认值、enum、集合的实际常量类型、公开导入 namespace；Contract-first 定义与实现参数兼容；Codec 构造器、父接口与类型参数；参数 DartDoc 和声明行列 | `route_model.dart`、`route_standalone_generator.dart`、`route_contract_generator.dart`、`route_binding_generator.dart`、`route_metadata_builder.dart` |
| Service / services、service_contracts、service_proxies、service_metadata | 实现类及构造器、直接 Contract 与继承关系、Token/Key/Scope/creationPolicy；Contract 注解、方法/属性、typedef、泛型 bound、递归类型、默认值原文及求值后的值/类型；消费者 Component、依赖、alias、公开 namespace 和源码位置 | `service_generator.dart`、`service_proxy_generator.dart` |
| Command / commands、command_metadata | Contract 注解/Owner/alias、`CCCommand<R>` 父接口、payload 字段、Handler 签名和结果类型；metadata 额外解析所有 Library fragment 的**函数体**，检查 `CCRouter.command` 的方法身份及参数静态类型上的注解；Contract/Handler 源码位置 | `command_generator.dart` |
| Event / events、event_metadata | Event Contract/Owner、payload 字段、Subscriber 参数及返回类型、Future/FutureOr 的解析类型；metadata 同样遍历**函数体**，检查 `CCRouter.event` 绕过生成 Client；源码位置 | `event_generator.dart` |
| InitTask / init_tasks、init_task_metadata | Contract 常量、ID/Owner/version/description、依赖 Owner/DAG、Gate、timeout、failurePolicy、Handler 签名；metadata 检查 `contract`/`dependsOn` 是否采用允许的顶层常量引用语法，不能只比较求值结果；源码位置 | `init_task_generator.dart` |
| 共享 / component_metadata | 顶层 `CCComponent` 常量、组件依赖及版本、Service/Command 消费声明、对应 Contract 的身份和类型、公开导入边界、Client 名称及源码位置 | `component_metadata_builder.dart`、`route_model.dart` |

注解类的构造默认值也属于常量求值链；SDK、语言版本、Package URI 映射、Builder 配置、
生成器/格式化器及实际执行工具实现均属于解析或执行环境。不能只保护业务源码而忽略这些输入。
上述表是读取职责清单，**不是可直接写入摘要的字段白名单**。

#### 可执行证据

[builder_dependency_scope_test.dart](../packages/ccrouter_test/generator_test/builder_dependency_scope_test.dart)
对真实生产工厂做冷构建。依赖 Package 只提供内存文件、不运行被测工厂；只对消费者运行
目标 Builder，断言它的 Resolver entrypoint 和实际读取的跨包 barrel/类型/常量文件。
读取快照在断言读取产物前采集，成功与失败均检查 BuildResult，不能用“空产物”掩盖构建失败。

复现命令（从 Workspace 根执行；测试依赖已经解析）：

```sh
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/builder_dependency_scope_test.dart
fvm dart run packages/ccrouter_test/benchmark/generator_component_topology.dart --invalidation 1
```

验证结果：新增 **33 项**读取范围测试与既有五类 Builder 专项合计 **191 项通过**；测试文件
Analyzer 无问题。Demo 缓存与无缓存检查均通过（6 组件、33 Route、11 generated Packages），
生成物无差异；文档链接检查通过。此次没有重新运行整个 Generator/Runtime/Analyzer 插件套件。

覆盖的边界：

- 15 个入口分别验证跨包常量变化及非法常量诊断。Route Binding 对合法 ID 改名可保持字节
  不变，但非法 ID 仍必须失败：**生成字节依赖与校验依赖不相等**。
- 五类 metadata 分别验证尾部普通注释不改变产物、声明前加行改变源码位置；Route DartDoc
  单独验证 metadata 改变、可执行 Route 文件不变。
- Route、Route Contract、Service Proxy 会嵌入跨包默认常量；Service Proxy 读取泛型 bound，
  typedef 指向不支持的函数类型时拒绝；Route Codec 的父接口类型参数变化也会触发校验。
- 没有本地注解、原本不生成 metadata 的普通函数，新增 raw Command/Event 调用仍须拒绝。
  消费者源码完全不变、只在跨包参数类型上新增 Command 注解，同样改变诊断。
- InitTask 使用等值的 inline Contract 替代顶层引用会失败；barrel 切换导出目标、`part`
  中声明位置变化均被观察；原本没有输出的普通输入新增 Route 后必须产生输出。

原有 Route/Service 测试继续覆盖默认值专属 enum、集合实际类型、公开导出路径、Contract-first
参数/Codec 兼容、受限泛型等组合。本轮不把历史测试当作条件导入全平台、任意语法、团队
clone 或并发发布状态的完整证明。所有输入的新增/删除、此前不存在的 URI、`show/hide`、
条件分支及工具升级仍是未来闭包原型的专门验收项，不因“上次未读取”就排除。

混合端到端样本复用第 12.6 节 `--invalidation 1`：6 个组件，30 个 Route，以及各 6 个
Service/Command/Event/InitTask。七种变更全部与 `--no-cache --check` 比较，**每组 97 份
受管文件的路径及字节一致**。共享默认常量变更更新 6 份 Dart，而 metadata 不变；共享实现
及等价 barrel 重排只更新 7 份 Portable State，进一步证明既有噪音真实存在，metadata 不变
不能作为复用证明。计时与本轮测试并行，不作为新的 P95、优化收益或硬件对比。
这些端到端参考检查保留 build_runner 自身缓存；本节新测试以独立内存构建补充 Builder 读取
反例，但尚未完成“七种变更各自全新冷工作区”的端到端矩阵，不声称排除上游增量图的所有遗漏。

#### 候选取舍与后续顺序

| 方案 | 准确性 / 收益 | 决策 |
| --- | --- | --- |
| 保留完整 Package 内容传播 | 已有保守路径；公共依赖变动可能导致无关状态更新 | 继续作为当前默认及参考路径 |
| 以文件闭包做候选传播 | 包含全部 eligible 消费者输入，以及 import/export/part 的保守传递闭包；排除未触达文件有潜在收益 | 下一步仅可做只读 shadow 原型，不接管 skip |
| 只哈希公开签名、剥离注释/函数体、或仅比较 metadata | 已有反例证明会漏默认值、诊断、DartDoc 或定位 | 不采用 |
| 生成模型与诊断共享符号级读取证明 | 才可能处理“同文件中无关实现变化”；成本高，必须避免再复制一套语义规则 | 暂缓，先验证文件闭包净收益 |

文件闭包的上限必须明确：如果 barrel 导出了整个包，或实现和被消费常量位于同一文件，
保守闭包仍会传播。本次共享实现样本就是后者；第一步不承诺解决这一类状态噪音。

推荐后续按以下顺序实施：

1. **已完成阶段屏障。** 生成命令在 build_runner 前重新确认执行输入；Builder 完成后、聚合前
   以及聚合完成后再次确认。变化时恢复受管输出、拒绝发布 Portable State，并要求重试；确定性
   测试覆盖了 Builder 完成后输入变化。该屏障仍不能阻止屏障之后立即发生的编辑，下一次运行会
   通过完整摘要失效。
2. 只读计算文件闭包及候选失效数，保持实际决策不变。保留全部自身输入的发现和完整 SHA-256；
   纳入所有条件分支、缺失 URI 身份、Package/SDK/语言/配置与工具身份。不支持或无法解析时
   标记 fallback，不把空集合视作无依赖。不得让副作用式物理读日志决定闭包。
3. 将 Builder 证明与聚合器证明分离。公开 exposure、组件 DAG、索引、Host Catalog 和校验仍
   读取它们自己的完整输入；不得以消费者 Builder 没变为由跳过依赖包自身生成/校验或接受
   陈旧 Portable State。输入图变动、删除产物及只读外部分发继续走既有严格门禁。
4. 覆盖新增/删除/重命名、barrel/part/条件分支、工具升级、并发保存及 Git/Pub/Path 的准确性
   矩阵；候选决定必须独立于完整参考路径。再测 Demo、3x/5x/10x 的失效数、P50/P95、解析
   开销、RSS 和团队 clone。证据不全或没有净收益，保留当前路径。
5. 只有以上证明成立，才设计版本化可移植协议与可关闭的执行原型。P6-2 的代码/文档/位置
   分层和 P6-3 默认开启仍未开始。不能把本节测试通过改写为“P6 收窄已完成”。

### 12.8 生成阶段输入一致性屏障（2026-10-04）

本项先于传播收窄落地，解决“源码在 Builder 或聚合期间变化，但仍发布看似成功的生成状态”
这一并发风险。生成命令在依赖预检后重新捕获执行输入；如果它与失效计划使用的摘要不同，
计划强制回退到 `runBuilder`，不会继续使用 Host-only/Portable fast path。Builder 完成后、
聚合开始前再次比较同一份完整输入摘要，聚合完成后、写入 Portable State 和 metadata cache
前再比较一次。任一比较失败都会返回稳定错误并由调用方恢复受管生成物快照；源码文件由开发者
保留，等待编辑稳定后重试。

屏障仍使用完整 SHA-256、解析环境和工具身份，未引入 `mtime/size` 或符号签名猜测。屏障之后
立即发生的编辑无法与文件系统写入组成事务；这类编辑会使下一次运行的 fast path/Build Plan
失效，不能把当前结果当作持续锁定。它也不改变 `--no-cache`、Builder、Workspace Validator
或聚合器的语义。

`packages/ccrouter_test/generator_test/generation_command_test.dart` 增加了确定性故障注入测试：
Builder 成功后修改受管源码，命令必须失败并报告 `before-aggregation` 输入变化，且后续冷生成
可以恢复到可验证状态。该测试钩子仅用于测试，不属于 CLI 公共参数。

本项完成的是一致性门禁，不等于 P6 传播收窄。文件闭包仍只能先以 shadow 结果观察，默认继续
使用完整传播和完整 Builder 回退。

### 12.9 文件闭包 Shadow 原型（历史 benchmark，已移出生产路径）

本节记录的实现和采样只用于研究候选失效规模。Shadow 计算已从生成 CLI 和 Tool
fingerprint 热路径移除，后续任何传播收窄都必须重新设计并通过独立 benchmark 验证；生产
路径继续使用完整内容摘要和保守 Builder 回退。

`generate --profile` 在失效路径上现在会计算一个只读的保守文件闭包，并输出总源码文件数、
反向 Package 候选数量、候选文件数量和无法精确解析的 Package。它只遍历当前解析 Host 的
可写 Package `lib/**/*.dart`，解析本地相对 `import`/`export`/`part` 和已解析 Workspace
Package URI；条件 URI、缺失目标、生成目录、语法异常或不明确的 URI 进入 Package-wide
`fallback`。外部 Pub/Git 依赖不被扫描，也不会因为 shadow 读取改变其只读校验。

该结果完全不参与 Build Plan、dirty set、传播或 Builder 跳过决策，故不会改变生成准确性；
shadow 解析失败也不会让生成失败。它的用途是收集真实项目的候选失效规模，判断文件闭包是否
有净收益。当前 Demo 的一次参考输出为 `packages=17 files=162 candidate-packages=74
candidate-files=660 fallback=none`，这个数字只是诊断样本，不是默认传播承诺。

在 1x 混合合成样本（6 个组件、30 Route、各 6 个 Service/Command/Event/InitTask）中，七种
变更均输出 `packages=8 files=46 candidate-packages=14 candidate-files=88 fallback=none`，
并与 `--no-cache --check` 的完整路径逐文件、逐字节一致。shadow 计算不改变任何 Build Plan，
当前只作为 Profile 归因。

随后完成的同机 3x/5x/10x 采样也覆盖相同七种变更和完整参考路径，候选规模如下：

| 规模 | 可写 Package | Dart 文件 | candidate Packages | candidate 文件 | fallback |
| --- | ---: | ---: | ---: | ---: | --- |
| 1x | 8 | 46 | 14 | 88 | none |
| 3x | 20 | 130 | 38 | 256 | none |
| 5x | 32 | 214 | 62 | 424 | none |
| 10x | 62 | 424 | 122 | 844 | none |

四个规模共 28 组变更均通过 `--no-cache --check` 的完整路径逐文件、逐字节比较；没有发现
Shadow 候选与参考产物不一致的样本。该结果只证明当前受控拓扑下 Shadow 是保守候选集合，
不构成 Dart 条件导入、任意 Package 图或外部依赖的完备语义证明。Shadow 的解析开销也未
证明稳定净收益，因此仍不参与 dirty set、传播或 Builder 跳过。

`generation_command_test.dart` 另有条件 URI 反例：Host 新增 `dart:io`/`dart:html` 条件导入时，
Profile 必须报告 `fallback=ccrouter_demo`，并保持 `actual=runBuilder`。这保证平台分支无法被
误认为精确的空文件闭包；测试结束后会恢复 Demo 生成物。

后续只有在多规模和真实团队样本中证明候选闭包与完整参考路径逐字节一致、并且解析开销有稳定
净收益时，才考虑可关闭的执行原型；任何 fallback、条件分支、新增/删除/重命名、工具升级或
外部依赖边界不确定时仍必须走完整路径。

### 12.10 Builder 证明与聚合器证明分离（2026-10-04）

本轮对 `aggregateOnly` 的执行边界做了代码与测试复核。Builder 是否可以跳过只由已验证的
Build Plan 决定；进入聚合阶段后，仍然重新加载当前 Workspace，执行内部 API 边界校验、Host
直接依赖校验、只读 Package Portable State 校验、Package Index 依赖身份校验、运行时 Bundle
闭包校验和 Workspace Validator。`dirtyPackages` 只控制可复用的聚合写入范围，不会跳过索引、
Contract exposure、Host Catalog、删除检查或最终输入一致性屏障。

P2 纯删除和 P3 可信预生成新增的测试都同时验证了：

- `CCROUTER_DISABLE_AGGREGATE_ONLY=1` 会强制完整 Builder，结果与聚合路径逐文件、逐字节一致；
- 聚合路径不会读取或接受缺失、篡改、版本不匹配的外部 Index/Portable State；
- 通过聚合路径产生的结果再经 `--no-cache --check` 参考生成，文件名、字节和错误语义一致；
- Builder 没有运行时，聚合仍会重新计算依赖顺序、运行时 Bundle 和 Host Catalog。

新增工具身份回归会在制造 Host 输入失效后篡改本地规划状态，验证 `tool-input-changed` 强制
完整 Builder；即使 Builder 产物没有业务差异，`--check` 仍按实际受管状态变化返回稳定结果。

因此当前可以确认两套证明已经在执行上分离，但不能把这项分离扩大成“消费者 Builder 未变就
可以忽略依赖 Package 的生成或校验”。任何新增/删除/重命名、barrel/part/条件导入、工具升级、
并发保存或 Git/Pub/Path 依赖边界变化仍回退完整路径。P6-2 的分层语义摘要以及 P6-3 的默认
启用继续暂缓，直到有真实项目净收益和更完整的可移植证明。

### 12.11 真实 Demo 门槛复测（2026-10-04）

在当前 Demo Host（6 个组件、33 Route、17 个生成 Package）执行一次 `--no-cache --profile`：
`build=853ms`、`discovery=54ms`、`parse=17ms`、`validate=13ms`、
`aggregate/format/write=261ms`，CLI 内部 `total=2145ms`。聚合阶段约占总耗时 **12.2%**，
低于继续做摘要/聚合专项优化的 20% 门槛；若只在内部五个阶段中计算，占比约 21.8%，不能替代
约定的总耗时口径。macOS 同机峰值 RSS 为 227,540,992 bytes（约 217 MiB），只作为同机趋势
样本，不设跨平台阈值。

同轮 3x/5x/10x 混合样本的冷生成 profile 如下，七种连续变更均与 `--no-cache --check` 参考
路径逐文件、逐字节一致：

| 规模 | 组件 / Route | 冷 Build | 冷聚合 | 典型失效聚合范围 | Shadow 候选 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 3x | 18 / 90 | 13,283ms | 379ms | 275–412ms | 38 Packages / 256 files |
| 5x | 30 / 150 | 13,615ms | 541ms | 370–606ms | 62 Packages / 424 files |
| 10x | 60 / 300 | 14,366ms | 878ms | 597–956ms | 122 Packages / 844 files |

即使 10x 样本的冷聚合增长明显，主要成本仍是 build_runner；当前数据不能证明语义摘要解析
会带来稳定净收益。因此 P6-2/P6-3 继续保持未实施，默认路径仍为完整内容摘要、完整 Builder
回退和完整聚合校验。

2026-10-05 收敛时，Tool fingerprint 改为显式 execution-kernel ownership。生成结果相关的
Generator `lib/`、主入口、Build Plan、Portable State 与 `build.yaml` 组成可审计边界；
Analyzer/scaffold/pub-hook CLI 模块不再因为源码变化使 generation tool identity 失效。该边界
只控制身份证明，不改变 generation lock、输入一致性屏障、P2/P3 `aggregateOnly` 或完整
Builder fallback。

### 12.12 post-Builder aggregation 输入矩阵（2026-10-05）

diagnostic-only `aggregation-input-fingerprint` 已接入 1x 隔离组件拓扑基准。除原有普通注释、
DartDoc、声明位置、共享实现、默认常量、描述和 dependency barrel 外，新增组件 public barrel
等价重排、Package dependency edge 和 Route 声明文件删除。10 个场景都要求 optimized 与
`--no-cache --check` reference 得到相同 fingerprint，并继续逐文件名、逐字节比较全部受管产物。

结果表明不能把 Builder outputs 和 aggregation inputs 混为一谈：共享默认常量变化会更新 6 份
Builder Dart，但不会改变 aggregation 消费的 metadata/index，因此 fingerprint 正确保持稳定；
共享描述、DartDoc、位置和声明删除会改变 metadata/index，因此必须失效。等价 dependency/public
barrel 重排保持稳定；新增未使用 dependency edge 虽然当前没有产物差异，仍因 Host/Package graph
变化而失效。

该矩阵补齐了 post-Builder reuse 的主要成功路径和结构性反例，但本阶段仍没有生产 skip。下一步
若实现 execution prototype，必须只位于 Builder 成功之后，并保留 Validator、输入一致性屏障、
生成锁、快照恢复和原子写入；提供 `CCROUTER_DISABLE_AGGREGATION_REUSE=1`，且 optimized/reference
继续逐字节对照。fingerprint 永远不能授权跳过 Builder，`--no-cache --check` 继续强制完整路径。

### 12.13 post-Builder aggregation reuse 收敛（2026-10-05）

execution prototype 已按 12.12 的边界落地。入口 artifact snapshot 提供当前 aggregation-owned
output fingerprint，cycle-end planning snapshot 提供成功输出 fingerprint；两者使用同一
build-root-relative identity，不新增目录扫描。只有 Tool、aggregation input 和 output bytes 都与
上次成功的 `.dart_tool` 本地状态一致时才命中。状态在完整 generation transaction 成功且 planning
snapshot 已验证输入稳定后原子发布，失败事务不会提前留下证明。

命中仍重建 Package graph/index 并运行 Workspace Validator 和前后 input barrier，只跳过确定性
aggregation rendering/writes、仅供这些写入使用的 dirty-set 计算，以及无需刷新的 metadata cache。
未来一次 miss 若面对旧 metadata cache，只会保守重算，不会接受旧产物。状态缺失/损坏、Tool 或
输入变化、aggregation output 篡改、metadata cache 损坏、自定义输出目录、Portable prepare、
`--no-cache` 或 kill switch 都会走完整 aggregation；损坏 cache 由该轮完整路径重建。

11 场景 1x matrix 逐字节通过，其中 output tamper 明确 `miss/output-changed`；Demo watch 的 5 样本
A/B 中，四类非生成语义编辑 wall P50 减少 106–158ms，Route annotation 保持 miss。最终 optimized
与 `CCROUTER_DISABLE_AGGREGATION_REUSE=1` reference 的 99 个受管文件 fingerprint 完全一致，并均
通过 `--no-cache --check`。因此保留该 production path；它不是 P6 语义摘要，也不改变 Builder
执行范围。
