import 'dart:async';

import 'package:ccrouter/ccrouter_generated.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:demo_network/demo_network.dart';
import 'package:demo_network/src/network_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final demoNetworkComponentManifest = ccrouterGeneratedHostAssembly
      .componentManifests
      .singleWhere((manifest) => manifest.id == demoNetworkComponentId.value);

  test('all Demo environments expose the shared anything endpoint', () {
    expect(
      demoNetworkEnvironments.map(
        (environment) => Uri.parse(environment.baseUrl).resolve('anything'),
      ),
      [
        Uri.parse('https://httpbin.org/anything'),
        Uri.parse('https://httpbingo.org/anything'),
        Uri.parse('https://httpbin.org/anything'),
      ],
    );
  });

  test(
    'generated network service releases authentication at App Scope end',
    () async {
      final host = CCRouterTestHost(components: [demoNetworkComponentManifest]);
      addTearDown(host.dispose);
      host.initialize();
      final service = host.runtime.service<DemoNetworkService>(
        contractToken: const CCServiceToken<DemoNetworkService>(
          'demo.network.client',
        ),
      );
      service.setAccessToken('test-only');
      expect(service.isAuthenticated, isTrue);
      await host.dispose();
      expect(service.isAuthenticated, isFalse);
      expect(service.logs, isEmpty);
      await expectLater(service.request(_request), throwsStateError);
      expect(() => service.setAccessToken('late'), throwsStateError);
    },
  );

  test(
    'Scope waits for the owned transport, late logs cannot repopulate',
    () async {
      final backend = _Backend();
      final service = DemoNetworkServiceImpl.withBackend(backend);
      Future<void>? reentrantDisposal;
      backend.onClose = () => reentrantDisposal = service.dispose();
      final host = CCRouterTestHost(
        components: [demoNetworkComponentManifest],
        overrides: [
          CCServiceOverride<DemoNetworkService>.value(
            service,
            contractToken: const CCServiceToken<DemoNetworkService>(
              'demo.network.client',
            ),
          ),
        ],
      );
      addTearDown(host.dispose);
      host.initialize();
      host.runtime.service<DemoNetworkService>(
        contractToken: const CCServiceToken<DemoNetworkService>(
          'demo.network.client',
        ),
      );
      final response = service.request(_request);
      await backend.started.future;
      expect(service.logs, isNotEmpty);
      var finished = false;
      final closing = host.dispose().then((_) => finished = true);
      await backend.closing.future;
      final sameDisposal = service.dispose();
      expect(identical(sameDisposal, reentrantDisposal), isTrue);
      expect(identical(sameDisposal, service.dispose()), isTrue);
      expect(finished, isFalse);
      expect(backend.closeCalls, 1);
      backend.response.complete(
        CCNetworkResponse(statusCode: 200, data: null, request: _request),
      );
      await response;
      expect(service.logs, isEmpty);
      backend.closed.complete();
      await closing;
      await sameDisposal;
      expect(finished, isTrue);
      expect(backend.closeCalls, 1);
    },
  );

  test(
    'transport close failure preserves cleared state and shared failure',
    () async {
      final backend = _Backend();
      final service = DemoNetworkServiceImpl.withBackend(backend)
        ..setAccessToken('test');
      final closing = service.dispose();
      final check = expectLater(closing, throwsStateError);
      backend.closed.completeError(StateError('transport close failed'));
      await check;
      expect(service.isAuthenticated, isFalse);
      expect(service.logs, isEmpty);
      expect(identical(service.dispose(), closing), isTrue);
      expect(backend.closeCalls, 1);
    },
  );
}

const _request = CCNetworkRequest(method: CCNetworkMethod.get, path: '/test');

final class _Backend implements CCNetworkBackend {
  void Function()? onClose;
  final started = Completer<void>();
  final response = Completer<CCNetworkResponse<Object?>>();
  final closing = Completer<void>();
  final closed = Completer<void>();
  int closeCalls = 0;
  @override
  Future<CCNetworkResponse<Object?>> send(CCNetworkRequest request) {
    started.complete();
    return response.future;
  }

  @override
  Future<void> close() {
    closeCalls++;
    onClose?.call();
    closing.complete();
    return closed.future;
  }
}
