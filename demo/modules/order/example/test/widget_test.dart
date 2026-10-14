import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_order_example/main.dart';
import 'package:demo_order_example/src/ccrouter_generated/ccrouter_host.api.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
    await CCRouterHost.runInitTasks(gate: CCInitTaskGate.appStarted);
  });

  tearDown(CCRouterHost.shutdown);

  testWidgets('opens the generated Order Route and receives its result', (
    tester,
  ) async {
    await tester.pumpWidget(const OrderExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Order component'), findsOneWidget);
    await tester.tap(find.text('Open order #1001'));
    await tester.pumpAndSettle();

    expect(find.text('订单 #1001'), findsOneWidget);
    expect(find.text('当前标签：summary'), findsOneWidget);
    await tester.tap(find.text('确认订单'));
    await tester.pumpAndSettle();

    expect(find.text('Order result: confirmed:1001'), findsOneWidget);
  });
}
