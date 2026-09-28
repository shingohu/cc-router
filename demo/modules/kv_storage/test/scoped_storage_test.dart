import 'package:demo_kv_storage/demo_kv_storage.dart';
import 'package:test/test.dart';

import 'package:demo_kv_storage/src/storage_service.dart'
    show DemoKeyValueStorageServiceImpl;

void main() {
  test('scoped facade resolves the latest account and environment', () async {
    final service = DemoKeyValueStorageServiceImpl();
    addTearDown(service.dispose);
    final context = DemoMutableStorageContextProvider(
      const DemoStorageContextSnapshot(
        environmentId: 'development',
        deviceId: 'device-1',
        accountId: 'account-1',
      ),
    );
    final storage = DemoScopedStorage(
      service: service,
      contextProvider: context,
    );

    await storage.global.setBool('privacy.accepted', true);
    await storage.currentUser.setString('theme', 'dark');
    await storage.currentEnvironment.setString('apiMode', 'v2');
    expect(await storage.global.getBool('privacy.accepted'), isTrue);
    expect(await storage.currentUser.getString('theme'), 'dark');

    context.update(
      const DemoStorageContextSnapshot(
        environmentId: 'production',
        deviceId: 'device-1',
        accountId: 'account-2',
      ),
    );
    expect(await storage.currentUser.getString('theme'), isNull);
    expect(await storage.currentEnvironment.getString('apiMode'), isNull);
    await storage.currentUser.setString('theme', 'light');
    expect(await storage.currentUser.getString('theme'), 'light');
    expect(await storage.global.getBool('privacy.accepted'), isTrue);
  });

  test('current user scope fails when the context is a guest', () async {
    final service = DemoKeyValueStorageServiceImpl();
    addTearDown(service.dispose);
    final storage = DemoScopedStorage(
      service: service,
      contextProvider: DemoMutableStorageContextProvider(
        const DemoStorageContextSnapshot(
          environmentId: 'development',
          deviceId: 'device-1',
        ),
      ),
    );

    expect(
      () => storage.currentUser.getString('theme'),
      throwsA(isA<DemoStorageContextError>()),
    );
  });
}
