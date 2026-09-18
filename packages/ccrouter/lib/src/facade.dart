import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';

part 'navigation.dart';
part 'deep_link.dart';

/// Static business-facing entry point for all CCRouter capabilities.
///
/// Applications initialize this facade once per isolate and use it for
/// component services, messages, Sessions, diagnostics, and navigation. Do not
/// construct or retain the lower-level Runtime in business code.
abstract final class CCRouter {
  /// Process-local navigation facade backed by the active Runtime.
  static final CCNavigator _navigator = _CCNavigator();

  /// Runtime owned by the current isolate's application host.
  static CCRouterRuntime? _defaultRuntime;

  /// Initialization operation currently in progress.
  static Future<void>? _initializing;

  /// Shutdown operation currently in progress.
  static Future<void>? _shuttingDown;

  /// Returns the active Runtime or fails when the host is not initialized.
  static CCRouterRuntime get _runtime {
    final active = _defaultRuntime;
    if (active == null) throw const CCRouterNotInitializedError();
    return active;
  }

  /// Whether the default Runtime has completed initialization.
  ///
  /// Use this only for host status and diagnostics; normal business code should
  /// rely on application startup ordering instead of polling it.
  static bool get isInitialized => _defaultRuntime?.isInitialized ?? false;

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

  /// Unified business-facing navigation entry point.
  ///
  /// The returned object is stable across Runtime restarts and resolves the
  /// currently active Runtime for each operation. Calls before [initialize]
  /// fail with [CCRouterNotInitializedError].
  static CCNavigator get navigator => _navigator;

  /// Creates, initializes, and owns the application's default Runtime.
  ///
  /// Call this once during application host startup with the complete component
  /// assembly. When supplied, [navigationAdapter] is owned, initialized, and
  /// disposed by CCRouter. Tests that need isolated hosts should use dedicated
  /// test support.
  ///
  /// A second call before [shutdown] completes throws
  /// [CCRouterAlreadyInitializedError].
  static Future<void> initialize({
    required Iterable<CCComponentManifest> components,
    int traceCapacity = 1000,
    CCNavigationAdapter? navigationAdapter,
  }) async {
    if (_defaultRuntime != null ||
        _initializing != null ||
        _shuttingDown != null) {
      throw const CCRouterAlreadyInitializedError();
    }

    final runtime = CCRouterRuntime.forHost(
      components: components,
      traceCapacity: traceCapacity,
      navigationAdapter: navigationAdapter,
    );
    final initializing = runtime.initialize();
    _initializing = initializing;
    try {
      await initializing;
      _defaultRuntime = runtime;
    } catch (_) {
      await runtime.dispose();
      rethrow;
    } finally {
      if (identical(_initializing, initializing)) _initializing = null;
    }
  }

  /// Resolves the default or keyed implementation of service contract [T].
  ///
  /// Use when the capability is required and absence is a configuration error.
  static T service<T extends Object>({CCServiceKey<T>? key}) =>
      _runtime.service<T>(key: key);

  /// Resolves service contract [T], returning null only when it is unregistered.
  ///
  /// Use for genuinely optional integrations; factory and lifecycle failures
  /// still propagate and are not converted to null.
  static T? serviceOrNull<T extends Object>({CCServiceKey<T>? key}) =>
      _runtime.serviceOrNull<T>(key: key);

  /// Resolves every registered implementation of service contract [T].
  ///
  /// Use when a caller intentionally composes all installed implementations.
  static List<T> services<T extends Object>() => _runtime.services<T>();

  /// Whether service contract [T] has a matching registration.
  ///
  /// Use for capability discovery without constructing the service instance.
  static bool hasService<T extends Object>({CCServiceKey<T>? key}) =>
      _runtime.hasService<T>(key: key);

  /// Dispatches [command] to its single handler.
  ///
  /// Use for one-to-one operations that intentionally change business state.
  static Future<R> command<R>(
    CCCommand<R> command, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _runtime.command(command, timeout: timeout, cancellation: cancellation);

  /// Dispatches [query] to its single handler.
  ///
  /// Use for one-to-one reads that should not intentionally change state.
  static Future<R> query<R>(
    CCQuery<R> query, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _runtime.query(query, timeout: timeout, cancellation: cancellation);

  /// Dispatches [action] to its handlers in stable identifier order.
  ///
  /// Use when multiple components may participate and the caller must await a
  /// deterministic aggregate completion report.
  static Future<CCActionReport> action(CCAction action) =>
      _runtime.action(action);

  /// Publishes [event] to isolated subscribers and awaits their completion.
  ///
  /// Use to announce an already completed fact without coupling the publisher
  /// to subscriber results; subscriber failures are isolated diagnostics.
  static Future<void> event(CCEvent event) => _runtime.event(event);

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

  /// Stops the default Runtime and releases all lifecycle-owned resources.
  ///
  /// Application hosts use this when permanently tearing down the current
  /// isolate or replacing its complete component assembly.
  ///
  /// Calling this method when no Runtime exists is a no-op.
  static Future<void> shutdown() async {
    if (_initializing != null) await _initializing;
    final existingShutdown = _shuttingDown;
    if (existingShutdown != null) return existingShutdown;
    final active = _defaultRuntime;
    if (active == null) return;

    _defaultRuntime = null;
    final shuttingDown = active.dispose();
    _shuttingDown = shuttingDown;
    try {
      await shuttingDown;
    } finally {
      if (identical(_shuttingDown, shuttingDown)) _shuttingDown = null;
    }
  }
}
