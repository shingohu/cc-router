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

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoPublicWebPageRoute() =>
    DemoPublicWebRoute.definition;

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

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoPrivateWebPageRoute() =>
    DemoPrivateWebRoute.definition;

/// Package-internal page factory bound to the public route contract.
DemoPrivateWebPage ccrouterBuildDemoPrivateWebPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = DemoPrivateWebRoute.definition.codec.decode(arguments);
  return DemoPrivateWebPage(decoded.request);
}
