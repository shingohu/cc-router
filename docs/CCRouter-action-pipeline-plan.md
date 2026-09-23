# CCRouter Action Pipeline 候选计划

## 1. 文档状态

- 状态：2.0 候选，等待真实生产场景触发
- 当前决策：1.x 不提供 Action Pipeline
- 不包含：普通一对一业务操作、事实广播、远程代码执行和任意方法调用

本文记录未来 Action Pipeline 的使用边界、生产触发条件和候选实施顺序，不代表已经承诺
公开 API。当前一对一操作由 `CCCommand<R>` 承担，事后通知由 `CCEvent` 承担。

## 2. 调研结论

- ARouter 以 Route、Service 和 Interceptor 解决组件协作，没有通用 Action Bus。
- Flutter Modular 聚焦 Route、DI 和 Scope，没有独立 Action 概念。
- MediatR 的稳定传输边界是 Request/Response 与 Notification，Command/Query 更多是业务语义。
- TheRouter 的 ActionManager 面向远程配置、H5 和动态页面触发的预埋本地操作，支持多个
 处理器、优先级和中断执行；它不是普通的一对一 Command。

因此 Action Pipeline 不是组件化框架的基础必选能力。只有应用确实需要从动态来源选择已编译
能力，并需要多个组件竞争或协作时，它才比 Command/Event 更合适。

参考：

- [ARouter](https://github.com/alibaba/ARouter)
- [Flutter Modular](https://github.com/Flutterando/modular)
- [MediatR](https://github.com/LuckyPennySoftware/MediatR)
- [TheRouter ActionManager](https://github.com/HuolalaTech/hll-wp-therouter-android/wiki/ActionManager)

## 3. 真实使用场景

### 3.1 多组件弹窗仲裁

首页的隐私、强制升级、营销和满意度组件共同响应一个展示机会，按确定优先级检查；第一个
成功展示的处理器停止后续执行。

### 3.2 动态页面调用本地白名单能力

H5、Server-Driven UI 或远程配置只提供稳定 Action ID 和经过 Schema 校验的数据，由宿主
映射成已编译能力，例如打开客服、扫码、分享或上传诊断信息。

### 3.3 运营策略选择本地候选实现

多个已安装组件可以声明同一操作的候选处理器，Runtime 根据静态优先级、当前环境和处理
结果决定继续或停止，并输出可追溯报告。

以下场景不得使用 Action Pipeline：

- 一个明确 Handler 的业务操作：使用 `CCCommand<R>`。
- 通知多个组件一个事实已经发生：使用 `CCEvent`。
- 可重复调用或读取状态的长期能力：使用 Service。
- 应用启动依赖编排：使用初始化任务。
- 远程下发类名、方法名、脚本或任意参数 Map：框架不支持。

## 4. 生产触发条件

只有生产工程出现以下任一证据，才重新立项评审：

1. 至少一个动态来源需要触发本地白名单能力，并且无法用静态 Command 安全表达。
2. 同一操作存在至少三个跨组件候选处理器，确实需要优先级和短路。
3. 至少两个生产 Action ID 重复实现了相同的来源校验、仲裁和诊断代码。
4. 已发生由于分散弹窗、H5 Bridge 或远程操作入口造成的顺序、安全或追踪缺陷。

Demo、测试夹具和为验证方案人为创建的 Handler 不计入阈值。达到阈值只启动需求与安全评审，
不代表直接冻结 Action 注解、metadata 或 Runtime API。

## 5. 候选语义

未来实施必须同时定义以下语义，不能只增加多 Handler 分发：

- Action ID、Handler ID 和来源 ID 使用稳定、有界标识。
- Handler 按优先级和稳定 ID 确定性串行执行。
- 每个 Handler 返回 `continue`、`handledAndContinue` 或 `handledAndStop` 等显式决策。
- 报告区分未找到、拒绝、已处理、短路、失败、取消和超时。
- 动态来源先经过 Host-owned ingress mapper，业务 Handler 不接收原始 URL、JSON 或任意 Map。
- 白名单可以限制来源、Action ID、参数 Codec、登录态、权限和环境。
- Handler 异常、超时和取消策略必须显式；禁止同步重入同一 Pipeline。
- Trace 只记录稳定 ID、来源类别、处理状态和耗时，不记录完整 URI、Token 或业务参数。
- 静态组件装配决定可用 Handler；1.x 不因此恢复动态组件激活/停用。

## 6. 候选实施顺序

1. 收集生产调用样本、来源和失败记录，确认 Command/Event 无法满足。
2. 冻结中立契约、执行报告、来源策略和威胁模型。
3. 在 Pure Dart Runtime 实现确定性 Pipeline、取消、超时和有界诊断。
4. 增加 Host ingress mapper，将 H5/远程输入转换为类型安全 Action。
5. 在 `ccrouter_test` 提供 Handler、来源和短路测试工具。
6. 先用手写注册验证真实组件；只有重复注册和契约漂移达到生产阈值后再评估生成器。
7. 补充安全、并发、性能、生命周期、降级和内存回归，再决定是否进入公开 API。

## 7. 验收门槛

- 不允许动态来源指定 Dart 类型、方法名或可执行代码。
- 相同输入和已安装组件集合必须产生确定的 Handler 顺序和报告。
- 未识别、非法或未授权 Action 安全失败，不能降级为 Route、Command 或反射调用。
- 一个 Handler 的失败不能被误报为成功；是否继续必须由公开策略确定。
- Pipeline、Ingress、Trace 和测试 API 必须保持分层，普通业务不能绕过来源策略。
- 在真实生产需求出现前，该能力保持文档候选，不进入 1.x 待办。
