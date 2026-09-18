import 'package:ccrouter/ccrouter.dart';
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

void main() {
  tearDown(CCRouter.shutdown);

  test('fixed ingress methods preserve external origin and source', () async {
    final adapter = CCMemoryNavigationAdapter();
    await CCRouter.initialize(
      components: const [
        CCComponentManifest(
          id: 'orders',
          version: '0.1.0',
          registrar: _DeepLinkRegistrar(),
        ),
      ],
      navigationAdapter: adapter,
    );

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
    await CCRouter.initialize(
      components: const [
        CCComponentManifest(
          id: 'orders',
          version: '0.1.0',
          registrar: _DeepLinkRegistrar(deepLink: CCDeepLinkPolicy.disabled),
        ),
      ],
      navigationAdapter: adapter,
    );

    await expectLater(
      CCDeepLinkIngress.fromPlatform(Uri.parse('/orders/42')),
      throwsA(isA<CCRouteNotFoundError>()),
    );
  });
}
