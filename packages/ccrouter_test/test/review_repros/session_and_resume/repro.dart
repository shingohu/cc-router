import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../reentrant_lifecycle_regression_test.dart' as fixture;
import '../init_task_reentrancy/error_zone_repro.dart'
    show NoOutcome, guardedZone;

class AccountResource implements CCDisposable {
  AccountResource(this.account);
  final String account;
  int disposals = 0;
  @override
  void dispose() => disposals++;
}

class StartupResource {}

const startupToken = CCServiceToken<StartupResource>('probe.startup');

class ResumePolicy implements CCNavigationInterceptor {
  bool deferred = true;
  bool denied = false;
  bool fails = false;
  @override
  CCNavigationInterceptorDecision intercept(
    CCNavigationInterceptorContext context,
  ) {
    if (deferred) return const CCNavigationDefer(code: 'fixture.wait');
    if (fails) throw StateError('fixture policy failure');
    return denied
        ? const CCNavigationCancel(code: 'fixture.denied')
        : const CCNavigationProceed();
  }
}

Future<Object?> observe(Future<Object?> Function() work) async {
  try {
    return await work();
  } catch (error) {
    return error;
  }
}

void main() {
  for (final fromInitializer in [true, false]) {
    for (final switchAccount in [false, true]) {
      for (final lookup in ['service', 'services', 'serviceAsync']) {
        test(
          'late work initializer=$fromInitializer, lookup=$lookup, switch=$switchAccount',
          () async {
            final runtime = CCRouterRuntime.forTesting();
            addTearDown(runtime.dispose);
            final started = Completer<void>();
            final release = Completer<void>();
            final lateOutcome = Completer<Object?>();
            final resources = <AccountResource>[];
            late CCInvocationContext initializerContext;
            Future<void> lateWork(CCInvocationContext context) async {
              initializerContext = context;
              started.complete();
              await release.future;
              lateOutcome.complete(
                await observe(
                  () async => switch (lookup) {
                    'service' => runtime.service<AccountResource>(),
                    'services' => runtime.services<AccountResource>().single,
                    _ => await runtime.serviceAsync<AccountResource>(),
                  },
                ),
              );
            }

            runtime.registerService(
              CCServiceProvider<AccountResource>(
                scope: CCServiceScope.session,
                factory: (_) {
                  final value = AccountResource(runtime.session!.accountId);
                  resources.add(value);
                  return value;
                },
              ),
            );
            runtime.registerService(
              CCServiceProvider<StartupResource>(
                contractToken: startupToken,
                scope: CCServiceScope.session,
                factory: (_) => StartupResource(),
                initializer: fromInitializer
                    ? (_, context) => lateWork(context)
                    : null,
              ),
            );
            runtime.initialize();
            runtime.openSession(accountId: 'old');
            final pending = observe(
              () => fromInitializer
                  ? runtime.serviceAsync<StartupResource>()
                  : runtime.invokeService<StartupResource, void>(
                      contractToken: startupToken,
                      methodId: 'load',
                      call: (_, context) => lateWork(context),
                    ),
            );
            await started.future;
            if (switchAccount) {
              await runtime.closeSession();
              expect(await pending, isA<CCInvocationCancelledError>());
              expect(initializerContext.cancellation.isCancelled, isTrue);
              runtime.openSession(accountId: 'new');
            }
            release.complete();
            final outcome = await lateOutcome.future.timeout(
              const Duration(seconds: 2),
            );
            if (switchAccount) {
              expect(
                outcome,
                anyOf(
                  isA<CCScopeClosedError>(),
                  isA<CCInvocationCancelledError>(),
                ),
                reason:
                    'Old work must not resolve new account resources; '
                    'actual=${outcome is AccountResource ? outcome.account : outcome}',
              );
              expect(resources, isEmpty);
              expect(runtime.service<AccountResource>().account, 'new');
            } else {
              expect((outcome as AccountResource).account, 'old');
              expect(
                await pending,
                fromInitializer ? isA<StartupResource>() : isNull,
              );
            }
            await runtime.closeSession();
            expect(
              resources.every((resource) => resource.disposals == 1),
              isTrue,
            );
          },
        );
      }
    }
  }

  for (final sameErrorZone in [true, false]) {
    for (final outcome in ['proceed', 'deny', 'failure']) {
      test(
        'defer resume: same error Zone=$sameErrorZone, outcome=$outcome',
        () async {
          final policy = ResumePolicy();
          final runtime = CCRouterRuntime.forTesting(
            navigationAdapter: CCMemoryNavigationAdapter(),
            globalInterceptors: [
              CCGlobalNavigationInterceptor(
                id: 'fixture.resume',
                interceptor: policy,
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
          final origin = guardedZone(uncaught);
          final resumer = sameErrorZone ? origin.fork() : guardedZone(uncaught);
          final originalOutcome = Completer<Object?>();
          final resumedOutcome = Completer<Object?>();
          origin.run(() {
            unawaited(
              observe(
                () => runtime.goRoute(const fixture.Intent()),
              ).then(originalOutcome.complete),
            );
          });
          await Future<void>.delayed(Duration.zero);
          final navigationId = runtime.pendingNavigations.single.navigationId;
          policy
            ..deferred = false
            ..denied = outcome == 'deny'
            ..fails = outcome == 'failure';
          resumer.run(() {
            unawaited(
              observe(
                () => runtime.resumePendingNavigation(navigationId),
              ).then(resumedOutcome.complete),
            );
          });
          final first = await originalOutcome.future.timeout(
            const Duration(seconds: 2),
          );
          final second = await resumedOutcome.future.timeout(
            const Duration(seconds: 2),
            onTimeout: NoOutcome.new,
          );
          expect(first, switch (outcome) {
            'deny' => isA<CCRouteCancelledError>(),
            'failure' => isA<CCRouterError>(),
            _ => isNull,
          });
          expect(
            second,
            outcome == 'proceed' ? isNull : same(first),
            reason:
                'Resume must finish in its own caller Zone; '
                'uncaught=${uncaught.map((error) => error.runtimeType).toList()}',
          );
          expect(runtime.pendingNavigations, isEmpty);
          expect(uncaught, isEmpty);
        },
      );
    }
  }
}
