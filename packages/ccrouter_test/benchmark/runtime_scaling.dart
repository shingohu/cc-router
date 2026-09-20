import 'dart:convert';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_test/ccrouter_test.dart';

const _lifecycleSamples = 20;
const _navigationSamples = 100;

final class _BenchmarkArguments {
  const _BenchmarkArguments(this.id);

  final String id;
}

final class _BenchmarkCodec implements CCRouteCodec<_BenchmarkArguments> {
  const _BenchmarkCodec();

  @override
  _BenchmarkArguments decode(CCEncodedRouteArguments input) =>
      _BenchmarkArguments(input.path['id']!);

  @override
  CCEncodedRouteArguments encode(_BenchmarkArguments arguments) =>
      CCEncodedRouteArguments(path: {'id': arguments.id});
}

final class _BenchmarkRegistrar implements CCComponentRegistrar {
  const _BenchmarkRegistrar(this.routes);

  final List<CCRouteDefinition<_BenchmarkArguments, void>> routes;

  @override
  void register(CCRegistry registry) {
    for (final route in routes) {
      registry.registerRoute(route);
    }
  }
}

Future<void> main() async {
  for (final routeCount in const [10, 100, 1000]) {
    final routes = _routes(routeCount);
    await _warmUp(routes);
    final initializeMicros = <int>[];
    final disposeMicros = <int>[];
    for (var sample = 0; sample < _lifecycleSamples; sample++) {
      final host = _host(routes);
      final initializeWatch = Stopwatch()..start();
      host.initialize();
      initializeWatch.stop();
      initializeMicros.add(initializeWatch.elapsedMicroseconds);

      final disposeWatch = Stopwatch()..start();
      await host.dispose();
      disposeWatch.stop();
      disposeMicros.add(disposeWatch.elapsedMicroseconds);
    }

    final host = _host(routes)..initialize();
    final runtime = host.runtime;
    final target = Uri.parse('/benchmark/${routeCount - 1}/42');
    await runtime.openRoute(target, mode: CCDeepLinkOpenMode.go);
    final navigationMicros = <int>[];
    for (var sample = 0; sample < _navigationSamples; sample++) {
      final watch = Stopwatch()..start();
      await runtime.openRoute(target, mode: CCDeepLinkOpenMode.go);
      watch.stop();
      navigationMicros.add(watch.elapsedMicroseconds);
    }
    await host.dispose();

    print(
      jsonEncode({
        'scenario': 'runtime-scaling',
        'routes': routeCount,
        'lifecycleSamples': _lifecycleSamples,
        'navigationSamples': _navigationSamples,
        'initializeUsP50': _percentile(initializeMicros, 0.50),
        'initializeUsP95': _percentile(initializeMicros, 0.95),
        'dynamicOpenUsP50': _percentile(navigationMicros, 0.50),
        'dynamicOpenUsP95': _percentile(navigationMicros, 0.95),
        'disposeUsP50': _percentile(disposeMicros, 0.50),
        'disposeUsP95': _percentile(disposeMicros, 0.95),
      }),
    );
  }
}

Future<void> _warmUp(
  List<CCRouteDefinition<_BenchmarkArguments, void>> routes,
) async {
  final host = _host(routes)..initialize();
  await host.runtime.openRoute(
    Uri.parse('/benchmark/${routes.length - 1}/0'),
    mode: CCDeepLinkOpenMode.go,
  );
  await host.dispose();
}

CCRouterTestHost _host(
  List<CCRouteDefinition<_BenchmarkArguments, void>> routes,
) => CCRouterTestHost(
  navigationAdapter: CCMemoryNavigationAdapter(),
  components: [
    CCComponentManifest(
      id: 'benchmark',
      version: '1.0.0',
      registrar: _BenchmarkRegistrar(routes),
    ),
  ],
);

List<CCRouteDefinition<_BenchmarkArguments, void>> _routes(int count) => [
  for (var index = 0; index < count; index++)
    CCRouteDefinition<_BenchmarkArguments, void>(
      routeId: 'benchmark.route.$index',
      patterns: [CCPathPattern('/benchmark/$index/:id', primary: true)],
      codec: const _BenchmarkCodec(),
    ),
];

int _percentile(List<int> values, double percentile) {
  final sorted = [...values]..sort();
  final index = (sorted.length * percentile).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}
