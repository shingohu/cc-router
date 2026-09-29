import 'package:ccrouter/ccrouter.dart';

/// Stable IDs for the Demo component's initialization DAG.
abstract final class DemoInitTaskIds {
  /// Foundation work that is available before privacy consent.
  static const foundation = 'demo.startup.foundation';

  /// Optional SDK task used to demonstrate isolated failure handling.
  static const optionalSdk = 'demo.startup.optional-sdk';

  /// Task blocked when [optionalSdk] fails.
  static const optionalDependent = 'demo.startup.optional-dependent';

  /// Analytics setup opened by [CCInitTaskGate.privacyGranted].
  static const analytics = 'demo.startup.analytics';

  /// First task in the generated parallel dependency layer.
  static const parallelPrimary = 'demo.startup.parallel-primary';

  /// Second task in the generated parallel dependency layer.
  static const parallelSecondary = 'demo.startup.parallel-secondary';

  /// Optional task used to demonstrate a custom Gate and timeout.
  static const timeout = 'demo.startup.timeout';
}

/// Stable custom Gates opened explicitly by the Demo Host UI.
abstract final class DemoInitializationGates {
  /// Opens the optional timeout task without changing privacy state.
  static const timeoutLab = CCInitTaskGate('demo.timeoutLab');
}

/// Typed dependency target for the Demo foundation task.
const demoFoundationInitTask = CCInitTaskContract(
  id: DemoInitTaskIds.foundation,
  description: '准备所有 Demo 初始化任务共享的基础状态。',
);

/// Typed dependency target for the deliberately failing optional SDK task.
const demoOptionalSdkInitTask = CCInitTaskContract(
  id: DemoInitTaskIds.optionalSdk,
  description: '模拟可选 SDK 初始化失败及依赖节点跳过。',
);

/// Stable Event IDs registered by the Demo component.
abstract final class DemoEventIds {
  /// Completed-order fact published by the Demo component.
  static const orderCompleted = 'demo_navigation_lab.order_completed';

  /// Fact with no installed subscribers, used to demonstrate no-op delivery.
  static const unobserved = 'demo_navigation_lab.unobserved';

  /// Fact whose subscriber waits until its invocation is cancelled.
  static const slow = 'demo_navigation_lab.slow';
}

/// Stable Event Subscriber IDs used by the diagnostics lab.
abstract final class DemoEventSubscriberIds {
  /// Analytics subscriber for a completed order.
  static const orderAnalytics = 'demo.analytics.order-completed';

  /// Deliberately failing subscriber used by the diagnostics lab.
  static const orderFailure = 'demo.broken.order-completed';
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

@CCCommandContract(
  id: 'demo_navigation_lab.create_receipt',
  description: '创建演示收据并返回稳定的收据编号。',
)
final class DemoCreateReceiptCommand implements CCCommand<String> {
  const DemoCreateReceiptCommand(this.amount);

  final int amount;
}

@CCCommandContract(
  id: 'demo_navigation_lab.refresh_cache',
  description: '刷新组件缓存并仅报告完成或失败。',
)
final class DemoRefreshCacheCommand implements CCCommand<void> {
  const DemoRefreshCacheCommand();
}

@CCCommandContract(
  id: 'demo_navigation_lab.wait',
  description: '保持等待直到超时或调用方取消，用于验证协作取消。',
)
final class DemoWaitCommand implements CCCommand<void> {
  const DemoWaitCommand();
}

@CCCommandContract(
  id: 'demo_navigation_lab.fail',
  description: '抛出业务异常以验证安全 Trace 和错误传播。',
)
final class DemoFailCommand implements CCCommand<void> {
  const DemoFailCommand();
}

@CCEventContract(
  id: DemoEventIds.orderCompleted,
  description: '订单完成后通知互不依赖的 Demo Subscriber。',
)
final class DemoOrderCompletedEvent implements CCEvent {
  const DemoOrderCompletedEvent(this.orderId);

  final int orderId;
}

@CCEventContract(
  id: DemoEventIds.unobserved,
  description: '验证零 Subscriber 发布仍是可追踪的成功 no-op。',
)
final class DemoUnobservedEvent implements CCEvent {
  const DemoUnobservedEvent();
}

@CCEventContract(
  id: DemoEventIds.slow,
  description: '验证 Event timeout 和 cooperative cancellation。',
)
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

final class DemoNewInstanceService {
  const DemoNewInstanceService(this.instanceId);

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
