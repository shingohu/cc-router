import 'dart:async';

import 'package:ccrouter/ccrouter.dart';

/// Storage namespaces supported by the Demo component.
enum CCStorageNamespaceKind { global, guest, user, apiEnvironment, hardware }

/// Identifies one isolated storage namespace.
final class DemoStorageNamespace {
  /// Namespace that is independent of account, environment, and device state.
  const DemoStorageNamespace.global()
    : kind = CCStorageNamespaceKind.global,
      identifier = 'global';

  /// Namespace for data owned by an unauthenticated visitor.
  const DemoStorageNamespace.guest()
    : kind = CCStorageNamespaceKind.guest,
      identifier = 'guest';

  /// Namespace for one authenticated account.
  factory DemoStorageNamespace.user(String userId) =>
      DemoStorageNamespace._(CCStorageNamespaceKind.user, userId);

  /// Namespace for one API environment such as development or production.
  factory DemoStorageNamespace.apiEnvironment(String environmentId) =>
      DemoStorageNamespace._(
        CCStorageNamespaceKind.apiEnvironment,
        environmentId,
      );

  /// Namespace for one physical device's local configuration.
  factory DemoStorageNamespace.hardware(String deviceId) =>
      DemoStorageNamespace._(CCStorageNamespaceKind.hardware, deviceId);

  const DemoStorageNamespace._(this.kind, this.identifier)
    : assert(identifier != '', 'Storage namespace identifier cannot be empty.');

  /// Namespace category.
  final CCStorageNamespaceKind kind;

  /// Stable identifier inside the category.
  final String identifier;

  /// Sanitized backend prefix used to isolate keys.
  String get storageId => '${kind.name}:$identifier';

  @override
  bool operator ==(Object other) =>
      other is DemoStorageNamespace &&
      other.kind == kind &&
      other.identifier == identifier;

  @override
  int get hashCode => Object.hash(kind, identifier);

  @override
  String toString() => storageId;
}

/// Value kinds accepted by the storage component.
enum CCStorageValueKind { string, integer, doubleValue, boolean, json }

/// A typed value exchanged between the storage client and its backend.
final class CCStorageValue {
  /// Creates a string value.
  const CCStorageValue.string(String value)
    : kind = CCStorageValueKind.string,
      raw = value;

  /// Creates an integer value.
  const CCStorageValue.integer(int value)
    : kind = CCStorageValueKind.integer,
      raw = value;

  /// Creates a double value.
  const CCStorageValue.doubleValue(double value)
    : kind = CCStorageValueKind.doubleValue,
      raw = value;

  /// Creates a boolean value.
  const CCStorageValue.boolean(bool value)
    : kind = CCStorageValueKind.boolean,
      raw = value;

  /// Creates a JSON object and defensively copies nested values.
  factory CCStorageValue.json(Map<String, Object?> value) {
    _validateJson(value);
    return CCStorageValue._(CCStorageValueKind.json, _copyJson(value));
  }

  const CCStorageValue._(this.kind, this.raw);

  /// Stored value kind.
  final CCStorageValueKind kind;

  /// Raw typed value. Use the typed getters where possible.
  final Object raw;

  /// Reads this value as a string or throws on a type mismatch.
  String get string => _read<String>(CCStorageValueKind.string);

  /// Reads this value as an integer or throws on a type mismatch.
  int get integer => _read<int>(CCStorageValueKind.integer);

  /// Reads this value as a double or throws on a type mismatch.
  double get doubleValue => _read<double>(CCStorageValueKind.doubleValue);

  /// Reads this value as a boolean or throws on a type mismatch.
  bool get boolean => _read<bool>(CCStorageValueKind.boolean);

  /// Reads a defensive copy of this value as a JSON object.
  Map<String, Object?> get json {
    _expect(CCStorageValueKind.json);
    return _copyJson(raw as Map<String, Object?>);
  }

  T _read<T>(CCStorageValueKind expected) {
    _expect(expected);
    return raw as T;
  }

  void _expect(CCStorageValueKind expected) {
    if (kind != expected) {
      throw CCStorageTypeError(expected: expected, actual: kind);
    }
  }
}

/// Raised when a caller reads a value using the wrong typed accessor.
final class CCStorageTypeError extends StateError {
  /// Creates a storage type mismatch error.
  CCStorageTypeError({required this.expected, required this.actual})
    : super('Expected ${expected.name}, found ${actual.name}.');

  /// Requested value kind.
  final CCStorageValueKind expected;

  /// Stored value kind.
  final CCStorageValueKind actual;
}

/// Backend contract for memory, file, database, or secure-storage adapters.
abstract interface class CCStorageBackend {
  /// Stores one already-qualified key.
  Future<void> write(String qualifiedKey, CCStorageValue value);

  /// Reads one already-qualified key.
  Future<CCStorageValue?> read(String qualifiedKey);

  /// Removes one already-qualified key.
  Future<void> remove(String qualifiedKey);

  /// Removes all keys with the supplied namespace prefix.
  Future<void> clear(String namespacePrefix);

  /// Lists keys under one namespace prefix without exposing values.
  Future<List<String>> keys(String namespacePrefix);

  /// Releases backend resources.
  FutureOr<void> close();
}

/// Backend-neutral typed client that applies namespace isolation.
final class CCStorageClient implements CCDisposable {
  /// Creates a client backed by [backend].
  CCStorageClient({required CCStorageBackend backend}) : _backend = backend;

  final CCStorageBackend _backend;
  bool _closed = false;

  /// Stores a string.
  Future<void> setString(
    DemoStorageNamespace namespace,
    String key,
    String value,
  ) => _write(namespace, key, CCStorageValue.string(value));

  /// Stores an integer.
  Future<void> setInt(DemoStorageNamespace namespace, String key, int value) =>
      _write(namespace, key, CCStorageValue.integer(value));

  /// Stores a double.
  Future<void> setDouble(
    DemoStorageNamespace namespace,
    String key,
    double value,
  ) => _write(namespace, key, CCStorageValue.doubleValue(value));

  /// Stores a boolean.
  Future<void> setBool(
    DemoStorageNamespace namespace,
    String key,
    bool value,
  ) => _write(namespace, key, CCStorageValue.boolean(value));

  /// Stores a JSON object using a defensive copy.
  Future<void> setJson(
    DemoStorageNamespace namespace,
    String key,
    Map<String, Object?> value,
  ) => _write(namespace, key, CCStorageValue.json(value));

  /// Reads a string.
  Future<String?> getString(DemoStorageNamespace namespace, String key) async =>
      (await _read(namespace, key))?.string;

  /// Reads an integer.
  Future<int?> getInt(DemoStorageNamespace namespace, String key) async =>
      (await _read(namespace, key))?.integer;

  /// Reads a double.
  Future<double?> getDouble(DemoStorageNamespace namespace, String key) async =>
      (await _read(namespace, key))?.doubleValue;

  /// Reads a boolean.
  Future<bool?> getBool(DemoStorageNamespace namespace, String key) async =>
      (await _read(namespace, key))?.boolean;

  /// Reads a JSON object as a defensive copy.
  Future<Map<String, Object?>?> getJson(
    DemoStorageNamespace namespace,
    String key,
  ) async => (await _read(namespace, key))?.json;

  /// Removes one value.
  Future<void> remove(DemoStorageNamespace namespace, String key) =>
      _run(() => _backend.remove(_qualifiedKey(namespace, key)));

  /// Removes all values in one namespace.
  Future<void> clear(DemoStorageNamespace namespace) =>
      _run(() => _backend.clear('${namespace.storageId}/'));

  /// Lists keys in one namespace.
  Future<List<String>> keys(DemoStorageNamespace namespace) async {
    _ensureOpen();
    final prefix = '${namespace.storageId}/';
    final values = await _backend.keys(prefix);
    return values
        .where((value) => value.startsWith(prefix))
        .map((value) => value.substring(prefix.length))
        .toList(growable: false);
  }

  Future<void> _write(
    DemoStorageNamespace namespace,
    String key,
    CCStorageValue value,
  ) => _run(() => _backend.write(_qualifiedKey(namespace, key), value));

  Future<CCStorageValue?> _read(
    DemoStorageNamespace namespace,
    String key,
  ) async {
    _ensureOpen();
    return _backend.read(_qualifiedKey(namespace, key));
  }

  Future<void> _run(FutureOr<void> Function() operation) async {
    _ensureOpen();
    await operation();
  }

  String _qualifiedKey(DemoStorageNamespace namespace, String key) {
    _ensureKey(key);
    return '${namespace.storageId}/$key';
  }

  void _ensureOpen() {
    if (_closed) throw StateError('CCStorageClient is closed.');
  }

  @override
  FutureOr<void> dispose() {
    if (_closed) return Future<void>.value();
    _closed = true;
    return _backend.close();
  }
}

void _ensureKey(String key) {
  if (key.trim().isEmpty || key.contains('\n')) {
    throw ArgumentError.value(key, 'key', 'Storage key must be non-empty.');
  }
}

void _validateJson(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return;
  }
  if (value is List<Object?>) {
    for (final item in value) {
      _validateJson(item);
    }
    return;
  }
  if (value is Map<String, Object?>) {
    for (final item in value.values) {
      _validateJson(item);
    }
    return;
  }
  throw ArgumentError.value(value, 'value', 'Value is not JSON-compatible.');
}

Object? _copyJsonValue(Object? value) {
  if (value is Map<String, Object?>) return _copyJson(value);
  if (value is List<Object?>) {
    return value.map<Object?>(_copyJsonValue).toList(growable: false);
  }
  return value;
}

Map<String, Object?> _copyJson(Map<String, Object?> value) => {
  for (final entry in value.entries) entry.key: _copyJsonValue(entry.value),
};
