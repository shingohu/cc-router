import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../reentrant_lifecycle_regression_test.dart' as fixture;

enum Kind { navigation, entry, visibility, failure, backend, capability }

// A legacy adapter produces visibility fallbacks; its explicit backend source
// also exercises diagnostic subscription identity without fabricating Core state.
class EventAdapter
    implements CCNavigationAdapter, CCNavigationBackendEventSource {
  final inner = CCMemoryNavigationAdapter();
  final listeners = <CCNavigationBackendEventListener>{};
  int sequence = 0;

  void emit() {
    final event = CCNavigationBackendEvent(
      kind: CCNavigationBackendEventKind.push,
      timestamp: DateTime.now(),
      backendEntryId: 'foreign-${++sequence}',
      hostId: 'default',
      navigatorOutlet: 'root',
      owner: CCBackendEntryOwner.foreign,
    );
    for (final listener in listeners.toList()) {
      listener(event);
    }
  }

  @override
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) => inner.initialize(routes, shells: shells);
  @override
  Future<Object?> navigate(CCNavigationRequest request) =>
      inner.navigate(request);
  @override
  Future<bool> maybePop({Object? result}) => inner.maybePop(result: result);
  @override
  void pop({Object? result}) => inner.pop(result: result);
  @override
  bool canPop() => inner.canPop();
  @override
  void dispose() {
    listeners.clear();
    inner.dispose();
  }
}

class MissingIntent implements CCRouteIntent<void> {
  @override
  String get routeId => 'probe.missing';
  @override
  Object get arguments => 'missing';
}

Future<void> trigger(
  CCRouterRuntime runtime,
  Kind kind,
  EventAdapter adapter,
) async {
  if (kind == Kind.backend) {
    adapter.emit();
  } else if (kind == Kind.failure) {
    await expectLater(
      runtime.goRoute(MissingIntent()),
      throwsA(isA<CCRouteNotFoundError>()),
    );
  } else {
    await runtime.goRoute(const fixture.Intent());
  }
}

void main() {
  for (final kind in Kind.values) {
    for (final scenario in [
      'removeOnly',
      'readdBeforeDrain',
      'oldRemoverAgain',
      'duplicateAdd',
      'independentListener',
    ]) {
      test('observer $kind: $scenario', () async {
        final adapter = EventAdapter();
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: adapter,
          components: [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: fixture.Registrar(),
            ),
          ],
        );
        addTearDown(runtime.dispose);
        runtime.initialize();
        final seen = <Object>[];
        void listener(Object event) => seen.add(event);
        void Function() subscribe([void Function(Object)? observer]) =>
            switch (kind) {
              Kind.navigation => runtime.addNavigationListener(
                observer ?? listener,
              ),
              Kind.entry => runtime.addRouteEntryListener(observer ?? listener),
              Kind.visibility => runtime.addRouteVisibilityListener(
                observer ?? listener,
              ),
              Kind.failure => runtime.addNavigationFailureListener(
                observer ?? listener,
              ),
              Kind.backend => runtime.addBackendNavigationListener(
                observer ?? listener,
              ),
              Kind.capability =>
                runtime.addNavigationCapabilityFallbackListener(
                  observer ?? listener,
                ),
            };

        final oldRemove = subscribe();
        if (scenario == 'duplicateAdd') {
          final duplicateRemove = subscribe();
          final baseline = <Object>[];
          final removeBaseline = subscribe(baseline.add);
          await trigger(runtime, kind, adapter);
          await Future<void>.delayed(Duration.zero);
          expect(seen, isNotEmpty);
          expect(seen, baseline, reason: 'Duplicate adds still deliver once');
          final count = seen.length;
          oldRemove();
          await trigger(runtime, kind, adapter);
          await Future<void>.delayed(Duration.zero);
          expect(
            seen,
            hasLength(count),
            reason: 'Existing dedup cleanup semantics',
          );
          duplicateRemove();
          removeBaseline();
          return;
        }
        if (scenario == 'independentListener') {
          final baseline = <Object>[];
          final removeBaseline = subscribe(baseline.add);
          await trigger(runtime, kind, adapter);
          oldRemove();
          await Future<void>.delayed(Duration.zero);
          expect(seen, isEmpty);
          expect(
            baseline,
            isNotEmpty,
            reason: 'Cancellation is subscription-local',
          );
          removeBaseline();
          return;
        }
        await trigger(runtime, kind, adapter);
        expect(
          seen,
          isEmpty,
          reason: 'Fixture must stop before queued delivery',
        );
        oldRemove();
        if (scenario == 'oldRemoverAgain') {
          // Drain the old subscription's queue before admitting the new one.
          await Future<void>.delayed(Duration.zero);
          expect(seen, isEmpty);
          final newRemove = subscribe();
          oldRemove();
          await trigger(runtime, kind, adapter);
          await Future<void>.delayed(Duration.zero);
          newRemove();
          expect(
            seen,
            isNotEmpty,
            reason: 'Old cleanup must not remove new subscription',
          );
        } else {
          final newRemove = scenario == 'readdBeforeDrain' ? subscribe() : null;
          await Future<void>.delayed(Duration.zero);
          newRemove?.call();
          expect(
            seen,
            isEmpty,
            reason: 'Unsubscribed queued events must not revive',
          );
        }
      });
    }
  }
}
