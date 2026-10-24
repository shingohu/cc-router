import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../reentrant_lifecycle_regression_test.dart' as fixture;
import 'error_zone_repro.dart' show NoOutcome, guardedZone;

class GatedPolicy implements CCNavigationInterceptor {
  final started = Completer<void>();
  final release = Completer<void>();
  int calls = 0;
  bool cancel = false;

  @override
  Future<CCNavigationInterceptorDecision> intercept(
    CCNavigationInterceptorContext context,
  ) async {
    calls++;
    started.complete();
    await release.future;
    return cancel
        ? const CCNavigationCancel(code: 'fixture.blocked')
        : const CCNavigationProceed();
  }
}

void main() {
  for (final sharedErrorZone in [true, false]) {
    for (final cancel in [false, true]) {
      test('singleFlight navigation: same error Zone=$sharedErrorZone, '
          'policy cancels=$cancel', () async {
        final policy = GatedPolicy()..cancel = cancel;
        final terminalIds = <String>[];
        final terminalOutcomes = <CCNavigationAspectOutcome>[];
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: CCMemoryNavigationAdapter(),
          navigationConcurrencyPolicy:
              CCNavigationConcurrencyPolicy.singleFlight,
          globalInterceptors: [
            CCGlobalNavigationInterceptor(
              id: 'fixture.gate',
              interceptor: policy,
            ),
          ],
          navigationAspects: [
            CCNavigationAspect(
              id: 'fixture.observe',
              onAfter: (event) {
                terminalIds.add(event.request.navigationId);
                terminalOutcomes.add(event.outcome!);
              },
            ),
          ],
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
        final uncaught = <Object>[];
        final owner = guardedZone(uncaught);
        final other = sharedErrorZone ? owner.fork() : guardedZone(uncaught);
        void observe(Zone zone, Completer<Object?> outcome) => zone.run(() {
          unawaited(
            runtime
                .goRoute(const fixture.Intent())
                .then<void>(
                  (_) => outcome.complete(),
                  onError: (Object error, StackTrace _) =>
                      outcome.complete(error),
                ),
          );
        });

        final first = Completer<Object?>();
        final second = Completer<Object?>();
        observe(owner, first);
        await policy.started.future;
        observe(other, second);
        policy.release.complete();
        final firstOutcome = await first.future.timeout(
          const Duration(seconds: 1),
        );
        final secondOutcome = await second.future.timeout(
          const Duration(seconds: 2),
          onTimeout: NoOutcome.new,
        );
        // Aspect delivery is observational and deferred until after completion.
        await Future<void>.delayed(Duration.zero);
        expect(policy.calls, 1);
        expect(firstOutcome, cancel ? isA<CCRouteCancelledError>() : isNull);
        expect(
          secondOutcome,
          cancel ? isA<CCRouteCancelledError>() : isNull,
          reason:
              'terminal observations=${terminalIds.length}, '
              'uncaught=${uncaught.map((e) => e.runtimeType).toList()}',
        );
        expect(terminalIds.toSet(), hasLength(2));
        expect(
          terminalOutcomes,
          everyElement(
            cancel
                ? CCNavigationAspectOutcome.cancelled
                : CCNavigationAspectOutcome.succeeded,
          ),
        );
        if (cancel) expect(secondOutcome, same(firstOutcome));
        expect(uncaught, isEmpty);
      });
    }
  }
}
