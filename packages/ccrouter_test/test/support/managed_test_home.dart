import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/widgets.dart';

/// A real Managed root, deliberately without a Route Service.
CCRouteDefinition<String, String> testHomeDefinition({
  CCRoutePlacement placement = const CCRoutePlacement.root(),
}) => CCRouteDefinition(
  routeId: 'fixture.home',
  patterns: [const CCPathPattern('/', primary: true)],
  codec: const _HomeCodec(),
  placement: placement,
);

final class _HomeCodec implements CCRouteCodec<String> {
  const _HomeCodec();
  @override
  String decode(CCRouteCodecValues input) => 'home';
  @override
  CCRouteCodecValues encode(String arguments) => CCRouteCodecValues();
}

/// Baseline-only Host for foreign Navigator and diagnostics regression tests.
final class TestHomeRegistrar implements CCComponentRegistrar {
  const TestHomeRegistrar();
  @override
  void register(CCRegistry registry) =>
      registry.registerRoute(testHomeDefinition());
}

/// Composes a baseline route with the scenario's real registration.
final class WithTestHome implements CCComponentRegistrar {
  const WithTestHome(
    this.delegate, {
    this.placement = const CCRoutePlacement.root(),
  });
  final CCComponentRegistrar delegate;
  final CCRoutePlacement placement;
  @override
  void register(CCRegistry registry) {
    registry.registerRoute(testHomeDefinition(placement: placement));
    delegate.register(registry);
  }
}

CCFlutterRouteDestination testHomeDestination({
  CCRoutePlacement placement = const CCRoutePlacement.root(),
}) => CCFlutterRouteDestination.fromDefinition(
  definition: testHomeDefinition(placement: placement),
  builder: (_) => const Text('home'),
);
