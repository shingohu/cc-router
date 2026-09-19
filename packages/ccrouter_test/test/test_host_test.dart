import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:test/test.dart';

void main() {
  test('test host owns an isolated Runtime and disposes its adapter', () async {
    final adapter = CCMemoryNavigationAdapter();
    final host = CCRouterTestHost(navigationAdapter: adapter);
    addTearDown(host.dispose);

    expect(host.isInitialized, isFalse);
    host.initialize();

    expect(host.isInitialized, isTrue);
    expect(adapter.isInitialized, isTrue);
    expect(host.runtime.isInitialized, isTrue);

    await host.dispose();
    await host.dispose();

    expect(host.isInitialized, isFalse);
    expect(adapter.isInitialized, isFalse);
  });

  test('test host rejects initialization after disposal', () async {
    final host = CCRouterTestHost();
    await host.dispose();

    expect(() => host.initialize(), throwsA(isA<StateError>()));
  });
}
