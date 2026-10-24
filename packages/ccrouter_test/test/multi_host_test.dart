import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Arguments {
  const _Arguments(this.value);

  final String value;
}

final class _ArgumentsCodec implements CCRouteCodec<_Arguments> {
  const _ArgumentsCodec();

  @override
  _Arguments decode(CCRouteCodecValues input) =>
      _Arguments(input.path['value']!);

  @override
  CCRouteCodecValues encode(_Arguments arguments) =>
      CCRouteCodecValues(path: {'value': arguments.value});
}

final class _Intent<R> implements CCRouteIntent<R> {
  const _Intent(this.routeId, this.arguments);

  @override
  final String routeId;

  @override
  final _Arguments arguments;
}

final class _Registrar implements CCComponentRegistrar {
  const _Registrar();

  @override
  void register(CCRegistry registry) {
    registry.registerRoute<_Arguments, String>(
      CCRouteDefinition<_Arguments, String>(
        routeId: 'shared.detail',
        patterns: [CCPathPattern('/shared/:value', primary: true)],
        codec: const _ArgumentsCodec(),
      ),
    );
    registry.registerRoute<_Arguments, String>(
      CCRouteDefinition<_Arguments, String>(
        routeId: 'secondary.detail',
        patterns: [CCPathPattern('/secondary/:value', primary: true)],
        codec: const _ArgumentsCodec(),
        placement: const CCRoutePlacement(hostId: 'window.secondary'),
      ),
    );
  }
}

final class _OutletResource implements CCDisposable {
  int disposeCount = 0;
  @override
  void dispose() {
    disposeCount++;
  }
}

final class _AdaptiveRegistrar implements CCComponentRegistrar {
  const _AdaptiveRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerService<_OutletResource>(
      CCServiceProvider(
        scope: CCServiceScope.route,
        factory: (_) => _OutletResource(),
      ),
    );
    registry.registerRoute<_Arguments, String>(
      CCRouteDefinition<_Arguments, String>(
        routeId: 'workspace.list',
        patterns: [CCPathPattern('/list/:value', primary: true)],
        codec: const _ArgumentsCodec(),
        placement: const CCRoutePlacement(navigatorOutlet: 'list'),
      ),
    );
    registry.registerRoute<_Arguments, String>(
      CCRouteDefinition<_Arguments, String>(
        routeId: 'workspace.detail',
        patterns: [CCPathPattern('/detail/:value', primary: true)],
        codec: const _ArgumentsCodec(),
        placement: const CCRoutePlacement(navigatorOutlet: 'detail'),
      ),
    );
  }
}

final class _RouteRevalidationPolicy implements CCRouteRevalidationPolicy {
  const _RouteRevalidationPolicy();

  @override
  CCRouteRevalidationDecision evaluate(CCRouteRevalidationContext context) =>
      context.entry.hostId == 'window.secondary' &&
          context.entry.routeId == 'secondary.detail'
      ? const CCRouteRevalidationClose()
      : const CCRouteRevalidationKeep();
}

final class _DefaultHostRevalidationPolicy
    implements CCRouteRevalidationPolicy {
  const _DefaultHostRevalidationPolicy(this.decision);

  final CCRouteRevalidationDecision decision;

  @override
  CCRouteRevalidationDecision evaluate(CCRouteRevalidationContext context) =>
      context.entry.hostId == 'window.secondary' &&
          context.entry.routeId == 'shared.detail'
      ? decision
      : const CCRouteRevalidationKeep();
}

final class _NamedOutletRevalidationPolicy
    implements CCRouteRevalidationPolicy {
  const _NamedOutletRevalidationPolicy(this.decision);
  final CCRouteRevalidationDecision decision;
  @override
  CCRouteRevalidationDecision evaluate(CCRouteRevalidationContext context) =>
      context.entry.hostId == 'window.secondary'
      ? decision
      : const CCRouteRevalidationKeep();
}

final class _StructuredRegistrar implements CCComponentRegistrar {
  const _StructuredRegistrar(this.shell);
  final bool shell;
  @override
  void register(CCRegistry registry) {
    if (shell)
      registry.registerShell(
        CCShellDefinition(
          shellId: 'structured.shell',
          type: CCShellType.singleNavigator,
          outlets: const ['detail'],
          initialOutlet: 'detail',
        ),
      );
    for (final id in ['detail', 'redirect']) {
      registry.registerRoute<_Arguments, Object?>(
        CCRouteDefinition(
          routeId: 'structured.$id',
          patterns: [CCPathPattern('/structured/$id/:value', primary: true)],
          codec: const _ArgumentsCodec(),
          placement: CCRoutePlacement(
            navigatorOutlet: 'detail',
            shellId: shell ? 'structured.shell' : null,
          ),
        ),
      );
    }
  }
}

final class _StructuredInterceptor implements CCNavigationInterceptor {
  _StructuredInterceptor(this.defer);
  final bool defer;
  bool armed = false;
  @override
  CCNavigationInterceptorDecision intercept(
    CCNavigationInterceptorContext context,
  ) {
    if (context.request.routeId == 'structured.redirect')
      return const CCNavigationRedirect.toIntent(
        _Intent<Object?>('structured.detail', _Arguments('redirected')),
      );
    if (armed && defer) {
      armed = false;
      return const CCNavigationDefer();
    }
    return const CCNavigationProceed();
  }
}

final class _StructuredRecovery implements CCNavigationFailurePolicy {
  const _StructuredRecovery();
  @override
  CCNavigationFailureDecision onFailure(CCNavigationFailureContext context) =>
      const CCNavigationFailureRedirect.toIntent(
        _Intent<Object?>('structured.detail', _Arguments('recovered')),
      );
}

final class _HostAdapter
    implements
        CCNavigationAdapter,
        CCNavigationDispatchAdapter,
        CCNavigationTargetedCloseAdapter,
        CCNavigationAdapterHostBinding,
        CCNavigationAdapterCapabilitySource,
        CCNavigationPopCoordinator {
  _HostAdapter(this.hostId);

  @override
  final String hostId;

  final CCMemoryNavigationAdapter delegate = CCMemoryNavigationAdapter();

  final List<CCNavigationRequest> requests = [];

  List<String> initializedRouteIds = const [];

  bool disposed = false;

  @override
  CCNavigationAdapterCapabilities get capabilities => delegate.capabilities;

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {
    initializedRouteIds = routes.map((route) => route.routeId).toList();
    delegate.initialize(routes, shells: shells);
  }

  @override
  Future<Object?> navigate(CCNavigationRequest request) {
    requests.add(request);
    return delegate.navigate(request);
  }

  @override
  CCNavigationDispatch dispatchNavigation(CCNavigationRequest request) =>
      CCNavigationDispatch(result: navigate(request));

  @override
  Future<CCRouteCloseOutcome> closeNavigation({
    required String navigationId,
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) => delegate.closeNavigation(
    navigationId: navigationId,
    hostId: hostId,
    navigatorOutlet: navigatorOutlet,
    result: result,
  );

  @override
  Future<bool> maybePop({Object? result}) => delegate.maybePop(result: result);

  @override
  Future<CCPopOutcome> maybePopOutcome({Object? result}) =>
      delegate.maybePopOutcome(result: result);

  @override
  void pop({Object? result}) => delegate.pop(result: result);

  @override
  CCPopOutcome popOutcome({Object? result}) =>
      delegate.popOutcome(result: result);

  @override
  bool canPop() => delegate.canPop();

  @override
  void dispose() {
    disposed = true;
    delegate.dispose();
  }
}

class _LegacyHostAdapter implements CCNavigationAdapter {
  final delegate = CCMemoryNavigationAdapter();
  int navigations = 0;
  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) => delegate.initialize(routes, shells: shells);
  @override
  Future<Object?> navigate(CCNavigationRequest request) {
    navigations++;
    return delegate.navigate(request);
  }

  @override
  Future<bool> maybePop({Object? result}) => delegate.maybePop(result: result);
  @override
  void pop({Object? result}) => delegate.pop(result: result);
  @override
  bool canPop() => delegate.canPop();
  @override
  void dispose() => delegate.dispose();
}

final class _UnavailableDispatchHostAdapter extends _LegacyHostAdapter
    implements CCNavigationDispatchAdapter {
  @override
  CCNavigationDispatch? dispatchNavigation(CCNavigationRequest request) => null;
}

final class _FailingInitializeHostAdapter extends _HostAdapter {
  _FailingInitializeHostAdapter(super.hostId);

  int disposeCalls = 0;

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {
    throw const CCNavigationAdapterError('Synthetic initialization failure.');
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

final class _ThrowingDisposeHostAdapter extends _HostAdapter {
  _ThrowingDisposeHostAdapter(super.hostId);

  @override
  void dispose() {
    super.dispose();
    throw StateError('Synthetic disposal failure.');
  }
}

final class _FailingBindHostAdapter extends _HostAdapter
    implements
        CCNavigationBackendEventSource,
        CCNavigationPredictiveBackSource {
  _FailingBindHostAdapter(super.hostId);

  final Set<CCNavigationBackendEventListener> backendListeners = {};
  int disposeCalls = 0;

  @override
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) {
    backendListeners.add(listener);
    return () => backendListeners.remove(listener);
  }

  @override
  void Function() addPredictiveBackListener(
    CCPredictiveBackEventListener listener,
  ) {
    throw const CCNavigationAdapterError('Synthetic listener bind failure.');
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

final class _ThrowingRemoverHostAdapter extends _HostAdapter
    implements CCNavigationBackendEventSource {
  _ThrowingRemoverHostAdapter(super.hostId);

  @override
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) =>
      () => throw StateError('Synthetic listener removal failure.');
}

// Retains captured callbacks to model a notification queued before unsubscribe.
final class _QueuedEventHostAdapter extends _HostAdapter
    implements
        CCNavigationBackendEventSource,
        CCNavigationPredictiveBackSource {
  _QueuedEventHostAdapter(super.hostId);
  late CCNavigationBackendEventListener queuedBackend;
  late CCPredictiveBackEventListener queuedPredictive;
  int removals = 0;

  @override
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) {
    queuedBackend = listener;
    return () => removals++;
  }

  @override
  void Function() addPredictiveBackListener(
    CCPredictiveBackEventListener listener,
  ) {
    queuedPredictive = listener;
    return () => removals++;
  }
}

void main() {
  for (final capacity in [0, 2]) {
    test(
      'repeated Host detach releases each Route Scope once (capacity=$capacity)',
      () async {
        final primary = _HostAdapter('window.primary');
        final registry = CCMultiHostNavigationAdapter(
          defaultHostId: primary.hostId,
          adapters: {primary.hostId: primary},
        );
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: registry,
          navigationDiagnosticCapacity: capacity,
          components: const [
            CCComponentManifest(
              id: 'workspace',
              version: '1.0.0',
              registrar: _AdaptiveRegistrar(),
            ),
          ],
        );
        addTearDown(runtime.dispose);
        runtime.initialize();
        await runtime.goRoute(
          const _Intent<void>('workspace.list', _Arguments('primary')),
        );
        final primaryEntry = runtime.activeRouteEntries.single;
        final resources = <_OutletResource>[];
        for (var generation = 0; generation < 5; generation++) {
          registry.registerHost(
            'window.secondary',
            _HostAdapter('window.secondary'),
          );
          registry.activateHost('window.secondary');
          await runtime.goRoute(
            const _Intent<void>('workspace.detail', _Arguments('same')),
          );
          final entry = runtime.activeRouteEntries.last;
          resources.add(
            runtime.serviceForRoute<_OutletResource>(
              navigationId: entry.navigationId,
            ),
          );
          registry.setActiveOutlets(
            hostId: 'window.secondary',
            outlets: ['detail'],
          );
          registry.unregisterHost(
            'window.secondary',
            replacementActiveHostId: primary.hostId,
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            runtime.activeRouteEntries.single.routeEntryId,
            primaryEntry.routeEntryId,
            reason: 'generation $generation',
          );
          expect(
            resources.map((resource) => resource.disposeCount),
            everyElement(1),
          );
        }
      },
    );
  }

  test(
    'child operation IDs are isolated per registration and deduplicated within it',
    () async {
      final primary = _QueuedEventHostAdapter('window.primary');
      final registry = CCMultiHostNavigationAdapter(
        defaultHostId: primary.hostId,
        adapters: {primary.hostId: primary},
      );
      final runtime = CCRouterRuntime.forTesting(navigationAdapter: registry);
      addTearDown(runtime.dispose);
      runtime.initialize();
      for (var generation = 0; generation < 4; generation++) {
        final secondary = _QueuedEventHostAdapter('window.secondary');
        registry.registerHost(secondary.hostId, secondary);
        final event = CCNavigationBackendEvent(
          kind: CCNavigationBackendEventKind.push,
          timestamp: DateTime.now(),
          backendOperationId: 'child-1',
          backendEntryId: 'surface-$generation',
          owner: CCBackendEntryOwner.foreign,
        );
        secondary.queuedBackend(event);
        expect(
          runtime
              .backendEntriesFor(hostId: secondary.hostId)
              .where(
                (entry) =>
                    entry.lifecycleState == CCBackendEntryLifecycleState.active,
              )
              .single
              .backendEntryId,
          endsWith('-entry-surface-$generation'),
        );
        final count = runtime.recentBackendNavigationEvents.length;
        secondary.queuedBackend(event);
        expect(runtime.recentBackendNavigationEvents, hasLength(count));
        registry.unregisterHost(secondary.hostId);
        expect(secondary.removals, 2);
      }
    },
  );

  test(
    'queued events from retired registration cannot detach replacement or publish gestures',
    () {
      final primary = _QueuedEventHostAdapter('window.primary');
      final old = _QueuedEventHostAdapter('window.secondary');
      final registry = CCMultiHostNavigationAdapter(
        defaultHostId: primary.hostId,
        adapters: {primary.hostId: primary, old.hostId: old},
      );
      addTearDown(registry.dispose);
      registry.initialize(const []);
      final backend = <CCNavigationBackendEvent>[];
      final predictive = <CCPredictiveBackEvent>[];
      registry.addBackendEventListener(backend.add);
      registry.addPredictiveBackListener(predictive.add);
      registry.unregisterHost(old.hostId);
      registry.registerHost(old.hostId, _QueuedEventHostAdapter(old.hostId));
      final count = backend.length;
      old.queuedBackend(
        CCNavigationBackendEvent(
          kind: CCNavigationBackendEventKind.hostDetached,
          timestamp: DateTime.now(),
          backendOperationId: 'late-detach',
        ),
      );
      old.queuedPredictive(
        CCPredictiveBackEvent(
          phase: CCPredictiveBackPhase.committed,
          timestamp: DateTime.now(),
        ),
      );
      expect(backend, hasLength(count));
      expect(predictive, isEmpty);
    },
  );

  for (final declaresDispatch in [false, true]) {
    test(
      'MultiHost refuses Replace before mutation when child receipt ${declaresDispatch ? "is unavailable" : "is unsupported"}',
      () async {
        final primary = _HostAdapter('window.primary');
        final secondary = declaresDispatch
            ? _UnavailableDispatchHostAdapter()
            : _LegacyHostAdapter();
        final aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: primary.hostId,
          adapters: {primary.hostId: primary, 'window.secondary': secondary},
        );
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: aggregate,
          routeRevalidationPolicies: const [
            CCGlobalRouteRevalidationPolicy(
              id: 'test.legacy.child',
              policy: _DefaultHostRevalidationPolicy(
                CCRouteRevalidationReplace(
                  _Intent<Object?>('shared.detail', _Arguments('replacement')),
                ),
              ),
            ),
          ],
          components: const [
            CCComponentManifest(
              id: 'routes',
              version: '1.0.0',
              registrar: _Registrar(),
            ),
          ],
        );
        addTearDown(runtime.dispose);
        runtime.initialize();
        aggregate.activateHost('window.secondary');
        await runtime.goRoute(
          const _Intent<Object?>('shared.detail', _Arguments('before')),
        );
        aggregate.activateHost(primary.hostId);
        final before = runtime.activeRouteEntries.single.handle;
        final report = await runtime.revalidateActiveRoutes(
          reason: 'permission_changed',
        );
        expect(
          report.entries.single.outcome,
          CCRouteRevalidationOutcome.unsupported,
        );
        expect(secondary.navigations, 1);
        expect(primary.requests, isEmpty);
        expect(runtime.activeRouteEntries.single.handle, same(before));
        expect(aggregate.activeHostId, primary.hostId);
      },
    );
  }
  for (final shell in [false, true]) {
    for (final operation in ['replace', 'reset']) {
      for (final path in ['direct', 'redirect', 'recovery', 'resume']) {
        test(
          '${shell ? "Shell" : "Outlet"} $operation pins inactive Host through $path',
          () async {
            final primary = _HostAdapter('window.primary');
            final secondary = _HostAdapter('window.secondary');
            final aggregate = CCMultiHostNavigationAdapter(
              defaultHostId: primary.hostId,
              adapters: {primary.hostId: primary, secondary.hostId: secondary},
            );
            final interceptor = _StructuredInterceptor(path == 'resume');
            final target = _Intent<Object?>(
              path == 'recovery'
                  ? 'structured.missing'
                  : path == 'redirect'
                  ? 'structured.redirect'
                  : 'structured.detail',
              const _Arguments('target'),
            );
            final runtime = CCRouterRuntime.forTesting(
              navigationAdapter: aggregate,
              globalInterceptors: [
                CCGlobalNavigationInterceptor(
                  id: 'test.structured',
                  interceptor: interceptor,
                ),
              ],
              navigationFailurePolicy: const _StructuredRecovery(),
              routeRevalidationPolicies: [
                CCGlobalRouteRevalidationPolicy(
                  id: 'test.structured',
                  policy: _NamedOutletRevalidationPolicy(
                    operation == 'replace'
                        ? CCRouteRevalidationReplace(target)
                        : CCRouteRevalidationReset(target),
                  ),
                ),
              ],
              components: [
                CCComponentManifest(
                  id: 'routes',
                  version: '1.0.0',
                  registrar: _StructuredRegistrar(shell),
                ),
              ],
            );
            addTearDown(runtime.dispose);
            runtime.initialize();
            aggregate.activateHost(secondary.hostId);
            await runtime.goRoute(
              const _Intent<Object?>('structured.detail', _Arguments('before')),
            );
            aggregate.activateHost(primary.hostId);
            interceptor.armed = true;
            final pass = runtime.revalidateActiveRoutes(
              reason: 'permission_changed',
            );
            Future<Object?>? resume;
            if (path == 'resume') {
              while (runtime.pendingNavigations.isEmpty) {
                await Future<void>.delayed(Duration.zero);
              }
              resume = runtime.resumePendingNavigation(
                runtime.pendingNavigations.single.navigationId,
              );
            }
            final report = await pass.timeout(const Duration(seconds: 1));
            expect(
              report.entries.single.outcome,
              operation == 'replace'
                  ? CCRouteRevalidationOutcome.replaced
                  : CCRouteRevalidationOutcome.reset,
            );
            expect(primary.requests, isEmpty);
            expect(secondary.requests, hasLength(2));
            expect(secondary.requests.last.hostId, secondary.hostId);
            expect(secondary.requests.last.placement.navigatorOutlet, 'detail');
            expect(
              secondary.requests.last.placement.shellId,
              shell ? 'structured.shell' : null,
            );
            expect(aggregate.activeHostId, primary.hostId);
            if (resume != null) {
              if (operation == 'replace') {
                aggregate.activateHost(secondary.hostId);
                runtime.popRoute();
              }
              await resume;
            }
          },
        );
      }
    }
  }
  for (final operation in ['replace', 'reset']) {
    test(
      'revalidation $operation pins named Outlet to an inactive Host',
      () async {
        final primary = _HostAdapter('window.primary');
        final secondary = _HostAdapter('window.secondary');
        final aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: primary.hostId,
          adapters: {primary.hostId: primary, secondary.hostId: secondary},
        );
        final intent = const _Intent<Object?>(
          'workspace.detail',
          _Arguments('target'),
        );
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: aggregate,
          routeRevalidationPolicies: [
            CCGlobalRouteRevalidationPolicy(
              id: 'test.named.outlet',
              policy: _NamedOutletRevalidationPolicy(
                operation == 'replace'
                    ? CCRouteRevalidationReplace(intent)
                    : CCRouteRevalidationReset(intent),
              ),
            ),
          ],
          components: const [
            CCComponentManifest(
              id: 'routes',
              version: '1.0.0',
              registrar: _AdaptiveRegistrar(),
            ),
          ],
        );
        addTearDown(runtime.dispose);
        runtime.initialize();
        aggregate.activateHost(secondary.hostId);
        await runtime.goRoute(
          const _Intent<void>('workspace.detail', _Arguments('before')),
        );
        aggregate.activateHost(primary.hostId);
        final report = await runtime.revalidateActiveRoutes(
          reason: 'permission_changed',
        );
        expect(
          report.entries.single.outcome,
          operation == 'replace'
              ? CCRouteRevalidationOutcome.replaced
              : CCRouteRevalidationOutcome.reset,
        );
        expect(primary.requests, isEmpty);
        expect(secondary.requests.last.hostId, secondary.hostId);
        expect(secondary.requests.last.placement.navigatorOutlet, 'detail');
        expect(aggregate.activeHostId, primary.hostId);
      },
    );
  }
  test(
    'routes and pops remain isolated across dynamically selected Hosts',
    () async {
      final primary = _HostAdapter('window.primary');
      final secondary = _HostAdapter('window.secondary');
      final registry = CCMultiHostNavigationAdapter(
        defaultHostId: primary.hostId,
        adapters: {primary.hostId: primary, secondary.hostId: secondary},
      );
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: registry,
        components: const [
          CCComponentManifest(
            id: 'routes',
            version: '1.0.0',
            registrar: _Registrar(),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      runtime.initialize();

      expect(primary.initializedRouteIds, ['shared.detail']);
      expect(secondary.initializedRouteIds, [
        'secondary.detail',
        'shared.detail',
      ]);

      await runtime.goRoute(
        const _Intent<void>('shared.detail', _Arguments('primary-root')),
      );
      expect(primary.requests.single.hostId, primary.hostId);

      registry.activateHost(secondary.hostId);
      await runtime.goRoute(
        const _Intent<void>('shared.detail', _Arguments('secondary-root')),
      );
      expect(secondary.requests.single.hostId, secondary.hostId);
      expect(runtime.activeRouteEntries, hasLength(2));
      expect(runtime.activeRouteEntries.map((entry) => entry.hostId), [
        primary.hostId,
        secondary.hostId,
      ]);

      registry.activateHost(primary.hostId);
      await runtime.goRoute(
        const _Intent<void>('secondary.detail', _Arguments('fixed-host')),
      );
      expect(secondary.requests.last.routeId, 'secondary.detail');
      expect(secondary.requests.last.hostId, secondary.hostId);
      expect(runtime.activeRouteEntries, hasLength(2));

      final primaryResult = runtime.pushRoute<String>(
        const _Intent<String>('shared.detail', _Arguments('primary-push')),
      );
      registry.activateHost(secondary.hostId);
      final secondaryResult = runtime.pushRoute<String>(
        const _Intent<String>('shared.detail', _Arguments('secondary-push')),
      );
      expect(runtime.activeRouteEntries, hasLength(4));

      runtime.popRoute(result: 'secondary-result');
      expect(await secondaryResult, 'secondary-result');
      expect(
        runtime.activeRouteEntries.where(
          (entry) => entry.hostId == secondary.hostId,
        ),
        hasLength(1),
      );
      expect(
        runtime.activeRouteEntries.where(
          (entry) => entry.hostId == primary.hostId,
        ),
        hasLength(2),
      );

      registry.activateHost(primary.hostId);
      runtime.popRoute(result: 'primary-result');
      expect(await primaryResult, 'primary-result');
    },
  );

  test(
    'revalidation closes a covered entry in its owning Host without activation',
    () async {
      final primary = _HostAdapter('window.primary');
      final secondary = _HostAdapter('window.secondary');
      final registry = CCMultiHostNavigationAdapter(
        defaultHostId: primary.hostId,
        adapters: {primary.hostId: primary, secondary.hostId: secondary},
      );
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: registry,
        routeRevalidationPolicies: const [
          CCGlobalRouteRevalidationPolicy(
            id: 'test.secondary.access',
            policy: _RouteRevalidationPolicy(),
          ),
        ],
        components: const [
          CCComponentManifest(
            id: 'routes',
            version: '1.0.0',
            registrar: _Registrar(),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      runtime.initialize();

      await runtime.goRoute(
        const _Intent<void>('shared.detail', _Arguments('primary-root')),
      );
      final secondaryTarget = runtime.pushRoute<String>(
        const _Intent<String>(
          'secondary.detail',
          _Arguments('secondary-target'),
        ),
      );
      registry.activateHost(secondary.hostId);
      final secondaryCover = runtime.pushRoute<String>(
        const _Intent<String>('shared.detail', _Arguments('secondary-cover')),
      );
      registry.activateHost(primary.hostId);

      final report = await runtime.revalidateActiveRoutes(
        reason: 'permission_changed',
      );

      expect(registry.activeHostId, primary.hostId);
      expect(await secondaryTarget, isNull);
      expect(
        report.entries
            .singleWhere((entry) => entry.routeId == 'secondary.detail')
            .outcome,
        CCRouteRevalidationOutcome.closed,
      );
      expect(
        runtime.activeRouteEntries.map(
          (entry) => (entry.hostId, entry.routeId),
        ),
        [
          (primary.hostId, 'shared.detail'),
          (secondary.hostId, 'shared.detail'),
        ],
      );

      registry.activateHost(secondary.hostId);
      runtime.popRoute(result: 'cover-result');
      expect(await secondaryCover, 'cover-result');
    },
  );

  for (final scenario
      in <
        ({
          String label,
          CCRouteRevalidationDecision decision,
          CCRouteRevalidationOutcome outcome,
          CCNavigationOperation operation,
        })
      >[
        (
          label: 'replace',
          decision: const CCRouteRevalidationReplace(
            _Intent<Object?>('shared.detail', _Arguments('secondary-replaced')),
          ),
          outcome: CCRouteRevalidationOutcome.replaced,
          operation: CCNavigationOperation.replace,
        ),
        (
          label: 'reset',
          decision: const CCRouteRevalidationReset(
            _Intent<Object?>('shared.detail', _Arguments('secondary-reset')),
          ),
          outcome: CCRouteRevalidationOutcome.reset,
          operation: CCNavigationOperation.reset,
        ),
      ]) {
    test(
      'revalidation ${scenario.label} pins a default route to its original Host',
      () async {
        final primary = _HostAdapter('window.primary');
        final secondary = _HostAdapter('window.secondary');
        final registry = CCMultiHostNavigationAdapter(
          defaultHostId: primary.hostId,
          adapters: {primary.hostId: primary, secondary.hostId: secondary},
        );
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: registry,
          routeRevalidationPolicies: [
            CCGlobalRouteRevalidationPolicy(
              id: 'test.secondary.default_host',
              policy: _DefaultHostRevalidationPolicy(scenario.decision),
            ),
          ],
          components: const [
            CCComponentManifest(
              id: 'routes',
              version: '1.0.0',
              registrar: _Registrar(),
            ),
          ],
        );
        addTearDown(runtime.dispose);
        runtime.initialize();

        await runtime.goRoute(
          const _Intent<void>('shared.detail', _Arguments('primary-root')),
        );
        registry.activateHost(secondary.hostId);
        await runtime.goRoute(
          const _Intent<void>('shared.detail', _Arguments('secondary-root')),
        );
        registry.activateHost(primary.hostId);

        final report = await runtime.revalidateActiveRoutes(
          reason: 'permission_changed',
        );

        expect(registry.activeHostId, primary.hostId);
        expect(report.entries.last.outcome, scenario.outcome);
        expect(secondary.requests.last.operation, scenario.operation);
        expect(secondary.requests.last.hostId, secondary.hostId);
        expect(primary.requests, hasLength(1));
        expect(
          runtime.activeRouteEntries.map(
            (entry) => (entry.hostId, entry.routeId),
          ),
          [
            (primary.hostId, 'shared.detail'),
            (secondary.hostId, 'shared.detail'),
          ],
        );
      },
    );
  }

  test('registers and unregisters a Host after initialization', () async {
    final primary = _HostAdapter('window.primary');
    final registry = CCMultiHostNavigationAdapter(
      defaultHostId: primary.hostId,
      adapters: {primary.hostId: primary},
    );
    registry.initialize([
      CCNavigationRoute(
        routeId: 'shared.detail',
        patterns: [const CCPathPattern('/shared/:value', primary: true)],
        presentation: const CCPagePresentation(),
        deepLink: CCDeepLinkPolicy.disabled,
      ),
    ]);
    addTearDown(registry.dispose);

    final external = _HostAdapter('window.external');
    registry.registerHost(external.hostId, external);
    expect(registry.registeredHostIds, contains(external.hostId));
    expect(external.initializedRouteIds, ['shared.detail']);
    registry.activateHost(external.hostId);
    expect(registry.activeHostId, external.hostId);

    expect(
      () => registry.unregisterHost(external.hostId),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(external.disposed, isFalse);
    expect(registry.activeHostId, external.hostId);
    expect(registry.registeredHostIds, {primary.hostId, external.hostId});

    registry.unregisterHost(
      external.hostId,
      replacementActiveHostId: primary.hostId,
    );
    expect(external.disposed, isTrue);
    expect(registry.activeHostId, primary.hostId);
    expect(registry.registeredHostIds, {primary.hostId});
  });

  test(
    'failed synchronous Host registration is atomic and releases ownership',
    () {
      final primary = _HostAdapter('window.primary');
      final registry = CCMultiHostNavigationAdapter(
        defaultHostId: primary.hostId,
        adapters: {primary.hostId: primary},
      );
      registry.initialize([
        CCNavigationRoute(
          routeId: 'shared.detail',
          patterns: [const CCPathPattern('/shared/:value', primary: true)],
          presentation: const CCPagePresentation(),
          deepLink: CCDeepLinkPolicy.disabled,
        ),
      ]);
      final failing = _FailingInitializeHostAdapter('window.failing');

      expect(
        () => registry.registerHost(failing.hostId, failing),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(registry.registeredHostIds, isNot(contains(failing.hostId)));
      expect(failing.disposeCalls, 1);

      registry.dispose();
      registry.dispose();
      expect(primary.disposed, isTrue);
      expect(registry.registeredHostIds, isEmpty);
    },
  );

  test('failed dynamic Host listener binding removes partial registration', () {
    final primary = _HostAdapter('window.primary');
    final registry = CCMultiHostNavigationAdapter(
      defaultHostId: primary.hostId,
      adapters: {primary.hostId: primary},
    );
    registry.initialize(const []);
    final failing = _FailingBindHostAdapter('window.failing-bind');

    expect(
      () => registry.registerHost(failing.hostId, failing),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(registry.registeredHostIds, isNot(contains(failing.hostId)));
    expect(failing.backendListeners, isEmpty);
    expect(failing.disposeCalls, 1);

    registry.dispose();
  });

  test('failed initial Host setup disposes the complete owned registry', () {
    final healthy = _HostAdapter('window.healthy');
    final failing = _FailingInitializeHostAdapter('window.failing');
    final registry = CCMultiHostNavigationAdapter(
      defaultHostId: healthy.hostId,
      adapters: {healthy.hostId: healthy, failing.hostId: failing},
    );

    expect(
      () => registry.initialize(const []),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(healthy.disposed, isTrue);
    expect(failing.disposeCalls, 1);
    expect(registry.registeredHostIds, isEmpty);
  });

  test('listener removal failure cannot skip owned Adapter cleanup', () {
    final failing = _ThrowingRemoverHostAdapter('window.remover');
    final healthy = _HostAdapter('window.healthy');
    final registry = CCMultiHostNavigationAdapter(
      defaultHostId: failing.hostId,
      adapters: {failing.hostId: failing, healthy.hostId: healthy},
    );
    registry.initialize(const []);

    expect(() => registry.dispose(), throwsA(isA<StateError>()));
    expect(failing.disposed, isTrue);
    expect(healthy.disposed, isTrue);
    expect(registry.registeredHostIds, isEmpty);
  });

  test('Host removal failure still completes structural cleanup', () {
    final healthy = _HostAdapter('window.healthy');
    final failing = _ThrowingRemoverHostAdapter('window.remover');
    final registry = CCMultiHostNavigationAdapter(
      defaultHostId: healthy.hostId,
      adapters: {healthy.hostId: healthy, failing.hostId: failing},
    );
    registry.initialize(const []);

    expect(
      () => registry.unregisterHost(failing.hostId),
      throwsA(isA<StateError>()),
    );
    expect(failing.disposed, isTrue);
    expect(registry.registeredHostIds, {healthy.hostId});

    registry.dispose();
  });

  test('registry releases every Host when one synchronous dispose fails', () {
    final failing = _ThrowingDisposeHostAdapter('window.failing');
    final healthy = _HostAdapter('window.healthy');
    final registry = CCMultiHostNavigationAdapter(
      defaultHostId: failing.hostId,
      adapters: {failing.hostId: failing, healthy.hostId: healthy},
    );
    registry.initialize(const []);

    expect(() => registry.dispose(), throwsA(isA<StateError>()));
    expect(failing.disposed, isTrue);
    expect(healthy.disposed, isTrue);
    expect(registry.registeredHostIds, isEmpty);
  });

  test(
    'detaching a Host removes only its Entries and completes pending results',
    () async {
      final primary = _HostAdapter('window.primary');
      final secondary = _HostAdapter('window.secondary');
      final registry = CCMultiHostNavigationAdapter(
        defaultHostId: primary.hostId,
        adapters: {primary.hostId: primary, secondary.hostId: secondary},
      );
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: registry,
        components: const [
          CCComponentManifest(
            id: 'routes',
            version: '1.0.0',
            registrar: _Registrar(),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      runtime.initialize();

      await runtime.goRoute(
        const _Intent<void>('shared.detail', _Arguments('primary-root')),
      );
      registry.activateHost(secondary.hostId);
      await runtime.goRoute(
        const _Intent<void>('shared.detail', _Arguments('secondary-root')),
      );
      final secondaryResult = runtime.pushRoute<String>(
        const _Intent<String>('secondary.detail', _Arguments('pending')),
      );
      expect(runtime.activeRouteEntries, hasLength(3));

      registry.unregisterHost(
        secondary.hostId,
        replacementActiveHostId: primary.hostId,
      );

      expect(await secondaryResult, isNull);
      expect(secondary.disposed, isTrue);
      expect(registry.activeHostId, primary.hostId);
      expect(runtime.activeRouteEntries.map((entry) => entry.hostId), [
        primary.hostId,
      ]);
      expect(
        runtime.recentRouteEntryEvents
            .where((event) => event.entry.hostId == secondary.hostId)
            .where(
              (event) =>
                  event.entry.lifecycleState ==
                  CCRouteEntryLifecycleState.disposed,
            ),
        hasLength(2),
      );
      expect(
        runtime
            .backendEntriesFor(hostId: secondary.hostId)
            .every(
              (entry) =>
                  entry.lifecycleState == CCBackendEntryLifecycleState.removed,
            ),
        isTrue,
      );
    },
  );

  test(
    'Host visibility preserves identities, results, Scopes and other Hosts',
    () async {
      final primary = _HostAdapter('window.primary');
      final secondary = _HostAdapter('window.secondary');
      final registry = CCMultiHostNavigationAdapter(
        defaultHostId: primary.hostId,
        adapters: {primary.hostId: primary, secondary.hostId: secondary},
      );
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: registry,
        components: const [
          CCComponentManifest(
            id: 'workspace',
            version: '1.0.0',
            registrar: _AdaptiveRegistrar(),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      runtime.initialize();
      final results = <Future<String?>>[];
      var completed = 0;
      for (final hostId in [primary.hostId, secondary.hostId]) {
        registry.activateHost(hostId);
        for (final route in ['workspace.list', 'workspace.detail']) {
          results.add(
            runtime
                .pushRoute<String>(
                  _Intent<String>(route, const _Arguments('42')),
                )
                .then((value) {
                  completed++;
                  return value;
                }),
          );
        }
      }
      final entries = runtime.activeRouteEntries;
      final resources = {
        for (final entry in entries)
          entry.navigationId: runtime.serviceForRoute<_OutletResource>(
            navigationId: entry.navigationId,
          ),
      };
      final backendEvents = <CCNavigationBackendEvent>[];
      registry.addBackendEventListener(backendEvents.add);
      final visible = ['list'];
      registry.setActiveOutlets(hostId: primary.hostId, outlets: visible);
      visible.add('detail'); // Caller mutation cannot change the admitted set.
      expect(backendEvents.last.activeNavigatorOutlets, ['list']);
      expect(
        () => backendEvents.last.activeNavigatorOutlets.clear(),
        throwsUnsupportedError,
      );
      expect(registry.activeHostId, secondary.hostId);
      expect(runtime.activeRouteEntries.map((entry) => entry.lifecycleState), [
        CCRouteEntryLifecycleState.visible,
        CCRouteEntryLifecycleState.hidden,
        CCRouteEntryLifecycleState.visible,
        CCRouteEntryLifecycleState.visible,
      ]);
      final eventCount = backendEvents.length;
      for (final invalid in <List<String>>[
        [],
        ['list', 'list'],
        [' '],
      ]) {
        expect(
          () => registry.setActiveOutlets(
            hostId: primary.hostId,
            outlets: invalid,
          ),
          throwsArgumentError,
        );
        expect(
          runtime.activeRouteEntries[1].lifecycleState,
          CCRouteEntryLifecycleState.hidden,
        );
      }
      expect(
        () => registry.setActiveOutlets(hostId: 'missing', outlets: ['list']),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(backendEvents, hasLength(eventCount));
      registry.setActiveOutlets(
        hostId: primary.hostId,
        outlets: ['list', 'detail'],
      );
      expect(
        runtime.activeRouteEntries.map((entry) => entry.routeEntryId),
        entries.map((entry) => entry.routeEntryId),
      );
      expect(
        runtime.activeRouteEntries.every(
          (entry) => entry.lifecycleState == CCRouteEntryLifecycleState.visible,
        ),
        isTrue,
      );
      for (final entry in runtime.activeRouteEntries) {
        expect(
          runtime.serviceForRoute<_OutletResource>(
            navigationId: entry.navigationId,
          ),
          same(resources[entry.navigationId]),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(completed, 0);
      expect(
        resources.values.every((resource) => resource.disposeCount == 0),
        isTrue,
      );
      expect(
        runtime.recentRouteEntryEvents.where(
          (event) =>
              event.entry.lifecycleState == CCRouteEntryLifecycleState.disposed,
        ),
        isEmpty,
      );
      await runtime.dispose();
      expect(await Future.wait(results), everyElement(isNull));
      expect(completed, 4);
      expect(
        resources.values.every((resource) => resource.disposeCount == 1),
        isTrue,
      );
      expect(
        () => registry.setActiveOutlets(
          hostId: primary.hostId,
          outlets: ['list'],
        ),
        throwsA(isA<CCNavigationAdapterError>()),
      );
    },
  );
}
