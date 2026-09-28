import 'package:ccrouter/ccrouter.dart';
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
    expect(find.text('Catalog'), findsOneWidget);
    expect(find.text('Call Graph'), findsOneWidget);
    expect(find.text('InitTask DAG'), findsOneWidget);
    expect(find.byTooltip('Refresh diagnostics'), findsOneWidget);
  });

  testWidgets('panel links static Catalog records to Runtime and source', (
    tester,
  ) async {
    final provider = CCStaticDevToolsSnapshotProvider(
      CCDevToolsSnapshot(
        capturedAt: DateTime.utc(2026, 1, 1),
        runtimeState: CCDevToolsRuntimeState.initialized,
        catalog: CCDevToolsStaticCatalogSnapshot(
          capturedAt: DateTime.utc(2026, 1, 1),
          components: [
            CCDevToolsCatalogComponent(id: 'orders', version: '1.0.0'),
          ],
          records: [
            CCDevToolsCatalogRecord(
              kind: 'route',
              id: 'orders.detail',
              ownerComponentId: 'orders',
              packageName: 'orders',
              source: const CCDevToolsSourceLocation(
                packageName: 'orders',
                packageUri: 'package:orders/src/detail.dart',
                line: 10,
                column: 2,
              ),
            ),
          ],
        ),
        traces: [
          CCTraceRecord(
            context: CCTraceContextSnapshot.from(
              CCInvocationContext(
                invocationId: 'invocation-1',
                traceId: 'trace-1',
                spanId: 'span-1',
                operation: 'route',
                target: 'orders.detail',
              ),
            ),
            operation: 'route',
            target: 'orders.detail',
            startedAt: DateTime.utc(2026, 1, 1),
            duration: const Duration(microseconds: 4),
            status: 'completed',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(child: CCRouterDevToolsPanel(provider: provider)),
      ),
    );
    await tester.tap(find.text('Catalog'));
    await tester.pumpAndSettle();
    expect(find.text('route · orders.detail'), findsOneWidget);
    await tester.tap(find.text('route · orders.detail'));
    await tester.pump();
    expect(
      find.textContaining('package:orders/src/detail.dart:10:2'),
      findsOneWidget,
    );
    expect(find.text('Runtime: active'), findsOneWidget);
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
