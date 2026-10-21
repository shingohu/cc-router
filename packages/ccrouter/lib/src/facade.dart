import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'generated_package_bundle.dart';
import 'host_tool_integration.dart';
import 'host_lifecycle_binding.dart';
import 'route_catalog.dart';

part 'navigation.dart';
part 'deep_link.dart';
part 'generated_command_binding.dart';
part 'generated_event_binding.dart';
part 'generated_service_binding.dart';
part 'runtime_resolver.dart';
part 'host_lifecycle.dart';
part 'test_binding.dart';

/// Resolves a strict call-site placement for the Flutter navigation facade.
CCRoutePlacement? _resolveContextPlacement(BuildContext? context) {
  if (context == null) return null;
  final host = CCRouterApp.of(context);
  return CCRoutePlacement(
    hostId: host.id,
    navigatorOutlet: host.resolveOutlet(context),
  );
}

/// Private backend payload correlating one Flutter Page with managed Runtime
/// navigation while preserving the original business Extra value.
final class _CCManagedNavigationPayload {
  /// Creates a payload for one admitted navigation request.
  const _CCManagedNavigationPayload({
    required this.navigationId,
    required this.extra,
    required this.runtimeIdentity,
  });

  /// Stable request identity used for exact RouteEntry lookup.
  final String navigationId;

  /// Payload-free Runtime generation token captured at backend dispatch.
  final Object? runtimeIdentity;

  /// Original process-local Extra value decoded by the generated page codec.
  final Object? extra;
}

/// Private inherited binding for one exact managed RouteEntry.
final class _CCRouteServiceBinding extends InheritedWidget {
  /// Wraps [child] with the immutable [navigationId] association.
  const _CCRouteServiceBinding({
    required this.navigationId,
    required this.runtimeIdentity,
    required super.child,
  });

  /// Runtime generation that admitted this Page, independent of reusable IDs.
  final Object? runtimeIdentity;

  /// Managed navigation whose Route Scope owns descendant Route Services.
  final String navigationId;

  @override
  /// Notifies when either the Page or its Runtime generation changes.
  bool updateShouldNotify(_CCRouteServiceBinding oldWidget) =>
      oldWidget.navigationId != navigationId ||
      !identical(oldWidget.runtimeIdentity, runtimeIdentity);
}

/// Static business-facing entry point for all CCRouter capabilities.
///
/// Business code uses this facade for component services, messages, Sessions,
/// diagnostics, and navigation. The application Composition Root initializes
/// and shuts down the default Runtime through [CCRouterHost]. Business code
/// cannot control or retain the lower-level Runtime.
abstract final class CCRouter {
  /// Process-local navigation facade backed by the active Runtime.
  static final CCNavigator _navigator = _CCNavigator();

  /// Returns the active Runtime or fails when the host is not initialized.
  static CCRouterRuntime get _runtime => _runtimeResolver.active;

  /// Whether the Runtime active for the current Facade Zone is initialized.
  ///
  /// Production calls observe the process-default Runtime. A dedicated test
  /// overlay observes its isolated Runtime without mutating that default. Use
  /// this only for host status and diagnostics; normal business code should
  /// rely on application startup ordering instead of polling it.
  static bool get isInitialized =>
      _runtimeResolver.activeOrNull?.isInitialized ?? false;

  /// Snapshot of the active authenticated Session, if one exists.
  ///
  /// Use this for immutable account and Session diagnostics, not as mutable
  /// authentication state or a replacement for the application's user model.
  static CCSession? get session => _runtime.session;

  /// Component manifests installed in deterministic dependency order.
  ///
  /// Hosts and diagnostics use this snapshot to inspect application assembly;
  /// business features should not branch on it for authorization.
  static List<CCComponentManifest> get registeredComponents =>
      _runtime.components;

  /// Bounded immutable snapshot of recent invocation traces.
  ///
  /// Use this for local diagnostics and observability export, not for storing
  /// business events or sensitive request payloads.
  static List<CCTraceRecord> get recentTraces => _runtime.recentTraces;

  /// Payload-free external diagnostic queue, write and drop counters.
  ///
  /// Use this to tune Host sampling and Sink capacity without reading events.
  /// A slow Sink never blocks business operations; overflow drops waiting data.
  static CCDiagnosticDeliverySnapshot get diagnosticDeliverySnapshot =>
      _runtime.diagnosticDeliverySnapshot;

  /// Returns the retained invocation records associated with [traceId].
  ///
  /// Use this after a failure event to assemble a local troubleshooting view.
  /// The bundle can be incomplete when the bounded trace history has rotated;
  /// it never contains arguments, return values, or raw exception messages.
  static CCTraceBundle traceBundle(String traceId) =>
      _runtime.traceBundle(traceId);

  /// Bounded snapshot of recent Runtime navigation lifecycle events.
  ///
  /// Use this for local diagnostics and sanitized telemetry export. Events do
  /// not contain typed route arguments, widget instances, or Pop results.
  static List<CCNavigationLifecycleEvent> get recentNavigationEvents =>
      _runtime.recentNavigationEvents;

  /// Bounded snapshot of sanitized navigation failures and recovery choices.
  ///
  /// Events contain stable routing identities and error types only. They never
  /// expose URI parameters, typed arguments, Pop results, or `extra` values.
  static List<CCNavigationFailureEvent> get recentNavigationFailures =>
      _runtime.recentNavigationFailures;

  /// Bounded snapshot of safe Adapter capability fallbacks used by navigation.
  ///
  /// Events identify only stable Route, Host, Outlet, capability, and behavior
  /// values. They never retain concrete URI values, arguments, `extra`, Widget,
  /// Navigator, or backend Route objects.
  static List<CCNavigationCapabilityFallbackEvent>
  get recentNavigationCapabilityFallbacks =>
      _runtime.recentNavigationCapabilityFallbacks;

  /// Bounded evidence that a previous route state could have been restored.
  ///
  /// Events always report `unsupported`; they measure demand and contain no
  /// replayable navigation state, URI parameters, arguments, or account IDs.
  static List<CCRouteRestorationOpportunityEvent>
  get recentRouteRestorationOpportunities =>
      _runtime.recentRouteRestorationOpportunities;

  /// Bounded snapshot of managed Route Entry visibility transitions.
  ///
  /// Use this for page exposure, focus restoration, and diagnostics. Flutter
  /// application lifecycle changes remain available through
  /// [CCRouterApp.onLifecycleChanged] and are not represented as Route
  /// visibility events.
  static List<CCRouteVisibilityEvent> get recentRouteVisibilityEvents =>
      _runtime.recentRouteVisibilityEvents;

  /// Snapshot of currently retained managed Route Entries in stack order.
  ///
  /// Snapshots are observational only and do not expose Route Scopes, close
  /// handles, Widgets, or backend Navigator objects. Capture a targeted-close
  /// handle from the owning Page with [routeEntryHandleOf].
  static List<CCRouteEntrySnapshot> get activeRouteEntries =>
      _runtime.activeRouteEntries;

  /// Bounded snapshot of backend Navigator transitions observed by the adapter.
  ///
  /// Use this for system back, gesture, and backend-owned stack diagnostics.
  /// Route metadata can be absent when application code bypasses CCRouter.
  static List<CCNavigationBackendDiagnosticEvent>
  get recentBackendNavigationEvents => _runtime.recentBackendNavigationEvents;

  /// Snapshot of the adapter-neutral backend Entry ledger.
  ///
  /// Use this for hybrid-navigation diagnostics. Foreign and opaque entries
  /// are immutable observations and cannot be popped or mutated through this
  /// API.
  static List<CCBackendEntrySnapshot> get backendEntries =>
      _runtime.backendEntries;

  /// Snapshot of backend Entries currently active in observed stacks.
  static List<CCBackendEntrySnapshot> get activeBackendEntries =>
      _runtime.activeBackendEntries;

  /// Returns backend entries isolated to an optional Host and Outlet.
  ///
  /// Use this for multi-Host, foldable-pane, Shell-branch, or embedded
  /// Navigator diagnostics. Null filters match every Host or Outlet, and the
  /// result remains observational only.
  static List<CCBackendEntrySnapshot> backendEntriesFor({
    String? hostId,
    String? navigatorOutlet,
    bool activeOnly = false,
  }) => _runtime.backendEntriesFor(
    hostId: hostId,
    navigatorOutlet: navigatorOutlet,
    activeOnly: activeOnly,
  );

  /// Subscribes to Runtime navigation lifecycle events.
  ///
  /// Use this at the application host boundary for navigation metrics. The
  /// returned callback removes the listener; listener failures do not fail
  /// navigation operations.
  static void Function() addNavigationListener(
    CCNavigationLifecycleListener listener,
  ) => _runtime.addNavigationListener(listener);

  /// Subscribes to sanitized navigation failure outcomes.
  ///
  /// Use this at the application Host boundary for failure-rate telemetry. The
  /// Runtime also reports failures when no recovery Policy is installed. The
  /// returned callback removes the listener, and listener failures are isolated.
  static void Function() addNavigationFailureListener(
    CCNavigationFailureListener listener,
  ) => _runtime.addNavigationFailureListener(listener);

  /// Subscribes to safe Adapter capability fallback observations.
  ///
  /// Host diagnostics use this to measure incomplete Observer or backend
  /// integration. Callbacks are asynchronous, cannot alter the fallback, and
  /// are isolated from navigation results.
  static void Function() addNavigationCapabilityFallbackListener(
    CCNavigationCapabilityFallbackListener listener,
  ) => _runtime.addNavigationCapabilityFallbackListener(listener);

  /// Subscribes to sanitized route-restoration demand observations.
  ///
  /// Analytics hosts use this to estimate whether full restoration is valuable.
  /// The returned callback removes the listener without affecting the source.
  static void Function() addRouteRestorationOpportunityListener(
    CCRouteRestorationOpportunityListener listener,
  ) => _runtime.addRouteRestorationOpportunityListener(listener);

  /// Subscribes to managed Route Entry visibility transitions.
  ///
  /// The returned callback removes the listener. Listener failures are
  /// isolated from navigation execution.
  static void Function() addRouteVisibilityListener(
    CCRouteVisibilityListener listener,
  ) => _runtime.addRouteVisibilityListener(listener);

  /// Subscribes to backend Navigator transitions observed by the adapter.
  ///
  /// The returned callback removes the listener. Adapters without backend
  /// observation support do not produce events.
  static void Function() addBackendNavigationListener(
    CCNavigationBackendDiagnosticListener listener,
  ) => _runtime.addBackendNavigationListener(listener);

  /// Unified business-facing navigation entry point.
  ///
  /// The returned object is stable across Runtime restarts and resolves the
  /// currently active Runtime for each operation. Calls before [CCRouterHost.initialize]
  /// fail with [CCRouterNotInitializedError].
  static CCNavigator get navigator => _navigator;

  /// Snapshot of navigation requests paused by an external policy.
  ///
  /// Authentication, consent, onboarding, and device-unlock hosts may inspect
  /// these IDs and later call [resumePendingNavigation] or
  /// [cancelPendingNavigation]. Typed arguments remain Runtime-owned.
  static List<CCPendingNavigation> get pendingNavigations =>
      _runtime.pendingNavigations;

  /// Resumes a pending navigation through the complete Runtime pipeline.
  static Future<Object?> resumePendingNavigation(String navigationId) =>
      _runtime.resumePendingNavigation(navigationId);

  /// Cancels a pending navigation and completes its original Future with a
  /// standard [CCRouteCancelledError].
  static bool cancelPendingNavigation(
    String navigationId, {
    String code = 'pending_cancelled',
  }) => _runtime.cancelPendingNavigation(navigationId, code: code);

  /// Resolves the default or keyed implementation of service contract [T].
  ///
  /// Generated registration binds promoted contracts to their stable identity;
  /// callers select only the Dart contract type and optional [key]. Absence is
  /// a configuration error reported as [CCServiceNotFoundError].
  static T service<T extends Object>({CCServiceKey<T>? key}) =>
      _runtime.service<T>(key: key);

  /// Resolves service contract [T], returning null only when it is unregistered.
  ///
  /// Use this only for genuinely optional integrations; factory and lifecycle
  /// failures still propagate and are not converted to null.
  static T? serviceOrNull<T extends Object>({CCServiceKey<T>? key}) =>
      _runtime.serviceOrNull<T>(key: key);

  /// Resolves a Service and awaits its optional lazy readiness initializer.
  ///
  /// Use this for a Provider that declares asynchronous setup. Existing purely
  /// synchronous Providers also work and complete after a lightweight traced
  /// readiness boundary. Initialization is single-flight per singleton and
  /// Scope; timeout and cancellation never change ownership of the instance.
  static Future<T> serviceAsync<T extends Object>({
    CCServiceKey<T>? key,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _runtime.serviceAsync<T>(
    key: key,
    timeout: timeout,
    cancellation: cancellation,
  );

  /// Resolves an optional Service asynchronously, returning null only if absent.
  ///
  /// Readiness, timeout, cancellation, and Scope failures remain explicit.
  static Future<T?> serviceOrNullAsync<T extends Object>({
    CCServiceKey<T>? key,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _runtime.serviceOrNullAsync<T>(
    key: key,
    timeout: timeout,
    cancellation: cancellation,
  );

  /// Returns the exact managed Page identity inherited by [context].
  ///
  /// Capture during page setup, before async work or covering navigation. This
  /// does not subscribe to inherited changes or infer the current top entry.
  /// Foreign, initial, or already removed pages return null.
  static CCRouteEntryHandle? routeEntryHandleOf(BuildContext context) {
    final binding = _validatedRouteServiceBinding(context);
    if (binding == null) return null;
    return _runtimeResolver.activeOrNull!.routeEntryHandleForNavigation(
      binding.navigationId,
    );
  }

  /// Returns the exact binding only while its Runtime generation is active.
  ///
  /// A binding can outlive a Runtime shutdown or be rendered from a payload
  /// created by another Runtime. Such bindings must not be allowed to fall
  /// back to a reusable navigation ID in the active Runtime.
  static _CCRouteServiceBinding? _validatedRouteServiceBinding(
    BuildContext context,
  ) {
    final binding = context
        .getInheritedWidgetOfExactType<_CCRouteServiceBinding>();
    final runtime = _runtimeResolver.activeOrNull;
    if (binding == null ||
        runtime == null ||
        !runtime.isInitialized ||
        binding.runtimeIdentity == null ||
        !identical(binding.runtimeIdentity, _runtimeResolver.activeIdentity)) {
      return null;
    }
    return binding;
  }

  /// Resolves a Route-scoped Service owned by the managed Page at [context].
  ///
  /// Use this for page-instance resources such as draft controllers that must
  /// survive PageHide but be disposed after the concrete RouteEntry is removed.
  /// The Page must have been opened through `CCRouter.navigator` and assembled
  /// by a Host that applies [CCRouterHostBinding.bindRouteEntry]. Initial or
  /// foreign backend pages have no managed Route Scope and fail with
  /// [CCServiceScopeUnavailableError]. This lookup uses an exact inherited
  /// identity; it never guesses from the visible or top route.
  static T routeService<T extends Object>(
    BuildContext context, {
    CCServiceKey<T>? key,
  }) {
    final binding = _validatedRouteServiceBinding(context);
    if (binding == null) {
      throw const CCServiceScopeUnavailableError(CCServiceScope.route);
    }
    return _runtime.serviceForRoute<T>(
      navigationId: binding.navigationId,
      key: key,
    );
  }

  /// Resolves an optional Route-scoped Service for the managed Page at
  /// [context].
  ///
  /// Null means no matching Provider is registered. A foreign, initial,
  /// removed, or disposed RouteEntry remains a lifecycle error and is never
  /// converted to null.
  static T? routeServiceOrNull<T extends Object>(
    BuildContext context, {
    CCServiceKey<T>? key,
  }) {
    final binding = _validatedRouteServiceBinding(context);
    if (binding == null) {
      throw const CCServiceScopeUnavailableError(CCServiceScope.route);
    }
    return _runtime.serviceForRouteOrNull<T>(
      navigationId: binding.navigationId,
      key: key,
    );
  }

  /// Resolves and readies a Route Service owned by [context]'s exact Page.
  ///
  /// Removing the managed RouteEntry cancels pending readiness. The Context is
  /// used only to read the immutable Navigation ID and never owns the Service.
  static Future<T> routeServiceAsync<T extends Object>(
    BuildContext context, {
    CCServiceKey<T>? key,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) {
    final binding = _validatedRouteServiceBinding(context);
    if (binding == null) {
      throw const CCServiceScopeUnavailableError(CCServiceScope.route);
    }
    return _runtime.serviceForRouteAsync<T>(
      navigationId: binding.navigationId,
      key: key,
      timeout: timeout,
      cancellation: cancellation,
    );
  }

  /// Resolves an optional Route Service asynchronously for [context]'s Page.
  ///
  /// Null means no Provider is registered; missing Route ownership and failed
  /// readiness remain lifecycle or initialization errors.
  static Future<T?> routeServiceOrNullAsync<T extends Object>(
    BuildContext context, {
    CCServiceKey<T>? key,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) {
    final binding = _validatedRouteServiceBinding(context);
    if (binding == null) {
      throw const CCServiceScopeUnavailableError(CCServiceScope.route);
    }
    return _runtime.serviceForRouteOrNullAsync<T>(
      navigationId: binding.navigationId,
      key: key,
      timeout: timeout,
      cancellation: cancellation,
    );
  }

  /// Resolves every registered implementation of service contract [T].
  ///
  /// Use when a caller intentionally composes all installed implementations.
  static List<T> services<T extends Object>() => _runtime.services<T>();

  /// Resolves all implementations and awaits each optional readiness hook.
  ///
  /// The result preserves deterministic key order. Use the synchronous
  /// [services] only when every matching Provider is synchronously ready.
  static Future<List<T>> servicesAsync<T extends Object>({
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _runtime.servicesAsync<T>(timeout: timeout, cancellation: cancellation);

  /// Whether service contract [T] has a matching registration.
  static bool hasService<T extends Object>({CCServiceKey<T>? key}) =>
      _runtime.hasService<T>(key: key);

  /// Dispatches [command] to its single handler.
  ///
  /// Use for one-to-one operations with one owning handler. `CCCommand<void>`
  /// reports completion or failure without a business result; repeatable reads
  /// and long-lived capabilities belong on a Service instead.
  static Future<R> command<R>(
    CCCommand<R> command, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _runtime.command(command, timeout: timeout, cancellation: cancellation);

  /// Publishes [event] concurrently and awaits matching subscribers.
  ///
  /// Use to announce an already completed fact without coupling the publisher
  /// to subscriber results. Individual failures become isolated diagnostics;
  /// caller cancellation, timeout, and Runtime shutdown still terminate the
  /// publish operation. Publishing with no subscribers succeeds.
  static Future<void> event(
    CCEvent event, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _runtime.event(event, timeout: timeout, cancellation: cancellation);

  /// Immutable initialization task snapshots ordered by stable task ID.
  ///
  /// Use for startup diagnostics and tests. Snapshots contain only stable IDs,
  /// state, duration, and sanitized error types, never task inputs or errors.
  static List<CCInitTaskSnapshot> get initTasks => _runtime.initTasks;

  /// Opens one authenticated account Session.
  ///
  /// Call after login succeeds or a persisted login is restored. Do not call on
  /// page changes, App backgrounding, or for anonymous request correlation.
  ///
  /// The existing Session must be fully closed before another can be opened.
  static void openSession({
    required String accountId,
    Map<String, Object?> metadata = const {},
  }) => _runtime.openSession(accountId: accountId, metadata: metadata);

  /// Closes the active Session and disposes all Session-owned resources.
  ///
  /// Call on logout, account switch, token invalidation, or forced sign-out;
  /// normal navigation and App backgrounding must not close the Session.
  static Future<void> closeSession() => _runtime.closeSession();
}

/// Host-only bridge that binds navigation infrastructure to [CCRouter].
///
/// Adapter packages and application composition roots use this after
/// `CCRouterHost.initialize` installs the startup components. Business and component
/// code must navigate through `CCRouter.navigator` and must never access this
/// ownership boundary.
abstract final class CCRouterHostBinding {
  /// Returns the route Catalog installed with the process-default Runtime.
  ///
  /// Managed application wrappers use this Host-only snapshot after
  /// `CCRouterHost.initialize` so the Composition Root cannot accidentally pass a
  /// Catalog from another generated assembly. Test Runtime overlays do not
  /// replace this value. Access before initialization or after shutdown throws
  /// [CCRouterNotInitializedError].
  static CCFlutterRouteCatalog get routeCatalog {
    final catalog = CCRouterHost._hostRouteCatalog;
    if (catalog == null) throw const CCRouterNotInitializedError();
    return catalog;
  }

  /// Encodes one managed request for backend navigation without exposing the
  /// wrapper to generated page codecs.
  ///
  /// Adapter implementations pass the returned object through their backend's
  /// process-local Extra channel. Custom Host route builders must use
  /// [decodeRouteExtra] and [bindRouteEntry] before rendering the destination.
  static Object encodeNavigationPayload(CCNavigationRequest request) =>
      _CCManagedNavigationPayload(
        navigationId: request.navigationId,
        extra: request.extra,
        runtimeIdentity: _runtimeResolver.activeIdentity,
      );

  /// Reads a managed opening identity without exposing its payload wrapper.
  ///
  /// Host adapters use this only to correlate exact declarative matches. It
  /// returns null for foreign or initial state and retains no business Extra.
  static String? navigationIdForPayload(Object? payload) =>
      payload is _CCManagedNavigationPayload ? payload.navigationId : null;

  /// Returns the original business Extra from a managed backend [payload].
  ///
  /// Unmanaged values pass through unchanged so the same Host builder can
  /// render initial, foreign, and CCRouter-managed locations.
  static Object? decodeRouteExtra(Object? payload) =>
      payload is _CCManagedNavigationPayload ? payload.extra : payload;

  /// Wraps [child] with an exact managed RouteEntry binding when available.
  ///
  /// Generated backend assemblers call this automatically. A custom Host route
  /// builder must call it with the backend's unmodified [payload]; passing only
  /// [decodeRouteExtra] intentionally produces an unmanaged page with no Route
  /// Service Scope.
  static Widget bindRouteEntry({
    required Object? payload,
    required Widget child,
  }) {
    if (payload is! _CCManagedNavigationPayload) return child;
    return _CCRouteServiceBinding(
      navigationId: payload.navigationId,
      runtimeIdentity: payload.runtimeIdentity,
      child: child,
    );
  }

  /// Synchronously transfers one ready [adapter] into the active Runtime.
  ///
  /// The Runtime configures the Adapter from the registered route table and
  /// imports its initial stack before this method returns. It owns Adapter
  /// disposal after success. A failed binding leaves Adapter cleanup with the
  /// caller so Backend-specific resources can be released deterministically.
  /// When supplied, [disposeBackend] is retained until `CCRouterHost.shutdown` and
  /// runs only after Runtime disposal.
  /// Test Runtime overlays must inject their Adapter when constructing the Test
  /// Host and cannot bind one through this production ownership boundary.
  static void attachNavigationAdapter(
    CCNavigationAdapter adapter, {
    Future<void> Function()? disposeBackend,
  }) {
    if (_runtimeResolver.hasOverlayRuntime) {
      throw const CCNavigationAdapterError(
        'A test Runtime receives its Adapter from CCRouterTestHost.',
      );
    }
    if (CCRouterHost._backendDisposer != null) {
      throw const CCNavigationAdapterError(
        'A navigation Backend is already bound to CCRouter.',
      );
    }
    CCRouter._runtime.attachNavigationAdapter(adapter);
    CCRouterHost._backendDisposer = disposeBackend;
  }
}
