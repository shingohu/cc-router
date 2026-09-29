import 'dart:math';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_demo/main.dart';
import 'package:ccrouter_demo/platform_deep_link_bridge.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _seeds = <int>[20260928, 0xCC2026, 314159];
const _stepsPerSeed = 120;

void main() {
  setUp(() async {
    demoNavigationLabStore
      ..blockDetailGlobally = false
      ..dirtyForm = true
      ..allowDeferredOnce = false
      ..clear();
    demoDiagnosticsSink.clear();
    demoApplicationLogger.clear();
    CCRouter.initialize(
      components: ccrouterGeneratedComponentManifests,
      contractBundle: ccrouterGeneratedHostAssembly.contractBundle,
      deepLinkIngressPolicy: demoDeepLinkIngressPolicy,
      globalInterceptors: const [
        CCGlobalNavigationInterceptor(
          id: DemoHostIds.globalNavigationInterceptor,
          interceptor: DemoGlobalNavigationInterceptor(),
        ),
      ],
      navigationFailurePolicy: const DemoNavigationFailurePolicy(),
      navigationAspects: [
        demoNavigationAspect,
        demoNavigationAnalytics.createAspect(),
      ],
      telemetryContextProvider: const DemoNavigationTelemetryProvider(),
      diagnostics: CCDiagnosticsConfig(
        sink: demoDiagnosticsSink,
        defaultMinimumLevel: CCDiagnosticLevel.debug,
      ),
    );
    await CCRouter.runInitTasks();
  });

  tearDown(CCRouter.shutdown);

  testWidgets('PopGuard remains usable in a small desktop window', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view
      ..physicalSize = const Size(980, 700)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const CCRouterDemoApp(listenForPlatformLinks: false),
    );
    await tester.pumpAndSettle();
    CCRouter.navigator.open(Uri.parse('/lab/policy/guarded')).ignore();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('模拟系统返回'));
    await tester.pumpAndSettle();

    expect(find.text('PopGuard'), findsOneWidget);
    expect(find.text('模拟系统返回').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await CCRouter.shutdown();
  });

  testWidgets('failure fallback remains usable in a small desktop window', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view
      ..physicalSize = const Size(980, 700)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const CCRouterDemoApp(listenForPlatformLinks: false),
    );
    await tester.pumpAndSettle();
    CCRouter.navigator.open(Uri.parse('/lab/not-found')).ignore();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('返回'));
    await tester.pumpAndSettle();

    expect(find.text('导航兜底'), findsOneWidget);
    expect(find.text('原目标不可用'), findsOneWidget);
    expect(find.text('返回').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await CCRouter.shutdown();
  });

  for (final seed in _seeds) {
    testWidgets(
      'semantic monkey remains consistent for seed $seed',
      (tester) async {
        final runner = _SemanticMonkey(tester: tester, seed: seed);
        await runner.mount();
        await runner.run(_stepsPerSeed);
        await runner.unmount();
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}

final class _SemanticMonkey {
  _SemanticMonkey({required this.tester, required this.seed})
    : _random = Random(seed);

  static const _tabs = <String>['总览', '导航', '策略', '展示', '生命周期', '诊断'];
  static const _sizes = <Size>[
    Size(720, 620),
    Size(960, 720),
    Size(1280, 900),
    Size(1540, 960),
  ];

  final WidgetTester tester;
  final int seed;
  final Random _random;
  final List<String> _history = <String>[];

  Future<void> mount() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view
      ..physicalSize = _sizes[2]
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const CCRouterDemoApp(listenForPlatformLinks: false),
    );
    await tester.pumpAndSettle();
    _assertInvariants(step: -1);
  }

  Future<void> run(int steps) async {
    for (var step = 0; step < steps; step += 1) {
      await _perform(step);
      await _settle(step);
      _assertNoFlutterException(step);
      _assertInvariants(step: step);
    }
  }

  Future<void> unmount() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    _record('unmount');
    await CCRouter.shutdown();
    await tester.pump();
    _record('shutdown');
    _assertNoFlutterException(_stepsPerSeed);
    expect(
      CCRouter.isInitialized,
      isFalse,
      reason: _failureContext(
        _stepsPerSeed,
        'Runtime remained initialized after shutdown',
      ),
    );
  }

  Future<void> _perform(int step) async {
    final roll = _random.nextInt(100);
    if (roll < 12) {
      await _systemBack();
      return;
    }
    if (roll < 24) {
      await _selectTab();
      return;
    }
    if (roll < 32) {
      await _resize();
      return;
    }
    if (roll < 42) {
      await _scroll();
      return;
    }
    if (await _tapRandomControl()) return;
    _record('step=$step fallback:systemBack');
    await _systemBack();
  }

  Future<bool> _tapRandomControl() async {
    final elements = <Element>{
      ...find
          .byWidgetPredicate(
            (widget) => widget is ListTile && widget.onTap != null,
          )
          .hitTestable()
          .evaluate(),
      ...find
          .byWidgetPredicate(
            (widget) => widget is ButtonStyleButton && widget.onPressed != null,
          )
          .hitTestable()
          .evaluate(),
      ...find
          .byWidgetPredicate(
            (widget) => widget is IconButton && widget.onPressed != null,
          )
          .hitTestable()
          .evaluate(),
      ...find
          .byWidgetPredicate(
            (widget) => widget is Switch && widget.onChanged != null,
          )
          .hitTestable()
          .evaluate(),
      ...find
          .byWidgetPredicate(
            (widget) => widget is BackButton || widget is CloseButton,
          )
          .hitTestable()
          .evaluate(),
    }.toList(growable: false);
    if (elements.isEmpty) return false;
    final element = elements[_random.nextInt(elements.length)];
    final target = find.byElementPredicate((candidate) => candidate == element);
    _record('tap:${_labelFor(element)}');
    await tester.tap(target);
    return true;
  }

  Future<void> _systemBack() async {
    final handled = await tester.binding.handlePopRoute();
    _record('systemBack:$handled');
  }

  Future<void> _selectTab() async {
    final navigation = find.byWidgetPredicate(
      (widget) => widget is NavigationBar || widget is NavigationRail,
    );
    final visibleTabs = <Finder>[
      for (final label in _tabs)
        if (find
            .descendant(of: navigation, matching: find.text(label))
            .hitTestable()
            .evaluate()
            .isNotEmpty)
          find
              .descendant(of: navigation, matching: find.text(label))
              .hitTestable(),
    ];
    if (visibleTabs.isEmpty) {
      await _systemBack();
      return;
    }
    final target = visibleTabs[_random.nextInt(visibleTabs.length)];
    _record('tab:${(target.evaluate().first.widget as Text).data}');
    await tester.tap(target);
  }

  Future<void> _resize() async {
    final size = _sizes[_random.nextInt(_sizes.length)];
    tester.view.physicalSize = size;
    _record('resize:${size.width.toInt()}x${size.height.toInt()}');
    await tester.pump();
  }

  Future<void> _scroll() async {
    final scrollables = find.byType(Scrollable).hitTestable();
    final count = scrollables.evaluate().length;
    if (count == 0) {
      _record('scroll:none');
      return;
    }
    final target = scrollables.at(_random.nextInt(count));
    final down = _random.nextBool();
    _record('scroll:${down ? 'down' : 'up'}');
    await tester.drag(target, Offset(0, down ? -320 : 320));
  }

  Future<void> _settle(int step) async {
    try {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 8),
      );
    } on FlutterError catch (error) {
      fail(_failureContext(step, 'pumpAndSettle failed: $error'));
    }
  }

  void _assertNoFlutterException(int step) {
    final errors = <Object>[];
    Object? error;
    while ((error = tester.takeException()) != null) {
      errors.add(error!);
    }
    expect(
      errors,
      isEmpty,
      reason: _failureContext(step, 'Flutter exception: $errors'),
    );
  }

  void _assertInvariants({required int step}) {
    final routes = CCRouter.activeRouteEntries;
    final routeEntryIds = routes
        .map((entry) => entry.routeEntryId)
        .toList(growable: false);
    expect(
      routeEntryIds.toSet(),
      hasLength(routeEntryIds.length),
      reason: _failureContext(step, 'Duplicate managed Route Entry identity'),
    );
    for (final entry in routes) {
      expect(
        entry.hostId,
        isNotEmpty,
        reason: _failureContext(step, 'Managed entry without Host'),
      );
      expect(
        entry.placement.navigatorOutlet,
        isNotEmpty,
        reason: _failureContext(step, 'Managed entry without Outlet'),
      );
      expect(
        entry.lifecycleState,
        isNot(
          anyOf(
            CCRouteEntryLifecycleState.removed,
            CCRouteEntryLifecycleState.disposed,
          ),
        ),
        reason: _failureContext(step, 'Terminal entry retained as active'),
      );
    }

    final backend = CCRouter.activeBackendEntries;
    final backendEntryIds = backend
        .map((entry) => entry.backendEntryId)
        .toList(growable: false);
    expect(
      backendEntryIds.toSet(),
      hasLength(backendEntryIds.length),
      reason: _failureContext(step, 'Duplicate backend Entry identity'),
    );
    for (final entry in backend) {
      expect(
        entry.navigatorOutlet,
        isNotEmpty,
        reason: _failureContext(step, 'Backend entry without Outlet'),
      );
      expect(
        entry.lifecycleState,
        isNot(CCBackendEntryLifecycleState.removed),
        reason: _failureContext(
          step,
          'Removed backend entry retained as active',
        ),
      );
    }
  }

  String _labelFor(Element element) {
    final labels = <String>[];
    void collect(Element child) {
      final widget = child.widget;
      if (widget is Text && widget.data != null) labels.add(widget.data!);
      child.visitChildren(collect);
    }

    collect(element);
    return labels.isEmpty
        ? element.widget.runtimeType.toString()
        : labels.take(2).join('|');
  }

  void _record(String action) {
    _history.add(action);
    if (_history.length > 30) _history.removeAt(0);
  }

  String _failureContext(int step, String message) =>
      '$message\nseed=$seed step=$step\nrecent actions:\n'
      '${_history.join('\n')}';
}
