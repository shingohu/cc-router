import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

class Payload {}

class Intent implements CCRouteIntent<void> {
  Intent(this.arguments);
  @override
  final Payload arguments;
  @override
  String get routeId => 'probe.payload';
}

class Codec implements CCRouteCodec<Payload> {
  const Codec();
  @override
  Payload decode(CCRouteCodecValues values) => Payload();
  @override
  CCRouteCodecValues encode(Payload arguments) => CCRouteCodecValues();
}

class Resource implements CCDisposable {
  int disposals = 0;
  @override
  void dispose() => disposals++;
}

const token = CCServiceToken<Resource>('probe.resource');

class Registrar implements CCComponentRegistrar {
  Registrar(
    this.kind,
    this.capture, {
    this.pending,
    this.scope = CCServiceScope.route,
  });
  final String kind;
  final void Function(Zone) capture;
  final Future<void>? pending;
  final CCServiceScope scope;
  @override
  void register(CCRegistry registry) {
    registry.registerRoute(
      CCRouteDefinition<Payload, void>(
        routeId: 'probe.payload',
        patterns: [const CCPathPattern('/payload', primary: true)],
        codec: const Codec(),
      ),
    );
    registry.registerService(
      CCServiceProvider<Resource>(
        contractToken: token,
        scope: scope,
        factory: (_) {
          if (kind == 'factory') launch();
          return Resource();
        },
        initializer: kind == 'initializer' ? (_, _) => launch() : null,
      ),
    );
  }

  void launch() {
    if (pending case final future?) {
      // Future.then binds the current Zone even though this callback captures
      // neither the Resource, the Runtime nor any route argument.
      unawaited(future.then(ignoreCompletion));
    } else {
      capture(Zone.current);
    }
  }
}

void ignoreCompletion(void value) {}

Future<(WeakReference<Payload>, Resource)> openAndClose(
  CCRouterRuntime runtime,
  String kind,
) async {
  final payload = Payload();
  final reference = WeakReference(payload);
  await runtime.goRoute(Intent(payload));
  final entry = runtime.activeRouteEntries.single;
  final resource = await runtime.serviceForRouteAsync<Resource>(
    navigationId: entry.navigationId,
  );
  // A direct method invocation is the control: it carries no construction owner.
  if (kind == 'method') {
    await runtime.invokeService<Resource, void>(
      contractToken: token,
      methodId: 'capture',
      navigationId: entry.navigationId,
      call: (_, _) => captures.add(Zone.current),
    );
  }
  expect(
    (await runtime.closeRoute(
      runtime.routeEntryHandleForNavigation(entry.navigationId)!,
    )).status,
    CCRouteCloseStatus.closed,
  );
  await Future<void>.delayed(Duration.zero);
  return (reference, resource);
}

final captures = <Zone>[];

Future<WeakReference<CCRouterRuntime>> createAndDisposeRuntime(
  Completer<void> pending, {
  required bool fromInvocation,
}) async {
  final runtime = CCRouterRuntime.forTesting();
  runtime.registerService(
    CCServiceProvider<Resource>(
      contractToken: token,
      factory: (_) => Resource(),
    ),
  );
  runtime.initialize();
  if (fromInvocation) {
    await runtime.invokeService<Resource, void>(
      contractToken: token,
      methodId: 'launch',
      call: (_, _) => unawaited(pending.future.then(ignoreCompletion)),
    );
  } else {
    unawaited(pending.future.then(ignoreCompletion));
  }
  await runtime.dispose();
  return WeakReference(runtime);
}

void main() {
  for (final fromInvocation in [false, true]) {
    test('ended Runtime is collectable with pending callback '
        'fromInvocation=$fromInvocation', () async {
      final pending = Completer<void>();
      final runtime = await createAndDisposeRuntime(
        pending,
        fromInvocation: fromInvocation,
      );
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
      final retainedWhilePending = runtime.target != null;
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
      expect(runtime.target, isNull);
      expect(
        retainedWhilePending,
        isFalse,
        reason:
            'Callback retains only its Zone; no application reference '
            'points at the disposed Runtime',
      );
    });
  }

  for (final kind in ['method', 'factory', 'initializer']) {
    test(
      'closed Route payload is collectable with retained $kind Zone',
      () async {
        captures.clear();
        addTearDown(captures.clear);
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: CCMemoryNavigationAdapter(),
          components: [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: Registrar(kind, captures.add),
            ),
          ],
        );
        addTearDown(runtime.dispose);
        runtime.initialize();
        final retained = await openAndClose(runtime, kind);
        expect(retained.$2.disposals, 1);
        expect(runtime.activeRouteEntries, isEmpty);
        expect(captures, hasLength(1));
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        final retainedWhileZoneLives = retained.$1.target != null;
        captures.clear();
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        expect(
          retained.$1.target,
          isNull,
          reason: 'Releasing the Zone must release the payload',
        );
        expect(
          retainedWhileZoneLives,
          isFalse,
          reason:
              'A framework construction Zone must not retain removed '
              'RouteEntry.request.arguments after Scope cleanup',
        );
      },
    );
  }

  for (final kind in ['factory', 'initializer']) {
    test(
      'unrelated pending Future in $kind cannot retain closed Route payload',
      () async {
        final pending = Completer<void>();
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: CCMemoryNavigationAdapter(),
          components: [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: Registrar(kind, (_) {}, pending: pending.future),
            ),
          ],
        );
        addTearDown(runtime.dispose);
        runtime.initialize();
        final retained = await openAndClose(runtime, kind);
        expect(retained.$2.disposals, 1);
        expect(runtime.activeRouteEntries, isEmpty);
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        final retainedWhilePending = retained.$1.target != null;
        pending.complete();
        await Future<void>.delayed(Duration.zero);
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        expect(
          retained.$1.target,
          isNull,
          reason: 'Completing the unrelated Future releases its bound Zone',
        );
        expect(
          retainedWhilePending,
          isFalse,
          reason: 'No application callback captured the route payload',
        );
      },
    );
  }
}
