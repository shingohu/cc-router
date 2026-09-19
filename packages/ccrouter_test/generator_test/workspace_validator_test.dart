import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/ccrouter_generator.dart';
import 'package:test/test.dart';

Map<String, Object?> document({
  required List<Map<String, Object?>> components,
  required List<Map<String, Object?>> routes,
  String source = 'routes.dart',
}) => {
  'schemaVersion': 1,
  'source': source,
  'componentDeclarations': components
      .map((component) => component['id'])
      .toList(),
  'components': components,
  'routes': routes,
};

Map<String, Object?> component(
  String id, {
  List<String> dependencies = const [],
}) => {
  'id': id,
  'version': '1.0.0',
  'dependencies': dependencies,
  'optionalDependencies': <String>[],
};

Map<String, Object?> route(
  String id,
  String owner, {
  String visibility = 'exported',
  List<String> visibleTo = const [],
  String pattern = '/detail/:id',
  String patternType = 'CCPathPattern',
  Map<String, String> constraints = const {},
}) => {
  'id': id,
  'componentId': owner,
  'visibility': visibility,
  'visibleTo': visibleTo,
  'deepLink': 'disabled',
  'description': 'Documented route.',
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
      'required': true,
      'description': 'Stable identity.',
    },
  ],
  'resultType': 'void',
};

void main() {
  test('accepts allowlisted consumers with explicit provider dependencies', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [
          route('orders.detail', 'orders', visibleTo: ['checkout']),
        ],
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
    expect(result.markdownDocument, contains('Stable identity.'));
    expect(jsonDecode(result.machineDocumentJson), isA<Map>());
  });

  test('rejects unknown owners, consumers and missing dependency edges', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders'), component('checkout')],
        routes: [
          route('unknown.owner', 'missing'),
          route('unknown.consumer', 'orders', visibleTo: ['missing']),
          route('missing.edge', 'orders', visibleTo: ['checkout']),
        ],
      ),
    ]);
    expect(result.errors, contains(contains('unknown owner component')));
    expect(result.errors, contains(contains('unknown consumer')));
    expect(result.errors, contains(contains('must depend on "orders"')));
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

  test('rejects unsupported metadata schemas', () {
    final result = CCRouteWorkspaceValidator.validate([
      {'schemaVersion': 2, 'source': 'future.json'},
    ]);
    expect(result.errors.single, contains('Unsupported route metadata schema'));
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

  test('requires exported route contracts in a public barrel show list', () {
    final root = Directory.systemTemp.createTempSync('ccrouter-barrel-test-');
    try {
      final package = Directory('${root.path}/demo_order')..createSync();
      Directory('${package.path}/lib/src').createSync(recursive: true);
      File(
        '${package.path}/pubspec.yaml',
      ).writeAsStringSync('name: demo_order\n');
      File(
        '${package.path}/lib/src/detail.dart',
      ).writeAsStringSync("part 'detail.ccroute.g.dart';\n");
      File('${package.path}/lib/demo_order.dart').writeAsStringSync(
        "export 'src/detail.dart' show DetailRoute, DetailRouteArguments;\n",
      );
      final metadata = document(
        source: 'lib/src/detail.dart',
        components: [component('orders')],
        routes: [
          route('orders.detail', 'orders')
            ..['contracts'] = {
              'route': 'DetailRoute',
              'arguments': 'DetailRouteArguments',
            },
        ],
      )..['package'] = 'demo_order';
      expect(CCRouteBarrelExportValidator.validate(root, [metadata]), isEmpty);
      File(
        '${package.path}/lib/demo_order.dart',
      ).writeAsStringSync("export 'src/detail.dart';\n");
      expect(
        CCRouteBarrelExportValidator.validate(root, [metadata]),
        contains(contains('must be re-exported')),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
