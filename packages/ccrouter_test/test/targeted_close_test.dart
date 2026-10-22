import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
// ignore: deprecated_member_use
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
  final CCGoRouterBackend backend;
  final Map<String, BuildContext> contexts;
  final Map<String, _Resource> resources;
  CCRouteEntryHandle handle(String id) =>
      CCRouter.routeEntryHandleOf(contexts[id]!)!;
  Future<String?> push(String id) => CCRouter.navigator.push(_Intent(id));
}

Future<_Harness> _mount(
  WidgetTester tester, {
  bool externalExit = false,
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
          registrar: _Registrar(placement: placement),
        ),
      ],
    ),
  );
  final contexts = <String, BuildContext>{};
  final resources = <String, _Resource>{};
  final destination = CCFlutterRouteDestination.fromDefinition(
    definition: _definition(placement: placement),
    builder: (args) => Builder(
      builder: (context) {
        final id = args.path['id']!;
        contexts[id] = context;
        resources[id] = CCRouter.routeService<_Resource>(context);
        return Text('page-$id');
      },
    ),
  );
  final shellKey = GlobalKey<NavigatorState>();
  final shellObserver = CCGoRouterNavigationObserver(outlet: 'content');
  final nestedDetail = GoRoute(
    path: '/detail/:id',
    pageBuilder: (_, state) => CCGoRouterPage<Object?>(
      key: state.pageKey,
      name: 'close.detail',
      presentation: const CCPagePresentation(),
      child: CCRouterHostBinding.bindRouteEntry(
        payload: state.extra,
        child: Builder(
          builder: (context) {
            final id = state.pathParameters['id']!;
            contexts[id] = context;
            resources[id] = CCRouter.routeService<_Resource>(context);
            return Text('page-$id');
          },
        ),
      ),
    ),
  );
  final shell = ShellRoute(
    navigatorKey: shellKey,
    observers: [shellObserver],
    builder: (_, _, child) => child,
    routes: [
      GoRoute(path: '/nested-home', builder: (_, _) => const Text('home')),
      nestedDetail,
    ],
  );
  final backend = CCGoRouterBackend.managed(
    host: nested
        ? CCNavigationHost(navigatorKeys: {'content': shellKey})
        : null,
    initialLocation: nested ? '/nested-home' : '/',
    overrides: nested
        ? {
            'close.detail': CCGoRouterRouteOverride(
              binding: CCGoRouterRouteBinding(
                routeId: 'close.detail',
                goRoute: nestedDetail,
              ),
              includeInRootRoutes: false,
            ),
          }
        : const {},
    shells: nested
        ? [
            CCGoRouterShellBinding(
              shellId: 'workspace',
              route: shell,
              initialOutlet: 'content',
              outlets: {'content': shellKey},
            ),
          ]
        : const [],
    outletObservers: nested ? [shellObserver] : const [],
    catalog: CCFlutterRouteCatalog(
      [destination],
      componentVersions: const {'close': '1.0.0'},
    ),
    hostRoutes: [
      GoRoute(
        path: '/',
        onExit: externalExit ? (_, _) async => true : null,
        builder: (_, _) => const Text('home'),
      ),
    ],
  );
  await tester.pumpWidget(
    CCRouterApp.managed(
      backend: backend,
      child: MaterialApp.router(routerConfig: backend.router),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(backend, contexts, resources);
}

void main() {
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
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
      expect(CCRouter.routeEntryHandleOf(context), isNull);
      expect(
        (await CCRouter.navigator.close(old)).status,
        CCRouteCloseStatus.notFound,
      );
    },
  );

  testWidgets(
    'foreign Runtime payload with reused navigationId cannot capture current handle',
    (tester) async {
      final h = await _mount(tester);
      final a = h.push('A');
      await tester.pumpAndSettle();
      final entry = CCRouter.activeRouteEntries.single;
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
      final popup = showDialog<void>(
        context: h.contexts['A']!,
        builder: (_) => CCRouterHostBinding.bindRouteEntry(
          payload: payload,
          child: Builder(
            builder: (context) {
              captured = CCRouter.routeEntryHandleOf(context);
              return const AlertDialog(content: Text('foreign-runtime-popup'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(captured, isNull);
      expect(CCRouter.activeRouteEntries.single.handle, same(entry.handle));
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

  testWidgets(
    'foreign Page with the same location and key is not targeted by close',
    (tester) async {
      final h = await _mount(tester);
      final a = h.push('A');
      await tester.pumpAndSettle();
      final target = h.handle('A');
      final configuration =
          h.backend.router.routerDelegate.currentConfiguration;
      final imperative = configuration.matches
          .whereType<ImperativeRouteMatch>()
          .single;
      final navigator = Navigator.of(h.contexts['A']!);
      navigator.push(
        MaterialPageRoute<void>(
          settings: MaterialPage<void>(
            key: imperative.pageKey,
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
      expect(CCRouter.activeRouteEntries.single.handle, same(bHandle));
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
        isNull,
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
    'declarative unsupported close preserves configuration, Popup and Scope',
    (tester) async {
      final h = await _mount(tester);
      await CCRouter.navigator.go(const _Intent('A'));
      await tester.pumpAndSettle();
      final target = h.handle('A');
      final configuration =
          h.backend.router.routerDelegate.currentConfiguration;
      final entries = CCRouter.activeRouteEntries.map((e) => e.handle).toList();
      final popup = showDialog<void>(
        context: h.contexts['A']!,
        builder: (_) => const AlertDialog(content: Text('unsupported-popup')),
      );
      await tester.pumpAndSettle();
      expect(
        (await CCRouter.navigator.close(target)).status,
        CCRouteCloseStatus.unsupported,
      );
      await tester.pumpAndSettle();
      expect(
        h.backend.router.routerDelegate.currentConfiguration,
        same(configuration),
      );
      expect(CCRouter.activeRouteEntries.map((e) => e.handle), entries);
      expect(find.text('unsupported-popup'), findsOneWidget);
      expect(h.resources['A']!.disposals, 0);
      Navigator.of(tester.element(find.text('unsupported-popup'))).pop();
      await popup;
      await tester.pumpAndSettle();
      expect(find.text('page-A'), findsOneWidget);
    },
  );

  testWidgets(
    'onExit unsupported close leaves declaration, Popup and result untouched',
    (tester) async {
      final h = await _mount(tester, externalExit: true);
      var completed = false;
      final a = h.push('A').then((value) {
        completed = true;
        return value;
      });
      unawaited(a.catchError((_) => null));
      await tester.pumpAndSettle();
      final configuration =
          h.backend.router.routerDelegate.currentConfiguration;
      final target = h.handle('A');
      final popup = showDialog<void>(
        context: h.contexts['A']!,
        builder: (_) => const AlertDialog(content: Text('unsupported-popup')),
      );
      await tester.pumpAndSettle();
      expect(
        (await CCRouter.navigator.close(target)).status,
        CCRouteCloseStatus.unsupported,
      );
      await tester.pumpAndSettle();
      expect(
        h.backend.router.routerDelegate.currentConfiguration,
        same(configuration),
      );
      expect(CCRouter.activeRouteEntries.single.handle, same(target));
      expect(completed, isFalse);
      expect(find.text('unsupported-popup'), findsOneWidget);
      expect(h.resources['A']!.disposals, 0);
      Navigator.of(tester.element(find.text('unsupported-popup'))).pop();
      await popup;
      await tester.pumpAndSettle();
      expect(find.text('page-A'), findsOneWidget);
    },
  );
}
