import 'package:ccrouter/ccrouter.dart';

export 'generated_route_types.dart';

import 'generated_route_types.dart';
import 'ccrouter_generated/route/generated_route_fixture.route.g.dart'
    as route_contract;

/// Component identity for standalone generated route regression tests.
const generatedRouteFixtureComponent = CCComponentDescriptor(
  id: 'generated_route_fixture',
  version: '1.0.0',
);

/// Registers generated route fixtures in isolated Runtime tests.
final class GeneratedRouteFixtureRegistrar implements CCComponentRegistrar {
  /// Creates the stateless fixture Registrar.
  const GeneratedRouteFixtureRegistrar();

  /// Registers fixed policies; generated route bridges are added after build.
  @override
  void register(CCRegistry registry) {
    route_contract.ccrouterRegisterGeneratedDetailPageRoute(registry);
    route_contract.ccrouterRegisterGeneratedInternalPageRoute(registry);
    route_contract.ccrouterRegisterGeneratedPositionalPageRoute(registry);
    route_contract.ccrouterRegisterGeneratedExtraPageRoute(registry);
    route_contract.ccrouterRegisterGeneratedPrefixedPageRoute(registry);
    registry.registerRouteInterceptor(
      'generated_route_fixture.auth',
      const GeneratedRouteProceed(),
    );
  }
}

/// Deterministic interceptor used by the generated fixture route.
final class GeneratedRouteProceed implements CCNavigationInterceptor {
  /// Creates the stateless proceed policy.
  const GeneratedRouteProceed();

  /// Allows every fixture request.
  @override
  CCNavigationInterception intercept(CCNavigationInterceptorContext context) =>
      const CCNavigationProceed();
}

/// Destination covering aliases, scalar codecs, defaults, and Extra values.
@CCRoute<String>(
  component: generatedRouteFixtureComponent,
  id: 'generated_route_fixture.detail',
  patterns: [
    CCPathPattern(
      '/generated/detail/:id',
      primary: true,
      constraints: {'id': r'\d+'},
    ),
    CCPathPattern('/generated/legacy/:id'),
    CCUriPattern('generated://detail/:id'),
    CCRegexPattern(r'/generated/old/(?<id>\d+)'),
  ],
  deepLink: CCDeepLinkPolicy.enabled,
  presentation: CCPagePresentation(
    transition: CCPageTransitionType.slideFromBottom,
    opaque: false,
  ),
  placement: CCRoutePlacement(hostId: 'default'),
  interceptors: ['generated_route_fixture.auth'],
  description: 'Generated route fixture with safe defaults.',
)
final class GeneratedDetailPage {
  /// Creates a detail destination from generated typed arguments.
  const GeneratedDetailPage({
    required this.id,
    @CCQueryParam(name: 'text') this.search,
    @CCQueryParam() this.tab = GeneratedDetailTab.summary,
    @CCQueryParam() this.enabled = false,
    @CCQueryParam() this.ratio = 1.0,
    @CCExtraParam() this.snapshot,
  });

  /// Stable fixture identity.
  final int id;

  /// Optional search text.
  final String? search;

  /// Selected tab.
  final GeneratedDetailTab tab;

  /// Boolean scalar codec probe.
  final bool enabled;

  /// Finite double codec probe.
  final double ratio;

  /// Optional in-memory snapshot.
  final GeneratedSnapshot? snapshot;
}

/// Parameterless route used to verify callable factory generation.
@CCRoute<void>(
  component: generatedRouteFixtureComponent,
  id: 'generated_route_fixture.internal',
  pattern: CCPathPattern('/generated/internal'),
)
final class GeneratedInternalPage {
  /// Creates the parameterless fixture page.
  const GeneratedInternalPage();
}

/// Positional-constructor route used by generated page bindings.
@CCRoute<int>(
  component: generatedRouteFixtureComponent,
  id: 'generated_route_fixture.positional',
  pattern: CCPathPattern('/generated/position/:value'),
)
final class GeneratedPositionalPage {
  /// Creates the positional fixture page.
  const GeneratedPositionalPage(
    this.value, [
    @CCQueryParam() this.input = 'default',
  ]);

  /// Path value.
  final String value;

  /// Optional positional query value.
  final String input;
}

/// Route requiring a typed Extra value.
@CCRoute<bool>(
  component: generatedRouteFixtureComponent,
  id: 'generated_route_fixture.extra',
  pattern: CCPathPattern('/generated/extra'),
)
final class GeneratedExtraPage {
  /// Creates the page with its required in-memory payload.
  const GeneratedExtraPage({@CCExtraParam() required this.snapshot});

  /// Required snapshot retained by identity.
  final GeneratedSnapshot snapshot;
}

/// Route using imported enum, Extra, and result types.
@CCRoute<GeneratedRouteResult>(
  component: generatedRouteFixtureComponent,
  id: 'generated_route_fixture.prefixed',
  pattern: CCPathPattern('/generated/prefixed'),
)
final class GeneratedPrefixedPage {
  /// Creates the page with imported contract-facing values.
  const GeneratedPrefixedPage({
    @CCQueryParam() this.mode = GeneratedRouteMode.normal,
    @CCExtraParam() this.payload,
  });

  /// Imported enum value.
  final GeneratedRouteMode mode;

  /// Optional imported payload.
  final GeneratedRoutePayload? payload;
}
