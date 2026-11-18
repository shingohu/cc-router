import 'dart:developer';
import 'dart:isolate';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'support/managed_test_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;
import 'package:vm_service/vm_service_io.dart';

final class _Resources {
  final routes = <WeakReference<Route<void>>>[];
  final controllers = <WeakReference<AnimationController>>[];
  final arguments = <WeakReference<Object>>[];
  var disposedRoutes = 0;
}

final class _TrackedRoute extends MaterialPageRoute<void> {
  _TrackedRoute(this.resources, int index)
    : super(
        settings: RouteSettings(name: '/closed/$index', arguments: Object()),
        builder: (_) => const Text('temporary page'),
      ) {
    resources.routes.add(WeakReference(this));
    resources.arguments.add(WeakReference(settings.arguments!));
  }

  final _Resources resources;

  @override
  AnimationController createAnimationController() {
    final controller = super.createAnimationController();
    resources.controllers.add(WeakReference(controller));
    return controller;
  }

  @override
  void dispose() {
    super.dispose();
    resources.disposedRoutes++;
  }
}

final class _DiagnosticOwner {
  final target = Object();
}

// Keep strong Route locals out of the scope that later forces GC.
Future<void> _visit(
  WidgetTester tester,
  NavigatorState navigator,
  _Resources resources,
  String removal,
  int index,
) async {
  final route = _TrackedRoute(resources, index * 2);
  final completed = navigator.push<void>(route);
  await tester.pumpAndSettle();
  switch (removal) {
    case 'pop':
      navigator.pop();
    case 'replace':
      navigator.pushReplacement<void, void>(
        _TrackedRoute(resources, index * 2 + 1),
      );
      await tester.pumpAndSettle();
      navigator.pop();
    case 'remove':
      navigator.removeRoute(route);
  }
  await tester.pumpAndSettle();
  await completed;
}

Future<void> _expectCollected(
  WidgetTester tester,
  Iterable<WeakReference<Object>> references,
) async {
  try {
    expect(references.map((ref) => ref.target), everyElement(isNull));
  } catch (_) {
    await tester.runAsync(() async {
      try {
        final uri = (await Service.getInfo()).serverWebSocketUri;
        if (uri == null) {
          debugPrint(
            'Retaining path unavailable; run with --enable-vmservice.',
          );
          return;
        }
        final service = await vmServiceConnectUri(
          uri.toString(),
        ).timeout(const Duration(seconds: 5));
        try {
          for (final reference in references) {
            final objectId = _objectId(reference);
            if (objectId == null) continue;
            final path = await service
                .getRetainingPath(
                  Service.getIsolateId(Isolate.current)!,
                  objectId,
                  100,
                )
                .timeout(const Duration(seconds: 5));
            debugPrint('Retaining path (target -> ${path.gcRootType}):');
            for (final element in path.elements!) {
              final value = element.value?.toJson();
              final type = value?['class'];
              debugPrint(
                '${type?['library']?['uri'] ?? ''} '
                '${type?['name'] ?? value?['type']} '
                'via ${element.parentField ?? element.parentMapKey ?? element.parentListIndex ?? '<target>'}',
              );
            }
            break;
          }
        } finally {
          await service.dispose();
        }
      } catch (error) {
        debugPrint('Retaining path unavailable: $error');
      }
    });
    rethrow;
  }
}

// Do not retain the target in an async frame while asking the VM who owns it.
String? _objectId(WeakReference<Object> reference) {
  final target = reference.target;
  return target == null ? null : Service.getObjectId(target);
}

void main() {
  testWidgets(
    'GC diagnostics preserve failures and identify a retained target',
    (tester) async {
      final owner = _DiagnosticOwner();
      final messages = <String>[];
      final originalDebugPrint = debugPrint;
      final serviceInfo = await tester.runAsync(Service.getInfo);
      debugPrint = (message, {wrapWidth}) {
        if (message != null) messages.add(message);
      };
      try {
        await expectLater(
          _expectCollected(tester, [WeakReference(owner.target)]),
          throwsA(isA<TestFailure>()),
        );
        expect(
          messages.join('\n'),
          contains(
            serviceInfo?.serverWebSocketUri == null
                ? 'run with --enable-vmservice'
                : '_DiagnosticOwner via target',
          ),
        );
        expect(owner.target, isNotNull);
      } finally {
        debugPrint = originalDebugPrint;
      }
    },
  );

  for (final capacity in [0, 2, 1000]) {
    for (final removal in ['pop', 'replace', 'remove']) {
      testWidgets(
        '$removal releases Routes and controllers with live history capacity $capacity',
        (tester) async {
          CCRouterHost.initialize(
            navigationDiagnosticCapacity: capacity,
            hostAssembly: CCHostAssembly.fromComponents(
              components: const [
                CCComponentManifest(
                  id: 'fixture',
                  version: '1.0.0',
                  registrar: TestHomeRegistrar(),
                ),
              ],
            ),
          );
          final backend = CCManagedRouterBackend(
            routeCatalog: CCFlutterRouteCatalog(
              [testHomeDestination()],
              componentVersions: const {'fixture': '1.0.0'},
            ),
          );
          final navigatorKey = backend.host.navigatorKey;
          addTearDown(CCRouterHost.shutdown);
          await tester.pumpWidget(
            CCRouterApp.managed(
              backend: backend,
              child: MaterialApp.router(routerConfig: backend.routerConfig),
            ),
          );
          await tester.pumpAndSettle();

          final resources = _Resources();
          for (var index = 0; index < 5; index++) {
            await _visit(
              tester,
              navigatorKey.currentState!,
              resources,
              removal,
              index,
            );
          }
          final expected = removal == 'replace' ? 10 : 5;
          expect(resources.disposedRoutes, expected);
          expect(resources.controllers, hasLength(expected));
          // Retain a caller's history snapshot too: neither it nor the live
          // Adapter may keep closed resources alive. No capacity eviction or
          // Adapter/Router disposal may be used to make this test pass.
          final history = CCRouter.recentBackendNavigationEvents;
          expect(history.length, capacity == 0 ? 0 : greaterThan(0));
          expect(history.length, lessThan(1000));
          await tester.runAsync(
            () =>
                forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20)),
          );
          await _expectCollected(tester, resources.routes);
          await _expectCollected(tester, resources.controllers);
          await _expectCollected(tester, resources.arguments);
          expect(CCRouter.recentBackendNavigationEvents.length, history.length);
          expect(find.text('home'), findsOneWidget);
          expect(navigatorKey.currentState!.canPop(), isFalse);
        },
      );
    }
  }
}
