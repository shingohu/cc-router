import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'managed_cross_lifecycle_regression_test.dart' as fixture;
import 'managed_operation_ownership_regression_test.dart' as links;

final extraDefinitions = [
  for (final id in ['explicit', 'parent', 'pane'])
    CCRouteDefinition<String, String>(
      routeId: 'probe.$id',
      patterns: [CCPathPattern('/$id/:id', primary: true)],
      codec: const fixture.Codec(),
      deepLink: id == 'pane'
          ? CCDeepLinkPolicy.enabled
          : CCDeepLinkPolicy.disabled,
      placement: id == 'explicit'
          ? const CCRoutePlacement(hostId: 'secondary')
          : CCRoutePlacement(
              shellId: 'probe.shell',
              navigatorOutlet: 'detail',
              parentRouteId: id == 'pane' ? 'probe.parent' : null,
            ),
    ),
];

final class PartitionRegistrar implements CCComponentRegistrar {
  @override
  void register(CCRegistry registry) {
    links.LinkRegistrar().register(registry);
    for (final definition in extraDefinitions) {
      registry.registerRoute(definition);
    }
    registry.registerShell(
      CCShellDefinition(
        shellId: 'probe.shell',
        type: CCShellType.singleNavigator,
        outlets: const ['detail'],
        initialOutlet: 'detail',
      ),
    );
  }
}

final class PartitionIntent implements CCRouteIntent<String> {
  const PartitionIntent(this.name, this.arguments);
  final String name;
  @override
  final String arguments;
  @override
  String get routeId => 'probe.$name';
}

Future<void> openFrom(CCNavigationOrigin origin) {
  final uri = Uri.parse('/detail/A');
  return switch (origin) {
    CCNavigationOrigin.internal => CCRouter.navigator.open(uri),
    CCNavigationOrigin.externalPlatform => CCDeepLinkIngress.fromPlatform(uri),
    CCNavigationOrigin.externalNotification =>
      CCDeepLinkIngress.fromNotification(uri),
    CCNavigationOrigin.externalQrCode => CCDeepLinkIngress.fromQrCode(uri),
  };
}

Future<CCManagedMultiHostBackend> mountMulti(
  WidgetTester tester, {
  CCNavigationInterceptor? interceptor,
  CCNavigationFailurePolicy? failurePolicy,
  CCNavigationConcurrencyPolicy concurrency =
      CCNavigationConcurrencyPolicy.allow,
}) async {
  CCRouterHost.initialize(
    hostAssembly: CCHostAssembly.fromComponents(
      components: [
        CCComponentManifest(
          id: 'probe',
          version: '1.0.0',
          registrar: PartitionRegistrar(),
        ),
      ],
      routeCatalog: CCFlutterRouteCatalog.merge(
        [
          links.linkCatalog(),
          CCFlutterRouteCatalog([
            for (final definition in extraDefinitions)
              CCFlutterRouteDestination.fromDefinition(
                definition: definition,
                builder: (values) => Scaffold(body: Text(values.path['id']!)),
              ),
          ]),
        ],
        componentVersions: const {'probe': '1.0.0'},
      ),
    ),
    globalInterceptors: [
      if (interceptor != null)
        CCGlobalNavigationInterceptor(
          id: 'probe.policy',
          interceptor: interceptor,
        ),
    ],
    navigationConcurrencyPolicy: concurrency,
    navigationFailurePolicy: failurePolicy,
    deepLinkIngressPolicy: CCDeepLinkIngressPolicy(allowRelativePaths: true),
  );
  final aggregate = CCManagedMultiHostBackend.managed(
    defaultHostId: 'primary',
    hostFactories: {
      for (final id in ['primary', 'secondary'])
        id: (config) => CCManagedRouterBackend(
          routeCatalog: config.catalog,
          host: CCNavigationHost(
            id: config.hostId,
            navigatorKeys: {'detail': GlobalKey<NavigatorState>()},
          ),
          shellBindings: [
            CCManagedShellBinding(
              shellId: 'probe.shell',
              builder: (_, shell) => shell.navigatorFor('detail'),
            ),
          ],
        ),
    },
  );
  await tester.pumpWidget(
    CCRouterApp.managed(
      backend: aggregate,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            for (final id in ['primary', 'secondary'])
              Expanded(
                child: MaterialApp.router(
                  routerConfig: aggregate.routerConfigFor(id),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return aggregate;
}

void main() {
  tearDown(CCRouterHost.shutdown);

  testWidgets('singleFlight must not skip external origin policy', (
    tester,
  ) async {
    final gate = Completer<CCNavigationInterceptorDecision>();
    var externalChecks = 0;
    await mountMulti(
      tester,
      concurrency: CCNavigationConcurrencyPolicy.singleFlight,
      interceptor: links.CallbackPolicy((context) {
        if (context.request.uri.path != '/detail/A')
          return const CCNavigationProceed();
        if (context.request.origin.isExternal) {
          externalChecks++;
          return const CCNavigationCancel(code: 'external_requires_consent');
        }
        return gate.future;
      }),
    );
    final internal = CCRouter.navigator.open(Uri.parse('/detail/A'));
    await tester.pump();
    final external = CCDeepLinkIngress.fromNotification(
      Uri.parse('/detail/A'),
    ).then<Object?>((_) => null, onError: (Object e, StackTrace _) => e);
    await tester.pump();
    gate.complete(const CCNavigationProceed());
    await tester.pumpAndSettle();
    await internal;
    final externalResult = await external;
    expect(externalChecks, 1);
    expect(externalResult, isA<CCRouteCancelledError>());
  });

  testWidgets('context-free redirect stays in originally selected Host', (
    tester,
  ) async {
    final gate = Completer<CCNavigationInterceptorDecision>();
    final aggregate = await mountMulti(
      tester,
      interceptor: links.CallbackPolicy((context) {
        return context.request.uri.path == '/detail/A'
            ? gate.future
            : const CCNavigationProceed();
      }),
    );
    final pending = CCRouter.navigator.go(const fixture.Intent('A'));
    await tester.pump();
    aggregate.adapter.activateHost('secondary');
    gate.complete(const CCNavigationRedirect.toIntent(fixture.Intent('B')));
    await tester.pumpAndSettle();
    await pending;
    expect(
      aggregate.backendFor('primary').adapter.requests.single.uri.path,
      '/detail/B',
    );
    expect(
      aggregate.backendFor('secondary').adapter.requests.single.uri.path,
      '/',
    );
  });

  testWidgets('pending context-free Back keeps actual Host in receipt', (
    tester,
  ) async {
    final aggregate = await mountMulti(tester);
    final result = CCRouter.navigator.push(const fixture.Intent('A'));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('A'));
    final route = ModalRoute.of(context)!;
    final gate = Completer<bool>();
    var entered = false;
    // ignore: deprecated_member_use
    route.addScopedWillPopCallback(() {
      entered = true;
      return gate.future;
    });
    final pending = CCRouter.navigator.maybePopOutcome(
      result: 'primary-result',
    );
    await tester.pump();
    expect(entered, isTrue);
    aggregate.adapter.activateHost('secondary');
    gate.complete(true);
    await tester.pumpAndSettle();
    final outcome = await pending;
    final actualResult = await result;
    expect(actualResult, 'primary-result');
    expect(
      aggregate.backendFor('primary').adapter.requests.single.uri.path,
      '/',
    );
    expect(
      aggregate.backendFor('secondary').adapter.requests.single.uri.path,
      '/',
    );
    expect(outcome.hostId, 'primary');
  });

  testWidgets('failure recovery stays in originally admitted Host', (
    tester,
  ) async {
    final recovery = links.RecoveryPolicy();
    final aggregate = await mountMulti(
      tester,
      failurePolicy: recovery,
      interceptor: links.CallbackPolicy(
        (context) => context.request.uri.path == '/detail/A'
            ? const CCNavigationCancel(code: 'recover_me')
            : const CCNavigationProceed(),
      ),
    );
    final pending = CCRouter.navigator.go(const fixture.Intent('A'));
    await tester.pump();
    expect(recovery.calls, 1);
    aggregate.adapter.activateHost('secondary');
    recovery.decision.complete(
      const CCNavigationFailureRedirect.toIntent(fixture.Intent('B')),
    );
    await tester.pumpAndSettle();
    await pending;
    expect(
      aggregate.backendFor('primary').adapter.requests.single.uri.path,
      '/detail/B',
    );
    expect(
      aggregate.backendFor('secondary').adapter.requests.single.uri.path,
      '/',
    );
  });

  testWidgets('control allow runs external origin policy independently', (
    tester,
  ) async {
    final gate = Completer<CCNavigationInterceptorDecision>();
    var externalChecks = 0;
    await mountMulti(
      tester,
      interceptor: links.CallbackPolicy((context) {
        if (context.request.uri.path != '/detail/A')
          return const CCNavigationProceed();
        if (context.request.origin.isExternal) {
          externalChecks++;
          return const CCNavigationCancel(code: 'external_requires_consent');
        }
        return gate.future;
      }),
    );
    final internal = CCRouter.navigator.open(Uri.parse('/detail/A'));
    await tester.pump();
    final external = CCDeepLinkIngress.fromNotification(
      Uri.parse('/detail/A'),
    ).then<Object?>((_) => null, onError: (Object e, StackTrace _) => e);
    await tester.pump();
    gate.complete(const CCNavigationProceed());
    await tester.pumpAndSettle();
    await internal;
    expect(externalChecks, 1);
    expect(await external, isA<CCRouteCancelledError>());
  });

  testWidgets('control same-origin singleFlight still shares one dispatch', (
    tester,
  ) async {
    final gate = Completer<CCNavigationInterceptorDecision>();
    var checks = 0;
    final aggregate = await mountMulti(
      tester,
      concurrency: CCNavigationConcurrencyPolicy.singleFlight,
      interceptor: links.CallbackPolicy((context) {
        if (context.request.uri.path != '/detail/A')
          return const CCNavigationProceed();
        checks++;
        return gate.future;
      }),
    );
    final first = CCRouter.navigator.open(Uri.parse('/detail/A'));
    await tester.pump();
    final second = CCRouter.navigator.open(Uri.parse('/detail/A'));
    await tester.pump();
    gate.complete(const CCNavigationProceed());
    await tester.pumpAndSettle();
    await Future.wait([first, second]);
    expect(checks, 1);
    expect(
      aggregate.backendFor('primary').adapter.requests.map((e) => e.uri.path),
      ['/', '/detail/A'],
    );
  });

  testWidgets('control async Proceed keeps originally selected Host', (
    tester,
  ) async {
    final gate = Completer<CCNavigationInterceptorDecision>();
    final aggregate = await mountMulti(
      tester,
      interceptor: links.CallbackPolicy(
        (context) => context.request.uri.path == '/detail/A'
            ? gate.future
            : const CCNavigationProceed(),
      ),
    );
    final pending = CCRouter.navigator.go(const fixture.Intent('A'));
    await tester.pump();
    aggregate.adapter.activateHost('secondary');
    gate.complete(const CCNavigationProceed());
    await tester.pumpAndSettle();
    await pending;
    expect(
      aggregate.backendFor('primary').adapter.requests.single.uri.path,
      '/detail/A',
    );
    expect(
      aggregate.backendFor('secondary').adapter.requests.single.uri.path,
      '/',
    );
  });

  testWidgets('control context-pinned redirect survives focus change', (
    tester,
  ) async {
    final gate = Completer<CCNavigationInterceptorDecision>();
    final aggregate = await mountMulti(
      tester,
      interceptor: links.CallbackPolicy(
        (context) => context.request.uri.path == '/detail/A'
            ? gate.future
            : const CCNavigationProceed(),
      ),
    );
    final context = tester.element(find.text('home').first);
    final pending = CCRouter.navigator.go(
      const fixture.Intent('A'),
      context: context,
    );
    await tester.pump();
    aggregate.adapter.activateHost('secondary');
    gate.complete(const CCNavigationRedirect.toIntent(fixture.Intent('B')));
    await tester.pumpAndSettle();
    await pending;
    expect(
      aggregate.backendFor('primary').adapter.requests.single.uri.path,
      '/detail/B',
    );
    expect(
      aggregate.backendFor('secondary').adapter.requests.single.uri.path,
      '/',
    );
  });

  testWidgets('control deferred redirect stays in originally admitted Host', (
    tester,
  ) async {
    var first = true;
    final aggregate = await mountMulti(
      tester,
      interceptor: links.CallbackPolicy((context) {
        if (context.request.uri.path != '/detail/A')
          return const CCNavigationProceed();
        if (first) {
          first = false;
          return const CCNavigationDefer();
        }
        return const CCNavigationRedirect.toIntent(fixture.Intent('B'));
      }),
    );
    final pending = CCRouter.navigator.go(const fixture.Intent('A'));
    await tester.pump();
    final id = CCRouter.pendingNavigations.single.navigationId;
    aggregate.adapter.activateHost('secondary');
    final resumed = CCRouter.resumePendingNavigation(id);
    await tester.pumpAndSettle();
    await pending;
    await resumed;
    expect(
      aggregate.backendFor('primary').adapter.requests.single.uri.path,
      '/detail/B',
    );
    expect(
      aggregate.backendFor('secondary').adapter.requests.single.uri.path,
      '/',
    );
  });

  for (final policy in [
    CCNavigationConcurrencyPolicy.singleFlight,
    CCNavigationConcurrencyPolicy.rejectDuplicate,
  ]) {
    for (final firstOrigin in CCNavigationOrigin.values) {
      for (final laterOrigin in CCNavigationOrigin.values) {
        if (firstOrigin == laterOrigin) continue;
        testWidgets('$policy isolates $firstOrigin from $laterOrigin', (
          tester,
        ) async {
          final gate = Completer<CCNavigationInterceptorDecision>();
          final checks = <CCNavigationOrigin>[];
          await mountMulti(
            tester,
            concurrency: policy,
            interceptor: links.CallbackPolicy((context) {
              if (context.request.uri.path != '/detail/A')
                return const CCNavigationProceed();
              checks.add(context.request.origin);
              return context.request.origin == firstOrigin
                  ? gate.future
                  : const CCNavigationCancel(code: 'distinct_origin');
            }),
          );
          final first = openFrom(firstOrigin);
          await tester.pump();
          final later = openFrom(
            laterOrigin,
          ).then<Object?>((_) => null, onError: (Object e, StackTrace _) => e);
          await tester.pump();
          gate.complete(const CCNavigationProceed());
          await tester.pumpAndSettle();
          await first;
          expect(checks, [firstOrigin, laterOrigin]);
          expect(await later, isA<CCRouteCancelledError>());
        });
      }
      testWidgets(
        '$policy keeps same-origin failure semantics for $firstOrigin',
        (tester) async {
          final gate = Completer<CCNavigationInterceptorDecision>();
          var checks = 0;
          await mountMulti(
            tester,
            concurrency: policy,
            interceptor: links.CallbackPolicy((context) {
              if (context.request.uri.path != '/detail/A')
                return const CCNavigationProceed();
              checks++;
              return checks == 1 ? gate.future : const CCNavigationProceed();
            }),
          );
          Future<Object?> observedOpen() => openFrom(
            firstOrigin,
          ).then<Object?>((_) => null, onError: (Object e, StackTrace _) => e);
          final first = observedOpen();
          await tester.pump();
          final later = observedOpen();
          await tester.pump();
          gate.complete(const CCNavigationCancel(code: 'first_cancelled'));
          await tester.pumpAndSettle();
          final firstError = await first;
          final laterError = await later;
          expect(checks, 1);
          expect(firstError, isA<CCRouteCancelledError>());
          if (policy == CCNavigationConcurrencyPolicy.singleFlight) {
            expect(laterError, same(firstError));
          } else {
            expect(laterError, isA<CCNavigationDuplicateError>());
          }
          final retry = openFrom(firstOrigin);
          await tester.pumpAndSettle();
          await retry;
          expect(checks, 2);
        },
      );
    }
  }

  for (final operation in [
    'go',
    'reset',
    'push',
    'replace',
    'openPush',
    'openGo',
  ]) {
    for (final recovery in [false, true]) {
      for (final uriTarget in [false, true]) {
        testWidgets(
          '$operation ${recovery ? 'recovery' : 'redirect'} ${uriTarget ? 'URI' : 'Intent'} preserves Shell and parent in admitted Host',
          (tester) async {
            final gate = Completer<CCNavigationInterceptorDecision>();
            final failure = links.RecoveryPolicy();
            final aggregate = await mountMulti(
              tester,
              failurePolicy: recovery ? failure : null,
              interceptor: links.CallbackPolicy(
                (context) => context.request.uri.path == '/detail/A'
                    ? gate.future
                    : const CCNavigationProceed(),
              ),
            );
            final Future<Object?> pending = switch (operation) {
              'go' => CCRouter.navigator.go(const fixture.Intent('A')),
              'reset' => CCRouter.navigator.reset(const fixture.Intent('A')),
              'push' => CCRouter.navigator.push(const fixture.Intent('A')),
              'replace' => CCRouter.navigator.replace(
                const fixture.Intent('A'),
              ),
              'openPush' => CCRouter.navigator.open(Uri.parse('/detail/A')),
              _ => CCDeepLinkIngress.fromPlatform(
                Uri.parse('/detail/A'),
                mode: CCDeepLinkOpenMode.go,
              ),
            };
            await tester.pump();
            if (recovery) {
              gate.complete(const CCNavigationCancel(code: 'recover'));
              await tester.pump();
              expect(failure.calls, 1);
            }
            aggregate.adapter.activateHost('secondary');
            if (recovery) {
              failure.decision.complete(
                uriTarget
                    ? CCNavigationFailureRedirect.toUri(Uri.parse('/pane/B'))
                    : const CCNavigationFailureRedirect.toIntent(
                        PartitionIntent('pane', 'B'),
                      ),
              );
            } else {
              gate.complete(
                uriTarget
                    ? CCNavigationRedirect.toUri(Uri.parse('/pane/B'))
                    : const CCNavigationRedirect.toIntent(
                        PartitionIntent('pane', 'B'),
                      ),
              );
            }
            await tester.pumpAndSettle();
            final requests = aggregate.backendFor('primary').adapter.requests;
            final leaf = requests.singleWhere((r) => r.routeId == 'probe.pane');
            expect(leaf.hostId, 'primary');
            expect(leaf.placement.hostId, 'primary');
            expect(leaf.placement.shellId, 'probe.shell');
            expect(leaf.placement.navigatorOutlet, 'detail');
            expect(leaf.placement.parentRouteId, 'probe.parent');
            final declarative = ['go', 'reset', 'openGo'].contains(operation);
            expect(
              requests.where((r) => r.routeId == 'probe.parent'),
              hasLength(declarative ? 1 : 0),
            );
            expect(
              aggregate
                  .backendFor('secondary')
                  .adapter
                  .requests
                  .single
                  .uri
                  .path,
              '/',
            );
            expect(aggregate.adapter.activeHostId, 'secondary');
            if (operation == 'push' || operation == 'replace') {
              final context = tester.element(find.text('B'));
              CCRouter.navigator.pop(
                result: 'original-result',
                context: context,
              );
              await tester.pumpAndSettle();
              expect(await pending, 'original-result');
            } else {
              await pending;
            }
          },
        );
      }
    }
  }

  for (final recovery in [false, true]) {
    testWidgets(
      'explicit target Host wins during ${recovery ? 'recovery' : 'redirect'}',
      (tester) async {
        final gate = Completer<CCNavigationInterceptorDecision>();
        final failure = links.RecoveryPolicy();
        final aggregate = await mountMulti(
          tester,
          failurePolicy: recovery ? failure : null,
          interceptor: links.CallbackPolicy(
            (context) => context.request.uri.path == '/detail/A'
                ? gate.future
                : const CCNavigationProceed(),
          ),
        );
        final pending = CCRouter.navigator.go(const fixture.Intent('A'));
        await tester.pump();
        if (recovery) {
          gate.complete(const CCNavigationCancel());
          await tester.pump();
          expect(failure.calls, 1);
          failure.decision.complete(
            const CCNavigationFailureRedirect.toIntent(
              PartitionIntent('explicit', 'B'),
            ),
          );
        } else {
          gate.complete(
            const CCNavigationRedirect.toIntent(
              PartitionIntent('explicit', 'B'),
            ),
          );
        }
        await tester.pumpAndSettle();
        await pending;
        expect(
          aggregate.backendFor('secondary').adapter.requests.single.uri.path,
          '/explicit/B',
        );
        expect(
          aggregate.backendFor('primary').adapter.requests.single.uri.path,
          '/',
        );
      },
    );
  }

  testWidgets('explicit initial Host owns later default redirect', (
    tester,
  ) async {
    final gate = Completer<CCNavigationInterceptorDecision>();
    final aggregate = await mountMulti(
      tester,
      interceptor: links.CallbackPolicy(
        (context) => context.request.uri.path == '/explicit/A'
            ? gate.future
            : const CCNavigationProceed(),
      ),
    );
    final pending = CCRouter.navigator.go(
      const PartitionIntent('explicit', 'A'),
    );
    await tester.pump();
    gate.complete(const CCNavigationRedirect.toIntent(fixture.Intent('B')));
    await tester.pumpAndSettle();
    await pending;
    expect(
      aggregate.backendFor('secondary').adapter.requests.single.uri.path,
      '/detail/B',
    );
    expect(
      aggregate.backendFor('primary').adapter.requests.single.uri.path,
      '/',
    );
  });

  testWidgets('resolution failure recovery uses invocation Host snapshot', (
    tester,
  ) async {
    final recovery = links.RecoveryPolicy();
    final aggregate = await mountMulti(tester, failurePolicy: recovery);
    final pending = CCRouter.navigator.open(Uri.parse('/missing'));
    await tester.pump();
    expect(recovery.calls, 1);
    aggregate.adapter.activateHost('secondary');
    recovery.decision.complete(
      const CCNavigationFailureRedirect.toIntent(
        fixture.Intent('B'),
        operation: CCNavigationOperation.go,
      ),
    );
    await tester.pumpAndSettle();
    await pending;
    expect(
      aggregate.backendFor('primary').adapter.requests.single.uri.path,
      '/detail/B',
    );
    expect(
      aggregate.backendFor('secondary').adapter.requests.single.uri.path,
      '/',
    );
  });

  for (final shutdown in [false, true]) {
    testWidgets(
      'pending Back keeps receipt after ${shutdown ? 'shutdown' : 'Host unregister'}',
      (tester) async {
        final aggregate = await mountMulti(tester);
        final result = CCRouter.navigator
            .push(const fixture.Intent('A'))
            .then<Object?>(
              (value) => value,
              onError: (Object e, StackTrace _) => e,
            );
        await tester.pumpAndSettle();
        final gate = Completer<bool>();
        var entered = false;
        // ignore: deprecated_member_use
        ModalRoute.of(tester.element(find.text('A')))!.addScopedWillPopCallback(
          () {
            entered = true;
            return gate.future;
          },
        );
        final pending = CCRouter.navigator.maybePopOutcome(result: 'unused');
        await tester.pump();
        expect(entered, isTrue);
        if (shutdown) {
          await CCRouterHost.shutdown();
        } else {
          aggregate.adapter.unregisterHost(
            'primary',
            replacementActiveHostId: 'secondary',
          );
        }
        await tester.pumpAndSettle();
        final outcome = await pending;
        expect(outcome.hostId, 'primary');
        expect(outcome.removedEntryOwner, CCPopRemovedEntryOwner.none);
        expect(await result, isA<CCNavigationAdapterError>());
        gate.completeError(StateError('late gate error'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final conditional in [false, true]) {
    testWidgets(
      'scoped ${conditional ? 'maybePop' : 'Pop'} reports actual root Popup Outlet',
      (tester) async {
        final aggregate = await mountMulti(tester);
        await CCRouter.navigator.go(const PartitionIntent('pane', 'B'));
        await tester.pumpAndSettle();
        final context = tester.element(find.text('B'));
        final popup = Navigator.of(context, rootNavigator: true).push(
          DialogRoute<String>(
            context: context,
            builder: (_) => const AlertDialog(content: Text('root-popup')),
          ),
        );
        await tester.pumpAndSettle();
        aggregate.adapter.activateHost('secondary');
        final outcome = conditional
            ? await aggregate.adapter.maybePopOutcomeAt(
                hostId: 'primary',
                navigatorOutlet: 'detail',
                result: 'popup-result',
              )
            : aggregate.adapter.popOutcomeAt(
                hostId: 'primary',
                navigatorOutlet: 'detail',
                result: 'popup-result',
              );
        await tester.pumpAndSettle();
        expect(outcome.hostId, 'primary');
        expect(outcome.navigatorOutlet, 'root');
        expect(outcome.removedEntryOwner, CCPopRemovedEntryOwner.foreign);
        expect(await popup, 'popup-result');
        expect(find.text('B'), findsOneWidget);
        expect(
          aggregate.backendFor('secondary').adapter.requests.single.uri.path,
          '/',
        );
      },
    );
  }

  for (final recoveryFirst in [false, true]) {
    for (final deferExplicit in [false, true]) {
      testWidgets(
        'default Host survives explicit hop (recovery=$recoveryFirst defer=$deferExplicit)',
        (tester) async {
          final gate = Completer<CCNavigationInterceptorDecision>();
          final recovery = links.RecoveryPolicy();
          var deferred = false;
          final explicitHosts = <String>[];
          final aggregate = await mountMulti(
            tester,
            failurePolicy: recoveryFirst ? recovery : null,
            interceptor: links.CallbackPolicy((context) {
              if (context.request.uri.path == '/detail/A') return gate.future;
              if (context.request.uri.path != '/explicit/B')
                return const CCNavigationProceed();
              explicitHosts.add(context.request.hostId);
              if (deferExplicit && !deferred) {
                deferred = true;
                return const CCNavigationDefer();
              }
              return const CCNavigationRedirect.toIntent(fixture.Intent('C'));
            }),
          );
          final pending = CCRouter.navigator.go(const fixture.Intent('A'));
          await tester.pump();
          aggregate.adapter.activateHost('secondary');
          if (recoveryFirst) {
            gate.complete(const CCNavigationCancel());
            await tester.pump();
            expect(recovery.calls, 1);
            recovery.decision.complete(
              const CCNavigationFailureRedirect.toIntent(
                PartitionIntent('explicit', 'B'),
              ),
            );
          } else {
            gate.complete(
              const CCNavigationRedirect.toIntent(
                PartitionIntent('explicit', 'B'),
              ),
            );
          }
          await tester.pumpAndSettle();
          Future<Object?>? resumed;
          if (deferExplicit) {
            resumed = CCRouter.resumePendingNavigation(
              CCRouter.pendingNavigations.single.navigationId,
            );
            await tester.pumpAndSettle();
          }
          await pending;
          if (resumed != null) await resumed;
          expect(explicitHosts, everyElement('secondary'));
          expect(explicitHosts, hasLength(deferExplicit ? 2 : 1));
          expect(
            aggregate.backendFor('primary').adapter.requests.single.uri.path,
            '/detail/C',
          );
          expect(
            aggregate.backendFor('secondary').adapter.requests.single.uri.path,
            '/',
          );
        },
      );
    }
  }

  for (final recoveryWait in [false, true]) {
    for (final shutdown in [false, true]) {
      testWidgets(
        '${recoveryWait ? 'recovery' : 'redirect'} cannot switch away from retired Host (shutdown=$shutdown)',
        (tester) async {
          final gate = Completer<CCNavigationInterceptorDecision>();
          final recovery = links.RecoveryPolicy();
          final aggregate = await mountMulti(
            tester,
            failurePolicy: recoveryWait ? recovery : null,
            interceptor: links.CallbackPolicy(
              (context) => context.request.uri.path == '/detail/A'
                  ? gate.future
                  : const CCNavigationProceed(),
            ),
          );
          final pending = CCRouter.navigator
              .go(const fixture.Intent('A'))
              .then<Object?>(
                (_) => null,
                onError: (Object e, StackTrace _) => e,
              );
          await tester.pump();
          if (recoveryWait) {
            gate.complete(const CCNavigationCancel());
            await tester.pump();
            expect(recovery.calls, 1);
          }
          final secondary = aggregate.backendFor('secondary');
          if (shutdown) {
            await CCRouterHost.shutdown();
          } else {
            aggregate.adapter.unregisterHost(
              'primary',
              replacementActiveHostId: 'secondary',
            );
          }
          if (recoveryWait) {
            recovery.decision.complete(
              const CCNavigationFailureRedirect.toIntent(fixture.Intent('B')),
            );
          } else {
            gate.complete(
              const CCNavigationRedirect.toIntent(fixture.Intent('B')),
            );
          }
          await tester.pumpAndSettle();
          expect(await pending, isA<CCRouterError>());
          expect(
            secondary.adapter.requests.where((r) => r.uri.path == '/detail/B'),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'LocalHistory receipt keeps origin when its callback changes focus',
    (tester) async {
      final aggregate = await mountMulti(tester);
      final result = CCRouter.navigator.push(const fixture.Intent('A'));
      await tester.pumpAndSettle();
      final route = ModalRoute.of(tester.element(find.text('A')))!;
      route.addLocalHistoryEntry(
        LocalHistoryEntry(
          onRemove: () => aggregate.adapter.activateHost('secondary'),
        ),
      );
      final outcome = aggregate.adapter.popOutcome(result: 'history-only');
      await tester.pumpAndSettle();
      expect(outcome.hostId, 'primary');
      expect(outcome.removedEntryOwner, CCPopRemovedEntryOwner.none);
      expect(find.text('A'), findsOneWidget);
      final context = tester.element(find.text('A'));
      CCRouter.navigator.pop(result: 'actual-result', context: context);
      await tester.pumpAndSettle();
      expect(await result, 'actual-result');
    },
  );
}
