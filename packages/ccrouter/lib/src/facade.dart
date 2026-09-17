import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';

/// Static business-facing entry point for all CCRouter capabilities.
abstract final class CCRouter {
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
  static bool get isInitialized => _defaultRuntime?.isInitialized ?? false;

  /// Snapshot of the active authenticated Session, if one exists.
  static CCSession? get session => _runtime.session;

  /// Component manifests installed in deterministic dependency order.
  static List<CCComponentManifest> get registeredComponents =>
      _runtime.components;

  /// Bounded immutable snapshot of recent invocation traces.
  static List<CCTraceRecord> get recentTraces => _runtime.recentTraces;

  /// Creates, initializes, and owns the application's default Runtime.
  ///
  /// A second call before [shutdown] completes throws
  /// [CCRouterAlreadyInitializedError].
  static Future<void> initialize({
    required Iterable<CCComponentManifest> components,
    int traceCapacity = 1000,
  }) async {
    if (_defaultRuntime != null ||
        _initializing != null ||
        _shuttingDown != null) {
      throw const CCRouterAlreadyInitializedError();
    }

    final runtime = CCRouterRuntime.forHost(
      components: components,
      traceCapacity: traceCapacity,
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
  static T service<T extends Object>({CCServiceKey<T>? key}) =>
      _runtime.service<T>(key: key);

  /// Resolves service contract [T], returning null only when it is unregistered.
  static T? serviceOrNull<T extends Object>({CCServiceKey<T>? key}) =>
      _runtime.serviceOrNull<T>(key: key);

  /// Resolves every registered implementation of service contract [T].
  static List<T> services<T extends Object>() => _runtime.services<T>();

  /// Whether service contract [T] has a matching registration.
  static bool hasService<T extends Object>({CCServiceKey<T>? key}) =>
      _runtime.hasService<T>(key: key);

  /// Dispatches [command] to its single handler.
  static Future<R> command<R>(
    CCCommand<R> command, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _runtime.command(command, timeout: timeout, cancellation: cancellation);

  /// Dispatches [query] to its single handler.
  static Future<R> query<R>(
    CCQuery<R> query, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _runtime.query(query, timeout: timeout, cancellation: cancellation);

  /// Dispatches [action] to its handlers in stable identifier order.
  static Future<CCActionReport> action(CCAction action) =>
      _runtime.action(action);

  /// Publishes [event] to isolated subscribers and awaits their completion.
  static Future<void> event(CCEvent event) => _runtime.event(event);

  /// Opens one authenticated account Session.
  ///
  /// The existing Session must be fully closed before another can be opened.
  static void openSession({
    required String accountId,
    Map<String, Object?> metadata = const {},
  }) => _runtime.openSession(accountId: accountId, metadata: metadata);

  /// Closes the active Session and disposes all Session-owned resources.
  static Future<void> closeSession() => _runtime.closeSession();

  /// Stops the default Runtime and releases all lifecycle-owned resources.
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
