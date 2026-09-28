# CCRouter 正式发布前能力设计与实施计划

## 1. 文档定位

本文把正式发布前的七项工作放到同一条可验收路线中，评估它们的真实收益、实现边界、
前置条件和回归要求。本文是实施计划，不代表七项能力都应立即进入公开 API。

当前基线为 1.x 维护阶段：已有能力优先做兼容性、性能、稳定性和生成物正确性维护；
只有能改善开发效率、问题定位或发布可信度的能力才进入本计划。任何新增公开 API 都必须
先通过本计划的边界评审，不能因为其它框架提供了类似按钮就直接加入。

## 2. 总体结论与优先级

| 项目 | 价值 | 可实现性 | 推荐阶段 | 结论 |
| --- | --- | --- | --- | --- |
| 官方 Flutter/Dart DevTools Extension | 高，降低排障和依赖图理解成本 | 中高，需要独立 Extension Package 和协议版本隔离 | P1 | 值得做，先只读，再逐步增强 |
| Catalog 与 Runtime 快照联动 | 高，是 Extension 的数据基础 | 高，可复用现有 Catalog/快照 | P0 | 先做稳定快照协议 |
| 路由到源码图形化跳转 | 中高，缩短定位时间 | 高，已有 source location 和 `ccrouter find` | P1 | 低风险，优先实现 |
| 组件依赖图高级交互 | 中高，帮助发现依赖方向和缺失 Owner | 高 | P1 | 只读筛选、聚焦、反向依赖即可 |
| Service/Command/Event/InitTask 调用链图 | 高，解决跨组件回溯问题 | 中，需要统一 Trace 边模型 | P1 | 先做单次 Trace 链，不承诺全局历史调用图 |
| Analyzer Demo bootstrap 使用 Git `main` | 中，验证未发布插件修复可被 Demo 使用 | 高，当前已具备 | P0 收口 | 保留固定 Git commit，增加可验证状态和 Hosted 切换说明 |
| 全局 Widget 自动识别 | 中，接入成本低但误报/隐私/性能风险高 | 中低，Flutter Widget 树无法可靠表达业务语义 | 观察项 | 不作为默认能力，不做基于文本/随机 Key 的全局猜测 |
| 黑名单 | 中高，能控制自动采集边界 | 高，但必须建立稳定 Target/Scope 语义 | P1 | 只做显式规则，不允许绕过 Consent |
| 通用节流 | 高，控制高频滚动/曝光压力 | 高 | P0 | 统一放到 Dispatcher/Target 层，不能由供应商各自实现 |
| 完整平台兼容矩阵 | 高，减少平台行为误判 | 高，主要是测试和能力声明 | P0 | 建立矩阵和最小回归集 |
| Firebase Adapter | 中高，满足常见落地 | 高，独立可选包 | P1 | 值得做，Core 不依赖 Firebase |
| 性能、队列压力、RSS/Heap 基准 | 高，支撑稳定性承诺 | 高 | P0 | 必须先建基线再优化 |
| Consent deny/grant/revoke 与 Foreign Popup 断言 | 高，验证隐私和归因边界 | 高 | P0 | Demo 必须覆盖并自动断言 |
| 高级 Service/Command/Event/InitTask 脚手架 | 中，减少模板代码 | 高 | P1 | 先生成声明骨架，不生成业务闭包或万能配置 |
| Contract 版本兼容 | 高，正式发布的必要门槛 | 中高，需要生成器、Index 和 CI 协同 | P0/P1 | 先设计协议，再实现最小校验闭环 |
| 长时间 Runtime、多平台回归 | 高，发现释放和平台差异 | 中高，需要设备/CI 资源 | P0 | 作为发布门禁，不扩大公开 API |

推荐落地顺序：

1. 先冻结 Contract 兼容协议、快照协议和性能指标；
2. 完成 Analyzer 固定 Git ref/Hosted fallback 验证和 Analytics Consent/Foreign Popup 回归；
3. 建立自动埋点的节流、黑名单、平台矩阵和基准；
4. 扩展 Catalog/Runtime 快照协议，随后开发官方 DevTools Extension；
5. 增加高级脚手架；
6. 做长时间 Runtime、RSS/Heap 和多平台发布前回归；
7. 所有门禁通过后，才评估 Hosted 发布和 1.0 标签。

## 3. 共同架构边界

### 3.1 数据来源分层

```text
生成器 metadata / Package Catalog  -> 静态拓扑、源码位置、Contract/Owner
Runtime immutable snapshot          -> 当前组件、Route Entry、Task、Trace、Failure
Trace edge                         -> 一次导航或一次能力调用的因果链
DevTools Extension                  -> 只读查询、筛选、图形化和源码跳转
应用 Analytics Sink                 -> 产品分析，不作为 DevTools 数据源
```

Catalog 不能伪造 Runtime 当前状态，Runtime 也不负责扫描源码。Extension 展示“静态声明”和
“当前运行”时必须标注数据来源和时间点，不能把静态路由当成已打开页面，也不能把一次 Trace
推断成完整历史调用图。

### 3.2 公开边界

- DevTools 只读，不允许导航、Pop、重试、销毁 Scope、激活组件或修改 Adapter。
- 自动埋点默认关闭；没有稳定业务 Target 时不生成业务点击事件。
- Consent 过滤在进入队列前执行，撤销时清理待发送事件；已经进入外部 Sink 的事件不能撤回。
- Firebase、ThinkingData、OpenTelemetry 等均为独立 Adapter，Core 不引入供应商依赖。
- 生成器只生成确定性声明、注册桥和 metadata；不生成业务逻辑、网络请求、匿名随机身份或
  任意 `Map<String, dynamic>` Contract。
- 长期回归使用快照、摘要和指标，不保留完整 URI、Query、Extra、Widget、Token 或业务返回值。

## 4. Contract 版本兼容设计

### 4.1 需要区分的四种版本

| 版本 | 所属 | 作用 | 能否替代 Contract 版本 |
| --- | --- | --- | --- |
| Package SemVer | Pub Package | 发布、依赖解析和升级 | 不能 |
| Component version | `CCComponent` | 组件实现身份和诊断 | 不能 |
| Metadata schema | 生成文件 | 工具读写格式演进 | 不能 |
| Contract SemVer | Route/Service/Command/Event/InitTask | 跨 Package API 兼容承诺 | 不能省略 |

当前 `ccrouter_*` 仍是开发期 `0.1.0`，现有 metadata schema 版本和 Package Index 版本也
只服务生成器。正式发布前应把 Contract 版本独立记录到生成 metadata 和 Package Index，
不使用 Component version 猜测兼容性。

### 4.2 Contract 身份

Contract 身份由以下字段组成：

```text
kind       route | service | command | event | init_task
id         全局稳定 ID
owner      CCComponentId
version    SemVer 2.0
fingerprint 规范化公共形状摘要
```

同一个 `id` 不允许在同一 Host 同时安装两个 Owner。需要并行迁移的破坏性版本使用新的
Contract ID（例如 `orders.summary.v2`），而不是让 Runtime 在同一个 ID 下猜测两个形状。

### 4.3 规范化 fingerprint

生成器根据 Analyzer 解析结果生成稳定的 `shapeFingerprint`。指纹包含公共行为形状，不包含
源码路径、注释、实现类名和生成时间。

- Route：Pattern 类型和值、Path/Query 参数名称、类型、可空性、默认值、Extra 类型、结果类型、
  Codec 版本、Presentation/Placement 语义；源码位置和 description 不计入。
- Service：方法、getter/setter、参数名称和类型、可空性、返回类型、受限泛型边界；实现类名和
  Provider 构造方式不计入。
- Command：Command 类型、字段、可空性、结果类型和 Codec；Handler 实现不计入。
- Event：Payload 类型、字段、可空性和稳定 Event ID；Subscriber 数量和 Subscriber 实现不计入。
- InitTask：Task ID、Owner、Contract 依赖、Gate 和失败传播语义；Handler 函数位置不计入。

指纹的用途是发现“版本号忘记升级”或“错误地标记为 patch”，不是安全签名。发布系统仍应
使用可信 Package 来源和 lockfile，Runtime 不把 fingerprint 当作权限凭证。

### 4.4 版本变更规则

| 变更 | 版本 | 默认结果 |
| --- | --- | --- |
| 只改说明、源码位置、诊断标签，公共形状不变 | patch | 允许 |
| Codec 修复但输入输出和错误边界完全不变 | patch | 允许，指纹必须不变 |
| 新增可选 Route alias/可选 Query，且旧 Intent 和旧 URI 仍有效 | minor | 需生成器证明兼容 |
| 新增 Service 方法、改变 Command/Event/Task 形状、删除字段、改结果类型 | major | 拒绝混装；建议新 ID 并行迁移 |
| 改变 Route 主 Pattern、参数语义、Presentation/Placement 或 Deep Link 策略 | major | 拒绝静默升级 |
| 改变 Owner、稳定 ID 或 wire name | major/新 ID | 必须显式迁移 |

`0.x` 阶段不提供跨 Package 兼容承诺：默认按精确版本和精确指纹消费。进入 `1.0.0` 后，
才启用上表的 SemVer 规则。这样可以避免在尚未稳定时把 `0.1.1` 误解为长期兼容保证。

### 4.5 消费者范围

生成的消费者 metadata 记录：

```text
contractId
contractKind
ownerComponentId
requiredVersionRange
requiredShapeFingerprint
sourcePackage
```

常规生成 Client 使用精确的 Contract 版本和指纹，不要求业务重复填写字符串范围。需要跨版本
兼容时，由 Contract Owner 在独立 contracts Package 的声明中发布经过审查的范围；生成器只接受
有限的 SemVer 范围，不接受运行时任意表达式。Service/Command/Event/InitTask 默认不自动放宽
minor，Route 只有在旧参数和旧 Intent 仍然有效时才允许 minor 兼容。

### 4.6 校验时机和失败语义

1. **生成期**：比较当前声明、上一次成功生成的 manifest 和已解析依赖 Index；检测缺失版本、
   指纹变化未升 major、Owner 漂移、消费者范围不满足。
2. **Host 聚合期**：验证每个实现 Contract 恰好一个 Owner、实现版本满足所有消费者范围、
   指纹满足声明；失败时不写入新的 Host Bundle。
3. **Runtime**：只做最终边界保护，检查生成 Bundle 的 Contract ID、Owner、版本协议和指纹；
   不在运行时下载、协商或自动降级到旧 Contract。
4. **诊断**：使用稳定错误码区分 `missing`、`owner_mismatch`、`version_out_of_range`、
   `fingerprint_changed`、`duplicate_implementation` 和 `stale_generated_output`，日志不记录
   完整参数或业务对象。

不兼容是确定性错误，不转换成普通 `CCResolutionError`，也不静默跳过。可选组件缺失仍遵循
现有 optional dependency 语义，但“存在且版本不兼容”不能伪装成“组件未安装”。

### 4.7 发布与迁移门禁

每个 Contract Package 发布前必须：

1. 保留上一发布版本的 Contract Index 和 fingerprint；
2. 运行生成器兼容检查，输出升级、废弃、缺失和不兼容列表；
3. 对 major 变更提供迁移说明和新 ID/适配期；
4. 重新生成 Owner、Consumer、Host 三类输出并执行 `generate --check`；
5. 通过 Pure Dart、Generator、Demo 和最小干净工程回归后才能打 tag。

废弃 Contract 至少保留一个已发布 minor 周期，并在 metadata 中记录 `deprecatedSince` 和
建议替代 ID。删除前必须没有已解析消费者；生成器应给出消费者 Package 和源码位置，而不是
只报一个 ID。

### 4.8 最小落地顺序

1. 先实现版本解析、范围判断和 canonical fingerprint 的 Pure Dart 契约；
2. 为五类 Contract metadata 增加版本、指纹和消费者引用；
3. Generator 在版本变化与指纹变化不一致时失败；
4. Workspace Validator 增加 Owner、范围和重复实现检查；
5. Runtime 加入只读边界保护和稳定错误码；
6. Demo 增加兼容、缺失、Owner 错误和旧生成物测试；
7. 才允许正式发布 `1.0.0` Contract。

## 5. DevTools 设计与实施

### 5.1 Catalog 与 Runtime 快照联动

先定义版本化的只读快照协议，不直接让 Extension 读取内部 Runtime：

```text
StaticCatalogSnapshot
  package/component/contract/route/service/source location
RuntimeSnapshot
  host/outlet/managed entry/task/trace/failure/fallback
TraceEdge
  navigationId/traceId/source/target/owner/kind/status/duration
```

同一能力用稳定 ID 连接；静态不存在或 Runtime 未安装时显示为“未解析”，不能删除一侧数据。
快照必须有界、脱敏、不可变，并带 `capturedAt`、协议版本和数据来源。

### 5.2 官方 Flutter/Dart DevTools Extension

建议独立 Package，不并入 `ccrouter_devtools` Widget Package：

- `ccrouter_devtools`：应用内只读面板，保持现有 API；
- `devtools/ccrouter_extension`：官方 DevTools Extension UI 和协议适配；
- `ccrouter_devtools_protocol`（必要时）：只读 JSON/RPC 数据模型，不导出 Runtime 控制器。

第一阶段仅支持 Overview、Components、Routes、Entries、Failures、InitTask DAG 和 Trace
详情；Extension 不执行导航、重试、销毁或修改配置。Flutter/Dart/DevTools 版本通过独立矩阵
验证，Extension 启动失败不能影响应用分析。

### 5.3 路由到源码图形化跳转

已有 Catalog 的 `packageUri`、行列号和生成物角色可直接转换为 DevTools `open` 请求：

- Route 节点默认跳到 authored Page/Contract；
- 需要诊断生成过程时，次级链接跳到 generated registration；
- 跨 Package 只跳到公开 Contract 或实现源码，不暴露 `src` 生成路径为业务 API；
- 找不到源码时保留稳定 ID 和 Package，不伪造文件位置。

### 5.4 组件依赖图高级交互

只做确定性图操作：Owner/consumer 聚焦、反向依赖、孤立节点、循环边、optional/required 筛选、
Contract 类型筛选和源码跳转。禁止在图上编辑依赖；修改仍由源码和生成器完成。

### 5.5 能力调用链图

第一阶段只绘制单个 Trace/Navigation 的调用链：

```text
Route/Command/Event/Service/InitTask ingress
 -> interceptor/handler/provider/subscriber/task
 -> result/failure/timeout/cancel
```

Event 的多个 Subscriber 以分支显示，失败隔离保持独立；Service Proxy 显示 caller/method/owner，
不显示参数内容。没有 Trace 边的能力显示“无运行时样本”，不能从静态声明推断“已调用”。

### 5.6 Demo 验收场景

- 打开静态 Route 并跳转到 authored source；
- 从一个 Route Trace 展开 Interceptor、Service Proxy 和 Command；
- Event 分发到两个 Subscriber，其中一个失败但另一条链完成；
- InitTask DAG 显示 Gate、依赖和 skipped；
- Foreign Popup 出现时只看到 Backend foreign entry，不生成 CCRouter Route 节点；
- 组件图筛选 required/optional 和反向依赖；
- Runtime 未初始化、快照过期、源码缺失和 Extension 断连均显示降级状态。

## 6. Analyzer Git `main` 接入

当前 Demo 已通过独立 bootstrap 使用：

```yaml
ccrouter_analyzer_plugin:
  git:
    url: https://github.com/shingohu/cc-router.git
    path: packages/ccrouter_analyzer_plugin
    ref: 97c72daae65d0dd01e1ecd5263c647d6b213f814
```

这个配置有正向收益：可以在 Hosted 发布前让 Demo 验证最新插件修复，同时不把 Analyzer 版本
约束混入生成器 Workspace。它不是正式发布依赖，不能复制到生产组件模板。

同目录的 `pubspec.hosted.yaml` 提供发布后的 Hosted fallback。两个 manifest 不能同时作为
同一个 bootstrap Package 的活动依赖。

实施收口：

1. 保留 Demo 固定 Git commit bootstrap，增加 `pub get`、loader analyze/compile 和诊断 smoke；
2. 对每次插件提交记录 commit/ref 和 Analyzer/`analyzer_plugin` 版本；
3. 插件不可用时业务分析和 `generate --check` 仍必须通过；
4. Hosted 发布后新增 Hosted bootstrap 回归，Demo 再切换到版本约束；
5. 不把 Git `main` 或 Git commit 写入稳定组件脚手架或公开集成文档作为生产推荐。

## 7. 自动埋点设计与实施

### 7.1 从参考项目吸收什么

`auto_track_plugin` 值得借鉴的部分是统一配置入口、页面进入/离开、点击/滑动开关、采样率、
用户身份更新、批量上报和错误/HTTP 观测。但它基于全局 Widget/Key 推断的方式存在跨平台、
业务语义、隐私和误报风险，不能直接复制为 CCRouter 默认行为；尤其不能用随机 Key 代替稳定
业务 ID，也不能默认采集设备 ID、完整参数或原生崩溃内容。

### 7.2 自动识别边界

分三档：

1. **默认档**：只采集 CCRouter Route PV/Leave 和显式 `CCAnalyticsTarget`、Scroll、Exposure；
2. **增强档**：允许应用注册 Widget 类型/语义角色映射和稳定黑名单，仍需显式 opt-in；
3. **实验档**：在 Debug/Profile 构建尝试全局 Widget 识别，仅用于误报率和性能评估，不进入
   Release 默认，也不把 Text、Key 或 Widget.toString 当作业务 ID。

全局 Widget 自动识别在 Flutter、Web、Desktop、OHOS 的语义和性能不一致，不能承诺“全平台
一致自动采集”。平台能力必须通过矩阵声明为 `supported`、`partial` 或 `unsupported`。

### 7.3 黑名单与定制按钮

黑名单只匹配稳定声明：`targetId`、Route ID、Component ID、Widget 类型注册表和 Host/Outlet，
不读取文本内容。按钮推荐保留现有显式 API：

```dart
final confirmTarget = CCAnalyticsTarget(
  tracker: tracker,
  eventId: 'order.detail.confirm',
  properties: const {'surface': 'detail'},
);

FilledButton(
  onPressed: () => confirmTarget.run(submitOrder),
  child: const Text('确认订单'),
)
```

这是比全局猜测更可测试、可审计和可迁移的入口。应用可通过封装自己的 Button 组件统一注入
Target，但不需要业务页面继承 CCRouter 基类。

### 7.4 通用节流与队列

节流放在 `CCAnalyticsEventDispatcher` 和 Target 聚合层，而不是 Firebase/ThinkingData Adapter
各做一套：

- 点击：默认不合并同一事件，支持显式 duplicate window；
- 滑动：按一次手势聚合 start/end、方向和距离桶；
- 曝光：按 target/session/Route 去重并满足可见比例和 dwell time；
- Route PV/Leave：由生命周期配对，不受普通 Widget 节流影响；
- 队列满：丢弃可采样非关键事件并计数，不能丢失 Consent/失败/生命周期安全诊断。

### 7.5 Firebase Adapter

新增独立 `ccrouter_analytics_firebase`，只负责：事件名/属性白名单映射、Consent 状态同步、
`page_view -> logScreenView`、批量策略和 Sink 异常隔离。Firebase 初始化、用户授权、账号身份和
Crashlytics 仍由应用 Composition Root 管理。没有 Firebase 依赖时 Core/Analytics/Auto Track 不应
增加编译成本。

### 7.6 平台兼容矩阵

最小矩阵覆盖 Android、iOS、macOS、Windows、Web、OHOS：

| 能力 | Android/iOS | macOS/Windows | Web | OHOS |
| --- | --- | --- | --- | --- |
| Route PV/Leave | required | required | required | required |
| 显式 Click Target | required | required | required | required |
| Scroll 聚合 | required | required | required | verify |
| Exposure 近似 | required | verify | verify | verify |
| 全局 Widget 识别 | experiment | unsupported by default | unsupported by default | unsupported by default |
| Firebase Adapter | optional | optional | separate validation | optional |

`verify` 必须有可执行测试或明确降级，不允许在文档中写“理论支持”。

### 7.7 Demo 验收与 Consent

Demo 增加独立测试和可视化状态：

- deny：点击、滚动、曝光、PV 均在入队前被过滤，过滤计数可见；
- grant：只允许 grant 之后产生的新事件入队；
- revoke：清理未发送队列，后续事件继续被拒绝；
- Foreign Popup：Popup push/pop 只产生 foreign/backend 诊断，不生成 CCRouter page view/leave，
  不改变底层 Route 的停留时间；
- Firebase mock Sink：校验映射、参数白名单、异常隔离和队列压力；
- 定制按钮：确认点击事件含稳定 `eventId`，不从按钮文字猜测。

## 8. 组件脚手架

### 8.1 值得生成的模板

CLI 继续保持非覆盖式，增加可选模板：

- Service Contract + implementation + `serviceDependencies` 示例；
- Command Contract + Handler + consumer Client 使用示例；
- Event Contract + Payload + static Subscriber 示例；
- InitTask Contract + Handler + Gate/dependsOn 示例；
- contracts Package public barrel、component definition 和最小测试。

### 8.2 不生成的内容

- 业务闭包、网络调用、假 Token、默认全局 EventBus；
- 自动修改 Host 依赖、跨 Package `src` import 或任意 Scope；
- 自动把所有 capability 提升为 external Contract；
- 供应商 SDK、Consent 策略和生产日志配置。

脚手架应复用生成器真实校验规则，生成后必须通过 `generate --check`；模板自身只增加 CLI 测试，
不需要把模板代码编译进框架 Core。

## 9. 性能、RSS/Heap、长时间 Runtime 和多平台回归

### 9.1 指标

| 类别 | 指标 | 目标用途 |
| --- | --- | --- |
| Generator | cold/warm P50/P95、cache hit、metadata bytes | 判断增量生成是否退化 |
| Runtime | initialize、route resolve、navigation、shutdown P50/P95 | 判断热路径和销毁成本 |
| Analytics | enqueue latency、drop count、queue high-water mark | 判断自动埋点压力 |
| Memory | RSS/Heap 增长、Route/Overlay/Timer/Stream 释放 | 发现长期泄漏 |
| Stability | 8/24 小时导航、Popup、后台前台、Session 切换 | 发现累计状态错误 |

### 9.2 场景矩阵

- 1x/10x/30x Route、Service、Command、Event、InitTask metadata；
- 并发导航、拦截超时、取消、Foreign Popup push/pop、Shell/多 Outlet；
- Analytics deny/grant/revoke、队列满、Sink 慢和 Sink 抛错；
- Runtime initialize/shutdown 重复调用、Session 开关、Route Service 创建/销毁；
- macOS、iOS Simulator/真机、Android、Web、OHOS（可用设备）各执行最小 smoke；
- Debug/Profile 运行与 release-like `generate --check` 分开记录，避免把开发工具开销当运行时开销。

### 9.3 判定原则

性能优化不能通过吞异常、取消生命周期事件、缓存脏 metadata 或降低类型校验实现。所有变化
必须同时比较行为回归、错误数、队列丢弃数、RSS/Heap 和生成物 fingerprint。

## 10. 实施阶段与验收门槛

### Phase 0：协议和基线（P0）

- [x] Contract 版本/fingerprint/范围的 Pure Dart 设计冻结；版本与 fingerprint 已进入新
  metadata schema，消费者范围和 Runtime descriptor 仍按后续阶段实现；
- [ ] Catalog/Runtime Snapshot/Trace Edge 协议冻结；
- [x] 性能、队列、RSS/Heap 和长时间运行基线脚本；已覆盖混合能力生成、Runtime 并发与
  资源回收，并提供独立进程的 `runtime_long_run.dart` RSS 趋势入口。绝对 RSS 不设跨平台
  阈值，Heap 细分仍需目标平台 VM Service 采样。
- [x] 生成器已增加 fail-closed per-Package dirty set；metadata、受管输出和直接依赖 Index
  使用精确 fingerprint，dirty 沿反向依赖传播，并以混合能力增量基准验证。
- [x] Demo Analyzer bootstrap 已接入固定 Git commit；插件 Package 兼容性测试、loader
  `analyze/compile` smoke 和 Hosted fallback manifest 均已补齐。发布后切换 Hosted 时需重新
  执行同一组 smoke，插件不可用仍安全降级到 Dart Analyzer/CLI 门禁。

### Phase 1：稳定性与隐私（P0）

- [x] Analytics 通用节流、黑名单和平台能力声明（平台矩阵仍需持续扩展）；
- [x] Consent deny/grant/revoke 与 Foreign Popup 自动断言；
- [x] Firebase mock/真实可选 Adapter 最小闭环；
- [ ] 多平台和长时间 Runtime 回归第一轮。

### Phase 2：Contract 兼容门禁（P0/P1）

- [ ] 五类 Contract 版本和指纹 metadata；
- [ ] Generator/Workspace Validator/Runtime 稳定错误码；
- [ ] 旧 Index、缺失 Owner、范围不满足、指纹漂移和迁移测试；
- [ ] Demo 与干净 Package Workspace 发布模拟。

### Phase 3：DevTools 数据基础（P1）

- [ ] 静态 Catalog 与 Runtime 快照联动；
- [ ] Trace Edge 和单次调用链；
- [ ] 源码位置、组件图筛选和缺失数据降级；
- [ ] 只读权限与脱敏回归。

### Phase 4：官方 DevTools Extension（P1）

- [ ] 独立 Extension Package、协议版本和 SDK 矩阵；
- [ ] Route/Component/Call Chain 视图；
- [ ] Extension 断连/启动失败不影响应用；
- [ ] Demo Extension smoke 和源码跳转验收。

### Phase 5：脚手架与发布回归（P1）

- [ ] 高级 Service/Command/Event/InitTask 模板；
- [ ] 模板非覆盖、生成、分析和错误示例；
- [ ] 全量生成物回归、性能/RSS/Heap/长时间 Runtime 和多平台报告；当前 P0-3 已完成可重复
  基线和确定性资源断言，真实 macOS/iOS/OHOS 设备矩阵与全量回归在所有专项完成后执行。
- [ ] 正式发布候选版本和迁移文档。

## 11. 明确不纳入本轮

- 不做默认全局 Widget 文本/Key 猜测、随机业务 ID、默认设备指纹或不可撤回的隐私数据采集；
- 不把 DevTools 做成 Runtime 控制台；
- 不在 Core 直接依赖 Firebase/ThinkingData；
- 不承诺所有平台都具备相同的全局 Widget 自动识别能力；
- 不用 Contract 兼容自动降级替代缺失的业务迁移；
- 不因为脚手架方便而自动创建跨组件依赖或修改 Host 组合根；
- 不把一次 Trace 伪装成完整历史调用图；历史审计和离线回放另行设计。

## 12. 完成定义

本计划只有在以下条件同时满足时才可标记正式发布前收口：

1. Contract 兼容检查能在生成/聚合阶段阻止不兼容组合，并有稳定错误码；
2. Analyzer 固定 Git ref、Hosted fallback 和插件失效降级均有验证；
3. Consent 和 Foreign Popup 归因测试自动通过；
4. DevTools Extension 只读快照、源码跳转和调用链在 Demo 中可用；
5. 生成脚手架通过非覆盖、生成和分析回归；
6. 性能、RSS/Heap、长时间 Runtime 和多平台报告没有未解释的回归；
7. README、Integration Skill、专项设计文档、CLI 文档和 Release Checklist 同步更新。
