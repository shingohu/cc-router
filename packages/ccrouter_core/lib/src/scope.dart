part of 'runtime.dart';

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
/// The Runtime creates scopes for App, Session, and Component lifetimes now,
/// and will use the same ownership model for Route lifetimes. Business and
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

  /// Cancellation signal shared by work owned by this Scope.
  final CCCancellationToken cancellation = CCCancellationToken();

  /// Disposal failures retained without blocking remaining cleanup.
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

  /// Cancels owned work and disposes instances in reverse construction order.
  ///
  /// Runtime lifecycle transitions call this on Session close and final host
  /// shutdown; callers must not use it merely because the App is backgrounded.
  Future<void> close({Duration timeout = const Duration(seconds: 5)}) {
    if (_closeFuture != null) return _closeFuture!;
    _state = CCScopeState.closing;
    cancellation.cancel();
    return _closeFuture = _dispose(timeout);
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
    _state = CCScopeState.closed;
  }

  /// Throws when this Scope no longer accepts ownership operations.
  void _ensureActive() {
    if (_state != CCScopeState.active) throw CCScopeClosedError(id);
  }
}
