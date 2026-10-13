# CCRouter 生成器性能优化与对比报告

> 文档状态：2026-09-28 性能快照；2026-10-03 补充 Build Plan P2-P5，以及 P6 只读失效归因；
> 2026-10-05 补充 generation watch 多轮编辑基线；2026-10-07 补充图算法、snapshot、Analyzer
> alias graph 与组合交错 A/B；2026-10-13 补充有界文件读取 A/B 与单个 snapshot 内去重评估。
> 包含多组件个人/团队拓扑与五类能力共享依赖样本。数值不自动代表后续提交或其他机器。

Package 增删导致的 Workspace AOT 冷路径及后续正确性优先优化方案，见
[build_runner 正确性优先优化计划](CCRouter-build-runner-optimization-plan.md)。

- 日期：2026-09-28
- 环境：macOS arm64、Flutter `3.41.10-ohos-1.0.0`、Dart `3.11.5`
- 目标：提升生成速度，同时不跳过校验、不漏生成、不接受陈旧生成物
- 权威路径：`ccrouter generate <host> --no-cache --check`

## 1. 问题与结论

原有主要瓶颈不是 Route Pattern 冲突检测，而是 public barrel 校验。旧实现对每份 metadata
重复递归扫描 Package，并重复解析每个包含 `export` 的 Dart 文件，随声明与源码数量接近
O(metadata × files)。930 条 Route 的旧压力样本仅 Validator 就耗时 246.335 秒。

本轮完成四项有效优化：

1. metadata 先按 Package 汇总公开导出需求，每个 Package 只建立一次 Analyzer AST export
   index；internal-only Package 不扫描 barrel。
2. 增加 fail-closed 的无变化 fast path。源码、工具、Package graph、外部 Index 和受管输出
   必须逐字节摘要一致；否则自动回退完整生成。
3. 增加永久混合能力 benchmark，真实运行 build_runner 和完整 CLI，并覆盖 Route、Service、
   Command、Event、InitTask，而不是只构造内存 metadata。
4. 修复 `clean -> generate` 的二次收敛：当 build cache 仍存在且 authored source 导入的
   Route/Command/Event 或稳定 Component API 已被 `clean` 删除时，先从缓存 metadata 临时恢复这些
   CLI aggregate，再运行 build_runner；当前轮仍会重新生成并完整校验所有最终产物。
5. 增加多 Package 拓扑 benchmark，分别测量个人新建未生成组件、个人删除、团队拉取预生成
   组件和团队删除，并在每条场景路径后执行权威 Builder 校验及逐文件逐字节比较。

生成格式、公开契约和 Runtime 行为均未改变。

## 2. 混合压力模型

永久基准位于：

```text
packages/ccrouter_test/benchmark/generator_full_scaling.dart
```

每个 1× 单元按当前 Demo 的能力比例生成：31 Route、8 Service、5 Command、3 Event、8
InitTask。每项能力使用真实注解、Handler/Subscription/Task 与实际 build_runner 输出。

```bash
fvm dart run packages/ccrouter_test/benchmark/generator_full_scaling.dart \
  1 10 20 30 --convergence
```

可使用 `--incremental` 修改一个 Service stable ID，验证增量失效与重新生成。

## 3. 优化前基线

旧基线为一文件一路由、冷 Asset Graph、`--no-cache --profile`。它不包含其它能力，因此只用于
展示旧 Validator 的增长缺陷，不能直接当作相同 fixture 的整体速度 A/B。

| 规模 | Route / 源文件 | Validator | Wall time |
| --- | ---: | ---: | ---: |
| 1× | 31 / 33 | 0.672s | 31.501s |
| 10× | 310 / 312 | 27.994s | 60.127s |
| 20× | 620 / 622 | 109.945s | 144.560s |
| 30× | 930 / 932 | 246.335s | 282.883s |

当前 Demo 的旧稳定无变化生成约为 CLI 1.286 秒、进程 wall 1.82 秒。

## 4. 优化后结果

以下为包含五类能力的最终冷生成和连续两次无变化生成结果。生成文件数包含按
`componentId` 稳定命名的 `.api.g.dart` 入口；该入口只增加一个受管聚合文件，不改变
底层 Builder 的能力拆分。

| 规模 | Route | Service | Command | Event | InitTask | 源文件 | 生成文件 | Validator | 冷 Wall | 无变化 Wall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1× | 31 | 8 | 5 | 3 | 8 | 57 | 152 | 10ms | 17.023s | 0.372-0.407s |
| 10× | 310 | 80 | 50 | 30 | 80 | 552 | 1420 | 17ms | 18.313s | 0.549-0.558s |
| 20× | 620 | 160 | 100 | 60 | 160 | 1102 | 2830 | 32ms | 20.786s | 0.706-0.722s |
| 30× | 930 | 240 | 150 | 90 | 240 | 1652 | 4240 | 38ms | 23.451s | 0.810-0.852s |

30× 样本共有 1650 项真实能力。Validator 从旧 Route-only 样本的 246.335 秒降到混合样本的
38ms，并保持接近线性增长。冷生成当前主要成本是 build_runner/AOT（30× 为 20.398 秒），
不再是 Workspace 校验。

真实 Demo 无变化 `--check --profile` 的 CLI 内部耗时为 137ms，进程 wall 约 0.59 秒；相对旧
稳定值分别下降约 89% 和 68%。

修改一个 Service ID 时只重写 2 个输出。实测 1× wall 约 2.7 秒，30× wall 约 5.7 秒；规模
增长来自 build_runner 增量图、全局 Host Catalog 与逐字节 manifest 更新，不是 Validator。

## 5. 正确性与回退

fast path 的输入摘要包括：

- Host 闭包内可写 Package 的 authored Dart 源码与 `pubspec/build/ccrouter` 配置；
- Pub lock、Package config 和 Package graph；
- 当前生成器 `lib/bin/build.yaml/pubspec`；
- Dart SDK 版本与可执行文件 identity；
- 只读依赖的 Package Index 与 Runtime Bundle；
- 每个 CCRouter 受管生成物的完整内容。

manifest 采用版本、内容摘要和自校验 fingerprint。缺失、损坏、版本不兼容、源码变化、依赖
变化、生成器变化或受管输出被编辑时均回退 build_runner 和完整校验。`--no-cache` 永久绕过
fast path。测试覆盖无变化命中、源码变化、输出篡改、cache 损坏、并发锁、clean/rebuild 和
`--check` 现场恢复。

`clean` 后的 component API bootstrap（包括稳定 `.api.g.dart`）只在对应 authored import 存在且目标文件缺失时启用，
只消费仍由 build_runner 管理的缓存 metadata。它不跳过 build_runner，也不信任旧 metadata
作为最终结果；当前轮构建、解析、Validator 与聚合仍完整执行。bootstrap 或后续生成失败时会
恢复生成前现场。回归用例要求 `clean -> generate -> --no-cache --check` 的第二轮明确报告
`wrote 0 outputs`，防止 Asset Graph 需要额外一轮才能收敛。

## 6. 未采用的优化

### 6.1 合并 metadata Builder

曾将 6 个 metadata Builder 组合成一个 phase，并保持输出逐字节一致。实测冷生成反而慢约
0.8-1.5 秒，30× 从约 21.65 秒上升到 23.14 秒。原因是六套能力扫描在一个 BuildStep 内串行
执行，失去了 build_runner 原有调度优势。该实验已完整回退。

### 6.2 已落地的 per-Package dirty set

本轮没有使用不可靠的 mtime/size 快捷判断，而是在 build_runner 完成后按精确内容状态计算
Package dirty set。每个可写 Package 的状态包含 metadata fingerprint、当前
`lib/src/ccrouter_generated` 受管输出 fingerprint，以及直接依赖 Package Index 的
content fingerprint。

任一字段变化、缓存缺失或输出被篡改都会把 Package 标为 dirty；dirty 状态沿依赖图向消费方
传播。只有状态完全一致的 Package 才跳过组件 API、Bundle 和 Package capability catalog
的聚合写入，Host Catalog、Workspace Validator 和输出删除检查仍然运行。这样不会因为“未变
Package”而漏掉依赖级联、删除或篡改。

缓存 schema 已升级为 `2`，旧缓存会 fail-closed 并在下一次成功生成时重建。`--no-cache` 仍
绕过缓存和 dirty reuse，作为逐字节参考路径。

1× 混合能力基准的增量修改结果会输出 `dirtyPackages/dirtyPackageTotal`；单 Package fixture
中修改一个 Service 时为 `1/1`，并重新写出 2 个 Builder 输出。多 Package dirty closure
需要用真实依赖图继续采样，不能把单 Package 数值外推为所有项目的承诺。

`--profile` 现在同时输出实际 `build-targets` 和逐 Package 的 dirty 原因。原因区分 Host 固定
聚合、缓存缺失、metadata 变化、受管输出变化、直接依赖 Index 变化和反向依赖传播。该输出只
增强诊断，不参与生成判断，也不改变产物。

### 6.3 Pub Hook 进程启动

真实 Demo 的无变化 fast path 对照中，`dart run --verbosity=error
ccrouter_generator:ccrouter` 两次墙钟为 1.34 秒和 1.45 秒，CLI 内部为 0.32 秒左右；直接执行
`dart packages/ccrouter_generator/bin/ccrouter.dart` 两次墙钟为 4.92 秒和 4.98 秒，反而增加
约 3.5 秒，因为源码入口需要重新加载和编译工具依赖。Pub Hook 继续使用项目解析图下的
`dart run`，不切换到直接源码入口。预编译独立可执行文件会引入 Generator 版本与 Package Graph
同步问题，只有真实高频样本证明约一秒启动成本不可接受时才重新评估。

### 6.4 Build Plan P2-P4 补充样本

2026-10-03 当前 Demo（6 个组件、33 条路由）的稳定 fast path 为 0.172 秒；warm
`--no-cache --check` 为 1.961 秒，其中 build_runner 913ms。删除 `demo_payment` 的 P2
aggregation-only 为 0.904-0.996 秒；重新加入该预生成 Package 且本机无对应 Builder metadata
时，P3 Portable State 路径为 1.091 秒、build_runner 0ms，相对同轮权威路径减少约 44%。

干净副本的过滤冷路径为 16.338 秒，其中 build_runner 15.560 秒、AOT 约 10 秒、Validator
14ms。无 build filters 对照没有改善约 14 秒的 Builder 内部耗时，却把 CCRouter Builder 输入从
`38/48` 增至 `47/58`，额外运行 76 个 `build_test:test_bootstrap` action，并将写出数量从 75
提高到 230。过滤能控制作用域和无关输出，不能消除 AOT 成本。

最新 `build_runner 2.16.1` 需要 `analyzer >=13.3.0` 和 `meta ^1.18.3`，与当前 Flutter 固定的
`meta 1.17.0` 不可解析，因此没有进行无效的运行时对比或扩大 SDK 升级。当前数据不支持引入
watch/daemon、自有 Analyzer runner 或 build_runner 私有 API。

### 6.5 多组件个人与团队增删样本

永久基准位于：

```text
packages/ccrouter_test/benchmark/generator_component_topology.dart
```

```bash
fvm dart run packages/ccrouter_test/benchmark/generator_component_topology.dart 3 5 10
```

当前 Demo 有 6 个业务组件，因此 3x、5x、10x 分别构造 18、30、60 个组件 Package。每个组件
包含 5 Route、1 Service、1 Command、1 Event 和 1 InitTask；总能力数分别为 162、270、540。
基准为 author 与 teammate 创建相互独立的临时 Workspace，并区分两类不能混淆的新增：

- 个人新增：目标组件没有受管生成物，也没有本机 Builder metadata，必须 `runBuilder`；
- 团队新增：拉取 author 已提交的受管生成物和 Portable Generation State，但本机没有该组件
  Builder metadata，可以在验证当前源码、解析图和全部输出后 `aggregateOnly`。

以下均为进程 wall time；Pub 依赖解析单独列出，不计入 generation。冷种子和 fresh clone 用于
建立隔离基线，不代表日常每次生成。

| 规模 | 组件 / Route | 冷种子 | 稳定检查 | 个人删除 | 个人新增未生成组件 | 团队新增预生成组件 | 团队删除 | Pub 变更 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3x | 18 / 90 | 29.811s | 0.819s | 2.389s | 6.255s | 2.721s | 2.244s | 0.756-0.839s |
| 5x | 30 / 150 | 32.909s | 0.852s | 3.348s | 7.702s | 3.662s | 2.978s | 1.040-1.080s |
| 10x | 60 / 300 | 35.358s | 1.089s | 5.100s | 9.866s | 5.382s | 4.494s | 1.510-1.568s |

个人新增未生成组件的 build_runner 为 4.004/4.648/5.145 秒，Build Plan 原因稳定为
`portable-state-missing:<package>`。个人和团队删除、团队新增预生成组件的 build_runner 均为
0ms。10x 团队新增完整参考路径为 9.894 秒，优化路径为 5.382 秒；该差值不能外推为固定比例，
因为内容指纹和 Host 聚合仍完整执行。

准确性结果：3 个规模、12 条新增/删除场景路径全部 `byteExact=true`；author 与 teammate 的完整
受管源码生成物逐文件逐字节一致；删除后恢复到相同基线；组件/Route/Package 数量均与模型相符。
每次场景路径后均执行 `--no-cache --check`，不是只比较 Catalog 数量或摘要。快照明确排除
`.dart_tool/build`，因为它是不可提交且按机器不同的 Builder 中间状态，只比较 Package/Host 的
`lib/src/ccrouter_generated` 受管输出。

本轮同时发现并修复 Workspace 外 Path 依赖的证明不一致：Portable State 已计算这类依赖的
authored fingerprint，但本地 Build Plan 原先没有计算，导致真实 Path 接入错误回退
`resolution-unproven`。两者现共用同一套 Path 内容指纹采集；状态仍不持久化绝对路径。无法解析
root 或 graph、源码变化、状态缺失/失配时仍 fail closed，不会为了命中性能路径降低准确性。

### 6.6 F03/F04/F09 准确性修复后的 3x 回归

2026-10-03 修复外部分发身份、外部文件缓存漏检与 Proxy 字符串默认值后，单独执行
`fvm dart run packages/ccrouter_test/benchmark/generator_component_topology.dart 3`。
仍为 18 个组件、90 Route，各 18 个 Service/Command/Event/InitTask；保持完整内容校验。

| 场景 | 修复前历史 wall time | 修复后 wall time |
| --- | ---: | ---: |
| 冷种子 | 29.811s | 31.090s |
| 稳定检查 | 0.819s | 0.842s |
| 个人删除 | 2.389s | 2.566s |
| 个人新增未生成组件 | 6.255s | 6.472s |
| 团队新增预生成组件 | 2.721s | 2.698s |
| 团队删除 | 2.244s | 2.280s |

本轮 4 条增删路径全部 `byteExact=true`，逐文件比较 277 份受管输出，并分别通过
`--no-cache --check`。个人新增仍执行 Builder（4081ms）；个人删除、团队新增/删除仍为
`aggregateOnly`（Builder 0ms）。团队新增完整参考路径为 6.272s，author/teammate 的完整
输出相同，删除后恢复相同基线。Pub 变更单独为 0.765–0.791s，不计入表中 generation。

Demo 另测完整检查内部 3734ms、三次快速检查 436/422/431ms；相较审查上一批的历史
单次快速检查 312ms 有增加。表中是同机分时单次样本，不是同轮 A/B 或 P95，不能把差异
全部归因于补丁或宣称固定加速比例。该结果确认既有聚合复用和产物准确性保持成立；本轮
未重测 5x/10x，也未实施 P6 注释/公共依赖失效优化。独立 Git/源码归档和外部文件篡改
回归见[全框架审查第 9 节](CCRouter-framework-audit-2026-10-03.md#9-f03f04f09-修复验证2026-10-03)。

## 7. 后续触发条件

只有真实生产样本满足以下任一条件时，再进入下一轮架构优化：

- 30× 级别的单 Package 增量 P95 持续超过 6 秒；
- 多 Package 项目的 Host 聚合稳定超过总时延 20%；
- build_runner 冷阶段稳定超过 30 秒且 AOT 编译不是主要波动来源；
- 内存/RSS 显示当前逐字节摘要造成不可接受峰值。

per-Package manifest 与 reverse dependency closure 已作为保守 dirty set 落地；后续只在真实
收益足够时优化其输入摘要速度。不得跳过 Validator、依赖 watch/daemon 保证正确，或用 mtime/size
替代内容摘要。

## 8. Runtime 长时间与 RSS 观测

### 8.1 统一性能回归入口

常规回归可通过一个独立进程编排入口执行：

```bash
fvm dart run packages/ccrouter_test/benchmark/performance_regression.dart
```

它依次运行 Runtime scaling、并发导航、Service 生命周期、1000 轮 Runtime 重建、Analytics
队列压力，并为每个子进程输出结构化 JSON。发布候选或生成器变更时追加完整混合能力生成：

```bash
fvm dart run packages/ccrouter_test/benchmark/performance_regression.dart --full
```

`--full` 会增加 1x/10x/20x/30x 的 Route、Service、Command、Event、InitTask 真实注解生成和
连续 warm-run。该入口不设置跨平台绝对耗时或 RSS 阈值；CI/本地应保存同 SDK、同平台的 JSON
并比较 P50/P95、丢弃数、峰值队列、生成物 fingerprint 和资源清理状态。Flutter Widget、真实
设备和 OHOS smoke 仍由各平台命令单独执行，不能用 Pure Dart benchmark 冒充平台兼容性。

CI 的 `Performance advisory` job 会在同一个 Linux runner、同一个 Flutter/Dart SDK 上依次
运行目标分支的 base SHA 与当前 SHA，并通过 `--output=<path>` 保存两份完整 JSON artifact。
`tool/performance_compare.dart` 比较各子 benchmark 的进程 wall time；相对 base 增长超过 30%
时写入 Job Summary advisory，但当前阶段不阻断合并。报告 schema、平台、SDK、suite mode 或
benchmark 集合不一致仍作为配置错误失败，防止把不可比样本误当成性能结论。首次 push 等没有
有效 base SHA 的场景只保存 current 报告。该预算用于发现趋势，不是跨平台 SLA；微秒级
P50/P95、RSS 与生成器内部指标保留在 artifact 中，出现 advisory 后再用重复采样确认归因。

2026-09-29 在 macOS arm64、Dart 3.11.5 的一次完整运行结果：Runtime 10/100/1000 路由
初始化 P95 为 40/120/502us，动态打开 P95 为 77/115/436us；Service 1000 Provider 初始化
P95 为 3.4ms、销毁 P95 为 423us；并发导航 10 轮、每轮 100 次 push/pop 后最终保留 1 个
基准首页 Entry，pending 和 Adapter 额外 Entry 均为 0。Runtime 长运行 1000 轮、每 100 轮
重建一次，所有确定性清理条件通过；该次进程 RSS 增长约 24.2MiB，只作为同机趋势，不作为
泄漏结论。Analytics 5000 事件、容量 64 的入队 P50/P95 为 0/1us，峰值队列 64，丢弃 4935，
关闭后残留 0。1x/10x/20x/30x 全能力生成的冷 wall 分别为 1.08/1.94/2.80/3.76s，连续
warm-run 分别约 0.34/0.52/0.68/0.82s，所有生成物和 dirty-set 校验通过。

长期 Runtime 基准位于：

```text
packages/ccrouter_test/benchmark/runtime_long_run.dart
```

它在一个独立 Dart 进程中反复执行 typed `push/pop`，每隔固定周期销毁并重建 Runtime，
并在每轮验证以下确定性条件：

- 活动 `RouteEntry`、Backend Entry 和 pending navigation 在 Pop 后归零；
- Runtime `dispose` 后上述状态仍然归零；
- 诊断缓存保持在配置容量内；
- 所有 push Future 都完成，且没有未处理的导航错误。

示例：

```bash
fvm dart run packages/ccrouter_test/benchmark/runtime_long_run.dart \
  --cycles=10000 --recreate-every=100
```

输出包含同机的 P50/P95 导航耗时、初始/最终 RSS、RSS 采样序列和确定性峰值计数。RSS
只用于相同 SDK、平台和进程条件下的版本趋势比较，不作为跨平台的固定阈值；Dart 应用没有
稳定的纯 Dart Heap 快照接口，Heap 细分需要目标平台的 VM Service/DevTools 采样。发现
RSS 单调增长时，先用 `resource_lifecycle_regression_test.dart` 和 VM Service heap
snapshot 区分 Dart 对象保留、原生 Flutter 资源、测试 runner 或平台分配器，再决定是否
进入框架修复。

P0-3 状态：已建立生成器混合能力冷/热基线、Runtime 并发/回收基线、Service 生命周期基线
和独立长期 RSS 观测入口。真实 macOS、iOS 和 OHOS 的设备结果仍需在对应 SDK/设备上持续
采样，不能用当前 OHOS FVM SDK 的桌面测试失败替代平台结论。

## 9. P6 只读归因与混合依赖采样（2026-10-03）

本轮落地只读 Profile 归因，不修改完整内容 SHA-256、缓存 schema、失效传播或 Builder
跳过规则，因而**没有宣称生成提速**。新增 `input-delta` 区分自身源码/配置变化、解析变化与
工具/Host 图变化；缺少两侧 authored 摘要时单列 `authoredUnavailable`，不把空值当作源码
相同。`output-delta` 统计实际 Dart/JSON metadata/Markdown/Portable State 文件变更，
名称输出有界。字段缺失、损坏或强制参考路径时不虚构归因。

复现入口：

```sh
fvm dart run packages/ccrouter_test/benchmark/generator_component_topology.dart --invalidation 1 3 5 10
```

样本复用组件拓扑基准：1x 为 6 个组件，每个组件 5 个 Route、各 1 个 Service、Command、Event
和 InitTask；所有组件依赖同一个普通 Dart Package，并实际消费其默认值、描述和实现。最大
10x 为 60 个组件、300 个 Route，以及各 60 个 Service/Command/Event/InitTask。

每个规模冷生成一次，热检查三次，然后串行执行七种连续变更。每次验证 Profile 变更总数与
实际差异一致，再用 `--no-cache --check` 逐文件名、逐字节比较完整产物；四个规模共 **28 组
对照全部通过**，Package 名称截断后的总数也保持完整。不会以相同 fingerprint 字符串代替字节比较。

macOS arm64 / Dart 3.11.5，以下是 CLI 内部 elapsed，单位秒，包含 build_runner，排除 Pub 与
外层 `dart run` 启动。1x 冷启动期间并行了一次 Workspace analyze，其余规模采样期间未运行
全量测试；不把冷值差异当作精确硬件基准。每种变更仅一个样本，热路径 P50 仅来自三次采样，
不能称为真实项目 P95，也不能直接与旧报告的不同样本作提速比较。

| 规模 / 组件 | 冷生成 | 无变化热检查 P50 | 本地尾注释 | 共享依赖实现 | 共享默认值 | Profile 输出比较额外耗时 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1x / 6 | 27.078 | 0.246 | 4.918 | 4.919 | 5.126 | 13–14ms |
| 3x / 18 | 27.504 | 0.327 | 5.824 | 6.244 | 6.504 | 35–39ms |
| 5x / 30 | 29.668 | 0.394 | 6.607 | 7.302 | 7.552 | 56–62ms |
| 10x / 60 | 31.618 | 0.567 | 8.972 | 10.552 | 11.003 | 109–116ms |

这里的额外耗时只在 `--profile` 未命中后发生；`--check` 复用同一次输出比较，普通非 Profile
生成不增加比较，热命中不重扫产物。采样后补充的 `authoredUnavailable` 空摘要分类不改变
本表中的已知源码样本、生成决策或产物；最终实现另做 1x 七场景参考复验，复验与全量测试
并行，耗时不混入本表。

10x 的精确产物差异：

| 变化 | Dart | JSON metadata | Markdown | Portable State | 解析身份变化但自身已知摘要未变的 Package |
| --- | ---: | ---: | ---: | ---: | ---: |
| 单组件末尾普通注释 | 0 | 0 | 0 | 2 | 1 |
| 单组件等长度 DartDoc 修改 | 2 | 3 | 1 | 2 | 1 |
| 单组件五类声明前增加一行 | 2 | 3 | 2 | 2 | 1 |
| 共享依赖仅修改方法实现 | 0 | 0 | 0 | 61 | 61 |
| 共享默认值常量变化 | 60 | 0 | 0 | 61 | 61 |
| 共享描述常量变化 | 121 | 62 | 1 | 61 | 61 |
| 等价 barrel 导出重排 | 0 | 0 | 0 | 61 | 61 |

Dart 数量包含携带静态 Catalog 的生成代码，不等同于业务 API 数量。这个样本证明三点：

1. 共享依赖实现和等价导出变化确实能造成大量仅状态更新，存在减少团队 diff 的机会。
2. 仅按 metadata JSON 是否改变判断复用是不安全的：默认值样本中 metadata 不变，60 份
   生成 Dart 却必须更新。未来读取集合必须覆盖常量默认值，而不只是注解字段或方法签名。
3. 文档和定位不能统一忽略；等长度 DartDoc 与前加行都会更新 Catalog、文档或内嵌 Catalog Dart。

本次采样当时建议先证明五类 Builder 的类型、默认值、常量、导出、Codec 和泛型读取集合；
2026-10-04 已补 15 个入口的源码核对、受控读取反例、1x 七场景逐字节复验和生成阶段输入一致性
屏障，见
[优化计划 12.7](CCRouter-build-runner-optimization-plan.md#127-五类-builder-读取范围证据与-p6-决策2026-10-04)。
下一步评估只观察的保守文件闭包，不直接启用传播收窄；屏障实现和测试见优化计划 12.8。
历史版本曾加入 `--profile` `shadow-closure` 只读计算用于观察候选失效规模，不参与默认传播或
Builder 跳过；相关 Demo 参考值、1x/3x/5x/10x 规模数据和边界见优化计划 12.9。该诊断已从
生产生成路径移除，研究数据仅保留在本文档和 benchmark/tooling 记录中。四个规模的七种
变更均与完整 `--no-cache --check` 路径逐文件、逐字节一致，Shadow fallback 均为 `none`，
但这仍只是受控拓扑证据，未证明可移植的符号级语义闭包。
尚未实施语义摘要或默认开启；本轮没有新增 clone/RSS/Heap/P95
基准，也没有满足真实项目聚合持续超过 20% 的摘要微优化触发条件。此前分发、平台与长期
运行门禁继续适用，不能用这 28 组样本替代它们。

### 9.1 2026-10-04 真实 Demo 与多规模复测

当前 Demo Host 的一次 `--no-cache --profile` 为 6 个组件、33 Route、17 个生成 Package：
`build=853ms`、`aggregate/format/write=261ms`、CLI `total=2145ms`，聚合占总耗时约 12.2%；
macOS 同机峰值 RSS 为 227,540,992 bytes。该 RSS 只用于同机趋势，不是跨平台上限。

3x/5x/10x 本轮重新执行了 21 组连续变更（每个规模 7 组），全部通过完整参考路径逐文件、
逐字节比较。冷 Build/聚合分别为 13,283/379ms、13,615/541ms、14,366/878ms；失效路径的
聚合阶段范围分别为 275–412ms、370–606ms、597–956ms。Shadow 候选规模保持为 38/256、
62/424、122/844（Package/文件），fallback 全部为 `none`。主要耗时仍是 build_runner，尚
未满足摘要或传播收窄的稳定净收益门槛。

## 10. build_runner watch 实测（2026-10-05）

实现使用正式 `build_runner watch --workspace`，按 Host closure 传 `asset:` filters。每个成功
Builder 轮次后先验证 exact-content fast path；未命中时执行原 CCRouter preflight、输入屏障、
快照恢复、Validator、聚合、原子写入和 planning state 提交。AI 入口为
`generate demo --watch=auto --machine`；stdout 是 schema `1` NDJSON，build_runner 明细在 stderr。
`CCROUTER_DISABLE_BUILD_WATCH=1` 回退 one-shot，CI 仍使用 `--no-cache --check`。

同机 macOS arm64 / Dart 3.11.5 / build_runner 2.15.1，Demo 为 9 个 Builder Package、6 个组件、
33 个 Route。以下为真实连续 session 的 wall time；样本量不足以称为 P95：

| 场景 | build_runner | CCRouter 子轮次 | 合计 | 受管输出差异 |
| --- | ---: | ---: | ---: | --- |
| 首次 ready（cache warm） | 0.51s | 0.27s fast path | 约 1.39s（含启动/保护快照） | 0 |
| 注释变化，首个增量 | 2.03s | 1.17s | 3.20s | 0 |
| 注释恢复，稳态增量 | 0.39s | 1.16s | 1.55s | 0 |
| Widget body 修改/恢复 | 0.40/0.40s | 1.17/1.20s | 1.57/1.60s | 0 |
| Route annotation 修改 | 0.54s | 1.28s | 1.82s | 7 个文件 |
| Route annotation 恢复 | 0.55s | 1.24s | 1.79s | 7 个文件，恢复 Git 基线 |

结论不是“watch 已消除所有耗时”。它稳定消除了每轮外部 `dart run build_runner` 的进程、AOT
entrypoint 与 Analyzer graph 恢复成本，但非声明变化仍会触发 Builder 的 source_gen/Analyzer
解析，CCRouter 自身重复指纹、preflight、屏障、聚合与状态提交约占 1.2 秒。首个增量还可能出现
Analyzer warm-up 抖动。后续优化应以这份 phase trace 为依据，不重新引入 private State body
fingerprint 或 AST preflight；任何收缩都必须继续通过 kill switch、`--no-cache --check` 和逐字节
A/B 对照。

### 10.1 post-Builder planning 收缩

watch 的 Builder 成功已经证明本轮 Builder 执行完成，原实现的子进程仍先运行普通 fast-path
inspection 和 Build Plan 推导，再强制改为 aggregate-only；这些计算不参与最终决策。新路径从
本轮开始即标记 `build-runner-watch-completed`，跳过这两个 planning span，但保留 input
fingerprint、execution/before/after barriers、preflight、快照、Validator、聚合、cache 与本地
state 写入。`CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION=1` 恢复原路径。

同机以 Host 非生成语义 probe 连续运行，两侧受管输出均为逐字节 `files=0`：优化路径 `1110ms`，
kill-switch reference `1193ms`，单样本减少 `83ms`（约 7%）。主要剩余时间仍是输入证明、聚合与
两类本地 state 更新；该结果不是 P95，也不支持跳过 Validator 或重新引入 AST/private body
fingerprint。

### 10.2 generation cycle 进程内执行

post-Builder 路径原先每轮通过子进程重新进入 generator CLI，虽然不再启动 build_runner，仍会
重复支付 Dart process、generator entrypoint 和 CLI library graph 的启动成本。现在 one-shot 与
watch 共享结构化 generation cycle result；watch 默认在进程内执行并隔离普通 stdout，machine
stream 仍逐行保持 schema `1` NDJSON。`CCROUTER_DISABLE_WATCH_IN_PROCESS_CYCLE=1` 保留原
subprocess reference，`aggregationSucceeded.cycleMode` 明确记录实际路径。

同机、同一测试进程连续运行默认与 reference 路径，全部受管产物逐字节一致且 `files=0`：
in-process `1083ms`，subprocess reference `2626ms`，单样本减少 `1543ms`（约 59%）。完整
generator suite 并发负载下的观察值分别为 `2062ms` 与 `4127ms`，方向一致但不纳入基准结论。
这些仍不是 P50/P95；它只验证消除重复进程启动有明确收益，不能据此缩减 input barrier、快照、
Validator、原子写入或最终 `--no-cache --check`。

### 10.3 连续编辑 P50/P95 基线

新增可重复 benchmark：

```bash
fvm dart run packages/ccrouter_test/benchmark/generator_watch_edits.dart --samples=10
```

它在同一 watch/Analyzer session 中依次修改真实 Demo 的注释、Widget body、`initState`、新增普通
函数和 Route annotation，并执行真实 Dart 文件的新增、删除和重命名。每个 apply 样本后都恢复原始源码或文件布局并等待完整
`aggregationSucceeded`；默认输出每个 profile span 的 min/P50/P95/max，`--raw-samples` 可附带
逐轮明细。文件生命周期场景使用 PID 隔离的 benchmark fixture，删除和重命名前同样校验精确
内容，拒绝覆盖并发编辑；结束后比较全部 99 个
受管产物的路径和字节，并在停止 watch 后执行 `generate demo --no-cache --check`。

同机 macOS arm64 / Dart 3.11.5，每种场景 10 个 apply 样本。首次 ready 为 `4578ms`；单独记录的
首个增量 warm-up 为 `3687ms`，不计入下面的稳态分布：

| 编辑场景 | wall P50/P95 | build_runner P50/P95 | aggregation P50/P95 | 受管输出差异 |
| --- | ---: | ---: | ---: | ---: |
| 仅注释 | 1623/1686ms | 488/524ms | 702/721ms | 0 |
| Widget body | 1588/1638ms | 482/500ms | 699/709ms | 0 |
| `initState` body | 1632/1672ms | 510/516ms | 700/707ms | 0 |
| 新增普通函数 | 1632/1676ms | 509/526ms | 697/707ms | 0 |
| Route annotation | 1717/1762ms | 615/638ms | 741/765ms | 7 |

四种非生成语义编辑的耗时分布基本一致，说明当前剩余成本不是产物写入，而是 Builder 对源文件的
Analyzer/source_gen 失效处理，以及 generation cycle 的固定证明和状态提交。各 span 中，
`fast-path-manifest-write` P50 为 95–98ms，`build-plan-state-write` P50 为 135–141ms；两者每轮合计
约 230ms，是下一步合并 exact-content planning snapshot 的直接证据。输入 fingerprint、执行边界、
聚合前后 barrier 仍分别约 45ms，属于正确性门禁；本数据不支持删除或合并这些屏障。

本轮 5 类场景全部使用 `cycleMode=inProcess`，非生成变更稳定为 `files=0`，Route annotation
稳定为 7 个文件；最终受管产物指纹为
`3d71ce6d5006aa92dfe4931505fc9cd6515ba2136e417b6371cabf346fb3b0fc`，逐字节恢复和
`--no-cache --check` 均通过。该基线只用于同机 A/B，不是跨机器性能门槛。

### 10.4 cycle 末尾 shared planning snapshot

基线中 `fast-path-manifest-write` 与 `build-plan-state-write` 分别重新扫描 authored inputs、
Package Index 和受管输出。新路径在 aggregation 成功后捕获一次 exact-content planning snapshot，
由 fast-path manifest 和本机 Build Plan state 共同消费，再分别原子写入。它没有合并或跳过
execution/aggregation input barrier、Validator、artifact snapshot、`--check` restore，也不改变
Portable State 的显式 `prepare/publish` 语义。设置
`CCROUTER_DISABLE_SHARED_PLANNING_SNAPSHOT=1` 可恢复两次独立扫描，供逐字节与耗时 A/B。

同机 macOS arm64 / Dart 3.11.5，每种场景各 10 个 apply 样本：

| 编辑场景 | shared wall P50/P95 | reference wall P50/P95 | shared aggregation P50/P95 | reference aggregation P50/P95 |
| --- | ---: | ---: | ---: | ---: |
| 仅注释 | 1532/1583ms | 1629/1717ms | 594/608ms | 704/744ms |
| Widget body | 1542/1598ms | 1574/1660ms | 589/600ms | 698/717ms |
| `initState` body | 1535/1603ms | 1662/1796ms | 590/601ms | 711/845ms |
| 新增普通函数 | 1497/1567ms | 1651/1676ms | 589/596ms | 709/723ms |
| Route annotation | 1636/1685ms | 1762/1848ms | 626/657ms | 753/803ms |

10 样本采集时 shared cycle-end state path P50 约为 123–126ms，reference 的两次扫描 P50
分别为 95–99ms 和 136–144ms。最终实现为保留 Build Plan failure isolation，将 shared facts
捕获和 Build Plan 派生分别计时；最后一次权威检查分别为 112.9ms 和 21.0ms，manifest 原子写入
为 0.25ms。Build Plan 本地状态失败只令后续运行保守执行完整 Builder。aggregation P50 稳定减少
109–127ms，收益来自删除重复 I/O 与摘要计算，而不是猜测 Dart 语义。两侧都恢复原始源码，99 个
受管产物的路径与字节完全相同，最终指纹仍为
`3d71ce6d5006aa92dfe4931505fc9cd6515ba2136e417b6371cabf346fb3b0fc`，并通过
`generate demo --no-cache --check`。

### 10.9 watch current-output evidence reuse（2026-10-05）

10.8 后继续拆分 reuse-hit cycle，发现 `workspace-aggregation` P50 约 123–127ms，其中 before/after
input barrier 各约 45–48ms；实际 metadata/model/validation 已不是主要耗时。更明显的重复来自
`output-delta-scan` 已读取本轮 current managed-output bytes，而紧随其后的 planning snapshot 又扫描
同一批输出。现在 delta scan 返回变化列表和 exact bytes，planning state 直接消费；Builder、完整
aggregation、两次 barrier、Validator、artifact restore、原子写入均不变。
`CCROUTER_DISABLE_WATCH_OUTPUT_EVIDENCE_REUSE=1` 保留 delta scan 但恢复独立 planning output scan；
Profile 默认报告 `input-and-current-output`。

同机连续 optimized/reference A/B，每场景 3 个 apply 样本；两侧仅切换本项 kill switch。机器仍为
Battery + macOS Low Power Mode，因此只用于方向判断：

| 编辑场景 | wall optimized/reference P50 | aggregation optimized/reference P50 | planning snapshot optimized/reference P50 |
| --- | ---: | ---: | ---: |
| 普通注释 | 1352/1397ms | 399/430ms | 23.4/60.2ms |
| Widget body | 1349/1389ms | 390/427ms | 23.5/59.9ms |
| `initState` body | 1364/1385ms | 390/425ms | 23.3/60.3ms |
| 新增普通函数 | 1353/1385ms | 387/422ms | 23.1/59.5ms |
| Route annotation | 1658/1732ms | 547/596ms | 24.4/65.1ms |
| 新增 Dart 文件 | 951/993ms | 389/426ms | 23.1/60.1ms |
| 删除 Dart 文件 | 954/963ms | 400/436ms | 23.2/60.7ms |
| 重命名 Dart 文件 | 960/1007ms | 395/445ms | 23.4/60.3ms |

planning snapshot P50 减少 36–41ms，aggregation cycle 减少 31–50ms，wall P50 减少 9–74ms。
optimized 八个场景均报告 `input-and-current-output`；reference 的七个 reuse hit 场景为
`input-and-aggregation-output`，Route annotation miss 为 `input`。两轮均恢复源码、删除 fixture、
得到相同的 99 文件指纹
`1a09cc7e146346a1490ea72190c2d9147788c318950c004d4e138e015cef7dc5`，并通过
`generate demo --no-cache --check`。

### 10.5 post-Builder aggregation input 诊断

下一阶段先增加 diagnostic-only `aggregation-input-fingerprint`，不增加缓存状态、不跳过 Builder、
Validator、aggregation 或写入。identity 覆盖 Builder metadata 的逐字节摘要、经过 public-barrel
和 consumer annotation 后的 Package Index identity、Host closure、依赖顺序及 runtime bundle
集合；普通源码全文不直接进入该 identity。fingerprint 作为 profile span 的安全 `attributes`
进入 one-shot trace 和 watch machine event。

同机 macOS arm64 / Dart 3.11.5，每种场景 10 个 apply 样本：

| 编辑场景 | baseline 匹配 | 不同 fingerprint | fingerprint P50/P95 | wall P50/P95 | aggregation P50/P95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 仅注释 | 10/10 | 1 | 0.220/0.264ms | 1591/1638ms | 609/624ms |
| Widget body | 10/10 | 1 | 0.209/0.369ms | 1563/1655ms | 601/635ms |
| `initState` body | 10/10 | 1 | 0.212/0.400ms | 1561/1599ms | 601/620ms |
| 新增普通函数 | 10/10 | 1 | 0.210/0.249ms | 1552/1612ms | 597/612ms |
| Route annotation | 0/10 | 10 | 0.214/0.240ms | 1714/1810ms | 641/687ms |

每个 restore cycle 都恢复同一 baseline identity；非生成语义编辑稳定保持 identity，Route
description 的每个不同值都产生不同 identity。最终源码恢复，99 个受管产物逐字节一致，指纹为
`9bd22a574ca8a17c68223a602b90fbb42469670b6a70b07e961f17c1fd1637b6`，并通过
`generate demo --no-cache --check`。

随后复用 1x 隔离组件拓扑样本补齐 aggregation 输入矩阵：6 个组件覆盖五类能力和共享依赖，
初始 31 个 Route；10 个变更串行执行，每次 optimized 结果都与 `--no-cache --check` 的
aggregation fingerprint 一致，并逐文件名、逐字节比较 92 份受管产物（声明删除后为 90 份）。

| 变更 | aggregation fingerprint | 受管产物差异 | 结论 |
| --- | --- | ---: | --- |
| 本地尾部普通注释 | 不变 | 0 | aggregation 不消费普通注释 |
| Route 参数 DartDoc | 变化 | 6 | 位置/文档 metadata 属于 aggregation 输入 |
| 五类声明前增加一行 | 变化 | 7 | 源码位置属于 aggregation 输入 |
| 共享依赖方法实现 | 不变 | 0 | 未被生成消费的实现不进入 aggregation identity |
| 被消费的共享默认常量 | 不变 | 6 Dart | Builder 输出变化，但 aggregation 输入不变 |
| 被消费的共享描述 | 变化 | 22 | Builder metadata、Catalog 和文档都需要更新 |
| 共享依赖等价 barrel 重排 | 不变 | 0 | 解析后的有效输入未变 |
| 组件 public barrel 等价重排 | 不变 | 0 | public annotation 结果未变 |
| 新增未使用的 Package dependency edge | 变化 | 0 | Host/Package graph identity 必须失效 |
| 删除一个 Route 声明文件 | 变化 | 11 | 删除、索引、Catalog 和旧产物清理必须执行 |

默认常量场景是关键边界：`aggregation-input-fingerprint` 描述的是 **post-Builder aggregation**
读取集合，不是全部 Builder outputs 的摘要。Builder 已经正确更新 6 份 Route Dart 后，稳定
fingerprint 才能授权未来只复用 aggregation 结果；它绝不能用于跳过 Builder。反过来，新增未使用
dependency edge 虽然当前产物为零差异，仍因图身份变化而失效，避免把一次输出巧合当作长期证明。
该矩阵先作为 diagnostic 证据建立边界；后续 production prototype 与结果见 10.6。

### 10.6 post-Builder aggregation reuse（2026-10-05）

production path 只在 Builder 已成功后检查三项 exact-content proof：Tool fingerprint、10.5 定义的
aggregation input fingerprint，以及入口 artifact snapshot 中 aggregation-owned outputs 的 bytes。
命中只跳过 aggregation rendering/writes、dirty-set 计算和本轮无必要的 metadata-cache persist；
内部 API/Portable 校验、Package graph/index 构造、Workspace Validator、前后 input barrier、
generation lock、artifact restore 和原子 state publication 均保留。入口与 cycle-end output proof
分别复用已有 artifact/planning snapshot，不额外扫描磁盘。状态只位于
`.dart_tool/ccrouter/v1/aggregation_reuse/`，`CCROUTER_DISABLE_AGGREGATION_REUSE=1` 恢复完整路径，
`--no-cache --check` 强制 `miss/no-cache-reference`；metadata cache 损坏也强制完整路径并重建缓存。

同机 Demo watch、每场景 5 个 apply 样本的 optimized/reference P50 如下（macOS arm64，Dart
3.11.5；只作同机趋势）：

| 编辑场景 | reuse | wall optimized/reference | aggregation optimized/reference |
| --- | ---: | ---: | ---: |
| 普通注释 | 5/5 | 1419/1525ms | 488/584ms |
| Widget body | 5/5 | 1428/1574ms | 466/581ms |
| `initState` body | 5/5 | 1406/1564ms | 460/581ms |
| 新增普通函数 | 5/5 | 1417/1542ms | 462/595ms |
| Route annotation | 0/5 | 1694/1726ms | 619/630ms |

四类命中场景 wall P50 减少 106–158ms，`workspace-aggregation` P50 从约 240–250ms 降至
119–126ms。Route annotation 保持 miss 并执行完整 aggregation。扩展后的 1x 矩阵共 11 个场景，
新增 output tamper 必须报告 `miss/output-changed` 并修复；所有场景均通过 `--no-cache --check`
逐文件名、逐字节对照。optimized/reference 最终 99 个受管文件 fingerprint 同为
`1bd915a3a986a88f94337111aa37b7114c41afabad1727548ab75a23ab766c14`。

### 10.7 Dart 文件生命周期 smoke A/B（2026-10-05）

在 10.3 的 benchmark 中补充三类真实 asset graph mutation：新增此前不存在的 Dart 文件、删除
watch 启动时已存在的 Dart 文件，以及把已存在文件重命名后再改回。fixture 均位于
`demo/modules/navigation_lab/lib/src`，不包含 CCRouter 注解；每次 apply/restore 都等待完整
`aggregationSucceeded`。异常路径按 exact contents 恢复，结束时要求 fixture 全部删除、99 个受管
产物逐字节不变，并通过 `--no-cache --check`。

以下为同机连续 optimized/reference A/B，每场景 3 个 apply 样本。机器运行于 Battery + macOS
Low Power Mode；样本量只够验证方向，因此列 P50/max，不把 max 表述为稳定 P95：

| 文件操作 | wall optimized/reference P50 | wall optimized/reference max | build_runner optimized/reference P50 | aggregation optimized/reference P50 |
| --- | ---: | ---: | ---: | ---: |
| 新增 Dart 文件 | 1622/1875ms | 1624/1876ms | 214/231ms | 900/1130ms |
| 删除 Dart 文件 | 1606/1856ms | 1616/1856ms | 193/193ms | 907/1147ms |
| 重命名 Dart 文件 | 1650/1875ms | 1679/1899ms | 229/226ms | 909/1132ms |

三类操作的 optimized 路径均为 `cycleMode=inProcess`、`aggregation-reuse=hit 3/3`、受管输出
`files=0`；kill switch 路径均为 `miss/disabled`。复用降低 wall P50 约 233–253ms，但 Builder
本身只有 193–229ms，当前文件生命周期场景的主要固定成本仍是 CCRouter input proof、barrier、
snapshot 和 planning state，而不是 build_runner 对新增/删除 asset 的图更新。本轮结果不支持
跳过这些正确性门禁；若要形成性能门槛，应在 AC Power、关闭 Low Power Mode 后执行至少 10 个
样本重新建立 P50/P95。

### 10.8 watch barrier evidence reuse（2026-10-05）

watch 的 after-aggregation barrier 原本完成一次 exact-content input capture 后只返回 `bool`，
紧随其后的 planning snapshot 又读取相同输入。现在 barrier 返回完整 snapshot，planning state 直接
消费该证据；aggregation reuse 命中时还复用入口 artifact snapshot 中已验证未变的
aggregation-owned bytes，但 Builder-owned outputs 始终从当前文件重新读取。所有 barrier、
Validator、artifact restore、独立原子状态写入和最终 `--no-cache --check` 均保留。
`CCROUTER_DISABLE_WATCH_EVIDENCE_REUSE=1` 恢复完整 recapture；Profile 通过
`planning-snapshot-capture.attributes.evidenceMode` 区分实际路径。

同机连续 optimized/reference A/B，每场景 3 个 apply 样本；两侧均启用 aggregation reuse，只切换
本项 kill switch。机器仍为 Battery + macOS Low Power Mode，因此只比较同轮 P50，不建立正式
性能门槛：

| 编辑场景 | wall optimized/reference P50 | aggregation optimized/reference P50 | planning snapshot optimized/reference P50 |
| --- | ---: | ---: | ---: |
| 普通注释 | 1384/1436ms | 437/473ms | 59.9/108.4ms |
| Widget body | 1387/1463ms | 434/470ms | 59.6/108.3ms |
| `initState` body | 1385/1413ms | 431/470ms | 59.5/108.3ms |
| 新增普通函数 | 1382/1423ms | 422/465ms | 59.9/108.6ms |
| Route annotation | 1674/1718ms | 584/636ms | 66.2/112.3ms |
| 新增 Dart 文件 | 979/1058ms | 427/480ms | 59.8/109.7ms |
| 删除 Dart 文件 | 990/1032ms | 441/485ms | 59.9/110.0ms |
| 重命名 Dart 文件 | 1003/1054ms | 435/485ms | 59.5/110.8ms |

planning snapshot P50 减少 46–51ms，wall P50 减少 28–79ms。七个 reuse-hit 场景报告
`input-and-aggregation-output`；Route annotation 因 aggregation miss 报告 `input`，只复用最终
barrier input。kill-switch reference 全部为 `recaptured`。额外的 Builder-only 边界测试把 Route
默认 const 从 `false` 改为 `true`：`.route.g.dart` 更新而 aggregation 仍命中，optimized/reference
的受管产物、fast-path manifest 和 Build Plan state 逐字节一致。两轮 benchmark 最终都恢复源码、
删除 fixture、得到相同的 99 文件指纹
`cb927a19b7867c0fcd6dd6dabe5c72e8b465975c2f73480b1b8258767783eab6`，并通过
`generate demo --no-cache --check`。

### 10.10 watch 调度窗口拆分（2026-10-05）

在 10.9 后继续拆分 `wall - build - aggregation` 的稳定空档。benchmark 现在直接监听 machine
events，并记录 `changeToBuildStartMs`、`observedBuildWindowMs`、
`buildToAggregationHandoffMs` 和 `observedAggregationWindowMs`；任一调度事件缺失都会 fail-fast。
3-sample 真实编辑矩阵得到：

| 编辑场景 | wall P50 | change → build start P50 | observed build P50 | handoff P50 | observed aggregation P50 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 普通注释 | 2235ms | 497ms | 967ms | 0ms | 760ms |
| Widget body | 2208ms | 500ms | 981ms | 0ms | 741ms |
| `initState` body | 2218ms | 498ms | 981ms | 0ms | 736ms |
| 新增普通函数 | 2208ms | 499ms | 982ms | 0ms | 722ms |
| Route annotation | 2774ms | 507ms | 1240ms | 0ms | 1020ms |
| 新增 Dart 文件 | 1448ms | 507ms | 209ms | 0ms | 728ms |
| 删除 Dart 文件 | 1439ms | 506ms | 186ms | 0ms | 747ms |
| 重命名 Dart 文件 | 1481ms | 508ms | 225ms | 0ms | 750ms |

本轮仍为 Battery + macOS Low Power Mode，build/aggregation 绝对值受当时机器负载影响；调度边界
仍清晰：build 完成到 CCRouter aggregation 启动的 P50 为 0ms，观察窗口与双方内部报告只差
0–2ms，CCRouter handoff 没有待消除的固定等待。约 500ms 全部位于 build_runner 开始构建前。

依赖源码解释了该窗口：`watcher 1.2.1` 的 macOS recursive watcher 在原生事件后固定等待 200ms，
待文件系统更新稳定后再 poll；`build_runner 2.15.1` 随后使用固定 250ms trailing
`debounceBuffer`。build_runner 只允许 testing-only `TestingOverrides.debounceDelay` 覆盖，CLI 和公开
API 均没有生产入口。通过私有 `src/`、修改 Pub cache 或自维护 bootstrap 降低 debounce 会引入
版本耦合，还会削弱编辑器 safe-write 与 AI agent 多文件写入的事件合并，因此本轮明确不改生产
调度。后续仅在 build_runner 提供正式配置时，用新增阶段指标对 250ms reference 做 A/B。

benchmark 最终恢复源码、删除 fixture、保留 99 个生成物的逐字节一致性，并通过
`generate demo --no-cache --check`。

### 10.11 Builder phase 与 Asset Graph 失效归因（2026-10-05）

watch machine event 的 `buildSucceeded.buildRunner` 现按 build_runner 2.15.1 正式
`--verbose-durations` console 格式记录每个 Builder phase 的 duration、inputs、skipped、
not-triggered、new/same/no-op output 和 analyzing/resolving/tracking/building/reading/writing。
`invalidatedInputs = inputs - skipped`，`executedInputs = output + same + no-op`；它们是上游计数的
诊断解释，不是 private Asset Graph 节点列表，也不参与任何生成决策。中间 progress line 不计入，
未知终态格式有界保留但不使生成失败。parser 位于 CLI diagnostic 层，不进入 execution-kernel
fingerprint。

3-sample 真实编辑矩阵的 P50 如下。`inputs`、`invalidated` 是 15 个 phase 的合计，同一个 Dart
asset 会在多个 phase 中重复计数，不能解释为唯一文件数：

| 编辑场景 | wall | 调度等待 | Builder | aggregation | inputs / skipped / invalidated / executed | new / same / no-op |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 普通注释 | 2272ms | 501ms | 890ms | 746ms | 660 / 639 / 21 / 21 | 0 / 3 / 18 |
| Widget body | 2246ms | 489ms | 900ms | 730ms | 660 / 639 / 21 / 21 | 0 / 3 / 18 |
| `initState` body | 2293ms | 503ms | 940ms | 737ms | 660 / 639 / 21 / 21 | 0 / 3 / 18 |
| 新增普通函数 | 2261ms | 500ms | 910ms | 725ms | 660 / 639 / 21 / 21 | 0 / 3 / 18 |
| Route annotation | 2787ms | 508ms | 1110ms | 1018ms | 660 / 535 / 125 / 125 | 2 / 26 / 97 |
| 新增无注解 Dart 文件 | 1460ms | 513ms | 90ms | 734ms | 675 / 660 / 15 / 15 | 0 / 0 / 15 |
| 删除无注解 Dart 文件 | 1453ms | 512ms | 60ms | 746ms | 645 / 645 / 0 / 0 | 0 / 0 / 0 |
| 重命名无注解 Dart 文件 | 1509ms | 513ms | 100ms | 749ms | 660 / 645 / 15 / 15 | 0 / 0 / 15 |

普通注释、Widget body、`initState` 和新增普通函数的失效形状完全相同：变更 asset 在所有相关
Builder 上重新执行，最终 18 次 no-op、3 次 same output、0 次 new output。耗时主要记在第一个
`service_contracts` phase，其 P50 为 760–810ms，其中 `resolving` 为 710–760ms、`analyzing`
约 30–40ms。该归因表示 long-lived Analyzer 在首个需要 Resolver 的 phase 更新 library graph，
不表示 Service Contract 业务生成本身耗时 800ms。build_runner 终态可能写 `wrote 3 outputs`，
这里对应 3 个 byte-identical `sameOutputs`，不是三份实际变化的生成物。

Route annotation 会真实扩大失效：125 次 Builder 执行、2 个 new output，并使 aggregation miss；
因此不能用“普通 body 编辑无输出”的结论跳过 Builder。无注解文件增删改名样本仅证明这类孤立
fixture 的 graph update 很低，不能外推到被 import、带注解或改变 public API 的文件。

结论是当前剩余 Builder 时间首先来自 Resolver/library graph update，其次才是 15-phase 的 no-op
执行。直接按 AST/body/comment 预判或跳过 Builder 仍不成立。下一轮若继续优化，应优先研究能否在
保持自动注解发现的前提下合并同一 asset 的 Resolver/Generator 遍历，并用现有逐 phase 指标验证；
不能退回手工 Binding，也不能依赖 build_runner private Asset Graph 或 testing-only debounce API。

本轮 benchmark 恢复源码、删除所有 add/delete/rename fixture，99 个受管生成物逐字节一致，并通过
`generate demo --no-cache --check`。

### 10.12 Analyzer exact-path polling 算法基线（2026-10-07）

Analyzer Plugin 的 scale benchmark 补充 100/1,000/5,000/10,000 exact paths，分别测量当前
full-scan reference、共享 reverse identity index、10-shard fallback 和单文件 event path。候选与
reference 对修改、删除、重建及 120 轮确定性 filesystem churn 的 affected source 集合完全一致；
101 路径跨 10 个 shard 的 inspected path 总数和结果也与一次 full scan 一致。

同机 10,000 路径样本中，reference/candidate full-scan P95 分别约 23.6/22.7ms，说明 reverse
index 没有让 correctness fallback 产生负优化；单文件 event path 约 17us。10-shard 单 tick P95
约 3.4ms，降低约 85%，代价是同时遗漏文件事件与 validated generation epoch 时，完整审计最坏
从 500ms 放宽到 5 秒。因此生产默认仍为逐 tick full scan，只通过
`CCROUTER_ENABLE_ANALYZER_TIERED_POLL=1` 提供 maintainer A/B。启用该开关后的真实 Legacy/LSP
Analysis Server 15 项回归通过；最终生成正确性仍由 Generator 与 `--no-cache --check` 负责。

### 10.13 Generator dirty graph 算法基线（2026-10-07）

`_GenerationDirtySet` 原先通过反复全图扫描传播上游失效；Package 迭代顺序与依赖方向相反时，
严格链会退化为 O(V²)。生产路径现改为先建立 reverse adjacency，再以 queue 求传递闭包，保持
“任一依赖 dirty 则所有可写下游 dirty”的保守边界，不改变 Builder、Validator、cache schema、
fingerprint 或写入协议。链、菱形、断图、环、外部 seed 以及 240 轮确定性随机图均与原 fixed-point
reference 得到完全相同的 dirty set。

预热后的 benchmark 直接调用生产 helper。5,000 Package、约 10,000 edges 的稀疏图中，旧实现与
reverse closure 的 P95 约为 2.49ms/0.66ms；5,000 Package 的反向严格链约为
367ms/0.70ms。100 Package 稀疏图也未出现负优化。完整 `CCRouteWorkspaceValidator` 在 120 个
component、600 routes 时约 10.7ms P95，远低于当前真实 watch 的 Builder 和 aggregation 耗时；
因此本阶段不引入增量 Validator，也不缩小权威校验范围。

### 10.14 Generator unified epoch snapshot（2026-10-07）

新增独立 filesystem benchmark，按 Demo 等价 11 个 Package 扩展到 1x/3x/5x/10x，分别读取
authored inputs、全部 managed outputs、writable outputs 和 aggregation outputs。reference 每个视图
独立遍历，candidate 一次 exact-content capture 后派生不可变视图；两侧对 baseline 及 input/output
的 add/change/delete/rename 均逐路径、逐字节、逐 fingerprint 相同。1x 的 reference/candidate P95
约为 38.2/18.9ms，10x 约为 396.8/196.9ms，四个 scale 均约 2.0x。

生产路径只复用处于同一成功边界的证据：最终 input barrier snapshot、profile/check 的 current
output delta，或 metadata-cache persist 已读取的 writable output bytes。入口 artifact snapshot、
Builder 前后 input barrier、`--check` restore 重扫仍独立保留，读取失败继续 fail closed。真实 Demo
的 `--no-cache --profile --check` 单次 A/B 中，planning capture 由约 101ms 降至 18.7ms，
wall 由约 1976ms 降至 1917ms；该 wall 数据仅作方向验证，Builder 抖动不计为算法收益。
`CCROUTER_DISABLE_UNIFIED_EPOCH_SNAPSHOT=1` 恢复完整 planning recapture，默认/reference 的生成物、
fast-path manifest 和 Build Plan state 逐字节一致，最终仍以 `--no-cache --check` 为权威门禁。

### 10.15 Builder protection snapshot reuse（2026-10-07）

one-shot generation 的入口 artifact snapshot 已读取 build root 内全部 managed outputs，随后
`_runBuildRunner` 为保护 non-target Package 又遍历一次相同目录。新路径从入口 bytes 派生 excluded
target view；build root 外 read-only Package 仍单独捕获，Builder 后 restore 仍重新扫描当前路径并
逐字节比较。bootstrap 只写 writable Builder targets，因此不会在两个时点之间合法改变被保护集合。

snapshot scale benchmark 中，1x reference/derived P95 约为 6.9ms/72us，10x 约为
79.8ms/2.17ms，所有 protection 路径与 bytes 完全一致。真实 Demo 单次 A/B 的
`build-runner-protection-snapshot` 约为 149ms/60ms；剩余时间来自 32 个 root 外 read-only Package，
不能复用 build-root snapshot。同期 wall 约为 3471ms/3483ms，受 Builder 与 input scan 抖动影响，
不作为总耗时收益证据。`CCROUTER_DISABLE_SHARED_BUILD_PROTECTION_SNAPSHOT=1` 恢复完整二次扫描，
Profile 以 `evidenceMode=shared/recaptured` 区分，两侧生成物、状态与 `--no-cache --check` 一致。

### 10.16 当前 Demo 组合交错 A/B 与入口边界（2026-10-07）

为避免把单次 Builder 抖动当作收益，当前 11 generated Packages、6 components、33 routes 的 Demo
先各做一次不计入统计的 warm-up，再按 `A-B-B-A` 交错执行 12 次；A 为当前默认路径，B 同时关闭
unified epoch、shared build protection、shared planning snapshot、Runtime Bundle reverse closure、
InitTask reachability memo 和 Route visibility memo。命令统一为：

```bash
fvm dart run ccrouter_generator:ccrouter generate demo --no-cache --check
```

该 B 组只覆盖上述六个现有 kill switch，不等同于把分支回退到所有优化前的历史提交。dirty graph
没有独立环境开关，因此不进入这一端到端组合数据，而由 10.17 的内置 fixed-point reference 做
集合等价和耗时对照。

| 路径 | Reference P50/P95 | Optimized P50/P95 | 结论 |
| --- | ---: | ---: | --- |
| 权威 one-shot | 3.713s / 3.725s | 3.330s / 3.346s | P50 减少 383ms，约 10.3% |
| unchanged fast path | 423ms / 430ms | 419ms / 421ms | 差异落在噪声范围 |

拆分复测中，全部开启、只关闭三项图算法、只关闭三项 snapshot 复用的 P50 分别约为
3.335s、3.338s、3.711s。因此当前小 Demo 的端到端可见收益主要来自同一 generation transaction
复用已验证 snapshot；图算法收益在该规模下被 build_runner/AOT/Analyzer 固定成本淹没。该数据
只代表 one-shot `--no-cache --check`，不能外推为 watch、Pub Hook wait 或 Analyzer latency。

入口正确性以共享 kernel 和 exact evidence 收敛，而不是强制相同 orchestration：无 watch 的
Pub Hook 启动默认 one-shot；活动 watch 复用常驻 Builder 并等待 exact Host/per-Package evidence；
package-local 不执行 Host-wide 校验；Analyzer 只提供 advisory diagnostics。watch、one-shot 和
Pub Hook 的逐字节/状态 differential 分别由对应 suite 覆盖，最终 CI 仍以实际 Host 的
`--no-cache --check` 为权威。

### 10.17 图算法与 Analyzer alias graph 放大 A/B（2026-10-07）

同机 reference/candidate benchmark 每轮先验证集合、映射或诊断结果等价，再记录耗时：

| 场景 | 指标 | Reference | Optimized | 约加速 |
| --- | --- | ---: | ---: | ---: |
| Dirty Package 反向链，5,000 Package | P95 | 697.9ms | 1.06ms | 657x |
| Runtime Bundle 反向链，5,000 Package | P95 | 763.0ms | 1.24ms | 614x |
| InitTask optional chain，1,000 tasks | P95 | 49.99ms | 0.30ms | 164x |
| Route visibility，1,000 components / 20,000 routes | P95 | 818.1ms | 44.8ms | 18.3x |
| Analyzer production alias，500 aliases | P50 | 464.4ms | 4.45ms | 104x |
| Analyzer production alias，1,000 aliases | P50 | 1.808s | 4.86ms | 372x |

这些是规模退化保护，不是“真实 Demo 提速数百倍”的声明。Generator 图算法作用于 Host
aggregation/validation；Analyzer alias graph 只作用于 Plugin 单文件 Owner 检查。Analyzer 100
alias 的 P95 受 JIT/GC warm-up 顺序影响明显，因此报告大型样本的 P50，不用一次尾部样本宣传收益。
Analyzer tiered exact-path polling 仍默认关闭，它的延迟/吞吐取舍见 10.12，不能与默认开启的 alias
graph 混为一项。

### 10.18 有界 exact-byte 文件读取（2026-10-13）

源码、managed outputs、Generator kernel 和 dependency preflight 的读取仍包含串行 I/O。
本轮只调整读取调度：每个 isolate 共享最多 4 个读取许可，Package capture 之间不增加并发，
每次 capture 独立读取完整 bytes，并按原 logical-name 顺序交付结果。任何读取失败都先排空
已启动的操作，再抛出原始错误；不发布部分结果，也不让 rollback 与残留读取交错。
`CCROUTER_DISABLE_PARALLEL_FILE_READS=1` 恢复串行读取。目录发现范围、摘要编码、input barriers、
Validator、锁、恢复重扫和原子写入继续保留；没有引入跨 cycle 内容缓存。

测量环境为 macOS arm64、Dart 3.11.5。规模 benchmark 使用当前 Demo 的 11 个 Package、155 个
源码/配置/生成 Dart 与 metadata 文件，复制为 1x/3x/5x/10x。三个独立进程按 1/4/8 workers
轮换顺序，每个进程预热两次、采样 12 次；每个结果均与独立串行 oracle 逐字节、逐摘要对照。
以下仅包含读取和 hashing，不包含目录发现、Analyzer、Builder 或完整生成：

| 规模 | 文件数 | 串行 P50 / P95 | 4 workers P50 / P95 |
| --- | ---: | ---: | ---: |
| 1x | 155 | 19.52 / 24.80ms | 14.67 / 19.29ms |
| 3x | 465 | 52.73 / 77.29ms | 41.51 / 55.81ms |
| 5x | 775 | 85.99 / 130.51ms | 82.39 / 100.21ms |
| 10x | 1550 | 183.64 / 338.88ms | 142.79 / 200.75ms |

8 workers 在部分样本中更快，但收益没有扩大到数量级，且会增加同时读入的文件数，因此采用
4 workers 作为保守默认值。独立进程峰值 RSS 包括 Dart VM/JIT、oracle 和候选快照，不能当作
reader 自身内存；10x 本轮峰值为串行约 301MiB、4 workers 约 361MiB、8 workers 约 377MiB。
不宣称内存无代价或已证明任何规模下都不会负优化；生产 reader 不缓存结果，失败后许可归还
和同时 capture 的总并发上限由确定性测试覆盖。

真实 Demo 通过正常缓存 CLI 入口交错执行 6+6 个样本，预热不计入。与文件规模 benchmark
分别计时，不能把阶段加速比例外推为完整生成收益：

| 路径 | 串行 wall P50 | 4 workers wall P50 | 串行内部 P50 | 4 workers 内部 P50 |
| --- | ---: | ---: | ---: | ---: |
| 无改动 `--check --profile` | 722ms | 692ms | 308.90ms | 298.03ms |
| `--no-cache --check --profile` | 2773ms | 2809ms | 2380.61ms | 2369.25ms |

无改动 fast path 的 wall P50 减少约 30ms；完整参考路径基本持平，wall P50 反而高 36ms，
不能据此宣传完整生成提速。完整参考路径 Builder actions 全 skipped，仍包含约 0.88s 子进程
执行，以及快照、preflight、聚合和恢复。六样本 P95 接近最大值，仅用于描述这一轮波动，
不建立产品尾延迟承诺。Analyzer Plugin 不使用此 reader，不需要升级 Plugin 或 Demo pin。

复现命令：

```bash
fvm dart run packages/ccrouter_test/benchmark/generator_file_read_scaling.dart
fvm dart run packages/ccrouter_test/benchmark/generator_file_read_scaling.dart --demo
```

完整 generation suite：`fvm dart test --concurrency=1 packages/ccrouter_test/generator_test`，
545 项通过，1 项可选远端 Analyzer installation smoke 默认跳过。覆盖 Host/package-local、
watch/Pub Hook 协作、输入中途变化、失败恢复、nested example 保护、Portable State 和缓存损坏。
新增 A/B 回归还逐字节比较了生成物、fast-path manifest 和 Build Plan state。

真实 watch 又按并发 / 串行 / 并发三个独立 session 跑编辑矩阵，每个场景每侧 3 个样本。
三轮均恢复源码、清理新增/删除/重命名 fixture，并验证 105 个受管产物逐字节一致，最终
fingerprint 均为 `4d8e60c8e2f1ca75fed7f172a0bb9bff5d5fcb99b6ff1b76db3b9b45751a83bf`。
三轮最后的 `generate demo --no-cache --check` 全部通过。以下是串行中间轮与并发复测轮：

| 编辑场景 | 串行 wall P50 | 并发复测 wall P50 | 串行 aggregation P50 | 并发复测 aggregation P50 |
| --- | ---: | ---: | ---: | ---: |
| 注释 | 2408ms | 1753ms | 794ms | 551ms |
| Widget body | 1953ms | 1592ms | 556ms | 488ms |
| initState | 2104ms | 1580ms | 598ms | 511ms |
| 新增函数 | 1806ms | 1666ms | 658ms | 535ms |
| Route annotation | 2441ms | 1886ms | 917ms | 629ms |
| 新增 Dart 文件 | 1194ms | 1305ms | 509ms | 537ms |
| 删除 Dart 文件 | 1193ms | 1269ms | 489ms | 573ms |
| 重命名 Dart 文件 | 1232ms | 1210ms | 484ms | 520ms |

这些不是交错于同一 Builder session 的纯 I/O 因果实验。Builder 和 debounce 也有波动，不能把
全部 wall 差异归因于读取调度。第一轮并发的文件新增/删除 wall P50 为 1099/1155ms，复测为
1305/1269ms：文件生命周期路径没有稳定的整体提速结论，也不能隐藏复测中比串行更慢的样本。
本轮保留 4-worker 有界调度，以精确内容、失败排空、规模读取收益和全部正确性回归作为依据，
不承诺任何项目或每次操作都更快；资源紧张或真实慢样本使用串行 kill switch 继续对照。

watch benchmark 原有断言还停留在 `buildRunner.formatVersion: 1`；已更新为当前 `2` 并明确要求
`available: true`。该变更只修复基准的协议检查，没有改变生产事件。

```bash
CCROUTER_DISABLE_PARALLEL_FILE_READS=0 fvm dart run packages/ccrouter_test/benchmark/generator_watch_edits.dart --samples=3
CCROUTER_DISABLE_PARALLEL_FILE_READS=1 fvm dart run packages/ccrouter_test/benchmark/generator_watch_edits.dart --samples=3
```

### 10.19 单个 input snapshot 内读取去重：撤回原型（2026-10-13）

结论：当前 Demo 的候选重复很少，真实命令对照未显示可复现净收益。**没有新增生产缓存或默认
优化**，临时原型和实验开关已经撤回，不宣称 watch、Pub Hook 或 Analyzer 提速。

清单按当前 input capture 的组成统计，包含 49 个 resolved runtime Packages、额外的 Path
bootstrap、authored inputs、Generator kernel、external managed artifacts 和 Pub resolution
identity。223 次逻辑读取对应 220 个文件；3 次重复是 `package_graph.json`、
`package_config.json` 与 `pubspec.lock` 解析后再进入原始字节摘要，占约 1.35% 读取次数、
82,716 bytes（约 3.6% 读取字节）。它不是整个命令的系统调用 trace，也不包含必须保持独立的
多次 barrier 或不同 cycle。大型外部分发拓扑可能有 index/Bundle/state alias 重复，当前 Demo
不提供这类收益证据。

临时生产原型仅复用同一次 capture 中的 Pub 解析 bytes 与已读取的 external managed-output
alias bytes，保留存在性检查、逻辑名称、摘要编码和全部独立 input barrier。真实 Demo
按相反顺序轮换原型与重复读取参考，每个场景每侧预热 1 次、采样 10 次，使用正常 CLI
`generate demo --check --profile`，完整路径另加 `--no-cache`。每次命令检查 97 个当前 Demo
受管文件的路径与全部 bytes，44 次命令均成功。只切换本项实验，不关闭已实施的其他优化。

| 真实命令 | 参考 wall P50 / P95 | 原型 wall P50 / P95 | 参考 / 原型内部 P50 |
| --- | ---: | ---: | ---: |
| 无改动 `--check --profile` | 1541 / 1985ms | 1592 / 2222ms | 255.83 / 271.78ms |
| `--no-cache --check --profile` | 3219 / 3782ms | 3263 / 4356ms | 1974.31 / 2012.04ms |

完整路径的 input-fingerprint-capture P50 为 144.06 / 146.77ms；before-aggregation barrier
为 65.85 / 67.61ms，after-aggregation barrier 为 67.57 / 65.04ms。各阶段和子进程都有波动，
不能把本轮所有慢样本因果归于去重，也不能从这组结果推导稳定负优化。能支持的决定是：目前
没有足够收益证据承担更多长期 byte evidence 和失效分支。机器负载与进程启动成本有变化，
不应把本轮绝对 wall 与 10.18 的历史数值直接比较；这里只做本轮交错 A/B。

撤回后保留的 benchmark 使用相同读取清单、4-worker budget、独立 byte oracle；每次 capture
重新创建候选证据，只缓存会被再次消费的路径。每侧预热 2 次、交错采样 12 次，单次
读取/hash（不含目录发现、解析、Builder、Analyzer）P50 为参考 22.96ms、候选 24.13ms，
P95 为 29.70ms、29.24ms，同样没有明确净收益。另验证新增、同大小/mtime 修改、删除、
重命名、缺失路径失败和下一 capture 恢复；这些验证不能证明并发修改期间的全局原子快照。

```bash
fvm dart run packages/ccrouter_test/benchmark/generator_snapshot_read_dedup.dart
```

此命令只运行 benchmark 内的局部研究原型。已撤回的 CLI 原型不再提供 `--demo` 模式或
受支持的运行时开关；不要用无效果的环境变量重测所谓生产 A/B。`ccrouter_test` 仅增加
benchmark 所用的直接 `yaml` dev dependency，解析版本保持现有解析结果，不升级 Analyzer。

最终提交不修改 Generator、watch、Pub Hook、Analyzer 的生产文件。完整
`fvm dart test --concurrency=1 packages/ccrouter_test/generator_test`：545 项通过，1 项可选
远端 Analyzer installation smoke 默认跳过。覆盖入口一致性、watch/Pub Hook、多 Host、文件
生命周期、Portable State、缓存损坏、失败恢复和 planning state 逐字节对照。
最终 `generate demo --no-cache --check` 通过：6 个组件、33 条 Route、11 个生成 Package，
Builder 写入 0 个输出，所有受管生成物保持最新。本轮无需更新 Plugin pin 或重装 Pub Hook。
`fvm dart analyze` 无问题，benchmark 格式检查与 `git diff --check` 通过；无测试遗留源码或产物变更。

### 10.20 流式 SHA-256：撤回生产原型（2026-10-13）

结论：保留研究 benchmark，**不新增生产优化或运行时开关**。分段 hashing 可以避免
`BytesBuilder.takeBytes()` 拼接完整连续数组，但真实 Demo CLI 尚未证明一致的耗时或内存净收益。
这不是语义指纹，不跳过文件读取或 Builder；候选保持所有原有编码与正确性边界。

原始字节编码为：按 logical name 排序，依次拼接 UTF-8 名称、NUL、完整文件 bytes、NUL。
候选将这些片段送入同一个 SHA-256 sink，每次创建新 sink 并完整重新计算。独立 oracle 通过
预分配数组和明确 offset 构造参考编码，不依赖候选的 chunk 逻辑。另验证空 map/空文件、
Unicode 与 NUL、SHA-256 block 边界、插入顺序、输入 bytes 未被修改、同大小/mtime 编辑、
文件新增/删除/重命名、缺失读取失败和下一 capture 恢复。它不证明并发修改期间的原子快照；
生产的多个 input barrier 仍须分别读取当前内容。

测量环境为 macOS arm64、Dart 3.11.5。Demo 文件 workload 包含 155 个源码/配置/生成 Dart
与 metadata 文件、11 个 Package、965,164 bytes，复制为 1x/3x/5x/10x；不声称这些复制是
实际解析的多 Host graph。大文件样本另用 1/8/32MiB 合成内容，不当作真实项目收益。

微基准只计已经读入内存的 hash，不含目录发现、I/O、解析、Analyzer、Builder、完整生成或
进程启动。独立进程测内存，每侧 3 个进程轮换顺序；每个进程预热 3 个 sample、采样 12 个，
每 sample 计 2 次 hash 的平均值。另用 3 个进程内交错两种算法计时，避免把跨进程机器负载
差异全部归因于算法。逐 Package 时间还包含相同的小摘要核对 proof，两侧口径一致。

首次同进程交错计时如下，每侧 36 个有效样本；范围内存在进程和 GC 波动：

| 文件规模 | 全局参考 / 流式 P50 | 全局参考 / 流式 P95 | 逐 Package 参考 / 流式 P50 |
| --- | ---: | ---: | ---: |
| 1x / 155 | 7.08 / 6.75ms | 9.71 / 8.19ms | 7.22 / 6.76ms |
| 3x / 465 | 20.53 / 19.59ms | 26.38 / 25.74ms | 21.48 / 19.48ms |
| 5x / 775 | 31.26 / 30.98ms | 55.95 / 44.21ms | 33.20 / 30.93ms |
| 10x / 1550 | 64.14 / 60.31ms | 76.65 / 83.22ms | 63.20 / 62.01ms |
| 合成 1MiB | 6.70 / 6.36ms | 7.71 / 6.98ms | 6.61 / 6.32ms |
| 合成 8MiB | 53.74 / 53.39ms | 76.31 / 80.60ms | 53.77 / 53.04ms |
| 合成 32MiB | 214.58 / 206.89ms | 255.16 / 279.49ms | 215.13 / 212.13ms |

1x 每次摘要只减少约 0.3–0.5ms，不能直接放大为整条 CLI/watch 提速。10x 逐 Package
P95 为 71.36 / 115.11ms，也没有一致的尾延迟改善。首次独立进程计时的 10x 全局 P50 为
59.14 / 65.47ms，与同进程复测方向不同；不得隐藏这个反例或据此断言因果性的负优化。

首次独立进程峰值 RSS 的 10x 最大值为参考约 623MiB、流式约 226MiB；32MiB 合成单文件
为约 309 / 212MiB。RSS 包含整个 Dart VM/JIT、fixture、全局与逐 Package 多轮 hashing，
不等于单次分配量或 Generator 内存。全局连续拼接 buffer 在 Demo 1x 为 976,897 bytes、
10x 为 9,768,970 bytes，候选去除的是这份临时数组；名称编码、排序、原始 bytes 与 hash
内部 buffer 仍存在。不能将长循环的 RSS 差额外推成真实 CLI 或常驻 watch 的节省。

临时生产原型覆盖既有 Generator input/state 与 watch/Hook 共用的 Package digest，保留
全部读取、独立 barrier、Builder、Validator、快照恢复和原子写入，并暂时纳入 execution
kernel ownership。真实 Demo 用正常 CLI 入口交错运行以下两个场景，每侧预热 1 次、采样
10 次，只切换本项临时开关，不关闭此前优化。每次成功检查 97 个受管产物和 10 份本地
manifest/Build Plan 的完整文件名与 bytes；44 次 `--check` 均成功。

| 真实命令 | 参考 wall P50 / P95 | 流式 wall P50 / P95 | 参考 / 流式内部 P50 | 参考 / 流式峰值 RSS P50 |
| --- | ---: | ---: | ---: | ---: |
| 无改动 `--check --profile` | 868 / 1398ms | 905 / 1417ms | 406.05 / 414.93ms | 165.34 / 170.53MiB |
| `--no-cache --check --profile` | 3093 / 4030ms | 3030 / 8399ms | 2615.48 / 2545.90ms | 214.34 / 208.55MiB |

峰值 RSS 取 macOS `/usr/bin/time -l` 同口径报告，不是多进程同时内存的求和。完整路径
8.399s 流式慢样本同时包含 1.101s dependency preflight、2.852s build_runner execution、
多个变慢的 I/O/快照阶段，不能把全部延迟归因于 hashing。无改动场景和完整参考路径的
耗时与 RSS 方向不同，只能支持“净收益证据不足”，不能宣称必然变慢或 Builder/Analyzer
已加速。这些绝对 wall 也不应直接与前序不同负载的历史测量比较。

保留脚本的默认完整入口复跑中，1x/3x/5x/10x 同进程全局 P50 为参考
5.75/17.39/29.07/57.25ms、流式 5.59/16.83/28.38/56.42ms；改善仅约
0.15/0.56/0.69/0.83ms。该轮全局 P95 为参考 6.33/17.94/30.38/59.20ms、流式
5.83/17.35/30.07/57.72ms，比首轮更稳定。两轮均完整保留摘要对照，方向和幅度的波动
不应被选择性展示；这组局部复测也不能替代真实 CLI 的不一致验收结果。

因此生产原型、独立模块、kernel 边界变更和临时开关已全部撤回。CLI 门槛未通过，没有
继续 watch A/B；不新增无效果的生产环境变量，也不宣称 watch、Pub Hook 或 Analyzer 收益。
保留的 benchmark 使用固定拼接参考和局部流式候选，两条实现均与独立编码 oracle 比较。

```bash
fvm dart run packages/ccrouter_test/benchmark/generator_digest_streaming.dart
fvm dart run packages/ccrouter_test/benchmark/generator_digest_streaming.dart --timing-only
fvm dart run packages/ccrouter_test/benchmark/generator_digest_streaming.dart --verify-only
```

默认入口同时报告独立进程 RSS 与同进程交错时间；`--timing-only` 不启动独立内存进程，
`--verify-only` 只运行 correctness differential。它们不提供已撤回的真实 CLI 原型模式。

撤回后文件读取/原子恢复回归 7 项通过；`fvm dart analyze` 无问题。Demo 普通生成、缓存
`--check` 与最终 `--no-cache --check` 均成功，97 个受管文件仍逐字节一致，权威检查 Builder
写入 0 个输出。最终生产文件无变更，未重复上一项已通过的完整 generation suite；无需
更新 Analyzer Plugin pin、重装 Pub Hook 或修改 Integration Skill 的使用语义。
