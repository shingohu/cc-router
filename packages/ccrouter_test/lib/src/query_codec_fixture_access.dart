import 'package:ccrouter/ccrouter.dart';

export 'query_codec_fixture.dart';

import 'query_codec_fixture.dart';
import 'ccrouter_generated/query_codec_fixture.route.g.dart' as route_contract;
import 'ccrouter_generated/query_codec_fixture.route_binding.g.dart'
    as route_binding;

/// Exposes the generated codec only to the dedicated test package.
CCRouteCodec<dynamic> get queryCodecFixtureCodec =>
    route_contract.ccrouterDescribeQueryCodecFixturePageRoute().codec;

/// Creates generated typed arguments without exposing their private class.
Object queryCodecFixtureArguments({
  required List<String> tags,
  required Set<int> ids,
  List<String> labels = const [],
  List<QueryCodecFixtureState>? states,
  QueryCodecFixtureFilter? filter,
}) => const route_contract.CCGeneratedQueryCodecFixturePageRouteFactory()(
  tags: tags,
  ids: ids,
  labels: labels,
  states: states,
  filter: filter,
).arguments;

/// Builds the fixture page through the generated encoded boundary.
QueryCodecFixturePage buildQueryCodecFixturePage(Object arguments) =>
    route_binding.ccrouterBuildQueryCodecFixturePageRoute(
      queryCodecFixtureCodec.encode(arguments),
    );
