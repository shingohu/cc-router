// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteBindingGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_test/src/multiple_extra_fixture.dart' as route_page;
import 'package:ccrouter_test/src/ccrouter_generated/route/multiple_extra_fixture.route.g.dart'
    as route_contract;
import 'package:ccrouter_test/src/ccrouter_generated/contract/multiple_extra_contract_fixture.route.contract.g.dart'
    as route_contract_0;

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.GeneratedMultiExtraPage ccrouterBuildGeneratedMultiExtraPageRoute(
  CCRouteCodecValues arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeGeneratedMultiExtraPageRoute()
      .codec
      .decode(arguments);
  return route_page.GeneratedMultiExtraPage(
    id: decoded.id,
    tab: decoded.tab,
    snapshot: decoded.snapshot,
    revision: decoded.revision,
    enabled: decoded.enabled,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.GeneratedOptionalExtrasPage
ccrouterBuildGeneratedOptionalExtrasPageRoute(CCRouteCodecValues arguments) {
  final decoded = route_contract
      .ccrouterDescribeGeneratedOptionalExtrasPageRoute()
      .codec
      .decode(arguments);
  return route_page.GeneratedOptionalExtrasPage(
    snapshot: decoded.snapshot,
    revision: decoded.revision,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.GeneratedExtrasChildPage ccrouterBuildGeneratedExtrasChildPageRoute(
  CCRouteCodecValues _,
) => route_page.GeneratedExtrasChildPage();

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.GeneratedDefaultExtrasPage
ccrouterBuildGeneratedDefaultExtrasPageRoute(CCRouteCodecValues arguments) {
  final decoded = route_contract
      .ccrouterDescribeGeneratedDefaultExtrasPageRoute()
      .codec
      .decode(arguments);
  return route_page.GeneratedDefaultExtrasPage(
    label: decoded.label,
    revision: decoded.revision,
  );
}

/// Package-internal bridge used by the generated component route index.
///
/// Registration retains the external Pure Dart contract as the single source
/// of route identity, parameters, and navigation policy.
void ccrouterRegisterGeneratedContractExtrasPageRoute(CCRegistry registry) =>
    registry.registerRoute(
      route_contract_0.GeneratedMultiExtrasRouteContractBinding.definition,
    );

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic>
ccrouterDescribeGeneratedContractExtrasPageRoute() =>
    route_contract_0.GeneratedMultiExtrasRouteContractBinding.definition;

/// Package-internal page factory bound to the public route contract.
route_page.GeneratedContractExtrasPage
ccrouterBuildGeneratedContractExtrasPageRoute(CCRouteCodecValues arguments) {
  final decoded = route_contract_0
      .GeneratedMultiExtrasRouteContractBinding
      .definition
      .codec
      .decode(arguments);
  return route_page.GeneratedContractExtrasPage(
    items: decoded.items,
    label: decoded.label,
  );
}
