# Event Contract alias 与多轮 review（2026-11-19，本地）

本轮在 `codex/unify-contract-validation` 上继续工作，基线为
`7f3d95754eefb978b0074380a19c5fb14c11a9c6`（Git tag `0.2.0`）。
此前的[名称与版本校验收口](../20261118-contract-validation/report.md)仍在同一未提交改动中。
本报告不将前一阶段的整套尝试、SDK bootstrap 失败与本轮 Event 验证相互替代。

## 行为与兼容边界

`CCEventContract.alias` 是可选的完整 Owner Publication Client 方法名，不追加前缀。
省略时保留既有 publish/type-name 推导，裸 `Event` 类型的历史 fallback `publishevent`
也保留。有效名称按统一的静态 Client 入口规则校验，同一 Owner 的方法名不能重复。
没有新增 `eventDependencies` 或消费者发布权。校验也适用于此前未检查的 Owner 推导名：
若旧类型产生包含 `_` 或 `$` 的静态入口名，需要显式设置合规 alias；这是输入约束收紧，
不应将“默认拼写保留”解读为任何历史未校验输入都继续接受。

显式 alias 写入 metadata 并参与 Contract fingerprint，与 Command 一致；未填写时不新增
空 alias 字段，旧 fingerprint 保持。更改 alias 后需评审版本并重生成 Owner/Subscriber/Host。
Event ID、payload、Publisher 权限、Subscriber ID、超时、取消和分发机制不变。

修改覆盖公开构造器、模型、本地与导入读取、metadata、Client、外部 metadata、Analyzer
及接入文档。命名算法由 Generator helper 共用；Plugin 因 Analyzer 隔离单独镜像。
没有新增运行时资源或生命周期 Owner。

## Review 轮次

1. **调用链与隔离**：核对上述全部入口，确认 alias 仅影响成员名与 fingerprint，不替换
   Event ID、不改变 Owner-only Publication Client 规则，也不向业务 facade 暴露内部接口。
2. **兼容与命名边界**：保留裸 `Event` fallback；旧无 payload、无 alias 的 Event 使用
   golden fingerprint `99e7c491a7c427b3e11322bb356458a6113f9305dfc43f23befbb3187b6ba883`。
   实际 Host 中添加两个默认撞名的临时 Event，确认 alias 生效且 Event ID 保留，移除 alias
   后报告冲突；finally 恢复源文件并重生成，产物与探针前一致。
3. **歧义与错误输入**：发现重复 Contract 注解可能静默选择第一个 alias，新增回归复现漏检，
   见 [duplicate-red.log](duplicate-red.log)。现本地声明和导入 Subscriber 路径均要求恰好
   一个注解。测试覆盖导入的非法 alias、重复注解、空/关键字/Object 保留名及非字符串外部
   metadata；计算型覆盖值仍保守交给 Generator，不推测其值。

上述轮次未发现本次改动仍需修复的问题；不构成全仓无缺陷、安全或发布认证。

## 验证

| 检查 | 结果 | 记录 |
| --- | --- | --- |
| Event、naming、Workspace 第三轮专项 | 79 项通过 | [generator-round3.log](generator-round3.log) |
| 真实 Host alias/冲突往返 | 1 项通过 | [host-round2.log](host-round2.log) |
| Plugin source/UI 专项 | 113 项通过 | [plugin-focused.log](plugin-focused.log) |
| 隔离 Plugin 完整套件 | 215 项通过，包含真实 Server | [plugin-full.log](plugin-full.log) |
| 框架完整回归 | 1720 项通过 | [framework-full.log](framework-full.log) |
| 根与相关 Package 分析 | 无问题 | [root](root-analyze.log)、[相关 Package](analyze-round3.log) |
| 隔离 Plugin 分析 | 无问题 | [plugin-analyze.log](plugin-analyze.log) |

专项与其它套件可能重叠，不累加测试数。Plugin 命令在隔离 Package 目录执行；框架从根
执行 `fvm flutter test --no-pub packages/ccrouter_test/test --reporter expanded`。
Generator 专项与 Host 回归从根执行：

```sh
fvm dart test --concurrency=1 \
  packages/ccrouter_test/generator_test/event_generator_test.dart \
  packages/ccrouter_test/generator_test/generated_client_naming_test.dart \
  packages/ccrouter_test/generator_test/workspace_validator_test.dart --reporter expanded
fvm dart test --concurrency=1 packages/ccrouter_test/generator_test/generation_command_test.dart \
  --name 'Event aliases resolve publication collisions' --reporter expanded
```

最终串行复验在恢复临时源文件后完成，使用与真实 Workspace 测试相同的排他锁：

| 检查 | 结果 | 记录 |
| --- | --- | --- |
| 最终 Host alias/冲突与恢复 | 1 项通过 | [host-final.log](host-final.log) |
| Demo 无缓存 freshness | 通过，6 组件、34 路由、11 Packages | [demo-check-fixed.log](demo-check-fixed.log) |
| Example 初次 freshness | 失败：两份生成物依赖指纹陈旧 | [example-check.log](example-check.log) |
| Example 正式生成后 freshness | 通过，2 组件、2 路由、3 Packages | [生成](example-generate.log)、[复验](example-check-fixed.log) |
| Portable prepare/publish | 9 个 Package 就绪，没有外部发布 | [prepare](prepare.log)、[portable](portable.log) |
| Demo 完整测试 | 118 项通过 | [demo-tests.log](demo-tests.log) |
| 独立 Example 测试 | 1 项通过 | [example-tests.log](example-tests.log) |
| Demo 分析 | 无问题 | [demo-analyze.log](demo-analyze.log) |

Example 只刷新了生成文件对既有依赖的指纹引用，没有修改业务代码。上述 freshness 使用
已有 Builder 缓存，不是冷构建基准。来源摘要见 [source-manifest.json](source-manifest.json)，
[只读复核](review-proof.json)确认生产/测试源码摘要未漂移，Demo 差异仅限 Portable 工具
身份与 Example 指纹；最终归档/链接/敏感信息检查见 [archive-checks.json](archive-checks.json)。

## pin 与未覆盖范围

没有提交、推送或创建 Git tag。Demo bootstrap 保留基线已发布 Plugin SHA，不能宣称
本地测试证明 Demo 已加载本轮诊断。Git 支持版本 tag、lockfile 能保存 resolved SHA，
但当前 bootstrap 工具只接受完整 SHA；改用 tag 需单独补齐 tag/SHA 一致性及移动检测。
现有 `0.2.0` 不包含本轮未提交功能。

没有 GUI IDE、真机、长期 heap、性能或正式安装/发布矩阵验证。完整 Generator 的历史
失败与标准入口复跑保留在前一阶段报告，不将分次通过改写为本轮一次完整全绿。
原始日志保留，归档只机械脱敏 home 路径和进度行尾空白，不改写结果或失败事实。
