import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:test/test.dart';

final class Registrar implements CCComponentRegistrar {
  Registrar(this.body);
  final void Function(CCRegistry) body;
  @override
  void register(CCRegistry registry) => body(registry);
}

final class StringCodec implements CCRouteCodec<String> {
  const StringCodec();

  @override
  String decode(CCEncodedRouteArguments input) => input.path['value']!;

  @override
  CCEncodedRouteArguments encode(String arguments) =>
      CCEncodedRouteArguments(path: {'value': arguments});
}

final class StringIntent<R> implements CCRouteIntent<R> {
  const StringIntent(this.routeId, this.arguments);

  @override
  final String routeId;

  @override
  final String arguments;
}

final class ServiceInvocationCommand implements CCCommand<int> {
  const ServiceInvocationCommand(this.value);

  final int value;
}

final class ComponentService implements CCDisposable {
  ComponentService(this.id, {this.onDispose});

  final String id;
  final Future<void> Function()? onDispose;
  bool disposed = false;

  @override
  Future<void> dispose() async {
    disposed = true;
    await onDispose?.call();
  }
}

final class DenyPopGuard implements CCPopGuard {
  const DenyPopGuard();

  @override
  CCPopGuardDecision evaluate(CCPopGuardContext context) => const CCPopDeny();
}

CCComponentManifest component(
  String id, {
  List<String> dependencies = const [],
  List<String> optional = const [],
  void Function(CCRegistry)? register,
}) => CCComponentManifest(
  id: id,
  version: '0.1.0',
  dependencies: dependencies,
  optionalDependencies: optional,
  registrar: Registrar(register ?? (_) {}),
);

void main() {
  test('descriptor-backed manifests share build-time component metadata', () {
    const descriptor = CCComponentDescriptor(
      id: 'checkout',
      version: '2.1.0',
      dependencies: ['orders'],
      optionalDependencies: ['campaign'],
    );
    final registrar = Registrar((_) {});
    final manifest = CCComponentManifest.fromDescriptor(
      descriptor: descriptor,
      registrar: registrar,
    );
    expect(manifest.id, descriptor.id);
    expect(manifest.version, descriptor.version);
    expect(manifest.dependencies, same(descriptor.dependencies));
    expect(
      manifest.optionalDependencies,
      same(descriptor.optionalDependencies),
    );
    expect(manifest.registrar, same(registrar));
  });

  test('route definitions retain page, sheet, and dialog presentation', () {
    final defaultRoute = CCRouteDefinition<String, void>(
      routeId: 'orders.default',
      patterns: [CCPathPattern('/orders/default', primary: true)],
      codec: const StringCodec(),
    );
    final defaultPresentation = defaultRoute.presentation;
    expect(defaultPresentation, isA<CCPagePresentation>());
    expect(
      (defaultPresentation as CCPagePresentation).routeType,
      CCPageRouteType.platformDefault,
    );
    expect(
      defaultPresentation.transition,
      CCPageTransitionType.platformDefault,
    );
    expect(defaultPresentation.opaque, isTrue);
    expect(defaultPresentation.fullscreenDialog, isFalse);

    const transparentCupertinoPage = CCPagePresentation(
      routeType: CCPageRouteType.cupertino,
      transition: CCPageTransitionType.slideFromBottom,
      opaque: false,
      fullscreenDialog: true,
    );
    expect(transparentCupertinoPage.routeType, CCPageRouteType.cupertino);
    expect(
      transparentCupertinoPage.transition,
      CCPageTransitionType.slideFromBottom,
    );
    expect(transparentCupertinoPage.opaque, isFalse);
    expect(transparentCupertinoPage.fullscreenDialog, isTrue);

    const sheetPresentation = CCModalBottomSheetPresentation(
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
    );
    final sheetRoute = CCRouteDefinition<String, void>(
      routeId: 'orders.filter',
      patterns: [CCPathPattern('/orders/filter', primary: true)],
      codec: const StringCodec(),
      presentation: sheetPresentation,
    );
    expect(sheetRoute.presentation, same(sheetPresentation));

    const dialogPresentation = CCDialogPresentation(
      routeType: CCDialogRouteType.material,
      barrierDismissible: false,
      useSafeArea: false,
    );
    final dialogRoute = CCRouteDefinition<String, bool>(
      routeId: 'orders.confirm',
      patterns: [CCPathPattern('/orders/confirm', primary: true)],
      codec: const StringCodec(),
      presentation: dialogPresentation,
    );
    expect(dialogRoute.presentation, same(dialogPresentation));
    expect(dialogPresentation.routeType, CCDialogRouteType.material);
    expect(dialogPresentation.barrierDismissible, isFalse);
    expect(dialogPresentation.useSafeArea, isFalse);
    expect(const CCDialogPresentation().barrierDismissible, isNull);

    const placement = CCRoutePlacement(
      parentRouteId: 'workspace',
      shellId: 'workspace-shell',
      navigatorOutlet: 'detail',
    );
    final placedRoute = CCRouteDefinition<String, void>(
      routeId: 'orders.detail',
      patterns: [CCPathPattern('/orders/detail', primary: true)],
      codec: const StringCodec(),
      placement: placement,
    );
    expect(placedRoute.placement, same(placement));
    expect(placement.navigatorOutlet, 'detail');
  });

  test('registrars receive a component-bound registry', () {
    CCRegistry? received;
    final runtime = CCRouterRuntime.forTesting(
      components: [
        component('orders', register: (registry) => received = registry),
      ],
    );

    expect(received, isNotNull);
    expect(received, isNot(same(runtime)));
    expect(received, isNot(isA<CCRouterRuntime>()));
  });

  test(
    'Shell contracts validate statically assembled route placement',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          component(
            'app-shell',
            register: (registry) => registry.registerShell(
              CCShellDefinition(
                shellId: 'tabs',
                type: CCShellType.statefulBranches,
                outlets: const ['home', 'settings'],
                initialOutlet: 'home',
              ),
            ),
          ),
          component(
            'settings',
            dependencies: ['app-shell'],
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'settings.detail',
                patterns: [CCPathPattern('/settings/:value', primary: true)],
                codec: const StringCodec(),
                placement: const CCRoutePlacement(
                  shellId: 'tabs',
                  navigatorOutlet: 'settings',
                ),
              ),
            ),
          ),
        ],
      );
      runtime.initialize();

      expect(runtime.registeredShellIds, ['tabs']);
      expect(adapter.shells, hasLength(1));
      expect(adapter.shells.single.type, CCShellType.statefulBranches);
      expect(adapter.shells.single.outlets, ['home', 'settings']);
      expect(runtime.resolveRoute('/settings/42').routeId, 'settings.detail');

      await runtime.dispose();
    },
  );

  test(
    'Shell registration rejects invalid definitions and placements',
    () async {
      expect(
        () => CCRouterRuntime.forTesting(
          components: [
            component(
              'shell',
              register: (registry) => registry.registerShell(
                CCShellDefinition(
                  shellId: 'tabs',
                  type: CCShellType.singleNavigator,
                  outlets: const ['home', 'settings'],
                  initialOutlet: 'home',
                ),
              ),
            ),
          ],
        ),
        throwsA(isA<CCShellRegistrationError>()),
      );
      final runtime = CCRouterRuntime.forTesting(
        components: [
          component(
            'shell',
            register: (registry) => registry.registerShell(
              CCShellDefinition(
                shellId: 'tabs',
                type: CCShellType.statefulBranches,
                outlets: const ['home', 'settings'],
                initialOutlet: 'home',
              ),
            ),
          ),
          component(
            'orders',
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'orders.detail',
                patterns: [CCPathPattern('/orders/:value', primary: true)],
                codec: const StringCodec(),
                placement: const CCRoutePlacement(
                  shellId: 'tabs',
                  navigatorOutlet: 'unknown',
                ),
              ),
            ),
          ),
        ],
      );
      expect(
        () => runtime.initialize(),
        throwsA(isA<CCRouteRegistrationError>()),
      );
      await runtime.dispose();

      final missingShell = CCRouterRuntime.forTesting(
        components: [
          component(
            'orders',
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'orders.missing-shell',
                patterns: [CCPathPattern('/missing/:value', primary: true)],
                codec: const StringCodec(),
                placement: const CCRoutePlacement(
                  shellId: 'missing',
                  navigatorOutlet: 'content',
                ),
              ),
            ),
          ),
        ],
      );
      expect(
        () => missingShell.initialize(),
        throwsA(isA<CCRouteRegistrationError>()),
      );
      await missingShell.dispose();
    },
  );

  test('registrars assemble in deterministic dependency order', () async {
    final order = <String>[];
    final runtime = CCRouterRuntime.forTesting(
      components: [
        component(
          'order',
          dependencies: ['payment'],
          register: (_) => order.add('order'),
        ),
        component(
          'payment',
          register: (runtime) {
            order.add('payment');
            runtime.registerService(
              CCServiceProvider<String>(factory: (_) => 'payment'),
            );
          },
        ),
      ],
    );
    runtime.initialize();
    expect(order, ['payment', 'order']);
    expect(runtime.components.map((item) => item.id), order);
    expect(runtime.service<String>(), 'payment');
    await runtime.dispose();
  });

  test(
    'component assembly matches workspace required and optional ordering',
    () async {
      final runtime = CCRouterRuntime.forTesting(
        components: [
          component(
            'checkout',
            dependencies: ['orders'],
            optional: ['analytics'],
          ),
          component('orders', dependencies: ['account']),
          component('unrelated'),
          component('analytics'),
          component('account'),
        ],
      );

      expect(runtime.components.map((component) => component.id), [
        'account',
        'analytics',
        'orders',
        'checkout',
        'unrelated',
      ]);
      await runtime.dispose();
    },
  );

  test(
    'component registrars own route definitions and match constrained paths',
    () async {
      final runtime = CCRouterRuntime.forTesting(
        components: [
          component(
            'orders',
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'orders.detail',
                patterns: [
                  CCPathPattern(
                    '/orders/:value',
                    primary: true,
                    constraints: {'value': r'\d+'},
                  ),
                  CCPathPattern('/orders/latest'),
                ],
                codec: const StringCodec(),
              ),
            ),
          ),
        ],
      );
      runtime.initialize();

      expect(runtime.registeredRouteIds, ['orders.detail']);
      expect(runtime.resolveRoute('/orders/latest').pathParameters, isEmpty);
      expect(
        runtime.decodeRouteArguments(runtime.resolveRoute('/orders/42')),
        '42',
      );
      expect(
        () => runtime.resolveRoute('/orders/abc'),
        throwsA(isA<CCRouteNotFoundError>()),
      );

      await runtime.dispose();
    },
  );

  test('one route resolves path, full URL, custom scheme, and regex', () async {
    final runtime = CCRouterRuntime.forTesting(
      components: [
        component(
          'orders',
          register: (registry) => registry.registerRoute<String, void>(
            CCRouteDefinition<String, void>(
              routeId: 'orders.detail',
              patterns: [
                CCPathPattern('/orders/:value', primary: true),
                CCUriPattern('https://therouter.com/orders/:value'),
                CCUriPattern('therouter://orders/detail/:value'),
                const CCRegexPattern(
                  r'https://legacy\.example\.com/order/(?<value>\d+)',
                ),
                const CCRegexPattern(
                  r'https://legacy\.example\.com/encoded/(?<value>[^/?#]+)',
                ),
              ],
              codec: const StringCodec(),
              deepLink: CCDeepLinkPolicy.enabled,
            ),
          ),
        ),
      ],
    );
    runtime.initialize();

    final path = runtime.resolveRoute('/orders/42');
    expect(path.routeId, 'orders.detail');
    expect(runtime.decodeRouteArguments(path), '42');
    expect(
      runtime.decodeRouteArguments(runtime.resolveRoute('/orders/a%2Fb')),
      'a/b',
    );
    expect(
      runtime.decodeRouteArguments(
        runtime.resolveRoute('/orders/%E5%BC%A0%E4%B8%89'),
      ),
      '张三',
    );

    final web = runtime.resolveRoute(
      'HTTPS://THEROUTER.COM/orders/43?tab=items&tab=history#summary',
      external: true,
    );
    expect(web.routeId, 'orders.detail');
    expect(web.pathParameters, {'value': '43'});
    expect(web.queryParameters, {
      'tab': ['items', 'history'],
    });
    expect(
      runtime.decodeRouteArguments(
        runtime.resolveRoute(
          'https://therouter.com/orders/%252F',
          external: true,
        ),
      ),
      '%2F',
    );

    final custom = runtime.resolveRoute(
      'therouter://orders/detail/44',
      external: true,
    );
    expect(custom.routeId, 'orders.detail');
    expect(runtime.decodeRouteArguments(custom), '44');
    expect(
      runtime.decodeRouteArguments(
        runtime.resolveRoute('therouter://orders/detail/a+b', external: true),
      ),
      'a+b',
    );

    final legacy = runtime.resolveRoute(
      'https://legacy.example.com/order/45?source=old#details',
      external: true,
    );
    expect(legacy.routeId, 'orders.detail');
    expect(runtime.decodeRouteArguments(legacy), '45');
    expect(legacy.queryParameters, {
      'source': ['old'],
    });
    final encodedCaptures = <String, String>{
      'https://legacy.example.com/encoded/%E5%BC%A0%E4%B8%89': '张三',
      'https://legacy.example.com/encoded/a%2Fb': 'a/b',
      'https://legacy.example.com/encoded/%25': '%',
      'https://legacy.example.com/encoded/%252F': '%2F',
      'https://legacy.example.com/encoded/a+b': 'a+b',
    };
    for (final entry in encodedCaptures.entries) {
      final location = runtime.resolveRoute(entry.key, external: true);
      expect(
        runtime.decodeRouteArguments(location),
        entry.value,
        reason: entry.key,
      );
    }
    final encodedQuery = runtime.resolveRoute(
      'https://legacy.example.com/encoded/value?space=a+b&plus=a%2Bb',
      external: true,
    );
    expect(encodedQuery.queryParameters, {
      'space': ['a b'],
      'plus': ['a+b'],
    });
    expect(
      () => runtime.resolveRoute('https://legacy.example.com/order/45/extra'),
      throwsA(isA<CCRouteNotFoundError>()),
    );
    await runtime.dispose();
  });

  test(
    'regex rejects a named capture that splits an encoded code point',
    () async {
      final runtime = CCRouterRuntime.forTesting(
        components: [
          component(
            'legacy',
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'legacy.partial-encoding',
                patterns: [
                  CCPathPattern('/fallback/:value', primary: true),
                  const CCRegexPattern(r'/legacy/(?<value>%E5)%BC%A0'),
                ],
                codec: const StringCodec(),
              ),
            ),
          ),
        ],
      );
      runtime.initialize();

      expect(
        () => runtime.resolveRoute('/legacy/%E5%BC%A0'),
        throwsA(isA<CCRouteNotFoundError>()),
      );
      await runtime.dispose();
    },
  );

  test(
    'structured URI outranks a matching authority-independent path',
    () async {
      final runtime = CCRouterRuntime.forTesting(
        components: [
          component(
            'generic',
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'generic.detail',
                patterns: [CCPathPattern('/orders/:value', primary: true)],
                codec: const StringCodec(),
              ),
            ),
          ),
          component(
            'web',
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'web.detail',
                patterns: [
                  CCUriPattern(
                    'https://therouter.com/orders/:value',
                    primary: true,
                  ),
                ],
                codec: const StringCodec(),
              ),
            ),
          ),
        ],
      );
      runtime.initialize();

      expect(runtime.resolveRoute('/orders/42').routeId, 'generic.detail');
      expect(
        runtime.resolveRoute('https://therouter.com/orders/42').routeId,
        'web.detail',
      );
      await runtime.dispose();
    },
  );

  test('external resolution enforces each route deep-link policy', () async {
    final runtime = CCRouterRuntime.forTesting(
      components: [
        component(
          'orders',
          register: (registry) => registry.registerRoute<String, void>(
            CCRouteDefinition<String, void>(
              routeId: 'orders.internal',
              patterns: [CCPathPattern('/internal/:value', primary: true)],
              codec: const StringCodec(),
            ),
          ),
        ),
      ],
    );
    runtime.initialize();

    expect(runtime.resolveRoute('/internal/42').routeId, 'orders.internal');
    expect(
      () => runtime.resolveRoute('/internal/42', external: true),
      throwsA(isA<CCDeepLinkRejectedError>()),
    );
    expect(
      () => runtime.resolveRoute('internal/42'),
      throwsA(isA<CCRouteNotFoundError>()),
    );
    await runtime.dispose();
  });

  test('route registration rejects missing primary and duplicate patterns', () {
    expect(
      () => CCRouterRuntime.forTesting(
        components: [
          component(
            'orders',
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'orders.invalid',
                patterns: [CCPathPattern('/orders/:value')],
                codec: const StringCodec(),
              ),
            ),
          ),
        ],
      ),
      throwsA(isA<CCRouteRegistrationError>()),
    );
    expect(
      () => CCRouterRuntime.forTesting(
        components: [
          component(
            'a',
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'a.route',
                patterns: [CCPathPattern('/same', primary: true)],
                codec: const StringCodec(),
              ),
            ),
          ),
          component(
            'b',
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'b.route',
                patterns: [CCPathPattern('/same', primary: true)],
                codec: const StringCodec(),
              ),
            ),
          ),
        ],
      ),
      throwsA(isA<CCRouteRegistrationError>()),
    );
    expect(
      () => CCRouterRuntime.forTesting(
        components: [
          component(
            'orders',
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'orders.duplicate',
                patterns: [
                  CCPathPattern('/orders/:value', primary: true),
                  CCPathPattern('/orders/:value'),
                ],
                codec: const StringCodec(),
              ),
            ),
          ),
        ],
      ),
      throwsA(isA<CCRouteRegistrationError>()),
    );
  });

  test('route registration rejects malformed URI and regex patterns', () {
    for (final pattern in [
      CCUriPattern('/orders/:value', primary: true),
      CCUriPattern(
        'https://therouter.com/orders/:value?tab=items',
        primary: true,
      ),
      CCUriPattern(
        'https://therouter.com/orders/:value#summary',
        primary: true,
      ),
      CCUriPattern('therouter://user@orders/detail/:value', primary: true),
    ]) {
      expect(
        () => CCRouterRuntime.forTesting(
          components: [
            component(
              'orders',
              register: (registry) => registry.registerRoute<String, void>(
                CCRouteDefinition<String, void>(
                  routeId: 'orders.invalid',
                  patterns: [pattern],
                  codec: const StringCodec(),
                ),
              ),
            ),
          ],
        ),
        throwsA(isA<CCRouteRegistrationError>()),
      );
    }

    expect(
      () => CCRouterRuntime.forTesting(
        components: [
          component(
            'orders',
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'orders.invalid-regex',
                patterns: [
                  CCPathPattern('/orders/:value', primary: true),
                  const CCRegexPattern('['),
                ],
                codec: const StringCodec(),
              ),
            ),
          ),
        ],
      ),
      throwsA(isA<CCRouteRegistrationError>()),
    );
    expect(const CCRegexPattern('.*').primary, isFalse);
    expect(const CCRegexPattern('.*'), isA<CCRegexPattern>());
  });

  test('runtime rejects invalid handwritten route identities and policies', () {
    final invalidDefinitions = <CCRouteDefinition<String, void>>[
      CCRouteDefinition<String, void>(
        routeId: 'Orders.detail',
        patterns: [CCPathPattern('/orders/:value', primary: true)],
        codec: const StringCodec(),
      ),
      CCRouteDefinition<String, void>(
        routeId: 'orders.detail',
        patterns: [CCPathPattern('/orders/:value', primary: true)],
        codec: const StringCodec(),
        placement: const CCRoutePlacement(hostId: 'Host.Main'),
      ),
      CCRouteDefinition<String, void>(
        routeId: 'orders.detail',
        patterns: [CCPathPattern('/orders/:value', primary: true)],
        codec: const StringCodec(),
        interceptorIds: const ['orders.auth', 'orders.auth'],
      ),
      CCRouteDefinition<String, void>(
        routeId: 'orders.detail',
        patterns: [CCPathPattern('/orders/:value', primary: true)],
        codec: const StringCodec(),
        popGuardIds: const ['orders.dirty', 'orders.dirty'],
      ),
    ];

    for (final definition in invalidDefinitions) {
      expect(
        () => CCRouterRuntime.forTesting(
          components: [
            component(
              'orders',
              register: (registry) => registry.registerRoute(definition),
            ),
          ],
        ),
        throwsA(isA<CCRouteRegistrationError>()),
      );
    }
  });

  test('runtime bounds handwritten route regular expressions', () {
    final oversized = List<String>.filled(2049, 'a').join();
    expect(
      () => CCRouterRuntime.forTesting(
        components: [
          component(
            'orders',
            register: (registry) => registry.registerRoute<String, void>(
              CCRouteDefinition<String, void>(
                routeId: 'orders.regex',
                patterns: [
                  CCPathPattern('/orders/:value', primary: true),
                  CCRegexPattern(oversized),
                ],
                codec: const StringCodec(),
              ),
            ),
          ),
        ],
      ),
      throwsA(isA<CCRouteRegistrationError>()),
    );
  });

  test('runtime applies generator expression bounds to handwritten routes', () {
    final tooManyCaptures = List<String>.generate(
      33,
      (index) => '(?<part$index>a)',
    ).join();
    final oversizedConstraint = List<String>.filled(257, 'a').join();
    for (final (pattern, diagnostic) in [
      (CCRegexPattern(tooManyCaptures), 'named captures'),
      (
        CCPathPattern(
          '/orders/:value',
          constraints: {'value': oversizedConstraint},
        ),
        'characters',
      ),
    ]) {
      expect(
        () => CCRouterRuntime.forTesting(
          components: [
            component(
              'orders',
              register: (registry) => registry.registerRoute<String, void>(
                CCRouteDefinition<String, void>(
                  routeId: 'orders.bounds',
                  patterns: [
                    const CCPathPattern('/orders/:value', primary: true),
                    pattern,
                  ],
                  codec: const StringCodec(),
                ),
              ),
            ),
          ],
        ),
        throwsA(
          isA<CCRouteRegistrationError>().having(
            (error) => error.message,
            'message',
            contains(diagnostic),
          ),
        ),
      );
    }
  });

  test('runtime validates component identity, SemVer, and dependencies', () {
    for (final manifest in [
      component('Bad ID'),
      CCComponentManifest(
        id: 'orders',
        version: '1.0.0-01',
        registrar: Registrar((_) {}),
      ),
      component('orders', dependencies: const ['orders']),
      component('orders', dependencies: const ['account', 'account']),
    ]) {
      expect(
        () => CCRouterRuntime.forTesting(components: [manifest]),
        throwsA(isA<CCRegistrationError>()),
      );
    }
  });

  test('runtime rejects invalid Shell and Outlet identities', () {
    expect(
      () => CCRouterRuntime.forTesting(
        components: [
          component(
            'orders',
            register: (registry) => registry.registerShell(
              CCShellDefinition(
                shellId: 'Orders.Tabs',
                type: CCShellType.singleNavigator,
                outlets: const ['Root'],
                initialOutlet: 'Root',
              ),
            ),
          ),
        ],
      ),
      throwsA(isA<CCShellRegistrationError>()),
    );
  });

  test(
    'runtime rejects missing, cyclic, and mismatched route parents',
    () async {
      CCRouterRuntime buildRuntime({
        bool cycle = false,
        bool missing = false,
        bool mismatch = false,
      }) {
        return CCRouterRuntime.forTesting(
          components: [
            component(
              'orders',
              register: (registry) {
                registry.registerRoute<String, void>(
                  CCRouteDefinition<String, void>(
                    routeId: 'orders.root',
                    patterns: [CCPathPattern('/root/:value', primary: true)],
                    codec: const StringCodec(),
                    placement: CCRoutePlacement(
                      parentRouteId: cycle ? 'orders.detail' : null,
                    ),
                  ),
                );
                registry.registerRoute<String, void>(
                  CCRouteDefinition<String, void>(
                    routeId: 'orders.detail',
                    patterns: [CCPathPattern('/detail/:value', primary: true)],
                    codec: const StringCodec(),
                    placement: CCRoutePlacement(
                      parentRouteId: missing ? 'orders.missing' : 'orders.root',
                      navigatorOutlet: mismatch ? 'detail' : 'root',
                    ),
                  ),
                );
              },
            ),
          ],
        );
      }

      for (final runtime in [
        buildRuntime(missing: true),
        buildRuntime(cycle: true),
        buildRuntime(mismatch: true),
      ]) {
        expect(runtime.initialize, throwsA(isA<CCRouteRegistrationError>()));
        await runtime.dispose();
      }
    },
  );

  test('overlapping regex routes fail resolution explicitly', () async {
    final runtime = CCRouterRuntime.forTesting(
      components: [
        component(
          'first',
          register: (registry) => registry.registerRoute<String, void>(
            CCRouteDefinition<String, void>(
              routeId: 'first.legacy',
              patterns: [
                CCPathPattern('/first/:value', primary: true),
                const CCRegexPattern(r'https://legacy\.example\.com/.*'),
              ],
              codec: const StringCodec(),
            ),
          ),
        ),
        component(
          'second',
          register: (registry) => registry.registerRoute<String, void>(
            CCRouteDefinition<String, void>(
              routeId: 'second.legacy',
              patterns: [
                CCPathPattern('/second/:value', primary: true),
                const CCRegexPattern(r'https://legacy\..*'),
              ],
              codec: const StringCodec(),
            ),
          ),
        ),
      ],
    );
    runtime.initialize();

    expect(
      () => runtime.resolveRoute('https://legacy.example.com/order/42'),
      throwsA(isA<CCRouteAmbiguityError>()),
    );
    await runtime.dispose();
  });

  test('missing dependencies fail before any registrar executes', () {
    var registered = false;
    expect(
      () => CCRouterRuntime.forTesting(
        components: [
          component('a', register: (_) => registered = true),
          component('b', dependencies: ['missing']),
        ],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    expect(registered, isFalse);
  });

  test('cycles, duplicate IDs and empty IDs fail assembly', () {
    expect(
      () => CCRouterRuntime.forTesting(
        components: [
          component('a', dependencies: ['b']),
          component('b', dependencies: ['a']),
        ],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    expect(
      () => CCRouterRuntime.forTesting(
        components: [component('a'), component('a')],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    expect(
      () => CCRouterRuntime.forTesting(components: [component('')]),
      throwsA(isA<CCRegistrationError>()),
    );
  });

  test(
    'absent optional components are allowed; present ones precede consumer',
    () async {
      final runtime = CCRouterRuntime.forTesting(
        components: [
          component('a', optional: ['b', 'missing']),
          component('b'),
        ],
      );
      expect(runtime.components.map((item) => item.id), ['b', 'a']);
      await runtime.dispose();
    },
  );

  test('cross-component duplicate capabilities fail assembly', () {
    void register(CCRegistry registry) => registry.registerService(
      CCServiceProvider<String>(factory: (_) => 'duplicate'),
    );
    expect(
      () => CCRouterRuntime.forTesting(
        components: [
          component('a', register: register),
          component('b', register: register),
        ],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
  });

  test(
    'generated Service invocation records sanitized ownership trace',
    () async {
      const contract = CCServiceToken<ComponentService>('feature.counter');
      late CCInvocationContext invocation;
      final runtime = CCRouterRuntime.forTesting(
        components: [
          component(
            'feature',
            register: (registry) {
              registry.registerService<ComponentService>(
                CCServiceProvider(
                  contract: contract,
                  factory: (_) => ComponentService('secret-service-value'),
                ),
              );
            },
          ),
        ],
      );
      runtime.initialize();

      final result = await runtime.invokeService<ComponentService, String>(
        contract: contract,
        methodId: 'read',
        callerComponentId: 'consumer',
        call: (service, context) {
          invocation = context;
          return 'secret-result-${service.id}';
        },
      );

      expect(result, 'secret-result-secret-service-value');
      expect(invocation.operation, 'service');
      expect(invocation.target, 'feature.counter.read');
      expect(invocation.callerComponentId, 'consumer');
      expect(invocation.targetComponentId, 'feature');
      final trace = runtime.recentTraces.single;
      expect(trace.operation, 'service');
      expect(trace.target, 'feature.counter.read');
      expect(trace.target, isNot(contains('secret')));
      expect(trace.context.operation, 'service');
      expect(trace.context.target, trace.target);
      expect(trace.context.callerComponentId, 'consumer');
      expect(trace.context.targetComponentId, 'feature');

      await runtime.dispose();
    },
  );

  test(
    'generated synchronous Service invocation preserves its result type',
    () async {
      const contract = CCServiceToken<ComponentService>('feature.sync-counter');
      late CCInvocationContext invocation;
      final runtime = CCRouterRuntime.forTesting(
        components: [
          component(
            'feature',
            register: (registry) {
              registry.registerService<ComponentService>(
                CCServiceProvider(
                  contract: contract,
                  factory: (_) => ComponentService('sync'),
                ),
              );
            },
          ),
        ],
      );
      runtime.initialize();

      final result = runtime.invokeServiceSync<ComponentService, String>(
        contract: contract,
        methodId: 'read',
        callerComponentId: 'consumer',
        call: (service, context) {
          invocation = context;
          return service.id;
        },
      );

      expect(result, 'sync');
      expect(invocation.operation, 'service');
      expect(invocation.target, 'feature.sync-counter.read');
      expect(invocation.callerComponentId, 'consumer');
      expect(invocation.targetComponentId, 'feature');
      final trace = runtime.recentTraces.single;
      expect(trace.status, 'succeeded');
      expect(trace.context.callerComponentId, 'consumer');
      expect(trace.context.targetComponentId, 'feature');

      await runtime.dispose();
    },
  );

  test('generated Service invocation awaits lazy readiness', () async {
    const contract = CCServiceToken<ComponentService>('feature.ready-counter');
    var initializations = 0;
    final runtime = CCRouterRuntime.forTesting(
      components: [
        component(
          'feature',
          register: (registry) {
            registry.registerService<ComponentService>(
              CCServiceProvider(
                contract: contract,
                factory: (_) => ComponentService('ready'),
                initializer: (_, context) async {
                  expect(context.operation, 'serviceInitialize');
                  initializations++;
                },
              ),
            );
          },
        ),
      ],
    );
    runtime.initialize();

    expect(
      () => runtime.service<ComponentService>(contract: contract),
      throwsA(isA<CCServiceNotReadyError>()),
    );
    final result = await runtime.invokeService<ComponentService, String>(
      contract: contract,
      methodId: 'read',
      call: (service, _) => service.id,
    );
    expect(result, 'ready');
    expect(initializations, 1);
    expect(runtime.service<ComponentService>(contract: contract).id, 'ready');

    await runtime.dispose();
  });

  test('nested Command and Service invocation share a trace tree', () async {
    const contract = CCServiceToken<ComponentService>('feature.counter');
    late CCInvocationContext commandContext;
    late CCInvocationContext serviceContext;
    late CCRouterRuntime runtime;
    runtime = CCRouterRuntime.forTesting(
      components: [
        component(
          'feature',
          register: (registry) {
            registry.registerService<ComponentService>(
              CCServiceProvider(
                contract: contract,
                factory: (_) => ComponentService('nested'),
              ),
            );
          },
        ),
      ],
    );
    runtime.registerCommand<ServiceInvocationCommand, int>((message, context) {
      commandContext = context;
      return runtime.invokeService<ComponentService, int>(
        contract: contract,
        methodId: 'increment',
        callerComponentId: 'consumer',
        call: (service, context) {
          serviceContext = context;
          return message.value + 1;
        },
      );
    });
    runtime.initialize();

    expect(await runtime.command(const ServiceInvocationCommand(3)), 4);
    expect(serviceContext.traceId, commandContext.traceId);
    expect(serviceContext.parentSpanId, commandContext.spanId);
    final serviceTrace = runtime.recentTraces.singleWhere(
      (trace) => trace.operation == 'service',
    );
    expect(serviceTrace.context.parentSpanId, commandContext.spanId);

    await runtime.dispose();
  });

  test(
    'Service timeout and caller cancellation reach invocation context',
    () async {
      const contract = CCServiceToken<ComponentService>('feature.counter');
      final pending = <Completer<int>>[];
      final contexts = <CCInvocationContext>[];
      final runtime = CCRouterRuntime.forTesting(
        components: [
          component(
            'feature',
            register: (registry) {
              registry.registerService<ComponentService>(
                CCServiceProvider(
                  contract: contract,
                  factory: (_) => ComponentService('pending'),
                ),
              );
            },
          ),
        ],
      );
      runtime.initialize();

      Future<int> invoke({
        Duration? timeout,
        CCCancellationToken? cancellation,
      }) => runtime.invokeService<ComponentService, int>(
        contract: contract,
        methodId: 'wait',
        timeout: timeout,
        cancellation: cancellation,
        call: (_, context) {
          contexts.add(context);
          final completer = Completer<int>();
          pending.add(completer);
          return completer.future;
        },
      );

      await expectLater(
        invoke(timeout: const Duration(milliseconds: 10)),
        throwsA(isA<CCInvocationTimeoutError>()),
      );
      expect(contexts.first.cancellation.isCancelled, isTrue);
      pending.first.complete(1);

      final token = CCCancellationToken();
      final cancelled = invoke(cancellation: token);
      token.cancel();
      await expectLater(cancelled, throwsA(isA<CCInvocationCancelledError>()));
      expect(contexts.last.cancellation.isCancelled, isTrue);
      pending.last.complete(2);

      await runtime.dispose();
    },
  );

  test('Session close cancels its in-flight Service invocation', () async {
    const contract = CCServiceToken<ComponentService>('account.counter');
    final pending = Completer<int>();
    final started = Completer<CCInvocationContext>();
    final runtime = CCRouterRuntime.forTesting(
      components: [
        component(
          'account',
          register: (registry) {
            registry.registerService<ComponentService>(
              CCServiceProvider(
                contract: contract,
                scope: CCServiceScope.session,
                factory: (_) => ComponentService('session'),
              ),
            );
          },
        ),
      ],
    );
    runtime.initialize();
    runtime.openSession(accountId: 'account-a');
    final call = runtime.invokeService<ComponentService, int>(
      contract: contract,
      methodId: 'wait',
      call: (_, context) {
        started.complete(context);
        return pending.future;
      },
    );
    final context = await started.future;

    final assertion = expectLater(
      call,
      throwsA(isA<CCInvocationCancelledError>()),
    );
    await runtime.closeSession();
    await assertion;
    expect(context.cancellation.isCancelled, isTrue);
    pending.complete(1);

    await runtime.dispose();
  });

  test(
    'Service invocation rejects invalid and inconsistent identities',
    () async {
      const contract = CCServiceToken<ComponentService>('feature.counter');
      final runtime = CCRouterRuntime.forTesting(
        components: [
          component(
            'feature',
            register: (registry) {
              registry.registerService<ComponentService>(
                CCServiceProvider(
                  contract: contract,
                  factory: (_) => ComponentService('identity'),
                ),
              );
            },
          ),
        ],
      );
      runtime.initialize();

      expect(
        () => runtime.invokeService<ComponentService, void>(
          contract: contract,
          methodId: 'Invalid method',
          call: (_, _) {},
        ),
        throwsA(isA<CCInvocationError>()),
      );
      expect(
        () => runtime.invokeService<ComponentService, void>(
          contract: contract,
          methodId: 'read',
          callerComponentId: 'InvalidCaller',
          call: (_, _) {},
        ),
        throwsA(isA<CCInvocationError>()),
      );
      expect(
        () => runtime.invokeService<ComponentService, void>(
          contract: contract,
          methodId: 'read',
          navigationId: 'stale-route',
          call: (_, _) {},
        ),
        throwsA(isA<CCInvocationError>()),
      );
      expect(runtime.recentTraces, isEmpty);

      await runtime.dispose();
    },
  );

  test('Route Scope is isolated by exact managed navigation', () async {
    final adapter = CCMemoryNavigationAdapter();
    final created = <ComponentService>[];
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        component(
          'feature',
          register: (registry) {
            registry.registerService<ComponentService>(
              CCServiceProvider(
                scope: CCServiceScope.route,
                factory: (_) {
                  final service = ComponentService('route-${created.length}');
                  created.add(service);
                  return service;
                },
              ),
            );
            registry.registerRoute<String, void>(
              CCRouteDefinition(
                routeId: 'feature.detail',
                patterns: [CCPathPattern('/feature/:value', primary: true)],
                codec: const StringCodec(),
              ),
            );
          },
        ),
      ],
    );
    runtime.initialize();

    expect(
      () => runtime.service<ComponentService>(),
      throwsA(isA<CCServiceScopeUnavailableError>()),
    );
    final firstPush = runtime.pushRoute<void>(
      const StringIntent('feature.detail', 'first'),
    );
    unawaited(firstPush.then<void>((_) {}, onError: (_, _) {}));
    await Future<void>.delayed(Duration.zero);
    final firstNavigationId = runtime.activeRouteEntries.single.navigationId;
    final first = runtime.serviceForRoute<ComponentService>(
      navigationId: firstNavigationId,
    );
    expect(
      runtime.serviceForRoute<ComponentService>(
        navigationId: firstNavigationId,
      ),
      same(first),
    );

    final secondPush = runtime.pushRoute<void>(
      const StringIntent('feature.detail', 'second'),
    );
    await Future<void>.delayed(Duration.zero);
    final secondNavigationId = runtime.activeRouteEntries.last.navigationId;
    final second = runtime.serviceForRoute<ComponentService>(
      navigationId: secondNavigationId,
    );
    expect(second, isNot(same(first)));
    expect(first.disposed, isFalse);

    runtime.popRoute();
    await secondPush;
    await Future<void>.delayed(Duration.zero);
    expect(second.disposed, isTrue);
    expect(first.disposed, isFalse);
    expect(
      () => runtime.serviceForRoute<ComponentService>(
        navigationId: secondNavigationId,
      ),
      throwsA(isA<CCServiceScopeUnavailableError>()),
    );
    expect(
      runtime.serviceForRoute<ComponentService>(
        navigationId: firstNavigationId,
      ),
      same(first),
    );

    await runtime.dispose();
    await firstPush;
    expect(first.disposed, isTrue);
  });

  test('Route Pop cancels only its exact Service invocation', () async {
    const contract = CCServiceToken<ComponentService>('feature.route-counter');
    final adapter = CCMemoryNavigationAdapter();
    final pending = <String, Completer<int>>{};
    final contexts = <String, CCInvocationContext>{};
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        component(
          'feature',
          register: (registry) {
            registry.registerService<ComponentService>(
              CCServiceProvider(
                contract: contract,
                scope: CCServiceScope.route,
                factory: (_) => ComponentService('route'),
              ),
            );
            registry.registerRoute<String, void>(
              CCRouteDefinition(
                routeId: 'feature.invocation',
                patterns: [
                  CCPathPattern('/feature/invocation/:value', primary: true),
                ],
                codec: const StringCodec(),
              ),
            );
          },
        ),
      ],
    );
    runtime.initialize();

    final firstPush = runtime.pushRoute<void>(
      const StringIntent('feature.invocation', 'first'),
    );
    unawaited(firstPush.then<void>((_) {}, onError: (_, _) {}));
    await Future<void>.delayed(Duration.zero);
    final firstNavigationId = runtime.activeRouteEntries.single.navigationId;
    final firstCall = runtime.invokeService<ComponentService, int>(
      contract: contract,
      methodId: 'wait',
      navigationId: firstNavigationId,
      call: (_, context) {
        contexts['first'] = context;
        return (pending['first'] = Completer<int>()).future;
      },
    );

    final secondPush = runtime.pushRoute<void>(
      const StringIntent('feature.invocation', 'second'),
    );
    await Future<void>.delayed(Duration.zero);
    final secondNavigationId = runtime.activeRouteEntries.last.navigationId;
    final secondCall = runtime.invokeService<ComponentService, int>(
      contract: contract,
      methodId: 'wait',
      navigationId: secondNavigationId,
      call: (_, context) {
        contexts['second'] = context;
        return (pending['second'] = Completer<int>()).future;
      },
    );

    final secondAssertion = expectLater(
      secondCall,
      throwsA(isA<CCInvocationCancelledError>()),
    );
    runtime.popRoute();
    await secondPush;
    await secondAssertion;
    expect(contexts['second']!.cancellation.isCancelled, isTrue);
    expect(contexts['first']!.cancellation.isCancelled, isFalse);
    pending['second']!.complete(2);

    pending['first']!.complete(1);
    expect(await firstCall, 1);
    runtime.popRoute();
    await firstPush;
    await runtime.dispose();
  });

  test('Route Service invocation requires a retained navigation ID', () async {
    const contract = CCServiceToken<ComponentService>('feature.route-counter');
    final runtime = CCRouterRuntime.forTesting(
      components: [
        component(
          'feature',
          register: (registry) {
            registry.registerService<ComponentService>(
              CCServiceProvider(
                contract: contract,
                scope: CCServiceScope.route,
                factory: (_) => ComponentService('route'),
              ),
            );
          },
        ),
      ],
    );
    runtime.initialize();

    expect(
      () => runtime.invokeService<ComponentService, void>(
        contract: contract,
        methodId: 'read',
        call: (_, _) {},
      ),
      throwsA(isA<CCServiceScopeUnavailableError>()),
    );
    expect(
      () => runtime.invokeService<ComponentService, void>(
        contract: contract,
        methodId: 'read',
        navigationId: 'removed',
        call: (_, _) {},
      ),
      throwsA(isA<CCServiceScopeUnavailableError>()),
    );

    await runtime.dispose();
  });

  test('Route Pop cancels pending Route Service readiness', () async {
    const contract = CCServiceToken<ComponentService>('feature.route-ready');
    final adapter = CCMemoryNavigationAdapter();
    final pending = Completer<void>();
    final started = Completer<CCInvocationContext>();
    late ComponentService service;
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        component(
          'feature',
          register: (registry) {
            registry.registerService<ComponentService>(
              CCServiceProvider(
                contract: contract,
                scope: CCServiceScope.route,
                factory: (_) => service = ComponentService('route-ready'),
                initializer: (_, context) {
                  started.complete(context);
                  return pending.future;
                },
              ),
            );
            registry.registerRoute<String, void>(
              CCRouteDefinition(
                routeId: 'feature.route-ready',
                patterns: [
                  CCPathPattern('/feature/route-ready/:value', primary: true),
                ],
                codec: const StringCodec(),
              ),
            );
          },
        ),
      ],
    );
    runtime.initialize();
    final pushed = runtime.pushRoute<void>(
      const StringIntent('feature.route-ready', 'first'),
    );
    await Future<void>.delayed(Duration.zero);
    final navigationId = runtime.activeRouteEntries.single.navigationId;
    final resolving = runtime.serviceForRouteAsync<ComponentService>(
      navigationId: navigationId,
      contract: contract,
    );
    final context = await started.future;

    final assertion = expectLater(
      resolving,
      throwsA(isA<CCInvocationCancelledError>()),
    );
    runtime.popRoute();
    await pushed;
    await assertion;
    expect(context.cancellation.isCancelled, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(service.disposed, isTrue);
    pending.complete();
    await runtime.dispose();
  });

  test('Route Scope survives a rejected Pop guard', () async {
    final adapter = CCMemoryNavigationAdapter();
    late ComponentService service;
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        component(
          'feature',
          register: (registry) {
            registry.registerService<ComponentService>(
              CCServiceProvider(
                scope: CCServiceScope.route,
                factory: (_) => service = ComponentService('guarded'),
              ),
            );
            registry.registerRoutePopGuard(
              'feature.unsaved',
              const DenyPopGuard(),
            );
            registry.registerRoute<String, void>(
              CCRouteDefinition(
                routeId: 'feature.guarded',
                patterns: [
                  CCPathPattern('/feature/guarded/:value', primary: true),
                ],
                codec: const StringCodec(),
                popGuardIds: const ['feature.unsaved'],
              ),
            );
          },
        ),
      ],
    );
    runtime.initialize();
    final pushed = runtime.pushRoute<void>(
      const StringIntent('feature.guarded', 'draft'),
    );
    unawaited(pushed.then<void>((_) {}, onError: (_, _) {}));
    await Future<void>.delayed(Duration.zero);
    final navigationId = runtime.activeRouteEntries.single.navigationId;
    runtime.serviceForRoute<ComponentService>(navigationId: navigationId);

    expect(() => runtime.popRoute(), throwsA(isA<CCPopGuardDeniedError>()));
    expect(service.disposed, isFalse);
    expect(runtime.activeRouteEntries, hasLength(1));
    expect(
      runtime.serviceForRoute<ComponentService>(navigationId: navigationId),
      same(service),
    );

    await runtime.dispose();
    await pushed;
    expect(service.disposed, isTrue);
  });

  test('Route Service cannot capture a Session Service', () async {
    late CCRouterRuntime runtime;
    final adapter = CCMemoryNavigationAdapter();
    runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        component(
          'feature',
          register: (registry) {
            registry.registerService<int>(
              CCServiceProvider(
                scope: CCServiceScope.session,
                factory: (_) => 42,
              ),
            );
            registry.registerService<String>(
              CCServiceProvider(
                scope: CCServiceScope.route,
                factory: (_) => '${runtime.service<int>()}',
              ),
            );
            registry.registerRoute<String, void>(
              CCRouteDefinition(
                routeId: 'feature.session-capture',
                patterns: [
                  CCPathPattern('/feature/session/:value', primary: true),
                ],
                codec: const StringCodec(),
              ),
            );
          },
        ),
      ],
    );
    runtime.initialize();
    runtime.openSession(accountId: 'account');
    final pushed = runtime.pushRoute<void>(
      const StringIntent('feature.session-capture', '42'),
    );
    await Future<void>.delayed(Duration.zero);
    final navigationId = runtime.activeRouteEntries.single.navigationId;

    expect(
      () => runtime.serviceForRoute<String>(navigationId: navigationId),
      throwsA(isA<CCResolutionError>()),
    );
    runtime.popRoute();
    await pushed;
    await runtime.dispose();
  });

  test('Route Service registration requires a component owner', () async {
    final runtime = CCRouterRuntime.forTesting();

    expect(
      () => runtime.registerService<ComponentService>(
        CCServiceProvider(
          scope: CCServiceScope.route,
          factory: (_) => ComponentService('invalid'),
        ),
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    await runtime.dispose();
  });

  test(
    'App service cannot capture Session service through a Factory',
    () async {
      final runtime = CCRouterRuntime.forTesting();
      runtime.registerService(
        CCServiceProvider<int>(
          scope: CCServiceScope.session,
          factory: (_) => 1,
        ),
      );
      runtime.registerService(
        CCServiceProvider<String>(
          creationPolicy: CCServiceCreationPolicy.factory,
          factory: (_) => '${runtime.service<int>()}',
        ),
      );
      runtime.registerService(
        CCServiceProvider<double>(
          factory: (_) => double.parse(runtime.service<String>()),
        ),
      );
      runtime.initialize();
      runtime.openSession(accountId: 'account-a');
      expect(
        () => runtime.service<double>(),
        throwsA(isA<CCResolutionError>()),
      );
      await runtime.dispose();
    },
  );

  test(
    'dependency constructors give reverse dependency disposal order',
    () async {
      final order = <String>[];
      final runtime = CCRouterRuntime.forTesting();
      runtime.registerService(
        CCServiceProvider<Resource>(
          key: const CCServiceKey('dependency'),
          factory: (_) => Resource('dependency', order),
        ),
      );
      runtime.registerService(
        CCServiceProvider<Resource>(
          factory: (_) {
            runtime.service<Resource>(key: const CCServiceKey('dependency'));
            return Resource('consumer', order);
          },
        ),
      );
      runtime.initialize();
      runtime.service<Resource>();
      await runtime.dispose();
      expect(order, ['consumer', 'dependency']);
    },
  );
}

final class Resource implements CCDisposable {
  Resource(this.id, this.order);
  final String id;
  final List<String> order;
  @override
  void dispose() => order.add(id);
}
