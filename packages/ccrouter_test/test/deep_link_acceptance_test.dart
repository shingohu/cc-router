import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:test/test.dart';

import 'navigation_test.dart'
    show
        TestIntent,
        RouteArgs,
        RouteArgsCodec,
        TestRegistrar,
        routeComponent,
        pathRoute;

final class _Interceptor implements CCNavigationInterceptor {
  _Interceptor(this.decide);
  final FutureOr<CCNavigationInterceptorDecision> Function(CCNavigationRequest)
  decide;

  @override
  FutureOr<CCNavigationInterceptorDecision> intercept(
    CCNavigationInterceptorContext context,
  ) => decide(context.request);
}

final class _FailurePolicy implements CCNavigationFailurePolicy {
  @override
  CCNavigationFailureDecision onFailure(CCNavigationFailureContext context) =>
      CCNavigationFailureFallback.toIntent(
        const TestIntent<void>('orders.fallback', RouteArgs('fallback')),
        operation: CCNavigationOperation.go,
      );
}

final class _Adapter implements CCNavigationAdapter {
  final delegate = CCMemoryNavigationAdapter();
  final requests = <CCNavigationRequest>[];
  final completions = <Completer<Object?>>[];

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) => delegate.initialize(routes, shells: shells);

  @override
  Future<Object?> navigate(CCNavigationRequest request) {
    requests.add(request);
    delegate.navigate(request);
    final completion = Completer<Object?>();
    completions.add(completion);
    return completion.future;
  }

  @override
  bool canPop() => delegate.canPop();
  @override
  Future<bool> maybePop({Object? result}) => delegate.maybePop(result: result);
  @override
  void pop({Object? result}) => delegate.pop(result: result);
  @override
  void dispose() => delegate.dispose();
}

void _initialize({
  CCNavigationConcurrencyPolicy concurrency =
      CCNavigationConcurrencyPolicy.allow,
  _Interceptor? interceptor,
  CCNavigationFailurePolicy? failurePolicy,
}) {
  CCRouterHost.initialize(
    deepLinkIngressPolicy: CCDeepLinkIngressPolicy(allowRelativePaths: true),
    navigationConcurrencyPolicy: concurrency,
    navigationFailurePolicy: failurePolicy,
    globalInterceptors: [
      if (interceptor != null)
        CCGlobalNavigationInterceptor(id: 'receipt', interceptor: interceptor),
    ],
    hostAssembly: CCHostAssembly.fromComponents(
      components: [
        CCComponentManifest(
          id: 'orders',
          version: '1.0.0',
          registrar: TestRegistrar((registry) {
            for (final name in ['detail', 'fallback']) {
              registry.registerRoute<RouteArgs, String>(
                CCRouteDefinition<RouteArgs, String>(
                  routeId: 'orders.$name',
                  patterns: [CCPathPattern('/$name/:value', primary: true)],
                  codec: const RouteArgsCodec(),
                  deepLink: CCDeepLinkPolicy.enabled,
                ),
              );
            }
          }),
        ),
      ],
    ),
  );
}

void main() {
  tearDown(CCRouterHost.shutdown);

  test(
    'all ingress methods return exact immutable acceptance identities',
    () async {
      _initialize();
      CCRouterHostBinding.attachNavigationAdapter(CCMemoryNavigationAdapter());
      for (final ingress in [
        CCDeepLinkIngress.fromPlatform,
        CCDeepLinkIngress.fromNotification,
        CCDeepLinkIngress.fromQrCode,
      ]) {
        final CCDeepLinkAcceptanceReceipt receipt = await ingress(
          Uri.parse('/detail/1'),
        );
        final entry = CCRouter.activeRouteEntries.last;
        expect(receipt.navigationId, entry.navigationId);
        expect(receipt.entryNavigationId, entry.navigationId);
        expect(receipt.routeEntryId, entry.routeEntryId);
        expect(receipt.routeId, 'orders.detail');
      }
    },
  );

  test('out-of-order acceptance never selects the latest Entry', () async {
    _initialize();
    final adapter = _Adapter();
    CCRouterHostBinding.attachNavigationAdapter(adapter);
    final first = CCDeepLinkIngress.fromPlatform(Uri.parse('/detail/1'));
    final second = CCDeepLinkIngress.fromPlatform(Uri.parse('/detail/1'));
    final entries = CCRouter.activeRouteEntries;
    expect(entries, hasLength(2));
    var firstCompleted = false;
    unawaited(first.then((_) => firstCompleted = true));
    adapter.completions[1].complete();
    final secondReceipt = await second;
    expect(firstCompleted, isFalse);
    adapter.completions[0].complete();
    final firstReceipt = await first;
    expect(firstReceipt.routeEntryId, entries.first.routeEntryId);
    expect(secondReceipt.routeEntryId, entries.last.routeEntryId);
    expect(firstReceipt.navigationId, isNot(secondReceipt.navigationId));
  });

  test('singleFlight shares Entry but preserves each invocation ID', () async {
    _initialize(concurrency: CCNavigationConcurrencyPolicy.singleFlight);
    final adapter = _Adapter();
    CCRouterHostBinding.attachNavigationAdapter(adapter);
    final first = CCDeepLinkIngress.fromPlatform(Uri.parse('/detail/1'));
    final second = CCDeepLinkIngress.fromPlatform(Uri.parse('/detail/1'));
    expect(adapter.requests, hasLength(1));
    adapter.completions.single.complete();
    final receipts = await Future.wait([first, second]);
    expect(receipts[0].routeEntryId, receipts[1].routeEntryId);
    expect(receipts[0].navigationId, isNot(receipts[1].navigationId));
    expect(receipts[1].entryNavigationId, receipts[0].navigationId);
    expect(CCRouter.activeRouteEntries, hasLength(1));
    expect(
      CCRouter.recentNavigationEvents
          .where((event) => event.phase == CCNavigationLifecyclePhase.completed)
          .map((event) => event.navigationId),
      containsAll(receipts.map((receipt) => receipt.navigationId)),
    );
  });

  test('singleFlight follower can join an existing non-receipt Open', () async {
    final adapter = _Adapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      navigationConcurrencyPolicy: CCNavigationConcurrencyPolicy.singleFlight,
      deepLinkIngressPolicy: CCDeepLinkIngressPolicy(allowRelativePaths: true),
      components: [
        routeComponent('orders', (registry) {
          registry.registerRoute(
            pathRoute(
              path: '/detail/:value',
              deepLink: CCDeepLinkPolicy.enabled,
            ),
          );
        }),
      ],
    );
    runtime.initialize();
    addTearDown(runtime.dispose);
    final uri = Uri.parse('/detail/1');
    final producer = runtime.openRoute(
      uri,
      origin: CCNavigationOrigin.externalPlatform,
    );
    final follower = runtime.openRouteWithReceipt(
      uri,
      origin: CCNavigationOrigin.externalPlatform,
    );
    expect(adapter.requests, hasLength(1));
    adapter.completions.single.complete();
    await producer;
    final receipt = await follower;
    expect(receipt.entryNavigationId, adapter.requests.single.navigationId);
    expect(receipt.navigationId, isNot(receipt.entryNavigationId));
    expect(
      receipt.routeEntryId,
      runtime.activeRouteEntries.single.routeEntryId,
    );
  });

  test(
    'duplicate rejection keeps the admitted ingress receipt intact',
    () async {
      _initialize(concurrency: CCNavigationConcurrencyPolicy.rejectDuplicate);
      final adapter = _Adapter();
      CCRouterHostBinding.attachNavigationAdapter(adapter);
      final accepted = CCDeepLinkIngress.fromPlatform(Uri.parse('/detail/1'));
      await expectLater(
        CCDeepLinkIngress.fromPlatform(Uri.parse('/detail/1')),
        throwsA(isA<CCNavigationDuplicateError>()),
      );
      expect(adapter.requests, hasLength(1));
      adapter.completions.single.complete();
      expect(
        (await accepted).routeEntryId,
        CCRouter.activeRouteEntries.single.routeEntryId,
      );
    },
  );

  for (final withReceipt in [false, true]) {
    test('shutdown keeps Adapter settlement, receipt=$withReceipt', () async {
      _initialize();
      final adapter = _Adapter();
      CCRouterHostBinding.attachNavigationAdapter(adapter);
      final uri = Uri.parse('/detail/1');
      final Future<void> work = withReceipt
          ? CCDeepLinkIngress.fromPlatform(uri)
          : CCRouter.navigator.open(uri);
      final pending = expectLater(
        work,
        throwsA(isA<CCNavigationAdapterError>()),
      );
      await CCRouterHost.shutdown();
      adapter.completions.single.completeError(StateError('late rejection'));
      await pending;
    });
  }

  test(
    'redirect and failure fallback identify the actual destination',
    () async {
      _initialize(
        interceptor: _Interceptor(
          (request) => request.routeId == 'orders.detail'
              ? CCNavigationRedirect.toUri(Uri.parse('/fallback/redirect'))
              : const CCNavigationProceed(),
        ),
        failurePolicy: _FailurePolicy(),
      );
      CCRouterHostBinding.attachNavigationAdapter(CCMemoryNavigationAdapter());
      for (final path in ['/detail/1', '/missing']) {
        final receipt = await CCDeepLinkIngress.fromPlatform(Uri.parse(path));
        expect(receipt.routeId, 'orders.fallback');
        expect(
          receipt.routeEntryId,
          CCRouter.activeRouteEntries.last.routeEntryId,
        );
      }
    },
  );

  test('defer waits for resume and keeps the original navigation ID', () async {
    var authorized = false;
    _initialize(
      interceptor: _Interceptor(
        (_) => authorized
            ? const CCNavigationProceed()
            : const CCNavigationDefer(),
      ),
    );
    CCRouterHostBinding.attachNavigationAdapter(CCMemoryNavigationAdapter());
    final pending = CCDeepLinkIngress.fromNotification(Uri.parse('/detail/1'));
    var completed = false;
    unawaited(pending.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(CCRouter.activeRouteEntries, isEmpty);
    final navigationId = CCRouter.pendingNavigations.single.navigationId;
    authorized = true;
    await CCRouter.resumePendingNavigation(navigationId);
    final receipt = await pending;
    expect(receipt.navigationId, navigationId);
    expect(
      receipt.routeEntryId,
      CCRouter.activeRouteEntries.single.routeEntryId,
    );
  });

  test(
    'asynchronous adapter rejection still throws and releases Entry',
    () async {
      _initialize();
      final adapter = _Adapter();
      CCRouterHostBinding.attachNavigationAdapter(adapter);
      final rejected = expectLater(
        CCDeepLinkIngress.fromQrCode(Uri.parse('/detail/1')),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      adapter.completions.single.completeError(StateError('rejected'));
      await rejected;
      expect(CCRouter.activeRouteEntries, isEmpty);
    },
  );

  test('fallback replaces a failed committed attempt identity', () async {
    _initialize(failurePolicy: _FailurePolicy());
    final adapter = _Adapter();
    CCRouterHostBinding.attachNavigationAdapter(adapter);
    final pending = CCDeepLinkIngress.fromPlatform(Uri.parse('/detail/1'));
    final failedEntry = CCRouter.activeRouteEntries.single.routeEntryId;
    adapter.completions.first.completeError(StateError('rejected'));
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requests, hasLength(2));
    adapter.completions.last.complete();
    final receipt = await pending;
    expect(receipt.routeId, 'orders.fallback');
    expect(receipt.routeEntryId, isNot(failedEntry));
    expect(
      receipt.routeEntryId,
      CCRouter.activeRouteEntries.single.routeEntryId,
    );
  });

  for (final shutdown in [false, true]) {
    test(
      'deferred ingress throws on ${shutdown ? 'shutdown' : 'cancel'}',
      () async {
        _initialize(
          interceptor: _Interceptor((_) => const CCNavigationDefer()),
        );
        CCRouterHostBinding.attachNavigationAdapter(
          CCMemoryNavigationAdapter(),
        );
        final pending = expectLater(
          CCDeepLinkIngress.fromPlatform(Uri.parse('/detail/1')),
          throwsA(isA<CCRouteCancelledError>()),
        );
        await Future<void>.delayed(Duration.zero);
        if (shutdown) {
          await CCRouterHost.shutdown();
        } else {
          expect(
            CCRouter.cancelPendingNavigation(
              CCRouter.pendingNavigations.single.navigationId,
            ),
            isTrue,
          );
        }
        await pending;
      },
    );
  }

  test('singleFlight retains receipt across defer and resume', () async {
    var authorized = false;
    _initialize(
      concurrency: CCNavigationConcurrencyPolicy.singleFlight,
      interceptor: _Interceptor(
        (_) => authorized
            ? const CCNavigationProceed()
            : const CCNavigationDefer(),
      ),
    );
    CCRouterHostBinding.attachNavigationAdapter(CCMemoryNavigationAdapter());
    final first = CCDeepLinkIngress.fromPlatform(Uri.parse('/detail/1'));
    final second = CCDeepLinkIngress.fromPlatform(Uri.parse('/detail/1'));
    await Future<void>.delayed(Duration.zero);
    expect(CCRouter.pendingNavigations, hasLength(1));
    authorized = true;
    await CCRouter.resumePendingNavigation(
      CCRouter.pendingNavigations.single.navigationId,
    );
    final receipts = await Future.wait([first, second]);
    expect(receipts[0].routeEntryId, receipts[1].routeEntryId);
    expect(receipts[1].entryNavigationId, receipts[0].navigationId);
    expect(receipts[0].navigationId, isNot(receipts[1].navigationId));
  });

  test(
    'receipt survives Entry removal and Runtime shutdown as history',
    () async {
      _initialize();
      CCRouterHostBinding.attachNavigationAdapter(CCMemoryNavigationAdapter());
      final receipt = await CCDeepLinkIngress.fromPlatform(
        Uri.parse('/detail/1'),
      );
      final replacement = await CCDeepLinkIngress.fromPlatform(
        Uri.parse('/detail/1'),
        mode: CCDeepLinkOpenMode.go,
      );
      expect(receipt.routeEntryId, isNot(replacement.routeEntryId));
      expect(CCRouter.activeRouteEntries, hasLength(1));
      await CCRouterHost.shutdown();
      expect(receipt.routeId, 'orders.detail');
      expect(receipt.entryNavigationId, receipt.navigationId);
    },
  );

  test(
    'ordinary navigation and ignored-value success callers stay compatible',
    () async {
      _initialize(concurrency: CCNavigationConcurrencyPolicy.singleFlight);
      CCRouterHostBinding.attachNavigationAdapter(CCMemoryNavigationAdapter());
      const intent = TestIntent<String>('orders.detail', RouteArgs('typed'));
      final first = CCRouter.navigator.push(intent);
      final shared = CCRouter.navigator.push(intent);
      expect(CCRouter.activeRouteEntries, hasLength(1));
      CCRouter.navigator.pop(result: 'shared result');
      expect(await first, 'shared result');
      expect(await shared, 'shared result');
      final replaced = CCRouter.navigator.replace(intent);
      CCRouter.navigator.pop(result: 'replacement result');
      expect(await replaced, 'replacement result');
      final Future<void> go = CCRouter.navigator.go(intent);
      await go;
      final Future<void> reset = CCRouter.navigator.reset(intent);
      await reset;
      final Future<void> open = CCRouter.navigator.open(
        Uri.parse('/detail/open'),
      );
      await open;
      final Future<void> Function(Uri) legacyCaller =
          CCDeepLinkIngress.fromPlatform;
      final Future<void> ingress = legacyCaller(Uri.parse('/detail/legacy'));
      await ingress;
      unawaited(CCDeepLinkIngress.fromQrCode(Uri.parse('/detail/unawaited')));
      await Future<void>.delayed(Duration.zero);
      expect(CCRouter.activeRouteEntries, hasLength(4));
    },
  );

  for (final ingress in {
    'platform': CCDeepLinkIngress.fromPlatform,
    'notification': CCDeepLinkIngress.fromNotification,
    'QR': CCDeepLinkIngress.fromQrCode,
  }.entries) {
    for (final cancelled in [false, true]) {
      test('${ingress.key} void error-handler migration on '
          '${cancelled ? 'cancellation' : 'Host rejection'}', () async {
        _initialize(
          interceptor: cancelled
              ? _Interceptor(
                  (_) => const CCNavigationCancel(code: 'legacy_cancelled'),
                )
              : null,
        );
        CCRouterHostBinding.attachNavigationAdapter(
          CCMemoryNavigationAdapter(),
        );
        final uri = cancelled
            ? Uri.parse('/detail/1')
            : Uri.parse('https://untrusted.example/detail/1');
        final expectedError = cancelled
            ? isA<CCRouteCancelledError>()
            : isA<CCDeepLinkIngressRejectedError>();
        final handledErrors = <Object>[];

        // A static void return annotation does not convert the actual Future.
        Future<void> legacyOpen() => ingress.value(uri);
        await expectLater(
          legacyOpen().catchError((Object error) {
            handledErrors.add(error);
          }),
          throwsA(isA<ArgumentError>()),
        );
        expect(handledErrors, [expectedError]);

        // Convert before catchError so a void handler may consume the error.
        await ingress.value(uri).then<void>((_) {}).catchError((Object error) {
          handledErrors.add(error);
        });
        expect(handledErrors, [expectedError, expectedError]);

        // Hosts already using try/catch need no conversion or new receipt.
        try {
          await ingress.value(uri);
        } on Object catch (error) {
          handledErrors.add(error);
        }
        expect(handledErrors, [expectedError, expectedError, expectedError]);
        expect(CCRouter.activeRouteEntries, isEmpty);
      });
    }
  }
}
