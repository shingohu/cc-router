# 第一次接入：完成一个可验证的业务闭环

先用现有 Route 完成“声明 → 生成 → 打开 → 返回或失败 → 释放”，再按实际场景增加
Service、Command、Event、InitTask 或 UI Fragment。已经有业务工程时，选一条真实调用链，
不为接入 CCRouter 重建业务分层或给所有对象注册 Service。

## 1. 确认版本、来源和工程角色

- 使用工程已选定的 FVM SDK，并确认当前安装的 CCRouter API 与本文一致。
- 当前框架仓库仍是 `0.1.0` 开发版本、`publish_to: none`，不能假设这个版本已在 Hosted 发布。
  外部工程先使用团队明确配置的固定 Git 完整 SHA 或本地联调来源；正式安装说明必须对应
  实际可解析的发布来源。不要把框架 Workspace 的 `resolution: workspace` 抄入独立 App。
- 本地 `pubspec_overrides.yaml` 可以覆盖配套框架包做受控联调；它不替代团队/CI 的固定来源。
  测试前查看实际 `.dart_tool/package_config.json`，确认没有混用不配套的 Generator/Runtime。
- Host 直接依赖 `ccrouter`，通过 `CCManagedRouterApp` 或 Managed Backend 接入，开发依赖包含 `ccrouter_generator` 和 `build_runner`；
  参与生成的组件和 contracts 包按自身角色声明依赖。可选工具包按需添加。
- 标准 Flutter app 的 `.metadata` 可表明 Host 角色。自定义 Flutter Host 可在 `ccrouter.yaml`
  显式声明 `host: { enabled: true }`；Workspace 聚合根不应冒充 Host。

已有 Workspace 仍使用自己的成员关系和 Pub 根；独立 App 使用自己的 Pub 解析与 lockfile。
不要复制框架或另一个应用的 `.dart_tool`。首次验证可以使用本机已有的 Pub 下载缓存，但必须
单独解析消费者依赖；这与证明 Hosted 或发布归档可用是不同的验收。

新建组件时可用 `create component <name> <parent> --with-example`：脚手架已接入原生 Managed、
生成的 Host Assembly 和 Example 自己的 `/` 首页。Workspace 同时登记组件和 Example；独立
场景先在组件 Pub get、`ccrouter portable prepare .`，再在 Example Pub get、`ccrouter generate .`。
组件变更后重新 prepare，工具链不匹配时对齐两边解析；不能让 Example 越权写入只读父组件。

## 2. 选择最窄的声明与依赖边界

| 当前需要 | 首次接入方式 |
| --- | --- |
| 只有组件自己打开页面 | `@CCRoute`，使用自身稳定的生成 API |
| 已有另一个组件需要打开页面 | Pure Dart `@CCRouteContract` + Owner 的 `@CCRouteImplementation` |
| 页面自己的普通资源 | 由 State/组件显式创建和释放 |
| 确实需要随精确 RouteEntry 持有的资源 | Route Service，通过 `CCRouter.routeService(context)` 获取 |
| 普通方法或应用基础设施 | 保持现有窄接口和明确 Owner；需要 Scope/readiness/生成依赖校验时再用 Service |

每个实现 Package 声明一个顶层 `const CCComponent`。真实跨组件契约才进入 contracts 包；
Consumer 依赖公开契约，Owner 绑定页面，Host 装配实现，Consumer 不导入 Owner 页面或 Registrar。
contracts 包由已有业务分层决定，不要求每个能力单独建包。

跨组件 Route 的入口分别面向业务和组件作者：

```dart
// Consumer：公开 barrel 仅暴露生成的 typed Route 和必要值类型。
import 'package:ccrouter/ccrouter.dart';
import 'package:adoption_contracts/adoption_contracts.dart';

Future<String?> openDetail() => CCRouter.navigator.push<String>(
  DetailRoute.intent(itemId: 7),
);
```

这里的 `DetailRoute` 来自实际 `DetailRouteContract` 的生成结果，不是手写 wrapper。
Owner 从自己的 component-author 入口导入 Contract 声明，使用
`@CCRouteImplementation(DetailRouteContract)`。普通内部路由不需要这次 Contract 提升。
详细声明、依赖与资源模式见[实现指导](implementation-patterns.md)及[能力选择](capability-decisions.md)。

多 Host 或左右 Outlet 中，调用点需要指定导航区域。单次操作可使用
`CCRouter.navigator.push(intent, context: context)`；重复操作可在目标 Navigator 内先获取：

```dart
final navigator = CCRouter.navigatorOf(context);
final result = await navigator.push<String>(DetailRoute.intent(itemId: 7));
```

在 build、didChangeDependencies 或交互回调获取，不在 initState 获取。
该对象绑定原 Host 注册轮次和 Outlet，不保存 Context，无须 dispose；显式路由 placement
仍优先。组件换区域时重新获取，Host 注销或 Runtime 关闭后旧对象同步抛出
`CCRouteCancelledError`（`code == 'host_detached'`）。页面退出本身不使对象失效，
业务仍须管理页面任务取消。原有全局入口保持可用，但无 Context 的全局调用不会自动推断
调用组件所在区域。完整生命周期与跨区域规则见[实现指导](implementation-patterns.md#typed-navigation)。

## 3. 从真实 Host 生成并装配

先按工程约定执行 Pub。独立 Flutter Host 可以从自己的目录执行：

```sh
fvm flutter pub get
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate .
```

第二条是明确的生成入口；如果已安装 Pub Hook，成功的 Pub 可能已经自动完成该步骤。
无 Hook 的环境使用同一生成命令，不依赖 IDE 插件或后台 watch 才能接入。
Workspace 可以从自己的根执行 `generate <实际-host>`；不要把聚合根当作参数。
确认输出包括最终校验成功，而不只看 Builder 成功。

Host 只传一个完整 Assembly。下列装配片段假定上一步已生成 Host，已注册可解析的 `/` 首页，
且 Contract 提供 `DetailRoute.intent(itemId: ...)`。若工程首页使用其它地址，修改
`initialLocation` 为该实际地址；CCRouter 不会自动生成首页或把未知 `/` 映射到 Detail。
平台启动链接仍遵循外部入口规则，不能为跑通示例而隐式关闭其校验：

```dart
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
import 'src/ccrouter_generated/ccrouter_host.api.g.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
  runApp(const CCManagedRouterApp(initialLocation: '/'));
}
```

真实启动任务存在时，由 Host 显式 `runInitTasks(gate: ...)`；没有任务无需增加 DAG。
Host 最终拥有 `CCRouterHost.shutdown`。页面返回、Tab 切换和单个导航 Host 卸载不能代替
应用 Runtime 的终止。`CCManagedRouterApp` 只管理导航 Backend，不自动 shutdown 共享 Runtime。

## 4. 用行为完成验收

从实际 Host/所属测试包执行分析、定向测试与最终生成检查：

```sh
fvm dart analyze
fvm flutter test <相关测试>
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate . --no-cache --check
```

至少验证 typed 参数和结果、取消、适用的业务失败，以及资源 Owner 的终态。
需要 Route Service 时，在 Pop、重开和 shutdown 后验证释放，不能只验证页面从屏幕消失。
异步业务还要验证取消后的迟到结果不提交失效状态；框架不能替应用停止任意 Dart Future。

未改变原生插件、平台配置或交付依赖时，先用 Dart/Widget/Host 测试定位接入行为；
平台手势、权限、硬件或发布交付仍须按应用自己的平台门禁补验。

## 5. 完成后再按需接工具

- [CLI 工作流](../../ccrouter-cli-development/SKILL.md)：watch、Pub Hook、Portable State 和维护命令。
- [IDE 指导](ide-analysis-server.md)：可选诊断、隔离 bootstrap 与实际加载验证。
- [DevTools 指导](devtools.md)：Host 拥有的只读诊断界面。
- [生产场景评估](production-scenarios.md)：区分应用职责、接入缺口与框架缺陷。

固定 Git 或本地来源的闭环通过后，正式发布仍需使用实际发布归档/Hosted 依赖重新验证
生成、运行和升级；不能把本地 override 成功标记成发布门禁关闭。
