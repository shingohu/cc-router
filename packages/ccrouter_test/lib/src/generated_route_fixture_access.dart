import 'package:ccrouter/ccrouter.dart';

export 'generated_route_fixture.dart';

import 'generated_route_fixture.dart';
import 'ccrouter_generated/generated_route_fixture.route.g.dart'
    as route_contract;
import 'ccrouter_generated/generated_route_fixture.route_binding.g.dart'
    as route_binding;

/// Generated detail definition used by runtime regression tests.
CCRouteDefinition<dynamic, dynamic> get detailDefinition =>
    route_contract.ccrouterDescribeGeneratedDetailPageRoute();

/// Generated detail codec used by boundary conversion tests.
CCRouteCodec<dynamic> get detailCodec => detailDefinition.codec;

/// Builds the detail page through the encoded generated binding boundary.
GeneratedDetailPage buildDetailPage(dynamic arguments) => route_binding
    .ccrouterBuildGeneratedDetailPageRoute(detailCodec.encode(arguments));

/// Creates a typed detail Intent without exposing generated private arguments.
CCRouteIntent<String> detailIntent({
  required int id,
  String? search,
  GeneratedDetailTab tab = GeneratedDetailTab.summary,
  bool enabled = false,
  double ratio = 1.0,
  GeneratedSnapshot? snapshot,
}) => const route_contract.CCGeneratedGeneratedDetailPageRouteFactory()(
  id: id,
  search: search,
  tab: tab,
  enabled: enabled,
  ratio: ratio,
  snapshot: snapshot,
);

/// Creates generated detail arguments for direct codec tests.
dynamic detailArguments({required int id, double ratio = 1.0}) =>
    const route_contract.CCGeneratedGeneratedDetailPageRouteFactory()(
      id: id,
      ratio: ratio,
    ).arguments;

/// Reads the ID from an intentionally opaque generated arguments object.
int detailArgumentId(Object? arguments) => (arguments as dynamic).id as int;

/// Creates the parameterless internal fixture Intent.
CCRouteIntent<void> internalIntent() =>
    const route_contract.CCGeneratedGeneratedInternalPageRouteFactory()();

/// Generated positional codec used by constructor binding tests.
CCRouteCodec<dynamic> get positionalCodec =>
    route_contract.ccrouterDescribeGeneratedPositionalPageRoute().codec;

/// Builds the positional page through its generated encoded boundary.
GeneratedPositionalPage buildPositionalPage(dynamic arguments) =>
    route_binding.ccrouterBuildGeneratedPositionalPageRoute(
      positionalCodec.encode(arguments),
    );

/// Generated Extra codec used by object-identity tests.
CCRouteCodec<dynamic> get extraCodec =>
    route_contract.ccrouterDescribeGeneratedExtraPageRoute().codec;

/// Builds the Extra page through its generated encoded boundary.
GeneratedExtraPage buildExtraPage(dynamic arguments) => route_binding
    .ccrouterBuildGeneratedExtraPageRoute(extraCodec.encode(arguments));

/// Generated prefixed-type codec used by import-boundary tests.
CCRouteCodec<dynamic> get prefixedCodec =>
    route_contract.ccrouterDescribeGeneratedPrefixedPageRoute().codec;

/// Builds the prefixed page through its generated encoded boundary.
GeneratedPrefixedPage buildPrefixedPage(dynamic arguments) => route_binding
    .ccrouterBuildGeneratedPrefixedPageRoute(prefixedCodec.encode(arguments));

/// Creates an Intent containing imported enum, Extra, and result types.
CCRouteIntent<GeneratedRouteResult> prefixedIntent({
  GeneratedRouteMode mode = GeneratedRouteMode.normal,
  GeneratedRoutePayload? payload,
}) => const route_contract.CCGeneratedGeneratedPrefixedPageRouteFactory()(
  mode: mode,
  payload: payload,
);
