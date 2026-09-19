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
    'Shell contracts validate route placement and follow component state',
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

      runtime.deactivateComponent('app-shell');
      expect(
        () => runtime.resolveRoute('/settings/42'),
        throwsA(isA<CCRouteUnavailableError>()),
      );
      runtime.activateComponent('app-shell');
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

      runtime.deactivateComponent('orders');
      expect(
        () => runtime.resolveRoute('/orders/42'),
        throwsA(isA<CCRouteUnavailableError>()),
      );
      runtime.activateComponent('orders');
      expect(runtime.resolveRoute('/orders/42').routeId, 'orders.detail');
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

    final web = runtime.resolveRoute(
      'HTTPS://THEROUTER.COM/orders/43?tab=items&tab=history#summary',
      external: true,
    );
    expect(web.routeId, 'orders.detail');
    expect(web.pathParameters, {'value': '43'});
    expect(web.queryParameters, {
      'tab': ['items', 'history'],
    });

    final custom = runtime.resolveRoute(
      'therouter://orders/detail/44',
      external: true,
    );
    expect(custom.routeId, 'orders.detail');
    expect(runtime.decodeRouteArguments(custom), '44');

    final legacy = runtime.resolveRoute(
      'https://legacy.example.com/order/45?source=old#details',
      external: true,
    );
    expect(legacy.routeId, 'orders.detail');
    expect(runtime.decodeRouteArguments(legacy), '45');
    expect(legacy.queryParameters, {
      'source': ['old'],
    });
    expect(
      () => runtime.resolveRoute('https://legacy.example.com/order/45/extra'),
      throwsA(isA<CCRouteNotFoundError>()),
    );
    await runtime.dispose();
  });

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
    'App service cannot capture Session service, including via Transient',
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
          scope: CCServiceScope.transient,
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
