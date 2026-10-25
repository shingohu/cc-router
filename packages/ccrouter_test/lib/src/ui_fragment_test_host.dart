import 'dart:async';

import 'package:ccrouter/ccrouter_host.dart';

/// Cleanup errors carried as data so each caller receives them in its own Zone.
typedef _UIFragmentTestCleanupFailure = ({Object error, StackTrace stackTrace});

/// Runs a Fragment test through the real process-default Host lifecycle.
///
/// Pass the complete generated Assembly, optionally adapted through
/// [CCHostAssembly.extend]. Renderers, Contract validation and Action revocation
/// use their production paths. This helper does not install a Zone overlay or
/// isolate concurrent default Hosts. Existing Hosts and overlays are rejected
/// without taking ownership. Each helper is single-use.
/// Register `addTearDown(host.dispose)` before [run]: test timeouts do not cancel
/// Dart Futures, so its ordinary `finally` may never execute.
final class CCUIFragmentTestHost {
  /// Captures immutable inputs without allocating a Runtime or mounting UI.
  ///
  /// Call [run] inside `testWidgets`, so Host-owned Timers use that test's fake
  /// scheduler. Tests drive startup/request time explicitly with `tester.pump`.
  CCUIFragmentTestHost({required CCHostAssembly hostAssembly})
    : _hostAssembly = hostAssembly;

  /// Complete production assembly; no Renderer or Contract data is reconstructed.
  final CCHostAssembly _hostAssembly;

  /// Fences overlapping or repeated execution before any Host is acquired.
  bool _used = false;

  /// Terminal admission fence, including disposal requested during startup.
  bool _disposed = false;

  /// Defers reentrant cleanup until synchronous initialization has unwound.
  bool _initializing = false;

  /// True only after the complete owned Host initialized successfully.
  bool _initialized = false;

  /// Non-owning identity used to avoid closing an unrelated default Host.
  _UIFragmentTestOwnership? _ownership;

  /// Caller-owned UI cleanup, released as soon as disposal takes it.
  Future<void> Function()? _unmount;

  /// Once-only cleanup outcome, shared as success data across error Zones.
  Future<_UIFragmentTestCleanupFailure?>? _disposal;

  /// Allows late teardown to replay data without scheduling in an ended fake Zone.
  bool _cleanupFinished = false;

  /// Original cleanup outcome retained without the completed Future's scheduler.
  _UIFragmentTestCleanupFailure? _cleanupFailure;

  /// Reserved before user cleanup can reenter; started after startup unwinds.
  Completer<_UIFragmentTestCleanupFailure?>? _pendingDisposal;

  /// Initializes, awaits [body], unmounts UI, and awaits owned Host shutdown.
  ///
  /// Supply `unmount: () => tester.pumpWidget(const SizedBox())` in Widget tests.
  /// [unmount] runs after [body] succeeds or fails, including when it throws
  /// before mounting anything. It is not called when initialization fails.
  /// Await all work started by [body]; arbitrary business Futures are not
  /// cancelled by the helper. Renderer resources remain Flutter State-owned.
  /// Register [dispose] with `addTearDown` before calling this method, so a
  /// framework timeout can release the Host while [body] is still pending.
  ///
  /// Cleanup continues through unmount errors. The earliest initialization,
  /// body, unmount or shutdown error is rethrown with its original stack.
  /// Initialization rollback is joined before returning. If the owned Host was
  /// explicitly shut down and replaced, cleanup never shuts down its replacement.
  Future<void> run(
    Future<void> Function() body, {
    required Future<void> Function() unmount,
  }) async {
    if (_used || _disposed) {
      throw StateError(
        'CCUIFragmentTestHost is single-use and may be disposed.',
      );
    }
    _used = true;
    final ownership = _ownership = _UIFragmentTestOwnership();
    _UIFragmentTestCleanupFailure? failure;
    try {
      _initializing = true;
      try {
        CCRouterHost.initialize(
          hostAssembly: CCHostAssembly.withLifecycleBindings(_hostAssembly, [
            ownership,
          ]),
        );
        _initialized = true;
        _unmount = unmount;
        // The async frame retains parameters while body is pending. Transfer
        // ownership so dispose can release the caller even before body ends.
        unmount = _releasedUnmount;
      } finally {
        _initializing = false;
        _startDisposal();
      }
      if (_disposed) {
        throw StateError('CCUIFragmentTestHost was disposed during startup.');
      }
      await body();
    } catch (error, stackTrace) {
      failure = (error: error, stackTrace: stackTrace);
    } finally {
      try {
        await dispose();
      } catch (error, stackTrace) {
        failure ??= (error: error, stackTrace: stackTrace);
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }

  /// Noncapturing placeholder for the transferred async-frame callback parameter.
  static Future<void> _releasedUnmount() async {}

  /// Unmounts UI and closes the owned Host without waiting for the test body.
  ///
  /// Register `addTearDown(host.dispose)` before [run] to cover framework timeouts.
  /// Normal completion and teardown join the same cleanup; unmount and shutdown
  /// execute once. Disposal before [run] allocates nothing and prevents startup.
  /// Disposal requested synchronously during initialization waits for startup
  /// to unwind, closes any acquired Host and prevents [run] from entering its body.
  ///
  /// Concurrent, reentrant and late callers receive the first cleanup error and
  /// original stack in their own error Zone. Handle each returned Future. If a
  /// test asserts cleanup failure, its registered teardown must handle it too.
  /// Never await disposal from this helper's own unmount or owned disposables.
  /// [run] preserves a body failure over a cleanup failure. A pending business
  /// Future is not cancelled, and late body completion cannot repeat cleanup or
  /// close a replacement Host. The caller's unmount must itself complete.
  /// Completed cleanup releases the helper's references to the unmount callback
  /// even if the body Future is still pending; application captures remain owned
  /// by the application.
  Future<void> dispose() {
    if (_cleanupFinished) {
      return Future<void>.sync(() => _throwCleanupFailure(_cleanupFailure));
    }
    final existing = _disposal;
    if (existing != null) return _joinDisposal(existing);
    final completion = Completer<_UIFragmentTestCleanupFailure?>();
    _disposal = completion.future;
    _pendingDisposal = completion;
    _disposed = true;
    _startDisposal();
    return _joinDisposal(completion.future);
  }

  /// Starts reserved cleanup only after synchronous startup has relinquished it.
  void _startDisposal() {
    final completion = _pendingDisposal;
    if (_initializing || completion == null) return;
    _pendingDisposal = null;
    completion.complete(_captureDisposal());
  }

  /// Clears caller references and records cleanup failures without error Futures.
  Future<_UIFragmentTestCleanupFailure?> _captureDisposal() async {
    final unmount = _unmount;
    _unmount = null;
    final ownership = _ownership;
    _ownership = null;
    _UIFragmentTestCleanupFailure? failure;
    if (unmount != null) {
      try {
        await unmount();
      } catch (error, stackTrace) {
        failure = (error: error, stackTrace: stackTrace);
      }
    }
    // Failed Runtime startup already detached its marker, but may still be
    // rolling back. Rejected foreign Hosts never attached it. A normal owned
    // Host can be replaced during unmount, so check its marker after the await.
    if (ownership != null &&
        (ownership.attached || (!_initialized && ownership.wasAttached))) {
      try {
        await CCRouterHost.shutdown();
      } catch (error, stackTrace) {
        failure ??= (error: error, stackTrace: stackTrace);
      }
    }
    _cleanupFailure = failure;
    _cleanupFinished = true;
    _disposal = null;
    return failure;
  }

  /// Recreates an error only in the joining caller's current error Zone.
  static Future<void> _joinDisposal(
    Future<_UIFragmentTestCleanupFailure?> completion,
  ) async {
    final failure = await completion;
    _throwCleanupFailure(failure);
  }

  /// Restores the original failure in the current caller without scheduling work.
  static void _throwCleanupFailure(_UIFragmentTestCleanupFailure? failure) {
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }
}

/// Non-owning generation marker; it retains no Widget, Runtime or callbacks.
final class _UIFragmentTestOwnership implements CCHostLifecycleBinding {
  /// Creates a detached marker for exactly one helper execution.
  _UIFragmentTestOwnership();

  /// Records whether initialization reached this helper's capability plan.
  bool wasAttached = false;

  /// Remains true only while the exact owned Host generation is installed.
  bool attached = false;

  /// Reserves one test owner per assembly; duplicate plans remain invalid.
  @override
  String get id => 'ccrouter.test.ui';

  /// Marks provisional ownership before Runtime construction starts.
  @override
  void attach() {
    wasAttached = true;
    attached = true;
  }

  /// Clears identity before rollback or shutdown can admit another Host.
  @override
  void detach() => attached = false;
}
