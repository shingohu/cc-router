import 'package:ccrouter_devtools/ccrouter_devtools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('panel renders tabs and remains read-only for empty Runtime', (
    tester,
  ) async {
    final provider = CCStaticDevToolsSnapshotProvider(
      CCDevToolsSnapshot.empty(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(child: CCRouterDevToolsPanel(provider: provider)),
      ),
    );

    expect(find.text('CCRouter DevTools'), findsOneWidget);
    expect(find.text('没有活动 Runtime。面板保持只读，不会自动初始化框架。'), findsOneWidget);
    expect(find.text('Components'), findsOneWidget);
    expect(find.text('InitTask DAG'), findsOneWidget);
    expect(find.byTooltip('Refresh diagnostics'), findsOneWidget);
  });

  testWidgets('panel refreshes from a static test snapshot', (tester) async {
    final provider = CCStaticDevToolsSnapshotProvider(
      CCDevToolsSnapshot.empty(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(child: CCRouterDevToolsPanel(provider: provider)),
      ),
    );
    provider.value = CCDevToolsSnapshot(
      capturedAt: DateTime.utc(2026, 1, 1),
      runtimeState: CCDevToolsRuntimeState.initialized,
    );

    await tester.tap(find.byTooltip('Refresh diagnostics'));
    await tester.pump();

    expect(find.textContaining('Runtime initialized'), findsOneWidget);
  });
}
