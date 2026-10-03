part of 'runtime.dart';

/// Isolated state for one Service initializer and its active dependency waits.
///
/// A pending Future retains this small record rather than its owning Scope, so
/// an initializer that ignores cooperative cancellation cannot by itself keep
/// every Scope-owned instance reachable after the Scope clears its map. A
/// singleton shares this record; new-instance providers allocate a fresh one.
final class _ServiceReadinessRecord {
  /// Completion installed before initialization or dependency traversal starts.
  final Completer<void> _completion = Completer<void>();

  /// Readiness operation shared by concurrent callers.
  Future<void> get future => _completion.future;

  /// Whether the operation completed successfully before Scope cancellation.
  bool ready = false;

  /// Whether this initializer still participates in active readiness waits.
  bool active = true;

  /// Counted edges preserve overlapping resolutions of the same dependency.
  final Map<_ServiceReadinessRecord, int> _dependencies = {};

  /// Starts initialization after its Future and incoming wait edge are installed.
  void start(
    Future<void> Function() initialize,
    CCCancellationToken token,
    String scopeId,
  ) {
    final completion = _completion;
    void deactivate() {
      active = false;
      _dependencies.clear();
    }

    final removeCancellation = token.addListener(deactivate);
    void finish() {
      deactivate();
      removeCancellation();
    }

    unawaited(
      Future<void>.sync(initialize).then<void>(
        (_) {
          finish();
          if (token.isCancelled) {
            completion.completeError(CCScopeClosedError(scopeId));
          } else {
            ready = true;
            completion.complete();
          }
        },
        onError: (Object error, StackTrace stack) {
          finish();
          completion.completeError(error, stack);
        },
      ),
    );
  }

  /// Waits through a temporary edge, rejecting cycles between independent roots.
  Future<void> waitFor(
    _ServiceReadinessRecord? owner,
    String identity,
    CCCancellationToken waitCancellation,
  ) async {
    if (owner == null || !owner.active || !active) return future;
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

    final cancelled = Completer<void>();
    final remove = waitCancellation.addListener(() {
      unlink();
      cancelled.completeError(const CCInvocationCancelledError());
    });
    try {
      await Future.any([future, cancelled.future]);
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

  /// Cached singleton instances indexed by provider identity.
  final Map<Object, Object> _instances = {};

  /// Disposable instances in construction order.
  final List<CCDisposable> _disposables = [];

  /// Provider keys currently being constructed for cycle detection.
  final Set<Object> _constructing = {};

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
      final value = own(create());
      if (cache) _instances[key] = value;
      return value;
    } finally {
      _constructing.remove(key);
    }
  }

  /// Adds [instance] to this Scope's disposal ownership.
  ///
  /// Runtime construction uses this for newly created factory and cached
  /// services so [CCDisposable] instances participate in Scope cleanup.
  T own<T extends Object>(T instance) {
    _ensureActive();
    if (instance is CCDisposable &&
        !_disposables.any((item) => identical(item, instance))) {
      _disposables.add(instance);
    }
    return instance;
  }

  /// Whether the singleton identified by [key] completed initialization.
  bool isServiceReady(Object key) => _serviceReadiness[key]?.ready ?? false;

  /// Runs one cached readiness operation for the singleton [key].
  ///
  /// Success and failure are both stable for this Scope lifetime. Runtime does
  /// not retry failed initialization implicitly because initializers may have
  /// externally visible side effects; retry belongs inside the initializer.
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
    final record = _ServiceReadinessRecord();
    _serviceReadiness[key] = record;
    final waiting = record.waitFor(owner, identity, waitCancellation);
    record.start(() => initialize(record), cancellation, id);
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
