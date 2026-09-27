// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_navigation_lab/src/navigation_lab_component.dart'
    as component_source;
import '../binding/capability_page.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_capability_page_route_binding_g_dart;
import '../binding/detail_page.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_detail_page_route_binding_g_dart;
import '../binding/failure_page.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_failure_page_route_binding_g_dart;
import '../binding/home_page.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_home_page_route_binding_g_dart;
import '../binding/lifecycle_page.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_lifecycle_page_route_binding_g_dart;
import '../binding/policy_pages.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_policy_pages_route_binding_g_dart;
import '../binding/presentation_pages.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_presentation_pages_route_binding_g_dart;
import '../binding/shell_pages.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_shell_pages_route_binding_g_dart;
import '../binding/stack_page.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_stack_page_route_binding_g_dart;
import '../command/navigation_lab_component_registrar.command.g.dart'
    as route_src_ccrouter_generated_command_navigation_lab_component_registrar_command_g_dart;
import '../event/navigation_lab_component_registrar.event.g.dart'
    as route_src_ccrouter_generated_event_navigation_lab_component_registrar_event_g_dart;
import '../init_task/navigation_lab_component_registrar.init_task.g.dart'
    as route_src_ccrouter_generated_init_task_navigation_lab_component_registrar_init_task_g_dart;
import '../route/capability_page.route.g.dart'
    as route_src_ccrouter_generated_route_capability_page_route_g_dart;
import '../route/detail_page.route.g.dart'
    as route_src_ccrouter_generated_route_detail_page_route_g_dart;
import '../route/failure_page.route.g.dart'
    as route_src_ccrouter_generated_route_failure_page_route_g_dart;
import '../route/home_page.route.g.dart'
    as route_src_ccrouter_generated_route_home_page_route_g_dart;
import '../route/lifecycle_page.route.g.dart'
    as route_src_ccrouter_generated_route_lifecycle_page_route_g_dart;
import '../route/policy_pages.route.g.dart'
    as route_src_ccrouter_generated_route_policy_pages_route_g_dart;
import '../route/presentation_pages.route.g.dart'
    as route_src_ccrouter_generated_route_presentation_pages_route_g_dart;
import '../route/shell_pages.route.g.dart'
    as route_src_ccrouter_generated_route_shell_pages_route_g_dart;
import '../route/stack_page.route.g.dart'
    as route_src_ccrouter_generated_route_stack_page_route_g_dart;
import 'package:demo_navigation_lab/src/navigation_lab_component_registrar.dart'
    as route_src_navigation_lab_component_registrar_dart;

/// Generated capability Registrar for component `demo_navigation_lab_component`.
final class _DemoNavigationLabComponentGeneratedRegistrar
    implements CCComponentRegistrar {
  /// Creates the stateless generated Registrar.
  const _DemoNavigationLabComponentGeneratedRegistrar();

  /// Registers every generated capability in stable order.
  @override
  void register(CCRegistry registry) {
    route_src_ccrouter_generated_route_capability_page_route_g_dart
        .ccrouterRegisterDemoCapabilitiesPageRoute(registry);
    route_src_ccrouter_generated_route_detail_page_route_g_dart
        .ccrouterRegisterDemoDetailPageRoute(registry);
    route_src_ccrouter_generated_route_failure_page_route_g_dart
        .ccrouterRegisterDemoFailurePageRoute(registry);
    route_src_ccrouter_generated_route_home_page_route_g_dart
        .ccrouterRegisterDemoNavigationHomePageRoute(registry);
    route_src_ccrouter_generated_route_lifecycle_page_route_g_dart
        .ccrouterRegisterDemoLifecyclePageRoute(registry);
    route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterRegisterDemoCancelledPageRoute(registry);
    route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterRegisterDemoDeferredPageRoute(registry);
    route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterRegisterDemoGuardedPageRoute(registry);
    route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterRegisterDemoProceedPageRoute(registry);
    route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterRegisterDemoRedirectSourcePageRoute(registry);
    route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterRegisterDemoRedirectTargetPageRoute(registry);
    route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterRegisterDemoTimeoutPageRoute(registry);
    route_src_ccrouter_generated_route_presentation_pages_route_g_dart
        .ccrouterRegisterDemoBottomPageRoute(registry);
    route_src_ccrouter_generated_route_presentation_pages_route_g_dart
        .ccrouterRegisterDemoCupertinoPageRoute(registry);
    route_src_ccrouter_generated_route_presentation_pages_route_g_dart
        .ccrouterRegisterDemoDialogPageRoute(registry);
    route_src_ccrouter_generated_route_presentation_pages_route_g_dart
        .ccrouterRegisterDemoFadePageRoute(registry);
    route_src_ccrouter_generated_route_presentation_pages_route_g_dart
        .ccrouterRegisterDemoScalePageRoute(registry);
    route_src_ccrouter_generated_route_presentation_pages_route_g_dart
        .ccrouterRegisterDemoBottomSheetPageRoute(registry);
    route_src_ccrouter_generated_route_presentation_pages_route_g_dart
        .ccrouterRegisterDemoTransparentPageRoute(registry);
    route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterRegisterDemoExtraPageRoute(registry);
    route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterRegisterDemoShellDetailPageRoute(registry);
    route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterRegisterDemoShellFeedPageRoute(registry);
    route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterRegisterDemoShellSettingsPageRoute(registry);
    route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterRegisterDemoWorkspaceActivityPageRoute(registry);
    route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterRegisterDemoWorkspaceDetailPageRoute(registry);
    route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterRegisterDemoWorkspaceHomePageRoute(registry);
    route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterRegisterDemoWorkspaceProfilePageRoute(registry);
    route_src_ccrouter_generated_route_stack_page_route_g_dart
        .ccrouterRegisterDemoStackPageRoute(registry);
    route_src_ccrouter_generated_command_navigation_lab_component_registrar_command_g_dart
        .ccrouterRegisterHandleDemoCreateReceiptCommand(registry);
    route_src_ccrouter_generated_command_navigation_lab_component_registrar_command_g_dart
        .ccrouterRegisterHandleDemoFailCommand(registry);
    route_src_ccrouter_generated_command_navigation_lab_component_registrar_command_g_dart
        .ccrouterRegisterHandleDemoRefreshCacheCommand(registry);
    route_src_ccrouter_generated_command_navigation_lab_component_registrar_command_g_dart
        .ccrouterRegisterHandleDemoWaitCommand(registry);
    route_src_navigation_lab_component_registrar_dart
        .registerDemoNavigationLabCapabilities(registry);
    route_src_ccrouter_generated_event_navigation_lab_component_registrar_event_g_dart
        .ccrouterRegisterTrackDemoOrderCompletedEventSubscription(
          registry,
          subscriberId: "demo.analytics.order-completed",
        );
    route_src_ccrouter_generated_event_navigation_lab_component_registrar_event_g_dart
        .ccrouterRegisterFailDemoOrderCompletedEventSubscription(
          registry,
          subscriberId: "demo.broken.order-completed",
        );
    route_src_ccrouter_generated_event_navigation_lab_component_registrar_event_g_dart
        .ccrouterRegisterWaitForDemoSlowEventEventSubscription(
          registry,
          subscriberId:
              "demo_navigation_lab_component.demo_navigation_lab.slow",
        );
    route_src_ccrouter_generated_init_task_navigation_lab_component_registrar_init_task_g_dart
        .ccrouterRegisterInitializeDemoAnalyticsInitTask(registry);
    route_src_ccrouter_generated_init_task_navigation_lab_component_registrar_init_task_g_dart
        .ccrouterRegisterInitializeDemoFoundationInitTask(registry);
    route_src_ccrouter_generated_init_task_navigation_lab_component_registrar_init_task_g_dart
        .ccrouterRegisterInitializeDemoOptionalDependentInitTask(registry);
    route_src_ccrouter_generated_init_task_navigation_lab_component_registrar_init_task_g_dart
        .ccrouterRegisterInitializeDemoOptionalSdkInitTask(registry);
    route_src_ccrouter_generated_init_task_navigation_lab_component_registrar_init_task_g_dart
        .ccrouterRegisterInitializeDemoParallelPrimaryInitTask(registry);
    route_src_ccrouter_generated_init_task_navigation_lab_component_registrar_init_task_g_dart
        .ccrouterRegisterInitializeDemoParallelSecondaryInitTask(registry);
    route_src_ccrouter_generated_init_task_navigation_lab_component_registrar_init_task_g_dart
        .ccrouterRegisterInitializeDemoTimeoutInitTask(registry);
  }
}

/// Generated Runtime Manifest for component `demo_navigation_lab_component`.
const demoNavigationLabComponentManifest = CCComponentManifest.fromComponent(
  component: component_source.demoNavigationLabComponent,
  registrar: _DemoNavigationLabComponentGeneratedRegistrar(),
);

/// Backend-neutral Flutter destinations owned by `demo_navigation_lab_component`.
final demoNavigationLabComponentRouteCatalog = CCFlutterRouteCatalog([
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_capability_page_route_g_dart
        .ccrouterDescribeDemoCapabilitiesPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_capability_page_route_binding_g_dart
            .ccrouterBuildDemoCapabilitiesPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_detail_page_route_g_dart
        .ccrouterDescribeDemoDetailPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_detail_page_route_binding_g_dart
            .ccrouterBuildDemoDetailPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_failure_page_route_g_dart
        .ccrouterDescribeDemoFailurePageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_failure_page_route_binding_g_dart
            .ccrouterBuildDemoFailurePageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_home_page_route_g_dart
        .ccrouterDescribeDemoNavigationHomePageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_home_page_route_binding_g_dart
            .ccrouterBuildDemoNavigationHomePageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_lifecycle_page_route_g_dart
        .ccrouterDescribeDemoLifecyclePageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_lifecycle_page_route_binding_g_dart
            .ccrouterBuildDemoLifecyclePageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterDescribeDemoCancelledPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_policy_pages_route_binding_g_dart
            .ccrouterBuildDemoCancelledPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterDescribeDemoDeferredPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_policy_pages_route_binding_g_dart
            .ccrouterBuildDemoDeferredPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterDescribeDemoGuardedPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_policy_pages_route_binding_g_dart
            .ccrouterBuildDemoGuardedPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterDescribeDemoProceedPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_policy_pages_route_binding_g_dart
            .ccrouterBuildDemoProceedPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterDescribeDemoRedirectSourcePageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_policy_pages_route_binding_g_dart
            .ccrouterBuildDemoRedirectSourcePageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterDescribeDemoRedirectTargetPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_policy_pages_route_binding_g_dart
            .ccrouterBuildDemoRedirectTargetPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_policy_pages_route_g_dart
        .ccrouterDescribeDemoTimeoutPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_policy_pages_route_binding_g_dart
            .ccrouterBuildDemoTimeoutPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition:
        route_src_ccrouter_generated_route_presentation_pages_route_g_dart
            .ccrouterDescribeDemoBottomPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_presentation_pages_route_binding_g_dart
            .ccrouterBuildDemoBottomPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition:
        route_src_ccrouter_generated_route_presentation_pages_route_g_dart
            .ccrouterDescribeDemoCupertinoPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_presentation_pages_route_binding_g_dart
            .ccrouterBuildDemoCupertinoPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition:
        route_src_ccrouter_generated_route_presentation_pages_route_g_dart
            .ccrouterDescribeDemoDialogPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_presentation_pages_route_binding_g_dart
            .ccrouterBuildDemoDialogPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition:
        route_src_ccrouter_generated_route_presentation_pages_route_g_dart
            .ccrouterDescribeDemoFadePageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_presentation_pages_route_binding_g_dart
            .ccrouterBuildDemoFadePageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition:
        route_src_ccrouter_generated_route_presentation_pages_route_g_dart
            .ccrouterDescribeDemoScalePageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_presentation_pages_route_binding_g_dart
            .ccrouterBuildDemoScalePageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition:
        route_src_ccrouter_generated_route_presentation_pages_route_g_dart
            .ccrouterDescribeDemoBottomSheetPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_presentation_pages_route_binding_g_dart
            .ccrouterBuildDemoBottomSheetPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition:
        route_src_ccrouter_generated_route_presentation_pages_route_g_dart
            .ccrouterDescribeDemoTransparentPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_presentation_pages_route_binding_g_dart
            .ccrouterBuildDemoTransparentPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterDescribeDemoExtraPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_shell_pages_route_binding_g_dart
            .ccrouterBuildDemoExtraPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterDescribeDemoShellDetailPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_shell_pages_route_binding_g_dart
            .ccrouterBuildDemoShellDetailPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterDescribeDemoShellFeedPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_shell_pages_route_binding_g_dart
            .ccrouterBuildDemoShellFeedPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterDescribeDemoShellSettingsPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_shell_pages_route_binding_g_dart
            .ccrouterBuildDemoShellSettingsPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterDescribeDemoWorkspaceActivityPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_shell_pages_route_binding_g_dart
            .ccrouterBuildDemoWorkspaceActivityPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterDescribeDemoWorkspaceDetailPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_shell_pages_route_binding_g_dart
            .ccrouterBuildDemoWorkspaceDetailPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterDescribeDemoWorkspaceHomePageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_shell_pages_route_binding_g_dart
            .ccrouterBuildDemoWorkspaceHomePageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_shell_pages_route_g_dart
        .ccrouterDescribeDemoWorkspaceProfilePageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_shell_pages_route_binding_g_dart
            .ccrouterBuildDemoWorkspaceProfilePageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition: route_src_ccrouter_generated_route_stack_page_route_g_dart
        .ccrouterDescribeDemoStackPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_stack_page_route_binding_g_dart
            .ccrouterBuildDemoStackPageRoute(arguments),
  ),
]);
