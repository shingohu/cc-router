import 'package:ccrouter_demo/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('initializes CCRouter and executes the demo Command', (
    tester,
  ) async {
    await tester.pumpWidget(const CCRouterDemoApp());
    await tester.pump();

    expect(find.text('Runtime 已初始化'), findsOneWidget);
    expect(find.text('开启 Session'), findsOneWidget);

    await tester.tap(find.text('开启 Session'));
    await tester.pump();
    expect(find.text('关闭 Session'), findsOneWidget);

    await tester.tap(find.text('调用 CreateOrder Command'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('订单已创建：¥100'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
