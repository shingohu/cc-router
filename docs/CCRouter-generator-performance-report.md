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
   Route/Command/Event component API 已被 `clean` 删除时，先从缓存 metadata 临时恢复这些
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

以下为包含五类能力的最终冷生成和连续两次无变化生成结果：

| 规模 | Route | Service | Command | Event | InitTask | 源文件 | 生成文件 | Validator | 冷 Wall | 无变化 Wall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1× | 31 | 8 | 5 | 3 | 8 | 57 | 151 | 10ms | 17.023s | 0.372-0.407s |
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

`clean` 后的 component API bootstrap 只在对应 authored import 存在且目标文件缺失时启用，
只消费仍由 build_runner 管理的缓存 metadata。它不跳过 build_runner，也不信任旧 metadata
作为最终结果；当前轮构建、解析、Validator 与聚合仍完整执行。bootstrap 或后续生成失败时会
恢复生成前现场。回归用例要求 `clean -> generate -> --no-cache --check` 的第二轮明确报告
`wrote 0 outputs`，防止 Asset Graph 需要额外一轮才能收敛。

## 6. 未采用的优化

### 6.1 合并 metadata Builder

曾将 6 个 metadata Builder 组合成一个 phase，并保持输出逐字节一致。实测冷生成反而慢约
0.8-1.5 秒，30× 从约 21.65 秒上升到 23.14 秒。原因是六套能力扫描在一个 BuildStep 内串行
执行，失去了 build_runner 原有调度优势。该实验已完整回退。

### 6.2 自定义 Package dirty set

当前 build_runner 已负责源码级增量，metadata cache 已按 Package 指纹复用。CLI 剩余聚合在
30× 约 0.8 秒。若跳过未变 Package 的输出校验，会漏掉“另一个 Package 源码变化，同时本
Package 生成物被篡改”的情况；正确实现需要 per-Package input/output manifest 和 reverse
dependency closure。现阶段收益不足以覆盖复杂度和错误风险，暂不实施。

## 7. 后续触发条件

只有真实生产样本满足以下任一条件时，再进入下一轮架构优化：

- 30× 级别的单 Package 增量 P95 持续超过 6 秒；
- 多 Package 项目的 Host 聚合稳定超过总时延 20%；
- build_runner 冷阶段稳定超过 30 秒且 AOT 编译不是主要波动来源；
- 内存/RSS 显示当前逐字节摘要造成不可接受峰值。

届时优先设计 per-Package manifest 与 reverse dependency closure；不得跳过 Validator、依赖
watch/daemon 保证正确，或用 mtime/size 替代内容摘要。
