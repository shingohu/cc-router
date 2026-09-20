// ignore_for_file: deprecated_member_use

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:test/test.dart';

final class _DeepLinkArgs {
  const _DeepLinkArgs(this.id);

  final String id;
}

final class _DeepLinkCodec implements CCRouteCodec<_DeepLinkArgs> {
  const _DeepLinkCodec();

  @override
  _DeepLinkArgs decode(CCEncodedRouteArguments input) =>
      _DeepLinkArgs(input.path['id']!);

  @override
  CCEncodedRouteArguments encode(_DeepLinkArgs arguments) =>
      CCEncodedRouteArguments(path: {'id': arguments.id});
}

final class _DeepLinkRegistrar implements CCComponentRegistrar {
  const _DeepLinkRegistrar({this.deepLink = CCDeepLinkPolicy.enabled});

  final CCDeepLinkPolicy deepLink;

  @override
  void register(CCRegistry registry) {
    registry.registerRoute<_DeepLinkArgs, void>(
      CCRouteDefinition<_DeepLinkArgs, void>(
        routeId: 'orders.detail',
        patterns: [
          const CCPathPattern('/orders/:id', primary: true),
          const CCUriPattern('https://example.com/orders/:id'),
        ],
        codec: const _DeepLinkCodec(),
        deepLink: deepLink,
      ),
    );
  }
}

final _deepLinkPolicy = CCDeepLinkIngressPolicy(
  allowedAuthorities: [
    CCDeepLinkAuthorityRule(scheme: 'https', host: 'example.com'),
  ],
  allowRelativePaths: true,
);

void main() {
  tearDown(CCRouter.shutdown);

  test('fixed ingress methods preserve external origin and source', () async {
    final adapter = CCMemoryNavigationAdapter();
    CCRouter.initialize(
      deepLinkIngressPolicy: _deepLinkPolicy,
      components: const [
        CCComponentManifest(
          id: 'orders',
          version: '0.1.0',
          registrar: _DeepLinkRegistrar(),
        ),
      ],
    );
    CCRouterHostBinding.attachNavigationAdapter(adapter);

    const platformSource = CCNavigationSource.deepLink('universal_link');
    await CCDeepLinkIngress.fromPlatform(
      Uri.parse('https://example.com/orders/42'),
      source: platformSource,
    );
    expect(adapter.currentRequest?.origin, CCNavigationOrigin.externalPlatform);
    expect(adapter.currentRequest?.source, same(platformSource));

    const notificationSource = CCNavigationSource.notification('order_ready');
    await CCDeepLinkIngress.fromNotification(
      Uri.parse('https://example.com/orders/43'),
      source: notificationSource,
    );
    expect(
      adapter.currentRequest?.origin,
      CCNavigationOrigin.externalNotification,
    );
    expect(adapter.currentRequest?.source, same(notificationSource));

    await CCDeepLinkIngress.fromQrCode(Uri.parse('/orders/44'));
    expect(adapter.currentRequest?.origin, CCNavigationOrigin.externalQrCode);
  });

  test('external ingress still enforces disabled Deep Link policy', () async {
    final adapter = CCMemoryNavigationAdapter();
    CCRouter.initialize(
      deepLinkIngressPolicy: _deepLinkPolicy,
      components: const [
        CCComponentManifest(
          id: 'orders',
          version: '0.1.0',
          registrar: _DeepLinkRegistrar(deepLink: CCDeepLinkPolicy.disabled),
        ),
      ],
    );
    CCRouterHostBinding.attachNavigationAdapter(adapter);

    await expectLater(
      CCDeepLinkIngress.fromPlatform(Uri.parse('/orders/42')),
      throwsA(isA<CCDeepLinkRejectedError>()),
    );
  });

  test(
    'default Host policy rejects absolute and relative external input',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      CCRouter.initialize(
        components: const [
          CCComponentManifest(
            id: 'orders',
            version: '0.1.0',
            registrar: _DeepLinkRegistrar(),
          ),
        ],
      );
      CCRouterHostBinding.attachNavigationAdapter(adapter);

      await expectLater(
        CCDeepLinkIngress.fromPlatform(
          Uri.parse('https://example.com/orders/42'),
        ),
        throwsA(
          isA<CCDeepLinkIngressRejectedError>().having(
            (error) => error.reason,
            'reason',
            CCDeepLinkIngressRejectionReason.authorityNotAllowed,
          ),
        ),
      );
      await expectLater(
        CCDeepLinkIngress.fromNotification(Uri.parse('/orders/42')),
        throwsA(
          isA<CCDeepLinkIngressRejectedError>().having(
            (error) => error.reason,
            'reason',
            CCDeepLinkIngressRejectionReason.relativePathNotAllowed,
          ),
        ),
      );
      expect(adapter.currentRequest, isNull);
    },
  );

  test(
    'authority rules match case and effective default Port exactly',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      CCRouter.initialize(
        deepLinkIngressPolicy: CCDeepLinkIngressPolicy(
          allowedAuthorities: [
            CCDeepLinkAuthorityRule(scheme: 'HTTPS', host: 'EXAMPLE.COM'),
          ],
        ),
        components: const [
          CCComponentManifest(
            id: 'orders',
            version: '0.1.0',
            registrar: _DeepLinkRegistrar(),
          ),
        ],
      );
      CCRouterHostBinding.attachNavigationAdapter(adapter);

      await CCDeepLinkIngress.fromPlatform(
        Uri.parse('https://EXAMPLE.com:443/orders/42'),
      );
      expect(adapter.currentRequest?.routeId, 'orders.detail');

      await expectLater(
        CCDeepLinkIngress.fromPlatform(
          Uri.parse('https://example.com:8443/orders/43'),
        ),
        throwsA(isA<CCDeepLinkIngressRejectedError>()),
      );
      await expectLater(
        CCDeepLinkIngress.fromPlatform(
          Uri.parse('https://user@example.com/orders/44'),
        ),
        throwsA(
          isA<CCDeepLinkIngressRejectedError>().having(
            (error) => error.reason,
            'reason',
            CCDeepLinkIngressRejectionReason.invalidAuthority,
          ),
        ),
      );
    },
  );

  test('Host policy rejects wildcard and invalid authority configuration', () {
    expect(
      () => CCDeepLinkAuthorityRule(scheme: 'https', host: '*.example.com'),
      throwsArgumentError,
    );
    expect(
      () =>
          CCDeepLinkAuthorityRule(scheme: 'not a scheme', host: 'example.com'),
      throwsArgumentError,
    );
    expect(
      () => CCDeepLinkAuthorityRule(
        scheme: 'https',
        host: 'example.com',
        port: 70000,
      ),
      throwsArgumentError,
    );

    final mutableRules = <CCDeepLinkAuthorityRule>[
      CCDeepLinkAuthorityRule(scheme: 'https', host: 'example.com'),
    ];
    final policy = CCDeepLinkIngressPolicy(allowedAuthorities: mutableRules);
    mutableRules.clear();
    expect(policy.allowedAuthorities, hasLength(1));
    expect(() => policy.allowedAuthorities.clear(), throwsUnsupportedError);
  });
}
