import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Mixin follows current PageRoute and application lifecycle transitions',
    (tester) async {
      final host = CCNavigationHost(id: 'window.mixin');
      final observer = CCGoRouterNavigationObserver(
        hostId: host.id,
        outlet: 'root',
      );
      final rootEvents = <String>[];
      final detailEvents = <String>[];
      BuildContext? rootContext;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        CCRouterApp(
          host: host,
          child: MaterialApp(
            navigatorKey: host.navigatorKey,
            navigatorObservers: [observer],
            home: _MixinLifecyclePage(
              label: 'root',
              events: rootEvents,
              onContext: (context) => rootContext = context,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(rootEvents, ['root:show']);

      final overlay = OverlayEntry(
        builder: (_) =>
            const Positioned(left: 0, top: 0, child: Text('overlay-entry')),
      );
      Overlay.of(rootContext!).insert(overlay);
      await tester.pump();
      expect(rootEvents, ['root:show']);
      overlay.remove();
      await tester.pump();
      expect(rootEvents, ['root:show']);

      final detailResult = host.navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              _MixinLifecyclePage(label: 'detail', events: detailEvents),
        ),
      );
      await tester.pumpAndSettle();
      expect(rootEvents, ['root:show', 'root:hide']);
      expect(detailEvents, ['detail:show']);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(rootEvents, ['root:show', 'root:hide']);
      expect(detailEvents, ['detail:show', 'detail:background']);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(detailEvents, [
        'detail:show',
        'detail:background',
        'detail:foreground',
      ]);

      host.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await detailResult;
      expect(detailEvents.last, 'detail:hide');
      expect(rootEvents.last, 'root:show');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(
        detailEvents.where((event) => event == 'detail:background'),
        hasLength(1),
      );
      expect(rootEvents.last, 'root:background');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
  );

  testWidgets(
    'Listener tracks foreign PopupRoutes and ignores widget rebuilds',
    (tester) async {
      final host = CCNavigationHost(id: 'window.listener');
      final observer = CCGoRouterNavigationObserver(
        hostId: host.id,
        outlet: 'root',
      );
      final events = <String>[];
      final rebuild = ValueNotifier(0);
      BuildContext? pageContext;

      await tester.pumpWidget(
        CCRouterApp(
          host: host,
          child: MaterialApp(
            navigatorKey: host.navigatorKey,
            navigatorObservers: [observer],
            home: CCPageLifecycleListener(
              onPageShow: () => events.add('show'),
              onPageHide: () => events.add('hide'),
              onForeground: () => events.add('foreground'),
              onBackground: () => events.add('background'),
              child: Builder(
                builder: (context) {
                  pageContext = context;
                  return ValueListenableBuilder<int>(
                    valueListenable: rebuild,
                    builder: (_, value, _) => Text('value:$value'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(events, ['show']);

      rebuild.value++;
      await tester.pump();
      expect(events, ['show']);

      final dialog = showDialog<void>(
        context: pageContext!,
        builder: (context) => AlertDialog(
          content: const Text('foreign-dialog'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('close'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(events, ['show', 'hide']);

      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      await dialog;
      expect(events, ['show', 'hide', 'show']);

      CCPageLifecycleHostBridge.setActiveOutlets(
        hostId: host.id,
        outlets: const [],
      );
      expect(events, ['show', 'hide', 'show', 'hide']);
      CCPageLifecycleHostBridge.setActiveOutlets(
        hostId: host.id,
        outlets: const ['root'],
      );
      expect(events, ['show', 'hide', 'show', 'hide', 'show']);

      rebuild.dispose();
    },
  );

  testWidgets('page lifecycle APIs degrade to inert outside CCRouterApp', (
    tester,
  ) async {
    final listenerEvents = <String>[];
    final mixinEvents = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            CCPageLifecycleListener(
              onPageShow: () => listenerEvents.add('show'),
              child: const Text('standalone-listener'),
            ),
            Expanded(
              child: _MixinLifecyclePage(
                label: 'standalone',
                events: mixinEvents,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(listenerEvents, isEmpty);
    expect(mixinEvents, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detached Host releases Routes before the same ID is reused', (
    tester,
  ) async {
    final firstEvents = <String>[];
    final secondEvents = <String>[];

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final firstHost = CCNavigationHost(id: 'window.reused');
    await tester.pumpWidget(
      CCRouterApp(
        host: firstHost,
        child: MaterialApp(
          navigatorKey: firstHost.navigatorKey,
          navigatorObservers: [
            CCGoRouterNavigationObserver(hostId: firstHost.id, outlet: 'root'),
          ],
          home: CCPageLifecycleListener(
            onPageShow: () => firstEvents.add('show'),
            onBackground: () => firstEvents.add('background'),
            child: const Text('first-host'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(firstEvents, ['show']);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final firstEventsAfterDetach = List<String>.of(firstEvents);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final secondHost = CCNavigationHost(id: 'window.reused');
    await tester.pumpWidget(
      CCRouterApp(
        host: secondHost,
        child: MaterialApp(
          navigatorKey: secondHost.navigatorKey,
          navigatorObservers: [
            CCGoRouterNavigationObserver(hostId: secondHost.id, outlet: 'root'),
          ],
          home: CCPageLifecycleListener(
            onPageShow: () => secondEvents.add('show'),
            onBackground: () => secondEvents.add('background'),
            child: const Text('second-host'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(secondEvents, ['show']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(firstEvents, firstEventsAfterDetach);
    expect(secondEvents, ['show', 'background']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });
}

final class _MixinLifecyclePage extends StatefulWidget {
  const _MixinLifecyclePage({
    required this.label,
    required this.events,
    this.onContext,
  });

  final String label;
  final List<String> events;
  final ValueChanged<BuildContext>? onContext;

  @override
  State<_MixinLifecyclePage> createState() => _MixinLifecyclePageState();
}

final class _MixinLifecyclePageState extends State<_MixinLifecyclePage>
    with CCPageLifecycleMixin<_MixinLifecyclePage> {
  @override
  void onPageShow() => widget.events.add('${widget.label}:show');

  @override
  void onPageHide() => widget.events.add('${widget.label}:hide');

  @override
  void onForeground() => widget.events.add('${widget.label}:foreground');

  @override
  void onBackground() => widget.events.add('${widget.label}:background');

  @override
  Widget build(BuildContext context) {
    widget.onContext?.call(context);
    return Scaffold(body: Text(widget.label));
  }
}
