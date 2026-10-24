import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:test/test.dart';

final class _Arguments {
  const _Arguments(this.value);

  final String value;
}

final class _Codec implements CCRouteCodec<_Arguments> {
  const _Codec();

  @override
  _Arguments decode(CCRouteCodecValues input) =>
      _Arguments(input.path['value'] ?? 'root');

  @override
  CCRouteCodecValues encode(_Arguments arguments) =>
      CCRouteCodecValues(path: {'value': arguments.value});
}

final class _Intent implements CCRouteIntent<Object?> {
  const _Intent(this.routeId, [this.value = 'target']);

  @override
  final String routeId;

  final String value;

  @override
  Object get arguments => _Arguments(value);
}

final class _Registrar implements CCComponentRegistrar {
  const _Registrar();

  @override
  void register(CCRegistry registry) {
    for (final routeId in ['home', 'protected', 'replacement']) {
      registry.registerRoute<_Arguments, Object?>(
        CCRouteDefinition(
          routeId: 'test.$routeId',
          patterns: [CCPathPattern('/$routeId/:value', primary: true)],
          codec: const _Codec(),
        ),
      );
    }
    registry.registerRoute<_Arguments, Object?>(
      CCRouteDefinition(
        routeId: 'test.other_host',
        patterns: [CCPathPattern('/other-host/:value', primary: true)],
        codec: const _Codec(),
        placement: const CCRoutePlacement(
          hostId: 'secondary',
          navigatorOutlet: 'detail',
        ),
      ),
    );
    registry.registerRoute<_Arguments, Object?>(
      CCRouteDefinition(
        routeId: 'test.other_outlet',
        patterns: [CCPathPattern('/other-outlet/:value', primary: true)],
        codec: const _Codec(),
        placement: const CCRoutePlacement(navigatorOutlet: 'detail'),
      ),
    );
  }
}

final class _Policy implements CCRouteRevalidationPolicy {
  _Policy(this.evaluateCallback);

  final FutureOr<CCRouteRevalidationDecision> Function(
    CCRouteRevalidationContext context,
  )
  evaluateCallback;

  @override
  FutureOr<CCRouteRevalidationDecision> evaluate(
    CCRouteRevalidationContext context,
  ) => evaluateCallback(context);
}

final class _CrossHostRedirectInterceptor implements CCNavigationInterceptor {
  const _CrossHostRedirectInterceptor();

  @override
  CCNavigationInterceptorDecision intercept(
    CCNavigationInterceptorContext context,
  ) => context.request.routeId == 'test.replacement'
      ? const CCNavigationRedirect.toIntent(_Intent('test.other_host'))
      : const CCNavigationProceed();
}

final class _CrossHostFailurePolicy implements CCNavigationFailurePolicy {
  const _CrossHostFailurePolicy();

  @override
  CCNavigationFailureDecision onFailure(CCNavigationFailureContext context) =>
      const CCNavigationFailureRedirect.toIntent(_Intent('test.other_host'));
}

final class _CrossOperationFailurePolicy implements CCNavigationFailurePolicy {
  const _CrossOperationFailurePolicy();

  @override
  CCNavigationFailureDecision onFailure(CCNavigationFailureContext context) =>
      const CCNavigationFailureRedirect.toIntent(
        _Intent('test.replacement'),
        operation: CCNavigationOperation.push,
      );
}

final class _SamePartitionFailurePolicy implements CCNavigationFailurePolicy {
  const _SamePartitionFailurePolicy();

  @override
  CCNavigationFailureDecision onFailure(CCNavigationFailureContext context) =>
      const CCNavigationFailureRedirect.toIntent(_Intent('test.replacement'));
}

final class _DeferringReplacementInterceptor
    implements CCNavigationInterceptor {
  const _DeferringReplacementInterceptor();

  @override
  CCNavigationInterceptorDecision intercept(
    CCNavigationInterceptorContext context,
  ) => context.request.routeId == 'test.replacement'
      ? const CCNavigationDefer(code: 'test.awaiting_access')
      : const CCNavigationProceed();
}

final class _DeferReplacementOnceInterceptor
    implements CCNavigationInterceptor {
  bool shouldDefer = true;

  @override
  CCNavigationInterceptorDecision intercept(
    CCNavigationInterceptorContext context,
  ) {
    if (context.request.routeId != 'test.replacement' || !shouldDefer) {
      return const CCNavigationProceed();
    }
    shouldDefer = false;
    return const CCNavigationDefer(code: 'test.awaiting_access');
  }
}

final class _BlockingReplacementInterceptor implements CCNavigationInterceptor {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<CCNavigationInterceptorDecision> intercept(
    CCNavigationInterceptorContext context,
  ) async {
    if (context.request.routeId != 'test.replacement') {
      return const CCNavigationProceed();
    }
    if (!started.isCompleted) started.complete();
    await release.future;
    return const CCNavigationProceed();
  }
}

/// Deliberately separates legacy asynchronous rejection and pending close work.
class _ControlledAdapter
    implements
        CCNavigationAdapter,
        CCNavigationTargetedCloseAdapter,
        CCNavigationAdapterCapabilitySource {
  final delegate = CCMemoryNavigationAdapter();
  final closeStarted = Completer<void>();
  final closeCompletion = Completer<CCRouteCloseOutcome>();
  bool blockClose = false;
  bool blockReset = false;
  Object? closeError;
  bool rejectReplace = false;
  bool disposed = false;
  int replaceCalls = 0;
  final resetCompletion = Completer<Object?>();

  @override
  CCNavigationAdapterCapabilities get capabilities => delegate.capabilities;

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) => delegate.initialize(routes, shells: shells);

  @override
  Future<Object?> navigate(CCNavigationRequest request) {
    if (request.operation == CCNavigationOperation.replace) {
      replaceCalls++;
      if (rejectReplace)
        return Future<Object?>.error(
          const CCNavigationAdapterError('rejected'),
        );
    }
    if (blockReset && request.operation == CCNavigationOperation.reset)
      return resetCompletion.future;
    return delegate.navigate(request);
  }

  @override
  Future<CCRouteCloseOutcome> closeNavigation({
    required String navigationId,
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) {
    final error = closeError;
    if (error != null) throw error;
    if (blockClose) {
      closeStarted.complete();
      return closeCompletion.future;
    }
    return delegate.closeNavigation(
      navigationId: navigationId,
      hostId: hostId,
      navigatorOutlet: navigatorOutlet,
      result: result,
    );
  }

  @override
  Future<bool> maybePop({Object? result}) => delegate.maybePop(result: result);
  @override
  void pop({Object? result}) => delegate.pop(result: result);
  @override
  bool canPop() => delegate.canPop();
  @override
  void dispose() {
    disposed = true;
    delegate.dispose();
  }
}

final class _RejectingDispatchAdapter extends _ControlledAdapter
    implements CCNavigationDispatchAdapter {
  @override
  CCNavigationDispatch dispatchNavigation(CCNavigationRequest request) {
    replaceCalls++;
    throw const CCNavigationAdapterError('rejected before commit');
  }
}

CCRouterRuntime _runtime(
  CCRouteRevalidationPolicy policy, {
  Duration? timeout,
  Iterable<CCGlobalNavigationInterceptor> globalInterceptors = const [],
  CCNavigationFailurePolicy? navigationFailurePolicy,
  CCNavigationConcurrencyPolicy navigationConcurrencyPolicy =
      CCNavigationConcurrencyPolicy.allow,
  CCNavigationAdapter? navigationAdapter,
}) {
  final runtime = CCRouterRuntime.forTesting(
    navigationAdapter: navigationAdapter ?? CCMemoryNavigationAdapter(),
    globalInterceptors: globalInterceptors,
    navigationFailurePolicy: navigationFailurePolicy,
    navigationConcurrencyPolicy: navigationConcurrencyPolicy,
    routeRevalidationPolicies: [
      CCGlobalRouteRevalidationPolicy(
        id: 'test.active.policy',
        policy: policy,
        timeout: timeout,
      ),
    ],
    components: const [
      CCComponentManifest(
        id: 'test_component',
        version: '1.0.0',
        registrar: _Registrar(),
      ),
    ],
  );
  runtime.initialize();
  return runtime;
}

Future<void> _open(
  CCRouterRuntime runtime,
  String routeId, {
  CCNavigationOperation operation = CCNavigationOperation.go,
}) async {
  final intent = _Intent(routeId);
  switch (operation) {
    case CCNavigationOperation.go:
      await runtime.goRoute(intent);
    case CCNavigationOperation.reset:
      await runtime.resetRoute(intent);
    case CCNavigationOperation.push:
      unawaited(runtime.pushRoute(intent));
      await Future<void>.delayed(Duration.zero);
    case CCNavigationOperation.replace:
      unawaited(runtime.replaceRoute(intent));
      await Future<void>.delayed(Duration.zero);
    case CCNavigationOperation.open:
      throw UnsupportedError('Tests use typed navigation only.');
  }
}

void main() {
  test(
    'Backend close failure is sanitized and leaves the target intact',
    () async {
      final adapter = _ControlledAdapter()
        ..closeError = StateError('private Backend payload');
      final runtime = _runtime(
        _Policy((_) => const CCRouteRevalidationClose()),
        navigationAdapter: adapter,
      );
      addTearDown(runtime.dispose);
      await _open(runtime, 'test.home');
      final before = runtime.activeRouteEntries.single.handle;
      await expectLater(
        runtime.revalidateActiveRoutes(reason: 'permission_changed'),
        throwsA(
          isA<CCNavigationAdapterError>().having(
            (error) => error.toString(),
            'sanitized message',
            isNot(contains('private Backend payload')),
          ),
        ),
      );
      expect(runtime.activeRouteEntries.single.handle, same(before));
      expect(adapter.delegate.stack.single.routeId, 'test.home');
    },
  );
  test(
    'legacy asynchronous rejection cannot be reported as replace acceptance',
    () async {
      final adapter = _ControlledAdapter()..rejectReplace = true;
      final runtime = _runtime(
        _Policy(
          (_) => const CCRouteRevalidationReplace(_Intent('test.replacement')),
        ),
        navigationAdapter: adapter,
      );
      addTearDown(runtime.dispose);
      await _open(runtime, 'test.home');
      final before = runtime.activeRouteEntries.single.handle;
      final report = await runtime.revalidateActiveRoutes(
        reason: 'permission_changed',
      );
      expect(
        report.entries.single.outcome,
        CCRouteRevalidationOutcome.unsupported,
      );
      expect(adapter.replaceCalls, 0);
      expect(runtime.activeRouteEntries.single.handle, same(before));
      expect(adapter.delegate.stack.single.routeId, 'test.home');
    },
  );

  test(
    'explicit dispatch rejection preserves the original Entry and propagates',
    () async {
      final adapter = _RejectingDispatchAdapter();
      final runtime = _runtime(
        _Policy(
          (_) => const CCRouteRevalidationReplace(_Intent('test.replacement')),
        ),
        navigationAdapter: adapter,
      );
      addTearDown(runtime.dispose);
      await _open(runtime, 'test.home');
      final before = runtime.activeRouteEntries.single.handle;
      await expectLater(
        runtime.revalidateActiveRoutes(reason: 'permission_changed'),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(adapter.replaceCalls, 1);
      expect(runtime.activeRouteEntries.single.handle, same(before));
      expect(adapter.delegate.stack.single.routeId, 'test.home');
    },
  );

  for (final lateError in [false, true]) {
    test(
      'shutdown cancels Backend close and ignores late ${lateError ? "error" : "success"}',
      () async {
        final adapter = _ControlledAdapter()..blockClose = true;
        final runtime = _runtime(
          _Policy((_) => const CCRouteRevalidationClose()),
          navigationAdapter: adapter,
        );
        await _open(runtime, 'test.home');
        final pass = runtime
            .revalidateActiveRoutes(reason: 'permission_changed')
            .then<Object?>(
              (report) => report,
              onError: (Object error) => error,
            );
        await adapter.closeStarted.future;
        final queued = runtime
            .revalidateActiveRoutes(reason: 'queued_permission_changed')
            .then<Object?>(
              (report) => report,
              onError: (Object error) => error,
            );
        final shutdown = runtime.dispose();
        try {
          await shutdown.timeout(const Duration(seconds: 1));
          expect(adapter.disposed, isTrue);
          expect(await pass, isA<CCRouteCancelledError>());
          expect(await queued, isA<CCRouteCancelledError>());
          expect(runtime.activeRouteEntries, isEmpty);
        } finally {
          if (lateError) {
            adapter.closeCompletion.completeError(
              StateError('late Backend failure'),
            );
          } else {
            adapter.closeCompletion.complete(
              const CCRouteCloseOutcome(CCRouteCloseStatus.closed),
            );
          }
          await pass;
          await shutdown;
        }
        await Future<void>.delayed(Duration.zero);
        expect(runtime.activeRouteEntries, isEmpty);
        expect(runtime.recentNavigationEvents, isEmpty);
        expect(runtime.recentRouteEntryEvents, isEmpty);
      },
    );
  }

  test('shutdown cancels a pending Backend reset acceptance', () async {
    final adapter = _ControlledAdapter()..blockReset = true;
    final runtime = _runtime(
      _Policy(
        (_) => const CCRouteRevalidationReset(_Intent('test.replacement')),
      ),
      navigationAdapter: adapter,
    );
    await _open(runtime, 'test.home');
    final pass = runtime
        .revalidateActiveRoutes(reason: 'permission_changed')
        .then<Object?>((report) => report, onError: (Object error) => error);
    await Future<void>.delayed(Duration.zero);
    final shutdown = runtime.dispose();
    try {
      await shutdown.timeout(const Duration(seconds: 1));
      expect(adapter.disposed, isTrue);
      expect(await pass, isA<CCRouteCancelledError>());
    } finally {
      adapter.resetCompletion.completeError(
        const CCNavigationAdapterError('late rejection'),
      );
      await pass;
      await shutdown;
    }
    await Future<void>.delayed(Duration.zero);
    expect(runtime.activeRouteEntries, isEmpty);
    expect(runtime.recentNavigationEvents, isEmpty);
    expect(runtime.recentRouteEntryEvents, isEmpty);
  });
  test(
    'revalidation closes an exact covered entry and keeps siblings',
    () async {
      final runtime = _runtime(
        _Policy(
          (context) => context.entry.routeId == 'test.protected'
              ? const CCRouteRevalidationClose()
              : const CCRouteRevalidationKeep(),
        ),
      );
      addTearDown(runtime.dispose);
      await _open(runtime, 'test.home');
      await _open(
        runtime,
        'test.protected',
        operation: CCNavigationOperation.push,
      );
      await _open(runtime, 'test.home', operation: CCNavigationOperation.push);

      final report = await runtime.revalidateActiveRoutes(
        reason: 'authentication_changed',
      );

      expect(report.changed, isTrue);
      expect(
        report.entries
            .singleWhere((entry) => entry.routeId == 'test.protected')
            .outcome,
        CCRouteRevalidationOutcome.closed,
      );
      expect(runtime.activeRouteEntries.map((entry) => entry.routeId), [
        'test.home',
        'test.home',
      ]);
    },
  );

  test(
    'revalidation replaces the current entry and returns on acceptance',
    () async {
      final runtime = _runtime(
        _Policy(
          (context) => context.entry.routeId == 'test.protected'
              ? const CCRouteRevalidationReplace(_Intent('test.replacement'))
              : const CCRouteRevalidationKeep(),
        ),
      );
      addTearDown(runtime.dispose);
      await _open(runtime, 'test.home');
      await _open(
        runtime,
        'test.protected',
        operation: CCNavigationOperation.push,
      );

      final report = await runtime
          .revalidateActiveRoutes(reason: 'permission_changed')
          .timeout(const Duration(seconds: 1));

      expect(report.changed, isTrue);
      expect(
        report.entries
            .singleWhere((entry) => entry.routeId == 'test.protected')
            .outcome,
        CCRouteRevalidationOutcome.replaced,
      );
      expect(runtime.activeRouteEntries.last.routeId, 'test.replacement');
    },
  );

  test('replace cannot escape the original Host or Outlet', () async {
    for (final target in ['test.other_host', 'test.other_outlet']) {
      final runtime = _runtime(
        _Policy((_) => CCRouteRevalidationReplace(_Intent(target))),
      );
      await _open(runtime, 'test.home');
      final before = runtime.activeRouteEntries.single.handle;

      final report = await runtime.revalidateActiveRoutes(
        reason: 'permission_changed',
      );

      expect(report.changed, isFalse, reason: target);
      expect(
        report.entries.single.outcome,
        CCRouteRevalidationOutcome.unsupported,
      );
      expect(runtime.activeRouteEntries.single.handle, same(before));
      await runtime.dispose();
    }
  });

  test(
    'replace fence survives interceptor and failure-policy redirects',
    () async {
      final scenarios = <CCRouterRuntime>[
        _runtime(
          _Policy(
            (_) =>
                const CCRouteRevalidationReplace(_Intent('test.replacement')),
          ),
          globalInterceptors: const [
            CCGlobalNavigationInterceptor(
              id: 'test.cross_host_redirect',
              interceptor: _CrossHostRedirectInterceptor(),
            ),
          ],
        ),
        _runtime(
          _Policy(
            (_) => const CCRouteRevalidationReplace(_Intent('test.missing')),
          ),
          navigationFailurePolicy: const _CrossHostFailurePolicy(),
        ),
        _runtime(
          _Policy(
            (_) => const CCRouteRevalidationReplace(_Intent('test.missing')),
          ),
          navigationFailurePolicy: const _CrossOperationFailurePolicy(),
        ),
      ];

      for (final runtime in scenarios) {
        await _open(runtime, 'test.home');
        final before = runtime.activeRouteEntries.single.handle;

        final report = await runtime.revalidateActiveRoutes(
          reason: 'permission_changed',
        );

        expect(report.changed, isFalse);
        expect(
          report.entries.single.outcome,
          CCRouteRevalidationOutcome.unsupported,
        );
        expect(runtime.activeRouteEntries.single.handle, same(before));
        await runtime.dispose();
      }
    },
  );

  test('replace returns on a valid same-partition failure recovery', () async {
    final runtime = _runtime(
      _Policy((_) => const CCRouteRevalidationReplace(_Intent('test.missing'))),
      navigationFailurePolicy: const _SamePartitionFailurePolicy(),
    );
    addTearDown(runtime.dispose);
    await _open(runtime, 'test.home');

    final report = await runtime
        .revalidateActiveRoutes(reason: 'permission_changed')
        .timeout(const Duration(seconds: 1));

    expect(report.changed, isTrue);
    expect(report.entries.single.outcome, CCRouteRevalidationOutcome.replaced);
    expect(runtime.activeRouteEntries.single.routeId, 'test.replacement');
  });

  test('replace is isolated from single-flight business navigation', () async {
    final runtime = _runtime(
      _Policy(
        (_) => const CCRouteRevalidationReplace(_Intent('test.replacement')),
      ),
      navigationConcurrencyPolicy: CCNavigationConcurrencyPolicy.singleFlight,
    );
    addTearDown(runtime.dispose);
    await _open(runtime, 'test.home');
    final businessReplace = runtime.replaceRoute<Object?>(
      const _Intent('test.replacement'),
    );
    await Future<void>.delayed(Duration.zero);
    final businessEntry = runtime.activeRouteEntries.single.handle;

    final report = await runtime
        .revalidateActiveRoutes(reason: 'permission_changed')
        .timeout(const Duration(seconds: 1));

    expect(await businessReplace, isNull);
    expect(report.entries.single.outcome, CCRouteRevalidationOutcome.replaced);
    expect(
      runtime.activeRouteEntries.single.handle,
      isNot(same(businessEntry)),
    );
  });

  test('replace returns on commit after a deferred request resumes', () async {
    final interceptor = _DeferReplacementOnceInterceptor();
    final runtime = _runtime(
      _Policy(
        (_) => const CCRouteRevalidationReplace(_Intent('test.replacement')),
      ),
      globalInterceptors: [
        CCGlobalNavigationInterceptor(
          id: 'test.defer_replacement_once',
          interceptor: interceptor,
        ),
      ],
    );
    addTearDown(runtime.dispose);
    await _open(runtime, 'test.home');

    final revalidation = runtime.revalidateActiveRoutes(
      reason: 'permission_changed',
    );
    while (runtime.pendingNavigations.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final resume = runtime.resumePendingNavigation(
      runtime.pendingNavigations.single.navigationId,
    );

    final report = await revalidation.timeout(const Duration(seconds: 1));
    expect(report.entries.single.outcome, CCRouteRevalidationOutcome.replaced);
    expect(runtime.activeRouteEntries.single.routeId, 'test.replacement');
    runtime.popRoute();
    await resume;
  });

  test(
    'replace rechecks topmost identity after asynchronous interception',
    () async {
      final interceptor = _BlockingReplacementInterceptor();
      final runtime = _runtime(
        _Policy(
          (_) => const CCRouteRevalidationReplace(_Intent('test.replacement')),
        ),
        globalInterceptors: [
          CCGlobalNavigationInterceptor(
            id: 'test.block_replacement',
            interceptor: interceptor,
          ),
        ],
      );
      addTearDown(runtime.dispose);
      await _open(runtime, 'test.home');

      final revalidation = runtime.revalidateActiveRoutes(
        reason: 'permission_changed',
      );
      await interceptor.started.future;
      await _open(runtime, 'test.home', operation: CCNavigationOperation.push);
      interceptor.release.complete();
      final report = await revalidation;

      expect(report.changed, isFalse);
      expect(
        report.entries.single.outcome,
        CCRouteRevalidationOutcome.unsupported,
      );
      expect(runtime.activeRouteEntries.map((entry) => entry.routeId), [
        'test.home',
        'test.home',
      ]);
    },
  );

  test(
    'reset reports stale when its selected Entry disappears while waiting',
    () async {
      final interceptor = _BlockingReplacementInterceptor();
      final runtime = _runtime(
        _Policy(
          (_) => const CCRouteRevalidationReset(_Intent('test.replacement')),
        ),
        globalInterceptors: [
          CCGlobalNavigationInterceptor(
            id: 'test.block_reset',
            interceptor: interceptor,
          ),
        ],
      );
      addTearDown(runtime.dispose);
      await _open(runtime, 'test.home');
      final handle = runtime.activeRouteEntries.single.handle;

      final revalidation = runtime.revalidateActiveRoutes(
        reason: 'session_closed',
      );
      await interceptor.started.future;
      expect(
        (await runtime.closeRoute(handle!)).status,
        CCRouteCloseStatus.closed,
      );
      interceptor.release.complete();
      final report = await revalidation;

      expect(report.changed, isFalse);
      expect(report.entries.single.outcome, CCRouteRevalidationOutcome.stale);
      expect(runtime.activeRouteEntries, isEmpty);
    },
  );

  test('reset cannot escape the selected Entry Host', () async {
    final runtime = _runtime(
      _Policy(
        (_) => const CCRouteRevalidationReset(_Intent('test.other_host')),
      ),
    );
    addTearDown(runtime.dispose);
    await _open(runtime, 'test.home');
    final before = runtime.activeRouteEntries.single.handle;

    final report = await runtime.revalidateActiveRoutes(
      reason: 'session_closed',
    );

    expect(report.changed, isFalse);
    expect(
      report.entries.single.outcome,
      CCRouteRevalidationOutcome.unsupported,
    );
    expect(runtime.activeRouteEntries.single.handle, same(before));
  });

  test('failed reset still suppresses lower-priority Host decisions', () async {
    final runtime = _runtime(
      _Policy(
        (context) => context.entry.routeId == 'test.protected'
            ? const CCRouteRevalidationReset(_Intent('test.other_host'))
            : const CCRouteRevalidationClose(),
      ),
    );
    addTearDown(runtime.dispose);
    await _open(runtime, 'test.home');
    await _open(
      runtime,
      'test.protected',
      operation: CCNavigationOperation.push,
    );

    final report = await runtime.revalidateActiveRoutes(
      reason: 'session_closed',
    );

    expect(report.changed, isFalse);
    expect(
      report.entries
          .singleWhere((entry) => entry.routeId == 'test.protected')
          .outcome,
      CCRouteRevalidationOutcome.unsupported,
    );
    expect(
      report.entries
          .singleWhere((entry) => entry.routeId == 'test.home')
          .outcome,
      CCRouteRevalidationOutcome.superseded,
    );
    expect(runtime.activeRouteEntries.map((entry) => entry.routeId), [
      'test.home',
      'test.protected',
    ]);
  });

  test('one reset decision supersedes every prior entry in its host', () async {
    final runtime = _runtime(
      _Policy(
        (context) => context.entry.routeId == 'test.protected'
            ? const CCRouteRevalidationReset(_Intent('test.home', 'signed-out'))
            : const CCRouteRevalidationClose(),
      ),
    );
    addTearDown(runtime.dispose);
    await _open(runtime, 'test.home');
    await _open(
      runtime,
      'test.protected',
      operation: CCNavigationOperation.push,
    );

    final report = await runtime.revalidateActiveRoutes(
      reason: 'session_closed',
    );

    expect(runtime.activeRouteEntries, hasLength(1));
    expect(runtime.activeRouteEntries.single.routeId, 'test.home');
    expect(
      report.entries.where(
        (entry) => entry.outcome == CCRouteRevalidationOutcome.reset,
      ),
      hasLength(1),
    );
    expect(
      report.entries.where(
        (entry) => entry.outcome == CCRouteRevalidationOutcome.superseded,
      ),
      isNotEmpty,
    );
  });

  test(
    'policy failure changes no route entries and sanitizes the error',
    () async {
      final runtime = _runtime(_Policy((_) => throw StateError('secret')));
      addTearDown(runtime.dispose);
      await _open(runtime, 'test.home');
      final before = runtime.activeRouteEntries.single.handle;

      await expectLater(
        runtime.revalidateActiveRoutes(reason: 'authentication_changed'),
        throwsA(
          isA<CCRouteRevalidationPolicyError>()
              .having(
                (error) => error.policyId,
                'policyId',
                'test.active.policy',
              )
              .having((error) => error.causeType, 'causeType', 'StateError')
              .having(
                (error) => error.toString(),
                'message',
                isNot(contains('secret')),
              ),
        ),
      );
      expect(runtime.activeRouteEntries.single.handle, same(before));
    },
  );

  test('policy timeout changes no route entries', () async {
    final runtime = _runtime(
      _Policy((_) => Completer<CCRouteRevalidationDecision>().future),
      timeout: const Duration(milliseconds: 20),
    );
    addTearDown(runtime.dispose);
    await _open(runtime, 'test.home');

    await expectLater(
      runtime.revalidateActiveRoutes(reason: 'permission_changed'),
      throwsA(isA<CCRouteRevalidationPolicyTimeoutError>()),
    );
    expect(runtime.activeRouteEntries.single.routeId, 'test.home');
  });

  test(
    'overlapping triggers run serially against fresh entry snapshots',
    () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      var calls = 0;
      final runtime = _runtime(
        _Policy((_) async {
          calls += 1;
          if (calls == 1) {
            firstStarted.complete();
            await releaseFirst.future;
          }
          return const CCRouteRevalidationKeep();
        }),
      );
      addTearDown(runtime.dispose);
      await _open(runtime, 'test.home');

      final first = runtime.revalidateActiveRoutes(reason: 'first_change');
      await firstStarted.future;
      final second = runtime.revalidateActiveRoutes(reason: 'second_change');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      releaseFirst.complete();

      final reports = await Future.wait([first, second]);
      expect(calls, 2);
      expect(reports[0].revision, lessThan(reports[1].revision));
    },
  );

  test(
    'policy navigation reentry fails closed without changing entries',
    () async {
      late final CCRouterRuntime runtime;
      runtime = _runtime(
        _Policy((_) async {
          await runtime.goRoute(const _Intent('test.home'));
          return const CCRouteRevalidationKeep();
        }),
      );
      addTearDown(runtime.dispose);
      await _open(runtime, 'test.protected');
      final before = runtime.activeRouteEntries.single.handle;

      await expectLater(
        runtime.revalidateActiveRoutes(reason: 'permission_changed'),
        throwsA(
          isA<CCRouteRevalidationPolicyError>().having(
            (error) => error.causeType,
            'causeType',
            'CCNavigationReentrancyError',
          ),
        ),
      );

      expect(runtime.activeRouteEntries.single.handle, same(before));
    },
  );

  test('shutdown cancels a pending policy and waits for quiescence', () async {
    final started = Completer<void>();
    final pending = Completer<CCRouteRevalidationDecision>();
    final runtime = _runtime(
      _Policy((context) {
        expect(context.cancellation.isCancelled, isFalse);
        started.complete();
        return pending.future;
      }),
    );
    await _open(runtime, 'test.home');

    final revalidation = runtime.revalidateActiveRoutes(
      reason: 'authentication_changed',
    );
    await started.future;
    final disposal = runtime.dispose();

    await expectLater(
      revalidation,
      throwsA(
        isA<CCRouteCancelledError>().having(
          (error) => error.code,
          'code',
          'runtime_disposed',
        ),
      ),
    );
    await expectLater(disposal, completes);
    expect(runtime.activeRouteEntries, isEmpty);

    pending.complete(const CCRouteRevalidationKeep());
    await Future<void>.delayed(Duration.zero);
  });

  test('shutdown cancels a deferred revalidation before joining it', () async {
    final runtime = _runtime(
      _Policy(
        (_) => const CCRouteRevalidationReplace(_Intent('test.replacement')),
      ),
      globalInterceptors: const [
        CCGlobalNavigationInterceptor(
          id: 'test.defer_replacement',
          interceptor: _DeferringReplacementInterceptor(),
        ),
      ],
    );
    await _open(runtime, 'test.home');

    final revalidation = runtime.revalidateActiveRoutes(
      reason: 'permission_changed',
    );
    while (runtime.pendingNavigations.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }

    final disposal = runtime.dispose();
    await expectLater(
      revalidation,
      throwsA(
        isA<CCRouteCancelledError>().having(
          (error) => error.code,
          'code',
          'runtime_disposed',
        ),
      ),
    );
    await disposal.timeout(const Duration(seconds: 1));
    expect(runtime.pendingNavigations, isEmpty);
    expect(runtime.activeRouteEntries, isEmpty);
  });

  test('route revalidation policy registration is validated eagerly', () {
    final policy = _Policy((_) => const CCRouteRevalidationKeep());

    expect(
      () => CCRouterRuntime.forTesting(
        routeRevalidationPolicies: [
          CCGlobalRouteRevalidationPolicy(id: 'Invalid ID', policy: policy),
        ],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    expect(
      () => CCRouterRuntime.forTesting(
        routeRevalidationPolicies: [
          CCGlobalRouteRevalidationPolicy(id: 'test.policy', policy: policy),
          CCGlobalRouteRevalidationPolicy(id: 'test.policy', policy: policy),
        ],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    expect(
      () => CCRouterRuntime.forTesting(
        routeRevalidationPolicies: [
          CCGlobalRouteRevalidationPolicy(
            id: 'test.policy',
            policy: policy,
            timeout: Duration.zero,
          ),
        ],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
  });
}
