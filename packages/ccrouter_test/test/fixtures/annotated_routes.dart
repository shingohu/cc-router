import 'package:ccrouter/ccrouter.dart';
import 'route_types.dart' as types;

const fixtureComponent = CCComponent(
  id: CCComponentId('fixture'),
  version: '1.0.0',
);

@CCComponentContribution(id: 'fixture.policies')
void registerFixturePolicies(CCRegistry registry) {
  registry.registerRouteInterceptor('fixture.auth', const FixtureProceed());
}

final class FixtureProceed implements CCNavigationInterceptor {
  const FixtureProceed();

  @override
  CCNavigationInterception intercept(CCNavigationInterceptorContext context) =>
      const CCNavigationProceed();
}

enum DetailTab { summary, items }

final class Snapshot {
  const Snapshot(this.label);
  final String label;
}

@CCRoute<String>(
  id: 'fixture.detail',
  patterns: [
    CCPathPattern('/detail/:id', primary: true, constraints: {'id': r'\d+'}),
    CCPathPattern('/legacy/:id'),
    CCUriPattern('sample://detail/:id'),
    CCRegexPattern(r'/old/(?<id>\d+)'),
  ],
  deepLink: CCDeepLinkPolicy.enabled,
  presentation: CCPagePresentation(
    transition: CCPageTransitionType.slideFromBottom,
    opaque: false,
  ),
  placement: CCRoutePlacement(hostId: 'default'),
  interceptors: ['fixture.auth'],
  description: 'A typed detail route.\nIncludes safe defaults.',
)
final class DetailPage {
  const DetailPage({
    required this.id,
    @CCQueryParam(name: 'text') this.search,
    @CCQueryParam() this.tab = DetailTab.summary,
    @CCQueryParam() this.enabled = false,
    @CCQueryParam() this.ratio = 1.0,
    @CCExtraParam() this.snapshot,
  });

  /// Stable fixture identity shown in generated route documentation.
  final int id;

  /// Optional filter whose wire name differs from this field name.
  final String? search;
  final DetailTab tab;
  final bool enabled;
  final double ratio;
  final Snapshot? snapshot;
}

@CCRoute<void>(id: 'fixture.internal', pattern: CCPathPattern('/internal'))
final class InternalPage {
  const InternalPage();
}

@CCRoute<int>(
  id: 'fixture.positional',
  patterns: [CCPathPattern('/position/:value', primary: true)],
)
final class PositionalPage {
  const PositionalPage(this.value, [@CCQueryParam() this.input = 'default']);
  final String value;
  final String input;
}

@CCRoute<bool>(
  id: 'fixture.extra',
  patterns: [CCPathPattern('/extra', primary: true)],
)
final class ExtraPage {
  const ExtraPage({@CCExtraParam() required this.snapshot});
  final Snapshot snapshot;
}

@CCRoute<types.Result>(
  id: 'fixture.prefixed',
  patterns: [CCPathPattern('/prefixed', primary: true)],
)
final class PrefixedPage {
  const PrefixedPage({
    @CCQueryParam() this.mode = types.Mode.normal,
    @CCExtraParam() this.payload,
  });

  final types.Mode mode;
  final types.Payload? payload;
}
