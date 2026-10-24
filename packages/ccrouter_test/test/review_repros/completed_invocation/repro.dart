import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

class AccountResource implements CCDisposable {
  AccountResource(this.account);
  final String account;
  int disposals = 0;
  @override
  void dispose() => disposals++;
}

class Launcher {}

class AppLauncher {}

const launcherToken = CCServiceToken<Launcher>('probe.launcher');
const appLauncherToken = CCServiceToken<AppLauncher>('probe.appLauncher');
const accountToken = CCServiceToken<AccountResource>('probe.account');

Future<Object?> observe(FutureOr<Object?> Function() work) async {
  try {
    return await work();
  } catch (error) {
    return error;
  }
}

FutureOr<Object?> lookup(CCRouterRuntime runtime, String kind) =>
    switch (kind) {
      'single' => runtime.service<AccountResource>(),
      'async' => runtime.serviceAsync<AccountResource>(),
      'all' => runtime.services<AccountResource>().single,
      'syncProxy' => runtime.invokeServiceSync<AccountResource, String>(
        contractToken: accountToken,
        methodId: 'read',
        call: (service, _) => service.account,
      ),
      _ => runtime.invokeService<AccountResource, String>(
        contractToken: accountToken,
        methodId: 'read',
        call: (service, _) => service.account,
      ),
    };

void main() {
  for (final origin in [
    'asyncMethod',
    'syncMethod',
    'nestedAsyncApp',
    'nestedSyncApp',
    'initializer',
  ]) {
    for (final kind in ['single', 'async', 'all', 'syncProxy', 'asyncProxy']) {
      for (final switchAccount in [false, true]) {
        test(
          'completed $origin fences $kind after switch=$switchAccount',
          () async {
            final runtime = CCRouterRuntime.forTesting();
            addTearDown(runtime.dispose);
            final release = Completer<void>();
            final resources = <AccountResource>[];
            late Future<Object?> lateOutcome;
            late CCInvocationContext originContext;
            void launch(CCInvocationContext context) {
              originContext = context;
              // The callback captures the invocation Zone by starting inside it.
              // The invocation itself returns successfully before Session close.
              lateOutcome = observe(() async {
                await release.future;
                return lookup(runtime, kind);
              });
            }

            runtime.registerService(
              CCServiceProvider<AccountResource>(
                contractToken: accountToken,
                scope: CCServiceScope.session,
                factory: (_) {
                  final value = AccountResource(runtime.session!.accountId);
                  resources.add(value);
                  return value;
                },
              ),
            );
            runtime.registerService(
              CCServiceProvider<AppLauncher>(
                contractToken: appLauncherToken,
                factory: (_) => AppLauncher(),
              ),
            );
            runtime.registerService(
              CCServiceProvider<Launcher>(
                contractToken: launcherToken,
                scope: CCServiceScope.session,
                factory: (_) => Launcher(),
                initializer: origin == 'initializer'
                    ? (_, context) => launch(context)
                    : null,
              ),
            );
            runtime.initialize();
            runtime.openSession(accountId: 'old');
            switch (origin) {
              case 'asyncMethod':
                await runtime.invokeService<Launcher, void>(
                  contractToken: launcherToken,
                  methodId: 'launch',
                  call: (_, context) => launch(context),
                );
              case 'syncMethod':
                runtime.invokeServiceSync<Launcher, void>(
                  contractToken: launcherToken,
                  methodId: 'launch',
                  call: (_, context) => launch(context),
                );
              case 'nestedAsyncApp':
                await runtime.invokeService<Launcher, void>(
                  contractToken: launcherToken,
                  methodId: 'launch',
                  call: (_, _) => runtime.invokeService<AppLauncher, void>(
                    contractToken: appLauncherToken,
                    methodId: 'launch',
                    call: (_, context) => launch(context),
                  ),
                );
              case 'nestedSyncApp':
                runtime.invokeServiceSync<Launcher, void>(
                  contractToken: launcherToken,
                  methodId: 'launch',
                  call: (_, _) => runtime.invokeServiceSync<AppLauncher, void>(
                    contractToken: appLauncherToken,
                    methodId: 'launch',
                    call: (_, context) => launch(context),
                  ),
                );
              default:
                await runtime.serviceAsync<Launcher>();
            }
            // No in-flight invocation is being cancelled here.
            expect(originContext.cancellation.isCancelled, isFalse);
            if (switchAccount) {
              await runtime.closeSession();
              runtime.openSession(accountId: 'new');
            }
            release.complete();
            final outcome = await lateOutcome.timeout(
              const Duration(seconds: 2),
            );
            final lateConstructions = resources.length;
            // A caller outside the old Zone must still access the live Session.
            final independent = runtime.service<AccountResource>();
            expect(independent.account, switchAccount ? 'new' : 'old');
            await runtime.closeSession();
            expect(
              resources.every((resource) => resource.disposals == 1),
              isTrue,
            );
            if (switchAccount) {
              expect(
                outcome,
                anyOf(
                  isA<CCInvocationCancelledError>(),
                  isA<CCScopeClosedError>(),
                ),
                reason:
                    'Ended Session callback entered replacement account: '
                    '${outcome is AccountResource ? outcome.account : outcome}; '
                    'original token cancelled='
                    '${originContext.cancellation.isCancelled}',
              );
              expect(lateConstructions, 0);
            } else {
              expect(
                outcome is AccountResource ? outcome.account : outcome,
                'old',
              );
              expect(lateConstructions, 1);
            }
          },
        );
      }
    }
  }

  for (final policy in CCServiceCreationPolicy.values) {
    for (final kind in [
      'single',
      'optional',
      'all',
      'async',
      'syncProxy',
      'asyncProxy',
    ]) {
      for (final shutdownInFactory in [false, true]) {
        test(
          'root $kind $policy rejects factory shutdown=$shutdownInFactory',
          () async {
            final runtime = CCRouterRuntime.forTesting();
            addTearDown(runtime.dispose);
            final resource = AccountResource('app');
            Future<void>? closing;
            runtime.registerService(
              CCServiceProvider<AccountResource>(
                contractToken: accountToken,
                creationPolicy: policy,
                factory: (_) {
                  if (shutdownInFactory) closing = runtime.dispose();
                  return resource;
                },
              ),
            );
            runtime.initialize();
            final outcome = await observe(
              () => switch (kind) {
                'single' => runtime.service<AccountResource>(),
                'optional' => runtime.serviceOrNull<AccountResource>(),
                'all' => runtime.services<AccountResource>().single,
                _ => lookup(runtime, kind),
              },
            );
            if (shutdownInFactory) {
              await closing;
              expect(resource.disposals, 1);
              expect(
                outcome,
                anyOf(
                  isA<CCInvocationCancelledError>(),
                  isA<CCScopeClosedError>(),
                  isA<CCResolutionError>(),
                  isA<CCRouterNotInitializedError>(),
                ),
                reason: 'Shutdown factory must not deliver a disposed resource',
              );
            } else {
              expect(
                outcome,
                kind.endsWith('Proxy') ? equals('app') : same(resource),
              );
              expect(resource.disposals, 0);
              await runtime.dispose();
              expect(resource.disposals, 1);
            }
          },
        );
      }
    }
  }
}
