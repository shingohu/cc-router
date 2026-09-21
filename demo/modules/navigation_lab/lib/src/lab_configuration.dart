import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/foundation.dart';

import 'ccrouter_generated/component/demo_navigation_lab_component.route_api.g.dart';

final demoNavigationLabStore = DemoNavigationLabStore();

final class DemoNavigationLabStore extends ChangeNotifier {
  final List<String> _events = <String>[];
  bool _notifyScheduled = false;

  bool blockDetailGlobally = false;
  bool dirtyForm = true;
  bool allowDeferredOnce = false;

  List<String> get events => List.unmodifiable(_events);

  void record(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    _events.insert(0, '$timestamp  $message');
    if (_events.length > 80) _events.removeRange(80, _events.length);
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  void clear() {
    _events.clear();
    notifyListeners();
  }

  void setBlockDetailGlobally(bool value) {
    blockDetailGlobally = value;
    record('全局拦截开关：${value ? '阻止详情页' : '允许详情页'}');
  }

  void setDirtyForm(bool value) {
    dirtyForm = value;
    record('PopGuard 表单状态：${value ? '未保存' : '已保存'}');
  }
}

final class DemoGlobalNavigationInterceptor implements CCNavigationInterceptor {
  const DemoGlobalNavigationInterceptor();

  @override
  CCNavigationInterception intercept(CCNavigationInterceptorContext context) {
    demoNavigationLabStore.record(
      'Global before · ${context.request.operation.name} · '
      '${context.request.routeId}',
    );
    if (demoNavigationLabStore.blockDetailGlobally &&
        context.request.routeId == 'demo_navigation_lab.detail') {
      return const CCNavigationCancel(code: 'demo_global_block');
    }
    return const CCNavigationProceed();
  }
}

final class DemoNavigationTelemetryProvider
    implements CCNavigationTelemetryContextProvider {
  const DemoNavigationTelemetryProvider();

  @override
  CCNavigationTelemetryContext currentContext() =>
      const CCNavigationTelemetryContext(
        anonymousVisitorId: 'demo-visitor',
        applicationSessionId: 'macos-demo-run',
      );
}

final class DemoNavigationFailurePolicy implements CCNavigationFailurePolicy {
  const DemoNavigationFailurePolicy();

  @override
  CCNavigationFailureDecision onFailure(CCNavigationFailureContext context) {
    demoNavigationLabStore.record(
      'Failure · ${context.stage.name}/${context.reason.name} · '
      '${context.initialRouteId ?? '-'} -> ${context.routeId ?? '-'} · '
      '${context.errorType}',
    );
    if (context.stage == CCNavigationFailureStage.resolution) {
      return CCNavigationFailureFallback.toIntent(
        DemoNavigationLabRoutes.failure(
              stage: context.stage.name,
              reason: context.reason.name,
              errorType: context.errorType,
              initialRouteId: context.initialRouteId,
              routeId: context.routeId,
            )
            as CCRouteIntent<Object?>,
        operation: CCNavigationOperation.push,
      );
    }
    return const CCNavigationFailurePropagate();
  }
}

final demoNavigationAspect = CCNavigationAspect(
  id: 'demo.navigation.timeline',
  onFound: _recordAspect,
  onArrival: _recordAspect,
  onShow: _recordAspect,
  onHide: _recordAspect,
  onRemoved: _recordAspect,
  onDisposed: _recordAspect,
  onLost: _recordAspect,
  onAfter: _recordAspect,
);

void _recordAspect(CCNavigationAspectEvent event) {
  final source = event.request.source?.id;
  final elapsed = event.timing?.total?.inMilliseconds;
  demoNavigationLabStore.record(
    'Aspect ${event.phase.name} · ${event.request.routeId}'
    '${source == null ? '' : ' · source=$source'}'
    '${elapsed == null ? '' : ' · ${elapsed}ms'}',
  );
}
