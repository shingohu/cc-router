import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'support/managed_test_home.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Args {
  const _Args(this.id);
  final String id;
}

final class _Codec implements CCRouteCodec<_Args> {
  const _Codec();
  @override
  _Args decode(CCRouteCodecValues input) => _Args(input.path['id']!);
  @override
  CCRouteCodecValues encode(_Args args) =>
      CCRouteCodecValues(path: {'id': args.id});
}

final class _Intent implements CCRouteIntent<String> {
  const _Intent(this.id);
  final String id;
  @override
  String get routeId => 'close.detail';
  @override
  Object get arguments => _Args(id);
}

CCRouteDefinition<_Args, String> _definition({
  CCRoutePlacement placement = const CCRoutePlacement.root(),
}) => CCRouteDefinition(
  routeId: 'close.detail',
  patterns: [const CCPathPattern('/detail/:id', primary: true)],
  codec: const _Codec(),
  placement: placement,
);

final class _Registrar implements CCComponentRegistrar {
  _Registrar({this.placement = const CCRoutePlacement.root()});
  final CCRoutePlacement placement;
  @override
  void register(CCRegistry registry) {
    registry.registerRoute(_definition(placement: placement));
    if (placement.shellId != null) {
      registry.registerShell(
        CCShellDefinition(
          shellId: placement.shellId!,
          type: CCShellType.singleNavigator,
          outlets: [placement.navigatorOutlet],
          initialOutlet: placement.navigatorOutlet,
        ),
      );
    }
    registry.registerService<_Resource>(
      CCServiceProvider(
        scope: CCServiceScope.route,
        factory: (_) => _Resource(),
      ),
    );
  }
}

final class _Resource implements CCDisposable {
  int disposals = 0;
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

final class _Harness {
  _Harness(this.backend, this.contexts, this.resources);
  final CCManagedRouterBackend backend;
  final Map<String, BuildContext> contexts;
  final Map<String, _Resource> resources;
  CCRouteEntryHandle handle(String id) =>
      CCRouter.routeEntryHandleOf(contexts[id]!)!;
  Future<String?> push(String id) => CCRouter.navigator.push(_Intent(id));
}

Future<_Harness> _mount(
  WidgetTester tester, {
  bool denyClose = false,
  bool nested = false,
}) async {
  final placement = nested
      ? const CCRoutePlacement(shellId: 'workspace', navigatorOutlet: 'content')
      : const CCRoutePlacement.root();
  CCRouterHost.initialize(
    hostAssembly: CCHostAssembly.fromComponents(
      components: [
        CCComponentManifest(
          id: 'close',
          version: '1.0.0',
          registrar: WithTestHome(
            _Registrar(placement: placement),
            placement: placement,
          ),
        ),
      ],
    ),
    globalPopGuards: denyClose
        ? [CCGlobalPopGuard(id: 'close.deny', guard: _DenyClose())]
        : const [],
  );
  final contexts = <String, BuildContext>{};
  final resources = <String, _Resource>{};
  final destination = CCFlutterRouteDestination.fromDefinition(
    definition: _definition(placement: placement),
    builder: (args) => Builder(
      builder: (context) {
        final id = args.path['id']!;
        final resource = CCRouter.routeService<_Resource>(context);
        if (ModalRoute.of(context)!.isCurrent) {
          contexts[id] = context;
          resources[id] = resource;
        }
        return Text('page-$id');
      },
    ),
  );
  final backend = CCManagedRouterBackend(
    host: nested
        ? CCNavigationHost(
            navigatorKeys: {'content': GlobalKey<NavigatorState>()},
          )
        : null,
    routeCatalog: CCFlutterRouteCatalog(
      [testHomeDestination(placement: placement), destination],
      componentVersions: const {'close': '1.0.0'},
    ),
    shellBindings: nested
        ? [
            CCManagedShellBinding(
              shellId: 'workspace',
              builder: (_, shell) => shell.navigatorFor('content'),
            ),
          ]
        : const [],
  );
  await tester.pumpWidget(
    CCRouterApp.managed(
      backend: backend,
      child: MaterialApp.router(routerConfig: backend.routerConfig),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(backend, contexts, resources);
}

final class _DenyClose implements CCPopGuard {
  @override
  CCPopGuardDecision evaluate(CCPopGuardContext context) =>
      const CCPopDeny(code: 'close_denied');
}

Iterable<CCRouteEntrySnapshot> get _detailEntries => CCRouter.activeRouteEntries
    .where((entry) => entry.routeId == 'close.detail');

Future<void> _expectUnavailableServices(BuildContext context) async {
  for (final lookup in <FutureOr<Object?> Function()>[
    () => CCRouter.routeService<_Resource>(context),
    () => CCRouter.routeServiceOrNull<_Resource>(context),
    () => CCRouter.routeServiceAsync<_Resource>(context),
    () => CCRouter.routeServiceOrNullAsync<_Resource>(context),
  ]) {
    await expectLater(
      Future<Object?>.sync(lookup),
      throwsA(isA<CCServiceScopeUnavailableError>()),
    );
  }
}

void main() {
  for (final nested in [false, true]) {
    for (final rootPopup in nested ? [false, true] : [true]) {
      testWidgets(
        'last declarative close retains foreign popup: nested=$nested root=$rootPopup',
        (tester) async {
          final h = await _mount(tester, nested: nested);
          await CCRouter.navigator.go(const _Intent('A'));
          await tester.pumpAndSettle();
          final target = h.handle('A');
          final oldContext = h.contexts['A']!;
          var popupDone = false;
          final popup =
              showDialog<String>(
                context: oldContext,
                useRootNavigator: rootPopup,
                builder: (_) =>
                    const AlertDialog(content: Text('last-entry-popup')),
              ).then((value) {
                popupDone = true;
                return value;
              });
          await tester.pumpAndSettle();
          expect(
            (await CCRouter.navigator.close(target)).status,
            CCRouteCloseStatus.closed,
          );
          await tester.pumpAndSettle();
          expect(_detailEntries, isEmpty);
          expect(popupDone, isFalse);
          expect(find.text('last-entry-popup'), findsOneWidget);
          expect(h.resources['A']!.disposals, 1);
          expect(oldContext.mounted, isFalse);
          final popupContext = tester.element(find.text('last-entry-popup'));
          Navigator.of(popupContext).pop('foreign-result');
          expect(await popup, 'foreign-result');
          await tester.pumpAndSettle();
          expect(find.text('last-entry-popup'), findsNothing);
          expect(
            (await CCRouter.navigator.close(target)).status,
            CCRouteCloseStatus.notFound,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'handle lookup from mounted old context returns null after shutdown and restart',
    (tester) async {
      final h = await _mount(tester);
      unawaited(h.push('A').catchError((_) => null));
      await tester.pumpAndSettle();
      final context = h.contexts['A']!;
      final old = h.handle('A');
      await CCRouterHost.shutdown();
      expect(context.mounted, isTrue);
      expect(CCRouter.routeEntryHandleOf(context), isNull);
      await _expectUnavailableServices(context);
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
      expect(CCRouter.routeEntryHandleOf(context), isNull);
      await _expectUnavailableServices(context);
      expect(
        (await CCRouter.navigator.close(old)).status,
        CCRouteCloseStatus.notFound,
      );
    },
  );

  testWidgets(
    'foreign Runtime payload cannot capture handle or resolve Route Services',
    (tester) async {
      final h = await _mount(tester);
      final a = h.push('A');
      await tester.pumpAndSettle();
      final entry = _detailEntries.single;
      final foreign = CCRouterTestHost();
      foreign.initialize();
      addTearDown(foreign.dispose);
      final payload = foreign.run(
        () => CCRouterHostBinding.encodeNavigationPayload(
          CCNavigationRequest(
            navigationId: entry.navigationId,
            operation: CCNavigationOperation.push,
            routeId: entry.routeId,
            uri: Uri.parse('/detail/A'),
            arguments: const _Args('A'),
            presentation: const CCPagePresentation(),
            origin: CCNavigationOrigin.internal,
            openMode: null,
          ),
        ),
      );
      CCRouteEntryHandle? captured;
      final serviceErrors = <Object>[];
      final serviceProbeDone = Completer<void>();
      var probed = false;
      final popup = showDialog<void>(
        context: h.contexts['A']!,
        builder: (_) => CCRouterHostBinding.bindRouteEntry(
          payload: payload,
          child: Builder(
            builder: (context) {
              captured = CCRouter.routeEntryHandleOf(context);
              if (!probed) {
                probed = true;
                try {
                  CCRouter.routeService<_Resource>(context);
                } catch (error) {
                  serviceErrors.add(error);
                }
                try {
                  CCRouter.routeServiceOrNull<_Resource>(context);
                } catch (error) {
                  serviceErrors.add(error);
                }
                unawaited(() async {
                  try {
                    await CCRouter.routeServiceAsync<_Resource>(context);
                  } catch (error) {
                    serviceErrors.add(error);
                  }
                  try {
                    await CCRouter.routeServiceOrNullAsync<_Resource>(context);
                  } catch (error) {
                    serviceErrors.add(error);
                  }
                  serviceProbeDone.complete();
                }());
              }
              return const AlertDialog(content: Text('foreign-runtime-popup'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await serviceProbeDone.future;
      expect(captured, isNull);
      expect(serviceErrors, hasLength(4));
      expect(
        serviceErrors,
        everyElement(isA<CCServiceScopeUnavailableError>()),
      );
      expect(_detailEntries.single.routeEntryId, entry.routeEntryId);
      Navigator.of(tester.element(find.text('foreign-runtime-popup'))).pop();
      await popup;
      await tester.pumpAndSettle();
      await CCRouter.navigator.close(h.handle('A'));
      await a;
    },
  );

  tearDown(CCRouterHost.shutdown);

  testWidgets(
    'covered exact entry stays removed after subsequent push and pop',
    (tester) async {
      final h = await _mount(tester);
      final a = h.push('A');
      await tester.pumpAndSettle();
      final target = h.handle('A');
      final b = h.push('B');
      await tester.pumpAndSettle();
      final outcome = await CCRouter.navigator.close(
        target,
        result: 'closed-A',
      );
      expect(outcome.status, CCRouteCloseStatus.closed);
      expect(await a, 'closed-A');
      await tester.pumpAndSettle();
      expect(h.resources['A']!.disposals, 1);
      expect(h.resources['B']!.disposals, 0);
      expect(find.text('page-B'), findsOneWidget);
      final c = h.push('C');
      await tester.pumpAndSettle();
      CCRouter.navigator.pop();
      await c;
      await tester.pumpAndSettle();
      CCRouter.navigator.pop();
      await b;
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('page-A', skipOffstage: false), findsNothing);
      expect(
        (await CCRouter.navigator.close(target)).status,
        CCRouteCloseStatus.notFound,
      );
      expect(h.resources['A']!.disposals, 1);
    },
  );

  testWidgets('foreign Popup remains mounted when its managed page is closed', (
    tester,
  ) async {
    final h = await _mount(tester);
    final a = h.push('A');
    await tester.pumpAndSettle();
    final target = h.handle('A');
    final popup = showDialog<String>(
      context: h.contexts['A']!,
      builder: (_) => const AlertDialog(content: Text('foreign-popup')),
    );
    await tester.pumpAndSettle();
    expect(
      (await CCRouter.navigator.close(target, result: 'A')).status,
      CCRouteCloseStatus.closed,
    );
    expect(await a, 'A');
    await tester.pumpAndSettle();
    expect(find.text('foreign-popup'), findsOneWidget);
    expect(h.resources['A']!.disposals, 1);
    final popupContext = tester.element(find.text('foreign-popup'));
    Navigator.of(popupContext).pop('popup');
    expect(await popup, 'popup');
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    final c = h.push('C');
    await tester.pumpAndSettle();
    CCRouter.navigator.pop();
    await c;
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  for (final reuseSettings in [false, true]) {
    testWidgets(
      'foreign Page with reused key/settings is not targeted: $reuseSettings',
      (tester) async {
        final h = await _mount(tester);
        final a = h.push('A');
        await tester.pumpAndSettle();
        final target = h.handle('A');
        final page = ModalRoute.of(h.contexts['A']!)!.settings as Page;
        final navigator = Navigator.of(h.contexts['A']!);
        navigator.push(
          MaterialPageRoute<void>(
            settings: reuseSettings
                ? page
                : MaterialPage<void>(
                    key: page.key,
                    name: '/detail/A',
                    child: const Text('foreign-same-page'),
                  ),
            builder: (_) => const Text('foreign-same-page'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          (await CCRouter.navigator.close(target, result: 'A')).status,
          CCRouteCloseStatus.closed,
        );
        expect(await a, 'A');
        await tester.pumpAndSettle();
        expect(find.text('foreign-same-page'), findsOneWidget);
        expect(find.text('page-A'), findsNothing);
        expect(find.text('home'), findsNothing);

        navigator.pop();
        await tester.pumpAndSettle();
        expect(find.text('home'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'foreign same-location push before managed observer keeps exact identity',
    (tester) async {
      final h = await _mount(tester);
      final a = h.push('A');
      final navigator = Navigator.of(tester.element(find.text('home')));
      navigator.push(
        MaterialPageRoute<void>(
          settings: const MaterialPage<void>(
            key: ValueKey<String>('foreign-race'),
            name: '/detail/A',
            child: Text('foreign-race'),
          ),
          builder: (_) => const Text('foreign-race'),
        ),
      );
      await tester.pumpAndSettle();

      final outcome = await CCRouter.navigator.close(
        h.handle('A'),
        result: 'managed',
      );
      expect(outcome.status, CCRouteCloseStatus.closed);
      expect(await a, 'managed');
      await tester.pumpAndSettle();
      expect(find.text('foreign-race'), findsOneWidget);
      expect(find.text('page-A'), findsNothing);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    },
  );

  testWidgets(
    'duplicate same-location instances keep selected typed result and Scope',
    (tester) async {
      final h = await _mount(tester);
      final a = h.push('same');
      await tester.pumpAndSettle();
      final aHandle = h.handle('same');
      final aResource = h.resources['same']!;
      var bCompleted = false;
      final b = h.push('same').then((value) {
        bCompleted = true;
        return value;
      });
      await tester.pumpAndSettle();
      final bHandle = h.handle('same');
      final bResource = h.resources['same']!;
      expect(bHandle, isNot(same(aHandle)));
      final outcomes = await Future.wait([
        CCRouter.navigator.close(aHandle, result: 'first'),
        CCRouter.navigator.close(aHandle, result: 'duplicate'),
      ]);
      expect(
        outcomes.where((o) => o.status == CCRouteCloseStatus.closed),
        hasLength(1),
      );
      expect(await a, 'first');
      await tester.pumpAndSettle();
      expect(bCompleted, isFalse);
      expect(aResource.disposals, 1);
      expect(bResource.disposals, 0);
      await expectLater(
        CCRouter.navigator.close(bHandle, result: 42),
        throwsA(isA<CCRouteResultTypeError>()),
      );
      expect(_detailEntries.single.routeEntryId, bHandle.routeEntryId);
      expect(
        (await CCRouter.navigator.close(bHandle, result: 'second')).status,
        CCRouteCloseStatus.closed,
      );
      expect(await b, 'second');
      await tester.pumpAndSettle();
      expect(bResource.disposals, 1);
      expect(find.text('home'), findsOneWidget);
    },
  );

  testWidgets(
    'exact nested Shell Outlet close preserves its covering entry and Shell',
    (tester) async {
      final h = await _mount(tester, nested: true);
      expect(
        CCRouter.routeEntryHandleOf(tester.element(find.text('home'))),
        isNotNull,
      );
      final a = h.push('A');
      await tester.pumpAndSettle();
      final target = h.handle('A');
      final b = h.push('B');
      await tester.pumpAndSettle();
      expect(
        (await CCRouter.navigator.close(target, result: 'nested')).status,
        CCRouteCloseStatus.closed,
      );
      expect(await a, 'nested');
      await tester.pumpAndSettle();
      expect(find.text('page-B'), findsOneWidget);
      expect(h.resources['A']!.disposals, 1);
      expect(h.resources['B']!.disposals, 0);
      CCRouter.navigator.pop();
      await b;
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('page-A', skipOffstage: false), findsNothing);
    },
  );

  testWidgets('replacement instance closes its own typed result', (
    tester,
  ) async {
    final h = await _mount(tester);
    final a = h.push('A');
    await tester.pumpAndSettle();
    final replaced = CCRouter.navigator.replace(const _Intent('B'));
    await tester.pumpAndSettle();
    expect(await a, isNull);
    expect(h.resources['A']!.disposals, 1);
    expect(
      (await CCRouter.navigator.close(
        h.handle('B'),
        result: 'replacement',
      )).status,
      CCRouteCloseStatus.closed,
    );
    expect(await replaced, 'replacement');
    await tester.pumpAndSettle();
    expect(h.resources['B']!.disposals, 1);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('push-mode dynamic open closes only its own retained Scope', (
    tester,
  ) async {
    final h = await _mount(tester);
    await CCRouter.navigator.open(Uri.parse('/detail/A'));
    await tester.pumpAndSettle();
    final target = h.handle('A');
    final b = h.push('B');
    await tester.pumpAndSettle();
    expect(
      (await CCRouter.navigator.close(target)).status,
      CCRouteCloseStatus.closed,
    );
    await tester.pumpAndSettle();
    expect(find.text('page-B'), findsOneWidget);
    expect(h.resources['A']!.disposals, 1);
    expect(h.resources['B']!.disposals, 0);
    CCRouter.navigator.pop();
    await b;
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets(
    'declarative close removes its exact Scope while preserving foreign Popup',
    (tester) async {
      final h = await _mount(tester);
      await CCRouter.navigator.go(const _Intent('A'));
      await tester.pumpAndSettle();
      final target = h.handle('A');
      final popup = showDialog<void>(
        context: h.contexts['A']!,
        builder: (_) => const AlertDialog(content: Text('declarative-popup')),
      );
      await tester.pumpAndSettle();
      expect(
        (await CCRouter.navigator.close(target)).status,
        CCRouteCloseStatus.closed,
      );
      await tester.pumpAndSettle();
      expect(_detailEntries, isEmpty);
      expect(find.text('declarative-popup'), findsOneWidget);
      expect(h.resources['A']!.disposals, 1);
      Navigator.of(tester.element(find.text('declarative-popup'))).pop();
      await popup;
      await tester.pumpAndSettle();
      expect(find.text('page-A'), findsNothing);
      expect(
        (await CCRouter.navigator.close(target)).status,
        CCRouteCloseStatus.notFound,
      );
      expect(h.resources['A']!.disposals, 1);
    },
  );

  testWidgets('denied close preserves configuration, Popup, result and Scope', (
    tester,
  ) async {
    final h = await _mount(tester, denyClose: true);
    var completed = false;
    final a = h.push('A').then((value) {
      completed = true;
      return value;
    });
    unawaited(a.catchError((_) => null));
    await tester.pumpAndSettle();
    final configuration =
        h.backend.routerConfig.routerDelegate.currentConfiguration!.uri;
    final target = h.handle('A');
    final popup = showDialog<void>(
      context: h.contexts['A']!,
      builder: (_) => const AlertDialog(content: Text('denied-popup')),
    );
    await tester.pumpAndSettle();
    expect(
      (await CCRouter.navigator.close(target)).status,
      CCRouteCloseStatus.guardDenied,
    );
    await tester.pumpAndSettle();
    expect(
      h.backend.routerConfig.routerDelegate.currentConfiguration!.uri,
      configuration,
    );
    expect(_detailEntries.single.routeEntryId, target.routeEntryId);
    expect(completed, isFalse);
    expect(find.text('denied-popup'), findsOneWidget);
    expect(h.resources['A']!.disposals, 0);
    Navigator.of(tester.element(find.text('denied-popup'))).pop();
    await popup;
    await tester.pumpAndSettle();
    expect(find.text('page-A'), findsOneWidget);
  });
}
