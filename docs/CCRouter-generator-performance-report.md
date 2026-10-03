# CCRouter 生成器性能优化与对比报告

> 文档状态：2026-09-28 性能快照；2026-10-03 补充 Build Plan P2-P5，其中包含 3x/5x/10x
> 多组件个人/团队拓扑样本。数值不自动代表后续提交或其他机器。

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
