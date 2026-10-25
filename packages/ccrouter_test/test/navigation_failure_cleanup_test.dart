import 'package:ccrouter/ccrouter.dart';
import 'dart:async';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'reentrant_lifecycle_regression_test.dart'
    show ProbeAdapter, Intent, Registrar, Resource;

class Release extends ProbeAdapter
    implements CCNavigationManagedEntryReleaseSink {
  Release() : super('primary');
  void Function()? onRelease;
  Completer<Object?>? dispatchResult;
  Object? dispatchFailure;
  StackTrace? dispatchStack;
  void Function()? onDispatch;

  @override
  Future<Object?> navigate(CCNavigationRequest request) {
    onDispatch?.call();
    if (dispatchResult != null) return dispatchResult!.future;
    final failure = dispatchFailure;
    if (failure != null) return Future<Object?>.error(failure, dispatchStack);
    return super.navigate(request);
  }

  @override
  void releaseManagedNavigation(String id) => onRelease?.call();
}

CCRouterRuntime runtimeFor(CCNavigationAdapter adapter, Resource resource) =>
    CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        CCComponentManifest(
          id: 'probe',
          version: '1.0.0',
          registrar: Registrar(
            extra: (r) => r.registerService<Resource>(
              CCServiceProvider(
                scope: CCServiceScope.route,
                factory: (_) => resource,
              ),
            ),
          ),
        ),
      ],
    )..initialize();

class HeldResource extends Resource {
  final released = Completer<void>();
  @override
  Future<void> dispose() {
    super.dispose();
    return released.future;
  }
}

void main() {
  test('reentrant shutdown sees the failure of removal it joined', () async {
    final adapter = Release();
    final resource = Resource();
    final runtime = runtimeFor(adapter, resource);
    await runtime.goRoute(const Intent());
    runtime.serviceForRoute<Resource>(
      navigationId: runtime.activeRouteEntries.single.navigationId,
    );
    final failure = StateError('release failed after reentry');
    Future<Object?>? stopping;
    adapter.onRelease = () {
      adapter.onRelease = null;
      stopping ??= runtime.dispose().then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      throw failure;
    };
    Object? navigationError;
    try {
      await runtime.goRoute(const Intent());
    } catch (e) {
      navigationError = e;
    }
    final shutdownError = await stopping;
    expect(navigationError, isA<CCNavigationAdapterError>());
    expect(shutdownError, same(failure));
  });
  test('release callback health agrees with active Entry stack', () async {
    final adapter = Release();
    final runtime = runtimeFor(adapter, Resource());
    addTearDown(runtime.dispose);
    await runtime.goRoute(const Intent());
    expect(runtime.runtimeHealth.activeRouteEntryCount, 1);
    int? cached, actual;
    adapter.onRelease = () {
      cached = runtime.runtimeHealth.activeRouteEntryCount;
      actual = runtime.activeRouteEntries.length;
    };
    await runtime.goRoute(const Intent());
    expect(cached, actual);
  });
  test(
    'failed navigation keeps original failure and terminal observations when release also fails',
    () async {
      final adapter = Release();
      final cleanup = StateError('private release failure');
      final after = <CCNavigationAspectOutcome?>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          CCComponentManifest(
            id: 'probe',
            version: '1.0.0',
            registrar: Registrar(),
          ),
        ],
        navigationAspects: [
          CCNavigationAspect(
            id: 'audit',
            onAfter: (event) => after.add(event.outcome),
          ),
        ],
      )..initialize();
      addTearDown(runtime.dispose);
      // A closed memory backend rejects dispatch with a stable framework error.
      adapter.delegate.dispose();
      adapter.onRelease = () => throw cleanup;
      Object? error;
      try {
        await runtime.goRoute(const Intent());
      } catch (e) {
        error = e;
      }
      await Future<void>.delayed(Duration.zero);
      expect(error, isA<CCNavigationAdapterError>());
      expect(
        runtime.recentNavigationEvents.last.phase,
        CCNavigationLifecyclePhase.failed,
      );
      expect(after, [CCNavigationAspectOutcome.failed]);
    },
  );
  for (final frameworkError in [false, true]) {
    test(
      'repeated dispatch failures finish scopes/aspects and preserve primary error framework=$frameworkError',
      () async {
        final adapter = Release();
        final resource = Resource();
        final primary = frameworkError
            ? const CCNavigationAdapterError('primary adapter failure')
            : StateError('private adapter failure');
        final stack = StackTrace.fromString('primary dispatch stack');
        final cleanup = StateError('private cleanup failure');
        final after = <CCNavigationAspectOutcome?>[];
        final lost = <CCNavigationAspectOutcome?>[];
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: adapter,
          components: [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: Registrar(
                extra: (registry) {
                  registry.registerService<Resource>(
                    CCServiceProvider(
                      scope: CCServiceScope.route,
                      factory: (_) => resource,
                    ),
                  );
                },
              ),
            ),
          ],
          navigationAspects: [
            CCNavigationAspect(
              id: 'audit',
              onAfter: (event) => after.add(event.outcome),
              onLost: (event) => lost.add(event.outcome),
            ),
          ],
        )..initialize();
        addTearDown(runtime.dispose);
        adapter.onRelease = () => throw cleanup;
        for (var i = 0; i < 3; i++) {
          final pending = Completer<Object?>();
          adapter.dispatchResult = pending;
          final navigation = runtime.goRoute(const Intent());
          await Future<void>.delayed(Duration.zero);
          runtime.serviceForRoute<Resource>(
            navigationId: runtime.activeRouteEntries.single.navigationId,
          );
          pending.completeError(primary, stack);
          try {
            await navigation;
            fail('dispatch must fail');
          } catch (error, actualStack) {
            if (frameworkError) {
              expect(error, same(primary));
              expect(
                actualStack.toString(),
                contains('primary dispatch stack'),
              );
            } else {
              expect(error, isA<CCNavigationAdapterError>());
              expect(error.toString(), isNot(contains('private')));
            }
          }
        }
        await Future<void>.delayed(Duration.zero);
        expect(resource.disposeCalls, 3);
        expect(runtime.activeRouteEntries, isEmpty);
        expect(after, List.filled(3, CCNavigationAspectOutcome.failed));
        expect(lost, List.filled(3, CCNavigationAspectOutcome.failed));
        expect(
          runtime.recentNavigationEvents.where(
            (event) => event.phase == CCNavigationLifecyclePhase.failed,
          ),
          hasLength(3),
        );
        expect(
          runtime.subscriberErrors.where(
            (error) => error.toString().contains('Failed navigation cleanup'),
          ),
          hasLength(3),
        );
        expect(runtime.subscriberErrors.toString(), isNot(contains('private')));
      },
    );
  }

  for (final crossZone in [false, true]) {
    test(
      'reentrant removal barrier preserves error/stack after scope closure crossZone=$crossZone',
      () async {
        final uncaught = <Object>[];
        late Zone owner;
        runZonedGuarded(
          () => owner = Zone.current,
          (error, _) => uncaught.add(error),
        );
        var closer = owner;
        if (crossZone)
          runZonedGuarded(
            () => closer = Zone.current,
            (error, _) => uncaught.add(error),
          );
        final adapter = Release();
        final resource = owner.run(HeldResource.new);
        final runtime = owner.run(() => runtimeFor(adapter, resource));
        Future<Object?> settle(Zone zone, Future<void> Function() action) {
          final completion = Completer<Object?>();
          zone.run(
            () => unawaited(
              Future<void>.sync(action).then<void>(
                (_) => completion.complete(null),
                onError: (Object error, StackTrace stack) =>
                    completion.complete((error, stack)),
              ),
            ),
          );
          return completion.future;
        }

        expect(
          await settle(owner, () => runtime.goRoute(const Intent())),
          isNull,
        );
        owner.run(
          () => runtime.serviceForRoute<Resource>(
            navigationId: runtime.activeRouteEntries.single.navigationId,
          ),
        );
        final failure = StateError('first release failure');
        final originalStack = StackTrace.fromString('original release stack');
        Future<Object?>? first, second;
        adapter.onRelease = () {
          adapter.onRelease = null;
          first = settle(closer, runtime.dispose);
          second = settle(closer, runtime.dispose);
          Error.throwWithStackTrace(failure, originalStack);
        };
        final navigation = await settle(
          owner,
          () => runtime.goRoute(const Intent()),
        );
        expect(navigation, isA<(Object, StackTrace)>());
        var completed = false;
        unawaited(first!.then((_) => completed = true));
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
        expect(resource.disposeCalls, 1);
        resource.released.completeError(StateError('later scope failure'));
        for (final result in [
          await first!,
          await second!,
          await settle(closer, runtime.dispose),
        ]) {
          final (error, stack) = result! as (Object, StackTrace);
          expect(error, same(failure));
          expect(stack.toString(), originalStack.toString());
        }
        expect(adapter.disposeCalls, 1);
        expect(resource.disposeCalls, 1);
        expect(runtime.activeRouteEntries, isEmpty);
        expect(uncaught, isEmpty);
      },
    );
  }
}
