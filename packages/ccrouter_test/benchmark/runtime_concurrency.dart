import 'dart:convert';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_test/ccrouter_test.dart';

const _cycles = 10;
const _concurrentPushes = 100;

final class _StressArguments {
  const _StressArguments(this.id);

  final String id;
}

final class _StressIntent<R> implements CCRouteIntent<R> {
  const _StressIntent(this.routeId, this.arguments);

  @override
  final String routeId;

  @override
  final Object arguments;
}

final class _StressCodec implements CCRouteCodec<_StressArguments> {
  const _StressCodec();

  @override
  _StressArguments decode(CCEncodedRouteArguments input) =>
      _StressArguments(input.path['id']!);

  @override
  CCEncodedRouteArguments encode(_StressArguments arguments) =>
      CCEncodedRouteArguments(path: {'id': arguments.id});
}

final class _StressRegistrar implements CCComponentRegistrar {
  const _StressRegistrar(this.route);

  final CCRouteDefinition<_StressArguments, String> route;

  @override
  void register(CCRegistry registry) => registry.registerRoute(route);
}

Future<void> main() async {
  final adapter = CCMemoryNavigationAdapter();
  final host = CCRouterTestHost(
    navigationAdapter: adapter,
    components: [
      CCComponentManifest(
        id: 'benchmark',
        version: '1.0.0',
        registrar: _StressRegistrar(_route),
      ),
    ],
  );
  host.initialize();
  await host.runtime.goRoute(
    const _StressIntent<void>('benchmark.detail', _StressArguments('root')),
  );

  final samples = <int>[];
  var peakEntries = host.runtime.activeRouteEntries.length;
  var peakPending = host.runtime.pendingNavigations.length;
  for (var cycle = 0; cycle < _cycles; cycle++) {
    final watch = Stopwatch()..start();
    final futures = [
      for (var index = 0; index < _concurrentPushes; index++)
        host.runtime.pushRoute<String>(
          _StressIntent<String>(
            'benchmark.detail',
            _StressArguments('$cycle-$index'),
          ),
        ),
    ];
    await Future<void>.delayed(Duration.zero);
    peakEntries = _max(peakEntries, host.runtime.activeRouteEntries.length);
    peakPending = _max(peakPending, host.runtime.pendingNavigations.length);
    for (var index = 0; index < futures.length; index++) {
      host.runtime.popRoute(result: 'ok:$cycle-$index');
    }
    await Future.wait(futures);
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
    if (host.runtime.activeRouteEntries.length != 1 ||
        host.runtime.pendingNavigations.isNotEmpty ||
        adapter.stack.length != 1) {
      throw StateError('Runtime retained state after stress cycle $cycle.');
    }
  }

  final result = {
    'scenario': 'runtime-concurrency-and-reclamation',
    'cycles': _cycles,
    'concurrentPushesPerCycle': _concurrentPushes,
    'cycleUsP50': _percentile(samples, 0.50),
    'cycleUsP95': _percentile(samples, 0.95),
    'peakActiveEntries': peakEntries,
    'peakPendingNavigations': peakPending,
    'finalActiveEntries': host.runtime.activeRouteEntries.length,
    'finalPendingNavigations': host.runtime.pendingNavigations.length,
    'finalAdapterEntries': adapter.stack.length,
  };
  await host.dispose();
  print(jsonEncode(result));
}

final _route = CCRouteDefinition<_StressArguments, String>(
  routeId: 'benchmark.detail',
  patterns: [CCPathPattern('/benchmark/:id', primary: true)],
  codec: const _StressCodec(),
);

int _max(int first, int second) => first > second ? first : second;

int _percentile(List<int> values, double percentile) {
  final sorted = [...values]..sort();
  final index = (sorted.length * percentile).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}
