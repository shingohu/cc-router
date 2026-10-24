import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_devtools/ccrouter_devtools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'provider replacement releases the old source even with value equality',
    (tester) async {
      final first = _EqualProvider();
      final second = _EqualProvider();
      expect(first == second, isTrue);
      await tester.pumpWidget(
        MaterialApp(home: CCRouterDevToolsPanel(provider: first)),
      );
      expect(first.listeners, 1);
      await tester.pumpWidget(
        MaterialApp(home: CCRouterDevToolsPanel(provider: second)),
      );
      expect(first.listeners, 0);
      expect(second.listeners, 1);
      await tester.pumpWidget(const SizedBox());
      expect(second.listeners, 0);
    },
  );

  testWidgets(
    'failures show placement, cancellation and recovery selection distinctly',
    (tester) async {
      final snapshot = CCRouterDevToolsSnapshot(
        capturedAt: DateTime.utc(2026),
        runtimeState: CCDevToolsRuntimeState.initialized,
        navigationFailures: [
          for (final recovered in [false, true])
            CCNavigationFailureEvent(
              context: CCNavigationFailureContext(
                navigationId: 'nav-$recovered',
                operation: CCNavigationOperation.push,
                origin: CCNavigationOrigin.internal,
                openMode: null,
                stage: CCNavigationFailureStage.interception,
                errorType: recovered
                    ? 'CCNavigationInterceptorError'
                    : 'CCRouteCancelledError',
                reason: recovered
                    ? CCNavigationFailureReason.interceptorFailed
                    : CCNavigationFailureReason.cancelled,
                attempt: CCNavigationFailureAttempt.pendingResume,
                recoveryDepth: 1,
                hostId: 'right',
                outlet: 'detail',
                routeId: 'orders.detail',
                initialRouteId: 'orders.start',
              ),
              timestamp: DateTime.utc(2026),
              recovered: recovered,
            ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CCRouterDevToolsPanel(
            provider: CCStaticDevToolsSnapshotProvider(snapshot),
          ),
        ),
      );
      final tab = find.widgetWithText(Tab, 'Failures');
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(find.textContaining('right/detail'), findsNWidgets(2));
      expect(
        find.textContaining(
          'attempt=pendingResume · depth=1 · initial=orders.start',
        ),
        findsNWidgets(2),
      );
      expect(find.textContaining('recovery selected'), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden panel suspends observation and resumes with a fresh snapshot',
    (tester) async {
      final provider = _CountingProvider();
      final enabled = ValueNotifier(true);
      addTearDown(enabled.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (_, value, _) => TickerMode(
              enabled: value,
              child: CCRouterDevToolsPanel(provider: provider),
            ),
          ),
        ),
      );
      expect(provider.listeners, 1);
      enabled.value = false;
      await tester.pump();
      expect(provider.listeners, 0);
      provider.value = CCRouterDevToolsSnapshot(
        capturedAt: DateTime.utc(2026),
        runtimeState: CCDevToolsRuntimeState.initialized,
      );
      enabled.value = true;
      await tester.pump();
      expect(provider.listeners, 1);
      expect(find.textContaining('Runtime initialized'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(provider.listeners, 0);
    },
  );

  testWidgets('small panel explains disabled retention and Sink losses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = CCStaticDevToolsSnapshotProvider(
      CCRouterDevToolsSnapshot(
        capturedAt: DateTime.utc(2026),
        runtimeState: CCDevToolsRuntimeState.initialized,
        diagnosticHealth: CCDiagnosticSnapshot(
          runtimeId: 'fixture',
          revision: 1,
          sinkConfigured: true,
          delivery: const CCDiagnosticDeliverySnapshot(
            queueCapacity: 4,
            queuedEventCount: 2,
            inFlightWriteCount: 1,
            peakQueueDepth: 4,
            deliveredEventCount: 3,
            failedEventCount: 1,
            droppedEventCount: 5,
            isClosed: false,
          ),
          histories: [
            const CCDiagnosticHistorySnapshot(
              name: 'failures',
              capacity: 0,
              retainedCount: 0,
              omittedCount: 8,
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CCRouterDevToolsPanel(provider: provider)),
    );
    await tester.scrollUntilVisible(
      find.textContaining('retained=0/0'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(TabBarView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('failures · retention disabled'), findsOneWidget);
    expect(find.text('retained=0/0 · omitted=8'), findsOneWidget);
    expect(find.textContaining('dropped=5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel renders tabs and remains read-only for empty Runtime', (
    tester,
  ) async {
    final provider = CCStaticDevToolsSnapshotProvider(
      CCRouterDevToolsSnapshot.empty(),
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
      CCRouterDevToolsSnapshot(
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
      CCRouterDevToolsSnapshot.empty(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(child: CCRouterDevToolsPanel(provider: provider)),
      ),
    );
    provider.value = CCRouterDevToolsSnapshot(
      capturedAt: DateTime.utc(2026, 1, 1),
      runtimeState: CCDevToolsRuntimeState.initialized,
    );

    await tester.tap(find.byTooltip('Refresh diagnostics'));
    await tester.pump();

    expect(find.textContaining('Runtime initialized'), findsOneWidget);
  });
}

final class _CountingProvider implements CCDevToolsSnapshotProvider {
  var value = CCRouterDevToolsSnapshot.empty();
  var listeners = 0;
  @override
  CCRouterDevToolsSnapshot snapshot() => value;
  @override
  void Function() addListener(VoidCallback listener) {
    listeners++;
    var removed = false;
    return () {
      if (removed) return;
      removed = true;
      listeners--;
    };
  }
}

final class _EqualProvider extends _CountingProvider {
  @override
  bool operator ==(Object other) => other is _EqualProvider;
  @override
  int get hashCode => 0;
}
