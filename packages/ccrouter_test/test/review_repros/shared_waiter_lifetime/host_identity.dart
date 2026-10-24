import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../reentrant_lifecycle_regression_test.dart' as fixture;

class Adapter extends fixture.ProbeAdapter
    implements CCNavigationPredictiveBackSource, CCNavigationPopCoordinator {
  Adapter(super.hostId, {this.backendId = 'entry-1'});

  final String backendId;

  final predictive = <CCPredictiveBackEventListener>{};

  @override
  Future<Object?> navigate(CCNavigationRequest request) {
    final pending = super.navigate(request);
    emit(
      CCNavigationBackendEvent(
        kind: CCNavigationBackendEventKind.push,
        timestamp: DateTime.now(),
        backendEntryId: backendId,
        navigationId: request.navigationId,
        owner: CCBackendEntryOwner.managed,
        hostId: hostId,
        navigatorOutlet: 'root',
      ),
    );
    return pending;
  }

  void emit(CCNavigationBackendEvent event) {
    for (final listener in listeners.toList()) {
      listener(event);
    }
  }

  @override
  CCPopOutcome popOutcome({Object? result}) {
    if (!delegate.canPop()) return const CCPopOutcome(handled: false);
    delegate.pop(result: result);
    return CCPopOutcome(
      handled: true,
      removedEntryOwner: CCPopRemovedEntryOwner.managed,
      removedBackendEntryId: backendId,
      hostId: hostId,
      navigatorOutlet: 'root',
    );
  }

  @override
  Future<CCPopOutcome> maybePopOutcome({Object? result}) async =>
      popOutcome(result: result);

  @override
  void Function() addPredictiveBackListener(
    CCPredictiveBackEventListener listener,
  ) {
    predictive.add(listener);
    return () => predictive.remove(listener);
  }

  void emitPredictive(CCPredictiveBackEvent event) {
    // Match the native Coordinator: application observer failures are isolated.
    for (final listener in predictive.toList()) {
      try {
        listener(event);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    predictive.clear();
    super.dispose();
  }
}

void main() {
  for (final collision in [false, true]) {
    test(
      'local Entry IDs remain isolated across children, collision=$collision',
      () async {
        final left = Adapter('left');
        final right = Adapter(
          'right',
          backendId: collision ? 'entry-1' : 'right-entry-1',
        );
        final aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: 'left',
          adapters: {'left': left, 'right': right},
        );
        final resources = <fixture.Resource>[];
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: aggregate,
          components: [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: fixture.Registrar(
                extra: (registry) {
                  registry.registerService(
                    CCServiceProvider<fixture.Resource>(
                      scope: CCServiceScope.route,
                      factory: (_) {
                        final resource = fixture.Resource();
                        resources.add(resource);
                        return resource;
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
        addTearDown(runtime.dispose);
        runtime.initialize();
        final results = <Future<Object?>>[];
        for (final hostId in ['left', 'right']) {
          aggregate.activateHost(hostId);
          results.add(
            runtime
                .pushRoute(const fixture.Intent())
                .then<Object?>((_) => null),
          );
          await Future<void>.delayed(Duration.zero);
          runtime.serviceForRoute<fixture.Resource>(
            navigationId: runtime.activeRouteEntries.last.navigationId,
          );
        }
        final rightEntry = runtime.activeRouteEntries.last;
        aggregate.activateHost('left');
        runtime.popRoute();
        await Future<void>.delayed(Duration.zero);
        final remaining = runtime.activeRouteEntries
            .map((value) => value.routeEntryId)
            .toList();
        final disposals = resources.map((value) => value.disposeCalls).toList();
        expect(left.delegate.stack, isEmpty);
        expect(right.delegate.stack, hasLength(1));
        await runtime.dispose();
        await Future.wait(results);
        expect(
          {'remaining': remaining, 'disposals': disposals},
          {
            'remaining': [rightEntry.routeEntryId],
            'disposals': [1, 0],
          },
        );
      },
    );
  }
  for (final collision in [false, true]) {
    test(
      'foreign event in right Host preserves left Entry, collision=$collision',
      () async {
        final left = Adapter('left');
        final right = Adapter('right');
        final aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: 'left',
          adapters: {'left': left, 'right': right},
        );
        final resource = fixture.Resource();
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: aggregate,
          components: [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: fixture.Registrar(
                extra: (registry) {
                  registry.registerService(
                    CCServiceProvider<fixture.Resource>(
                      scope: CCServiceScope.route,
                      factory: (_) => resource,
                    ),
                  );
                },
              ),
            ),
          ],
        );
        addTearDown(runtime.dispose);
        runtime.initialize();
        await runtime.goRoute(const fixture.Intent());
        final entry = runtime.activeRouteEntries.single;
        runtime.serviceForRoute<fixture.Resource>(
          navigationId: entry.navigationId,
        );
        final popupId = collision ? 'entry-1' : 'right-popup-1';
        for (final kind in [
          CCNavigationBackendEventKind.push,
          CCNavigationBackendEventKind.pop,
        ]) {
          right.emit(
            CCNavigationBackendEvent(
              kind: kind,
              timestamp: DateTime.now(),
              backendEntryId: popupId,
              owner: CCBackendEntryOwner.foreign,
              hostId: 'right',
              navigatorOutlet: 'root',
            ),
          );
        }
        await Future<void>.delayed(Duration.zero);
        expect(runtime.activeRouteEntries.map((value) => value.routeEntryId), [
          entry.routeEntryId,
        ]);
        expect(resource.disposeCalls, 0);
        expect(left.delegate.stack, hasLength(1));
      },
    );
  }

  for (final throws in [false, true]) {
    test(
      'MultiHost predictive observer failure is isolated, throws=$throws',
      () {
        final child = Adapter('left');
        final aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: 'left',
          adapters: {'left': child},
        );
        addTearDown(aggregate.dispose);
        aggregate.initialize(const []);
        aggregate.addPredictiveBackListener((_) {
          if (throws) throw StateError('Host observer failure');
        });
        final observed = <CCPredictiveBackPhase>[];
        aggregate.addPredictiveBackListener(
          (event) => observed.add(event.phase),
        );
        for (final phase in CCPredictiveBackPhase.values) {
          child.emitPredictive(
            CCPredictiveBackEvent(phase: phase, timestamp: DateTime.now()),
          );
        }
        expect(observed, CCPredictiveBackPhase.values);
      },
    );
  }
}
