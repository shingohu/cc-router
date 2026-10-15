# 类型化 UI Fragment 实施验收与核心价值回归

日期：2026-10-15。实施分支：`codex/typed-ui-fragment`，基线 `c8812f8`。
本文记录本次增量验证，不替代正式发布门禁或既有全框架审计。

## 1. 问题、取舍与实现

A 组件需要嵌入 B 组件的一块局部 UI。直接 import B 实现会破坏组件隔离；通过 Service
返回 Widget 会污染 Pure Dart 契约、模糊资源所有权；使用 Route Mount 又会引入不需要的导航语义。

| 方案 | 收益 | 代价与结论 |
| --- | --- | --- |
| 应用层直接 Widget 组合 | 无框架成本 | 缺少跨组件契约、依赖与兼容校验，适用于同一组件内部 |
| Service 返回 Widget | 可以复用现有注册 | 破坏 Service 边界，拒绝此路径 |
| 通用 Core UI 注册与动态 Slot | 可承载多实现 | 扩大 Core、生命周期和业务 API，当前不采用 |
| 可选 UI Package + 生成式 Assembly wrapper | 类型安全、静态校验、独立回退 | 新增生成链和 Host binding，采用此路径 |

实现链：Pure Dart UI Contract → 消费组件自己的生成 Client → Host 静态 Renderer catalog →
Flutter State。`ccrouter_ui` 为可选 Flutter 包，Core 不依赖它；旧五类 Contract enum 不变。
`CCComponent.uiDependencies` 默认空；普通 Host 无新增必填参数。
仅安装带 Renderer 的组件而没有 UI 消费声明时，Host 不启用 UI catalog，也不新增直接依赖。

v1 只接受不可变 final DTO、标量、普通业务 enum 和无环嵌套 DTO；Flutter/dart:ui 的 enum 同样
拒绝，避免仅校验 Widget/Context 而漏过平台类型。集合、sealed Action、动态 Slot、
多贡献者和原生平台 Fragment 不在本次范围。完整接入步骤见
[UI Fragment 指南](../skills/ccrouter-integration-development/references/ui-fragments.md)。

## 2. 生命周期、失败与回退

- A 拥有布局、Props、Key、active 和 Action 处理；B 的 State 拥有请求、Timer、Controller。
- Fragment 不创建 RouteEntry 或 Scope。相同 Key 保留 State，换 Key 或卸载释放 State；
  `active: false` 阻断 Action，暂停工作仍需 B 显式实现，不等同于曝光判断。
- 装配拒绝缺失/重复 Renderer、Owner 或依赖错误、版本和 fingerprint 不匹配。
  Props 字段、枚举成员和构造器有效默认值进入 fingerprint；公共 barrel 需要显式暴露相关类型。
- 初始化失败逆序回滚 binding；shutdown 先使 UI generation 失效，再完成 Runtime 清理。
  一个 detach 异常不阻断其他资源释放；旧 Action 不会进入新 Runtime。
- 重新初始化需要 Host 显式重挂 UI 子树；旧 State 下次 build 会报 generation mismatch。
  当前 UI catalog 仅对应 process-default Runtime，不提供 TestHost Zone overlay 隔离。
- catalog 仅保留静态工厂与 schema，不存 Widget、Context、实例 State 或消费回调。
  generation detach 清空工厂引用；诊断最多 128 条，仅保留声明身份与错误码，不含 Props/Action。
- 回退时先迁走 UI 消费点、Renderer 和 `uiDependencies`，重新生成，再移除可选 UI 包依赖。
  未使用 UI 的组件保留原调用形式；不需要迁移原 Route/Service/Command/Event/InitTask API。

资源验证覆盖 State dispose、Key 重建、多实例、KeepAlive、GlobalKey reparent、旧回调失效及
shutdown/reinitialize。Demo 的 Timer 与 TextEditingController 均由 State 释放。
这证明已测试路径的显式清理行为，不等同于长期生产 Heap/RSS 无增长结论。

## 3. 核心价值回归

| # | 核心价值 | 本次证据及边界 |
| --- | --- | --- |
| 1 | 智能 | 注解生成 schema、消费 Client、Renderer glue 与 Host 装配；不扫描业务函数体推断依赖 |
| 2 | 简单易用 | A 仅使用自身 Client 与 contracts，Host 保留原 initialize 入口；高级生命周期规则显式说明 |
| 3 | 功能强大 | 支持跨组件摘要/推荐 UI、Props 更新、typed Action、多实例与局部错误重试 |
| 4 | 可扩展性 | UI Assembly wrapper 隔离 Flutter 工厂，通用 Host lifecycle binding 不耦合 UI |
| 5 | 可测试 | 生成器、框架 Widget/Host、真实 Demo 三层测试；不声称支持 Zone overlay UI Host |
| 6 | 最小公开 API | business、generated、Host 三个 barrel 分层；无业务 registry lookup 或 Runtime getter |
| 7 | 编译器校验与类型安全 | Pure Dart DTO/enum、类型对校验、public barrel、版本和 shape 三层验证；required Owner edge 与 uiDependencies 双重声明 |
| 8 | 非侵入式 | 普通 Widget/State 无强制基类，不缓存 Context；A 不 import B 实现；Renderer-only 旧 Host 不新增 UI 依赖 |
| 9 | 可降级回退 | required 装配错误不静默降级，业务 loading/retry 自管；可移除 UI 消费声明并重新生成，旧能力调用与 Service 限制不变 |
| 10 | 明确生命周期 | Flutter State 拥有实例资源，Host binding 拥有 catalog generation，无隐式 Route Scope |
| 11 | 可观测可诊断可溯源 | 有界 payload-free 生命周期诊断；UI 专属 find/DevTools/IDE 诊断暂未实现 |
| 12 | 并发安全 | 初始化重入 gate、失败逆序回滚、旧 generation Action 丢弃；请求竞态由 B State 自管 |
| 13 | 性能和稳定 | 无反射或每帧全局注册，诊断有界，既有生成缓存/无缓存门禁；没有未经测量的帧耗时承诺 |

## 4. 验证记录

以下结果在本次 worktree 执行；生成器全量在冻结源码后完整重跑，退出码为 0。

| 检查 | 结果 |
| --- | --- |
| `fvm flutter test packages/ccrouter_test/test` | 436 项通过（含 UI/Host lifecycle 回归） |
| `cd demo && fvm flutter test` | 48 项通过（含 2 项 UI Demo 场景） |
| `fvm dart test --concurrency=1 packages/ccrouter_test/generator_test` | 完整一轮 571 项通过、1 项远程 Analyzer 安装 smoke 按配置跳过，退出码 0（28 分 50 秒） |
| UI generator 专项 | 18 项通过（含 Flutter/dart:ui enum 拒绝） |
| Workspace validator 专项 | 55 项通过 |
| `fvm dart analyze`（根 Workspace） | 无问题 |
| 既有 Contract shape 比较 | 基线 47 条 fingerprint 无改变或缺失 |
| 旧稳定 `.api.g.dart` | 没有差异；新 UI Client 使用独立入口 |
| `portable prepare demo` / `portable publish demo` | 生成成功，9 个 Package 的 Portable State 可用；不执行外部发布 |
| `generate demo --check` / `generate demo --no-cache --check` | 均通过；6 个组件、34 条 Route、12 个生成 Package |
| `cd demo && CCROUTER_PUB_HOOK_DISABLE=1 fvm flutter build macos --debug --no-pub` | 构建成功；第三方插件弃用和既有脚本阶段警告未阻断构建 |
| `cd demo && CCROUTER_PUB_HOOK_DISABLE=1 fvm flutter build web --debug --no-pub` | 构建成功（含 Flutter Wasm dry run）；未执行浏览器/设备矩阵 |

生成器测试中的三个 Workspace root helper 原先只接受 `.git` 目录，本次修正为同时识别
worktree 的 `.git` 文件，不改变生产 Host 检测逻辑。首次全量生成器测试曾因未知 schema 接受范围、
上述 helper，以及测试期间修改生成器源码造成的 tool fingerprint 变化失败；修复后以冻结源码的
完整重跑结果为最终依据，不能把中途通过数量视为全量成功。
后续多 Host watch 回归还发现 Renderer-only 组件会迫使未消费 UI 的旧 Host 新增依赖，
已将装配触发条件收窄为实际 UI required consumer，并新增旧 example Host 的无缓存生成回归；
这项修复不通过给旧 Host 补依赖来掩盖影响。
UI framework barrel 也纳入已有依赖预检的精确已知库集合，避免新增 import 令原 Service/Command
缺失 Owner 诊断退回 Builder；预检全套 12 项通过，包括两项新增的 namespace 回归。

一次完整执行曾出现 566 通过、3 失败、1 跳过：预检问题按上文修复；心跳退出超时来自
中断测试遗留的两份手动 lease，确认所属进程已退出后移至临时目录保留，定向复跑通过；
clean 后 UI Client barrel 重建会令 Analyzer 额外分析一次新恢复的 export edge，出现 3 个 `same`
输出但实际生成物变化为零。clean 回归现同时要求首轮 `output-delta.files == 0`、
下一轮继续无字节变化且 Builder `wrote 0 outputs`，定向复跑通过。普通缓存 fast path 未因此
增加 Builder 调用。

前一轮完整执行记录为 568 通过、3 失败、1 跳过（共 572 个用例），三个失败均已完成
整改并通过最终完整重跑：UI 指纹用例连续进行四次 Analyzer 构建，在机器负载下触发默认 30 秒上限，
现为 UI generator 测试设置 2 分钟上限，18 项完整专项通过，全部语义断言保留；
另外两项直接 Dart 启动的 Post-Pub 夹具没有真实 Flutter wrapper 提供的 SDK 上下文，
现由夹具从配对 Flutter executable 推导 `FLUTTER_ROOT`，在没有额外 shell 环境设置的普通
`fvm dart test` 下两项均通过。生产 Hook 未因这两项夹具修正而改变。
最终完整命令在 28 分 50 秒结束，结果为 `571 passed / 1 skipped`、`All tests passed!`，
退出码 0。跳过项需要显式 `CCROUTER_ANALYZER_NETWORK_SMOKE=1` 及远程 Git/Pub。

## 5. Demo 验收与剩余范围

从 Demo 首页「展示」进入 UI Fragment 页面。实际消费组件是 navigation_lab，Owner 是 order，
公共契约位于 order_contracts。页面包含两个独立订单摘要与推荐列表；可以更新 Props、切换保活页、
模拟账号 Key 更换、触发业务错误/重试和观察 Action。A 仅依赖 contracts 与自身 Client。

自动化 Demo 测试验证实际生成 Host 装配、实例独立、active、Props、Key 和重试流程。
macOS 桌面实测从首页「展示」进入，确认两个摘要实例分离、Tab 切换保留输入、Props 更新保留输入、
模拟账号 Key 更换清空输入，以及推荐 Action 显示「A 收到推荐选择」。
本次不宣称完成 Android/iOS/OHOS/Web 真机、长期内存压力或 UI 专属 Analyzer Plugin 验收；
未改插件生产代码，不更新 Demo 插件 pin。UI 启用 Package index schema 3 需要配套新生成器，
旧工具应显式拒绝；无 UI Package 保留 schema 2。
