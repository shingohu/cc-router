part of 'runtime.dart';

/// Isolated state for one Service initializer and its active dependency waits.
///
/// A pending Future retains this small record rather than its owning Scope, so
/// an initializer that ignores cooperative cancellation cannot by itself keep
/// every Scope-owned instance reachable after the Scope clears its map. A
/// singleton shares this record; new-instance providers allocate a fresh one.
/// Ending the concrete initializer owner settles readiness immediately and
/// removes its listener; a late business Future cannot change that outcome.
final class _ServiceReadinessRecord {
  /// Completion installed before initialization or dependency traversal starts.
  final _SharedResult<void> _completion = _SharedResult<void>();

  /// Whether the operation completed successfully before Scope cancellation.
  bool ready = false;

  /// Whether this initializer still participates in active readiness waits.
  bool active = true;

  /// Counted edges preserve overlapping resolutions of the same dependency.
  final Map<_ServiceReadinessRecord, int> _dependencies = {};

  /// Detaches owner cancellation when readiness reaches its first terminal state.
  void Function()? _removeCancellation;

  /// Starts initialization after its Future and incoming wait edge are installed.
  void start(
    Future<void> Function() initialize,
    CCCancellationToken token,
    String scopeId,
  ) {
    final remove = token.addListener(
      () => _fail(CCScopeClosedError(scopeId), StackTrace.current),
    );
    // Registration may synchronously observe an already-ended owner.
    if (!active) {
      remove();
      return;
    }
    _removeCancellation = remove;
    unawaited(
      Future<void>.sync(initialize).then<void>(_succeed, onError: _fail),
    );
  }

  /// Releases wait edges and the owner listener before publishing an outcome.
  void _deactivate() {
    active = false;
    _dependencies.clear();
    final remove = _removeCancellation;
    _removeCancellation = null;
    remove?.call();
  }

  /// Accepts success only while the concrete initializer owner is still live.
  void _succeed(void _) {
    if (!active) return;
    ready = true;
    _deactivate();
    _completion.complete(null);
  }

  /// Settles owner cancellation or failure once and consumes late failures.
  void _fail(Object error, StackTrace stack) {
    if (!active) return;
    _deactivate();
    _completion.fail(error, stack);
  }

  /// Waits through a removable relay and, for initializers, a temporary edge.
  ///
  /// Independent invocation cancellation releases its caller Zone without
  /// ending shared initialization. Live dependency edges still reject cycles.
  Future<void> waitFor(
    _ServiceReadinessRecord? owner,
    String identity,
    CCCancellationToken waitCancellation,
  ) async {
    if (owner == null || !owner.active || !active) {
      return _completion.wait(cancellation: waitCancellation);
    }
    if (_reaches(owner, {})) {
      throw CCCircularServiceDependencyError(identity);
    }
    owner._dependencies.update(this, (count) => count + 1, ifAbsent: () => 1);
    var linked = true;
    void unlink() {
      if (!linked) return;
      linked = false;
      final count = owner._dependencies[this];
      if (count == 1) {
        owner._dependencies.remove(this);
      } else if (count != null) {
        owner._dependencies[this] = count - 1;
      }
    }

    final remove = waitCancellation.addListener(unlink);
    try {
      await _completion.wait(cancellation: waitCancellation);
    } finally {
      unlink();
      remove();
    }
  }

  /// Traverses only live initializer edges; completed records cannot form cycles.
  bool _reaches(
    _ServiceReadinessRecord target,
    Set<_ServiceReadinessRecord> visited,
  ) {
    if (!active || !visited.add(this)) return false;
    if (identical(this, target)) return true;
    return _dependencies.keys.any((next) => next._reaches(target, visited));
  }
}

/// Internal lifecycle state of an instance-owning Scope.
///
/// Runtime internals use these states to reject new work as soon as cleanup
/// begins and to make repeated close operations deterministic.
enum CCScopeState {
  /// Accepts new resolutions and owns live instances.
  active,

  /// Rejects new resolutions while disposing existing instances.
  closing,

  /// Has released all owned instances.
  closed,
}

/// Owns service instances, cancellation, and disposal for one lifecycle.
///
/// The Runtime creates scopes for App and Session lifetimes now, and uses the
/// same ownership model for Route lifetimes. Business and
/// component code must not create or close scopes directly.
final class CCScope {
  /// Creates an active Scope with the stable [id].
  CCScope(this.id);

  /// Stable diagnostic identity of this Scope.
  final String id;

  /// Owning Host context for retained records and shared initializer producers.
  ///
  /// A Scope's first consumer may have a shorter lifetime and a different error
  /// Zone. Cached completion Futures must not adopt that consumer's Zone.
  final Zone _ownerZone = Zone.current;

  /// Cached singleton instances indexed by provider identity.
  final Map<Object, Object> _instances = {};

  /// Disposable instances in construction order.
  final List<CCDisposable> _disposables = [];

  /// Provider keys currently being constructed for cycle detection.
  final Set<Object> _constructing = {};

  /// Joins synchronous factories that reentrantly request Scope closure.
  Completer<void>? _constructionDrained;

  /// Single-flight readiness records retained for singleton providers.
  final Map<Object, _ServiceReadinessRecord> _serviceReadiness = {};

  /// Cancellation signal shared by work owned by this Scope.
  final CCCancellationToken cancellation = CCCancellationToken();

  /// Cancellation and disposal failures retained without blocking cleanup.
  final List<Object> disposalErrors = [];

  /// Current mutable lifecycle state.
  CCScopeState _state = CCScopeState.active;

  /// Memoized close operation that makes close idempotent.
  Future<void>? _closeFuture;

  /// Current lifecycle state.
  CCScopeState get state => _state;

  /// Returns a cached instance for [key] or owns a newly created one.
  ///
  /// Runtime service resolution uses this to enforce per-Scope singleton and
  /// factory ownership while detecting recursive construction.
  /// A factory that closes this Scope still transfers its returned disposable
  /// to cleanup before lookup fails. Closure joins all admitted constructions.
  T resolve<T extends Object>(
    Object key,
    T Function() create, {
    bool cache = true,
  }) {
    _ensureActive();
    final existing = _instances[key];
    if (cache && existing != null) return existing as T;
    if (!_constructing.add(key)) {
      throw CCCircularServiceDependencyError(key.toString());
    }
    try {
      final value = create();
      // Construction may synchronously close this Scope. The reserved factory
      // still transfers a returned resource into cleanup before lookup fails.
      _retainDisposable(value);
      _ensureActive();
      if (cache) _instances[key] = value;
      return value;
    } finally {
      _constructing.remove(key);
      if (_constructing.isEmpty) {
        _constructionDrained?.complete();
        _constructionDrained = null;
      }
    }
  }

  /// Adds [instance] to this Scope's disposal ownership.
  ///
  /// Runtime construction uses this for newly created factory and cached
  /// services so [CCDisposable] instances participate in Scope cleanup.
  T own<T extends Object>(T instance) {
    _ensureActive();
    _retainDisposable(instance);
    return instance;
  }

  /// Records exactly-once cleanup, including a closing factory's late return.
  void _retainDisposable(Object instance) {
    if (instance is CCDisposable &&
        !_disposables.any((item) => identical(item, instance))) {
      _disposables.add(instance);
    }
  }

  /// Whether the singleton identified by [key] completed initialization.
  bool isServiceReady(Object key) => _serviceReadiness[key]?.ready ?? false;

  /// Runs one cached readiness operation for the singleton [key].
  ///
  /// Success and failure are both stable for this Scope lifetime. Runtime does
  /// not retry failed initialization implicitly because initializers may have
  /// externally visible side effects; retry belongs inside the initializer.
  /// Retained records and shared producer execution use the Scope's Host Zone;
  /// independent consumer waits still deliver results in their own error Zone.
  Future<void> ensureServiceReady(
    Object key,
    Future<void> Function(_ServiceReadinessRecord record) initialize, {
    required _ServiceReadinessRecord? owner,
    required String identity,
    required CCCancellationToken waitCancellation,
  }) {
    _ensureActive();
    final existing = _serviceReadiness[key];
    if (existing != null)
      return existing.waitFor(owner, identity, waitCancellation);
    final record = _ownerZone.run(_ServiceReadinessRecord.new);
    _serviceReadiness[key] = record;
    final waiting = record.waitFor(owner, identity, waitCancellation);
    _ownerZone.run(
      () => record.start(() => initialize(record), cancellation, id),
    );
    return waiting;
  }

  /// Cancels owned work and disposes instances in reverse construction order.
  ///
  /// Runtime lifecycle transitions call this on Session close and final host
  /// shutdown; callers must not use it merely because the App is backgrounded.
  /// Cancellation listeners and disposables may fail independently: errors
  /// enter [disposalErrors], while all remaining resources are still released.
  /// Reentrant closes join the operation established before callbacks run.
  Future<void> close({Duration timeout = const Duration(seconds: 5)}) {
    if (_closeFuture != null) return _closeFuture!;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    _state = CCScopeState.closing;
    try {
      cancellation.cancel();
    } catch (error) {
      disposalErrors.add(error);
    }
    completion.complete(_dispose(timeout));
    return completion.future;
  }

  /// Runs isolated, timeout-bounded disposal for every owned instance.
  Future<void> _dispose(Duration timeout) async {
    if (_constructing.isNotEmpty) {
      _constructionDrained ??= Completer<void>();
      await _constructionDrained!.future;
    }
    for (final disposable in _disposables.reversed) {
      try {
        await Future<void>.sync(disposable.dispose).timeout(timeout);
      } catch (error) {
        disposalErrors.add(error);
      }
    }
    _instances.clear();
    _disposables.clear();
    _serviceReadiness.clear();
    _state = CCScopeState.closed;
  }

  /// Throws when this Scope no longer accepts ownership operations.
  void _ensureActive() {
    if (_state != CCScopeState.active) throw CCScopeClosedError(id);
  }
}
