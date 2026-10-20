# 2026-10-20 UI Fragment 独立首次接入技术验证

从全新临时目录完成了 `create --dry-run → create → 显式配置 → generate → find --usage → 渲染与 Action 回传`。
enum 与 DTO 两条路径均通过。这是代理执行的技术闭环验证，不是新人接入计时或外部可用性研究，
也不代表 API 冻结或 Hosted 分发验收完成。

[检查摘要](checks.json)记录 20 个命令检查：19 个退出 0，另 1 个为故意漏配 Owner 的预期失败。
[源码归档](consumer-source.tar.gz)包含 enum、DTO 两个版本共 34 个 authored/lockfile 文件，
不包含生成物、`.dart_tool`、平台目录或框架二进制。

## 独立工程与实际边界

- Host、contracts、A（dashboard）、B（catalog）使用自己的 Pub Workspace 和解析状态。
- 五个框架包复制到 Workspace 外的 `framework/`，仅从复制品 pubspec 中去掉
  `resolution: workspace`。未借用原仓库 `.dart_tool` 或 lockfile。
- Flutter `3.41.10-ohos-1.0.0`、Dart `3.11.5`，macOS 主机；使用已有 Pub 下载缓存离线解析。
  临时工程显式关闭 Pub Hook，再显式执行生成，以区分依赖解析和生成步骤。
- A 仅导入公开 Contract 和自身生成 Client；Host 导入 A 的普通 Widget 入口和自身 Assembly。
  B 的实现不通过契约导出，Host 生命周期仍由 Composition Root 负责。
- UI 自身没有增加 Route，实际校验 2 个组件、0 条 Route；Widget 测试也断言 RouteEntry 为空。

[框架源码摘要](framework-source-digests.json)覆盖本轮复制的 159 个源码与配置文件，
排除复制时附带的 4 个 macOS `.DS_Store` 文件。
摘要对应当前工作区源码；`checks.json` 的基线提交不单独代表尚未提交的修改，不能当作发布 SHA。

## 发现及修正

独立消费首先暴露了仓库 Workspace 内未触发的框架缺陷：`ccrouter_ui` 遗漏在框架包集合外，
只读解析时被当作业务组件，首次生成报缺少 Portable State。
修正仅将其加入现有框架包识别集合；真实远端业务组件继续需要自己的 Package Index/Portable State。
新增回归在修改前复现 `requiresPackageIndex == true`，修改后为 false，并保留普通 UI 组件的 true 断言。

原型接入还遗漏了各参与包的生成器开发依赖，曾出现只生成空索引而 `find` 无匹配的结果。
修正接入前置配置后，从另一个全新目录重新执行了本页记录的完整流程。
脚手架提示与指南现明确要求 Contract、A、B 各包声明 `ccrouter_generator` 开发依赖，Host 另需
`build_runner`；Host 的生成器依赖不能替代成员包声明。应核对组件/UI 数量，不能只看命令退出成功。

把 UI runtime 强制改成 Portable 业务包会增加错误的发布责任；把所有外部业务包都视为可写则会
扩大文件所有权。采用现有框架分类规则的窄修正，保留业务分发校验和生成路径。

## 闭环结果

| 检查 | 实际结果 |
| --- | --- |
| dry-run / create | authored 文件零变化 / 新增 3 个文件，既有文件零变化；见[源码变更证明](scaffold-source-proof.json) |
| enum 生成及 `find --usage` | 找到 Contract/Renderer、公开 import、required Owner 和真实 `DashboardComponentFragments.selectionCard` |
| enum Widget 测试 | 1 项通过：双实例、精确 enum 回调、inactive、Props 更新、无 RouteEntry |
| Owner 漏配 | 预期退出 1，包含 consumer、Owner 与 `dependencyMissing`；恢复后检查退出 0 |
| enum → DTO | Contract 升为 `2.0.0`，消费范围改为 `^2.0.0`，重生成 A/B/Host |
| DTO metadata | Contract、Renderer、Consumer 均为 UI schema 2 / Package Index 4 |
| DTO Widget 测试 | 3 项通过：私有 ID 回传与实例隔离、Props 竞态/最新 callback/inactive/实例重建、卸载取消、shutdown 失效与新 Host 重挂 |
| 独立消费者 analyze | enum、DTO 均无问题；只用标准 Analyzer，未安装可选 Plugin |
| 生成新鲜度 | enum 无缓存检查、DTO 缓存及无缓存检查均通过 |
| 仓库回归 | Package Workspace 与 UI 工具共 21 项通过；全仓 analyze 无问题 |
| Demo Portable / 参考检查 | 9 个 Package 就绪；`generate demo --no-cache --check` 通过，非 Pub/Git 发布 |

独立工程的主要日志按命令编号保存在本目录；21–24 为仓库分析、回归、Demo 检查及修复前失败日志。
归档日志已脱敏本地路径，并规整 ANSI 控制符及行尾空白；命令结果与断言内容保留。
预期失败不计入成功 Widget 测试数量。

## 这次样例中的手工成本

前提是已经有 Host、A/B/contracts 包、canonical Owner ID，以及各参与包的生成器开发依赖。
脚手架自动创建 3 个文件：Contract、显式公共 barrel、B Renderer。

| 手动位置 | 文件数 | 内容 |
| --- | --- | --- |
| A、B、Host pubspec | 3 | UI/契约的直接依赖与来源 |
| A 组件定义 | 1 | 公共 import、required Owner、UI Contract/range/alias |
| A 渲染调用与公开 Widget 入口 | 2 | 按 `find` 输出调用自身 Client、Key/active/callback，以及样例 Widget 导出 |
| Host 展示入口 | 1 | 用真实生成 Assembly 启动并展示 A |
| Host 测试 | 1 | 另计，不属于业务 API 接入声明 |

本样例共手动写入或更新 7 个生产文件，另有 1 个测试文件；这不是普遍最低成本。
已有页面和 Host 展示入口可直接复用，不必为每个 Fragment 新增公开 Widget/barrel。
DTO 迁移另改 Contract、B Renderer、A 的消费范围 3 个生产文件，并更新测试；A 的生成 Client 名称保持一致。
业务 schema、异步取消和账号状态隔离仍由开发者设计，工具只能减少模板和查找成本。

## 复现已接线的样例

1. 在新的临时目录解压 `consumer-source.tar.gz`，得到 `enum/` 与 `dto/`。
2. 从包含本轮改动的框架 checkout 复制以下五包到同级 `framework/<package>/`：
   `ccrouter_contracts`、`ccrouter_core`、`ccrouter`、`ccrouter_ui`、`ccrouter_generator`。
   每包复制 `lib/`、存在时的 `bin/`、`build.yaml` 和 `pubspec.yaml`；只从复制品 pubspec
   移除 `resolution: workspace`。可按 `framework-source-digests.json` 核对字节。
3. 选择 `enum/` 或 `dto/`，使用相同 SDK，依次执行：

   ```sh
   CCROUTER_PUB_HOOK_DISABLE=1 fvm flutter pub get --offline
   fvm dart run --verbosity=error ccrouter_generator:ccrouter generate .
   fvm dart run --verbosity=error ccrouter_generator:ccrouter find catalog.selection . --usage dashboard_component
   fvm dart analyze
   fvm flutter test --no-pub test/fragment_test.dart
   fvm dart run --verbosity=error ccrouter_generator:ccrouter generate . --no-cache --check
   ```

归档已含脚手架产物，不能对同名目标再次执行 `create`。从空目标开始的 dry-run/create 结果见编号
02/03 日志和源码变更证明；后续 enum/DTO 样例可分别独立解析、生成和测试。

下一步由未参与实现的接入者按指南完成首个 Fragment，再记录漏配、修正步骤和主观理解成本。
本轮未覆盖 Hosted/发布升级、独立工程的真实 IDE/Plugin 安装、其他 SDK/平台或真机、
真实后端、长期内存/性能，以及最终 API 冻结。
