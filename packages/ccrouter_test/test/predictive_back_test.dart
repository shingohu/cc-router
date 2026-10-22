import 'dart:async';
import 'dart:io';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
// ignore: deprecated_member_use
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Codec implements CCRouteCodec<String> {
  const _Codec();
  @override
  String decode(CCRouteCodecValues input) => input.path['id']!;
  @override
  CCRouteCodecValues encode(String value) =>
      CCRouteCodecValues(path: {'id': value});
}

class _HarnessRegistrar implements CCComponentRegistrar {
  _HarnessRegistrar(this.definition, this.resources);
  final CCRouteDefinition<String, String> definition;
  final List<_Resource> resources;

  @override
  void register(CCRegistry registry) {
    registry.registerRoute(definition);
    registry.registerService<_Resource>(
      CCServiceProvider(
        scope: CCServiceScope.route,
        factory: (_) {
          final resource = _Resource();
          resources.add(resource);
          return resource;
        },
      ),
    );
  }
}

final class _ThrowingActiveHandler implements CCFlutterPredictiveBackHandler {
  var attachCount = 0;
  var disposeCount = 0;

  @override
  bool get isActive => throw StateError('broken Host lifetime probe');

  @override
  void onAttach(Route<dynamic> route) => attachCount++;

  @override
  bool canCommit(Route<dynamic> route) => true;

  @override
  void onCancel(Route<dynamic> route) {}

  @override
  void onCommit(Route<dynamic> route) {}

  @override
  void onDispose(Route<dynamic> route) => disposeCount++;

  @override
  void onStart(Route<dynamic> route) {}

  @override
  void onUpdate(Route<dynamic> route, double progress) {}
}

class _Harness {
  final allowed = ValueNotifier(true);
  final resources = <_Resource>[];
  final events = <CCPredictiveBackEvent>[];
  final life = <String>[];
  final results = <String?>[];
  final errors = <Object>[];
  late CCGoRouterBackend backend;

  List<CCPredictiveBackPhase> get phases =>
      events.map((event) => event.phase).toList();
  ModalRoute<Object?> route(WidgetTester tester, [String id = '1']) =>
      ModalRoute.of(tester.element(find.text('detail:$id')))!;

  Future<void> mount(
    WidgetTester tester, {
    bool enabled = true,
    bool attached = false,
    bool wireAttached = true,
    bool globalGuard = false,
    CCPagePresentation presentation = const CCPagePresentation(),
    TargetPlatform platform = TargetPlatform.android,
    PageTransitionsTheme? transitions,
    int lifecycleEventCapacity = 1000,
  }) async {
    final definition = CCRouteDefinition<String, String>(
      routeId: 'probe.detail',
      patterns: [const CCPathPattern('/probe/:id', primary: true)],
      codec: const _Codec(),
      presentation: presentation,
    );
    final assembly = CCHostAssembly.fromComponents(
      components: [
        CCComponentManifest(
          id: 'probe',
          version: '1.0.0',
          registrar: _HarnessRegistrar(definition, resources),
        ),
      ],
      routeCatalog: CCFlutterRouteCatalog([
        CCFlutterRouteDestination.fromDefinition(
          definition: definition,
          builder: (arguments) => Builder(
            builder: (context) {
              CCRouter.routeService<_Resource>(context);
              final id = arguments.path['id'];
              return CCPageLifecycleListener(
                onPageShow: () => life.add('$id.show'),
                onPageHide: () => life.add('$id.hide'),
                child: ValueListenableBuilder<bool>(
                  valueListenable: allowed,
                  builder: (_, canPop, _) => PopScope<String>(
                    canPop: canPop,
                    child: Scaffold(body: Text('detail:$id')),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
    CCRouterHost.initialize(
      hostAssembly: assembly,
      globalPopGuards: globalGuard
          ? [CCGlobalPopGuard(id: 'probe.global', guard: _Guard(false, []))]
          : const [],
    );
    await tester.pumpWidget(
      CCGoRouterApp(
        enablePredictiveBack: enabled,
        lifecycleEventCapacity: lifecycleEventCapacity,
        theme: ThemeData(
          platform: platform,
          pageTransitionsTheme: transitions ?? const PageTransitionsTheme(),
        ),
        hostRoutes: [GoRoute(path: '/', builder: (_, _) => const Text('home'))],
        backendFactory: (configuration) {
          if (!attached) return backend = configuration.createManagedBackend();
          final host = CCNavigationHost();
          final observer = CCGoRouterNavigationObserver(outlet: 'root');
          final binding = GoRoute(
            path: '/probe/:id',
            pageBuilder: (_, state) => ccGoRouterPage(
              child: CCRouterHostBinding.bindRouteEntry(
                payload: state.extra,
                child: configuration.catalog
                    .destinationFor('probe.detail')!
                    .build(CCRouteCodecValues(path: state.pathParameters)),
              ),
              presentation: presentation,
              key: state.pageKey,
              name: 'probe.detail',
              predictiveBackHandler: wireAttached
                  ? backend.adapter.predictiveBackBridge
                  : null,
            ),
          );
          final router = GoRouter(
            navigatorKey: host.navigatorKey,
            observers: [observer],
            routes: [
              GoRoute(path: '/', builder: (_, _) => const Text('home')),
              binding,
            ],
          );
          addTearDown(router.dispose);
          return backend = CCGoRouterBackend.attach(
            catalog: configuration.catalog,
            host: host,
            router: router,
            observers: [observer],
            enablePredictiveBack: enabled,
            bindings: [
              CCGoRouterRouteBinding(routeId: 'probe.detail', goRoute: binding),
            ],
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    backend.adapter.predictiveBackBridge?.addPredictiveBackListener(events.add);
  }

  void push([String id = '1']) =>
      _watch(CCRouter.navigator.push<String>(_Intent(id)));

  void _watch(Future<String?> pending) {
    unawaited(
      pending.then<void>(
        results.add,
        onError: (Object error) {
          errors.add(error);
        },
      ),
    );
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await CCRouterHost.shutdown();
    allowed.dispose();
  }
}

void _boundaryTests() {
  for (final enabled in [false, true]) {
    testWidgets('Theme platform change preserves system fallback: $enabled', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.mount(tester, enabled: enabled);
      harness.push();
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        CCGoRouterApp(
          enablePredictiveBack: enabled,
          themeAnimationDuration: Duration.zero,
          theme: ThemeData(platform: TargetPlatform.iOS),
        ),
      );
      await tester.pumpAndSettle();
      await _event(tester, 'startBackGesture');
      expect(
        harness.backend.host.navigatorKey.currentState!.userGestureInProgress,
        isFalse,
      );
      await _event(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(harness.results, [null]);
      expect(harness.resources.single.disposeCount, 1);
      expect(harness.phases, isEmpty);
      if (enabled) {
        expect(
          harness.backend.adapter.predictiveBackFallbacks.single.reason,
          CCGoRouterPredictiveBackFallbackReason.unsupportedTransition,
        );
      }
      await harness.close(tester);
    });
  }

  for (final platformChange in [false, true]) {
    for (final terminal in ['commitBackGesture', 'cancelBackGesture']) {
      testWidgets(
        'Theme change cancels preview: platform=$platformChange terminal=$terminal',
        (tester) async {
          final harness = _Harness();
          await harness.mount(tester);
          harness.push();
          await tester.pumpAndSettle();
          final route = harness.route(tester);
          final before = [...harness.life];
          await _event(tester, 'startBackGesture');
          await _event(tester, 'updateBackGestureProgress');
          expect(route.animation!.value, closeTo(.6, .001));
          await tester.pumpWidget(
            CCGoRouterApp(
              enablePredictiveBack: true,
              themeAnimationDuration: Duration.zero,
              theme: ThemeData(
                platform: platformChange
                    ? TargetPlatform.iOS
                    : TargetPlatform.android,
                pageTransitionsTheme: platformChange
                    ? const PageTransitionsTheme()
                    : const PageTransitionsTheme(
                        builders: {
                          TargetPlatform.android: ZoomPageTransitionsBuilder(),
                        },
                      ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(route.animation!.value, 1);
          expect(route.navigator!.userGestureInProgress, isFalse);
          expect(harness.phases, [
            CCPredictiveBackPhase.started,
            CCPredictiveBackPhase.updated,
            CCPredictiveBackPhase.cancelled,
          ]);
          if (terminal == 'commitBackGesture') {
            // A replacement detector must not revive a cancelled preview even
            // when the supported Theme returns before the platform commits.
            await tester.pumpWidget(
              CCGoRouterApp(
                enablePredictiveBack: true,
                themeAnimationDuration: Duration.zero,
                theme: ThemeData(platform: TargetPlatform.android),
              ),
            );
            await tester.pumpAndSettle();
          }
          await _event(tester, terminal);
          await _event(tester, 'commitBackGesture');
          await tester.pumpAndSettle();
          expect(harness.results, isEmpty);
          expect(harness.resources.single.disposeCount, 0);
          expect(harness.life, before);
          expect(CCRouter.activeRouteEntries, hasLength(1));
          // Returning to a supported Theme must not revive the old preview.
          await tester.pumpWidget(
            CCGoRouterApp(
              enablePredictiveBack: true,
              themeAnimationDuration: Duration.zero,
              theme: ThemeData(platform: TargetPlatform.android),
            ),
          );
          await tester.pumpAndSettle();
          await _event(tester, 'startBackGesture');
          await _event(tester, 'commitBackGesture');
          await tester.pumpAndSettle();
          expect(harness.results, [null]);
          expect(harness.resources.single.disposeCount, 1);
          expect(harness.phases, [
            CCPredictiveBackPhase.started,
            CCPredictiveBackPhase.updated,
            CCPredictiveBackPhase.cancelled,
            CCPredictiveBackPhase.started,
            CCPredictiveBackPhase.committed,
          ]);
          await harness.close(tester);
        },
      );
    }
  }
  testWidgets('throwing handler lifetime probe restores Flutter fallback', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final handler = _ThrowingActiveHandler();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(platform: TargetPlatform.android),
        home: const Text('home'),
      ),
    );
    final route =
        CCFlutterRouteFactory.createRoute<void>(
              context: navigatorKey.currentContext!,
              child: const Text('detail'),
              presentation: const CCPagePresentation(),
              predictiveBackHandler: handler,
            )
            as PageRoute<void>;
    navigatorKey.currentState!.push<void>(route);
    await tester.pumpAndSettle();

    expect(handler.attachCount, 1);
    expect(() => route.popGestureEnabled, returnsNormally);
    expect(route.popGestureEnabled, isTrue);
    expect(handler.disposeCount, 1);
    expect(() => route.handleStartBackGesture(progress: 0), returnsNormally);
    route.handleUpdateBackGestureProgress(progress: .4);
    route.handleCommitBackGesture();
    await tester.pumpAndSettle();

    expect(find.text('detail'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(handler.disposeCount, 1);
  });

  for (final predictive in [false, true]) {
    testWidgets('theme transition predictive=$predictive preserves fallback', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.mount(
        tester,
        transitions: PageTransitionsTheme(
          builders: {
            TargetPlatform.android: predictive
                ? const PredictiveBackFullscreenPageTransitionsBuilder()
                : const ZoomPageTransitionsBuilder(),
          },
        ),
      );
      harness.push();
      await tester.pumpAndSettle();
      await _event(tester, 'startBackGesture', edge: 1);
      await _event(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(harness.results, [null]);
      expect(
        harness.phases,
        predictive
            ? [CCPredictiveBackPhase.started, CCPredictiveBackPhase.committed]
            : isEmpty,
      );
      expect(
        harness.backend.adapter.predictiveBackFallbacks.map(
          (event) => event.reason,
        ),
        predictive
            ? isEmpty
            : [CCGoRouterPredictiveBackFallbackReason.unsupportedTransition],
      );
      await harness.close(tester);
    });
  }

  testWidgets('predictive fallback diagnostics use lifecycle capacity', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.mount(tester, lifecycleEventCapacity: 2);
    harness.push();
    await tester.pumpAndSettle();
    for (var index = 0; index < 3; index++) {
      await _event(tester, 'startBackGesture', button: true);
    }

    expect(harness.backend.adapter.predictiveBackFallbacks, hasLength(2));
    expect(
      harness.backend.adapter.predictiveBackFallbacks.every(
        (event) =>
            event.reason == CCGoRouterPredictiveBackFallbackReason.buttonEvent,
      ),
      isTrue,
    );
    await harness.close(tester);
  });

  testWidgets('three-button system back is not claimed by automatic bridge', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.mount(tester);
    harness.push();
    await tester.pumpAndSettle();
    await _event(tester, 'startBackGesture', button: true);
    await _event(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(harness.results, [null]);
    expect(harness.phases, isEmpty);
    expect(
      harness.backend.adapter.predictiveBackFallbacks.single.reason,
      CCGoRouterPredictiveBackFallbackReason.buttonEvent,
    );
    await harness.close(tester);
  });

  for (final enabled in [false, true]) {
    testWidgets(
      'switch $enabled preserves construction, results and progress',
      (tester) async {
        final harness = _Harness();
        await harness.mount(tester, enabled: enabled);
        harness.push();
        await tester.pumpAndSettle();
        final route = harness.route(tester);
        expect(route is MaterialPageRoute<Object?>, isTrue);
        expect(route.runtimeType == MaterialPageRoute<Object?>, !enabled);
        expect(harness.backend.adapter.predictiveBackBridge == null, !enabled);
        expect(harness.backend.adapter.predictiveBackFallbacks, isEmpty);
        final before = [...harness.life];
        await _event(tester, 'startBackGesture');
        await _event(tester, 'updateBackGestureProgress');
        expect(route.animation!.value, closeTo(.6, .001));
        if (enabled) expect(harness.events.last.progress, closeTo(.4, .001));
        await _event(tester, 'cancelBackGesture');
        await tester.pumpAndSettle();
        expect(harness.results, isEmpty);
        expect(harness.resources.single.disposeCount, 0);
        expect(harness.life, before);
        CCRouter.navigator.pop(result: 'confirmed');
        await tester.pumpAndSettle();
        expect(harness.results, ['confirmed']);
        expect(harness.resources.single.disposeCount, 1);
        expect(
          harness.phases,
          enabled
              ? [
                  CCPredictiveBackPhase.started,
                  CCPredictiveBackPhase.updated,
                  CCPredictiveBackPhase.cancelled,
                ]
              : isEmpty,
        );
        await harness.close(tester);
      },
    );

    testWidgets('switch $enabled dynamic PopScope commit policy', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.mount(tester, enabled: enabled);
      harness.push();
      await tester.pumpAndSettle();
      await _event(tester, 'startBackGesture');
      harness.allowed.value = false;
      await tester.pump();
      await _event(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(harness.results.length, enabled ? 0 : 1);
      expect(harness.resources.single.disposeCount, enabled ? 0 : 1);
      if (enabled) {
        expect(harness.phases, [
          CCPredictiveBackPhase.started,
          CCPredictiveBackPhase.cancelled,
        ]);
        expect(harness.route(tester).animation!.value, 1);
        harness.allowed.value = true;
        await tester.pump();
        await _event(tester, 'startBackGesture');
        await _event(tester, 'commitBackGesture');
        await tester.pumpAndSettle();
        expect(harness.results, [null]);
      }
      await harness.close(tester);
    });
  }

  testWidgets(
    'independent gestures, duplicate terminal and manual report are safe',
    (tester) async {
      final harness = _Harness();
      await harness.mount(tester);
      harness.backend.adapter.predictiveBackBridge!.addPredictiveBackListener(
        (_) => throw StateError('observer failure'),
      );
      harness.push();
      await tester.pumpAndSettle();
      harness.push('2');
      await tester.pumpAndSettle();
      await _event(tester, 'startBackGesture');
      await _event(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      final committed = harness.events.last;
      expect(committed.phase, CCPredictiveBackPhase.committed);
      expect(committed.outcome!.removedBackendEntryId, isNotNull);
      expect(committed.outcome!.trigger, CCPopTrigger.predictiveBack);
      harness.backend.adapter.predictiveBackBridge!.committed(
        committed.outcome!,
      );
      await _event(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(harness.results, [null]);
      expect(CCRouter.activeRouteEntries, hasLength(1));
      await _event(tester, 'startBackGesture');
      await _event(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(harness.results, [null, null]);
      expect(harness.resources.map((resource) => resource.disposeCount), [
        1,
        1,
      ]);
      expect(
        harness.phases.where((p) => p == CCPredictiveBackPhase.committed),
        hasLength(2),
      );
      expect(CCRouter.activeRouteEntries, isEmpty);
      await harness.close(tester);
    },
  );

  for (final operation in ['push', 'replace', 'go', 'reset', 'popup']) {
    testWidgets('$operation invalidates old gesture without popping new top', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.mount(tester);
      harness.push();
      await tester.pumpAndSettle();
      await _event(tester, 'startBackGesture');
      switch (operation) {
        case 'push':
          harness.push('2');
        case 'replace':
          harness._watch(
            CCRouter.navigator.replace<String>(const _Intent('2')),
          );
        case 'go':
          await CCRouter.navigator.go(const _Intent('2'));
        case 'reset':
          await CCRouter.navigator.reset(const _Intent('2'));
        case 'popup':
          unawaited(
            showDialog<void>(
              context: tester.element(find.text('detail:1')),
              builder: (_) => const AlertDialog(content: Text('popup')),
            ),
          );
      }
      await tester.pumpAndSettle();
      final count = harness.results.length;
      await _event(tester, 'updateBackGestureProgress');
      await _event(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(harness.results.length, count);
      expect(
        find.text(operation == 'popup' ? 'popup' : 'detail:2'),
        findsOneWidget,
      );
      expect(harness.phases, [
        CCPredictiveBackPhase.started,
        CCPredictiveBackPhase.cancelled,
      ]);
      expect(harness.resources.last.disposeCount, 0);
      await harness.close(tester);
    });
  }

  testWidgets('LocalHistory consumes fallback without managed removal', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.mount(tester);
    harness.push();
    await tester.pumpAndSettle();
    var removed = false;
    harness
        .route(tester)
        .addLocalHistoryEntry(
          LocalHistoryEntry(onRemove: () => removed = true),
        );
    await tester.pumpAndSettle();
    await _event(tester, 'startBackGesture');
    await _event(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(removed, isTrue);
    expect(harness.results, isEmpty);
    expect(harness.phases, isEmpty);
    expect(harness.resources.single.disposeCount, 0);
    await harness.close(tester);
  });

  testWidgets('disposed Adapter ignores late commit and never performs Pop', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.mount(tester);
    harness.push();
    await tester.pumpAndSettle();
    await _event(tester, 'startBackGesture');
    harness.backend.adapter.dispose();
    final phases = [...harness.phases];
    await _event(tester, 'updateBackGestureProgress');
    await _event(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('detail:1'), findsOneWidget);
    expect(harness.phases, phases);
    expect(harness.errors.single, isA<CCNavigationAdapterError>());
    await harness.close(tester);
    expect(harness.resources.single.disposeCount, 1);
  });

  for (final enabled in [false, true]) {
    testWidgets('attached Router survives Adapter disposal, enabled=$enabled', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.mount(tester, attached: true, enabled: enabled);
      harness.push();
      await tester.pumpAndSettle();
      harness.backend.adapter.dispose();
      await tester.pumpAndSettle();
      await _event(tester, 'startBackGesture');
      await _event(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('detail:1'), findsNothing);
      expect(harness.phases, isEmpty);
      expect(harness.errors.single, isA<CCNavigationAdapterError>());
      await harness.close(tester);
      expect(harness.resources.single.disposeCount, 1);
    });
  }

  for (final terminal in ['commitBackGesture', 'cancelBackGesture']) {
    testWidgets('attached Router recovers after retired gesture $terminal', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.mount(tester, attached: true);
      harness.push();
      await tester.pumpAndSettle();
      await _event(tester, 'startBackGesture');
      await _event(tester, 'updateBackGestureProgress');
      harness.backend.adapter.dispose();
      await tester.pumpAndSettle();
      await _event(tester, terminal);
      await tester.pumpAndSettle();
      expect(find.text('detail:1'), findsOneWidget);
      expect(harness.route(tester).animation!.value, 1);
      expect(
        harness.backend.host.navigatorKey.currentState!.userGestureInProgress,
        isFalse,
      );
      await _event(tester, 'startBackGesture');
      await _event(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('detail:1'), findsNothing);
      expect(harness.phases, [
        CCPredictiveBackPhase.started,
        CCPredictiveBackPhase.updated,
      ]);
      await harness.close(tester);
      expect(harness.resources.single.disposeCount, 1);
    });
  }

  testWidgets('replaced Host consumes the previous gesture commit', (
    tester,
  ) async {
    final previous = _Harness();
    await previous.mount(tester);
    previous.push();
    await tester.pumpAndSettle();
    await _event(tester, 'startBackGesture');
    await previous.close(tester);

    final current = _Harness();
    await current.mount(tester);
    current.push('2');
    await tester.pumpAndSettle();
    await _event(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('detail:2'), findsOneWidget);
    expect(current.results, isEmpty);
    await current.close(tester);
  });

  for (final recovery in ['cancel', 'restart', 'timeout']) {
    testWidgets('retired Host releases observation on $recovery', (
      tester,
    ) async {
      final previous = _Harness();
      await previous.mount(tester);
      previous.push();
      await tester.pumpAndSettle();
      await _event(tester, 'startBackGesture');
      await previous.close(tester);
      if (recovery == 'timeout') {
        await tester.pump(const Duration(seconds: 31));
      }

      final current = _Harness();
      await current.mount(tester);
      current.push('2');
      await tester.pumpAndSettle();
      if (recovery == 'cancel') {
        await _event(tester, 'cancelBackGesture');
        expect(current.results, isEmpty);
      }
      await _event(tester, 'startBackGesture');
      await _event(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(current.results, [null]);
      expect(current.phases, [
        CCPredictiveBackPhase.started,
        CCPredictiveBackPhase.committed,
      ]);
      await current.close(tester);
    });
  }

  for (final wire in [false, true]) {
    testWidgets('attached router requires explicit Page wiring: $wire', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.mount(tester, attached: true, wireAttached: wire);
      harness.push();
      await tester.pumpAndSettle();
      await _event(tester, 'startBackGesture');
      await _event(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(harness.results, [null]);
      expect(harness.resources.single.disposeCount, 1);
      expect(
        harness.phases,
        wire
            ? [CCPredictiveBackPhase.started, CCPredictiveBackPhase.committed]
            : isEmpty,
      );
      expect(
        harness.backend.adapter.predictiveBackFallbacks.map(
          (event) => event.reason,
        ),
        wire
            ? isEmpty
            : [CCGoRouterPredictiveBackFallbackReason.noEligibleRoute],
      );
      await harness.close(tester);
    });
  }

  for (final platform in [
    TargetPlatform.iOS,
    if (Platform.operatingSystem == 'ohos')
      TargetPlatform.values.byName(Platform.operatingSystem),
  ]) {
    testWidgets(
      '$platform retains original Material Route with bridge enabled',
      (tester) async {
        final harness = _Harness();
        await harness.mount(tester, platform: platform);
        harness.push();
        await tester.pumpAndSettle();
        expect(harness.route(tester).runtimeType, MaterialPageRoute<Object?>);
        CCRouter.navigator.pop(result: 'original');
        await tester.pumpAndSettle();
        expect(harness.results, ['original']);
        expect(harness.phases, isEmpty);
        await harness.close(tester);
      },
    );
  }

  testWidgets('global Guard denial retains non-interactive fallback', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.mount(tester, globalGuard: true);
    harness.push();
    await tester.pumpAndSettle();
    await _event(tester, 'startBackGesture');
    expect(
      harness.backend.host.navigatorKey.currentState!.userGestureInProgress,
      isFalse,
    );
    await _event(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(harness.results, isEmpty);
    expect(harness.phases, isEmpty);
    expect(harness.resources.single.disposeCount, 0);
    await harness.close(tester);
  });

  testWidgets('custom transition retains Route type and ordinary fallback', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.mount(
      tester,
      presentation: const CCPagePresentation(
        transition: CCPageTransitionType.fade,
      ),
    );
    harness.push();
    await tester.pumpAndSettle();
    expect(harness.route(tester), isA<PageRouteBuilder<Object?>>());
    await _event(tester, 'startBackGesture');
    await _event(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(harness.results, [null]);
    expect(harness.phases, isEmpty);
    await harness.close(tester);
  });
}

class _Intent implements CCRouteIntent<String> {
  const _Intent([this.id = '1']);
  final String id;
  @override
  String get routeId => 'probe.detail';
  @override
  Object get arguments => id;
}

class _Resource implements CCDisposable {
  int disposeCount = 0;
  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

class _Guard implements CCPopGuard {
  _Guard(this.allow, this.triggers);
  final bool allow;
  final List<CCPopTrigger> triggers;
  @override
  CCPopGuardDecision evaluate(CCPopGuardContext context) {
    triggers.add(context.trigger);
    return allow ? const CCPopAllow() : const CCPopDeny();
  }
}

class _Registrar implements CCComponentRegistrar {
  _Registrar(this.definition, this.guard, this.resource);
  final CCRouteDefinition<String, String> definition;
  final _Guard guard;
  final _Resource resource;
  @override
  void register(CCRegistry registry) {
    registry.registerRoute(definition);
    registry.registerRoutePopGuard('probe.guard', guard);
    registry.registerService<_Resource>(
      CCServiceProvider(scope: CCServiceScope.route, factory: (_) => resource),
    );
  }
}

Future<void> _event(
  WidgetTester tester,
  String method, {
  int edge = 0,
  bool button = false,
}) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        method == 'startBackGesture' || method == 'updateBackGestureProgress'
            ? <String, Object>{
                if (!button) 'touchOffset': <double>[5, 300],
                'progress': method == 'startBackGesture' ? 0.0 : 0.4,
                'swipeEdge': edge,
              }
            : null,
      ),
    ),
    (_) {},
  );
  await tester.pump();
}

void main() {
  tearDown(CCRouterHost.shutdown);
  for (final terminal in ['commitBackGesture', 'cancelBackGesture']) {
    testWidgets(
      'eligibility query preserves retired gesture fence: $terminal',
      (tester) async {
        final harness = _Harness();
        await harness.mount(tester, attached: true);
        harness.push();
        await tester.pumpAndSettle();
        final route = harness.route(tester);
        await _event(tester, 'startBackGesture');
        harness.backend.adapter.dispose();
        // A Host capability query must not change the in-flight gesture owner.
        expect(route.popGestureEnabled, isTrue);
        await _event(tester, terminal);
        await tester.pumpAndSettle();
        expect(find.text('detail:1'), findsOneWidget);
        expect(route.animation!.value, 1);
        expect(
          harness.backend.host.navigatorKey.currentState!.userGestureInProgress,
          isFalse,
        );
        await _event(tester, 'startBackGesture');
        await _event(tester, 'commitBackGesture');
        await tester.pumpAndSettle();
        expect(find.text('detail:1'), findsNothing);
        await harness.close(tester);
        expect(harness.resources.single.disposeCount, 1);
      },
    );
  }
  testWidgets('new start replaces retired gesture with a lost terminal', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.mount(tester, attached: true);
    harness.push();
    await tester.pumpAndSettle();
    final route = harness.route(tester);
    await _event(tester, 'startBackGesture');
    harness.backend.adapter.dispose();

    // An eligibility read keeps the old commit fence, but the next platform
    // start is a new sequence and must retire the abandoned one.
    expect(route.popGestureEnabled, isTrue);
    await _event(tester, 'startBackGesture');
    expect(route.navigator!.userGestureInProgress, isTrue);
    await _event(tester, 'commitBackGesture');
    await tester.pumpAndSettle();

    expect(find.text('detail:1'), findsNothing);
    expect(harness.phases, [CCPredictiveBackPhase.started]);
    await harness.close(tester);
    expect(harness.resources.single.disposeCount, 1);
  });
  _boundaryTests();
  final cases = [
    (
      name: '默认关闭 bridge，Flutter 动画与 managed Scope 正常',
      bridge: false,
      guarded: false,
      allow: true,
      local: false,
      foreign: false,
    ),
    (
      name: '开启 bridge 自动报告取消与确认提交',
      bridge: true,
      guarded: false,
      allow: true,
      local: false,
      foreign: false,
    ),
    (
      name: '框架 Guard allow：交互动画关闭，提交后按 system 判断',
      bridge: true,
      guarded: true,
      allow: true,
      local: false,
      foreign: false,
    ),
    (
      name: '框架 Guard deny：提交不移除页面与 Scope',
      bridge: true,
      guarded: true,
      allow: false,
      local: false,
      foreign: false,
    ),
    (
      name: '页面 PopScope 拒绝：提交交还业务，取消无副作用',
      bridge: true,
      guarded: false,
      allow: true,
      local: true,
      foreign: false,
    ),
    (
      name: 'foreign Dialog：预测提交只关闭弹窗，managed Scope 保留',
      bridge: true,
      guarded: false,
      allow: true,
      local: false,
      foreign: true,
    ),
  ];
  for (final spec in cases) {
    testWidgets(spec.name, (tester) async {
      final life = <String>[];
      final phases = <CCPredictiveBackPhase>[];
      final triggers = <CCPopTrigger>[];
      final resource = _Resource();
      final definition = CCRouteDefinition<String, String>(
        routeId: 'probe.detail',
        patterns: [const CCPathPattern('/probe/:id', primary: true)],
        codec: const _Codec(),
        popGuardIds: spec.guarded ? ['probe.guard'] : [],
      );
      final destination = CCFlutterRouteDestination.fromDefinition(
        definition: definition,
        builder: (_) => Builder(
          builder: (context) {
            CCRouter.routeService<_Resource>(context);
            return CCPageLifecycleListener(
              onPageShow: () => life.add('detail.show'),
              onPageHide: () => life.add('detail.hide'),
              child: PopScope<String>(
                canPop: !spec.local,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) life.add('local.blocked');
                },
                child: const Scaffold(body: Text('detail')),
              ),
            );
          },
        ),
      );
      final assembly = CCHostAssembly.fromComponents(
        components: [
          CCComponentManifest(
            id: 'probe',
            version: '1.0.0',
            registrar: _Registrar(
              definition,
              _Guard(spec.allow, triggers),
              resource,
            ),
          ),
        ],
        routeCatalog: CCFlutterRouteCatalog([destination]),
      );
      CCRouterHost.initialize(hostAssembly: assembly);
      late CCGoRouterBackend backend;
      await tester.pumpWidget(
        CCGoRouterApp(
          enablePredictiveBack: spec.bridge,
          theme: ThemeData(platform: TargetPlatform.android),
          backendFactory: (config) => backend = config.createManagedBackend(),
          hostRoutes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
        ),
      );
      await tester.pumpAndSettle();
      final remove = backend.adapter.predictiveBackBridge
          ?.addPredictiveBackListener((event) => phases.add(event.phase));
      var completed = false;
      var completionCount = 0;
      String? returnedValue;
      var shuttingDown = false;
      final pushed = CCRouter.navigator.push<String>(_Intent());
      unawaited(
        pushed.then<void>(
          (value) {
            completed = true;
            completionCount++;
            returnedValue = value;
          },
          onError: (Object error, StackTrace stack) {
            if (!shuttingDown) Error.throwWithStackTrace(error, stack);
            expect(error, isA<CCNavigationAdapterError>());
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(CCRouter.activeRouteEntries, hasLength(1));
      if (spec.foreign) {
        unawaited(
          showDialog<void>(
            context: tester.element(find.text('detail')),
            builder: (_) => const AlertDialog(content: Text('foreign')),
          ),
        );
        await tester.pumpAndSettle();
      }
      final before = List<String>.of(life);
      await _event(tester, 'startBackGesture');
      final interactive = backend
          .router
          .routerDelegate
          .navigatorKey
          .currentState!
          .userGestureInProgress;
      expect(interactive, !spec.guarded && !spec.local && !spec.foreign);
      await _event(tester, 'updateBackGestureProgress');
      await _event(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(life, before);
      expect(resource.disposeCount, 0);
      expect(completed, isFalse);
      expect(CCRouter.activeRouteEntries, hasLength(1));
      await _event(tester, 'startBackGesture');
      await _event(tester, 'updateBackGestureProgress');
      await _event(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      final popsManaged =
          !spec.foreign && !spec.local && (!spec.guarded || spec.allow);
      expect(completed, popsManaged);
      expect(completionCount, popsManaged ? 1 : 0);
      expect(returnedValue, isNull);
      expect(resource.disposeCount, popsManaged ? 1 : 0);
      expect(CCRouter.activeRouteEntries, hasLength(popsManaged ? 0 : 1));
      expect(
        phases,
        spec.bridge && interactive
            ? [
                CCPredictiveBackPhase.started,
                CCPredictiveBackPhase.updated,
                CCPredictiveBackPhase.cancelled,
                CCPredictiveBackPhase.started,
                CCPredictiveBackPhase.updated,
                CCPredictiveBackPhase.committed,
              ]
            : isEmpty,
      );
      expect(triggers, spec.guarded ? [CCPopTrigger.system] : isEmpty);
      if (spec.local) {
        expect(life.where((event) => event == 'local.blocked'), hasLength(1));
      }
      if (spec.foreign) expect(find.text('foreign'), findsNothing);
      remove?.call();
      shuttingDown = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await CCRouterHost.shutdown();
    });
  }
}
