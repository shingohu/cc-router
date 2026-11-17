# build_runner 2.15.1 增量构建空值异常排查

日期：2026-11-04。Owner：项目构建工具链维护者；缺陷实现归 dart-lang/build。
代码基线：`cde22c402`。SDK：根 `.fvmrc` 的 `ohos/oh-3.41.9-release`，Dart 3.11.5。
本轮仅诊断与记录，没有修改项目依赖、业务代码、共享 Pub 缓存或 main，也没有清缓存。
不涉及 Android/iOS/OHOS 原生产物、签名或设备操作。

## 结论

这是 `build_runner 2.15.1` 的增量输入分类缺陷。保留旧 `asset_graph.json` 后，
从 Git 合入“新增输入文件 + 对应生成文件”，新增生成文件不在旧图中，会被当作普通 source。
构建步骤同时将它注册为 output，形成 source/output 双重归属。
`BuildState.contentOf` 优先读取 source 内容；未读取过该 source 时返回 null，随后
`BuildSeries._writeBuildOutput` 第 333 行使用 `!` 崩溃。

与商城 UI、业务 Dart 语法及 Flutter-OHOS 原生编译无关；不需要依赖 CCRouter 或 FlutterGen
也能复现。上游已报告同一输入分类问题：[dart-lang/build #5079](https://github.com/dart-lang/build/issues/5079)。
上游案例表现为生成步骤相互等待，本项目表现为空值断言；两者不能混称为相同堆栈。

## 项目现场

原 worktree 在最新合并代码下执行以下正式检查仍复现，退出码 1，Builder 子进程为 255：

```sh
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate app --no-cache --check --profile
```

组件依赖 preflight 为 0 个问题，Builder 已完成各阶段计算，在最终写回时失败。
`--no-cache` 禁用的是 CCRouter 的复用判断，不代表删除 build_runner 自己的增量状态。
重新 Pub 解析没有改变 lockfile，也没有消除异常。
干净 worktree 对同一合并代码生成成功，并通过 `--no-cache --check`。

旧图完全未知的已提交 CCRouter 生成 Dart 文件共 22 个。临时诊断副本捕获到其中两个文件
同时满足 `isSource=true`、`isUnreadSource=true`、`isActualOutput=true`；旧图中两者既不是
source，也不是 output，且不是 post-process 输出：

| 空值输出 | 所属原始输入 |
| --- | --- |
| `liberlive_contracts/lib/src/ccrouter_generated/contract/profile/sheet_editor.service.contract.g.dart` | `liberlive_contracts/lib/src/profile/sheet_editor.dart` |
| `liberlive_contracts/lib/src/ccrouter_generated/contract/works/content_changes.service.contract.g.dart` | `liberlive_contracts/lib/src/works/content_changes.dart` |

两者均为 phase 2 的正常 Service Contract 输出，`cleanBuild=false`。
“22 个未知文件”不等于“22 个空值输出”；其它文件的内容是否已被读取也影响这一分支。

诊断包只在 `/tmp` 中复制并加观测，没有改共享安装。重新编译诊断程序会改变
`buildPlanDigest.compileDigest` 并触发全量构建，因此在隔离副本中只对齐该字段到诊断程序值，
保留旧图其余字段不变，再捕获增量现场。原 worktree 的未修改正式命令和下述 stock 最小工程
独立复现，结论不依赖这个诊断调整。

## build_runner 源码链路

以下位置均以 Pub 的 `build_runner 2.15.1` 源码为准：

1. `lib/src/build_plan/build_plan.dart:89`：全量路径计算 declared outputs，随后
   `inputSources.removeAll(declaredOutputs)`，排除已存在的生成文件。
2. 同文件 `:326`：增量路径对 `!oldExisted && exists` 的文件无条件加入
   `buildInputs.sources`，重算输出声明后缺少相同的排除步骤。
3. `lib/src/build/build_state/build_state.dart:216`：`contentOf` 先检查 `isSource`，
   在 source 内容尚未读取时直接返回 null，不再查询已生成的 output 内容。
4. `lib/src/build/build_series.dart:329`：写回输出时对上述结果使用非空断言，`333` 行崩溃。

失败发生在 asset graph 成功写回前，旧图仍保留。因此不改变触发条件的反复重跑会再次失败。

## 不含 CCRouter 的最小复现

独立临时工程只使用 stock `build_runner 2.15.1` 和 `build 4.0.7`，没有 Flutter、
CCRouter、FlutterGen 或 post-process builder。项目依赖声明如下：

```yaml
name: incremental_probe_fixture
version: 1.0.0
environment:
  sdk: ^3.11.5
dependencies:
  build: 4.0.7
dev_dependencies:
  build_runner: 2.15.1
```

`build.yaml`：

```yaml
builders:
  emit:
    import: "package:incremental_probe_fixture/builder.dart"
    builder_factories: ["createBuilder"]
    build_extensions: {".seed": [".result"]}
    auto_apply: root_package
    build_to: source
```

`lib/builder.dart`：

```dart
import 'package:build/build.dart';

Builder createBuilder(BuilderOptions options) => _Emit();

class _Emit implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {'.seed': ['.result']};

  @override
  Future<void> build(BuildStep step) async {
    final value = await step.readAsString(step.inputId);
    await step.writeAsString(
      step.inputId.changeExtension('.result'),
      'generated:$value',
    );
  }
}
```

在独立临时目录使用相同 FVM SDK 解析这些依赖后，按序执行：

```sh
printf A > lib/a.seed
fvm dart run build_runner build
printf B > lib/b.seed
printf generated:B > lib/b.result
fvm dart run build_runner build
```

第二个 `.result` 已经是正确内容，仍然触发缺陷；不是错误生成内容导致。
本轮为避免重新解析其它版本，实际复现复用了项目已安装的 stock 包和版本锁定信息，
通过 CLI launcher 指定独立工程目录；构建状态和文件均在临时目录，不修改项目解算。

| 场景 | 观察结果 |
| --- | --- |
| 首次仅有 a.seed | 成功，退出 0 |
| 在其增量图下加入 b.seed 与预生成 b.result | 同一第 333 行空值异常，退出 255 |
| 同样增量图只加入 b.seed，不预放 b.result | 成功，退出 0 |
| 全部文件在首次全量构建前已存在 | 成功，退出 0 |

## 上游版本与可选处理

[2.16.1 变更记录](https://pub.dev/packages/build_runner/versions/2.16.1/changelog)
明确修复“增量构建将已有冲突输出当作 source”的问题，并关联 #5079。
查询时最新版本为 2.17.1；它的发布归档已按 Pub API 的 SHA-256 校验，源码仍包含相应处理。
这属于上游源码/发布记录核对，不代表本项目已经升级或通过新版本的完整门禁。

| 方案 | 收益 | 成本与边界 |
| --- | --- | --- |
| 临时使用干净 worktree 重生并检查 | 本轮已验证可用，不改变版本、不清理共享缓存 | 原 worktree 的触发条件仍在，不算根治 |
| 协调 CCRouter 工具链后升级到含修复版本 | 使用上游维护的解决方案，推荐长期路径 | 需要解决 analyzer/build 约束并回归生成、缓存复用、FlutterGen 与 Hook |
| 给 2.15.1 做受控补丁回移 | 可保持当前 analyzer 大版本 | 需要明确 fork Owner、来源/许可证/台账、维护与移除条件；需单独评估后采用 |

`analyzer 13.3.0` 的 Pub SDK 约束是 `^3.11.0`，并不直接依赖 Flutter。
项目 FVM 当前实测 Flutter-OHOS `3.41.10-ohos-1.0.0`，自带 Dart 3.11.5，已经满足这个 SDK 条件；
不需要为了 analyzer 13.3.0 升级 Flutter。实际冲突是下述包版本约束。

当前 CCRouter Generator（Git `f5ee57721dc3a7dbe87d06b784e97d97e0b82570`）依赖
`analyzer ^10.0.0`，项目实际解析为 10.0.1；`build_runner 2.16.1` 要求
`analyzer >=13.3.0 <15.0.0` 和 `build ^4.0.9`，不能只升级 build_runner。
`2.17.1` 进一步要求 `build >=5.0.0 <5.1.0`、`build_config ^1.4.0`，与当前
CCRouter/FlutterGen 的 `build ^4.0.0` 不兼容，不推荐直接跳到最新版。

不建议通过 `content == null` 时跳过输出来掩盖失败，也不修改共享 Pub 缓存或增加
生产 `dependency_overrides`。若后续决定升级或回移修复，须验证本最小复现、跨 Git 状态增量生成、
全量/增量产物一致性、FlutterGen 产物、CCRouter `--no-cache --check` 和项目相关门禁。

## 本机证据

以下是本机临时材料，不承诺跨机器可访问，不提交约 24MB 的构建缓存：

- `/tmp/build-runner-diagnosis-current.log`：原 worktree 正式命令复现及 profile。
- `/tmp/liberlive-build-runner-evidence-20261104/capture.json`：原 asset graph 指纹及采集时间。
- `/tmp/liberlive-build-runner-evidence-20261104/build/`：修改前构建状态快照。
- `/tmp/liberlive-build-runner-evidence-20261104/captured-missing-outputs.json`：两个输出的归属观测。
- `/tmp/build-runner-probe-incremental.log`：临时观测包增量失败日志。
- `/tmp/liberlive-build-runner-evidence-20261104/minimal-stock/`：stock 最小工程及失败/全量对照日志。
- `/tmp/liberlive-build-runner-evidence-20261104/minimal-source-only/`：只新增输入的成功对照。

未改变 Pub 依赖或 native 产物，本轮无需平台构建；上游已修复版本在本项目中的实际兼容性尚未验收。
