import 'storage_client.dart';
import 'storage_service.dart';

/// Supplies the current account, API environment, and device context to the
/// storage facade.
///
/// The provider is owned by the Host or composition root. Storage reads the
/// latest snapshot for each operation and never owns authentication, account,
/// environment, or device state.
abstract interface class DemoStorageContextProvider {
  /// Returns the immutable context used by the next storage operation.
  DemoStorageContextSnapshot get current;
}

/// Immutable context used to resolve dynamic storage scopes.
final class DemoStorageContextSnapshot {
  /// Creates a context with optional authenticated account and required
  /// environment/device identities.
  const DemoStorageContextSnapshot({
    required this.environmentId,
    required this.deviceId,
    this.accountId,
  }) : assert(environmentId != '', 'Storage environment cannot be empty.'),
       assert(deviceId != '', 'Storage device cannot be empty.');

  /// Account identity, or `null` while the current Session is a guest.
  final String? accountId;

  /// Current validated API environment.
  final String environmentId;

  /// Current device identity.
  final String deviceId;

  /// Whether the current context has no authenticated account.
  bool get isGuest => accountId == null;
}

/// Raised when a dynamic storage scope has no valid current context.
final class DemoStorageContextError extends StateError {
  /// Creates an error for [scope].
  DemoStorageContextError(this.scope)
    : super('Storage context is unavailable for $scope.');

  /// Scope that could not be resolved.
  final String scope;
}

/// Mutable provider used by a Host or deterministic Demo test.
final class DemoMutableStorageContextProvider
    implements DemoStorageContextProvider {
  /// Creates a provider with an initial context.
  DemoMutableStorageContextProvider(this._current);

  DemoStorageContextSnapshot _current;

  @override
  DemoStorageContextSnapshot get current => _current;

  /// Replaces the complete context atomically for subsequent operations.
  void update(DemoStorageContextSnapshot value) {
    _current = value;
  }
}

/// Business-facing storage facade that resolves namespaces from current
/// application context instead of requiring IDs at every call site.
final class DemoScopedStorage {
  /// Creates a facade over the low-level [service] and [contextProvider].
  DemoScopedStorage({
    required DemoKeyValueStorageService service,
    required DemoStorageContextProvider contextProvider,
  }) : _service = service,
       _contextProvider = contextProvider;

  final DemoKeyValueStorageService _service;
  final DemoStorageContextProvider _contextProvider;

  /// Storage independent of account, environment, and device state.
  DemoStorageScope get global =>
      DemoStorageScope._(_service, () => const DemoStorageNamespace.global());

  /// Storage for the unauthenticated visitor.
  DemoStorageScope get guest =>
      DemoStorageScope._(_service, () => const DemoStorageNamespace.guest());

  /// Storage for the account in the latest context snapshot.
  DemoStorageScope get currentUser => DemoStorageScope._(_service, () {
    final accountId = _contextProvider.current.accountId;
    if (accountId == null || accountId.isEmpty) {
      throw DemoStorageContextError('currentUser');
    }
    return DemoStorageNamespace.user(accountId);
  });

  /// Storage for the API environment in the latest context snapshot.
  DemoStorageScope get currentEnvironment => DemoStorageScope._(
    _service,
    () => DemoStorageNamespace.apiEnvironment(
      _contextProvider.current.environmentId,
    ),
  );

  /// Storage for the device in the latest context snapshot.
  DemoStorageScope get hardware => DemoStorageScope._(
    _service,
    () => DemoStorageNamespace.hardware(_contextProvider.current.deviceId),
  );
}

/// Typed operations bound to one dynamically resolved storage scope.
final class DemoStorageScope {
  DemoStorageScope._(this._service, this._namespaceResolver);

  final DemoKeyValueStorageService _service;
  final DemoStorageNamespace Function() _namespaceResolver;

  /// Stores a string under [key].
  Future<void> setString(String key, String value) =>
      _service.setString(_namespaceResolver(), key, value);

  /// Stores an integer under [key].
  Future<void> setInt(String key, int value) =>
      _service.setInt(_namespaceResolver(), key, value);

  /// Stores a double under [key].
  Future<void> setDouble(String key, double value) =>
      _service.setDouble(_namespaceResolver(), key, value);

  /// Stores a boolean under [key].
  Future<void> setBool(String key, bool value) =>
      _service.setBool(_namespaceResolver(), key, value);

  /// Stores a JSON object under [key].
  Future<void> setJson(String key, Map<String, Object?> value) =>
      _service.setJson(_namespaceResolver(), key, value);

  /// Reads a string under [key].
  Future<String?> getString(String key) =>
      _service.getString(_namespaceResolver(), key);

  /// Reads an integer under [key].
  Future<int?> getInt(String key) => _service.getInt(_namespaceResolver(), key);

  /// Reads a double under [key].
  Future<double?> getDouble(String key) =>
      _service.getDouble(_namespaceResolver(), key);

  /// Reads a boolean under [key].
  Future<bool?> getBool(String key) =>
      _service.getBool(_namespaceResolver(), key);

  /// Reads a JSON object under [key].
  Future<Map<String, Object?>?> getJson(String key) =>
      _service.getJson(_namespaceResolver(), key);

  /// Removes [key].
  Future<void> remove(String key) => _service.remove(_namespaceResolver(), key);

  /// Clears this scope.
  Future<void> clear() => _service.clear(_namespaceResolver());

  /// Lists keys in this scope.
  Future<List<String>> keys() => _service.keys(_namespaceResolver());
}
