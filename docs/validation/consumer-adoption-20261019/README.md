# 2026-10-19 消费者最小闭环验证

结论与后续顺序见[核心价值回归](../../CCRouter-core-principles-audit.md)。
[检查摘要](checks.json)记录环境、范围、退出码及未覆盖项；
[通用消费者源码](consumer-source.tar.gz)只包含合成场景，不含 LiberLive 私有业务源码或数据。

## 实际消费者

`liberlive-flutter` 的登录 Route/门禁与外部入口失败专项 14 项通过；
`generate app --check` 通过。前后 985 个相关源码和依赖输入的摘要一致。
使用原项目的 OHOS 锁入口，未改变业务源码、依赖、生成物、签名或平台配置。
AccountRuntime 关闭负责结束其 SignInGate；测试名称中的 Runtime 不能替代默认
CCRouter Runtime shutdown 的验证。App 测试使用内存/测试后端，不请求真实认证服务。

## 独立消费者与复现

此验证检查消费者是否借用了框架 Workspace 状态，不验证尚未发布的 Hosted 分发。
消费者自身包含 contracts、页面实现与 Host；框架的五个基础包另放在 `framework/`。
初始目录没有 `.dart_tool` 和 lockfile，仅复用本机已有 Pub 下载缓存。

1. 在新的临时目录解压 `consumer-source.tar.gz`，得到 `consumer/`。
2. 从记录的框架基线复制 `ccrouter_contracts`、`ccrouter_core`、`ccrouter`、
   `ccrouter_go_router`、`ccrouter_generator` 到同级 `framework/<package>/`；
   只需要各包的 `lib/`、存在时的 `bin/`、`build.yaml` 与 `pubspec.yaml`。
   从这些复制品的 pubspec 中移除 `resolution: workspace`，原仓库不变。
   这是明确的本地源码快照方案，不是正式发布归档。
3. 使用同一 FVM SDK，从 `consumer/` 执行：

   ```sh
   fvm flutter pub get --offline
   fvm dart run --verbosity=error ccrouter_generator:ccrouter generate .
   fvm flutter test --no-pub --concurrency=1 --reporter expanded test
   fvm dart analyze
   fvm dart run --verbosity=error ccrouter_generator:ccrouter generate . --check
   fvm dart run --verbosity=error ccrouter_generator:ccrouter generate . --no-cache --check
   ```

本轮首次 Pub 使用已安装的 Hook，自动生成 2 个组件、1 条 Route、3 个生成 Package；
无 Hook 时显式执行第二条即可。4 项 Widget 测试覆盖 typed result、取消后重开、业务失败与
shutdown 释放 Timer/Route Service。独立分析和缓存/无缓存生成检查通过。
包配置核对证明五个框架依赖均指向复制品，Pub Workspace 指向消费者自身。
首次接入指南的两个 Dart 片段也使用这些真实生成 API 完成标准 Analyzer 编译检查，退出 0。

另在隔离 Analyzer 探针中，将 `DetailRoute.intent` 的 `int itemId` 传成 String，
并只导入业务 barrel 后调用 `CCRouterHost.shutdown()`；标准 Analyzer 分别拒绝错误类型和
Host 符号，退出 3。这是预期失败，不计入成功测试数量，也不依赖可选 Plugin。

归档保留本轮 lockfile；首次无 lockfile 的解析结果已由本轮 Pub 记录确认。复现时可保留锁定
版本；重新测量首次依赖解析时，应在另一个新目录使用 authored pubspec 重新解析。
普通重跑通过不能证明其它 SDK、发布升级或真机行为。
