import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'review_repros/session_and_resume/repro.dart' as fixture;

const _accountToken = CCServiceToken<fixture.AccountResource>('probe.account');
const _accountKey = CCServiceKey<fixture.AccountResource>('named');

void main() {
  for (final terminal in ['session', 'cancel', 'timeout']) {
    for (final lookup in ['single', 'optional', 'all', 'key', 'optionalKey']) {
      for (final policy in CCServiceCreationPolicy.values) {
        for (final prewarm in [false, true]) {
          test('$terminal fences $lookup, $policy, prewarm=$prewarm', () async {
            final runtime = CCRouterRuntime.forTesting();
            addTearDown(runtime.dispose);
            final started = Completer<CCInvocationContext>();
            final release = Completer<void>();
            final late = Completer<Object?>();
            final resources = <fixture.AccountResource>[];
            final token = CCCancellationToken();
            runtime.registerService(
              CCServiceProvider<fixture.AccountResource>(
                contractToken: _accountToken,
                key: _accountKey,
                isDefault: true,
                scope: CCServiceScope.session,
                creationPolicy: policy,
                factory: (_) {
                  final resource = fixture.AccountResource(
                    runtime.session!.accountId,
                  );
                  resources.add(resource);
                  return resource;
                },
              ),
            );
            runtime.registerService(
              CCServiceProvider<fixture.StartupResource>(
                contractToken: fixture.startupToken,
                scope: CCServiceScope.session,
                factory: (_) => fixture.StartupResource(),
              ),
            );
            runtime.initialize();
            runtime.openSession(accountId: 'old');
            if (prewarm) runtime.service<fixture.AccountResource>();
            final pending = fixture.observe(
              () => runtime.invokeService<fixture.StartupResource, void>(
                contractToken: fixture.startupToken,
                methodId: 'load',
                cancellation: token,
                timeout: terminal == 'timeout'
                    ? const Duration(milliseconds: 100)
                    : null,
                call: (_, context) async {
                  started.complete(context);
                  await release.future;
                  late.complete(
                    await fixture.observe(() async {
                      return switch (lookup) {
                        'single' => runtime.service<fixture.AccountResource>(),
                        'optional' =>
                          runtime.serviceOrNull<fixture.AccountResource>(),
                        'all' =>
                          runtime.services<fixture.AccountResource>().single,
                        'key' => runtime.service<fixture.AccountResource>(
                          key: _accountKey,
                        ),
                        _ => runtime.serviceOrNull<fixture.AccountResource>(
                          key: _accountKey,
                        ),
                      };
                    }),
                  );
                },
              ),
            );
            final context = await started.future;
            if (terminal == 'session') {
              await runtime.closeSession();
              runtime.openSession(accountId: 'new');
            } else if (terminal == 'cancel') {
              token.cancel();
            }
            expect(
              await pending,
              terminal == 'timeout'
                  ? isA<CCInvocationTimeoutError>()
                  : isA<CCInvocationCancelledError>(),
            );
            expect(context.cancellation.isCancelled, isTrue);
            final before = resources.length;
            release.complete();
            expect(
              await late.future.timeout(const Duration(seconds: 2)),
              anyOf(
                isA<CCInvocationCancelledError>(),
                isA<CCScopeClosedError>(),
              ),
            );
            expect(
              resources.length,
              before,
              reason: 'No late factory admission',
            );
            // An independent caller still resolves against its live account.
            expect(
              runtime.service<fixture.AccountResource>().account,
              terminal == 'session' ? 'new' : 'old',
            );
            await runtime.closeSession();
            expect(
              resources.every((resource) => resource.disposals == 1),
              isTrue,
            );
          });
        }
      }
    }
  }

  for (final scope in [CCServiceScope.app, CCServiceScope.session]) {
    for (final terminal in ['cancel', 'timeout']) {
      test(
        'shared $scope initializer resolves after first waiter $terminal',
        () async {
          final runtime = CCRouterRuntime.forTesting();
          addTearDown(runtime.dispose);
          final token = CCCancellationToken();
          final started = Completer<CCInvocationContext>();
          final release = Completer<void>();
          final resource = fixture.AccountResource('shared');
          var runs = 0;
          runtime.registerService(
            CCServiceProvider<fixture.AccountResource>(
              factory: (_) => resource,
            ),
          );
          runtime.registerService(
            CCServiceProvider<fixture.StartupResource>(
              scope: scope,
              factory: (_) => fixture.StartupResource(),
              initializer: (_, context) async {
                runs++;
                started.complete(context);
                await release.future;
                expect(
                  runtime.service<fixture.AccountResource>(),
                  same(resource),
                );
              },
            ),
          );
          runtime.initialize();
          if (scope == CCServiceScope.session)
            runtime.openSession(accountId: 'live');
          final first = fixture.observe(
            () => runtime.serviceAsync<fixture.StartupResource>(
              cancellation: token,
              timeout: terminal == 'timeout'
                  ? const Duration(milliseconds: 100)
                  : null,
            ),
          );
          final initializer = await started.future;
          final second = runtime.serviceAsync<fixture.StartupResource>();
          if (terminal == 'cancel') token.cancel();
          expect(
            await first,
            terminal == 'timeout'
                ? isA<CCInvocationTimeoutError>()
                : isA<CCInvocationCancelledError>(),
          );
          expect(initializer.cancellation.isCancelled, isFalse);
          release.complete();
          expect(await second, isA<fixture.StartupResource>());
          expect(runs, 1);
          await runtime.dispose();
          expect(resource.disposals, 1);
        },
      );
    }
  }

  test(
    'factory cancellation fences handoff but keeps App-owned resource',
    () async {
      final runtime = CCRouterRuntime.forTesting();
      addTearDown(runtime.dispose);
      final token = CCCancellationToken();
      final resource = fixture.AccountResource('app');
      var returned = false;
      runtime.registerService(
        CCServiceProvider<fixture.AccountResource>(
          factory: (_) {
            token.cancel();
            return resource;
          },
        ),
      );
      runtime.registerService(
        CCServiceProvider<fixture.StartupResource>(
          contractToken: fixture.startupToken,
          factory: (_) => fixture.StartupResource(),
        ),
      );
      runtime.initialize();
      final outcome = await fixture.observe(
        () => runtime.invokeService<fixture.StartupResource, void>(
          contractToken: fixture.startupToken,
          methodId: 'load',
          cancellation: token,
          call: (_, _) {
            runtime.service<fixture.AccountResource>();
            returned = true;
          },
        ),
      );
      expect(outcome, isA<CCInvocationCancelledError>());
      expect(returned, isFalse);
      expect(resource.disposals, 0);
      expect(runtime.service<fixture.AccountResource>(), same(resource));
      await runtime.dispose();
      expect(resource.disposals, 1);
    },
  );
}
