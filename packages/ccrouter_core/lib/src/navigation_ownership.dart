part of 'runtime.dart';

/// Captures the Host registrations visited by one navigation operation.
///
/// A logical Host ID can be reused after detach; its cancellation token cannot.
/// Losing any visited registration ends the operation, including recovery and
/// deferred replay. This record owns only listener removers, never UI payloads.
final class _NavigationOperationLifetime {
  /// Cancellation shared by all policy waits belonging to this operation.
  final CCCancellationToken cancellation = CCCancellationToken();

  /// Host registration tokens captured before policy or backend work begins.
  final Map<String, CCCancellationToken> hosts = {};

  /// Listener removers released when the original navigation Future settles.
  final List<void Function()> _removers = [];

  /// Binds one concrete registration without allowing a detached one to revive.
  void bind(String hostId, CCCancellationToken registration) {
    ensureAlive();
    if (hosts.containsKey(hostId)) return;
    hosts[hostId] = registration;
    _removers.add(registration.addListener(cancellation.cancel));
    ensureAlive();
  }

  /// Rejects late policy, resolution and backend work after Host removal.
  void ensureAlive() {
    if (cancellation.isCancelled) {
      throw const CCRouteCancelledError('host_detached');
    }
  }

  /// Releases registration listeners even when a caller retains a late Future.
  void release() {
    for (final remove in _removers) {
      remove();
    }
    _removers.clear();
    hosts.clear();
  }
}

/// Keeps navigation lifecycle ownership internal to the Runtime library.
extension CCRouterRuntimeNavigationOwnership on CCRouterRuntime {
  /// Operation propagated by identity without retaining the owning Runtime.
  _NavigationOperationLifetime? get _navigationOperation {
    final current = Zone.current[CCRouterRuntime._navigationOwnershipZoneKey];
    return current is (Object, _NavigationOperationLifetime) &&
            identical(current.$1, _zoneIdentity)
        ? current.$2
        : null;
  }

  /// Runs one original operation and releases its registration links on exit.
  Future<T> _withNavigationOwnership<T>(Future<T> Function() action) async {
    final lifetime = _NavigationOperationLifetime();
    try {
      return await _inNavigationOwnership(lifetime, action);
    } finally {
      lifetime.release();
    }
  }

  /// Restores an operation by non-owning identity when replay changes caller.
  Future<T> _inNavigationOwnership<T>(
    _NavigationOperationLifetime? lifetime,
    Future<T> Function() action,
  ) => runZoned(
    action,
    zoneValues: {
      CCRouterRuntime._navigationOwnershipZoneKey: lifetime == null
          ? null
          : (_zoneIdentity, lifetime),
    },
  );

  /// Captures a non-reusable registration before entering asynchronous work.
  CCCancellationToken _bindNavigationHost(String hostId) {
    _navigationOperation?.ensureAlive();
    final registration = _navigationHostRegistration(hostId);
    _navigationOperation?.bind(hostId, registration);
    return registration;
  }

  /// Allocates Host ownership in Host context, independent of its first caller.
  ///
  /// A token owns a Future and therefore its creation Zone. Retaining a token
  /// must not retain the first navigation or Pop caller for the Host's lifetime.
  CCCancellationToken _navigationHostRegistration(String hostId) =>
      _navigationHostRegistrations.putIfAbsent(
        hostId,
        () => _hostZone.run(CCCancellationToken.new),
      );

  /// Ends the old registration before an identical logical ID can be reused.
  void _detachNavigationHost(String hostId) {
    final registration = _navigationHostRegistrations.remove(hostId);
    _inFlightNavigation.removeWhere((key, _) => key.hostId == hostId);
    try {
      registration?.cancel();
    } catch (error) {
      _recordNavigationCallbackFailure(
        'Host cancellation listener failed: ${error.runtimeType}.',
      );
    }
  }
}
