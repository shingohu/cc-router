// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_navigation_lab/src/detail_page.dart'
    as route_src_detail_page_dart;
import 'package:demo_navigation_lab/src/failure_page.dart'
    as route_src_failure_page_dart;
import 'package:demo_navigation_lab/src/home_page.dart'
    as route_src_home_page_dart;
import 'package:demo_navigation_lab/src/lifecycle_page.dart'
    as route_src_lifecycle_page_dart;
import 'package:demo_navigation_lab/src/policy_pages.dart'
    as route_src_policy_pages_dart;
import 'package:demo_navigation_lab/src/presentation_pages.dart'
    as route_src_presentation_pages_dart;
import 'package:demo_navigation_lab/src/shell_pages.dart'
    as route_src_shell_pages_dart;
import 'package:demo_navigation_lab/src/stack_page.dart'
    as route_src_stack_page_dart;

/// Generated registration index for component `demo_navigation_lab_component`.
final class DemoNavigationLabComponentGeneratedRoutes {
  /// Creates the immutable component route index.
  const DemoNavigationLabComponentGeneratedRoutes();

  /// Registers every route owned by `demo_navigation_lab_component` in stable order.
  void register(CCRegistry registry) {
    route_src_detail_page_dart.ccrouterRegisterDemoDetailPageRoute(registry);
    route_src_failure_page_dart.ccrouterRegisterDemoFailurePageRoute(registry);
    route_src_home_page_dart.ccrouterRegisterDemoNavigationHomePageRoute(
      registry,
    );
    route_src_lifecycle_page_dart.ccrouterRegisterDemoLifecyclePageRoute(
      registry,
    );
    route_src_policy_pages_dart.ccrouterRegisterDemoCancelledPageRoute(
      registry,
    );
    route_src_policy_pages_dart.ccrouterRegisterDemoDeferredPageRoute(registry);
    route_src_policy_pages_dart.ccrouterRegisterDemoGuardedPageRoute(registry);
    route_src_policy_pages_dart.ccrouterRegisterDemoProceedPageRoute(registry);
    route_src_policy_pages_dart.ccrouterRegisterDemoRedirectSourcePageRoute(
      registry,
    );
    route_src_policy_pages_dart.ccrouterRegisterDemoRedirectTargetPageRoute(
      registry,
    );
    route_src_policy_pages_dart.ccrouterRegisterDemoTimeoutPageRoute(registry);
    route_src_presentation_pages_dart.ccrouterRegisterDemoBottomPageRoute(
      registry,
    );
    route_src_presentation_pages_dart.ccrouterRegisterDemoCupertinoPageRoute(
      registry,
    );
    route_src_presentation_pages_dart.ccrouterRegisterDemoDialogPageRoute(
      registry,
    );
    route_src_presentation_pages_dart.ccrouterRegisterDemoFadePageRoute(
      registry,
    );
    route_src_presentation_pages_dart.ccrouterRegisterDemoScalePageRoute(
      registry,
    );
    route_src_presentation_pages_dart.ccrouterRegisterDemoBottomSheetPageRoute(
      registry,
    );
    route_src_presentation_pages_dart.ccrouterRegisterDemoTransparentPageRoute(
      registry,
    );
    route_src_shell_pages_dart.ccrouterRegisterDemoExtraPageRoute(registry);
    route_src_shell_pages_dart.ccrouterRegisterDemoShellDetailPageRoute(
      registry,
    );
    route_src_shell_pages_dart.ccrouterRegisterDemoShellFeedPageRoute(registry);
    route_src_shell_pages_dart.ccrouterRegisterDemoShellSettingsPageRoute(
      registry,
    );
    route_src_shell_pages_dart.ccrouterRegisterDemoWorkspaceActivityPageRoute(
      registry,
    );
    route_src_shell_pages_dart.ccrouterRegisterDemoWorkspaceDetailPageRoute(
      registry,
    );
    route_src_shell_pages_dart.ccrouterRegisterDemoWorkspaceHomePageRoute(
      registry,
    );
    route_src_shell_pages_dart.ccrouterRegisterDemoWorkspaceProfilePageRoute(
      registry,
    );
    route_src_stack_page_dart.ccrouterRegisterDemoStackPageRoute(registry);
  }
}

/// Shared generated index used by the component Registrar.
const demoNavigationLabComponentGeneratedRoutes =
    DemoNavigationLabComponentGeneratedRoutes();

/// Backend-neutral Flutter destinations owned by `demo_navigation_lab_component`.
final demoNavigationLabComponentRouteCatalog = CCFlutterRouteCatalog([
  CCFlutterRouteDestination(
    route: route_src_detail_page_dart.ccrouterDescribeDemoDetailPageRoute(),
    builder: (arguments) =>
        route_src_detail_page_dart.ccrouterBuildDemoDetailPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_failure_page_dart.ccrouterDescribeDemoFailurePageRoute(),
    builder: (arguments) => route_src_failure_page_dart
        .ccrouterBuildDemoFailurePageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_home_page_dart
        .ccrouterDescribeDemoNavigationHomePageRoute(),
    builder: (arguments) => route_src_home_page_dart
        .ccrouterBuildDemoNavigationHomePageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_lifecycle_page_dart
        .ccrouterDescribeDemoLifecyclePageRoute(),
    builder: (arguments) => route_src_lifecycle_page_dart
        .ccrouterBuildDemoLifecyclePageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_policy_pages_dart.ccrouterDescribeDemoCancelledPageRoute(),
    builder: (arguments) => route_src_policy_pages_dart
        .ccrouterBuildDemoCancelledPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_policy_pages_dart.ccrouterDescribeDemoDeferredPageRoute(),
    builder: (arguments) => route_src_policy_pages_dart
        .ccrouterBuildDemoDeferredPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_policy_pages_dart.ccrouterDescribeDemoGuardedPageRoute(),
    builder: (arguments) => route_src_policy_pages_dart
        .ccrouterBuildDemoGuardedPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_policy_pages_dart.ccrouterDescribeDemoProceedPageRoute(),
    builder: (arguments) => route_src_policy_pages_dart
        .ccrouterBuildDemoProceedPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_policy_pages_dart
        .ccrouterDescribeDemoRedirectSourcePageRoute(),
    builder: (arguments) => route_src_policy_pages_dart
        .ccrouterBuildDemoRedirectSourcePageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_policy_pages_dart
        .ccrouterDescribeDemoRedirectTargetPageRoute(),
    builder: (arguments) => route_src_policy_pages_dart
        .ccrouterBuildDemoRedirectTargetPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_policy_pages_dart.ccrouterDescribeDemoTimeoutPageRoute(),
    builder: (arguments) => route_src_policy_pages_dart
        .ccrouterBuildDemoTimeoutPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_presentation_pages_dart
        .ccrouterDescribeDemoBottomPageRoute(),
    builder: (arguments) => route_src_presentation_pages_dart
        .ccrouterBuildDemoBottomPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_presentation_pages_dart
        .ccrouterDescribeDemoCupertinoPageRoute(),
    builder: (arguments) => route_src_presentation_pages_dart
        .ccrouterBuildDemoCupertinoPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_presentation_pages_dart
        .ccrouterDescribeDemoDialogPageRoute(),
    builder: (arguments) => route_src_presentation_pages_dart
        .ccrouterBuildDemoDialogPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_presentation_pages_dart
        .ccrouterDescribeDemoFadePageRoute(),
    builder: (arguments) => route_src_presentation_pages_dart
        .ccrouterBuildDemoFadePageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_presentation_pages_dart
        .ccrouterDescribeDemoScalePageRoute(),
    builder: (arguments) => route_src_presentation_pages_dart
        .ccrouterBuildDemoScalePageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_presentation_pages_dart
        .ccrouterDescribeDemoBottomSheetPageRoute(),
    builder: (arguments) => route_src_presentation_pages_dart
        .ccrouterBuildDemoBottomSheetPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_presentation_pages_dart
        .ccrouterDescribeDemoTransparentPageRoute(),
    builder: (arguments) => route_src_presentation_pages_dart
        .ccrouterBuildDemoTransparentPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_shell_pages_dart.ccrouterDescribeDemoExtraPageRoute(),
    builder: (arguments) =>
        route_src_shell_pages_dart.ccrouterBuildDemoExtraPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_shell_pages_dart
        .ccrouterDescribeDemoShellDetailPageRoute(),
    builder: (arguments) => route_src_shell_pages_dart
        .ccrouterBuildDemoShellDetailPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_shell_pages_dart.ccrouterDescribeDemoShellFeedPageRoute(),
    builder: (arguments) => route_src_shell_pages_dart
        .ccrouterBuildDemoShellFeedPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_shell_pages_dart
        .ccrouterDescribeDemoShellSettingsPageRoute(),
    builder: (arguments) => route_src_shell_pages_dart
        .ccrouterBuildDemoShellSettingsPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_shell_pages_dart
        .ccrouterDescribeDemoWorkspaceActivityPageRoute(),
    builder: (arguments) => route_src_shell_pages_dart
        .ccrouterBuildDemoWorkspaceActivityPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_shell_pages_dart
        .ccrouterDescribeDemoWorkspaceDetailPageRoute(),
    builder: (arguments) => route_src_shell_pages_dart
        .ccrouterBuildDemoWorkspaceDetailPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_shell_pages_dart
        .ccrouterDescribeDemoWorkspaceHomePageRoute(),
    builder: (arguments) => route_src_shell_pages_dart
        .ccrouterBuildDemoWorkspaceHomePageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_shell_pages_dart
        .ccrouterDescribeDemoWorkspaceProfilePageRoute(),
    builder: (arguments) => route_src_shell_pages_dart
        .ccrouterBuildDemoWorkspaceProfilePageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_stack_page_dart.ccrouterDescribeDemoStackPageRoute(),
    builder: (arguments) =>
        route_src_stack_page_dart.ccrouterBuildDemoStackPageRoute(arguments),
  ),
]);
