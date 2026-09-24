import 'dart:async';

import 'package:ccrouter_analytics/ccrouter_analytics.dart';
import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/foundation.dart';

import 'ccrouter_generated/component/demo_navigation_lab_component.route_api.g.dart';
import 'component_capabilities.dart';

final demoApplicationLogger = DemoApplicationLogger();
final demoNavigationLabStore = DemoNavigationLabStore();
final demoDiagnosticsSink = DemoDiagnosticsSink();
final demoAnalyticsSink = DemoAnalyticsSink();
final demoAnalyticsDispatcher = CCAnalyticsEventDispatcher(
  sinks: [demoAnalyticsSink],
  policy: CCAnalyticsPolicy(consentGranted: true),
);
final demoNavigationAnalytics = CCRouterNavigationAnalytics(
  dispatcher: demoAnalyticsDispatcher,
);
final demoAnalyticsTracker = CCAnalyticsTracker(
  dispatcher: demoAnalyticsDispatcher,
  context: const CCAnalyticsContext(
    componentId: 'demo_navigation_lab',
    hostId: 'default',
    outlet: 'root',
  ),
);

/// Application-level structured log retained by the Demo Host.
///
/// This is intentionally a small in-memory stand-in for an application Logger,
/// Sentry bridge, or OpenTelemetry exporter. It stores only framework-safe
/// identifiers and lets the Demo correlate framework and application records
/// by trace and navigation IDs without retaining route arguments or payloads.
final class DemoApplicationLogEntry {
  /// Creates one immutable application log record.
  const DemoApplicationLogEntry({
    required this.occurredAt,
    required this.source,
    required this.level,
    required this.operation,
    required this.status,
    required this.message,
    this.category,
    this.duration = Duration.zero,
    this.runtimeId,
    this.traceId,
    this.spanId,
    this.parentSpanId,
    this.invocationId,
    this.target,
    this.callerComponentId,
    this.targetComponentId,
    this.scopeId,
    this.navigationId,
    this.routeId,
    this.eventId,
    this.subscriberId,
    this.hostId,
    this.outlet,
    this.failureStage,
    this.errorType,
    this.fallbackKind,
  });

  /// Timestamp assigned by the application logger.
  final DateTime occurredAt;

  /// `application` for Host/application records or `framework` for Sink data.
  final String source;

  /// Sanitized severity name.
  final String level;

  /// Functional category, when this is a framework diagnostic.
  final CCDiagnosticCategory? category;

  /// Stable operation name.
  final String operation;

  /// Terminal or intermediate status.
  final String status;

  /// Short application message without arbitrary payload data.
  final String message;

  /// Elapsed duration reported by the framework.
  final Duration duration;

  /// Runtime identity.
  final String? runtimeId;

  /// Trace identity shared by nested calls.
  final String? traceId;

  /// Current span identity.
  final String? spanId;

  /// Parent span identity.
  final String? parentSpanId;

  /// Invocation identity.
  final String? invocationId;

  /// Sanitized target identity.
  final String? target;

  /// Calling component identity.
  final String? callerComponentId;

  /// Owning component identity.
  final String? targetComponentId;

  /// Scope identity.
  final String? scopeId;

  /// Navigation identity.
  final String? navigationId;

  /// Route identity.
  final String? routeId;

  /// Event type identity.
  final String? eventId;

  /// Event subscriber identity.
  final String? subscriberId;

  /// Host identity.
  final String? hostId;

  /// Outlet identity.
  final String? outlet;

  /// Navigation failure stage.
  final String? failureStage;

  /// Sanitized error type.
  final String? errorType;

  /// Adapter fallback identity.
  final String? fallbackKind;
}

/// Host-owned application logger used by the Demo observability lab.
final class DemoApplicationLogger {
  static const int _capacity = 300;
  final List<DemoApplicationLogEntry> _entries = <DemoApplicationLogEntry>[];

  /// Recent records in newest-first order.
  List<DemoApplicationLogEntry> get entries => List.unmodifiable(_entries);

  /// Returns records sharing [traceId], newest first.
  List<DemoApplicationLogEntry> entriesForTrace(String traceId) =>
      List.unmodifiable(_entries.where((entry) => entry.traceId == traceId));

  /// Records a sanitized framework diagnostic from [event].
  void recordDiagnostic(CCDiagnosticEvent event) {
    _add(
      DemoApplicationLogEntry(
        occurredAt: event.occurredAt,
        source: 'framework',
        level: event.level.name,
        category: event.category,
        operation: event.operation,
        status: event.status,
        message: '${event.category.name}/${event.operation} · ${event.status}',
        duration: event.duration,
        runtimeId: event.runtimeId,
        traceId: event.traceId,
        spanId: event.spanId,
        parentSpanId: event.parentSpanId,
        invocationId: event.invocationId,
        target: event.target,
        callerComponentId: event.callerComponentId,
        targetComponentId: event.targetComponentId,
        scopeId: event.scopeId,
        navigationId: event.navigationId,
        routeId: event.routeId,
        eventId: event.eventId,
        subscriberId: event.subscriberId,
        hostId: event.hostId,
        outlet: event.outlet,
        failureStage: event.failureStage,
        errorType: event.errorType,
        fallbackKind: event.fallbackKind,
      ),
    );
  }

  /// Records a short application-owned message without business payloads.
  void recordApplication(String message) {
    _add(
      DemoApplicationLogEntry(
        occurredAt: DateTime.now(),
        source: 'application',
        level: 'info',
        operation: 'application',
        status: 'observed',
        message: message,
      ),
    );
  }

  /// Clears the application log retained by the Demo.
  void clear() => _entries.clear();

  void _add(DemoApplicationLogEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > _capacity) {
      _entries.removeRange(_capacity, _entries.length);
    }
  }
}

final class DemoNavigationLabStore extends ChangeNotifier {
  final List<String> _events = <String>[];
  bool _notifyScheduled = false;

  bool blockDetailGlobally = false;
  bool dirtyForm = true;
  bool allowDeferredOnce = false;

  List<String> get events => List.unmodifiable(_events);

  void record(String message, {bool mirrorToApplicationLogger = true}) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    _events.insert(0, '$timestamp  $message');
    if (_events.length > 80) _events.removeRange(80, _events.length);
    if (mirrorToApplicationLogger) {
      demoApplicationLogger.recordApplication(message);
    }
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

/// Host-owned diagnostics bridge used by the Demo observability lab.
final class DemoDiagnosticsSink implements CCDiagnosticSink {
  final List<CCDiagnosticEvent> _events = <CCDiagnosticEvent>[];

  /// Recent sanitized events received from the Runtime Sink.
  List<CCDiagnosticEvent> get events => List.unmodifiable(_events);

  @override
  void record(CCDiagnosticEvent event) {
    _events.insert(0, event);
    if (_events.length > 80) _events.removeRange(80, _events.length);
    demoApplicationLogger.recordDiagnostic(event);
    demoNavigationLabStore.record(
      'Sink · ${event.category.name}/${event.operation} · ${event.status}',
      mirrorToApplicationLogger: false,
    );
  }

  /// Clears only the Demo's displayed Sink history.
  void clear() {
    _events.clear();
    demoApplicationLogger.clear();
    demoNavigationLabStore.record(
      'Sink · history cleared',
      mirrorToApplicationLogger: false,
    );
  }
}

/// Demo application sink that makes product events visible beside framework logs.
final class DemoAnalyticsSink implements CCAnalyticsSink {
  @override
  void write(CCAnalyticsEvent event) {
    demoApplicationLogger.recordApplication(
      'Analytics · ${event.type.name} · ${event.eventId}'
      ' · route=${event.routeId ?? '-'}'
      ' · nav=${event.navigationId ?? '-'}',
    );
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
    if (context.reason == CCNavigationFailureReason.routeNotFound) {
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
  id: DemoAspectIds.navigationTimeline,
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
