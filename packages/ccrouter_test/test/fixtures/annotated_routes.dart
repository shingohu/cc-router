import 'package:ccrouter/ccrouter.dart';
import 'route_types.dart' as types;

part 'annotated_routes.ccroute.g.dart';

const fixtureComponent = CCComponentDescriptor(id: 'fixture', version: '1.0.0');

@CCComponent(fixtureComponent)
final class FixtureComponentRegistrar implements CCComponentRegistrar {
  const FixtureComponentRegistrar();

  @override
  void register(CCRegistry registry) {
    DetailPageRoute.register(registry);
    PositionalPageRoute.register(registry);
    ExtraPageRoute.register(registry);
    PrefixedPageRoute.register(registry);
    _InternalPageRoute.register(registry);
    registry.registerRouteInterceptor('fixture.auth', const FixtureProceed());
  }
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
  component: fixtureComponent,
  id: 'fixture.detail',
  patterns: [
    CCPathPattern('/detail/:id', primary: true, constraints: {'id': r'\d+'}),
    CCPathPattern('/legacy/:id'),
    CCUriPattern('sample://detail/:id'),
    CCRegexPattern(r'/old/(?<id>\d+)'),
  ],
  visibility: CCRouteVisibility.exported,
  visibleTo: {'home'},
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

@CCRoute<void>(
  component: fixtureComponent,
  id: 'fixture.internal',
  patterns: [CCPathPattern('/internal', primary: true)],
)
final class _InternalPage {
  const _InternalPage();
}

CCRouteIntent<void> internalIntent() => _InternalPageRoute.intent();
void registerInternal(CCRegistry registry) =>
    _InternalPageRoute.register(registry);

@CCRoute<int>(
  component: fixtureComponent,
  id: 'fixture.positional',
  patterns: [CCPathPattern('/position/:value', primary: true)],
  visibility: CCRouteVisibility.exported,
)
final class PositionalPage {
  const PositionalPage(this.value, [@CCQueryParam() this.input = 'default']);
  final String value;
  final String input;
}

@CCRoute<bool>(
  component: fixtureComponent,
  id: 'fixture.extra',
  patterns: [CCPathPattern('/extra', primary: true)],
  visibility: CCRouteVisibility.exported,
)
final class ExtraPage {
  const ExtraPage({@CCExtraParam() required this.snapshot});
  final Snapshot snapshot;
}

@CCRoute<types.Result>(
  component: fixtureComponent,
  id: 'fixture.prefixed',
  patterns: [CCPathPattern('/prefixed', primary: true)],
  visibility: CCRouteVisibility.exported,
)
final class PrefixedPage {
  const PrefixedPage({
    @CCQueryParam() this.mode = types.Mode.normal,
    @CCExtraParam() this.payload,
  });

  final types.Mode mode;
  final types.Payload? payload;
}
