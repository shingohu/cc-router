import 'dart:async';
import 'dart:math' as math;

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_demo/demo_router_backend.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:demo_navigation_lab/demo_navigation_lab_host.dart';
import 'package:flutter/material.dart';

import 'platform_deep_link_bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CCRouter.initialize(
    hostAssembly: ccrouterGeneratedHostAssembly,
    deepLinkIngressPolicy: demoDeepLinkIngressPolicy,
  );
  runApp(createMultiHostDemoApp());
}

Widget createMultiHostDemoApp() => _MultiHostDemoApp(
  backend: CCGoRouterMultiHostBackend.managed(
    defaultHostId: _primaryHostId,
    hostFactories: {
      _primaryHostId: (configuration) => createDemoRouterBackend(
        catalog: configuration.catalog,
        hostId: configuration.hostId,
      ),
      _secondaryHostId: (configuration) => createDemoRouterBackend(
        catalog: configuration.catalog,
        hostId: configuration.hostId,
      ),
    },
  ),
);

const _primaryHostId = 'host.primary';
const _secondaryHostId = 'host.secondary';

final class _MultiHostDemoApp extends StatelessWidget {
  const _MultiHostDemoApp({required this.backend});

  final CCGoRouterMultiHostBackend backend;

  @override
  Widget build(BuildContext context) => CCRouterApp.managed(
    backend: backend,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CCRouter Multi Host Lab',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
        useMaterial3: true,
      ),
      home: _MultiHostWorkspace(backend: backend),
    ),
  );
}

final class _MultiHostWorkspace extends StatefulWidget {
  const _MultiHostWorkspace({required this.backend});

  final CCGoRouterMultiHostBackend backend;

  @override
  State<_MultiHostWorkspace> createState() => _MultiHostWorkspaceState();
}

final class _MultiHostWorkspaceState extends State<_MultiHostWorkspace> {
  _HostLabMode _mode = _HostLabMode.isolation;
  String _status = '选择 Host 后执行类型安全导航';

  bool _activateHost(String hostId) {
    if (widget.backend.adapter.activeHostId == hostId) return false;
    widget.backend.adapter.activateHost(hostId);
    return true;
  }

  void _activateHostFromInteraction(String hostId) {
    if (!_activateHost(hostId)) return;
    setState(() => _status = '$hostId · active');
  }

  Future<void> _navigate(String hostId, int level) async {
    _activateHost(hostId);
    setState(() => _status = '$hostId · navigating');
    await CCRouter.navigator.go(demoStackIntent(level: level));
    if (mounted) setState(() => _status = '$hostId · /lab/stack/$level');
  }

  Future<void> _home(String hostId) async {
    _activateHost(hostId);
    await CCRouter.navigator.go(demoHomeIntent());
    if (mounted) setState(() => _status = '$hostId · /');
  }

  void _selectMode(Set<_HostLabMode> selection) {
    final mode = selection.single;
    if (mode == _HostLabMode.adaptive) {
      _activateHost(_primaryHostId);
    }
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Host & Adaptive Layout Lab')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentedButton<_HostLabMode>(
            segments: const [
              ButtonSegment(
                value: _HostLabMode.isolation,
                icon: Icon(Icons.call_split_outlined),
                label: Text('Host 隔离'),
              ),
              ButtonSegment(
                value: _HostLabMode.adaptive,
                icon: Icon(Icons.view_sidebar_outlined),
                label: Text('自适应布局'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _selectMode,
          ),
        ),
        Expanded(
          child: switch (_mode) {
            _HostLabMode.isolation => _buildIsolationView(),
            _HostLabMode.adaptive => _AdaptiveHostView(
              host: widget.backend.hostFor(_primaryHostId),
              registry: widget.backend.adapter,
            ),
          },
        ),
      ],
    ),
  );

  Widget _buildIsolationView() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(_status, key: const ValueKey('host-isolation-status')),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panes = <Widget>[
              Expanded(
                child: _HostPane(
                  key: const ValueKey('host.primary'),
                  title: 'Primary Host',
                  hostId: _primaryHostId,
                  router: widget.backend.routerFor(_primaryHostId),
                  isActive:
                      widget.backend.adapter.activeHostId == _primaryHostId,
                  onActivate: () =>
                      _activateHostFromInteraction(_primaryHostId),
                  onNavigate: () => unawaited(_navigate(_primaryHostId, 101)),
                  onHome: () => unawaited(_home(_primaryHostId)),
                ),
              ),
              Expanded(
                child: _HostPane(
                  key: const ValueKey('host.secondary'),
                  title: 'Secondary Host',
                  hostId: _secondaryHostId,
                  router: widget.backend.routerFor(_secondaryHostId),
                  host: widget.backend.hostFor(_secondaryHostId),
                  isActive:
                      widget.backend.adapter.activeHostId == _secondaryHostId,
                  onActivate: () =>
                      _activateHostFromInteraction(_secondaryHostId),
                  onNavigate: () => unawaited(_navigate(_secondaryHostId, 202)),
                  onHome: () => unawaited(_home(_secondaryHostId)),
                ),
              ),
            ];
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: constraints.maxWidth < 900 ? 900 : constraints.maxWidth,
                height: constraints.maxHeight,
                child: Row(children: panes),
              ),
            );
          },
        ),
      ),
    ],
  );
}

enum _HostLabMode { isolation, adaptive }

final class _AdaptiveHostView extends StatefulWidget {
  const _AdaptiveHostView({required this.host, required this.registry});

  final CCNavigationHost host;
  final CCMultiHostNavigationAdapter registry;

  @override
  State<_AdaptiveHostView> createState() => _AdaptiveHostViewState();
}

final class _AdaptiveHostViewState extends State<_AdaptiveHostView> {
  static final _outletPolicy = CCAdaptiveOutletPolicy(
    primaryOutlet: demoAdaptiveListOutlet,
    secondaryOutlet: demoAdaptiveDetailOutlet,
  );

  bool _simulateHinge = false;
  bool _showCompactDetail = false;
  int _selectedItem = 1;
  String? _lastMetricsSignature;
  CCHostLayoutMetrics? _pendingMetrics;
  CCAdaptiveHostLayoutSnapshot? _layout;
  bool _layoutUpdateScheduled = false;

  void _scheduleLayoutUpdate(CCHostLayoutMetrics metrics) {
    final signature = <Object>[
      metrics.hostId,
      metrics.width.round(),
      metrics.height.round(),
      _simulateHinge,
    ].join(':');
    if (signature == _lastMetricsSignature) return;
    _lastMetricsSignature = signature;
    _pendingMetrics = metrics;
    if (_layoutUpdateScheduled) return;
    _layoutUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutUpdateScheduled = false;
      if (!mounted) return;
      final pending = _pendingMetrics;
      if (pending == null) return;
      final layout = widget.registry.updateHostLayout(
        pending,
        layoutPolicy: CCAdaptiveLayoutPolicy(
          compact: pending.hasSeparatingFeature
              ? CCAdaptiveLayoutKind.splitPane
              : CCAdaptiveLayoutKind.singlePane,
          medium: CCAdaptiveLayoutKind.splitPane,
          expanded: CCAdaptiveLayoutKind.splitPane,
        ),
        outletPolicy: _outletPolicy,
      );
      if (mounted) setState(() => _layout = layout);
    });
  }

  void _toggleHinge(bool value) {
    setState(() {
      _simulateHinge = value;
      _lastMetricsSignature = null;
    });
  }

  void _selectItem(int item, {required bool compact}) {
    setState(() {
      _selectedItem = item;
      _showCompactDetail = compact;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final features = _simulateHinge
          ? <CCDisplayFeature>[
              CCDisplayFeature(
                type: CCDisplayFeatureType.hinge,
                bounds: CCLayoutRect(
                  left: width / 2 - 6,
                  top: 0,
                  width: 12,
                  height: height,
                ),
                separating: true,
              ),
            ]
          : const <CCDisplayFeature>[];
      final metrics = CCHostLayoutMetrics(
        hostId: widget.host.id,
        width: width,
        height: height,
        displayFeatures: features,
      );
      _scheduleLayoutUpdate(metrics);
      final split =
          _layout?.layout == CCAdaptiveLayoutKind.splitPane ||
          metrics.sizeClass != CCHostSizeClass.compact ||
          metrics.hasSeparatingFeature;
      final orientation = width >= height ? '横向' : '纵向';
      final activeOutlets = split
          ? '$demoAdaptiveListOutlet + $demoAdaptiveDetailOutlet'
          : demoAdaptiveListOutlet;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '同一 Host：${widget.host.id}',
                  key: const ValueKey('adaptive-host-id'),
                ),
                Text(
                  '${width.round()} x ${height.round()} · $orientation · '
                  '${metrics.sizeClass.name}',
                  key: const ValueKey('adaptive-metrics'),
                ),
                Text(
                  'Active Outlet：$activeOutlets',
                  key: const ValueKey('adaptive-active-outlets'),
                ),
              ],
            ),
          ),
          SwitchListTile(
            key: const ValueKey('simulate-hinge'),
            value: _simulateHinge,
            onChanged: _toggleHinge,
            title: const Text('模拟折叠屏 separating hinge'),
            subtitle: Text(
              _simulateHinge
                  ? '1 个 Display Feature，同一 Host 切换为双 Outlet'
                  : '调整窗口大小或设备方向，Host ID 保持不变',
              key: const ValueKey('adaptive-display-features'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: split
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      const minimumSplitWidth = 600.0;
                      final splitWidth =
                          constraints.maxWidth < minimumSplitWidth
                          ? minimumSplitWidth
                          : constraints.maxWidth;
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: splitWidth,
                          height: constraints.maxHeight,
                          child: Row(
                            children: [
                              Expanded(
                                child: _AdaptiveOutletNavigator(
                                  navigatorKey: widget.host.navigatorKeyFor(
                                    demoAdaptiveListOutlet,
                                  ),
                                  pageKey: 'adaptive-list',
                                  child: _AdaptiveListPane(
                                    selectedItem: _selectedItem,
                                    onSelected: (item) =>
                                        _selectItem(item, compact: false),
                                  ),
                                ),
                              ),
                              if (_simulateHinge)
                                Container(
                                  key: const ValueKey('adaptive-hinge'),
                                  width: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                )
                              else
                                const VerticalDivider(width: 1),
                              Expanded(
                                child: _AdaptiveOutletNavigator(
                                  navigatorKey: widget.host.navigatorKeyFor(
                                    demoAdaptiveDetailOutlet,
                                  ),
                                  pageKey: 'adaptive-detail',
                                  child: _AdaptiveDetailPane(
                                    item: _selectedItem,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                : _AdaptiveOutletNavigator(
                    navigatorKey: widget.host.navigatorKeyFor(
                      demoAdaptiveListOutlet,
                    ),
                    pageKey: 'adaptive-compact',
                    child: _showCompactDetail
                        ? _AdaptiveDetailPane(
                            item: _selectedItem,
                            outletName: demoAdaptiveListOutlet,
                            onBack: () =>
                                setState(() => _showCompactDetail = false),
                          )
                        : _AdaptiveListPane(
                            selectedItem: _selectedItem,
                            onSelected: (item) =>
                                _selectItem(item, compact: true),
                          ),
                  ),
          ),
        ],
      );
    },
  );
}

final class _AdaptiveOutletNavigator extends StatelessWidget {
  const _AdaptiveOutletNavigator({
    required this.navigatorKey,
    required this.pageKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final String pageKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    pages: [MaterialPage<void>(key: ValueKey(pageKey), child: child)],
    onDidRemovePage: (_) {},
  );
}

final class _AdaptiveListPane extends StatelessWidget {
  const _AdaptiveListPane({
    required this.selectedItem,
    required this.onSelected,
  });

  final int selectedItem;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('adaptive-list-pane'),
    color: Theme.of(context).colorScheme.surface,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 240;
        return ListView(
          padding: EdgeInsets.all(compact ? 8 : 16),
          children: [
            Text(
              'List Outlet · $demoAdaptiveListOutlet',
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (var item = 1; item <= 5; item++)
              ListTile(
                selected: selectedItem == item,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: compact ? 4 : 16,
                ),
                leading: compact ? null : const Icon(Icons.article_outlined),
                title: Text(
                  'Item $item',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: compact ? null : const Icon(Icons.chevron_right),
                onTap: () => onSelected(item),
              ),
          ],
        );
      },
    ),
  );
}

final class _AdaptiveDetailPane extends StatelessWidget {
  const _AdaptiveDetailPane({
    required this.item,
    this.outletName = demoAdaptiveDetailOutlet,
    this.onBack,
  });

  final int item;
  final String outletName;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('adaptive-detail-pane'),
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 320 ? 12.0 : 24.0;
        return SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, constraints.maxHeight - padding * 2),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onBack != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: '返回列表',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                  const Icon(Icons.description_outlined, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    'Detail View · $outletName',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Item $item',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

final class _HostPane extends StatelessWidget {
  const _HostPane({
    super.key,
    required this.title,
    required this.hostId,
    required this.router,
    required this.isActive,
    required this.onActivate,
    required this.onNavigate,
    required this.onHome,
    this.host,
  });

  final String title;
  final String hostId;
  final GoRouter router;
  final CCNavigationHost? host;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onNavigate;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final routerView = Router.withConfig(config: router);
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) onActivate();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => onActivate(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: isActive ? colorScheme.primary : colorScheme.outline,
                width: isActive ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: [
                Material(
                  color: colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(child: Text('$title · $hostId')),
                        SizedBox.square(
                          dimension: 24,
                          child: isActive
                              ? Tooltip(
                                  message: '当前活动 Host',
                                  child: Icon(
                                    Icons.radio_button_checked,
                                    key: ValueKey('$hostId-active'),
                                    size: 18,
                                    color: colorScheme.primary,
                                  ),
                                )
                              : null,
                        ),
                        IconButton(
                          tooltip: '打开隔离栈页',
                          onPressed: onNavigate,
                          icon: const Icon(Icons.open_in_new),
                        ),
                        IconButton(
                          tooltip: '回到首页',
                          onPressed: onHome,
                          icon: const Icon(Icons.home_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: host == null
                        ? routerView
                        : CCRouterApp(host: host, child: routerView),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
