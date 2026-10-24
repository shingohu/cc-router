import 'dart:async';

import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../reentrant_lifecycle_regression_test.dart' as fixture;
import '../shared_waiter_lifetime/host_identity.dart' as identity;

class InitialAdapter extends identity.Adapter
    implements
        CCNavigationBackendSnapshotSource,
        CCNavigationAdapterCapabilitySource,
        CCNavigationScopedPopCoordinator {
  InitialAdapter(super.hostId);
  final gate = Completer<CCPopOutcome>();

  @override
  CCNavigationAdapterCapabilities get capabilities =>
      const CCNavigationAdapterCapabilities(
        supportsManagedPopObservation: true,
      );
  @override
  List<CCInitialBackendEntrySnapshot> readInitialBackendEntries() => [
    CCInitialBackendEntrySnapshot(
      backendEntryId: backendId,
      owner: CCBackendEntryOwner.managed,
      navigatorOutlet: 'root',
    ),
  ];
  @override
  Future<CCPopOutcome> maybePopOutcome({Object? result}) => gate.future;
  @override
  Future<CCPopOutcome> maybePopOutcomeAt({
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) => gate.future;
  @override
  CCPopOutcome popOutcomeAt({
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) => popOutcome(result: result);
  @override
  bool canPopAt({required String hostId, required String navigatorOutlet}) =>
      true;
}

void main() {
  for (final capacity in [0, 4]) {
    for (final scoped in [false, true]) {
      for (final runtimeNavigation in [false, true]) {
        test(
          'initial stack late Pop: history=$capacity scoped=$scoped priorRuntimeNavigation=$runtimeNavigation',
          () async {
            final old = InitialAdapter('right');
            final aggregate = CCMultiHostNavigationAdapter(
              defaultHostId: 'right',
              adapters: {'left': identity.Adapter('left'), 'right': old},
            );
            final runtime = CCRouterRuntime.forTesting(
              navigationAdapter: aggregate,
              navigationDiagnosticCapacity: capacity,
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
            expect(runtime.backendEntries, hasLength(1));
            if (runtimeNavigation) {
              await runtime.goRoute(const fixture.Intent());
            }
            final pending = runtime.maybePopOutcomeRoute<void>(
              placementOverride: scoped
                  ? const CCRoutePlacement(hostId: 'right')
                  : null,
            );
            aggregate.unregisterHost('right', replacementActiveHostId: 'left');
            aggregate.registerHost('right', InitialAdapter('right'));
            aggregate.activateHost('right');
            await runtime.goRoute(const fixture.Intent());
            final replacement = runtime.activeRouteEntries.single.routeEntryId;
            expect(runtime.desynchronizedBackendHosts, isEmpty);
            old.gate.complete(
              CCPopOutcome(
                handled: true,
                hostId: 'right',
                navigatorOutlet: 'root',
                removedBackendEntryId: old.backendId,
                removedEntryOwner: CCPopRemovedEntryOwner.managed,
              ),
            );
            expect((await pending).handled, isTrue);
            expect(runtime.activeRouteEntries.single.routeEntryId, replacement);
            expect(
              runtime.desynchronizedBackendHosts,
              isEmpty,
              reason: 'A retired initial stack cannot taint its replacement.',
            );
          },
        );
      }
    }
  }
}
