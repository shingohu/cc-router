import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reentrant_lifecycle_regression_test.dart' as fixture;

class ExternalRegistrar implements CCComponentRegistrar {
  @override
  void register(CCRegistry registry) {
    registry.registerRoute(
      CCRouteDefinition<String, void>(
        routeId: 'probe.detail',
        patterns: const [CCPathPattern('/detail/:id', primary: true)],
        codec: const fixture.Codec(),
        deepLink: CCDeepLinkPolicy.enabled,
      ),
    );
  }
}

CCRouterRuntime createRuntime(CCMemoryNavigationAdapter adapter) {
  final runtime = CCRouterRuntime.forTesting(
    navigationAdapter: adapter,
    deepLinkIngressPolicy: CCDeepLinkIngressPolicy(
      allowedAuthorities: [
        CCDeepLinkAuthorityRule(scheme: 'https', host: 'example.com'),
      ],
    ),
    components: [
      CCComponentManifest(
        id: 'probe',
        version: '1.0.0',
        registrar: ExternalRegistrar(),
      ),
    ],
  );
  runtime.initialize();
  return runtime;
}

void main() {
  for (final origin in [
    CCNavigationOrigin.externalPlatform,
    CCNavigationOrigin.externalNotification,
    CCNavigationOrigin.externalQrCode,
  ]) {
    for (final sample in <(String, String)>[
      ('A', 'A'),
      ('a%2Fb', 'a/b'),
      ('a%252Fb', 'a%2Fb'),
      ('a+b', 'a+b'),
      ('%E4%B8%AD%E6%96%87', '中文'),
      ('a%3Fb%23c', 'a?b#c'),
      ('a%20b', 'a b'),
    ]) {
      test(
        'external $origin decodes Path exactly once: ${sample.$1}',
        () async {
          final adapter = CCMemoryNavigationAdapter();
          final runtime = createRuntime(adapter);
          addTearDown(runtime.dispose);
          await runtime.openRoute(
            Uri.parse(
              'https://example.com:443/detail/${sample.$1}?filter=x&filter=y',
            ),
            origin: origin,
            mode: CCDeepLinkOpenMode.go,
          );
          expect(adapter.currentRequest!.arguments, sample.$2);
          expect(adapter.currentRequest!.uri.queryParametersAll['filter'], [
            'x',
            'y',
          ]);
          expect(adapter.currentRequest!.origin, origin);
          expect(runtime.activeRouteEntries, hasLength(1));
        },
      );
    }

    for (final location in [
      'https://evil.example/detail/A',
      'https://example.com.evil/detail/A',
      'http://example.com/detail/A',
      'https://user@example.com/detail/A',
      'https://example.com:8443/detail/A',
      '/detail/A',
      '//example.com/detail/A',
    ]) {
      test(
        'external $origin rejects authority/path before mutation: $location',
        () async {
          final adapter = CCMemoryNavigationAdapter();
          final runtime = createRuntime(adapter);
          addTearDown(runtime.dispose);
          await expectLater(
            runtime.openRoute(Uri.parse(location), origin: origin),
            throwsA(
              location.startsWith('//')
                  ? isA<CCRouteNotFoundError>()
                  : isA<CCDeepLinkIngressRejectedError>(),
            ),
          );
          expect(adapter.stack, isEmpty);
          expect(runtime.activeRouteEntries, isEmpty);
          // Rejection must not poison later admission to the intended authority.
          await runtime.openRoute(
            Uri.parse('https://example.com/detail/valid'),
            origin: origin,
            mode: CCDeepLinkOpenMode.go,
          );
          expect(adapter.currentRequest!.arguments, 'valid');
        },
      );
    }
  }
}
