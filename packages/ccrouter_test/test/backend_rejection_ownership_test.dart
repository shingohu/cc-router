import 'dart:async';
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:flutter/widgets.dart' hide Intent;
import 'package:flutter_test/flutter_test.dart';
import 'reentrant_lifecycle_regression_test.dart' show ProbeAdapter;

class Backend implements CCRouterAppBackend {
  Backend(
    this.navigationAdapter, {
    CCNavigationHost? host,
    this.invalidCatalog = false,
    this.onDispose,
  }) : host = host ?? CCNavigationHost(id: 'primary');
  @override
  final CCNavigationAdapter navigationAdapter;
  @override
  final CCNavigationHost host;
  final bool invalidCatalog;
  final Future<void> Function()? onDispose;
  @override
  CCFlutterRouteCatalog get routeCatalog => CCFlutterRouteCatalog(
    const [],
    componentVersions: invalidCatalog ? const {'invalid': '1'} : const {},
  );
  int disposals = 0;
  @override
  Future<void> dispose() async {
    disposals++;
    await onDispose?.call();
  }
}

class Reusable extends ProbeAdapter {
  Reusable({this.onDispose}) : super('primary');
  void Function()? onDispose;
  @override
  void dispose() {
    try {
      onDispose?.call();
    } finally {
      super.dispose();
    }
  }
}

class _GetterBackend implements CCRouterAppBackend {
  _GetterBackend(this.adapter);
  final CCNavigationAdapter adapter;
  void Function()? onReadAdapter;
  int adapterReads = 0;
  @override
  CCNavigationAdapter get navigationAdapter {
    adapterReads++;
    onReadAdapter?.call();
    return adapter;
  }

  @override
  final host = CCNavigationHost(id: 'primary');
  @override
  CCFlutterRouteCatalog get routeCatalog => CCFlutterRouteCatalog(const []);
  int disposals = 0;
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  testWidgets(
    'Adapter getter reentry cannot destroy ownership acquired during that getter',
    (tester) async {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
      final adapter = ProbeAdapter('primary');
      final backend = _GetterBackend(adapter);
      addTearDown(CCRouterHost.shutdown);
      backend.onReadAdapter = () {
        backend.onReadAdapter = null;
        CCRouterHostBinding.attachNavigationAdapter(adapter);
      };
      await tester.pumpWidget(
        CCRouterApp.managed(backend: backend, child: const SizedBox()),
      );
      expect(tester.takeException(), isA<CCNavigationAdapterError>());
      expect(adapter.disposeCalls, 0);
      expect(backend.disposals, 0);
      expect(backend.adapterReads, 1);
      await tester.pumpWidget(const SizedBox());
      await CCRouterHost.shutdown();
      expect(adapter.disposeCalls, 1);
      await backend.dispose();
    },
  );

  testWidgets('rejected Adapter cannot transfer while disposer is on stack', (
    tester,
  ) async {
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(components: const []),
    );
    addTearDown(CCRouterHost.shutdown);
    Object? attemptedError;
    final adapter = Reusable();
    final backend = Backend(adapter, invalidCatalog: true);
    var attempted = false;
    adapter.onDispose = () {
      if (attempted) return;
      attempted = true;
      try {
        CCRouterHostBinding.attachNavigationAdapter(adapter);
      } catch (e) {
        attemptedError = e;
      }
    };
    await tester.pumpWidget(
      CCRouterApp.managed(backend: backend, child: const SizedBox()),
    );
    expect(tester.takeException(), isA<CCRegistrationError>());
    await tester.pumpWidget(const SizedBox());
    await CCRouterHost.shutdown();
    expect(attemptedError, isA<CCNavigationAdapterError>());
    expect(adapter.disposeCalls, 1);
  });
  testWidgets(
    'managed alias rejection cannot dispose overlay TestHost Adapter',
    (tester) async {
      final adapter = ProbeAdapter('primary');
      final host = CCRouterTestHost(navigationAdapter: adapter)..initialize();
      addTearDown(host.dispose);
      final backend = Backend(adapter);
      await host.run(
        () => tester.pumpWidget(
          CCRouterApp.managed(backend: backend, child: const SizedBox()),
        ),
      );
      expect(tester.takeException(), isA<CCNavigationAdapterError>());
      expect(adapter.disposeCalls, 0);
      expect(backend.disposals, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final cleanupFails in [false, true]) {
    testWidgets(
      'rejected identities stay reserved through async cleanup fails=$cleanupFails',
      (tester) async {
        CCRouterHost.initialize(
          hostAssembly: CCHostAssembly.fromComponents(components: const []),
        );
        addTearDown(CCRouterHost.shutdown);
        final gate = Completer<void>();
        final adapter = Reusable();
        final backend = Backend(
          adapter,
          invalidCatalog: true,
          onDispose: () async {
            await gate.future;
            if (cleanupFails) throw StateError('backend cleanup failed');
          },
        );
        await tester.pumpWidget(
          CCRouterApp.managed(backend: backend, child: const SizedBox()),
        );
        expect(tester.takeException(), isA<CCRegistrationError>());
        expect(backend.disposals, 1);
        expect(
          () => CCRouterHostBinding.attachNavigationAdapter(adapter),
          throwsA(isA<CCNavigationAdapterError>()),
        );
        final alias = Backend(adapter);
        for (final rejected in [backend, alias]) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            CCRouterApp.managed(backend: rejected, child: const SizedBox()),
          );
          expect(tester.takeException(), isA<CCNavigationAdapterError>());
        }
        expect(alias.disposals, 0);
        expect(backend.disposals, 1);
        expect(adapter.disposeCalls, 1);
        final independent = ProbeAdapter('primary');
        CCRouterHostBinding.attachNavigationAdapter(independent);
        expect(independent.disposeCalls, 0);
        gate.complete();
        await tester.pump();
        expect(
          tester.takeException(),
          cleanupFails ? isA<StateError>() : isNull,
        );
        await tester.pumpWidget(const SizedBox());
        await CCRouterHost.shutdown();
        expect(independent.disposeCalls, 1);
        expect(adapter.disposeCalls, 1);
        expect(backend.disposals, 1);
        await alias.dispose();
      },
    );
  }

  testWidgets(
    'overlay preflight retains independent rejected resources with caller',
    (tester) async {
      final owned = ProbeAdapter('primary');
      final host = CCRouterTestHost(navigationAdapter: owned)..initialize();
      addTearDown(host.dispose);
      final independent = ProbeAdapter('primary');
      final backend = Backend(independent);
      await host.run(
        () => tester.pumpWidget(
          CCRouterApp.managed(backend: backend, child: const SizedBox()),
        ),
      );
      expect(tester.takeException(), isA<CCNavigationAdapterError>());
      expect(independent.disposeCalls, 0);
      expect(owned.disposeCalls, 0);
      expect(backend.disposals, 0);
      await tester.pumpWidget(const SizedBox());
      independent.dispose();
      await backend.dispose();
      // The registered teardown performs disposal outside the fake clock.
    },
  );
  testWidgets(
    'managed convenience rejects overlay before Backend factory allocation',
    (tester) async {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
      addTearDown(CCRouterHost.shutdown);
      final adapter = ProbeAdapter('primary');
      final host = CCRouterTestHost(navigationAdapter: adapter)..initialize();
      addTearDown(host.dispose);
      var factories = 0;
      await host.run(
        () => tester.pumpWidget(
          CCManagedRouterApp(
            backendFactory: (configuration) {
              factories++;
              return configuration.createManagedBackend();
            },
          ),
        ),
      );
      expect(tester.takeException(), isA<CCNavigationAdapterError>());
      expect(factories, 0);
      expect(adapter.disposeCalls, 0);
      expect(CCRouter.isInitialized, isTrue);
      await tester.pumpWidget(const SizedBox());
      // The registered teardown performs disposal outside Flutter's fake clock.
    },
  );
  testWidgets(
    'rejected cleanup finishes despite Adapter, Backend and diagnostics failures',
    (tester) async {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
      addTearDown(CCRouterHost.shutdown);
      final adapterFailure = StateError('adapter cleanup');
      final backendFailure = StateError('backend cleanup');
      final reports = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.context?.toDescription().contains(
              'while disposing a rejected',
            ) ??
            false) {
          reports.add(details.exception);
          throw StateError('diagnostic handler failure');
        }
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);
      final adapter = Reusable();
      adapter.onDispose = () {
        expect(
          () => CCRouterHostBinding.attachNavigationAdapter(adapter),
          throwsA(isA<CCNavigationAdapterError>()),
        );
        throw adapterFailure;
      };
      final backend = Backend(
        adapter,
        invalidCatalog: true,
        onDispose: () async => throw backendFailure,
      );
      await tester.pumpWidget(
        CCRouterApp.managed(backend: backend, child: const SizedBox()),
      );
      expect(tester.takeException(), isA<CCRegistrationError>());
      await tester.pump();
      expect(reports, [same(adapterFailure), same(backendFailure)]);
      expect(adapter.disposeCalls, 1);
      expect(backend.disposals, 1);
      await tester.pumpWidget(const SizedBox());
      await CCRouterHost.shutdown();
      expect(adapter.disposeCalls, 1);
      expect(backend.disposals, 1);
    },
  );
}
