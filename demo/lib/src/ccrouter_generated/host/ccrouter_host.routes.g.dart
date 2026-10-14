// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'package:ccrouter/ccrouter_host.dart' show CCHostAssembly;
import 'package:ccrouter_devtools/ccrouter_devtools.dart';

import 'package:ccrouter_demo/src/ccrouter_generated/host/ccrouter_demo_ccrouter.g.dart'
    as host_package;

/// Generated static source and dependency index for DevTools.
final ccrouterGeneratedDevToolsCatalog = CCDevToolsStaticCatalogSnapshot(
  capturedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  catalogFingerprint:
      "0b0176a1e1d7d4976f8a490b0cbbedb05e88e329eb655550e096bea634dc0d2b",
  components: [
    CCDevToolsCatalogComponent(
      id: "demo_kv_storage_component",
      version: "0.1.0",
      dependencies: [],
      optionalDependencies: [],
    ),
    CCDevToolsCatalogComponent(
      id: "demo_navigation_lab_component",
      version: "0.1.0",
      dependencies: [
        "demo_kv_storage_component",
        "demo_network_component",
        "demo_order_component",
        "demo_web_component",
      ],
      optionalDependencies: [],
    ),
    CCDevToolsCatalogComponent(
      id: "demo_network_component",
      version: "0.1.0",
      dependencies: [],
      optionalDependencies: [],
    ),
    CCDevToolsCatalogComponent(
      id: "demo_order_component",
      version: "0.1.0",
      dependencies: [],
      optionalDependencies: [],
    ),
    CCDevToolsCatalogComponent(
      id: "demo_payment_component",
      version: "0.1.0",
      dependencies: ["demo_order_component"],
      optionalDependencies: [],
    ),
    CCDevToolsCatalogComponent(
      id: "demo_web_component",
      version: "0.1.0",
      dependencies: [],
      optionalDependencies: [],
    ),
  ],
  records: [
    CCDevToolsCatalogRecord(
      kind: "command",
      id: "demo_navigation_lab.create_receipt",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "创建演示收据并返回稳定的收据编号。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/navigation_lab_component_registrar.dart",
        line: 178,
        column: 8,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "command",
      id: "demo_navigation_lab.fail",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "抛出业务异常以验证安全 Trace 和错误传播。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/navigation_lab_component_registrar.dart",
        line: 200,
        column: 6,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "command",
      id: "demo_navigation_lab.refresh_cache",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "刷新组件缓存并仅报告完成或失败。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/navigation_lab_component_registrar.dart",
        line: 183,
        column: 14,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "command",
      id: "demo_navigation_lab.wait",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "保持等待直到超时或调用方取消，用于验证协作取消。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/navigation_lab_component_registrar.dart",
        line: 190,
        column: 14,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "command",
      id: "demo_order.reserve",
      ownerComponentId: "demo_order_component",
      packageName: "demo_order",
      description: "Reserves one order for a cross-component checkout flow.",
      source: CCDevToolsSourceLocation(
        packageName: "demo_order",
        packageUri: "package:demo_order/src/order_commands.dart",
        line: 6,
        column: 16,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "event",
      id: "demo_navigation_lab.order_completed",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/component_capabilities.dart",
        line: 142,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "event",
      id: "demo_navigation_lab.slow",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/component_capabilities.dart",
        line: 160,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "event",
      id: "demo_navigation_lab.unobserved",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/component_capabilities.dart",
        line: 152,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "initTask",
      id: "demo.startup.analytics",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/navigation_lab_component_registrar.dart",
        line: 115,
        column: 6,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "initTask",
      id: "demo.startup.foundation",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/navigation_lab_component_registrar.dart",
        line: 82,
        column: 14,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "initTask",
      id: "demo.startup.optional-dependent",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/navigation_lab_component_registrar.dart",
        line: 104,
        column: 6,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "initTask",
      id: "demo.startup.optional-sdk",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/navigation_lab_component_registrar.dart",
        line: 93,
        column: 6,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "initTask",
      id: "demo.startup.parallel-primary",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/navigation_lab_component_registrar.dart",
        line: 126,
        column: 14,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "initTask",
      id: "demo.startup.parallel-secondary",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/navigation_lab_component_registrar.dart",
        line: 138,
        column: 14,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "initTask",
      id: "demo.startup.timeout",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri:
            "package:demo_navigation_lab/src/navigation_lab_component_registrar.dart",
        line: 150,
        column: 14,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "initTask",
      id: "demo_order.startup.foundation",
      ownerComponentId: "demo_order_component",
      packageName: "demo_order",
      source: CCDevToolsSourceLocation(
        packageName: "demo_order",
        packageUri: "package:demo_order/src/order_init_tasks.dart",
        line: 10,
        column: 14,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.cancel",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "路由级拦截器取消示例；页面正常情况下不会创建。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/policy_pages.dart",
        line: 147,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.capabilities",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "Command、Event、初始化任务与 Service 生命周期交互实验页。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/capability_page.dart",
        line: 17,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.defer",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "等待外部同意后恢复的 Deferred Navigation 示例。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/policy_pages.dart",
        line: 188,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.detail",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "验证类型安全参数、Query 集合、多 Path、完整 URL、Scheme 与返回值。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/detail_page.dart",
        line: 26,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.extra",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "展示仅在进程内传递的类型安全 Extra 对象。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/shell_pages.dart",
        line: 224,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.failure",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "展示标准导航失败经 Host Failure Policy 恢复后的安全页面。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/failure_page.dart",
        line: 15,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.guarded",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "未保存状态下拒绝 CCRouter Pop 的路由。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/policy_pages.dart",
        line: 220,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.home",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "CCRouter 全功能交互验证首页。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/home_page.dart",
        line: 22,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.lifecycle",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "同时验证 CCPageLifecycleMixin 与 Listener 的页面和 App 生命周期。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/lifecycle_page.dart",
        line: 12,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.network",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "动态 API 环境、Header、授权和网络拦截器示例。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/network_page.dart",
        line: 13,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.presentation.bottom_page",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "普通全屏 Page 从底部滑入，不是 BottomSheet。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/presentation_pages.dart",
        line: 61,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.presentation.cupertino",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/presentation_pages.dart",
        line: 42,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.presentation.dialog",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/presentation_pages.dart",
        line: 139,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.presentation.fade",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/presentation_pages.dart",
        line: 10,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.presentation.scale",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/presentation_pages.dart",
        line: 26,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.presentation.sheet",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/presentation_pages.dart",
        line: 168,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.presentation.transparent",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "用于海报分享预览的透明全屏 Page。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/presentation_pages.dart",
        line: 82,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.proceed",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "路由级拦截器放行示例。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/policy_pages.dart",
        line: 131,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.redirect.source",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "路由级拦截器重定向源页面；页面正常情况下不会创建。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/policy_pages.dart",
        line: 161,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.redirect.target",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "拦截器重定向后的目标页面。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/policy_pages.dart",
        line: 174,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.shell.detail",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "ShellRoute 嵌套子路由。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/shell_pages.dart",
        line: 60,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.shell.feed",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "ShellRoute 共享框架中的内容首页。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/shell_pages.dart",
        line: 17,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.shell.settings",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "ShellRoute 共享框架中的设置页。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/shell_pages.dart",
        line: 89,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.stack",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "交互验证 Push、Replace、Pop、Go 与 Reset。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/stack_page.dart",
        line: 12,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.storage",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "基本类型、JSON Map 和受控存储命名空间示例。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/storage_page.dart",
        line: 15,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.timeout",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "触发标准 Interceptor Timeout Error 的示例。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/policy_pages.dart",
        line: 204,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.workspace.activity",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "StatefulShellRoute 活动分支。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/shell_pages.dart",
        line: 172,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.workspace.detail",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "StatefulShellRoute 首页分支的可 Deep Link 子路由。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/shell_pages.dart",
        line: 143,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.workspace.home",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "StatefulShellRoute 首页分支。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/shell_pages.dart",
        line: 109,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_navigation_lab.workspace.profile",
      ownerComponentId: "demo_navigation_lab_component",
      packageName: "demo_navigation_lab",
      description: "StatefulShellRoute 个人分支。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_navigation_lab",
        packageUri: "package:demo_navigation_lab/src/shell_pages.dart",
        line: 208,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_web.private",
      ownerComponentId: "demo_web_component",
      packageName: "demo_web",
      description:
          "Loads a sensitive process-local request without URI serialization.",
      source: CCDevToolsSourceLocation(
        packageName: "demo_web",
        packageUri: "package:demo_web/src/web_pages.dart",
        line: 30,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "demo_web.public",
      ownerComponentId: "demo_web_component",
      packageName: "demo_web",
      description:
          "Loads one allowlisted public HTTPS URL in the shared Web container.",
      source: CCDevToolsSourceLocation(
        packageName: "demo_web",
        packageUri: "package:demo_web/src/web_pages.dart",
        line: 9,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "route",
      id: "order.detail",
      ownerComponentId: "demo_order_component",
      packageName: "demo_order",
      description: "订单详情，确认后返回订单编号。",
      source: CCDevToolsSourceLocation(
        packageName: "demo_order",
        packageUri: "package:demo_order/src/order_detail_page.dart",
        line: 6,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "service",
      id: "demo.kv_storage",
      ownerComponentId: "demo_kv_storage_component",
      packageName: "demo_kv_storage",
      description: "Stores typed values in isolated application namespaces.",
      source: CCDevToolsSourceLocation(
        packageName: "demo_kv_storage",
        packageUri: "package:demo_kv_storage/src/storage_service.dart",
        line: 70,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "service",
      id: "demo.network.client",
      ownerComponentId: "demo_network_component",
      packageName: "demo_network",
      description:
          "Provides environment-aware HTTP requests with safe interceptors.",
      source: CCDevToolsSourceLocation(
        packageName: "demo_network",
        packageUri: "package:demo_network/src/network_service.dart",
        line: 45,
        column: 13,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: "service",
      id: "demo_order.summary",
      ownerComponentId: "demo_order_component",
      packageName: "demo_order",
      description: "Formats one order identity for cross-component display.",
      source: CCDevToolsSourceLocation(
        packageName: "demo_order",
        packageUri: "package:demo_order/src/order_summary_service.dart",
        line: 6,
        column: 13,
      ),
    ),
  ],
  relations: [
    CCDevToolsCatalogRelation(
      sourceId: "demo_navigation_lab_component",
      targetId: "demo.kv_storage",
      kind: "calls",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo_navigation_lab_component",
      targetId: "demo.network.client",
      kind: "calls",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo_navigation_lab_component",
      targetId: "demo_order.summary",
      kind: "calls",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo_payment_component",
      targetId: "demo_order.summary",
      kind: "calls",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo.startup.analytics",
      targetId: "demo.startup.foundation",
      kind: "dependsOn",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo.startup.foundation",
      targetId: "demo_order.startup.foundation",
      kind: "dependsOn",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo.startup.optional-dependent",
      targetId: "demo.startup.optional-sdk",
      kind: "dependsOn",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo.startup.parallel-primary",
      targetId: "demo.startup.foundation",
      kind: "dependsOn",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo.startup.parallel-secondary",
      targetId: "demo.startup.foundation",
      kind: "dependsOn",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo_navigation_lab_component",
      targetId: "demo_kv_storage_component",
      kind: "dependsOn",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo_navigation_lab_component",
      targetId: "demo_network_component",
      kind: "dependsOn",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo_navigation_lab_component",
      targetId: "demo_order_component",
      kind: "dependsOn",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo_navigation_lab_component",
      targetId: "demo_web_component",
      kind: "dependsOn",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo_payment_component",
      targetId: "demo_order_component",
      kind: "dependsOn",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo_navigation_lab_component",
      targetId: "demo_order.reserve",
      kind: "executes",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo_navigation_lab_component",
      targetId: "demo_navigation_lab.order_completed",
      kind: "subscribes",
    ),
    CCDevToolsCatalogRelation(
      sourceId: "demo_navigation_lab_component",
      targetId: "demo_navigation_lab.slow",
      kind: "subscribes",
    ),
  ],
);

/// Validated generated Package graph installed in this Host.
final ccrouterGeneratedHostAssembly = CCHostAssembly.fromPackageBundles(
  [host_package.ccrouterGeneratedPackageBundle],
  hostToolIntegrations: [
    CCDevToolsHostIntegration(catalog: ccrouterGeneratedDevToolsCatalog),
  ],
);
