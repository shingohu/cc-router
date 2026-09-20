// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

part of '../web_pages.dart';

// **************************************************************************
// _RouteGenerator
// **************************************************************************

/// Package-internal bridge used by the generated component route index.
///
/// Registration retains the external Pure Dart contract as the single source
/// of route identity, parameters, and navigation policy.
void ccrouterRegisterDemoPublicWebPageRoute(CCRegistry registry) =>
    registry.registerRoute(DemoPublicWebRoute.definition);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoPublicWebPageRoute() {
  final definition = DemoPublicWebRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bound to the public route contract.
DemoPublicWebPage ccrouterBuildDemoPublicWebPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = DemoPublicWebRoute.definition.codec.decode(arguments);
  return DemoPublicWebPage(target: decoded.target);
}

/// Package-internal bridge used by the generated component route index.
///
/// Registration retains the external Pure Dart contract as the single source
/// of route identity, parameters, and navigation policy.
void ccrouterRegisterDemoPrivateWebPageRoute(CCRegistry registry) =>
    registry.registerRoute(DemoPrivateWebRoute.definition);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoPrivateWebPageRoute() {
  final definition = DemoPrivateWebRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bound to the public route contract.
DemoPrivateWebPage ccrouterBuildDemoPrivateWebPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = DemoPrivateWebRoute.definition.codec.decode(arguments);
  return DemoPrivateWebPage(decoded.request);
}
