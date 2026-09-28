import 'package:ccrouter/ccrouter.dart';

import 'demo_kv_storage_component.dart';
import 'storage_client.dart';

/// Service contract for namespace-aware key-value storage.
@CCServiceContract(
  componentId: demoKvStorageComponentId,
  id: 'demo.kv_storage',
  description: 'Stores typed values in isolated application namespaces.',
)
abstract interface class DemoKeyValueStorageService {
  /// Stores a string.
  Future<void> setString(
    DemoStorageNamespace namespace,
    String key,
    String value,
  );

  /// Stores an integer.
  Future<void> setInt(DemoStorageNamespace namespace, String key, int value);

  /// Stores a double.
  Future<void> setDouble(
    DemoStorageNamespace namespace,
    String key,
    double value,
  );

  /// Stores a boolean.
  Future<void> setBool(DemoStorageNamespace namespace, String key, bool value);

  /// Stores a JSON object.
  Future<void> setJson(
    DemoStorageNamespace namespace,
    String key,
    Map<String, Object?> value,
  );

  /// Reads a string.
  Future<String?> getString(DemoStorageNamespace namespace, String key);

  /// Reads an integer.
  Future<int?> getInt(DemoStorageNamespace namespace, String key);

  /// Reads a double.
  Future<double?> getDouble(DemoStorageNamespace namespace, String key);

  /// Reads a boolean.
  Future<bool?> getBool(DemoStorageNamespace namespace, String key);

  /// Reads a JSON object.
  Future<Map<String, Object?>?> getJson(
    DemoStorageNamespace namespace,
    String key,
  );

  /// Removes one key.
  Future<void> remove(DemoStorageNamespace namespace, String key);

  /// Clears one namespace.
  Future<void> clear(DemoStorageNamespace namespace);

  /// Lists keys in one namespace.
  Future<List<String>> keys(DemoStorageNamespace namespace);
}

/// Default in-memory implementation used by the Demo.
@CCService()
final class DemoKeyValueStorageServiceImpl
    implements DemoKeyValueStorageService, CCDisposable {
  /// Creates an app-scoped in-memory storage service.
  DemoKeyValueStorageServiceImpl()
    : _client = CCStorageClient(backend: _MemoryStorageBackend());

  final CCStorageClient _client;

  @override
  Future<void> setString(
    DemoStorageNamespace namespace,
    String key,
    String value,
  ) => _client.setString(namespace, key, value);

  @override
  Future<void> setInt(DemoStorageNamespace namespace, String key, int value) =>
      _client.setInt(namespace, key, value);

  @override
  Future<void> setDouble(
    DemoStorageNamespace namespace,
    String key,
    double value,
  ) => _client.setDouble(namespace, key, value);

  @override
  Future<void> setBool(
    DemoStorageNamespace namespace,
    String key,
    bool value,
  ) => _client.setBool(namespace, key, value);

  @override
  Future<void> setJson(
    DemoStorageNamespace namespace,
    String key,
    Map<String, Object?> value,
  ) => _client.setJson(namespace, key, value);

  @override
  Future<String?> getString(DemoStorageNamespace namespace, String key) =>
      _client.getString(namespace, key);

  @override
  Future<int?> getInt(DemoStorageNamespace namespace, String key) =>
      _client.getInt(namespace, key);

  @override
  Future<double?> getDouble(DemoStorageNamespace namespace, String key) =>
      _client.getDouble(namespace, key);

  @override
  Future<bool?> getBool(DemoStorageNamespace namespace, String key) =>
      _client.getBool(namespace, key);

  @override
  Future<Map<String, Object?>?> getJson(
    DemoStorageNamespace namespace,
    String key,
  ) => _client.getJson(namespace, key);

  @override
  Future<void> remove(DemoStorageNamespace namespace, String key) =>
      _client.remove(namespace, key);

  @override
  Future<void> clear(DemoStorageNamespace namespace) =>
      _client.clear(namespace);

  @override
  Future<List<String>> keys(DemoStorageNamespace namespace) =>
      _client.keys(namespace);

  /// Releases the backend owned by the app-scoped Service.
  @override
  Future<void> dispose() async {
    await _client.dispose();
  }
}

final class _MemoryStorageBackend implements CCStorageBackend {
  final _values = <String, CCStorageValue>{};

  @override
  Future<void> write(String qualifiedKey, CCStorageValue value) async {
    _values[qualifiedKey] = value;
  }

  @override
  Future<CCStorageValue?> read(String qualifiedKey) async =>
      _values[qualifiedKey];

  @override
  Future<void> remove(String qualifiedKey) async {
    _values.remove(qualifiedKey);
  }

  @override
  Future<void> clear(String namespacePrefix) async {
    _values.removeWhere((key, _) => key.startsWith(namespacePrefix));
  }

  @override
  Future<List<String>> keys(String namespacePrefix) async => _values.keys
      .where((key) => key.startsWith(namespacePrefix))
      .toList(growable: false);

  @override
  Future<void> close() async {
    _values.clear();
  }
}
