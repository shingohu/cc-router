import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'reentrant_lifecycle_regression_test.dart' show ProbeAdapter;

class Backend implements CCRouterAppBackend {
  Backend(this.host, {ProbeAdapter? adapter, this.invalidCatalog = false})
    : navigationAdapter = adapter ?? ProbeAdapter(host.id);
  @override
  final CCNavigationHost host;
  @override
  final ProbeAdapter navigationAdapter;
  @override
  CCFlutterRouteCatalog get routeCatalog => CCFlutterRouteCatalog(
    const [],
    componentVersions: invalidCatalog ? const {'missing': '1.0.0'} : const {},
  );
  final bool invalidCatalog;
  int disposals = 0;
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  for (final sameHostObject in [true, false]) {
    testWidgets(
      'managed Backend mount rollback sameHostObject=$sameHostObject',
      (tester) async {
        CCRouterHost.initialize(
          hostAssembly: CCHostAssembly.fromComponents(components: const []),
        );
        addTearDown(CCRouterHost.shutdown);
        final host = CCNavigationHost(id: 'shared');
        final rejected = Backend(
          sameHostObject ? host : CCNavigationHost(id: 'shared'),
        );
        addTearDown(() async {
          if (rejected.navigationAdapter.disposeCalls == 0)
            rejected.navigationAdapter.dispose();
          if (rejected.disposals == 0) await rejected.dispose();
        });
        await tester.pumpWidget(
          Stack(
            textDirection: TextDirection.ltr,
            children: [
              CCRouterApp(
                key: const ValueKey('owner'),
                host: host,
                child: const SizedBox(),
              ),
            ],
          ),
        );
        await tester.pumpWidget(
          Stack(
            textDirection: TextDirection.ltr,
            children: [
              CCRouterApp(
                key: const ValueKey('owner'),
                host: host,
                child: const SizedBox(),
              ),
              CCRouterApp.managed(
                key: const ValueKey('rejected'),
                backend: rejected,
                child: const SizedBox(),
              ),
            ],
          ),
        );
        expect(tester.takeException(), isA<FlutterError>());
        await tester.pumpWidget(const SizedBox());
        await CCRouterHost.shutdown();
        expect(rejected.navigationAdapter.disposeCalls, 1);
        expect(rejected.disposals, 1);
      },
    );
  }

  for (final alias in ['sameBackend', 'sameAdapter', 'independent']) {
    for (final sameHost in [true, false]) {
      testWidgets('rejected $alias preserves mounted owner sameHost=$sameHost', (
        tester,
      ) async {
        CCRouterHost.initialize(
          hostAssembly: CCHostAssembly.fromComponents(components: const []),
        );
        addTearDown(CCRouterHost.shutdown);
        final host = CCNavigationHost(id: 'owner');
        final active = Backend(host);
        final rejected = alias == 'sameBackend'
            ? active
            : Backend(
                sameHost ? host : CCNavigationHost(id: 'rejected'),
                adapter: alias == 'sameAdapter'
                    ? active.navigationAdapter
                    : null,
              );
        Widget tree({bool reject = false}) => Stack(
          textDirection: TextDirection.ltr,
          children: [
            CCRouterApp.managed(
              key: const ValueKey('owner'),
              backend: active,
              child: const SizedBox(),
            ),
            if (reject)
              CCRouterApp.managed(
                key: const ValueKey('rejected'),
                backend: rejected,
                child: const Text('must not build'),
              ),
          ],
        );
        await tester.pumpWidget(tree());
        await tester.pumpWidget(tree(reject: true));
        expect(tester.takeException(), isA<CCNavigationAdapterError>());
        expect(find.text('must not build'), findsNothing);
        expect(find.text('Application failed to start.'), findsOneWidget);
        expect(active.navigationAdapter.disposeCalls, 0);
        expect(active.disposals, 0);
        expect(CCRouter.isInitialized, isTrue);
        expect(rejected.disposals, alias == 'independent' ? 1 : 0);
        await tester.pumpWidget(tree());
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await CCRouterHost.shutdown();
        expect(active.navigationAdapter.disposeCalls, 1);
        expect(active.disposals, 1);
        if (alias == 'independent') {
          expect(rejected.navigationAdapter.disposeCalls, 1);
          expect(rejected.disposals, 1);
        } else if (alias == 'sameAdapter') {
          // This wrapper never transferred ownership; its creator releases only
          // wrapper resources, without disposing the shared Adapter again.
          await rejected.dispose();
        }
      });
    }
  }

  testWidgets('catalog rejection rolls back Host bridge and Flutter observer', (
    tester,
  ) async {
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(components: const []),
    );
    addTearDown(CCRouterHost.shutdown);
    final host = CCNavigationHost(id: 'retry');
    final rejected = Backend(host, invalidCatalog: true);
    await tester.pumpWidget(
      CCRouterApp.managed(backend: rejected, child: const SizedBox()),
    );
    expect(tester.takeException(), isA<CCRegistrationError>());
    expect(rejected.navigationAdapter.disposeCalls, 1);
    expect(rejected.disposals, 1);
    await tester.pumpWidget(const SizedBox());
    final replacement = Backend(host);
    await tester.pumpWidget(
      CCRouterApp.managed(backend: replacement, child: const SizedBox()),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await CCRouterHost.shutdown();
    expect(replacement.navigationAdapter.disposeCalls, 1);
    expect(replacement.disposals, 1);
    expect(rejected.disposals, 1);
  });
}
