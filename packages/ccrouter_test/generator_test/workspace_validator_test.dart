import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/ccrouter_generator.dart';
import 'package:test/test.dart';

Map<String, Object?> document({
  required List<Map<String, Object?>> components,
  required List<Map<String, Object?>> routes,
  List<Map<String, Object?>> routeImplementations = const [],
  String source = 'routes.dart',
  String package = 'orders',
}) => {
  'schemaVersion': 2,
  'package': package,
  'source': source,
  'componentDeclarations': components
      .map((component) => component['id'])
      .toList(),
  'components': components,
  'routes': routes,
  'routeImplementations': routeImplementations,
};

Map<String, Object?> component(
  String id, {
  List<String> dependencies = const [],
  List<String> optionalDependencies = const [],
}) => {
  'id': id,
  'version': '1.0.0',
  'dependencies': dependencies,
  'optionalDependencies': optionalDependencies,
};

Map<String, Object?> route(
  String id,
  String owner, {
  String? exposure,
  String pattern = '/detail/:id',
  String patternType = 'CCPathPattern',
  Map<String, String> constraints = const {},
  bool publicContract = false,
  String contractPackage = 'orders',
  String hostId = 'default',
  String? parentRouteId,
  String? shellId = 'orders.shell',
  String navigatorOutlet = 'detail',
  List<String> interceptorIds = const [],
  List<String> popGuardIds = const [],
}) => {
  'id': id,
  'componentId': owner,
  'exposure': exposure ?? (publicContract ? 'public' : 'internal'),
  'deepLink': 'disabled',
  'description': 'Documented route.',
  'declaration': {
    'package': contractPackage,
    'library': 'lib/detail.dart',
    'kind': publicContract ? 'contract' : 'page',
  },
  'navigationSources': ['typedIntent', 'internalUri'],
  'restoration': {'status': 'unsupported'},
  'placement': {
    'hostId': hostId,
    'parentRouteId': parentRouteId,
    'shellId': shellId,
    'navigatorOutlet': navigatorOutlet,
  },
  'interceptorIds': interceptorIds,
  'popGuardIds': popGuardIds,
  'presentation': {'type': 'page'},
  'contracts': {
    'route': 'DetailRoute',
    'arguments': 'DetailRouteArguments',
    'package': contractPackage,
    'library': 'lib/detail.route.contract.g.dart',
  },
  if (!publicContract) 'registration': 'ccrouterRegisterDetailRoute',
  if (!publicContract)
    'destination': {
      'descriptor': 'ccrouterDescribeDetailRoute',
      'builder': 'ccrouterBuildDetailRoute',
    },
  'patterns': [
    {
      'type': patternType,
      'value': pattern,
      'primary': true,
      if (patternType != 'CCRegexPattern') 'constraints': constraints,
    },
  ],
  'parameters': [
    {
      'name': 'id',
      'wireName': 'id',
      'source': 'path',
      'type': 'int',
      'cardinality': null,
      'required': true,
      'description': 'Stable identity.',
    },
  ],
  'resultType': 'void',
};

Map<String, Object?> implementation(
  String routeId,
  String owner, {
  String package = 'orders',
}) => {
  'routeId': routeId,
  'componentId': owner,
  'package': package,
  'source': 'lib/detail_page.dart',
  'registration': 'ccrouterRegisterDetailRoute',
  'destination': {
    'descriptor': 'ccrouterDescribeDetailRoute',
    'builder': 'ccrouterBuildDetailRoute',
  },
};

void main() {
  test('accepts components and emits derived route exposure', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [route('orders.detail', 'orders')],
      ),
      document(
        source: 'checkout.dart',
        components: [
          component('checkout', dependencies: ['orders']),
        ],
        routes: [],
      ),
    ]);
    expect(result.errors, isEmpty);
    expect(result.markdownDocument, contains('`orders.detail`'));
    expect(result.markdownDocument, contains('Exposure: `internal`'));
    expect(result.markdownDocument, contains('Stable identity.'));
    expect(result.markdownDocument, contains('outlet `detail`'));
    expect(result.markdownDocument, contains('Restoration: `unsupported`'));
    expect(jsonDecode(result.machineDocumentJson), isA<Map>());
  });

  test('rejects missing required component dependencies', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [
          component('checkout', dependencies: ['orders']),
        ],
        routes: const [],
      ),
    ]);

    expect(
      result.errors,
      contains('Component "checkout" requires missing "orders".'),
    );
  });

  test('rejects required and optional self dependencies', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [
          component('orders', dependencies: ['orders']),
          component('payments', optionalDependencies: ['payments']),
        ],
        routes: const [],
      ),
    ]);

    expect(
      result.errors,
      containsAll([
        'Component "orders" cannot depend on itself.',
        'Component "payments" cannot depend on itself.',
      ]),
    );
  });

  test('rejects cycles across required and present optional dependencies', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [
          component('account', dependencies: ['orders']),
          component('orders', optionalDependencies: ['payment']),
          component('payment', dependencies: ['account']),
        ],
        routes: const [],
      ),
    ]);

    expect(
      result.errors,
      contains(
        'Component dependency cycle: account -> orders -> payment -> account.',
      ),
    );
  });

  test('ignores absent optional dependencies', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [
          component('orders', optionalDependencies: ['campaign']),
        ],
        routes: const [],
      ),
    ]);

    expect(result.errors, isEmpty);
    expect(
      (result.machineDocument['components'] as List).map(
        (component) => (component as Map)['id'],
      ),
      ['orders'],
    );
  });

  test(
    'orders present optional and required dependencies deterministically',
    () {
      final result = CCRouteWorkspaceValidator.validate([
        document(
          components: [
            component(
              'checkout',
              dependencies: ['orders'],
              optionalDependencies: ['analytics'],
            ),
            component('orders', dependencies: ['account']),
            component('unrelated'),
            component('analytics'),
            component('account'),
          ],
          routes: const [],
        ),
      ]);

      expect(result.errors, isEmpty);
      expect(
        (result.machineDocument['components'] as List).map(
          (component) => (component as Map)['id'],
        ),
        ['account', 'analytics', 'orders', 'checkout', 'unrelated'],
      );
    },
  );

  test('rejects unknown route owners', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders'), component('checkout')],
        routes: [route('unknown.owner', 'missing')],
      ),
    ]);
    expect(result.errors, contains(contains('unknown owner component')));
  });

  test('rejects unknown source exposure', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [route('orders.detail', 'orders', exposure: 'external')],
        routeImplementations: [implementation('orders.detail', 'orders')],
      ),
    ]);

    expect(result.errors, contains(contains('unknown source exposure')));
  });

  test('rejects duplicate routes and conflicting component descriptors', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [route('orders.detail', 'orders')],
      ),
      document(
        source: 'other.dart',
        components: [
          component('orders', dependencies: ['account']),
        ],
        routes: [route('orders.detail', 'orders')],
      ),
    ]);
    expect(result.errors, contains(contains('conflicting descriptors')));
    expect(result.errors, contains(contains('declared more than once')));
    expect(result.errors, contains(contains('more than one CCComponent')));
  });

  test('requires an explicit registrar component declaration', () {
    final metadata = document(
      components: [component('orders')],
      routes: [route('orders.detail', 'orders')],
    );
    metadata['componentDeclarations'] = <String>[];
    final result = CCRouteWorkspaceValidator.validate([metadata]);
    expect(result.errors.single, contains('no CCComponent declaration'));
  });

  test('derives package exposure for a same-package public contract', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [route('orders.detail', 'orders', publicContract: true)],
        routeImplementations: [implementation('orders.detail', 'orders')],
      ),
    ]);

    expect(result.errors, isEmpty);
    expect(
      (result.machineDocument['routes'] as List).single['implementation'],
      isNotNull,
    );
    expect(
      (result.machineDocument['routes'] as List).single['exposure'],
      'package',
    );
  });

  test('rejects missing, duplicate, and unknown public implementations', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        source: 'contract.dart',
        components: [component('orders')],
        routes: [
          route('orders.detail', 'orders', publicContract: true),
          route(
            'orders.missing',
            'orders',
            pattern: '/missing/:id',
            publicContract: true,
          ),
        ],
        routeImplementations: [
          implementation('orders.detail', 'orders'),
          implementation('orders.unknown', 'orders'),
        ],
      ),
      document(
        source: 'implementation.dart',
        components: const [],
        routes: const [],
        routeImplementations: [implementation('orders.detail', 'orders')],
      ),
    ]);

    expect(result.errors, contains(contains('more than one implementation')));
    expect(result.errors, contains(contains('has no CCRouteImplementation')));
    expect(result.errors, contains(contains('unknown route contract')));
  });

  test('derives external exposure and requires the owner implementation', () {
    final contractDocument = document(
      source: 'contract.dart',
      components: [component('orders')],
      routes: [
        route(
          'orders.detail',
          'orders',
          publicContract: true,
          contractPackage: 'orders_contracts',
        ),
      ],
      package: 'orders_contracts',
    )..['componentDeclarations'] = <String>[];
    final ownerDocument = document(
      source: 'registrar.dart',
      components: [component('orders')],
      routes: const [],
      package: 'orders_impl',
    );
    final foreignImplementation = document(
      source: 'foreign_page.dart',
      components: const [],
      routes: const [],
      routeImplementations: [
        implementation('orders.detail', 'orders')
          ..['package'] = 'checkout_impl',
      ],
      package: 'checkout_impl',
    );

    final result = CCRouteWorkspaceValidator.validate([
      contractDocument,
      ownerDocument,
      foreignImplementation,
    ]);

    expect(result.errors, contains(contains('instead of owner package')));
    expect(
      (result.machineDocument['routes'] as List).single['exposure'],
      'external',
    );
  });

  test('rejects unsupported metadata schemas', () {
    final result = CCRouteWorkspaceValidator.validate([
      {'schemaVersion': 4, 'source': 'future.json'},
    ]);
    expect(result.errors.single, contains('Unsupported metadata schema'));
  });

  test('rejects invalid persisted identifiers and SemVer values', () {
    final invalidComponent = component('Bad ID')..['version'] = '1.0.0-01';
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [invalidComponent],
        routes: [
          route(
            'Bad.route',
            'Bad ID',
            hostId: 'Host.Main',
            interceptorIds: const ['bad id', 'bad id'],
          ),
        ],
      ),
    ]);

    expect(result.errors, contains(contains('Component ID')));
    expect(result.errors, contains(contains('SemVer 2.0')));
    expect(result.errors, contains(contains('Route ID')));
    expect(result.errors, contains(contains('invalid hostId')));
    expect(result.errors, contains(contains('interceptorIds')));
  });

  test('rejects missing, self-referencing, and cyclic route parents', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [
          route(
            'orders.missing',
            'orders',
            pattern: '/missing/:id',
            parentRouteId: 'orders.unknown',
          ),
          route(
            'orders.self',
            'orders',
            pattern: '/self/:id',
            parentRouteId: 'orders.self',
          ),
          route(
            'orders.a',
            'orders',
            pattern: '/a/:id',
            parentRouteId: 'orders.b',
          ),
          route(
            'orders.b',
            'orders',
            pattern: '/b/:id',
            parentRouteId: 'orders.a',
          ),
        ],
      ),
    ]);

    expect(result.errors, contains(contains('unknown parent')));
    expect(result.errors, contains(contains('cannot be its own parent')));
    expect(result.errors, contains(contains('Route parent cycle')));
  });

  test('rejects parent placement mismatches', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [
          route('orders.root', 'orders', pattern: '/root/:id'),
          route(
            'orders.detail',
            'orders',
            parentRouteId: 'orders.root',
            navigatorOutlet: 'other',
          ),
        ],
      ),
    ]);

    expect(result.errors, contains(contains('same navigatorOutlet')));
  });

  test('requires cross-component parents to be visible dependencies', () {
    final hidden = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders'), component('checkout')],
        routes: [
          route(
            'orders.root',
            'orders',
            pattern: '/root/:id',
            publicContract: true,
          ),
          route(
            'checkout.detail',
            'checkout',
            pattern: '/checkout/:id',
            parentRouteId: 'orders.root',
          ),
        ],
        routeImplementations: [implementation('orders.root', 'orders')],
      ),
    ]);
    expect(
      hidden.errors,
      contains(contains('not a visible public dependency')),
    );

    final visible = CCRouteWorkspaceValidator.validate([
      document(
        components: [
          component('orders'),
          component('checkout', dependencies: ['orders']),
        ],
        routes: [
          route(
            'orders.root',
            'orders',
            pattern: '/root/:id',
            publicContract: true,
          ),
          route(
            'checkout.detail',
            'checkout',
            pattern: '/checkout/:id',
            parentRouteId: 'orders.root',
          ),
        ],
        routeImplementations: [implementation('orders.root', 'orders')],
      ),
    ]);
    expect(visible.errors, isEmpty);
  });

  test('rejects equal-specificity overlapping path patterns', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [
          route('orders.byId', 'orders'),
          route('orders.byOrder', 'orders', pattern: '/detail/:orderId'),
        ],
      ),
    ]);
    expect(result.errors, contains(contains('ambiguous patterns')));
  });

  test('accepts path patterns with different fixed segments', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [
          route('orders.detail', 'orders'),
          route('orders.summary', 'orders', pattern: '/summary/:id'),
        ],
      ),
    ]);
    expect(result.errors, isEmpty);
  });

  test('accepts provably disjoint path constraints', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [
          route('orders.numeric', 'orders', constraints: {'id': r'\d+'}),
          route('orders.alpha', 'orders', constraints: {'id': r'[a-z]+'}),
        ],
      ),
    ]);
    expect(result.errors, isEmpty);
  });

  test('does not compare URI patterns with different authorities', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [
          route(
            'orders.primary',
            'orders',
            patternType: 'CCUriPattern',
            pattern: 'app://orders/detail/:id',
          ),
          route(
            'orders.otherHost',
            'orders',
            patternType: 'CCUriPattern',
            pattern: 'app://checkout/detail/:id',
          ),
        ],
      ),
    ]);
    expect(result.errors, isEmpty);
  });

  test('rejects identical regex patterns', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [
          route(
            'orders.first',
            'orders',
            patternType: 'CCRegexPattern',
            pattern: r'/orders/(?<id>\d+)',
          ),
          route(
            'orders.second',
            'orders',
            patternType: 'CCRegexPattern',
            pattern: r'/orders/(?<id>\d+)',
          ),
        ],
      ),
    ]);
    expect(result.errors, contains(contains('ambiguous patterns')));
  });

  test('leaves complex regex overlap to runtime validation', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [
          route(
            'orders.first',
            'orders',
            patternType: 'CCRegexPattern',
            pattern: r'/orders/(?:a|b)',
          ),
          route(
            'orders.second',
            'orders',
            patternType: 'CCRegexPattern',
            pattern: r'/orders/(?:b|c)',
          ),
        ],
      ),
    ]);
    expect(result.errors, isEmpty);
  });

  test('does not require a public barrel for internal contracts', () {
    final root = Directory.systemTemp.createTempSync('ccrouter-barrel-test-');
    try {
      final package = Directory('${root.path}/demo_order')..createSync();
      Directory('${package.path}/lib/src').createSync(recursive: true);
      File(
        '${package.path}/pubspec.yaml',
      ).writeAsStringSync('name: demo_order\n');
      File(
        '${package.path}/lib/src/detail.dart',
      ).writeAsStringSync("part 'detail.route.g.dart';\n");
      File(
        '${package.path}/lib/demo_order.dart',
      ).writeAsStringSync('library;\n');
      final metadata = document(
        source: 'lib/src/detail.dart',
        components: [component('orders')],
        routes: [route('orders.detail', 'orders')],
      )..['package'] = 'demo_order';
      expect(CCRouteBarrelExportValidator.validate(root, [metadata]), isEmpty);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('requires public contracts to export the generated library', () {
    final root = Directory.systemTemp.createTempSync(
      'ccrouter-separate-barrel-test-',
    );
    try {
      final package = Directory('${root.path}/demo_order')..createSync();
      Directory(
        '${package.path}/lib/src/ccrouter_generated',
      ).createSync(recursive: true);
      File(
        '${package.path}/pubspec.yaml',
      ).writeAsStringSync('name: demo_order\n');
      File(
        '${package.path}/lib/src/detail.dart',
      ).writeAsStringSync("part 'ccrouter_generated/detail.route.g.dart';\n");
      File(
        '${package.path}/lib/src/ccrouter_generated/detail.route.contract.g.dart',
      ).writeAsStringSync('library;\n');
      final metadata = document(
        source: 'lib/src/detail.dart',
        components: [component('orders')],
        routes: [
          route('orders.detail', 'orders', publicContract: true)
            ..['contracts'] = {
              'route': 'DetailRoute',
              'arguments': 'DetailRouteArguments',
              'package': 'demo_order',
              'library':
                  'lib/src/ccrouter_generated/detail.route.contract.g.dart',
            },
        ],
      )..['package'] = 'demo_order';
      final barrel = File('${package.path}/lib/demo_order.dart');
      barrel.writeAsStringSync(
        "export 'src/ccrouter_generated/detail.route.contract.g.dart' show DetailRoute, DetailRouteArguments;\n",
      );
      expect(CCRouteBarrelExportValidator.validate(root, [metadata]), isEmpty);
      barrel.writeAsStringSync(
        "export 'src/detail.dart' show DetailRoute, DetailRouteArguments;\n",
      );
      expect(
        CCRouteBarrelExportValidator.validate(root, [metadata]),
        contains(contains('detail.route.contract.g.dart')),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
