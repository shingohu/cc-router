import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'extends an assembly without losing optional bindings or provenance',
    () {
      final binding = _LifecycleBinding();
      final tool = _HostToolIntegration('tool');
      final original = CCHostAssembly.withLifecycleBindings(
        CCHostAssembly.fromPackageBundles(
          [bundle('orders', componentId: 'orders')],
          hostToolIntegrations: [tool],
        ),
        [binding],
      );
      final extended = CCHostAssembly.extend(
        original,
        additionalComponents: const [
          CCComponentManifest(
            id: 'extra',
            version: '1.0.0',
            dependencies: ['orders'],
            registrar: _Registrar(),
          ),
        ],
        routeCatalog: const CCFlutterRouteCatalog.empty(),
      );

      expect(extended.packages, same(original.packages));
      expect(extended.contractBundle, same(original.contractBundle));
      expect(
        extended.hostToolIntegrations,
        same(original.hostToolIntegrations),
      );
      expect(extended.lifecycleBindings, same(original.lifecycleBindings));
      expect(extended.componentManifests.map((value) => value.id), [
        'orders',
        'extra',
      ]);
      expect(original.componentManifests, hasLength(1));
      expect(extended.routeCatalog.componentVersions, {
        'orders': '1.0.0',
        'extra': '1.0.0',
      });
      expect(
        () => CCHostAssembly.withLifecycleBindings(extended, [binding]),
        throwsStateError,
      );
      expect(() => extended.componentManifests.clear(), throwsUnsupportedError);
    },
  );

  test('extension rejects component replacement and missing dependencies', () {
    final original = CCHostAssembly.fromPackageBundles([
      bundle('orders', componentId: 'orders'),
    ]);
    for (final (id, dependencies, code) in [
      ('orders', <String>[], CCHostAssemblyErrorCode.duplicateComponent),
      (
        'extra',
        ['missing'],
        CCHostAssemblyErrorCode.missingComponentDependency,
      ),
    ]) {
      expect(
        () => CCHostAssembly.extend(
          original,
          additionalComponents: [
            CCComponentManifest(
              id: id,
              version: '1.0.0',
              dependencies: dependencies,
              registrar: const _Registrar(),
            ),
          ],
        ),
        throwsA(isA<CCHostAssemblyError>().having((e) => e.type, 'type', code)),
      );
    }
  });

  test('resolves transitive bundles and deduplicates a diamond dependency', () {
    final shared = bundle('shared', componentId: 'shared_component');
    final left = bundle('left', dependencies: [shared]);
    final right = bundle('right', dependencies: [shared]);

    final assembly = CCHostAssembly.fromPackageBundles([right, left]);

    expect(assembly.packages.map((package) => package.packageName), [
      'shared',
      'left',
      'right',
    ]);
    expect(
      () => assembly.packages.add(bundle('unexpected')),
      throwsUnsupportedError,
    );
    expect(assembly.componentManifests.map((manifest) => manifest.id), [
      'shared_component',
    ]);
  });

  test('orders required and present optional component dependencies', () {
    final assembly = CCHostAssembly.fromPackageBundles([
      bundle('feature', componentId: 'feature', dependencies: const []),
      bundle(
        'checkout',
        componentId: 'checkout',
        componentDependencies: const ['feature'],
        optionalComponentDependencies: const ['analytics'],
      ),
      bundle('analytics', componentId: 'analytics'),
    ]);

    expect(assembly.componentManifests.map((manifest) => manifest.id), [
      'analytics',
      'feature',
      'checkout',
    ]);
  });

  test('creates the same deterministic graph from handwritten components', () {
    final assembly = CCHostAssembly.fromComponents(
      components: const [
        CCComponentManifest(
          id: 'checkout',
          version: '1.0.0',
          dependencies: ['orders'],
          registrar: _Registrar(),
        ),
        CCComponentManifest(
          id: 'orders',
          version: '1.0.0',
          registrar: _Registrar(),
        ),
      ],
    );

    expect(assembly.packages, isEmpty);
    expect(assembly.componentManifests.map((manifest) => manifest.id), [
      'orders',
      'checkout',
    ]);
    expect(assembly.routeCatalog.componentVersions, {
      'orders': '1.0.0',
      'checkout': '1.0.0',
    });
  });

  test('rejects an incomplete handwritten component graph', () {
    expect(
      () => CCHostAssembly.fromComponents(
        components: const [
          CCComponentManifest(
            id: 'checkout',
            version: '1.0.0',
            dependencies: ['orders'],
            registrar: _Registrar(),
          ),
        ],
      ),
      throwsA(
        isA<CCHostAssemblyError>().having(
          (error) => error.type,
          'type',
          CCHostAssemblyErrorCode.missingComponentDependency,
        ),
      ),
    );
  });

  test('orders Host tool integrations and rejects duplicate identities', () {
    final first = _HostToolIntegration('zeta');
    final second = _HostToolIntegration('alpha');
    final assembly = CCHostAssembly.fromPackageBundles(
      [bundle('host')],
      hostToolIntegrations: [first, second],
    );

    expect(assembly.hostToolIntegrations.map((tool) => tool.id), [
      'alpha',
      'zeta',
    ]);
    expect(
      () => assembly.hostToolIntegrations.add(first),
      throwsUnsupportedError,
    );
    expect(
      () => CCHostAssembly.fromPackageBundles(
        [bundle('host')],
        hostToolIntegrations: [first, _HostToolIntegration('zeta')],
      ),
      throwsA(
        isA<CCHostAssemblyError>().having(
          (error) => error.type,
          'type',
          CCHostAssemblyErrorCode.hostToolIntegration,
        ),
      ),
    );
    expect(
      () => CCHostAssembly.fromPackageBundles(
        [bundle('host')],
        hostToolIntegrations: [_HostToolIntegration('  ')],
      ),
      throwsA(
        isA<CCHostAssemblyError>().having(
          (error) => error.type,
          'type',
          CCHostAssemblyErrorCode.hostToolIntegration,
        ),
      ),
    );
  });

  test('rejects incompatible Package identities in a diamond', () {
    final left = bundle(
      'left',
      dependencies: [bundle('shared', fingerprint: 'first')],
    );
    final right = bundle(
      'right',
      dependencies: [bundle('shared', fingerprint: 'second')],
    );

    expect(
      () => CCHostAssembly.fromPackageBundles([left, right]),
      throwsA(
        isA<CCHostAssemblyError>().having(
          (error) => error.type,
          'type',
          CCHostAssemblyErrorCode.packageConflict,
        ),
      ),
    );
  });

  test('rejects duplicate component identities', () {
    expect(
      () => CCHostAssembly.fromPackageBundles([
        bundle('first', componentId: 'duplicate'),
        bundle('second', componentId: 'duplicate'),
      ]),
      throwsA(
        isA<CCHostAssemblyError>().having(
          (error) => error.type,
          'type',
          CCHostAssemblyErrorCode.duplicateComponent,
        ),
      ),
    );
  });

  test('rejects missing required component dependencies', () {
    expect(
      () => CCHostAssembly.fromPackageBundles([
        bundle(
          'checkout',
          componentId: 'checkout',
          componentDependencies: const ['orders'],
        ),
      ]),
      throwsA(
        isA<CCHostAssemblyError>().having(
          (error) => error.type,
          'type',
          CCHostAssemblyErrorCode.missingComponentDependency,
        ),
      ),
    );
  });

  test('merges route catalogs with resolved component versions', () {
    final destination = CCFlutterRouteDestination(
      route: CCNavigationRoute(
        routeId: 'orders.detail',
        patterns: const [CCPathPattern('/orders/:id', primary: true)],
        presentation: const CCPagePresentation(),
        deepLink: CCDeepLinkPolicy.disabled,
      ),
      builder: (_) => const SizedBox.shrink(),
    );
    final assembly = CCHostAssembly.fromPackageBundles([
      CCGeneratedPackageBundle(
        packageName: 'orders',
        packageVersion: '1.0.0',
        contentFingerprint: 'orders-fingerprint',
        componentManifests: const [
          CCComponentManifest(
            id: 'orders_component',
            version: '1.2.0',
            registrar: _Registrar(),
          ),
        ],
        routeCatalog: CCFlutterRouteCatalog([destination]),
      ),
    ]);

    expect(
      assembly.routeCatalog.destinationFor('orders.detail'),
      same(destination),
    );
    expect(assembly.routeCatalog.componentVersions, {
      'orders_component': '1.2.0',
    });
  });
}

CCGeneratedPackageBundle bundle(
  String packageName, {
  String fingerprint = 'fingerprint',
  String? componentId,
  List<String> componentDependencies = const [],
  List<String> optionalComponentDependencies = const [],
  List<CCGeneratedPackageBundle> dependencies = const [],
}) => CCGeneratedPackageBundle(
  packageName: packageName,
  packageVersion: '1.0.0',
  contentFingerprint: '$packageName-$fingerprint',
  componentManifests: [
    if (componentId != null)
      CCComponentManifest(
        id: componentId,
        version: '1.0.0',
        registrar: const _Registrar(),
        dependencies: componentDependencies,
        optionalDependencies: optionalComponentDependencies,
      ),
  ],
  dependencies: dependencies,
);

final class _Registrar implements CCComponentRegistrar {
  const _Registrar();

  @override
  void register(CCRegistry registry) {}
}

final class _HostToolIntegration implements CCHostToolIntegration {
  _HostToolIntegration(this.id);

  @override
  final String id;

  @override
  void onRuntimeReady() {}

  @override
  void onRuntimeStopping() {}
}

final class _LifecycleBinding implements CCHostLifecycleBinding {
  @override
  String get id => 'test.binding';
  @override
  void attach() {}
  @override
  void detach() {}
}
