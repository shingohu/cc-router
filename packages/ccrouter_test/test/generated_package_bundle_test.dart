import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves transitive bundles and deduplicates a diamond dependency', () {
    final shared = bundle('shared', componentId: 'shared_component');
    final left = bundle('left', dependencies: [shared]);
    final right = bundle('right', dependencies: [shared]);

    final assembly = CCGeneratedPackageBundle.resolve([right, left]);

    expect(assembly.packages.map((package) => package.packageName), [
      'shared',
      'left',
      'right',
    ]);
    expect(assembly.componentManifests.map((manifest) => manifest.id), [
      'shared_component',
    ]);
  });

  test('orders required and present optional component dependencies', () {
    final assembly = CCGeneratedPackageBundle.resolve([
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
      () => CCGeneratedPackageBundle.resolve([left, right]),
      throwsA(
        isA<CCGeneratedPackageBundleError>().having(
          (error) => error.type,
          'type',
          CCGeneratedPackageBundleErrorType.packageConflict,
        ),
      ),
    );
  });

  test('rejects duplicate component identities', () {
    expect(
      () => CCGeneratedPackageBundle.resolve([
        bundle('first', componentId: 'duplicate'),
        bundle('second', componentId: 'duplicate'),
      ]),
      throwsA(
        isA<CCGeneratedPackageBundleError>().having(
          (error) => error.type,
          'type',
          CCGeneratedPackageBundleErrorType.duplicateComponent,
        ),
      ),
    );
  });

  test('rejects missing required component dependencies', () {
    expect(
      () => CCGeneratedPackageBundle.resolve([
        bundle(
          'checkout',
          componentId: 'checkout',
          componentDependencies: const ['orders'],
        ),
      ]),
      throwsA(
        isA<CCGeneratedPackageBundleError>().having(
          (error) => error.type,
          'type',
          CCGeneratedPackageBundleErrorType.missingComponentDependency,
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
    final assembly = CCGeneratedPackageBundle.resolve([
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
