import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(CCRouterHost.shutdown);

  test('Host initializes and restarts on VM and JavaScript', () async {
    for (var iteration = 0; iteration < 2; iteration++) {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
      expect(CCRouter.isInitialized, isTrue);

      await CCRouterHost.shutdown();
      expect(CCRouter.isInitialized, isFalse);
    }
  });
}
