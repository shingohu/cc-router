import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_navigation_lab/demo_navigation_lab_host.dart';
import 'package:flutter/material.dart';

import 'demo_managed_router_backend.dart';

/// Host-owned manual gate; feature components never manage Host registrations.
final class DemoHostLifecyclePolicy implements CCNavigationInterceptor {
  static const hostId = 'host.auxiliary';
  Completer<CCNavigationInterceptorDecision>? _gate;
  bool _armed = false;

  bool get hasGate => _gate != null;

  void arm() {
    release(allow: false);
    _gate = Completer<CCNavigationInterceptorDecision>();
    _armed = true;
  }

  void release({bool allow = true}) {
    final gate = _gate;
    _gate = null;
    _armed = false;
    gate?.complete(
      allow
          ? const CCNavigationProceed()
          : const CCNavigationCancel(code: 'demo_gate_cancelled'),
    );
  }

  @override
  FutureOr<CCNavigationInterceptorDecision> intercept(
    CCNavigationInterceptorContext context,
  ) {
    if (_armed &&
        context.request.hostId == hostId &&
        context.request.uri.path == '/lab/stack/901') {
      _armed = false;
      return _gate!.future;
    }
    return const CCNavigationProceed();
  }
}

/// Reuses one logical Host ID with a fresh Backend and fresh Navigator keys.
class DemoHostLifecycleLab extends StatefulWidget {
  const DemoHostLifecycleLab({
    required this.aggregate,
    required this.policy,
    super.key,
  });

  final CCManagedMultiHostBackend aggregate;
  final DemoHostLifecyclePolicy policy;

  @override
  State<DemoHostLifecycleLab> createState() => _DemoHostLifecycleLabState();
}

class _DemoHostLifecycleLabState extends State<DemoHostLifecycleLab> {
  CCManagedRouterBackend? _backend;
  int _generation = 0;
  bool _waiting = false;
  String _oldOutcome = '尚未发起延迟导航';
  String _freshOutcome = '尚未导航';

  @override
  void initState() {
    super.initState();
    _open();
  }

  void _open() {
    final backend = createDemoManagedRouterBackend(
      catalog: widget.aggregate.routeCatalog,
      hostId: DemoHostLifecyclePolicy.hostId,
      // This auxiliary surface owns a trusted home, not platform startup links.
      overridePlatformDefaultLocation: true,
    );
    try {
      widget.aggregate.adapter.registerHost(
        DemoHostLifecyclePolicy.hostId,
        backend.navigationAdapter,
      );
    } catch (_) {
      unawaited(backend.dispose());
      rethrow;
    }
    _backend = backend;
    _generation++;
    _freshOutcome = '新实例首页';
  }

  Future<void> _retire() async {
    final backend = _backend;
    _backend = null;
    if (backend == null) return;
    final registry = widget.aggregate.adapter;
    try {
      if (registry.registeredHostIds.contains(DemoHostLifecyclePolicy.hostId)) {
        registry.unregisterHost(
          DemoHostLifecyclePolicy.hostId,
          replacementActiveHostId:
              registry.activeHostId == DemoHostLifecyclePolicy.hostId
              ? 'host.primary'
              : null,
        );
      }
    } finally {
      await backend.dispose();
    }
  }

  Future<void> _reopen() async {
    final retirement = _retire();
    setState(() {});
    await retirement;
    // A logical Host may have only one mounted CCRouterApp. Cleanup already
    // finished; wait for old Widget disposal before mounting the replacement.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(_open);
  }

  Future<void> _navigate({required bool delayed}) async {
    if (_backend == null) return;
    widget.aggregate.adapter.activateHost(DemoHostLifecyclePolicy.hostId);
    final generation = _generation;
    if (delayed) {
      widget.policy.arm();
      setState(() {
        _waiting = true;
        _oldOutcome = '第 $generation 代：等待策略';
      });
    }
    try {
      await CCRouter.navigator.go(demoStackIntent(level: 901));
      if (!mounted) return;
      setState(() {
        if (delayed) {
          _oldOutcome = '第 $generation 代：已完成';
        } else {
          _freshOutcome = '第 $generation 代：导航成功';
        }
      });
    } on CCRouterError catch (error) {
      if (!mounted) return;
      setState(() {
        final outcome = error is CCRouteCancelledError
            ? error.code
            : error.runtimeType.toString();
        if (delayed) {
          _oldOutcome = '第 $generation 代：$outcome';
        } else {
          _freshOutcome = '第 $generation 代：$outcome';
        }
      });
    } finally {
      if (delayed && mounted) setState(() => _waiting = false);
    }
  }

  @override
  void dispose() {
    widget.policy.release(allow: false);
    unawaited(_retire());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          '先发起延迟导航，再关闭并重开辅助 Host。旧请求应取消；'
          '新实例可独立导航，放行旧决策不应改变新页面。',
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          FilledButton(
            onPressed: _waiting || _backend == null
                ? null
                : () => _navigate(delayed: true),
            child: const Text('发起延迟导航'),
          ),
          OutlinedButton(
            onPressed: _backend == null ? null : _reopen,
            child: const Text('关闭并重开 Host'),
          ),
          OutlinedButton(
            onPressed: _backend == null
                ? null
                : () => _navigate(delayed: false),
            child: const Text('新实例导航'),
          ),
          OutlinedButton(
            onPressed: widget.policy.hasGate
                ? () => setState(widget.policy.release)
                : null,
            child: const Text('放行旧决策'),
          ),
        ],
      ),
      Text('辅助 Host 第 $_generation 代', key: const ValueKey('host-generation')),
      Text(_oldOutcome, key: const ValueKey('host-old-outcome')),
      Text(_freshOutcome, key: const ValueKey('host-fresh-outcome')),
      Expanded(
        child: _backend == null
            ? const Center(child: Text('辅助 Host 已关闭'))
            : CCRouterApp(
                key: ValueKey(_generation),
                host: _backend!.host,
                child: MaterialApp.router(routerConfig: _backend!.routerConfig),
              ),
      ),
    ],
  );
}
