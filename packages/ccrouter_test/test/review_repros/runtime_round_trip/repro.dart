// Exploratory contract probe, NOT an accepted production regression.
// Independent Runtime crossing is not the public MultiHost model. The proposed
// A-B-A lineage expectation below needs a contract decision before a fix or
// promotion to the default suite. See the accompanying review report.
import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../completed_invocation/repro.dart' as fixture;

class Bridge {}

const bridgeToken = CCServiceToken<Bridge>('probe.bridge');

void main() {
  for (final switchAccount in [false, true]) {
    for (final kind in ['single', 'async', 'syncProxy', 'asyncProxy']) {
      for (final hop in ['method', 'factory', 'initializer']) {
        test('A-B-A $hop $kind switch=$switchAccount', () async {
          final first = CCRouterRuntime.forTesting();
          final second = CCRouterRuntime.forTesting();
          addTearDown(first.dispose);
          addTearDown(second.dispose);
          first.registerService(
            CCServiceProvider<fixture.Launcher>(
              contractToken: fixture.launcherToken,
              scope: CCServiceScope.session,
              factory: (_) => fixture.Launcher(),
            ),
          );
          first.registerService(
            CCServiceProvider<fixture.AccountResource>(
              contractToken: fixture.accountToken,
              scope: CCServiceScope.session,
              factory: (_) => fixture.AccountResource(first.session!.accountId),
            ),
          );
          final release = Completer<void>();
          late Future<Object?> outcome;
          void launch() {
            outcome = fixture.observe(() async {
              await release.future;
              return fixture.lookup(first, kind);
            });
          }

          second.registerService(
            CCServiceProvider<Bridge>(
              contractToken: bridgeToken,
              factory: (_) {
                if (hop == 'factory') launch();
                return Bridge();
              },
              initializer: hop == 'initializer' ? (_, _) => launch() : null,
            ),
          );
          first.initialize();
          second.initialize();
          first.openSession(accountId: 'old');
          await first.invokeService<fixture.Launcher, void>(
            contractToken: fixture.launcherToken,
            methodId: 'launch',
            call: (_, _) async {
              if (hop == 'method') {
                await second.invokeService<Bridge, void>(
                  contractToken: bridgeToken,
                  methodId: 'bridge',
                  call: (_, _) => launch(),
                );
              } else {
                await second.serviceAsync<Bridge>();
              }
            },
          );
          if (switchAccount) {
            await first.closeSession();
            first.openSession(accountId: 'new');
          }
          release.complete();
          final result = await outcome.timeout(const Duration(seconds: 2));
          if (switchAccount) {
            expect(
              result,
              isA<CCInvocationCancelledError>(),
              reason: 'A still has an old Session ancestor beneath B',
            );
          } else {
            expect(
              result is fixture.AccountResource ? result.account : result,
              'old',
            );
          }
        });
      }
    }
  }
}
