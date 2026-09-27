import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/ccrouter_generator.dart';
import 'package:test/test.dart';

Map<String, Object?> document({
  required List<Map<String, Object?>> components,
  required List<Map<String, Object?>> routes,
  List<Map<String, Object?>> routeImplementations = const [],
  List<Map<String, Object?>> contributions = const [],
  List<Map<String, Object?>> serviceContracts = const [],
  List<Map<String, Object?>> serviceImplementations = const [],
  List<Map<String, Object?>> eventContracts = const [],
  List<Map<String, Object?>> eventSubscriptions = const [],
  List<Map<String, Object?>> initTaskContracts = const [],
  List<Map<String, Object?>> initTasks = const [],
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
  'contributions': contributions,
  'serviceContracts': serviceContracts,
  'serviceImplementations': serviceImplementations,
  'eventContracts': eventContracts,
  'eventSubscriptions': eventSubscriptions,
  'initTaskContracts': initTaskContracts,
  'initTasks': initTasks,
};

Map<String, Object?> component(
  String id, {
  List<String> dependencies = const [],
  List<String> optionalDependencies = const [],
  List<Map<String, Object?>> serviceDependencies = const [],
}) => {
  'id': id,
  'version': '1.0.0',
  'dependencies': dependencies,
  'optionalDependencies': optionalDependencies,
  'serviceDependencies': serviceDependencies,
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
  test('accepts typed InitTask dependencies across required components', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        package: 'foundation',
        components: [component('foundation')],
        routes: const [],
        initTaskContracts: const [
          {'id': 'foundation.logging', 'componentId': 'foundation'},
        ],
        initTasks: const [
          {
            'id': 'foundation.logging',
            'componentId': 'foundation',
            'contractId': 'foundation.logging',
            'dependsOn': <String>[],
            'gateId': 'appStarted',
            'failurePolicy': 'critical',
          },
        ],
      ),
      document(
        package: 'analytics',
        components: [
          component('analytics', dependencies: ['foundation']),
        ],
        routes: const [],
        initTaskContracts: const [
          {'id': 'analytics.sdk', 'componentId': 'analytics'},
        ],
        initTasks: const [
          {
            'id': 'analytics.sdk',
            'componentId': 'analytics',
            'contractId': 'analytics.sdk',
            'dependsOn': ['foundation.logging'],
            'gateId': 'privacyGranted',
            'failurePolicy': 'optional',
            'timeoutMicroseconds': 3000000,
          },
          {
            'id': 'analytics.internal_cache',
            'componentId': 'analytics',
            'dependsOn': <String>[],
            'gateId': 'appStarted',
            'failurePolicy': 'critical',
          },
        ],
      ),
    ]);

    expect(result.errors, isEmpty);
  });

  test('rejects missing, optional-owner, and cyclic InitTask dependencies', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        package: 'foundation',
        components: [component('foundation')],
        routes: const [],
        initTaskContracts: const [
          {'id': 'foundation.logging', 'componentId': 'foundation'},
        ],
        initTasks: const [
          {
            'id': 'foundation.logging',
            'componentId': 'foundation',
            'contractId': 'foundation.logging',
            'dependsOn': ['analytics.sdk'],
            'gateId': 'appStarted',
            'failurePolicy': 'critical',
          },
        ],
      ),
      document(
        package: 'analytics',
        components: [
          component('analytics', optionalDependencies: ['foundation']),
        ],
        routes: const [],
        initTaskContracts: const [
          {'id': 'analytics.sdk', 'componentId': 'analytics'},
        ],
        initTasks: const [
          {
            'id': 'analytics.sdk',
            'componentId': 'analytics',
            'contractId': 'analytics.sdk',
            'dependsOn': ['foundation.logging', 'missing.task'],
            'gateId': 'privacyGranted',
            'failurePolicy': 'optional',
          },
        ],
      ),
    ]);

    expect(result.errors, contains(contains('requires missing task')));
    expect(result.errors, contains(contains('does not require it')));
    expect(result.errors, contains(contains('dependency cycle')));
  });

  test('rejects malformed persisted InitTask ownership and policy', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: const [],
        initTaskContracts: const [
          {'id': 'orders.foundation', 'componentId': 'orders'},
          {'id': 'orders.unimplemented', 'componentId': 'orders'},
        ],
        initTasks: const [
          {
            'id': 'orders.foundation',
            'componentId': 'unknown',
            'contractId': 'orders.foundation',
            'dependsOn': <String>[],
            'gateId': 'Invalid gate',
            'failurePolicy': 'ignored',
            'timeoutMicroseconds': 0,
          },
        ],
      ),
    ]);

    expect(result.errors, contains(contains('unknown owner component')));
    expect(result.errors, contains(contains('instead of "orders"')));
    expect(result.errors, contains(contains('has no Handler')));
    expect(result.errors, contains(contains('invalid Gate ID')));
    expect(result.errors, contains(contains('unsupported failure policy')));
    expect(result.errors, contains(contains('timeout must be positive')));
  });

  test('accepts Event subscribers through required or optional owners', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        package: 'orders',
        components: [component('orders')],
        routes: const [],
        eventContracts: const [
          {
            'id': 'orders.created',
            'componentId': 'orders',
            'type': 'OrderCreatedEvent',
          },
          {
            'id': 'orders.unobserved',
            'componentId': 'orders',
            'type': 'OrderUnobservedEvent',
          },
        ],
      ),
      document(
        package: 'analytics',
        components: [
          component('analytics', optionalDependencies: ['orders']),
        ],
        routes: const [],
        eventSubscriptions: const [
          {
            'eventId': 'orders.created',
            'eventComponentId': 'orders',
            'componentId': 'analytics',
            'subscriberId': 'analytics.orders-created',
            'eventType': 'OrderCreatedEvent',
          },
        ],
      ),
    ]);

    expect(result.errors, isEmpty);
  });

  test('rejects invalid Event relationships and duplicate Subscriber IDs', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        package: 'orders',
        components: [component('orders')],
        routes: const [],
        eventContracts: const [
          {
            'id': 'orders.created',
            'componentId': 'orders',
            'type': 'OrderCreatedEvent',
          },
          {
            'id': 'orders.created',
            'componentId': 'orders',
            'type': 'OrderCreatedEvent',
          },
          {
            'id': 'missing.changed',
            'componentId': 'missing',
            'type': 'MissingChangedEvent',
          },
        ],
      ),
      document(
        package: 'analytics',
        components: [component('analytics')],
        routes: const [],
        eventSubscriptions: const [
          {
            'eventId': 'orders.created',
            'eventComponentId': 'other',
            'componentId': 'analytics',
            'subscriberId': 'analytics.shared',
            'eventType': 'WrongEvent',
          },
          {
            'eventId': 'orders.unknown',
            'eventComponentId': 'orders',
            'componentId': 'analytics',
            'subscriberId': 'analytics.shared',
            'eventType': 'UnknownEvent',
          },
        ],
      ),
    ]);

    expect(
      result.errors,
      contains('Event contract "orders.created" is declared more than once.'),
    );
    expect(
      result.errors,
      contains(
        'Event contract "missing.changed" references unknown owner component "missing".',
      ),
    );
    expect(
      result.errors,
      contains(
        'Event Subscriber ID "analytics.shared" is declared more than once.',
      ),
    );
    expect(
      result.errors,
      contains(contains('records Event "orders.created" owner')),
    );
    expect(result.errors, contains(contains('records type "WrongEvent"')));
    expect(
      result.errors,
      contains(contains('does not declare owner component "orders"')),
    );
  });

  test('accepts an exact Service dependency owned by a required component', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        package: 'orders',
        components: [component('orders')],
        routes: const [],
        serviceContracts: [
          {'id': 'orders.summary', 'componentId': 'orders'},
        ],
      ),
      document(
        package: 'payment',
        components: [
          component(
            'payment',
            dependencies: ['orders'],
            serviceDependencies: const [
              {
                'id': 'orders.summary',
                'componentId': 'orders',
                'contract': 'OrderSummaryService',
                'key': null,
                'member': 'orderSummary',
              },
            ],
          ),
        ],
        routes: const [],
      ),
    ]);

    expect(result.errors, isEmpty);
  });

  test('rejects missing owner and duplicate Service Client members', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: const [],
        serviceContracts: [
          {'id': 'orders.summary', 'componentId': 'orders'},
          {'id': 'orders.quote', 'componentId': 'orders'},
        ],
      ),
      document(
        package: 'payment',
        components: [
          component(
            'payment',
            serviceDependencies: const [
              {
                'id': 'orders.summary',
                'componentId': 'orders',
                'member': 'orders',
              },
              {
                'id': 'orders.quote',
                'componentId': 'orders',
                'member': 'orders',
              },
            ],
          ),
        ],
        routes: const [],
      ),
    ]);

    expect(result.errors, contains(contains('does not require owner')));
    expect(
      result.errors,
      contains(contains('duplicate Service Client member')),
    );
  });

  test('rejects a generated consumer for a Route-scoped Service', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        package: 'orders',
        components: [component('orders')],
        routes: const [],
        serviceContracts: [
          {'id': 'orders.draft', 'componentId': 'orders'},
        ],
        serviceImplementations: [
          {
            'id': 'orders.draft',
            'contractId': 'orders.draft',
            'componentId': 'orders',
            'key': null,
            'scope': 'route',
            'isDefault': false,
          },
        ],
      ),
      document(
        package: 'payment',
        components: [
          component(
            'payment',
            dependencies: ['orders'],
            serviceDependencies: const [
              {
                'id': 'orders.draft',
                'componentId': 'orders',
                'member': 'orderDraft',
              },
            ],
          ),
        ],
        routes: const [],
      ),
    ]);

    expect(result.errors, contains(contains('Route-scoped contract')));
  });

  test('accepts components and emits derived route exposure', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [route('orders.detail', 'orders')],
      ),
      document(
        source: 'checkout.dart',
        package: 'checkout',
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
          package: 'checkout',
          components: [
            component(
              'checkout',
              dependencies: ['orders'],
              optionalDependencies: ['analytics'],
            ),
          ],
          routes: const [],
        ),
        document(
          package: 'orders',
          components: [
            component('orders', dependencies: ['account']),
          ],
          routes: const [],
        ),
        document(
          package: 'unrelated',
          components: [component('unrelated')],
          routes: const [],
        ),
        document(
          package: 'analytics',
          components: [component('analytics')],
          routes: const [],
        ),
        document(
          package: 'account',
          components: [component('account')],
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

  test('rejects duplicate and unknown component contributions', () {
    Map<String, Object?> contribution(String id, String owner) => {
      'id': id,
      'componentId': owner,
      'symbol': 'registerProbe',
    };
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: const [],
        contributions: [contribution('orders.services', 'orders')],
      ),
      document(
        package: 'orders_extensions',
        components: const [],
        routes: const [],
        contributions: [
          contribution('orders.services', 'orders'),
          contribution('missing.services', 'missing'),
        ],
      ),
    ]);

    expect(
      result.errors,
      contains(
        'Component "orders" declares contribution "orders.services" more than once.',
      ),
    );
    expect(
      result.errors,
      contains(
        'Component contribution "missing.services" references unknown owner component "missing".',
      ),
    );
  });

  test('accepts a generated Service contract and implementation', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: const [],
        serviceContracts: [
          {'id': 'orders.summary', 'componentId': 'orders'},
        ],
        serviceImplementations: [
          {
            'id': 'orders.summary',
            'componentId': 'orders',
            'contractId': 'orders.summary',
            'key': 'primary',
            'isDefault': true,
          },
        ],
      ),
    ]);

    expect(result.errors, isEmpty);
  });

  test('rejects invalid Service ownership and Provider conflicts', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders'), component('payments')],
        routes: const [],
        serviceContracts: [
          {'id': 'orders.summary', 'componentId': 'orders'},
          {'id': 'orders.summary', 'componentId': 'orders'},
          {'id': 'missing.service', 'componentId': 'missing'},
        ],
        serviceImplementations: [
          {
            'id': 'orders.summary',
            'componentId': 'payments',
            'contractId': 'orders.summary',
            'key': 'primary',
            'isDefault': true,
          },
          {
            'id': 'orders.summary',
            'componentId': 'payments',
            'contractId': 'orders.summary',
            'key': 'primary',
            'isDefault': true,
          },
          {
            'id': 'unknown.service',
            'componentId': 'orders',
            'contractId': 'unknown.service',
            'key': null,
            'isDefault': false,
          },
        ],
      ),
    ]);

    expect(
      result.errors,
      contains('Service contract "orders.summary" is declared more than once.'),
    );
    expect(
      result.errors,
      contains(
        'Service contract "missing.service" references unknown owner component "missing".',
      ),
    );
    expect(
      result.errors,
      contains(
        'Component "payments" declares Service "orders.summary" with Key "primary" more than once.',
      ),
    );
    expect(
      result.errors,
      contains(
        'Component "payments" declares more than one default implementation of Service "orders.summary": "primary" and "primary".',
      ),
    );
    expect(
      result.errors,
      contains(
        'Service implementation "orders.summary" belongs to component "payments" but contract "orders.summary" belongs to "orders".',
      ),
    );
    expect(
      result.errors,
      contains(
        'Service implementation "unknown.service" references unknown contract "unknown.service".',
      ),
    );
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
        package: 'orders',
        components: [component('orders')],
        routes: [
          route(
            'orders.root',
            'orders',
            pattern: '/root/:id',
            publicContract: true,
          ),
        ],
        routeImplementations: [implementation('orders.root', 'orders')],
      ),
      document(
        package: 'checkout',
        components: [
          component('checkout', dependencies: ['orders']),
        ],
        routes: [
          route(
            'checkout.detail',
            'checkout',
            pattern: '/checkout/:id',
            parentRouteId: 'orders.root',
          ),
        ],
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

  test('indexed candidates retain swapped fixed and dynamic conflicts', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [
          route('orders.bySection', 'orders', pattern: '/detail/:section/item'),
          route('orders.byItem', 'orders', pattern: '/detail/item/:id'),
        ],
      ),
    ]);
    expect(result.errors, contains(contains('ambiguous patterns')));
  });

  test('indexed candidates retain wildcard conflicts', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [
          route('orders.firstFiles', 'orders', pattern: '/files/*rest'),
          route('orders.secondFiles', 'orders', pattern: '/files/*path'),
        ],
      ),
    ]);
    expect(result.errors, contains(contains('ambiguous patterns')));
  });

  test('validates a large fixed-path catalog without conflict diagnostics', () {
    final result = CCRouteWorkspaceValidator.validate([
      document(
        components: [component('orders')],
        routes: [
          for (var index = 0; index < 2000; index++)
            route(
              'orders.route.$index',
              'orders',
              pattern: '/catalog/$index/:id',
            ),
        ],
      ),
    ]);
    expect(result.errors, isEmpty);
    expect(result.machineDocument['routes'], hasLength(2000));
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
        '${package.path}/lib/src/ccrouter_generated/contract',
      ).createSync(recursive: true);
      File(
        '${package.path}/pubspec.yaml',
      ).writeAsStringSync('name: demo_order\n');
      File('${package.path}/lib/src/detail.dart').writeAsStringSync(
        "part 'ccrouter_generated/route/detail.route.g.dart';\n",
      );
      File(
        '${package.path}/lib/src/ccrouter_generated/contract/detail.route.contract.g.dart',
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
                  'lib/src/ccrouter_generated/contract/detail.route.contract.g.dart',
            },
        ],
      )..['package'] = 'demo_order';
      final barrel = File('${package.path}/lib/demo_order.dart');
      barrel.writeAsStringSync(
        "export 'src/ccrouter_generated/contract/detail.route.contract.g.dart' show DetailRoute, DetailRouteArguments;\n",
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

  test('requires public Service contracts to export the authored interface', () {
    final root = Directory.systemTemp.createTempSync(
      'ccrouter-service-barrel-test-',
    );
    try {
      final package = Directory('${root.path}/demo_order_contracts')
        ..createSync();
      Directory(
        '${package.path}/lib/src/ccrouter_generated/contract',
      ).createSync(recursive: true);
      File(
        '${package.path}/pubspec.yaml',
      ).writeAsStringSync('name: demo_order_contracts\n');
      File(
        '${package.path}/lib/src/order_summary_service.dart',
      ).writeAsStringSync('abstract interface class OrderSummaryService {}\n');
      final metadata = document(
        source: 'lib/src/order_summary_service.dart',
        components: const [],
        routes: const [],
        serviceContracts: [
          {
            'id': 'orders.summary',
            'componentId': 'orders',
            'declaration': {
              'symbol': 'OrderSummaryService',
              'packageUri':
                  'package:demo_order_contracts/src/order_summary_service.dart',
            },
          },
        ],
      )..['package'] = 'demo_order_contracts';
      final barrel = File('${package.path}/lib/demo_order_contracts.dart');
      barrel.writeAsStringSync(
        "export 'src/order_summary_service.dart' "
        'show OrderSummaryService;\n',
      );
      expect(CCRouteBarrelExportValidator.validate(root, [metadata]), isEmpty);

      barrel.writeAsStringSync(
        "export 'src/order_summary_service.dart' "
        'show AnotherService;\n',
      );
      expect(
        CCRouteBarrelExportValidator.validate(root, [metadata]),
        contains(contains('OrderSummaryService')),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'requires contracts Package Command declarations in a public barrel',
    () {
      final root = Directory.systemTemp.createTempSync(
        'ccrouter-command-barrel-test-',
      );
      try {
        final package = Directory('${root.path}/demo_order_contracts')
          ..createSync();
        Directory('${package.path}/lib/src').createSync(recursive: true);
        File(
          '${package.path}/pubspec.yaml',
        ).writeAsStringSync('name: demo_order_contracts\n');
        final source = File('${package.path}/lib/src/submit_order.dart')
          ..writeAsStringSync('final class SubmitOrderCommand {}\n');
        final metadata =
            document(
                source: 'lib/src/submit_order.dart',
                components: const [],
                routes: const [],
              )
              ..['package'] = 'demo_order_contracts'
              ..['commandContracts'] = [
                {
                  'id': 'orders.submit',
                  'componentId': 'orders',
                  'declaration': {
                    'symbol': 'SubmitOrderCommand',
                    'packageUri':
                        'package:demo_order_contracts/src/submit_order.dart',
                  },
                },
              ];
        final barrel = File('${package.path}/lib/demo_order_contracts.dart')
          ..writeAsStringSync(
            "export 'src/submit_order.dart' show SubmitOrderCommand;\n",
          );
        expect(
          CCRouteBarrelExportValidator.validate(root, [metadata]),
          isEmpty,
        );

        barrel.writeAsStringSync(
          "export 'src/submit_order.dart' show AnotherCommand;\n",
        );
        expect(
          CCRouteBarrelExportValidator.validate(root, [metadata]),
          contains(contains('SubmitOrderCommand')),
        );
        expect(source.existsSync(), isTrue);
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('requires contracts Package Event declarations in a public barrel', () {
    final root = Directory.systemTemp.createTempSync(
      'ccrouter-event-barrel-test-',
    );
    try {
      final package = Directory('${root.path}/demo_order_contracts')
        ..createSync();
      Directory('${package.path}/lib/src').createSync(recursive: true);
      File(
        '${package.path}/pubspec.yaml',
      ).writeAsStringSync('name: demo_order_contracts\n');
      File(
        '${package.path}/lib/src/order_submitted.dart',
      ).writeAsStringSync('final class OrderSubmittedEvent {}\n');
      final metadata =
          document(
              source: 'lib/src/order_submitted.dart',
              components: const [],
              routes: const [],
            )
            ..['package'] = 'demo_order_contracts'
            ..['eventContracts'] = [
              {
                'id': 'orders.submitted',
                'componentId': 'orders',
                'declaration': {
                  'symbol': 'OrderSubmittedEvent',
                  'packageUri':
                      'package:demo_order_contracts/src/order_submitted.dart',
                },
              },
            ];
      final barrel = File('${package.path}/lib/demo_order_contracts.dart')
        ..writeAsStringSync(
          "export 'src/order_submitted.dart' show OrderSubmittedEvent;\n",
        );
      expect(CCRouteBarrelExportValidator.validate(root, [metadata]), isEmpty);

      barrel.writeAsStringSync(
        "export 'src/order_submitted.dart' show AnotherEvent;\n",
      );
      expect(
        CCRouteBarrelExportValidator.validate(root, [metadata]),
        contains(contains('OrderSubmittedEvent')),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'does not require component-internal messaging contracts in a barrel',
    () {
      final root = Directory.systemTemp.createTempSync(
        'ccrouter-internal-message-barrel-test-',
      );
      try {
        final package = Directory('${root.path}/demo_order')..createSync();
        Directory('${package.path}/lib/src').createSync(recursive: true);
        File(
          '${package.path}/pubspec.yaml',
        ).writeAsStringSync('name: demo_order\n');
        File('${package.path}/lib/src/messages.dart').writeAsStringSync(
          'final class InternalCommand {}\nfinal class InternalEvent {}\n',
        );
        final metadata =
            document(
                source: 'lib/src/messages.dart',
                components: [component('orders')],
                routes: const [],
              )
              ..['package'] = 'demo_order'
              ..['commandContracts'] = [
                {
                  'id': 'orders.internal_command',
                  'componentId': 'orders',
                  'declaration': {'symbol': 'InternalCommand'},
                },
              ]
              ..['eventContracts'] = [
                {
                  'id': 'orders.internal_event',
                  'componentId': 'orders',
                  'declaration': {'symbol': 'InternalEvent'},
                },
              ];
        expect(
          CCRouteBarrelExportValidator.validate(root, [metadata]),
          isEmpty,
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('requires contracts Package InitTask constants in a public barrel', () {
    final root = Directory.systemTemp.createTempSync(
      'ccrouter-init-task-barrel-test-',
    );
    try {
      final package = Directory('${root.path}/foundation_contracts')
        ..createSync();
      Directory('${package.path}/lib/src').createSync(recursive: true);
      File(
        '${package.path}/pubspec.yaml',
      ).writeAsStringSync('name: foundation_contracts\n');
      File(
        '${package.path}/lib/src/startup.dart',
      ).writeAsStringSync('const foundationTask = Object();\n');
      final metadata = document(
        package: 'foundation_contracts',
        source: 'lib/src/startup.dart',
        components: const [],
        routes: const [],
        initTaskContracts: const [
          {
            'id': 'foundation.logging',
            'componentId': 'foundation',
            'declaration': {'symbol': 'foundationTask'},
          },
        ],
      );
      final barrel = File('${package.path}/lib/foundation_contracts.dart')
        ..writeAsStringSync("export 'src/startup.dart' show foundationTask;\n");
      expect(CCRouteBarrelExportValidator.validate(root, [metadata]), isEmpty);

      barrel.writeAsStringSync("export 'src/startup.dart' show anotherTask;\n");
      expect(
        CCRouteBarrelExportValidator.validate(root, [metadata]),
        contains(contains('foundationTask')),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
