import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reentrant_lifecycle_regression_test.dart' as fixture;

class Change implements CCEvent {}

class Write implements CCCommand<void> {}

void main() {
  test(
    'late readiness of closed account cannot enter the next Session',
    () async {
      final runtime = CCRouterRuntime.forTesting();
      addTearDown(runtime.dispose);
      final oldStarted = Completer<void>();
      final oldGate = Completer<void>();
      final resources = <fixture.Resource>[];
      final calls = <fixture.Resource>[];
      runtime.registerService(
        CCServiceProvider<fixture.Resource>(
          contractToken: fixture.serviceToken,
          scope: CCServiceScope.session,
          factory: (_) {
            final resource = fixture.Resource();
            resources.add(resource);
            return resource;
          },
          initializer: (resource, context) {
            if (identical(resource, resources.first)) {
              oldStarted.complete();
              return oldGate.future;
            }
          },
        ),
      );
      runtime.initialize();
      runtime.openSession(accountId: 'old');
      Future<int> invoke() => runtime.invokeService<fixture.Resource, int>(
        contractToken: fixture.serviceToken,
        methodId: 'write',
        call: (service, context) {
          calls.add(service);
          return calls.length;
        },
      );
      final oldResult = invoke().then<Object?>(
        (v) => v,
        onError: (Object e) => e,
      );
      await oldStarted.future;
      await runtime.closeSession();
      expect(await oldResult, isA<CCInvocationCancelledError>());
      runtime.openSession(accountId: 'new');
      expect(await invoke(), 1);
      oldGate.completeError(StateError('late old initializer'));
      await Future<void>.delayed(Duration.zero);
      expect(calls, [resources.last]);
      expect(resources.first.disposeCalls, 1);
      expect(resources.last.disposeCalls, 0);
      await runtime.closeSession();
      expect(resources.last.disposeCalls, 1);
    },
  );

  test(
    'nested Event Command Service cancellation fences late failure',
    () async {
      final runtime = CCRouterRuntime.forTesting();
      addTearDown(runtime.dispose);
      runtime.registerService(
        CCServiceProvider<fixture.Resource>(
          contractToken: fixture.serviceToken,
          factory: (_) => fixture.Resource(),
        ),
      );
      final contexts = <CCInvocationContext>[];
      final started = Completer<void>();
      final gate = Completer<void>();
      var delayed = true;
      runtime.registerCommand<Write, void>((message, context) async {
        contexts.add(context);
        await runtime.invokeService<fixture.Resource, void>(
          contractToken: fixture.serviceToken,
          methodId: 'write',
          call: (service, serviceContext) {
            contexts.add(serviceContext);
            if (delayed) {
              started.complete();
              return gate.future;
            }
          },
        );
      });
      runtime.registerEvent<Change>('write', (event, context) {
        contexts.add(context);
        return runtime.command(Write());
      });
      runtime.initialize();
      final token = CCCancellationToken();
      final pending = runtime.event(Change(), cancellation: token);
      final observed = pending.then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      await started.future;
      token.cancel();
      expect(await observed, isA<CCInvocationCancelledError>());
      expect(contexts, hasLength(3));
      expect(contexts.every((c) => c.cancellation.isCancelled), isTrue);
      expect(contexts.map((c) => c.traceId).toSet(), hasLength(1));
      gate.completeError(StateError('late application failure'));
      await Future<void>.delayed(Duration.zero);
      delayed = false;
      await runtime.event(Change());
      expect(contexts, hasLength(6));
      expect(
        contexts.skip(3).every((c) => !c.cancellation.isCancelled),
        isTrue,
      );
    },
  );
}
