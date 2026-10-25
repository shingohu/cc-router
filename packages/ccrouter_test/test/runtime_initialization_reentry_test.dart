import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'reentrant_lifecycle_regression_test.dart' show Registrar, Resource;

class Plain implements CCNavigationAdapter {
  Plain({this.onInitialize});
  final void Function()? onInitialize;
  int disposals = 0;
  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {
    onInitialize?.call();
  }

  @override
  Future<Object?> navigate(CCNavigationRequest request) async => null;
  @override
  Future<bool> maybePop({Object? result}) async => false;
  @override
  void pop({Object? result}) {}
  @override
  bool canPop() => false;
  @override
  void dispose() {
    disposals++;
  }
}

class SharedSource extends Plain implements CCNavigationBackendEventSource {
  SharedSource(this.externalListeners, this.onSubscribe);
  final Set<CCNavigationBackendEventListener> externalListeners;
  final void Function() onSubscribe;
  int removals = 0;
  @override
  void dispose() {
    externalListeners.clear();
    super.dispose();
  }

  @override
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) {
    externalListeners.add(listener);
    onSubscribe();
    return () {
      removals++;
      externalListeners.remove(listener);
    };
  }
}

class PhaseAdapter extends Plain
    implements
        CCNavigationAdapterCapabilitySource,
        CCNavigationPopGuardBinding,
        CCNavigationBackendEventSource,
        CCNavigationPredictiveBackSourceProvider,
        CCNavigationPredictiveBackSource,
        CCNavigationBackendSnapshotSource {
  PhaseAdapter(this.stage, this.stop);
  final String stage;
  final void Function() stop;
  final listeners = <CCNavigationBackendEventListener>{};
  void phase(String value) {
    if (stage == value) stop();
  }

  @override
  CCNavigationAdapterCapabilities get capabilities {
    phase('capabilities');
    return const CCNavigationAdapterCapabilities(supportsPredictiveBack: true);
  }

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) => phase('initialize');
  @override
  void bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator) {
    if (evaluator != null) phase('guard');
  }

  @override
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) {
    listeners.add(listener);
    phase('backend');
    return () => listeners.remove(listener);
  }

  @override
  CCNavigationPredictiveBackSource? get predictiveBackSource {
    phase('predictiveProvider');
    return this;
  }

  @override
  void Function() addPredictiveBackListener(
    CCPredictiveBackEventListener listener,
  ) {
    phase('predictive');
    return () {};
  }

  @override
  List<CCInitialBackendEntrySnapshot> readInitialBackendEntries() {
    phase('snapshot');
    return const [];
  }

  @override
  void dispose() {
    listeners.clear();
    super.dispose();
  }
}

void main() {
  test('initialization reentry cannot resurrect a disposed Runtime', () async {
    late CCRouterRuntime runtime;
    Future<void>? stopping;
    final adapter = Plain(onInitialize: () => stopping = runtime.dispose());
    final resource = Resource();
    runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        CCComponentManifest(
          id: 'probe',
          version: '1.0.0',
          registrar: Registrar(
            extra: (r) => r.registerService<Resource>(
              CCServiceProvider(
                scope: CCServiceScope.session,
                factory: (_) => resource,
              ),
            ),
          ),
        ),
      ],
    );
    Object? error;
    try {
      runtime.initialize();
    } catch (e) {
      error = e;
    }
    await stopping;
    Object? sessionError;
    try {
      runtime.openSession(accountId: 'after-dispose');
      runtime.service<Resource>();
    } catch (e) {
      sessionError = e;
    }
    await runtime.dispose();
    // Release any erroneously acquired Scope so this review probe cannot leak.
    if (runtime.session != null) await runtime.closeSession();
    expect(error, isA<CCRouteCancelledError>());
    expect(sessionError, isA<CCRouterNotInitializedError>());
    expect(runtime.session, isNull);
    expect(runtime.isInitialized, isFalse);
  });
  test(
    'compliant child disposal releases its listeners during initial subscription reentry',
    () {
      late CCMultiHostNavigationAdapter aggregate;
      final external = <CCNavigationBackendEventListener>{};
      final child = SharedSource(external, () => aggregate.dispose());
      aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'main',
        adapters: {'main': child},
      );
      Object? error;
      try {
        aggregate.initialize(const []);
      } catch (e) {
        error = e;
      }
      aggregate.dispose();
      expect(error, isA<CCNavigationAdapterError>());
      expect(external, isEmpty);
      expect(child.disposals, 1);
    },
  );
  for (final stage in [
    'capabilities',
    'initialize',
    'guard',
    'backend',
    'predictiveProvider',
    'predictive',
    'snapshot',
  ]) {
    test('initial disposal fences optional SPI stage=$stage', () async {
      late CCRouterRuntime runtime;
      Future<void>? stopping;
      final adapter = PhaseAdapter(stage, () => stopping ??= runtime.dispose());
      runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter);
      expect(runtime.initialize, throwsA(isA<CCRouteCancelledError>()));
      await stopping;
      expect(runtime.isInitialized, isFalse);
      expect(
        () => runtime.openSession(accountId: 'closed'),
        throwsA(isA<CCRouterNotInitializedError>()),
      );
      expect(runtime.session, isNull);
      expect(adapter.listeners, isEmpty);
      await runtime.dispose();
      expect(adapter.disposals, 1);
      expect(runtime.initialize, throwsA(isA<CCScopeClosedError>()));
    });
  }

  test(
    'nested initialize is rejected while outer initialization can complete',
    () async {
      late CCRouterRuntime runtime;
      var calls = 0;
      final adapter = Plain(
        onInitialize: () {
          calls++;
          expect(runtime.initialize, throwsA(isA<CCRegistrationError>()));
        },
      );
      runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter);
      runtime.initialize();
      runtime.initialize();
      expect(calls, 1);
      expect(runtime.isInitialized, isTrue);
      await runtime.dispose();
      expect(adapter.disposals, 1);
    },
  );
}
