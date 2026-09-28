import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_generated.dart' show CCServiceToken;
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:demo_kv_storage/demo_kv_storage.dart';
import 'package:demo_kv_storage/src/storage_service.dart'
    show DemoKeyValueStorageServiceImpl;
import 'package:flutter_test/flutter_test.dart';

import 'package:demo_navigation_lab/src/ccrouter_generated/demo_navigation_lab_component.api.g.dart';

final class _StorageRegistrar implements CCComponentRegistrar {
  const _StorageRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerService<DemoKeyValueStorageService>(
      CCServiceProvider(
        contractToken: const CCServiceToken<DemoKeyValueStorageService>(
          'demo.kv_storage',
        ),
        factory: (_) => DemoKeyValueStorageServiceImpl(),
      ),
    );
  }
}

final class _EmptyRegistrar implements CCComponentRegistrar {
  const _EmptyRegistrar();

  @override
  void register(CCRegistry registry) {}
}

void main() {
  test(
    'generated Service Proxy preserves namespace and caller boundary',
    () async {
      final host = CCRouterTestHost(
        components: const [
          CCComponentManifest(
            id: 'demo_kv_storage_component',
            version: '0.1.0',
            registrar: _StorageRegistrar(),
          ),
          CCComponentManifest(
            id: 'demo_navigation_lab_component',
            version: '0.1.0',
            dependencies: ['demo_kv_storage_component'],
            registrar: _EmptyRegistrar(),
          ),
        ],
      );
      addTearDown(host.dispose);
      host.initialize();

      await host.run(() async {
        const global = DemoStorageNamespace.global();
        final user = DemoStorageNamespace.user('demo-account');
        await DemoNavigationLabServices.demoKeyValueStorage.setBool(
          global,
          'privacy.accepted',
          true,
        );
        await DemoNavigationLabServices.demoKeyValueStorage.setString(
          user,
          'theme',
          'dark',
        );

        expect(
          await DemoNavigationLabServices.demoKeyValueStorage.getBool(
            global,
            'privacy.accepted',
          ),
          isTrue,
        );
        expect(
          await DemoNavigationLabServices.demoKeyValueStorage.getString(
            user,
            'theme',
          ),
          'dark',
        );
        expect(
          await DemoNavigationLabServices.demoKeyValueStorage.getString(
            global,
            'theme',
          ),
          isNull,
        );

        final traces = CCRouter.recentTraces
            .where((trace) => trace.operation == 'service')
            .toList(growable: false);
        expect(traces, isNotEmpty);
        expect(traces.map((trace) => trace.context.callerComponentId).toSet(), {
          'demo_navigation_lab_component',
        });
        expect(traces.map((trace) => trace.context.targetComponentId).toSet(), {
          'demo_kv_storage_component',
        });
      });
    },
  );
}
