import 'package:ccrouter/ccrouter.dart';

/// Stable IDs for the Demo component's initialization DAG.
abstract final class DemoInitializationTaskIds {
  /// Foundation work that is available before privacy consent.
  static const foundation = 'demo.startup.foundation';

  /// Optional SDK task used to demonstrate isolated failure handling.
  static const optionalSdk = 'demo.startup.optional-sdk';

  /// Task blocked when [optionalSdk] fails.
  static const optionalDependent = 'demo.startup.optional-dependent';

  /// Analytics setup opened by [CCInitializationGate.privacyGranted].
  static const analytics = 'demo.startup.analytics';
}

/// Stable Event IDs registered by the Demo component.
abstract final class DemoEventIds {
  /// Analytics subscriber for a completed order.
  static const orderCompleted = 'demo.analytics.order-completed';

  /// Deliberately failing subscriber used by the diagnostics lab.
  static const brokenOrderCompleted = 'demo.broken.order-completed';

  /// Subscriber that remains pending until its invocation is cancelled.
  static const slow = 'demo.slow-event';
}

/// Typed Event subscriber identities used by the diagnostics lab.
abstract final class DemoEventSubscribers {
  /// Analytics subscriber for a completed order.
  static const orderAnalytics = CCEventSubscriberId<DemoOrderCompletedEvent>(
    DemoEventIds.orderCompleted,
  );

  /// Deliberately failing subscriber used by the diagnostics lab.
  static const orderFailure = CCEventSubscriberId<DemoOrderCompletedEvent>(
    DemoEventIds.brokenOrderCompleted,
  );

  /// Subscriber that remains pending until its invocation is cancelled.
  static const slow = CCEventSubscriberId<DemoSlowEvent>(DemoEventIds.slow);
}

/// Stable route policy IDs registered by the Demo component.
abstract final class DemoRoutePolicyIds {
  /// Interceptor that allows navigation to continue.
  static const proceed = 'demo_navigation_lab.proceed';

  /// Interceptor that cancels navigation.
  static const cancel = 'demo_navigation_lab.cancel';

  /// Interceptor that redirects to another route.
  static const redirect = 'demo_navigation_lab.redirect';

  /// Interceptor that defers navigation until the lab resumes it.
  static const defer = 'demo_navigation_lab.defer';

  /// Interceptor that intentionally exceeds its deadline.
  static const timeout = 'demo_navigation_lab.timeout';

  /// Pop Guard protecting the dirty-form route.
  static const dirty = 'demo_navigation_lab.dirty';
}

/// Stable source IDs used by the Demo navigation lab.
abstract final class DemoNavigationSourceIds {
  /// Platform-like external link source using push semantics.
  static const simulatedExternal = 'demo.simulated_external';

  /// Platform-like external link source using go semantics.
  static const simulatedExternalGo = 'demo.simulated_external_go';
}

/// Stable Aspect IDs owned by the Demo navigation component.
abstract final class DemoAspectIds {
  /// Timeline Aspect used by the diagnostics page.
  static const navigationTimeline = 'demo.navigation.timeline';
}

const demoBackupChannelKey = CCServiceKey<DemoChannelService>('backup');

final class DemoCreateReceiptCommand implements CCCommand<String> {
  const DemoCreateReceiptCommand(this.amount);

  final int amount;
}

final class DemoRefreshCacheCommand implements CCCommand<void> {
  const DemoRefreshCacheCommand();
}

final class DemoWaitCommand implements CCCommand<void> {
  const DemoWaitCommand();
}

final class DemoFailCommand implements CCCommand<void> {
  const DemoFailCommand();
}

final class DemoOrderCompletedEvent implements CCEvent {
  const DemoOrderCompletedEvent(this.orderId);

  final int orderId;
}

final class DemoUnobservedEvent implements CCEvent {
  const DemoUnobservedEvent();
}

final class DemoSlowEvent implements CCEvent {
  const DemoSlowEvent();
}

final class DemoAppService implements CCDisposable {
  DemoAppService(this.instanceId, this.onDispose);

  final int instanceId;
  final void Function(String) onDispose;

  @override
  void dispose() => onDispose('App Service #$instanceId disposed');
}

final class DemoSessionService implements CCDisposable {
  DemoSessionService(this.instanceId, this.onDispose);

  final int instanceId;
  final void Function(String) onDispose;

  @override
  void dispose() => onDispose('Session Service #$instanceId disposed');
}

final class DemoRouteService implements CCDisposable {
  DemoRouteService(this.instanceId, this.onDispose);

  final int instanceId;
  final void Function(String) onDispose;

  @override
  void dispose() => onDispose('Route Service #$instanceId disposed');
}

final class DemoFactoryService {
  const DemoFactoryService(this.instanceId);

  final int instanceId;
}

final class DemoLazyService {
  DemoLazyService(this.instanceId);

  final int instanceId;
  bool ready = false;
}

abstract interface class DemoChannelService {
  String get name;
}

final class DemoPrimaryChannelService implements DemoChannelService {
  const DemoPrimaryChannelService();

  @override
  String get name => 'primary';
}

final class DemoBackupChannelService implements DemoChannelService {
  const DemoBackupChannelService();

  @override
  String get name => 'backup';
}

abstract interface class DemoMissingService {}

final class DemoCapabilityInstanceIds {
  DemoCapabilityInstanceIds._();

  static int _nextValue = 0;

  static int next() => ++_nextValue;
}
