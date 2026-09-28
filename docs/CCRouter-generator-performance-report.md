# CCRouter 生成器性能优化与对比报告

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
