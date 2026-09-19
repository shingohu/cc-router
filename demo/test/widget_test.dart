import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_demo/ccrouter_generated/ccrouter_host.routes.g.dart';
import 'package:ccrouter_demo/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    CCRouter.initialize(components: ccrouterGeneratedComponentManifests);
  });
  tearDown(CCRouter.shutdown);

  testWidgets('initializes CCRouter and opens the order route', (tester) async {
    await tester.pumpWidget(const CCRouterDemoApp());
    await tester.pump();

    expect(find.text('Runtime 已初始化'), findsOneWidget);
    expect(find.text('开启 Session'), findsOneWidget);

    await tester.tap(find.text('开启 Session'));
    await tester.pump();
    expect(find.text('关闭 Session'), findsOneWidget);

    await tester.tap(find.text('打开订单详情'));
    await tester.pumpAndSettle();
    expect(find.text('订单 #100'), findsOneWidget);
    expect(find.text('当前标签：items'), findsOneWidget);
    await tester.tap(find.text('确认订单'));
    await tester.pumpAndSettle();
    expect(find.text('confirmed:100'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
