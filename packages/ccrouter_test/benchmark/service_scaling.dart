import 'dart:convert';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';

// Benchmark support intentionally consumes Core's visible-for-testing boundary.
// ignore_for_file: invalid_use_of_visible_for_testing_member

const _lifecycleSamples = 20;
const _lookupSamples = 1000;
const _invocationSamples = 1000;
const _readinessSamples = 100;
const _serviceContract = CCServiceToken<_BenchmarkService>('benchmark.service');
const _readyServiceContract = CCServiceToken<_ReadyBenchmarkService>(
  'benchmark.ready-service',
);
const _readyServiceKey = CCServiceKey<_ReadyBenchmarkService>('factory-ready');

final class _BenchmarkService implements CCDisposable {
  _BenchmarkService(this.index) {
    liveInstances++;
  }

  static int liveInstances = 0;

  final int index;

  @override
  void dispose() {
    liveInstances--;
  }
}

final class _ReadyBenchmarkService implements CCDisposable {
  _ReadyBenchmarkService() {
    liveInstances++;
  }

  static int liveInstances = 0;

  bool ready = false;

  @override
  void dispose() {
    liveInstances--;
  }
}

final class _BenchmarkRegistrar implements CCComponentRegistrar {
  const _BenchmarkRegistrar(this.providerCount);

  final int providerCount;

  @override
  void register(CCRegistry registry) {
    for (var index = 0; index < providerCount; index++) {
      registry.registerService<_BenchmarkService>(
        CCServiceProvider(
          contract: _serviceContract,
          key: _serviceKey(index),
          factory: (_) => _BenchmarkService(index),
        ),
      );
    }
    registry.registerService<_ReadyBenchmarkService>(
      CCServiceProvider(
        contract: _readyServiceContract,
        key: _readyServiceKey,
        creationPolicy: CCServiceCreationPolicy.factory,
        factory: (_) => _ReadyBenchmarkService(),
        initializer: (service, _) async {
          service.ready = true;
        },
      ),
    );
  }
}

Future<void> main() async {
  for (final providerCount in const [10, 100, 1000]) {
    await _warmUp(providerCount);
    final assembleInitializeMicros = <int>[];
    final disposeMicros = <int>[];
    for (var sample = 0; sample < _lifecycleSamples; sample++) {
      final initializeWatch = Stopwatch()..start();
      final runtime = _runtime(providerCount);
      runtime.initialize();
      initializeWatch.stop();
      assembleInitializeMicros.add(initializeWatch.elapsedMicroseconds);

      _resolveAllSingletons(runtime, providerCount);
      await runtime.serviceAsync<_ReadyBenchmarkService>(
        contract: _readyServiceContract,
        key: _readyServiceKey,
      );
      final disposeWatch = Stopwatch()..start();
      await runtime.dispose();
      disposeWatch.stop();
      disposeMicros.add(disposeWatch.elapsedMicroseconds);
      _verifyNoLiveInstances();
    }

    final runtime = _runtime(providerCount)..initialize();
    _resolveAllSingletons(runtime, providerCount);
    final targetKey = _serviceKey(providerCount - 1);

    final lookupMicros = <int>[];
    for (var sample = 0; sample < _lookupSamples; sample++) {
      final watch = Stopwatch()..start();
      final service = runtime.service<_BenchmarkService>(
        contract: _serviceContract,
        key: targetKey,
      );
      watch.stop();
      if (service.index != providerCount - 1) {
        throw StateError('Resolved the wrong benchmark Service.');
      }
      lookupMicros.add(watch.elapsedMicroseconds);
    }

    final invocationMicros = <int>[];
    for (var sample = 0; sample < _invocationSamples; sample++) {
      final watch = Stopwatch()..start();
      final result = runtime.invokeServiceSync<_BenchmarkService, int>(
        contract: _serviceContract,
        key: targetKey,
        methodId: 'read',
        callerComponentId: 'benchmark-consumer',
        call: (service, _) => service.index,
      );
      watch.stop();
      if (result != providerCount - 1) {
        throw StateError('Service invocation returned the wrong result.');
      }
      invocationMicros.add(watch.elapsedMicroseconds);
    }

    final readinessMicros = <int>[];
    for (var sample = 0; sample < _readinessSamples; sample++) {
      final watch = Stopwatch()..start();
      final service = await runtime.serviceAsync<_ReadyBenchmarkService>(
        contract: _readyServiceContract,
        key: _readyServiceKey,
      );
      watch.stop();
      if (!service.ready) {
        throw StateError('Factory Service completed before readiness.');
      }
      readinessMicros.add(watch.elapsedMicroseconds);
    }
    await runtime.dispose();
    _verifyNoLiveInstances();

    print(
      jsonEncode({
        'scenario': 'service-scaling',
        'providers': providerCount,
        'lifecycleSamples': _lifecycleSamples,
        'lookupSamples': _lookupSamples,
        'invocationSamples': _invocationSamples,
        'readinessSamples': _readinessSamples,
        'assembleInitializeUsP50': _percentile(assembleInitializeMicros, 0.50),
        'assembleInitializeUsP95': _percentile(assembleInitializeMicros, 0.95),
        'singletonLookupUsP50': _percentile(lookupMicros, 0.50),
        'singletonLookupUsP95': _percentile(lookupMicros, 0.95),
        'invokeSyncUsP50': _percentile(invocationMicros, 0.50),
        'invokeSyncUsP95': _percentile(invocationMicros, 0.95),
        'factoryReadinessUsP50': _percentile(readinessMicros, 0.50),
        'factoryReadinessUsP95': _percentile(readinessMicros, 0.95),
        'disposeUsP50': _percentile(disposeMicros, 0.50),
        'disposeUsP95': _percentile(disposeMicros, 0.95),
      }),
    );
  }
}

Future<void> _warmUp(int providerCount) async {
  final runtime = _runtime(providerCount)..initialize();
  _resolveAllSingletons(runtime, providerCount);
  runtime.invokeServiceSync<_BenchmarkService, int>(
    contract: _serviceContract,
    key: _serviceKey(providerCount - 1),
    methodId: 'read',
    callerComponentId: 'benchmark-consumer',
    call: (service, _) => service.index,
  );
  await runtime.serviceAsync<_ReadyBenchmarkService>(
    contract: _readyServiceContract,
    key: _readyServiceKey,
  );
  await runtime.dispose();
  _verifyNoLiveInstances();
}

CCRouterRuntime _runtime(int providerCount) => CCRouterRuntime.forTesting(
  traceCapacity: _invocationSamples,
  components: [
    CCComponentManifest(
      id: 'benchmark',
      version: '1.0.0',
      registrar: _BenchmarkRegistrar(providerCount),
    ),
  ],
);

void _resolveAllSingletons(CCRouterRuntime runtime, int providerCount) {
  for (var index = 0; index < providerCount; index++) {
    runtime.service<_BenchmarkService>(
      contract: _serviceContract,
      key: _serviceKey(index),
    );
  }
}

CCServiceKey<_BenchmarkService> _serviceKey(int index) =>
    CCServiceKey<_BenchmarkService>('provider-$index');

void _verifyNoLiveInstances() {
  if (_BenchmarkService.liveInstances != 0 ||
      _ReadyBenchmarkService.liveInstances != 0) {
    throw StateError(
      'Service instances leaked: singleton=${_BenchmarkService.liveInstances}, '
      'factory=${_ReadyBenchmarkService.liveInstances}.',
    );
  }
}

int _percentile(List<int> values, double percentile) {
  final sorted = [...values]..sort();
  final index = (sorted.length * percentile).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}
