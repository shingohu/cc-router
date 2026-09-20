import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_demo/ccrouter_generated/ccrouter_host.routes.g.dart';
import 'package:ccrouter_demo/demo_router_backend.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:flutter/material.dart';

import '../platform_deep_link_bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CCRouter.initialize(
    components: ccrouterGeneratedComponentManifests,
    deepLinkIngressPolicy: demoDeepLinkIngressPolicy,
  );
  runApp(createMultiHostDemoApp());
}

Widget createMultiHostDemoApp() =>
    _MultiHostDemoApp(backend: _MultiHostDemoBackend.create());

final class _MultiHostDemoBackend implements CCRouterAppBackend {
  _MultiHostDemoBackend._({
    required this.primary,
    required this.secondary,
    required this.registry,
  });

  factory _MultiHostDemoBackend.create() {
    final primary = createDemoRouterBackend(
      catalog: ccrouterGeneratedRouteCatalog,
      hostId: 'window.primary',
    );
    final secondary = createDemoRouterBackend(
      catalog: ccrouterGeneratedRouteCatalog,
      hostId: 'window.secondary',
    );
    return _MultiHostDemoBackend._(
      primary: primary,
      secondary: secondary,
      registry: CCNavigationHostRegistry(
        defaultHostId: primary.host.id,
        adapters: {
          primary.host.id: primary.adapter,
          secondary.host.id: secondary.adapter,
        },
      ),
    );
  }

  final CCGoRouterBackend primary;
  final CCGoRouterBackend secondary;
  final CCNavigationHostRegistry registry;

  @override
  CCFlutterRouteCatalog get routeCatalog => ccrouterGeneratedRouteCatalog;

  @override
  CCNavigationHost get host => primary.host;

  @override
  CCNavigationAdapter get navigationAdapter => registry;

  @override
  Future<void> dispose() async {
    await primary.dispose();
    await secondary.dispose();
  }
}

final class _MultiHostDemoApp extends StatelessWidget {
  const _MultiHostDemoApp({required this.backend});

  final _MultiHostDemoBackend backend;

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

  final _MultiHostDemoBackend backend;

  @override
  State<_MultiHostWorkspace> createState() => _MultiHostWorkspaceState();
}

final class _MultiHostWorkspaceState extends State<_MultiHostWorkspace> {
  String _status = '选择 Host 后执行类型安全导航';

  Future<void> _navigate(String hostId, int level) async {
    widget.backend.registry.activateHost(hostId);
    setState(() => _status = '$hostId · navigating');
    await CCRouter.navigator.go(demoStackIntent(level: level));
    if (mounted) setState(() => _status = '$hostId · /lab/stack/$level');
  }

  Future<void> _home(String hostId) async {
    widget.backend.registry.activateHost(hostId);
    await CCRouter.navigator.go(demoHomeIntent());
    if (mounted) setState(() => _status = '$hostId · /');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Multi Host Isolation'),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(28),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_status),
        ),
      ),
    ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final panes = <Widget>[
          Expanded(
            child: _HostPane(
              key: const ValueKey('window.primary'),
              title: 'Primary Host',
              hostId: widget.backend.primary.host.id,
              router: widget.backend.primary.router,
              onNavigate: () =>
                  unawaited(_navigate(widget.backend.primary.host.id, 101)),
              onHome: () => unawaited(_home(widget.backend.primary.host.id)),
            ),
          ),
          Expanded(
            child: _HostPane(
              key: const ValueKey('window.secondary'),
              title: 'Secondary Host',
              hostId: widget.backend.secondary.host.id,
              router: widget.backend.secondary.router,
              host: widget.backend.secondary.host,
              onNavigate: () =>
                  unawaited(_navigate(widget.backend.secondary.host.id, 202)),
              onHome: () => unawaited(_home(widget.backend.secondary.host.id)),
            ),
          ),
        ];
        return Flex(
          direction: constraints.maxWidth < 900
              ? Axis.vertical
              : Axis.horizontal,
          children: panes,
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
    required this.onNavigate,
    required this.onHome,
    this.host,
  });

  final String title;
  final String hostId;
  final GoRouter router;
  final CCNavigationHost? host;
  final VoidCallback onNavigate;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final routerView = Router.withConfig(config: router);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(child: Text('$title · $hostId')),
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
    );
  }
}
